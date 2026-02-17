function Remove-AdoServiceConnection {
    <#
    .SYNOPSIS
        Deletes an Azure DevOps Service Connection.
    
    .DESCRIPTION
        Deletes a service connection from specified Azure DevOps projects using REST API.
        Includes pre-deletion validation, optional execution history check, and comprehensive logging.
        
        CRITICAL: Delete operation is organization-scoped, not project-scoped.
    
    .PARAMETER Organization
        Azure DevOps organization name (without dev.azure.com)
    
    .PARAMETER Project
        Project name or ID (required for pre-validation queries)
    
    .PARAMETER EndpointId
        Service connection GUID to delete
    
    .PARAMETER ProjectIds
        Array of project IDs from which to delete the endpoint. Defaults to current project.
    
    .PARAMETER PAT
        Personal Access Token with 'vso.serviceendpoint_manage' scope
    
    .PARAMETER Deep
        Delete the service principal (SPN) created by the endpoint
    
    .PARAMETER SkipHistory
        Skip execution history check before deletion
    
    .PARAMETER NoLog
        Disable logging (enabled by default)
    
    .OUTPUTS
        PSCustomObject with Success, Message, LogFiles properties
    
    .EXAMPLE
        Remove-AdoServiceConnection -Organization "myorg" -Project "myproject" -EndpointId "guid" -PAT "token"
        
    .EXAMPLE
        Remove-AdoServiceConnection -Organization "myorg" -Project "myproject" -EndpointId "guid" -PAT "token" -Deep
        
    .EXAMPLE
        Remove-AdoServiceConnection -Organization "myorg" -Project "myproject" -EndpointId "guid" -PAT "token" -SkipHistory -NoLog
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Organization,
        
        [Parameter(Mandatory = $false)]
        [string]$Project,
        
        [Parameter(Mandatory = $false)]
        [string]$EndpointId,
        
        [Parameter(Mandatory = $false)]
        [string[]]$ProjectIds,
        
        [Parameter(Mandatory = $false)]
        [string]$PAT,
        
        [switch]$Deep,
        
        [switch]$SkipHistory,
        
        [switch]$NoLog
    )

    $resolvedDefaults = Resolve-AdoDefaultContext -Organization $Organization -Project $Project -PAT $PAT -EndpointId $EndpointId -Required @('Organization', 'Project', 'PAT', 'EndpointId')
    $Organization = $resolvedDefaults.Organization
    $Project = $resolvedDefaults.Project
    $PAT = $resolvedDefaults.PAT
    $EndpointId = $resolvedDefaults.EndpointId
    
    $LogData = @{
        Organization = $Organization
        Project = $Project
        EndpointId = $EndpointId
        ProjectIds = $ProjectIds
        Deep = $Deep.IsPresent
        SkipHistory = $SkipHistory.IsPresent
        PAT = $PAT
        HttpMethod = 'DELETE'
    }
    
    try {
        # Validate GUID format
        if (-not (Test-AdoGuidFormat -EndpointId $EndpointId)) {
            throw "Invalid EndpointId format. Must be a valid GUID."
        }
        
        # Create auth header
        $headers = New-AdoAuthHeader -PAT $PAT
        
        # Step 1: Pre-deletion GET - Verify endpoint exists
        Write-Verbose "Step 1: Verifying endpoint exists..."
        $getUrl = "https://dev.azure.com/$Organization/$Project/_apis/serviceendpoint/endpoints/${EndpointId}?api-version=7.1"
        $LogData['PreDeleteUrl'] = $getUrl
        
        $getResult = Invoke-AdoRestMethod -Method GET -Uri $getUrl -Headers $headers
        
        if (-not $getResult.Success) {
            $LogData['Result'] = 'FAIL'
            $LogData['ErrorMessage'] = "Pre-deletion check failed: $($getResult.ErrorMessage)"
            $LogData['StatusCode'] = $getResult.StatusCode
            $LogData['StatusDescription'] = $getResult.StatusDescription
            
            $logFiles = Write-AdoLog -Operation "Remove" -LogData $LogData -NoLog:$NoLog
            
            return [PSCustomObject]@{
                Success = $false
                Message = $LogData['ErrorMessage']
                LogFiles = $logFiles
            }
        }
        
        $endpointName = $getResult.Data.name
        $LogData['EndpointName'] = $endpointName
        $LogData['PreDeleteResponse'] = $getResult.Data | ConvertTo-Json -Depth 5
        
        Write-Host "Found endpoint: $endpointName (ID: $EndpointId)" -ForegroundColor Cyan
        
        # Step 2: Get Execution History (unless skipped)
        if (-not $SkipHistory) {
            Write-Verbose "Step 2: Checking execution history..."
            
            try {
                $historyResult = Get-AdoServiceConnectionHistory -Organization $Organization -Project $Project -EndpointId $EndpointId -PAT $PAT -NoLog
                
                if ($historyResult.Success -and $historyResult.Data -and $historyResult.Data.Count -gt 0) {
                    $recentUsage = $historyResult.Data | Select-Object -First 5
                    $LogData['ExecutionHistory'] = $recentUsage | ConvertTo-Json -Depth 3
                    
                    Write-Host "`nRecent pipeline usage (last 5 executions):" -ForegroundColor Yellow
                    $recentUsage | ForEach-Object {
                        $finishTime = if ($_.finishTime) { 
                            [DateTime]::Parse($_.finishTime).ToString("yyyy-MM-dd HH:mm")
                        } else { 
                            "N/A" 
                        }
                        $planType = if ($_.planType) { $_.planType } else { "Unknown" }
                        $result = if ($_.result) { $_.result } else { "N/A" }
                        $definition = if ($_.definition.name) { $_.definition.name } else { "N/A" }
                        
                        Write-Host "  - $definition | Type: $planType | Result: $result | Time: $finishTime"
                    }
                    Write-Host ""
                }
                else {
                    Write-Host "`nNo execution history found (endpoint hasn't been used yet)" -ForegroundColor Gray
                }
            }
            catch {
                Write-Warning "Could not retrieve execution history: $_"
            }
        }
        
        # Step 3: Confirm deletion
        if ($PSCmdlet.ShouldProcess("Service Connection '$endpointName' ($EndpointId)", "Delete")) {
            
            # Determine project IDs for deletion
            if (-not $ProjectIds) {
                # Use current project ID from GET response
                $ProjectIds = @($getResult.Data.serviceEndpointProjectReferences[0].projectReference.id)
            }
            
            $projectIdsParam = $ProjectIds -join ','
            
            # Build DELETE URL
            $deleteUrl = "https://dev.azure.com/$Organization/_apis/serviceendpoint/endpoints/${EndpointId}?projectIds=$projectIdsParam&api-version=7.1"
            
            if ($Deep) {
                $deleteUrl += "&deep=true"
            }
            
            $LogData['RequestUrl'] = $deleteUrl
            
            Write-Verbose "Step 3: Executing DELETE..."
            Write-Host "Deleting service connection..." -ForegroundColor Yellow
            
            $deleteResult = Invoke-AdoRestMethod -Method DELETE -Uri $deleteUrl -Headers $headers
            
            $LogData['StatusCode'] = $deleteResult.StatusCode
            $LogData['StatusDescription'] = $deleteResult.StatusDescription
            $LogData['ResponseBody'] = if ($deleteResult.Data) { $deleteResult.Data | ConvertTo-Json -Depth 5 } else { $deleteResult.RawResponse }
            
            if (-not $deleteResult.Success) {
                $LogData['Result'] = 'FAIL'
                $LogData['ErrorMessage'] = $deleteResult.ErrorMessage
                
                $logFiles = Write-AdoLog -Operation "Remove" -LogData $LogData -NoLog:$NoLog
                
                Write-Host "FAIL: $($deleteResult.ErrorMessage)" -ForegroundColor Red
                
                if ($logFiles) {
                    Write-Host "`nLogs saved to:" -ForegroundColor Cyan
                    $logFiles | ForEach-Object { Write-Host "  $_" }
                }
                
                return [PSCustomObject]@{
                    Success = $false
                    Message = $deleteResult.ErrorMessage
                    LogFiles = $logFiles
                }
            }
            
            # Step 4: Post-deletion verification
            Write-Verbose "Step 4: Verifying deletion..."
            Write-Host "Waiting for Azure DevOps to propagate deletion..." -ForegroundColor Gray
            Start-Sleep -Seconds 2  # Increased delay for Azure DevOps propagation
            
            $verifyResult = Invoke-AdoRestMethod -Method GET -Uri $getUrl -Headers $headers
            
            $LogData['PostDeleteStatusCode'] = $verifyResult.StatusCode
            $LogData['PostDeleteVerification'] = if ($verifyResult.StatusCode -eq 404) { "Confirmed - Endpoint deleted" } else { "Warning - Endpoint still exists" }
            
            if ($verifyResult.StatusCode -eq 404) {
                $LogData['Result'] = 'PASS'
                
                $logFiles = Write-AdoLog -Operation "Remove" -LogData $LogData -NoLog:$NoLog
                
                Write-Host "PASS: Service connection successfully deleted" -ForegroundColor Green
                
                if ($logFiles) {
                    Write-Host "`nLogs saved to:" -ForegroundColor Cyan
                    $logFiles | ForEach-Object { Write-Host "  $_" }
                }
                
                return [PSCustomObject]@{
                    Success = $true
                    Message = "Service connection '$endpointName' successfully deleted"
                    LogFiles = $logFiles
                }
            }
            else {
                $LogData['Result'] = 'PARTIAL'
                $LogData['ErrorMessage'] = "DELETE returned success but endpoint still exists (may be propagation delay)"
                
                $logFiles = Write-AdoLog -Operation "Remove" -LogData $LogData -NoLog:$NoLog
                
                Write-Host "WARNING: DELETE succeeded (204) but endpoint still visible in API" -ForegroundColor Yellow
                Write-Host "`nThis is often an Azure DevOps propagation delay. Please verify:" -ForegroundColor Cyan
                Write-Host "  1. Check Azure DevOps portal: https://dev.azure.com/$Organization/$Project/_settings/adminservices" -ForegroundColor White
                Write-Host "  2. Wait 30-60 seconds and check if endpoint is gone" -ForegroundColor White
                Write-Host "  3. If endpoint persists, it may be in a corrupted state" -ForegroundColor White
                
                Write-Host "`nIf the service connection still exists after 2 minutes, please collect:" -ForegroundColor Yellow
                Write-Host "  • Log files from: $(Split-Path $logFiles[0])" -ForegroundColor Gray
                Write-Host "  • Screenshot from portal showing the service connection" -ForegroundColor Gray
                Write-Host "  • Output of: Get-AdoServiceConnection -Organization $Organization -Project $Project -EndpointId $EndpointId -PAT `$pat" -ForegroundColor Gray
                
                if ($logFiles) {
                    Write-Host "`nLogs saved to:" -ForegroundColor Cyan
                    $logFiles | ForEach-Object { Write-Host "  $_" }
                }
                
                return [PSCustomObject]@{
                    Success = $false
                    Message = "DELETE succeeded (204) but verification failed - check portal and wait for propagation"
                    LogFiles = $logFiles
                }
            }
        }
        else {
            Write-Host "Operation cancelled by user" -ForegroundColor Yellow
            return [PSCustomObject]@{
                Success = $false
                Message = "Operation cancelled"
                LogFiles = @()
            }
        }
    }
    catch {
        $LogData['Result'] = 'ERROR'
        $LogData['ErrorMessage'] = $_.Exception.Message
        $LogData['StackTrace'] = $_.ScriptStackTrace
        
        $logFiles = Write-AdoLog -Operation "Remove" -LogData $LogData -NoLog:$NoLog
        
        Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
        
        if ($logFiles) {
            Write-Host "`nLogs saved to:" -ForegroundColor Cyan
            $logFiles | ForEach-Object { Write-Host "  $_" }
        }
        
        return [PSCustomObject]@{
            Success = $false
            Message = $_.Exception.Message
            LogFiles = $logFiles
        }
    }
}
