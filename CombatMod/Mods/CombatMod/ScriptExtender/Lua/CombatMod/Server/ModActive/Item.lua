local itemBlacklist = Require("CombatMod/Templates/ItemBlacklist.lua")

local weapons = nil
local armor = nil
local objects = nil
local function loadItems()
    if Ext.Mod.IsModLoaded(C.ModUUID) then
        weapons = Ext.Stats.GetStatsLoadedBefore(C.ModUUID, "Weapon")
        armor = Ext.Stats.GetStatsLoadedBefore(C.ModUUID, "Armor")
        objects = Ext.Stats.GetStatsLoadedBefore(C.ModUUID, "Object")
    else
        L.Debug("Mod not loaded. Using all items.")
        weapons = Ext.Stats.GetStats("Weapon")
        armor = Ext.Stats.GetStats("Armor")
        objects = Ext.Stats.GetStats("Object")
    end

    L.Debug("Item lists loaded.", #objects, #armor, #weapons)
end

-------------------------------------------------------------------------------------------------
--                                                                                             --
--                                          Structures                                         --
--                                                                                             --
-------------------------------------------------------------------------------------------------

---@class Item : LibsStruct
---@field Name string
---@field Type string
---@field RootTemplate string
---@field Rarity string
---@field GUID string|nil
---@field Slot string|nil
local Object = Libs.Struct({
    Name = nil,
    Type = nil,
    RootTemplate = "",
    Rarity = C.ItemRarity[1],
    GUID = nil,
    PingSpawn = true,
    Slot = nil,
    Tab = nil,
})

---@param name string
---@param type string
---@param fake boolean|nil
---@return Item
function Object.New(name, type, fake)
    local o = Object.Init()

    o.Name = name
    o.Type = type

    if not fake then
        local item = Ext.Stats.Get(name)
        o.RootTemplate = item.RootTemplate
        o.Rarity = item.Rarity
        o.Tab = item.InventoryTab

        if type == "Armor" or type == "Weapon" then
            o.Slot = item.Slot
        end
        if type == "Object" then
            o.Slot = item.ItemUseType
        end
    end

    o.GUID = nil

    return o
end

function Object:ModifyTemplate()
    local template = self:GetTemplate()

    if template.Stats ~= self.Name then
        template.Stats = self.Name
    end
end

function Object:IsSpawned()
    return self.GUID ~= nil
end

function Object:GetTemplate()
    return Ext.Template.GetTemplate(self.RootTemplate)
end

function Object:GetTranslatedName()
    local handle
    if self:IsSpawned() then
        handle = Osi.GetDisplayName(self.GUID)
    else
        handle = self:GetTemplate().DisplayName.Handle.Handle
    end
    return Osi.ResolveTranslatedString(handle)
end

---@param x number
---@param y number
---@param z number
---@return boolean
function Object:Spawn(x, y, z)
    if self:IsSpawned() then
        return false
    end

    self:ModifyTemplate()

    x, y, z = Osi.FindValidPosition(x, y, z, 20, Player.Host(), 1)

    self.GUID = Osi.CreateAt(self.RootTemplate, x, y, z, 0, 1, "")

    if self:IsSpawned() then
        PersistentVars.SpawnedItems[self.GUID] = self

        if self.PingSpawn then
            Schedule(function() -- basically a pcall
                Osi.RequestPing(x, y, z, self.GUID, "")
            end)
        end

        return true
    end

    L.Error("Failed to spawn: ", self.Name)

    return false
end

function Object:Clear()
    local guid = self.GUID
    self.GUID = nil

    RetryUntil(function()
        GU.Object.Remove(guid)
        return Osi.IsItem(guid) ~= 0
    end, { immediate = true }).After(function()
        PersistentVars.SpawnedItems[guid] = nil
    end).Catch(function()
        L.Error("Failed to delete item: ", guid, self.Name)
    end)
end

-------------------------------------------------------------------------------------------------
--                                                                                             --
--                                            Public                                           --
--                                                                                             --
-------------------------------------------------------------------------------------------------

function Item.Create(name, type, rootTemplate, rarity)
    local item = Object.New(name, type, true)
    item.RootTemplate = rootTemplate
    item.Rarity = rarity

    return item
end

local itemCache = {
    Objects = {},
    Armor = {},
    Weapons = {},
    CombatObjects = {},
}

function Item.ClearCache()
    itemCache = {
        Objects = {},
        Armor = {},
        Weapons = {},
        CombatObjects = {},
    }
end

function Item.Get(items, type, rarity)
    return UT.Map(items, function(name)
        local item = Object.New(name, type)

        if rarity == nil or item.Rarity == rarity then
            return item
        end
    end)
end

function Item.Objects(rarity, forCombat)
    local cacheKey = forCombat and "CombatObjects" or "Objects"
    if #itemCache[cacheKey] > 0 then
        return Item.Get(itemCache[cacheKey], "Object", rarity)
    end

    if objects == nil then
        loadItems()
    end

    local items = UT.Filter(objects, function(name)
        local stat = Ext.Stats.Get(name)
        if not stat then
            return false
        end
        local cat = stat.ObjectCategory
        local tab = stat.InventoryTab
        local type = stat.ItemUseType

        if US.Contains(name, itemBlacklist, true) then
            return false
        end

        if name:match("^_") then
            return false
        end

        if stat.Rarity == "" or stat.RootTemplate == "" then
            return false
        end

        if forCombat then
            if not (type == "Potion" or tab == "Magical") then
                return false
            end
        else
            if
                not (
                    (cat:match("^Food") and name:match("^CONS_"))
                    -- or cat:match("^Drink")
                    -- alchemy items
                    or name:match("^ALCH_Ingredient")
                )
            then
                return false
            end
        end

        local temp = Ext.Template.GetTemplate(stat.RootTemplate)
        if not temp or temp.Name:match("DONOTUSE$") then
            return false
        end

        local a = Ext.Stats.TreasureCategory.GetLegacy("I_" .. name)
        local b = Ext.Stats.TreasureCategory.GetLegacy("I_" .. temp.Name)
        local c = false
        for _, v in pairs(US.Split(stat.ObjectCategory, ";")) do
            c = Ext.Stats.TreasureCategory.GetLegacy(v)
            if c then
                break
            end
        end
        if not a and not b and not c then
            return false
        end

        return true
    end)

    itemCache[cacheKey] = items

    return Item.Get(items, "Object", rarity)
end

function Item.Armor(rarity)
    if #itemCache.Armor > 0 then
        return Item.Get(itemCache.Armor, "Armor", rarity)
    end

    if armor == nil then
        loadItems()
    end

    local items = UT.Filter(armor, function(name)
        local stat = Ext.Stats.Get(name)
        if not stat then
            return false
        end
        local slot = stat.Slot

        if US.Contains(name, itemBlacklist, true) then
            return false
        end

        if name:match("^_") then
            return false
        end

        if
            not Config.LootIncludesCampSlot
            and (slot:match("VanityBody") or slot:match("VanityBoots") or slot:match("Underwear"))
        then
            return false
        end

        if stat.Rarity == "" or stat.RootTemplate == "" then
            return false
        end

        -- doesnt exist iirc
        if stat.UseConditions ~= "" then
            return false
        end

        local temp = Ext.Template.GetTemplate(stat.RootTemplate)
        if not temp or temp.Name:match("DONOTUSE$") then
            return false
        end

        return true
    end)

    itemCache.Armors = items

    return Item.Get(items, "Armor", rarity)
end

function Item.Weapons(rarity)
    if #itemCache.Weapons > 0 then
        return Item.Get(itemCache.Weapons, "Weapon", rarity)
    end

    if weapons == nil then
        loadItems()
    end

    local items = UT.Filter(weapons, function(name)
        local stat = Ext.Stats.Get(name)
        if not stat then
            return false
        end

        if US.Contains(name, itemBlacklist, true) then
            return false
        end

        if name:match("^_") then
            return false
        end

        if stat.Rarity == "" or stat.RootTemplate == "" then
            return false
        end

        -- weapons that can't be used by players
        if stat.UseConditions ~= "" then
            return false
        end

        local temp = Ext.Template.GetTemplate(stat.RootTemplate)
        if not temp or temp.Name:match("DONOTUSE$") then
            return false
        end

        return true
    end)

    itemCache.Weapons = items

    return Item.Get(items, "Weapon", rarity)
end

function Item.IsOwned(obj)
    return Osi.IsInInventory(obj) == 1
        or Osi.GetInventoryOwner(obj) ~= nil
        or Osi.GetFirstInventoryOwnerCharacter(obj) ~= nil
end

-- not used
function Item.Cleanup()
    for guid, item in pairs(PersistentVars.SpawnedItems) do
        Object.Init(item):Clear()
    end
end

function Item.DestroyAll(rarity, type)
    for guid, item in pairs(PersistentVars.SpawnedItems) do
        if item.Rarity == rarity and not Item.IsOwned(item.GUID) and (not type or item.Type == type) then
            GU.Object.Remove(guid)
            PersistentVars.SpawnedItems[guid] = nil
        end
    end
end

function Item.PickupAll(character, rarity, type)
    for _, item in pairs(PersistentVars.SpawnedItems) do
        if
            not Item.IsOwned(item.GUID)
            and (type == nil or item.Type == type)
            and (rarity == nil or item.Rarity == rarity)
        then
            Osi.ToInventory(item.GUID, character)
            Schedule(function()
                if Item.IsOwned(item.GUID) then
                    PersistentVars.SpawnedItems[item.GUID] = nil
                end
            end)
        end
    end
end

function Item.SpawnLoot(loot, x, y, z, autoPickup)
    local i = 0
    Async.Interval(300 - (#loot * 2), function(self)
        i = i + 1

        if i > #loot then
            self:Clear()
            if autoPickup and Player.InCamp() then
                Player.PickupAll()
            end

            return
        end

        if loot[i] == nil then
            L.Error("Loot was empty.", i, #loot)
            return
        end

        local x2 = x + U.Random() * U.Random(-1, 1)
        local z2 = z + U.Random() * U.Random(-1, 1)

        loot[i]:Spawn(x2, y, z2)
    end)
end

function Item.GenerateLoot(rolls, lootRates)
    local loot = {}

    -- each kill gets an object/weapon/armor roll
    if not lootRates then
        lootRates = C.LootRates
    end

    local function add(t, rarity, amount)
        for i = 1, amount do
            table.insert(t, rarity)
        end

        return t
    end

    -- build rarity roll tables from template e.g. { "Common", "Common", "Uncommon", "Rare" }
    -- if rarity is 0 it will be at least added once
    -- if rarity is not defined it will not be added
    local rarities = {}
    for _, category in ipairs({ "CombatObject", "Weapon", "Armor" }) do
        local rarity = {}

        for _, r in ipairs(C.ItemRarity) do
            if category == "CombatObject" and lootRates.Objects[r] then
                add(rarity, r, lootRates.Objects[r])
            elseif category == "Weapon" and lootRates.Weapons[r] then
                add(rarity, r, lootRates.Weapons[r])
            elseif category == "Armor" and lootRates.Armor[r] then
                add(rarity, r, lootRates.Armor[r])
            end
        end

        rarities[category] = rarity
    end

    local chanceFood = 9
    for i = 1, rolls do
        local items = {}
        local fail = 0

        local category = ({ "CombatObject", "Object", "Weapon", "Armor" })[U.Random(4)]

        local rarity = nil
        -- avoid 0 rolls e.g. legendary objects dont exist
        while #items == 0 and fail < 5 do
            fail = fail + 1

            if category == "Object" then
                items = Item.Objects(nil, false)

                local isFood = U.Random() < chanceFood / 10

                if isFood then
                    chanceFood = math.max(1, chanceFood - 0.5)
                end
                L.Debug("Rolling Object loot slot:", isFood, chanceFood)

                items = UT.Filter(items, function(item)
                    return isFood and item.Tab == "Consumable" or item.Tab ~= "Consumable"
                end)

                if #items > 0 then
                    i = i - 1
                end
            else
                rarity = rarities[category][U.Random(#rarities[category])]

                if category == "CombatObject" then
                    items = Item.Objects(rarity, true)
                    if #items > 0 then
                        local bySlot = UT.GroupBy(items, "Slot")
                        local slots = UT.Keys(bySlot)
                        local randomSlot = slots[U.Random(#slots)]
                        L.Debug("Rolling CombatObject loot slot:", randomSlot, rarity)

                        if randomSlot == "Potion" and U.Random() < 0.40 then
                            items = UT.Filter(items, function(item)
                                return item.Name:match("^OBJ_Potion_Healing")
                            end)
                        else
                            items = UT.Values(bySlot[randomSlot])
                        end
                    end
                elseif category == "Weapon" then
                    items = Item.Weapons(rarity)
                elseif category == "Armor" then
                    items = Item.Armor(rarity)
                    if #items > 0 then
                        local bySlot = UT.GroupBy(items, "Slot")
                        local slots = UT.Keys(bySlot)
                        local randomSlot = slots[U.Random(#slots)]
                        L.Debug("Rolling Armor loot slot:", randomSlot, rarity)
                        items = UT.Values(bySlot[randomSlot])
                    end
                end
            end
        end

        L.Debug("Rolling loot items:", #items, category, rarity)
        if #items > 0 then
            local random = items[U.Random(#items)]

            if UT.Contains(PersistentVars.RandomLog.Items, random.Name) then
                random = items[U.Random(#items)]
            end
            LogRandom("Items", random.Name, 100)

            table.insert(loot, random)
        end
    end

    return loot
end

-------------------------------------------------------------------------------------------------
--                                                                                             --
--                                           Events                                            --
--                                                                                             --
-------------------------------------------------------------------------------------------------

GameState.OnUnload(Item.ClearCache)

U.Osiris.On(
    "RequestCanPickup",
    3,
    "after",
    Async.Throttle( -- avoid recursion
        10,
        function(character, object, requestID)
            if GC.IsNonPlayer(character, true) then
                return
            end

            local item = UT.Find(PersistentVars.SpawnedItems, function(item)
                return U.UUID.Equals(item.GUID, object)
            end)

            if item then
                L.Debug("Auto pickup:", object, character)
                Item.PickupAll(character, item.Rarity)
            end
        end
    )
)