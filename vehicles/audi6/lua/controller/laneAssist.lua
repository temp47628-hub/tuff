local M = {}
M.type = "auxiliary"

local MIN_ACTIVATION_SPEED = 18.05555555555556 -- 65 km/h in m/s

local function update(dt)
    local switched = (electrics.values.laneAssistSwitch or 0) == 1
    local ignition = electrics.values.ignitionLevel or 0
    local velocity = electrics.values.wheelspeed or 0

    -- Only operate if the switch is ON and ignition is at level 2
    if not switched or ignition ~= 2 then
        electrics.values.laneAssistAmber = 0
        electrics.values.laneAssistGreen = 0
        return
    end

    if velocity >= MIN_ACTIVATION_SPEED then
        electrics.values.laneAssistAmber = 0
        electrics.values.laneAssistGreen = 1
    else
        electrics.values.laneAssistAmber = 1
        electrics.values.laneAssistGreen = 0
    end
end

local function reset()
    electrics.values.laneAssistAmber = 0
    electrics.values.laneAssistGreen = 0
end

local function init(jbeamData)
    electrics.values.laneAssistAmber = 0
    electrics.values.laneAssistGreen = 0
end

M.init = init
M.update = update
M.reset = reset

print("Lane Assist indicator loaded.")

return M