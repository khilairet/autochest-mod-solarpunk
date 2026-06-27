# 📦 AutoChest

Craft and build directly from the items stored in chests across your island — no more shuffling materials back and forth. Plus a one-key **quick-deposit** to tidy your inventory into nearby chests.

When you open a workbench or enter build mode, ingredient counts reflect **everything you own** (inventory + chests), and crafting pulls any missing materials straight from your chests the moment you click **Craft**.

---

## 🌟 Features

- 🧰 **Craft from chests** — Workbench and cooking recipes count materials from your inventory *and* your chests. The Craft button lights up and the quantities (e.g. `55/2`) show your true combined totals.
- 🖱️ **One-click crafting** — Missing ingredients are pulled from chests the moment you craft. Nothing is ever pre-loaded into your bag, so there are no leftovers (multiplayer-safe).
- 🔨 **Build mode counts** — Required-material counts in the hammer/build menu also reflect what you have stored in chests.
- ⌨️ **Quick-deposit hotkey (F2)** — Press one key to push items from your inventory into nearby chests that *already hold that item* (drop your wood into the chest that already has wood). Key and range are configurable.
- 🎯 **Consumes correctly** — Pulls exactly what's needed (hotbar slots included) and never consumes anything if a recipe isn't fully affordable.
- ⚡ **Lightweight** — Chest lookups are cached, skip empty slots, and stop early once a recipe is satisfied; the Craft button only rescans when you actually click it. Set a search radius to ignore far-away chests entirely.

---

## 🔧 Installation

1. Install [UE4SS](https://github.com/UE4SS-RE/RE-UE4SS) for Solarpunk.
2. Copy the `AutoChest` folder into:
   ```
   Solarpunk/Binaries/Win64/ue4ss/Mods/
   ```
3. Make sure the folder contains an empty `enabled.txt` file (it ships with one).
4. Launch the game — the mod loads automatically.

To uninstall, simply delete the `AutoChest` folder.

---

## 📋 Requirements

- **UE4SS** (Unreal Engine Scripting System) installed for Solarpunk — required for any Lua mod to load.
- No other mods required.

---

## ⚙️ Configuration

Edit **`config.txt`** in the `AutoChest` folder (changes apply on the next launch / mod reload):

| Setting | Default | Meaning |
|---|---|---|
| `scan_radius` | `0` | How far (Unreal units; `100` = 1 m) crafting searches chests for materials. `0` = the whole map. e.g. `5000` ≈ 50 m. |
| `deposit_radius` | `2200` | How far the quick-deposit hotkey looks for chests (≈ the in-game "nearby" range). Not a whole-map value — keep it a real distance. |
| `deposit_key` | `F2` | Key for quick-deposit. A UE4SS `Key` name: `F1`–`F12`, a letter (`G`), or numpad (`NUM_ONE`). |

For verbose troubleshooting logs, set `local DEBUG_ENABLED = false` to `true` at the top of `Scripts/config.lua` (leave it `false` for normal play).

---

## 💚 Credits

- Big thanks to the **UE4SS** team for the modding framework.
- Thanks to the **Solarpunk modding community** for sharing knowledge.
