#requires -module @{ModuleName = 'Az.Storage'; ModuleVersion = '1.1.0'}
#requires -version 6.0

using module Az.Storage
using namespace Microsoft.Azure.Cosmos.Table

class DscNodeCertificateInformation {
  [string] $FriendlyName
  [string] $Issuer
  [System.DateTimeOffset] $NotAfter
  [System.DateTimeOffset] $NotBefore
  [string] $Subject
  [string] $PublicKey
  [string] $Thumbprint
  [UInt16] $Version

  [string] ToString () {
    return $this.PublicKey
  }
}

class DscNodeRegistration {
  hidden [string] $PartitionKey
  hidden [string] $RowKey
  [System.DateTimeOffset] $Timestamp
  hidden [string] $ETag
  [Guid] $AgentId
  [string] $LCMVersion
  [string] $NodeName
  [IPAddress[]] $IPAddress
  [string[]] $ConfigurationNames
  [System.DateTimeOffset] $CreationTime
  [DscNodeCertificateInformation] $CertificateInformation

  DscNodeRegistration ([guid] $agentId, [IPAddress[]] $ipAddress, [string] $lcmVersion, [string] $nodeName, [string[]] $configurationNames, [DscNodeCertificateInformation] $certificateInformation) {
    $this.RowKey = $agentId
    $this.PartitionKey = 'dscregistration'
    $this.AgentId = $agentId
    $this.IPAddress = $ipAddress
    $this.LCMVersion = $lcmVersion
    $this.NodeName = $nodeName
    $this.ConfigurationNames = $configurationNames
    $this.CertificateInformation = $certificateInformation
    $this.CreationTime = [System.DateTimeOffset]::UtcNow
  }

  DscNodeRegistration ([DynamicTableEntity]$Entity) {
    $this.PartitionKey = $Entity.PartitionKey
    $this.RowKey = $Entity.RowKey
    $this.Timestamp = $Entity.Timestamp
    $this.ETag = $Entity.ETag
    $this.AgentId = $Entity.RowKey
    $this.LCMVersion = $Entity.Properties['LCMVersion'].StringValue
    $this.NodeName = $Entity.Properties['NodeName'].StringValue
    $this.IPAddress = ($Entity.Properties['IPAddress'].StringValue -split ',') -split ';' |
      ForEach-Object -Process {
        if ($_ -ne [string]::Empty) {
          $_
        }
      }
    $this.ConfigurationNames = $Entity.Properties['ConfigurationNames'].StringValue |
      ConvertFrom-Json

    $this.CreationTime = $Entity.Properties['CreationTime'].DateTimeOffsetValue

    $certInfo = $Entity.Properties['CertificateInformation'].StringValue | ConvertFrom-Json -AsHashtable
    $this.CertificateInformation = [DscNodeCertificateInformation]$certInfo
  }

  [DynamicTableEntity] UpdateEntity() {
    $update = [DynamicTableEntity]::new($this.PartitionKey, $this.RowKey)
    @(
      'LCMVersion'
      'NodeName'
    ).ForEach{
      if ($null -eq $this."$_") {
        $update.Properties.Add($_, [string]::Empty)
      } else {
        $update.Properties.Add($_, $this."$_")
      }
    }

    $update.Properties.Add('IPAddress', [EntityProperty]::GeneratePropertyForString(
        $this.IPAddress -join ';'
      ))

    $configurationsString = if ($this.ConfigurationNames.Count -ge 1) {
      '["{0}"]' -f ($this.ConfigurationNames -join '","')
    } else {
      '[]'
    }
    $update.Properties.Add('ConfigurationNames', [EntityProperty]::GeneratePropertyForString(
        $configurationsString
      )
    )

    $update.Properties.Add('CertificateInformation', [EntityProperty]::GeneratePropertyForString(
        ($this.CertificateInformation | ConvertTo-Json)
      )
    )

    $update.Properties.Add('CreationTime', [EntityProperty]::GeneratePropertyForDateTimeOffset(
        $this.CreationTime
      )
    )

    return $update
  }

  [TableEntity] GetEntity() {
    $entity = [TableEntity]::new($this.PartitionKey, $this.RowKey)
    $entity.ETag = $this.ETag
    return $entity
  }
}

function Get-DscRegistration {
  [OutputType([DscNodeRegistration])]
  [CmdletBinding(DefaultParameterSetName = 'All')]
  param (
    [Parameter(Mandatory, ParameterSetName = 'All')]
    [Parameter(Mandatory, ParameterSetName = 'AgentId')]
    [CloudTable] $Table,

    [Parameter(Mandatory, ParameterSetName = 'AgentId')]
    [AllowEmptyString()]
    [string] $AgentId
  )

  $tableQuery = [TableQuery]::new()

  if ($PSCmdlet.ParameterSetName -eq 'AgentId') {
    $tableQuery.FilterString = [TableQuery]::CombineFilters(
      [TableQuery]::GenerateFilterCondition(
        'PartitionKey',
        [QueryComparisons]::Equal,
        'dscregistration'
      ),
      'and',
      [TableQuery]::GenerateFilterCondition(
        'RowKey',
        [QueryComparisons]::Equal,
        $AgentId
      )
    )
  }

  if (($null -ne $TableQuery.FilterString) -or ($PSCmdlet.ParameterSetName -eq 'All')) {
    $Table.ExecuteQuery($tableQuery) | ForEach-Object -Process {
      [DscNodeRegistration]::new($_)
    }
  }
}

function Update-DscRegistration {
  [CmdletBinding(SupportsShouldProcess)]
  [Alias('New-DscRegistration')]
  param (
    [Parameter(Mandatory)]
    [CloudTable] $Table,

    [Parameter(Mandatory, ValueFromPipeline)]
    [DscNodeRegistration] $DscNodeRegistration,

    [Parameter()]
    [switch] $Replace
  )

  process {
    if ($Replace) {
      $operation = [TableOperation]::InsertOrReplace($DscNodeRegistration.UpdateEntity())
    } else {
      $operation = [TableOperation]::InsertOrMerge($DscNodeRegistration.UpdateEntity())
    }
    if ($PSCmdlet.ShouldProcess($operation.Entity.RowKey)) {
      $result = $Table.Execute(
        $operation
      )

      if ($result.HttpStatusCode -ne '204') {
        Write-Error -Message "Failed Table Operation for $($DscNodeRegistration.AgentId). StatusCode: $($result.HttpStatusCode)" -ErrorAction Continue
      }
    }
  }
}

function Remove-DscRegistration {
  [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
  param (
    [Parameter(Mandatory)]
    [CloudTable] $Table,

    [Parameter(Mandatory, ValueFromPipeline)]
    [DscNodeRegistration] $DscNodeRegistration
  )

  process {
    $operation = [TableOperation]::Delete($DscNodeRegistration.GetEntity())
    if ($PSCmdlet.ShouldProcess($operation.Entity.RowKey)) {
      $result = $Table.Execute(
        $operation
      )

      if ($result.HttpStatusCode -ne '204') {
        Write-Error -Message "Failed Table Operation for $($DscNodeRegistration.AgentId). StatusCode: $($result.HttpStatusCode)" -ErrorAction Continue
      }
    }
  }
}
