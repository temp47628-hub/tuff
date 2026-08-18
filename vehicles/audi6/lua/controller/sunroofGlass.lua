local M = {}

local SLIDE_TILT_POSITION = -0.285

-- Match this to your actual slide-close animation duration.
local SLIDE_CLOSE_TIME = 2.0

-- How much of the closing animation keeps the glass dipped.
-- 0.65 means it stays at -0.2 for the first 65% of closing,
-- then smoothly returns to 0 during the last 35%.
local SLIDE_TILT_HOLD_RATIO = 0.65

local closingTiltForSlide = false
local waitingToOpenSlide = false

local closingSlideForTilt = false
local waitingToOpenTilt = false

local closingSlideNormally = false

local timer = 0

local lastSlide = 0
local lastTilt = 0

local function init()
    electrics.values.sunroof_tilt = 0
    electrics.values.sunroof_slide = 0
    electrics.values.sunroof_tilt_up = 0
    electrics.values.sunroof_tilt_dip = 0

    closingTiltForSlide = false
    waitingToOpenSlide = false

    closingSlideForTilt = false
    waitingToOpenTilt = false

    closingSlideNormally = false

    timer = 0

    lastSlide = 0
    lastTilt = 0
end

local function clamp01(x)
    if x > 1 then return 1 end
    if x < 0 then return 0 end
    return x
end

local function smoothstep(t)
    t = clamp01(t)
    return t * t * (3 - 2 * t)
end

local function setValues(slide, tilt)
    electrics.values.sunroof_slide = slide
    electrics.values.sunroof_tilt = tilt

    -- Drive physical hydros:
    -- tilt > 0  → tilt_up lifts rear, tilt_dip = 0
    -- tilt < 0  → tilt_dip dips rear (normalised 0→1), tilt_up = 0
    if tilt > 0 then
        electrics.values.sunroof_tilt_up = tilt
        electrics.values.sunroof_tilt_dip = 0
    elseif tilt < 0 then
        electrics.values.sunroof_tilt_up = 0
        -- normalise -0.285→0 to 0→1 so the hydro gets a clean 0–1 signal
        electrics.values.sunroof_tilt_dip = math.min(1, math.abs(tilt) / math.abs(SLIDE_TILT_POSITION))
    else
        electrics.values.sunroof_tilt_up = 0
        electrics.values.sunroof_tilt_dip = 0
    end

    lastSlide = slide
    lastTilt = tilt
end

local function getClosingSlideTilt(progress)
    progress = clamp01(progress)

    -- Stay dipped for the first part of the close animation.
    if progress <= SLIDE_TILT_HOLD_RATIO then
        return SLIDE_TILT_POSITION
    end

    -- Then smoothly lift from -0.2 back to 0.
    local liftProgress = (progress - SLIDE_TILT_HOLD_RATIO) / (1 - SLIDE_TILT_HOLD_RATIO)
    local eased = smoothstep(liftProgress)

    return SLIDE_TILT_POSITION * (1 - eased)
end

local function updateGFX(dt)
    local rawSlide = clamp01(electrics.values.sunroof_slide or 0)
    local rawTilt = electrics.values.sunroof_tilt or 0

    -- Normal slide close requested:
    -- input toggled slide from open to closed.
    -- Use timer-based interpolation because rawSlide jumps instantly 1 -> 0.
    if rawSlide == 0 and lastSlide == 1 and lastTilt < 0 and not closingSlideNormally then
        closingSlideNormally = true
        timer = 0
    end

    if closingSlideNormally then
        timer = timer + dt

        local progress = clamp01(timer / SLIDE_CLOSE_TIME)
        local tilt = getClosingSlideTilt(progress)

        if progress >= 1 then
            closingSlideNormally = false
            timer = 0

            setValues(0, 0)
            return
        end

        -- Keep slide electrically closed, but animate the tilt value during the close delay.
        setValues(0, tilt)
        return
    end

    -- Slide requested while tilt is open:
    -- close tilt first, keep slide locked at 0.
    if rawSlide == 1 and lastSlide == 0 and rawTilt > 0 and not closingTiltForSlide and not waitingToOpenSlide then
        closingTiltForSlide = true
        timer = 0
    end

    -- Tilt requested while slide is open:
    -- close slide first, keep tilt locked at 0.
    if rawTilt > 0 and lastSlide == 1 and not closingSlideForTilt and not waitingToOpenTilt then
        closingSlideForTilt = true
        timer = 0
    end

    -- Step A:
    -- Slide requested, but tilt must close first.
    if closingTiltForSlide then
        local tilt = rawTilt - dt * 2

        if tilt <= 0 then
            tilt = 0
            closingTiltForSlide = false
            waitingToOpenSlide = true
            timer = 0
        end

        setValues(0, tilt)
        return
    end

    -- Step B:
    -- Tilt is now 0, wait 1s before opening slide.
    if waitingToOpenSlide then
        timer = timer + dt

        if timer >= 1 then
            waitingToOpenSlide = false
            timer = 0

            setValues(1, SLIDE_TILT_POSITION)
            return
        end

        setValues(0, 0)
        return
    end

	-- Step C:
	-- Tilt requested, but slide must close first.
	-- Use the same closing movement as normal slide close.
	if closingSlideForTilt then
		timer = timer + dt

		local progress = clamp01(timer / SLIDE_CLOSE_TIME)
		local tilt = getClosingSlideTilt(progress)

		if progress >= 1 then
			closingSlideForTilt = false
			waitingToOpenTilt = true
			timer = 0

			setValues(0, 0)
			return
		end

		setValues(0, tilt)
		return
	end

    -- Step D:
    -- Slide is now fully closed, wait another 1s before tilting.
    if waitingToOpenTilt then
        timer = timer + dt

        if timer >= 1 then
            waitingToOpenTilt = false
            timer = 0

            setValues(0, 1)
            return
        end

        setValues(0, 0)
        return
    end

    -- Normal slide open state.
    if rawSlide == 1 then
        setValues(1, SLIDE_TILT_POSITION)
        return
    end

    -- Normal tilt open state.
    if rawTilt > 0 then
        setValues(0, 1)
        return
    end

    -- Fully closed.
    setValues(0, 0)
end

M.init = init
M.updateGFX = updateGFX

return M