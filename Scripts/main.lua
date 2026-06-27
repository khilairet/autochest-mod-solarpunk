-- AutoChest entry point. Wires the modules together through a shared `ctx`
-- table (each module is a factory: require("x")(ctx)) and registers the game
-- hooks / hotkey. Modules are built in dependency order so each can capture the
-- ones it needs at construction time.
--
-- Module layout (all in this Scripts/ folder):
--   config.lua    constants + config.txt loader
--   util.lua      generic UObject / slot-field / logging helpers
--   inventory.lua chest & player resolution, content caches, combined totals
--   mutate.lua    decrement / restore / move items between inventories
--   hooks.lua     the crafting/affordability hooks + their registration
--   deposit.lua   the quick-deposit hotkey

local ctx = {}

ctx.config = require("config")
ctx.util = require("util")(ctx)
ctx.inventory = require("inventory")(ctx)
ctx.mutate = require("mutate")(ctx)
ctx.hooks = require("hooks")(ctx)
ctx.deposit = require("deposit")(ctx)

-- Apply config.txt overrides before anything reads the tunables.
ctx.config.load_file(ctx.util.log)

-- Quick-deposit hotkey can be registered immediately (no game class needed).
ctx.deposit.register_keybind()

-- Hook registration must be deferred: at launch BC_InventorySystem_C isn't
-- loaded yet, so RegisterHook on its functions fails. Retry on ClientRestart
-- and on any new UserWidget until everything we need is registered.
RegisterHook("/Script/Engine.PlayerController:ClientRestart", function()
    ExecuteInGameThread(ctx.hooks.register_hooks)
end)

NotifyOnNewObject("/Script/UMG.UserWidget", function(widget)
    if not ctx.hooks.all_registered() then
        ExecuteInGameThread(ctx.hooks.register_hooks)
    end
end)

ctx.util.log("Loaded v" .. ctx.config.VERSION .. ".")
