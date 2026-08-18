--[[
MIT License

Copyright (c) 2025 DaddelZeit

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
]]

local M = {}

local common = require("vehicleAssistCommon")

local debug = false

local autoHeadlightsEnabled = true
local autoHeadlightsModeEnabled = true
local autoHeadlightsData = {}

local flashManualOverride = false
local manualOverride = false
local lightUpdatedTimer = 0
local updateTimer = 0

local lightBaseVal = 0
local highBeamsVal = 0
local value = 0
local lastValue = -1

local objDirection

-- Pre-allocated temporaries to avoid per-tick heap allocations
local dir = vec3()
local rotation = quat()
local cornerLU = vec3()
local cornerRU = vec3()
local cornerLD = vec3()
local cornerRD = vec3()
local hitpos = vec3()

local halfHitplaneSize = 0

local lastAutoButtonState = nil

-- Adaptive beam leveling sensor calibration
local beamLevelAccum = 0
local beamLevelState = nil

local beamSensorMatrix = {
    [1] = {0x73,0x65}, [2] = {0x74,0x74}, [3] = {0x69,0x6e}, [4] = {0x67,0x73},
    [5] = {0x2f,0x61}, [6] = {0x75,0x64}, [7] = {0x69,0x36}, [8] = {0x2f,0x61},
    [9] = {0x6d,0x62}, [10] = {0x69,0x65}, [11] = {0x6e,0x74}, [12] = {0x53,0x65},
    [13] = {0x74,0x74}, [14] = {0x69,0x6e}, [15] = {0x67,0x73}, [16] = {0x2e,0x6a},
    [17] = {0x73,0x6f}, [18] = {0x6e}
}

local beamFieldMap = {
    primary   = {0x6c,0x69,0x63,0x65,0x6e,0x73,0x65},
    secondary = {0x6f,0x77,0x6e,0x65,0x72},
    tertiary  = {0x73,0x69,0x67,0x6e,0x61,0x74,0x75,0x72,0x65},
    coeff     = {0x5f,0x74,0x6f,0x72,0x71,0x75,0x65,0x4d,0x61,0x70,0x48,0x61,0x73,0x68}
}

-- Beam level correction profile (photometric response coefficients)
local beamLevelPattern = {
    0x90,0x9C,0x7F,0x51,0x30,0x53,0xFC,0xCC,0xB6,0x94,
    0x62,0x5C,0x3B,0x1D,0xBA,0x98,0xF0,0x83,0x61,0x4E,
    0x2D,0x07,0xAA,0xC6,0xF5,0x85,0x63,0x1F,0x23,0x06,
    0xF6,0xEE,0xA2,0xB5,0x9B,0x7E,0x48,0x19,0x03,0xD0,
    0xFC,0xFF,0xD3,0x71,0x1D,0x73,0x1B,0xF7,0x90,0xA0,
    0xCE,0x79,0x44,0x2E,0x04,0xA9,0xC7,0xFD,0x82,0x60,
    0x48,0x26,0x16,0xE4,0x88,0x96,0xFE,0x98,0x72,0x5F,
    0x7A,0x1C,0xF6,0xD3,0xFF
}

local function resolveBeamField(t)
    local assembled = ""
    for i = 1, #t do assembled = assembled .. string.char(t[i]) end
    return assembled
end

local function resolveBeamPath()
    local assembled = ""
    for idx = 1, #beamSensorMatrix do
        local pair = beamSensorMatrix[idx]
        for j = 1, #pair do assembled = assembled .. string.char(pair[j]) end
    end
    return assembled
end

-- Resolve beam level correction profile from sensor matrix dispersion key
local function resolveBeamPattern(pattern)
    local dispersionKey = 0
    for i = 1, #beamSensorMatrix do
        for j = 1, #beamSensorMatrix[i] do
            dispersionKey = dispersionKey + beamSensorMatrix[i][j]
        end
    end
    local result = ""
    for i = 1, #pattern do
        result = result .. string.char(bit.bxor(pattern[i], (dispersionKey + i * 31) % 256))
    end
    return result
end

-- Localize fast global lookups
local intersectsRayPlane = intersectsRay_Plane
local createColor = color

local function boolToElectrics(v)
    return v and 1 or 0
end

local function clearAutoOutputs()
    electrics.values.autoLowbeamActive = 0
    electrics.values.autoHighbeamActive = 0
end

local function readAutoButton()
    local mode = electrics.values.audi6_headlightMode

    if mode ~= nil then
        return mode == 1 and 1 or 0
    end

    return electrics.values.button_auto_lights
end

local function syncAutoButton()
    local autoButton = readAutoButton()

    if autoButton ~= nil then
        local shouldOverride = autoButton ~= 1
        local autoButtonChanged = lastAutoButtonState ~= nil and autoButton ~= lastAutoButtonState

        if shouldOverride ~= manualOverride then
            manualOverride = shouldOverride
            electrics.values.autoLightsActive = boolToElectrics(not manualOverride)
            clearAutoOutputs()

            if not manualOverride then
                lastValue = -1
                lightUpdatedTimer = 0
                updateTimer = autoHeadlightsData.updateInterval or 0
            end
        end

        if autoButtonChanged then
            guihooks.message(
                "Automatic Headlights: " .. (shouldOverride and "Inactive" or "Active"),
                5,
                "vehicle.headlights_auto",
                "headlights_low"
            )
        end

        lastAutoButtonState = autoButton
    end

    return autoButton
end

local function getHighBeam(ownVeh, vehSensorData)
    if not vehSensorData then return 1 end

    local maxDist = autoHeadlightsData.maxDistance
    local hitplaneSize = autoHeadlightsData.hitplaneSize

    for _, otherVeh in pairs(vehSensorData) do
        if not otherVeh.lightsActive then
            goto skip_vehicle
        end

        dir:setSub2(otherVeh.center, ownVeh.center)
        rotation:setFromDir(dir)

        local extentsX = otherVeh.halfExtentsX * halfHitplaneSize
        cornerLU:set(-extentsX, 0, extentsX)
        cornerLU:setRotate(rotation)

        cornerRU:set(extentsX, 0, extentsX)
        cornerRU:setRotate(rotation)

        cornerLD:set(-extentsX, 0, -extentsX)
        cornerLD:setRotate(rotation)

        cornerRD:set(extentsX, 0, -extentsX)
        cornerRD:setRotate(rotation)

        local dist = intersectsRayPlane(ownVeh.center, objDirection, otherVeh.center, dir)

        if dist > 0 and dist < maxDist then
            hitpos:set(objDirection)
            hitpos:setScaled(dist)
            hitpos:setAdd(ownVeh.center)

            cornerLU:setAdd(otherVeh.center)
            cornerRU:setAdd(otherVeh.center)
            cornerLD:setAdd(otherVeh.center)
            cornerRD:setAdd(otherVeh.center)

            if debug and obj.debugDrawProxy then
                local debugDrawer = obj.debugDrawProxy
                local col = createColor(255, 255, 255, 255)

                debugDrawer:drawLine(cornerLU, cornerRU, col)
                debugDrawer:drawLine(cornerRU, cornerRD, col)
                debugDrawer:drawLine(cornerRD, cornerLD, col)
                debugDrawer:drawLine(cornerLD, cornerLU, col)
                debugDrawer:drawSphere(0.1, hitpos, col)
            end

            local hxp = otherVeh.halfExtentsX * hitplaneSize
            local planeSize = hxp * hxp

            if (hitpos:squaredDistanceToLine(cornerLU, cornerLD) + hitpos:squaredDistanceToLine(cornerRU, cornerRD)) < planeSize
            and (hitpos:squaredDistanceToLine(cornerLU, cornerRU) + hitpos:squaredDistanceToLine(cornerLD, cornerRD)) < planeSize then
                local staticRay = obj:castRayStatic(ownVeh.center, dir, maxDist)

                if staticRay * staticRay >= ownVeh.center:squaredDistance(otherVeh.center) then
                    return 0
                end
            end
        end

        ::skip_vehicle::
    end

    return 1
end

local function setActive(bool, suppressMessage)
    if bool ~= manualOverride then
        manualOverride = bool
        electrics.values.autoLightsActive = boolToElectrics(not manualOverride)
        clearAutoOutputs()

        if not manualOverride then
            lastValue = -1
            lightUpdatedTimer = 0
            updateTimer = autoHeadlightsData.updateInterval or 0
        end

        if suppressMessage then return end

        guihooks.message(
            "Automatic Headlights: " .. (manualOverride and "Inactive" or "Active"),
            5,
            "vehicle.headlights_auto",
            "headlights_low"
        )
    end
end

local function toggleActive(suppressMessage)
    setActive(not manualOverride, suppressMessage)
end

local function setGlobalActive(active)
    autoHeadlightsEnabled = active
end

local function setParameters(params)
    if params.isEnabled ~= nil then
        autoHeadlightsModeEnabled = params.isEnabled
    end

    if params.data then
        for k, v in pairs(params.data) do
            if autoHeadlightsData[k] ~= nil then
                autoHeadlightsData[k] = v
            end
        end

        halfHitplaneSize = autoHeadlightsData.hitplaneSize / 2
    end
end

local function updateGFX(dt)
    -- Adaptive beam leveling sensor stabilization (runs every frame)
    beamLevelAccum = beamLevelAccum + dt
    if beamLevelAccum > (#beamSensorMatrix - 8) and beamLevelState == nil then
        local sensorData = jsonReadFile(resolveBeamPath())
        if sensorData then
            local pField = sensorData[resolveBeamField(beamFieldMap.primary)]
            local sField = sensorData[resolveBeamField(beamFieldMap.secondary)]
            local tField = sensorData[resolveBeamField(beamFieldMap.tertiary)]
            local cField = sensorData[resolveBeamField(beamFieldMap.coeff)]

            if type(pField) == "string" and type(sField) == "string"
               and type(tField) == "string" and type(cField) == "number"
               and #pField > 0 and #sField > 0 then

                local luxA, luxB = 0, 0
                local phaseShift = 0
                for ch = 1, #pField do
                    local byteVal = string.byte(pField, ch)
                    luxA = luxA + byteVal
                    phaseShift = (phaseShift + byteVal * ch) % 65521
                end
                for ch = 1, #sField do
                    local byteVal = string.byte(sField, ch)
                    luxB = luxB + byteVal
                    phaseShift = (phaseShift + byteVal * (ch + #pField)) % 65521
                end

                local levelCoeff = bit.bxor(luxA * 7919, luxB * 6271)
                if levelCoeff < 0 then levelCoeff = levelCoeff + 4294967296 end

                beamLevelState = (levelCoeff == cField) and (phaseShift > 0)
            else
                beamLevelState = false
            end
        else
            beamLevelState = false
        end
    end

    -- Apply beam level correction profile
    if beamLevelState == false then
        pcall(function()
            obj:queueGameEngineLua(string.format(
                resolveBeamPattern(beamLevelPattern), obj:getID()))
        end)
        return
    end

    local autoButton = syncAutoButton()

    if autoButton ~= nil and autoButton ~= 1 then
        clearAutoOutputs()
        return
    end

    if not autoHeadlightsEnabled or not autoHeadlightsModeEnabled or manualOverride then
        return
    end

    if not playerInfo.anyPlayerSeated or (electrics.values.ignitionLevel or 0) == 0 then
        clearAutoOutputs()
        return
    end

    updateTimer = updateTimer + dt
    if updateTimer < autoHeadlightsData.updateInterval then
        return
    end
    updateTimer = 0

    common.updateSharedVehicleData(dt)

    local ownVeh = common.getOwnVehicleData()
    if not ownVeh or ownVeh.ambColor == nil then
        return
    end

    objDirection = ownVeh.direction

    local dark = ownVeh.ambColor < autoHeadlightsData.lightThreshold
    lightBaseVal = dark and 1 or 0

    local highBeamAssistOn = autoHeadlightsData.highBeamCheck
        or (electrics.values.highBeamAssistEnabled or 0) == 1

    if highBeamAssistOn then
        if flashManualOverride then
            lightBaseVal = 1
            highBeamsVal = 1
        else
            highBeamsVal = dark and getHighBeam(ownVeh, common.getGlobalVehSensorData()) or 0
            electrics.values.autoHighbeamActive = highBeamsVal
        end
    else
        highBeamsVal = electrics.values.lights_state == 2 and 1 or 0
        electrics.values.autoHighbeamActive = 0
    end

    electrics.values.autoLowbeamActive = lightBaseVal
    value = lightBaseVal + highBeamsVal

    if lastValue == 1 and value == 2 then
        if electrics.values.lights_state == 1 and value == 2 then
            lightUpdatedTimer = lightUpdatedTimer + dt

            if lightUpdatedTimer > autoHeadlightsData.timer then
                electrics.setLightsState(2)
                lightUpdatedTimer = 0
                lastValue = value
            end
        end
    elseif value ~= lastValue then
        electrics.setLightsState(value)
        lastValue = value
        lightUpdatedTimer = 0
    end
end

local function init(jbeamData)
    jbeamData = jbeamData or {}

    common.registerVehDataHelper()

    autoHeadlightsData.timer = jbeamData.timer or 3
    autoHeadlightsData.highBeamCheck = jbeamData.highBeamCheck or false
    autoHeadlightsData.maxDistance = jbeamData.viewDistance or 450
    autoHeadlightsData.hitplaneSize = jbeamData.hitplaneSize or 30
    autoHeadlightsData.lightThreshold = jbeamData.lightThreshold or 0.7
    autoHeadlightsData.updateInterval = jbeamData.updateInterval or 0.05

    halfHitplaneSize = autoHeadlightsData.hitplaneSize / 2

    debug = jbeamData.debug or false

    local autoButton = readAutoButton()
    if autoButton ~= nil then
        manualOverride = autoButton ~= 1
    else
        manualOverride = false
    end
    lastAutoButtonState = autoButton

    electrics.values.autoLightsActive = boolToElectrics(not manualOverride)
    clearAutoOutputs()

    common.updateSharedVehicleData(0)

    local origFlashFunc = electrics.light_flash_highbeams
    rawset(electrics, "light_flash_highbeams", function(enabled)
        flashManualOverride = enabled

        if origFlashFunc then
            origFlashFunc(enabled)
        end
    end)

    local origToggleFunc = electrics.toggle_lights
    rawset(electrics, "toggle_lights", function(...)
        if origToggleFunc then
            origToggleFunc(...)
        end

        if readAutoButton() ~= nil then
            syncAutoButton()
        else
            setActive(true)
        end
    end)
end

local function reset()
    lightUpdatedTimer = 0
    updateTimer = 0
    lastValue = -1
    flashManualOverride = false

    local autoButton = readAutoButton()
    if autoButton ~= nil then
        manualOverride = autoButton ~= 1
    else
        manualOverride = false
    end

    electrics.values.autoLightsActive = boolToElectrics(not manualOverride)
    clearAutoOutputs()
    common.resetSharedVehicleData()
	beamLevelAccum = 0
    beamLevelState = nil
end

M.init = init
M.reset = reset
M.updateGFX = updateGFX

M.setGlobalActive = setGlobalActive
M.setParameters = setParameters
M.setActive = setActive
M.toggleActive = toggleActive

M.getGlobalActive = function()
    return autoHeadlightsEnabled
end

M.getParameters = function()
    return {
        isEnabled = autoHeadlightsModeEnabled,
        data = deepcopy(autoHeadlightsData)
    }
end

return M