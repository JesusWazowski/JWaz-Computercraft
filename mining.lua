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
    ["minecraft:chest"] = { "Chest", 0xFF9D36 },
    ["minecraft:trapped_chest"] = { "Trapped Chest", 0xFF6655 },
    ["minecraft:ender_chest"] = { "Ender Chest", 0x67D9BC },
}

local directions = {
    vector.new(1, 0, 0), vector.new(-1, 0, 0),
    vector.new(0, 1, 0), vector.new(0, -1, 0),
    vector.new(0, 0, 1), vector.new(0, 0, -1),
}
local blockCenter = vector.new(0.5, 0.5, 0.5)
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

local function scan()
    if not glasses.isEquipped() then return end

    local eye = vector.new(overlay.getEyePosition())
    local blocks, err = scanner.scanBlocks(8)
    if not blocks then
        print(err or "Scan failed")
        return
    end

    local targetsByPosition = {}
    local hits = {}
    for _, block in ipairs(blocks) do
        local id = block.name:gsub(":deepslate_", ":")
        local target = targets[id]
        if target then
            -- World block centers are at integer coordinates plus 0.5.
            local pos = vector.new(math.floor(eye.x + block.x),
                math.floor(eye.y + block.y), math.floor(eye.z + block.z))
            local index = key(pos)
            if not targetsByPosition[index] then
                local hit = { pos = pos, target = target }
                targetsByPosition[index] = hit
                hits[#hits + 1] = hit
            end
        end
    end

    clearMarkers()
    for _, hit in ipairs(hits) do
        if targetsByPosition[key(hit.pos)] then
            local points = { hit.pos }
            targetsByPosition[key(hit.pos)] = nil
            local i = 1
            while i <= #points do
                for _, direction in ipairs(directions) do
                    local neighbor = points[i] + direction
                    local index = key(neighbor)
                    local nextHit = targetsByPosition[index]
                    if nextHit and nextHit.target == hit.target then
                        targetsByPosition[index] = nil
                        points[#points + 1] = neighbor
                    end
                end
                i = i + 1
            end
            drawDeposit(points, hit.target, eye)
        end
    end
end

local function faceLabels()
    if #labels == 0 or not glasses.isEquipped() then return end

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
