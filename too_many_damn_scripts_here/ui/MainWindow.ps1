Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------

$UiRoot      = $PSScriptRoot
$ProjectRoot = Split-Path -Parent $UiRoot

$CoreRoot     = Join-Path $ProjectRoot 'modules\Core'
$ConfigRoot   = Join-Path $ProjectRoot 'config'
$ProviderRoot = Join-Path $ProjectRoot 'modules\Providers'

$BackupDirectory = Join-Path $ProjectRoot 'backups'

$XamlPath = Join-Path $UiRoot 'MainWindow.xaml'

# ---------------------------------------------------------------------------
# Validate required files
# ---------------------------------------------------------------------------

$RequiredFiles = @(
    (Join-Path $CoreRoot 'Config.psm1'),
    (Join-Path $CoreRoot 'StateStore.psm1'),
    (Join-Path $CoreRoot 'Engine.psm1'),
    (Join-Path $ProviderRoot 'Registry.psm1'),
    (Join-Path $ProviderRoot 'Services.psm1'),
	(Join-Path $ProviderRoot 'SystemRestore.psm1')
)

foreach ($File in $RequiredFiles) {
    if (-not (Test-Path -LiteralPath $File -PathType Leaf)) {
        throw "Required module not found: $File"
    }
}

if (-not (Test-Path -LiteralPath $XamlPath -PathType Leaf)) {
    throw "MainWindow.xaml not found: $XamlPath"
}

# ---------------------------------------------------------------------------
# Load backend
# ---------------------------------------------------------------------------

Import-Module `
    (Join-Path $CoreRoot 'Config.psm1') `
    -Force `
    -ErrorAction Stop

Import-Module `
    (Join-Path $CoreRoot 'StateStore.psm1') `
    -Force `
    -ErrorAction Stop

Import-Module `
    (Join-Path $CoreRoot 'Engine.psm1') `
    -Force `
    -ErrorAction Stop
	
Import-Module `
    (Join-Path $ProviderRoot 'SystemRestore.psm1') `
    -Force `
    -ErrorAction Stop

# ---------------------------------------------------------------------------
# Initialize backend infrastructure
# ---------------------------------------------------------------------------

$ToolVersion = '0.1.0-dev'

Initialize-MSTEngine `
    -ToolVersion $ToolVersion `
    -BackupDirectory $BackupDirectory `


# ---------------------------------------------------------------------------
# Load XAML
# ---------------------------------------------------------------------------

try {
    [xml]$Xaml = Get-Content `
        -LiteralPath $XamlPath `
        -Raw `
        -ErrorAction Stop

    $Reader = New-Object System.Xml.XmlNodeReader($Xaml)

    $Window = [Windows.Markup.XamlReader]::Load($Reader)
}
catch {
    throw "Failed to load MainWindow.xaml: $($_.Exception.Message)"
}

if ($null -eq $Window) {
    throw 'Failed to create the main WPF window.'
}

# ---------------------------------------------------------------------------
# Find controls
# ---------------------------------------------------------------------------

$DragRegion         = $Window.FindName('DragRegion')
$CloseButton = $Window.FindName('CloseButton')

$ThemeButton        = $Window.FindName('ThemeButton')
$MoonIcon           = $Window.FindName('MoonIcon')
$SunIcon            = $Window.FindName('SunIcon')

$AppsTab            = $Window.FindName('AppsTab')
$RegistryTab        = $Window.FindName('RegistryTab')
$WindowsAITab            = $Window.FindName('WindowsAITab')
$TabIndicator       = $Window.FindName('TabIndicator')

$SectionTitle       = $Window.FindName('SectionTitle')
$SectionDescription = $Window.FindName('SectionDescription')

$AppsContent        = $Window.FindName('AppsContent')
$RegistryContent    = $Window.FindName('RegistryContent')
$WindowsAIContent        = $Window.FindName('WindowsAIContent')

$AppsTweakList      = $Window.FindName('AppsTweakList')
$RegistryTweakList  = $Window.FindName('RegistryTweakList')
$WindowsAITweakList      = $Window.FindName('WindowsAITweakList')

$SystemRestoreCheckbox = $Window.FindName('SystemRestoreCheckbox')
$ActionButton       = $Window.FindName('ActionButton')

# ---------------------------------------------------------------------------
# Window top bar
# ---------------------------------------------------------------------------

$DragRegion.Add_MouseLeftButtonDown({
    param($sender, $e)

    if ($e.ButtonState -eq 'Pressed') {
        $Window.DragMove()
    }
})

$CloseButton.Add_Click({
    $Window.Close()
})

# ---------------------------------------------------------------------------
# Load test tweaks
# ---------------------------------------------------------------------------

$Tweaks = Get-MSTTweakConfigs `
    -ConfigDirectory $ConfigRoot

foreach ($Tweak in $Tweaks) {

    Test-MSTTweakDefinition `
        -Tweak $Tweak |
        Out-Null
}

# ---------------------------------------------------------------------------
# Theme
# ---------------------------------------------------------------------------

$script:IsDarkTheme = $true

function Set-MSTTheme {
    param (
        [Parameter(Mandatory = $true)]
        [bool]$Dark
    )

    $BrushConverter = [Windows.Media.BrushConverter]::new()

    if ($Dark) {

        $Window.Resources['WindowBackgroundBrush'] =
            $BrushConverter.ConvertFromString('#0A0C0B')

        $Window.Resources['SurfaceBrush'] =
            $BrushConverter.ConvertFromString('#0D100E')

        $Window.Resources['PrimaryTextBrush'] =
            $BrushConverter.ConvertFromString('#E8EEE9')

        $Window.Resources['SecondaryTextBrush'] =
            $BrushConverter.ConvertFromString('#69756D')

        $Window.Resources['MutedTextBrush'] =
            $BrushConverter.ConvertFromString('#59645D')

        $Window.Resources['BorderBrush'] =
            $BrushConverter.ConvertFromString('#202722')

        $Window.Resources['AccentBrush'] =
            $BrushConverter.ConvertFromString('#7FD99A')

        $Window.Resources['ButtonBackgroundBrush'] =
            $BrushConverter.ConvertFromString('#151A17')

        $Window.Resources['ButtonBorderBrush'] =
            $BrushConverter.ConvertFromString('#242C27')

        $MoonIcon.Visibility = [Windows.Visibility]::Visible
        $SunIcon.Visibility = [Windows.Visibility]::Collapsed
    }
    else {

        $Window.Resources['WindowBackgroundBrush'] =
            $BrushConverter.ConvertFromString('#F2F5F3')

        $Window.Resources['SurfaceBrush'] =
            $BrushConverter.ConvertFromString('#E7ECE9')

        $Window.Resources['PrimaryTextBrush'] =
            $BrushConverter.ConvertFromString('#172019')

        $Window.Resources['SecondaryTextBrush'] =
            $BrushConverter.ConvertFromString('#526158')

        $Window.Resources['MutedTextBrush'] =
            $BrushConverter.ConvertFromString('#68756D')

        $Window.Resources['BorderBrush'] =
            $BrushConverter.ConvertFromString('#CBD4CE')

        $Window.Resources['AccentBrush'] =
            $BrushConverter.ConvertFromString('#3E9B5F')

        $Window.Resources['ButtonBackgroundBrush'] =
            $BrushConverter.ConvertFromString('#DCE4DF')

        $Window.Resources['ButtonBorderBrush'] =
            $BrushConverter.ConvertFromString('#B9C6BD')

        $MoonIcon.Visibility = [Windows.Visibility]::Collapsed
        $SunIcon.Visibility = [Windows.Visibility]::Visible
    }

    $script:IsDarkTheme = $Dark
}

$ThemeButton.Add_Click({
    Set-MSTTheme -Dark (-not $script:IsDarkTheme)
})

# ---------------------------------------------------------------------------
# Tab state
# ---------------------------------------------------------------------------

function Set-MSTTab {
    param (
        [ValidateSet('Apps', 'Registry', 'WindowsAI')]
        [string]$Tab
    )

    $AppsContent.Visibility =
        [Windows.Visibility]::Collapsed

    $RegistryContent.Visibility =
        [Windows.Visibility]::Collapsed

    $WindowsAIContent.Visibility =
        [Windows.Visibility]::Collapsed

    $AppsTab.Foreground =
        $Window.Resources['SecondaryTextBrush']

    $RegistryTab.Foreground =
        $Window.Resources['SecondaryTextBrush']

    $WindowsAITab.Foreground =
        $Window.Resources['SecondaryTextBrush']

    switch ($Tab) {

        'Apps' {

            $AppsContent.Visibility =
                [Windows.Visibility]::Visible

            $SectionTitle.Text = 'WINDOWS APPS'

            $SectionDescription.Text =
                'Remove applications you don''t need.'

            $TabIndicator.SetValue(
                [Windows.Controls.Grid]::ColumnProperty,
                0
            )

            $AppsTab.Foreground =
                $Window.Resources['AccentBrush']
        }

        'Registry' {

            $RegistryContent.Visibility =
                [Windows.Visibility]::Visible

            $SectionTitle.Text = 'REGISTRY'

            $SectionDescription.Text =
                'Change Windows settings and behavior.'

            $TabIndicator.SetValue(
                [Windows.Controls.Grid]::ColumnProperty,
                1
            )

            $RegistryTab.Foreground =
                $Window.Resources['AccentBrush']
        }

        'WindowsAI' {

            $WindowsAIContent.Visibility =
                [Windows.Visibility]::Visible

            $SectionTitle.Text = 'WINDOWS AI'

            $SectionDescription.Text =
                'Disable or remove Windows AI features.'

            $TabIndicator.SetValue(
                [Windows.Controls.Grid]::ColumnProperty,
                2
            )

            $WindowsAITab.Foreground =
                $Window.Resources['AccentBrush']
        }
    }
}

$AppsTab.Add_Click({
    Set-MSTTab -Tab 'Apps'
})

$RegistryTab.Add_Click({
    Set-MSTTab -Tab 'Registry'
})

$WindowsAITab.Add_Click({
    Set-MSTTab -Tab 'WindowsAI'
})

# ---------------------------------------------------------------------------
# Selection state
# ---------------------------------------------------------------------------

$script:SelectedTweaks = New-Object System.Collections.ArrayList

$AppsTweakList.Children.Clear()
$RegistryTweakList.Children.Clear()
$WindowsAITweakList.Children.Clear()

foreach ($Tweak in $Tweaks) {

    $Targets = @(
        Get-MSTTweakTargets -Tweak $Tweak
    )

    $TargetTypes = @(
        $Targets |
            ForEach-Object {
                [string]$_.type
            } |
            Select-Object -Unique
    )

if ([string]$Tweak.category -eq 'Windows AI') {
    $TargetList = $WindowsAITweakList
}
elseif ($TargetTypes.Count -eq 1 -and $TargetTypes[0] -eq 'appxPackage') {
    $TargetList = $AppsTweakList
}
elseif ($TargetTypes.Count -eq 1 -and $TargetTypes[0] -eq 'registry') {
    $TargetList = $RegistryTweakList
}
else {
    $TargetList = $WindowsAITweakList
}

    $Border = New-Object System.Windows.Controls.Border

    $Border.BorderBrush =
        $Window.Resources['BorderBrush']

    $Border.BorderThickness =
        [Windows.Thickness]::new(0, 1, 0, 0)

    $Border.Padding =
        [Windows.Thickness]::new(0, 15, 0, 15)


    $Grid = New-Object System.Windows.Controls.Grid

    $ColumnMain = New-Object System.Windows.Controls.ColumnDefinition
    $ColumnMain.Width = '*'

    $ColumnRisk = New-Object System.Windows.Controls.ColumnDefinition
    $ColumnRisk.Width = 'Auto'

    [void]$Grid.ColumnDefinitions.Add($ColumnMain)
    [void]$Grid.ColumnDefinitions.Add($ColumnRisk)


$Stack = New-Object System.Windows.Controls.StackPanel

$Stack.HorizontalAlignment =
    [Windows.HorizontalAlignment]::Stretch


$Checkbox = New-Object System.Windows.Controls.CheckBox

$Checkbox.Content =
    $Tweak.displayName

$Checkbox.Style =
    $Window.Resources['MarioslCheckBox']


$Description = New-Object System.Windows.Controls.TextBlock

$Description.Text =
    $Tweak.description

$Description.Margin =
    [Windows.Thickness]::new(26, 5, 30, 0)

$Description.FontSize = 12

$Description.Foreground =
    $Window.Resources['MutedTextBrush']

$Description.TextWrapping =
    [Windows.TextWrapping]::Wrap


[void]$Stack.Children.Add($Checkbox)
[void]$Stack.Children.Add($Description)


    $Risk = New-Object System.Windows.Controls.TextBlock

    $Risk.Text =
        "$($Tweak.riskLevel.ToUpper()) RISK"

    $Risk.VerticalAlignment =
        [Windows.VerticalAlignment]::Top

    $Risk.FontSize = 9

    $Risk.Foreground =
        $Window.Resources['SecondaryTextBrush']

    $Risk.Margin =
        [Windows.Thickness]::new(20, 3, 4, 0)


    [void]$Grid.Children.Add($Stack)
    [void]$Grid.Children.Add($Risk)

    [Windows.Controls.Grid]::SetColumn(
        $Risk,
        1
    )

    $Border.Child = $Grid

    [void]$TargetList.Children.Add($Border)


    $Checkbox.Add_Checked({

        if (-not $script:SelectedTweaks.Contains($Tweak)) {
            [void]$script:SelectedTweaks.Add($Tweak)
        }

        $ActionButton.IsEnabled = $true

        $ActionButton.Content =
            'JUST DEBLOAT ME ALREADY~'

        $ActionButton.Foreground =
            $Window.Resources['AccentBrush']

    }.GetNewClosure())


    $Checkbox.Add_Unchecked({

        [void]$script:SelectedTweaks.Remove($Tweak)

        if ($script:SelectedTweaks.Count -eq 0) {

            $ActionButton.IsEnabled = $false

            $ActionButton.Content =
                'SELECT SOMETHING'

            $ActionButton.Foreground =
                $Window.Resources['SecondaryTextBrush']
        }

    }.GetNewClosure())
}

# ---------------------------------------------------------------------------
# Execute selected tweaks
# ---------------------------------------------------------------------------

$ActionButton.Add_Click({

    if ($script:SelectedTweaks.Count -eq 0) {
        return
    }


    $ActionButton.IsEnabled = $false
$AppsTweakList.IsEnabled = $false
$RegistryTweakList.IsEnabled = $false
$WindowsAITweakList.IsEnabled = $false

    $ActionButton.Content = 'APPLYING...'

    $UseSystemRestore =
        $SystemRestoreCheckbox.IsChecked -eq $true

    try {

$Results = @(
    Invoke-MSTBatch `
        -Tweaks $script:SelectedTweaks `
        -CreateSystemRestorePoint $UseSystemRestore
)


        if ($Results.Count -eq 0) {
            throw 'The engine returned no tweak results.'
        }

        $FailedResults = @(
            $Results | Where-Object {
                -not $_.success
            }
        )

        if ($FailedResults.Count -gt 0) {

            throw @(
                'One or more tweaks failed.'
                ''
                ($FailedResults | ForEach-Object {
                    $_.message
                })
            ) -join "`n"
        }


        $ChangedResults = @(
            $Results | Where-Object {
                $_.changed
            }
        )


        if ($ChangedResults.Count -gt 0) {

            $ActionButton.Content =
                'APPLIED'

            $ActionButton.Foreground =
                $Window.Resources['AccentBrush']


            $Snapshots = (
                $ChangedResults | ForEach-Object {
                    $_.snapshot
                }
            ) -join "`n"


            [System.Windows.MessageBox]::Show(
                "The selected tweaks were applied and verified.`n`nSnapshots:`n$Snapshots",
                'MARIOSL35 Windows Tools',
                [System.Windows.MessageBoxButton]::OK,
                [System.Windows.MessageBoxImage]::Information
            ) | Out-Null
        }
        else {

            $ActionButton.Content =
                'ALREADY APPLIED'


            [System.Windows.MessageBox]::Show(
                "All selected tweaks are already in their desired state.",
                'MARIOSL35 Windows Tools',
                [System.Windows.MessageBoxButton]::OK,
                [System.Windows.MessageBoxImage]::Information
            ) | Out-Null
        }

    }
    catch {

        $ActionButton.Content =
            'FAILED'

        $ActionButton.Foreground =
            $Window.Resources['SecondaryTextBrush']


        [System.Windows.MessageBox]::Show(
            $_.Exception.Message,
            'MARIOSL35 Windows Tools — Error',
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Error
        ) | Out-Null
    }
    finally {

$AppsTweakList.IsEnabled = $true
$RegistryTweakList.IsEnabled = $true
$WindowsAITweakList.IsEnabled = $true

        if ($script:SelectedTweaks.Count -gt 0) {
            $ActionButton.IsEnabled = $true
        }
    }
})

# ---------------------------------------------------------------------------
# Initial state
# ---------------------------------------------------------------------------

Set-MSTTheme -Dark $true
Set-MSTTab -Tab 'Apps'

# ---------------------------------------------------------------------------
# Show window
# ---------------------------------------------------------------------------

$Window.ShowDialog() | Out-Null