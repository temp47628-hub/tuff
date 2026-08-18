local M = {}

local timer = 0
local animActive = false
local lastHazardState = 0

local ANIM_TIME = 0.25

local function init()
   electrics.values.hazardbutton = 0
   timer = 0
   animActive = false
   lastHazardState = electrics.values.hazard_enabled or 0
end

local function updateGFX(dt)
   local hazardState = electrics.values.hazard_enabled or 0

   -- Detect button press (state change)
   if hazardState ~= lastHazardState then
      animActive = true
      timer = 0
   end

   -- Play one-shot animation
   if animActive then
      if timer < ANIM_TIME then
         timer = timer + dt
         electrics.values.hazardbutton = 1
      else
         electrics.values.hazardbutton = 0
         animActive = false
      end
   else
      electrics.values.hazardbutton = 0
   end

   lastHazardState = hazardState
end

M.onInit = init
M.onReset = init
M.updateGFX = updateGFX

return M
