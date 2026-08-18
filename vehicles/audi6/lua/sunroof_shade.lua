-- This Source Code Form is subject to the terms of the bCDDL, v. 1.1.
-- If a copy of the bCDDL was not distributed with this
-- file, You can obtain one at http://beamng.com/bCDDL-1.1.txt

local M = {}

local SHADE_SPEED = 0.5

local function clamp01(x)
  if x < 0 then return 0 end
  if x > 1 then return 1 end
  return x
end

local function moveToward(current, target, amount)
  if current < target then
    current = current + amount
    if current > target then current = target end
  elseif current > target then
    current = current - amount
    if current < target then current = target end
  end

  return current
end

local function onReset()
  electrics.values.movf = 0
  electrics.values.movf_target = 0

  electrics.values.movr = 0
  electrics.values.movr_target = 0
end

local function updateGFX(dt)
  electrics.values.movf = moveToward(
    electrics.values.movf or 0,
    electrics.values.movf_target or 0,
    dt * SHADE_SPEED
  )

  electrics.values.movr = moveToward(
    electrics.values.movr or 0,
    electrics.values.movr_target or 0,
    dt * SHADE_SPEED
  )
end

local function movfRoof(value)
  electrics.values.movf_target = clamp01(value or 0)
end

local function movrRoof(value)
  electrics.values.movr_target = clamp01(value or 0)
end

local function openRoof()
  electrics.values.movf_target = 1
end

local function closeRoof()
  if electrics.values.sunroof_slide == 0 then
    electrics.values.movf_target = 0
  else
    guihooks.message('Close sunroof glass first', 2)
  end
end

local function toggleRoof()
  local current = electrics.values.movf or 0
  local target = electrics.values.movf_target or current

  -- If the shade is mostly open or currently opening, close it.
  -- Otherwise, open it.
  if target > 0.5 or current > 0.5 then
    closeRoof()
  else
    openRoof()
  end
end

M.onInit = onReset
M.onReset = onReset
M.updateGFX = updateGFX

M.movfRoof = movfRoof
M.movrRoof = movrRoof

M.openRoof = openRoof
M.closeRoof = closeRoof
M.toggleRoof = toggleRoof

return M