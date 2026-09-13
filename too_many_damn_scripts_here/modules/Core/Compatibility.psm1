Set-StrictMode -Version Latest

function Get-MSTWindowsInfo {
    [CmdletBinding()]
    param ()

    try {
        $currentVersion = Get-ItemProperty `
            -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' `
            -ErrorAction Stop

        $osVersion = [Environment]::OSVersion.Version

        return [PSCustomObject]@{
            productName                 = [string]$currentVersion.ProductName
            displayVersion              = [string]$currentVersion.DisplayVersion
            currentBuild                = [string]$currentVersion.CurrentBuild
            ubr                         = [int]$currentVersion.UBR
            version                     = $osVersion.ToString()
            platform                    = [Environment]::OSVersion.Platform.ToString()
            processArchitecture         = if ([Environment]::Is64BitProcess) { 'x64' } else { 'x86' }
            operatingSystemArchitecture = if ([Environment]::Is64BitOperatingSystem) { 'x64' } else { 'x86' }

            warning = if (
                [int]$currentVersion.CurrentBuild -ge 22000 -and
                $currentVersion.ProductName -like 'Windows 10*'
            ) {
                'Windows reports a legacy Windows 10 product name despite running a Windows 11 build.'
            }
            else {
                $null
            }
        }
    }
    catch {
        throw "Failed to determine Windows information: $($_.Exception.Message)"
    }
}

function Get-MSTPowerShellInfo {
    [CmdletBinding()]
    param ()

    $version = $PSVersionTable.PSVersion

    return [PSCustomObject]@{
        versionMajor = $version.Major
        versionMinor = $version.Minor
        version      = $version.ToString()
        edition      = $PSVersionTable.PSEdition
    }
}

function Test-MSTWindowsCompatibility {
    [CmdletBinding()]
    param ()

    $windows = Get-MSTWindowsInfo

    $build = [int]$windows.currentBuild

    $isWindows11 = ($build -ge 22000)
    $is64Bit = ($windows.operatingSystemArchitecture -eq 'x64')

    $compatible = (
        $isWindows11 -and
        $is64Bit
    )

    return [PSCustomObject]@{
        compatible  = $compatible
        checks      = [PSCustomObject]@{
            windows11 = $isWindows11
            x64       = $is64Bit
        }
        windows     = $windows
    }
}

function Test-MSTPowerShellCompatibility {
    [CmdletBinding()]
    param ()

    $powershell = Get-MSTPowerShellInfo

    $isSupportedVersion = (
        $powershell.versionMajor -ge 5
    )

    $compatible = $isSupportedVersion

    return [PSCustomObject]@{
        compatible = $compatible

        checks = [PSCustomObject]@{
            minimumVersion = $isSupportedVersion
        }

        powershell = $powershell
    }
}

function Get-MSTSystemCompatibility {
    [CmdletBinding()]
    param ()

    $windowsCompatibility = Test-MSTWindowsCompatibility
    $powershellCompatibility = Test-MSTPowerShellCompatibility

    $compatible = (
        $windowsCompatibility.compatible -and
        $powershellCompatibility.compatible
    )

    return [PSCustomObject]@{
        compatible = $compatible

        windows = $windowsCompatibility
        powershell = $powershellCompatibility
    }
}

Export-ModuleMember -Function @(
    'Get-MSTWindowsInfo',
    'Get-MSTPowerShellInfo',
    'Test-MSTWindowsCompatibility',
    'Test-MSTPowerShellCompatibility',
    'Get-MSTSystemCompatibility'
)