local M = {}

local function init()
   electrics.values.ignitionLevel2 = 0
end

local function reset()
   init()
end

local function updateGFX(dt)
   if electrics.values.ignitionLevel > 0 then
      electrics.values.ignitionLevel2 = 1
   else
      electrics.values.ignitionLevel2 = 0
   end
end

M.onInit = init
M.onReset = init
M.updateGFX = updateGFX

return M