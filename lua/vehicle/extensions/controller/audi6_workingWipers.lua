-- Code by SineMatic(YT)
-- If you want to use this code, let me know

-- This Source Code Form is subject to the terms of the bCDDL, v. 1.1.
-- If a copy of the bCDDL was not distributed with this
-- file, You can obtain one at http://beamng.com/bCDDL-1.1.txt

local M = {}

-- coefficients of this smoothing function: value = k*(x-t)^4 + n
local stalkSmootherTime = 1 -- t. Default, rewritten by jbeamData
local counter = 0 -- x.
local k -- k.
local n -- n.
local currentStalkPosition
local targetStalkPosition
local pendingStalkUpdate = false
local smootherCoefSet = false
local stalkPositions = {[0] = 0, [1] = 0.33, [2] = 0.66, [3] = 1}

-- signal stalk smoother (independent state)
local counterSignal = 0
local kSignal
local nSignal
local currentSignalStalkPosition = 0
local targetSignalStalkPosition = 0
local pendingSignalStalkUpdate = false
local smootherSignalCoefSet = false

-- service position override (coordinated with mmi.lua)
local serviceBlocking = false
local savedModeForService = 0
local savedSpeedForService = 0

-- constants
local pi = 3.14159
local rearWiperPresent = false
local frontWipersPresent = false
local frontWipersVolume = 1 -- default, rewritten by jbeamData
local rearWiperVolume = 1 -- default, rewritten by jbeamData

-- vars for sound objects
local sfx_wipers
local sfx_rear_wiper
local sfx_wiper_stalk
local sfx_rear_wiper_stalk

-- vars for rear wiper position calculation
electrics.values.wiperValR = 0
local periodR = 0
local modeR = 0
local pendingOffR = false

-- vars for front wipers position calculation
local wiperSpeed = 0
electrics.values.wipers_position = 0
electrics.values.wiperstalk = 0
electrics.values.signalstalk = 0
local period = 0
local mode = 0
local pendingOff = false

local function resetValues()
  electrics.values.wipers_position = 0
  electrics.values.wiperstalk = 0
  period = 0
  mode = 0
  pendingOff = false
end

local function resetSignalStalk()
  electrics.values.signalstalk = 0
  currentSignalStalkPosition = 0
  targetSignalStalkPosition = 0
  pendingSignalStalkUpdate = false
  smootherSignalCoefSet = false
  counterSignal = 0
end

local function resetServiceOverride()
  serviceBlocking = false
  savedModeForService = 0
  savedSpeedForService = 0
end

local function resetValuesR()
  electrics.values.wiperValR = 0
  periodR = 0
  modeR = 0
  pendingOffR = false
end

local function init(jbeamData)
  rearWiperPresent = jbeamData.rearWiperPresent
  frontWipersPresent = jbeamData.frontWipersPresent
  frontWipersVolume = jbeamData.frontWipersVolume or 1
  rearWiperVolume = jbeamData.rearWiperVolume or 1
  resetValues()
  resetValuesR()
  resetSignalStalk()
  resetServiceOverride()
  
  stalkSmootherTime = jbeamData.stalkSmootherTime or 1
end

local function reset()
  resetValues()
  resetValuesR()
  resetSignalStalk()
  resetServiceOverride()
end

-- the mode the driver perceives right now: while a shut-off is pending the
-- wipers are already on their way to 0, so treat them as being off
local function effectiveMode()
  return pendingOff and 0 or mode
end

-- shared by both stalk directions
local function applyMode(modeTemp)
  if modeTemp == 0 then
    pendingOff = true
    period = period % (2*pi)
  else
    mode = modeTemp
    pendingOff = false
    wiperSpeed = 2 + 3 * math.ceil(mode/2)
    if electrics.values.wipers_position == 0 then
      if period > 2*pi then
        period = 0
      end
      sounds.playSoundSkipAI(sfx_wipers, frontWipersVolume)
    end
  end
  guihooks.message("Wiper mode: "..modeTemp)
  sounds.playSoundSkipAI(sfx_wiper_stalk)

  smootherCoefSet = false
  pendingStalkUpdate = true
  targetStalkPosition = stalkPositions[modeTemp]
  currentStalkPosition = electrics.values.wiperstalk
end

-- true when the stalk must not move (service position active)
local function stalkInputBlocked()
  if not frontWipersPresent then return true end
  -- Block stalk input while service position is active (deactivate via MMI first)
  if (electrics.values.mmi_wiperServicePos or 0) == 1 then return true end
  sfx_wiper_stalk = sfx_wiper_stalk or sounds.createSoundscapeSound("indicatorStart")
  sfx_wipers = sfx_wipers or sounds.createSoundscapeSound("frontWipers")
  return false
end

-- stalk up: 0 -> 1 -> 2 -> 3 -> 0
local function toggleMode()
  if stalkInputBlocked() then return end
  applyMode((effectiveMode() + 1) % 4)
end

-- stalk down: 3 -> 2 -> 1 -> 0 (-> 3)
local function toggleModeDown()
  if stalkInputBlocked() then return end
  -- Lua's % is floored, so (0 - 1) % 4 == 3 and the cycle wraps around
  applyMode((effectiveMode() - 1) % 4)
end

local function toggleModeR()
  if not rearWiperPresent then return end
  local modeRtemp = (modeR + 1) % 2
  guihooks.message("Rear wiper mode: "..modeRtemp)
  if modeRtemp == 0 then
    pendingOffR = true
  else
    modeR = 1
    if electrics.values.wiperValR == 0 then
      periodR = 0
    end
    sfx_rear_wiper = sfx_rear_wiper or sounds.createSoundscapeSound("rearWiper")
    sounds.playSoundSkipAI(sfx_rear_wiper, rearWiperVolume)
  end
  sfx_rear_wiper_stalk = sfx_rear_wiper_stalk or sounds.createSoundscapeSound("rearWiperStalk")
  sounds.playSoundSkipAI(sfx_rear_wiper_stalk)
end

local function calculatePosition(mode, period, electricName)
  if mode == 1 and period > 2*pi then
    electrics.values[electricName] = 0
  else
    electrics.values[electricName] = (1 - math.cos(period))/2
  end
end

local function updateStalk(dt)
  if not smootherCoefSet then
    counter = 0
    k = (currentStalkPosition - targetStalkPosition) / stalkSmootherTime ^ 4
    n = targetStalkPosition
    smootherCoefSet = true
  end
  
  counter = counter + dt
  currentStalkPosition = k * (counter - stalkSmootherTime)^4 + n
  
  if counter > stalkSmootherTime then
    pendingStalkUpdate = false
    smootherCoefSet = false
    electrics.values.wiperstalk = targetStalkPosition
  else
    electrics.values.wiperstalk = currentStalkPosition
  end
  
end

local function updateSignalStalk(dt)
  if not smootherSignalCoefSet then
    counterSignal = 0
    kSignal = (currentSignalStalkPosition - targetSignalStalkPosition) / stalkSmootherTime ^ 4
    nSignal = targetSignalStalkPosition
    smootherSignalCoefSet = true
  end

  counterSignal = counterSignal + dt
  currentSignalStalkPosition = kSignal * (counterSignal - stalkSmootherTime)^4 + nSignal

  if counterSignal > stalkSmootherTime then
    pendingSignalStalkUpdate = false
    smootherSignalCoefSet = false
    electrics.values.signalstalk = targetSignalStalkPosition
  else
    electrics.values.signalstalk = currentSignalStalkPosition
  end
end

local function updateGFX(dt)
  -- Service position override: mmi.lua controls wipers_position while service is active or animating back
  local nowServiceBlocking = (electrics.values.mmi_wiperServicePos or 0) == 1
                          or (electrics.values.mmi_wiperServiceBusy or 0) == 1

  if nowServiceBlocking and not serviceBlocking then
    -- Entering service override: save current wiper state
    if mode ~= 0 and not pendingOff then
      savedModeForService = mode
      savedSpeedForService = wiperSpeed
    end
    -- Suppress sweep without resetting position (mmi.lua will animate it)
    mode = 0
    wiperSpeed = 0
    pendingOff = false
    period = 0
  end

  if not nowServiceBlocking and serviceBlocking then
    -- Leaving service override: restore saved wiper mode
    if savedModeForService ~= 0 then
      mode = savedModeForService
      wiperSpeed = savedSpeedForService
      period = 0
      savedModeForService = 0
      savedSpeedForService = 0
      sfx_wipers = sfx_wipers or sounds.createSoundscapeSound("frontWipers")
      sounds.playSoundSkipAI(sfx_wipers, frontWipersVolume)
      -- Smooth the stalk back to the restored mode's position
      smootherCoefSet = false
      pendingStalkUpdate = true
      targetStalkPosition = stalkPositions[mode]
      currentStalkPosition = electrics.values.wiperstalk
    end
  end

  serviceBlocking = nowServiceBlocking

  if mode ~= 0 then
    if pendingOff and period > 2*pi then
      resetValues()
    end
    period = (period + dt*wiperSpeed)
    calculatePosition(mode, period, "wipers_position")
    if mode == 1 then
      if period > 6*pi then
        period = period % (6*pi)
        sounds.playSoundSkipAI(sfx_wipers, frontWipersVolume)
      end
    else 
      if period > 2*pi then
        if pendingOff then
          resetValues()
          goto continue
        end
        period = period % (2*pi)
        sounds.playSoundSkipAI(sfx_wipers, frontWipersVolume)
      end
      ::continue::
    end
  end
  
  if modeR ~= 0 then
    if pendingOffR and periodR > 2*pi then
      resetValuesR()
    end
    periodR = (periodR + dt*5)
    calculatePosition(modeR, periodR, "wiperValR")
    if periodR > 6*pi then
      periodR = periodR % (6*pi)
      sounds.playSoundSkipAI(sfx_rear_wiper, rearWiperVolume)
    end
  end
  
  if pendingStalkUpdate then
    updateStalk(dt)
  end
  
  -- signal stalk: read inputs and trigger smooth transition on change
  -- When hazards are active, hold the stalk at its current position (hazards use a button, not the stalk)
  local newSignalTarget = 0
  local hazardOn = (electrics.values.hazard_enabled or 0) == 1
  if hazardOn then
    newSignalTarget = targetSignalStalkPosition
  else
    if (electrics.values.signal_left_input or 0) == 1 then
      newSignalTarget = -1
    elseif (electrics.values.signal_right_input or 0) == 1 then
      newSignalTarget = 1
    end
  end
  
  if newSignalTarget ~= targetSignalStalkPosition then
    currentSignalStalkPosition = electrics.values.signalstalk
    targetSignalStalkPosition = newSignalTarget
    pendingSignalStalkUpdate = true
    smootherSignalCoefSet = false
  end
  
  if pendingSignalStalkUpdate then
    updateSignalStalk(dt)
  end
end

M.init = init
M.reset = reset
M.toggleMode = toggleMode
M.toggleModeDown = toggleModeDown
M.toggleModeR = toggleModeR
M.updateGFX = updateGFX

return M