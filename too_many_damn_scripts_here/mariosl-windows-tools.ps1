# ============================================================
# mariosl35 Windows Tools
# Main entry point
#
# Development version.
# ============================================================

[CmdletBinding()]
param (
    [Parameter(Position = 0)]
    [ValidateSet(
        'Status',
        'Preflight',
        'Test',
        'UndoTest'
    )]
    [string]$Command = 'Status'
)

# Require administrator privileges before starting the application.

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)

if (-not $principal.IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)) {
    try {
        Start-Process `
            -FilePath 'powershell.exe' `
            -ArgumentList @(
                '-NoProfile',
                '-ExecutionPolicy',
                'Bypass',
                '-File',
                "`"$PSCommandPath`""
            ) `
            -Verb RunAs `
            -ErrorAction Stop | Out-Null

        exit
    }
    catch {
        Write-Host "Disagreed to run the script. What a wussy." -ForegroundColor Yellow
        exit 0
    }
}



Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ------------------------------------------------------------
# Tool information
# ------------------------------------------------------------

$ToolVersion = '0.1.0-dev'

# ------------------------------------------------------------
# Project paths
# ------------------------------------------------------------

$ProjectRoot = Split-Path -Parent $PSCommandPath

$ModuleRoot   = Join-Path $ProjectRoot 'modules'
$CoreRoot     = Join-Path $ModuleRoot 'Core'
$ProviderRoot = Join-Path $ModuleRoot 'Providers'

$ConfigRoot = Join-Path $ProjectRoot 'config'

$BackupDirectory = Join-Path $ProjectRoot 'backups'

# ------------------------------------------------------------
# Verify required files before loading anything
# ------------------------------------------------------------

$RequiredFiles = @(
    (Join-Path $CoreRoot 'Config.psm1'),
    (Join-Path $CoreRoot 'StateStore.psm1'),
    (Join-Path $ProviderRoot 'Registry.psm1'),
    (Join-Path $CoreRoot 'Engine.psm1'),
	(Join-Path $CoreRoot 'Compatibility.psm1')
)

foreach ($File in $RequiredFiles) {
    if (-not (Test-Path -LiteralPath $File -PathType Leaf)) {
        throw "Required module not found: $File"
    }
}

# ------------------------------------------------------------
# Load modules
# ------------------------------------------------------------

Import-Module `
    (Join-Path $CoreRoot 'Config.psm1') `
    -Force `
    -ErrorAction Stop

Import-Module `
    (Join-Path $CoreRoot 'StateStore.psm1') `
    -Force `
    -ErrorAction Stop

Import-Module `
    (Join-Path $ProviderRoot 'Registry.psm1') `
    -Force `
    -ErrorAction Stop

Import-Module `
    (Join-Path $CoreRoot 'Engine.psm1') `
    -Force `
    -ErrorAction Stop

Import-Module `
    (Join-Path $CoreRoot 'Compatibility.psm1') `
    -Force `
    -ErrorAction Stop

# ------------------------------------------------------------
# Initialize application infrastructure
# ------------------------------------------------------------

Initialize-MSTStateStore `
    -BackupDirectory $BackupDirectory

Initialize-MSTEngine `
    -ToolVersion $ToolVersion `
    -BackupDirectory $BackupDirectory `

# ------------------------------------------------------------
# Status
# ------------------------------------------------------------

function Show-MSTStatus {
    Write-Host ''
    Write-Host '========================================' -ForegroundColor Cyan
    Write-Host ' mariosl35 Windows Tools' -ForegroundColor Cyan
    Write-Host '========================================' -ForegroundColor Cyan
    Write-Host ''

    Write-Host "Version:    $ToolVersion"
    Write-Host "PowerShell: $($PSVersionTable.PSVersion)"
    Write-Host "OS:         $([Environment]::OSVersion.Version)"
    Write-Host ''

    Write-Host "Project:    $ProjectRoot"
    Write-Host "Backups:    $BackupDirectory"

    Write-Host ''
    Write-Host 'No Windows changes were made.' -ForegroundColor Green
    Write-Host ''
}

# ------------------------------------------------------------
# Load development test tweak
# ------------------------------------------------------------

function Get-MSTTestTweak {
    [CmdletBinding()]
    param ()

    $TestConfigPath = Join-Path `
        $ConfigRoot `
        'test\registry-test.json'

    if (-not (Test-Path -LiteralPath $TestConfigPath -PathType Leaf)) {
        throw "Test configuration not found: $TestConfigPath"
    }

    return Import-MSTConfig -Path $TestConfigPath
}

# ------------------------------------------------------------
# Generic test command
# ------------------------------------------------------------

function Invoke-MSTTest {
    [CmdletBinding()]
    param ()

    Write-Host ''
    Write-Host '========================================' -ForegroundColor Yellow
    Write-Host ' DEVELOPMENT TWEAK TEST' -ForegroundColor Yellow
    Write-Host '========================================' -ForegroundColor Yellow
    Write-Host ''

    $Tweak = Get-MSTTestTweak

    Write-Host "Tweak:     $($Tweak.displayName)"
    Write-Host "ID:        $($Tweak.id)"
    Write-Host "Provider:  $($Tweak.target.type)"
    Write-Host "Operation: $($Tweak.target.operation)"
    Write-Host ''

    Write-Host 'Target:' -ForegroundColor Cyan
    Write-Host "  Path: $($Tweak.target.path)"
    Write-Host "  Name: $($Tweak.target.name)"
    Write-Host ''

    if ($Tweak.target.operation -eq 'set') {
        Write-Host 'Desired value:' -ForegroundColor Cyan
        Write-Host "  Type:  $($Tweak.target.valueType)"
        Write-Host "  Value: $($Tweak.target.desiredValue)"
        Write-Host ''
    }

    $CurrentState = Get-MSTTweakState -Tweak $Tweak

    Write-Host 'Current state:' -ForegroundColor Cyan
    $CurrentState | Format-List | Out-Host

    if (Compare-MSTTweakState -Tweak $Tweak -State $CurrentState) {
        Write-Host 'Test target is already in the desired state.' `
            -ForegroundColor Yellow
        Write-Host ''
        return
    }

    Write-Host 'Creating snapshot and applying test...' `
        -ForegroundColor Yellow
    Write-Host ''

    $Result = Invoke-MSTTweak -Tweak $Tweak

    Write-Host ''
    Write-Host 'TEST SUCCESSFUL' -ForegroundColor Green
    Write-Host ''

    Write-Host "Success: $($Result.success)"
    Write-Host "Changed:   $($Result.changed)"
    Write-Host "Snapshot: $($Result.snapshot)"
    Write-Host ''

    Write-Host 'The change was applied and verified.' `
        -ForegroundColor Green

    Write-Host ''
}

# ------------------------------------------------------------
# Generic test rollback
# ------------------------------------------------------------

function Invoke-MSTUndoTest {
    [CmdletBinding()]
    param ()

    Write-Host ''
    Write-Host '========================================' -ForegroundColor Yellow
    Write-Host ' DEVELOPMENT TWEAK ROLLBACK' -ForegroundColor Yellow
    Write-Host '========================================' -ForegroundColor Yellow
    Write-Host ''

    $Tweak = Get-MSTTestTweak

    $Snapshots = @(
         Get-MSTActiveSnapshots `
             -TweakId $Tweak.id
     )

    if ($Snapshots.Count -eq 0) {
        Write-Host "No snapshot found for '$($Tweak.id)'." `
            -ForegroundColor Yellow
        Write-Host ''
        return
    }

    $Snapshot = $Snapshots |
        Select-Object -First 1

    Write-Host "Tweak:    $($Snapshot.tweakId)"
    Write-Host "Snapshot: $($Snapshot.snapshotId)"
    Write-Host "Created:  $($Snapshot.createdUtc)"
    Write-Host ''

    Write-Host 'Original state:' -ForegroundColor Cyan
    $Snapshot.state | Format-List | Out-Host

    Write-Host 'Restoring original state...' `
        -ForegroundColor Yellow

    $Result = Restore-MSTTweak `
	    -Tweak $tweak `
        -SnapshotPath $Snapshot.SnapshotPath
		
		if (-not $Result.success -or -not $Result.restored) {
			throw "Rollback did not report successful restoration."
		}

    Write-Host ''
    Write-Host 'ROLLBACK SUCCESSFUL' -ForegroundColor Green
    Write-Host ''

    Write-Host "Success: $($Result.success)"
	Write-Host "Restored: $($Result.restored)"
    Write-Host ''

    Write-Host 'The original state was restored and verified.' `
        -ForegroundColor Green

    Write-Host ''
}

# ------------------------------------------------------------
# Read-only preflight
# ------------------------------------------------------------

function Invoke-MSTPreflight {
    [CmdletBinding()]
    param ()

    Write-Host ''
    Write-Host '========================================' -ForegroundColor Cyan
    Write-Host ' READ-ONLY PREFLIGHT CHECK' -ForegroundColor Cyan
    Write-Host '========================================' -ForegroundColor Cyan
    Write-Host ''

    $Tweak = Get-MSTTestTweak

    Write-Host "Test target:" -ForegroundColor Cyan
    Write-Host "  Path: $($Tweak.target.path)"
    Write-Host "  Name: $($Tweak.target.name)"
    Write-Host "  Operation: $($Tweak.target.operation)"
    Write-Host ''

    Write-Host 'Reading current registry state...' `
        -ForegroundColor Yellow

    $State = Get-MSTTweakState -Tweak $Tweak

    Write-Host ''
    Write-Host 'Registry provider: OK' -ForegroundColor Green
    Write-Host ''

    Write-Host 'Current state:' -ForegroundColor Cyan
    $State | Format-List | Out-Host

    Write-Host 'Preflight completed.' -ForegroundColor Green
    Write-Host ''

    Write-Host 'No registry values were created, changed, or removed.' `
        -ForegroundColor Green

    Write-Host ''
	Write-Host ''
    Write-Host 'System compatibility:'

    $compatibility = Get-MSTSystemCompatibility

    if ($compatibility.windows.compatible) {
        Write-Host '[OK] Windows compatibility'
    }
    else {
        Write-Host '[FAIL] Windows compatibility'
    }

    if ($compatibility.powershell.compatible) {
        Write-Host '[OK] PowerShell compatibility'
    }
    else {
        Write-Host '[FAIL] PowerShell compatibility'
    }

    if (-not $compatibility.compatible) {
        throw 'System compatibility requirements are not satisfied.'
    }
}

# ------------------------------------------------------------
# Command dispatcher
# ------------------------------------------------------------

switch ($Command) {

    'Status' {
        Show-MSTStatus
    }

    'Preflight' {
        Invoke-MSTPreflight
    }

    'Test' {
        Invoke-MSTTest
    }

    'UndoTest' {
        Invoke-MSTUndoTest
    }

    default {
        throw "Unknown command: $Command"
    }
}