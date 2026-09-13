Set-StrictMode -Version Latest

function Initialize-MSTLogging {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$LogDirectory
    )

    if (-not (Test-Path -LiteralPath $LogDirectory -PathType Container)) {
        New-Item `
            -ItemType Directory `
            -Path $LogDirectory `
            -Force `
            -ErrorAction Stop | Out-Null
    }

    $script:MSTLogDirectory = $LogDirectory
}

function Write-MSTLog {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateSet('Debug', 'Info', 'Warning', 'Error')]
        [string]$Level,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Message,

        [Parameter()]
        [AllowNull()]
        [hashtable]$Data
    )

    if (-not $script:MSTLogDirectory) {
        throw 'Logging has not been initialized. Call Initialize-MSTLogging first.'
    }

    $entry = [ordered]@{
        timestamp = (Get-Date).ToUniversalTime().ToString('o')
        level     = $Level
        message   = $Message
    }

    if ($null -ne $Data) {
        $entry.data = $Data
    }

    $json = [PSCustomObject]$entry |
        ConvertTo-Json -Compress -Depth 10

    $date = (Get-Date).ToString('yyyy-MM-dd')
    $logPath = Join-Path $script:MSTLogDirectory "$date.jsonl"

    Add-Content `
        -LiteralPath $logPath `
        -Value $json `
        -Encoding UTF8 `
        -ErrorAction Stop
}

function Get-MSTLog {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$LogDirectory,

        [Parameter()]
        [datetime]$Since
    )

    if (-not (Test-Path -LiteralPath $LogDirectory -PathType Container)) {
        return @()
    }

    $files = Get-ChildItem `
        -LiteralPath $LogDirectory `
        -Filter '*.jsonl' `
        -File `
        -ErrorAction Stop

    $entries = foreach ($file in $files) {
        foreach ($line in (Get-Content -LiteralPath $file.FullName -ErrorAction Stop)) {

            if ([string]::IsNullOrWhiteSpace($line)) {
                continue
            }

            try {
                $entry = $line | ConvertFrom-Json -ErrorAction Stop

                if (
                    $null -eq $Since -or
                    ([datetime]$entry.timestamp) -ge $Since
                ) {
                    $entry
                }
            }
            catch {
                # Ignore malformed entries so one bad line
                # does not prevent the remaining log from loading.
                continue
            }
        }
    }

    return $entries | Sort-Object -Property timestamp
}

Export-ModuleMember -Function @(
    'Initialize-MSTLogging',
    'Write-MSTLog',
    'Get-MSTLog'
)