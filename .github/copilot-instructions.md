# Azure DevOps Service Connection Troubleshooter - AI Agent Instructions

## Project Overview
This is a PowerShell-based tool for managing Azure DevOps Service Connections via REST API. The primary goal is to provide cross-platform (Windows/Linux) utilities for deleting and troubleshooting service connections that may be in corrupted or problematic states.

## Core Requirements

### Cross-Platform PowerShell
- **Must** support Windows PowerShell 5.1 AND PowerShell 7+ on Linux
- Use `Invoke-RestMethod` or `Invoke-WebRequest` (both are cross-compatible)
- Avoid Windows-specific cmdlets or .NET types unavailable on Linux
- Test path handling with both `/` and `\` separators

### Authentication Pattern
Azure DevOps REST API authentication uses **Basic Auth with PAT**:
```powershell
$base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$PAT"))
$headers = @{ Authorization = "Basic $base64AuthInfo" }
```
**Critical**: Username is an empty string - format is `":$PAT"`, not `"user:$PAT"`

### REST API Specifics
- **API Version**: `7.1` (stable) - Use this instead of `7.1-preview.4`
- **Required PAT Scopes**:
  - `vso.serviceendpoint` - Read operations (GET)
  - `vso.serviceendpoint_manage` - Manage operations (POST, PUT, PATCH, DELETE)
- Service connections are **project-scoped** resources (except DELETE and SHARE which are org-scoped)

#### Complete API Method Reference

| Method | HTTP | URL Pattern | Purpose |
|--------|------|-------------|----------|
| **Get Single** | GET | `/{org}/{project}/_apis/serviceendpoint/endpoints/{id}` | Retrieve one endpoint |
| **Get List** | GET | `/{org}/{project}/_apis/serviceendpoint/endpoints` | List all endpoints (supports filters) |
| **Get By Names** | GET | `/{org}/{project}/_apis/serviceendpoint/endpoints?endpointNames={names}` | Query by friendly names |
| **Create** | POST | `/{org}/_apis/serviceendpoint/endpoints` | Create new endpoint |
| **Refresh Auth** | POST | `/{org}/{project}/_apis/serviceendpoint/endpoints?endpointIds={ids}` | Refresh OAuth tokens |
| **Update Single** | PUT | `/{org}/_apis/serviceendpoint/endpoints/{id}` | Update one endpoint |
| **Update Bulk** | PUT | `/{org}/_apis/serviceendpoint/endpoints` | Update multiple endpoints |
| **Share** | PATCH | `/{org}/_apis/serviceendpoint/endpoints/{id}` | Share across projects |
| **Delete** | DELETE | `/{org}/_apis/serviceendpoint/endpoints/{id}?projectIds={ids}` | Delete from projects |
| **Get History** | GET | `/{org}/{project}/_apis/serviceendpoint/executionhistory` | Query usage audit trail |
| **Get Types** | GET | `/{org}/_apis/serviceendpoint/types` | List available endpoint types |

All URLs use `?api-version=7.1` query parameter.

## Code Structure Standards

### Function Naming
Use PowerShell approved verbs with consistent `Verb-AdoServiceConnection` pattern:

- `Get-AdoServiceConnection` - Retrieve single or list of endpoints
- `New-AdoServiceConnection` - Create new endpoint
- `Set-AdoServiceConnection` - Update existing endpoint
- `Remove-AdoServiceConnection` - Delete endpoint
- `Share-AdoServiceConnection` - Share endpoint across projects  
- `Update-AdoServiceConnectionAuth` - Refresh OAuth tokens
- `Get-AdoServiceConnectionHistory` - Query execution history
- `Get-AdoServiceConnectionType` - List available types

Prefix all functions with `Ado` to avoid naming conflicts with other modules.

### Logging Standards
**Logging is ENABLED by default** - All functions must implement comprehensive logging:

```powershell
param(
    [switch]$NoLog  # Disable logging (default: logging enabled)
)
```

**Log Requirements:**
- **Directory**: Save to `logs/` in script/module root (create if missing)
- **Filename Pattern**: `ado-sc-{operation}-{timestamp}.log` 
  - Example: `ado-sc-remove-20260206-143052.log`
- **Dual Format**: Generate BOTH formats simultaneously
  - **Human-readable**: `{filename}.log` - Text with timestamps, request/response summaries
  - **JSON structured**: `{filename}.json` - Machine-parseable with full details
- **Content to Log**:
  - Timestamp (ISO 8601 format)
  - Operation type and parameters (PAT MUST be redacted)
  - Full HTTP request (method, URL, headers with redacted auth)
  - Full HTTP response (status, headers, body)
  - Success/failure status
  - Any error messages with stack traces
- **Output Message**: Print log file paths on completion
  ```
  Logs saved to:
    c:\path\to\logs\ado-sc-remove-20260206-143052.log
    c:\path\to\logs\ado-sc-remove-20260206-143052.json
  ```

**PAT Redaction Pattern**:
```powershell
$redactedPAT = $PAT.Substring(0, 4) + "****" + $PAT.Substring($PAT.Length - 4)
```

### Required Parameters
Standard parameter pattern for all functions:
```powershell
param(
    [Parameter(Mandatory=$true)]
    [string]$Organization,
    
    [Parameter(Mandatory=$true)]
    [string]$Project,
    
    [Parameter(Mandatory=$true)]
    [string]$EndpointId,
    
    [Parameter(Mandatory=$true)]
    [string]$PAT,
    
    [switch]$NoLog  # Disable logging (enabled by default)
)
```

### Testing Workflow
Every function must include self-test capabilities:
1. **Pre-operation GET** - Verify endpoint exists and capture current state
2. **Get Execution History** - Query recent usage (enabled by default via `-SkipHistory` flag)
3. **Execute operation** - Perform the requested action (DELETE, UPDATE, etc.)
4. **Post-operation GET** - Verify expected state change
5. **Log verification** - Confirm both .log and .json files created
6. **PASS/FAIL reporting** - Clear success/failure status with log paths

**Execution History Integration:**
- By default, query execution history BEFORE destructive operations (DELETE)
- Display recent pipeline usage to inform user of potential impact
- Use `-SkipHistory` flag to bypass this check for automation scenarios
- Log execution history results to help troubleshoot "in-use" errors

### Error Handling
- Wrap REST calls in try/catch blocks
- Provide **actionable** error messages for common issues:
  - 401 Unauthorized → Check PAT permissions and scope
  - 404 Not Found → Verify Organization/Project/EndpointId
  - 403 Forbidden → Verify PAT has "Manage" scope
  - Network errors → Check connectivity to dev.azure.com

## File Organization

### PowerShell Module Structure (Long-Term Support)
Use a proper PowerShell module for maintainability and code reuse:

```
AdoServiceConnectionTools/
├── AdoServiceConnectionTools.psd1    # Module manifest
├── AdoServiceConnectionTools.psm1    # Main module file
├── Public/                           # Exported functions
│   ├── Get-AdoServiceConnection.ps1
│   ├── New-AdoServiceConnection.ps1
│   ├── Set-AdoServiceConnection.ps1
│   ├── Remove-AdoServiceConnection.ps1
│   ├── Share-AdoServiceConnection.ps1
│   └── Get-AdoServiceConnectionHistory.ps1
├── Private/                          # Internal helper functions
│   ├── New-AdoAuthHeader.ps1        # PAT to Base64 conversion
│   ├── Write-AdoLog.ps1             # Dual-format logging
│   ├── Invoke-AdoRestMethod.ps1     # Wrapper with error handling
│   └── Test-AdoGuidFormat.ps1       # Parameter validation
├── Tests/                            # Pester tests
│   └── AdoServiceConnectionTools.Tests.ps1
├── logs/                             # Generated at runtime
└── README.md
```

**Module Development Rules:**
- **No placeholders**: All code must be immediately runnable
- **Shared logic**: Extract common patterns (auth, logging, error handling) to Private/ functions
- **Export only Public/** functions via module manifest
- **Cross-platform compatible**: Test on both Windows PowerShell 5.1 and PowerShell 7+ on Linux
- **Single import**: Users run `Import-Module .\AdoServiceConnectionTools` to access all functions

## Development Workflow

### Module Usage
**Import Module** (first time):
```powershell
# Windows or Linux
Import-Module .\AdoServiceConnectionTools -Force
```

**Testing Commands**:
```powershell
# Delete with execution history check and logging (default behavior)
Remove-AdoServiceConnection -Organization "myorg" -Project "myproject" -EndpointId "guid" -PAT "token"

# Delete without history check, no logging
Remove-AdoServiceConnection -Organization "myorg" -Project "myproject" -EndpointId "guid" -PAT "token" -SkipHistory -NoLog

# Get endpoint details
Get-AdoServiceConnection -Organization "myorg" -Project "myproject" -EndpointId "guid" -PAT "token"

# List all endpoints with logging
Get-AdoServiceConnection -Organization "myorg" -Project "myproject" -PAT "token"

# Query execution history
Get-AdoServiceConnectionHistory -Organization "myorg" -Project "myproject" -EndpointId "guid" -PAT "token"
```

**Cross-Platform Testing**:
```bash
# Linux/macOS with PowerShell 7+
pwsh -Command "Import-Module ./AdoServiceConnectionTools; Remove-AdoServiceConnection -Organization 'myorg' -Project 'myproject' -EndpointId 'guid' -PAT 'token'"
```

### No Azure CLI Dependency
- Do **not** use `az devops` commands
- Do **not** require `az login`
- Pure REST API calls with PAT authentication only

## Troubleshooting Patterns

When implementing diagnostic features, check for:
1. **PAT validation** - Test with GET request before destructive operations
2. **Endpoint ID format** - Validate GUID format
3. **URL construction** - Log full URLs during testing (redact PAT)
4. **Response body inspection** - Parse JSON responses for detailed error info
5. **Corrupted state detection** - Service connections may exist but be unusable

## Reference Files
- [OriginalPrompt.md](OriginalPrompt.md) - Complete requirements specification and context
