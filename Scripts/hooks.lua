-- The crafting/affordability hooks on BC_InventorySystem_C and the crafting UI
-- widgets, plus their registration. Owns the material-UI gating state and the
-- per-craft player snapshot used to reconcile what the native removal consumed.
--
-- NOTE: For /Game/... (Blueprint) UFunctions, RegisterHook's single callback
-- runs AFTER the native function executes, and its return value overrides the
-- native function's return value.

return function(ctx)
    local config = ctx.config
    local util = ctx.util
    local inventory = ctx.inventory
    local mutate = ctx.mutate

    local get_param = util.get_param
    local set_param = util.set_param
    local is_valid = util.is_valid
    local get_slot_item = util.get_slot_item
    local get_slot_qty = util.get_slot_qty
    local full_name_of = util.full_name_of
    local log = util.log
    local log_debug = util.log_debug
    local now_seconds = util.now_seconds

    local M = {}

    -- Player count per item captured during the affordability check that runs
    -- immediately before the native craft removal. Lets the removal hook tell
    -- how much the native pass actually consumed from the player.
    local pre_craft_counts = {}

    -- GetAmtOfItem is called all over the game (HUD, quests, etc.), not just by
    -- the crafting/building material displays. Inflating + chest-scanning on
    -- every such call is wasteful and would leak chest contents into unrelated
    -- counts. So we only override it while a material display (crafting tiles or
    -- the build menu's SW_MissingBuildingParts widget) is actively refreshing,
    -- which the relevant hooks timestamp here. This gating only switches on if
    -- we successfully detect the build-mode widget; otherwise we fall back to
    -- overriding globally so build mode still shows combined counts.
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

    -- Fires only as part of an actual craft consumption (never from the passive
    -- UI refresh). By the time this post-hook runs, the native removal has
    -- already taken whatever it could from the player's regular inventory slots.
    -- But the native removal does NOT touch hotbar/equipped slots, so items
    -- sitting there (and items still only in chests) are left unconsumed even
    -- though the craft succeeds. We compute how much the native pass actually
    -- consumed (using the player count captured before it ran) and remove the
    -- remainder ourselves.
    local function on_remove_multiple_items_post(context, items_param, save_param, ignored_param, success_param)
        local player_inventory = get_param(context)
        local items = get_param(items_param)

        if not is_valid(player_inventory) or items == nil then
            return nil
        end

        -- This hook fires ONLY on a real craft (a click), never on the passive
        -- UI refresh, so the per-frame UI path keeps using the cached counts and
        -- stays fast. Here, at craft time, we deliberately drop ALL cached counts
        -- and recompute the affordability decision (all_ok below) from the true,
        -- CURRENT contents of the player inventory AND every chest. This is the
        -- "check before, never roll back after" guarantee: we only ever
        -- decrement a chest once this live recount has confirmed the whole recipe
        -- is covered, so we never have to put anything back into a chest. In
        -- multiplayer it is also what keeps the decision correct when another
        -- player has just emptied a chest a moment ago. The one fresh chest
        -- rescan this costs is the small craft-time hitch; it does not affect UI
        -- smoothness.
        inventory.invalidate_all_totals()

        -- First pass: work out what each item still needs removed and confirm the
        -- whole recipe can be fully satisfied before touching anything. We must
        -- not remove partially, or a non-craftable recipe would eat ingredients
        -- for no output.
        local removals = {}
        local restorations = {}
        local any_work = false
        local all_ok = true

        items:ForEach(function(_, elem)
            local slot = get_param(elem)
            local item_class = get_slot_item(slot)
            local qty_needed = get_slot_qty(slot)

            if item_class ~= nil and qty_needed > 0 then
                local key = full_name_of(item_class)
                local pre = key ~= nil and pre_craft_counts[key] or nil
                local now_player = inventory.count_item_in_inventory(player_inventory, item_class)

                -- Track what the native pass already took from the player so we
                -- can give it back if the recipe turns out to be uncraftable.
                if pre ~= nil then
                    local native_removed = pre - now_player
                    if native_removed > 0 then
                        table.insert(restorations, { item_class = item_class, amount = native_removed, template = slot })
                    end
                end

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

                    -- Early-break check: stops as soon as enough is found (and
                    -- never touches chests if the player alone already covers it).
                    if inventory.has_enough_with_chests(player_inventory, item_class, still_needed, key) then
                        table.insert(removals, { item_class = item_class, amount = still_needed })
                    else
                        all_ok = false
                    end
                end
            end
        end)

        -- Native already consumed everything needed: nothing for us to do.
        if not any_work then
            return nil
        end

        -- Can't fully satisfy the recipe: undo what native already took from the
        -- player so a failed craft never eats components, force failure so no
        -- output item is produced, and let the craft abort.
        if not all_ok then
            for _, entry in ipairs(restorations) do
                mutate.add_to_inventory(player_inventory, entry.item_class, entry.amount, entry.template)
            end

            inventory.invalidate_all_totals()

            set_param(success_param, false)
            return false
        end

        for _, entry in ipairs(removals) do
            mutate.remove_amount(player_inventory, entry.item_class, entry.amount)
        end

        set_param(success_param, true)
        return true
    end

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
                -- Snapshot the player's count now (before the native craft
                -- removal that may follow this check) so the removal hook can
                -- tell how much native actually consumed.
                local key = full_name_of(item_class)
                if key ~= nil then
                    pre_craft_counts[key] = inventory.count_item_in_inventory(player_inventory, item_class, key)
                end

                local enough = inventory.has_enough_with_chests(player_inventory, item_class, qty_needed, key)

                if config.DEBUG_ENABLED then
                    log_debug("ContainsItemsAmt item=" .. tostring(key) .. " needed=" .. tostring(qty_needed) .. " enough=" .. tostring(enough))
                end

                if not enough then
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

        if inventory.has_enough_with_chests(player_inventory, item_class, qty_needed) then
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

        local player_inventory = inventory.get_player_inventory()

        if not is_valid(player_inventory) then
            return nil
        end

        if inventory.has_enough_with_chests(player_inventory, item_class, qty_needed) then
            set_param(return_param, true)
            return true
        end

        return nil
    end

    -- Marks build-mode material display as active. The build menu rebuilds this
    -- widget (and calls GetAmtOfItem from it) as you browse buildables, so a
    -- fresh timestamp here keeps GetAmtOfItem overridden throughout build mode.
    local function on_building_parts_construct(context)
        mark_material_ui_activity()
    end

    local function on_get_amt_of_item_post(context, param1, param2)
        if inventory.is_chest_lookup_in_progress() then
            return nil
        end

        -- Only inflate with chest contents while a crafting/build material
        -- display is active (when gating is enabled). Otherwise leave the native
        -- value so we don't periodically scan chests or leak chest counts into
        -- HUD/quests.
        if gating_enabled and not material_ui_active() then
            return nil
        end

        local inventory_system = get_param(context)
        local value1 = get_param(param1)
        local value2 = get_param(param2)

        if not is_valid(inventory_system) or value1 == nil or inventory.is_chest_inventory(inventory_system) then
            return nil
        end

        local item_class = get_slot_item(value1) or value1

        local total = inventory.get_total_amount_with_chests(inventory_system, item_class)

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

    function M.register_hooks()
        if not contains_hook_registered then
            local ok_contains, err_contains = pcall(function()
                RegisterHook(config.CONTAINS_ITEMS_AMT, on_contains_items_amt_post)
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
                RegisterHook(config.CONTAINS_ITEM_AMT, on_contains_item_amt_post)
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
                RegisterHook(config.GET_AMT_OF_ITEM, on_get_amt_of_item_post)
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
                RegisterHook(config.REMOVE_MULTIPLE_ITEMS, on_remove_multiple_items_post)
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

            for _, function_path in ipairs(config.HAS_ENOUGH_PARTS_FUNCTIONS) do
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
        -- not found), gating_enabled stays false and GetAmtOfItem keeps
        -- overriding globally, so build mode still shows combined counts.
        if not building_parts_hook_registered and building_parts_attempts < BUILDING_PARTS_MAX_ATTEMPTS then
            building_parts_attempts = building_parts_attempts + 1

            for _, function_path in ipairs(config.BUILDING_PARTS_CONSTRUCT_FUNCTIONS) do
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

    -- True once every hook we care about is registered (the building-parts hook
    -- is considered done after the attempt budget is exhausted, since it may not
    -- exist on this build). Used to stop re-attempting on every new widget.
    function M.all_registered()
        local building_done = building_parts_hook_registered or building_parts_attempts >= BUILDING_PARTS_MAX_ATTEMPTS

        return contains_hook_registered and contains_item_hook_registered and get_amt_hook_registered
            and remove_multiple_hook_registered and has_enough_parts_hooks_registered and building_done
    end

    return M
end
