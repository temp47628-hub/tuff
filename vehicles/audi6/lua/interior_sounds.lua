local M = {}

-- Add new boolean electrics here.
-- Each entry needs: electric name, sound file for on (1), sound file for off (0), volume, pitch.
local electricSounds = {
    {
        electric  = "armrest",
        onSound   = "/art/sound/audi6/armrest/up.ogg",
        offSound  = "/art/sound/audi6/armrest/down.ogg",
        volume    = 2,
        pitch     = 1,
    },
    {
        electric  = "armrest_door",
        onSound   = "/art/sound/audi6/armrest_door/open.ogg",
        offSound  = "/art/sound/audi6/armrest_door/close.ogg",
        volume    = 2,
        pitch     = 1,
    },
    {
        electric  = "cupholder_door",
        onSound   = "/art/sound/audi6/cupholder_door/open.ogg",
        offSound  = "/art/sound/audi6/cupholder_door/close.ogg",
        volume    = 2,
        pitch     = 1,
    },
    {
        electric  = "glovebox_door",
        onSound   = "/art/sound/audi6/glovebox_door/open.ogg",
        offSound  = "/art/sound/audi6/glovebox_door/close.ogg",
        volume    = 2,
        pitch     = 1,
    },
}

local lastStates = {}

local function isInside()
    local camPos = obj:getCameraPosition()
    local vehPos = obj:getPosition()
    local velocity = obj:getVelocity()

    if not camPos or not vehPos then return false end

    local adjustedCamPos = camPos + (velocity * 0.04)
    return adjustedCamPos:distance(vehPos) < 2.0
end

local function update(dt)
    if not isInside() then return end

    for _, entry in ipairs(electricSounds) do
        local current = electrics.values[entry.electric] or 0
        if current ~= lastStates[entry.electric] then
            if current == 1 then
                obj:playSFXOnce(entry.electric .. "_sfx_on", 0, entry.volume, entry.pitch)
            elseif current == 0 then
                obj:playSFXOnce(entry.electric .. "_sfx_off", 0, entry.volume, entry.pitch)
            end
            lastStates[entry.electric] = current
        end
    end
end

local function init()
    for _, entry in ipairs(electricSounds) do
        lastStates[entry.electric] = electrics.values[entry.electric] or 0
        obj:createSFXSource(entry.onSound,  "Audio2D", entry.electric .. "_sfx_on",  -1)
        obj:createSFXSource(entry.offSound, "Audio2D", entry.electric .. "_sfx_off", -1)
    end
end

M.onInit = init
M.updateGFX = update
return M
