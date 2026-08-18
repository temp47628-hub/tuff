local M = {}

-- Couplers that count as "a door is open" for the cabin courtesy lights.
local allDoors = {
  "door_FL_coupler_notAttached",
  "door_FR_coupler_notAttached",
  "door_RL_coupler_notAttached",
  "door_RR_coupler_notAttached",
  "trunkCoupler_notAttached",
}

-- Each dome light and the couplers that trigger its courtesy behaviour.
-- Cabin lights respond to any door; the trunk light only to the trunk.
local lights = {
  {light = "domelight_FL",    triggers = allDoors},
  {light = "domelight_FR",    triggers = allDoors},
  {light = "domelight_RL",    triggers = allDoors},
  {light = "domelight_RR",    triggers = allDoors},
  {light = "domelight_R",     triggers = allDoors},
  {light = "domelight_trunk", triggers = {"trunkCoupler_notAttached"}},
}

-- ---- tunable timing, in seconds --------------------------------
local holdTime    = 8.0    -- how long lights stay fully on after the last door shuts (car off)
local fadeOutTime = 2.5    -- smooth dim-to-off after the hold ends
local fadeInTime  = 0.12   -- near-instant turn-on when a door opens
local ignFadeTime = 1.5    -- quicker fade once the ignition is switched on
-- ----------------------------------------------------------------

-- per-light runtime state
local st = {}

local function anyOpen(triggers)
  for _, c in ipairs(triggers) do
    if (electrics.values[c] or 0) == 1 then return true end
  end
  return false
end

local function onInit()
  for i, L in ipairs(lights) do
    st[i] = {bright = 0, hold = 0, manual = nil, prevOpen = false, lastOut = 0}
    electrics.values[L.light] = 0
  end
end

local function updateGFX(dt)
  -- ignitionLevel: 0 = off, 1 = accessory, 2 = on/run, 3 = cranking
  local ignOn = (electrics.values["ignitionLevel"] or 0) >= 2

  for i, L in ipairs(lights) do
    local s   = st[i]
    local cur = electrics.values[L.light] or 0

    -- Manual toggle detection: if the value changed to something we didn't
    -- write, a keybind/button flipped it. Latch that as a manual override so
    -- the courtesy logic below won't stomp it. (Works with the car fully off.)
    if math.abs(cur - s.lastOut) > 0.01 then
      s.manual = (cur >= 0.5) and 1 or 0
    end

    local open = anyOpen(L.triggers)

    -- Opening a door clears a manual "off" so courtesy can still light up,
    -- but a manual "on" stays latched until you toggle it back off.
    if open and not s.prevOpen and s.manual == 0 then
      s.manual = nil
    end
    s.prevOpen = open

    -- ---- courtesy engine (drives s.bright) ----
    local target, fade = 0, fadeOutTime
    if open then
      target = 1
      s.hold = holdTime
    elseif ignOn then
      target = 0
      fade   = ignFadeTime
      s.hold = 0
    elseif s.hold > 0 then
      s.hold = s.hold - dt
      target = 1
    end

    if s.bright < target then
      s.bright = math.min(target, s.bright + dt / fadeInTime)
    elseif s.bright > target then
      s.bright = math.max(target, s.bright - dt / fade)
    end

    -- ---- combine manual override with courtesy ----
    local out
    if s.manual == 1 then
      out = 1              -- manually forced on (stays on until toggled off)
    elseif s.manual == 0 then
      out = 0              -- manually forced off
    else
      out = s.bright       -- automatic courtesy control
    end

    electrics.values[L.light] = out
    s.lastOut = out
  end
end

M.onInit    = onInit
M.onReset   = onInit
M.updateGFX = updateGFX

return M