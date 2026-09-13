Set-StrictMode -Version Latest

Import-Module `
    (Join-Path (Split-Path -Parent $PSScriptRoot) 'Providers\Registry.psm1') `
    -Force `
    -ErrorAction Stop

Import-Module `
    (Join-Path (Split-Path -Parent $PSScriptRoot) 'Providers\Services.psm1') `
    -Force `
    -ErrorAction Stop
	
Import-Module `
    (Join-Path $PSScriptRoot '..\Providers\Appx.psm1') `
    -Force `
    -ErrorAction Stop
	
Import-Module `
    (Join-Path $PSScriptRoot 'StateStore.psm1') `
    -Force `
    -ErrorAction Stop

Import-Module `
    (Join-Path $PSScriptRoot '..\Providers\SystemRestore.psm1') `
	-Force `
	-ErrorAction Stop

function Initialize-MSTEngine {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ToolVersion,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$BackupDirectory
    )

    $script:MSTToolVersion = $ToolVersion
    $script:MSTBackupDirectory = $BackupDirectory

    Initialize-MSTStateStore `
        -BackupDirectory $BackupDirectory
}

function New-MSTBatchRestorePoint {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Description
    )

    try {
        return New-MSTSystemRestorePoint -Description $Description
    }
    catch {
        throw "System Restore protection failed: $($_.Exception.Message)"
    }
}

function Invoke-MSTBatch {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [object[]]$Tweaks,

        [Parameter(Mandatory = $false)]
        [bool]$CreateSystemRestorePoint = $false
    )

    if ($CreateSystemRestorePoint) {
        [void](New-MSTBatchRestorePoint `
            -Description 'MARIOSL Windows Tools — Before Changes')
    }

    $Results = @()

    foreach ($Tweak in $Tweaks) {
        $Results += Invoke-MSTTweak -Tweak $Tweak
    }

    return $Results
}

function Test-MSTTweakDefinition {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [object]$Tweak
    )

    $requiredProperties = @(
        'schemaVersion',
        'id',
        'displayName',
        'requiresElevation',
        'description',
        'category',
        'riskLevel',
        'rollbackCapability',
        'requiresRestart'
    )

    foreach ($property in $requiredProperties) {
        if ($null -eq $Tweak.PSObject.Properties[$property]) {
            throw "Tweak definition is missing required property '$property'."
        }
    }

    if ([int]$Tweak.schemaVersion -ne 1) {
        throw "Unsupported tweak schema version '$($Tweak.schemaVersion)'."
    }

    if ([string]::IsNullOrWhiteSpace([string]$Tweak.id)) {
        throw 'Tweak id cannot be empty.'
    }

    if ([string]::IsNullOrWhiteSpace([string]$Tweak.displayName)) {
        throw "Tweak '$($Tweak.id)' has an empty displayName."
    }

    if ($Tweak.requiresElevation -isnot [bool]) {
        throw "Tweak '$($Tweak.id)' requiresElevation must be a boolean."
    }

    $validRollbackCapabilities = @(
        'full',
        'bestEffort',
        'none'
    )

    if (
        [string]$Tweak.rollbackCapability -notin
        $validRollbackCapabilities
    ) {
        throw "Tweak '$($Tweak.id)' has invalid rollbackCapability '$($Tweak.rollbackCapability)'."
    }

    $validRestartModes = @(
        'none',
        'required',
        'recommended'
    )

    if (
        [string]$Tweak.requiresRestart -notin
        $validRestartModes
    ) {
        throw "Tweak '$($Tweak.id)' has invalid requiresRestart '$($Tweak.requiresRestart)'."
    }

    $HasTarget =
        $Tweak.PSObject.Properties.Name -contains 'target'

    $HasTargets =
        $Tweak.PSObject.Properties.Name -contains 'targets'

    if ($HasTarget -and $HasTargets) {
        throw "Tweak '$($Tweak.id)' cannot define both 'target' and 'targets'."
    }

    if (-not $HasTarget -and -not $HasTargets) {
        throw "Tweak '$($Tweak.id)' must define either 'target' or 'targets'."
    }

    if ($HasTarget) {
        $Targets = @($Tweak.target)
    }
    else {
        if ($null -eq $Tweak.targets) {
            throw "Tweak '$($Tweak.id)' has a null 'targets' collection."
        }

        $Targets = @($Tweak.targets)
    }

    if ($Targets.Count -eq 0) {
        throw "Tweak '$($Tweak.id)' must contain at least one target."
    }

    foreach ($Target in $Targets) {

        if ($null -eq $Target) {
            throw "Tweak '$($Tweak.id)' contains a null target."
        }

        if ($null -eq $Target.PSObject.Properties['type']) {
            throw "Tweak '$($Tweak.id)' target is missing type."
        }

        if ($null -eq $Target.PSObject.Properties['operation']) {
            throw "Tweak '$($Tweak.id)' target is missing operation."
        }

        $targetType = [string]$Target.type
        $operation = [string]$Target.operation

        switch ($targetType) {

            'registry' {

                if ($operation -notin @('set', 'remove')) {
                    throw "Tweak '$($Tweak.id)' has unsupported registry operation '$operation'."
                }

                if ($null -eq $Target.PSObject.Properties['path']) {
                    throw "Registry tweak '$($Tweak.id)' is missing target.path."
                }

                if ($null -eq $Target.PSObject.Properties['name']) {
                    throw "Registry tweak '$($Tweak.id)' is missing target.name."
                }

                if ($operation -eq 'set') {

                    if ($null -eq $Target.PSObject.Properties['valueType']) {
                        throw "Registry tweak '$($Tweak.id)' is missing target.valueType."
                    }

                    if ($null -eq $Target.PSObject.Properties['desiredValue']) {
                        throw "Registry tweak '$($Tweak.id)' is missing target.desiredValue."
                    }

                    if (
                        [string]$Target.valueType -notin @(
                            'String',
                            'ExpandString',
                            'Binary',
                            'DWord',
                            'MultiString',
                            'QWord'
                        )
                    ) {
                        throw "Tweak '$($Tweak.id)' has unsupported valueType '$($Target.valueType)'."
                    }
                }
            }

            'service' {

                if ($operation -ne 'set') {
                    throw "Tweak '$($Tweak.id)' has unsupported service operation '$operation'."
                }

                if ($null -eq $Target.PSObject.Properties['name']) {
                    throw "Service tweak '$($Tweak.id)' is missing target.name."
                }

                if ($null -eq $Target.PSObject.Properties['startMode']) {
                    throw "Service tweak '$($Tweak.id)' is missing target.startMode."
                }

                if (
                    [string]$Target.startMode -notin @(
                        'Automatic',
                        'Manual',
                        'Disabled'
                    )
                ) {
                    throw "Tweak '$($Tweak.id)' has unsupported startMode '$($Target.startMode)'."
                }
            }
			
			'appxPackage' {
                if ([string]$Target.operation -ne 'remove') {
                    throw "AppX target '$($Target.name)' must use operation 'remove'."
                }

                if ([string]::IsNullOrWhiteSpace([string]$Target.name)) {
                    throw "AppX target name cannot be empty."
                }
            }

            default {
                throw "Tweak '$($Tweak.id)' has unsupported target type '$targetType'."
            }
        }
    }

    return $true
}

function Get-MSTTweakState {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [object]$Tweak
    )

    Test-MSTTweakDefinition -Tweak $Tweak | Out-Null

$Targets = @(
    Get-MSTTweakTargets -Tweak $Tweak
)
    $States = @()

    foreach ($Target in $Targets) {

        switch ([string]$Target.type) {

            'registry' {
                $States += Get-MSTRegistryValueState `
                    -Path $Target.path `
                    -Name $Target.name
            }

            'service' {
                $States += Get-MSTServiceState `
                    -Name $Target.name
            }
			
			'appxPackage' {
                $States += Get-MSTAppxPackageState `
                    -Name $Target.name
            }

            default {
                throw "Unsupported target provider '$($Target.type)'."
            }
        }
    }

    if ($Targets.Count -eq 1) {
        return $States[0]
    }

    return $States
}

function Get-MSTTweakTargets {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [object]$Tweak
    )

    Test-MSTTweakDefinition -Tweak $Tweak | Out-Null

    if ($Tweak.PSObject.Properties.Name -contains 'targets') {
        return @($Tweak.targets)
    }

    return @($Tweak.target)
}

function Compare-MSTTweakState {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [object]$Tweak,

        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [object]$State
    )

    Test-MSTTweakDefinition -Tweak $Tweak | Out-Null

    $Targets = @(
    Get-MSTTweakTargets -Tweak $Tweak
)
    $States = @($State)

    if ($States.Count -ne $Targets.Count) {
        throw "Tweak '$($Tweak.id)' returned $($States.Count) states for $($Targets.Count) targets."
    }

    for ($i = 0; $i -lt $Targets.Count; $i++) {

        $Target = $Targets[$i]
        $TargetState = $States[$i]

        switch ([string]$Target.type) {

            'registry' {

                if (
                    -not $TargetState.exists -or
                    $TargetState.value -ne $Target.desiredValue
                ) {
                    return $false
                }
            }

'service' {

    if (-not $TargetState.exists) {
        continue
    }

    if (
        -not (
            Test-MSTServiceState `
                -State $TargetState `
                -ExpectedStartMode $Target.startMode
        )
    ) {
        return $false
    }
}
			
			'appxPackage' {
                if ($TargetState.exists) {
                    return $false
                }
            }

            default {
                throw "Unsupported target provider '$($Target.type)'."
            }
        }
    }

    return $true
}


function Invoke-MSTTweak {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [object]$Tweak
    )

    if (
        -not (Get-Variable -Name MSTToolVersion -Scope Script -ErrorAction SilentlyContinue) -or
        [string]::IsNullOrWhiteSpace($script:MSTToolVersion)
    ) {
        throw @"
MARIOSL Windows Tools engine has not been initialized.

Call Initialize-MSTEngine before invoking tweaks.
"@
    }

    if (
        -not (Get-Variable -Name MSTBackupDirectory -Scope Script -ErrorAction SilentlyContinue) -or
        [string]::IsNullOrWhiteSpace($script:MSTBackupDirectory)
    ) {
        throw @"
MARIOSL Windows Tools state store has not been initialized.

Call Initialize-MSTEngine before invoking tweaks.
"@
    }

    Test-MSTTweakDefinition -Tweak $Tweak | Out-Null

    $Targets = @(
    Get-MSTTweakTargets -Tweak $Tweak
)
    $beforeState = Get-MSTTweakState -Tweak $Tweak

    if (Compare-MSTTweakState -Tweak $Tweak -State $beforeState) {
        return [PSCustomObject]@{
            success    = $true
            changed    = $false
            tweakId    = $Tweak.id
            snapshot   = $null
            before     = $beforeState
            after      = $beforeState
        }
    }

    if ($Tweak.rollbackCapability -eq 'none') {
        $snapshotPath = $null
    }
    else {
        $snapshotPath = New-MSTSnapshot `
            -TweakId $Tweak.id `
            -ToolVersion $script:MSTToolVersion `
            -State $beforeState
    }

    try {

        foreach ($Target in $Targets) {

            switch ([string]$Target.type) {

                'registry' {

                    switch ([string]$Target.operation) {

                        'set' {
                            Set-MSTRegistryValue `
                                -Path $Target.path `
                                -Name $Target.name `
                                -Value $Target.desiredValue `
                                -ValueType $Target.valueType
                        }

                        'remove' {
                            Remove-MSTRegistryValue `
                                -Path $Target.path `
                                -Name $Target.name
                        }

                        default {
                            throw "Unsupported registry operation '$($Target.operation)'."
                        }
                    }
                }

                'service' {

                    Set-MSTServiceState `
                        -Name $Target.name `
                        -StartMode $Target.startMode
                }
				
'appxPackage' {

    switch ([string]$Target.operation) {

        'remove' {
            Remove-MSTAppxPackage `
                -Name $Target.name | Out-Null
        }

        default {
            throw "Unsupported AppX operation '$($Target.operation)'."
        }
    }
}

                default {
                    throw "Unsupported target provider '$($Target.type)'."
                }
            }
        }

        $afterState = Get-MSTTweakState -Tweak $Tweak

        if (-not (Compare-MSTTweakState -Tweak $Tweak -State $afterState)) {
            throw "Verification failed after applying tweak '$($Tweak.id)'."
        }

        return [PSCustomObject]@{
            success    = $true
            changed    = $true
            tweakId    = $Tweak.id
            snapshot   = $snapshotPath
            before     = $beforeState
            after      = $afterState
        }
    }
    catch {
        $originalError = $_

        if ($null -ne $snapshotPath) {
            try {
                Restore-MSTTweak `
                    -Tweak $Tweak `
                    -SnapshotPath $snapshotPath
            }
            catch {
                throw @"
Tweak '$($Tweak.id)' failed and automatic rollback also failed.

Original error:
$($originalError.Exception.Message)

Rollback error:
$($_.Exception.Message)
"@
            }
        }

        throw "Failed to apply tweak '$($Tweak.id)': $($originalError.Exception.Message)"
    }
}


function Restore-MSTTweak {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [object]$Tweak,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$SnapshotPath
    )

    Test-MSTTweakDefinition -Tweak $Tweak | Out-Null

    $snapshot = Get-MSTSnapshot -Path $SnapshotPath

    if ($snapshot.tweakId -ne $Tweak.id) {
        throw @"
Snapshot does not belong to tweak '$($Tweak.id)'.

Snapshot tweak:
$($snapshot.tweakId)
"@
    }

    $Targets = @(
        Get-MSTTweakTargets -Tweak $Tweak
    )

    $States = @(
        $snapshot.state
    )

    if ($States.Count -ne $Targets.Count) {
        throw @"
Snapshot state count does not match tweak target count.

Tweak:
$($Tweak.id)

Targets:
$($Targets.Count)

Snapshot states:
$($States.Count)
"@
    }

    for ($i = 0; $i -lt $Targets.Count; $i++) {

        $Target = $Targets[$i]
        $State = $States[$i]

        switch ([string]$State.provider) {

            'registry' {
                Restore-MSTRegistryValueState `
                    -State $State
            }

            'service' {
                Restore-MSTServiceState `
                    -State $State
            }
			
'appxPackage' {
    throw @"
AppX package restoration is not currently supported.

Tweak:
$($Tweak.id)

Package:
$($Target.name)
"@
}

            default {
                throw "Unsupported snapshot provider '$($State.provider)'."
            }
        }
    }

    $currentState = Get-MSTTweakState -Tweak $Tweak

    $CurrentStates = @(
        $currentState
    )

    if ($CurrentStates.Count -ne $Targets.Count) {
        throw "Rollback verification returned an unexpected number of states for tweak '$($Tweak.id)'."
    }

    for ($i = 0; $i -lt $Targets.Count; $i++) {

        $Target = $Targets[$i]
        $ExpectedState = $States[$i]
        $ActualState = $CurrentStates[$i]

        switch ([string]$ExpectedState.provider) {

            'registry' {

                $restored = (
                    $ActualState.keyExists -eq $ExpectedState.keyExists -and
                    $ActualState.exists -eq $ExpectedState.exists -and
                    $ActualState.valueType -eq $ExpectedState.valueType -and
                    $ActualState.value -eq $ExpectedState.value
                )
            }

            'service' {

                $restored = (
                    $ActualState.startMode -eq $ExpectedState.startMode
                )
            }
			
			'appxPackage' {
    throw @"
AppX rollback verification is not currently supported.

Tweak:
$($Tweak.id)

Package:
$($Target.name)
"@
}

            default {
                throw "Unsupported snapshot provider '$($ExpectedState.provider)'."
            }
        }

        if (-not $restored) {
            throw @"
Rollback verification failed for tweak '$($Tweak.id)'.

Target:
$($i + 1)
Type:
$($Target.type)
"@
        }
    }

    Set-MSTSnapshotStatus `
        -Snapshot $snapshot `
        -Status 'rolledBack' | Out-Null

    return [PSCustomObject]@{
        success   = $true
        tweakId   = $Tweak.id
        snapshot  = $SnapshotPath
        restored  = $true
        state     = $currentState
    }
}


Export-ModuleMember -Function @(
    'Initialize-MSTEngine',
    'Test-MSTTweakDefinition',
	'Get-MSTTweakTargets',
    'Get-MSTTweakState',
    'Compare-MSTTweakState',
    'Invoke-MSTTweak',
    'Restore-MSTTweak',
	'New-MSTBatchRestorePoint',
	'Invoke-MSTBatch'
)