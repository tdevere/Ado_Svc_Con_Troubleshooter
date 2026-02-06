# AdoServiceConnectionTools Module
# Main module file that loads all public and private functions

# Get the module root path
$ModuleRoot = $PSScriptRoot

# Import private helper functions (not exported)
$PrivateFunctions = Get-ChildItem -Path "$ModuleRoot\Private\*.ps1" -ErrorAction SilentlyContinue
foreach ($Function in $PrivateFunctions) {
    try {
        . $Function.FullName
    }
    catch {
        Write-Error "Failed to import private function $($Function.FullName): $_"
    }
}

# Import public functions (exported via manifest)
$PublicFunctions = Get-ChildItem -Path "$ModuleRoot\Public\*.ps1" -ErrorAction SilentlyContinue
foreach ($Function in $PublicFunctions) {
    try {
        . $Function.FullName
    }
    catch {
        Write-Error "Failed to import public function $($Function.FullName): $_"
    }
}

# Module initialization
Write-Verbose "AdoServiceConnectionTools module loaded successfully"
Write-Verbose "Use Get-Command -Module AdoServiceConnectionTools to see available commands"
