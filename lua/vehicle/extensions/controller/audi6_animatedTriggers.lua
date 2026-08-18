-- This Source Code Form is subject to the terms of the bCDDL, v. 1.1.
-- If a copy of the bCDDL was not distributed with this
-- file, You can obtain one at http://beamng.com/bCDDL-1.1.txt

local M = {}

local elements = {}

local function init(jbeamData)
    local defs = jbeamData.animatedTriggers or {}

    for name, data in pairs(defs) do
        local rot = data.rot or 0
        local rotVec

        if type(rot) == "table" then
            rotVec = vec3(rot[1] or 0, rot[2] or 0, rot[3] or 0)
        else
            rotVec = vec3(rot, 0, 0)
        end

        elements[name] = {
            triggerID       = nil,
            posDiff         = vec3(
                data.pos and data.pos[1] or 0,
                data.pos and data.pos[2] or 0,
                data.pos and data.pos[3] or 0
            ),
            rotAngle        = rotVec,
            electricName     = data.electricName or (name:match("^(.-)_int$") or name),

            -- default keeps previous lua behavior for other triggers
            mode            = data.mode or "default",

            hideTime        = data.hideTime or 1.2,
            hideTimer       = 0,
            lastRawInput    = 0,

            currentState    = 0,
            wasVisible      = false
        }
    end

    for _, triggerData in pairs(v.data.triggers) do
        local name = triggerData.name
        if elements[name] then
            elements[name].triggerID = triggerData.abid
        end
    end
end

local function hideTrigger(element)
    if not element.triggerID then return end

    if element.wasVisible then
        obj:queueGameEngineLua(string.format(
            [[local veh = be:getObjectByID(%d)
              if veh then
                local trg = veh:getTrigger(%d)
                if trg then
                  trg:update(vec3(0,0,-1000), vec3(0,0,0), true, 0)
                end
              end]],
            obj:getId(), element.triggerID
        ))

        element.wasVisible = false
    end
end

local function showTrigger(element)
    if not element.triggerID then return end

    local t = element.currentState

    local p = element.posDiff * t
    local r = vec3(
        math.rad(element.rotAngle.x) * t,
        math.rad(element.rotAngle.y) * t,
        math.rad(element.rotAngle.z) * t
    )

    obj:queueGameEngineLua(string.format(
        [[local veh = be:getObjectByID(%d)
          if veh then
            local trg = veh:getTrigger(%d)
            if trg then
              trg:update(vec3(%f,%f,%f), vec3(%f,%f,%f), true, 0)
            end
          end]],
        obj:getId(), element.triggerID,
        p.x, p.y, p.z,
        r.x, r.y, r.z
    ))

    element.wasVisible = true
end

local function updateDefault(element)
    local isClosed = element.currentState <= 0.02
    local isOpen   = element.currentState >= 0.98

    if isClosed or isOpen then
        showTrigger(element)
    else
        hideTrigger(element)
    end
end

local function updateTimerHide(element, dt)
    local rawInput = electrics.values[element.electricName] or 0

    -- detect click/input change and hide trigger for a timed duration
    if math.abs(rawInput - element.lastRawInput) > 0.05 then
        element.hideTimer = element.hideTime
    end

    element.lastRawInput = rawInput

    if element.hideTimer > 0 then
        element.hideTimer = math.max(0, element.hideTimer - dt)
        hideTrigger(element)
    else
        showTrigger(element)
    end
end

local function updateGFX(dt)
    for name, element in pairs(elements) do
        element.currentState = electrics.values[element.electricName .. "_s"]
                            or electrics.values[element.electricName]
                            or 0

        if element.mode == "timerHide" then
            updateTimerHide(element, dt)
        elseif element.mode == "continuous" then
            showTrigger(element)
        else
            updateDefault(element)
        end
    end
end

M.init = init
M.updateGFX = updateGFX

return M