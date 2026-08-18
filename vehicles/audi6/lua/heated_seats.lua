local M = {}

local MAX_LEVEL = 3
local MIN_LEVEL = 0

local lastIgnition = 0

-- Helper to update glowmap electrics for a given seat
local function updateSeatElectrics(level, prefix)
	electrics.values[prefix.."Level1"] = level > 0 and 1 or 0
	electrics.values[prefix.."Level2"] = level > 1 and 1 or 0
	electrics.values[prefix.."Level3"] = level > 2 and 1 or 0
end

-- Update all electrics
local function updateElectrics()
	local driverLevel = electrics.values.heatedSeatLevel or 0
	updateSeatElectrics(driverLevel, "heatedSeat")

	local passengerLevel = electrics.values.heatedSeatLevelP or 0
	updateSeatElectrics(passengerLevel, "heatedSeatP")
end

local function onInit()
	electrics.values.heatedSeatLevel = 0      -- driver
	electrics.values.heatedSeatLevelP = 0     -- passenger
	lastIgnition = electrics.values and electrics.values.ignitionLevel or 0
	updateElectrics()
end

local function onReset()
	onInit()
end

-- Driver seat controls
local function increaseHeatedSeat()
	local level = electrics.values.heatedSeatLevel or 0
	level = math.min(level + 1, MAX_LEVEL)
	electrics.values.heatedSeatLevel = level
	updateElectrics()
end

local function decreaseHeatedSeat()
	local level = electrics.values.heatedSeatLevel or 0
	level = math.max(level - 1, MIN_LEVEL)
	electrics.values.heatedSeatLevel = level
	updateElectrics()
end

-- Passenger seat controls
local function increaseHeatedSeatP()
	local level = electrics.values.heatedSeatLevelP or 0
	level = math.min(level + 1, MAX_LEVEL)
	electrics.values.heatedSeatLevelP = level
	updateElectrics()
end

local function decreaseHeatedSeatP()
	local level = electrics.values.heatedSeatLevelP or 0
	level = math.max(level - 1, MIN_LEVEL)
	electrics.values.heatedSeatLevelP = level
	updateElectrics()
end

local function updateGFX(dt)
	local values = electrics.values
	if not values then return end

	local ignition = values.ignitionLevel or 0

	if ignition <= 1 and lastIgnition > 1 then
		values.heatedSeatLevel = 0
		values.heatedSeatLevelP = 0
		updateElectrics()
	end

	lastIgnition = ignition
end

-- public interface
M.onInit = onInit
M.onReset = onReset
M.updateGFX = updateGFX

-- driver controls
M.increaseHeatedSeat = increaseHeatedSeat
M.decreaseHeatedSeat = decreaseHeatedSeat

-- passenger controls
M.increaseHeatedSeatP = increaseHeatedSeatP
M.decreaseHeatedSeatP = decreaseHeatedSeatP

return M