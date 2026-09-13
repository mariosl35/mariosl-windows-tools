Set-StrictMode -Version Latest

function Get-MSTServiceState {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Name
    )

    try {
        $service = Get-CimInstance `
            -ClassName Win32_Service `
            -Filter "Name='$Name'" `
            -ErrorAction Stop
    }
    catch {
        throw "Failed to query service '$Name': $($_.Exception.Message)"
    }

    if ($null -eq $service) {
        return [PSCustomObject]@{
            provider    = 'service'
            name        = $Name
            displayName = $null
            exists      = $false
            startMode   = $null
            state       = $null
        }
    }

    return [PSCustomObject]@{
        provider    = 'service'
        name        = [string]$service.Name
        displayName = [string]$service.DisplayName
        exists      = $true
        startMode   = [string]$service.StartMode
        state       = [string]$service.State
    }
}

function Set-MSTServiceState {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [ValidateSet(
            'Automatic',
            'Manual',
            'Disabled'
        )]
        [string]$StartMode
    )

$service = Get-Service `
    -Name $Name `
    -ErrorAction SilentlyContinue

if ($null -eq $service) {
    return [PSCustomObject]@{
        success = $true
        changed = $false
        exists  = $false
        name    = $Name
    }
}

    try {
        Set-Service `
            -Name $Name `
            -StartupType $StartMode `
            -ErrorAction Stop
    }
    catch {
        throw "Failed to set startup mode for service '$Name' to '$StartMode': $($_.Exception.Message)"
    }
}

function Restore-MSTServiceState {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [object]$State
    )

    if ($State.provider -ne 'service') {
        throw 'Invalid state provider. Expected service state.'
    }

    if (-not $State.exists) {
        return
    }

    if ([string]::IsNullOrWhiteSpace([string]$State.name)) {
        throw 'Service state does not contain a service name.'
    }

$restoreStartMode = switch ([string]$State.startMode) {
    'Auto' {
        'Automatic'
    }

    'Automatic' {
        'Automatic'
    }

    'Manual' {
        'Manual'
    }

    'Disabled' {
        'Disabled'
    }

    default {
        throw "Unsupported original service startup mode '$($State.startMode)'."
    }
}

    try {
        Get-Service `
            -Name $State.name `
            -ErrorAction Stop | Out-Null
    }
    catch {
        throw "Service '$($State.name)' no longer exists."
    }

    try {
        Set-Service `
            -Name $State.name `
            -StartupType $restoreStartMode `
            -ErrorAction Stop
    }
    catch {
        throw "Failed to restore startup mode for service '$($State.name)' to '$($State.startMode)': $($_.Exception.Message)"
    }
}

function Test-MSTServiceState {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [object]$State,

        [Parameter(Mandatory = $true)]
        [ValidateSet(
            'Automatic',
            'Manual',
            'Disabled'
        )]
        [string]$ExpectedStartMode
    )

    if ($State.provider -ne 'service') {
        throw 'Invalid state provider. Expected service state.'
    }

    $current = Get-MSTServiceState -Name $State.name

    $normalizedStartMode = switch ($current.startMode) {
        'Auto' {
            'Automatic'
        }

        'Manual' {
            'Manual'
        }

        'Disabled' {
            'Disabled'
        }

        default {
            throw "Unsupported service startup mode '$($current.startMode)'."
        }
    }

    return (
        $normalizedStartMode -eq $ExpectedStartMode
    )
}

Export-ModuleMember -Function @(
    'Get-MSTServiceState',
    'Set-MSTServiceState',
    'Restore-MSTServiceState',
    'Test-MSTServiceState'
)