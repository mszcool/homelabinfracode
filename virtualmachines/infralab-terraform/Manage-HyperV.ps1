#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Hyper-V VM Management Script using Terraform
    
.DESCRIPTION
    This PowerShell script provides easy commands for managing Hyper-V-based VMs through Terraform.
    It includes proper error handling, logging, and validation checks.
    
.PARAMETER Action
    The action to perform: init, plan, apply, destroy, status, clean, validate
    
.PARAMETER Verbose
    Enable verbose output for debugging
    
.PARAMETER Force
    Skip confirmation prompts for destructive operations
    
.EXAMPLE
    .\Manage-HyperV.ps1 -Action init
    Initializes Terraform for Hyper-V
    
.EXAMPLE
    .\Manage-HyperV.ps1 -Action apply -Verbose
    Applies Terraform changes with verbose output
    
.EXAMPLE
    .\Manage-HyperV.ps1 -Action destroy -Force
    Destroys all resources without confirmation
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateSet("init", "plan", "apply", "destroy", "status", "clean", "validate", "help")]
    [string]$Action,
    
    [Parameter(Mandatory = $false)]
    [switch]$Force,
    
    [Parameter(Mandatory = $false)]
    [switch]$ShowLogs
)

# Set error action preference
$ErrorActionPreference = "Stop"

# Script variables
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$HyperVDir = Join-Path $ScriptDir "hyperv"
$LogFile = Join-Path $ScriptDir "hyperv-management.log"

# Color constants for output
$ColorInfo = "Cyan"
$ColorSuccess = "Green" 
$ColorWarning = "Yellow"
$ColorError = "Red"

#region Helper Functions

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet("Info", "Warning", "Error", "Success")]
        [string]$Level = "Info"
    )
    
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogMessage = "[$Timestamp] [$Level] $Message"
    
    # Write to console with colors
    switch ($Level) {
        "Info"    { Write-Host $Message -ForegroundColor $ColorInfo }
        "Success" { Write-Host $Message -ForegroundColor $ColorSuccess }
        "Warning" { Write-Host $Message -ForegroundColor $ColorWarning }
        "Error"   { Write-Host $Message -ForegroundColor $ColorError }
    }
    
    # Write to log file
    Add-Content -Path $LogFile -Value $LogMessage -ErrorAction SilentlyContinue
}

function Write-Header {
    param([string]$Title)
    
    $Border = "=" * 60
    Write-Log ""
    Write-Log $Border
    Write-Log $Title
    Write-Log $Border
}

function Test-Administrator {
    $CurrentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $Principal = New-Object Security.Principal.WindowsPrincipal($CurrentUser)
    return $Principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-HyperVEnabled {
    try {
        $HyperVFeature = Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -ErrorAction Stop
        return $HyperVFeature.State -eq "Enabled"
    }
    catch {
        Write-Log "Error checking Hyper-V status: $($_.Exception.Message)" -Level Error
        return $false
    }
}

function Test-TerraformInstalled {
    try {
        $TerraformVersion = terraform version 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Log "Terraform is installed: $($TerraformVersion.Split("`n")[0])" -Level Success
            return $true
        }
        return $false
    }
    catch {
        return $false
    }
}

function Test-Prerequisites {
    Write-Header "Checking Prerequisites"
    
    $AllChecksPassed = $true
    
    # Check if running as Administrator
    if (-not (Test-Administrator)) {
        Write-Log "Error: This script must be run as Administrator for Hyper-V operations" -Level Error
        $AllChecksPassed = $false
    } else {
        Write-Log "✓ Running as Administrator" -Level Success
    }
    
    # Check if Terraform is installed
    if (-not (Test-TerraformInstalled)) {
        Write-Log "Error: Terraform is not installed or not in PATH" -Level Error
        Write-Log "Please install Terraform from: https://terraform.io/downloads" -Level Info
        $AllChecksPassed = $false
    }
    
    # Check if Hyper-V is enabled
    if (-not (Test-HyperVEnabled)) {
        Write-Log "Error: Hyper-V is not enabled" -Level Error
        Write-Log "Enable Hyper-V with: Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -All" -Level Info
        $AllChecksPassed = $false
    } else {
        Write-Log "✓ Hyper-V is enabled" -Level Success
    }
    
    # Check if hyperv directory exists
    if (-not (Test-Path $HyperVDir)) {
        Write-Log "Error: Hyper-V configuration directory not found: $HyperVDir" -Level Error
        $AllChecksPassed = $false
    } else {
        Write-Log "✓ Hyper-V configuration directory found" -Level Success
    }
    
    return $AllChecksPassed
}

function Invoke-TerraformCommand {
    param(
        [string]$Command,
        [string]$Description,
        [switch]$RequireConfirmation
    )
    
    Write-Log $Description -Level Info
    
    if ($RequireConfirmation -and -not $Force) {
        $Confirmation = Read-Host "Do you want to continue? (y/N)"
        if ($Confirmation -notmatch "^[Yy]") {
            Write-Log "Operation cancelled by user" -Level Warning
            return $false
        }
    }
    
    Push-Location $HyperVDir
    try {
        Write-Log "Executing: terraform $Command" -Level Info
        
        if ($VerbosePreference -eq "Continue") {
            $env:TF_LOG = "DEBUG"
        }
        
        Invoke-Expression "terraform $Command"
        
        if ($LASTEXITCODE -eq 0) {
            Write-Log "✓ Command completed successfully" -Level Success
            return $true
        } else {
            Write-Log "✗ Command failed with exit code: $LASTEXITCODE" -Level Error
            return $false
        }
    }
    catch {
        Write-Log "Error executing Terraform command: $($_.Exception.Message)" -Level Error
        return $false
    }
    finally {
        Pop-Location
        $env:TF_LOG = $null
    }
}

function Show-Usage {
    Write-Host @"

Hyper-V VM Management Script

USAGE:
    .\Manage-HyperV.ps1 -Action <action> [options]

ACTIONS:
    init        Initialize Terraform
    plan        Show planned changes
    apply       Apply changes
    destroy     Destroy all resources
    status      Show current state
    clean       Clean Terraform cache
    validate    Validate Terraform configuration
    help        Show this help message

OPTIONS:
    -Force      Skip confirmation prompts for destructive operations
    -Verbose    Enable verbose output for debugging
    -ShowLogs   Display the log file content

EXAMPLES:
    .\Manage-HyperV.ps1 -Action init
    .\Manage-HyperV.ps1 -Action apply -Verbose
    .\Manage-HyperV.ps1 -Action destroy -Force
    .\Manage-HyperV.ps1 -Action status -ShowLogs

"@ -ForegroundColor $ColorInfo
}

function Show-Status {
    Write-Header "Current Infrastructure Status"
    
    # Show Terraform state
    Write-Log "Terraform State:" -Level Info
    Invoke-TerraformCommand "show" "Displaying Terraform state"
    
    Write-Log ""
    Write-Log "Hyper-V Virtual Machines:" -Level Info
    
    try {
        $VMs = Get-VM -ErrorAction SilentlyContinue
        if ($VMs) {
            $VMs | Format-Table Name, State, CPUUsage, MemoryAssigned, Uptime -AutoSize
        } else {
            Write-Log "No Hyper-V VMs found" -Level Warning
        }
    }
    catch {
        Write-Log "Error retrieving Hyper-V VMs: $($_.Exception.Message)" -Level Error
    }
    
    Write-Log ""
    Write-Log "Hyper-V Virtual Switches:" -Level Info
    
    try {
        $Switches = Get-VMSwitch -ErrorAction SilentlyContinue
        if ($Switches) {
            $Switches | Format-Table Name, SwitchType, NetAdapterInterfaceDescription -AutoSize
        } else {
            Write-Log "No Hyper-V virtual switches found" -Level Warning
        }
    }
    catch {
        Write-Log "Error retrieving Hyper-V switches: $($_.Exception.Message)" -Level Error
    }
}

function Clear-TerraformCache {
    Write-Header "Cleaning Terraform Cache"
    
    Push-Location $HyperVDir
    try {
        $ItemsToClean = @(
            ".terraform",
            ".terraform.lock.hcl", 
            "terraform.tfstate.backup",
            "*.tfplan"
        )
        
        foreach ($Item in $ItemsToClean) {
            $Path = Join-Path $HyperVDir $Item
            if (Test-Path $Path) {
                Remove-Item $Path -Recurse -Force -ErrorAction SilentlyContinue
                Write-Log "✓ Removed: $Item" -Level Success
            }
        }
        
        Write-Log "Terraform cache cleaned successfully" -Level Success
    }
    catch {
        Write-Log "Error cleaning cache: $($_.Exception.Message)" -Level Error
    }
    finally {
        Pop-Location
    }
}

function Show-Logs {
    if (Test-Path $LogFile) {
        Write-Header "Recent Log Entries"
        Get-Content $LogFile -Tail 50 | Write-Host
    } else {
        Write-Log "No log file found at: $LogFile" -Level Warning
    }
}

#endregion

#region Main Script Logic

function Main {
    # Initialize logging
    Write-Log "Starting Hyper-V management script" -Level Info
    Write-Log "Action: $Action" -Level Info
    Write-Log "Script Directory: $ScriptDir" -Level Info
    Write-Log "Hyper-V Directory: $HyperVDir" -Level Info
    
    # Handle help action first
    if ($Action -eq "help") {
        Show-Usage
        return
    }
    
    # Show logs if requested
    if ($ShowLogs) {
        Show-Logs
        return
    }
    
    # Check prerequisites for most actions
    if ($Action -notin @("clean", "help")) {
        if (-not (Test-Prerequisites)) {
            Write-Log "Prerequisites check failed. Aborting operation." -Level Error
            exit 1
        }
    }
    
    # Execute the requested action
    switch ($Action) {
        "init" {
            Write-Header "Initializing Terraform for Hyper-V"
            $Success = Invoke-TerraformCommand "init" "Initializing Terraform..."
            if ($Success) {
                Write-Log "✓ Terraform initialized successfully" -Level Success
                Write-Log "You can now run: .\Manage-HyperV.ps1 -Action plan" -Level Info
            }
        }
        
        "plan" {
            Write-Header "Planning Terraform Changes"
            $Success = Invoke-TerraformCommand "plan" "Generating Terraform plan..."
            if ($Success) {
                Write-Log "✓ Plan generated successfully" -Level Success
                Write-Log "To apply changes, run: .\Manage-HyperV.ps1 -Action apply" -Level Info
            }
        }
        
        "apply" {
            Write-Header "Applying Terraform Changes"
            $Success = Invoke-TerraformCommand "apply" "Applying Terraform configuration..." -RequireConfirmation
            if ($Success) {
                Write-Log "✓ Infrastructure deployed successfully" -Level Success
                Write-Log "Check status with: .\Manage-HyperV.ps1 -Action status" -Level Info
            }
        }
        
        "destroy" {
            Write-Header "Destroying Hyper-V Resources"
            $Success = Invoke-TerraformCommand "destroy" "Destroying all Terraform-managed resources..." -RequireConfirmation
            if ($Success) {
                Write-Log "✓ Infrastructure destroyed successfully" -Level Success
            }
        }
        
        "status" {
            Show-Status
        }
        
        "clean" {
            Clear-TerraformCache
        }
        
        "validate" {
            Write-Header "Validating Terraform Configuration"
            $Success = Invoke-TerraformCommand "validate" "Validating Terraform configuration..."
            if ($Success) {
                Write-Log "✓ Configuration is valid" -Level Success
            }
        }
        
        default {
            Write-Log "Unknown action: $Action" -Level Error
            Show-Usage
            exit 1
        }
    }
}

# Execute main function with error handling
try {
    Main
}
catch {
    Write-Log "Unexpected error: $($_.Exception.Message)" -Level Error
    Write-Log "Stack trace: $($_.ScriptStackTrace)" -Level Error
    exit 1
}
finally {
    Write-Log "Script execution completed" -Level Info
}

#endregion
