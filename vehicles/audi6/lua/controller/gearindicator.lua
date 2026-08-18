-- This Source Code Form is subject to the terms of the bCDDL, v. 1.1.
-- If a copy of the bCDDL was not distributed with this
-- file, You can obtain one at http://beamng.com/bCDDL-1.1.txt
local M = {}

local gearA = 0
local isCVT = false

-- Normal (non-CVT) thresholds
local NORMAL_R = 0.07
local NORMAL_N = 0.14
local NORMAL_D = 0.21
local NORMAL_S = 0.33
local NORMAL_M = 0.45

-- CVT thresholds
local CVT_R = 0.2
local CVT_N = 0.4
local CVT_D = 0.6
local CVT_S = 0.8

local function init(jbeamData)
    local gearbox = powertrain.getDevice('gearbox')
    isCVT = gearbox ~= nil and gearbox.type == 'cvtGearbox'

    electrics.values['auto_p'] = 0
    electrics.values['auto_r'] = 0
    electrics.values['auto_n'] = 0
    electrics.values['auto_d'] = 0
    electrics.values['auto_s'] = 0
    electrics.values['auto_m'] = 0
end

local function reset()
    init({})
end

local function updateGFX(dt)
    gearA = electrics.values['gear_A'] or 0

    local tR, tN, tD, tS, tM
    if isCVT then
        tR = CVT_R
        tN = CVT_N
        tD = CVT_D
        tS = CVT_S
        tM = nil  -- CVT has no manual gear
    else
        tR = NORMAL_R
        tN = NORMAL_N
        tD = NORMAL_D
        tS = NORMAL_S
        tM = NORMAL_M
    end

    if electrics.values['ignitionLevel'] > 0 then
        electrics.values['auto_p'] = (gearA < tR) and 1 or 0
        electrics.values['auto_r'] = (gearA >= tR and gearA < tN) and 1 or 0
        electrics.values['auto_n'] = (gearA >= tN and gearA < tD) and 1 or 0
        electrics.values['auto_d'] = (gearA >= tD and gearA < tS) and 1 or 0
        electrics.values['auto_s'] = (tM ~= nil and gearA >= tS and gearA < tM or tM == nil and gearA >= tS) and 1 or 0
        electrics.values['auto_m'] = (tM ~= nil and gearA >= tM) and 1 or 0
    else
        electrics.values['auto_p'] = 0
        electrics.values['auto_r'] = 0
        electrics.values['auto_n'] = 0
        electrics.values['auto_d'] = 0
        electrics.values['auto_s'] = 0
        electrics.values['auto_m'] = 0
    end
end

-- public interface
M.init      = init
M.reset     = reset
M.updateGFX = updateGFX

return M
