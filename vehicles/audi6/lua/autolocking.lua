local M = {}

-- ── Constants ──────────────────────────────────────────────────────────────
local SPEED_LOCK_KMH      = 15
local RELOCK_DELAY        = 30
local UNLOCK_HOLD_FRAMES  = 3

-- ── State ──────────────────────────────────────────────────────────────────
local hasSpeedLocked      = false
local manualOverride      = false    -- set when player manually unlocks; suppresses auto-lock
local lastIgnition        = 0
local relockTimer         = 0
local relockArmed         = false
local lastAnyDoorOpen     = false
local lastLockState       = nil
local unlockHoldTimer     = 0

local lockSound   = "/art/sound/audi6/lock/lock.ogg"
local unlockSound = "/art/sound/audi6/lock/unlock.ogg"

-- ── Helpers ────────────────────────────────────────────────────────────────
local LOCK_KEYS = {'doorLocked_FL', 'doorLocked_FR', 'doorLocked_RL', 'doorLocked_RR', 'doorLocked_trunk'}

local INCLUDE_FLAGS = {
    doorLocked_FR    = 'lockInclude_FR',
    doorLocked_RL    = 'lockInclude_RL',
    doorLocked_RR    = 'lockInclude_RR',
    doorLocked_trunk = 'lockInclude_trunk',
}

local function applyLock()
    for _, k in ipairs(LOCK_KEYS) do
        local iKey = INCLUDE_FLAGS[k]
        if not iKey or (electrics.values[iKey] or 1) == 1 then
            electrics.values[k] = 1
        end
    end
end

local function applyUnlock()
    for _, k in ipairs(LOCK_KEYS) do
        electrics.values[k] = 0
    end
    unlockHoldTimer = UNLOCK_HOLD_FRAMES
end

local function allLocked()
    for _, k in ipairs(LOCK_KEYS) do
        local iKey = INCLUDE_FLAGS[k]
        local included = not iKey or (electrics.values[iKey] or 1) == 1
        if included and (electrics.values[k] or 0) == 0 then return false end
    end
    return true
end

local function anyDoorOpen()
    return (electrics.values.door_FL_coupler_notAttached   or 0) == 1
        or (electrics.values.door_FR_coupler_notAttached   or 0) == 1
        or (electrics.values.door_RL_coupler_notAttached   or 0) == 1
        or (electrics.values.door_RR_coupler_notAttached   or 0) == 1
        or (electrics.values.trunkCoupler_notAttached      or 0) == 1
end

local function checkLockSound()
    local locked = allLocked()
    if lastLockState ~= nil and locked ~= lastLockState then
        if locked then
            obj:playSFXOnce("door_lock", 0, 20, 1)
            electrics.values['allLocked'] = 1
        else
            obj:playSFXOnce("door_unlock", 0, 20, 1)
            electrics.values['allLocked'] = 0
        end
    end
    lastLockState = locked
end

-- ── Public: called from interaction JSON ───────────────────────────────────
local function lockAll()
    applyLock()
    manualOverride = false   -- player re-locked, auto-lock can resume normally
end

local function unlockAll()
    applyUnlock()
    manualOverride = true    -- player manually unlocked, suppress auto-lock
end

local function toggleLockAll()
    if allLocked() then
        applyUnlock()
        manualOverride = true
    else
        applyLock()
        manualOverride = false
    end
end

-- ── Update ─────────────────────────────────────────────────────────────────
local function update(dt)
    local e        = electrics.values
    local ignition = e.ignitionLevel or 0
    local speedKmh = (e.wheelspeed   or 0) * 3.6
    local autoLock = (e.centralLock  or 0) == 1
    local doorOpen = anyDoorOpen()

    -- ── 1. Ignition-off unlock ─────────────────────────────────────────────
    if ignition < 2 and lastIgnition >= 2 then
        applyUnlock()           -- internal unlock, does NOT set manualOverride
        hasSpeedLocked = false
        manualOverride = false  -- fresh drive cycle clears the override
        relockArmed    = false
        relockTimer    = 0
    end

    -- ── 2. Speed auto-lock ────────────────────────────────────────────────
    if ignition >= 2 and autoLock and not hasSpeedLocked and not manualOverride then
        if speedKmh >= SPEED_LOCK_KMH and not doorOpen then
            applyLock()
            hasSpeedLocked = true
            relockArmed    = false
            relockTimer    = 0
        end
    end

    -- Re-arm only when not manually overridden
    if hasSpeedLocked and not allLocked() and not doorOpen and not manualOverride then
        hasSpeedLocked = false
    end

    -- ── 3. Re-lock timer ──────────────────────────────────────────────────
    if ignition < 2 then
        if unlockHoldTimer == 1 and not allLocked() then
            relockArmed = true
            relockTimer = RELOCK_DELAY
        end

        if relockArmed then
            if doorOpen then
                relockArmed = false
                relockTimer = 0
            else
                relockTimer = relockTimer - dt
                if relockTimer <= 0 then
                    applyLock()
                    relockArmed = false
                end
            end
        end
    else
        relockArmed = false
        relockTimer = 0
    end

    -- ── Bookkeeping ────────────────────────────────────────────────────────
    if unlockHoldTimer > 0 then unlockHoldTimer = unlockHoldTimer - 1 end
    lastIgnition    = ignition
    lastAnyDoorOpen = doorOpen
    checkLockSound()
end

-- ── Lifecycle ──────────────────────────────────────────────────────────────
local function init()
    hasSpeedLocked  = false
    manualOverride  = false
    relockArmed     = false
    relockTimer     = 0
    unlockHoldTimer = 0
    lastIgnition    = 0
    lastAnyDoorOpen = false
    lastLockState   = allLocked()

    obj:createSFXSource(lockSound,   "Audio2D", "door_lock",   -1)
    obj:createSFXSource(unlockSound, "Audio2D", "door_unlock", -1)
end

M.onInit        = init
M.onReset       = init
M.updateGFX     = update
M.lockAll       = lockAll
M.unlockAll     = unlockAll
M.toggleLockAll = toggleLockAll

return M