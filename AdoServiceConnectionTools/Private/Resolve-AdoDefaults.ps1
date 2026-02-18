function Get-AdoEnvDefaults {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    if ($script:AdoEnvDefaultsCache) {
        return $script:AdoEnvDefaultsCache
    }

    $candidatePaths = @()

    if ($env:ADO_SC_ENV_PATH) {
        $candidatePaths += $env:ADO_SC_ENV_PATH
    }

    try {
        $currentPath = (Get-Location).Path
        if ($currentPath) {
            $candidatePaths += (Join-Path $currentPath ".env")
        }
    }
    catch {
    }

    if ($PSScriptRoot) {
        $moduleRoot = Split-Path $PSScriptRoot -Parent
        $repoRoot = Split-Path $moduleRoot -Parent
        $candidatePaths += (Join-Path $moduleRoot ".env")
        $candidatePaths += (Join-Path $repoRoot ".env")
    }

    $envPath = $candidatePaths | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1

    $defaults = @{}

    if ($envPath) {
        Get-Content -Path $envPath -ErrorAction Stop | ForEach-Object {
            $line = $_.Trim()
            if (-not $line -or $line.StartsWith('#')) {
                return
            }

            $separatorIndex = $line.IndexOf('=')
            if ($separatorIndex -lt 1) {
                return
            }

            $key = $line.Substring(0, $separatorIndex).Trim()
            $value = $line.Substring($separatorIndex + 1).Trim()

            if (($value.StartsWith('"') -and $value.EndsWith('"')) -or ($value.StartsWith("'") -and $value.EndsWith("'"))) {
                $value = $value.Substring(1, $value.Length - 2)
            }

            if ($key) {
                $defaults[$key] = $value
            }
        }
    }

    $script:AdoEnvDefaultsCache = $defaults
    return $defaults
}

function Resolve-AdoDefaultContext {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [string]$Organization,
        [string]$Project,
        [string]$PAT,
        [string]$EndpointId,
        [string[]]$Required = @('Organization', 'Project', 'PAT')
    )

    $defaults = Get-AdoEnvDefaults

    if ([string]::IsNullOrWhiteSpace($Organization)) {
        $Organization = if ($defaults['ORGANIZATION']) { $defaults['ORGANIZATION'] } elseif ($defaults['AZDO_ORGANIZATION']) { $defaults['AZDO_ORGANIZATION'] } else { $null }
    }

    if ([string]::IsNullOrWhiteSpace($Project)) {
        $Project = if ($defaults['PROJECT']) { $defaults['PROJECT'] } elseif ($defaults['AZDO_PROJECT']) { $defaults['AZDO_PROJECT'] } else { $null }
    }

    if ([string]::IsNullOrWhiteSpace($PAT)) {
        $PAT = if ($defaults['PAT']) { $defaults['PAT'] } elseif ($defaults['AZDO_PAT']) { $defaults['AZDO_PAT'] } else { $null }
    }

    if ([string]::IsNullOrWhiteSpace($EndpointId)) {
        $EndpointId = if ($defaults['ENDPOINT_ID']) { $defaults['ENDPOINT_ID'] } elseif ($defaults['TEST_ENDPOINT_ID']) { $defaults['TEST_ENDPOINT_ID'] } else { $null }
    }

    $resolved = [ordered]@{
        Organization = $Organization
        Project = $Project
        PAT = $PAT
        EndpointId = $EndpointId
    }

    $envKeyMap = @{
        Organization = 'ORGANIZATION'
        Project = 'PROJECT'
        PAT = 'PAT'
        EndpointId = 'ENDPOINT_ID (or TEST_ENDPOINT_ID)'
    }

    foreach ($name in $Required) {
        if ([string]::IsNullOrWhiteSpace($resolved[$name])) {
            $envKey = $envKeyMap[$name]
            throw "Missing required parameter '$name'. Provide -$name or define $envKey in .env."
        }
    }

    return [PSCustomObject]$resolved
}

function Get-AdoEnvPath {
    <#
    .SYNOPSIS
        Locates the .env file used by AdoServiceConnectionTools, or returns $null if none found.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $candidatePaths = @()

    if ($env:ADO_SC_ENV_PATH) { $candidatePaths += $env:ADO_SC_ENV_PATH }

    try {
        $currentPath = (Get-Location).Path
        if ($currentPath) { $candidatePaths += (Join-Path $currentPath ".env") }
    } catch {}

    if ($PSScriptRoot) {
        $moduleRoot = Split-Path $PSScriptRoot -Parent
        $repoRoot   = Split-Path $moduleRoot -Parent
        $candidatePaths += (Join-Path $moduleRoot ".env")
        $candidatePaths += (Join-Path $repoRoot   ".env")
    }

    return ($candidatePaths | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1)
}

function Set-AdoEnvValue {
    <#
    .SYNOPSIS
        Writes or updates a single key=value pair in the .env file, then invalidates the cache.

    .PARAMETER Key
        The environment variable name (e.g. TEST_ENDPOINT_ID).

    .PARAMETER Value
        The value to write.

    .PARAMETER EnvPath
        Optional explicit path to the .env file. Auto-detected when omitted.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Key,

        [Parameter(Mandatory = $true)]
        [string]$Value,

        [Parameter(Mandatory = $false)]
        [string]$EnvPath
    )

    if (-not $EnvPath) {
        $EnvPath = Get-AdoEnvPath
    }

    if (-not $EnvPath) {
        # No existing .env — create one next to the module root or in CWD
        $EnvPath = if ($PSScriptRoot) {
            Join-Path (Split-Path $PSScriptRoot -Parent) ".env"
        } else {
            Join-Path (Get-Location).Path ".env"
        }
    }

    if (Test-Path $EnvPath) {
        $lines = Get-Content $EnvPath -Encoding UTF8
        $found = $false
        $newLines = $lines | ForEach-Object {
            if ($_ -match "^\s*$([regex]::Escape($Key))\s*=") {
                "$Key=$Value"
                $found = $true
            } else {
                $_
            }
        }
        if (-not $found) { $newLines += "$Key=$Value" }
        $newLines | Set-Content $EnvPath -Encoding UTF8
    } else {
        "$Key=$Value" | Set-Content $EnvPath -Encoding UTF8
    }

    # Invalidate the in-memory cache so next read picks up the new value
    $script:AdoEnvDefaultsCache = $null

    Write-Verbose "Set-AdoEnvValue: '$Key' written to '$EnvPath'"
    return $EnvPath
}
