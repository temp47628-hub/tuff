local M = {}

-- ── Constants ──────────────────────────────────────────────────────────────
local PUDDLE_TIMEOUT = 10  -- seconds lights stay on after unlock before door is opened

-- ── State ──────────────────────────────────────────────────────────────────
local lastLockState = nil
local timerFL = 0
local timerFR = 0

-- ── Update ─────────────────────────────────────────────────────────────────
local function update(dt)
    local ignition  = electrics.values.ignitionLevel or 0
    local doorFL    = (electrics.values.door_FL_coupler_notAttached or 0) == 1
    local doorFR    = (electrics.values.door_FR_coupler_notAttached or 0) == 1
    local allLocked = (electrics.values.allLocked or 0) == 1

    -- when ignition is off, reset everything
    if ignition == 0 then
        electrics.values.puddlelight_FL = 0
        electrics.values.puddlelight_FR = 0
        timerFL = 0
        timerFR = 0
        lastLockState = allLocked
        return
    end

    -- detect unlock event (locked -> unlocked transition)
    if lastLockState == true and not allLocked then
        timerFL = PUDDLE_TIMEOUT
        timerFR = PUDDLE_TIMEOUT
    end

    -- FL puddle light
    if doorFL then
        -- door open: light on, reset timer
        electrics.values.puddlelight_FL = 1
        timerFL = PUDDLE_TIMEOUT
    elseif timerFL > 0 then
        -- door closed but timer still running (post-unlock or post-close)
        timerFL = timerFL - dt
        electrics.values.puddlelight_FL = 1
    else
        electrics.values.puddlelight_FL = 0
    end

    -- FR puddle light
    if doorFR then
        electrics.values.puddlelight_FR = 1
        timerFR = PUDDLE_TIMEOUT
    elseif timerFR > 0 then
        timerFR = timerFR - dt
        electrics.values.puddlelight_FR = 1
    else
        electrics.values.puddlelight_FR = 0
    end

    lastLockState = allLocked
end

-- ── Lifecycle ──────────────────────────────────────────────────────────────
local function init()
    timerFL = 0
    timerFR = 0
    lastLockState = nil
    electrics.values.puddlelight_FL = 0
    electrics.values.puddlelight_FR = 0
end

M.onInit    = init
M.onReset   = init
M.updateGFX = update

return M