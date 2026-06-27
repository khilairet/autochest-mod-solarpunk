-- Constants and the config.txt loader. Returns a single table that every other
-- module reads. The two tunables (scan_radius, deposit_radius) are mutated by
-- load_file() at startup; modules must read them dynamically (config.scan_radius)
-- rather than copying them, so an edited config.txt takes effect.

local C = {}

C.MOD = "[AutoChest] "

-- Mod version. Bump this when releasing; it is printed at load so the running
-- version is visible in the UE4SS console. Keep it in sync with the version you
-- enter on the CurseForge / Nexus upload page.
C.VERSION = "1.0.1"

-- Set to true to print verbose per-item DEBUG traces. Leave false in normal
-- play: these fire hundreds of times per crafting-UI refresh and printing to
-- the UE4SS console is slow enough to noticeably lag the Craft button.
C.DEBUG_ENABLED = false

C.INVENTORY_SYSTEM_CLASS = "BC_InventorySystem_C"

-- Runtime-tunable via config.txt. Distances are in Unreal units (≈ centimetres;
-- 100 = 1 metre). scan_radius 0 = search every chest on the map regardless of
-- distance. deposit_radius 0 is NOT "whole map"; keep it a real nearby distance.
C.scan_radius = 0
C.deposit_radius = 2200.0

-- Key that triggers quick-deposit (move inventory items into nearby chests that
-- already hold that item). A UE4SS Key enum name (e.g. "F2", "G", "NUM_ONE");
-- runtime-tunable via config.txt (deposit_key=...).
C.deposit_key = "F2"

C.CONTAINS_ITEMS_AMT =
    "/Game/Code/Inventory_Items/Framework_and_Data/BC_InventorySystem.BC_InventorySystem_C:ContainsItemsAmt"

C.CONTAINS_ITEM_AMT =
    "/Game/Code/Inventory_Items/Framework_and_Data/BC_InventorySystem.BC_InventorySystem_C:ContainsItemAmt"

C.GET_AMT_OF_ITEM =
    "/Game/Code/Inventory_Items/Framework_and_Data/BC_InventorySystem.BC_InventorySystem_C:GetAmtOfItem"

C.REMOVE_MULTIPLE_ITEMS =
    "/Game/Code/Inventory_Items/Framework_and_Data/BC_InventorySystem.BC_InventorySystem_C:RemoveMultipleItems"

-- The Craft button's click handler appears to gate on these widget checks
-- (seen registered by other mods doing similar "ignore the cost" features)
-- rather than re-running ContainsItemsAmt itself, so they need their own
-- override too or the click silently no-ops when chests are needed.
C.HAS_ENOUGH_PARTS_FUNCTIONS = {
    "/Game/UI/Widgets/WidgetComponents/SW_MissingCraftingPartsSlot.SW_MissingCraftingPartsSlot_C:HasEnoughParts?",
    "/Game/UI/Widgets/WidgetComponents/SW_MissingCraftingPartsSlot_DualLine.SW_MissingCraftingPartsSlot_DualLine_C:HasEnoughParts?",
    "/Game/UI/Widgets/WidgetComponents/SW_MissingCraftingPartsSlot_Vertical.SW_MissingCraftingPartsSlot_Vertical_C:HasEnoughParts?",
}

-- Build mode shows required materials through SW_MissingBuildingParts, whose
-- Construct calls GetAmtOfItem (confirmed via an EventViewer GetAmtOfItem entry
-- capture). Hooking its Construct lets us detect build mode as a material-UI
-- activity. Several candidate asset paths are tried since the exact folder
-- isn't known; whichever registers is used.
C.BUILDING_PARTS_CONSTRUCT_FUNCTIONS = {
    "/Game/UI/Widgets/WidgetComponents/SW_MissingBuildingParts.SW_MissingBuildingParts_C:Construct",
    "/Game/UI/Widgets/SW_MissingBuildingParts.SW_MissingBuildingParts_C:Construct",
    "/Game/UI/Widgets/Build/SW_MissingBuildingParts.SW_MissingBuildingParts_C:Construct",
    "/Game/UI/Widgets/BuildMode/SW_MissingBuildingParts.SW_MissingBuildingParts_C:Construct",
}

C.ITEM_FIELDS = {
    "Item",
    "Item_4_B9922CA845A5618A776EAFAB1A690E93",
    "ItemActor",
    "ItemActor_16_A80D2B2B49E59CC810744B999AEA8F92",
}

C.QTY_FIELDS = {
    "Quantity",
    "Quantity_5_A1813C42482CE5E7961C589A983BD034",
    "Amount",
    "Amount_5_12AB5DA84DB6E8C535AD7D82D7F29009",
}

C.MAX_STACK_FIELDS = {
    "MaxStackSize",
    "MaxStackSize_5_38058E5746B557DCB034A6B0A98794B6",
}

-- "@D:\...\AutoChest\Scripts\config.lua" -> "D:\...\AutoChest"
local function mod_root_dir()
    local ok, src = pcall(function()
        return debug.getinfo(1, "S").source
    end)

    if not ok or type(src) ~= "string" then
        return nil
    end

    return (src:gsub("^@", "")):match("^(.*)[/\\]Scripts[/\\][^/\\]+$")
end

-- Reads AutoChest/config.txt (lines like "scan_radius=5000") and overrides the
-- tunables above. Read once at load; a change takes effect after a game/mod
-- reload. `log` is optional and only used to report the loaded values.
function C.load_file(log)
    if io == nil then
        return
    end

    local dir = mod_root_dir()

    if dir == nil then
        return
    end

    local ok, file = pcall(io.open, dir .. "\\config.txt", "r")

    if not ok or file == nil then
        return
    end

    for line in file:lines() do
        -- key = value, where value is any run of non-space, non-# characters
        -- (so numbers and key names like "F2" both parse; # starts a comment).
        local key, value = line:match("^%s*([%w_]+)%s*=%s*([^%s#]+)")

        if key ~= nil and value ~= nil then
            if key == "scan_radius" then
                local n = tonumber(value)
                if n ~= nil then C.scan_radius = n end
            elseif key == "deposit_radius" then
                local n = tonumber(value)
                if n ~= nil then C.deposit_radius = n end
            elseif key == "deposit_key" then
                C.deposit_key = value
            end
        end
    end

    file:close()

    if log then
        log("Config loaded: scan_radius=" .. tostring(C.scan_radius)
            .. ", deposit_radius=" .. tostring(C.deposit_radius)
            .. ", deposit_key=" .. tostring(C.deposit_key))
    end
end

return C
