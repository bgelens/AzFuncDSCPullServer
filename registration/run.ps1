using namespace System.Net
using module AzFuncDscPullServer

param(
  $Request,
  $TriggerMetadata
)

$agentId = $Request.Params.agentId

$stContext = New-AzStorageContext -ConnectionString $env:AzureWebJobsStorage
$table = (Get-AzStorageTable -Name $env:registrationTableName -Context $stContext).CloudTable

$existingNode = Get-DscRegistration -Table $table -AgentId $agentId

if ($null -eq $existingNode) {
  # ReportServer registration does not contain ConfigurationNames
  $configNames = if ($Request.Body.RegistrationInformation.RegistrationMessageType -eq 'ConfigurationRepository') {
    $Request.Body.ConfigurationNames
  } else {
    $null
  }

  $newNode = [DscNodeRegistration]::new(
    $agentId,
    ($Request.Body.AgentInformation.IPAddress -split ';' -split ',' | Where-Object -FilterScript { $_ -ne [string]::Empty }),
    $Request.Body.AgentInformation.LCMVersion,
    $Request.Body.AgentInformation.NodeName,
    $configNames
  )

  Update-DscRegistration -Table $table -DscNodeRegistration $newNode
} else {
  $existingNode.IPAddress = $Request.Body.AgentInformation.IPAddress -split ';' -split ',' | Where-Object -FilterScript { $_ -ne [string]::Empty }
  $existingNode.LCMVersion = $Request.Body.AgentInformation.LCMVersion
  $existingNode.NodeName = $Request.Body.AgentInformation.NodeName

  # ReportServer registration does not contain ConfigurationNames
  if ($Request.Body.RegistrationInformation.RegistrationMessageType -eq 'ConfigurationRepository') {
    $existingNode.ConfigurationNames = $Request.Body.ConfigurationNames
  }

  Update-DscRegistration -Table $table -DscNodeRegistration $existingNode
}

Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
    StatusCode = [HttpStatusCode]::NoContent
    Body = [string]::Empty
  })
