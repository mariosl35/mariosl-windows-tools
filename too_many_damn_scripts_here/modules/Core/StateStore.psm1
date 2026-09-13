Set-StrictMode -Version Latest

function Initialize-MSTStateStore {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$BackupDirectory
    )

    if (-not (Test-Path -LiteralPath $BackupDirectory -PathType Container)) {
        New-Item `
            -ItemType Directory `
            -Path $BackupDirectory `
            -Force `
            -ErrorAction Stop | Out-Null
    }

    $script:MSTBackupDirectory = $BackupDirectory
}

function New-MSTSnapshot {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$TweakId,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ToolVersion,

        [Parameter(Mandatory = $true)]
        [object]$State
    )

    if (-not $script:MSTBackupDirectory) {
        throw 'State store has not been initialized. Call Initialize-MSTStateStore first.'
    }

    $timestamp = (Get-Date).ToUniversalTime()
    $snapshotId = $timestamp.ToString('yyyyMMddTHHmmssfffZ')

    $safeTweakId = $TweakId -replace '[^a-zA-Z0-9._-]', '_'

    $snapshotDirectory = Join-Path `
        $script:MSTBackupDirectory `
        $snapshotId

    New-Item `
        -ItemType Directory `
        -Path $snapshotDirectory `
        -Force `
        -ErrorAction Stop | Out-Null

    $snapshotPath = Join-Path `
        $snapshotDirectory `
        "$safeTweakId.json"

    $snapshot = [ordered]@{
        schemaVersion = 2
        snapshotId    = $snapshotId
        createdUtc    = $timestamp.ToString('o')
        toolVersion   = $ToolVersion
        tweakId       = $TweakId
        status        = 'active'
        state         = $State
    }

    $snapshot |
        ConvertTo-Json -Depth 20 |
        Set-Content `
            -LiteralPath $snapshotPath `
            -Encoding UTF8 `
            -ErrorAction Stop

    return $snapshotPath
}

function Get-MSTSnapshot {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Snapshot not found: $Path"
    }

    try {
        $raw = Get-Content `
            -LiteralPath $Path `
            -Raw `
            -ErrorAction Stop

        if ([string]::IsNullOrWhiteSpace($raw)) {
            throw 'Snapshot file is empty.'
        }

        $snapshot = $raw | ConvertFrom-Json -ErrorAction Stop

        # Preserve the physical snapshot location so callers
        # can update the exact snapshot later.
        $snapshot | Add-Member `
            -NotePropertyName 'snapshotPath' `
            -NotePropertyValue $Path `
            -Force

        return $snapshot
    }
    catch {
        throw "Failed to read snapshot '$Path': $($_.Exception.Message)"
    }
}

function Get-MSTSnapshots {
    [CmdletBinding()]
    param ()

    if (-not $script:MSTBackupDirectory) {
        throw 'State store has not been initialized. Call Initialize-MSTStateStore first.'
    }

    if (-not (Test-Path -LiteralPath $script:MSTBackupDirectory -PathType Container)) {
        return @()
    }

    $files = Get-ChildItem `
        -LiteralPath $script:MSTBackupDirectory `
        -Filter '*.json' `
        -File `
        -Recurse `
        -ErrorAction Stop

    $snapshots = foreach ($file in $files) {
        try {
            Get-MSTSnapshot -Path $file.FullName
        }
        catch {
            # Ignore invalid snapshot files.
            continue
        }
    }

    return $snapshots | Sort-Object -Property createdUtc -Descending
}

function Get-MSTActiveSnapshots {
    [CmdletBinding()]
    param (
        [Parameter()]
        [string]$TweakId
    )

    $snapshots = Get-MSTSnapshots

    $active = $snapshots | Where-Object {
        # Only schema version 2 snapshots participate in
        # active snapshot management.
        $_.schemaVersion -eq 2 -and
        $_.status -eq 'active'
    }

    if (-not [string]::IsNullOrWhiteSpace($TweakId)) {
        $active = $active | Where-Object {
            $_.tweakId -eq $TweakId
        }
    }

    return @(
        $active |
            Sort-Object -Property createdUtc -Descending
    )
}

function Set-MSTSnapshotStatus {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [object]$Snapshot,

        [Parameter(Mandatory = $true)]
        [ValidateSet(
            'active',
            'rolledBack'
        )]
        [string]$Status
    )

    if (-not $Snapshot.snapshotPath) {
        throw 'Snapshot does not contain a snapshotPath.'
    }

    if (-not (Test-Path -LiteralPath $Snapshot.snapshotPath -PathType Leaf)) {
        throw "Snapshot file not found: $($Snapshot.snapshotPath)"
    }

    $current = Get-MSTSnapshot `
        -Path $Snapshot.snapshotPath

    $current.status = $Status

    $current |
        Select-Object `
            schemaVersion,
            snapshotId,
            createdUtc,
            toolVersion,
            tweakId,
            status,
            state |
        ConvertTo-Json -Depth 20 |
        Set-Content `
            -LiteralPath $Snapshot.snapshotPath `
            -Encoding UTF8 `
            -ErrorAction Stop

    return Get-MSTSnapshot `
        -Path $Snapshot.snapshotPath
}

Export-ModuleMember -Function @(
    'Initialize-MSTStateStore',
    'New-MSTSnapshot',
    'Get-MSTSnapshot',
    'Get-MSTSnapshots',
    'Get-MSTActiveSnapshots',
    'Set-MSTSnapshotStatus'
)
