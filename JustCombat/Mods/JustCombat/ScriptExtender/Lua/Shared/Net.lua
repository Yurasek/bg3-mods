---@type Constants
local Constants = Require("Shared/Constants")
---@type Utils
local Utils = Require("Shared/Utils")
---@type Libs
local Libs = Require("Shared/Libs")

---@class Net
local M = {}

---@class NetEvent : LibsObject
---@field Action string
---@field Payload table
---@field UserId string|nil
---@field ResponseAction string|nil
local NetEvent = Libs.Object({
    Action = nil,
    Payload = nil,
    UserId = nil,
    ResponseAction = nil,
})

function NetEvent:__tostring()
    return Ext.Json.Stringify(self)
end

local listeners = {}

---@class NetListener : LibsObject
---@field Action string
---@field Once boolean
---@field Func fun(event: NetEvent): void
---@field Unregister fun(self: NetListener)
---@field New fun(action: string, callback: fun(event: NetEvent): void, once: boolean): NetListener
local NetListener = Libs.Object({
    Id = nil,
    Action = nil,
    Once = false,
    Func = function() end,
    Exec = function(self, e)
        xpcall(function()
            self.Func(m)
        end, function(err)
            Utils.Log.Error(err)
        end)

        if self.Once then
            self:Unregister()
        end
    end,
    Unregister = function(self)
        for i, l in pairs(listeners) do
            if l.Id == self.Id then
                table.remove(listeners, i)
            end
        end
    end,
})

function NetListener.New(action, callback, once)
    local o = NetListener.Init({
        Action = action,
        Func = callback,
        Once = once and true or false,
    })

    o.Id = tostring(o)

    table.insert(listeners, o)

    return o
end

Ext.Events.NetEvent:Subscribe(function(msg)
    if Constants.NetChannel ~= msg.Channel then
        return
    end

    local event = Ext.Json.Parse(msg.Payload)

    -- TODO Validate event
    local m = NetEvent.Init({
        Action = event.Action,
        Payload = event.Payload,
        UserId = msg.UserID,
        ResponseAction = event.ResponseAction,
    })

    for _, listener in pairs(listeners) do
        if listener.Action == m.Action then
            listener:Exec(m)
        end
    end
end)

---@param action string
---@param payload any
---@param userId string|nil
---@param responseAction string|nil
function M.Send(action, payload, userId, responseAction)
    local event = NetEvent.Init({
        Action = action,
        Payload = payload,
        UserId = userId,
        ResponseAction = responseAction or action,
    })

    if Ext.IsServer() then
        if event.UserId == nil then
            Ext.Net.BroadcastMessage(Constants.NetChannel, tostring(event))
        else
            Ext.Net.PostMessageToUser(event.UserId, Constants.NetChannel, tostring(event))
        end
        return
    end

    Ext.Net.PostMessageToServer(Constants.NetChannel, tostring(event))
end

---@param action string
---@param callback fun(event: NetEvent): void
---@param once boolean|nil
---@return NetListener
function M.On(action, callback, once)
    return NetListener.New(action, callback, once)
end

---@param action string
---@param callback fun(event: NetEvent): void
---@param params table
function M.Request(action, callback, params)
    local responseAction = action .. tostring(callback):gsub("function: ", "")
    local listener = M.On(responseAction, callback, true)

    M.Send(action, params, nil, responseAction)
end

---@param event NetEvent
---@param payload any
function M.Respond(event, payload)
    M.Send(event.ResponseAction, payload, event.UserId)
end

return M