function Get-AdoServiceConnection {
    <#
    .SYNOPSIS
        Retrieves Azure DevOps Service Connection(s).
    
    .DESCRIPTION
        Gets service connection details from Azure DevOps using REST API.
        Can retrieve a single endpoint by ID or list all endpoints in a project.
    
    .PARAMETER Organization
        Azure DevOps organization name
    
    .PARAMETER Project
        Project name or ID
    
    .PARAMETER EndpointId
        Service connection GUID (optional - omit to list all)
    
    .PARAMETER EndpointNames
        Array of endpoint friendly names to query
    
    .PARAMETER Type
        Filter by endpoint type (e.g., "AzureRM", "GitHub", "Generic")
    
    .PARAMETER IncludeFailed
        Include failed service connections in the results (only for list operations)
    
    .PARAMETER PAT
        Personal Access Token with 'vso.serviceendpoint' scope
    
    .PARAMETER NoLog
        Disable logging (enabled by default)
    
    .OUTPUTS
        PSCustomObject with Success, Data, Message, LogFiles properties
    
    .EXAMPLE
        Get-AdoServiceConnection -Organization "myorg" -Project "myproject" -EndpointId "guid" -PAT "token"
        
    .EXAMPLE
        Get-AdoServiceConnection -Organization "myorg" -Project "myproject" -PAT "token"
        
    .EXAMPLE
        Get-AdoServiceConnection -Organization "myorg" -Project "myproject" -Type "AzureRM" -PAT "token"
        
    .EXAMPLE
        Get-AdoServiceConnection -Organization "myorg" -Project "myproject" -IncludeFailed -PAT "token"
    #>
    [CmdletBinding(DefaultParameterSetName = 'List')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Organization,
        
        [Parameter(Mandatory = $false)]
        [string]$Project,
        
        [Parameter(Mandatory = $false, ParameterSetName = 'Single')]
        [string]$EndpointId,
        
        [Parameter(Mandatory = $false, ParameterSetName = 'ByName')]
        [string[]]$EndpointNames,
        
        [Parameter(Mandatory = $false, ParameterSetName = 'List')]
        [string]$Type,
        
        [Parameter(Mandatory = $false, ParameterSetName = 'List')]
        [Parameter(Mandatory = $false, ParameterSetName = 'ByName')]
        [switch]$IncludeFailed,
        
        [Parameter(Mandatory = $false)]
        [string]$PAT,
        
        [switch]$NoLog
    )

    $resolvedDefaults = Resolve-AdoDefaultContext -Organization $Organization -Project $Project -PAT $PAT -EndpointId $EndpointId -Required @('Organization', 'Project', 'PAT')
    $Organization = $resolvedDefaults.Organization
    $Project = $resolvedDefaults.Project
    $PAT = $resolvedDefaults.PAT
    $EndpointId = if ($EndpointId) { $EndpointId } else { $resolvedDefaults.EndpointId }
    
    $LogData = @{
        Organization = $Organization
        Project = $Project
        EndpointId = $EndpointId
        EndpointNames = $EndpointNames
        Type = $Type
        IncludeFailed = $IncludeFailed.IsPresent
        PAT = $PAT
        HttpMethod = 'GET'
    }
    
    try {
        # Create auth header
        $headers = New-AdoAuthHeader -PAT $PAT
        
        # Build URL based on parameter set
        if ($PSCmdlet.ParameterSetName -eq 'Single') {
            # Validate GUID format
            if (-not (Test-AdoGuidFormat -EndpointId $EndpointId)) {
                throw "Invalid EndpointId format. Must be a valid GUID."
            }
            
            $url = "https://dev.azure.com/$Organization/$Project/_apis/serviceendpoint/endpoints/${EndpointId}?api-version=7.1"
        }
        elseif ($PSCmdlet.ParameterSetName -eq 'ByName') {
            $namesParam = $EndpointNames -join ','
            $url = "https://dev.azure.com/$Organization/$Project/_apis/serviceendpoint/endpoints?endpointNames=$namesParam&api-version=7.1"
            
            if ($IncludeFailed) {
                $url += "&includeFailed=true"
            }
        }
        else {
            # List all
            $url = "https://dev.azure.com/$Organization/$Project/_apis/serviceendpoint/endpoints?api-version=7.1"
            
            if ($Type) {
                $url += "&type=$Type"
            }
            
            if ($IncludeFailed) {
                $url += "&includeFailed=true"
            }
        }
        
        $LogData['RequestUrl'] = $url
        
        Write-Verbose "Retrieving service connection(s)..."
        $result = Invoke-AdoRestMethod -Method GET -Uri $url -Headers $headers
        
        $LogData['StatusCode'] = $result.StatusCode
        $LogData['StatusDescription'] = $result.StatusDescription
        $LogData['ResponseBody'] = if ($result.Data) { $result.Data | ConvertTo-Json -Depth 5 } else { $result.RawResponse }
        
        if (-not $result.Success) {
            $LogData['Result'] = 'FAIL'
            $LogData['ErrorMessage'] = $result.ErrorMessage
            
            $logFiles = Write-AdoLog -Operation "Get" -LogData $LogData -NoLog:$NoLog
            
            Write-Host "FAIL: $($result.ErrorMessage)" -ForegroundColor Red
            
            if ($logFiles) {
                Write-Host "`nLogs saved to:" -ForegroundColor Cyan
                $logFiles | ForEach-Object { Write-Host "  $_" }
            }
            
            return [PSCustomObject]@{
                Success = $false
                Data = $null
                Message = $result.ErrorMessage
                LogFiles = $logFiles
            }
        }
        
        $LogData['Result'] = 'PASS'
        
        # Handle list vs. single response
        $data = if ($result.Data.value) {
            $result.Data.value
        } else {
            $result.Data
        }
        
        # Add endpoint summary to logs for easy parsing
        if ($data -is [array]) {
            $LogData['EndpointCount'] = $data.Count
            $LogData['EndpointSummary'] = $data | ForEach-Object {
                @{
                    Id = $_.id
                    Name = $_.name
                    Type = $_.type
                    Owner = $_.owner
                    IsReady = $_.isReady
                }
            }
        }
        else {
            $LogData['EndpointCount'] = 1
            $LogData['EndpointSummary'] = @{
                Id = $data.id
                Name = $data.name
                Type = $data.type
                Owner = $data.owner
                IsReady = $data.isReady
            }
        }
        
        $logFiles = Write-AdoLog -Operation "Get" -LogData $LogData -NoLog:$NoLog
        
        # Display results
        if ($data -is [array]) {
            Write-Host "Found $($data.Count) service connection(s)" -ForegroundColor Green
            $data | ForEach-Object {
                Write-Host "  - $($_.name) ($($_.type)) [ID: $($_.id)]"
            }
        }
        else {
            Write-Host "Service Connection Details:" -ForegroundColor Green
            Write-Host "  Name: $($data.name)"
            Write-Host "  Type: $($data.type)"
            Write-Host "  ID: $($data.id)"
            Write-Host "  URL: $($data.url)"
            Write-Host "  Owner: $($data.owner)"
        }
        
        if ($logFiles) {
            Write-Host "`nLogs saved to:" -ForegroundColor Cyan
            $logFiles | ForEach-Object { Write-Host "  $_" }
        }
        
        return [PSCustomObject]@{
            Success = $true
            Data = $data
            Message = "Retrieved service connection(s) successfully"
            LogFiles = $logFiles
        }
    }
    catch {
        $LogData['Result'] = 'ERROR'
        $LogData['ErrorMessage'] = $_.Exception.Message
        $LogData['StackTrace'] = $_.ScriptStackTrace
        
        $logFiles = Write-AdoLog -Operation "Get" -LogData $LogData -NoLog:$NoLog
        
        Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
        
        if ($logFiles) {
            Write-Host "`nLogs saved to:" -ForegroundColor Cyan
            $logFiles | ForEach-Object { Write-Host "  $_" }
        }
        
        return [PSCustomObject]@{
            Success = $false
            Data = $null
            Message = $_.Exception.Message
            LogFiles = $logFiles
        }
    }
}
