param(
    [Parameter(Mandatory=$true)]
    [string]$VMName,
    
    [Parameter(Mandatory=$true)]
    [string[]]$AdapterNames
)

try {
    Write-Host "Attempting to fix network adapters for VM: $VMName"
    
    $vm = Get-VM -Name $VMName -ErrorAction Stop
    Write-Host "Found VM: $VMName, State: $($vm.State)"
    
    foreach ($adapterName in $AdapterNames) {
        try {
            # Determine the correct switch based on adapter name
            $switchName = if ($adapterName -eq "lab-wan") { "lab-wan" } else { "lab-lan" }
            
            Write-Host "Processing adapter: $adapterName -> switch: $switchName"
            
            # Get the network adapter
            $adapter = Get-VMNetworkAdapter -VMName $VMName -Name $adapterName -ErrorAction Stop
            Write-Host "Current switch for adapter $adapterName : $($adapter.SwitchName)"
            
            # Check if adapter is already connected to the correct switch
            if ($adapter.SwitchName -eq $switchName) {
                Write-Host "Adapter $adapterName is already connected to correct switch $switchName"
                continue
            }
            
            # Connect the adapter to the correct switch
            Connect-VMNetworkAdapter -VMName $VMName -Name $adapterName -SwitchName $switchName -ErrorAction Stop
            Write-Host "Successfully connected adapter $adapterName to switch $switchName"
            
            # Verify the connection
            $adapterAfter = Get-VMNetworkAdapter -VMName $VMName -Name $adapterName -ErrorAction Stop
            Write-Host "Verification - adapter $adapterName is now connected to: $($adapterAfter.SwitchName)"
            
        } catch {
            Write-Warning "Failed to connect adapter $adapterName to switch $switchName : $($_.Exception.Message)"
            # Don't exit here, try to fix other adapters
        }
    }
    
    Write-Host "Completed network adapter fix for VM: $VMName"
    
} catch {
    Write-Error "Failed to process VM ${VMName}: $($_.Exception.Message)"
    exit 1
}
