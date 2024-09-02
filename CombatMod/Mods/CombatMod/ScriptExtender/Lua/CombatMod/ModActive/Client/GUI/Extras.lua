Extras = {}

function Extras.Main(tab)
    ---@type ExtuiTabItem
    local root = tab:AddTabItem(__("Extras")):AddChildWindow(""):AddGroup("")
    root.PositionOffset = { 5, 5 }
    root:AddSeparatorText(__("Extra features"))

    Components.Conditional(nil, function()
        return {
            Extras.Button(root, "Clean Ground", "", function(btn)
                Net.Request("ClearSurfaces"):After(DisplayResponse)
            end),
            Extras.Button(
                root,
                "Remove all Entities",
                "",
                function(btn)
                    Net.Request("RemoveAllEntities"):After(DisplayResponse)
                end
            ),
        }
    end, "ToggleDebug")

    root:AddSeparator()
    Extras.Button(root, __("End Long Rest"), __("Use when stuck in night time."), function(btn)
        Net.Request("CancelLongRest"):After(DisplayResponse)
    end)

    root:AddSeparator()
    Extras.Button(root, __("Cancel Dialog"), __("End the current dialog."), function(btn)
        Net.Request("CancelDialog"):After(DisplayResponse)
    end)

    root:AddSeparatorText(__("Recruit Origins (Experimental)"))
    root:AddDummy(1, 1)
    for name, char in pairs(C.OriginCharacters) do
        local desc = ""

        local b = Extras.Button(root, name, desc, function(btn)
            Net.Request("RecruitOrigin", name):After(DisplayResponse)
        end)

        b.SameLine = true
    end
    root:AddText(__("Needs to be run multiple times in some cases. May not work in all cases."))
    root:AddText(__("Level will be reset. Inventory will be emptied."))
    root:AddSeparator()
end

function Extras.Button(root, text, desc, callback)
    local root = root:AddGroup("")

    local b = root:AddButton(text)
    b.IDContext = U.RandomId()
    b.OnClick = callback

    if desc then
        for i, s in ipairs(string.split(desc, "\n")) do
            if s ~= "" then
                root:AddText(s).SameLine = i == 1
            end
        end
    end

    return root
end
