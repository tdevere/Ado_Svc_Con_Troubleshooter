function Get-AdoServiceConnectionHistory {
    <#
    .SYNOPSIS
        Retrieves execution history for Azure DevOps Service Connections.
    
    .DESCRIPTION
        Gets the audit trail of service connection usage in pipelines.
        Useful for understanding dependencies before deletion.
    
    .PARAMETER Organization
        Azure DevOps organization name
    
    .PARAMETER Project
        Project name or ID
    
    .PARAMETER EndpointId
        Service connection GUID (optional - omit to get all history)
    
    .PARAMETER Top
        Number of records to return (default: 50)
    
    .PARAMETER PAT
        Personal Access Token with 'vso.serviceendpoint' scope
    
    .PARAMETER NoLog
        Disable logging (enabled by default)
    
    .OUTPUTS
        PSCustomObject with Success, Data, Message, LogFiles properties
    
    .EXAMPLE
        Get-AdoServiceConnectionHistory -Organization "myorg" -Project "myproject" -EndpointId "guid" -PAT "token"
        
    .EXAMPLE
        Get-AdoServiceConnectionHistory -Organization "myorg" -Project "myproject" -Top 10 -PAT "token"
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Organization,
        
        [Parameter(Mandatory = $false)]
        [string]$Project,
        
        [Parameter(Mandatory = $false)]
        [string]$EndpointId,
        
        [Parameter(Mandatory = $false)]
        [int]$Top = 50,
        
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
        Top = $Top
        PAT = $PAT
        HttpMethod = 'GET'
    }
    
    try {
        # Validate GUID format if provided
        if ($EndpointId -and -not (Test-AdoGuidFormat -EndpointId $EndpointId)) {
            throw "Invalid EndpointId format. Must be a valid GUID."
        }
        
        # Create auth header
        $headers = New-AdoAuthHeader -PAT $PAT
        
        # Build URL
        $url = "https://dev.azure.com/$Organization/$Project/_apis/serviceendpoint/executionhistory?api-version=7.1&top=$Top"
        
        if ($EndpointId) {
            $url += "&endpointId=$EndpointId"
        }
        
        $LogData['RequestUrl'] = $url
        
        Write-Verbose "Retrieving execution history..."
        $result = Invoke-AdoRestMethod -Method GET -Uri $url -Headers $headers
        
        $LogData['StatusCode'] = $result.StatusCode
        $LogData['StatusDescription'] = $result.StatusDescription
        $LogData['ResponseBody'] = if ($result.Data) { $result.Data | ConvertTo-Json -Depth 5 } else { $result.RawResponse }
        
        if (-not $result.Success) {
            $LogData['Result'] = 'FAIL'
            $LogData['ErrorMessage'] = $result.ErrorMessage
            
            $logFiles = Write-AdoLog -Operation "GetHistory" -LogData $LogData -NoLog:$NoLog
            
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
        
        $data = if ($result.Data.value) {
            $result.Data.value
        } else {
            $result.Data
        }
        
        $logFiles = Write-AdoLog -Operation "GetHistory" -LogData $LogData -NoLog:$NoLog
        
        # Display results
        if ($data) {
            Write-Host "Execution History ($($data.Count) records):" -ForegroundColor Green
            
            $data | Select-Object -First 10 | ForEach-Object {
                $finishTime = if ($_.finishTime) { 
                    [DateTime]::Parse($_.finishTime).ToString("yyyy-MM-dd HH:mm:ss")
                } else { 
                    "N/A" 
                }
                
                $planType = if ($_.planType) { $_.planType } else { "Unknown" }
                $result = if ($_.result) { $_.result } else { "N/A" }
                $definition = if ($_.definition.name) { $_.definition.name } else { "N/A" }
                
                Write-Host "  - Definition: $definition | Type: $planType | Result: $result | Finished: $finishTime"
            }
            
            if ($data.Count -gt 10) {
                Write-Host "  ... and $($data.Count - 10) more records"
            }
        }
        else {
            Write-Host "No execution history found" -ForegroundColor Yellow
        }
        
        if ($logFiles) {
            Write-Host "`nLogs saved to:" -ForegroundColor Cyan
            $logFiles | ForEach-Object { Write-Host "  $_" }
        }
        
        return [PSCustomObject]@{
            Success = $true
            Data = $data
            Message = "Retrieved execution history successfully"
            LogFiles = $logFiles
        }
    }
    catch {
        $LogData['Result'] = 'ERROR'
        $LogData['ErrorMessage'] = $_.Exception.Message
        $LogData['StackTrace'] = $_.ScriptStackTrace
        
        $logFiles = Write-AdoLog -Operation "GetHistory" -LogData $LogData -NoLog:$NoLog
        
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
