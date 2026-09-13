Set-StrictMode -Version Latest

function New-MSTSystemRestorePoint {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Description
    )
	
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()

    $principal = New-Object `
        Security.Principal.WindowsPrincipal($identity)

    if (-not $principal.IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator
    )) {
        throw @"
Administrator privileges are required to create a System Restore point.

Restart MARIOSL Windows Tools as Administrator and try again.
"@
    }

    try {
        Checkpoint-Computer `
            -Description $Description `
            -RestorePointType MODIFY_SETTINGS `
            -ErrorAction Stop

        return [PSCustomObject]@{
            success     = $true
            description = $Description
        }
    }
    catch {
        throw "Failed to create System Restore point '$Description': $($_.Exception.Message)"
    }
}

Export-ModuleMember -Function @(
    'New-MSTSystemRestorePoint'
)