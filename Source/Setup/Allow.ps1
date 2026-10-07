#Requires -Version 5.1
param(
    [Parameter(Mandatory = $true)]
    [string]$RepoRoot,

    [string[]]$Path = @(),

    [switch]$Quiet
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-CleanPath {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return $null }
    return [System.IO.Path]::GetFullPath($Value).TrimEnd("\")
}

function Test-Listed {
    param($Existing, [string]$Value)
    $norm = $Value.TrimEnd("\")
    foreach ($item in @($Existing)) {
        if ($item -and ([string]$item).TrimEnd("\") -ieq $norm) { return $true }
    }
    return $false
}

function Find-SkateRoots {
    $hits = New-Object System.Collections.Generic.List[string]
    $rels = @(
        "Steam\steamapps\common\Skate",
        "Program Files (x86)\Steam\steamapps\common\Skate",
        "Program Files\Steam\steamapps\common\Skate"
    )
    $letters = New-Object System.Collections.Generic.List[string]
    foreach ($disk in [System.IO.DriveInfo]::GetDrives()) {
        if ($disk.DriveType -ne [System.IO.DriveType]::Fixed -or -not $disk.IsReady) { continue }
        $letters.Add($disk.Name.Substring(0, 1))
    }
    foreach ($letter in ($letters | Select-Object -Unique)) {
        foreach ($rel in $rels) {
            $candidate = "{0}:\{1}" -f $letter, $rel
            if (Test-Path -LiteralPath (Join-Path $candidate "Skate.exe")) {
                $full = Get-CleanPath $candidate
                if ($full) { Add-Wanted $hits $full }
            }
        }
    }
    return $hits
}

function Add-Wanted {
    param($List, [string]$Full)
    if (-not $Full) { return }
    foreach ($item in $List) {
        if ($item -ieq $Full) { return }
    }
    [void]$List.Add($Full)
}

if (-not (Test-Administrator)) {
    Write-Host "Press Yes to allow ReSkate through Windows Security."
    $cmd = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -RepoRoot `"$RepoRoot`""
    foreach ($item in @($Path)) {
        if ($item) { $cmd += " -Path `"$item`"" }
    }
    if ($Quiet) { $cmd += " -Quiet" }
    try {
        $proc = Start-Process `
            -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" `
            -Verb RunAs `
            -ArgumentList $cmd `
            -Wait `
            -PassThru
    }
    catch {
        exit 1223
    }
    if ($null -eq $proc -or $null -eq $proc.ExitCode) { exit 1 }
    exit $proc.ExitCode
}

$RepoRoot = Get-CleanPath $RepoRoot
if (-not $RepoRoot) { throw "The ReSkate folder path is missing." }

$wanted = New-Object System.Collections.Generic.List[string]
foreach ($item in @($RepoRoot) + @($Path) + @(Find-SkateRoots) + @(Join-Path $env:TEMP "ReSkateInstaller")) {
    $full = Get-CleanPath ([string]$item)
    if ($full) { Add-Wanted $wanted $full }
}

if (-not (Get-Command Get-MpPreference -ErrorAction SilentlyContinue)) {
    Write-Host "Windows Security is not available on this PC."
    if (-not $Quiet) { Start-Sleep -Seconds 3 }
    exit 2
}

try {
    $pref = Get-MpPreference
}
catch {
    Write-Host "Windows Security could not be changed."
    Write-Host $_.Exception.Message
    if (-not $Quiet) { Start-Sleep -Seconds 4 }
    exit 2
}

function Get-PrefList {
    param($Object, [string]$Name)
    $prop = $Object.PSObject.Properties[$Name]
    if (-not $prop) { return @() }
    return @($prop.Value)
}

$exclusionPaths = Get-PrefList $pref "ExclusionPath"
$exclusionProcesses = Get-PrefList $pref "ExclusionProcess"
$allowedApps = Get-PrefList $pref "ControlledFolderAccessAllowedApplications"

Write-Host "Allowing ReSkate through Windows Security"
foreach ($folder in $wanted) {
    Write-Host "  $folder"
    if (-not (Test-Listed $exclusionPaths $folder)) {
        Add-MpPreference -ExclusionPath $folder
    }
}

$processes = New-Object System.Collections.Generic.List[string]
[void]$processes.Add("ReSkateLauncher.exe")
foreach ($folder in $wanted) {
    foreach ($name in @("ReSkateLauncher.exe", "Skate.exe")) {
        $exe = Join-Path $folder $name
        $seen = $false
        foreach ($item in $processes) { if ($item -ieq $exe) { $seen = $true; break } }
        if ((Test-Path -LiteralPath $exe) -and -not $seen) {
            [void]$processes.Add($exe)
        }
    }
}
foreach ($image in $processes) {
    Write-Host "  $image"
    if (-not (Test-Listed $exclusionProcesses $image)) {
        Add-MpPreference -ExclusionProcess $image
    }
}
foreach ($image in $processes) {
    if (-not (Test-Path -LiteralPath $image)) { continue }
    if (-not (Test-Listed $allowedApps $image)) {
        try { Add-MpPreference -ControlledFolderAccessAllowedApplications $image }
        catch { Write-Host "  skipped controlled-folder entry for $image" }
    }
}

$settingsPath = Join-Path $RepoRoot "ReSkate.settings.json"
$payload = [ordered]@{ reskate = $false; mods = $false; allowed = @() }
if (Test-Path -LiteralPath $settingsPath) {
    try {
        $json = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json
        foreach ($key in @("reskate", "mods")) {
            $prop = $json.PSObject.Properties[$key]
            if ($prop) { $payload[$key] = [bool]$prop.Value }
        }
        $prev = $json.PSObject.Properties["allowed"]
        if ($prev) {
            foreach ($item in @($prev.Value)) {
                $full = Get-CleanPath ([string]$item)
                if ($full) { Add-Wanted $wanted $full }
            }
        }
    }
    catch {}
}
$payload.allowed = @($wanted)
$payload | ConvertTo-Json | Set-Content -LiteralPath $settingsPath -Encoding UTF8

Write-Host "Done."
if (-not $Quiet) { Start-Sleep -Seconds 2 }
exit 0
