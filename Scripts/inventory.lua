-- Reading and caching inventory/chest contents: chest & player resolution,
-- distance filtering, per-inventory totals, and the combined player+chest
-- queries used by crafting. Owns all the read caches and the
-- chest-lookup-in-progress flag; other modules invalidate via the exposed
-- functions rather than touching the caches directly.

return function(ctx)
    local config = ctx.config
    local util = ctx.util

    local full_name_of = util.full_name_of
    local is_valid = util.is_valid
    local get_param = util.get_param
    local get_outer = util.get_outer
    local get_slot_item = util.get_slot_item
    local get_slot_qty = util.get_slot_qty
    local get_inventory_array = util.get_inventory_array
    local now_seconds = util.now_seconds

    local M = {}

    function M.is_chest_inventory(inventory_system)
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

            -- Read quantity first: an empty slot reports 0 here, letting us skip
            -- it without probing its Item fields or calling GetFullName on it.
            -- Empty slots are usually the bulk of a chest, so this avoids the
            -- most work.
            local slot_qty = get_slot_qty(slot)

            if slot_qty <= 0 then
                return
            end

            local slot_item = get_slot_item(slot)

            if slot_item ~= nil then
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

    function M.invalidate_inventory_totals()
        inventory_totals_cache = {}
    end

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

    function M.count_item_in_inventory(inventory_system, item_class, item_key)
        -- item_key is optional; pass it in to avoid a redundant GetFullName call
        -- when the caller already resolved the item class name.
        if item_key == nil then
            if item_class == nil then
                return 0
            end

            item_key = full_name_of(item_class)
        end

        if item_key == nil then
            return 0
        end

        return get_inventory_totals_map(inventory_system)[item_key] or 0
    end

    -- FindAllOf scans every instance of the class in the world, then GetOuter()
    -- + GetFullName() each one to filter chests. That's heavy to repeat on every
    -- single GetAmtOfItem/ContainsItemAmt call (which can happen dozens of times
    -- per refresh burst). FindAllOf scans every UObject in the world, which is
    -- the single most expensive thing we do and the cause of periodic micro
    -- freezes if run often (the game polls GetAmtOfItem from HUD/quests/etc.).
    -- Chests rarely appear or disappear, so cache the list for a good while.
    -- Chest *contents* stay fresh independently via inventory_totals_cache.
    local CHEST_LIST_TTL_SECONDS = 10.0
    local chest_list_cache = nil
    local chest_list_cache_time = nil

    function M.get_all_chest_inventories(player_inventory)
        local now = now_seconds()

        if now ~= nil and chest_list_cache ~= nil and (now - chest_list_cache_time) < CHEST_LIST_TTL_SECONDS then
            return chest_list_cache
        end

        local result = {}
        local all_inventories = FindAllOf(config.INVENTORY_SYSTEM_CLASS)

        if all_inventories ~= nil then
            for _, inventory_system in ipairs(all_inventories) do
                if is_valid(inventory_system) and inventory_system ~= player_inventory and M.is_chest_inventory(inventory_system) then
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

    -- World location of an inventory's owning actor (the chest actor, or the
    -- player character), or nil if it can't be resolved. Callers treat nil as
    -- "in range" (fail-open) so a position we can't read never hides stock.
    function M.actor_location_of(inventory_system)
        local owner = get_outer(inventory_system)

        if not is_valid(owner) or owner.K2_GetActorLocation == nil then
            return nil
        end

        local ok, loc = pcall(function()
            return owner:K2_GetActorLocation()
        end)

        if not ok or loc == nil then
            return nil
        end

        local x = tonumber(get_param(loc.X))
        local y = tonumber(get_param(loc.Y))
        local z = tonumber(get_param(loc.Z))

        if x == nil or y == nil or z == nil then
            return nil
        end

        return x, y, z
    end

    -- Returns the subset of `all_chests` whose owning actor is within `radius`
    -- of the player. Fail-open: if the player's position can't be read, returns
    -- every chest unfiltered; a chest whose own position can't be read is kept.
    function M.filter_chests_within_radius(player_inventory, all_chests, radius)
        local px, py, pz = M.actor_location_of(player_inventory)

        if px == nil then
            return all_chests
        end

        local radius_sq = radius * radius
        local in_range = {}

        for _, chest in ipairs(all_chests) do
            local cx, cy, cz = M.actor_location_of(chest)

            if cx == nil then
                table.insert(in_range, chest)
            else
                local dx = cx - px
                local dy = cy - py
                local dz = cz - pz

                if (dx * dx + dy * dy + dz * dz) <= radius_sq then
                    table.insert(in_range, chest)
                end
            end
        end

        return in_range
    end

    -- The full chest list (cached above) filtered to those within
    -- config.scan_radius of the player. When the radius is disabled (0) this is
    -- a no-op that returns the full list with zero extra work. The filtered
    -- result is cached very briefly so a multi-ingredient craft doesn't
    -- recompute distances per item; the player barely moves during a craft, so
    -- a short TTL is accurate enough.
    local relevant_chests_cache = nil
    local relevant_chests_cache_time = nil
    local RELEVANT_CHESTS_TTL_SECONDS = 0.25

    function M.get_relevant_chest_inventories(player_inventory)
        local all_chests = M.get_all_chest_inventories(player_inventory)

        if config.scan_radius <= 0 then
            return all_chests
        end

        local now = now_seconds()

        if now ~= nil and relevant_chests_cache ~= nil
            and (now - relevant_chests_cache_time) < RELEVANT_CHESTS_TTL_SECONDS then
            return relevant_chests_cache
        end

        local in_range = M.filter_chests_within_radius(player_inventory, all_chests, config.scan_radius)

        if now ~= nil then
            relevant_chests_cache = in_range
            relevant_chests_cache_time = now
        end

        return in_range
    end

    -- HasEnoughParts? is called on a UI widget (self = the widget, not an
    -- inventory), so we need to separately find the player's own inventory
    -- instance to compute combined totals. This also uses FindAllOf, and the
    -- player's inventory object is stable for the session, so cache it for a
    -- good while too (re-resolved if it ever becomes invalid, e.g. on respawn).
    local PLAYER_INVENTORY_TTL_SECONDS = 10.0
    local player_inventory_cache = nil
    local player_inventory_cache_time = nil

    function M.get_player_inventory()
        local now = now_seconds()

        if now ~= nil and player_inventory_cache ~= nil and is_valid(player_inventory_cache)
            and (now - player_inventory_cache_time) < PLAYER_INVENTORY_TTL_SECONDS then
            return player_inventory_cache
        end

        local result = nil
        local all_inventories = FindAllOf(config.INVENTORY_SYSTEM_CLASS)

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

    -- Set while we are scanning chest contents so the GetAmtOfItem hook can bow
    -- out and avoid re-entrancy / chest counts leaking into unrelated queries.
    local chest_lookup_in_progress = false

    function M.is_chest_lookup_in_progress()
        return chest_lookup_in_progress
    end

    -- This is queried very frequently (potentially once per visible inventory
    -- slot, every UI refresh tick), and a full re-scan of every chest's every
    -- slot on each call was heavy enough to freeze the game. Cache results
    -- briefly so bursts of calls within the same refresh reuse one computation.
    local total_cache = {}
    local CACHE_TTL_SECONDS = 0.25

    function M.invalidate_combined_totals()
        total_cache = {}
    end

    -- Clears every read cache that the player's inventory changing can affect.
    function M.invalidate_all_totals()
        inventory_totals_cache = {}
        total_cache = {}
    end

    function M.get_total_amount_with_chests(player_inventory, item_class)
        -- Resolve the item name once and reuse it for the cache key and every
        -- per-inventory lookup below, instead of calling GetFullName ~once per
        -- chest. This runs per ingredient per recipe tile per UI refresh, so it
        -- is the hottest path in the mod.
        local item_key = full_name_of(item_class)
        local cache_key = item_key or tostring(item_class)
        local now = now_seconds()

        if cache_key ~= nil and now ~= nil then
            local cached = total_cache[cache_key]

            if cached ~= nil and (now - cached.time) < CACHE_TTL_SECONDS then
                return cached.value
            end
        end

        chest_lookup_in_progress = true

        local ok, total = pcall(function()
            local sum = M.count_item_in_inventory(player_inventory, item_class, item_key)

            for _, chest_inventory in ipairs(M.get_relevant_chest_inventories(player_inventory)) do
                sum = sum + M.count_item_in_inventory(chest_inventory, item_class, item_key)
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

    -- Like get_total_amount_with_chests, but answers only "is there at least
    -- `needed`?" so it can stop as soon as the answer is known: if the player's
    -- own inventory already covers it, NO chest is scanned at all (the common
    -- case), and otherwise chests are added one at a time until the threshold is
    -- reached. Used by the craft/affordability decisions, which only need the
    -- boolean. The displayed combined totals still use
    -- get_total_amount_with_chests because they need the exact sum.
    function M.has_enough_with_chests(player_inventory, item_class, needed, item_key)
        if needed <= 0 then
            return true
        end

        item_key = item_key or full_name_of(item_class)

        if item_key == nil then
            return false
        end

        chest_lookup_in_progress = true

        local ok, enough = pcall(function()
            local sum = M.count_item_in_inventory(player_inventory, item_class, item_key)

            if sum >= needed then
                return true
            end

            for _, chest_inventory in ipairs(M.get_relevant_chest_inventories(player_inventory)) do
                sum = sum + M.count_item_in_inventory(chest_inventory, item_class, item_key)

                if sum >= needed then
                    return true
                end
            end

            return false
        end)

        chest_lookup_in_progress = false

        return ok and enough
    end

    return M
end
