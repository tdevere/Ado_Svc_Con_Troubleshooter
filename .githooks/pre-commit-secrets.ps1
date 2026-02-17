[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$diffOutput = git diff --cached --unified=0 --no-color
if (-not $diffOutput) {
    exit 0
}

$addedLines = $diffOutput -split "`n" | Where-Object {
    $_.StartsWith('+') -and -not $_.StartsWith('+++')
}

if (-not $addedLines) {
    exit 0
}

$patterns = @(
    '(?i)\bPAT\b\s*=\s*"[^"]{12,}"',
    '(?i)\b(AZDO_PAT|PAT)\s*=\s*[^\s]+'
)

$knownTokenPatterns = @(
    '(?i)ghp_[A-Za-z0-9]{20,}',
    '(?i)glpat-[A-Za-z0-9\-_]{20,}',
    '(?i)xox[baprs]-[A-Za-z0-9\-]{10,}'
)

$allowedPlaceholders = @(
    'YOUR_PAT_TOKEN',
    'your-pat-token',
    'your-pat-token-here',
    'YOUR_PAT',
    '<PAT>',
    'REPLACE_ME',
    '****'
)

$hits = New-Object System.Collections.Generic.List[string]

foreach ($line in $addedLines) {
    $isAllowedPlaceholder = $false
    foreach ($placeholder in $allowedPlaceholders) {
        if ($line -like "*$placeholder*") {
            $isAllowedPlaceholder = $true
            break
        }
    }

    if ($isAllowedPlaceholder) {
        continue
    }

    foreach ($pattern in $patterns) {
        if ($line -match $pattern) {
            $hits.Add($line)
            break
        }
    }

    foreach ($pattern in $knownTokenPatterns) {
        if ($line -match $pattern) {
            $hits.Add($line)
            break
        }
    }
}

if ($hits.Count -gt 0) {
    Write-Host ""
    Write-Host "[pre-commit] Blocked: possible secret or token found in staged changes." -ForegroundColor Red
    Write-Host "Please remove/redact these lines before committing:" -ForegroundColor Yellow
    $hits | Select-Object -Unique | ForEach-Object { Write-Host "  $_" -ForegroundColor Yellow }
    Write-Host ""
    Write-Host "Tip: use placeholders like YOUR_PAT_TOKEN and keep real values only in local .env." -ForegroundColor Cyan
    exit 1
}

exit 0
