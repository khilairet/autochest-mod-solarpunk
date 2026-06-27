-- Quick-deposit hotkey: push inventory items into nearby chests that already
-- hold that same item (e.g. dump your wood into the chest that already has
-- wood). Finds nearby chests, then tops up their matching stacks via mutate.

return function(ctx)
    local config = ctx.config
    local util = ctx.util
    local inventory = ctx.inventory
    local mutate = ctx.mutate

    local is_valid = util.is_valid
    local log = util.log

    local M = {}

    local quick_deposit_running = false

    function M.quick_deposit_to_nearby_chests()
        if quick_deposit_running then
            return
        end

        local player_inventory = inventory.get_player_inventory()

        if not is_valid(player_inventory) then
            log("Quick-deposit skipped: player inventory not found.")
            return
        end

        quick_deposit_running = true

        local all_chests = inventory.get_all_chest_inventories(player_inventory)
        local nearby = inventory.filter_chests_within_radius(player_inventory, all_chests, config.deposit_radius)
        local moved_stacks = 0

        for _, chest in ipairs(nearby) do
            moved_stacks = moved_stacks + mutate.top_up_matching_stacks(chest, player_inventory)
        end

        -- Player and chest contents just changed; drop cached counts so the next
        -- craft/affordability check reflects the new distribution.
        inventory.invalidate_all_totals()

        if moved_stacks > 0 then
            log("Quick-deposit moved " .. tostring(moved_stacks) .. " stack(s) into nearby chests.")
        end

        quick_deposit_running = false
    end

    function M.register_keybind()
        if RegisterKeyBind == nil or Key == nil then
            log("Quick-deposit hotkey unavailable: RegisterKeyBind/Key not present.")
            return
        end

        local key = Key[config.deposit_key]

        if key == nil then
            log("Quick-deposit hotkey unavailable: unknown key '" .. tostring(config.deposit_key) .. "'.")
            return
        end

        local ok, err = pcall(function()
            RegisterKeyBind(key, function()
                ExecuteInGameThread(M.quick_deposit_to_nearby_chests)
            end)
        end)

        if ok then
            log("Quick-deposit hotkey registered on " .. tostring(config.deposit_key) .. ".")
        else
            log("Could not register quick-deposit hotkey: " .. tostring(err))
        end
    end

    return M
end
