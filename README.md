# AzFuncDSCPullServer

DSC Pull Server running on Azure Functions using Azure Storage Blobs and Tables

## Prepare Storage account

Prepare the storage account so it contains the blob containers and tables (reflect this with the application settings)

```powershell
$stContext = New-AzStorageContext -ConnectionString '<connectionString>'

# create tables if they don't exist yet
@(
  'dscReg'
  'dscRep'
  'dscMod'
  'dscConf'
).ForEach{
  $table = Get-AzStorageTable -Name $_ -Context $stContext -ErrorAction SilentlyContinue
  if ($null -eq $table) {
    $null = New-AzStorageTable -Name $_ -Context $stContext -ErrorAction Stop
  }
}

# create blob containers if they don't exist
@(
  'dscmod'
  'dscconf'
).ForEach{
  $container = Get-AzStorageContainer -Name $_ -Context $stContext -ErrorAction SilentlyContinue

  if ($null -eq $container) {
    $null = New-AzStorageContainer -Name $_ -Context $stContext -Permission Off -ErrorAction Stop
  } else {
    # make sure permission is ok
    $null = Set-AzStorageContainerAcl -Name $_ -Context $stContext -Permission Off
  }
}
```

