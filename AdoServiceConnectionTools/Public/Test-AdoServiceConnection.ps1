function Test-AdoServiceConnection {
    <#
    .SYNOPSIS
        Performs a structured health-check on an Azure DevOps Service Connection.

    .DESCRIPTION
        Runs a series of diagnostic checks against the service connection and reports a
        PASS / WARN / FAIL result per check.  No destructive operations are performed.

        Checks performed:
          1. Endpoint Exists        - Can the endpoint be retrieved via GET?
          2. Ready State            - Is the 'isReady' field set to $true?
          3. Not Disabled           - Is the 'isDisabled' field set to $false?
          4. Authorization Present  - Does the authorization object contain credentials?
          5. Scheme Recognised      - Is the scheme a known type (not 'unknown')?
          6. Recent Activity        - Was the connection used in the last 90 days?
             (Skipped if -SkipHistory is set; warns if history API returns no data)

        The function returns a PSCustomObject with:
          - Healthy    : $true only when ALL checks PASS or WARN (no FAILs)
          - Checks     : Array of individual check results
          - Data       : Raw endpoint object from Azure DevOps
          - Message    : Summary string
          - LogFiles   : Paths to log files (if logging enabled)

    .PARAMETER Organization
        Azure DevOps organization name. Falls back to ORGANIZATION in .env.

    .PARAMETER Project
        Project name or ID. Falls back to PROJECT in .env.

    .PARAMETER EndpointId
        Service connection GUID. Falls back to ENDPOINT_ID / TEST_ENDPOINT_ID in .env.

    .PARAMETER PAT
        Personal Access Token with 'vso.serviceendpoint' (read) scope.
        Falls back to PAT in .env.

    .PARAMETER SkipHistory
        Skip the recent-activity check (useful for freshly-created connections, or
        when the connection type does not record pipeline execution history).

    .PARAMETER NoLog
        Disable logging (enabled by default).

    .OUTPUTS
        PSCustomObject with Success, Healthy, Checks, Data, Message, LogFiles properties.

    .EXAMPLE
        # Health-check using .env defaults
        Test-AdoServiceConnection

    .EXAMPLE
        # Explicit parameters, no logging
        Test-AdoServiceConnection -Organization "myorg" -Project "myproject" -EndpointId "guid" -PAT "token" -NoLog

    .EXAMPLE
        # Check and act on result
        $result = Test-AdoServiceConnection -EndpointId "guid"
        if (-not $result.Healthy) {
            Write-Host "Unhealthy - attempting credential refresh..."
            Update-AdoServiceConnectionAuth -EndpointId "guid" -NewCredentials @{ serviceprincipalkey = $newSecret }
        }
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
        [string]$PAT,

        [switch]$SkipHistory,

        [switch]$NoLog
    )

    # ── Resolve org / project / PAT / endpointId from .env where not supplied ──
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

    $headers = New-AdoAuthHeader -PAT $PAT

    $checks  = [System.Collections.Generic.List[PSCustomObject]]::new()
    $LogData = @{
        Organization = $Organization
        Project      = $Project
        EndpointId   = $EndpointId
        PAT          = $PAT
    }

    # ── Helper: add a check result ─────────────────────────────────────────────
    function _AddCheck {
        param([string]$Name, [string]$Status, [string]$Detail)
        $checks.Add([PSCustomObject]@{ Check = $Name; Status = $Status; Detail = $Detail })
    }

    # ── Helper: coloured status label ──────────────────────────────────────────
    function _WriteCheck {
        param([string]$Name, [string]$Status, [string]$Detail)
        $color = switch ($Status) {
            'PASS' { 'Green'  }
            'WARN' { 'Yellow' }
            'FAIL' { 'Red'    }
            default{ 'Gray'   }
        }
        $label = $Status.PadRight(4)
        Write-Host "  [$label] $Name" -ForegroundColor $color -NoNewline
        if ($Detail) { Write-Host " - $Detail" -ForegroundColor DarkGray }
        else         { Write-Host "" }
    }

    Write-Host ""
    Write-Host "  Azure DevOps Service Connection Health Check" -ForegroundColor Cyan
    Write-Host "  Organization : $Organization" -ForegroundColor DarkGray
    Write-Host "  Project      : $Project"      -ForegroundColor DarkGray
    Write-Host "  Endpoint ID  : $EndpointId"   -ForegroundColor DarkGray
    Write-Host ""

    # ── Check 1: Endpoint exists ───────────────────────────────────────────────
    $getUrl    = "https://dev.azure.com/$Organization/$Project/_apis/serviceendpoint/endpoints/${EndpointId}?api-version=7.1"
    $getResult = Invoke-AdoRestMethod -Method GET -Uri $getUrl -Headers $headers

    if (-not $getResult.Success) {
        $hint = switch ($getResult.StatusCode) {
            401     { "PAT is invalid or expired (HTTP 401)." }
            403     { "PAT lacks read permission on this connection (HTTP 403)." }
            404     { "Endpoint not found in '$Organization/$Project' (HTTP 404). Verify the GUID and project." }
            default { "HTTP $($getResult.StatusCode): $($getResult.ErrorMessage)" }
        }
        _AddCheck  -Name "Endpoint Exists" -Status "FAIL" -Detail $hint
        _WriteCheck -Name "Endpoint Exists" -Status "FAIL" -Detail $hint

        $LogData['Result'] = 'FAIL'
        $LogData['Checks'] = $checks | ForEach-Object { "$($_.Check): $($_.Status) - $($_.Detail)" }
        $logFiles = Write-AdoLog -Operation "TestConnection" -LogData $LogData -NoLog:$NoLog

        return [PSCustomObject]@{
            Success  = $false
            Healthy  = $false
            Checks   = $checks
            Data     = $null
            Message  = "Cannot reach endpoint: $hint"
            LogFiles = $logFiles
        }
    }

    $ep = $getResult.Data
    _AddCheck  -Name "Endpoint Exists" -Status "PASS" -Detail "$($ep.name) ($($ep.type))"
    _WriteCheck -Name "Endpoint Exists" -Status "PASS" -Detail "$($ep.name) ($($ep.type))"

    # ── Check 2: isReady ───────────────────────────────────────────────────────
    if ($ep.isReady -eq $true) {
        _AddCheck  -Name "Ready State"  -Status "PASS" -Detail "isReady = true"
        _WriteCheck -Name "Ready State" -Status "PASS" -Detail "isReady = true"
    } else {
        _AddCheck  -Name "Ready State"  -Status "FAIL" -Detail "isReady = false. The connection failed its last verification. Try Update-AdoServiceConnectionAuth or re-create the connection."
        _WriteCheck -Name "Ready State" -Status "FAIL" -Detail "isReady = false (verification failed)"
    }

    # ── Check 3: Not disabled ─────────────────────────────────────────────────
    if ($ep.isDisabled -eq $true) {
        _AddCheck  -Name "Not Disabled" -Status "FAIL" -Detail "isDisabled = true. Re-enable the connection in Project Settings > Service Connections."
        _WriteCheck -Name "Not Disabled" -Status "FAIL" -Detail "isDisabled = true"
    } else {
        _AddCheck  -Name "Not Disabled" -Status "PASS" -Detail "isDisabled = false"
        _WriteCheck -Name "Not Disabled" -Status "PASS" -Detail "isDisabled = false"
    }

    # ── Check 4: Authorization present ────────────────────────────────────────
    $authObj    = $ep.authorization
    $authParams = $authObj.parameters

    if ($null -eq $authObj -or $null -eq $authParams) {
        _AddCheck  -Name "Authorization Present" -Status "FAIL" -Detail "No authorization object found. The connection may be corrupted."
        _WriteCheck -Name "Authorization Present" -Status "FAIL" -Detail "authorization object missing"
    } else {
        $paramCount = ($authParams | Get-Member -MemberType NoteProperty).Count
        if ($paramCount -eq 0) {
            _AddCheck  -Name "Authorization Present" -Status "WARN" -Detail "Authorization scheme is '$($authObj.scheme)' but parameters are empty."
            _WriteCheck -Name "Authorization Present" -Status "WARN" -Detail "scheme='$($authObj.scheme)', parameters empty"
        } else {
            _AddCheck  -Name "Authorization Present" -Status "PASS" -Detail "scheme='$($authObj.scheme)', $paramCount parameter(s) stored"
            _WriteCheck -Name "Authorization Present" -Status "PASS" -Detail "scheme='$($authObj.scheme)', $paramCount parameter(s)"
        }
    }

    # ── Check 5: Scheme recognised ────────────────────────────────────────────
    $knownSchemes = @('ServicePrincipal','ManagedServiceIdentity','WorkloadIdentityFederation',
                      'UsernamePassword','Token','OAuth','InstallationToken','Certificate','None','JWT')
    $scheme = $authObj.scheme
    if ($null -eq $scheme -or $scheme -eq 'unknown' -or $scheme -notin $knownSchemes) {
        _AddCheck  -Name "Scheme Recognised" -Status "WARN" -Detail "Scheme '$scheme' is not in the standard list. The connection may still work."
        _WriteCheck -Name "Scheme Recognised" -Status "WARN" -Detail "scheme='$scheme' (non-standard)"
    } else {
        _AddCheck  -Name "Scheme Recognised" -Status "PASS" -Detail "scheme='$scheme'"
        _WriteCheck -Name "Scheme Recognised" -Status "PASS" -Detail "scheme='$scheme'"
    }

    # ── Check 6: Recent activity ──────────────────────────────────────────────
    if ($SkipHistory) {
        _AddCheck  -Name "Recent Activity" -Status "SKIP" -Detail "-SkipHistory supplied"
        _WriteCheck -Name "Recent Activity" -Status "SKIP" -Detail "-SkipHistory supplied"
    } else {
        $histUrl    = "https://dev.azure.com/$Organization/$Project/_apis/serviceendpoint/executionhistory?endpointId=$EndpointId&api-version=7.1"
        $histResult = Invoke-AdoRestMethod -Method GET -Uri $histUrl -Headers $headers

        if ($histResult.Success -and $histResult.Data.count -gt 0) {
            $entries     = $histResult.Data.value
            $latestEntry = $entries | Sort-Object { $_.data.startTime } -Descending | Select-Object -First 1
            $lastUsed    = $latestEntry.data.startTime
            $daysSince   = [int]((Get-Date) - [datetime]$lastUsed).TotalDays

            if ($daysSince -le 90) {
                _AddCheck  -Name "Recent Activity" -Status "PASS" -Detail "Last used $daysSince day(s) ago ($lastUsed)"
                _WriteCheck -Name "Recent Activity" -Status "PASS" -Detail "Last used $daysSince day(s) ago"
            } else {
                _AddCheck  -Name "Recent Activity" -Status "WARN" -Detail "Last used $daysSince day(s) ago. Consider removing if no longer needed."
                _WriteCheck -Name "Recent Activity" -Status "WARN" -Detail "Last used $daysSince day(s) ago (>90 days)"
            }
        } elseif ($histResult.Success) {
            _AddCheck  -Name "Recent Activity" -Status "WARN" -Detail "No execution history found. Newly created, or not yet used in a pipeline."
            _WriteCheck -Name "Recent Activity" -Status "WARN" -Detail "No history found"
        } else {
            _AddCheck  -Name "Recent Activity" -Status "WARN" -Detail "Could not retrieve history (HTTP $($histResult.StatusCode)). Check PAT has 'vso.serviceendpoint' scope."
            _WriteCheck -Name "Recent Activity" -Status "WARN" -Detail "History API error (HTTP $($histResult.StatusCode))"
        }
    }

    # ── Summary ────────────────────────────────────────────────────────────────
    $failCount = ($checks | Where-Object { $_.Status -eq 'FAIL' }).Count
    $warnCount = ($checks | Where-Object { $_.Status -eq 'WARN' }).Count
    $passCount = ($checks | Where-Object { $_.Status -eq 'PASS' }).Count
    $healthy   = ($failCount -eq 0)

    Write-Host ""
    if ($healthy) {
        Write-Host "  Result: HEALTHY  ($passCount PASS  $warnCount WARN  $failCount FAIL)" -ForegroundColor Green
    } else {
        Write-Host "  Result: UNHEALTHY  ($passCount PASS  $warnCount WARN  $failCount FAIL)" -ForegroundColor Red
        Write-Host ""
        Write-Host "  Suggested next steps:" -ForegroundColor Yellow
        if (($checks | Where-Object { $_.Check -eq 'Ready State' -and $_.Status -eq 'FAIL' }).Count -gt 0) {
            Write-Host "    - Run Update-AdoServiceConnectionAuth to refresh credentials." -ForegroundColor Yellow
        }
        if (($checks | Where-Object { $_.Check -eq 'Not Disabled' -and $_.Status -eq 'FAIL' }).Count -gt 0) {
            Write-Host "    - Re-enable the connection in Azure DevOps Project Settings > Service Connections." -ForegroundColor Yellow
        }
        if (($checks | Where-Object { $_.Check -eq 'Authorization Present' -and $_.Status -eq 'FAIL' }).Count -gt 0) {
            Write-Host "    - The connection may be corrupted. Consider running Remove-AdoServiceConnection and re-creating it." -ForegroundColor Yellow
        }
    }
    Write-Host ""

    $summary  = if ($healthy) { "Healthy - '$($ep.name)' passed $passCount/$($checks.Count) checks ($warnCount warn)" } `
                else           { "Unhealthy - '$($ep.name)' has $failCount failing check(s)" }

    $LogData['Result']   = if ($healthy) { 'HEALTHY' } else { 'UNHEALTHY' }
    $LogData['Summary']  = $summary
    $LogData['Checks']   = $checks | ForEach-Object { "$($_.Check): $($_.Status) - $($_.Detail)" }
    $logFiles = Write-AdoLog -Operation "TestConnection" -LogData $LogData -NoLog:$NoLog

    return [PSCustomObject]@{
        Success  = $true
        Healthy  = $healthy
        Checks   = $checks
        Data     = $ep
        Message  = $summary
        LogFiles = $logFiles
    }
}
