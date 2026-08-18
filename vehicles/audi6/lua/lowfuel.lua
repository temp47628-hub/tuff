local M = {}

local lastLowFuelState = 0
local volume, pitch = 2, 1
local camNode = 0

local function inside()
    local camPos = obj:getCameraPosition()
    local vehPos = obj:getPosition()
    local velocity = obj:getVelocity()

    if not camPos or not vehPos then return false end

    local adjustedCamPos = camPos + (velocity * 0.04)
    return adjustedCamPos:distance(vehPos) < 2.0
end

local function normalize(value)
    if value == true then
        return 1
    elseif value == false or value == nil then
        return 0
    else
        return value > 0 and 1 or 0
    end
end

local function init()
    lastLowFuelState = normalize(electrics.values.lowfuel)
    camNode = beamstate.nodeNameMap["driver"] or 0

    obj:createSFXSource("/art/sound/audi6/lowfuel/lowfuel.ogg", "Audio2D", "lowfuel.ogg", -1)
end

local function updateGFX(dt)
    local lowFuelState = normalize(electrics.values.lowfuel)

    if lowFuelState == 1 and lastLowFuelState == 0 then
        if inside() then
            obj:playSFXOnce("lowfuel.ogg", camNode, volume, pitch)
        end
    end

    lastLowFuelState = lowFuelState
end

M.onInit = init
M.onReset = init
M.updateGFX = updateGFX

return M
