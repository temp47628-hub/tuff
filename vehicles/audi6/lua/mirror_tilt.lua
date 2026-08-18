local M = {}

local rightMirror = nil
local mirrorDetected = false
local reverseTiltX = 8
local reverseTiltZ = -8
local tiltSpeed = 1.0
local currentProgress = 0
local targetProgress = 0

local function setMirrorTilt(xOffset, zOffset)
    if not rightMirror then return end
    local vid = obj:getId()
    obj:queueGameEngineLua(string.format(
        "local veh = getObjectByID(%d); extensions.core_vehicle_mirror.setAngleOffset('%s', %f, %f, veh, false)",
        vid, rightMirror, xOffset, zOffset
    ))
end

local function detectRightMirror()
    if mirrorDetected then return end
    if not v or not v.data or not v.data.mirrors then return end
    for _, mirror in pairs(v.data.mirrors) do
        if type(mirror) == 'table' and mirror.mesh then
            if mirror.mesh:lower():find("mirrormain_r") then
                rightMirror = mirror.mesh
            end
        end
    end
    log('I', 'mirrors', 'right=' .. tostring(rightMirror))
    mirrorDetected = true
    setMirrorTilt(0, 0)
end

local function updateGFX(dt)
    if not mirrorDetected then detectRightMirror() end
    if not electrics.values or not rightMirror then return end
    if electrics.values.memoryMirrorsEnabled ~= 1 then return end

    targetProgress = (electrics.values.reverse == 1) and 2 or 0

    if currentProgress ~= targetProgress then
        local step = tiltSpeed * dt
        if currentProgress < targetProgress then
            currentProgress = math.min(currentProgress + step, targetProgress)
        else
            currentProgress = math.max(currentProgress - step, targetProgress)
        end
        setMirrorTilt(
            math.min(currentProgress, 1) * reverseTiltX,
            math.max(currentProgress - 1, 0) * reverseTiltZ
        )
    end
end

local function onReset()
    currentProgress = 0
    targetProgress = 0
    setMirrorTilt(0, 0)
end

M.updateGFX = updateGFX
M.onReset = onReset
return M