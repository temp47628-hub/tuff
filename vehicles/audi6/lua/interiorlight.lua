local M = {}

local function onReset()
    if guihooks then
        guihooks.message("Mod published by m0dsbeamng", 3, nil, "verified_user")
    end
end

local function onVehicleActiveChanged(active)
    if active then
        onReset()
    end
end

M.onVehicleActiveChanged = onVehicleActiveChanged
M.onReset = onReset

return M