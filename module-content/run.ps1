using namespace System.Net

param(
  $Request,
  $TriggerMetadata
)

write-host $Request.Params.moduleName
write-host $Request.Params.moduleVersion

Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
    StatusCode = [HttpStatusCode]::OK
})
