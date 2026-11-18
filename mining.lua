local glasses = assert(smartglasses, "Run this program on Smart Glasses")
local scanner = assert(peripheral.find("geo_scanner"), "Install a Geo Scanner")
local overlay = assert(glasses.modules["advancedperipherals:overlay"],
    "Install the Overlay Module")
assert(glasses.modules["advancedperipherals:hotkey"], "Install the Hotkey Module")

local targets = {
    ["minecraft:diamond_ore"] = { "Diamond", 0x44E8F5 },
    ["minecraft:iron_ore"] = { "Iron", 0xD8AE91 },
    ["minecraft:gold_ore"] = { "Gold", 0xFFCD35 },
    ["minecraft:redstone_ore"] = { "Redstone", 0xFF4040 },
    ["mekanism:osmium_ore"] = { "Osmium", 0x9DB6FF },
    ["minecraft:ancient_debris"] = { "Ancient Debris", 0xBB7755 },
    ["minecraft:nether_quartz_ore"] = { "Nether Quartz", 0xFFF0D9 },
    ["mekanism:fluorite_ore"] = { "Fluorite", 0xA8EEA0 },
    ["replication:replica_ore"] = { "Replica Ore", 0xD18BFF },
    ["minecraft:chest"] = { "Chest", 0xFF9D36 },
    ["minecraft:trapped_chest"] = { "Trapped Chest", 0xFF6655 },
    ["minecraft:ender_chest"] = { "Ender Chest", 0x67D9BC },
    ["lootr:lootr_chest"] = { "Lootr Chest", 0xFFD36A },
    ["lootr:lootr_trapped_chest"] = { "Lootr Trapped Chest", 0xFF8D51 },
    ["lootr:lootr_barrel"] = { "Lootr Barrel", 0xD9A362 },
    ["lootr:lootr_shulker"] = { "Lootr Shulker", 0xE79AF1 },
    ["lootr:lootr_inventory"] = { "Lootr Custom Inventory", 0xFFC18D },
    ["lootr:decorated_pot"] = { "Lootr Decorated Pot", 0xD7896A },
}

local directions = {
    vector.new(1, 0, 0), vector.new(-1, 0, 0),
    vector.new(0, 1, 0), vector.new(0, -1, 0),
    vector.new(0, 0, 1), vector.new(0, 0, -1),
}
local blockCenter = vector.new(0.5, 0.5, 0.5)
local scanRadius = 8
local memoryRadiusSquared = 30 * 30
local memoryPath = "mining-memory.json"
local unknownDimension = "unknown"
local remembered = {}
local memoryDimension
local memoryLoaded = false
local markerIds = {}
local labels = {}

local function key(pos)
    return ("%d,%d,%d"):format(pos.x, pos.y, pos.z)
end

local function lengthSquared(pos)
    return pos:dot(pos)
end

-- A minimal enclosing sphere is supported by at most four block centers.
local function sphereThrough(points)
    local a, b, c, d = points[1], points[2], points[3], points[4]
    if not a then return nil end
    if not b then return { center = a, radiusSquared = 0 } end

    local u = b - a
    local offset = u / 2
    if c then
        local v = c - a
        local normal = u:cross(v)
        local denominator = 2 * lengthSquared(normal)
        if denominator == 0 then return nil end
        if d then
            local w = d - a
            denominator = 2 * u:dot(v:cross(w))
            if denominator == 0 then return nil end
            offset = (v:cross(w) * lengthSquared(u)
                + w:cross(u) * lengthSquared(v)
                + normal * lengthSquared(w)) / denominator
        else
            offset = (v:cross(normal) * lengthSquared(u)
                + normal:cross(u) * lengthSquared(v)) / denominator
        end
    end
    return { center = a + offset, radiusSquared = lengthSquared(offset) }
end

local function encloses(sphere, point)
    return sphere and lengthSquared(point - sphere.center) <= sphere.radiusSquared + 1e-8
end

-- Degenerate boundary sets can be covered by a smaller subset.
local function boundarySphere(boundary)
    local sphere = sphereThrough(boundary)
    if sphere or #boundary == 0 then return sphere end

    local best
    local subset = {}
    local function search(start)
        local candidate = sphereThrough(subset)
        if candidate and (not best or candidate.radiusSquared < best.radiusSquared) then
            local covers = true
            for _, point in ipairs(boundary) do
                if not encloses(candidate, point) then
                    covers = false
                    break
                end
            end
            if covers then best = candidate end
        end
        for i = start, #boundary do
            subset[#subset + 1] = boundary[i]
            search(i + 1)
            subset[#subset] = nil
        end
    end
    search(1)
    return best
end

local function enclosingCenter(points)
    for i = #points, 2, -1 do
        local j = math.random(i)
        points[i], points[j] = points[j], points[i]
    end

    -- Only recurse when a point must join the boundary, so depth is at most four.
    local boundary = {}
    local function enclose(count)
        local sphere = boundarySphere(boundary)
        if #boundary == 4 then return sphere end
        for i = 1, count do
            local point = points[i]
            if not encloses(sphere, point) then
                boundary[#boundary + 1] = point
                sphere = enclose(i - 1)
                boundary[#boundary] = nil
            end
        end
        return sphere
    end

    return enclose(#points).center + blockCenter
end

local function labelRotation(center, eye)
    local delta = eye - center
    local horizontal = math.sqrt(delta.x * delta.x + delta.z * delta.z)
    local yaw = horizontal == 0 and 0 or math.deg(math.atan2(delta.x, delta.z))
    local pitch = delta.y == 0 and 0 or -math.deg(math.atan2(delta.y, horizontal))
    return pitch % 360, yaw % 360
end

local function drawDeposit(points, target, eye)
    for _, pos in ipairs(points) do
        local center = pos + blockCenter
        local box = overlay.createBox({
            x = center.x, y = center.y, z = center.z,
            sizeX = 1, sizeY = 1, sizeZ = 1,
            color = target[2], opacity = 0.35,
            depthTest = false, depthMask = false,
        })
        markerIds[#markerIds + 1] = box.getId()
    end

    local center = enclosingCenter(points)
    local pitch, yaw = labelRotation(center, eye)
    local label = overlay.createText({
        x = center.x, y = center.y, z = center.z,
        rotX = pitch, rotY = yaw,
        content = target[1], color = target[2],
        center = true, fontSize = 0.05, shadow = true,
        depthTest = false, depthMask = false, culling = false,
    })
    markerIds[#markerIds + 1] = label.getId()
    labels[#labels + 1] = { object = label, center = center, pitch = pitch, yaw = yaw }
end

local function clearMarkers()
    for _, id in ipairs(markerIds) do overlay.removeObject(id) end
    markerIds = {}
    labels = {}
end

local function getDimension()
    if type(glasses.getOwner) == "function" then
        local owner = glasses.getOwner()
        if owner and type(owner.dimension) == "string" then return owner.dimension end
    end

    local detector = peripheral.find("environment_detector")
    if detector and type(detector.getDimension) == "function" then
        local dimension = detector.getDimension()
        if type(dimension) == "string" then return dimension end
    end

    return unknownDimension
end

local function memoryFile(dimension)
    if dimension == unknownDimension then return "mining-memory-unknown.json" end
    return memoryPath
end

local function loadMemory(dimension)
    if memoryLoaded then return end
    memoryLoaded = true
    local path = memoryFile(dimension)
    if not fs.exists(path) then return end

    local file = fs.open(path, "r")
    if not file then return end
    local content = file.readAll()
    file.close()
    local ok, data = pcall(textutils.unserializeJSON, content)
    if not ok or type(data) ~= "table" or data.dimension ~= dimension
        or type(data.blocks) ~= "table" then return end

    for _, block in ipairs(data.blocks) do
        if type(block) == "table" and targets[block.id]
            and type(block.x) == "number" and block.x == math.floor(block.x)
            and type(block.y) == "number" and block.y == math.floor(block.y)
            and type(block.z) == "number" and block.z == math.floor(block.z)
            and math.abs(block.x) <= 30000000 and math.abs(block.y) <= 30000000
            and math.abs(block.z) <= 30000000 then
            local pos = vector.new(block.x, block.y, block.z)
            remembered[key(pos)] = { pos = pos, id = block.id, target = targets[block.id] }
        end
    end
end

local function saveMemory()
    local blocks = {}
    for _, hit in pairs(remembered) do
        blocks[#blocks + 1] = { x = hit.pos.x, y = hit.pos.y, z = hit.pos.z, id = hit.id }
    end
    local ok, err = pcall(function()
        local file = assert(fs.open(memoryFile(memoryDimension), "w"), "Cannot open memory file")
        file.write(textutils.serializeJSON({ dimension = memoryDimension, blocks = blocks }))
        file.close()
    end)
    if not ok then print("Could not save scan memory: " .. tostring(err)) end
end

local function drawMemory(eye)
    -- Group a copy so flood filling does not consume the saved blocks.
    local targetsByPosition = {}
    for index, hit in pairs(remembered) do targetsByPosition[index] = hit end

    clearMarkers()
    for index, hit in pairs(remembered) do
        if targetsByPosition[index] then
            local points = { hit.pos }
            targetsByPosition[index] = nil
            local i = 1
            while i <= #points do
                for _, direction in ipairs(directions) do
                    local neighbor = points[i] + direction
                    local neighborIndex = key(neighbor)
                    local nextHit = targetsByPosition[neighborIndex]
                    if nextHit and nextHit.target == hit.target then
                        targetsByPosition[neighborIndex] = nil
                        points[#points + 1] = neighbor
                    end
                end
                i = i + 1
            end
            drawDeposit(points, hit.target, eye)
        end
    end
    if not overlay.isAutoUpdating() then overlay.update() end
end

local function scan()
    if not glasses.isEquipped() then return end

    local dimension = getDimension()
    if dimension ~= memoryDimension then
        remembered = {}
        memoryLoaded = false
    end
    memoryDimension = dimension
    loadMemory(dimension)

    local eye = vector.new(overlay.getEyePosition())
    local blocks, err = scanner.scanBlocks(scanRadius)
    local origin = vector.new(math.floor(eye.x), math.floor(eye.y), math.floor(eye.z))
    for index, hit in pairs(remembered) do
        local delta = hit.pos - origin
        local inScan = math.abs(delta.x) <= scanRadius
            and math.abs(delta.y) <= scanRadius and math.abs(delta.z) <= scanRadius
        if lengthSquared(hit.pos + blockCenter - eye) > memoryRadiusSquared
            or (blocks and inScan) then
            remembered[index] = nil
        end
    end

    if blocks then
        for _, block in ipairs(blocks) do
            local id = block.name:gsub(":deepslate_", ":")
            local target = targets[id]
            if target then
                local pos = vector.new(math.floor(eye.x + block.x),
                    math.floor(eye.y + block.y), math.floor(eye.z + block.z))
                if lengthSquared(pos + blockCenter - eye) <= memoryRadiusSquared then
                    remembered[key(pos)] = { pos = pos, id = id, target = target }
                end
            end
        end
    else
        print(err or "Scan failed")
    end

    saveMemory()
    drawMemory(eye)
end

local function faceLabels()
    if #labels == 0 or not glasses.isEquipped() then return end

    if getDimension() ~= memoryDimension then
        clearMarkers()
        return
    end
    local eye = vector.new(overlay.getEyePosition())
    for _, label in ipairs(labels) do
        local pitch, yaw = labelRotation(label.center, eye)
        if pitch ~= label.pitch then
            label.object.setRotX(pitch)
            label.pitch = pitch
        end
        if yaw ~= label.yaw then
            label.object.setRotY(yaw)
            label.yaw = yaw
        end
    end

    if not overlay.isAutoUpdating() then overlay.update() end
end

print("Press the Smart Glasses hotkey to scan.")
local timer
while true do
    local event, value = os.pullEventRaw()
    if event == "terminate" then
        clearMarkers()
        break
    elseif event == "glasses_key_pressed" then
        scan()
        if #labels > 0 and not timer then timer = os.startTimer(0.1) end
    elseif event == "timer" and value == timer then
        faceLabels()
        timer = #labels > 0 and os.startTimer(0.1) or nil
    end
end
