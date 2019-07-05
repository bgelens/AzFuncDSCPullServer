using namespace System.Net

param(
  $Request,
  $TriggerMetadata
)

write-host $Request.Params.agentId

Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
    StatusCode = [HttpStatusCode]::OK
})
