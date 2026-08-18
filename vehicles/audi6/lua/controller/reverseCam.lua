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

-- MASTER SWITCH: set to true to re-enable the reverse camera.
local ENABLED = false

local geExt = "carReverseCam"
local target
local geLuaStr = ""
local electricsName = "reverseCam"
local lastAnyPlayerSeated = false

local directionVector = vec3()
local posOffset = vec3()
local pos = vec3()
local rot = quat()

local debug = false

local nodeIdRef, nodeIdX, nodeIdY = 0, 0, 0

local res = {512, 256}
local fov = 70
local clip = {0.1, 100}

local function onPlayersChanged(...)
    if playerInfo.anyPlayerSeated then
        dump(...)
        obj:queueGameEngineLua([[
            extensions.]]..geExt..[[.setFocusCar(]]..objectId..[[)
        ]])
    end
end

local function updateGFX(dt)
    if not ENABLED then
        -- keep the screen signal alive so the display (and the "disabled"
        -- notice overlay) still turns on in reverse - just never render
        electrics.values[electricsName] = (electrics.values.reverse == 1 and playerInfo.anyPlayerSeated) and 1 or 0
        return
    end

    if lastAnyPlayerSeated ~= playerInfo.anyPlayerSeated then
        onPlayersChanged()
        lastAnyPlayerSeated = playerInfo.anyPlayerSeated
    end

    electrics.values[electricsName] = 0
    if electrics.values.reverse == 1 and playerInfo.anyPlayerSeated and target then
        pos:set(obj:getPositionXYZ())
        rot:set(obj:getRotation())

        local id1 = vec3(obj:getNodePosition(nodeIdRef))
        local id2 = vec3(obj:getNodePosition(nodeIdX))
        local id3 = vec3(obj:getNodePosition(nodeIdY))

        local camDir = (id2 - id1):cross(id3 - id2):normalized() + directionVector:rotated(rot)
        local camPos = id1 + posOffset:rotated(rot) + obj:getVelocity() * dt

        if debug then
            obj.debugDrawProxy:drawSphere(0.01, pos + id1, color(255,255,255,255))
            obj.debugDrawProxy:drawSphere(0.01, pos + id2, color(255,255,255,255))
            obj.debugDrawProxy:drawSphere(0.01, pos + id3, color(255,255,255,255))

            obj.debugDrawProxy:drawLine(pos + camPos, pos + camPos + camDir, color(255,255,255,255))
        end

        obj:queueGameEngineLua(string.format(geLuaStr,
            pos + camPos,
            quatFromDir(camDir, obj:getDirectionVectorUp()),
            res[1],
            res[2],
            fov,
            clip[1],
            clip[2]
        ))

        electrics.values[electricsName] = 1
    end
end

local function init(jbeamData)
    if not ENABLED then
        electricsName = jbeamData.electricsName or electricsName
        electrics.values[electricsName] = 0
        return
    end

    geExt = jbeamData.geExt or geExt
    electricsName = jbeamData.electricsName or electricsName
    nodeIdRef = beamstate.nodeNameMap[jbeamData.camNodes.idRef or 0]
    nodeIdX = beamstate.nodeNameMap[jbeamData.camNodes.idX or 0]
    nodeIdY = beamstate.nodeNameMap[jbeamData.camNodes.idY or 0]
    target = jbeamData.texTargetName
    debug = jbeamData.debug

    if jbeamData.posOffset then
        posOffset:set(jbeamData.posOffset.x, jbeamData.posOffset.y, jbeamData.posOffset.z)
    end

    if jbeamData.rotOffset then
        directionVector = (directionVector + vec3(jbeamData.rotOffset)):normalized()
    end

    res = jbeamData.res or res
    fov = jbeamData.fov or fov
    clip = jbeamData.clip or clip

    if not target then
        return
    end

    obj:queueGameEngineLua([[
        extensions.load(]]..geExt..[[)
    ]])

    geLuaStr = geExt..".renderCam('"..target.."', %s, %s, %d, %d, %d, %s, %s)"
    if electricsName then electrics.values[electricsName] = 0 end
    onPlayersChanged()
end

M.updateGFX = updateGFX
M.init = init

return M