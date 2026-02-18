function Update-AdoServiceConnectionAuth {
    <#
    .SYNOPSIS
        Refreshes or replaces credentials on an Azure DevOps Service Connection.

    .DESCRIPTION
        Two modes:

        1. OAuth Refresh (-OAuthRefresh switch, default)
           Calls the POST /endpoints?endpointIds={id} API to ask Azure DevOps to
           re-negotiate the OAuth token for the connection. Works only for connections
           whose scheme is OAuth-based (e.g. GitHub OAuth, Azure Resource Manager with
           automatic service principal). Does NOT require new credential values.

        2. Credential Update (-NewCredentials hashtable)
           Fetches the existing endpoint definition via GET, merges in the new
           authorization parameters supplied in -NewCredentials, then PUTs the updated
           definition back. Use this when a service principal secret or PAT has rotated.

           -NewCredentials keys match the authorization.parameters object for the
           connection type, e.g.:
             @{ serviceprincipalkey = "new-secret-value" }   # AzureRM SPN
             @{ accessToken         = "new-github-pat" }     # GitHub PAT
             @{ password            = "new-password" }       # Generic UsernamePassword

    .PARAMETER Organization
        Azure DevOps organization name. Falls back to ORGANIZATION in .env.

    .PARAMETER Project
        Project name or ID. Falls back to PROJECT in .env.

    .PARAMETER EndpointId
        Service connection GUID. Falls back to ENDPOINT_ID / TEST_ENDPOINT_ID in .env.

    .PARAMETER PAT
        Personal Access Token with 'vso.serviceendpoint_manage' scope.
        Falls back to PAT in .env.

    .PARAMETER OAuthRefresh
        Trigger OAuth token refresh via POST (default mode, no new credentials needed).

    .PARAMETER NewCredentials
        Hashtable of authorization parameter key/value pairs to update.
        When supplied, -OAuthRefresh is ignored and a GET-then-PUT update is performed.

    .PARAMETER NoLog
        Disable logging (enabled by default).

    .OUTPUTS
        PSCustomObject with Success, Data, Message, LogFiles properties.

    .EXAMPLE
        # OAuth refresh (e.g. GitHub OAuth connection)
        Update-AdoServiceConnectionAuth -EndpointId "guid"

    .EXAMPLE
        # Rotate a service principal secret on an AzureRM connection
        Update-AdoServiceConnectionAuth -EndpointId "guid" -NewCredentials @{ serviceprincipalkey = "NEW-SECRET" }

    .EXAMPLE
        # Update a GitHub PAT-based connection
        Update-AdoServiceConnectionAuth -EndpointId "guid" -NewCredentials @{ accessToken = "ghp_newtoken" }
    #>
    [CmdletBinding(DefaultParameterSetName = 'OAuth')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Organization,

        [Parameter(Mandatory = $false)]
        [string]$Project,

        [Parameter(Mandatory = $false)]
        [string]$EndpointId,

        [Parameter(Mandatory = $false)]
        [string]$PAT,

        [Parameter(ParameterSetName = 'OAuth')]
        [switch]$OAuthRefresh,

        [Parameter(Mandatory = $true, ParameterSetName = 'Credentials')]
        [hashtable]$NewCredentials,

        [switch]$NoLog
    )

    $resolvedDefaults = Resolve-AdoDefaultContext `
        -Organization $Organization -Project $Project -PAT $PAT -EndpointId $EndpointId `
        -Required @('Organization', 'Project', 'PAT', 'EndpointId')

    $Organization = $resolvedDefaults.Organization
    $Project      = $resolvedDefaults.Project
    $PAT          = $resolvedDefaults.PAT
    $EndpointId   = $resolvedDefaults.EndpointId

    if (-not (Test-AdoGuidFormat -EndpointId $EndpointId)) {
        throw "Invalid EndpointId format. Must be a valid GUID."
    }

    $LogData = @{
        Organization = $Organization
        Project      = $Project
        EndpointId   = $EndpointId
        Mode         = $PSCmdlet.ParameterSetName
        PAT          = $PAT
    }

    $headers = New-AdoAuthHeader -PAT $PAT
    $headers['Content-Type'] = 'application/json'

    try {
        # ── Step 1: GET current definition (needed for both modes) ─────────────
        Write-Host ""
        Write-Host "  Fetching current endpoint definition..." -ForegroundColor DarkGray

        $getUrl    = "https://dev.azure.com/$Organization/$Project/_apis/serviceendpoint/endpoints/${EndpointId}?api-version=7.1"
        $getResult = Invoke-AdoRestMethod -Method GET -Uri $getUrl -Headers $headers

        if (-not $getResult.Success) {
            $hint = switch ($getResult.StatusCode) {
                401 { "PAT is invalid or expired." }
                404 { "Endpoint '$EndpointId' not found in '$Organization/$Project'." }
                default { $getResult.ErrorMessage }
            }
            $LogData['Result'] = 'FAIL'; $LogData['ErrorMessage'] = $hint
            $logFiles = Write-AdoLog -Operation "UpdateAuth" -LogData $LogData -NoLog:$NoLog
            return [PSCustomObject]@{ Success = $false; Data = $null; Message = $hint; LogFiles = $logFiles }
        }

        $endpoint = $getResult.Data
        Write-Host "  Found : $($endpoint.name) ($($endpoint.type))" -ForegroundColor DarkGray
        Write-Host "  Scheme: $($endpoint.authorization.scheme)"     -ForegroundColor DarkGray

        # ── Mode A: OAuth refresh (POST) ───────────────────────────────────────
        if ($PSCmdlet.ParameterSetName -eq 'OAuth') {
            Write-Host ""
            Write-Host "  Requesting OAuth token refresh..." -ForegroundColor Yellow

            $postUrl    = "https://dev.azure.com/$Organization/$Project/_apis/serviceendpoint/endpoints?endpointIds=$EndpointId&api-version=7.1"
            $LogData['HttpMethod'] = 'POST'
            $LogData['Url']        = $postUrl

            $postResult = Invoke-AdoRestMethod -Method POST -Uri $postUrl -Headers $headers -Body @{}

            if (-not $postResult.Success) {
                $hint = switch ($postResult.StatusCode) {
                    400 { "This connection type does not support OAuth refresh. Use -NewCredentials to update credentials directly." }
                    401 { "PAT lacks 'vso.serviceendpoint_manage' scope." }
                    default { $postResult.ErrorMessage }
                }
                $LogData['Result'] = 'FAIL'; $LogData['ErrorMessage'] = $hint
                $logFiles = Write-AdoLog -Operation "UpdateAuth" -LogData $LogData -NoLog:$NoLog
                return [PSCustomObject]@{ Success = $false; Data = $null; Message = $hint; LogFiles = $logFiles }
            }

            $LogData['Result'] = 'SUCCESS'
            $logFiles = Write-AdoLog -Operation "UpdateAuth" -LogData $LogData -NoLog:$NoLog

            Write-Host ""
            Write-Host "  OAuth refresh submitted successfully." -ForegroundColor Green
            Write-Host "  Azure DevOps will re-negotiate the token in the background." -ForegroundColor DarkGray
            Write-Host "  Run Test-AdoServiceConnection to verify isReady returns true." -ForegroundColor DarkGray
            Write-Host ""

            return [PSCustomObject]@{
                Success  = $true
                Data     = $postResult.Data
                Message  = "OAuth refresh submitted for '$($endpoint.name)'"
                LogFiles = $logFiles
            }
        }

        # ── Mode B: Credential update (GET then PUT) ───────────────────────────
        Write-Host ""
        Write-Host "  Merging new credentials into endpoint definition..." -ForegroundColor Yellow

        # Merge supplied key/value pairs into the existing authorization.parameters
        foreach ($key in $NewCredentials.Keys) {
            $endpoint.authorization.parameters | Add-Member -MemberType NoteProperty -Name $key -Value $NewCredentials[$key] -Force
        }

        $putUrl = "https://dev.azure.com/$Organization/_apis/serviceendpoint/endpoints/${EndpointId}?api-version=7.1"
        $LogData['HttpMethod'] = 'PUT'
        $LogData['Url']        = $putUrl
        $LogData['UpdatedKeys'] = ($NewCredentials.Keys -join ', ')

        $putResult = Invoke-AdoRestMethod -Method PUT -Uri $putUrl -Headers $headers -Body $endpoint

        if (-not $putResult.Success) {
            $hint = switch ($putResult.StatusCode) {
                400 { "The credential keys supplied do not match the connection's authorization scheme ($($endpoint.authorization.scheme)). Check -NewCredentials keys." }
                401 { "PAT lacks 'vso.serviceendpoint_manage' scope." }
                403 { "PAT lacks Manage permission on this service connection." }
                default { $putResult.ErrorMessage }
            }
            $LogData['Result'] = 'FAIL'; $LogData['ErrorMessage'] = $hint
            $logFiles = Write-AdoLog -Operation "UpdateAuth" -LogData $LogData -NoLog:$NoLog
            return [PSCustomObject]@{ Success = $false; Data = $null; Message = $hint; LogFiles = $logFiles }
        }

        $LogData['Result'] = 'SUCCESS'
        $logFiles = Write-AdoLog -Operation "UpdateAuth" -LogData $LogData -NoLog:$NoLog

        Write-Host ""
        Write-Host "  Credentials updated successfully." -ForegroundColor Green
        Write-Host "  Run Test-AdoServiceConnection to verify the connection is healthy." -ForegroundColor DarkGray
        Write-Host ""

        return [PSCustomObject]@{
            Success  = $true
            Data     = $putResult.Data
            Message  = "Credentials updated for '$($endpoint.name)' (keys: $($NewCredentials.Keys -join ', '))"
            LogFiles = $logFiles
        }
    }
    catch {
        $LogData['Result'] = 'FAIL'; $LogData['ErrorMessage'] = $_.Exception.Message
        $logFiles = Write-AdoLog -Operation "UpdateAuth" -LogData $LogData -NoLog:$NoLog
        return [PSCustomObject]@{ Success = $false; Data = $null; Message = $_.Exception.Message; LogFiles = $logFiles }
    }
}
