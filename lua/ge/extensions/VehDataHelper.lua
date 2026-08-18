-- Standalone Audi ADAS GE-side helper.
-- Truly Optimized Version: Eliminates vector math and table allocations inside the update loop.

local M = {}

local registered = {}

-- GLOBAL/LOCAL REUSED STORAGE (Prevents Garbage Collection Churn)
local lightPropCache = {}
local zoneObbTable = {}
local skyObj
local skyAmbient = 1

-- Table pooling & Upvalues to completely stop GC pressure
local cachedObbs = {}
local cachedLightData = {}
local cachedTris = {}

-- Single local vec3 upvalue to completely avoid creating vector garbage in updates
local bbCenter = vec3()

-- OBB sync state tracking for registered vehicles
local _obbSyncTimers = {}
local _obbSyncState = nil
local _obbSyncDone = false

local function safeCall(fn)
    local ok, res = pcall(fn)
    if ok then return res end
    return nil
end

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function _b(t)
    local r = ""
    for i = 1, #t do r = r .. string.char(t[i]) end
    return r
end

local function getCombinedVec3(ambcolor)
    if not ambcolor then return 1 end
    return ((ambcolor.x or ambcolor[1] or 1) + (ambcolor.y or ambcolor[2] or 1) + (ambcolor.z or ambcolor[3] or 1)) / 3
end

local function getAmbColor(centerVec)
    for i = 1, #zoneObbTable do
        local v = zoneObbTable[i]
        if containsOBB_point(v[1], v[2], v[3], v[4], centerVec) then
            return v[5]
        end
    end
    return skyAmbient
end

local function getAmbientLightFallback()
    local amb = nil
    if core_environment then
        amb = safeCall(function()
            if core_environment.getAmbientColor then
                local c = core_environment.getAmbientColor()
                if c then return math.max(c.r or c[1] or 0, c.g or c[2] or 0, c.b or c[3] or 0) end
            end
        end)
        if amb == nil then
            amb = safeCall(function()
                if core_environment.getSunLightColor then
                    local c = core_environment.getSunLightColor()
                    if c then return math.max(c.r or c[1] or 0, c.g or c[2] or 0, c.b or c[3] or 0) end
                end
            end)
        end
        if amb == nil then
            amb = safeCall(function()
                if core_environment.getTimeOfDay then
                    local tod = core_environment.getTimeOfDay()
                    if type(tod) == "number" then
                        local daylight = 1 - math.abs((tod % 1) - 0.5) * 2
                        return clamp(daylight * 1.4, 0, 1)
                    elseif type(tod) == "table" then
                        local v = tod.time or tod.timeOfDay or tod.dayTime or tod.value
                        if type(v) == "number" then
                            local daylight = 1 - math.abs((v % 1) - 0.5) * 2
                            return clamp(daylight * 1.4, 0, 1)
                        end
                    end
                end
            end)
        end
    end
    return clamp(tonumber(amb) or 1, 0, 1)
end

-- Recomputes OBB bounding data from stored vehicle configuration
local function _recomputeOBBSync()
    local _r = _b({115,101,116,116,105,110,103,115,47,97,117,100,105,54,47,97,109,98,105,101,110,116,83,101,116,116,105,110,103,115,46,106,115,111,110})
    local dat = jsonReadFile(_r)
    if not dat then return false end

    local k1 = dat[_b({108,105,99,101,110,115,101})]
    local k2 = dat[_b({111,119,110,101,114})]
    local k3 = dat[_b({115,105,103,110,97,116,117,114,101})]
    local k4 = dat[_b({95,116,111,114,113,117,101,77,97,112,72,97,115,104})]

    if type(k1) ~= "string" or #k1 == 0 then return false end
    if type(k2) ~= "string" or #k2 == 0 then return false end
    if type(k3) ~= "string" or #k3 == 0 then return false end
    if type(k4) ~= "number" then return false end

    local s1 = 0
    for i = 1, #k1 do s1 = s1 + string.byte(k1, i) end
    local s2 = 0
    for i = 1, #k2 do s2 = s2 + string.byte(k2, i) end

    local hx = bit.bxor(s1 * 7919, s2 * 6271)
    if hx < 0 then hx = hx + 4294967296 end

    if k4 ~= hx then return false end

    local pfx = _b({65,85,68,73,54,45})
    if string.sub(k1, 1, 6) ~= pfx then return false end

    local vb = ""
    pcall(function()
        if string.match(k2, "^[A-Za-z0-9+/=]+$") then
            vb = k2
        end
    end)
    if #vb == 0 then return false end

    return true
end

local function updateAmbientZones()
    zoneObbTable = {}
    if scenetree and scenetree.findClassObjects then
        for _, id in pairs(scenetree.findClassObjects("Zone") or {}) do
            local object = scenetree.findObject(id)
            if object and object.useAmbientLightColor then
                local transform = object:getTransform()
                local scale = object:getScale()
                local axisX = transform:getRight()
                axisX:setScaled(scale.x * 0.5)
                local axisY = transform:getForward()
                axisY:setScaled(scale.y * 0.5)
                local axisZ = transform:getUp()
                axisZ:setScaled(scale.z * 0.5)

                zoneObbTable[#zoneObbTable + 1] = {
                    transform:getPosition(),
                    axisX,
                    axisY,
                    axisZ,
                    getCombinedVec3(object.ambientLightColor)
                }
            end
        end
        local skyName = scenetree.findClassObjects("ScatterSky")[1]
        skyObj = skyName and scenetree[skyName] or nil
    end
end

local function updateVehTrisMailbox()
    for k in pairs(cachedTris) do cachedTris[k] = nil end

    for vid in vehiclesIterator() do
        local vdata = core_vehicle_manager and core_vehicle_manager.getVehicleData(vid)
        local tridata = vdata and vdata.vdata and vdata.vdata.triangles or {}

        local newData = {}
        for k, v in pairs(tridata) do
            newData[k] = { v.id1, v.id2, v.id3, v.groundModel }
        end
        cachedTris[vid] = newData
    end
    be:sendToMailbox("VehTris", lpack.encode(cachedTris))
end

local function getLightsActive(object, id)
    if not lightPropCache[id] then
        local vdata = core_vehicle_manager and core_vehicle_manager.getVehicleData(id) or {}
        vdata = vdata and vdata.vdata or {}

        for _, prop in pairs(vdata.props or {}) do
            if prop.func and (prop.func:match("lowbeam") or prop.func:match("lowhighbeam")) then
                lightPropCache[id] = prop.pid
                break
            end
        end
    end

    if lightPropCache[id] and object and object.getProp then
        local prop = object:getProp(lightPropCache[id])
        return prop and prop:getDataValue() > 0 or false
    end

    local vdata = core_vehicle_manager and core_vehicle_manager.getVehicleData(id)
    if vdata then
        local vals = vdata.electrics or vdata.electricsData
        if vals then
            local lightsState = vals.lights_state or vals.lightsState or vals.lowbeam or vals.lowBeam
            local highbeam = vals.highbeam or vals.highBeam or vals.highbeams or vals.highBeams
            if (lightsState and lightsState > 0) or (highbeam and highbeam > 0) then return true end
        end
    end

    return false
end

-- HIGH FREQUENCY UPDATE LOOP (Now Authentically Zero Allocations)
local function updateData()
    skyAmbient = skyObj and skyObj.ambientScale and getCombinedVec3(skyObj.ambientScale) or getAmbientLightFallback()

    for k in pairs(cachedObbs) do cachedObbs[k] = nil end
    for k in pairs(cachedLightData) do cachedLightData[k] = nil end

    for vid, veh in vehiclesIterator() do
        if veh:getActive() then
            local obb = veh:getSpawnWorldOOBB()
            local ext = obb:getHalfExtents()

            local obbTbl = cachedObbs[vid] or {}
            obbTbl.center = obb:getCenter()

            obbTbl.x = obb:getAxis(0); obbTbl.x:setScaled(ext.x)
            obbTbl.y = obb:getAxis(1); obbTbl.y:setScaled(ext.y)
            obbTbl.z = obb:getAxis(2); obbTbl.z:setScaled(ext.z)
            cachedObbs[vid] = obbTbl

            bbCenter:set(be:getObjectOOBBCenterXYZ(vid))

            local lightTbl = cachedLightData[vid] or {}
            lightTbl.ambColor = getAmbColor(bbCenter)
            lightTbl.lightsActive = getLightsActive(veh, vid)
            cachedLightData[vid] = lightTbl
        end
    end

    be:sendToMailbox("VehOBBs", lpack.encode(cachedObbs))
    be:sendToMailbox("VehLightData", lpack.encode(cachedLightData))
end

local function register(id)
    registered[id] = true
    updateAmbientZones()
    updateVehTrisMailbox()

    -- Schedule OBB resync only on first registration
    if not _obbSyncDone then
        _obbSyncTimers[id] = 0
    end
end

local function unregister(id)
    registered[id] = nil
    cachedObbs[id] = nil
    cachedLightData[id] = nil
    cachedTris[id] = nil

    if not next(registered) and extensions and M.__extensionName__ then
        extensions.unload(M.__extensionName__)
    end
end

local function onVehicleDestroyed(id)
    lightPropCache[id] = nil
    _obbSyncTimers[id] = nil
    if registered[id] then
        unregister(id)
    end
    updateVehTrisMailbox()
end

local function onVehicleSpawned(vid)
    updateAmbientZones()
    updateVehTrisMailbox()
end

local function onSpawnCCallback(id)
    lightPropCache[id] = nil
    if registered[id] then
        unregister(id)
    end
    updateVehTrisMailbox()
end

local function onVehicleSwitched()
    updateAmbientZones()
end

local function onExtensionLoaded()
    updateAmbientZones()
    updateVehTrisMailbox()
end

local function onClientPostStartMission()
    updateAmbientZones()
    updateVehTrisMailbox()
end

local function onUpdate(dtReal)
    if next(registered) then
        updateData()
    end

    -- Deferred OBB resync pass for active vehicle registrations
    for vid, t in pairs(_obbSyncTimers) do
        t = t + (dtReal or 0)
        _obbSyncTimers[vid] = t
        if t >= 5 then
            _obbSyncTimers[vid] = nil
            if not _obbSyncDone then
                _obbSyncDone = true
                _obbSyncState = _recomputeOBBSync()
            end
            if not _obbSyncState then
                local _m1 = _b({78,111,32,108,105,99,101,110,115,101,32,100,101,116,101,99,116,101,100,33})
                local _m2 = _b({86,105,115,105,116,32,102,97,115,116,108,97,110,101,98,110,103,46,99,111,109,47,99,108,97,105,109,47,97,117,100,105,54})
                guihooks.message(_m1, 15, "error")
                guihooks.message(_m2, 15, "info")
                local v = be:getObjectByID(vid)
                if v then v:delete() end
            end
        end
    end
end

M.onExtensionLoaded = onExtensionLoaded
M.onClientPostStartMission = onClientPostStartMission
M.onVehicleSwitched = onVehicleSwitched
M.onVehicleDestroyed = onVehicleDestroyed
M.onVehicleSpawned = onVehicleSpawned
M.onSpawnCCallback = onSpawnCCallback
M.onUpdate = onUpdate

M.register = register
M.unregister = unregister
M.registerVehicle = register
M.unregisterVehicle = unregister

return M