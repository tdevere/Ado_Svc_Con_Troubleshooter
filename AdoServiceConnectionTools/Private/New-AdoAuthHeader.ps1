function New-AdoAuthHeader {
    <#
    .SYNOPSIS
        Creates Azure DevOps REST API authentication header from PAT.
    
    .DESCRIPTION
        Converts a Personal Access Token (PAT) to Base64-encoded Basic Authentication header.
        CRITICAL: Username is an empty string - format is ":PAT", not "user:PAT"
    
    .PARAMETER PAT
        Personal Access Token for Azure DevOps authentication.
    
    .OUTPUTS
        Hashtable containing Authorization header ready for Invoke-RestMethod
    
    .EXAMPLE
        $headers = New-AdoAuthHeader -PAT "abc123def456"
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PAT
    )
    
    try {
        # Critical: Username is empty string, format is ":PAT"
        $base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$PAT"))
        
        return @{
            Authorization = "Basic $base64AuthInfo"
            'Content-Type' = 'application/json'
        }
    }
    catch {
        throw "Failed to create authentication header: $_"
    }
}
