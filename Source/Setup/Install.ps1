#Requires -Version 5.1
<#
    ReSkate Installer / Updater
    --------------------------------
    Provided By: Iron Will Interactive
    --------------------------------
    Entry: ReSkate.bat
    This file installs, updates, and switches ReSkate / Skate mode.
#>

param(
    [ValidateSet("All", "Install", "Update", "Check", "ReSkate", "Skate")]
    [string]$Action = "All",

    [string]$Drive,

    [string]$SkatePath,

    [switch]$Quiet
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
}
catch {
}

# ============================================================================
# CONFIGURATION
# ============================================================================

$AppName        = "ReSkate"
$Version        = "1.1.1"
$SkateRelativePath = "Steam\steamapps\common\Skate"
$LatestApiUrl   = "https://api.github.com/repos/Dingo-Shenanigans/ReSkate/releases/latest"

$ZipUrl         = "https://github.com/Dingo-Shenanigans/ReSkate/releases/download/v1.1.1/ReSkate-1.1.1.zip"

$ExpectedFiles = @(
    "ReSkateLauncher.exe",
    "ReSkate.dll",
    "Launcher.json",
    "LICENSE.txt",
    "licenses"
)

$ProcessNames = @(
    "Skate",
    "ReSkateLauncher"
)

$TempRoot       = Join-Path $env:TEMP "ReSkateInstaller"
$DownloadPath   = Join-Path $TempRoot "ReSkate-$Version.zip"
$StagePath      = Join-Path $TempRoot "Stage"
$ExtractPath    = Join-Path $TempRoot "Extracted"

$LogPath        = Join-Path $TempRoot "install.log"

$PythonInstallerUrl = `
    "https://www.python.org/ftp/python/3.14.8/python-3.14.8-amd64.exe"

$PythonInstallerPath = Join-Path $TempRoot "python-installer.exe"

# ============================================================================
# FUNCTIONS
# ============================================================================

function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    $line = "[$timestamp] [$Level] $Message"

    Add-Content -Path $LogPath -Value $line

    switch ($Level) {
        "ERROR" {
            Write-Host $line -ForegroundColor Red
        }

        "WARN" {
            Write-Host $line -ForegroundColor Yellow
        }

        "SUCCESS" {
            Write-Host $line -ForegroundColor Green
        }

        default {
            Write-Host $line
        }
    }
}

function Pause-Script {
    Write-Host ""
    Read-Host "Press ENTER to continue"
}

function Fail {
    param(
        [string]$Message
    )

    Write-Log $Message "ERROR"

    Write-Host ""
    Write-Host "======================================================================" -ForegroundColor Red
    Write-Host " INSTALLATION FAILED" -ForegroundColor Red
    Write-Host "======================================================================" -ForegroundColor Red
    Write-Host ""
    Write-Host $Message -ForegroundColor Red
    Write-Host ""
    Write-Host "Log:"
    Write-Host $LogPath
    Write-Host ""

    if (-not $Quiet) {
        Pause-Script
    }

    exit 1
}

function Test-Administrator {

    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()

    $principal = New-Object Security.Principal.WindowsPrincipal($identity)

    return $principal.IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator
    )
}

function Restart-AsAdministrator {

    Write-Host ""
    Write-Host "[*] Requesting Administrator privileges..." -ForegroundColor Yellow
    Write-Host "    Approve the prompt. This window waits until that one finishes."

    if (-not $PSCommandPath) {
        Fail "Run ReSkate.bat. Pasting this script into a console cannot relaunch it."
    }

    $argLine = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Action $Action"

    if ($Drive) {
        $argLine += " -Drive $($Drive.Substring(0,1))"
    }

    if ($Quiet) {
        $argLine += " -Quiet"
    }

    if ($SkatePath) {
        $argLine += " -SkatePath `"$SkatePath`""
    }

    try {
        $startArgs = @{
            FilePath     = "powershell.exe"
            Verb         = "RunAs"
            ArgumentList = $argLine
            Wait         = $true
            PassThru     = $true
        }
        if ($Quiet) { $startArgs.WindowStyle = "Hidden" }
        $proc = Start-Process @startArgs
    }
    catch {
        Fail "Administrator approval was cancelled."
    }

    if ($null -eq $proc.ExitCode) {
        exit 1
    }

    exit $proc.ExitCode
}

function Ensure-Directory {
    param(
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {

        New-Item `
            -ItemType Directory `
            -Path $Path `
            -Force | Out-Null
    }
}

function Get-FreeSpaceGB {
    param(
        [string]$Path
    )

    $root = [System.IO.Path]::GetPathRoot($Path)
    $drive = New-Object System.IO.DriveInfo $root
    if (-not $drive.IsReady) {
        return 0
    }

    return [math]::Round(
        $drive.AvailableFreeSpace / 1GB,
        2
    )
}

function Test-Internet {

    try {

        $request = [System.Net.WebRequest]::Create(
            "https://github.com"
        )

        $request.Timeout = 10000

        $response = $request.GetResponse()

        $response.Close()

        return $true
    }
    catch {

        return $false
    }
}

function Find-SkateOnFixedDrives {

    $hits = @()

    foreach ($disk in [System.IO.DriveInfo]::GetDrives()) {
        if ($disk.DriveType -ne [System.IO.DriveType]::Fixed -or -not $disk.IsReady) { continue }

        $path = Join-Path $disk.Name $SkateRelativePath
        $exe = Join-Path $path "Skate.exe"

        if (Test-Path -LiteralPath $exe -PathType Leaf) {
            $hits += [System.IO.Path]::GetFullPath($path)
        }
    }

    return ,$hits
}

function Resolve-SkateDirectory {

    Write-Host ""
    Write-Host "Expected install:"
    Write-Host "  <drive>:\$SkateRelativePath"
    Write-Host "Type a drive letter to use a different root drive."
    Write-Host ""

    if ($Drive) {

        $letter = ($Drive.ToUpper() -replace "[^A-Z]", "")

        if ($letter.Length -ge 1) {
            $letter = $letter.Substring(0, 1)
        }

        $direct = "{0}:\{1}" -f $letter, $SkateRelativePath
        $directExe = Join-Path $direct "Skate.exe"

        if (Test-Path -LiteralPath $directExe -PathType Leaf) {
            return [System.IO.Path]::GetFullPath($direct)
        }

        Fail "Skate.exe was not found at $direct"
    }

    $found = @(Find-SkateOnFixedDrives | Where-Object { $_ })

    while ($true) {

        if ($found.Count -eq 1) {

            Write-Host "Found $($found[0])" -ForegroundColor Green
            $answer = Read-Host "Press ENTER to use it, or type a drive letter"

            if ([string]::IsNullOrWhiteSpace($answer)) {
                return $found[0]
            }
        }
        elseif ($found.Count -gt 1) {

            Write-Host "Found Skate on more than one drive:"

            foreach ($hit in $found) {
                Write-Host "  $hit"
            }

            $answer = Read-Host "Drive letter"
        }
        else {

            Write-Host "Skate was not found under \$SkateRelativePath" -ForegroundColor Yellow
            $answer = Read-Host "Drive letter where Steam is installed"
        }

        $letter = ($answer.ToUpper() -replace "[^A-Z]", "")

        if ($letter.Length -lt 1) {
            Write-Host "[!] Enter a drive letter such as D." -ForegroundColor Red
            continue
        }

        $letter = $letter.Substring(0, 1)
        $candidate = "{0}:\{1}" -f $letter, $SkateRelativePath
        $exe = Join-Path $candidate "Skate.exe"

        if (Test-Path -LiteralPath $exe -PathType Leaf) {

            $resolved = [System.IO.Path]::GetFullPath($candidate)
            Write-Log "Skate found: $exe" "SUCCESS"
            return $resolved
        }

        Write-Host "[!] Skate.exe was not found at $candidate" -ForegroundColor Red
    }
}

function Get-LatestRelease {

    $fallback = @{
        Version = $Version
        Url     = $ZipUrl
    }

    try {

        $release = Invoke-RestMethod `
            -Uri $LatestApiUrl `
            -Headers @{ "User-Agent" = "ReSkateInstaller" } `
            -UseBasicParsing `
            -TimeoutSec 60

        $asset = @($release.assets) |
            Where-Object { $_.name -match "\.zip$" -and $_.browser_download_url } |
            Select-Object -First 1

        if (-not $asset) {
            throw "Latest release has no zip asset."
        }

        $tag = [string]$release.tag_name

        if ($tag.StartsWith("v") -or $tag.StartsWith("V")) {
            $tag = $tag.Substring(1)
        }

        return @{
            Version = $tag
            Url     = [string]$asset.browser_download_url
        }
    }
    catch {

        Write-Log `
            "Latest release lookup failed. Using $($fallback.Version). $($_.Exception.Message)" `
            "WARN"

        return $fallback
    }
}

function Get-InstalledVersion {

    param(
        [string]$SkateRoot
    )

    $path = Join-Path $SkateRoot "Launcher.json"

    if (-not (Test-Path -LiteralPath $path)) {
        return $null
    }

    try {

        $json = Get-Content -LiteralPath $path -Raw -ErrorAction Stop |
            ConvertFrom-Json

        $property = $json.PSObject.Properties["Version"]

        if ($property) {
            return [string]$property.Value
        }
    }
    catch {

        Write-Log "Could not read installed version from Launcher.json." "WARN"
    }

    return $null
}

function Test-ReSkateDependencies {

    param(
        [string]$SkateRoot
    )

    $rows = New-Object System.Collections.Generic.List[object]

    $psOk = $PSVersionTable.PSVersion -ge [version]"5.1"
    $rows.Add([pscustomobject]@{
        Name   = "PowerShell"
        Ok     = [bool]$psOk
        Hard   = $true
        Detail = [string]$PSVersionTable.PSVersion
    })

    $archOk = $env:PROCESSOR_ARCHITECTURE -in @("AMD64", "ARM64")
    $rows.Add([pscustomobject]@{
        Name   = "64-bit Windows"
        Ok     = [bool]$archOk
        Hard   = $true
        Detail = [string]$env:PROCESSOR_ARCHITECTURE
    })

    $online = Test-Internet
    $rows.Add([pscustomobject]@{
        Name   = "Internet"
        Ok     = [bool]$online
        Hard   = $true
        Detail = "github.com"
    })

    $zipOk = $false

    try {
        Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop
        $zipOk = $true
    }
    catch {
        $zipOk = $false
    }

    $rows.Add([pscustomobject]@{
        Name   = "ZIP support"
        Ok     = [bool]$zipOk
        Hard   = $true
        Detail = "System.IO.Compression"
    })

    $sevenZip = Find-7Zip
    $rows.Add([pscustomobject]@{
        Name   = "7-Zip"
        Ok     = [bool]$sevenZip
        Hard   = $false
        Detail = $(if ($sevenZip) { $sevenZip } else { "optional, PowerShell ZIP is used first" })
    })

    if ($SkateRoot) {

        $exe = Join-Path $SkateRoot "Skate.exe"
        $rows.Add([pscustomobject]@{
            Name   = "Skate.exe"
            Ok     = (Test-Path -LiteralPath $exe -PathType Leaf)
            Hard   = $true
            Detail = $exe
        })

        $free = Get-FreeSpaceGB $SkateRoot
        $rows.Add([pscustomobject]@{
            Name   = "Free space"
            Ok     = ($free -ge 1)
            Hard   = $true
            Detail = "$free GB"
        })
    }

    foreach ($row in $rows) {

        $level = $(if ($row.Ok) { "SUCCESS" } else { "WARN" })
        Write-Log "$($row.Name): $($row.Detail)" $level
    }

    return $rows
}

function Remove-OldBackups {

    param(
        [string]$SkateRoot,
        [string]$Keep
    )

    $backups = Get-ChildItem `
        -LiteralPath $SkateRoot `
        -Directory `
        -Filter "ReSkate_Backup_*" `
        -ErrorAction SilentlyContinue

    foreach ($backup in $backups) {

        if ($Keep -and ($backup.FullName -eq $Keep)) {
            continue
        }

        Remove-Item `
            -LiteralPath $backup.FullName `
            -Recurse `
            -Force `
            -ErrorAction SilentlyContinue

        Write-Log "Removed old backup: $($backup.Name)"
    }
}

function Get-ModePath {

    param(
        [string]$SkateRoot,
        [string]$Child
    )

    $root = Join-Path $SkateRoot "ReSkate_Mode"

    if ($Child) {
        return Join-Path $root $Child
    }

    return $root
}

function Set-ActiveMode {

    param(
        [string]$SkateRoot,
        [string]$Mode
    )

    $root = Get-ModePath $SkateRoot
    Ensure-Directory $root

    Set-Content `
        -LiteralPath (Join-Path $root "active.txt") `
        -Value $Mode `
        -Encoding ASCII
}

function Get-ActiveMode {

    param(
        [string]$SkateRoot
    )

    $file = Get-ModePath $SkateRoot "active.txt"

    if (Test-Path -LiteralPath $file) {

        $text = (Get-Content -LiteralPath $file -Raw).Trim()

        if ($text -eq "Skate" -or $text -eq "ReSkate") {
            return $text
        }
    }

    $modHold = Get-ModePath $SkateRoot "mod"

    foreach ($name in $ExpectedFiles) {

        if (Test-Path -LiteralPath (Join-Path $modHold $name)) {
            return "Skate"
        }
    }

    return "ReSkate"
}

function Move-ModeEntry {

    param(
        [string]$Source,
        [string]$Destination
    )

    if (-not (Test-Path -LiteralPath $Source)) {
        return
    }

    $parent = Split-Path -Parent $Destination

    if ($parent) {
        Ensure-Directory $parent
    }

    if (Test-Path -LiteralPath $Destination) {
        Remove-Item -LiteralPath $Destination -Recurse -Force
    }

    Move-Item -LiteralPath $Source -Destination $Destination -Force
}

function Copy-ModeEntry {

    param(
        [string]$Source,
        [string]$Destination
    )

    if (-not (Test-Path -LiteralPath $Source)) {
        return
    }

    if (Test-Path -LiteralPath $Destination) {
        return
    }

    $parent = Split-Path -Parent $Destination

    if ($parent) {
        Ensure-Directory $parent
    }

    Copy-Item -LiteralPath $Source -Destination $Destination -Recurse -Force
}

function Import-VanillaHold {

    param(
        [string]$SkateRoot,
        [string]$BackupRoot
    )

    if (-not $BackupRoot -or -not (Test-Path -LiteralPath $BackupRoot)) {
        return
    }

    $vanilla = Get-ModePath $SkateRoot "vanilla"

    foreach ($name in $ExpectedFiles) {
        Copy-ModeEntry `
            -Source (Join-Path $BackupRoot $name) `
            -Destination (Join-Path $vanilla $name)
    }
}

function Clear-ModHold {

    param(
        [string]$SkateRoot
    )

    $mod = Get-ModePath $SkateRoot "mod"

    if (Test-Path -LiteralPath $mod) {
        Remove-Item -LiteralPath $mod -Recurse -Force
    }
}

function Test-ReSkateLive {

    param(
        [string]$SkateRoot
    )

    foreach ($name in $ExpectedFiles) {

        if (Test-Path -LiteralPath (Join-Path $SkateRoot $name)) {
            return $true
        }
    }

    return $false
}

function Switch-GameMode {

    param(
        [string]$SkateRoot,
        [string]$Target
    )

    $current = Get-ActiveMode $SkateRoot
    $liveReSkate = Test-ReSkateLive $SkateRoot

    Write-Host "Current mode: $current" -ForegroundColor White
    Write-Log "Mode now: $current. Requested: $Target. ReSkate files live: $liveReSkate"

    if ($current -eq $Target -and -not ($Target -eq "Skate" -and $liveReSkate)) {
        Write-Host "Already in $Target mode. Nothing moved." -ForegroundColor Green
        return
    }

    Stop-ReSkateProcesses

    $vanilla = Get-ModePath $SkateRoot "vanilla"
    $mod = Get-ModePath $SkateRoot "mod"
    $hasVanilla = $false

    foreach ($name in $ExpectedFiles) {

        if (Test-Path -LiteralPath (Join-Path $vanilla $name)) {
            $hasVanilla = $true
        }
    }

    if (-not $hasVanilla) {

        $newest = Get-ChildItem `
            -LiteralPath $SkateRoot `
            -Directory `
            -Filter "ReSkate_Backup_*" `
            -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1

        if ($newest) {
            Import-VanillaHold -SkateRoot $SkateRoot -BackupRoot $newest.FullName
        }
    }

    $oldestBackup = Get-ChildItem `
        -LiteralPath $SkateRoot `
        -Directory `
        -Filter "ReSkate_Backup_*" `
        -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime |
        Select-Object -First 1

    foreach ($name in $ExpectedFiles) {

        $live = Join-Path $SkateRoot $name

        if ($Target -eq "Skate") {

            Move-ModeEntry -Source $live -Destination (Join-Path $mod $name)

            $original = $null
            if ($oldestBackup -and $name -notin @("ReSkateLauncher.exe", "ReSkate.dll", "Launcher.json")) {
                $original = Join-Path $oldestBackup.FullName $name
            }
            if ($original -and (Test-Path -LiteralPath $original)) {
                Copy-ModeEntry -Source $original -Destination $live
            }
        }
        else {

            Move-ModeEntry -Source $live -Destination (Join-Path $vanilla $name)
            Move-ModeEntry -Source (Join-Path $mod $name) -Destination $live
        }
    }

    Set-ActiveMode -SkateRoot $SkateRoot -Mode $Target

    if ($Target -eq "Skate" -and (Test-ReSkateLive $SkateRoot)) {
        Fail "ReSkate files are still beside Skate.exe. Normal launch was stopped."
    }

    if ($Target -eq "Skate") {
        Write-Host "Skate is ON. ReSkate files are parked." -ForegroundColor Green
        Write-Host "Launch skate.exe." -ForegroundColor Green
    }
    else {
        Write-Host "ReSkate is ON. Original files are parked." -ForegroundColor Green
        Write-Host "Launch ReSkateLauncher.exe." -ForegroundColor Green
    }
}

function Download-WithRetry {

    param(
        [string]$Url,
        [string]$Destination,
        [int]$Retries = 3
    )

    Write-Log "Downloading:"
    Write-Log $Url

    for ($attempt = 1; $attempt -le $Retries; $attempt++) {

        try {

            Write-Host ""
            Write-Host "Download attempt $attempt / $Retries"

            if (Test-Path -LiteralPath $Destination) {

                Remove-Item `
                    -LiteralPath $Destination `
                    -Force `
                    -ErrorAction SilentlyContinue
            }

            [Net.ServicePointManager]::SecurityProtocol = `
                [Net.SecurityProtocolType]::Tls12

            Invoke-WebRequest `
                -Uri $Url `
                -OutFile $Destination `
                -UseBasicParsing `
                -TimeoutSec 120

            if (-not (Test-Path -LiteralPath $Destination)) {

                throw "Download completed but file was not created."
            }

            $size = (Get-Item $Destination).Length

            if ($size -lt 1024) {

                throw "Downloaded file is suspiciously small: $size bytes."
            }

            Write-Log "Download complete: $size bytes" "SUCCESS"

            return
        }
        catch {

            Write-Log `
                "Download attempt $attempt failed: $($_.Exception.Message)" `
                "WARN"

            if ($attempt -lt $Retries) {

                Start-Sleep -Seconds (2 * $attempt)
            }
        }
    }

    throw "Unable to download file after $Retries attempts."
}

function Test-ZipIntegrity {

    param(
        [string]$ZipPath
    )

    Write-Log "Validating ZIP archive."

    if (-not (Test-Path -LiteralPath $ZipPath)) {

        throw "ZIP file does not exist."
    }

    try {

        Add-Type -AssemblyName System.IO.Compression.FileSystem

        $zip = `
            [System.IO.Compression.ZipFile]::OpenRead($ZipPath)

        try {

            if ($zip.Entries.Count -eq 0) {

                throw "ZIP archive contains no files."
            }

            Write-Log `
                "ZIP contains $($zip.Entries.Count) entries."

        }
        finally {

            $zip.Dispose()
        }
    }
    catch {

        throw "ZIP validation failed: $($_.Exception.Message)"
    }
}

function Test-ZipSafePaths {

    param(
        [string]$ZipPath
    )

    Write-Log "Checking archive paths for unsafe traversal."

    Add-Type -AssemblyName System.IO.Compression.FileSystem

    $zip = `
        [System.IO.Compression.ZipFile]::OpenRead($ZipPath)

    try {

        foreach ($entry in $zip.Entries) {

            $entryName = $entry.FullName

            # Normalize separators
            $normalized = $entryName.Replace("/", "\")

            # Reject absolute paths
            if (
                $normalized.StartsWith("\") -or
                $normalized -match "^[A-Za-z]:\\"
            ) {

                throw "Unsafe absolute path found in archive: $entryName"
            }

            # Reject traversal
            $segments = $normalized.Split("\")

            if ($segments -contains "..") {

                throw "Unsafe traversal path found in archive: $entryName"
            }
        }

    }
    finally {

        $zip.Dispose()
    }

    Write-Log "Archive paths passed safety check." "SUCCESS"
}

function Find-7Zip {

    $candidates = @(
        "$env:ProgramFiles\7-Zip\7z.exe",
        "${env:ProgramFiles(x86)}\7-Zip\7z.exe",
        "$env:LOCALAPPDATA\Programs\7-Zip\7z.exe",
        "$env:USERPROFILE\scoop\apps\7zip\current\7z.exe"
    )

    foreach ($candidate in $candidates) {

        if ($candidate -and (Test-Path -LiteralPath $candidate)) {

            return $candidate
        }
    }

    $command = Get-Command "7z.exe" -ErrorAction SilentlyContinue

    if ($command) {

        return $command.Source
    }

    return $null
}

function Find-Python {

    $commands = @(
        "python.exe",
        "python3.exe",
        "py.exe"
    )

    foreach ($name in $commands) {

        $command = Get-Command $name -ErrorAction SilentlyContinue

        if ($command) {

            return $command.Source
        }
    }

    $knownPaths = @(
        "$env:LOCALAPPDATA\Programs\Python\Python314\python.exe",
        "$env:LOCALAPPDATA\Programs\Python\Python313\python.exe",
        "$env:ProgramFiles\Python314\python.exe",
        "$env:ProgramFiles\Python313\python.exe"
    )

    foreach ($path in $knownPaths) {

        if (Test-Path -LiteralPath $path) {

            return $path
        }
    }

    return $null
}

function Try-WinGetInstall {

    $winget = Get-Command "winget.exe" -ErrorAction SilentlyContinue

    if (-not $winget) {

        Write-Log "WinGet is not available." "WARN"

        return $false
    }

    try {

        Write-Log "Attempting to install Python through WinGet."

        & $winget.Source install `
            --id Python.Python.3.14 `
            --exact `
            --silent `
            --accept-package-agreements `
            --accept-source-agreements

        if ($LASTEXITCODE -eq 0) {

            Write-Log "Python installed through WinGet." "SUCCESS"

            return $true
        }
    }
    catch {

        Write-Log `
            "WinGet Python installation failed: $($_.Exception.Message)" `
            "WARN"
    }

    return $false
}

function Install-PythonFallback {

    Write-Log "Python is required as a final extraction fallback."

    if (Try-WinGetInstall) {

        $python = Find-Python

        if ($python) {

            return $python
        }
    }

    Write-Log "Downloading Python from python.org."

    Download-WithRetry `
        -Url $PythonInstallerUrl `
        -Destination $PythonInstallerPath

    if (-not (Test-Path -LiteralPath $PythonInstallerPath)) {

        throw "Python installer download failed."
    }

    Write-Log "Launching Python installer."

    $process = Start-Process `
        -FilePath $PythonInstallerPath `
        -ArgumentList @(
            "/quiet"
            "InstallAllUsers=1"
            "PrependPath=1"
            "Include_test=0"
            "Include_launcher=1"
        ) `
        -Wait `
        -PassThru

    if ($process.ExitCode -ne 0) {

        throw `
            "Python installer returned exit code $($process.ExitCode)."
    }

    Start-Sleep -Seconds 3

    $python = Find-Python

    if (-not $python) {

        throw "Python installation completed but python.exe could not be found."
    }

    Write-Log "Python available at: $python" "SUCCESS"

    return $python
}

function Extract-WithPowerShell {

    param(
        [string]$Zip,
        [string]$Destination
    )

    Write-Log "Trying PowerShell Expand-Archive."

    try {

        Expand-Archive `
            -LiteralPath $Zip `
            -DestinationPath $Destination `
            -Force `
            -ErrorAction Stop

        return $true
    }
    catch {

        Write-Log `
            "Expand-Archive failed: $($_.Exception.Message)" `
            "WARN"

        return $false
    }
}

function Extract-With7Zip {

    param(
        [string]$Zip,
        [string]$Destination
    )

    $sevenZip = Find-7Zip

    if (-not $sevenZip) {

        return $false
    }

    Write-Log "Trying 7-Zip: $sevenZip"

    try {

        & $sevenZip `
            x `
            $Zip `
            "-o$Destination" `
            "-y"

        if ($LASTEXITCODE -eq 0) {

            return $true
        }
    }
    catch {

        Write-Log `
            "7-Zip extraction failed: $($_.Exception.Message)" `
            "WARN"
    }

    return $false
}

function Extract-WithPython {

    param(
        [string]$Zip,
        [string]$Destination
    )

    $python = Find-Python

    if (-not $python) {

        $python = Install-PythonFallback
    }

    Write-Log "Using Python ZIP fallback."

    $script = @'
import sys
import zipfile
from pathlib import Path

zip_path = Path(sys.argv[1])
destination = Path(sys.argv[2]).resolve()

destination.mkdir(parents=True, exist_ok=True)

with zipfile.ZipFile(zip_path, "r") as z:
    for info in z.infolist():

        name = info.filename.replace("\\", "/")

        if name.startswith("/") or ":" in Path(name).parts[0]:
            raise RuntimeError(f"Unsafe absolute path: {name}")

        target = (destination / name).resolve()

        if destination not in target.parents and target != destination:
            raise RuntimeError(f"Unsafe archive path: {name}")

        if info.is_dir():
            target.mkdir(parents=True, exist_ok=True)
        else:
            target.parent.mkdir(parents=True, exist_ok=True)
            with z.open(info) as src, open(target, "wb") as dst:
                dst.write(src.read())

print("Extraction completed successfully.")
'@

    $pythonScript = Join-Path $TempRoot "extract.py"

    Set-Content `
        -Path $pythonScript `
        -Value $script `
        -Encoding UTF8

    & $python $pythonScript $Zip $Destination

    if ($LASTEXITCODE -ne 0) {

        throw "Python extraction failed."
    }
}

function Extract-Zip {

    param(
        [string]$Zip,
        [string]$Destination
    )

    Ensure-Directory $Destination

    # 1. Native Windows
    if (Extract-WithPowerShell $Zip $Destination) {

        Write-Log "Extraction succeeded using PowerShell." "SUCCESS"

        return
    }

    # Clean failed extraction
    Remove-Item `
        -LiteralPath $Destination `
        -Recurse `
        -Force `
        -ErrorAction SilentlyContinue

    Ensure-Directory $Destination

    # 2. Existing 7-Zip
    if (Extract-With7Zip $Zip $Destination) {

        Write-Log "Extraction succeeded using 7-Zip." "SUCCESS"

        return
    }

    # Clean failed extraction
    Remove-Item `
        -LiteralPath $Destination `
        -Recurse `
        -Force `
        -ErrorAction SilentlyContinue

    Ensure-Directory $Destination

    # 3. Python
    Extract-WithPython $Zip $Destination

    Write-Log "Extraction succeeded using Python." "SUCCESS"
}

function Find-ReSkateFiles {

    param(
        [string]$Root
    )

    $results = @{}

    foreach ($file in $ExpectedFiles) {

        $found = Get-ChildItem `
            -LiteralPath $Root `
            -Filter $file `
            -Recurse `
            -Force `
            -ErrorAction SilentlyContinue |
            Select-Object -First 1

        if ($found) {

            $results[$file] = $found.FullName
        }
    }

    return $results
}

function Stop-ReSkateProcesses {

    foreach ($name in $ProcessNames) {

        $processes = `
            Get-Process -Name $name -ErrorAction SilentlyContinue

        foreach ($process in $processes) {

            Write-Log `
                "Stopping running process: $($process.ProcessName) [$($process.Id)]" `
                "WARN"

            try {

                $process.CloseMainWindow() | Out-Null

                Start-Sleep -Seconds 2

                if (-not $process.HasExited) {

                    Stop-Process `
                        -Id $process.Id `
                        -Force `
                        -ErrorAction Stop
                }
            }
            catch {

                throw `
                    "Could not stop $($process.ProcessName). Close it manually."
            }
        }
    }
}

function Backup-ExistingFile {

    param(
        [string]$Source,
        [string]$BackupRoot,
        [string]$SkateRoot
    )

    if (-not (Test-Path -LiteralPath $Source)) {

        return
    }

    $relative = $Source.Substring(
        $SkateRoot.Length
    ).TrimStart("\","/")

    $destination = Join-Path `
        $BackupRoot `
        $relative

    $parent = Split-Path `
        -Parent `
        $destination

    Ensure-Directory $parent

    Copy-Item `
        -LiteralPath $Source `
        -Destination $destination `
        -Force

    Write-Log "Backed up: $relative"
}

function Install-StagedFiles {

    param(
        [string]$StageRoot,
        [string]$SkateRoot,
        [string]$BackupRoot
    )

    $files = Get-ChildItem `
        -Path $StageRoot `
        -File `
        -Recurse

    if (-not $files) {

        throw "No files were found in extracted archive."
    }

    foreach ($file in $files) {

        $relative = $file.FullName.Substring(
            $StageRoot.Length
        ).TrimStart("\","/")

        $destination = Join-Path `
            $SkateRoot `
            $relative

        # Ensure destination cannot escape Skate directory
        $resolvedRoot = `
            [System.IO.Path]::GetFullPath($SkateRoot).TrimEnd("\")

        $resolvedDest = `
            [System.IO.Path]::GetFullPath($destination)

        $rootPrefix = $resolvedRoot + "\"

        $insideRoot = $resolvedDest.Equals(
            $resolvedRoot,
            [StringComparison]::OrdinalIgnoreCase
        ) -or $resolvedDest.StartsWith(
            $rootPrefix,
            [StringComparison]::OrdinalIgnoreCase
        )

        if (-not $insideRoot) {

            throw "Refusing to install outside Skate directory: $relative"
        }

        if (Test-Path -LiteralPath $destination) {

            Backup-ExistingFile `
                -Source $destination `
                -BackupRoot $BackupRoot `
                -SkateRoot $SkateRoot
        }

        $parent = Split-Path -Parent $destination

        Ensure-Directory $parent

        Copy-Item `
            -LiteralPath $file.FullName `
            -Destination $destination `
            -Force

        Write-Log "Installed: $relative"
    }
}

function Verify-Installation {

    param(
        [string]$SkateRoot
    )

    foreach ($file in $ExpectedFiles) {

        $path = Join-Path $SkateRoot $file

        if (-not (Test-Path -LiteralPath $path)) {

            throw "Expected file missing after installation: $file"
        }

        $item = Get-Item -LiteralPath $path

        if ($item.PSIsContainer) {

            $count = @(
                Get-ChildItem `
                    -LiteralPath $path `
                    -Recurse `
                    -File `
                    -ErrorAction SilentlyContinue
            ).Count

            if ($count -le 0) {
                throw "Installed folder is empty: $file"
            }

            Write-Log "Verified $file ($count files)." "SUCCESS"
            continue
        }

        if ($item.Length -le 0) {

            throw "Installed file is empty: $file"
        }

        Write-Log `
            "Verified $file ($($item.Length) bytes)." `
            "SUCCESS"
    }
}

function Show-Banner {

    param(
        [string]$Mode = "INSTALLER   /   PATCHER   /   UPDATER"
    )

    $logo = @(
        " ______    _______         _______  ___   _  _______  _______  _______",
        "|    _ |  |       |       |       ||   | | ||   _   ||       ||       |",
        "|   | ||  |    ___| ____  |  _____||   |_| ||  |_|  ||_     _||    ___|",
        "|   |_||_ |   |___ |____| | |_____ |      _||       |  |   |  |   |___",
        "|    __  ||    ___|       |_____  ||     |_ |       |  |   |  |    ___|",
        "|   |  | ||   |___         _____| ||    _  ||   _   |  |   |  |   |___",
        "|___|  |_||_______|       |_______||___| |_||__| |__|  |___|  |_______|"
    )

    try {
        $Host.UI.RawUI.WindowTitle = "ReSkate  |  Overhaul Mod"
    }
    catch {
    }

    Write-Host ""

    foreach ($line in $logo) {
        Write-Host $line -ForegroundColor Cyan
    }

    Write-Host "========================================================================" -ForegroundColor DarkCyan
    Write-Host "      RESKATE OVERHAUL MOD" -ForegroundColor White
    Write-Host "      $Mode" -ForegroundColor Green
    Write-Host "      Offline play  /  community servers  /  custom mods" -ForegroundColor Gray
    Write-Host "========================================================================" -ForegroundColor DarkCyan
    Write-Host ""
}

function Write-Step {

    param(
        [string]$Label
    )

    Write-Host ""
    Write-Host "------------------------------------------------------------------------" -ForegroundColor DarkCyan
    Write-Host "  $Label" -ForegroundColor Cyan
    Write-Host "------------------------------------------------------------------------" -ForegroundColor DarkCyan
}

# ============================================================================
# INITIALIZATION
# ============================================================================

trap {
    Write-Host ""
    Write-Host $_.Exception.Message -ForegroundColor Red
    Read-Host "Press ENTER to close"
    exit 1
}

Clear-Host

Ensure-Directory $TempRoot

if (-not (Test-Path -LiteralPath $LogPath)) {

    New-Item `
        -ItemType File `
        -Path $LogPath `
        -Force | Out-Null
}

Write-Log "============================================================"
Write-Log "$AppName launcher. Action: $Action"
Write-Log "============================================================"

if (-not $Quiet) {
    Show-Banner
}

if ($Quiet -and $SkatePath -and ($Action -eq "Update" -or $Action -eq "All")) {
    $quietRoot = $SkatePath.Trim().Trim('"')
    if (Test-Path -LiteralPath (Join-Path $quietRoot "Skate.exe")) {
        $quietRelease = Get-LatestRelease
        $quietInstalled = Get-InstalledVersion -SkateRoot $quietRoot
        if ($quietInstalled -and $quietInstalled -eq [string]$quietRelease.Version) {
            Write-Log "ReSkate $($quietRelease.Version) is already installed."
            exit 0
        }
    }
}

if ($Action -ne "Check" -and -not (Test-Administrator)) {
    Restart-AsAdministrator
}

if ($Action -ne "Check") {
    Write-Log "Administrator privileges confirmed." "SUCCESS"
}

# ============================================================================
# 1. DEPENDENCY CHECK
# ============================================================================

Write-Step "1 / 4    DEPENDENCY CHECK"

$os = Get-CimInstance Win32_OperatingSystem
Write-Log "Windows: $($os.Caption) $($os.Version)"

$systemChecks = @(Test-ReSkateDependencies)
$systemFailed = @($systemChecks | Where-Object { $_.Hard -and -not $_.Ok })

if ($Action -ne "ReSkate" -and $Action -ne "Skate" -and $systemFailed.Count -gt 0) {
    $names = ($systemFailed | ForEach-Object { $_.Name }) -join ", "
    Fail "Dependency check failed: $names"
}

# ============================================================================
# 2. LOCATE SKATE  <drive>:\Steam\steamapps\common\Skate
# ============================================================================

Write-Step "2 / 4    LOCATE SKATE"

if ($SkatePath) {
    $candidate = $SkatePath.Trim().Trim('"')
    $candidateExe = Join-Path $candidate "Skate.exe"
    if (-not (Test-Path -LiteralPath $candidateExe)) {
        Fail "Skate.exe was not found at $candidate"
    }
    $skateDir = [System.IO.Path]::GetFullPath($candidate)
    Write-Log "Skate found: $candidateExe" "SUCCESS"
}
else {
    $skateDir = Resolve-SkateDirectory
}

$gameChecks = @(Test-ReSkateDependencies -SkateRoot $skateDir)
$gameFailed = @($gameChecks | Where-Object { $_.Hard -and -not $_.Ok })

if ($Action -ne "ReSkate" -and $Action -ne "Skate" -and $gameFailed.Count -gt 0) {
    $names = ($gameFailed | ForEach-Object { $_.Name }) -join ", "
    Fail "Dependency check failed: $names"
}

if ($Action -eq "ReSkate" -or $Action -eq "Skate") {

    Write-Step "MODE SWITCH"

    Switch-GameMode -SkateRoot $skateDir -Target $Action

    $bannerMode = "RESKATE ON    SKATE OFF"

    if ($Action -eq "Skate") {
        $bannerMode = "SKATE ON    RESKATE OFF"
    }

    if ($Quiet) {
        exit 0
    }

    Show-Banner -Mode $bannerMode
    Write-Host "  Folder    $skateDir" -ForegroundColor White
    Write-Host "  Hold      $(Get-ModePath $skateDir)" -ForegroundColor Gray
    Write-Host ""
    Pause-Script
    exit 0
}

if ($Action -eq "Check") {
    Write-Host ""
    Write-Host "Dependency check finished." -ForegroundColor Green
    Write-Host "Skate: $skateDir"
    Pause-Script
    exit 0
}

# ============================================================================
# STOP GAME
# ============================================================================

Write-Step "3 / 4    LATEST RELEASE"

$release = Get-LatestRelease
$Version = [string]$release.Version
$ZipUrl = [string]$release.Url
$DownloadPath = Join-Path $TempRoot "ReSkate-$Version.zip"

$installedVersion = Get-InstalledVersion -SkateRoot $skateDir
Write-Log "Installed version: $(if ($installedVersion) { $installedVersion } else { 'none' })"
Write-Log "Latest version: $Version"
Write-Log "Download: $ZipUrl"

$skipInstall = $false

if ($installedVersion -and $installedVersion -eq $Version -and $Action -ne "Install") {
    Write-Host "ReSkate $Version is already installed." -ForegroundColor Green
    if ($Quiet) {
        exit 0
    }
    $again = Read-Host "Reinstall anyway? [y/N]"
    if ($again -notmatch "^[Yy]$") {
        $skipInstall = $true
    }
}

if ($skipInstall) {
    Write-Host ""
    Write-Host "No files were changed." -ForegroundColor Green
    Write-Host "Skate: $skateDir"
    if (-not $Quiet) { Pause-Script }
    exit 0
}

Write-Host ""
Write-Host "Stopping Skate and ReSkate if they are running..." -ForegroundColor Cyan

Stop-ReSkateProcesses

# ============================================================================
# DEFENDER
# ============================================================================

Write-Host ""
Write-Host "Windows Defender..." -ForegroundColor Cyan

try {

    if (Get-Command Add-MpPreference -ErrorAction SilentlyContinue) {

        if ($Quiet) {
            Write-Log "Defender exclusion skipped."
        }
        else {
        Write-Host ""
        Write-Host "Optional Defender exclusion for the Skate folder."
        Write-Host "It is not required. If added, it stays until you remove it"
        Write-Host "in Windows Security."
        Write-Host ""

        $answer = Read-Host `
            "Add Defender exclusion for this folder? [y/N]"

        if ($answer -match "^[Yy]$") {

            Add-MpPreference `
                -ExclusionPath $skateDir `
                -ErrorAction Stop

            Write-Log `
                "Defender exclusion added: $skateDir" `
                "WARN"
        }
        else {

            Write-Log `
                "Defender exclusion skipped."
        }
        }
    }
}
catch {

    Write-Log `
        "Unable to configure Defender: $($_.Exception.Message)" `
        "WARN"
}

# ============================================================================
# BACKUP
# ============================================================================

Write-Host ""
Write-Host "Preparing backup..." -ForegroundColor Cyan

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"

$backupDir = Join-Path `
    $skateDir `
    "ReSkate_Backup_$timestamp"

Ensure-Directory $backupDir

Write-Log "Backup directory: $backupDir"

# ============================================================================
# DOWNLOAD
# ============================================================================

Get-ChildItem `
    -LiteralPath $TempRoot `
    -Filter "ReSkate-*.zip" `
    -File `
    -ErrorAction SilentlyContinue |
    Remove-Item -Force -ErrorAction SilentlyContinue

Write-Step "4 / 4    INSTALL  $Version"

Download-WithRetry `
    -Url $ZipUrl `
    -Destination $DownloadPath

Test-ZipIntegrity `
    -ZipPath $DownloadPath

Test-ZipSafePaths `
    -ZipPath $DownloadPath

# ============================================================================
# EXTRACT
# ============================================================================

Write-Host ""
Write-Host "Extracting archive..." -ForegroundColor Cyan

if (Test-Path -LiteralPath $ExtractPath) {

    Remove-Item `
        -LiteralPath $ExtractPath `
        -Recurse `
        -Force
}

Ensure-Directory $ExtractPath

Extract-Zip `
    -Zip $DownloadPath `
    -Destination $ExtractPath

# ============================================================================
# FIND ACTUAL RELEASE CONTENT
# ============================================================================

Write-Host ""
Write-Host "Inspecting extracted release..." -ForegroundColor Cyan

$releaseFiles = Find-ReSkateFiles `
    -Root $ExtractPath

foreach ($file in $ExpectedFiles) {

    if (-not $releaseFiles.ContainsKey($file)) {

        Fail "Required release file was not found: $file"
    }

    Write-Log `
        "Found release file: $file -> $($releaseFiles[$file])" `
        "SUCCESS"
}

# ============================================================================
# STAGE
# ============================================================================

if (Test-Path -LiteralPath $StagePath) {

    Remove-Item `
        -LiteralPath $StagePath `
        -Recurse `
        -Force
}

Ensure-Directory $StagePath

foreach ($file in $ExpectedFiles) {

    $source = $releaseFiles[$file]

    $destination = Join-Path `
        $StagePath `
        $file

    $sourceItem = Get-Item -LiteralPath $source

    if ($sourceItem.PSIsContainer) {
        Copy-Item `
            -LiteralPath $source `
            -Destination $destination `
            -Recurse `
            -Force
    }
    else {
        Copy-Item `
            -LiteralPath $source `
            -Destination $destination `
            -Force
    }
}

# ============================================================================
# INSTALL
# ============================================================================

Write-Host ""
Write-Host "Copying files into Skate..." -ForegroundColor Cyan

try {

    Install-StagedFiles `
        -StageRoot $StagePath `
        -SkateRoot $skateDir `
        -BackupRoot $backupDir

    Verify-Installation `
        -SkateRoot $skateDir
}
catch {

    Write-Log `
        "Installation failed: $($_.Exception.Message)" `
        "ERROR"

    Write-Host ""
    Write-Host "The installation did not complete." -ForegroundColor Red
    Write-Host "Existing files were backed up to:"
    Write-Host $backupDir

    Fail $_.Exception.Message
}

# ============================================================================
# CLEANUP
# ============================================================================

$backupFiles = @(
    Get-ChildItem `
        -LiteralPath $backupDir `
        -Recurse `
        -File `
        -ErrorAction SilentlyContinue
)

if ($backupFiles.Count -eq 0) {
    Remove-Item -LiteralPath $backupDir -Recurse -Force -ErrorAction SilentlyContinue
    Write-Log "No previous ReSkate files needed a backup."
    $backupDir = $null
}

if ($backupDir) {
    Import-VanillaHold -SkateRoot $skateDir -BackupRoot $backupDir
}

Clear-ModHold -SkateRoot $skateDir
Set-ActiveMode -SkateRoot $skateDir -Mode "ReSkate"

Remove-OldBackups -SkateRoot $skateDir -Keep $backupDir

Write-Log "Cleaning temporary installer files."

try {

    Remove-Item `
        -LiteralPath $ExtractPath `
        -Recurse `
        -Force `
        -ErrorAction SilentlyContinue

    Remove-Item `
        -LiteralPath $StagePath `
        -Recurse `
        -Force `
        -ErrorAction SilentlyContinue

    Remove-Item `
        -LiteralPath $DownloadPath `
        -Force `
        -ErrorAction SilentlyContinue

    Remove-Item `
        -LiteralPath $PythonInstallerPath `
        -Force `
        -ErrorAction SilentlyContinue
}
catch {

    Write-Log `
        "Some temporary files could not be removed." `
        "WARN"
}

# ============================================================================
# COMPLETE
# ============================================================================

Show-Banner -Mode "INSTALL COMPLETE    v$Version"

Write-Host "  Skate     $skateDir" -ForegroundColor White
Write-Host "  Backup    $(if ($backupDir) { $backupDir } else { 'none' })" -ForegroundColor Gray
Write-Host "  Log       $LogPath" -ForegroundColor Gray
Write-Host ""
Write-Host "  Launch ReSkateLauncher.exe from the Skate folder." -ForegroundColor Green
Write-Host ""

if ($Quiet) {
    exit 0
}

Pause-Script