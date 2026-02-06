@{
    RootModule = 'AdoServiceConnectionTools.psm1'
    ModuleVersion = '1.0.0'
    GUID = 'a7b8c9d0-e1f2-4a3b-9c8d-7e6f5a4b3c2d'
    Author = 'Azure DevOps Service Connection Troubleshooter Team'
    CompanyName = 'Unknown'
    Copyright = '(c) 2026. All rights reserved.'
    Description = 'PowerShell module for managing Azure DevOps Service Connections via REST API. Supports cross-platform operation (Windows/Linux) with comprehensive logging and troubleshooting capabilities.'
    PowerShellVersion = '5.1'
    
    FunctionsToExport = @(
        'Get-AdoServiceConnection'
        'New-AdoServiceConnection'
        'Set-AdoServiceConnection'
        'Remove-AdoServiceConnection'
        'Share-AdoServiceConnection'
        'Update-AdoServiceConnectionAuth'
        'Get-AdoServiceConnectionHistory'
        'Get-AdoServiceConnectionType'
    )
    
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()
    
    PrivateData = @{
        PSData = @{
            Tags = @('AzureDevOps', 'ServiceConnection', 'REST-API', 'CrossPlatform', 'Troubleshooting')
            ProjectUri = 'https://github.com/yourusername/Ado_Svc_Con_Troubleshooter'
            RequireLicenseAcceptance = $false
        }
    }
}
