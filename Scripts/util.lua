-- Generic, stateless helpers (the one piece of state, resolved_field_cache, is a
-- pure optimisation). No knowledge of crafting/chests — just UObject access,
-- logging, and slot-field reading. Depends only on config.

return function(ctx)
    local config = ctx.config

    local M = {}

    function M.log(message)
        print(config.MOD .. tostring(message) .. "\n")
    end

    function M.log_debug(message)
        if config.DEBUG_ENABLED then
            print(config.MOD .. "DEBUG: " .. tostring(message) .. "\n")
        end
    end

    local clock_available = pcall(function() return os.clock() end)

    function M.now_seconds()
        if clock_available then
            return os.clock()
        end

        return nil
    end

    function M.is_valid(obj)
        if type(obj) ~= "table" and type(obj) ~= "userdata" then
            return false
        end

        local ok, result = pcall(function()
            return obj.IsValid ~= nil and obj:IsValid()
        end)

        return ok and result
    end

    function M.get_param(param)
        -- Only table/userdata can be indexed for a :get() accessor. Plain
        -- values (e.g. FVector .X/.Y/.Z come through as numbers) are returned
        -- as-is; indexing them would raise "attempt to index a number value".
        local t = type(param)

        if (t == "table" or t == "userdata") and param.get ~= nil then
            local ok, value = pcall(function()
                return param:get()
            end)

            if ok then
                return value
            end
        end

        return param
    end

    function M.set_param(param, value)
        if param ~= nil and param.set ~= nil then
            pcall(function()
                param:set(value)
            end)
        end
    end

    -- Which candidate name actually resolved for each field group, keyed by the
    -- fields table itself (config.ITEM_FIELDS / QTY_FIELDS / MAX_STACK_FIELDS are
    -- stable table identities). On this build the same struct field always wins,
    -- so after the first probe we read it directly and skip the 3-4 failing
    -- pcalls per slot. The full probe still runs as a fallback if the remembered
    -- name ever misses, so correctness never depends on the cache being right.
    local resolved_field_cache = {}

    function M.try_get(obj, fields)
        if obj == nil then
            return nil
        end

        local remembered = resolved_field_cache[fields]

        if remembered ~= nil then
            local ok, value = pcall(function()
                return obj[remembered]
            end)

            if ok and value ~= nil then
                return value
            end
        end

        for _, field in ipairs(fields) do
            local ok, value = pcall(function()
                return obj[field]
            end)

            if ok and value ~= nil then
                resolved_field_cache[fields] = field
                return value
            end
        end

        return nil
    end

    function M.find_field_name(obj, fields)
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

    function M.full_name_of(obj)
        if not M.is_valid(obj) or obj.GetFullName == nil then
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

    function M.get_outer(obj)
        if not M.is_valid(obj) or obj.GetOuter == nil then
            return nil
        end

        local ok, outer = pcall(function()
            return obj:GetOuter()
        end)

        if ok and M.is_valid(outer) then
            return outer
        end

        return nil
    end

    function M.object_key(obj)
        if obj == nil then
            return nil
        end

        if M.is_valid(obj) then
            return M.full_name_of(obj)
        end

        return tostring(obj)
    end

    function M.same_item(a, b)
        local a_key = M.object_key(a)
        local b_key = M.object_key(b)

        return a_key ~= nil and b_key ~= nil and a_key == b_key
    end

    function M.get_slot_item(slot)
        return M.try_get(slot, config.ITEM_FIELDS)
    end

    function M.get_slot_qty(slot)
        local value = M.try_get(slot, config.QTY_FIELDS)

        if value == nil then
            return 0
        end

        return tonumber(value) or 0
    end

    function M.get_slot_max_stack(slot)
        local value = tonumber(M.try_get(slot, config.MAX_STACK_FIELDS))

        if value == nil or value <= 0 then
            return 999
        end

        return value
    end

    function M.get_inventory_array(inventory_system)
        if not M.is_valid(inventory_system) then
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

    return M
end
