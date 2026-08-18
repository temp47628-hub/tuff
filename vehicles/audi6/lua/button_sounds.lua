local M = {}

local volume, pitch = 2, 1

local soundPath1 = "/art/sound/audi6/buttons/press_button.ogg"
local soundPath2 = "/art/sound/audi6/buttons/press_knob.ogg"
local soundPath3 = "/art/sound/audi6/buttons/rotate_knob.ogg"

local lastDriveMode = nil

local function getDriveModeName()
    local controllerData = controller.getController("driveModes")
    if controllerData then
        local serialized = controllerData.serialize()
        return serialized and serialized.activeDriveModeKey or nil
    end
    return nil
end

local function isInside()
    local camPos = obj:getCameraPosition()
    local vehPos = obj:getPosition()
    local velocity = obj:getVelocity()
    
    if not camPos or not vehPos then return false end

    local adjustedCamPos = camPos + (velocity * 0.04)
    return adjustedCamPos:distance(vehPos) < 2.0
end

-- Direct sound function for button press (button clicks)
function M.playPressSound()
    if isInside() then
        obj:playSFXOnce("press_button", 0, volume, pitch)
    end
end

-- Direct sound function for knob press
function M.playKnobSound()
    if isInside() then
        obj:playSFXOnce("press_knob", 0, volume, pitch)
    end
end

-- Direct sound function for knob rotation
function M.playRotateSound()
    if isInside() then
        obj:playSFXOnce("rotate_knob", 0, volume, pitch)
    end
end

local function checkDriveMode()
    local currentDriveMode = getDriveModeName()
    if currentDriveMode ~= lastDriveMode then
        if lastDriveMode ~= nil and isInside() then
            obj:playSFXOnce("press_button", 0, volume, pitch)
        end
        lastDriveMode = currentDriveMode
    end
end

local function update(dt)
    -- Only monitor drive mode changes for ESC button
    checkDriveMode()
end

local function init()
    lastDriveMode = getDriveModeName()
    
    obj:createSFXSource(soundPath1, "Audio2D", "press_button", -1)
    obj:createSFXSource(soundPath2, "Audio2D", "press_knob", -1)
    obj:createSFXSource(soundPath3, "Audio2D", "rotate_knob", -1)
end

M.onInit = init
M.updateGFX = update
return M