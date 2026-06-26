local MOD = "[AutoChest] "

-- Set to true to print verbose per-item DEBUG traces. Leave false in normal
-- play: these fire hundreds of times per crafting-UI refresh and printing to
-- the UE4SS console is slow enough to noticeably lag the Craft button.
local DEBUG_ENABLED = false

local INVENTORY_SYSTEM_CLASS = "BC_InventorySystem_C"

local CONTAINS_ITEMS_AMT =
    "/Game/Code/Inventory_Items/Framework_and_Data/BC_InventorySystem.BC_InventorySystem_C:ContainsItemsAmt"

local CONTAINS_ITEM_AMT =
    "/Game/Code/Inventory_Items/Framework_and_Data/BC_InventorySystem.BC_InventorySystem_C:ContainsItemAmt"

local GET_AMT_OF_ITEM =
    "/Game/Code/Inventory_Items/Framework_and_Data/BC_InventorySystem.BC_InventorySystem_C:GetAmtOfItem"

local REMOVE_MULTIPLE_ITEMS =
    "/Game/Code/Inventory_Items/Framework_and_Data/BC_InventorySystem.BC_InventorySystem_C:RemoveMultipleItems"

-- The Craft button's click handler appears to gate on these widget checks
-- (seen registered by other mods doing similar "ignore the cost" features)
-- rather than re-running ContainsItemsAmt itself, so they need their own
-- override too or the click silently no-ops when chests are needed.
local HAS_ENOUGH_PARTS_FUNCTIONS = {
    "/Game/UI/Widgets/WidgetComponents/SW_MissingCraftingPartsSlot.SW_MissingCraftingPartsSlot_C:HasEnoughParts?",
    "/Game/UI/Widgets/WidgetComponents/SW_MissingCraftingPartsSlot_DualLine.SW_MissingCraftingPartsSlot_DualLine_C:HasEnoughParts?",
    "/Game/UI/Widgets/WidgetComponents/SW_MissingCraftingPartsSlot_Vertical.SW_MissingCraftingPartsSlot_Vertical_C:HasEnoughParts?",
}

-- Build mode shows required materials through SW_MissingBuildingParts, whose
-- Construct calls GetAmtOfItem (confirmed via an EventViewer GetAmtOfItem entry
-- capture). Hooking its Construct lets us detect build mode as a material-UI
-- activity. Several candidate asset paths are tried since the exact folder
-- isn't known; whichever registers is used.
local BUILDING_PARTS_CONSTRUCT_FUNCTIONS = {
    "/Game/UI/Widgets/WidgetComponents/SW_MissingBuildingParts.SW_MissingBuildingParts_C:Construct",
    "/Game/UI/Widgets/SW_MissingBuildingParts.SW_MissingBuildingParts_C:Construct",
    "/Game/UI/Widgets/Build/SW_MissingBuildingParts.SW_MissingBuildingParts_C:Construct",
    "/Game/UI/Widgets/BuildMode/SW_MissingBuildingParts.SW_MissingBuildingParts_C:Construct",
}

local ITEM_FIELDS = {
    "Item",
    "Item_4_B9922CA845A5618A776EAFAB1A690E93",
    "ItemActor",
    "ItemActor_16_A80D2B2B49E59CC810744B999AEA8F92",
}

local QTY_FIELDS = {
    "Quantity",
    "Quantity_5_A1813C42482CE5E7961C589A983BD034",
    "Amount",
    "Amount_5_12AB5DA84DB6E8C535AD7D82D7F29009",
}

local function log(message)
    print(MOD .. tostring(message) .. "\n")
end

local function log_debug(message)
    if DEBUG_ENABLED then
        print(MOD .. "DEBUG: " .. tostring(message) .. "\n")
    end
end

local clock_available = pcall(function() return os.clock() end)

local function now_seconds()
    if clock_available then
        return os.clock()
    end

    return nil
end

local function is_valid(obj)
    if type(obj) ~= "table" and type(obj) ~= "userdata" then
        return false
    end

    local ok, result = pcall(function()
        return obj.IsValid ~= nil and obj:IsValid()
    end)

    return ok and result
end

local function get_param(param)
    if param ~= nil and param.get ~= nil then
        local ok, value = pcall(function()
            return param:get()
        end)

        if ok then
            return value
        end
    end

    return param
end

local function set_param(param, value)
    if param ~= nil and param.set ~= nil then
        pcall(function()
            param:set(value)
        end)
    end
end

local function try_get(obj, fields)
    if obj == nil then
        return nil
    end

    for _, field in ipairs(fields) do
        local ok, value = pcall(function()
            return obj[field]
        end)

        if ok and value ~= nil then
            return value
        end
    end

    return nil
end

local function find_field_name(obj, fields)
    if obj == nil then
        return nil
    end

    for _, field in ipairs(fields) do
        local ok, value = pcall(function()
            return obj[field]
        end)

        if ok and value ~= nil then
            return field
        end
    end

    return nil
end

local function full_name_of(obj)
    if not is_valid(obj) or obj.GetFullName == nil then
        return nil
    end

    local ok, full_name = pcall(function()
        return obj:GetFullName()
    end)

    if ok then
        return tostring(full_name)
    end

    return nil
end

local function get_outer(obj)
    if not is_valid(obj) or obj.GetOuter == nil then
        return nil
    end

    local ok, outer = pcall(function()
        return obj:GetOuter()
    end)

    if ok and is_valid(outer) then
        return outer
    end

    return nil
end

local function object_key(obj)
    if obj == nil then
        return nil
    end

    if is_valid(obj) then
        return full_name_of(obj)
    end

    return tostring(obj)
end

local function same_item(a, b)
    local a_key = object_key(a)
    local b_key = object_key(b)

    return a_key ~= nil and b_key ~= nil and a_key == b_key
end

local function get_slot_item(slot)
    return try_get(slot, ITEM_FIELDS)
end

local function get_slot_qty(slot)
    local value = try_get(slot, QTY_FIELDS)

    if value == nil then
        return 0
    end

    return tonumber(value) or 0
end

local function get_inventory_array(inventory_system)
    if not is_valid(inventory_system) then
        return nil
    end

    local ok, inventory = pcall(function()
        return inventory_system.Inventory
    end)

    if ok then
        return inventory
    end

    return nil
end

local function is_chest_inventory(inventory_system)
    local owner_name = full_name_of(get_outer(inventory_system))
    return owner_name ~= nil and string.find(owner_name, "Chest", 1, true) ~= nil
end

-- Tallies every slot of an inventory into a {item_key -> qty} map in one
-- pass, instead of calling the native GetAmtOfItem UFunction (its real
-- parameter types/marshaling proved too fragile to call manually from Lua:
-- struct "Item" param, mystery numeric 2nd param, "Out" param table errors)
-- and instead of rescanning all slots once per distinct item queried (a
-- recipe list with many ingredients was slow enough to freeze the game).
local function build_inventory_totals_map(inventory_system)
    local totals = {}

    if not is_valid(inventory_system) then
        return totals
    end

    local slots = get_inventory_array(inventory_system)

    if slots == nil then
        return totals
    end

    slots:ForEach(function(_, elem)
        local slot = get_param(elem)
        local slot_item = get_slot_item(slot)
        local slot_qty = get_slot_qty(slot)

        if slot_item ~= nil and slot_qty > 0 then
            local key = full_name_of(slot_item)

            if key ~= nil then
                totals[key] = (totals[key] or 0) + slot_qty
            end
        end
    end)

    return totals
end

local INVENTORY_TOTALS_TTL_SECONDS = 0.5
local inventory_totals_cache = {}

local function get_inventory_totals_map(inventory_system)
    local key = full_name_of(inventory_system)

    if key == nil then
        return build_inventory_totals_map(inventory_system)
    end

    local now = now_seconds()
    local cached = inventory_totals_cache[key]

    if now ~= nil and cached ~= nil and (now - cached.time) < INVENTORY_TOTALS_TTL_SECONDS then
        return cached.totals
    end

    local totals = build_inventory_totals_map(inventory_system)

    if now ~= nil then
        inventory_totals_cache[key] = { totals = totals, time = now }
    end

    return totals
end

local function count_item_in_inventory(inventory_system, item_class)
    if item_class == nil then
        return 0
    end

    local item_key = full_name_of(item_class)

    if item_key == nil then
        return 0
    end

    return get_inventory_totals_map(inventory_system)[item_key] or 0
end

-- FindAllOf scans every instance of the class in the world, then GetOuter()
-- + GetFullName() each one to filter chests. That's heavy to repeat on every
-- single GetAmtOfItem/ContainsItemAmt call (which can happen dozens of times
-- per refresh burst). FindAllOf scans every UObject in the world, which is the
-- single most expensive thing we do and the cause of periodic micro freezes if
-- run often (the game polls GetAmtOfItem from HUD/quests/etc.). Chests rarely
-- appear or disappear, so cache the list for a good while. Chest *contents*
-- stay fresh independently via inventory_totals_cache below.
local CHEST_LIST_TTL_SECONDS = 10.0
local chest_list_cache = nil
local chest_list_cache_time = nil

local function get_all_chest_inventories(player_inventory)
    local now = now_seconds()

    if now ~= nil and chest_list_cache ~= nil and (now - chest_list_cache_time) < CHEST_LIST_TTL_SECONDS then
        return chest_list_cache
    end

    local result = {}
    local all_inventories = FindAllOf(INVENTORY_SYSTEM_CLASS)

    if all_inventories ~= nil then
        for _, inventory_system in ipairs(all_inventories) do
            if is_valid(inventory_system) and inventory_system ~= player_inventory and is_chest_inventory(inventory_system) then
                table.insert(result, inventory_system)
            end
        end
    end

    if now ~= nil then
        chest_list_cache = result
        chest_list_cache_time = now
    end

    return result
end

-- HasEnoughParts? is called on a UI widget (self = the widget, not an
-- inventory), so we need to separately find the player's own inventory
-- instance to compute combined totals. This also uses FindAllOf, and the
-- player's inventory object is stable for the session, so cache it for a good
-- while too (re-resolved if it ever becomes invalid, e.g. on respawn).
local PLAYER_INVENTORY_TTL_SECONDS = 10.0
local player_inventory_cache = nil
local player_inventory_cache_time = nil

local function get_player_inventory()
    local now = now_seconds()

    if now ~= nil and player_inventory_cache ~= nil and is_valid(player_inventory_cache)
        and (now - player_inventory_cache_time) < PLAYER_INVENTORY_TTL_SECONDS then
        return player_inventory_cache
    end

    local result = nil
    local all_inventories = FindAllOf(INVENTORY_SYSTEM_CLASS)

    if all_inventories ~= nil then
        for _, inventory_system in ipairs(all_inventories) do
            local owner_name = full_name_of(get_outer(inventory_system))

            if owner_name ~= nil and string.find(owner_name, "MainPlayerCharacter", 1, true) ~= nil then
                result = inventory_system
                break
            end
        end
    end

    if now ~= nil then
        player_inventory_cache = result
        player_inventory_cache_time = now
    end

    return result
end

local chest_lookup_in_progress = false

-- This is queried very frequently (potentially once per visible inventory
-- slot, every UI refresh tick), and a full re-scan of every chest's every
-- slot on each call was heavy enough to freeze the game. Cache results
-- briefly so bursts of calls within the same refresh reuse one computation.
local total_cache = {}
local CACHE_TTL_SECONDS = 0.25

-- Player count per item captured during the affordability check that runs
-- immediately before the native craft removal. Lets the removal hook tell how
-- much the native pass actually consumed from the player (see its comment).
local pre_craft_counts = {}

-- GetAmtOfItem is called all over the game (HUD, quests, etc.), not just by the
-- crafting/building material displays. Inflating + chest-scanning on every such
-- call is wasteful and would leak chest contents into unrelated counts. So we
-- only override it while a material display (crafting tiles or the build menu's
-- SW_MissingBuildingParts widget) is actively refreshing, which the relevant
-- hooks timestamp here. This gating only switches on if we successfully detect
-- the build-mode widget; otherwise we fall back to overriding globally so build
-- mode still shows combined counts (see gating_enabled below).
local MATERIAL_UI_WINDOW_SECONDS = 2.0
local last_material_ui_activity = nil
local gating_enabled = false

local function mark_material_ui_activity()
    last_material_ui_activity = now_seconds()
end

local function material_ui_active()
    if last_material_ui_activity == nil then
        return false
    end

    local now = now_seconds()

    if now == nil then
        return true
    end

    return (now - last_material_ui_activity) < MATERIAL_UI_WINDOW_SECONDS
end

local function get_total_amount_with_chests(player_inventory, item_class)
    local cache_key = full_name_of(item_class) or tostring(item_class)
    local now = now_seconds()

    if cache_key ~= nil and now ~= nil then
        local cached = total_cache[cache_key]

        if cached ~= nil and (now - cached.time) < CACHE_TTL_SECONDS then
            return cached.value
        end
    end

    chest_lookup_in_progress = true

    local ok, total = pcall(function()
        local sum = count_item_in_inventory(player_inventory, item_class)

        for _, chest_inventory in ipairs(get_all_chest_inventories(player_inventory)) do
            sum = sum + count_item_in_inventory(chest_inventory, item_class)
        end

        return sum
    end)

    chest_lookup_in_progress = false

    local result = ok and total or 0

    if cache_key ~= nil and now ~= nil then
        total_cache[cache_key] = { value = result, time = now }
    end

    return result
end

-- Decrements chest slot quantities directly (clearing the slot if it hits
-- zero) without ever depositing the items into the player's inventory.
-- Used at the exact moment the native craft consumption happens, so chest
-- stock is only ever touched as part of a real craft (RemoveMultipleItems
-- is never called by the passive UI refresh).
-- Decrements up to `amount` of item_class from a single inventory's slots,
-- clearing any slot that hits zero. Returns how many were actually removed.
local function decrement_from_inventory(inventory_system, item_class, amount)
    local removed = 0
    local slots = get_inventory_array(inventory_system)

    if slots == nil then
        return 0
    end

    slots:ForEach(function(_, elem)
        if removed >= amount then
            return
        end

        local slot = get_param(elem)
        local slot_item = get_slot_item(slot)
        local slot_qty = get_slot_qty(slot)

        if slot_item == nil or slot_qty <= 0 or not same_item(slot_item, item_class) then
            return
        end

        local take = math.min(slot_qty, amount - removed)
        local new_qty = slot_qty - take

        local qty_field = find_field_name(slot, QTY_FIELDS)

        if qty_field ~= nil then
            slot[qty_field] = new_qty

            if new_qty <= 0 then
                local item_field = find_field_name(slot, ITEM_FIELDS)

                if item_field ~= nil then
                    slot[item_field] = nil
                end
            end

            local set_ok = pcall(function()
                elem:set(slot)
            end)

            if set_ok then
                removed = removed + take
                log_debug("removed " .. tostring(take) .. " of " .. tostring(full_name_of(item_class)) .. " from a slot (new_qty=" .. tostring(new_qty) .. ").")
            else
                log_debug("failed to write decremented quantity onto a slot.")
            end
        end
    end)

    return removed
end

-- Removes `amount` of item_class, taking from the player's own inventory first
-- (this covers items the native craft removal left behind, e.g. hotbar slots
-- it does not consume) and then from chests. Returns true if fully removed.
local function remove_amount(player_inventory, item_class, amount)
    local remaining = amount - decrement_from_inventory(player_inventory, item_class, amount)

    for _, chest_inventory in ipairs(get_all_chest_inventories(player_inventory)) do
        if remaining <= 0 then
            break
        end

        remaining = remaining - decrement_from_inventory(chest_inventory, item_class, remaining)
    end

    inventory_totals_cache = {}

    return remaining <= 0
end

-- Fires only as part of an actual craft consumption (never from the passive
-- UI refresh). By the time this post-hook runs, the native removal has already
-- taken whatever it could from the player's regular inventory slots. But the
-- native removal does NOT touch hotbar/equipped slots, so items sitting there
-- (and items still only in chests) are left unconsumed even though the craft
-- succeeds. We compute how much the native pass actually consumed (using the
-- player count captured before it ran) and remove the remainder ourselves.
local function on_remove_multiple_items_post(context, items_param, save_param, ignored_param, success_param)
    local player_inventory = get_param(context)
    local items = get_param(items_param)

    if not is_valid(player_inventory) or items == nil then
        return nil
    end

    -- The native removal just mutated the real inventory; drop cached counts so
    -- we read the true post-removal numbers below.
    inventory_totals_cache = {}
    total_cache = {}

    -- First pass: work out what each item still needs removed and confirm the
    -- whole recipe can be fully satisfied before touching anything. We must not
    -- remove partially, or a non-craftable recipe would eat ingredients for no
    -- output.
    local removals = {}
    local any_work = false
    local all_ok = true

    items:ForEach(function(_, elem)
        local slot = get_param(elem)
        local item_class = get_slot_item(slot)
        local qty_needed = get_slot_qty(slot)

        if item_class ~= nil and qty_needed > 0 then
            local key = full_name_of(item_class)
            local pre = key ~= nil and pre_craft_counts[key] or nil
            local now_player = count_item_in_inventory(player_inventory, item_class)

            local still_needed
            if pre ~= nil then
                -- How much native actually consumed from the player this craft.
                local native_removed = pre - now_player
                if native_removed < 0 then native_removed = 0 end
                still_needed = qty_needed - native_removed
            else
                -- No pre-count captured: fall back to topping up only the
                -- shortfall the player no longer has, which avoids ever
                -- double-removing on top of the native pass.
                still_needed = qty_needed - now_player
            end

            if still_needed > 0 then
                any_work = true

                local total_available = get_total_amount_with_chests(player_inventory, item_class)

                if total_available < still_needed then
                    all_ok = false
                else
                    table.insert(removals, { item_class = item_class, amount = still_needed })
                end
            end
        end
    end)

    -- Native already consumed everything needed: nothing for us to do.
    if not any_work then
        return nil
    end

    -- Can't fully satisfy the recipe: don't remove anything, let the craft fail.
    if not all_ok then
        return nil
    end

    for _, entry in ipairs(removals) do
        remove_amount(player_inventory, entry.item_class, entry.amount)
    end

    set_param(success_param, true)
    return true
end

-- NOTE: For /Game/... (Blueprint) UFunctions, RegisterHook's single callback runs
-- AFTER the native function executes, and its return value overrides the native
-- function's return value (see Docs/lua-api/global-functions/registerhook.md).

local function on_contains_items_amt_post(context, items_param, contains_param)
    local player_inventory = get_param(context)
    local items = get_param(items_param)

    if not is_valid(player_inventory) or items == nil then
        return nil
    end

    mark_material_ui_activity()

    local all_satisfied = true

    items:ForEach(function(_, elem)
        local slot = get_param(elem)
        local item_class = get_slot_item(slot)
        local qty_needed = get_slot_qty(slot)

        if item_class ~= nil and qty_needed > 0 then
            -- Snapshot the player's count now (before the native craft removal
            -- that may follow this check) so the removal hook can tell how much
            -- native actually consumed.
            local key = full_name_of(item_class)
            if key ~= nil then
                pre_craft_counts[key] = count_item_in_inventory(player_inventory, item_class)
            end

            local total = get_total_amount_with_chests(player_inventory, item_class)

            log_debug("ContainsItemsAmt item=" .. tostring(full_name_of(item_class)) .. " needed=" .. tostring(qty_needed) .. " total=" .. tostring(total))

            if total < qty_needed then
                all_satisfied = false
            end
        end
    end)

    if all_satisfied then
        set_param(contains_param, true)
        return true
    end

    return nil
end

local function on_contains_item_amt_post(context, slot_param, contains_param)
    local player_inventory = get_param(context)
    local slot = get_param(slot_param)

    if not is_valid(player_inventory) or slot == nil then
        return nil
    end

    local item_class = get_slot_item(slot)
    local qty_needed = get_slot_qty(slot)

    if item_class == nil or qty_needed <= 0 then
        return nil
    end

    local total = get_total_amount_with_chests(player_inventory, item_class)

    if total >= qty_needed then
        set_param(contains_param, true)
        return true
    end

    return nil
end

-- HasEnoughParts? is called with no input parameters (self = the crafting
-- tile widget, holding its own Item/Quantity fields), unlike the
-- BC_InventorySystem_C functions above.
local function on_has_enough_parts_post(context, return_param)
    local widget = get_param(context)

    if not is_valid(widget) then
        return nil
    end

    mark_material_ui_activity()

    local item_class = get_slot_item(widget)
    local qty_needed = get_slot_qty(widget)

    if item_class == nil or qty_needed <= 0 then
        return nil
    end

    local player_inventory = get_player_inventory()

    if not is_valid(player_inventory) then
        return nil
    end

    local total = get_total_amount_with_chests(player_inventory, item_class)

    if total >= qty_needed then
        set_param(return_param, true)
        return true
    end

    return nil
end

-- Marks build-mode material display as active. The build menu rebuilds this
-- widget (and calls GetAmtOfItem from it) as you browse buildables, so a fresh
-- timestamp here keeps GetAmtOfItem overridden throughout build mode.
local function on_building_parts_construct(context)
    mark_material_ui_activity()
end

local function on_get_amt_of_item_post(context, param1, param2)
    if chest_lookup_in_progress then
        return nil
    end

    -- Only inflate with chest contents while a crafting/build material display
    -- is active (when gating is enabled). Otherwise leave the native value so we
    -- don't periodically scan chests or leak chest counts into HUD/quests.
    if gating_enabled and not material_ui_active() then
        return nil
    end

    local inventory_system = get_param(context)
    local value1 = get_param(param1)
    local value2 = get_param(param2)

    if not is_valid(inventory_system) or value1 == nil or is_chest_inventory(inventory_system) then
        return nil
    end

    local item_class = get_slot_item(value1) or value1

    local total = get_total_amount_with_chests(inventory_system, item_class)

    set_param(param2, total)

    return total
end

local contains_hook_registered = false
local contains_item_hook_registered = false
local get_amt_hook_registered = false
local remove_multiple_hook_registered = false
local has_enough_parts_hooks_registered = false
local building_parts_hook_registered = false
local building_parts_attempts = 0
local BUILDING_PARTS_MAX_ATTEMPTS = 120

local function register_hooks()
    if not contains_hook_registered then
        local ok_contains, err_contains = pcall(function()
            RegisterHook(CONTAINS_ITEMS_AMT, on_contains_items_amt_post)
        end)

        if ok_contains then
            contains_hook_registered = true
            log("Registered ContainsItemsAmt override hook.")
        else
            log("Could not register ContainsItemsAmt hook: " .. tostring(err_contains))
        end
    end

    if not contains_item_hook_registered then
        local ok_contains_item, err_contains_item = pcall(function()
            RegisterHook(CONTAINS_ITEM_AMT, on_contains_item_amt_post)
        end)

        if ok_contains_item then
            contains_item_hook_registered = true
            log("Registered ContainsItemAmt override hook.")
        else
            log("Could not register ContainsItemAmt hook: " .. tostring(err_contains_item))
        end
    end

    if not get_amt_hook_registered then
        local ok_get_amt, err_get_amt = pcall(function()
            RegisterHook(GET_AMT_OF_ITEM, on_get_amt_of_item_post)
        end)

        if ok_get_amt then
            get_amt_hook_registered = true
            log("Registered GetAmtOfItem override hook.")
        else
            log("Could not register GetAmtOfItem hook: " .. tostring(err_get_amt))
        end
    end

    if not remove_multiple_hook_registered then
        local ok_remove, err_remove = pcall(function()
            RegisterHook(REMOVE_MULTIPLE_ITEMS, on_remove_multiple_items_post)
        end)

        if ok_remove then
            remove_multiple_hook_registered = true
            log("Registered RemoveMultipleItems chest pull hook.")
        else
            log("Could not register RemoveMultipleItems hook: " .. tostring(err_remove))
        end
    end

    if not has_enough_parts_hooks_registered then
        local all_ok = true

        for _, function_path in ipairs(HAS_ENOUGH_PARTS_FUNCTIONS) do
            local ok_parts, err_parts = pcall(function()
                RegisterHook(function_path, on_has_enough_parts_post)
            end)

            if ok_parts then
                log("Registered HasEnoughParts? override hook for " .. function_path)
            else
                all_ok = false
                log("Could not register HasEnoughParts? hook for " .. function_path .. ": " .. tostring(err_parts))
            end
        end

        if all_ok then
            has_enough_parts_hooks_registered = true
        end
    end

    -- Best-effort: detect build mode so GetAmtOfItem only overrides during a
    -- material display. If none of the candidate paths ever registers (class
    -- not found), gating_enabled stays false and GetAmtOfItem keeps overriding
    -- globally, so build mode still shows combined counts (no regression).
    if not building_parts_hook_registered and building_parts_attempts < BUILDING_PARTS_MAX_ATTEMPTS then
        building_parts_attempts = building_parts_attempts + 1

        for _, function_path in ipairs(BUILDING_PARTS_CONSTRUCT_FUNCTIONS) do
            local ok_build = pcall(function()
                RegisterHook(function_path, on_building_parts_construct)
            end)

            if ok_build then
                building_parts_hook_registered = true
                gating_enabled = true
                log("Registered build-mode material widget hook (GetAmtOfItem gating enabled): " .. function_path)
                break
            end
        end
    end
end

RegisterHook("/Script/Engine.PlayerController:ClientRestart", function()
    ExecuteInGameThread(register_hooks)
end)

NotifyOnNewObject("/Script/UMG.UserWidget", function(widget)
    local building_done = building_parts_hook_registered or building_parts_attempts >= BUILDING_PARTS_MAX_ATTEMPTS

    if not (contains_hook_registered and contains_item_hook_registered and get_amt_hook_registered and remove_multiple_hook_registered and has_enough_parts_hooks_registered and building_done) then
        ExecuteInGameThread(register_hooks)
    end
end)

log("Loaded.")
