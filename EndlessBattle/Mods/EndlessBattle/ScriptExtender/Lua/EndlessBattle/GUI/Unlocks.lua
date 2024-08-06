ClientUnlock = {}

---@param tab ExtuiTabBar
function ClientUnlock.Main(tab)
    ---@type ExtuiTree
    local root = tab:AddTabItem(__("Unlocks"))

    Components.Computed(root:AddSeparatorText(__("Currency owned: %d", 0)), function(root, currency)
        return __("Currency owned: %d", currency)
    end, "CurrencyChanged")

    Event.On("StateChange", function(state)
        Event.Trigger("CurrencyChanged", state.Currency or 0)
    end)

    Event.ChainOn("StateChange"):After(function(self, state)
        local unlocks = state.Unlocks
        if UT.Size(unlocks) == 0 then
            return
        end
        self:Unregister()

        local cols = 3
        local nrows = math.ceil(#unlocks / cols)
        Components.Layout(root, cols, nrows, function(layout)
            layout.Table.Borders = true
            for i, unlock in ipairs(unlocks) do
                local c = (i - 1) % cols
                local r = math.ceil(i / cols)
                local cell = layout.Cells[r][c + 1]
                ClientUnlock.Tile(cell, unlock)
            end
        end)
    end)
end

function ClientUnlock.GetStock(unlock)
    L.Dump("Unlock", unlock)
    local stock = unlock.Amount - unlock.Bought
    if stock > 0 then
        return __("Stock: %s", unlock.Amount - unlock.Bought .. "/" .. unlock.Amount)
    end
    return __("Out of stock")
end

function ClientUnlock.Tile(root, unlock)
    local grp = root:AddGroup(unlock.Id)

    grp:AddIcon(unlock.Icon)

    local text = grp:AddText(unlock.Name)
    grp:AddSeparator()

    local cost = grp:AddText(__("Cost: %s", unlock.Cost))
    grp:AddSeparator()

    do
        local unlock = unlock

        local notUnlocked = grp:AddText(__("Not unlocked"))
        notUnlocked.Visible = not unlock.Unlocked

        local cond = Components.Conditional(grp, function()
            if unlock.Character then
                return ClientUnlock.BuyChar(grp, unlock)
            end

            return ClientUnlock.Buy(grp, unlock)
        end)
        cond.Update(unlock.Unlocked)

        Event.On("StateChange", function(state)
            for _, new in pairs(state.Unlocks) do
                if new.Id == unlock.Id then
                    unlock = new
                    cond.Update(unlock.Unlocked)
                    notUnlocked.Visible = not unlock.Unlocked
                end
            end
        end)
    end
end

function ClientUnlock.Buy(root, unlock)
    local grp = root:AddGroup(U.RandomId())

    local buyLabel = grp:AddText("")
    grp:AddSeparator()
    local btn = grp:AddButton(__("Buy"))

    if unlock.Amount ~= nil then
        local amount = Components.Computed(buyLabel, function(root, unlock)
            return ClientUnlock.GetStock(unlock)
        end)
        amount.Update(unlock)

        Event.On("StateChange", function(state)
            for _, new in pairs(state.Unlocks) do
                if new.Id == unlock.Id then
                    amount.Update(new)
                    btn.Visible = new.Bought < new.Amount
                end
            end
        end)
    else
        buyLabel.Label = __("Infinite")
    end

    btn.IDContext = U.RandomId()
    btn.OnClick = function()
        Net.Request("BuyUnlock", { Id = unlock.Id }).After(function(event)
            local ok, res = table.unpack(event.Payload)

            if not ok then
                Event.Trigger("Error", res)
            else
                Event.Trigger("Success", __("Unlock %s bought.", unlock.Name))
                Event.Trigger("CurrencyChanged", res)
            end
        end)
    end

    return grp
end

function ClientUnlock.BuyChar(root, unlock)
    local grp = root:AddGroup(U.RandomId())

    local buyLabel = grp:AddText("")
    grp:AddSeparator()

    ---@type ExtuiCombo
    local combo = grp:AddCombo("")
    combo.IDContext = U.RandomId()
    combo.SameLine = true
    combo.SelectedIndex = 0
    ---@type ExtuiButton
    local btn = grp:AddButton(__("Buy"))
    btn.IDContext = U.RandomId()
    btn.SameLine = true

    if unlock.Amount ~= nil then
        local amount = Components.Computed(buyLabel, function(root, unlock)
            return ClientUnlock.GetStock(unlock)
        end)
        amount.Update(unlock)

        Event.On("StateChange", function(state)
            for _, new in pairs(state.Unlocks) do
                if new.Id == unlock.Id then
                    amount.Update(new)
                    local buyable = new.Amount == nil or new.Bought < new.Amount
                    btn.Visible = buyable
                    combo.Visible = buyable
                end
            end
        end)
    else
        buyLabel.Label = ""
    end

    local list = UT.Map(UE.GetParty(), function(e)
        return e.CustomName.Name .. " (" .. e.Uuid.EntityUuid .. ")", e.Uuid.EntityUuid
    end)

    btn.OnClick = function()
        local val = combo.Options[combo.SelectedIndex + 1]
        L.Debug("Buy", val, unlock.Id)
        local _, uuid = UT.Find(list, function(v)
            return v == val
        end)
        Net.Request("BuyUnlock", { Id = unlock.Id, Character = uuid }).After(function(event)
            local ok, res = table.unpack(event.Payload)
            combo.SelectedIndex = 0

            if not ok then
                Event.Trigger("Error", res)
            else
                local name = list[uuid]:match("^(.-) %(")
                Event.Trigger("Success", __("Unlock %s bought for %s.", unlock.Name, name))
                Event.Trigger("CurrencyChanged", res)
            end
        end)
    end

    Components.Computed(combo, function(_, state)
        local options = list
        if state.Unlocks then
            for _, u in pairs(state.Unlocks) do
                if u.Id == unlock.Id then
                    options = UT.Filter(list, function(v, k)
                        return not u.BoughtBy[k]
                    end, true)
                end
            end
        end

        return UT.Values(options)
    end, "StateChange", "Options").Update({})

    return grp
end