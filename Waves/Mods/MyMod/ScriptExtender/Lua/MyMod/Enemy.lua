---@diagnostic disable: undefined-global

local enemyTemplates = Require("MyMod/Templates/Enemies.lua")

L.Debug("Enemies loaded", #enemyTemplates)

-------------------------------------------------------------------------------------------------
--                                                                                             --
--                                            Structures                                       --
--                                                                                             --
-------------------------------------------------------------------------------------------------

---@class Enemy : LibsObject
---@field Name string
---@field TemplateId string
---@field IsBoss boolean
---@field Tier string
---@field Info table
---@field GUID string
-- potential overwrites
---@field LevelOverride integer
---@field Equipment string
---@field Stats string
---@field SpellSet string
---@field AiHint string
---@field Archetype string
---@field CharacterVisualResourceID string
---@field Icon string
local Object = Libs.Object({
    Name = "Empty",
    TemplateId = nil,
    Tier = nil,
    Info = {},
    GUID = nil,
    IsBoss = false,
    -- not required
    LevelOverride = nil,
    Equipment = nil,
    Stats = nil,
    SpellSet = nil,
    AiHint = nil,
    Archetype = nil,
    CharacterVisualResourceID = nil,
    Icon = nil,
})

Object.__tostring = function(self)
    return self.GUID
end

---@param data table enemy source data
---@return Enemy
function Object.New(data)
    local o = Object.Init(data)

    o.LevelOverride = o.LevelOverride and tonumber(o.LevelOverride) or 0
    o.GUID = nil

    return o
end

function Object:GetId()
    return self.Name .. "_" .. self.TemplateId
end

function Object:IsSpawned()
    return self.GUID ~= nil
end

---@return table<ExtComponentType, any>
function Object:Entity()
    return Ext.Entity.Get(self.GUID)
end

function Object:ModifyTemplate()
    local template = Ext.Template.GetTemplate(self.TemplateId)

    -- only overwrite if different, and save the original value for restoration
    local overwrites = {}
    local function templateOverwrite(prop, value)
        if type(value) == "table" then
            for k, v in pairs(value) do
                if template[prop][k] ~= v then
                    overwrites[prop] = overwrites[prop] or {}
                    overwrites[prop][k] = template[prop][k]

                    template[prop][k] = v
                end
            end
            return
        end

        if template[prop] ~= value then
            overwrites[prop] = template[prop]

            template[prop] = value
        end
    end

    -- most relevant, blocks loot drops
    templateOverwrite("IsEquipmentLootable", false)
    templateOverwrite("IsLootable", false)
    templateOverwrite("Treasures", { "Empty" })

    -- potential overwrites
    local combatComp = {}
    if self.Archetype ~= nil then
        combatComp.Archetype = self.Archetype
    end
    if self.AiHint ~= nil then
        combatComp.AiHint = self.AiHint
    end
    -- set later anyways
    -- combatComp.Faction = C.NeutralFaction
    -- combatComp.CombatGroupID = ""
    templateOverwrite("CombatComponent", combatComp)

    if self.Equipment ~= nil then
        templateOverwrite("Equipment", self.Equipment)
    end

    if self.CharacterVisualResourceID ~= nil then
        -- might not apply when to many enemies are spawned at once
        templateOverwrite("CharacterVisualResourceID", self.CharacterVisualResourceID)
    end

    if self.Icon ~= nil then
        templateOverwrite("Icon", self.Icon)
    end

    if self.Stats ~= nil then
        templateOverwrite("Stats", self.Stats)
    end

    if self.SpellSet ~= nil then
        templateOverwrite("SpellSet", self.SpellSet)
    end

    if self.LevelOverride > 0 then
        templateOverwrite("LevelOverride", self.LevelOverride)
    end

    -- restore template
    -- maybe not needed but template overwrites seem to be global
    Require("Shared/GameState").RegisterUnloadingAction(function()
        L.Debug("Restoring template:", self.TemplateId)
        local template = Ext.Template.GetTemplate(self.TemplateId)
        for i, v in pairs(overwrites) do
            if type(v) == "table" then
                for k, v in pairs(v) do
                    template[i][k] = v
                end
            else
                template[i] = v
            end
        end
    end)
end

function Object:Modify(keepFaction)
    if not self:IsSpawned() then
        return
    end

    Osi.SetCharacterLootable(self.GUID, 0)
    Osi.SetCombatGroupID(self.GUID, "")

    if not keepFaction then
        Osi.SetFaction(self.GUID, C.NeutralFaction)
    end

    Schedule(function()
        local entity = self:Entity()
        local expMod = self.IsBoss and 10 or 3
        entity.ServerExperienceGaveOut.Experience = entity.BaseHp.Vitality
            * math.ceil(entity.EocLevel.Level / 2) -- ceil(1/2) = 1
            * expMod

        -- entity.ServerCharacter.Treasures = { "Empty" }
    end)

    -- maybe useful
    -- Osi.CharacterGiveEquipmentSet(target, equipmentSet)
    -- Osi.SetAiHint(target, aiHint)
    -- Osi.AddCustomVisualOverride(character, visual)
end

function Object:Sync()
    local entity = self:Entity()

    local currentTemplate = entity.ServerCharacter.Template
    if self.TemplateId == nil then
        self.TemplateId = currentTemplate.Id
    end

    self.CharacterVisualResourceID = currentTemplate.CharacterVisualResourceID
    self.Icon = currentTemplate.Icon
    self.Stats = currentTemplate.Stats
    self.Equipment = currentTemplate.Equipment
    self.Archetype = currentTemplate.CombatComponent.Archetype
    self.AiHint = currentTemplate.CombatComponent.AiHint
    self.IsBoss = currentTemplate.CombatComponent.IsBoss
    self.SpellSet = currentTemplate.SpellSet
    self.LevelOverride = currentTemplate.LevelOverride
end

---@param x number
---@param y number
---@param z number
---@return boolean
function Object:CreateAt(x, y, z)
    if self:IsSpawned() then
        return false
    end

    self:ModifyTemplate()

    self.GUID = Osi.CreateAt(self:GetId(), x, y, z, 1, 1, "")

    if not self:IsSpawned() then
        L.Error("Failed to create real: ", self:GetId())
        return false
    end

    self:Sync()

    self:Modify()

    PersistentVars.SpawnedEnemies[self.GUID] = self

    L.Debug("Enemy registered: ", self:GetId(), guid)

    return true
end

---@param x number
---@param y number
---@param z number
---@param neutral boolean|nil if combat should not be initiated
---@return boolean
function Object:Spawn(x, y, z, neutral)
    if self:IsSpawned() then
        return false
    end

    local target = ""
    local radius = 100
    local avoidDangerousSurfaces = 0
    local x2, y2, z2 = Osi.FindValidPosition(x, y, z, radius, target, avoidDangerousSurfaces)

    local success = self:CreateAt(x2 or x, y2 or y, z2 or z)

    if success then
        if not neutral then
            self:Combat()
        end

        return true
    end

    return false
end

function Object:Combat(force)
    if not self:IsSpawned() then
        return
    end

    local enemy = self.GUID

    Osi.ApplyStatus(enemy, "InitiateCombat", -1)
    Osi.ApplyStatus(enemy, "BringIntoCombat", -1)

    Osi.SetFaction(enemy, C.EnemyFaction)
    Osi.SetCanJoinCombat(enemy, 1)
    Osi.SetCanFight(enemy, 1)

    if force then
        for _, player in pairs(UE.GetPlayers()) do
            Osi.EnterCombat(enemy, player)
            Osi.EnterCombat(player, enemy)
        end
    end
end

function Object:Clear(keepCorpse)
    local guid = self.GUID
    local id = self:GetId()
    self.GUID = nil

    RetryFor(function()
        if keepCorpse then
            Osi.Die(guid, 0, "NULL_00000000-0000-0000-0000-000000000000", 0, 0)
        else
            UE.Remove(guid)
        end

        return Osi.IsDead(guid) == 1
    end, {
        interval = 300,
        immediate = true,
        success = function()
            if not keepCorpse then
                PersistentVars.SpawnedEnemies[guid] = nil
            end
        end,
        failed = function()
            L.Error("Failed to kill: ", guid, id)
        end,
    })
end

-------------------------------------------------------------------------------------------------
--                                                                                             --
--                                            Public                                           --
--                                                                                             --
-------------------------------------------------------------------------------------------------

---@param enemy Enemy
---@return Enemy
function Enemy.Restore(enemy)
    local e = Object.Init(enemy)
    e:ModifyTemplate()
    e:Modify(true)

    return e
end

---@param object string GUID
---@return Enemy
-- mostly for tracking summons
function Enemy.CreateTemporary(object)
    local e = Object.New({ Name = "Temporary" })
    e.GUID = U.UUID.GetGUID(object)

    e:Sync()
    e:Modify(true)

    PersistentVars.SpawnedEnemies[e.GUID] = e

    return e
end

---@return Enemy|nil
function Enemy.Random(filter)
    local list = {}
    for _, enemy in Enemy.Iter(filter) do
        table.insert(list, enemy)
    end
    if #list == 0 then
        return nil
    end
    local enemy = list[U.Random(#list)]
    return Object.New(enemy)
end

---@return Enemy
function Enemy.GetByIndex(index)
    local enemy = enemyTemplates[index]
    return Object.New(enemy)
end

---@return Enemy[]
function Enemy.GetByTemplateId(templateId)
    local list = {}
    for _, enemy in Enemy.Iter(filter) do
        if enemy.TemplateId == templateId then
            table.insert(list, enemy)
        end
    end

    return list
end

---@field filter fun(data: Enemy):boolean data is the enemy source data
---@return fun():number,Enemy
function Enemy.Iter(filter)
    local i = 0
    local j = 0
    return function()
        i = i + 1
        j = j + 1
        if filter then
            while enemyTemplates[j] and not filter(enemyTemplates[j]) do
                j = j + 1
            end
        end
        if enemyTemplates[j] then
            return i, Object.New(enemyTemplates[j])
        end
    end
end

---@param object string GUID
---@return boolean
function Enemy.IsValid(object)
    return UE.IsNonPlayer(object, true)
        and (
            Osi.IsSummon(object) == 1
            or (S and UT.Find(S.SpawnedEnemies, function(v)
                return U.UUID.Equals(v.GUID, object)
            end) ~= nil)
            or (UT.Find(PersistentVars.SpawnedEnemies, function(v)
                return U.UUID.Equals(v.GUID, object)
            end) ~= nil)
            or UT.Contains({
                C.EnemyFaction,
                C.NeutralFaction,
            }, U.UUID.GetGUID(Osi.GetFaction(object)))
        )
end

function Enemy.Cleanup()
    for guid, enemy in pairs(PersistentVars.SpawnedEnemies) do
        Object.Init(enemy):Clear()
    end
end

function Enemy.KillSpawned()
    for guid, enemy in pairs(PersistentVars.SpawnedEnemies) do
        Object.Init(enemy):Clear(true)
    end
end

function Enemy.SpawnNamed(name, x, y, z)
    local enemy = Enemy.GetByName(name)
    if enemy then
        enemy:Spawn(x, y, z)
        return enemy
    end
end

function Enemy.SpawnTemplate(templateId, x, y, z)
    local e = Object.New({ Name = "Custom", TemplateId = templateId })
    e:Spawn(x, y, z)
    return e
end

---@param enemy Enemy
---@return string, table
function Enemy.CalcTier(enemy)
    local vit = enemy:Entity().BaseHp.Vitality
    local level = enemy:Entity().EocLevel.Level

    local stats = enemy:Entity().Stats.AbilityModifiers
    local prof = enemy:Entity().Stats.ProficiencyBonus
    local ac = enemy:Entity().Resistances.AC

    -- for i, v in pairs(enemy:Entity().Resistances.Resistances) do
    --     local s = Ext.Json.Stringify(v)
    --     if s:match("ImmuneToNonMagical") or s:match("ImmuneToMagical") then
    --         return "trash"
    --     end
    -- end

    -- if enemy:Entity().ServerCharacter.Template.IsLootable ~= true then
    --     return "trash"
    -- end

    local sum = 0
    local statsValid = false
    for _, stat in pairs(stats) do
        sum = sum + stat
        if stat ~= 0 then
            statsValid = true
        end
    end

    if vit < 5 then
        return "trash"
    end

    if not statsValid then
        return "trash"
    end

    local pwr = (vit / 2) + sum + prof + ac + level

    local category
    if pwr > 150 then
        category = C.EnemyTier[6]
    elseif pwr % 151 > 90 then
        category = C.EnemyTier[5]
    elseif pwr % 91 > 65 then
        category = C.EnemyTier[4]
    elseif pwr % 66 > 45 then
        category = C.EnemyTier[3]
    elseif pwr % 46 > 25 then
        category = C.EnemyTier[2]
    else
        category = C.EnemyTier[1]
    end

    return category,
        {
            Vit = vit,
            Stats = sum,
            AC = ac,
            Level = level,
            Pwr = pwr,
        }
end

function Enemy.GenerateEnemyList(templates)
    local function isValidFilename(filename)
        return US.Contains(filename, {
            "Public/Gustav",
            "Public/GustavDev",
            "Public/Shared",
            "Public/SharedDev",
            "Public/Honour",

            "Mods/Gustav",
            "Mods/GustavDev",
            "Mods/Shared",
            "Mods/SharedDev",
            "Mods/Honour",
        })
    end

    local function check(template)
        if not isValidFilename(template.FileName) then
            return
        end

        if template.TemplateType ~= "character" then
            return
        end

        if template.LevelOverride < 0 then
            return
        end

        if template.CombatComponent.Archetype == "base" then
            return
        end

        local patterns = {
            "_Civilian",
            "Dummy",
            "Orin",
            "DaisyPlaceholder",
            "Template",
            "Player",
            "Backup",
            "DarkUrge",
            "Daisy",
            "donotuse",
            "_Hireling",
            "_Guild",
        }
        local startswith = {
            "^_",
            "^ORIGIN_",
            "^Child_",
            "^TEMP_",
            "^CINE_",
            "^BASE_",
            "^S_CAMP_",
            "^QUEST_",
        }

        if US.Contains(template.Name, patterns, true) then
            return false
        end
        if US.Contains(template.Name, startswith, true) then
            return false
        end

        return true
    end

    local enemies = {}
    for templateId, templateData in pairs(templates) do
        if check(templateData) then
            local data = {
                Name = templateData.Name,
                TemplateId = templateData.Id,
                CharacterVisualResourceID = templateData.CharacterVisualResourceID,
                Icon = templateData.Icon,
                Stats = templateData.Stats,
                Equipment = templateData.Equipment,
                Archetype = templateData.CombatComponent.Archetype,
                AiHint = templateData.CombatComponent.AiHint,
                IsBoss = templateData.CombatComponent.IsBoss,
                SpellSet = templateData.SpellSet,
                LevelOverride = templateData.LevelOverride,
            }
            table.insert(enemies, Object.New(data))
        end
    end

    L.Info("Enemies generated from templates: ", #enemies)

    return enemies
end

---@param enemies Enemy[]
function Enemy.TestEnemies(enemies, keepAlive)
    local i = 0
    local pause = false
    local dump = {}
    RetryFor(function(handle)
        if pause then
            return
        end

        i = i + 1
        L.Debug("Checking template: ", i, #enemies)
        local enemy = enemies[i]

        local x, y, z = Player.Pos()
        local target = Player.Host()
        local radius = 100
        local avoidDangerousSurfaces = 1
        local x2, y2, z2 = Osi.FindValidPosition(x, y, z, radius, target, avoidDangerousSurfaces)

        xpcall(function()
            if enemy:CreateAt(x2 or x, y2 or y, z2 or z) then
                pause = true
                Defer(400, function()
                    Defer(100, function()
                        pause = false
                    end)

                    if not enemy:IsSpawned() then
                        return
                    end

                    local tier, info = Enemy.CalcTier(enemy)
                    enemy.Tier = tier
                    enemy.Info = info
                    if tier ~= "trash" then
                        table.insert(
                            dump,
                            UT.Filter(enemy, function(v, k)
                                return k ~= "GUID"
                            end, true)
                        )
                    end

                    if not keepAlive then
                        enemy:Clear()
                    end
                end)
            end
        end, function(err)
            L.Error(err)
            error(err)
        end)

        return i >= #enemies
    end, {
        interval = 1,
        retries = -1,
        success = function()
            Ext.IO.SaveFile(Require("Shared/Mod").ModTableKey .. "/Enemies.json", Ext.Json.Stringify(dump))
        end,
        failed = function(err)
            L.Error(err)
        end,
    })
end