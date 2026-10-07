# ReSkate

**ReSkate** is an overhaul mod for *Skate (4)* featuring offline mode play, community-dedicated servers, and custom map/mod support.

---

## Table of Contents

- [Overview](#overview)
- [Key Features](#key-features)
- [Directory Structure](#directory-structure)
- [Quick Start](#quick-start)
- [Configuration (`Launcher.json`)](#configuration-launcherjson)
- [Mods (Maps, Scripts, Etc...)](#mods-maps-scripts-etc)
- [License & Third-Party Dependencies](#license--third-party-dependencies)
- [Download (Latest Release Link)](#download-latest-release-link)

---

## Overview

ReSkateOverhaul Repo (This Tool) provides a custom launcher and runtime utility framework that hooks directly into *Skate (4)*. It unlocks local offline gameplay, manages custom server connections, and validates required runtime files before bootstrapping the game.

---

## Key Features

- **Offline Mode Play:** Play *Skate (4)* locally without requiring active online connections to official servers.
- **Community Dedicated Servers:** Join and host custom player-driven multiplayer servers.
- **Custom Map & Mod Support:** Load custom parks, maps, and client-side modifications dynamically.
- **Automated Environment Verification:** Validates primary binaries, runtime libraries, and third-party compliance folders prior to execution.
- **JSON-Driven Configuration:** Fast, human-readable configuration parameters via `Launcher.json`.
- **Modular DLL Architecture:** Decouples the UI/launcher wrapper from core execution and hook logic.

---

## Project Structure

```text
ReSkate.bat
Assets/Logos/          # reskate.png, skate.png, skate-element.png
Assets/Backgrounds/    # window.jpg, mods.jpg, reskate-card.jpg, skate-card.jpg
Source/Launch/         # Pre-launch card window
Source/Setup/          # Install, update, and mode switch
Source/Mods/           # Thunderstore catalog and mod install
```

After install, the game folder beside `Skate.exe` contains `ReSkateLauncher.exe`, `ReSkate.dll`, `Launcher.json`, `LICENSE.txt`, and `licenses\`. Community mods go in `Mods\`.

---

## Quick Start

Double-click `ReSkate.bat`. The startup screen shows two cards. Wordmarks are in `Assets\Logos` and the card and window photos are in `Assets\Backgrounds`. The ReSkate card and the Skate card each switch the parked files, then start that game. Update, Mods, and Check sit under the cards.

Update installs the latest release. Auto-update on the card screen checks that release in the background. Mods opens on Recommended: Skate 2, Skate 3, Skater XL, Other, Maps, and Audio. Browse lists the ReSkate catalog for Mods or Modpacks, ordered last updated, newest, most downloaded, or top rated. A search keeps that filter and puts your words in the query. A checked package is extracted into its own folder, `Mods\<Author-Name>`, beside `Skate.exe`. Back returns to the game cards. Profiles saves that Mods folder into `Profiles\<name>`. Auto-update on the mods screen replaces an installed package when Thunderstore has a newer version. Enable the mod in the in-game ReSkate MODS menu.

Skate is resolved at:

```text
<drive>:\Steam\steamapps\common\Skate
```

The card screen fills that path when `Skate.exe` is there. `ReSkate.bat D` limits the search to drive D. The folder list can point at another install.

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

## Mods (Maps, Scripts, Etc...)

Recommended lists [Skate 3 Improved](https://old.thunderstore.io/c/reskate/p/333/Skate_3_Improved/) under Skate 3 and Maps. Checking it lands the zip in `Mods\333-Skate_3_Improved`. Browse opens on [last updated mods](https://old.thunderstore.io/c/reskate/?ordering=last-updated&section=mods). The same page can switch to modpacks, newest, most downloaded, or top rated. Rest on a package to see its Thunderstore thumbnail. Mods and Modpacks split single packages from packs. Profiles saves the installed set under `Profiles\<name>`, and Load copies it back. Enable the mod in the in-game ReSkate MODS menu.

---

## License & Third-Party Dependencies

The installer copies `LICENSE.txt` and `licenses\` into the Skate folder with the release.

---

## Download (Latest Release Link)

`ReSkate.bat` downloads the latest zip from [Dingo-Shenanigans/ReSkate](https://github.com/Dingo-Shenanigans/ReSkate/releases/latest).

---
