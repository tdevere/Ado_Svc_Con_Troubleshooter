function Invoke-AdoRestMethod {
    <#
    .SYNOPSIS
        Wrapper for Invoke-RestMethod with ADO-specific error handling.
    
    .DESCRIPTION
        Provides consistent error handling and response parsing for Azure DevOps REST API calls.
        Returns detailed error information for common HTTP status codes.
    
    .PARAMETER Method
        HTTP method (GET, POST, PUT, PATCH, DELETE)
    
    .PARAMETER Uri
        Full URI for the REST API call
    
    .PARAMETER Headers
        Headers hashtable (including Authorization)
    
    .PARAMETER Body
        Request body (will be converted to JSON if needed)
    
    .OUTPUTS
        PSCustomObject with properties: Success, StatusCode, Data, ErrorMessage
    
    .EXAMPLE
        $result = Invoke-AdoRestMethod -Method GET -Uri $url -Headers $headers
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('GET', 'POST', 'PUT', 'PATCH', 'DELETE')]
        [string]$Method,
        
        [Parameter(Mandatory = $true)]
        [string]$Uri,
        
        [Parameter(Mandatory = $true)]
        [hashtable]$Headers,
        
        [Parameter(Mandatory = $false)]
        [object]$Body
    )
    
    $result = [PSCustomObject]@{
        Success = $false
        StatusCode = $null
        StatusDescription = $null
        Data = $null
        ErrorMessage = $null
        RawResponse = $null
    }
    
    try {
        $splat = @{
            Method = $Method
            Uri = $Uri
            Headers = $Headers
            ErrorAction = 'Stop'
        }
        
        if ($Body) {
            if ($Body -is [string]) {
                $splat['Body'] = $Body
            }
            else {
                $splat['Body'] = $Body | ConvertTo-Json -Depth 10
            }
        }
        
        # Execute REST call with PowerShell version compatibility
        # PowerShell 7+ supports -ResponseHeadersVariable and -StatusCodeVariable
        # PowerShell 5.1 does not, so we use different approaches
        if ($PSVersionTable.PSVersion.Major -ge 6) {
            # PowerShell 7+ - use modern parameters
            $response = Invoke-RestMethod @splat -ResponseHeadersVariable responseHeaders -StatusCodeVariable statusCode
            $result.StatusCode = $statusCode
        }
        else {
            # PowerShell 5.1 - response variables not supported
            # Success means 2xx status code (Invoke-RestMethod throws on errors)
            $response = Invoke-RestMethod @splat
            $result.StatusCode = 200  # Assume 200 OK on success for PS 5.1
        }
        
        $result.Success = $true
        $result.StatusDescription = "Success"
        $result.Data = $response
        $result.RawResponse = $response
    }
    catch {
        $result.Success = $false
        $result.ErrorMessage = $_.Exception.Message
        
        # Parse HTTP status code from exception
        if ($_.Exception.Response) {
            $result.StatusCode = [int]$_.Exception.Response.StatusCode
            $result.StatusDescription = $_.Exception.Response.StatusDescription
            
            # Provide actionable error messages
            switch ($result.StatusCode) {
                401 {
                    $result.ErrorMessage = "401 Unauthorized - Check PAT permissions and ensure scope includes 'vso.serviceendpoint' or 'vso.serviceendpoint_manage'"
                }
                403 {
                    $result.ErrorMessage = "403 Forbidden - PAT lacks required permissions. For write operations, ensure 'vso.serviceendpoint_manage' scope is granted"
                }
                404 {
                    $result.ErrorMessage = "404 Not Found - Verify Organization name, Project name, and Endpoint ID are correct. Endpoint may not exist or has been deleted"
                }
                409 {
                    $result.ErrorMessage = "409 Conflict - Resource conflict. Endpoint may be in use by pipelines or has dependencies"
                }
                500 {
                    $result.ErrorMessage = "500 Internal Server Error - Azure DevOps service issue. Check service health at status.dev.azure.com"
                }
                default {
                    $result.ErrorMessage = "$($result.StatusCode) $($result.StatusDescription) - $($_.Exception.Message)"
                }
            }
            
            # Try to parse error response body
            try {
                $errorStream = $_.Exception.Response.GetResponseStream()
                $reader = New-Object System.IO.StreamReader($errorStream)
                $responseBody = $reader.ReadToEnd()
                $result.RawResponse = $responseBody
                
                if ($responseBody) {
                    $errorDetails = $responseBody | ConvertFrom-Json -ErrorAction SilentlyContinue
                    if ($errorDetails.message) {
                        $result.ErrorMessage += " | Details: $($errorDetails.message)"
                    }
                }
            }
            catch {
                # Ignore errors parsing error response
            }
        }
        else {
            # Network or other non-HTTP errors
            $result.ErrorMessage = "Network or connection error: $($_.Exception.Message). Verify connectivity to dev.azure.com"
        }
    }
    
    return $result
}
