-- This Source Code Form is subject to the terms of the bCDDL, v. 1.1.
-- If a copy of the bCDDL was not distributed with this
-- file, You can obtain one at http://beamng.com/bCDDL-1.1.txt

local M = {}
M.type = "auxiliary"

local springHydro
local springBeams = {}
local springModes = {}

local function setSpringsMode(modeName)
  local mode = springModes[modeName]
  if not mode then
    log("E", "activeSprings.setSpringsMode", "Can't find mode: " .. modeName)
    return
  end
  
  for _, cid in ipairs(springBeams) do
    local beam = v.data.beams[cid]
    obj:setBeamSpringDamp(cid, beam.beamSpring * mode.beamSpringCoef, -1, beam.beamDamp, -1)
  end
  electrics.values[springHydro] = mode.springLengthCoef
end

local function init(jbeamData)
  springHydro = jbeamData.springHydro or "springHydro"

  local springBeamNames = jbeamData.springBeamNames or {}
  for _, b in pairs(v.data.beams) do
    if b.name then
      for _, name in pairs(springBeamNames) do
        if b.name == name then
          table.insert(springBeams, b.cid)
        end
      end
    end
  end
  for _, mode in pairs(tableFromHeaderTable(jbeamData.modes or {})) do
    springModes[mode.name] = {
      springLengthCoef = mode.springLengthCoef or 1,
      beamSpringCoef = mode.beamSpringCoef or 1
  }
  end

  local nameString = jbeamData.name
  local slashPos = nameString:find("/", -nameString:len())
  if slashPos then
    nameString = nameString:sub(slashPos + 1)
  end
end

local function setParameters(parameters)
  if parameters.springMode then
    setSpringsMode(parameters.springMode)
  end
end

M.init = init
M.setParameters = setParameters

return M
