local scanner = assert(peripheral.find("geo_scanner"), "Install a Geo Scanner")
local overlay = assert(smartglasses.modules["advancedperipherals:overlay"],
    "Install the Overlay Module")
assert(smartglasses.modules["advancedperipherals:hotkey"],
    "Install the Hotkey Module")

local ores = {
    diamond_ore = { "Diamond", 0x44E8F5 },
    iron_ore    = { "Iron",    0xD8AE91 },
    gold_ore    = { "Gold",    0xFFCD35 },
    redstone_ore = { "Redstone", 0xFF4040 },
}

local markers = {}

local function scan()
    if not smartglasses.isEquipped() then return end

    local ex, ey, ez = overlay.getEyePosition()
    local blocks, err = scanner.scanBlocks(8)
    if not blocks then
        print(err or "Scan failed")
        return
    end

    for _, id in ipairs(markers) do overlay.removeObject(id) end
    markers = {}

    for _, block in ipairs(blocks) do
        local name = block.name:match("^minecraft:(.+)$")
        local ore = name and ores[(name:gsub("^deepslate_", ""))]
        if ore then
            local x, y, z = ex + block.x, ey + block.y, ez + block.z

            local box = overlay.createBox({
                x = x, y = y, z = z,
                sizeX = 1, sizeY = 1, sizeZ = 1,
                relativePosition = false,
                color = ore[2], opacity = 0.35,
                depthTest = false, depthMask = false,
            })
            local label = overlay.createText({
                x = x, y = y + 0.6, z = z,
                gui = false, relativePosition = false,
                content = ore[1], color = ore[2],
                center = true, fontSize = 0.025,
                depthTest = false, culling = false,
            })

            markers[#markers + 1] = box.getId()
            markers[#markers + 1] = label.getId()
        end
    end
end

print("Press the Smart Glasses hotkey to scan.")
while true do
    os.pullEvent("glasses_key_pressed")
    scan()
end
