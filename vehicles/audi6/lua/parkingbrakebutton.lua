local M = {}
local timer = 0
local animActive = false
local animDir = 0
local lastParkingBrakeState = 0
local ANIM_TIME = 0.25
local volume, pitch = 1, 1
local camNode = 0
local function inside()
   local camPos = obj:getCameraPosition()
   local vehPos = obj:getPosition()
   local velocity = obj:getVelocity()

   if not camPos or not vehPos then return false end
   local adjustedCamPos = camPos + (velocity * 0.04)
   return adjustedCamPos:distance(vehPos) < 2.0
end
local function init()
   electrics.values.parkingbrakebutton = 0
   timer = 0
   animActive = false
   animDir = 0
   -- Force clean 0/1
   lastParkingBrakeState = (electrics.values.parkingbrake_input or 0) > 0 and 1 or 0
   camNode = beamstate.nodeNameMap["driver"] or 0
   obj:createSFXSource("/art/sound/audi6/parkingbrake/engage.ogg",  "Audio2D", "engage.ogg",  -1)
   obj:createSFXSource("/art/sound/audi6/parkingbrake/disengage.ogg","Audio2D", "disengage.ogg", -1)
end
local function updateGFX(dt)
   local rawState = electrics.values.parkingbrake_input or 0
   local parkingBrakeState = rawState > 0 and 1 or 0  -- normalize
   -- Detect real toggle
   if parkingBrakeState ~= lastParkingBrakeState then
      if inside() then
         if parkingBrakeState == 1 then
            obj:playSFXOnce("engage.ogg", camNode, volume, pitch)
         else
            obj:playSFXOnce("disengage.ogg", camNode, volume, pitch)
         end
      end
      -- Alternate the button direction each press:
      -- engaging (->1) drives the electric to 1, disengaging (->0) to -1.
      -- The timer below then returns it to 0.
      animDir = (parkingBrakeState == 1) and 1 or -1
      animActive = true
      timer = 0
      -- Update immediately to prevent double/missed triggers
      lastParkingBrakeState = parkingBrakeState
   end
   -- One-shot animation
   if animActive then
      if timer < ANIM_TIME then
         timer = timer + dt
         electrics.values.parkingbrakebutton = animDir
      else
         electrics.values.parkingbrakebutton = 0
         animActive = false
      end
   else
      electrics.values.parkingbrakebutton = 0
   end
end
M.onInit = init
M.onReset = init
M.updateGFX = updateGFX
return M