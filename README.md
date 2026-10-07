# ReSkate

<img width="1024" height="1024" alt="ReSkate Logo" src="https://github.com/user-attachments/assets/2ce77b81-9156-4665-8eb1-fd4361376e76" />


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
- [Contributors Credits](#download-latest-release-link)

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

Double-click `ReSkate.exe`. `ReSkate.bat` starts the same window. The first start asks you to press Yes so Windows Security excludes this launcher folder and the Skate folder, including ReSkateLauncher. `ReSkate.bat allow` does that same approval on its own. The startup screen shows two cards. Folder opens an Explorer window. Pick the folder that contains `Skate.exe` and press Open. Wordmarks are in `Assets\Logos` and the card and window photos are in `Assets\Backgrounds`. The ReSkate card and the Skate card each switch the parked files, then start that game. Update, Mods, and Settings sit under the cards. The window checks this PC and looks for Skate before anything starts.

The top-right corner of each card has an auto update checkbox. ReSkate refreshes the release into the chosen Skate folder. Skate refreshes the game files with SteamCMD, which downloads into `Source\Setup\steamcmd` the first time it is needed and then runs hidden. Settings decides what the footer Update button includes: this launcher (`git pull`), the ReSkate release, and the game. Launcher and ReSkate start checked. The game stays off until it is checked. A checked card runs that update when the window opens. Mods opens on Recommended: Skate 2, Skate 3, Skater XL, Other, Maps, and Audio. Browse lists the ReSkate catalog for Mods or Modpacks, ordered last updated, newest, most downloaded, or top rated. A search keeps that filter and puts your words in the query. A checked package is extracted into its own folder, `Mods\<Author-Name>`, beside `Skate.exe`. Back returns to the game cards. Profiles saves that Mods folder into `Profiles\<name>`. Auto-update on the mods screen replaces an installed package when Thunderstore has a newer version. Enable the mod in the in-game ReSkate MODS menu.

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

## [Click here to download the latest launcher](https://github.com/gamedev44/ReSkateOverhaul/releases/latest/download/ReSkateOverhaul-launcher.zip)

The zip includes `ReSkate.exe`. The release page is [ReSkate launcher](https://github.com/gamedev44/ReSkateOverhaul/releases/latest).

## Contributors Credits

* [@IronWillInteractive](https://www.google.com/search?q=https://github.com/IronWillInteractive)
* [@Dingo-Shenanigans](https://github.com/Dingo-Shenanigans)
* [@zeex64](https://github.com/zeex64)
* [@claude](https://github.com/claude)
* [@Gamedev44](https://www.google.com/search?q=https://github.com/Gamedev44)
* [@gpt](https://www.google.com/search?q=https://github.com/gpt)
* [@xThrasherrr](https://github.com/xThrasherrr)
* [@jnslol](https://www.google.com/search?q=https://github.com/jnslol)
* [@DeckardDetribine](https://github.com/DeckardDetribine)
* [@ReGlitched](https://www.google.com/search?q=https://github.com/ReGlitched)
* [@lennyblk](https://github.com/lennyblk)
* [@VexFlint](https://www.google.com/search?q=https://github.com/VexFlint)
* [@Bortlesboat](https://github.com/Bortlesboat)
* [@worthlessnorms](https://github.com/worthlessnorms)
* [@Wackyhcky](https://www.google.com/search?q=https://github.com/Wackyhcky)
* [@moelrobi](https://www.google.com/search?q=https://github.com/moelrobi)
* [@Vebjorhk](https://www.google.com/search?q=https://github.com/Vebjorhk)
* [@wishluna](https://www.google.com/search?q=https://github.com/wishluna)

---

> A heartfelt thank you to everyone listed above. Every single line of code, fix, and contribution—big or small—made this project possible and necessary. Your time, energy, and work are deeply appreciated!

---
