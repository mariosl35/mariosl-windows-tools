Set-StrictMode -Version Latest

function Test-MSTRegistryPath {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )

    try {
        return Test-Path -LiteralPath $Path -ErrorAction Stop
    }
    catch {
        throw "Failed to check registry path '$Path': $($_.Exception.Message)"
    }
}

function Get-MSTRegistryValueState {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Name
    )

    $keyExists = Test-MSTRegistryPath -Path $Path

    if (-not $keyExists) {
        return [PSCustomObject]@{
            provider  = 'registry'
            path      = $Path
            name      = $Name
            keyExists = $false
            exists    = $false
            valueType = $null
            value     = $null
        }
    }

    try {
        $key = Get-Item -LiteralPath $Path -ErrorAction Stop
        $valueNames = $key.GetValueNames()

        if ($valueNames -notcontains $Name) {
            return [PSCustomObject]@{
                provider  = 'registry'
                path      = $Path
                name      = $Name
                keyExists = $true
                exists    = $false
                valueType = $null
                value     = $null
            }
        }

        $value = $key.GetValue(
            $Name,
            $null,
            [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames
        )

        $kind = $key.GetValueKind($Name)

        return [PSCustomObject]@{
            provider  = 'registry'
            path      = $Path
            name      = $Name
            keyExists = $true
            exists    = $true
            valueType = $kind.ToString()
            value     = $value
        }
    }
    catch {
        throw "Failed to read registry value '$Name' from '$Path': $($_.Exception.Message)"
    }
}

function Set-MSTRegistryValue {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [object]$Value,

        [Parameter(Mandatory = $true)]
        [ValidateSet(
            'String',
            'ExpandString',
            'Binary',
            'DWord',
            'MultiString',
            'QWord'
        )]
        [string]$ValueType
    )

    try {
        if (-not (Test-Path -LiteralPath $Path)) {
            New-Item `
                -Path $Path `
                -Force `
                -ErrorAction Stop | Out-Null
        }

        $propertyType = switch ($ValueType) {
            'String'       { [Microsoft.Win32.RegistryValueKind]::String }
            'ExpandString' { [Microsoft.Win32.RegistryValueKind]::ExpandString }
            'Binary'       { [Microsoft.Win32.RegistryValueKind]::Binary }
            'DWord'        { [Microsoft.Win32.RegistryValueKind]::DWord }
            'MultiString'  { [Microsoft.Win32.RegistryValueKind]::MultiString }
            'QWord'        { [Microsoft.Win32.RegistryValueKind]::QWord }

            default {
                throw "Unsupported registry value type '$ValueType'."
            }
        }

        $key = Get-Item `
            -LiteralPath $Path `
            -ErrorAction Stop

        $valueExists = $key.GetValueNames() -contains $Name

        if ($valueExists) {
            Set-ItemProperty `
                -LiteralPath $Path `
                -Name $Name `
                -Value $Value `
                -Force `
                -ErrorAction Stop
        }
        else {
            New-ItemProperty `
                -LiteralPath $Path `
                -Name $Name `
                -Value $Value `
                -PropertyType $propertyType `
                -Force `
                -ErrorAction Stop | Out-Null
        }
    }
    catch {
        throw "Failed to set registry value '$Name' in '$Path': $($_.Exception.Message)"
    }
}

function Remove-MSTRegistryValue {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Name
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }

    try {
        $key = Get-Item `
            -LiteralPath $Path `
            -ErrorAction Stop

        if ($key.GetValueNames() -notcontains $Name) {
            return
        }

        Remove-ItemProperty `
            -LiteralPath $Path `
            -Name $Name `
            -ErrorAction Stop
    }
    catch {
        throw "Failed to remove registry value '$Name' from '$Path': $($_.Exception.Message)"
    }
}

function Restore-MSTRegistryValueState {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [object]$State
    )

    if ($State.provider -ne 'registry') {
        throw 'Invalid state provider. Expected registry state.'
    }

    # The registry key did not exist before the tweak.
    if (-not $State.keyExists) {

        if (Test-Path -LiteralPath $State.path) {

            $key = Get-Item `
                -LiteralPath $State.path `
                -ErrorAction Stop

            $valueNames = $key.GetValueNames()

            if ($valueNames -contains $State.name) {
                Remove-MSTRegistryValue `
                    -Path $State.path `
                    -Name $State.name
            }

            # Only remove the key if it is now empty.
            #
            # This prevents rollback from deleting unrelated values
            # that may have appeared while the tweak was active.
            $remainingValueNames = (
                Get-Item `
                    -LiteralPath $State.path `
                    -ErrorAction Stop
            ).GetValueNames()

            if ($remainingValueNames.Count -eq 0) {
                Remove-Item `
                    -LiteralPath $State.path `
                    -Force `
                    -ErrorAction Stop
            }
        }

        return
    }

    # The key existed, but the specific value did not.
    if (-not $State.exists) {
        Remove-MSTRegistryValue `
            -Path $State.path `
            -Name $State.name

        return
    }

    # The value existed originally.
    Set-MSTRegistryValue `
        -Path $State.path `
        -Name $State.name `
        -Value $State.value `
        -ValueType $State.valueType
}

Export-ModuleMember -Function @(
    'Test-MSTRegistryPath',
    'Get-MSTRegistryValueState',
    'Set-MSTRegistryValue',
    'Remove-MSTRegistryValue',
    'Restore-MSTRegistryValueState'
)