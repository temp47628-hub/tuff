local M = {}
M.type = "auxiliary"

local initialized = false
local supportedExtensions = {"ogg", "mp3"}

local function updateGFX(dt) end

local function updateGaugeData(moduleData, dt)
    if not initialized then
        moduleData.names = {}

        local files = {}

        for _, ext in ipairs(supportedExtensions) do
            for _, f in ipairs(FS:findFiles("/art/sound/audi6/music", "*." .. ext, 0, false, false)) do
                table.insert(files, f)
            end
        end

        table.sort(files)

        for i, f in ipairs(files) do
            moduleData.names[i] = f:match("([^/]+)%.[^%.]+$")
        end

        initialized = true
    end
end

local function setupGaugeData(properties) end
local function reset() end
local function init(jbeamData) end

M.init = init
M.reset = reset
M.updateGFX = updateGFX
M.setupGaugeData = setupGaugeData
M.updateGaugeData = updateGaugeData

return M