param(
    [Parameter(Mandatory=$true)]
    [string]$VMName
)

try {
    Write-Host "Attempting to disable automatic checkpoints for VM: $VMName"
    
    $vm = Get-VM -Name $VMName -ErrorAction Stop
    Write-Host "Found VM: $VMName, Current AutomaticCheckpointsEnabled: $($vm.AutomaticCheckpointsEnabled)"
    
    if ($vm.AutomaticCheckpointsEnabled) {
        Set-VM -Name $VMName -AutomaticCheckpointsEnabled $false -ErrorAction Stop
        Write-Host "Successfully disabled automatic checkpoints for $VMName"
    } else {
        Write-Host "Automatic checkpoints already disabled for $VMName"
    }
    
    # Verify the change
    $vmAfter = Get-VM -Name $VMName -ErrorAction Stop
    Write-Host "Verification - AutomaticCheckpointsEnabled is now: $($vmAfter.AutomaticCheckpointsEnabled)"
    
} catch {
    Write-Error "Failed to configure checkpoints for ${VMName}: $($_.Exception.Message)"
    exit 1
}