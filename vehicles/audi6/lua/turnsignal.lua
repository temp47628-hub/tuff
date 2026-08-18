local M = {}
local volume, pitch = 2, 1
local wasOn = false

-- Increased threshold + Velocity compensation
local function isInside()
    local camPos = obj:getCameraPosition()
    local vehPos = obj:getPosition()
    local velocity = obj:getVelocity()
    
    if not camPos or not vehPos then return false end

    -- At high speeds, the camera lags by roughly 0.03 to 0.05 seconds.
    -- We "pull" the camera position forward by the car's velocity to fix the lag.
    local adjustedCamPos = camPos + (velocity * 0.04)
    
    -- We use a slightly larger 2-meter bubble. 
    -- This is small enough to stay 'inside' but large enough to never cut out.
    return adjustedCamPos:distance(vehPos) < 2.0
end

local function update(dt)
    -- Check if either signal is active (using > 0.5 for reliability)
    local isOn = (electrics.values.signal_L > 0.5) or (electrics.values.signal_R > 0.5)
    
    if isOn ~= wasOn then
        if isInside() then
            -- Use '0' for the node to attach the sound to the vehicle center
            obj:playSFXOnce(isOn and "ts1.ogg" or "ts2.ogg", 0, volume, pitch)
        end
        wasOn = isOn
    end
end

local function init()
    -- Audio2D is essential here because it ignores 3D positioning, 
    -- ensuring you hear it perfectly regardless of speed.
    obj:createSFXSource("/art/sound/audi6/turnsignal/ts1.ogg", "Audio2D", "ts1.ogg", -1)
    obj:createSFXSource("/art/sound/audi6/turnsignal/ts2.ogg", "Audio2D", "ts2.ogg", -1)
end

M.onInit = init
M.updateGFX = update
return M