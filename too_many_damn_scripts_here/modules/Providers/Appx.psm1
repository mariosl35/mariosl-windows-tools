Set-StrictMode -Version Latest

function Get-MSTAppxPackage {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Name
    )

    try {
        $Packages = @(
            Get-AppxPackage `
                -Name $Name `
                -ErrorAction Stop
        )

        if ($Packages.Count -eq 0) {
            return $null
        }

        if ($Packages.Count -gt 1) {
            throw "Multiple AppX packages matched '$Name'."
        }

        return $Packages[0]
    }
    catch {
        throw "Failed to query AppX package '$Name': $($_.Exception.Message)"
    }
}


function Get-MSTAppxPackageState {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Name
    )

    $Package = Get-MSTAppxPackage -Name $Name

    if ($null -eq $Package) {
        return [PSCustomObject]@{
            exists           = $false
            name             = $Name
            packageFullName  = $null
            version          = $null
            publisher        = $null
            installLocation  = $null
        }
    }

    return [PSCustomObject]@{
        exists           = $true
        name             = [string]$Package.Name
        packageFullName  = [string]$Package.PackageFullName
        version          = [string]$Package.Version
        publisher        = [string]$Package.Publisher
        installLocation  = [string]$Package.InstallLocation
    }
}


function Remove-MSTAppxPackage {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Name
    )

    $Package = Get-MSTAppxPackage -Name $Name

    if ($null -eq $Package) {
        return [PSCustomObject]@{
            success = $true
            changed = $false
            name    = $Name
        }
    }

    try {
        Remove-AppxPackage `
            -Package $Package.PackageFullName `
            -ErrorAction Stop

        return [PSCustomObject]@{
            success = $true
            changed = $true
            name    = [string]$Package.Name
        }
    }
    catch {
        throw "Failed to remove AppX package '$Name': $($_.Exception.Message)"
    }
}


Export-ModuleMember -Function @(
    'Get-MSTAppxPackage'
    'Get-MSTAppxPackageState'
    'Remove-MSTAppxPackage'
)