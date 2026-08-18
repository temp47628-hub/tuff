local M = {}

local function init()
   electrics.values.decals_gauges_timer = 0
end

local function reset()
   init()
end

local timer = 0

local function updateGFX(dt)
   if electrics.values.ignitionLevel == 2 then
      if timer < 2 then
         timer = timer + dt
         electrics.values.decals_gauges_timer = 1
      else
         electrics.values.decals_gauges_timer = 0
      end
   else
      timer = 0
      electrics.values.decals_gauges_timer = 0
   end
end

M.onInit = init
M.onReset = init
M.updateGFX = updateGFX

return M