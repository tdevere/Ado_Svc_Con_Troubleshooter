function New-AdoServiceConnection {
    <#
    .SYNOPSIS
        Creates a new Azure DevOps Service Connection.
    
    .DESCRIPTION
        Creates a new service endpoint in Azure DevOps with specified configuration.
        Requires full endpoint definition including type, authorization, and project references.
        The EndpointDefinition must include serviceEndpointProjectReferences with a valid
        project GUID. Use New-AdoTestServiceConnection for a simple generic test endpoint.
    
    .PARAMETER Organization
        Azure DevOps organization name. Falls back to ORGANIZATION in .env.
    
    .PARAMETER EndpointDefinition
        Hashtable or PSCustomObject containing the complete endpoint configuration.
        Must include: name, type, url, authorization, serviceEndpointProjectReferences.
    
    .PARAMETER PAT
        Personal Access Token with 'vso.serviceendpoint_manage' scope.
        Falls back to PAT in .env.
    
    .PARAMETER NoLog
        Disable logging (enabled by default)
    
    .OUTPUTS
        PSCustomObject with Success, Data (new endpoint object), Message, LogFiles properties
    
    .EXAMPLE
        $definition = @{
            name = "MyGenericConnection"
            type = "generic"
            url  = "https://myserver.example.com"
            authorization = @{ scheme = "UsernamePassword"; parameters = @{ username = "user"; password = "pass" } }
            isShared = $false; isReady = $true
            serviceEndpointProjectReferences = @(@{
                projectReference = @{ id = "<project-guid>"; name = "myproject" }
                name = "MyGenericConnection"
            })
        }
        New-AdoServiceConnection -Organization "myorg" -EndpointDefinition $definition -PAT "token"
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Organization,
        
        [Parameter(Mandatory = $true)]
        [object]$EndpointDefinition,
        
        [Parameter(Mandatory = $false)]
        [string]$PAT,
        
        [switch]$NoLog
    )

    $resolvedDefaults = Resolve-AdoDefaultContext -Organization $Organization -PAT $PAT -Required @('Organization', 'PAT')
    $Organization = $resolvedDefaults.Organization
    $PAT            = $resolvedDefaults.PAT

    $LogData = @{
        Organization     = $Organization
        EndpointName     = if ($EndpointDefinition.name) { $EndpointDefinition.name } else { '(unknown)' }
        EndpointType     = if ($EndpointDefinition.type) { $EndpointDefinition.type } else { '(unknown)' }
        PAT              = $PAT
        HttpMethod       = 'POST'
    }

    try {
        # Validate minimal required fields
        if (-not $EndpointDefinition.name) { throw "EndpointDefinition must include 'name'." }
        if (-not $EndpointDefinition.type) { throw "EndpointDefinition must include 'type'." }
        if (-not $EndpointDefinition.serviceEndpointProjectReferences) {
            throw "EndpointDefinition must include 'serviceEndpointProjectReferences' with at least one project reference containing a valid project GUID."
        }

        $headers              = New-AdoAuthHeader -PAT $PAT
        $headers['Content-Type'] = 'application/json'

        $postUrl  = "https://dev.azure.com/$Organization/_apis/serviceendpoint/endpoints?api-version=7.1"
        $LogData['PostUrl'] = $postUrl

        Write-Verbose "Creating service connection '$($EndpointDefinition.name)' in org '$Organization'..."

        $postResult = Invoke-AdoRestMethod -Method POST -Uri $postUrl -Headers $headers -Body $EndpointDefinition

        if (-not $postResult.Success) {
            $LogData['Result']       = 'FAIL'
            $LogData['ErrorMessage'] = $postResult.ErrorMessage
            $LogData['StatusCode']   = $postResult.StatusCode
            $logFiles = Write-AdoLog -Operation "Create" -LogData $LogData -NoLog:$NoLog

            $hint = switch ($postResult.StatusCode) {
                401 { "Check PAT is valid and has 'vso.serviceendpoint_manage' scope." }
                403 { "PAT lacks 'Manage' permission on service connections." }
                400 { "EndpointDefinition is invalid - verify all required fields and that project GUID is correct." }
                default { $postResult.ErrorMessage }
            }

            return [PSCustomObject]@{ Success = $false; Data = $null; Message = $hint; LogFiles = $logFiles }
        }

        $newEndpoint = $postResult.Data
        $LogData['Result']     = 'SUCCESS'
        $LogData['EndpointId'] = $newEndpoint.id
        $logFiles = Write-AdoLog -Operation "Create" -LogData $LogData -NoLog:$NoLog

        Write-Host ""
        Write-Host "  Service connection created successfully." -ForegroundColor Green
        Write-Host "  Name : $($newEndpoint.name)"            -ForegroundColor Cyan
        Write-Host "  ID   : $($newEndpoint.id)"              -ForegroundColor Cyan
        Write-Host "  Type : $($newEndpoint.type)"            -ForegroundColor Cyan
        Write-Host ""

        return [PSCustomObject]@{
            Success  = $true
            Data     = $newEndpoint
            Message  = "Created '$($newEndpoint.name)' (id: $($newEndpoint.id))"
            LogFiles = $logFiles
        }
    }
    catch {
        $LogData['Result']       = 'FAIL'
        $LogData['ErrorMessage'] = $_.Exception.Message
        $logFiles = Write-AdoLog -Operation "Create" -LogData $LogData -NoLog:$NoLog

        return [PSCustomObject]@{ Success = $false; Data = $null; Message = $_.Exception.Message; LogFiles = $logFiles }
    }
}
