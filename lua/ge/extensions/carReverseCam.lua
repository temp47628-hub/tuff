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

local vehicle = nil
local registeredVehicles = {}

local function renderCam(target, pos, rot, resX, resY, fov, clipN, clipF)
    if not vehicle then return end

    local shadowsOff = getConsoleVariable("$pref::Shadows::disable")
    setConsoleVariable("$pref::Shadows::disable", "2")
    vehicle:renderCameraToMaterial(target,
        pos,
        QuatF(rot.x, rot.y, rot.z, rot.w),
        Point2I(resX, resY),
        fov,
        Point2F(clipN, clipF)
    )
    setConsoleVariable("$pref::Shadows::disable", shadowsOff)
end

local function setFocusCar(id)
    vehicle = scenetree.findObject(id)
    registeredVehicles[id] = true
end

local function onVehicleDestroyed(vid)
    if vehicle and vehicle:getId() == vid then
        vehicle = nil
    end
    registeredVehicles[vid] = nil
    if not next(registeredVehicles) then
        extensions.unload(M.__extensionName__)
    end
end

M.renderCam = renderCam
M.setFocusCar = setFocusCar
M.onVehicleDestroyed = onVehicleDestroyed

return M