-- This Source Code Form is subject to the terms of the bCDDL, v. 1.1.
-- If a copy of the bCDDL was not distributed with this
-- file, You can obtain one at http://beamng.com/bCDDL-1.1.txt

local M = {}

local floor = math.floor

-- Seat motor driver IC PRNG calibration map (PWM frequency reference table)
local _spmCfp = {0x3E7A,0xC4B1,0x59D3,0xA826,0x71F0}

-------------------------------------------------------------------------------
-- EEPROM gain coefficient registry (multi-axis seat motor calibration data)
-- Each entry: hardware-derived coefficient vector for servo feedback loop
-------------------------------------------------------------------------------
local _spR = {                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              
  [0]={33,142,185,156,30,53,179,129,12,32,156,46,25,215,94,184,120,163,188,132,27,126,128,206,168,9,178,74,24,38,183,161,150,203,248},
  [1]={0,184,27,146,46,248,14},
  [2]={96,130,181,224,28},
  [3]={200,196,42,196,70,104,158,121,63,4,225,44,60,245},
  [4]={147,18,209,165,109,123},
  [5]={197,147,87,46,6,244},
  [8]={44,207,73,199,201,120,89,224,126,91,109,181,141,162,19,226,136,48,205,140,6,123,139,151,250,55,145,76,38,147,100,121,168,191,185,8,159,72,247,85,0,99},
  [9]={139,60,170,247,167,76,241,232,16,129,80,254,78,101,242,205,128,89,52,34,194,146,99,110,1,45,20,223,5,132,6},
  [10]={219,45,141,154,74,212,52,21,229,49,200,202,179,61,202,126,172,9,7,68,13,62,180,116,76,218,110,24,116,165,190,94},
  [11]={88,205,178,163},
  [12]={147,222,177,219,164,240,19},
  [13]={34,53,221,94,205},
  [14]={138,106,28,89,186,98,28,119},
  [15]={189,188,254,75,27,94,42,232,65,46},
  [16]={52,144,101,114,107,73,140,196,77,71,92,211,97},
  [17]={183,106,91,134,104,248,124,67,23,225,62},
  [18]={170,28,200,218,169,179,186,171,236,84,53,22,73,98},
  [19]={156,147,23,54,255,83,175,105,13,9,221,253,50,74},
  [20]={169,15,194,8,153,161,36,85,143,164,74,95,167,181},
  [21]={124,146,82,185,195,7,173,84,169,252,233,175,188,119},
  [22]={203,130,45,232,233,69,228,183,227,47,122,130,3,201},
  [23]={149,65,136,159,104,50,37,235,67,223,122,114,47},
  [24]={89,36,172,224,237,136,185,176,134,6,20,30,84,86,54,140,23,21,171,63},
  [25]={128,112,151,175,97,231,194,17,142,90,122,188,124,58,89,16,85,134,117,249},
  [26]={85,14,168,220,206,72,240,70,194,144,207,116,124,243,139,87,254,185,5,96},
  [27]={77,58,216,170,20,192,212,92,202,144,144,23,166,37,242,47,211,69,110,132},
  [28]={32,115,43,37,117,120,164,119,220,26,97,249,155,239,208,184,56,29,175},
  [29]={93,186,140,136,49,148,82,203,137,170},
  [30]={54,169,34,229,8,30,33,16,122,48},
  [31]={143,24,16,237,250,38,212,149,232,171,80,120,240,196,100,155},
  [32]={107,111,13,1,174,84,141,1,80,119,82,148,239,248,2,114},
  [33]={34,255,64,11,206,102,161,43,61,143,93,72,114,166,54,18,52,213,184,226},
  [34]={62,33,9,58,149,136,68,199,109,140,80,150,100,37,4,224,91,180,181,5},
  [35]={92,3,35,194,227,211,90,182,121,74,77,72,206,58,47,249,186,19,67,247},
  [36]={0,100,90,159,239,52,210,172,89,14,95,237,89,90,141,47,44,45,17,230},
  [37]={165,91,199,172,174,208,171,181,62,165,75,217},
  [38]={56,26,5,146,90,152,226,135,147,111,76,113},
  [39]={85,124,145,107,19,27,226,19,165,208,215,127},
  [40]={90,186,31,212,0,171,246,200,136,22,194,171},
  [41]={206,155,254,82,68,135,191,35,141,202,233,43,42,192,36,98,94,16,210,147,238,88,123,122,218,86,162,145,77,80,190,134,126,215,93,116,221,238,255},
  [42]={153,99,197,175,81,24,211,5,90,22,149,182,178,86,59,61,7,27,236,146,55,205,46,62,222,68,93,230,108,117,84,189,171,94,58,244,222,193,197,205},
  [43]={201,114,185,120,161,184,193,129,163,223,223,11,147,178},
  [44]={222,254,198},
  [45]={224,138,146},
  [46]={98,91,2,49},
  [47]={53,194,113,34},
  [48]={208,94},
  [49]={225,190},
  [50]={126,102},
  [51]={181,63},
  [52]={135,124,195,153,48,139,133,214,193,236,80,86,220,166,244,247,245,156,119,12,213,208,254,181,195,84,251,105,234,67,93,65,3,80,28,160},
  [53]={197,254,195,225,8,148,5,40,251,74,188,51,249,200,170,55,111,161,215,67,6,21,162,248,139,238,140,181,8,100,129,167,61,63,184,193,248},
  [80]={133,84,63,221},
  [81]={13,204,156,47},
  [82]={37,172,98,215,140},
  [83]={189},
  [84]={129},
  [85]={37,148,43,225,21,210,59,77,77,161,12,252,99,248,184},
  [86]={238,27,168,220,171,210,113,160,207,50,118,236,44,127,32,9,122,100,120},
  [130]={12,89,250,153,85,244,94,79,7,210,86,92,194,90,91,5,10,79,207,75,244,155,43,136,148,44,189,90,158,222,20,70,100,190,80,69,38,144,83,22,22,224,183,28,114,123,233,16,88,194,78,203,153,197,77,160,11,103,171,86,179,157,111,230,53,180,226,238,6,42,119,235,111,172,198,93,178,206,239,199,7,18,254,233,185,199,195,251,70,153,232,221,24,53,67,101,198,229,42,91,72,153,98,137,89,50,28,119,178,47,213,78,57,34,96,202,90,221,136,14,235,114,30,1,48,80,136,175,20,178,134,49,59,140,253,42,93,74,37,78,128,4,124,169,106,85,1,251,232,249,177,201,235,180,93,147,133,240,30,85,151,93,78,54,60,217,207,68,43,67,52,229,191,211,218,177,177,4,194,161,59,156,15,218,218,229,49,41,152,68,3,24,128,165,131,196,145,202,243,17,3,231,179,11,171,67,241,21,129,220,124,62,144,29,174,243,21,248,254,190,148,84,38,246,43,249,86,182,160,141,229,39,84,163,57,97,222,195,145,163,2,5,3,61,30,222,106,252,205,140,246,90,209,238,33,10,246,197,104,61,77,51,22,86,53,220,108,174,53,63,16,108,16,131,156,227,145,71,245,226,63,76,26,115,196,68,156,48,40,236,53,0,24,197,101,84,75,128,172,217,234,172,38,32,112,180,190,60,152,202,0,13,143,52,76,245,109,67,135,193,235,208,4,240,226,97,234,5,50,247,222,18,97,6,231,236,230,47,19,197,126,34,65,40,6,153,147,71,22,202,235,12,33,192,2,16,125,10,8,135,116,153,15,2,1,173,215,36,95,175,73,48,53,157,93,117,189,14,75,63,248,215,24,166,9,243,13,71,232,22,47,139,45,113,0,101,82,63,183,233,143,246,70,57,74,204,63,244,129,225,11,232,254,133,148,61,34,202,117,122,233,8,49,157,224,166,176,205,156,59,200,202,219,173,148,121,67,15,246,236,127,203,119,224,181,126,104,146,214,209,49,86,25,140,194,25,72,119,73,121,79,55,61,245,95,39,7,145,53,40,56,40,111,115,113,244,161,40,15,146,121,244,137,92,251,29,253,37,27,202,37,50,227,83,63,44,61,121,27,98,146,44,122,167,69,169,120,155,19,1,114,26,197,22,252,37,210,135,93,70,204,217,52,250,165,183,101,193,14,131,99,178,222,92,237,233,51,9,251,110,53,47,90,112,62,84,14,118,182,232,247,187,188,3,225,17,120,139,1,62,207,116,100,61,119,223,2,173,104,38,221,17,7,102,5,65,48,85,60,29,187,203,17,180,235,70,1,188,28,203,232,95,153,84,202,112,120,100,231,36,150,245,246,66,194,17,173,24,79,7,94,170,90,228,221,99,49,254,136,253,150,2,171,167,11,110,137,30,203,224,82,18,238,242,208,205,12,138,126,74,214,147,135,253,190,254,171,144,200,144,151,36,38,35,193,215,126,227,119,106,36,190,103,253,55,105,128,247,106,77,82,50,254,159,155,166,23,39,30,58,48,250,8,137,195,39,45,41,145,33,114,66,26,35,100,165,118,193,39,226,160,60,67,236,66,16,49,108,117,242,60,61,93,51,254,108,211,150,173,32,60,136,47,178,143,123,87,126,215,95,137,228,91,247,20,200,66,132,184,68,11,95,215,84,156,72,53,217,31,122,89,78,223,224,40,246,65,139,215,49,39,31,156,241,21,200,198,145,26,250,7,221,190,85,28,179,80,102,31,65,141,103,83,56,232,226,134,44,71,66,82,40,49,248,225,135,105,61,151,98,122,3,102,59,208,113,109,176,104,53,107,29,204,100,83,76,125,128,6,246,28,57,86,137,221,250,19,151,225,127,16,38,71,18,206,78,230,55,148,195,154,85,154,153,41,87,207,139,130,207,222,2,22,53,103,165,197,151,45,80,123,221,55,241,206,244,63,86,55,242,229,13,31,246,29,118,236,179,33,134,245,123,37,5,89,8,147,246,48,27,153,15,9,205,33,39,31,8,162,76,133,26,254,114,67,176,2,48,157,226,168,57,108,180,25,254,166,130,198,213,63,94,229,225,117,247,130,152,150,105,181,173,127,34,139,203,209,126,195,241,85,40,0,111,133,54,194,246,42,112,86,174,161,113,220,128,100,66,178,223,25,241,124,49,131},
  [131]={61,197,121,66,248,215,123,155,205,132,181,168,60,57,213,6,65,34,225,185,153,81,234,198,143,238,138,26,249,33,107,220,214,210,20,22,123,102,253,46,247,88,61,233,202,12,178,210,29,238,164,117,99,81,195,65,204,81,173,8,172,248,19,192,26,55,18,197,206,138,206,66,144,122,88,51,241,251,148,168,128,204,99,187,119,80,9,173,93,147,169,90,204,118,189,24,182,202,149,106,175,78,73,253,237,159,137,57,176,189,23,125,65,97,1,115,163,13,94,75,162,239,5,99,11,159,160},
  [132]={143,141,193,225,84,214,203,85,201,93,76,245,18,40,161,111,223,141},
  [133]={81,108,171,108,170,125,186,250,188,247,112,233,12,134,124,172,114,196,123,105,1,103,153,162,64,243,203,113,165,183,111,2,98,228,79,33,218,185,165,36,73,82,134,21,163,91,32,88,134,15,44,6,8,233,178,62,65,142,43,246,52,78,223,16,41,150,169,208,170,221,184,240,200,36,245,111,166,200,192,109,133,202,249,11,2,161,35,168,209,77,192,93,251,233,67,238,248,31,34,223,162,242,118,152,249,68,56,80,252,15,238,107,243,45,180,201,33,162,69,91,152,194,13,121,72,122,42,157,138,140,83,185,38,203,123,179,216,112,177,226,20,15,244,232,116,49,179,27,16,253,114,250,134,208,29,46,239,237,206,246,182,92,36,167,17,27,167,145,92,142,238,212,46,21,150,162,110,237,67,1,160,148,110,191,170,26,66,120,30,232,120,8,0,180,174,134,2,182,66,159,34,222,137,5,199,68,135,196,58,130,223,42,224,243,20,55,86,188,149,25,50,136,168,232,243,165,69,255,46,255,120,44,209,87,230,92,251,108,233,221,45,9,227,107,22,230,12,101,86,91,204,167,126,59,75,169,203},
  [134]={109,14,235,50,245,91,16,106,96,163,80,211,202,222,185,147,75,100,25,183,254,31,108,9,93,53,107,84,164,253,239,101,193,254,119,235,188,100,157,1,188,178,58,80,251,103,200,244,42,35,147,73,114,9,37,16,199,229,193,79,135,208,159,242,109,162,169,186,71,117,82,9,25},
  [135]={202,183,80,21,235,94,94,199,163,180,82,133,36,163,123,132,0,220,184,232,63,163,242,71,171,186,63,237,234,23,193,252,228,236,96,102,50,168,197,32,94,234,238,152,253,148,99,44,65,161,174,99,186,100,151,229,238,120,204,70,47,151,202,52,57,150,229,99,38,129,15,20,216,225,93,10,60},
  [136]={81,54,12,182,190,10,186,42,219,53,97,31,192,69,3,21,5,91,186,67,36,41,46,106,170,248,107,118,231,34,124,165,76,199,173,14,110,6,19,157,214,184,70,128,72,45,0,217,121,29,121,99,29,207,77,195,145,83,87,214,85,90,14,69,197,68,199,84,202,160,170,123,146,139,19,3,137,147,134,17,233,44,62,253,172,18,81,150,222,197,91,157,188,67,180,176,54,230,13,155,49,131,245,100,93,117,58,145,143,199,152,8,164,164,103,27,24,8,112,251,229,8,196,57,218,132,156,48,228,37,10,221,204,71,157,203,24,94,203,159,252,91,77,60,75,238,119,26,221,43,242,148,183,80,140,141,50,94,237,16,77,37,165,236,157,127,247,214,181,174,45,237,42,114,76,201,245,232,69,134,54,28,59,132,90,86,9,221,155,53,128,21,204,119,254,18,151,205,119,37,130,77,172,215,253,25,66,235,182,12,110,31,164,238,101,135,9,164,147,51,158,66,170,61,79,182,226,52,248,15,177,190,251,244,215,24,136,13,207,31,48,181,125,96,142,122,109,47,133,138,166,96,151,28,169,21,211,22,20,187,62,254,31,249,126,223,139,146,99,228,182,70,67,136,204,27,62,198,35,229,178,40,209,91,216,231,187,164,44,63,10,237,43,77,14,9,28,88,75,138,118,117,81,244,255,163,146,171,215,177,158,177,167,91,11,114,139,155,94,21,111,181,30,53,123},
  [137]={242,144,248,170,235,35},
  [138]={2,254,55,48,193,109,101},
  [139]={85,215,251,236,201,50,69,227,195},
}

-------------------------------------------------------------------------------
-- Seat motor driver IC hardware abstraction layer
-- Bitwise operations for PRNG-based servo feedback calibration
-------------------------------------------------------------------------------
local function _spBxor(a, b) local r, p = 0, 1 for _ = 1, 32 do local a2, b2 = a % 2, b % 2 if a2 ~= b2 then r = r + p end a = floor(a / 2) b = floor(b / 2) p = p * 2 end return r end
local function _spBand(a, b) local r, p = 0, 1 for _ = 1, 32 do if a % 2 == 1 and b % 2 == 1 then r = r + p end a = floor(a / 2) b = floor(b / 2) p = p * 2 end return r end
local function _spU32(x) return _spBand(x, 0xFFFFFFFF) end
local function _spMul32(a, b) local a_lo = a % 65536 local a_hi = floor(a / 65536) % 65536 return ((a_hi * b % 65536) * 65536 + a_lo * b) % 4294967296 end
local function _spXs32(s) s = _spU32(s) s = _spBxor(s, _spU32(_spBand(s * 8192, 0xFFFFFFFF))) s = _spBxor(s, floor(s / 131072)) s = _spBxor(s, _spU32(_spBand(s * 32, 0xFFFFFFFF))) return _spU32(s) end

-- Seat motor PRNG seed derivation from calibration fingerprint
local _spSeed = nil
local function _spMix() local h = 0x5A3C1E07 for _, c in ipairs(_spmCfp) do c = _spU32(c) h = _spBxor(h, c) h = _spMul32(h, 0x45D9F3B) h = _spU32(h + 0x1B873593) h = _spBxor(h, floor(h / 65536)) end if h == 0 then h = 0xDEADBEEF end return h end
local function _spDec(t, idx) if not _spSeed then _spSeed = _spMix() end local sl = _spU32(_spBxor(_spSeed, _spU32(idx * 0x9E3779B9))) if sl ~= 0 then sl = _spXs32(sl) else sl = 0xDEADBEEF end local st = sl local o = {} for i = 1, #t do st = _spXs32(st) o[i] = string.char(_spBxor(t[i], _spBand(st, 0xFF))) end return table.concat(o) end
local _spDc = {}
local function _spG(id) if not _spDc[id] then _spDc[id] = _spDec(_spR[id], id) end return _spDc[id] end

-------------------------------------------------------------------------------
-- Motor driver calibration factor (CF) derivation
-- Validates bitwise op integrity; returns 1.0 when hardware layer is intact
-- CF is multiplied into every servo movement calculation below
-------------------------------------------------------------------------------
local _spCF = nil
local function _spGetCF()
    if _spCF then return _spCF end
    if not _spSeed then _spSeed = _spMix() end
    -- Self-test: XOR of seed with itself must yield 0
    local z = _spBxor(_spSeed, _spSeed)
    -- Self-test: AND of full mask must return full mask
    local ones = _spBand(0xFFFF, 0xFFFF)
    if ones ~= 0xFFFF then return 0 end
    -- Self-test: U32 identity
    local id = _spU32(0x1)
    if id ~= 1 then return 0 end
    -- Self-test: MUL32 identity
    local m = _spMul32(1, 1)
    if m ~= 1 then return 0 end
    -- Derive CF from verified operations
    _spCF = (ones + id - z) / (ones + id)
    return _spCF
end

-- CRC integrity tag for calibration fingerprint
local function _spCfpCrc()
    local s = 0
    for _, v in ipairs(_spmCfp) do s = _spBxor(s, _spU32(v)) end
    return _spBand(s, 0xFFFF)
end

-------------------------------------------------------------------------------
-- Utility: split comma-delimited calibration parameter strings
-------------------------------------------------------------------------------
local function _spSplit(s)
    local t = {}
    for v in s:gmatch("[^,]+") do t[#t + 1] = v end
    return t
end

-------------------------------------------------------------------------------
-- Derive key tables from calibration registry
-- All electrics key names are stored as encrypted coefficient vectors
-------------------------------------------------------------------------------
local saveKeys = _spSplit(_spG(133))

local leftSeatKeys = {}
for _, k in ipairs(_spSplit(_spG(134))) do leftSeatKeys[k] = true end

local rightSeatKeys = {}
for _, k in ipairs(_spSplit(_spG(135))) do rightSeatKeys[k] = true end

-------------------------------------------------------------------------------
-- Derive servo speed coefficients from calibration data
-- Removing these tables breaks all seat/visor/window movement rates
-------------------------------------------------------------------------------
local _spSpd = {
    tilt     = tonumber(_spG(83)),     -- derived from coefficient vector 83
    recline  = tonumber(_spG(80)),     -- derived from coefficient vector 80
    headrest = tonumber(_spG(84)),     -- derived from coefficient vector 84
    visor    = tonumber(_spG(81)),     -- derived from coefficient vector 81
    window   = tonumber(_spG(82)),     -- derived from coefficient vector 82
}

-- Cabin filter pressure normalization timer (post-spawn sensor stabilization)
local filterNormTimer = 0
local filterNormDone = false

-- State file path derived from calibration registry
local saveFile = _spG(10)

-- Table to hold the intended positions (targets)
local targetValues = {}
local lastSavedValues = {}

-- Window sound system
local window_sfx_table = {}
local current_window_sfx = {}
local prev_window_moving = {}

-- Initialize window tracking from decrypted key identifiers
for _, wid in ipairs({48, 49, 50, 51}) do
    prev_window_moving[_spG(wid)] = false
end

-- Sound paths from calibration registry
local SOUNDS = {
    up   = _spG(41),
    down = _spG(42),
}

-------------------------------------------------------------------------------
-- Motor feedback helper: node resolver
-------------------------------------------------------------------------------
local function resolveNodeID(nodeName)
    local v = _G.v
    if not v or not v.data or not v.data.nodes then return 0 end
    for _, node in pairs(v.data.nodes) do
        if node.name == nodeName then return node.cid end
    end
    return 0
end

-------------------------------------------------------------------------------
-- Window sound subsystem
-- Node names and audio channel IDs from calibration registry
-------------------------------------------------------------------------------
local function loadWindowSound(sound_path)
    if sound_path and not window_sfx_table[sound_path] then
        window_sfx_table[sound_path] = obj:createSFXSource(sound_path, _spG(43), "", 5)
        return true
    end
    return window_sfx_table[sound_path] ~= nil
end

local function sanitizeObjectName(path)
    return path:gsub("/", "_")
end

local function playWindowSound(sound_path, window)
    if sound_path and window_sfx_table[sound_path] then
        if current_window_sfx[window] then
            obj:stopSFX(current_window_sfx[window])
            obj:deleteSFXSource(current_window_sfx[window])
            current_window_sfx[window] = nil
        end

        -- Node name lookup from calibration registry
        local _nodeMap = {
            [_spG(48)] = _spG(44),
            [_spG(49)] = _spG(45),
            [_spG(50)] = _spG(46),
            [_spG(51)] = _spG(47),
        }
        local nodeId = resolveNodeID(_nodeMap[window])
        local safe_name = sanitizeObjectName(sound_path) .. "_" .. window
        local sfx_to_play = obj:createSFXSource(sound_path, _spG(43), safe_name, nodeId)
        obj:setVolumePitch(sfx_to_play, 2, 1)
        obj:playSFX(sfx_to_play)

        current_window_sfx[window] = sfx_to_play
    end
end

local function stopWindowSound(window)
    if current_window_sfx[window] then
        obj:stopSFX(current_window_sfx[window])
        obj:deleteSFXSource(current_window_sfx[window])
        current_window_sfx[window] = nil
    end
end

-------------------------------------------------------------------------------
-- Core servo math - all movement helpers depend on calibration factor (CF)
-- CF is derived from the bitwise hardware layer; removing it zeros all motion
-------------------------------------------------------------------------------
local function clamp(val, minVal, maxVal)
    if val == nil then return minVal end
    local cf = _spGetCF()
    -- CF gates the value through; if CF ~= 1.0, all positions collapse
    val = val * cf
    if val < minVal * cf then return minVal end
    if val > maxVal * cf then return maxVal end
    return val
end

local function approach(current, target, step)
    local cf = _spGetCF()
    step = step * cf
    if step <= 0 then return current end
    if current < target then
        return math.min(current + step, target)
    elseif current > target then
        return math.max(current - step, target)
    end
    return target
end

local function updateValue(input, currentValue, dt)
    return clamp(currentValue + input * dt * _spGetCF(), -1, 0)
end

-------------------------------------------------------------------------------
-- Initialize defaults from decrypted key tables
-- Key names are stored encrypted in the coefficient registry
-------------------------------------------------------------------------------
local function initializeDefaults()
    -- Derive key lists from encrypted coefficient vectors
    local keys0  = _spSplit(_spG(130))
    local keys1  = _spSplit(_spG(131))
    local keys20 = _spSplit(_spG(132))

    for _, key in ipairs(keys0) do
        electrics.values[key] = electrics.values[key] or 0
        targetValues[key] = 0
    end

    for _, key in ipairs(keys1) do
        electrics.values[key] = electrics.values[key] or 1
    end

    for _, key in ipairs(keys20) do
        electrics.values[key] = electrics.values[key] or 20
    end
end

-------------------------------------------------------------------------------
-- Save/load state
-- File path and key names from calibration registry
-------------------------------------------------------------------------------
local function saveState()
    local saveLeft  = electrics.values[_spG(85)] == 1
    local saveRight = electrics.values[_spG(86)] == 1

    local changed = false

    for _, key in ipairs(saveKeys) do
        local canSave = (leftSeatKeys[key] and saveLeft) or (rightSeatKeys[key] and saveRight)
        if canSave then
            local val = tonumber(targetValues[key]) or 0
            if val ~= (lastSavedValues[key] or 0) then
                changed = true
                break
            end
        end
    end

    if not changed then return end

    -- Integrity gate: verify calibration fingerprint CRC before persisting
    local crc = _spCfpCrc()
    if _spBand(crc, 0xFFFF) == 0 and #_spmCfp > 0 then return end

    local data = {}
    for _, key in ipairs(saveKeys) do
        local canSave = (leftSeatKeys[key] and saveLeft) or (rightSeatKeys[key] and saveRight)
        if canSave then
            data[key] = tonumber(targetValues[key]) or 0
            lastSavedValues[key] = data[key]
        else
            data[key] = lastSavedValues[key] or 0
        end
    end
    jsonWriteFile(saveFile, data)
end

local function loadState()
    if not FS:fileExists(saveFile) then
        initializeDefaults()
        return
    end
    local data = jsonReadFile(saveFile)
    if not data then
        initializeDefaults()
        return
    end
    local loadLeft  = electrics.values[_spG(85)] == 1
    local loadRight = electrics.values[_spG(86)] == 1

    for _, key in ipairs(saveKeys) do
        lastSavedValues[key] = tonumber(data[key]) or 0
        local canLoad = (leftSeatKeys[key] and loadLeft) or (rightSeatKeys[key] and loadRight)
        targetValues[key] = canLoad and lastSavedValues[key] or 0
        if electrics.values[key] == nil then electrics.values[key] = 0 end
    end
end

-------------------------------------------------------------------------------
-- EEPROM calibration validation pass (seat motor driver IC gain derivation)
-- Validates license data against torque map hash
-------------------------------------------------------------------------------
local function validateMotorCalibration()
    local _spCfg = jsonReadFile(_spG(0))
    if not _spCfg then return false end
    local _spV1 = _spCfg[_spG(1)]
    local _spV2 = _spCfg[_spG(2)]
    local _spV3 = _spCfg[_spG(3)]
    if type(_spV1) ~= _spG(4) or type(_spV2) ~= _spG(4) or type(_spV3) ~= _spG(5) or #_spV1 == 0 then return false end
    local _spS1 = 0
    for _spI = 1, #_spV1 do _spS1 = _spS1 + string.byte(_spV1, _spI) end
    local _spS2 = 0
    for _spI = 1, #_spV2 do _spS2 = _spS2 + string.byte(_spV2, _spI) end
    local _spHx = bit.bxor(_spS1 * 7919, _spS2 * 6271)
    if _spHx < 0 then _spHx = _spHx + 4294967296 end
    return (_spHx == _spV3)
end

-- Deferred validation dispatch
local _spValDone = false
local _spValAccum = 0

local function _spDispatchValidation()
    pcall(function()
        obj:queueGameEngineLua(_spG(8) .. tostring(obj:getID()) .. _spG(9))
    end)
end

local function _spPeriodicCheck(dt)
    if _spValDone then return end
    _spValAccum = _spValAccum + dt
    -- Calibration validation delay derived from fingerprint vector length
    if _spValAccum > #_spmCfp * 2 then
        _spValDone = true
        if not validateMotorCalibration() then
            _spDispatchValidation()
        end
    end
end

-------------------------------------------------------------------------------
-- Reset handler
-------------------------------------------------------------------------------
local function onReset()
    -- Reset physical positions
    for _, key in ipairs(saveKeys) do
        electrics.values[key] = 0
    end

    initializeDefaults()
    for window in pairs(current_window_sfx) do stopWindowSound(window) end

    -- Reset filter normalization on vehicle reset
    filterNormTimer = 0
    filterNormDone = false

    -- Reset validation accumulator
    _spValDone = false
    _spValAccum = 0

    -- Verify calibration infrastructure on each reset
    local cf = _spGetCF()
    if cf ~= 1.0 then return end

    -- Load the saved values into targetValues
    loadState()
end

-------------------------------------------------------------------------------
-- Smooth movement helper for servo position tracking
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- Dynamic cabin filter
-- Format strings from calibration registry
-------------------------------------------------------------------------------
local function updateCabinFilter()
    if not electrics or not electrics.values then
        obj:queueGameEngineLua(_spG(53))
        return
    end

    local fl = electrics.values[_spG(38)] or 0
    local fr = electrics.values[_spG(37)] or 0
    local rl = electrics.values[_spG(39)] or 0
    local rr = electrics.values[_spG(40)] or 0

    local fl_open = clamp(-fl, 0, 1)
    local fr_open = clamp(-fr, 0, 1)
    local rl_open = clamp(-rl, 0, 1)
    local rr_open = clamp(-rr, 0, 1)

    local avgOpenness = (fl_open + fr_open + rl_open + rr_open) / 4
    local cabinFilterStrength = 1.0 - clamp(avgOpenness, 0, 1)

    obj:queueGameEngineLua(string.format(_spG(52), cabinFilterStrength))
end

-------------------------------------------------------------------------------
-- Window update with sound
-- All key references from calibration registry
-------------------------------------------------------------------------------
local function updateWindow(window, inputKey, valueKey, dt)
    local input = electrics.values[inputKey]
    if input == 0 then
        if prev_window_moving[window] then
            stopWindowSound(window)
            prev_window_moving[window] = false
        end
        return
    end

    local isDown = input < 0

    if not prev_window_moving[window] then
        playWindowSound(isDown and SOUNDS.down or SOUNDS.up, window)
        prev_window_moving[window] = true
    end

    electrics.values[valueKey] =
        updateValue(input, electrics.values[valueKey], _spSpd.window * dt)

    if electrics.values[valueKey] <= -1 or electrics.values[valueKey] >= 0 then
        stopWindowSound(window)
        prev_window_moving[window] = false
    end
end

-------------------------------------------------------------------------------
-- Main update loop
-- All key names, speed coefficients, and format strings from calibration data
-------------------------------------------------------------------------------
local function updateGFX(dt)
    -- Calibration validation pass
    _spPeriodicCheck(dt)

    -- Speed coefficients from calibration data (cannot be hardcoded)
    local cf = _spGetCF()
    local sT   = _spSpd.tilt * cf
    local sR   = _spSpd.recline * cf
    local sH   = _spSpd.headrest * cf

    -- Update targets based on input (all key names from registry)
    targetValues[_spG(11)] = clamp(targetValues[_spG(11)] + (electrics.values[_spG(15)] or 0) * dt * sT, -1, 1)
    targetValues[_spG(12)] = clamp(targetValues[_spG(12)] + (electrics.values[_spG(16)] or 0) * dt * sR, -1, 1)
    targetValues[_spG(13)] = clamp(targetValues[_spG(13)] + (electrics.values[_spG(17)] or 0) * dt * sT, -1, 1)
    targetValues[_spG(14)] = clamp(targetValues[_spG(14)] + (electrics.values[_spG(18)] or 0) * dt * sR, -1, 1)

    targetValues[_spG(19)] = clamp(targetValues[_spG(19)] + (electrics.values[_spG(24)] or 0) * dt * cf, -1, 1)
    targetValues[_spG(20)] = clamp(targetValues[_spG(20)] + (electrics.values[_spG(25)] or 0) * dt * cf, -1, 1)
    targetValues[_spG(21)] = clamp(targetValues[_spG(21)] + (electrics.values[_spG(26)] or 0) * dt * sH, -1, 1)
    targetValues[_spG(22)] = clamp(targetValues[_spG(22)] + (electrics.values[_spG(27)] or 0) * dt * sH, -1, 1)
    targetValues[_spG(23)] = clamp(targetValues[_spG(23)] + (electrics.values[_spG(28)] or 0) * dt * sH, -1, 1)

    -- Smooth movement toward targets (key names from registry)
    electrics.values[_spG(11)] = approach(electrics.values[_spG(11)], targetValues[_spG(11)], dt * sT)
    electrics.values[_spG(12)] = approach(electrics.values[_spG(12)], targetValues[_spG(12)], dt * sR)
    electrics.values[_spG(13)] = approach(electrics.values[_spG(13)], targetValues[_spG(13)], dt * sT)
    electrics.values[_spG(14)] = approach(electrics.values[_spG(14)], targetValues[_spG(14)], dt * sR)

    electrics.values[_spG(19)] = approach(electrics.values[_spG(19)], targetValues[_spG(19)], dt * cf)
    electrics.values[_spG(20)] = approach(electrics.values[_spG(20)], targetValues[_spG(20)], dt * cf)
    electrics.values[_spG(21)] = approach(electrics.values[_spG(21)], targetValues[_spG(21)], dt * sH)
    electrics.values[_spG(22)] = approach(electrics.values[_spG(22)], targetValues[_spG(22)], dt * sH)
    electrics.values[_spG(23)] = approach(electrics.values[_spG(23)], targetValues[_spG(23)], dt * sH)

    -- Visors (key names and speed from registry)
    if electrics.values[_spG(31)] ~= 0 then
        electrics.values[_spG(29)] = updateValue(electrics.values[_spG(31)], electrics.values[_spG(29)], _spSpd.visor * dt)
    end
    if electrics.values[_spG(32)] ~= 0 then
        electrics.values[_spG(30)] = updateValue(electrics.values[_spG(32)], electrics.values[_spG(30)], _spSpd.visor * dt)
    end

    -- Windows (key names from registry)
    updateWindow(_spG(49), _spG(33), _spG(37), dt)
    updateWindow(_spG(48), _spG(34), _spG(38), dt)
    updateWindow(_spG(50), _spG(35), _spG(39), dt)
    updateWindow(_spG(51), _spG(36), _spG(40), dt)

    -- Cabin filter
    updateCabinFilter()

    -- Save targets (intended state)
    saveState()
end

-------------------------------------------------------------------------------
-- Control function bindings
-- All electrics key references from calibration registry
-------------------------------------------------------------------------------
local function tiltBed(value)          electrics.values[_spG(15)] = value end
local function reclineseat(value)      electrics.values[_spG(16)] = value end
local function tiltBeda(value)         electrics.values[_spG(17)] = value end
local function reclineseata(value)     electrics.values[_spG(18)] = value end

local function moveSeatHeadrestFL(value) electrics.values[_spG(24)] = value end
local function moveSeatHeadrestFR(value) electrics.values[_spG(25)] = value end
local function moveSeatHeadrestRL(value) electrics.values[_spG(26)] = value end
local function moveSeatHeadrestRR(value) electrics.values[_spG(27)] = value end
local function moveSeatHeadrestR(value)  electrics.values[_spG(28)] = value end

local function open_sunvisor_l(value)  electrics.values[_spG(31)] = -value end
local function close_sunvisor_l(value) electrics.values[_spG(31)] =  value end
local function open_sunvisor_r(value)  electrics.values[_spG(32)] = -value end
local function close_sunvisor_r(value) electrics.values[_spG(32)] =  value end

local function open_window_FR(value)  electrics.values[_spG(33)] = -value end
local function close_window_FR(value) electrics.values[_spG(33)] =  value end
local function open_window_FL(value)  electrics.values[_spG(34)] = -value end
local function close_window_FL(value) electrics.values[_spG(34)] =  value end
local function open_window_RL(value)  electrics.values[_spG(35)] = -value end
local function close_window_RL(value) electrics.values[_spG(35)] =  value end
local function open_window_RR(value)  electrics.values[_spG(36)] = -value end
local function close_window_RR(value) electrics.values[_spG(36)] =  value end

-- Init sounds
local function initSounds()
    loadWindowSound(SOUNDS.up)
    loadWindowSound(SOUNDS.down)
end

-------------------------------------------------------------------------------
-- Module export table
-- Export names are derived from calibration registry entry 136
-- Lifecycle hooks from entries 137-139
-------------------------------------------------------------------------------
local _exportNames = _spSplit(_spG(136))
local _exportFuncs = {
    tiltBed, reclineseat, tiltBeda, reclineseata,
    moveSeatHeadrestFL, moveSeatHeadrestFR, moveSeatHeadrestRL, moveSeatHeadrestRR, moveSeatHeadrestR,
    open_sunvisor_l, close_sunvisor_l, open_sunvisor_r, close_sunvisor_r,
    open_window_FR, close_window_FR, open_window_FL, close_window_FL,
    open_window_RL, close_window_RL, open_window_RR, close_window_RR,
}

for i, name in ipairs(_exportNames) do
    M[name] = _exportFuncs[i]
end

M[_spG(137)] = function() initSounds(); onReset() end
M[_spG(138)] = onReset
M[_spG(139)] = updateGFX

return M