$ErrorActionPreference = 'Stop'

Set-Location $PSScriptRoot

$imageExt = @('.avif', '.bmp', '.gif', '.jpg', '.jpeg', '.png', '.svg', '.webp')
$audioExt = @('.aac', '.flac', '.m4a', '.mp3', '.ogg', '.wav', '.webm')

function Normalize-Path([string]$path) {
    return ($path -replace '\\', '/').TrimStart('./')
}

function To-Relative([string]$fullPath) {
    $rootPath = Normalize-Path((Get-Location).Path).TrimEnd('/')
    $assetPath = Normalize-Path([System.IO.Path]::GetFullPath($fullPath))
    $rootPrefix = ($rootPath + '/').ToLowerInvariant()
    $assetLower = $assetPath.ToLowerInvariant()

    if ($assetLower.StartsWith($rootPrefix)) {
        return $assetPath.Substring($rootPrefix.Length)
    }

    return $assetPath
}

function Is-Image([string]$path) {
    $ext = [System.IO.Path]::GetExtension($path).ToLowerInvariant()
    return $imageExt -contains $ext
}

function Is-Audio([string]$path) {
    $ext = [System.IO.Path]::GetExtension($path).ToLowerInvariant()
    return $audioExt -contains $ext
}

function Segment-From-Name([string]$name) {
    $value = $name.ToLowerInvariant()
    if ($value.Contains('sunrise')) { return 'morning' }
    if ($value.Contains('morning')) { return 'morning' }
    if ($value.Contains('sunset') -or $value.Contains('evening')) { return 'sunset' }
    if ($value.Contains('night')) { return 'night' }
    if ($value.Contains('day')) { return 'day' }
    return $null
}

function Visual-Theme-From-Name([string]$name) {
    $value = $name.ToLowerInvariant()
    if ($value.Contains('severe')) { return 'severe' }
    if ($value.Contains('clear')) { return 'clear' }
    if ($value.Contains('sunrise') -or $value.Contains('morning')) { return 'sunrise' }
    if ($value.Contains('sunset') -or $value.Contains('evening')) { return 'sunset' }
    if ($value.Contains('night')) { return 'night' }
    if ($value.Contains('day')) { return 'day' }
    if ($value.Contains('rain')) { return 'rain' }
    if ($value -match '(storm|thunder|squall)') { return 'storm' }
    if ($value -match '(fog|haze|mist|smoke)') { return 'fog' }
    if ($value -match '(snow|blizzard|flurr)') { return 'snow' }
    if ($value.Contains('cloud')) { return 'cloudy' }
    return $null
}

function Severe-Theme-From-Name([string]$name) {
    $value = $name.ToLowerInvariant()
    if ($value -match '(tornado emergency|tornado warning|tornado)') { return 'tornado' }
    if ($value -match '(hurricane warning|tropical storm warning|hurricane|tropical storm)') { return 'hurricane' }
    if ($value -match '(coastal flood warning|flash flood warning|river flood warning|storm surge warning|flood)') { return 'flood' }
    if ($value -match '(high wind warning|extreme wind warning|gale warning|hurricane force wind warning|special marine warning|wind)') { return 'wind' }
    if ($value -match '(blizzard warning|winter storm warning|ice storm warning|snow squall warning|freeze warning|extreme cold warning|snow|blizzard|ice storm)') { return 'snow' }
    if ($value -match '(red flag warning|red flag|fire)') { return 'fire' }
    return $null
}

function Visual-Theme-From-Bucket([string]$bucket) {
    $value = $bucket.ToLowerInvariant()
    if ($value -eq 'rainy') { return 'rain' }
    if ($value -eq 'stormy') { return 'storm' }
    if ($value -eq 'foggy') { return 'fog' }
    if ($value -eq 'snowy') { return 'snow' }
    if ($value -eq 'cloudy') { return 'cloudy' }
    return $null
}

function Add-Theme-Paths([System.Collections.IDictionary]$themeState, [string]$themeKey, [string[]]$paths) {
    if (-not $themeState.Contains($themeKey)) { return }
    if (-not $paths) { return }

    $existing = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($path in $themeState[$themeKey]) {
        [void]$existing.Add($path)
    }

    foreach ($path in $paths) {
        if (Is-Image $path) {
            [void]$existing.Add($path)
        }
    }

    $themeState[$themeKey] = @($existing)
}

function Add-Severe-Theme-Paths([System.Collections.IDictionary]$themeState, [string]$categoryKey, [string[]]$paths) {
    if (-not $themeState.Contains('severe')) { return }
    if (-not $paths) { return }

    $severeState = $themeState['severe']
    if (-not ($severeState -is [System.Collections.IDictionary])) { return }

    $normalizedCategory = 'general'
    if (@('general', 'snow', 'fire', 'wind', 'storm', 'heat', 'tornado', 'hurricane', 'flood') -contains $categoryKey) {
        $normalizedCategory = $categoryKey
    }
    $existing = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($path in $severeState[$normalizedCategory]) {
        [void]$existing.Add($path)
    }

    foreach ($path in $paths) {
        if (Is-Image $path) {
            [void]$existing.Add($path)
        }
    }

    $severeState[$normalizedCategory] = @($existing)
}

function Condition-Bucket([string]$name) {
    $value = $name.ToLowerInvariant()
    if ($value -match '(snow|blizzard|flurr)') { return 'snowy' }
    if ($value -match '(thunder|storm|squall)') { return 'stormy' }
    if ($value -match '(freezing rain|drizzle|rain|shower)') { return 'rainy' }
    if ($value -match '(fog|haze|smoke|mist)') { return 'foggy' }
    if ($value -match '(cloud|overcast)') { return 'cloudy' }
    return 'sunny'
}

function Season-From-Name([string]$name) {
    $value = $name.ToLowerInvariant()
    if ($value.Contains('spring')) { return 'spring' }
    if ($value.Contains('summer')) { return 'summer' }
    if ($value.Contains('fall') -or $value.Contains('autumn')) { return 'fall' }
    if ($value.Contains('winter')) { return 'winter' }
    return $null
}

$manifest = [ordered]@{
    marineImages = @()
    winterImages = @()
    music = [ordered]@{
        normal = @()
        warning = @()
        welcome = @()
    }
    backgrounds = [ordered]@{
        morning = [ordered]@{ folderPath = ''; direct = @(); byCondition = [ordered]@{} }
        day = [ordered]@{ folderPath = ''; direct = @(); byCondition = [ordered]@{} }
        sunset = [ordered]@{ folderPath = ''; direct = @(); byCondition = [ordered]@{} }
        night = [ordered]@{ folderPath = ''; direct = @(); byCondition = [ordered]@{} }
    }
    backgroundThemes = [ordered]@{
        sunrise = @()
        day = @()
        sunset = @()
        rain = @()
        cloudy = @()
        storm = @()
        fog = @()
        snow = @()
        night = @()
        severe = [ordered]@{
            general = @()
            snow = @()
            fire = @()
            wind = @()
            storm = @()
            heat = @()
            tornado = @()
            hurricane = @()
            flood = @()
        }
    }
    welcome = [ordered]@{
        morning = [ordered]@{ folderPath = ''; direct = @(); bySeason = [ordered]@{} }
        day = [ordered]@{ folderPath = ''; direct = @(); bySeason = [ordered]@{} }
        sunset = [ordered]@{ folderPath = ''; direct = @(); bySeason = [ordered]@{} }
        night = [ordered]@{ folderPath = ''; direct = @(); bySeason = [ordered]@{} }
    }
}

if (Test-Path 'marine') {
    $manifest.marineImages = @(
        Get-ChildItem 'marine' -File |
        ForEach-Object { To-Relative $_.FullName } |
        Where-Object { Is-Image $_ }
    )
}

if (Test-Path 'winter') {
    $manifest.winterImages = @(
        Get-ChildItem 'winter' -Recurse -File |
        ForEach-Object { To-Relative $_.FullName } |
        Where-Object { Is-Image $_ }
    )
}

foreach ($mode in @('normal', 'warning', 'welcome')) {
    $folder = "music/$mode"
    if (Test-Path $folder) {
        $manifest.music[$mode] = @(
            Get-ChildItem $folder -File |
            ForEach-Object { To-Relative $_.FullName } |
            Where-Object { Is-Audio $_ }
        )
    }
}

if (Test-Path 'Backgrounds') {
    foreach ($rootFolder in Get-ChildItem 'Backgrounds' -Directory) {
        $rootVisualTheme = Visual-Theme-From-Name $rootFolder.Name

        if ($rootVisualTheme -eq 'clear') {
            $clearChildren = Get-ChildItem $rootFolder.FullName
            foreach ($timeFolder in $clearChildren | Where-Object { $_.PSIsContainer }) {
                $segmentKey = Segment-From-Name $timeFolder.Name
                if (-not $segmentKey) { continue }

                $timeTheme = Visual-Theme-From-Name $timeFolder.Name
                if (-not $timeTheme) { continue }

                $segmentState = $manifest.backgrounds[$segmentKey]
                $segmentState.folderPath = To-Relative $timeFolder.FullName
                $timeFiles = @(
                    Get-ChildItem $timeFolder.FullName -File |
                    ForEach-Object { To-Relative $_.FullName } |
                    Where-Object { Is-Image $_ }
                )

                $segmentState.direct += $timeFiles
                Add-Theme-Paths $manifest.backgroundThemes $timeTheme $timeFiles
            }

            $clearDirect = @(
                $clearChildren |
                Where-Object { -not $_.PSIsContainer } |
                ForEach-Object { To-Relative $_.FullName } |
                Where-Object { Is-Image $_ }
            )
            Add-Theme-Paths $manifest.backgroundThemes 'day' $clearDirect
            continue
        }

        if ($rootVisualTheme -eq 'severe') {
            $severeChildren = Get-ChildItem $rootFolder.FullName
            $severeDirect = @(
                $severeChildren |
                Where-Object { -not $_.PSIsContainer } |
                ForEach-Object { To-Relative $_.FullName } |
                Where-Object { Is-Image $_ }
            )
            Add-Severe-Theme-Paths $manifest.backgroundThemes 'general' $severeDirect

            foreach ($severeFolder in $severeChildren | Where-Object { $_.PSIsContainer }) {
                $severeCategory = Severe-Theme-From-Name $severeFolder.Name
                if (-not $severeCategory) { continue }
                $severeFiles = @(
                    Get-ChildItem $severeFolder.FullName -Recurse -File |
                    ForEach-Object { To-Relative $_.FullName } |
                    Where-Object { Is-Image $_ }
                )
                Add-Severe-Theme-Paths $manifest.backgroundThemes $severeCategory $severeFiles
            }

            continue
        }

        if ($rootVisualTheme -and $rootVisualTheme -ne 'day' -and $rootVisualTheme -ne 'sunrise' -and $rootVisualTheme -ne 'sunset' -and $rootVisualTheme -ne 'night') {
            $weatherFiles = @(
                Get-ChildItem $rootFolder.FullName -Recurse -File |
                ForEach-Object { To-Relative $_.FullName } |
                Where-Object { Is-Image $_ }
            )
            Add-Theme-Paths $manifest.backgroundThemes $rootVisualTheme $weatherFiles
            continue
        }

        $segmentKey = Segment-From-Name $rootFolder.Name
        if (-not $segmentKey) { continue }

        $segmentState = $manifest.backgrounds[$segmentKey]
        $segmentState.folderPath = To-Relative $rootFolder.FullName

        $children = Get-ChildItem $rootFolder.FullName
        $segmentState.direct = @(
            $children |
            Where-Object { -not $_.PSIsContainer } |
            ForEach-Object { To-Relative $_.FullName } |
            Where-Object { Is-Image $_ }
        )
        $timeTheme = Visual-Theme-From-Name $rootFolder.Name
        if ($timeTheme) {
            Add-Theme-Paths $manifest.backgroundThemes $timeTheme $segmentState.direct
        }

        foreach ($conditionFolder in $children | Where-Object { $_.PSIsContainer }) {
            $bucket = Condition-Bucket $conditionFolder.Name
            $files = @(
                Get-ChildItem $conditionFolder.FullName -File |
                ForEach-Object { To-Relative $_.FullName } |
                Where-Object { Is-Image $_ }
            )

            if (-not $segmentState.byCondition.Contains($bucket)) {
                $segmentState.byCondition[$bucket] = @()
            }

            $segmentState.byCondition[$bucket] += $files
            $weatherTheme = Visual-Theme-From-Bucket $bucket
            if ($weatherTheme) {
                Add-Theme-Paths $manifest.backgroundThemes $weatherTheme $files
            }
        }
    }
}

if (Test-Path 'Welcome') {
    foreach ($segmentFolder in Get-ChildItem 'Welcome' -Directory) {
        $segmentKey = Segment-From-Name $segmentFolder.Name
        if (-not $segmentKey) { continue }

        $segmentState = $manifest.welcome[$segmentKey]
        $segmentState.folderPath = To-Relative $segmentFolder.FullName

        $children = Get-ChildItem $segmentFolder.FullName
        $segmentState.direct = @(
            $children |
            Where-Object { -not $_.PSIsContainer } |
            ForEach-Object { To-Relative $_.FullName } |
            Where-Object { Is-Image $_ }
        )

        foreach ($seasonFolder in $children | Where-Object { $_.PSIsContainer }) {
            $seasonKey = Season-From-Name $seasonFolder.Name
            if (-not $seasonKey) { continue }

            $files = @(
                Get-ChildItem $seasonFolder.FullName -File |
                ForEach-Object { To-Relative $_.FullName } |
                Where-Object { Is-Image $_ }
            )

            if (-not $segmentState.bySeason.Contains($seasonKey)) {
                $segmentState.bySeason[$seasonKey] = @()
            }

            $segmentState.bySeason[$seasonKey] += $files
        }
    }
}

$manifest | ConvertTo-Json -Depth 10 | Set-Content 'assets-manifest.json' -Encoding UTF8
Write-Host 'Updated assets-manifest.json'
