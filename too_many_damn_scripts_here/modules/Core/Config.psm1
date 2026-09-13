Set-StrictMode -Version Latest

function Import-MSTConfig {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Configuration file not found: $Path"
    }

    try {
        $raw = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop

        if ([string]::IsNullOrWhiteSpace($raw)) {
            throw "Configuration file is empty."
        }

        $config = $raw | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "Failed to load configuration '$Path': $($_.Exception.Message)"
    }

    if ($null -eq $config) {
        throw "Configuration file '$Path' produced no configuration object."
    }

    return $config
}

function Get-MSTProjectRoot {
    [CmdletBinding()]
    param ()

    # Config.psm1 is located at:
    # <project root>\modules\Core\Config.psm1
    $coreDirectory = Split-Path -Parent $PSCommandPath
    $modulesDirectory = Split-Path -Parent $coreDirectory
    $projectRoot = Split-Path -Parent $modulesDirectory

    return $projectRoot
}

function Get-MSTTweakConfigs {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ConfigDirectory
    )

    if (-not (Test-Path -LiteralPath $ConfigDirectory -PathType Container)) {
        throw "Configuration directory not found: $ConfigDirectory"
    }

    $ConfigFiles = Get-ChildItem `
        -LiteralPath $ConfigDirectory `
        -Filter '*.json' `
        -File `
        -ErrorAction Stop

    if ($ConfigFiles.Count -eq 0) {
        throw "No configuration files found in: $ConfigDirectory"
    }

    $Tweaks = @()

    foreach ($ConfigFile in $ConfigFiles) {

        $Config = Import-MSTConfig `
            -Path $ConfigFile.FullName

        if ($Config -is [System.Array]) {

            foreach ($Tweak in $Config) {
                $Tweaks += $Tweak
            }

        }
        else {
            $Tweaks += $Config
        }
    }

    return $Tweaks
}

Export-ModuleMember -Function @(
    'Import-MSTConfig',
    'Get-MSTProjectRoot',
	'Get-MSTTweakConfigs'
)