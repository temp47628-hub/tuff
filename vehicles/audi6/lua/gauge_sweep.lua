local M = {}

local function lerp(a, b, t) return a + (b - a) * t end
local function smoothTo(current, target, dt, rate) return current + (target - current) * math.min(dt * rate, 1) end

local function makeWheelspeed(t1_kmh, t2_kmh)
    local t1 = t1_kmh / 3.6
    local t2 = t2_kmh and (t2_kmh / 3.6)
    return function(speed)
        if speed <= t1 then return speed * 2 end
        if not t2 or speed <= t2 then return (t1 * 2) + (speed - t1) end
        return (t1 * 2) + (t2 - t1) + (speed - t2) / 1.5
    end
end

local function makeWheelspeedMPH(t1_mph)
    local t1 = t1_mph / 1.61
    return function(speed)
        if speed <= t1 then return speed end
        return t1 + (speed - t1) * 0.66
    end
end

local ws2 = makeWheelspeed(80)
local ws3 = makeWheelspeed(80, 200)
local ws4 = makeWheelspeed(80, 240)

-- ┌─────────────────────────────────────────────────────────────┐
-- │  ADD NEW SWEEP ELECTRICS HERE                               │
-- │  name     = electrics.values key to write to                │
-- │  getValue = function returning the live target value        │
-- │  sweepMax = value the needle sweeps up to on ignition       │
-- └─────────────────────────────────────────────────────────────┘
local sweeps = {
    { name = "rpm_sweep",            getValue = function() return electrics.values.rpm or 0 end,                           sweepMax = 8000 },
    { name = "rpm_diesel_sweep",     getValue = function() return electrics.values.rpm or 0 end,                           sweepMax = 6000 },
    { name = "wheelspeed_sweep",     getValue = function() return electrics.values.wheelspeed or 0 end,                    sweepMax = 77.77 },
    { name = "wheelspeed_sweep_mph",     getValue = function() return electrics.values.wheelspeed or 0 end,                    sweepMax = 83.33 },
	
	--kmh
	
    { name = "wheelspeed_sweep_kmh", getValue = function() return ws2(electrics.values.wheelspeed or 0) end,               sweepMax = ws2(77.77) },
    { name = "wheelspeed_sweep_kmh2",getValue = function() return ws3(electrics.values.wheelspeed or 0) end,               sweepMax = ws3(91.66) },
    { name = "wheelspeed_sweep_kmh3",getValue = function() return ws4(electrics.values.wheelspeed or 0) end,               sweepMax = ws4(83.33) },
}

local previousIgnitionLevel = 0
local sweeping = false
local sweepDirection = 1
local timer = 0
local duration = 1
local holdDuration = 0.3
local smoothRate = 10

local function init()
    for _, s in ipairs(sweeps) do electrics.values[s.name] = 0 end
    previousIgnitionLevel = 0
    sweeping = false
    sweepDirection = 1
    timer = 0
end

local function updateGFX(dt)
    local currentIgnitionLevel = electrics.values.ignitionLevel or 0

    if previousIgnitionLevel < 2 and currentIgnitionLevel == 2 then
        sweeping = true
        sweepDirection = 1
        timer = 0
    end

    if currentIgnitionLevel >= 2 then
        if sweeping then
            timer = timer + dt
            local t = math.min(timer / duration, 1)

            if sweepDirection == 1 then
                for _, s in ipairs(sweeps) do
                    electrics.values[s.name] = lerp(0, s.sweepMax, t)
                end
                if t >= 1 then sweepDirection = 0; timer = 0 end

            elseif sweepDirection == 0 then
                for _, s in ipairs(sweeps) do
                    electrics.values[s.name] = s.sweepMax
                end
                if timer >= holdDuration then sweepDirection = -1; timer = 0 end

            elseif sweepDirection == -1 then
                for _, s in ipairs(sweeps) do
                    electrics.values[s.name] = lerp(s.sweepMax, s.getValue(), t)
                end
                if t >= 1 then sweeping = false end
            end
        else
            for _, s in ipairs(sweeps) do
                electrics.values[s.name] = smoothTo(electrics.values[s.name] or 0, s.getValue(), dt, smoothRate)
            end
        end
    else
        for _, s in ipairs(sweeps) do
            electrics.values[s.name] = smoothTo(electrics.values[s.name] or 0, 0, dt, smoothRate)
        end
        timer = 0
        sweeping = false
    end

    previousIgnitionLevel = currentIgnitionLevel
end

M.onInit = init
M.onReset = init
M.updateGFX = updateGFX

return M