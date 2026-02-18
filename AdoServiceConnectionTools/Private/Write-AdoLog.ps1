function Write-AdoLog {
    <#
    .SYNOPSIS
        Writes dual-format logs (human-readable and JSON) for ADO operations.
    
    .DESCRIPTION
        Creates both .log and .json files in the logs/ directory with comprehensive operation details.
        Automatically redacts PAT tokens from all logged content.
    
    .PARAMETER Operation
        The operation being performed (e.g., "Remove", "Get", "Create")
    
    .PARAMETER LogData
        Hashtable containing all data to log (parameters, request, response, etc.)
    
    .PARAMETER NoLog
        Switch to skip logging entirely
    
    .OUTPUTS
        Array of file paths where logs were saved
    
    .EXAMPLE
        Write-AdoLog -Operation "Remove" -LogData @{ Organization="myorg"; EndpointId="guid"; Status="Success" }
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Operation,
        
        [Parameter(Mandatory = $true)]
        [hashtable]$LogData,
        
        [switch]$NoLog
    )
    
    if ($NoLog) {
        return @()
    }
    
    try {
        # Determine log directory (module root or script directory)
        $LogDir = if ($PSScriptRoot) {
            Join-Path (Split-Path $PSScriptRoot -Parent) "logs"
        } else {
            Join-Path $PWD "logs"
        }
        
        # Create logs directory if it doesn't exist
        if (-not (Test-Path $LogDir)) {
            New-Item -Path $LogDir -ItemType Directory -Force | Out-Null
        }
        
        # Generate timestamp and filenames
        $Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
        $BaseFilename = "ado-sc-$($Operation.ToLower())-$Timestamp"
        $LogFile = Join-Path $LogDir "$BaseFilename.log"
        $JsonFile = Join-Path $LogDir "$BaseFilename.json"
        
        # Add timestamp to log data
        $LogData['Timestamp'] = Get-Date -Format "o"
        $LogData['Operation'] = $Operation
        
        # Redact PAT in all string values
        $RedactedData = @{}
        foreach ($key in $LogData.Keys) {
            $value = $LogData[$key]
            if ($value -is [string] -and $key -eq 'PAT' -and $value.Length -gt 8) {
                $RedactedData[$key] = $value.Substring(0, 4) + "****" + $value.Substring($value.Length - 4)
            }
            elseif ($value -is [string] -and $value -match 'Basic [A-Za-z0-9+/=]+') {
                # Redact Base64 auth headers
                $RedactedData[$key] = $value -replace 'Basic [A-Za-z0-9+/=]+', 'Basic ****'
            }
            else {
                $RedactedData[$key] = $value
            }
        }
        
        # Write human-readable log
        $LogContent = @"
========================================
Azure DevOps Service Connection Log
========================================
Timestamp: $($RedactedData['Timestamp'])
Operation: $($RedactedData['Operation'])

Parameters:
$(($RedactedData.GetEnumerator() | Where-Object { $_.Key -notin @('Timestamp', 'Operation', 'ResponseBody', 'RequestBody') } | ForEach-Object { "  $($_.Key): $($_.Value)" }) -join "`n")

Request Details:
  Method: $($RedactedData['HttpMethod'])
  URL: $($RedactedData['RequestUrl'])
  
Response Details:
  Status Code: $($RedactedData['StatusCode'])
  Status Description: $($RedactedData['StatusDescription'])
  
$(if ($RedactedData['ResponseBody']) { "Response Body:`n$($RedactedData['ResponseBody'])" })

$(if ($RedactedData['ErrorMessage']) { "ERROR: $($RedactedData['ErrorMessage'])" })

Result: $($RedactedData['Result'])
========================================
"@
        
        Set-Content -Path $LogFile -Value $LogContent -Encoding UTF8
        
        # Write JSON log
        $RedactedData | ConvertTo-Json -Depth 10 | Set-Content -Path $JsonFile -Encoding UTF8
        
        return @($LogFile, $JsonFile)
    }
    catch {
        Write-Warning "Failed to write log files: $_"
        return @()
    }
}
