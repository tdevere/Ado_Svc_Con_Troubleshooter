# Azure DevOps Service Connection Troubleshooter

A guided tool for removing broken or stuck Azure DevOps Service Connections.
No coding experience required for the standard workflow.

> **Community Tool — No Official Support.** Use at your own risk.

---

## Before You Start: Create a Personal Access Token (PAT)

A PAT is a temporary password that lets the tool talk to Azure DevOps on your behalf.

1. Open: **https://dev.azure.com/YOUR_ORG/_usersSettings/tokens**
   (replace `YOUR_ORG` with your organization name)
2. Click **+ New Token**
3. Fill in:
   - **Name:** `Service Connection Troubleshooter`
   - **Expiration:** 7 days is enough
   - **Scopes:** Choose **Custom defined**, then check **Service Connections — Read & manage**
4. Click **Create**
5. **Copy the token immediately** — you cannot view it again after closing the dialog

---

## Option A — Guided Wizard (Recommended)

The wizard walks you through every step, shows selectable lists, and requires no typing of GUIDs.

1. **Download or clone this repository** and extract it to a folder on your computer
2. In that folder, **double-click `Start-CustomerValidation.bat`**
3. Follow the on-screen prompts:
   - Enter your **organization name** (the part after `dev.azure.com/`)
   - Paste your **PAT** when asked
   - Select your **project** from the numbered list
   - Select the **service connection** to remove from the numbered list
   - Confirm when prompted
4. When it finishes, the wizard prints a list of log files to send to your support contact if needed

**Tip:** The wizard offers to save your settings to a `.env` file at the end. Doing so means you can run it again later without re-entering anything.

---

## Option B — Manual PowerShell Commands

Use this if you prefer to run commands yourself or need to script the workflow.

### Step 1 — Open PowerShell and import the tool

```powershell
cd C:\path\to\Ado_Svc_Con_Troubleshooter
Import-Module .\AdoServiceConnectionTools -Force
```

You may see a warning about "unapproved verbs" — this is harmless, ignore it.

### Step 2 — Save your PAT to a variable

```powershell
$pat = "paste-your-pat-here"
```

### Step 3 — Find the service connection

```powershell
$result = Get-AdoServiceConnection -Organization "YOUR_ORG" -Project "YOUR_PROJECT" -PAT $pat -IncludeFailed
```

This returns all service connections, including ones that are broken or corrupted (`-IncludeFailed`).

**If you get back more than one result**, narrow it down by name:

```powershell
$target = @($result.Data | Where-Object { $_.name -eq "EXACT_NAME_HERE" })
$target | Select-Object name, type, id, isReady | Format-Table -AutoSize
```

Confirm `$target.Count` is `1` before continuing.

### Step 4 — Delete the service connection

```powershell
Remove-AdoServiceConnection -Organization "YOUR_ORG" -Project "YOUR_PROJECT" -PAT $pat -EndpointId $target[0].id
```

Type **Y** and press Enter when asked to confirm.

### Step 5 — Verify in the portal

Open **https://dev.azure.com/YOUR_ORG/YOUR_PROJECT/_settings/adminservices** and confirm the connection is gone.

> **Note:** It is normal for the connection to remain visible for up to 60 seconds after deletion. Refresh the page after a minute if needed.

---

## Stuck or Corrupted Connections: Force Delete

If a normal delete returns an error or the connection keeps reappearing, add the `-Deep` flag.
This removes the service connection **and** the underlying service principal in Azure AD.

```powershell
Remove-AdoServiceConnection -Organization "YOUR_ORG" -Project "YOUR_PROJECT" -PAT $pat -EndpointId "ENDPOINT_GUID" -Deep
```

Use `Get-AdoServiceConnection ... -IncludeFailed` first to confirm the endpoint ID,
as corrupted connections may not appear without that flag.

---

## Saving Your Settings (.env File)

If you run this tool more than once, create a `.env` file in the root folder to avoid
re-entering your details every time:

```
ORGANIZATION=your-org-name
PROJECT=your-project-name
PAT=your-pat-token
```

Once this file exists, all commands work without any parameters:

```powershell
Get-AdoServiceConnection -IncludeFailed
Remove-AdoServiceConnection -EndpointId "GUID" -Deep
```

> **Security:** The `.env` file is excluded from git and never committed.
> Treat it like a password file — do not share it or store it in a shared drive.

---

## Troubleshooting

| Error | Cause | Fix |
|-------|-------|-----|
| `401 Unauthorized` | PAT is invalid, expired, or wrong scope | Create a new PAT with **Service Connections (Read & manage)** checked |
| `403 Forbidden` | PAT lacks manage permission | Same as above — ensure the **manage** box is checked, not just read |
| `404 Not Found` | Wrong org, project, or endpoint ID | Double-check each value; run `Get-AdoServiceConnection` to list available IDs |
| Connection still visible after delete | Azure propagation delay | Wait 60 seconds and refresh the portal. This is expected behaviour. |
| Connection still visible after 2+ minutes | Corrupted state | Re-run with `-Deep` flag; if still stuck, collect logs and contact support |

---

## Log Files

Every operation writes logs to `AdoServiceConnectionTools\logs\`:

```
ado-sc-remove-20260218-143052.log    <- human-readable summary
ado-sc-remove-20260218-143052.json   <- full machine-readable detail
```

PAT values are always redacted in logs (only first and last 4 characters are shown).

If you need to escalate an issue, send the `.log` and `.json` files for the relevant
operation along with a screenshot from the Azure DevOps portal.

---

## License

MIT — see [LICENSE](LICENSE). Community-supported; no warranties or support commitments.