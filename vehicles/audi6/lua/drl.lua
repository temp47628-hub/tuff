local M = {}

local STEERING_THRESHOLD = 122

-- Brightness tiers. Ordered so math.max resolves overlaps correctly:
-- DRL (signal only) < cornering (short-range illumination) < high beam (full).
local DRL_BRIGHTNESS      = 0.3
local CORNER_BRIGHTNESS   = 0.6
local HIGHBEAM_BRIGHTNESS = 1.0

-- BeamNG electrics can be 0/1 numbers or true/false booleans depending on the
-- vehicle's light controller. Lua does not coerce, so compare via this helper.
local function isOn(v)
    return v ~= nil and v ~= false and v ~= 0
end

local function onInit()
    local e = electrics.values

    e.audi6_drl = 0
    e.audi6_drl_L = 0
    e.audi6_drl_R = 0
    e.audi6_drl_strip = 0
    e.audi6_drl_alt_L = 0
    e.audi6_drl_alt_R = 0
end

local function updateGFX(dt)
    local e = electrics.values

    local ignition = isOn(e.ignitionLevel2)
    local low      = isOn(e.lowbeam)
    local high     = isOn(e.highbeam)
    local drlOn    = isOn(e.mmi_drlActive)

    -- Cornering state
    local cornerEnabled = isOn(e.ignitionLevel) and isOn(e.adaptiveLightsEnabled)
    local steer = e.steering or 0

    local cornerL = cornerEnabled and steer >  STEERING_THRESHOLD
    local cornerR = cornerEnabled and steer < -STEERING_THRESHOLD

    -- Reset
    e.audi6_drl = 0
    e.audi6_drl_L = 0
    e.audi6_drl_R = 0
    e.audi6_drl_strip = 0
    e.audi6_drl_alt_L = 0
    e.audi6_drl_alt_R = 0

    if ignition then
        -- Cornering: mid tier
        if cornerL then e.audi6_drl_L = CORNER_BRIGHTNESS end
        if cornerR then e.audi6_drl_R = CORNER_BRIGHTNESS end

        -- High beam: top tier, wins over cornering
        if high then
            e.audi6_drl = HIGHBEAM_BRIGHTNESS
            e.audi6_drl_L = math.max(e.audi6_drl_L, HIGHBEAM_BRIGHTNESS)
            e.audi6_drl_R = math.max(e.audi6_drl_R, HIGHBEAM_BRIGHTNESS)
        end
    end

    -- DRLs disabled in MMI — cornering and high beam still work above
    if not drlOn then
        e.audi6_drl_alt_L = math.max(e.audi6_drl, e.audi6_drl_L)
        e.audi6_drl_alt_R = math.max(e.audi6_drl, e.audi6_drl_R)
        return
    end

    -- LED strip stays on whenever the engine is running, regardless of low beams
    if ignition then
        e.audi6_drl_strip = 1
    end

    -- Need ignition for anything below
    if not ignition then
        return
    end

    -- Base DRL brightness only without low beams and without high beams
    if not low and not high then
        e.audi6_drl = DRL_BRIGHTNESS
    end

    -- Combined tier: DRL 0.3 -> cornering 0.6 -> high beam 1.0
    e.audi6_drl_alt_L = math.max(e.audi6_drl, e.audi6_drl_L)
    e.audi6_drl_alt_R = math.max(e.audi6_drl, e.audi6_drl_R)
end

M.onInit = onInit
M.updateGFX = updateGFX

return M