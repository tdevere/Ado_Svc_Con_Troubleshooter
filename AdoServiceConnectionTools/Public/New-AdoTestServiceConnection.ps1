function New-AdoTestServiceConnection {
    <#
    .SYNOPSIS
        Creates a throwaway Generic service connection for deletion testing.

    .DESCRIPTION
        Provisions a "Generic / UsernamePassword" service connection named
        "Test-SC-<timestamp>" in the target project. The endpoint uses a
        dummy URL and dummy credentials – it is not intended for real use.

        After a successful create the function offers (or automatically writes)
        the new endpoint GUID back to the .env file as TEST_ENDPOINT_ID, so that
        Remove-AdoServiceConnection (and other commands) can target it with no
        extra parameters.

        Typical workflow
        ----------------
          # 1. Create a throwaway connection and save its ID to .env
          New-AdoTestServiceConnection

          # 2. Run whatever diagnostics / deletion test you need
          Remove-AdoServiceConnection            # reads TEST_ENDPOINT_ID from .env automatically

          # 3. Done – connection is gone; .env TEST_ENDPOINT_ID can be cleared manually

    .PARAMETER Organization
        Azure DevOps organization name. Falls back to ORGANIZATION in .env.

    .PARAMETER Project
        Project name. Falls back to PROJECT in .env.

    .PARAMETER PAT
        PAT with 'vso.serviceendpoint_manage' scope. Falls back to PAT in .env.

    .PARAMETER Name
        Friendly name for the test connection. Defaults to "Test-SC-<yyyyMMdd-HHmmss>".

    .PARAMETER AutoSave
        Automatically write TEST_ENDPOINT_ID to .env without prompting.
        Useful for scripted / CI scenarios.

    .PARAMETER NoLog
        Disable logging (enabled by default).

    .OUTPUTS
        PSCustomObject with Success, EndpointId, Data, Message, LogFiles properties.

    .EXAMPLE
        # Interactive – will prompt whether to save to .env
        New-AdoTestServiceConnection

    .EXAMPLE
        # Fully automated – creates and saves to .env silently
        New-AdoTestServiceConnection -AutoSave -NoLog
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Organization,

        [Parameter(Mandatory = $false)]
        [string]$Project,

        [Parameter(Mandatory = $false)]
        [string]$PAT,

        [Parameter(Mandatory = $false)]
        [string]$Name,

        [switch]$AutoSave,

        [switch]$NoLog
    )

    # ── Resolve defaults ───────────────────────────────────────────────────────
    $resolvedDefaults = Resolve-AdoDefaultContext `
        -Organization $Organization -Project $Project -PAT $PAT `
        -Required @('Organization', 'Project', 'PAT')

    $Organization = $resolvedDefaults.Organization
    $Project      = $resolvedDefaults.Project
    $PAT          = $resolvedDefaults.PAT

    # ── Build a timestamp-based name if not supplied ───────────────────────────
    if (-not $Name) {
        $Name = "Test-SC-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    }

    $headers = New-AdoAuthHeader -PAT $PAT

    # ── Step 1: Resolve the project GUID (required by the create API body) ────
    Write-Host ""
    Write-Host "  Resolving project GUID for '$Project'..." -ForegroundColor DarkGray

    $projectUrl  = "https://dev.azure.com/$Organization/_apis/projects/$Project`?api-version=7.1"
    $projectResp = Invoke-AdoRestMethod -Method GET -Uri $projectUrl -Headers $headers

    if (-not $projectResp.Success) {
        $hint = switch ($projectResp.StatusCode) {
            401 { "PAT is invalid or lacks read access. Verify PAT scopes." }
            404 { "Project '$Project' not found in org '$Organization'." }
            default { $projectResp.ErrorMessage }
        }
        return [PSCustomObject]@{
            Success    = $false
            EndpointId = $null
            Data       = $null
            Message    = "Could not resolve project GUID: $hint"
            LogFiles   = $null
        }
    }

    $projectId = $projectResp.Data.id
    Write-Host "  Project GUID : $projectId" -ForegroundColor DarkGray

    # ── Step 2: Build Generic endpoint definition ──────────────────────────────
    $definition = @{
        name        = $Name
        description = "Automated test endpoint – created by New-AdoTestServiceConnection. Safe to delete."
        type        = "generic"
        url         = "https://example-test-only.invalid"
        isShared    = $false
        isReady     = $true
        authorization = @{
            scheme     = "UsernamePassword"
            parameters = @{
                username = "testuser"
                password = "testpassword"
            }
        }
        serviceEndpointProjectReferences = @(
            @{
                projectReference = @{
                    id   = $projectId
                    name = $Project
                }
                name        = $Name
                description = "Automated test endpoint – created by New-AdoTestServiceConnection. Safe to delete."
            }
        )
    }

    # ── Step 3: Create the endpoint ────────────────────────────────────────────
    Write-Host "  Creating test service connection '$Name'..." -ForegroundColor DarkGray

    $createResult = New-AdoServiceConnection `
        -Organization $Organization `
        -EndpointDefinition $definition `
        -PAT $PAT `
        -NoLog:$NoLog

    if (-not $createResult.Success) {
        return [PSCustomObject]@{
            Success    = $false
            EndpointId = $null
            Data       = $null
            Message    = $createResult.Message
            LogFiles   = $createResult.LogFiles
        }
    }

    $endpointId = $createResult.Data.id

    # ── Step 4: Offer / auto-save TEST_ENDPOINT_ID to .env ────────────────────
    $savedPath = $null

    if ($AutoSave) {
        $savedPath = Set-AdoEnvValue -Key "TEST_ENDPOINT_ID" -Value $endpointId
        Write-Host "  TEST_ENDPOINT_ID saved to .env ($savedPath)" -ForegroundColor Green
    } else {
        Write-Host ""
        Write-Host "  Would you like to save this endpoint ID to .env as TEST_ENDPOINT_ID?" -ForegroundColor Yellow
        Write-Host "  This lets Remove-AdoServiceConnection target it without any parameters." -ForegroundColor DarkGray
        Write-Host ""
        $answer = Read-Host "  Save to .env? [Y/n]"
        if ([string]::IsNullOrWhiteSpace($answer) -or $answer -match '^[Yy]') {
            $savedPath = Set-AdoEnvValue -Key "TEST_ENDPOINT_ID" -Value $endpointId
            Write-Host ""
            Write-Host "  Saved. You can now run:" -ForegroundColor Green
            Write-Host "    Remove-AdoServiceConnection" -ForegroundColor Cyan
            Write-Host "  to delete this connection using the .env default." -ForegroundColor DarkGray
        }
    }

    Write-Host ""
    Write-Host "  ✓ Test connection ready." -ForegroundColor Green
    Write-Host ""
    Write-Host "  Name       : $($createResult.Data.name)" -ForegroundColor Cyan
    Write-Host "  ID         : $endpointId"                -ForegroundColor Cyan
    Write-Host "  Type       : $($createResult.Data.type)" -ForegroundColor Cyan
    Write-Host "  .env saved : $(if ($savedPath) { $savedPath } else { 'No' })" -ForegroundColor Cyan
    Write-Host ""

    return [PSCustomObject]@{
        Success    = $true
        EndpointId = $endpointId
        Data       = $createResult.Data
        Message    = $createResult.Message
        LogFiles   = $createResult.LogFiles
    }
}
