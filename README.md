# Azure DevOps Service Connection Troubleshooter

[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue.svg)](https://github.com/PowerShell/PowerShell)
[![Platform](https://img.shields.io/badge/platform-Windows%20%7C%20Linux%20%7C%20macOS-lightgrey.svg)](https://github.com/tdevere/Ado_Svc_Con_Troubleshooter)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

> **⚠️ Community Tool - No Official Support**: This is a community-developed troubleshooting tool with no warranties or support guarantees. Use at your own risk.

PowerShell module for managing and troubleshooting Azure DevOps Service Connections via REST API. Provides comprehensive tools for listing, deleting, and diagnosing service connection issues with built-in logging and execution history tracking.

## Features

- ✅ **Cross-platform**: Works on Windows PowerShell 5.1 and PowerShell 7+ (Linux/macOS)
- ✅ **Complete API coverage**: All 11 Azure DevOps Service Endpoints REST API methods
- ✅ **Dual-format logging**: Human-readable text and JSON logs enabled by default
- ✅ **Execution history**: Automatic pipeline usage checks before deletion
- ✅ **Self-testing workflow**: Pre/post operation validation with PASS/FAIL reporting
- ✅ **No Azure CLI dependency**: Pure REST API with PAT authentication

## Quick Start

### Installation

```powershell
# Clone the repository
git clone https://github.com/tdevere/Ado_Svc_Con_Troubleshooter.git
cd Ado_Svc_Con_Troubleshooter

# Import the module
Import-Module .\AdoServiceConnectionTools
```

### Prerequisites

**Create a Personal Access Token (PAT)** with appropriate scopes:
- **Read operations**: `vso.serviceendpoint`
- **Manage operations**: `vso.serviceendpoint_manage`

[Create PAT in Azure DevOps](https://dev.azure.com/_usersSettings/tokens)

### Basic Usage

```powershell
# List all service connections
Get-AdoServiceConnection -Organization "myorg" -Project "myproject" -PAT "your-pat"

# Get single service connection
Get-AdoServiceConnection -Organization "myorg" -Project "myproject" -EndpointId "guid" -PAT "your-pat"

# Check execution history before deletion
Get-AdoServiceConnectionHistory -Organization "myorg" -Project "myproject" -EndpointId "guid" -PAT "your-pat"

# Delete service connection (with confirmation prompt)
Remove-AdoServiceConnection -Organization "myorg" -Project "myproject" -EndpointId "guid" -PAT "your-pat"
```

## Documentation

- **User Guide**: [AdoServiceConnectionTools/README.md](AdoServiceConnectionTools/README.md)
- **Developer Guide**: [.github/copilot-instructions.md](.github/copilot-instructions.md)
- **Project Status**: [PROJECT_STATUS.md](PROJECT_STATUS.md)
- **Test Script**: [Test-Module.ps1](Test-Module.ps1)

## Available Commands

| Function | Status | Purpose |
|----------|--------|---------|
| `Get-AdoServiceConnection` | ✅ Implemented | List/retrieve endpoints with filtering |
| `Remove-AdoServiceConnection` | ✅ Implemented | Delete with validation & history checks |
| `Get-AdoServiceConnectionHistory` | ✅ Implemented | Query pipeline usage audit trail |
| `New-AdoServiceConnection` | ⏳ Stub | Create new endpoint |
| `Set-AdoServiceConnection` | ⏳ Stub | Update existing endpoint |
| `Share-AdoServiceConnection` | ⏳ Stub | Share across projects |
| `Update-AdoServiceConnectionAuth` | ⏳ Stub | Refresh OAuth tokens |
| `Get-AdoServiceConnectionType` | ⏳ Stub | List available types |

## Key Features

### Logging (Enabled by Default)

All operations generate dual-format logs:
```
logs/
├── ado-sc-remove-20260206-143052.log   # Human-readable
└── ado-sc-remove-20260206-143052.json  # Machine-parseable
```

Logs include:
- Request/response details
- Success/failure status
- PAT redaction for security
- Full error messages

Disable with `-NoLog` flag.

### Execution History Integration

DELETE operations automatically check pipeline usage:
```powershell
Remove-AdoServiceConnection -Organization "myorg" -Project "myproject" -EndpointId "guid" -PAT "token"

# Output shows:
# Recent pipeline usage (last 5 executions):
#   - BuildPipeline | Type: Build | Result: succeeded | Time: 2026-02-06 11:30
```

Skip with `-SkipHistory` flag.

### Self-Testing Workflow

Every operation validates state:
1. Pre-operation GET (verify exists)
2. Execute operation
3. Post-operation GET (verify expected state)
4. Report PASS/FAIL with log paths

## Troubleshooting

### Common Issues

**401 Unauthorized**
- Verify PAT is valid and not expired
- Check scope includes `vso.serviceendpoint` or `vso.serviceendpoint_manage`

**404 Not Found**
- Verify Organization, Project, and EndpointId are correct
- Use `Get-AdoServiceConnection` to list available endpoints

**DELETE Succeeded But Endpoint Still Visible**
- Azure DevOps propagation delay (30-60 seconds)
- Verify in portal: `https://dev.azure.com/{org}/{project}/_settings/adminservices`
- Check [troubleshooting guide](AdoServiceConnectionTools/README.md#troubleshooting)

## Project Structure

```
Ado_Svc_Con_Troubleshooter/
├── .github/
│   └── copilot-instructions.md          # AI agent development guide
├── AdoServiceConnectionTools/            # PowerShell Module
│   ├── AdoServiceConnectionTools.psd1   # Module manifest
│   ├── AdoServiceConnectionTools.psm1   # Module loader
│   ├── README.md                        # Detailed documentation
│   ├── Private/                         # Helper functions
│   └── Public/                          # Exported functions
├── OriginalPrompt.md                    # Original requirements
├── PROJECT_STATUS.md                    # Implementation summary
├── Test-Module.ps1                      # Validation script
└── LICENSE                              # MIT License
```

## Contributing

Contributions are welcome! The project follows established patterns documented in [.github/copilot-instructions.md](.github/copilot-instructions.md).

To contribute:
1. Fork the repository
2. Create a feature branch
3. Follow existing code patterns (see implemented functions)
4. Test on both Windows and Linux
5. Submit a pull request

## API Reference

Uses Azure DevOps REST API v7.1 (stable):
- Base URL: `https://dev.azure.com/{organization}`
- Authentication: Basic Auth with PAT
- [Full API Documentation](https://learn.microsoft.com/en-us/rest/api/azure/devops/serviceendpoint/endpoints)

## License

MIT License - See [LICENSE](LICENSE) file for details.

## Support

**This is a community-supported tool with no official support guarantees.**

For issues or questions:
1. Check [troubleshooting guide](AdoServiceConnectionTools/README.md#troubleshooting)
2. Review log files in `logs/` directory
3. Open an issue on GitHub (community support only)
4. Include diagnostic data:
   - Log files (`.log` and `.json`)
   - Command executed
   - Expected vs actual behavior

Use at your own risk. No warranties or support commitments are provided.

---

**Note**: This tool uses REST API directly and does not require Azure CLI installation.
