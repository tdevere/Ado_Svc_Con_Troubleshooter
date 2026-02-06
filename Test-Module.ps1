# Azure DevOps Service Connection Tools - Test Script
# This script demonstrates module usage and validates the implementation

<#
.SYNOPSIS
    Test script for AdoServiceConnectionTools module
    
.DESCRIPTION
    Demonstrates all implemented functions and validates the module works correctly.
    
    REQUIRED: Update the variables below with your Azure DevOps details before running.
    
.NOTES
    For actual testing, you'll need:
    - Valid Azure DevOps organization
    - Project name
    - PAT with appropriate permissions
    - Existing service connection ID (for GET/DELETE tests)
#>

# ============================================================================
# CONFIGURATION - UPDATE THESE VALUES
# ============================================================================

$Organization = "YOUR_ORG"          # e.g., "myorg" from https://dev.azure.com/myorg
$Project = "YOUR_PROJECT"            # e.g., "myproject"
$PAT = "YOUR_PAT_TOKEN"              # Create at https://dev.azure.com/_usersSettings/tokens
$TestEndpointId = "YOUR_ENDPOINT_GUID"  # Optional - for testing specific endpoint

# ============================================================================
# MODULE IMPORT
# ============================================================================

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Azure DevOps Service Connection Tools" -ForegroundColor Cyan
Write-Host "Module Test Script" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Import module
$ModulePath = Join-Path $PSScriptRoot "AdoServiceConnectionTools"
try {
    Import-Module $ModulePath -Force
    Write-Host "✓ Module imported successfully`n" -ForegroundColor Green
}
catch {
    Write-Host "✗ Failed to import module: $_" -ForegroundColor Red
    exit 1
}

# List available commands
Write-Host "Available Commands:" -ForegroundColor Yellow
Get-Command -Module AdoServiceConnectionTools | Format-Table Name, Version -AutoSize
Write-Host ""

# ============================================================================
# TEST 1: LIST ALL SERVICE CONNECTIONS
# ============================================================================

Write-Host "TEST 1: List All Service Connections" -ForegroundColor Magenta
Write-Host "----------------------------------------`n" -ForegroundColor Magenta

if ($Organization -ne "YOUR_ORG" -and $Project -ne "YOUR_PROJECT" -and $PAT -ne "YOUR_PAT_TOKEN") {
    try {
        $result = Get-AdoServiceConnection -Organization $Organization -Project $Project -PAT $PAT
        
        if ($result.Success) {
            Write-Host "`n✓ TEST 1 PASSED`n" -ForegroundColor Green
        }
        else {
            Write-Host "`n✗ TEST 1 FAILED: $($result.Message)`n" -ForegroundColor Red
        }
    }
    catch {
        Write-Host "`n✗ TEST 1 ERROR: $_`n" -ForegroundColor Red
    }
}
else {
    Write-Host "⚠ TEST 1 SKIPPED - Update configuration variables first`n" -ForegroundColor Yellow
}

# ============================================================================
# TEST 2: GET SINGLE SERVICE CONNECTION
# ============================================================================

Write-Host "TEST 2: Get Single Service Connection" -ForegroundColor Magenta
Write-Host "----------------------------------------`n" -ForegroundColor Magenta

if ($TestEndpointId -ne "YOUR_ENDPOINT_GUID") {
    try {
        $result = Get-AdoServiceConnection -Organization $Organization -Project $Project -EndpointId $TestEndpointId -PAT $PAT
        
        if ($result.Success) {
            Write-Host "`n✓ TEST 2 PASSED`n" -ForegroundColor Green
        }
        else {
            Write-Host "`n✗ TEST 2 FAILED: $($result.Message)`n" -ForegroundColor Red
        }
    }
    catch {
        Write-Host "`n✗ TEST 2 ERROR: $_`n" -ForegroundColor Red
    }
}
else {
    Write-Host "⚠ TEST 2 SKIPPED - Set TestEndpointId variable`n" -ForegroundColor Yellow
}

# ============================================================================
# TEST 3: GET EXECUTION HISTORY
# ============================================================================

Write-Host "TEST 3: Get Execution History" -ForegroundColor Magenta
Write-Host "----------------------------------------`n" -ForegroundColor Magenta

if ($TestEndpointId -ne "YOUR_ENDPOINT_GUID") {
    try {
        $result = Get-AdoServiceConnectionHistory -Organization $Organization -Project $Project -EndpointId $TestEndpointId -PAT $PAT -Top 10
        
        if ($result.Success) {
            Write-Host "`n✓ TEST 3 PASSED`n" -ForegroundColor Green
        }
        else {
            Write-Host "`n✗ TEST 3 FAILED: $($result.Message)`n" -ForegroundColor Red
        }
    }
    catch {
        Write-Host "`n✗ TEST 3 ERROR: $_`n" -ForegroundColor Red
    }
}
else {
    Write-Host "⚠ TEST 3 SKIPPED - Set TestEndpointId variable`n" -ForegroundColor Yellow
}

# ============================================================================
# TEST 4: LOGGING VERIFICATION
# ============================================================================

Write-Host "TEST 4: Verify Logging Functionality" -ForegroundColor Magenta
Write-Host "----------------------------------------`n" -ForegroundColor Magenta

$LogsDir = Join-Path $PSScriptRoot "AdoServiceConnectionTools\logs"

if (Test-Path $LogsDir) {
    $logFiles = Get-ChildItem -Path $LogsDir -Filter "*.log" | Sort-Object LastWriteTime -Descending | Select-Object -First 3
    
    if ($logFiles) {
        Write-Host "Recent log files:" -ForegroundColor Cyan
        $logFiles | ForEach-Object {
            Write-Host "  - $($_.Name) ($([math]::Round($_.Length / 1KB, 2)) KB)" -ForegroundColor Gray
        }
        
        Write-Host "`n✓ TEST 4 PASSED - Logging functional`n" -ForegroundColor Green
    }
    else {
        Write-Host "⚠ No log files found yet (run other tests first)`n" -ForegroundColor Yellow
    }
}
else {
    Write-Host "⚠ Logs directory not created yet (will be created on first operation)`n" -ForegroundColor Yellow
}

# ============================================================================
# TEST 5: FILTER BY TYPE
# ============================================================================

Write-Host "TEST 5: Filter Service Connections by Type" -ForegroundColor Magenta
Write-Host "----------------------------------------`n" -ForegroundColor Magenta

if ($Organization -ne "YOUR_ORG" -and $Project -ne "YOUR_PROJECT" -and $PAT -ne "YOUR_PAT_TOKEN") {
    try {
        $result = Get-AdoServiceConnection -Organization $Organization -Project $Project -Type "AzureRM" -PAT $PAT
        
        if ($result.Success) {
            Write-Host "`n✓ TEST 5 PASSED`n" -ForegroundColor Green
        }
        else {
            Write-Host "`n✗ TEST 5 FAILED: $($result.Message)`n" -ForegroundColor Red
        }
    }
    catch {
        Write-Host "`n✗ TEST 5 ERROR: $_`n" -ForegroundColor Red
    }
}
else {
    Write-Host "⚠ TEST 5 SKIPPED - Update configuration variables first`n" -ForegroundColor Yellow
}

# ============================================================================
# SUMMARY
# ============================================================================

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Test Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

Write-Host "`nImplemented Functions:" -ForegroundColor Green
Write-Host "  ✓ Get-AdoServiceConnection" -ForegroundColor Green
Write-Host "  ✓ Get-AdoServiceConnectionHistory" -ForegroundColor Green
Write-Host "  ✓ Remove-AdoServiceConnection" -ForegroundColor Green

Write-Host "`nStub Functions (Not Yet Implemented):" -ForegroundColor Yellow
Write-Host "  ○ New-AdoServiceConnection" -ForegroundColor Yellow
Write-Host "  ○ Set-AdoServiceConnection" -ForegroundColor Yellow
Write-Host "  ○ Share-AdoServiceConnection" -ForegroundColor Yellow
Write-Host "  ○ Update-AdoServiceConnectionAuth" -ForegroundColor Yellow
Write-Host "  ○ Get-AdoServiceConnectionType" -ForegroundColor Yellow

Write-Host "`nNext Steps:" -ForegroundColor Cyan
Write-Host "  1. Update configuration variables at top of script" -ForegroundColor White
Write-Host "  2. Create PAT at: https://dev.azure.com/_usersSettings/tokens" -ForegroundColor White
Write-Host "  3. Run script again to test with real data" -ForegroundColor White
Write-Host "  4. Check logs/ directory for operation logs" -ForegroundColor White

Write-Host "`nDocumentation:" -ForegroundColor Cyan
Write-Host "  - README: AdoServiceConnectionTools\README.md" -ForegroundColor White
Write-Host "  - AI Instructions: .github\copilot-instructions.md" -ForegroundColor White

Write-Host "`n========================================`n" -ForegroundColor Cyan
