# Customer Guide: Delete Azure DevOps Service Connection

This guide walks you through using the PowerShell module to delete an Azure DevOps Service Connection that may be in a corrupted or problematic state.

## Prerequisites

### 1. Install PowerShell
- **Windows**: PowerShell 5.1+ (built-in) ✅ **Fully compatible**
- **Linux/macOS**: [Install PowerShell 7+](https://docs.microsoft.com/en-us/powershell/scripting/install/installing-powershell)

**Note**: This tool works on both Windows PowerShell 5.1 and PowerShell 7+ across all platforms.

### 2. Download the Tool
```powershell
# Clone or download the repository
git clone https://github.com/tdevere/Ado_Svc_Con_Troubleshooter.git
cd Ado_Svc_Con_Troubleshooter
```

Or download ZIP from GitHub and extract.

### 3. Create a Personal Access Token (PAT)

1. Go to: **https://dev.azure.com/{your-organization}/_usersSettings/tokens**
2. Click **"+ New Token"**
3. Set the following:
   - **Name**: Service Connection Troubleshooter
   - **Expiration**: 7 days (or custom)
   - **Scopes**: Custom defined
     - ✅ **Service Connections (Read & manage)** - Check this box
4. Click **"Create"**
5. **COPY THE TOKEN** - You won't be able to see it again!

---

## Step-by-Step Instructions

### Step 1: Open PowerShell

**Windows**: Press `Win + X` → Select "Windows PowerShell"  
**Linux/macOS**: Open Terminal and type `pwsh`

### Step 2: Navigate to the Tool Directory

```powershell
cd C:\path\to\Ado_Svc_Con_Troubleshooter
```

Replace `C:\path\to\` with the actual location where you downloaded the tool.

### Step 3: Store Your PAT Securely

```powershell
$pat = "your-pat-token-here"
```

Replace `your-pat-token-here` with the PAT you created in the prerequisites.

**Example:**
```powershell
$pat = "abc123xyz789yourpattoken"
```

### Step 4: Import the Module

```powershell
Import-Module .\AdoServiceConnectionTools -Force
```

You may see a warning about unapproved verbs - **this is normal, ignore it**.

### Step 5: Find Your Service Connection

First, list all service connections to find the one you want to delete:

```powershell
$result = Get-AdoServiceConnection -Organization "YOUR_ORG" -Project "YOUR_PROJECT" -PAT $pat
```

**Replace:**
- `YOUR_ORG` - Your Azure DevOps organization name (e.g., "MCAPDevOpsOrg")
- `YOUR_PROJECT` - Your project name (e.g., "PermaSamples")

**Example:**
```powershell
$result = Get-AdoServiceConnection -Organization "MCAPDevOpsOrg" -Project "PermaSamples" -PAT $pat
```

**Output will show:**
```
Service Connection Details:
  Name: deleteme2
  Type: azurerm
  ID: a8af53d8-8ae2-493d-8b4f-43775f96f6f8
  URL: https://management.azure.com/
  Owner: Library
```

### Step 6: Delete the Service Connection

```powershell
Remove-AdoServiceConnection -Organization "YOUR_ORG" -Project "YOUR_PROJECT" -PAT $pat -EndpointId $result.Data.id
```

Use the **same organization and project** from Step 5.

**Example:**
```powershell
Remove-AdoServiceConnection -Organization "MCAPDevOpsOrg" -Project "PermaSamples" -PAT $pat -EndpointId $result.Data.id
```

**What happens:**
1. Script verifies the service connection exists
2. Checks execution history (shows recent pipeline usage)
3. Asks for confirmation: **Type `Y` and press Enter**
4. Deletes the service connection
5. Waits 2 seconds for Azure DevOps to process
6. Verifies deletion

### Step 7: Verify Deletion in Azure DevOps Portal

Even if you see a warning, **check the portal to confirm**:

1. Go to: **https://dev.azure.com/{your-org}/{your-project}/_settings/adminservices**
2. Look for the service connection name
3. **If it's gone** - ✅ Success! Deletion worked.
4. **If it still exists** - Wait 1-2 minutes and refresh the page.

---

## Expected Output

### Successful Deletion

```
Found endpoint: deleteme2 (ID: a8af53d8-8ae2-493d-8b4f-43775f96f6f8)

No execution history found (endpoint hasn't been used yet)

Confirm
Are you sure you want to perform this action?
Performing the operation "Delete" on target "Service Connection 'deleteme2' (...)".
[Y] Yes  [A] Yes to All  [N] No  [L] No to All  [S] Suspend  [?] Help (default is "Y"): y

Deleting service connection...
Waiting for Azure DevOps to propagate deletion...
PASS: Service connection successfully deleted
```

### Propagation Delay Warning (Common)

```
WARNING: DELETE succeeded but endpoint still visible in API

This is often an Azure DevOps propagation delay. Please verify:
  1. Check Azure DevOps portal: https://dev.azure.com/YOUR_ORG/YOUR_PROJECT/_settings/adminservices
  2. Wait 30-60 seconds and check if endpoint is gone
  3. If endpoint persists, it may be in a corrupted state
```

**This warning is NORMAL** - Azure DevOps may take 30-60 seconds to propagate deletions.

---

## Troubleshooting

### Error: "A parameter cannot be found that matches parameter name 'ResponseHeadersVariable'"
**Problem**: Using Windows PowerShell 5.1 with an older version of the module  
**Solution**: 
1. Re-download/update the module to the latest version
2. Re-import: `Import-Module .\AdoServiceConnectionTools -Force`
3. Verify your PowerShell version: `$PSVersionTable.PSVersion`
   - Version 5.x = Windows PowerShell (now supported)
   - Version 7.x = PowerShell Core (supported)

**Note**: This error was fixed in version 1.0.1 - the module now works on both PowerShell versions.

### Error: "401 Unauthorized"
**Problem**: PAT is invalid or expired  
**Solution**: 
1. Create a new PAT (see prerequisites)
2. Ensure scope includes **"Service Connections (Read & manage)"**
3. Update `$pat` variable with new token

### Error: "404 Not Found"
**Problem**: Organization, Project, or Endpoint ID is incorrect  
**Solution**:
1. Verify organization name: `https://dev.azure.com/{org-name-here}`
2. Verify project name in Azure DevOps
3. Run Step 5 again to get correct endpoint ID

### Error: "403 Forbidden"
**Problem**: PAT doesn't have management permissions  
**Solution**: Create new PAT with **"Service Connections (Read & manage)"** scope

### Service Connection Still Exists After 2 Minutes

**If the endpoint is still visible in the portal after 2+ minutes:**

1. Collect the log files:
   - Location: `AdoServiceConnectionTools\logs\`
   - Look for: `ado-sc-remove-*.log` and `ado-sc-remove-*.json`

2. Take a screenshot of the service connection in the Azure DevOps portal

3. Run this command and save the output:
   ```powershell
   Get-AdoServiceConnection -Organization "YOUR_ORG" -Project "YOUR_PROJECT" -EndpointId "YOUR_ENDPOINT_ID" -PAT $pat
   ```

4. Open an issue on GitHub with:
   - Log files
   - Screenshot
   - Command output
   - Expected vs actual behavior

---

## Security Notes

- **Never share your PAT** - Treat it like a password
- **Delete PAT after use** - Go to https://dev.azure.com/_usersSettings/tokens and revoke it
- **Log files redact PAT** - Only first/last 4 characters are visible in logs

---

## Quick Reference

```powershell
# Full workflow example
cd C:\path\to\Ado_Svc_Con_Troubleshooter
$pat = "your-pat-token"
Import-Module .\AdoServiceConnectionTools -Force

# Find service connection
$result = Get-AdoServiceConnection -Organization "myorg" -Project "myproject" -PAT $pat

# Delete it
Remove-AdoServiceConnection -Organization "myorg" -Project "myproject" -PAT $pat -EndpointId $result.Data.id

# Verify in portal
Start-Process "https://dev.azure.com/myorg/myproject/_settings/adminservices"
```

---

## Need Help?

This is a **community-supported tool** with no official support guarantees.

For help:
1. Review this guide carefully
2. Check log files in `AdoServiceConnectionTools\logs\`
3. Open an issue on GitHub: https://github.com/tdevere/Ado_Svc_Con_Troubleshooter/issues
4. Include diagnostic data (logs, commands, error messages)

---

**Remember**: Always verify deletion in the Azure DevOps portal after running the script!
