# Azure DevOps Service Connection Troubleshooter

PowerShell module for managing and troubleshooting Azure DevOps Service Connections via REST API.

## Features

- ✅ **Cross-platform**: Works on Windows PowerShell 5.1 and PowerShell 7+ (Linux/macOS)
- ✅ **Comprehensive API coverage**: All 11 Azure DevOps Service Endpoints REST API methods
- ✅ **Dual-format logging**: Human-readable text and JSON logs enabled by default
- ✅ **Execution history**: Automatic pipeline usage checks before deletion
- ✅ **Self-testing**: Built-in validation workflow (pre-check → execute → verify)
- ✅ **PAT authentication**: No Azure CLI dependency

## Installation

```powershell
# Clone or download the module
cd c:\Users\azadmin\Repos\Ado_Svc_Con_Troubleshooter

# Import the module
Import-Module .\AdoServiceConnectionTools -Force
```

## Prerequisites

### Personal Access Token (PAT)
Create a PAT in Azure DevOps with appropriate scopes:

- **Read operations** (GET): `vso.serviceendpoint`
- **Manage operations** (DELETE, POST, PUT, PATCH): `vso.serviceendpoint_manage`

[Create a PAT](https://dev.azure.com/_usersSettings/tokens)

### Required Information
- **Organization name**: Your Azure DevOps organization (e.g., "myorg" from `https://dev.azure.com/myorg`)
- **Project name**: Project containing the service connection
- **Endpoint ID**: Service connection GUID (use `Get-AdoServiceConnection` to find)

## Quick Start

### List All Service Connections
```powershell
Import-Module .\AdoServiceConnectionTools

Get-AdoServiceConnection -Organization "myorg" -Project "myproject" -PAT "your-pat-token"
```

### Get Single Service Connection
```powershell
Get-AdoServiceConnection -Organization "myorg" -Project "myproject" -EndpointId "guid" -PAT "token"
```

### Delete Service Connection (with confirmation)
```powershell
Remove-AdoServiceConnection -Organization "myorg" -Project "myproject" -EndpointId "guid" -PAT "token"
```

### Check Execution History
```powershell
Get-AdoServiceConnectionHistory -Organization "myorg" -Project "myproject" -EndpointId "guid" -PAT "token"
```

## Advanced Usage

### Delete Without Execution History Check
```powershell
Remove-AdoServiceConnection -Organization "myorg" -Project "myproject" -EndpointId "guid" -PAT "token" -SkipHistory
```

### Delete Without Logging
```powershell
Remove-AdoServiceConnection -Organization "myorg" -Project "myproject" -EndpointId "guid" -PAT "token" -NoLog
```

### Delete Service Principal Too
```powershell
Remove-AdoServiceConnection -Organization "myorg" -Project "myproject" -EndpointId "guid" -PAT "token" -Deep
```

### Filter by Type
```powershell
Get-AdoServiceConnection -Organization "myorg" -Project "myproject" -Type "AzureRM" -PAT "token"
```

### Query by Name
```powershell
Get-AdoServiceConnection -Organization "myorg" -Project "myproject" -EndpointNames @("MyConnection1", "MyConnection2") -PAT "token"
```

## Logging

Logging is **enabled by default** and creates two files per operation:

```
logs/
├── ado-sc-remove-20260206-143052.log   # Human-readable
└── ado-sc-remove-20260206-143052.json  # Machine-parseable
```

### Log Contents
- Timestamp (ISO 8601)
- Operation parameters (PAT redacted)
- HTTP request details
- HTTP response details
- Success/failure status
- Error messages and stack traces

### Disable Logging
Add `-NoLog` switch to any command:
```powershell
Get-AdoServiceConnection -Organization "myorg" -Project "myproject" -PAT "token" -NoLog
```

## Available Functions

| Function | Purpose | API Method |
|----------|---------|------------|
| `Get-AdoServiceConnection` | Retrieve single or list of endpoints | GET |
| `Remove-AdoServiceConnection` | Delete endpoint from projects | DELETE |
| `Get-AdoServiceConnectionHistory` | Query usage audit trail | GET |
| `New-AdoServiceConnection` | Create new endpoint | POST |
| `Set-AdoServiceConnection` | Update existing endpoint | PUT |
| `Share-AdoServiceConnection` | Share across projects | PATCH |
| `Update-AdoServiceConnectionAuth` | Refresh OAuth tokens | POST |
| `Get-AdoServiceConnectionType` | List available types | GET |

## Cross-Platform Testing

### Windows PowerShell 5.1
```powershell
powershell.exe -File test.ps1
```

### PowerShell 7+ (Linux/macOS)
```bash
pwsh -Command "Import-Module ./AdoServiceConnectionTools; Get-AdoServiceConnection -Organization 'myorg' -Project 'myproject' -PAT 'token'"
```

## Troubleshooting

### 401 Unauthorized
- Verify PAT is valid and not expired
- Check PAT has required scope: `vso.serviceendpoint` or `vso.serviceendpoint_manage`

### 403 Forbidden
- PAT lacks "Manage" permissions
- Ensure PAT includes `vso.serviceendpoint_manage` scope

### 404 Not Found
- Verify Organization, Project, and EndpointId are correct
- Endpoint may have already been deleted
- Use `Get-AdoServiceConnection` without ID to list all available

### 409 Conflict
- Endpoint is currently in use by active pipelines
- Check execution history: `Get-AdoServiceConnectionHistory`
- Wait for pipelines to complete or disable them first

### DELETE Succeeded But Endpoint Still Visible
- Azure DevOps may take 30-60 seconds to propagate deletions
- **Verify in portal**: https://dev.azure.com/{organization}/{project}/_settings/adminservices
- If still present after 2 minutes:
  - Collect log files from `logs/` directory
  - Take screenshot from portal
  - Run: `Get-AdoServiceConnection` and save output
  - Contact support with collected data

### Network Errors
- Verify connectivity to `dev.azure.com`
- Check firewall/proxy settings
- Confirm organization name is correct

## Testing Workflow

Each operation follows a comprehensive test pattern:

1. **Pre-operation GET** - Verify resource exists
2. **Execution History** (for DELETE) - Show recent usage
3. **Execute operation** - Perform the action
4. **Post-operation GET** - Verify expected state
5. **Log verification** - Confirm logs created
6. **PASS/FAIL report** - Clear status output

Example output:
```
Found endpoint: MyServiceConnection (ID: abc123...)

Recent pipeline usage (last 5 executions):
  - Pipeline: Build | Result: succeeded | Date: 2026-02-05 14:23:15
  - Pipeline: Release | Result: succeeded | Date: 2026-02-04 10:15:42

Deleting service connection...
PASS: Service connection successfully deleted

Logs saved to:
  c:\...\logs\ado-sc-remove-20260206-143052.log
  c:\...\logs\ado-sc-remove-20260206-143052.json
```

## Module Structure

```
AdoServiceConnectionTools/
├── AdoServiceConnectionTools.psd1    # Module manifest
├── AdoServiceConnectionTools.psm1    # Module loader
├── Public/                           # Exported functions
│   ├── Get-AdoServiceConnection.ps1
│   ├── Remove-AdoServiceConnection.ps1
│   └── Get-AdoServiceConnectionHistory.ps1
├── Private/                          # Helper functions
│   ├── New-AdoAuthHeader.ps1
│   ├── Write-AdoLog.ps1
│   ├── Invoke-AdoRestMethod.ps1
│   └── Test-AdoGuidFormat.ps1
└── logs/                             # Generated at runtime
```

## API Reference

All functions use Azure DevOps REST API v7.1 (stable):
- Base URL: `https://dev.azure.com/{organization}`
- Authentication: Basic Auth with PAT (empty username)
- API Version: `7.1`

[Full API Documentation](https://learn.microsoft.com/en-us/rest/api/azure/devops/serviceendpoint/endpoints)

## Contributing

See [.github/copilot-instructions.md](.github/copilot-instructions.md) for development guidelines.

## License

MIT License - See LICENSE file for details
