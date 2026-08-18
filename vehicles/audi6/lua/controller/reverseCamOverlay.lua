local M = {}

local htmlTexture = require("htmlTexture")

local gaugesScreenName = nil
local htmlPath = nil
local updateFPS = 30

local function updateGFX(dt)
  if electrics.values.reverseCam == 1 then
    local data = {
      steering = electrics.values.steering,
      speed = electrics.values.wheelspeed,
      throttle = electrics.values.throttle,
      button_parkingsensors = electrics.values.button_parkingsensors,
      reverseCameraEnabled = electrics.values.reverseCam,
      frontParkingSensorsEnabled = electrics.values.frontParkingSensorsEnabled
    }

    htmlTexture.call(gaugesScreenName, "updateGuide", data)
  end
end

local function init(jbeamData)
  gaugesScreenName = jbeamData.materialName or "@audi6_zeit_reversecam_overlay"
  htmlPath = jbeamData.htmlPath or "local://local/vehicles/audi6/reverse_cam/audi6_reversecam_overlay.html"
  local width = jbeamData.textureWidth or 512
  local height = jbeamData.textureHeight or 256

  if not gaugesScreenName then
    log("E", "reverseCamOverlay", "Got no material name for the texture, can't display anything...")
    M.updateGFX = nop
  else
    if htmlPath then
      htmlTexture.create(gaugesScreenName, htmlPath, width, height, updateFPS, "automatic")
    else
      log("E", "reverseCamOverlay", "Got no html path for the texture, can't display anything...")
      M.updateGFX = nop
    end
  end
end

M.updateGFX = updateGFX
M.init = init

return M