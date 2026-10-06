#Requires -Version 5.1
<#
    ReSkate Installer / Bootstrapper
    --------------------------------
   Provided By: Iron Will Interactive
    --------------------------------
    - Elevates to Administrator
    - Validates Windows / architecture
    - Validates Skate installation
    - Stops conflicting game processes
    - Creates targeted backup
    - Downloads release with retry
    - Validates ZIP
    - Extracts using:
        1. PowerShell Expand-Archive
        2. 7-Zip if available
        3. Python zipfile
    - Bootstraps Python only if absolutely necessary
    - Verifies archive paths against Zip Slip
    - Installs through staging directory
    - Verifies expected files
    - Logs everything
    - Cleans temporary files
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ============================================================================
# CONFIGURATION
# ============================================================================

$AppName        = "ReSkate"
$Version        = "1.1.1"

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

$SevenZipInstallers = @(
    "7z-x64.exe",
    "7z.exe"
)

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

    Pause-Script

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

    $arguments = @(
        "-NoProfile"
        "-ExecutionPolicy"
        "Bypass"
        "-File"
        "`"$PSCommandPath`""
    )

    Start-Process `
        -FilePath "powershell.exe" `
        -Verb RunAs `
        -ArgumentList $arguments

    exit
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

    $drive = Get-CimInstance Win32_LogicalDisk |
        Where-Object {
            $_.DeviceID -eq $root.TrimEnd('\')
        }

    if (-not $drive) {
        return 0
    }

    return [math]::Round(
        $drive.FreeSpace / 1GB,
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
            -Path $Root `
            -Filter $file `
            -File `
            -Recurse `
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
            [System.IO.Path]::GetFullPath($SkateRoot)

        $resolvedDest = `
            [System.IO.Path]::GetFullPath($destination)

        if (-not $resolvedDest.StartsWith(
            $resolvedRoot,
            [StringComparison]::OrdinalIgnoreCase
        )) {

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

        if ($item.Length -le 0) {

            throw "Installed file is empty: $file"
        }

        Write-Log `
            "Verified $file ($($item.Length) bytes)." `
            "SUCCESS"
    }
}

# ============================================================================
# INITIALIZATION
# ============================================================================

Clear-Host

Ensure-Directory $TempRoot

# Initialize log
if (-not (Test-Path -LiteralPath $LogPath)) {

    New-Item `
        -ItemType File `
        -Path $LogPath `
        -Force | Out-Null
}

Write-Log "============================================================"
Write-Log "$AppName v$Version Installer"
Write-Log "============================================================"

# ============================================================================
# ADMIN
# ============================================================================

if (-not (Test-Administrator)) {

    Restart-AsAdministrator
}

Write-Log "Administrator privileges confirmed." "SUCCESS"

# ============================================================================
# HEADER
# ============================================================================

Write-Host @"
 ______    _______         _______  ___   _  _______  _______  _______
|    _ |  |       |       |       ||   | | ||   _   ||       ||       |
|   | ||  |    ___| ____  |  _____||   |_| ||  |_|  ||_     _||    ___|
|   |_||_ |   |___ |____| | |_____ |      _||       |  |   |  |   |___
|    __  ||    ___|       |_____  ||     |_ |       |  |   |  |    ___|
|   |  | ||   |___         _____| ||    _  ||   _   |  |   |  |   |___
|___|  |_||_______|       |_______||___| |_||__| |__|  |___|  |_______|
========================================================================
      ReSkate installer for Skate
      Offline play / community servers / mods
========================================================================
"@

Write-Host ""

# ============================================================================
# SYSTEM CHECKS
# ============================================================================

Write-Host "[PRECHECK] Checking system..." -ForegroundColor Cyan

$os = Get-CimInstance Win32_OperatingSystem

Write-Log "Windows: $($os.Caption)"
Write-Log "Version: $($os.Version)"
Write-Log "Architecture: $env:PROCESSOR_ARCHITECTURE"

if ($env:PROCESSOR_ARCHITECTURE -notin @("AMD64","ARM64")) {

    Fail "This installer requires a 64-bit Windows installation."
}

if (-not (Test-Internet)) {

    Fail "Internet connectivity test failed."
}

Write-Log "Internet connectivity confirmed." "SUCCESS"

# ============================================================================
# LOCATE SKATE
# ============================================================================

Write-Host ""
Write-Host "======================================================================" -ForegroundColor Cyan
Write-Host " Locate Skate"
Write-Host "======================================================================"
Write-Host ""
Write-Host "Steam:"
Write-Host "  Right-click Skate"
Write-Host "  Manage"
Write-Host "  Browse local files"
Write-Host ""
Write-Host "Paste the folder containing skate.exe."
Write-Host ""

$skateDir = $null

while (-not $skateDir) {

    $inputPath = Read-Host "Skate directory"

    $cleanedPath = $inputPath.Trim().Trim('"').Trim("'")

    if (-not (Test-Path -LiteralPath $cleanedPath -PathType Container)) {

        Write-Host "[!] Directory does not exist." -ForegroundColor Red

        continue
    }

    $skateExe = Join-Path `
        $cleanedPath `
        "Skate.exe"

    if (Test-Path -LiteralPath $skateExe -PathType Leaf) {

        $skateDir = `
            [System.IO.Path]::GetFullPath($cleanedPath)

        Write-Log "Skate found: $skateExe" "SUCCESS"

    }
    else {

        Write-Host ""
        Write-Host "[!] skate.exe was not found." -ForegroundColor Red
    }
}

# ============================================================================
# DISK SPACE
# ============================================================================

$freeGB = Get-FreeSpaceGB $skateDir

Write-Log "Free disk space: $freeGB GB"

if ($freeGB -lt 1) {

    Fail "Less than 1 GB of free disk space is available."
}

# ============================================================================
# STOP GAME
# ============================================================================

Write-Host ""
Write-Host "[1/6] Checking running processes..." -ForegroundColor Cyan

Stop-ReSkateProcesses

# ============================================================================
# DEFENDER
# ============================================================================

Write-Host ""
Write-Host "[2/6] Windows Defender..." -ForegroundColor Cyan

try {

    if (Get-Command Add-MpPreference -ErrorAction SilentlyContinue) {

        Write-Host ""
        Write-Host "This installer can add a temporary Defender exclusion for"
        Write-Host "the Skate directory."
        Write-Host ""
        Write-Host "This is NOT required for extraction or installation."
        Write-Host "It should only be used if ReSkate is being incorrectly blocked."
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
catch {

    Write-Log `
        "Unable to configure Defender: $($_.Exception.Message)" `
        "WARN"
}

# ============================================================================
# BACKUP
# ============================================================================

Write-Host ""
Write-Host "[3/6] Preparing backup..." -ForegroundColor Cyan

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"

$backupDir = Join-Path `
    $skateDir `
    "ReSkate_Backup_$timestamp"

Ensure-Directory $backupDir

Write-Log "Backup directory: $backupDir"

# ============================================================================
# DOWNLOAD
# ============================================================================

Write-Host ""
Write-Host "[4/6] Downloading ReSkate v$Version..." -ForegroundColor Cyan

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
Write-Host "[5/6] Extracting archive..." -ForegroundColor Cyan

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

    Copy-Item `
        -LiteralPath $source `
        -Destination $destination `
        -Force
}

# ============================================================================
# INSTALL
# ============================================================================

Write-Host ""
Write-Host "[6/6] Installing files..." -ForegroundColor Cyan

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

Write-Host ""
Write-Host "======================================================================" -ForegroundColor Green
Write-Host " INSTALLATION COMPLETE" -ForegroundColor Green
Write-Host "======================================================================" -ForegroundColor Green
Write-Host ""
Write-Host "ReSkate $Version has been installed."
Write-Host ""
Write-Host "Skate:"
Write-Host "  $skateDir"
Write-Host ""
Write-Host "Backup:"
Write-Host "  $backupDir"
Write-Host ""
Write-Host "Installer log:"
Write-Host "  $LogPath"
Write-Host ""
Write-Host "The installer used:"
Write-Host "  PowerShell ZIP extraction first"
Write-Host "  7-Zip if available"
Write-Host "  Python as the final fallback"
Write-Host ""
Write-Host "======================================================================" -ForegroundColor Green

Pause-Script