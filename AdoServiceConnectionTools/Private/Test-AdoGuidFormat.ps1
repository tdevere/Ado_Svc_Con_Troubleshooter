function Test-AdoGuidFormat {
    <#
    .SYNOPSIS
        Validates that a string is a properly formatted GUID.
    
    .DESCRIPTION
        Checks if the provided EndpointId is a valid GUID format.
        Azure DevOps Endpoint IDs must be valid GUIDs.
    
    .PARAMETER EndpointId
        The endpoint ID to validate
    
    .OUTPUTS
        Boolean indicating if the format is valid
    
    .EXAMPLE
        if (Test-AdoGuidFormat -EndpointId $id) { ... }
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$EndpointId
    )
    
    try {
        $guid = [System.Guid]::Parse($EndpointId)
        return $true
    }
    catch {
        return $false
    }
}
