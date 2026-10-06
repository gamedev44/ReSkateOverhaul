# ReSkate

**ReSkate** is an overhaul mod for *Skate (4)* featuring offline mode play, community-dedicated servers, and custom map/mod support.

---

## Overview

ReSkate provides a custom launcher and runtime utility framework that hooks directly into *Skate (4)*. It unlocks local offline gameplay, manages custom server connections, and validates required runtime files before bootstrapping the game.

---

## Key Features

- **Offline Mode Play:** Play *Skate (4)* locally without requiring active online connections to official servers.
- **Community Dedicated Servers:** Join and host custom player-driven multiplayer servers.
- **Custom Map & Mod Support:** Load custom parks, maps, and client-side modifications dynamically.
- **Automated Environment Verification:** Validates primary binaries, runtime libraries, and third-party compliance folders prior to execution.
- **JSON-Driven Configuration:** Fast, human-readable configuration parameters via `Launcher.json`.
- **Modular DLL Architecture:** Decouples the UI/launcher wrapper from core execution and hook logic.

---

## Directory Structure

All ReSkate assets must be extracted into your main *Skate* root installation folder (where `skate.exe` resides). Ensure the following structure exists prior to launching:

```text
├── ReSkateLauncher.exe  # Main client bootstrapper
├── ReSkate.dll          # Core runtime & mod hook library
├── Launcher.json        # Client configuration & launch parameters
├── LICENSE.txt          # Primary license document
└── licenses/            # Directory containing third-party OSS notices

```

---

## Quick Start

### 1. Locate Your *Skate (4)* Installation Directory

**In Steam:**

1. Right-click **Skate** in your Steam Library.
2. Hover over **Manage** and click **Browse local files**.
3. Copy the full folder path from the address bar.

### 2. Installation & Verification

1. Extract the release contents directly into your *Skate* directory.
2. Verify that all required files and the `licenses/` directory are present using PowerShell:

```powershell
# PowerShell Quick Validation
$ExpectedFiles = @(
    "ReSkateLauncher.exe",
    "ReSkate.dll",
    "Launcher.json",
    "LICENSE.txt",
    "licenses"
)

$missing = $ExpectedFiles | Where-Object { -not (Test-Path -Path ".\$_") }
if ($missing) {
    Write-Warning "Missing required items: $($missing -join ', ')"
} else {
    Write-Host "ReSkate environment valid." -ForegroundColor Green
}

```

### 3. Launch

Start the game via the custom launcher:

```powershell
.\ReSkateLauncher.exe

```

---

## Configuration (`Launcher.json`)

The default configuration template manages execution flags, offline options, and server connections:

```json
{
  "Version": "1.0.0",
  "TargetExecutable": "skate.exe",
  "OfflineMode": true,
  "ServerAddress": "127.0.0.1",
  "ServerPort": 27015,
  "EnableCustomMaps": true,
  "EnableLogging": true,
  "CheckIntegrity": true
}

```

---

## License & Third-Party Dependencies

ReSkate is distributed under the terms of the project license included in [`LICENSE.txt`](https://www.google.com/search?q=LICENSE.txt). Third-party dependencies and open-source compliance notices are stored within the [`licenses/`](https://www.google.com/search?q=licenses/) directory.

---
