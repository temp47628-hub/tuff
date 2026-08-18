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

local camPos
local vehPos
local camDistToCar
local isInCar = false

M.isInCar = false

M.otherVehSensors = {
    sensors = {},
    directions = {},
    velocities = {},
    objects = {},
    idSlotMatch = {}
}

local curSlot = 1

-- Blind spot state
local blindSpotTimer = 0
local blindSpotData = {}
local blindSpotEnabled = true
local storedJbeamData = nil

M.blindSpotRightTriggered = false
M.blindSpotLeftTriggered = false

-- Debug/log state
local logTag = "blis"

-- Audi A6 C6 / early Audi side assist model constants.
local audiSideAssist = {
    updateInterval = 0.05,

    minActiveSpeedKmh = 60.0,
    deactivateSpeedKmh = 55.0,

    rearRadarRange = 50.0,
    monitoredLaneWidth = 3.60,

    minObjectCenterLateral = 1.45,
    maxObjectCenterLateral = 5.15,

    bPillarForwardLimit = 1.25,
    blindSpotRearLimit = -7.0,

    rearApproachStart = -50.0,
    closingSpeedThresholdKmh = 15.0,
    warningTtcSeconds = 5.0,
    warningBaseDistance = 7.0,

    triggerHoldSeconds = 0.35,

    minCurveRadiusM = 170.0,
    reactivateCurveRadiusM = 200.0,

    debug = false
}

local sideAssistCurrentlyActive = false
local curveSuppressed = false
local rightTriggerHold = 0
local leftTriggerHold = 0

local hasLoggedNoMailbox = false
local hasLoggedMailboxOk = false
local hasLoggedNoBlindSpotPrefixes = false
local hasLoggedNoPlayerOrIgnition = false

local lastLoggedVehicleCount = -1
local lastLoggedLeftState = nil
local lastLoggedRightState = nil

local debugCycle = 0
local noHitLogTimer = 0
local mailboxLogTimer = 0
local rayLogTimer = 0

-- Cache own vehicle id at init
local ownId = -1

-- Pre-allocated ray start offset tables
local rightRayStarts = {}
local leftRayStarts = {}
local RAY_COUNT = 11
for i = 1, RAY_COUNT do
    rightRayStarts[i] = vec3()
    leftRayStarts[i] = vec3()
end

-- Helper temporaries used inside updates to eliminate runtime allocations completely
local _rel            = vec3()
local _sideDir        = vec3()
local _rightPoint     = vec3()
local _leftPoint      = vec3()
local _rightPoint2    = vec3()
local _leftPoint2     = vec3()
local _rightDir       = vec3()
local _leftDir        = vec3()
local _rayStartWorld  = vec3()

local function debugLog(msg)
    log("D", logTag, msg)
end

local function warnLog(msg)
    log("W", logTag, msg)
end

local function boolStr(v)
    return v and "true" or "false"
end

local function vecStr(v)
    if not v then return "nil" end
    return string.format("(%.3f, %.3f, %.3f)", v.x or 0, v.y or 0, v.z or 0)
end

local function countTable(t)
    local c = 0
    if t then
        for _, _ in pairs(t) do
            c = c + 1
        end
    end
    return c
end

local function checkCamInside()
    vehPos = common.getDriverWorldPosition()
    isInCar = common.cameraNearPosition(vehPos, 0.6, 0)
    M.isInCar = isInCar
end

local function updateSensors(dt)
    local slotCount
    curSlot, slotCount = common.cycleOtherVehicleSensors(
        M.otherVehSensors,
        curSlot,
        dt,
        7,
        nil
    )

    if slotCount ~= lastLoggedVehicleCount then
        lastLoggedVehicleCount = slotCount
        debugLog("Vehicle slots refreshed. Count: " .. tostring(slotCount))
    end
end

local _maxRayDistance = 0

local function getHitDistance(result1, result2)
    local r1 = tonumber(result1)
    local r2 = tonumber(result2)

    if r1 and r1 ~= math.huge and r1 > 0.1 and r1 < _maxRayDistance then
        return r1
    end

    if r2 and r2 ~= math.huge and r2 > 0.1 and r2 < _maxRayDistance then
        return r2
    end

    return nil
end

local function checkRayList(rayStarts, rayDir, v, vehiclePos, vehicleId, sideName)
    for rayIndex = 1, RAY_COUNT do
        _rayStartWorld:setAdd2(vehiclePos, rayStarts[rayIndex])
        local result1, result2 = intersectsRay_OBB(
            _rayStartWorld,
            rayDir,
            v.center,
            v.x,
            v.y,
            v.z
        )

        local hitDist = getHitDistance(result1, result2)

        if audiSideAssist.debug and noHitLogTimer > 1 then
            debugLog(
                sideName .. " ray " .. tostring(rayIndex) ..
                " vs vehicle " .. tostring(vehicleId) ..
                " result1=" .. tostring(result1) ..
                ", result2=" .. tostring(result2) ..
                ", hitDist=" .. tostring(hitDist)
            )
        end

        if hitDist then
            return true, hitDist, rayIndex
        end
    end

    return false, nil, nil
end

local function clamp(v, lo, hi)
    return math.min(hi, math.max(lo, v))
end

local function updateBlindSpot(dt, mailboxData)
    if not blindSpotEnabled then return end

    if not blindSpotData.resolvedNodes then
        if not hasLoggedNoBlindSpotPrefixes then
            hasLoggedNoBlindSpotPrefixes = true
            warnLog("Blind spot update skipped: resolvedNodes missing")
        end
        return
    end

    blindSpotTimer = blindSpotTimer + dt
    noHitLogTimer = noHitLogTimer + dt
    rayLogTimer = rayLogTimer + dt

    rightTriggerHold = math.max(0, rightTriggerHold - dt)
    leftTriggerHold = math.max(0, leftTriggerHold - dt)

    if blindSpotTimer > audiSideAssist.updateInterval then
        debugCycle = debugCycle + 1

        local vehiclePos = obj:getPosition()
        local wheelSpeed = electrics.values.wheelspeed or 0
        local speedKmh = wheelSpeed * 3.6

        if sideAssistCurrentlyActive then
            if speedKmh < audiSideAssist.deactivateSpeedKmh then
                sideAssistCurrentlyActive = false
            end
        else
            if speedKmh >= audiSideAssist.minActiveSpeedKmh then
                sideAssistCurrentlyActive = true
            end
        end

        local forwardDir = obj:getDirectionVector()
        local ownVelocity = obj:getVelocity()
        local ownLongSpeed = ownVelocity and ownVelocity:dot(forwardDir) or wheelSpeed

        local yawRate = electrics.values.yawRate or electrics.values.yawrate or electrics.values.yaw_rate or electrics.values.espYawRate
        if yawRate then
            local absYawRate = math.abs(yawRate)
            if absYawRate > 0.001 and ownLongSpeed > 5 then
                local curveRadius = math.abs(ownLongSpeed / absYawRate)
                if curveSuppressed then
                    if curveRadius > audiSideAssist.reactivateCurveRadiusM then
                        curveSuppressed = false
                    end
                elseif curveRadius < audiSideAssist.minCurveRadiusM then
                    curveSuppressed = true
                end
            else
                curveSuppressed = false
            end
        end

        if not sideAssistCurrentlyActive or curveSuppressed then
            M.blindSpotRightTriggered = false
            M.blindSpotLeftTriggered = false
            rightTriggerHold = 0
            leftTriggerHold = 0
            electrics.values.rightBlindSpotTriggered = false
            electrics.values.leftBlindSpotTriggered = false
            electrics.values.rightBlindSpotImminent = false
            electrics.values.leftBlindSpotImminent = false
            electrics.values.audiSideAssistActive = false
            blindSpotTimer = 0
            return
        end

        electrics.values.audiSideAssistActive = true

        local rn = blindSpotData.resolvedNodes
        
        _rightPoint:set(obj:getNodePosition(rn.right1))
        _leftPoint:set(obj:getNodePosition(rn.left1))

        if rn.right3 then
            _rightPoint2:set(obj:getNodePosition(rn.right2))
            _rightPoint2:setAdd(obj:getNodePosition(rn.right3))
            _rightPoint2:setScaled(0.5)
        else
            _rightPoint2:set(obj:getNodePosition(rn.right2))
        end

        if rn.left3 then
            _leftPoint2:set(obj:getNodePosition(rn.left2))
            _leftPoint2:setAdd(obj:getNodePosition(rn.left3))
            _leftPoint2:setScaled(0.5)
        else
            _leftPoint2:set(obj:getNodePosition(rn.left2))
        end

        _rightDir:setSub2(_rightPoint2, _rightPoint)
        _rightDir:normalize()

        _leftDir:setSub2(_leftPoint2, _leftPoint)
        _leftDir:normalize()

        _sideDir:setSub2(_rightPoint, _leftPoint)
        _sideDir:normalize()

        _maxRayDistance = audiSideAssist.rearRadarRange

        rightRayStarts[1]:set(_rightPoint)
        rightRayStarts[2]:set(_rightPoint.x,        _rightPoint.y - 0.5,  _rightPoint.z)
        rightRayStarts[3]:set(_rightPoint.x,        _rightPoint.y - 1.0,  _rightPoint.z)
        rightRayStarts[4]:set(_rightPoint.x,        _rightPoint.y - 1.5,  _rightPoint.z)
        rightRayStarts[5]:set(_rightPoint.x,        _rightPoint.y - 2.0,  _rightPoint.z)
        rightRayStarts[6]:set(_rightPoint.x,        _rightPoint.y - 2.5,  _rightPoint.z)
        rightRayStarts[7]:set(_rightPoint.x,        _rightPoint.y - 3.0,  _rightPoint.z)
        rightRayStarts[8]:set(_rightPoint.x,        _rightPoint.y - 1.0,  _rightPoint.z + 0.35)
        rightRayStarts[9]:set(_rightPoint.x,        _rightPoint.y - 1.0,  _rightPoint.z - 0.35)
        rightRayStarts[10]:set(_rightPoint.x,       _rightPoint.y - 2.0,  _rightPoint.z + 0.35)
        rightRayStarts[11]:set(_rightPoint.x,       _rightPoint.y - 2.0,  _rightPoint.z - 0.35)

        leftRayStarts[1]:set(_leftPoint)
        leftRayStarts[2]:set(_leftPoint.x,          _leftPoint.y - 0.5,   _leftPoint.z)
        leftRayStarts[3]:set(_leftPoint.x,          _leftPoint.y - 1.0,   _leftPoint.z)
        leftRayStarts[4]:set(_leftPoint.x,          _leftPoint.y - 1.5,   _leftPoint.z)
        leftRayStarts[5]:set(_leftPoint.x,          _leftPoint.y - 2.0,   _leftPoint.z)
        leftRayStarts[6]:set(_leftPoint.x,          _leftPoint.y - 2.5,   _leftPoint.z)
        leftRayStarts[7]:set(_leftPoint.x,          _leftPoint.y - 3.0,   _leftPoint.z)
        leftRayStarts[8]:set(_leftPoint.x,          _leftPoint.y - 1.0,   _leftPoint.z + 0.35)
        leftRayStarts[9]:set(_leftPoint.x,          _leftPoint.y - 1.0,   _leftPoint.z - 0.35)
        leftRayStarts[10]:set(_leftPoint.x,         _leftPoint.y - 2.0,   _leftPoint.z + 0.35)
        leftRayStarts[11]:set(_leftPoint.x,         _leftPoint.y - 2.0,   _leftPoint.z - 0.35)

        local rightCandidate = false
        local leftCandidate  = false
        local rightImminent  = false
        local leftImminent   = false

        local checkedVehicles = 0
        local invalidVehicles = 0
        local filteredVehicles = 0

        local absBlindSpotRearLimit = math.abs(audiSideAssist.blindSpotRearLimit)

        for k, v in pairs(mailboxData) do
            if k ~= ownId and v and v.center and v.x and v.y and v.z then
                checkedVehicles = checkedVehicles + 1

                -- Reusing upvalue buffers instead of operator syntax to eliminate GC allocation pressure
                _rel:setSub2(v.center, vehiclePos)
                local longitudinal = _rel:dot(forwardDir)
                local lateral      = _rel:dot(_sideDir)
                local absLateral   = math.abs(lateral)

                local targetVel = M.otherVehSensors.velocities[k]
                local targetLongSpeed = targetVel and targetVel:dot(forwardDir) or ownLongSpeed
                local closingSpeed    = targetLongSpeed - ownLongSpeed
                local closingSpeedKmh = closingSpeed * 3.6

                local inAdjacentLane =
                    absLateral >= audiSideAssist.minObjectCenterLateral and
                    absLateral <= audiSideAssist.maxObjectCenterLateral

                local inBlindSpotArea =
                    longitudinal >= audiSideAssist.blindSpotRearLimit and
                    longitudinal <= audiSideAssist.bPillarForwardLimit

                local behindInRadar =
                    longitudinal >= audiSideAssist.rearApproachStart and
                    longitudinal < audiSideAssist.blindSpotRearLimit

                local rearDistance = math.abs(longitudinal)
                local speedBasedWarningDistance = clamp(
                    audiSideAssist.warningBaseDistance + (math.max(0, closingSpeed) * audiSideAssist.warningTtcSeconds),
                    absBlindSpotRearLimit,
                    audiSideAssist.rearRadarRange
                )

                local rapidlyApproaching =
                    behindInRadar and
                    closingSpeedKmh >= audiSideAssist.closingSpeedThresholdKmh and
                    rearDistance <= speedBasedWarningDistance

                local shouldWarn = inAdjacentLane and (inBlindSpotArea or rapidlyApproaching)

                if shouldWarn then
                    local rightRayHit = false
                    local leftRayHit  = false

                    if audiSideAssist.debug then
                        rightRayHit = checkRayList(rightRayStarts, _rightDir, v, vehiclePos, k, "Right")
                        leftRayHit  = checkRayList(leftRayStarts,  _leftDir,  v, vehiclePos, k, "Left")
                    end

                    if lateral > 0 then
                        rightCandidate = true
                        rightImminent = rightImminent or rapidlyApproaching
                        rightTriggerHold = audiSideAssist.triggerHoldSeconds
                    else
                        leftCandidate = true
                        leftImminent = leftImminent or rapidlyApproaching
                        leftTriggerHold = audiSideAssist.triggerHoldSeconds
                    end
                else
                    filteredVehicles = filteredVehicles + 1
                end
            end
        end

        M.blindSpotRightTriggered = rightCandidate or rightTriggerHold > 0
        M.blindSpotLeftTriggered  = leftCandidate  or leftTriggerHold  > 0

        electrics.values.rightBlindSpotTriggered = M.blindSpotRightTriggered
        electrics.values.leftBlindSpotTriggered  = M.blindSpotLeftTriggered
		
		local level = (math.min(math.max(electrics.values.mmi_sideAssistLevel or 1, 1), 5)) / 5

		electrics.values.leftAudiSideAssistLevel = M.blindSpotLeftTriggered and level or 0
		electrics.values.rightAudiSideAssistLevel = M.blindSpotRightTriggered and level or 0
		
        electrics.values.rightBlindSpotImminent  = rightImminent
        electrics.values.leftBlindSpotImminent   = leftImminent

        if lastLoggedRightState ~= M.blindSpotRightTriggered then
            lastLoggedRightState = M.blindSpotRightTriggered
            debugLog("Right Audi side assist state changed to: " .. tostring(M.blindSpotRightTriggered))
        end

        if lastLoggedLeftState ~= M.blindSpotLeftTriggered then
            lastLoggedLeftState = M.blindSpotLeftTriggered
            debugLog("Left Audi side assist state changed to: " .. tostring(M.blindSpotLeftTriggered))
        end

        blindSpotTimer = 0
    end
end

local function updateGFX(dt)
    if electrics.values.button_blis ~= 1 then
        M.blindSpotRightTriggered = false
        M.blindSpotLeftTriggered = false
        electrics.values.rightBlindSpotTriggered = false
        electrics.values.leftBlindSpotTriggered = false
        electrics.values.audiSideAssistActive = false
        return
    end

    if not playerInfo.anyPlayerSeated or electrics.values.ignitionLevel == 0 then
        if not hasLoggedNoPlayerOrIgnition then
            hasLoggedNoPlayerOrIgnition = true
            warnLog("updateGFX skipped: Player unseated or Ignition turned completely off.")
        end
        return
    end

    hasLoggedNoPlayerOrIgnition = false
    checkCamInside()
    mailboxLogTimer = mailboxLogTimer + dt

    local rawMailboxData, mailboxData = common.getMailbox("VehOBBs")

    if not rawMailboxData then
        if not hasLoggedNoMailbox or mailboxLogTimer > 2 then
            hasLoggedNoMailbox = true
            mailboxLogTimer = 0
            warnLog("No VehOBBs mailbox data found.")
        end
        return
    end

    if not hasLoggedMailboxOk then
        hasLoggedMailboxOk = true
        debugLog("VehOBBs mailbox data received successfully")
    end

    if not mailboxData or not next(mailboxData) then
        return
    end

    updateSensors(dt)
    updateBlindSpot(dt, mailboxData)
end

local function initBlindSpot(jbeamData)
    local n = beamstate.nodeNameMap

    blindSpotData = jbeamData or {}
    blindSpotEnabled = true

    if not blindSpotData.nodePrefixes then
        blindSpotEnabled = false
        warnLog("No nodePrefixes specified, blind spot disabled")
        return
    end

    if #blindSpotData.nodePrefixes < 2 then
        blindSpotEnabled = false
        warnLog("nodePrefixes must have at least 2 entries. Blind spot disabled.")
        return
    end

    for _, v in ipairs(blindSpotData.nodePrefixes) do
        local rightName = v .. "r"
        local leftName  = v .. "l"
        local rightId   = n[rightName]
        local leftId    = n[leftName]

        if not rightId or not leftId then
            blindSpotEnabled = false
            warnLog("Missing mirror node mappings. Blind spot disabled.")
            break
        end
    end

    if blindSpotEnabled then
        local nm = blindSpotData.nodePrefixes
        blindSpotData.resolvedNodes = {
            right1 = n[nm[1] .. "r"],
            left1  = n[nm[1] .. "l"],
            right2 = n[nm[2] .. "r"],
            left2  = n[nm[2] .. "l"],
            right3 = nm[3] and n[nm[3] .. "r"] or nil,
            left3  = nm[3] and n[nm[3] .. "l"] or nil
        }
    end

    electrics.values.rightBlindSpotTriggered = false
    electrics.values.leftBlindSpotTriggered  = false
    electrics.values.rightBlindSpotImminent  = false
    electrics.values.leftBlindSpotImminent   = false
    electrics.values.audiSideAssistActive    = false
	electrics.values.leftAudiSideAssistLevel = 0
	electrics.values.rightAudiSideAssistLevel = 0
end

local function findBlindSpotData(jbeamData)
    if not jbeamData then return nil end
    if jbeamData.nodePrefixes then return jbeamData end
    if jbeamData.blindSpot and jbeamData.blindSpot.nodePrefixes then return jbeamData.blindSpot end

    if jbeamData.components then
        for _, controllerData in ipairs(tableFromHeaderTable(jbeamData.components)) do
            if controllerData.nodePrefixes then return controllerData end
            if controllerData.blindSpot and controllerData.blindSpot.nodePrefixes then return controllerData.blindSpot end
        end
    end
    return nil
end

local function init(jbeamData)
    ownId = obj:getId()
    storedJbeamData = jbeamData
    local bsData = findBlindSpotData(jbeamData)
    if bsData then initBlindSpot(bsData) end
end

local function initSecondStage(jbeamData)
    common.registerVehDataHelper()
    local bsData = findBlindSpotData(jbeamData) or findBlindSpotData(storedJbeamData)
    if bsData then 
        initBlindSpot(bsData) 
    else
        blindSpotEnabled = false
    end
end

local function reset()
    blindSpotTimer = 0
    sideAssistCurrentlyActive = false
    curveSuppressed = false
    rightTriggerHold = 0
    leftTriggerHold = 0

    M.blindSpotRightTriggered = false
    M.blindSpotLeftTriggered  = false

    electrics.values.rightBlindSpotTriggered = false
    electrics.values.leftBlindSpotTriggered  = false
    electrics.values.rightBlindSpotImminent  = false
    electrics.values.leftBlindSpotImminent   = false
    electrics.values.audiSideAssistActive    = false

    table.clear(M.otherVehSensors.sensors)
    table.clear(M.otherVehSensors.directions)
    table.clear(M.otherVehSensors.velocities)
    table.clear(M.otherVehSensors.objects)
    table.clear(M.otherVehSensors.idSlotMatch)

    curSlot = 1
    hasLoggedNoMailbox = false
    hasLoggedMailboxOk = false
    hasLoggedNoBlindSpotPrefixes = false
    hasLoggedNoPlayerOrIgnition  = false
    lastLoggedVehicleCount = -1
    lastLoggedLeftState    = nil
    lastLoggedRightState   = nil
    debugCycle    = 0
    noHitLogTimer = 0
    mailboxLogTimer = 0
    rayLogTimer   = 0
end

M.updateGFX = updateGFX
M.reset = reset
M.init = init
M.initSecondStage = initSecondStage

return M