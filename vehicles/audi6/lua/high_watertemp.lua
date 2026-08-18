local M = {}

local function onInit()
	electrics.values.high_watertemp = 0
end

local function onReset()
	onInit()
end

local function updateGFX(dt)
	if electrics.values.watertemp >= 115 then
		electrics.values.high_watertemp = 1
	else
		electrics.values.high_watertemp = 0
	end
end

-- public interface

M.onInit      = onInit
M.onReset     = onInit
M.updateGFX = updateGFX

return M
