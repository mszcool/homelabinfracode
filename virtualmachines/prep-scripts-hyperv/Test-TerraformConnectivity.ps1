# Test-TerraformConnectivity.ps1
# Enhanced test script to verify Terraform Hyper-V provider connectivity
param(
    [Parameter(Mandatory=$true)]
    [string]$ServiceUsername,
    
    [Parameter(Mandatory=$true)]
    [SecureString]$ServicePassword
)

Write-Host "=== Terraform Hyper-V Connectivity Test ===" -ForegroundColor Cyan
Write-Host "Service Account: $ServiceUsername"
Write-Host ""

# Convert SecureString to credential
$credential = New-Object System.Management.Automation.PSCredential($ServiceUsername, $ServicePassword)

# Pre-flight checks
Write-Host "Pre-flight Checks:" -ForegroundColor Yellow
$winrmService = Get-Service -Name WinRM
Write-Host "   WinRM Service: $($winrmService.Status)" -ForegroundColor $(if($winrmService.Status -eq 'Running') {'Green'} else {'Red'})

$portTest = Test-NetConnection -ComputerName 127.0.0.1 -Port 5986 -InformationLevel Quiet
Write-Host "   Port 5986 (HTTPS): $(if($portTest) {'Listening'} else {'Not Listening'})" -ForegroundColor $(if($portTest) {'Green'} else {'Red'})

if ($winrmService.Status -ne 'Running' -or -not $portTest) {
    Write-Host ""
    Write-Host "❌ Pre-flight checks failed. Please run Fix-WinRM-PostReboot.ps1 first." -ForegroundColor Red
    return
}

Write-Host ""

# Test 1: Basic WinRM connectivity with different authentication methods
Write-Host "1. Testing WinRM connectivity..." -ForegroundColor Yellow

$authMethods = @('Basic', 'Negotiate', 'Default')
$connectionSuccessful = $false

foreach ($authMethod in $authMethods) {
    Write-Host "   Trying $authMethod authentication..." -ForegroundColor Gray
    try {        $connectParams = @{
            ComputerName = '127.0.0.1'
            Port = 5986
            UseSSL = $true
            Credential = $credential
            ScriptBlock = { "Connected as: $env:USERNAME on $env:COMPUTERNAME" }
            ErrorAction = 'Stop'
            SessionOption = New-PSSessionOption -SkipCACheck -SkipCNCheck -SkipRevocationCheck
        }
        
        if ($authMethod -ne 'Default') {
            $connectParams.Authentication = $authMethod
        }
        
        $result = Invoke-Command @connectParams
        Write-Host "   ✓ SUCCESS with $authMethod auth: $result" -ForegroundColor Green
        $connectionSuccessful = $true
        break
    } catch {
        Write-Host "   ✗ Failed with $authMethod auth: $($_.Exception.Message)" -ForegroundColor Red
    }
}

if (-not $connectionSuccessful) {
    Write-Host ""
    Write-Host "❌ All authentication methods failed. Check these:" -ForegroundColor Red
    Write-Host "   1. Service account password is correct" -ForegroundColor Yellow
    Write-Host "   2. Service account has 'Log on as a service' right" -ForegroundColor Yellow
    Write-Host "   3. Service account is in 'Hyper-V Administrators' group" -ForegroundColor Yellow
    Write-Host "   4. Computer was rebooted after running Prepare-HyperV.ps1" -ForegroundColor Yellow
    return
}

# Test 2: User rights verification
Write-Host ""
Write-Host "2. Verifying user rights..." -ForegroundColor Yellow
try {
    $result = Invoke-Command -ComputerName 127.0.0.1 -Port 5986 -UseSSL:$true -Credential $credential -SessionOption (New-PSSessionOption -SkipCACheck -SkipCNCheck -SkipRevocationCheck) -ScriptBlock { 
        # Check if user has necessary privileges
        $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object System.Security.Principal.WindowsPrincipal($currentUser)
        
        # Check group memberships
        $groups = $currentUser.Groups | ForEach-Object {
            try {
                $_.Translate([System.Security.Principal.NTAccount]).Value
            } catch {
                $_.Value
            }
        }
        
        @{
            UserName = $currentUser.Name
            Groups = $groups -join ', '
            IsAdmin = $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
        }
    } -ErrorAction Stop
    
    Write-Host "   ✓ Connected as: $($result.UserName)" -ForegroundColor Green
    Write-Host "   Groups: $($result.Groups)" -ForegroundColor Gray
    Write-Host "   Is Admin: $($result.IsAdmin)" -ForegroundColor Gray
} catch {
    Write-Host "   ✗ Failed to verify user rights: $($_.Exception.Message)" -ForegroundColor Red
}

# Test 3: Hyper-V module availability
Write-Host ""
Write-Host "3. Testing Hyper-V module access..." -ForegroundColor Yellow
try {
    $result = Invoke-Command -ComputerName 127.0.0.1 -Port 5986 -UseSSL:$true -Credential $credential -SessionOption (New-PSSessionOption -SkipCACheck -SkipCNCheck -SkipRevocationCheck) -ScriptBlock { 
        $module = Get-Module -ListAvailable Hyper-V | Select-Object Name, Version -First 1
        if ($module) {
            "Hyper-V module: $($module.Name) v$($module.Version)"
        } else {
            "Hyper-V module not found"
        }
    } -ErrorAction Stop
    Write-Host "   ✓ $result" -ForegroundColor Green
} catch {
    Write-Host "   ✗ Failed: $($_.Exception.Message)" -ForegroundColor Red
}

# Test 4: Hyper-V host access
Write-Host ""
Write-Host "4. Testing Hyper-V host access..." -ForegroundColor Yellow
try {
    $result = Invoke-Command -ComputerName 127.0.0.1 -Port 5986 -UseSSL:$true -Credential $credential -SessionOption (New-PSSessionOption -SkipCACheck -SkipCNCheck -SkipRevocationCheck) -ScriptBlock { 
        $hyperVHost = Get-VMHost
        "Host: $($hyperVHost.Name), VM Path: $($hyperVHost.VirtualMachinePath)"
    } -ErrorAction Stop
    Write-Host "   ✓ $result" -ForegroundColor Green
} catch {
    Write-Host "   ✗ Failed: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "   This may indicate insufficient Hyper-V permissions" -ForegroundColor Yellow
}

# Test 5: VM enumeration
Write-Host ""
Write-Host "5. Testing VM enumeration..." -ForegroundColor Yellow
try {
    $result = Invoke-Command -ComputerName 127.0.0.1 -Port 5986 -UseSSL:$true -Credential $credential -SessionOption (New-PSSessionOption -SkipCACheck -SkipCNCheck -SkipRevocationCheck) -ScriptBlock { 
        $vms = Get-VM
        "VM Count: $($vms.Count)"
    } -ErrorAction Stop
    Write-Host "   ✓ $result" -ForegroundColor Green
} catch {
    Write-Host "   ✗ Failed: $($_.Exception.Message)" -ForegroundColor Red
}

# Test 6: Switch enumeration
Write-Host ""
Write-Host "6. Testing Virtual Switch access..." -ForegroundColor Yellow
try {
    $result = Invoke-Command -ComputerName 127.0.0.1 -Port 5986 -UseSSL:$true -Credential $credential -SessionOption (New-PSSessionOption -SkipCACheck -SkipCNCheck -SkipRevocationCheck) -ScriptBlock { 
        $switches = Get-VMSwitch
        if ($switches.Count -gt 0) {
            "Switches: " + ($switches.Name -join ', ')
        } else {
            "No virtual switches found"
        }
    } -ErrorAction Stop
    Write-Host "   ✓ $result" -ForegroundColor Green
} catch {
    Write-Host "   ✗ Failed: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""
Write-Host "=== Summary ===" -ForegroundColor Cyan
if ($connectionSuccessful) {
    Write-Host "✅ Basic connectivity is working!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Terraform provider configuration:" -ForegroundColor Yellow
    Write-Host "provider `"hyperv`" {" -ForegroundColor Gray
    Write-Host "  user     = `"$ServiceUsername`"" -ForegroundColor Gray
    Write-Host "  password = `"[your-password]`"" -ForegroundColor Gray
    Write-Host "  host     = `"127.0.0.1`"" -ForegroundColor Gray
    Write-Host "  port     = 5986" -ForegroundColor Gray
    Write-Host "  https    = true" -ForegroundColor Gray
    Write-Host "  insecure = true  # Accept self-signed certificates" -ForegroundColor Gray
    Write-Host "  use_ntlm = true" -ForegroundColor Gray
    Write-Host "  timeout  = `"30s`"" -ForegroundColor Gray
    Write-Host "}" -ForegroundColor Gray
} else {
    Write-Host "❌ Connection failed. Please run Fix-WinRM-PostReboot.ps1" -ForegroundColor Red
}