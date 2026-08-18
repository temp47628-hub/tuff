local M = {}
M.type = 'auxiliary'
M.relevantDevice = nil

local function getDriveModeName()
    local controllerData = controller.getController("driveModes")
    if controllerData then
        local serialized = controllerData.serialize()
        return serialized and serialized.activeDriveModeKey or nil
    end
    return nil
end

local function onInit()
    electrics.values.tcsoff = 0	
end

local function updateGFX(dt)

    local driveMode = getDriveModeName()
	if electrics.values.ignitionLevel > 0 then
		if driveMode == 'comfort' or driveMode == 'sport' then
			electrics.values.tcsoff = 0	
		else
			electrics.values.tcsoff = 1
		end
	else
		electrics.values.tcsoff = 0	
	end
end

M.onInit = onInit
M.onReset = onInit
M.updateGFX = updateGFX

return M
