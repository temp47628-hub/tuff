local M = {}

-- headlight button state
local prevIgnitionLevel = 0
local savedMode = 0
local prevLightsState = 0

-- light sound state
local volume, pitch = 1, 1
local lastButtonMode = -1

-- ============================================================
-- headlight mode handling
-- ============================================================

local function applyMode(m)
    electrics.values.audi6_headlightMode = m
    if m == 0 then
        electrics.values.button_auto_lights = 0
        electrics.setLightsState(0)
    elseif m == 1 then
        electrics.values.button_auto_lights = 1
        local autoLights = controller.getControllerSafe('autoHeadlights')
        if autoLights and autoLights.setActive then
            autoLights.setActive(false, true)
        end
    elseif m == 2 then
        electrics.values.button_auto_lights = 0
        electrics.setLightsState(1)
    end
end

local function resetLights()
    electrics.values.button_auto_lights = 0
    electrics.setLightsState(0)
    local autoLights = controller.getControllerSafe('autoHeadlights')
    if autoLights and autoLights.setActive then
        autoLights.setActive(false, true)
    end
end

local function cycleHeadlights()
    -- always cycle the mode and move the button regardless of ignition
    local m = (electrics.values.audi6_headlightMode or 0)
    m = (m + 1) % 3
    electrics.values.audi6_headlightMode = m
    savedMode = m

    -- only actually turn lights on if ignition is on
    if (electrics.values.ignitionLevel or 0) > 0 then
        applyMode(m)
    end
end

-- ============================================================
-- light sound handling
-- ============================================================

local function isInside()
    local camPos = obj:getCameraPosition()
    local vehPos = obj:getPosition()
    local velocity = obj:getVelocity()

    if not camPos or not vehPos then return false end

    local adjustedCamPos = camPos + (velocity * 0.04)
    return adjustedCamPos:distance(vehPos) < 2.0
end

-- ============================================================
-- lifecycle
-- ============================================================

local function resetState()
    electrics.values.lightbutton = 0
    electrics.values.audi6_headlightMode = 0
    lastButtonMode = electrics.values.audi6_headlightMode or 0
    prevLightsState = electrics.values.lights_state or 0
end

local function init()
    resetState()
    obj:createSFXSource("/art/sound/audi6/lights/lights.ogg", "Audio2D", "lights.ogg", -1)
end

local function updateGFX(dt)
    local ignition = electrics.values.ignitionLevel or 0
    local ignitionChanged = false

    -- ignition -> light state
    if prevIgnitionLevel > 0 and ignition == 0 then
        resetLights()
        ignitionChanged = true
    elseif prevIgnitionLevel == 0 and ignition > 0 then
        applyMode(savedMode)
        ignitionChanged = true
    end
    prevIgnitionLevel = ignition

    -- Sync the switch when the headlights are toggled OUTSIDE our button.
    -- Only lights_state 0 (off) and 1 (lowbeam) drive the switch. State 2 is
    -- highbeam -- and a flash is just a momentary highbeam -- so we ignore 2
    -- completely: it never moves the button, and we don't track it, so flashing
    -- leaves everything untouched.
    -- We run the FULL applyMode for the target (not just a mode change) so that
    -- button_auto_lights is cleared when leaving auto; otherwise the interior
    -- auto symbol would stay lit. Since we only ever sync on state 0/1, applyMode
    -- re-commands the same low/off state the game already set -- no override.
    local lightsState = electrics.values.lights_state or 0
    if ignitionChanged then
        -- ignition changed the lights itself this frame; not a manual toggle
        if lightsState == 0 or lightsState == 1 then
            prevLightsState = lightsState
        end
    elseif (lightsState == 0 or lightsState == 1) and lightsState ~= prevLightsState then
        prevLightsState = lightsState
        local target = (lightsState == 1) and 2 or 0  -- 2 = switch "on", 0 = "off"
        if target ~= (electrics.values.audi6_headlightMode or 0) then
            savedMode = target
            applyMode(target)
        end
    end

    -- button prop position
    local m = electrics.values.audi6_headlightMode or 0
    if m == 0 then
        electrics.values.lightbutton = 0.0
    elseif m == 1 then
        electrics.values.lightbutton = 0.25
    elseif m == 2 then
        electrics.values.lightbutton = 1.0
    end

    -- click sound whenever the switch position changes, from ANY source
    -- (custom button, ignition restore, or an external low/off toggle)
    if m ~= lastButtonMode then
        if isInside() then
            obj:playSFXOnce("lights.ogg", 0, volume, pitch)
        end
        lastButtonMode = m
    end
end

M.cycleHeadlights = cycleHeadlights
M.onInit = init
M.onReset = resetState
M.updateGFX = updateGFX

return M