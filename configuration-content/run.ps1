using namespace System.Net

param(
  $Request,
  $TriggerMetadata
)

write-host $Request.Params.agentId
write-host $Request.Params.configName

Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
    StatusCode = [HttpStatusCode]::OK
})
