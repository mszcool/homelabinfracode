param(
    [Parameter(Mandatory=$true)]
    [string]$VMName,
    
    [Parameter(Mandatory=$true)]
    [string]$AdapterNames,
    
    [Parameter(Mandatory=$false)]
    [string]$StaticMacAddresses = ""
)

# Parse comma-separated adapter names - ensure we get arrays even for single items
$AdapterList = @($AdapterNames -split "," | ForEach-Object { $_.ToString().Trim() } | Where-Object { $_ -ne "" })
$MacList = @()
if ($StaticMacAddresses -and $StaticMacAddresses.Trim() -ne "") {
    $MacList = @($StaticMacAddresses -split "," | ForEach-Object { $_.ToString().Trim() } | Where-Object { $_ -ne "" })
}

Write-Host "Adding disconnected network adapters to VM: $VMName"
Write-Host "Adapters to add: $($AdapterList -join ', ')"

try {
    # Get existing network adapters for the VM
    $ExistingAdapters = Get-VMNetworkAdapter -VMName $VMName | Select-Object -ExpandProperty Name
    
    for ($i = 0; $i -lt $AdapterList.Length; $i++) {
        $AdapterName = $AdapterList[$i]
        $MacAddress = if ($i -lt $MacList.Length -and $MacList[$i] -and $MacList[$i] -ne "") { $MacList[$i] } else { $null }
        
        # Check if adapter already exists
        if ($ExistingAdapters -contains $AdapterName) {
            Write-Host "Network adapter '$AdapterName' already exists on VM '$VMName' - skipping"
            continue
        }
        
        Write-Host "Adding disconnected network adapter: $AdapterName"
        
        # Add the network adapter without specifying a switch (disconnected)
        Add-VMNetworkAdapter -VMName $VMName -Name $AdapterName
        
        # Set static MAC address if provided
        if ($MacAddress -and $MacAddress -ne "") {
            # Remove colons from MAC address for Hyper-V
            $CleanMac = $MacAddress -replace ":", ""
            Write-Host "Setting static MAC address for adapter '$AdapterName': $MacAddress"
            Set-VMNetworkAdapter -VMName $VMName -Name $AdapterName -StaticMacAddress $CleanMac
        }
        
        Write-Host "Successfully added disconnected adapter: $AdapterName"
    }
    
    Write-Host "Completed adding disconnected network adapters to VM: $VMName"
}
catch {
    Write-Error "Failed to add disconnected network adapters to VM '$VMName': $($_.Exception.Message)"
    exit 1
}
