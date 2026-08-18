local M = {}
M.autosave = true

local SAVE_INTERVAL = 60

local valueMeters = 0
local timer = 0
local speedMin = 0.5
local speedMax = 600

local function path()
    return "settings/audi6/odometerValue.json"
end

local function save()
    -- save in kilometers
    jsonWriteFile(path(), {value = valueMeters / 1000}, true)
end

local function onInit()
    -- load saved value
    local d = jsonReadFile(path())
    if d and d.value then
        valueMeters = tonumber(d.value) * 1000 -- convert km to meters
    end
end

local function updateGFX(dt)
    -- autosave timer
    if M.autosave then
        timer = timer + dt
        if timer >= SAVE_INTERVAL then
            save()
            timer = 0
        end
    end

    if electrics.values.audi6_odo == nil then
        electrics.values.audi6_odo = valueMeters
    end

    -- update odometer (integrate wheelspeed, which is m/s)
    if (electrics.values.engineRunning or 0) > 0.5 and (electrics.values.gearIndex or 0) ~= 0 then
        local s = electrics.values.wheelspeed or 0
        if s > speedMin and s < speedMax then
            valueMeters = valueMeters + (s * dt) -- meters
            electrics.values.audi6_odo = valueMeters
        end
    end
end

M.onInit = onInit
M.updateGFX = updateGFX
M.saveOdometer = save

return M
