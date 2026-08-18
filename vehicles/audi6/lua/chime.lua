local M = {}
local volume, pitch = 2, 1
local camNode = 0

local timer = 0
local nextDoorChimeTime = 0

local doorInterval = 1
local ignInterval = 1
local ignMaxDuration = 3

local ignTimer = 0
local ignActive = false
local nextIgnChimeTime = 0

local lastIgnitionLevel = 0

-- Lights-on door chime state
local lightsInterval = 0.658798  -- Exact duration of the chime sound
local lightsChimeLastPlayedTime = -999  -- Track actual last play time

local function inside()
    local camPos = obj:getCameraPosition()
    local vehPos = obj:getPosition()
    local velocity = obj:getVelocity()
    
    if not camPos or not vehPos then return false end

    local adjustedCamPos = camPos + (velocity * 0.04)
    return adjustedCamPos:distance(vehPos) < 2.0
end

local function anyDoorOpen()
    return
        electrics.values['door_FL_coupler_notAttached'] == 1 or
        electrics.values['door_FR_coupler_notAttached'] == 1 or
        electrics.values['door_RL_coupler_notAttached'] == 1 or
        electrics.values['door_RR_coupler_notAttached'] == 1 or
        electrics.values['trunkCoupler_notAttached'] == 1 or
        electrics.values['hoodLatchCoupler_notAttached'] == 1
end

local function update(dt)
    timer = timer + dt

    local ignitionLevel = electrics.values['ignitionLevel'] or 0
    local lights = (electrics.values['lights_state'] or 0)
    local doorOpen = anyDoorOpen()
    local doorActive = ignitionLevel >= 2 and doorOpen
    local isInside = inside()

    -- Lights-on door chime: car off (ignLevel < 2) + lights on + door open
    local lightsChimeActive = ignitionLevel < 2 and lights > 0 and doorOpen

    -- Detect ignition entering level 2
    if ignitionLevel == 2 and lastIgnitionLevel ~= 2 then
        ignActive = true
        ignTimer = 0
        nextIgnChimeTime = 0
    end

    -- If ignition leaves level 2, stop ignition chime immediately
    if ignitionLevel ~= 2 then
        ignActive = false
    end

    if not isInside then
        ignActive = false
        nextDoorChimeTime = timer
        lastIgnitionLevel = ignitionLevel
        return
    end

    -- Door chime (highest priority: ignition on + door open)
    if doorActive then
        if timer >= nextDoorChimeTime then
            obj:playSFXOnce("chimeOn.ogg", camNode, volume, pitch)
            nextDoorChimeTime = timer + doorInterval
        end

    -- Ignition level 2 chime
    elseif ignActive then
        ignTimer = ignTimer + dt

        if ignTimer >= nextIgnChimeTime and ignTimer < ignMaxDuration then
            obj:playSFXOnce("chimeOn.ogg", camNode, volume, pitch)
            nextIgnChimeTime = ignTimer + ignInterval
        end

        if ignTimer >= ignMaxDuration then
            ignActive = false
        end

    -- Lights-on door chime (car off, lights on, door open)
    elseif lightsChimeActive then
        if timer - lightsChimeLastPlayedTime >= lightsInterval then
            obj:playSFXOnce("chimeLightsOn.ogg", camNode, volume, pitch)
            lightsChimeLastPlayedTime = timer
        end

    else
        nextDoorChimeTime = timer
    end

    lastIgnitionLevel = ignitionLevel
end

local function init()
    camNode = beamstate.nodeNameMap["driver"] or 0
    obj:createSFXSource("/art/sound/audi6/chime/chimeOn.ogg", "Audio2D", "chimeOn.ogg", -1)
    obj:createSFXSource("/art/sound/audi6/chime/chimeLightsOn.ogg", "Audio2D", "chimeLightsOn.ogg", -1)
end

M.onInit = init
M.updateGFX = update
return M