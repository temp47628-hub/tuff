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

local common = require("vehicleAssistCommon")

local sensorConfig = {}
local isSensorActive = false
local beepSound, loopSound
local timers = { pulse = 0, logicUpdate = 0 }
local otherVehicles, triangleData = {}, {}
local isPlayerInCar = false
local activateSound
local lastGear = 0
local reversePlayed = false
local activationDelay = 0
local lastPdcButton = 0
local lastPdcButtonDirect = 0
local suppressActivation = false

local brokenBreakGroupCache = {}

-- Maximum sensor ray length, in meters. Kept in one place so the static ray,
-- the vehicle ray and the "no target" reset value can never drift apart.
local RAY_LENGTH = 2

-- Set to true to have the first raycast pass report what the mailboxes are
-- actually delivering. Answers "is VehDataHelper alive" and "what shape are the
-- triangles" in one line each, then goes quiet.
local debugMailboxes = false
local diagDone = false

-- The GE helper unregisters this vehicle on respawn and unloads itself once no
-- vehicle is registered. Re-registering from reset() alone is order-dependent,
-- so this tracks how long the mailboxes have been silent and re-registers.
local mailboxSilentFor = 0
local reregisterCooldown = 0

M.sensorDistances = { front = RAY_LENGTH, rear = RAY_LENGTH }

-- Persistent hit tables — reused every frame instead of allocating
local _hitsTable = { frontBumper = {}, rearBumper = {} }

-- Pre-allocated static scratchpads for math transformations inside loops to hit 0 runtime allocations
-- Static array to prevent table creation inside the update loop
local _sides = {"front", "rear"}
local _targetPos = vec3()
local _vRot = quat()
local _vPos = vec3()
local _sensorTransPos = vec3()
local _sensorDir = vec3()

-- Three separate scratchpads: the triangle corners must all be live at the
-- same time when handed to intersectsRay_Triangle.
local _p1 = vec3()
local _p2 = vec3()
local _p3 = vec3()

-- Localize fast global engine lookups
local intersectsRayOBB = intersectsRay_OBB
local intersectsRayTriangle = intersectsRay_Triangle
local mathAbs = math.abs
local mathMin = math.min

local function runDiagnostics(obbMailbox)
    diagDone = true

    local obbCount = 0
    for _ in pairs(obbMailbox) do obbCount = obbCount + 1 end
    local triCount = 0
    for _ in pairs(triangleData) do triCount = triCount + 1 end

    log("I", "parkingBeeper", "VehOBBs entries: " .. obbCount .. ", VehTris entries: " .. triCount)

    if obbCount == 0 and triCount == 0 then
        log("W", "parkingBeeper", "Both mailboxes empty - VehDataHelper is not publishing. Vehicle detection cannot work.")
        return
    end

    local _, tris = next(triangleData)
    local _, tri = next(tris or {})
    if type(tri) == "table" then
        log("I", "parkingBeeper", "First triangle nodes: " .. tostring(tri[1]) .. " " ..
            tostring(tri[2]) .. " " .. tostring(tri[3]))
    end

    local _, obb = next(obbMailbox)
    if type(obb) == "table" then
        log("I", "parkingBeeper", "OBB center type: " .. type(obb.center) ..
            ", is vec3: " .. tostring(type(obb.center) == "table" and obb.center.squaredLength ~= nil))
    end
end

local function clearHitsTable()
    local fb = _hitsTable.frontBumper
    local rb = _hitsTable.rearBumper
    for k in pairs(fb) do fb[k] = nil end
    for k in pairs(rb) do rb[k] = nil end
    electrics.values.parkingSensorHits = _hitsTable
end

local function isInside()
    return common.cameraNearPosition(obj:getPosition(), 2.0, 0.04)
end

local function getRayDistance(origin, direction, obbMailbox)
    local staticRay = obj:castRayStatic(origin, direction, RAY_LENGTH)

    -- Tracked separately from staticRay, exactly like parkingSensors does:
    -- shrinking it as triangles are hit lets the broad-phase cull tighten up.
    local vehicleRay = RAY_LENGTH
    -- Generous cull radius (ray length + half a meter) so large triangles whose
    -- first corner sits just past the ray end are not discarded prematurely.
    local cullSq = (vehicleRay + 0.5) * (vehicleRay + 0.5)

    for id, obb in pairs(obbMailbox) do
        if id ~= objectId then
            local targetVeh = otherVehicles[id]
            local tris = triangleData[id]

            if targetVeh and tris
                and mathAbs(intersectsRayOBB(origin, direction, obb.center, obb.x, obb.y, obb.z)) < 6 then

                _targetPos:set(targetVeh:getPositionXYZ())

                for _, tri in pairs(tris) do
                    -- VehDataHelper publishes each triangle as {id1, id2, id3, groundModel}
                    local i1, i2, i3 = tri[1], tri[2], tri[3]

                    if i1 and i2 and i3 then
                        _p1:setAdd2(targetVeh:getNodePosition(i1), _targetPos)

                        -- Broad phase: skip triangles that cannot possibly be
                        -- closer than the best hit so far.
                        if _p1:squaredDistance(origin) < cullSq then
                            _p2:setAdd2(targetVeh:getNodePosition(i2), _targetPos)
                            _p3:setAdd2(targetVeh:getNodePosition(i3), _targetPos)

                            local d = intersectsRayTriangle(origin, direction, _p1, _p2, _p3)
                            if d >= 0 and d < vehicleRay then
                                vehicleRay = d
                                cullSq = (vehicleRay + 0.5) * (vehicleRay + 0.5)
                            end
                        end
                    end
                end
            end
        end
    end

    return mathMin(staticRay, vehicleRay)
end

local function stopParkingSounds()
    if loopSound and obj:isPlayingSFX(loopSound) then
        obj:setVolume(loopSound, 0)
        obj:stopSFX(loopSound)
    end
end

local function beamBroken(id)
    local beam = v.data.beams[id]
    if not beam or not beam.breakGroup then return end

    if type(beam.breakGroup) == "table" then
        for _, bg in pairs(beam.breakGroup) do
            brokenBreakGroupCache[bg] = true
        end
    else
        brokenBreakGroupCache[beam.breakGroup] = true
    end
end

local function updateGFX(dt)
    if reregisterCooldown > 0 then reregisterCooldown = reregisterCooldown - dt end

    local gear = electrics.values.gearIndex or 0
    local ignition = electrics.values.ignitionLevel or 0
    local speed = electrics.values.wheelspeed or 0
    local shiftedIntoReverse = gear < 0 and lastGear >= 0

    local pdcButton = electrics.values.button_parkingsensors or 0
    local pdcButtonDirect = electrics.values.button_pdc or 0
    local pdcTurnedOn = pdcButtonDirect == 1 and lastPdcButtonDirect == 0

    if not suppressActivation and ignition > 0 and pdcButton == 1 and not reversePlayed and (shiftedIntoReverse or pdcTurnedOn) then
        if isInside() then
            activateSound = activateSound or obj:createSFXSource2(sensorConfig.activateFile, "Audio2D", "pdc_activate", 0, 0)
            obj:setVolume(activateSound, 5)
            obj:playSFX(activateSound)
        end
        reversePlayed = true
        activationDelay = 0.7
    end

    if activationDelay > 0 then
        activationDelay = activationDelay - dt
        stopParkingSounds()
        if activationDelay <= 0 then suppressActivation = false end
        lastGear = gear
        lastPdcButton = pdcButton
        lastPdcButtonDirect = pdcButtonDirect
        return
    end

    if gear >= 0 and not pdcTurnedOn then reversePlayed = false end
    lastGear = gear
    lastPdcButton = pdcButton
    lastPdcButtonDirect = pdcButtonDirect

    local isBroken = (gear > 0 and brokenBreakGroupCache[sensorConfig.frontBumperBreakGroup]) or
                     (gear < 0 and brokenBreakGroupCache[sensorConfig.rearBumperBreakGroup])

    local canRun = isSensorActive and ignition > 0 and gear ~= 0 and speed <= (sensorConfig.speedLimit or 5) and pdcButton == 1 and not isBroken

    if not canRun then
        stopParkingSounds()
        timers.pulse = 0
        M.sensorDistances.front = RAY_LENGTH
        M.sensorDistances.rear = RAY_LENGTH
        electrics.values.parkingSensorShow = 0
        clearHitsTable()
        return
    end

    timers.logicUpdate = (timers.logicUpdate + 1) % 3
    if timers.logicUpdate == 0 then
        -- Vehicle objects, OBBs and collision triangles are all refreshed here,
        -- immediately before they are consumed. Fetching the triangles on a
        -- different frame left the first raycast pass with an empty table and
        -- every later pass working on two-frame-old data.
        otherVehicles = common.getVehicleObjects()

        -- getVehTris never returns nil: on a frame where the mailbox has not
        -- arrived it hands back a shared EMPTY_TABLE. Overwriting with that
        -- would blank out detection for that pass, so only take a non-empty
        -- result and otherwise keep the previous set. Node indices stay valid
        -- across frames, so slightly stale triangles are harmless.
        local tris = common.getVehTris()
        if tris and next(tris) then triangleData = tris end

        isPlayerInCar = common.isCameraNearDriver(0.6)

        _vPos:set(obj:getPositionXYZ())
        _vRot:set(obj:getRotation())
        local nodeMap = beamstate.nodeNameMap or {}
        local obbMailbox = common.getVehOBBs()
        local showSensors = 0

        if debugMailboxes and not diagDone then runDiagnostics(obbMailbox) end

        -- Watchdog: an empty OBB mailbox is normal for a moment, but sustained
        -- silence means the GE helper unloaded itself and will never come back
        -- on its own. Re-register, at most once every few seconds.
        if next(obbMailbox) then
            mailboxSilentFor = 0
        else
            mailboxSilentFor = mailboxSilentFor + dt * 3
            if mailboxSilentFor > 2 and reregisterCooldown <= 0 then
                common.registerVehDataHelper()
                reregisterCooldown = 5
                mailboxSilentFor = 0
            end
        end

        -- Replaced inline array allocation with cached global reference
        for i = 1, 2 do
            local side = _sides[i]
            local bumperKey = side == "front" and "frontBumper" or "rearBumper"
            local dist = RAY_LENGTH
            local bumperHits = _hitsTable[bumperKey]
            for k in pairs(bumperHits) do bumperHits[k] = nil end

            for idx, s in ipairs(sensorConfig[side] or {}) do
                -- Allocation optimization: compute vector rotation and translation offsets in place using scratchpads
                _sensorTransPos:set(s.translationVec)
                _sensorTransPos:setRotate(_vRot)
                _sensorTransPos:setAdd(_vPos)
                _sensorTransPos:setAdd(obj:getNodePosition(s.refNodeId or nodeMap[s.refNode] or 0))

                -- Rotate in place instead of :rotated(), which allocates a vec3
                -- per sensor per pass.
                _sensorDir:set(s.dirVec)
                _sensorDir:setRotate(_vRot)

                local rayDist = getRayDistance(_sensorTransPos, _sensorDir, obbMailbox)
                if rayDist < 1.9 then showSensors = 1 end
                dist = mathMin(dist, rayDist)
                bumperHits[idx] = rayDist
            end
            M.sensorDistances[side] = dist
        end

        electrics.values.parkingSensorHits = _hitsTable
        electrics.values.parkingSensorShow = showSensors
    end

    local currentDist = gear < 0 and mathMin(M.sensorDistances.rear, M.sensorDistances.front) or M.sensorDistances.front
    if currentDist >= 1.5 then
        -- Only the sound stops here. Clearing the hit table also wiped the
        -- freshly measured distances, so targets between 1.5 m and 1.9 m turned
        -- the display on with nothing to draw.
        stopParkingSounds()
        timers.pulse = 0
        return
    end

    beepSound = beepSound or obj:createSFXSource2(sensorConfig.beepFile, "Audio2D", "p_once", 0, 0)
    loopSound = loopSound or obj:createSFXSource2(sensorConfig.loopFile, "AudioLoop2D", "p_loop", 0, 0)
    local mmiVol, mmiFreq
    if gear < 0 then
        mmiVol  = electrics.values.mmi_parkingRearVolume or 5
        mmiFreq = electrics.values.mmi_parkingRearFreq  or 5
    else
        mmiVol  = electrics.values.mmi_parkingFrontVolume or 5
        mmiFreq = electrics.values.mmi_parkingFrontFreq  or 5
    end
    local volume = mmiVol * (isPlayerInCar and 1 or 0.1)

    if currentDist < 0.4 then
        if isInside() then
            if not obj:isPlayingSFX(loopSound) then obj:playSFX(loopSound) end
            obj:setVolume(loopSound, volume)
        else
            stopParkingSounds()
        end
    else
        stopParkingSounds()
        timers.pulse = timers.pulse + dt
        local baseInterval = currentDist < 0.7 and 0.15 or currentDist < 0.9 and 0.3 or currentDist < 1.2 and 0.5 or 0.7
        local interval = baseInterval * (5 / (mmiFreq > 0 and mmiFreq or 5))
        if timers.pulse > interval then
            if isInside() then
                obj:playSFXOnce("p_once", 0, volume, 1)
            end
            timers.pulse = 0
        end
    end
end

local function init(jbeam)
    isSensorActive = jbeam ~= nil
    if not isSensorActive then return end

    common.registerVehDataHelper()

    brokenBreakGroupCache = {}
    otherVehicles, triangleData = {}, {}
    sensorConfig = {
        speedLimit = (jbeam.maxSpeed or 15) / 3.6,
        beepFile = jbeam.beepFile or "",
        loopFile = jbeam.loopFile or "",
        activateFile = jbeam.activateFile or "",
        front = tableFromHeaderTable(jbeam.frontBumper or {}),
        rear = tableFromHeaderTable(jbeam.rearBumper or {}),
        frontBumperBreakGroup = jbeam.frontBumperBreakGroupName,
        rearBumperBreakGroup = jbeam.rearBumperBreakGroupName
    }

    local nodeMap = beamstate.nodeNameMap or {}
    for i = 1, 2 do
        local side = _sides[i]
        for _, sensor in ipairs(sensorConfig[side]) do
            sensor.dirVec = vec3():fromString(sensor.direction or "0,1,0")
            sensor.dirVec:normalize()
            sensor.translationVec = vec3():fromString(sensor.translation or "0,0,0")

            -- Resolve the reference node once and complain loudly if it is bad.
            -- Silently falling back to node 0 put the ray origin somewhere in
            -- the middle of the car, which is very hard to diagnose in-game.
            sensor.refNodeId = nodeMap[sensor.refNode]
            if not sensor.refNodeId then
                log("E", "parkingBeeper", "Invalid refNode '" .. tostring(sensor.refNode) .. "' on " .. side .. " bumper")
                sensor.refNodeId = 0
            end
        end
    end

    lastGear = electrics.values.gearIndex or 0
    lastPdcButton = electrics.values.button_parkingsensors or 0
    lastPdcButtonDirect = electrics.values.button_pdc or 0
    reversePlayed = false
    suppressActivation = true
    activationDelay = 1
    timers.logicUpdate = 0
    timers.pulse = 0
    M.sensorDistances.front = RAY_LENGTH
    M.sensorDistances.rear = RAY_LENGTH
    clearHitsTable()
    electrics.values.parkingSensorShow = 0
end

local function reset()
    stopParkingSounds()

    -- init only runs when the vehicle is spawned, so without this the GE-side
    -- helper registration is never renewed after a reset. If it lapses the
    -- mailboxes go quiet and vehicle detection stops with no error anywhere.
    if isSensorActive then common.registerVehDataHelper() end

    brokenBreakGroupCache = {}
    otherVehicles, triangleData = {}, {}
    diagDone = false
    mailboxSilentFor = 0
    reregisterCooldown = 0
    timers.pulse = 0
    M.sensorDistances.front = RAY_LENGTH
    M.sensorDistances.rear = RAY_LENGTH
    clearHitsTable()
    electrics.values.parkingSensorShow = 0
end

M.init = init
M.reset = reset
M.updateGFX = updateGFX
M.beamBroken = beamBroken

return M