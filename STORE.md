# Store / mod-page copy

Text for the CurseForge / Nexus listing. Keep in sync with README.md.

## Summary (≤ 250 chars — currently 242)

Craft and build straight from your chests in Solarpunk — ingredient counts and the Craft button include items stored nearby, and missing materials are pulled the moment you craft. Plus a one-key quick-deposit. Multiplayer-safe & configurable.

## Description

📦 **Description**

AutoChest lets you craft and build directly from the items stored in chests across your island — no more shuffling materials back and forth! 🏃‍♂️💨

When you open a workbench or enter build mode, ingredient counts reflect everything you own (inventory + chests), and crafting pulls any missing materials straight from your chests the moment you click Craft. Need to tidy up? One key dumps your items into the chests that already hold them. 🗃️✨

🔧 **Installation instructions**

- Install UE4SS for Solarpunk (see Requirements below).
- Copy the **AutoChest** folder into `Solarpunk/Binaries/Win64/ue4ss/Mods/`
- Launch the game — the mod loads automatically!

To uninstall, simply delete the AutoChest folder.

> ⚠️ **Updating from an older version?** If your previous install used a different
> folder name (e.g. `AutoChestCraft`), delete that old folder first — otherwise
> the mod loads twice and may consume chest items twice when crafting.

🌟 **Main features**

- 🧰 **Craft from chests** — Workbench and cooking recipes count materials from your inventory and your chests. The Craft button lights up and the quantities (e.g. 55/2) show your true combined totals.
- 🖱️ **One-click crafting** — Missing ingredients are pulled from chests the moment you craft. Nothing is ever pre-loaded into your bag, so there are no leftovers (multiplayer-safe).
- 🔨 **Build mode counts** — Required-material counts in the hammer/build menu also reflect what you have stored in chests.
- ⌨️ **Quick-deposit hotkey (F2)** — Press one key to push items from your inventory into nearby chests that already hold that item (drop your wood into the chest that already has wood).
- 🎯 **Consumes correctly** — Pulls exactly what's needed (hotbar slots included) and never consumes anything if a recipe isn't fully affordable.
- ⚙️ **Configurable** — A simple config.txt sets the chest search radius, the deposit range, and the hotkey — no code editing needed.
- ⚡ **Lightweight** — Chest lookups are cached, skip empty slots, and stop early once a recipe is covered; the Craft button only rescans on click, and an optional radius ignores far-away chests. Zero impact while exploring.

📋 **Requirements**

🔌 UE4SS installed for Solarpunk — required for any Lua mod to load.
✔️ No other mods required.

💚 **Shout outs**

🙏 Big thanks to the UE4SS team for the modding framework, and to the Solarpunk modding community for sharing their knowledge.

## Description (Nexus BBCode, colored titles)

Paste as-is into the Nexus description field (title color `#7CC576`):

```
[size=5][color=#7CC576]📦 Description[/color][/size]

AutoChest lets you craft and build directly from the items stored in chests across your island — no more shuffling materials back and forth! 🏃‍♂️💨

When you open a workbench or enter build mode, ingredient counts reflect everything you own (inventory + chests), and crafting pulls any missing materials straight from your chests the moment you click Craft. Need to tidy up? One key dumps your items into the chests that already hold them. 🗃️✨

[size=5][color=#7CC576]🔧 Installation instructions[/color][/size]

[list]
[*]Install UE4SS for Solarpunk (see Requirements below).
[*]Copy the [b]AutoChest[/b] folder into [b]Solarpunk/Binaries/Win64/ue4ss/Mods/[/b]
[*]Launch the game — the mod loads automatically!
[/list]

To uninstall, simply delete the AutoChest folder.

[quote]⚠️ Updating from an older version? If your previous install used a different folder name (e.g. AutoChestCraft), delete that old folder first — otherwise the mod loads twice and may consume chest items twice when crafting.[/quote]

[size=5][color=#7CC576]🌟 Main features[/color][/size]

[list]
[*]🧰 [b]Craft from chests[/b] — Workbench and cooking recipes count materials from your inventory and your chests. The Craft button lights up and the quantities (e.g. 55/2) show your true combined totals.
[*]🖱️ [b]One-click crafting[/b] — Missing ingredients are pulled from chests the moment you craft. Nothing is ever pre-loaded into your bag, so there are no leftovers (multiplayer-safe).
[*]🔨 [b]Build mode counts[/b] — Required-material counts in the hammer/build menu also reflect what you have stored in chests.
[*]⌨️ [b]Quick-deposit hotkey (F2)[/b] — Press one key to push items from your inventory into nearby chests that already hold that item (drop your wood into the chest that already has wood).
[*]🎯 [b]Consumes correctly[/b] — Pulls exactly what's needed (hotbar slots included) and never consumes anything if a recipe isn't fully affordable.
[*]⚙️ [b]Configurable[/b] — A simple config.txt sets the chest search radius, the deposit range, and the hotkey — no code editing needed.
[*]⚡ [b]Lightweight[/b] — Chest lookups are cached, skip empty slots, and stop early once a recipe is covered; the Craft button only rescans on click, and an optional radius ignores far-away chests. Zero impact while exploring.
[/list]

[size=5][color=#7CC576]📋 Requirements[/color][/size]

🔌 UE4SS installed for Solarpunk — required for any Lua mod to load.
✔️ No other mods required.

[size=5][color=#7CC576]💚 Shout outs[/color][/size]

🙏 Big thanks to the UE4SS team for the modding framework, and to the Solarpunk modding community for sharing their knowledge.
```
