# Solarpunk UE4SS mods — context for Claude

This folder hosts the **AutoChest** UE4SS Lua mod for the game **Solarpunk** (Unreal Engine 5, modded via UE4SS).

Reference implementations also installed on this machine (treat as read-only examples of UE4SS Lua patterns — hook registration, struct field access, item moves, keybinds):
- **`ue4ss-essential/Mods/EnhancedChests/`** — internal name `SolarpunkBetterQuickStack`. Implements quick-stack to nearby chests via the native `MoveItemAmtToDiffInv`; the source of AutoChest's quick-deposit item-move pattern.
- **`ue4ss-essential/Mods/VanguardFramework/`** — multi-file mod; source of the `require("module")(ctx)` factory pattern and `RegisterKeyBind(Key.X, {ModifierKey.Y}, fn)` usage.

## Goal of AutoChest

When the player opens a workbench/crafting UI or build mode, displayed ingredient quantities and the "Craft" button's enabled state account for items in **chests** (within an optional radius), not just the player's inventory. Clicking "Craft" pulls missing ingredients from chests **at that exact moment**, consumed by the same action. A hotkey also quick-deposits inventory items into nearby chests that already hold them.

### Explicit design decision ("Option B")

The user rejected pre-loading/borrowing chest items into the player's bag while a workbench is open (risk: leftovers after closing, bad in multiplayer). Instead, missing amounts are pulled from chests **only** inside the native craft consumption, in the same call that consumes them. Zero pre-display top-up, zero leftover risk. The "craftable" UI state is kept correct by also hooking the affordability check, even though no items have physically moved yet.

## Status: working

Crafting-from-chests, build-mode counts, and the F2 quick-deposit are all confirmed working in-game (incl. a mixed host/client multiplayer setup, where each client runs the mod).

## Architecture (`Scripts/`, multi-file)

`main.lua` is the entry point. It builds a shared `ctx` table and requires each module as a factory — `ctx.x = require("x")(ctx)` — in dependency order, so each module captures the ones it needs. Each module owns its own mutable state (caches); other modules mutate it only through exposed functions.

| File | Responsibility |
|---|---|
| `config.lua` | Constants (UFunction paths, struct field-name candidates, radii, key) + `load_file()` reading `config.txt`. Returns one table; `scan_radius`/`deposit_radius`/`deposit_key` are read dynamically so an edited file takes effect. |
| `util.lua` | Stateless helpers: logging, `now_seconds`, `is_valid`, `get_param`/`set_param`, `try_get` (with a resolved-field-name cache), `find_field_name`, `full_name_of`, `get_outer`, `same_item`, slot accessors, `get_inventory_array`. |
| `inventory.lua` | Chest & player resolution (`FindAllOf` + outer-name filter, both cached ~10 s), `actor_location_of` + `filter_chests_within_radius`, per-inventory content maps (cached 0.5 s), combined `get_total_amount_with_chests` (exact, for display) and `has_enough_with_chests` (early-break boolean, for decisions). Owns all read caches + `chest_lookup_in_progress`. |
| `mutate.lua` | The only writers: `decrement_from_inventory`, `add_to_inventory`, `remove_amount`, and `move_amount`/`top_up_matching_stacks` (native `MoveItemAmtToDiffInv`). Invalidates inventory caches after changes. |
| `hooks.lua` | The crafting/affordability hooks + their registration, the material-UI gating for `GetAmtOfItem`, and the per-craft player snapshot (`pre_craft_counts`). |
| `deposit.lua` | Quick-deposit logic + `RegisterKeyBind`. |

### Performance notes (Craft latency)

- `try_get` remembers which candidate field name resolved (keyed by the fields table) and reads it directly, skipping failed `pcall`s per slot.
- Inventory scan reads quantity first and skips empty slots without probing item fields / `GetFullName`.
- Decisions use `has_enough_with_chests`, which checks the player's bag first (no chest scan if it already covers the need) and stops as soon as enough is found.
- `config.scan_radius` (0 = whole map) skips out-of-range chests entirely.
- At craft time the removal hook drops **all** content caches to force a fresh recount before deciding — deliberate: it only fires on a real click, keeps multiplayer decisions correct, and means chest stock is only ever decremented after a fresh "have enough" confirmation (check-before, never roll-back, so nothing is ever put back into a chest).

## Key native functions (via UE4SS EventViewer trace of clicking "Craft")

On `BC_InventorySystem_C`, full path prefix `/Game/Code/Inventory_Items/Framework_and_Data/BC_InventorySystem.BC_InventorySystem_C:`

- **`CraftItemSlot(CraftingRecipy, CraftingPlayerController)`** — master craft fn. Internally: `ContainsItemsAmt` (afford check) → `RemoveMultipleItems` (consumption) → `AddItemForPlayer` (output) → replication/UI refresh → `SaveInventory`. AutoChest hooks `RemoveMultipleItems` (not `CraftItemSlot`) for the chest pull.
- **`ContainsItemsAmt(Items: Array<S_InventorySlotSlim>) -> Contains: Bool`** — drives BOTH the craft-time afford gate AND the tile's craftable/button-enabled display.
- **`ContainsItemAmt(Item, GivenItem) -> Contains: Bool`** — per-item version.
- **`GetAmtOfItem`** — the per-item count the material displays read; hooked to inflate with chest totals, gated to material-UI windows.
- **`RemoveMultipleItems`** — native consumption; only consumes the player's regular inventory (not hotbar/equipped, not chests), so the post-hook removes the remainder from hotbar + chests.
- **`MoveItemAmtToDiffInv(source, target, sourceIndex0, targetIndex0, amount)`** — moves between inventories with correct save/replication; used by quick-deposit (and by EnhancedChests).
- Struct fields confirmed (the `_N_HEX` suffixes are why `config.*_FIELDS` try several candidates): `S_InventorySlotSlim` → `Item_4_...` (item class), `Quantity_5_...` (int). Inventory slot array is the `Inventory` property.
- Chest detection: an inventory's `GetOuter()` full name contains `"Chest"`; the player's contains `"MainPlayerCharacter"`.
- Hook timing: for `/Game/...` (Blueprint) UFunctions, `RegisterHook`'s callback runs AFTER the native fn and its return value overrides the native return.

### Hook-registration timing pitfall (handled)

At launch, `BC_InventorySystem_C` isn't loaded yet, so `RegisterHook` fails. `hooks.register_hooks()` is deferred to `/Script/Engine.PlayerController:ClientRestart` and retried on every new `UserWidget` until `hooks.all_registered()` is true (guarded by per-hook flags so each only registers once).

## Configuration

`config.txt` in the mod root (read once at load by `config.load_file`; lines `key=value`, `#` comments):
- `scan_radius` (default `0`) — crafting chest-search radius in Unreal units (100 = 1 m); `0` = whole map.
- `deposit_radius` (default `2200`) — quick-deposit nearby range (not a whole-map value).
- `deposit_key` (default `F2`) — UE4SS `Key` enum name for quick-deposit.

`DEBUG_ENABLED` at the top of `config.lua` toggles verbose per-item traces (leave `false`; printing lags the Craft button).

## Multiplayer notes

- Each client must install the mod. Behaviour confirmed across host (listen-server, authoritative) and client (server-authoritative) sessions.
- The craft decision is recomputed fresh at click time, so another player emptying a chest in the stale-cache window can't allow a phantom craft. A microscopic race remains between the fresh recount and the decrement, but `decrement_from_inventory` always re-reads live slot quantities, so the worst case is "slightly less removed", never a chest-rollback or item loss.
- Direct chest slot writes (decrement/add) are authoritative on a listen-server; on a pure client the server may override them — an area to watch if desync is ever reported.

## Deferred work

- Hammer/build-mode ingredient *pulling* (counts already work). `SW_CurBuildableInfo_C` placement fn not reverse-engineered. Deferred by the user until crafting/cooking is solid.

## Install/sync

Single live copy: `…/ue4ss/Mods/AutoChest/`. UE4SS auto-detects the mod via the `enabled.txt` file in its folder (no `mods.txt` entry needed). After editing, no build step — restart the game (or reload UE4SS Lua mods) to apply.
