-- In your Lua vehicle module
local M = {}

-- electric to hold yaw value
M.yawElectric = "vehicleYaw"

local function updateYaw()
    if not obj then return end

    -- Get vehicle forward direction (normalized vector)
    local dir = obj:getDirectionVector()
    -- Calculate yaw in radians
    local yaw = math.atan2(dir.y, dir.x) -- atan2 returns -pi..pi

    -- Normalize 0..2pi
    if yaw < 0 then yaw = yaw + 2 * math.pi end

    -- Store in electrics for JS
    electrics.values[M.yawElectric] = yaw
end

-- Called every frame
M.updateGFX = function(dt)
    updateYaw()
end

M.onInit = function()
    electrics.values[M.yawElectric] = 0
end

return M
