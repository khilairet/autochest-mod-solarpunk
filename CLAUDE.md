# Solarpunk UE4SS mods — context for Claude

This folder hosts two UE4SS Lua mods for the game **Solarpunk** (Unreal Engine 5, modded via UE4SS):

1. **`Scripts/` + `enabled.txt` at the root** — `SolarpunkBetterQuickStack`, an existing/older mod (chest quick-stack helpers). Treat its `Scripts/main.lua` as a reference implementation for UE4SS Lua patterns (hook registration, struct field access, etc.) — it is NOT the mod currently being worked on.
2. **`AutoChest/`** — the mod currently under active development (this is the one we're building/debugging). Also installed live at:
   `D:\SteamLibrary\steamapps\common\Solarpunk\Solarpunk\Binaries\Win64\ue4ss\Mods\AutoChest\`
   **Both copies must be kept in sync manually** (there is no symlink — copy the file both ways after edits).

## Goal of AutoChest

When the player opens a workbench/crafting UI, the displayed ingredient quantities and the "Craft" button's enabled state should account for items in **all chests on the map**, not just the player's personal inventory. When the player actually clicks "Craft", missing ingredients should be pulled from chests **at that exact moment**, immediately consumed by the same action.

### Explicit design decision ("Option B")

The user explicitly rejected pre-loading/borrowing chest items into the player's bag while a workbench window is open (risk: leftover items in player inventory after closing the window, especially bad in multiplayer). Chosen approach instead: pull the missing amount from chests **only** inside the native craft function, in the same call that consumes it. Zero pre-display top-up, zero leftover risk. The user explicitly accepted that this means the displayed quantity prior to having items pulled may not perfectly preview combined totals — mitigated by also hooking the affordability check (below) so the UI's "craftable" state still reflects combined player+chest totals even though no items have physically moved yet.

## Key native functions discovered (via UE4SS EventViewer trace of clicking "Craft")

All on `BC_InventorySystem_C`, full path prefix `/Game/Code/Inventory_Items/Framework_and_Data/BC_InventorySystem.BC_InventorySystem_C:`

- **`CraftItemSlot(CraftingRecipy: S_SingleCraftingRecipy, CraftingPlayerController: PlayerController)`** — the master craft function, called directly from the Craft button's click chain. Internally calls `ContainsItemsAmt` (afford check) → `RemoveMultipleItems` (consumption) → `AddItemForPlayer` (gives output) → `Replace Inventory`/`OnRep_Inventory` (replication, fires UI refresh) → `SaveInventory`.
  - `S_SingleCraftingRecipy` struct fields (confirmed via Live View dump): `Endproduct_6_A149C932493B1524BFE79E81F4E544C5` (array of `S_InventorySlotSlim`) and `CraftingParts_5_3D0AF1AA4E64FE01DBBCCB8204A9DA6C` (array of `S_InventorySlotSlim`, the actual ingredients needed).
  - `S_InventorySlotSlim` fields: `Item_4_B9922CA845A5618A776EAFAB1A690E93` (ClassProperty — item class), `Quantity_5_A1813C42482CE5E7961C589A983BD034` (Int), `AdditionalSavedata_12_7C875E564155FCA4AA2B4597ACB03361` (Str).
- **`ContainsItemsAmt(Items: Array<S_InventorySlotSlim>) -> Contains: Bool`** — checks whether `self` (an inventory system instance) contains enough of every listed item. Used BOTH by `CraftItemSlot`'s internal check AND by the UI's `SW_PreFilledGrid_*.UpdateCraftingTiles` → `SW_CraftingTile_C.SetIsCraftable` refresh cycle (i.e., this single function drives both the "can afford" gate at craft-time and the tile's craftable-looking display/button-enabled state).
- **`ContainsItemAmt(Item, GivenItem) -> Contains: Bool`** — per-item version, called in a loop by `ContainsItemsAmt`.
- Also available on `BC_InventorySystem_C` (seen in the full function list dump): `GetAmtOfItem`, `MoveItemAmtToDiffInv`, `GetFirstNotFullSlotForItem`, `GetFirstIndexWithFreeSlot`, `RemoveMultipleItems`, `AddItemForPlayer`, `Inventory` (the slot array property), `SaveInventory`, `Quick Stack`.
- Player's own inventory component is a property literally named `InventorySystem` on `BP_MainPlayerCharacter_C` (confirmed via the bound-event name `BndEvt__BP_MainPlayerCharacter_InventorySystem_K2Node_...`).
- Chest ownership check: an inventory system instance's `GetOuter()` full name contains `"Chest"` when it belongs to a chest actor (pattern reused from the older quick-stack mod).

## Current mod implementation (`AutoChest/Scripts/main.lua`)

Two hooks on `BC_InventorySystem_C`:

1. **Post-hook on `ContainsItemsAmt`** — if the native result is `false`, recomputes using player inventory + every chest found via `FindAllOf("BC_InventorySystem_C")` filtered by the chest-outer check; if the combined total covers every required item, overrides `Contains` to `true`. This is meant to fix both the tile's craftable-looking state and unblock the Craft button itself (since native click-handling likely gates on the tile's `IsCraftable`/button-enabled state, which derives from this same check).
2. **Pre-hook on `CraftItemSlot`** — reads `CraftingRecipy.CraftingParts_5_...` (tries a few candidate field name strings for robustness), and for each ingredient computes `deficit = qty_needed - get_amt_of_item(player_inventory, item_class)`. If `deficit > 0`, pulls that amount from chest slots into the player's inventory via `MoveItemAmtToDiffInv`, using `GetFirstNotFullSlotForItem`/`GetFirstIndexWithFreeSlot` to pick a target slot index. The native `CraftItemSlot` logic then proceeds immediately afterward and consumes/saves — so nothing is left over in the player's bag beyond what gets spent in the very same craft action.

### Known pitfall already hit and fixed

At game launch, `BC_InventorySystem_C` is not yet loaded as a class, so `RegisterHook` on its functions fails immediately with "no UFunction with the specified name was found". Fix (same pattern as the older quick-stack mod): defer hook registration until `/Script/Engine.PlayerController:ClientRestart` fires (and also retry on any new `UserWidget` until both hooks are registered), guarded by `contains_hook_registered`/`craft_hook_registered` booleans so registration only actually happens once successfully. This part now works — logs confirm both hooks register successfully after the fix.

### Currently being debugged

Hooks register fine (confirmed in logs), but in-game testing shows:

- The Craft button still can't be clicked when ingredients are only in a chest (not in player inventory).
- No combined player+chest resource count appears to be reflected anywhere.

Debug `log("DEBUG: ...")` lines have just been added throughout `on_contains_items_amt_post`, `get_all_chest_inventories`, and `call_inventory_function` to surface: whether the post-hook fires at all when the UI recalculates craftability, what `Contains` value the native function originally computed, per-item needed/total-with-chests amounts, how many chest inventories are actually found vs. skipped (and why), and whether `GetAmtOfItem`/`GetFirstNotFullSlotForItem`/`GetFirstIndexWithFreeSlot` are found as valid callable functions on the inventory instance at all.

**Next step when resuming:** get a fresh in-game log capture (open workbench with ingredients only in a nearby chest) and read the new `[AutoChest] DEBUG: ...` lines to find which assumption is wrong — likely candidates: `ContainsItemsAmt` post-hook never firing for the UI's craftability check (vs. only firing at actual craft time), `is_chest_inventory` not matching the real chest outer name, or `GetAmtOfItem`/slot field names not matching what's actually on this struct version.

## Deferred work

- Hammer/build mode (construction ingredient pulling) — `SW_CurBuildableInfo_C` and its placement function have not been reverse-engineered yet. Explicitly deferred by the user until crafting/cooking works end-to-end.

## How to install/sync

After editing either copy, copy the file to the other location to keep them identical:

- Installed: `D:\SteamLibrary\steamapps\common\Solarpunk\Solarpunk\Binaries\Win64\ue4ss\Mods\AutoChest\Scripts\main.lua`

UE4SS in this install auto-detects mods by the presence of `enabled.txt` in the mod's folder — no `mods.txt` entry is required for custom mods (confirmed: other custom mods like `EnhancedChests` aren't listed in `mods.txt` either).
