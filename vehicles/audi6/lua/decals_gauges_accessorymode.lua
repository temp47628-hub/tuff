local M = {}

local function init()
   electrics.values.decals_gauges_accessorymode = 0
end

local function reset()
   init()
end

local function updateGFX(dt)
   if electrics.values.ignitionLevel == 1 then
         electrics.values.decals_gauges_accessorymode = 1
   else
      electrics.values.decals_gauges_accessorymode = 0
   end
end

M.onInit = init
M.onReset = init
M.updateGFX = updateGFX

return M