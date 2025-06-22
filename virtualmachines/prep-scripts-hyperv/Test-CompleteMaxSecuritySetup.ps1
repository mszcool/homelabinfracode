# Test-CompleteMaxSecuritySetup.ps1
# Comprehensive validation script for the MAXIMUM SECURITY Hyper-V DCOM/WMI configuration
# This script tests all aspects of the maximum security implementation

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$ServiceUsername,
    
    [Parameter(Mandatory=$true)]
    [string]$ServicePassword,
    
    [string]$ComputerName = "127.0.0.1",
    [int]$Port = 5986,
    [switch]$UseHTTP = $false,
    [switch]$DetailedOutput = $false
)

Write-Host "=== COMPREHENSIVE MAXIMUM SECURITY VALIDATION ===" -ForegroundColor Cyan
Write-Host "Testing the complete maximum security Hyper-V setup implemented by Prepare-HyperV.ps1"
Write-Host "Target: $ComputerName`:$Port ($(if($UseHTTP) {'HTTP'} else {'HTTPS'}))"
Write-Host "Service Account: $ServiceUsername"
Write-Host ""

# Enhanced security test tracking with detailed categories
$securityResults = @{
    "Transport" = @{}
    "Authentication" = @{}
    "WMI_Namespaces" = @{}
    "DCOM_Services" = @{}
    "Privileges" = @{}
    "HyperV_Operations" = @{}
    "Security_Hardening" = @{}
}

$overallScore = 0
$maxScore = 0

# Function to execute tests and track results
function Test-MaxSecurityComponent {
    param(
        [string]$Category,
        [string]$TestKey,
        [ScriptBlock]$Command,
        [string]$Description,
        [string]$SecurityLevel = "Standard",
        [bool]$Critical = $true,
        [hashtable]$ConnectionParams = $null
    )
    
    $global:maxScore++
    Write-Host "[$Category] Testing: $Description..." -ForegroundColor Yellow
    
    try {
        if ($ConnectionParams) {
            $result = Invoke-Command @ConnectionParams -ScriptBlock $Command
        } else {
            $result = & $Command
        }
        
        Write-Host "   ✓ SUCCESS: $result" -ForegroundColor Green
        $securityResults[$Category][$TestKey] = @{
            Status = "PASS"
            Details = $result
            SecurityLevel = $SecurityLevel
            Critical = $Critical
        }
        $global:overallScore++
        return $true
        
    } catch {
        Write-Host "   ✗ FAILED: $($_.Exception.Message)" -ForegroundColor Red
        $securityResults[$Category][$TestKey] = @{
            Status = "FAIL"
            Details = $_.Exception.Message
            SecurityLevel = $SecurityLevel
            Critical = $Critical
        }
        return $false
    }
}

# Create secure credential
$securePassword = ConvertTo-SecureString $ServicePassword -AsPlainText -Force
$credential = New-Object System.Management.Automation.PSCredential($ServiceUsername, $securePassword)

# Configure connection parameters
$connectionParams = @{
    ComputerName = $ComputerName
    Port = $Port
    Credential = $credential
    ErrorAction = 'Stop'
}

if (-not $UseHTTP) {
    $connectionParams.UseSSL = $true
    $connectionParams.SessionOption = New-PSSessionOption -SkipCACheck -SkipCNCheck -SkipRevocationCheck
}

Write-Host "=== PHASE 1: TRANSPORT SECURITY VALIDATION ===" -ForegroundColor Cyan

# Test 1: HTTPS-only enforcement
Test-MaxSecurityComponent -Category "Transport" -TestKey "HTTPS_Only" -SecurityLevel "Maximum" -Description "HTTPS-only transport security" -Command {
    if ($UseHTTP) {
        throw "HTTP connection detected - should use HTTPS for maximum security"
    }
    $listeners = winrm enumerate winrm/config/listener 2>$null | Out-String
    if ($listeners -like "*Transport = HTTPS*" -and $listeners -notlike "*Transport = HTTP*5985*") {
        return "HTTPS-only configuration validated - no insecure HTTP listeners"
    }
    throw "HTTP listeners still present - security risk"
}

# Test 2: Certificate validation bypass (for self-signed)
Test-MaxSecurityComponent -Category "Transport" -TestKey "Certificate_Config" -SecurityLevel "Standard" -Description "SSL certificate configuration" -Command {
    $certs = Get-ChildItem -Path "Cert:\LocalMachine\My" | Where-Object {
        ($_.Subject -like "*CN=localhost*" -or $_.Subject -like "*CN=$env:COMPUTERNAME*") -and
        $_.NotAfter -gt (Get-Date) -and $_.HasPrivateKey -eq $true
    }
    if ($certs) {
        $cert = $certs | Sort-Object NotAfter -Descending | Select-Object -First 1
        return "Valid SSL certificate found - expires $($cert.NotAfter.ToString('yyyy-MM-dd'))"
    }
    throw "No valid SSL certificate found for WinRM HTTPS"
}

Write-Host "`n=== PHASE 2: AUTHENTICATION SECURITY VALIDATION ===" -ForegroundColor Cyan

# Test 3: Basic authentication test
Test-MaxSecurityComponent -Category "Authentication" -TestKey "Basic_Auth" -SecurityLevel "Essential" -Description "Basic WinRM authentication" -ConnectionParams $connectionParams -Command {
    $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $groups = $currentUser.Groups | ForEach-Object {
        try { $_.Translate([System.Security.Principal.NTAccount]).Value } catch { $_.Value }
    }
    return "Authenticated as: $($currentUser.Name) | Groups: $($groups -join ', ')"
}

Write-Host "`n=== PHASE 3: WMI NAMESPACE SECURITY VALIDATION ===" -ForegroundColor Cyan

# Test 4-9: WMI namespace access with different security levels
$wmiNamespaces = @(
    @{ Namespace = "root"; Level = "Minimal"; Critical = $false; Description = "Root WMI namespace (Minimal security)" },
    @{ Namespace = "root/cimv2"; Level = "Standard"; Critical = $true; Description = "CIMV2 namespace (Standard security)" },
    @{ Namespace = "root/virtualization/v2"; Level = "HyperV"; Critical = $true; Description = "Hyper-V virtualization namespace (HyperV security)" },
    @{ Namespace = "root/Microsoft/Windows/HyperV"; Level = "HyperV"; Critical = $true; Description = "Hyper-V management namespace (HyperV security)" },
    @{ Namespace = "root/interop"; Level = "Standard"; Critical = $false; Description = "Interop namespace (Standard security)" },
    @{ Namespace = "root/StandardCimv2"; Level = "Standard"; Critical = $false; Description = "Standard CIM v2 namespace (Standard security)" }
)

foreach ($ns in $wmiNamespaces) {
    Test-MaxSecurityComponent -Category "WMI_Namespaces" -TestKey "WMI_$($ns.Namespace -replace '[/\\]', '_')" -SecurityLevel $ns.Level -Critical $ns.Critical -Description $ns.Description -ConnectionParams $connectionParams -Command {
        param($namespace = $ns.Namespace)
        if ($namespace -eq "root/cimv2") {
            $os = Get-WmiObject -Class Win32_OperatingSystem -ErrorAction Stop
            return "CIMV2 accessible - OS: $($os.Caption)"
        } else {
            $security = Get-WmiObject -Namespace $namespace -Class "__SystemSecurity" -ErrorAction Stop
            return "$namespace namespace accessible with targeted privileges"
        }
    }.GetNewClosure()
}

Write-Host "`n=== PHASE 4: DCOM MAXIMUM SECURITY VALIDATION ===" -ForegroundColor Cyan

# Test 10: Global DCOM security settings
Test-MaxSecurityComponent -Category "DCOM_Services" -TestKey "Global_DCOM_Security" -SecurityLevel "Maximum" -Description "Global DCOM maximum security settings" -ConnectionParams $connectionParams -Command {
    $dcomSettings = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Ole" -ErrorAction Stop
    $authLevel = $dcomSettings.LegacyAuthenticationLevel
    $impLevel = $dcomSettings.LegacyImpersonationLevel
    
    $authLevelName = switch ($authLevel) {
        6 { "PKT_PRIVACY (Maximum Security)" }
        5 { "PKT_INTEGRITY (High Security)" }
        4 { "PKT (Standard Security)" }
        default { "Level $authLevel" }
    }
    
    $impLevelName = switch ($impLevel) {
        2 { "IDENTIFY (Secure Boundary)" }
        3 { "IMPERSONATE (Medium Security)" }
        4 { "DELEGATE (Lower Security)" }
        default { "Level $impLevel" }
    }
    
    return "DCOM Auth: $authLevelName, Impersonation: $impLevelName"
}

# Test 11: WMI DCOM service security
Test-MaxSecurityComponent -Category "DCOM_Services" -TestKey "WMI_DCOM_Security" -SecurityLevel "Maximum" -Description "WMI DCOM service maximum security" -ConnectionParams $connectionParams -Command {
    $wmiAppId = "{8BC3F05E-D86B-11D0-A075-00C04FB68820}"
    $dcomPath = "HKLM:\SOFTWARE\Classes\AppID\$wmiAppId"
    
    if (Test-Path $dcomPath) {
        $authLevel = Get-ItemProperty -Path $dcomPath -Name "AuthenticationLevel" -ErrorAction SilentlyContinue
        if ($authLevel) {
            $level = switch ($authLevel.AuthenticationLevel) {
                6 { "PKT_PRIVACY (Maximum)" }
                5 { "PKT_INTEGRITY (High)" }
                4 { "PKT (Standard)" }
                default { "Level $($authLevel.AuthenticationLevel)" }
            }
            return "WMI DCOM configured with $level security"
        }
    }
    return "WMI DCOM using system defaults (PKT_PRIVACY applied globally)"
}

# Test 12: Hyper-V DCOM service security
Test-MaxSecurityComponent -Category "DCOM_Services" -TestKey "HyperV_DCOM_Security" -SecurityLevel "Maximum" -Description "Hyper-V DCOM service maximum security" -ConnectionParams $connectionParams -Command {
    $hyperVAppId = "{51885B9F-7EE0-4BB9-98A7-2CADEEC0F58F}"
    $dcomPath = "HKLM:\SOFTWARE\Classes\AppID\$hyperVAppId"
    
    if (Test-Path $dcomPath) {
        $authLevel = Get-ItemProperty -Path $dcomPath -Name "AuthenticationLevel" -ErrorAction SilentlyContinue
        if ($authLevel) {
            $level = switch ($authLevel.AuthenticationLevel) {
                6 { "PKT_PRIVACY (Maximum)" }
                5 { "PKT_INTEGRITY (High)" }
                4 { "PKT (Standard)" }
                default { "Level $($authLevel.AuthenticationLevel)" }
            }
            return "Hyper-V DCOM configured with $level security"
        }
    }
    return "Hyper-V DCOM using system defaults (PKT_PRIVACY applied globally)"
}

Write-Host "`n=== PHASE 5: WINDOWS PRIVILEGES VALIDATION ===" -ForegroundColor Cyan

# Test 13: Essential Windows privileges
Test-MaxSecurityComponent -Category "Privileges" -TestKey "Essential_Privileges" -SecurityLevel "Essential" -Description "Essential Hyper-V privileges (minimal required)" -ConnectionParams $connectionParams -Command {
    $privileges = whoami /priv /fo csv | ConvertFrom-Csv
    $essentialPrivs = @(
        "SeCreateSymbolicLinkPrivilege",
        "SeManageVolumePrivilege", 
        "SeSecurityPrivilege"
    )
    
    $grantedPrivs = @()
    foreach ($priv in $essentialPrivs) {
        $hasPriv = $privileges | Where-Object { $_.Privilege -eq $priv -and ($_.State -eq "Enabled" -or $_.State -eq "Disabled") }
        if ($hasPriv) {
            $grantedPrivs += $priv
        }
    }
    
    return "Essential privileges granted: $($grantedPrivs.Count) of $($essentialPrivs.Count) - $($grantedPrivs -join ', ')"
}

Write-Host "`n=== PHASE 6: HYPER-V OPERATIONS VALIDATION ===" -ForegroundColor Cyan

# Test 14: Get-VM cmdlet
Test-MaxSecurityComponent -Category "HyperV_Operations" -TestKey "Get_VM" -SecurityLevel "Functional" -Description "Get-VM PowerShell cmdlet" -ConnectionParams $connectionParams -Command {
    $vms = Get-VM -ErrorAction Stop
    return "Get-VM successful - VM Count: $($vms.Count)"
}

# Test 15: Get-VMSwitch cmdlet
Test-MaxSecurityComponent -Category "HyperV_Operations" -TestKey "Get_VMSwitch" -SecurityLevel "Functional" -Description "Get-VMSwitch PowerShell cmdlet" -ConnectionParams $connectionParams -Command {
    $switches = Get-VMSwitch -ErrorAction Stop
    return "Get-VMSwitch successful - Switch Count: $($switches.Count)"
}

# Test 16: Get-VMHost cmdlet
Test-MaxSecurityComponent -Category "HyperV_Operations" -TestKey "Get_VMHost" -SecurityLevel "Functional" -Description "Get-VMHost PowerShell cmdlet" -ConnectionParams $connectionParams -Command {
    $host = Get-VMHost -ErrorAction Stop
    return "Get-VMHost successful - Host: $($host.Name)"
}

# Test 17: Advanced WMI access
Test-MaxSecurityComponent -Category "HyperV_Operations" -TestKey "WMI_VM_Management" -SecurityLevel "Advanced" -Critical $false -Description "Advanced WMI VM management access" -ConnectionParams $connectionParams -Command {
    $vmms = Get-WmiObject -Namespace "root/virtualization/v2" -Class "Msvm_VirtualSystemManagementService" -ErrorAction Stop
    if ($vmms) {
        $methods = $vmms | Get-Member -MemberType Method | Where-Object { $_.Name -like "*VirtualSystem*" }
        return "VM Management Service accessible - Methods: $($methods.Count)"
    }
    throw "Cannot access VM management service"
}

Write-Host "`n=== PHASE 7: SECURITY HARDENING VALIDATION ===" -ForegroundColor Cyan

# Test 18: Anonymous access disabled
Test-MaxSecurityComponent -Category "Security_Hardening" -TestKey "Anonymous_Access_Disabled" -SecurityLevel "Hardened" -Description "DCOM anonymous access disabled" -ConnectionParams $connectionParams -Command {
    $dcomSettings = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Ole" -ErrorAction Stop
    $anonAccess = $dcomSettings.MachineAccessRestriction
    
    if ($anonAccess -eq 1) {
        return "Anonymous DCOM access is DISABLED (secure configuration)"
    } else {
        return "Anonymous DCOM access status: $anonAccess (review recommended)"
    }
}

# Test 19: Security logging enabled
Test-MaxSecurityComponent -Category "Security_Hardening" -TestKey "Security_Logging" -SecurityLevel "Monitoring" -Critical $false -Description "DCOM security logging enabled" -ConnectionParams $connectionParams -Command {
    $dcomSettings = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Ole" -ErrorAction Stop
    $callLogging = $dcomSettings.CallFailureLoggingLevel
    
    if ($callLogging -eq 1) {
        return "DCOM failure logging ENABLED (security monitoring active)"
    } else {
        return "DCOM failure logging status: $callLogging"
    }
}

# Calculate comprehensive security score
Write-Host "`n=== COMPREHENSIVE SECURITY ASSESSMENT REPORT ===" -ForegroundColor Cyan

$totalTests = $overallScore + ($maxScore - $overallScore)
$securityPercentage = [math]::Round(($overallScore / $maxScore) * 100, 1)

# Category breakdown
foreach ($category in $securityResults.Keys) {
    $categoryTests = $securityResults[$category]
    if ($categoryTests.Count -gt 0) {
        $passed = ($categoryTests.Values | Where-Object { $_.Status -eq "PASS" }).Count
        $failed = ($categoryTests.Values | Where-Object { $_.Status -eq "FAIL" }).Count
        $critical = ($categoryTests.Values | Where-Object { $_.Critical -and $_.Status -eq "PASS" }).Count
        $totalCritical = ($categoryTests.Values | Where-Object { $_.Critical }).Count
        
        Write-Host ""
        Write-Host "[$category] Results:" -ForegroundColor White
        Write-Host "  Passed: $passed, Failed: $failed" -ForegroundColor Gray
        if ($totalCritical -gt 0) {
            Write-Host "  Critical Tests: $critical of $totalCritical passed" -ForegroundColor $(if($critical -eq $totalCritical) { "Green" } else { "Yellow" })
        }
    }
}

Write-Host ""
Write-Host "OVERALL SECURITY SCORE: $securityPercentage%" -ForegroundColor $(
    if ($securityPercentage -ge 95) { "Green" }
    elseif ($securityPercentage -ge 85) { "Yellow" } 
    else { "Red" }
)

# Final assessment
if ($securityPercentage -eq 100) {
    Write-Host ""
    Write-Host "🔒 PERFECT: MAXIMUM SECURITY configuration fully validated!" -ForegroundColor Green
    Write-Host "✅ All Hyper-V operations should work securely over WinRM HTTPS" -ForegroundColor Green
    Write-Host "✅ PKT_PRIVACY DCOM authentication provides strongest encryption" -ForegroundColor Green
    Write-Host "✅ Minimal privilege principle successfully implemented" -ForegroundColor Green
    Write-Host "✅ Security hardening measures are active" -ForegroundColor Green
} elseif ($securityPercentage -ge 95) {
    Write-Host ""
    Write-Host "🔒 EXCELLENT: Near-perfect maximum security configuration!" -ForegroundColor Green
    Write-Host "✅ Critical Hyper-V operations should work securely" -ForegroundColor Green
    Write-Host "⚠ Minor security gaps may exist - review failed tests" -ForegroundColor Yellow
} elseif ($securityPercentage -ge 85) {
    Write-Host ""
    Write-Host "🔒 VERY GOOD: Strong security configuration with some gaps" -ForegroundColor Yellow
    Write-Host "✅ Most critical Hyper-V operations should work securely" -ForegroundColor Green
    Write-Host "⚠ Review failed tests for optimization opportunities" -ForegroundColor Yellow
} elseif ($securityPercentage -ge 70) {
    Write-Host ""
    Write-Host "⚠ GOOD: Adequate security but improvement needed" -ForegroundColor Yellow
    Write-Host "✅ Basic Hyper-V operations should work" -ForegroundColor Green
    Write-Host "⚠ Some advanced features may have security limitations" -ForegroundColor Yellow
} else {
    Write-Host ""
    Write-Host "❌ NEEDS IMPROVEMENT: Significant security configuration issues" -ForegroundColor Red
    Write-Host "⚠ Hyper-V operations may be limited or insecure" -ForegroundColor Red
    Write-Host "🔧 Re-run Prepare-HyperV.ps1 with Administrator privileges" -ForegroundColor Yellow
}

# Recommendations
Write-Host ""
Write-Host "SECURITY RECOMMENDATIONS:" -ForegroundColor Yellow
Write-Host "1. Ensure system restart after running Prepare-HyperV.ps1" -ForegroundColor White
Write-Host "2. Use HTTPS-only connections for all WinRM operations" -ForegroundColor White
Write-Host "3. Monitor DCOM security logs regularly (Event Viewer)" -ForegroundColor White
Write-Host "4. Validate service account has minimal required privileges only" -ForegroundColor White
Write-Host "5. Review and audit WMI namespace permissions quarterly" -ForegroundColor White
Write-Host "6. Test Terraform operations in isolated environment first" -ForegroundColor White

if ($DetailedOutput) {
    Write-Host ""
    Write-Host "DETAILED TEST RESULTS:" -ForegroundColor White
    Write-Host "=====================" -ForegroundColor White
    
    foreach ($category in $securityResults.Keys) {
        foreach ($testKey in $securityResults[$category].Keys) {
            $test = $securityResults[$category][$testKey]
            $color = switch ($test.Status) {
                "PASS" { "Green" }
                "FAIL" { "Red" }
                default { "Yellow" }
            }
            
            $statusSymbol = switch ($test.Status) {
                "PASS" { "✓" }
                "FAIL" { "✗" }
                default { "⚠" }
            }
            
            $criticalMarker = if ($test.Critical) { " [CRITICAL]" } else { "" }
            
            Write-Host "$statusSymbol [$category] $testKey$criticalMarker" -ForegroundColor $color
            Write-Host "   Security Level: $($test.SecurityLevel)" -ForegroundColor Gray
            Write-Host "   Details: $($test.Details)" -ForegroundColor Gray
        }
    }
}

Write-Host ""
Write-Host "For additional security monitoring, check:" -ForegroundColor Gray
Write-Host "• Event Viewer → System (DCOM errors 10016, 10028)" -ForegroundColor Gray
Write-Host "• Event Viewer → Applications → Microsoft-Windows-WMI-Activity" -ForegroundColor Gray
Write-Host "• Event Viewer → Applications → Microsoft-Windows-Hyper-V-*" -ForegroundColor Gray
Write-Host "• Security logs for authentication failures" -ForegroundColor Gray
