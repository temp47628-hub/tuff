--[[
MIT License

Copyright (c) 2025 DaddelZeit

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
]]

local M = {}

-- Highly Optimized Consolidated Standalone Vehicle Helper.
-- Merges sensors.lua, utils.lua, and the data management loop of v1.lua.

local max = math.max
local min = math.min
local abs = math.abs

local objData = nil
local globalVehSensors = {
    data = {},
    idToSlotMap = {}
}

local validSlots = {}
local curCount = 0
local updatesPerFrame = 24
local maxUpdatesPerFrame = 20

-- PER-FRAME MAILBOX DECODE CACHING
local cachedMailboxes = { VehOBBs = nil, VehTris = nil, VehLightData = nil }
local lastRawMailboxes = { VehOBBs = nil, VehTris = nil, VehLightData = nil }

-- Fixed Allocation Upvalues to eliminate micro-stutters
local EMPTY_TABLE = {}
local fallbackVel = vec3()
local fallbackDir = vec3()
local cycleDirBuf  = vec3()
local cycleVelBuf  = vec3()

local function getSpeedWithUnits(jbeamData, field, fallback)
    return jbeamData[field]
        or (jbeamData[field .. "KMH"] and jbeamData[field .. "KMH"] / 3.6)
        or (jbeamData[field .. "MPH"] and jbeamData[field .. "MPH"] / 2.237)
        or fallback
end
M.getSpeedWithUnits = getSpeedWithUnits

local function updateObjectBoundingBox(dir, dirUp, x, y, z, halfExtentsX, halfExtentsY, halfExtentsZ)
    x:set(dir)
    y:setCross(dirUp, dir)
    z:set(dirUp)

    y:setScaled(-halfExtentsX / max(y:squaredLength(), 1e-30))
    x:setScaled(-halfExtentsY)
    z:setScaled(-halfExtentsZ)
end
M.updateObjectBoundingBox = updateObjectBoundingBox

local function initVehData()
    return {
        g_sensors = {
            gx_smooth2 = newTemporalSmoothingNonLinear(20),
            gy_smooth2 = newTemporalSmoothingNonLinear(20),
            gz_smooth2 = newTemporalSmoothingNonLinear(20),
            gx2 = 0,
            gy2 = 0,
            gz2 = 0,
        },
        center = vec3(),
        x = vec3(),
        y = vec3(),
        z = vec3(),
        halfExtentsX = 0,
        halfExtentsY = 0,
        halfExtentsZ = 0,
        velocity = vec3(),
        direction = vec3(),
        directionUp = vec3(),
        position = vec3(),
        rotation = quat(),
        pitch = 0,
        gravity = 0,
        angVel = {
            rollAVSmoother = newTemporalSmoothingNonLinear(15),
            pitchAVSmoother = newTemporalSmoothingNonLinear(15),
            yawAVSmoother = newTemporalSmoothingNonLinear(20),
            rollAV = 0,
            pitchAV = 0,
            yawAV = 0,
        },
        lane = 0,
        lightsActive = false,
        ambColor = 1,
    }
end
M.initVehData = initVehData

local function updateVehData(BeamObjectInstance, BeamObjectInstanceID, dataTbl, dt)
    local g_sensors = dataTbl.g_sensors
    g_sensors.gx2 = g_sensors.gx_smooth2:get(BeamObjectInstance:getSensorX(), dt)
    g_sensors.gy2 = g_sensors.gy_smooth2:get(BeamObjectInstance:getSensorY(), dt)
    g_sensors.gz2 = g_sensors.gz_smooth2:get(BeamObjectInstance:getSensorZnonInertial(), dt)

    if BeamObjectInstance.getDirectionVectorXYZ then
        dataTbl.direction:set(BeamObjectInstance:getDirectionVectorXYZ())
    else
        fallbackDir:set(BeamObjectInstance:getDirectionVector())
        dataTbl.direction:set(fallbackDir)
    end

    if BeamObjectInstance.getDirectionVectorUpXYZ then
        dataTbl.directionUp:set(BeamObjectInstance:getDirectionVectorUpXYZ())
    else
        dataTbl.directionUp:set(0, 0, 1)
    end

    if BeamObjectInstance.getVelocityXYZ then
        dataTbl.velocity:set(BeamObjectInstance:getVelocityXYZ())
    else
        fallbackVel:set(BeamObjectInstance:getVelocity())
        dataTbl.velocity:set(fallbackVel)
    end

    if dataTbl.halfExtentsX == 0 and dataTbl.halfExtentsY == 0 and dataTbl.halfExtentsZ == 0 then
        dataTbl.halfExtentsX = obj:getObjectInitialWidth(BeamObjectInstanceID) * 0.5
        dataTbl.halfExtentsY = obj:getObjectInitialLength(BeamObjectInstanceID) * 0.5
        dataTbl.halfExtentsZ = obj:getObjectInitialHeight(BeamObjectInstanceID) * 0.5
    end

    dataTbl.center:set(obj:getObjectCenterPosition(BeamObjectInstanceID))

    updateObjectBoundingBox(
        dataTbl.direction, dataTbl.directionUp,
        dataTbl.y, dataTbl.x, dataTbl.z,
        dataTbl.halfExtentsX, dataTbl.halfExtentsY, dataTbl.halfExtentsZ
    )

    local rollAV, pitchAV, yawAV = BeamObjectInstance:getRollPitchYawAngularVelocity()
    local angVel = dataTbl.angVel
    angVel.rollAV = angVel.rollAVSmoother:get(rollAV, dt)
    angVel.pitchAV = angVel.pitchAVSmoother:get(pitchAV, dt)
    angVel.yawAV = angVel.yawAVSmoother:get(yawAV, dt)
end
M.updateVehData = updateVehData

local function updateOwnVehData(dataTbl, dt)
    local _, pitch = obj:getRollPitchYaw()

    if obj.getPositionXYZ then
        dataTbl.position:set(obj:getPositionXYZ())
    else
        fallbackVel:set(obj:getPosition())
        dataTbl.position:set(fallbackVel)
    end

    dataTbl.rotation:set(obj:getRotation())
    dataTbl.pitch = pitch
    dataTbl.gravity = -obj:getGravity()

    updateVehData(obj, objectId, dataTbl, dt)
end
M.updateOwnVehData = updateOwnVehData

function M.registerVehDataHelper()
    obj:queueGameEngineLua(string.format(
        "if not VehDataHelper then extensions.load('VehDataHelper') end; VehDataHelper.register(%d)",
        objectId
    ))
end

function M.getMailbox(name)
    local raw = obj:getLastMailbox(name)
    if not raw then return nil, nil end

    if lastRawMailboxes[name] == raw then
        return raw, cachedMailboxes[name]
    end

    lastRawMailboxes[name] = raw
    cachedMailboxes[name] = lpack.decode(raw)
    return raw, cachedMailboxes[name]
end

function M.decodeMailbox(name)
    local _, decoded = M.getMailbox(name)
    return decoded
end

function M.getVehOBBs()
    return M.decodeMailbox("VehOBBs") or cachedMailboxes.VehOBBs or EMPTY_TABLE
end

function M.getVehTris()
    return M.decodeMailbox("VehTris") or cachedMailboxes.VehTris or EMPTY_TABLE
end

function M.getVehLightData()
    return M.decodeMailbox("VehLightData") or cachedMailboxes.VehLightData or EMPTY_TABLE
end

function M.getAmbientLight()
    local lightData = M.getVehLightData()
    local ownData = lightData and lightData[objectId]

    if ownData and type(ownData.ambColor) == "number" then
        return ownData.ambColor
    end

    local direct = electrics.values.ambColor
        or electrics.values.ambientColor
        or electrics.values.ambientLight
        or electrics.values.ambientBrightness
        or electrics.values.envLight

    if type(direct) == "number" then
        return direct
    end

    return 1
end

function M.vehicleLightsActive(vehicleId)
    local lightData = M.getVehLightData()
    local data = lightData and lightData[vehicleId]

    if data and data.lightsActive ~= nil then
        return data.lightsActive and true or false
    end

    return true
end

function M.updateGeDataFromMailboxes()
    local lightData = M.getVehLightData()

    if objData then
        local ownLight = lightData[objectId]
        if ownLight then
            objData.ambColor = ownLight.ambColor
            objData.lightsActive = ownLight.lightsActive
        else
            objData.ambColor = M.getAmbientLight()
        end
    end

    for id, data in pairs(globalVehSensors.data) do
        local ge = lightData[id]
        if ge then
            data.ambColor = ge.ambColor
            data.lightsActive = ge.lightsActive
        else
            data.lightsActive = true
        end
    end
end

local function updateSensors(dt)
    local curVeh = BeamEngine:getSlot(validSlots[curCount] or 0)

    if curVeh then
        local curVehId = curVeh:getId()
        local curVehData = globalVehSensors.data[curVehId]

        if not curVehData then
            globalVehSensors.data[curVehId] = initVehData()
            curVehData = globalVehSensors.data[curVehId]
        end

        updateVehData(curVeh, curVehId, curVehData, dt)
    end

    curCount = curCount - 1

    if curCount <= 0 then
        table.clear(validSlots)

        for i = 0, BeamEngine:getSlotCount() - 1 do
            local slot = BeamEngine:getSlot(i)
            if slot then
                local slotId = slot:getId()

                if slotId ~= objectId and slotId ~= -1 then
                    validSlots[#validSlots + 1] = i
                    globalVehSensors.idToSlotMap[slotId] = i
                else
                    globalVehSensors.idToSlotMap[slotId] = nil
                    globalVehSensors.data[slotId] = nil
                end
            end
        end

        curCount = #validSlots
        updatesPerFrame = min(max(#validSlots, 1), maxUpdatesPerFrame)
        return true
    end

    return false
end

function M.updateSharedVehicleData(dt)
    dt = dt or 0

    if not objData then
        objData = initVehData()
    end

    updateOwnVehData(objData, dt)

    for _ = 1, updatesPerFrame do
        if updateSensors(dt) then
            break
        end
    end

    M.updateGeDataFromMailboxes()
end

function M.getOwnVehicleData()
    if not objData then
        M.updateSharedVehicleData(0)
    end
    return objData
end

function M.getGlobalVehSensorData() return globalVehSensors.data end
function M.getGlobalVehSensors() return globalVehSensors end

function M.resetSharedVehicleData()
    objData = nil
    table.clear(globalVehSensors.data)
    table.clear(globalVehSensors.idToSlotMap)
    table.clear(validSlots)
    curCount = 0
end

function M.getVehicleObjects()
    local vehicles = {}
    for i = 0, BeamEngine:getSlotCount() - 1 do
        local veh = BeamEngine:getSlot(i)
        if veh then
            vehicles[veh:getId()] = veh
        end
    end
    return vehicles
end

local camPosCache = vec3()
local scaleTmp = vec3()

function M.cameraNearPosition(position, radius, velocityLeadTime)
    local camPos = obj:getCameraPosition()
    if not camPos or not position then return false end

    if velocityLeadTime and velocityLeadTime ~= 0 then
        camPosCache:set(camPos)
        scaleTmp:set(obj:getVelocity())
        scaleTmp:setScaled(velocityLeadTime)
        camPosCache:setAdd(scaleTmp)
        return camPosCache:distance(position) <= radius
    end

    return camPos:distance(position) <= radius
end

local driverPosCache = vec3()
function M.getDriverWorldPosition()
    local nodeMap = beamstate.nodeNameMap or {}
    if obj.getPositionXYZ then
        driverPosCache:set(obj:getPositionXYZ())
    else
        driverPosCache:set(obj:getPosition())
    end
    
    local nodeIdx = nodeMap.driver or 0
    if nodeIdx then
        driverPosCache:setAdd(obj:getNodePosition(nodeIdx))
    end
    return driverPosCache
end
M.getDirverWorldPosition = M.getDriverWorldPosition -- Explicit typo-mapping alias requested by blis.lua

function M.isCameraNearDriver(radius)
    return M.cameraNearPosition(M.getDriverWorldPosition(), radius or 0.6, 0)
end

-- ZERO-ALLOCATION VECTOR LOOKUPS FOR OBB OPERATIONS
local dC = vec3()
local ux1, uy1, uz1 = vec3(), vec3(), vec3()
local ux2, uy2, uz2 = vec3(), vec3(), vec3()

function M.OBBtoOBBDistance(c1, x1, y1, z1, c2, x2, y2, z2)
    dC:setSub2(c2, c1)

    local h1x, h1y, h1z = x1:length(), y1:length(), z1:length()
    local h2x, h2y, h2z = x2:length(), y2:length(), z2:length()

    ux1:set(x1) ux1:normalize()
    uy1:set(y1) uy1:normalize()
    uz1:set(z1) uz1:normalize()
    ux2:set(x2) ux2:normalize()
    uy2:set(y2) uy2:normalize()
    uz2:set(z2) uz2:normalize()

    local dist1x = abs(dC:dot(ux1))
    local r2_on_1x = abs(ux2:dot(ux1)) * h2x + abs(uy2:dot(ux1)) * h2y + abs(uz2:dot(ux1)) * h2z
    local gap1x = max(0, dist1x - (h1x + r2_on_1x))

    local dist1y = abs(dC:dot(uy1))
    local r2_on_1y = abs(ux2:dot(uy1)) * h2x + abs(uy2:dot(uy1)) * h2y + abs(uz2:dot(uy1)) * h2z
    local gap1y = max(0, dist1y - (h1y + r2_on_1y))

    local dist1z = abs(dC:dot(uz1))
    local r2_on_1z = abs(ux2:dot(uz1)) * h2x + abs(uy2:dot(uz1)) * h2y + abs(uz2:dot(uz1)) * h2z
    local gap1z = max(0, dist1z - (h1z + r2_on_1z))

    local dist2x = abs(dC:dot(ux2))
    local r1_on_2x = abs(ux1:dot(ux2)) * h1x + abs(uy1:dot(ux2)) * h1y + abs(uz1:dot(ux2)) * h1z
    local gap2x = max(0, dist2x - (h2x + r1_on_2x))

    local dist2y = abs(dC:dot(uy2))
    local r1_on_2y = abs(ux1:dot(uy2)) * h1x + abs(uy1:dot(uy2)) * h1y + abs(uz1:dot(uy2)) * h1z
    local gap2y = max(0, dist2y - (h2y + r1_on_2y))

    local dist2z = abs(dC:dot(uz2))
    local r1_on_2z = abs(ux1:dot(uz2)) * h1x + abs(uy1:dot(uz2)) * h1y + abs(uz1:dot(uz2)) * h1z
    local gap2z = max(0, dist2z - (h2z + r1_on_2z))

    return max(gap1x, gap1y, gap1z, gap2x, gap2y, gap2z)
end

local v, w = vec3(), vec3()

function M.normalZFromTri(a, b, c)
    return ((b.x - a.x) * (c.y - a.y)) - ((b.y - a.y) * (c.x - a.x))
end

function M.normalFromTri(a, b, c, vec)
    v:setSub2(b, a)
    w:setSub2(c, a)
    vec = vec or vec3()
    vec:set(
        (v.y * w.z) - (v.z * w.y),
        (v.z * w.x) - (v.x * w.z),
        (v.x * w.y) - (v.y * w.x)
    )
    return vec
end

function M.setupPriorityStack(setFunc)
    local overrideStack = {}

    local function enableHighestPriorityOverride()
        local highestPriority, override = 0, nil
        for key, val in pairs(overrideStack) do
            if key > highestPriority then
                highestPriority = key
                override = val
            end
        end
        setFunc(override)
    end

    local function pushOverride(priority, override)
        overrideStack[priority] = override
        enableHighestPriorityOverride()
    end

    local function popOverride(priority)
        overrideStack[priority] = nil
        enableHighestPriorityOverride()
    end

    return pushOverride, popOverride, enableHighestPriorityOverride
end

function M.cycleOtherVehicleSensors(vehicleSensors, curSlot, dt, smoothingStrength, createdCallback)
    smoothingStrength = smoothingStrength or 7
    local id = vehicleSensors.idSlotMatch[curSlot]
    local curVeh = id and vehicleSensors.objects[id]

    if curVeh then
        local vehId = curVeh:getId()
        local sensors = vehicleSensors.sensors

        if not sensors[vehId] then
            sensors[vehId] = {
                gx_smooth2 = newTemporalSmoothingNonLinear(smoothingStrength),
                gy_smooth2 = newTemporalSmoothingNonLinear(smoothingStrength),
                gz_smooth2 = newTemporalSmoothingNonLinear(smoothingStrength),
                sensors = {}
            }
            if createdCallback then createdCallback(vehId) end
        end

        local sensorValues = sensors[vehId].sensors
        sensorValues.gx2 = sensors[vehId].gx_smooth2:get(obj:getSensorX(), dt)
        sensorValues.gy2 = sensors[vehId].gy_smooth2:get(obj:getSensorY(), dt)
        sensorValues.gz2 = sensors[vehId].gz_smooth2:get(obj:getSensorZnonInertial(), dt)

        -- Mutating shared local upvalues to prevent frame-by-frame garbage generation allocation
        cycleDirBuf:set(curVeh:getDirectionVector())
        cycleVelBuf:set(curVeh:getVelocity())

        vehicleSensors.directions[vehId] = cycleDirBuf
        vehicleSensors.velocities[vehId] = cycleVelBuf
    end

    curSlot = curSlot - 1
    if curSlot <= 0 then
        table.clear(vehicleSensors.idSlotMatch)
        table.clear(vehicleSensors.objects)

        for i = 0, BeamEngine:getSlotCount() - 1 do
            local slot = BeamEngine:getSlot(i)
            if slot then
                local slotId = slot:getId()
                vehicleSensors.idSlotMatch[#vehicleSensors.idSlotMatch + 1] = slotId
                vehicleSensors.objects[slotId] = slot
            end
        end
        curSlot = #vehicleSensors.idSlotMatch
    end

    return curSlot, #vehicleSensors.idSlotMatch
end

return M