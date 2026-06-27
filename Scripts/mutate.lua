-- Writing to inventories: decrement, restore, and move items between
-- inventories. These are the only functions that mutate slot structs / call
-- the native move, and they invalidate the read caches in `inventory` after
-- changing anything.

return function(ctx)
    local config = ctx.config
    local util = ctx.util
    local inventory = ctx.inventory

    local get_inventory_array = util.get_inventory_array
    local get_param = util.get_param
    local get_slot_item = util.get_slot_item
    local get_slot_qty = util.get_slot_qty
    local get_slot_max_stack = util.get_slot_max_stack
    local find_field_name = util.find_field_name
    local same_item = util.same_item
    local full_name_of = util.full_name_of
    local log = util.log
    local log_debug = util.log_debug

    local M = {}

    -- Decrements up to `amount` of item_class from a single inventory's slots,
    -- clearing any slot that hits zero. Returns how many were actually removed.
    -- Used at the exact moment the native craft consumption happens, so chest
    -- stock is only ever touched as part of a real craft (RemoveMultipleItems
    -- is never called by the passive UI refresh).
    function M.decrement_from_inventory(inventory_system, item_class, amount)
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

            local qty_field = find_field_name(slot, config.QTY_FIELDS)

            if qty_field ~= nil then
                slot[qty_field] = new_qty

                if new_qty <= 0 then
                    local item_field = find_field_name(slot, config.ITEM_FIELDS)

                    if item_field ~= nil then
                        slot[item_field] = nil
                    end
                end

                local set_ok = pcall(function()
                    elem:set(slot)
                end)

                if set_ok then
                    removed = removed + take
                    if config.DEBUG_ENABLED then
                        log_debug("removed " .. tostring(take) .. " of " .. tostring(full_name_of(item_class)) .. " from a slot (new_qty=" .. tostring(new_qty) .. ").")
                    end
                else
                    log_debug("failed to write decremented quantity onto a slot.")
                end
            end
        end)

        return removed
    end

    -- Puts `amount` of item_class back into an inventory after a failed craft,
    -- to undo what the native RemoveMultipleItems consumed. Tops up existing
    -- same-item stacks first, then writes item_class directly into empty slots.
    -- template_slot (the recipe slot) is only read, never mutated, to discover
    -- the right field names for an inventory whose same-item slots were all
    -- emptied. Returns the amount it could not place.
    function M.add_to_inventory(inventory_system, item_class, amount, template_slot)
        local remaining = amount
        local slots = get_inventory_array(inventory_system)

        if slots == nil then
            return remaining
        end

        -- Field names for placing into an EMPTY slot can't be read off the empty
        -- slot itself (its Item is nil), so fall back to the recipe slot's names.
        -- (Pass 1 resolves the qty field off each occupied slot directly,
        -- matching decrement_from_inventory's proven approach.)
        local fallback_item_field = find_field_name(template_slot, config.ITEM_FIELDS)
        local default_max_stack = get_slot_max_stack(template_slot)

        -- Pass 1: top up existing stacks of the same item.
        slots:ForEach(function(_, elem)
            if remaining <= 0 then
                return
            end

            local slot = get_param(elem)
            local slot_item = get_slot_item(slot)
            local slot_qty = get_slot_qty(slot)

            if slot_item == nil or slot_qty <= 0 or not same_item(slot_item, item_class) then
                return
            end

            local space = get_slot_max_stack(slot) - slot_qty

            if space <= 0 then
                return
            end

            local qty_field = find_field_name(slot, config.QTY_FIELDS)

            if qty_field == nil then
                return
            end

            local add = math.min(space, remaining)
            slot[qty_field] = slot_qty + add

            if pcall(function() elem:set(slot) end) then
                remaining = remaining - add
            end
        end)

        -- Pass 2: place leftovers into empty slots by writing item_class onto the
        -- empty slot's own struct. The empty slot still exposes its Quantity
        -- field (value 0, so find_field_name resolves it), but not its Item
        -- field, so we use the recipe slot's item field name for that one.
        if remaining > 0 and fallback_item_field ~= nil then
            slots:ForEach(function(_, elem)
                if remaining <= 0 then
                    return
                end

                local slot = get_param(elem)
                local slot_item = get_slot_item(slot)
                local slot_qty = get_slot_qty(slot)

                if slot_item ~= nil and slot_qty > 0 then
                    return
                end

                local qty_field = find_field_name(slot, config.QTY_FIELDS)

                if qty_field == nil then
                    return
                end

                local place = math.min(default_max_stack, remaining)

                slot[fallback_item_field] = item_class
                slot[qty_field] = place

                if pcall(function() elem:set(slot) end) then
                    remaining = remaining - place
                end
            end)
        end

        return remaining
    end

    -- Removes `amount` of item_class, taking from the player's own inventory
    -- first (this covers items the native craft removal left behind, e.g.
    -- hotbar slots it does not consume) and then from chests. Returns true if
    -- fully removed.
    function M.remove_amount(player_inventory, item_class, amount)
        local remaining = amount - M.decrement_from_inventory(player_inventory, item_class, amount)

        for _, chest_inventory in ipairs(inventory.get_relevant_chest_inventories(player_inventory)) do
            if remaining <= 0 then
                break
            end

            remaining = remaining - M.decrement_from_inventory(chest_inventory, item_class, remaining)
        end

        inventory.invalidate_inventory_totals()

        return remaining <= 0
    end

    -- Moves `amount` from one inventory slot to another via the game's own
    -- MoveItemAmtToDiffInv UFunction (so the transfer saves and replicates
    -- correctly — the same native call the in-game quick-stack button uses).
    function M.move_amount(source_inventory, target_inventory, source_index_zero, target_index_zero, amount)
        local fn = source_inventory["MoveItemAmtToDiffInv"]

        if fn == nil or not fn:IsValid() then
            log("Quick-deposit move failed: MoveItemAmtToDiffInv was not available.")
            return false
        end

        local ok, err = pcall(function()
            fn(source_inventory, target_inventory, source_index_zero, target_index_zero, amount)
        end)

        if not ok then
            log("Quick-deposit move failed: " .. tostring(err))
        end

        return ok
    end

    -- Moves each of the source inventory's stacks into the first target slot
    -- that already holds the same item. Only tops up existing matching stacks,
    -- so a chest with no slot for that item receives nothing. Returns stacks
    -- moved.
    function M.top_up_matching_stacks(target_inventory_system, source_inventory_system)
        local target_slots = get_inventory_array(target_inventory_system)
        local source_slots = get_inventory_array(source_inventory_system)

        if target_slots == nil or source_slots == nil then
            return 0
        end

        local moved_stacks = 0

        source_slots:ForEach(function(source_lua_index, source_elem)
            local source_slot = get_param(source_elem)
            local source_item = get_slot_item(source_slot)
            local source_qty = get_slot_qty(source_slot)

            if source_item == nil or source_qty <= 0 then
                return
            end

            local source_index_zero = source_lua_index - 1

            target_slots:ForEach(function(target_lua_index, target_elem)
                local target_slot = get_param(target_elem)
                local target_item = get_slot_item(target_slot)
                local target_qty = get_slot_qty(target_slot)

                -- Only deposit into a slot that already holds the same item.
                if target_item == nil or target_qty <= 0 or not same_item(source_item, target_item) then
                    return
                end

                local target_index_zero = target_lua_index - 1

                if M.move_amount(source_inventory_system, target_inventory_system, source_index_zero, target_index_zero, source_qty) then
                    moved_stacks = moved_stacks + 1
                    return true
                end
            end)
        end)

        return moved_stacks
    end

    return M
end
