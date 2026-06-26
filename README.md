# 📦 AutoChest

Craft and build directly from the items stored in chests across your island — no more shuffling materials back and forth.

When you open a workbench or enter build mode, ingredient counts reflect **everything you own** (inventory + all chests), and crafting pulls any missing materials straight from your chests the moment you click **Craft**.

---

## 🌟 Features

- 🧰 **Craft from chests** — Workbench and cooking recipes count materials from your inventory *and* every chest on the map. The Craft button lights up and the quantities (e.g. `55/2`) show your true combined totals.
- 🖱️ **One-click crafting** — Missing ingredients are pulled from chests the moment you craft. Nothing is ever pre-loaded into your bag, so there are no leftovers (multiplayer-safe).
- 🔨 **Build mode counts** — Required-material counts in the hammer/build menu also reflect what you have stored in chests.
- 🎯 **Consumes correctly** — Pulls exactly what's needed (hotbar slots included) and never consumes anything if a recipe isn't fully affordable.
- ⚡ **Lightweight** — Chest lookups are cached and only run while a crafting or build menu is open, so there's zero performance impact while exploring.

---

## 🔧 Installation

1. Install [UE4SS](https://github.com/UE4SS-RE/RE-UE4SS) for Solarpunk.
2. Copy the `AutoChestCraft` folder into:
   ```
   Solarpunk/Binaries/Win64/ue4ss/Mods/
   ```
3. Make sure the folder contains an empty `enabled.txt` file (it ships with one).
4. Launch the game — the mod loads automatically.

To uninstall, simply delete the `AutoChestCraft` folder.

---

## 📋 Requirements

- **UE4SS** (Unreal Engine Scripting System) installed for Solarpunk — required for any Lua mod to load.
- No other mods required.

---

## ⚙️ Configuration

Open `Scripts/main.lua` and edit the flag at the top if you want verbose logging for troubleshooting:

```lua
local DEBUG_ENABLED = false  -- set to true to print per-item DEBUG traces
```

Leave it `false` for normal play.

---

## 💚 Credits

- Big thanks to the **UE4SS** team for the modding framework.
- Thanks to the **Solarpunk modding community** for sharing knowledge.
