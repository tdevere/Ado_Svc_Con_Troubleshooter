#Requires -Version 5.1
$ErrorActionPreference = 'Continue'
$Host.UI.RawUI.WindowTitle = "Azure DevOps Service Connection Validator"

# ── HELPERS ──────────────────────────────────────────────────────────────────

function Write-Banner {
    Clear-Host
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host "  Azure DevOps Service Connection Wizard  "  -ForegroundColor Cyan
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host ""
}

function Write-Step ($Number, $Total, $Text) {
    Write-Host ""
    Write-Host "  [$Number/$Total] $Text" -ForegroundColor Cyan
    Write-Host ("  " + ("-" * ($Text.Length + 6))) -ForegroundColor DarkGray
    Write-Host ""
}

function Read-RequiredText ($Prompt, $Default) {
    $suffix = if ($Default) { " [default: $Default]" } else { " (required)" }
    while ($true) {
        $val = Read-Host "  $Prompt$suffix"
        if ([string]::IsNullOrWhiteSpace($val) -and $Default) { return $Default }
        if (-not [string]::IsNullOrWhiteSpace($val)) { return $val.Trim() }
        Write-Host "  This value is required. Please try again." -ForegroundColor Yellow
    }
}

function Select-FromList ($Title, $Items, $DisplayScript) {
    Write-Host "  $Title" -ForegroundColor White
    Write-Host ""
    $i = 1
    foreach ($item in $Items) {
        $label = & $DisplayScript $item
        Write-Host "    [$i] $label" -ForegroundColor White
        $i++
    }
    Write-Host ""
    while ($true) {
        $raw = Read-Host "  Enter a number (1 - $($Items.Count))"
        $n = 0
        if ([int]::TryParse($raw.Trim(), [ref]$n) -and $n -ge 1 -and $n -le $Items.Count) {
            return $Items[$n - 1]
        }
        Write-Host "  Please enter a number between 1 and $($Items.Count)." -ForegroundColor Yellow
    }
}

function Invoke-AzDoGet ($Url, $PAT) {
    $b64 = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$PAT"))
    $headers = @{ Authorization = "Basic $b64" }
    try {
        $r = Invoke-RestMethod -Uri $Url -Headers $headers -Method GET -ErrorAction Stop
        return @{ Success = $true; Data = $r }
    } catch {
        $code = $_.Exception.Response.StatusCode.value__
        return @{ Success = $false; StatusCode = $code; Error = $_.Exception.Message }
    }
}

function Load-DotEnv {
    $path = Join-Path $PSScriptRoot ".env"
    $d = @{}
    if (Test-Path $path) {
        Get-Content $path | ForEach-Object {
            $line = $_.Trim()
            if (-not $line -or $line.StartsWith('#')) { return }
            $idx = $line.IndexOf('=')
            if ($idx -lt 1) { return }
            $k = $line.Substring(0, $idx).Trim()
            $v = $line.Substring($idx + 1).Trim().Trim('"').Trim("'")
            if ($k) { $d[$k] = $v }
        }
    }
    return $d
}

function Save-DotEnv ($Org, $Project, $PAT, $EndpointId) {
    $path = Join-Path $PSScriptRoot ".env"
    Set-Content -Path $path -Encoding UTF8 -Value @"
ORGANIZATION=$Org
PROJECT=$Project
PAT=$PAT
TEST_ENDPOINT_ID=$EndpointId
"@
    Write-Host ""
    Write-Host "  Saved to: $path" -ForegroundColor Green
    Write-Host "  Next time you run this wizard, your values will be pre-filled." -ForegroundColor Gray
}

# ── INTRO ─────────────────────────────────────────────────────────────────────
Write-Banner
Write-Host "  This wizard will:" -ForegroundColor White
Write-Host "    1. Connect to your Azure DevOps account" -ForegroundColor Gray
Write-Host "    2. Let you pick your project and service connection" -ForegroundColor Gray
Write-Host "    3. Attempt to force-delete the stuck connection" -ForegroundColor Gray
Write-Host "    4. Collect evidence in case deletion fails" -ForegroundColor Gray
Write-Host "    5. Tell you exactly what files to send back" -ForegroundColor Gray
Write-Host ""
Write-Host "  You do not need any PowerShell experience." -ForegroundColor Yellow
Write-Host "  Just follow the prompts and press Enter when asked." -ForegroundColor Yellow
Write-Host ""
Read-Host "  Press Enter to begin"

# ── LOAD .ENV ─────────────────────────────────────────────────────────────────
$defaults = Load-DotEnv
Write-Host ""
if ($defaults.Count -gt 0) {
    Write-Host "  Found saved settings from a previous run." -ForegroundColor Green
} else {
    Write-Host "  No saved settings found. You will be prompted for each value." -ForegroundColor Yellow
}

# ── START TRANSCRIPT ──────────────────────────────────────────────────────────
$transcriptPath = Join-Path $PSScriptRoot "customer-validation-transcript.txt"
try { Start-Transcript -Path $transcriptPath -Force | Out-Null } catch {}

# ── STEP 1: ORGANIZATION ─────────────────────────────────────────────────────
Write-Banner
Write-Step 1 8 "Connect to Azure DevOps"
Write-Host "  Your organization name is the part after dev.azure.com/ in your browser." -ForegroundColor Gray
Write-Host "  Example: https://dev.azure.com/contoso-org  -->  type: contoso-org" -ForegroundColor Gray
Write-Host ""
$org = Read-RequiredText "Organization name" $defaults['ORGANIZATION']

# ── STEP 2: PAT WITH EARLY VALIDATION ────────────────────────────────────────
Write-Banner
Write-Step 2 8 "Enter and validate your Personal Access Token (PAT)"
Write-Host "  Your PAT gives this tool permission to read and delete service connections." -ForegroundColor Gray
Write-Host ""
Write-Host "  If you do not have one, create it at:" -ForegroundColor Gray
Write-Host "  https://dev.azure.com/_usersSettings/tokens" -ForegroundColor Cyan
Write-Host "  Required scope: Service Connections > Read and manage" -ForegroundColor Gray
Write-Host ""

$patValid = $false
$attemptsLeft = 3

while (-not $patValid -and $attemptsLeft -gt 0) {
    $pat = Read-RequiredText "Paste your PAT" $defaults['PAT']
    Write-Host ""
    Write-Host "  Validating PAT against organization '$org'..." -ForegroundColor Gray

    $checkUrl = "https://dev.azure.com/$org/_apis/projects?`$top=1&api-version=7.1"
    $check = Invoke-AzDoGet $checkUrl $pat

    if ($check.Success) {
        Write-Host "  PAT is valid." -ForegroundColor Green
        $patValid = $true
    } elseif ($check.StatusCode -eq 401) {
        $attemptsLeft--
        Write-Host "  PAT was rejected (401 Unauthorized)." -ForegroundColor Red
        Write-Host "  Please check:" -ForegroundColor Yellow
        Write-Host "    - You copied the full token with no extra spaces" -ForegroundColor White
        Write-Host "    - The token has not expired" -ForegroundColor White
        Write-Host "    - The token scope includes 'Service Connections: Read and manage'" -ForegroundColor White
        Write-Host "    - The organization name is correct" -ForegroundColor White
        if ($attemptsLeft -gt 0) {
            Write-Host "  Attempts remaining: $attemptsLeft" -ForegroundColor Yellow
            $defaults['PAT'] = ''
        }
    } elseif ($check.StatusCode -eq 404) {
        $attemptsLeft--
        Write-Host "  Organization '$org' was not found (404). Please re-enter." -ForegroundColor Red
        $org = Read-RequiredText "Organization name" $defaults['ORGANIZATION']
        $defaults['PAT'] = ''
    } else {
        Write-Host "  Unexpected error: $($check.Error)" -ForegroundColor Red
        $attemptsLeft--
    }
}

if (-not $patValid) {
    Write-Host ""
    Write-Host "  Could not validate PAT after 3 attempts. Please contact your support representative." -ForegroundColor Red
    try { Stop-Transcript | Out-Null } catch {}
    Read-Host "  Press Enter to close"
    exit 1
}

# ── STEP 3: SELECT PROJECT ────────────────────────────────────────────────────
Write-Banner
Write-Step 3 8 "Select your project"

$projectsUrl = "https://dev.azure.com/$org/_apis/projects?api-version=7.1&`$top=100&`$orderby=name"
$projectsResult = Invoke-AzDoGet $projectsUrl $pat

if (-not $projectsResult.Success -or -not $projectsResult.Data.value) {
    Write-Host "  Could not retrieve project list. Please enter your project name manually." -ForegroundColor Yellow
    $project = Read-RequiredText "Project name" $defaults['PROJECT']
} else {
    $projects = $projectsResult.Data.value | Sort-Object name
    $defaultProject = $defaults['PROJECT']
    $autoMatch = $projects | Where-Object { $_.name -eq $defaultProject }

    if ($autoMatch) {
        Write-Host "  Using saved project: $($autoMatch.name)" -ForegroundColor Green
        $selectedProject = $autoMatch
    } else {
        $selectedProject = Select-FromList "Choose your project:" $projects { param($p) $p.name }
    }
    $project = $selectedProject.name
    Write-Host ""
    Write-Host "  Selected: $project" -ForegroundColor Green
}

# ── STEP 4: SELECT SERVICE CONNECTION ────────────────────────────────────────
Write-Banner
Write-Step 4 8 "Select the service connection to delete"
Write-Host "  Retrieving all service connections (including failed/corrupted ones)..." -ForegroundColor Gray
Write-Host ""

$modulePath = Join-Path $PSScriptRoot "AdoServiceConnectionTools"
if (Test-Path $modulePath) {
    Import-Module $modulePath -Force -WarningAction SilentlyContinue
    $scResult = Get-AdoServiceConnection -Organization $org -Project $project -PAT $pat -IncludeFailed
    $allConnections = if ($scResult.Success) { @($scResult.Data) } else { @() }
} else {
    $scUrl = "https://dev.azure.com/$org/$project/_apis/serviceendpoint/endpoints?includeFailed=true&api-version=7.1"
    $scApiResult = Invoke-AzDoGet $scUrl $pat
    $allConnections = if ($scApiResult.Success -and $scApiResult.Data.value) { @($scApiResult.Data.value) } else { @() }
}

if ($allConnections.Count -eq 0) {
    Write-Host "  No service connections found in project '$project'." -ForegroundColor Yellow
    Write-Host "  Please verify the project name and PAT scope, then run the wizard again." -ForegroundColor White
    try { Stop-Transcript | Out-Null } catch {}
    Read-Host "  Press Enter to close"
    exit 1
}

$selectedSC = Select-FromList "Choose the service connection to delete:" $allConnections {
    param($sc)
    $status = if ($sc.isReady) { "OK     " } else { "FAILED " }
    "[$status]  $($sc.name)  |  $($sc.type)  |  $($sc.id)"
}

$endpointId = $selectedSC.id

Write-Host ""
Write-Host "  You selected:" -ForegroundColor White
Write-Host "    Name   : $($selectedSC.name)"   -ForegroundColor White
Write-Host "    Type   : $($selectedSC.type)"   -ForegroundColor White
Write-Host "    ID     : $endpointId"           -ForegroundColor White
$statusColor = if ($selectedSC.isReady) { 'Green' } else { 'Yellow' }
$statusText  = if ($selectedSC.isReady) { 'Ready' } else { 'FAILED / CORRUPTED' }
Write-Host "    Status : $statusText" -ForegroundColor $statusColor
Write-Host ""
$confirm = Read-Host "  Is this the correct service connection to DELETE? (yes / no)"
if ($confirm.Trim().ToLower() -notin @('yes','y')) {
    Write-Host "  Cancelled. Run the wizard again to choose a different connection." -ForegroundColor Yellow
    try { Stop-Transcript | Out-Null } catch {}
    Read-Host "  Press Enter to close"
    exit 0
}

# ── STEP 5: VERIFY REACHABILITY ───────────────────────────────────────────────
Write-Banner
Write-Step 5 8 "Checking if endpoint is visible via API (-IncludeFailed)"

if (-not (Get-Module AdoServiceConnectionTools)) {
    if (Test-Path $modulePath) {
        Import-Module $modulePath -Force -WarningAction SilentlyContinue
    }
}

$verifyResult = Get-AdoServiceConnection -Organization $org -Project $project -PAT $pat -IncludeFailed
$matchCheck = @($verifyResult.Data | Where-Object { $_.id -eq $endpointId })

Write-Host "  Total connections returned (including failed): $(@($verifyResult.Data).Count)" -ForegroundColor White
Write-Host "  Matches for selected endpoint ID            : $($matchCheck.Count)" -ForegroundColor White

if ($matchCheck.Count -eq 0) {
    Write-Host ""
    Write-Host "  NOTE: Endpoint is not returned by the API even with -IncludeFailed." -ForegroundColor Yellow
    Write-Host "  This is important diagnostic evidence. Deletion will still be attempted." -ForegroundColor Gray
}
Write-Host ""
Read-Host "  Press Enter to continue to deletion"

# ── STEP 6: FORCE DELETE ─────────────────────────────────────────────────────
Write-Banner
Write-Step 6 8 "Force deleting service connection"
Write-Host "  Targeting : $($selectedSC.name)" -ForegroundColor White
Write-Host "  Endpoint ID: $endpointId" -ForegroundColor White
Write-Host ""

Remove-AdoServiceConnection -Organization $org -Project $project `
    -PAT $pat -EndpointId $endpointId -Deep

# ── STEP 7: PORTAL VERIFICATION ──────────────────────────────────────────────
Write-Banner
Write-Step 7 8 "Verify in Azure DevOps portal"

$portalUrl = "https://dev.azure.com/$org/$project/_settings/adminservices"
Write-Host "  Please check in your browser whether the service connection is still visible." -ForegroundColor White
Write-Host ""
Write-Host "  $portalUrl" -ForegroundColor Cyan
Write-Host ""
Write-Host "  If still visible, wait 60-120 seconds and refresh before answering." -ForegroundColor Yellow
Write-Host ""
try { Start-Process $portalUrl } catch {}

$stillVisible = Read-Host "  Is the service connection still visible in the portal? (yes / no)"

# ── STOP TRANSCRIPT ────────────────────────────────────────────────────────────
try { Stop-Transcript | Out-Null } catch {}

# ── STEP 8: OFFER TO SAVE .ENV ────────────────────────────────────────────────
Write-Banner
Write-Step 8 8 "Save settings for next time"

Write-Host "  Would you like to save your values so the wizard pre-fills them next time?" -ForegroundColor White
Write-Host "  (Your PAT will be stored locally in a .env file - do not share that file)" -ForegroundColor Yellow
Write-Host ""
$saveEnv = Read-Host "  Save settings? (yes / no)"
if ($saveEnv.Trim().ToLower() -in @('yes','y')) {
    Save-DotEnv $org $project $pat $endpointId
}

# ── FINAL SUMMARY ─────────────────────────────────────────────────────────────
Write-Banner
Write-Host "  All steps complete." -ForegroundColor Green
Write-Host ""
Write-Host "  Please send the following to your support contact:" -ForegroundColor Cyan
Write-Host ""
Write-Host "  1. Transcript file:" -ForegroundColor White
Write-Host "     $transcriptPath" -ForegroundColor Gray

$logsDir = Join-Path $PSScriptRoot "AdoServiceConnectionTools\logs"
if (Test-Path $logsDir) {
    $logFiles = Get-ChildItem $logsDir -File | Sort-Object LastWriteTime -Descending | Select-Object -First 6
    if ($logFiles.Count -gt 0) {
        Write-Host ""
        Write-Host "  2. Log files:" -ForegroundColor White
        $logFiles | ForEach-Object { Write-Host "     $($_.FullName)" -ForegroundColor Gray }
    }
}

Write-Host ""
Write-Host "  3. These answers:" -ForegroundColor White
Write-Host "     - Endpoint visible in API (with -IncludeFailed): $(if ($matchCheck.Count -gt 0) { 'Yes' } else { 'No' })" -ForegroundColor Gray
Write-Host "     - Portal still shows endpoint after delete     : $stillVisible" -ForegroundColor Gray
Write-Host ""
Write-Host "  All files are in:" -ForegroundColor Yellow
Write-Host "  $PSScriptRoot" -ForegroundColor White
Write-Host ""
Read-Host "  Press Enter to close"
