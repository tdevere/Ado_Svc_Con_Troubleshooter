# Customer Guide: Force Delete a Service Connection

Use this quick guide when a service connection is stuck/corrupted and normal delete fails.

## Assumptions
- You already know the service connection `EndpointId` (GUID)
- You have a PAT with **Service Connections (Read & manage)** scope
- If you omit `-Organization`, `-Project`, and `-PAT`, those values must exist in `.env` as `ORGANIZATION`, `PROJECT`, and `PAT`

## 1) Open PowerShell and import the module

```powershell
cd C:\path\to\Ado_Svc_Con_Troubleshooter
$endpointId = "YOUR_ENDPOINT_ID"

Import-Module .\AdoServiceConnectionTools -Force
```

If you are **not** using `.env` defaults, set these too:

```powershell
$org = "YOUR_ORG"
$project = "YOUR_PROJECT"
$pat = "your-pat-token"
```

## 2) Pull from API using the new flag (`-IncludeFailed`)

Use `-IncludeFailed` to ensure failed/corrupted connections are returned.

```powershell
$result = Get-AdoServiceConnection -IncludeFailed
$target = @($result.Data | Where-Object { $_.id -eq $endpointId })
$target | Select-Object name, type, id, url, isReady | Format-Table -AutoSize
$target.Count
```

If not using `.env` defaults:

```powershell
$result = Get-AdoServiceConnection -Organization $org -Project $project -IncludeFailed -PAT $pat
```

Expected: `$target.Count` is `1`.

If count is `0`, verify org/project/endpoint ID and retry.

## 3) Force delete using the new flag (`-Deep`)

```powershell
Remove-AdoServiceConnection -EndpointId $endpointId -Deep
```

If not using `.env` defaults:

```powershell
Remove-AdoServiceConnection -Organization $org -Project $project -EndpointId $endpointId -PAT $pat -Deep
```

What `-Deep` does:
- Deletes the service connection
- Also attempts to delete the associated service principal

## 4) Verify in Azure DevOps portal

Open:

`https://dev.azure.com/YOUR_ORG/YOUR_PROJECT/_settings/adminservices`

- If still visible, wait 30–60 seconds and refresh (propagation delay is common)
- If still present after ~2 minutes, collect logs from `AdoServiceConnectionTools\logs\`

## One-command version

```powershell
Import-Module .\AdoServiceConnectionTools -Force; $endpointId = "YOUR_ENDPOINT_ID"; $result = Get-AdoServiceConnection -IncludeFailed -NoLog; $target = @($result.Data | Where-Object { $_.id -eq $endpointId }); if ($target.Count -ne 1) { Write-Error "Endpoint not uniquely found. Count=$($target.Count). EndpointId=$endpointId" } else { $target | Select-Object name, type, id, isReady | Format-Table -AutoSize; Remove-AdoServiceConnection -EndpointId $endpointId -Deep }
```

If you are not using `.env` defaults, use this one-liner instead:

```powershell
Import-Module .\AdoServiceConnectionTools -Force; $endpointId = "YOUR_ENDPOINT_ID"; $org = "YOUR_ORG"; $project = "YOUR_PROJECT"; $pat = "YOUR_PAT"; $result = Get-AdoServiceConnection -Organization $org -Project $project -IncludeFailed -PAT $pat -NoLog; $target = @($result.Data | Where-Object { $_.id -eq $endpointId }); if ($target.Count -ne 1) { Write-Error "Endpoint not uniquely found. Count=$($target.Count). EndpointId=$endpointId" } else { $target | Select-Object name, type, id, isReady | Format-Table -AutoSize; Remove-AdoServiceConnection -Organization $org -Project $project -EndpointId $endpointId -PAT $pat -Deep }
```
