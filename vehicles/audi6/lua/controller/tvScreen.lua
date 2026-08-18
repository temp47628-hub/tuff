local M = {}
local htmlTexture = require("htmlTexture")

local gaugesScreenName, htmlPath, updateFPS = nil, nil, 30

local function updateGFX()
  if electrics.values.reverseCam == 1 and gaugesScreenName then
    htmlTexture.call(gaugesScreenName, "updateGuide", {
      ignitionLevel = electrics.values.ignitionLevel or 0,
    })
  end
end

local function init(jbeamData)
  gaugesScreenName = jbeamData.materialName or "@audi6_tv_screen"
  htmlPath = jbeamData.htmlPath or "local://local/vehicles/audi6/tv_screen/audi6_tv_screen.html"
  if htmlPath then
    htmlTexture.create(gaugesScreenName, htmlPath, jbeamData.textureWidth or 512, jbeamData.textureHeight or 256, jbeamData.updateFPS or 30, "automatic")
  else
    log("E", "etkGauges", "No HTML path provided.")
  end
end

M.updateGFX = updateGFX
M.init = init

return M