local M = {}

-- UI Context
local CONTEXT = { NONE = 0, FAN = 1, SEAT_L = 2, SEAT_R = 3, AIR_L = 4, AIR_R = 5 }

local pulseMapping = {
    button_fan           = CONTEXT.FAN,
    button_auto1         = CONTEXT.FAN,
    button_auto2         = CONTEXT.FAN,
    button_heatedseat1   = CONTEXT.SEAT_L,
    button_heatedseat2   = CONTEXT.SEAT_R,
    button_airflow1      = CONTEXT.AIR_L,
    button_airflow2      = CONTEXT.AIR_R,
    button_frontdemister = CONTEXT.FAN
}

local statusButtons = {
    button_auto1 = true,
    button_auto2 = true,
    button_frontdemister = true
}

local savedHVAC = {}

local activeTimers = {}
local prevValues = {}
local prevMMIMenu = nil

local lastManualFan = 2
local lastIgnition = 0
local dialChangedButtons = {}

-- MMI scroll sync: delta-only, no bidirectional sync needed
local prevSyncCtx    = 0
local lastMmiScroll  = 0
local savedMmiScroll = nil
local savedMmiMax    = nil

-- HVAC value ranges per context: max value + electrics key
-- wrap = true: modular arithmetic (airflow), otherwise clamped (fan/seat)
local HVAC_SCROLL_CFG = {
    [CONTEXT.FAN]    = {max = 12, min = 1, key = 'button_fan'},
    [CONTEXT.SEAT_L] = {max = 6,  key = 'button_heatedseat1'},
    [CONTEXT.SEAT_R] = {max = 6,  key = 'button_heatedseat2'},
    [CONTEXT.AIR_L]  = {max = 8,  key = 'button_airflow1',  wrap = true},
    [CONTEXT.AIR_R]  = {max = 8,  key = 'button_airflow2',  wrap = true},
}

-- 5-position airflow dial for prop rotation (4 and 5 are closer together)
--            2
--  1                   3
--            4    5
local airflowDialMap = {[0]=0.0, [1]=0.10, [2]=0.40, [3]=0.62, [4]=0.85}

-- 13-position fan dial for prop rotation (0 = auto, 1-12 = manual)
local fanDialMap = {[0]=0.0, [1]=0.15, [2]=0.218, [3]=0.286, [4]=0.355, [5]=0.423, [6]=0.491, [7]=0.559, [8]=0.627, [9]=0.695, [10]=0.764, [11]=0.832, [12]=0.9}

-- SFX
local sfxID = nil
local currentVolume = 0
local lerpSpeed = 3

-- NEW realism variables
local smoothedFan = 0
local fanRampSpeed = 4

local ignitionFadeTimer = 0
local ignitionFadeDuration = 1.2

local compressorTimer = 0
local compressorDelay = 0.7

-- Camera check
local function isInside()
    local camPos = obj:getCameraPosition()
    local vehPos = obj:getPosition()
    local velocity = obj:getVelocity()

    if not camPos or not vehPos then return false end

    local adjustedCamPos = camPos + (velocity * 0.04)
    return adjustedCamPos:distance(vehPos) < 2.0
end

-- Auto fan logic: fan speed based on gap between set temp and ambient
local function getAmbientTemp()
    if obj.getEnvTemperature then
        local tempK = obj:getEnvTemperature()
        if tempK and tempK > 0 then return tempK - 273.15 end
    end
    return 20
end

local lastAutoFanLog = 0

local function calculateAutoFan(values)
    local tL = values.tempLeft or 20
    local tR = values.tempRight or 20
    local setTemp = (tL + tR) * 0.5
    local ambientTemp = getAmbientTemp()
    local delta = math.abs(setTemp - ambientTemp)

    -- Realistic Climatronic curve:
    -- <2°C delta: fan 1 (whisper, maintaining)
    -- 2-5°C: fan 2-3 (gentle adjustment)
    -- 5-10°C: fan 3-5 (moderate conditioning)
    -- 10-15°C: fan 5-7 (strong conditioning)
    -- 15-20°C: fan 7-9 (aggressive, e.g. hot summer day)
    -- >20°C: fan 10 (max auto, demister reserved for 12)
    local targetFan
    if delta < 2 then
        targetFan = 1
    elseif delta < 5 then
        targetFan = 1 + (delta - 2) * 0.67
    elseif delta < 10 then
        targetFan = 3 + (delta - 5) * 0.4
    elseif delta < 15 then
        targetFan = 5 + (delta - 10) * 0.4
    elseif delta < 20 then
        targetFan = 7 + (delta - 15) * 0.4
    else
        targetFan = 10
    end

    local result = math.floor(math.max(1, math.min(10, targetFan)))

    -- Debug log (once per second)
    local now = os.clock()
    if now - lastAutoFanLog > 1 then
        log('I', 'hvac', string.format('AutoFan: ambient=%.1fC set=%.1fC delta=%.1f -> fan %d', ambientTemp, setTemp, delta, result))
        lastAutoFanLog = now
    end

    return result
end

local function changeValue(side, amount)
    local values = electrics.values
    local ctx = values.hvac_context or 0

    activeTimers["hvac_context"] = 5

    if side == "left" then
        if ctx == CONTEXT.SEAT_L then
            values.button_heatedseat1 = math.max(0, math.min(6,(values.button_heatedseat1 or 0)+amount))
            dialChangedButtons["button_heatedseat1"] = true
        elseif ctx == CONTEXT.AIR_L then
            local step = (amount > 0) and 1 or 7
            values.button_airflow1 = ((values.button_airflow1 or 0) + step) % 8
            dialChangedButtons["button_airflow1"] = true
            if values.fanDial ~= nil and values.fanDial == 0 then values.fanDial = values.button_fan or 1 end
        elseif ctx == CONTEXT.FAN then
            if (values.button_econ or 0) == 2 then values.button_econ = 0; savedEconFan = nil end
            values.button_fan = math.max(1, math.min(12,(values.button_fan or 0)+amount))
            dialChangedButtons["button_fan"] = true
            values.fanDial = values.button_fan
        else
            values.tempLeft = math.max(16, math.min(28,(values.tempLeft or 20)+(amount*0.5)))
        end
    end

    if side == "right" then
        if ctx == CONTEXT.SEAT_R then
            values.button_heatedseat2 = math.max(0, math.min(6,(values.button_heatedseat2 or 0)+amount))
            dialChangedButtons["button_heatedseat2"] = true
        elseif ctx == CONTEXT.AIR_R then
            local step = (amount > 0) and 1 or 7
            values.button_airflow2 = ((values.button_airflow2 or 0) + step) % 8
            dialChangedButtons["button_airflow2"] = true
            if values.fanDial ~= nil and values.fanDial == 0 then values.fanDial = values.button_fan or 1 end
        elseif ctx == CONTEXT.FAN then
            if (values.button_econ or 0) == 2 then values.button_econ = 0; savedEconFan = nil end
            values.button_fan = math.max(1, math.min(12,(values.button_fan or 0)+amount))
            dialChangedButtons["button_fan"] = true
            values.fanDial = values.button_fan
        else
            values.tempRight = math.max(16, math.min(28,(values.tempRight or 20)+(amount*0.5)))
        end
    end
end

local function triggerPulse(name)
    local values = electrics.values
    local ctx = pulseMapping[name]
    if not ctx then return end

    -- Toggle: if the same HVAC button is pressed while its context is already active, dismiss
    local toggleable = {
        button_fan = true, button_heatedseat1 = true, button_heatedseat2 = true,
        button_airflow1 = true, button_airflow2 = true,
    }
    if toggleable[name] and (values.hvac_context or 0) == ctx then
        values.hvac_context = CONTEXT.NONE
        activeTimers["hvac_context"] = nil
        return
    end

    -- Auto buttons: toggle silently without showing the fan overlay
    if name == "button_auto1" or name == "button_auto2" then
        if (values.button_econ or 0) == 2 then values.button_econ = 0; savedEconFan = nil end
        if values.fanDial ~= nil and values.fanDial == 0 and (values.button_airflow1 or 0) == 0 then
            -- Currently in full auto → switch to manual
            values.button_fan = (lastManualFan > 0) and lastManualFan or 2
            values.fanDial = values.button_fan
        else
            -- Switch to full auto: fan + airflow
            local currentFan = values.button_fan or 0
            if currentFan ~= 12 and currentFan ~= 0 then
                lastManualFan = currentFan
            end
            values.fanDial = 0
            values.button_airflow1 = 0
            values.button_airflow2 = 0
            if values.airflowDial then values.airflowDial = 0 end
        end
        dialChangedButtons["button_fan"] = true
        dialChangedButtons["button_airflow1"] = true
        dialChangedButtons["button_airflow2"] = true
        return
    end

    values.hvac_context = ctx
    activeTimers["hvac_context"] = 5

    local currentFan = values.button_fan or 0
    local autoFan = calculateAutoFan(values)

    if name == "button_frontdemister" then
        if values.button_frontdemister == 1 then
            if currentFan ~= autoFan and currentFan ~= 12 and currentFan ~= 0 then
                lastManualFan = currentFan
            end
            values.button_fan = 12
            values.fanDial = 12
        else
            values.button_fan = (values.button_auto1 == 1) and 5 or lastManualFan
            values.fanDial = values.button_fan
        end
    end
end

-- Econ: 0 = off, 1 = econ (AC compressor off), 2 = fully off (fan forced to 0)
local savedEconFan = nil

local function toggleEcon()
    local values = electrics.values
    if not values or (values.ignitionLevel or 0) <= 1 then return end
    local prev = values.button_econ or 0
    local next = (prev + 1) % 3

    if next == 2 then
        savedEconFan = values.button_fan or 0
    elseif prev == 2 and next == 0 and savedEconFan then
        values.button_fan = savedEconFan
        values.fanDial = savedEconFan
        dialChangedButtons["button_fan"] = true
        savedEconFan = nil
    end

    values.button_econ = next
    local labels = {[0] = 'OFF', [1] = 'ECON', [2] = 'FULLY OFF'}
    log('I', 'hvac', 'Econ mode: '..next..' ['..labels[next]..']')
end

------------------------------------------------
-- DIRECT CONTROLS (context-free, for trigger knobs)
------------------------------------------------

-- 8-level fan/airflow (old electrics values)
local function fanspeedHigher()
    local values = electrics.values
    if not values or (values.ignitionLevel or 0) <= 1 then return end
    if (values.button_econ or 0) == 2 then values.button_econ = 0; savedEconFan = nil end
    values.button_fan = math.min(12, (values.button_fan or 0) + 1)
    dialChangedButtons["button_fan"] = true
    log('I', 'hvac', 'Fan speed: '..values.button_fan..'/12 (norm: '..string.format('%.3f', values.button_fan / 12)..')')
end

local function fanspeedLower()
    local values = electrics.values
    if not values or (values.ignitionLevel or 0) <= 1 then return end
    if (values.button_econ or 0) == 2 then values.button_econ = 0; savedEconFan = nil end
    values.button_fan = math.max(1, (values.button_fan or 0) - 1)
    dialChangedButtons["button_fan"] = true
    log('I', 'hvac', 'Fan speed: '..values.button_fan..'/12 (norm: '..string.format('%.3f', values.button_fan / 12)..')')
end

local function airflowHigher()
    local values = electrics.values
    if not values or (values.ignitionLevel or 0) <= 1 then return end
    values.button_airflow1 = ((values.button_airflow1 or 0) + 1) % 8
    values.button_airflow2 = ((values.button_airflow2 or 0) + 1) % 8
    dialChangedButtons["button_airflow1"] = true
    dialChangedButtons["button_airflow2"] = true
    if values.fanDial ~= nil and values.fanDial == 0 then values.fanDial = values.button_fan or 1 end
    log('I', 'hvac', 'Airflow: '..values.button_airflow1..'/7 (norm: '..string.format('%.3f', values.button_airflow1 / 7)..')')
end

local function airflowLower()
    local values = electrics.values
    if not values or (values.ignitionLevel or 0) <= 1 then return end
    values.button_airflow1 = ((values.button_airflow1 or 0) + 7) % 8
    values.button_airflow2 = ((values.button_airflow2 or 0) + 7) % 8
    dialChangedButtons["button_airflow1"] = true
    dialChangedButtons["button_airflow2"] = true
    if values.fanDial ~= nil and values.fanDial == 0 then values.fanDial = values.button_fan or 1 end
    log('I', 'hvac', 'Airflow: '..values.button_airflow1..'/7 (norm: '..string.format('%.3f', values.button_airflow1 / 7)..')')
end

-- 5-position airflow dial (prop knob)
local function directAirflowHigher()
    local values = electrics.values
    if not values or (values.ignitionLevel or 0) <= 1 then return end
    values.airflowDial = ((values.airflowDial or 0) + 1) % 5
    if values.fanDial ~= nil and values.fanDial == 0 then values.fanDial = values.button_fan or 1 end
    log('I', 'hvac', 'Airflow dial: '..values.airflowDial..'/4 (norm: '..string.format('%.3f', airflowDialMap[values.airflowDial])..')')
end

local function directAirflowLower()
    local values = electrics.values
    if not values or (values.ignitionLevel or 0) <= 1 then return end
    values.airflowDial = ((values.airflowDial or 0) + 4) % 5
    if values.fanDial ~= nil and values.fanDial == 0 then values.fanDial = values.button_fan or 1 end
    log('I', 'hvac', 'Airflow dial: '..values.airflowDial..'/4 (norm: '..string.format('%.3f', airflowDialMap[values.airflowDial])..')')
end

-- 13-position fan dial (prop knob, 0=auto, 1-12=manual)
local function directFanHigher()
    local values = electrics.values
    if not values or (values.ignitionLevel or 0) <= 1 then return end
    if (values.button_econ or 0) == 2 then values.button_econ = 0; savedEconFan = nil end
    values.fanDial = math.min(12, (values.fanDial or 0) + 1)
    if values.fanDial > 0 then
        values.button_fan = values.fanDial
    end
    dialChangedButtons["button_fan"] = true
    local mode = values.fanDial == 0 and ' [AUTO]' or ' [MANUAL '..values.fanDial..']'
    log('I', 'hvac', 'Fan dial: '..values.fanDial..'/12 (norm: '..string.format('%.3f', fanDialMap[values.fanDial])..')'..mode)
end

local function directFanLower()
    local values = electrics.values
    if not values or (values.ignitionLevel or 0) <= 1 then return end
    if (values.button_econ or 0) == 2 then values.button_econ = 0; savedEconFan = nil end
    values.fanDial = math.max(0, (values.fanDial or 0) - 1)
    if values.fanDial > 0 then
        values.button_fan = values.fanDial
    end
    dialChangedButtons["button_fan"] = true
    local mode = values.fanDial == 0 and ' [AUTO]' or ' [MANUAL '..values.fanDial..']'
    log('I', 'hvac', 'Fan dial: '..values.fanDial..'/12 (norm: '..string.format('%.3f', fanDialMap[values.fanDial])..')'..mode)
end

-- Direct temperature (context-free)
local function directTempLeftHigher()
    local values = electrics.values
    if not values or (values.ignitionLevel or 0) <= 1 then return end
    values.tempLeft = math.min(28, (values.tempLeft or 20) + 0.5)
    log('I', 'hvac', 'Temp left: '..values.tempLeft..' C (norm: '..string.format('%.3f', (values.tempLeft - 16) / 12)..')')
end

local function directTempLeftLower()
    local values = electrics.values
    if not values or (values.ignitionLevel or 0) <= 1 then return end
    values.tempLeft = math.max(16, (values.tempLeft or 20) - 0.5)
    log('I', 'hvac', 'Temp left: '..values.tempLeft..' C (norm: '..string.format('%.3f', (values.tempLeft - 16) / 12)..')')
end

local function directTempRightHigher()
    local values = electrics.values
    if not values or (values.ignitionLevel or 0) <= 1 then return end
    values.tempRight = math.min(28, (values.tempRight or 20) + 0.5)
    log('I', 'hvac', 'Temp right: '..values.tempRight..' C (norm: '..string.format('%.3f', (values.tempRight - 16) / 12)..')')
end

local function directTempRightLower()
    local values = electrics.values
    if not values or (values.ignitionLevel or 0) <= 1 then return end
    values.tempRight = math.max(16, (values.tempRight or 20) - 0.5)
    log('I', 'hvac', 'Temp right: '..values.tempRight..' C (norm: '..string.format('%.3f', (values.tempRight - 16) / 12)..')')
end

------------------------------------------------

local function updateGFX(dt)

    local values = electrics.values
    if not values then return end

    local ignition = values.ignitionLevel or 0

    ------------------------------------------------
    -- IGNITION STATE SAVE / RESTORE
    ------------------------------------------------
    if ignition <= 1 and lastIgnition > 1 then

        savedHVAC = {
			fan = values.button_fan or 0,
			airL = values.button_airflow1 or 0,
			airR = values.button_airflow2 or 0,
			auto1 = values.button_auto1 or 0,
			auto2 = values.button_auto2 or 0,
			tempL = values.tempLeft or 20,
			tempR = values.tempRight or 20,
            parkingsensors = values.button_parkingsensors or 0,
            blis = values.button_blis or 0,
            econ = values.button_econ or 2
		}

        values.button_fan = 0
        values.button_heatedseat1 = 0
        values.button_heatedseat2 = 0
        values.button_airflow1 = 0
        values.button_airflow2 = 0
        values.button_frontdemister = 0
        values.button_reardemister = 0
        values.button_recirculation = 0
        values.button_econ = 2
        values.button_onoff = 0
        values.button_auto1 = 0
        values.button_auto2 = 0
        values.button_parkingsensors = 0
        values.button_blis = 0
        values.fanDial = nil

    elseif ignition > 1 and lastIgnition <= 1 then

		values.button_fan = savedHVAC.fan or 0
		values.button_airflow1 = savedHVAC.airL or 0
		values.button_airflow2 = savedHVAC.airR or 0
		values.button_auto1 = savedHVAC.auto1 or 0
		values.button_auto2 = savedHVAC.auto2 or 0
		values.tempLeft = savedHVAC.tempL or 20
		values.tempRight = savedHVAC.tempR or 20
        values.button_parkingsensors = savedHVAC.parkingsensors or 0
        values.button_blis = savedHVAC.blis or 0
        values.button_econ = savedHVAC.econ or 2
        values.fanDial = 0
        -- Suppress overlay: mark restored values so the detection loop treats them
        -- as internal changes, not physical button presses
        dialChangedButtons["button_fan"] = true
        dialChangedButtons["button_airflow1"] = true
        dialChangedButtons["button_airflow2"] = true
    end

    lastIgnition = ignition

    ------------------------------------------------
    -- HVAC logic
    ------------------------------------------------
    local autoFan = calculateAutoFan(values)

    local currentMenu = values.mmiMenu
    if prevMMIMenu ~= nil and currentMenu ~= prevMMIMenu then
        values.hvac_context = CONTEXT.NONE
        activeTimers["hvac_context"] = nil
        values.mmi_activeScreen = currentMenu  -- prevent one-frame flash
    end
    prevMMIMenu = currentMenu

    -- Process MMI corner button requests (mmi_hvac_request: >0 = open, -1 = close)
    local req = values.mmi_hvac_request or 0
    if req > 0 then
        values.hvac_context = req
        activeTimers["hvac_context"] = 5
        values.mmi_hvac_request = 0
    elseif req == -1 then
        values.hvac_context = CONTEXT.NONE
        activeTimers["hvac_context"] = nil
        values.mmi_hvac_request = 0
        values.mmi_activeScreen = values.mmiMenu or 0
    end

    -- Detect hvac_context transitions → save/setup or restore mmiscroll/mmimax
    local currentCtx = values.hvac_context or 0
    local cfg = HVAC_SCROLL_CFG[currentCtx]

    if currentCtx > 0 and prevSyncCtx == 0 and cfg then
        -- Overlay just opened → save scroll state, center at 400 with large range
        savedMmiScroll = values.mmiscroll
        savedMmiMax    = values.mmimax
        values.mmimax    = 800
        values.mmiscroll = 400
        lastMmiScroll    = 400
    elseif currentCtx == 0 and prevSyncCtx > 0 then
        -- Overlay closed → restore scroll state
        if savedMmiScroll then
            values.mmiscroll = savedMmiScroll
            values.mmimax    = savedMmiMax
            savedMmiScroll = nil
            savedMmiMax    = nil
        end
    end

    -- Delta-only scroll sync: detect direction, apply to HVAC value
    if currentCtx > 0 and cfg then
        local scroll = values.mmiscroll or lastMmiScroll
        if scroll ~= lastMmiScroll then
            local delta = scroll - lastMmiScroll
            local val = values[cfg.key] or 0
            if cfg.wrap then
                val = (val + delta) % cfg.max
            else
                val = math.max(cfg.min or 0, math.min(cfg.max, val + delta))
            end
            values[cfg.key] = val
            dialChangedButtons[cfg.key] = true
            if cfg.key == 'button_fan' then
                values.fanDial = val
            elseif (cfg.key == 'button_airflow1' or cfg.key == 'button_airflow2') and values.fanDial ~= nil and values.fanDial == 0 then
                values.fanDial = values.button_fan or 1
            end
            lastMmiScroll = scroll
            activeTimers["hvac_context"] = 5
        end
    end

    prevSyncCtx = currentCtx

    -- Fan dial auto mode: position 0 continuously tracks the calculated auto speed
    -- Runs before the detection loop so the change is flagged and won't trigger the fan overlay
    -- Skipped when econ fully off (mode 2)
    if values.fanDial ~= nil and values.fanDial == 0 and ignition > 1 and (values.button_econ or 0) ~= 2 then
        if values.button_fan ~= autoFan then
            values.button_fan = autoFan
            dialChangedButtons["button_fan"] = true
        end
    end

    -- Econ fully off: force fan to 0
    if (values.button_econ or 0) == 2 then
        if values.button_fan ~= 0 then
            values.button_fan = 0
            dialChangedButtons["button_fan"] = true
        end
    end

    for btn,_ in pairs(pulseMapping) do
        local val = values[btn] or 0

        if not statusButtons[btn] and prevValues[btn] ~= nil and val ~= prevValues[btn] then
            if dialChangedButtons[btn] then
                -- Value changed by MMI sync, direct control, or auto-tracking — no overlay
            else
                triggerPulse(btn)
            end
        end

        prevValues[btn] = val
    end
    dialChangedButtons = {}

    local f = values.button_fan or 0
    local isAuto = (values.fanDial ~= nil and values.fanDial == 0) and 1 or 0

    values.button_auto1 = isAuto
    values.button_auto2 = isAuto
    values.button_frontdemister = (f == 12) and 1 or 0

    if activeTimers["hvac_context"] then
        activeTimers["hvac_context"] = activeTimers["hvac_context"] - dt
        if activeTimers["hvac_context"] <= 0 then
            values.hvac_context = CONTEXT.NONE
            activeTimers["hvac_context"] = nil
            values.mmi_activeScreen = values.mmiMenu or 0
        end
    end

    ------------------------------------------------
    -- NORMALISED VALUES FOR PROPS (0-1)
    ------------------------------------------------
    values.tempLeftNorm    = ((values.tempLeft  or 20) - 16) / 12
    values.tempRightNorm   = ((values.tempRight or 20) - 16) / 12
    values.fanNorm         = (values.button_fan or 0) / 12
    values.airflowNorm     = (values.button_airflow1 or 0) / 7
    values.airflowDialNorm = airflowDialMap[values.airflowDial or 0] or 0
    values.fanDialNorm     = fanDialMap[values.fanDial or 0] or 0

    ------------------------------------------------
    -- REALISTIC FAN + AC SOUND
    ------------------------------------------------

    local fanTarget = values.button_fan or 0

    smoothedFan = smoothedFan + (fanTarget - smoothedFan) * math.min(dt * fanRampSpeed,1)

    if ignition <= 1 then
        ignitionFadeTimer = math.min(ignitionFadeTimer + dt, ignitionFadeDuration)
    else
        ignitionFadeTimer = 0
    end

    local fadeFactor = 1 - (ignitionFadeTimer / ignitionFadeDuration)
    fadeFactor = math.max(fadeFactor,0)

    if ignition > 1 then
        compressorTimer = math.min(compressorTimer + dt, compressorDelay)
    else
        compressorTimer = 0
    end

    local compressorFactor = compressorTimer / compressorDelay

    local finalTarget = (isInside()) and smoothedFan * fadeFactor * compressorFactor or 0

    currentVolume = currentVolume + (finalTarget - currentVolume) * math.min(dt * lerpSpeed,1)

    if sfxID then
        obj:setVolumePitch(sfxID, currentVolume * 0.2, 1)

        if currentVolume > 0.001 then
            obj:playSFX(sfxID)
        else
            obj:stopSFX(sfxID)
        end
    end
end

local function init()
    lastIgnition = electrics.values and electrics.values.ignitionLevel or 0
    if electrics.values then
        electrics.values.button_econ = 2
        if lastIgnition > 1 then
            electrics.values.fanDial = 0
        end
    end
    sfxID = obj:createSFXSource("/art/sound/audi6/ac/acOn.ogg","Audio2D","acLoop",0)
    obj:setVolumePitch(sfxID,0,1)
end

local function reset()
    if electrics.values then
        electrics.values.button_fan = 0
        electrics.values.button_econ = 2
    end

    if sfxID then
        obj:stopSFX(sfxID)
        obj:setVolumePitch(sfxID,0,1)
    end

    currentVolume = 0
    prevSyncCtx = 0
    lastMmiScroll = 0
    savedMmiScroll = nil
    savedMmiMax = nil
end

-- Original exports
M.onInit = init
M.onReset = reset
M.updateGFX = updateGFX
M.changeValue = changeValue
M.triggerPulse = triggerPulse
M.onTrigger = function(event)
    if event and event.triggerName then
        triggerPulse(event.triggerName)
    end
end

-- Direct control exports (context-free)
M.fanspeedHigher = fanspeedHigher
M.fanspeedLower = fanspeedLower
M.airflowHigher = airflowHigher
M.airflowLower = airflowLower
M.directAirflowHigher = directAirflowHigher
M.directAirflowLower = directAirflowLower
M.directFanHigher = directFanHigher
M.directFanLower = directFanLower
M.directTempLeftHigher = directTempLeftHigher
M.directTempLeftLower = directTempLeftLower
M.directTempRightHigher = directTempRightHigher
M.directTempRightLower = directTempRightLower
M.toggleEcon = toggleEcon

return M