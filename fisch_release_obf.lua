local Players     = game:GetService("Players")
local RunService  = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local Workspace   = game:GetService("Workspace")
local function getLP() return Players.LocalPlayer end



-- validation
if _G.FischMacro then pcall(function() _G.FischMacro.unload() end) end
local FM = { conns = {}, drawings = {}, dead = false }
_G.FischMacro = FM
function FM.track(c) FM.conns[#FM.conns + 1] = c; return c end
function FM.draw(kind)
    local d = Drawing.new(kind)
    FM.drawings[#FM.drawings + 1] = d
    return d
end
function FM.unload()
    FM.dead = true
    pcall(function() if FM.lib and FM.lib.Unload then FM.lib:Unload() end end) 
    for _, c in ipairs(FM.conns) do pcall(function() c:Disconnect() end) end
    for _, d in ipairs(FM.drawings) do pcall(function() d:Remove() end) end
    pcall(function() mouse1release() end)
end

if type(setrobloxinput) == "function" then setrobloxinput(true) end
pcall(function() mouse1release() end)   -- release anything stuck from a crash
pcall(function() mouse2release() end)

if type(memory_read) ~= "function" then
    notify("Enable Unsafe LuaU in Matcha settings.", "Fisch Macro", 6)
end


local WEBHOOK_URL_FILE = "webhook_url.txt"
local function loadWebhookUrl()
    local url = ""
    pcall(function()
        if isfile(WEBHOOK_URL_FILE) then
            local s = tostring(readfile(WEBHOOK_URL_FILE) or ""):gsub("%s", "")
            if s ~= "" then url = s end
        else
            writefile(WEBHOOK_URL_FILE, "")  
        end
    end)
    return url
end



local CONFIG = {
    -- manual assists (only active while Auto Fish is OFF)
    auto_cast            = false,
    auto_shake           = false,
    auto_reel            = false,

    -- casting
    cast_mode            = "short",  -- "short" "long" "custom"
    cast_short_max_ms    = 300,     -- short mode: release after this hold time 
    cast_power_custom    = 96.0,
    cast_timeout_ms      = 15000,
    cast_stall_ms        = 2500,
    cast_reinit_hold_ms  = 250,     -- mouse-up window before pressing, so the press is a fresh edge
    cast_frozen_ms       = 600,     -- raw power bar frozen this long -> treat as released
    cast_nobar_ms        = 4000,    -- no power bar at all -> restart the cycle
    cast_on_timeout      = true,
    pre_cast_delay_ms    = 0,
    post_cast_delay_ms   = 200,
    post_catch_delay_ms  = 2500,    -- wait after a CATCH before recasting. Must outlast the catch
    post_lost_delay_ms   = 800,     -- wait after a LOST fish (no catch animation to sit out)
    reel_stale_lockout_ms = 700,    -- after a reel closes, ignore its lingering frames this long

    -- equip
    auto_equip           = true,
    equip_autodetect     = true,
    equip_slot           = 1,
    equip_settle_ms      = 350,

    -- shake
    shake_interval_ms    = 25,

    -- reel controller 
    proportional_gain    = 0.42,
    derivative_gain      = 0.55,
    velocity_damping     = 38.0,
    neutral_duty_cycle   = 0.50,
    prediction_strength  = 7.5,
    close_threshold      = 0.01,
    edge_boundary        = 0.10,
    completion_threshold = 90,      -- progress % at reel close that counts as a catch
    reel_input_stop_pct  = 99,      -- progress % where the reel is effectively won


    -- instant reel (setgc patch)
    instant_reel_speed   = 10,

    -- waypoint ESP
    wp_show_on_load      = false,
    wp_include_fishing   = false,
    wp_square_size       = 8,
    wp_text_size         = 14,
    wp_show_distance     = true,
    wp_max_distance      = 0,    

    -- treasure chest ESP (chests spawn/despawn -> re-scanned on a timer)
    chest_show_on_load   = false,
    chest_square_size    = 10,
    chest_text_size      = 14,
    chest_show_distance  = true,
    chest_max_distance   = 0,
    chest_rescan_ms      = 1500,

    -- teleport
    tp_speed             = 250,     -- tween speed

    -- watchdog w zerodeath
    watchdog_enabled     = true,
    watchdog_stall_ms    = 20000,

    -- status HUD -- fucking useless
    hud_show_on_load     = false,
    hud_x                = 16,
    hud_y                = 170,
    hud_text_size        = 15,

    -- webhook 
    webhook_enabled      = false,
    webhook_url          = loadWebhookUrl(),
    webhook_on_start     = true,
    webhook_stats        = true,
    webhook_interval_s   = 300,

    -- offsets
    offsets_auto         = true,
    offsets_url          = "https://offsets.imtheo.lol/offsets.hpp",
    autostart            = false,
    debug_logging        = false,
}

local OFFSETS = {
    Name                       = 0x98,
    ClassDescriptor            = 0x18,
    ClassDescriptorToClassName = 0x8,
    Children                   = 0x70,
    Parent                     = 0x68,
    StringLength               = 0x10,
    TextLabelVisible           = 0x5ad,
    FrameVisible               = 0x5ad,
    ScreenGuiEnabled           = 0x4c4,
    FramePositionX             = 0x510,
    FrameSizeX                 = 0x530,
    GuiObjectRotation          = 0x178,
    TextLabelText              = 0xda0,
}

local function parseOffsetsHpp(body)
    if type(body) ~= "string" or body == "" then return nil end
    local map = {
        ["GuiObject.Position"]          = { "FramePositionX" },
        ["GuiObject.Size"]              = { "FrameSizeX" },
        ["GuiObject.Visible"]           = { "FrameVisible", "TextLabelVisible" },
        ["GuiObject.Rotation"]          = { "GuiObjectRotation" },
        ["GuiObject.ScreenGui_Enabled"] = { "ScreenGuiEnabled" },
        ["ScreenGui.Enabled"]           = { "ScreenGuiEnabled" },
        ["TextLabel.Text"]              = { "TextLabelText" },
        ["Instance.Name"]               = { "Name" },
        ["Instance.ChildrenStart"]      = { "Children" },
        ["Instance.Parent"]             = { "Parent" },
    }
    local current, n = nil, 0
    for line in (body .. "\n"):gmatch("([^\n]*)\n") do
        local ns = line:match("namespace%s+([%w_]+)%s*{")
        if ns then current = ns end
        local member, hex = line:match("uintptr_t%s+([%w_]+)%s*=%s*(0x[0-9a-fA-F]+)")
        if member and hex then
            local keys = map[(current or "") .. "." .. member]
            local val = keys and tonumber(hex)
            if val then for _, k in ipairs(keys) do OFFSETS[k] = val; n = n + 1 end end
        end
    end
    return n
end

if CONFIG.offsets_auto and type(httpget) == "function" then
    local ok, body = pcall(httpget, CONFIG.offsets_url)
    local n = ok and parseOffsetsHpp(body) or nil
    if not (n and n > 0) then warn("[FM] offset fetch/parse failed, using defaults") end
end

pcall(function()
    if isfile("fisch_offsets.json") then
        local parsed = HttpService:JSONDecode(readfile("fisch_offsets.json"))
        for k, v in pairs(parsed) do
            if OFFSETS[k] ~= nil and type(v) == "number" then OFFSETS[k] = v end
        end
        print("[FM] offsets overridden from fisch_offsets.json")
    end
end)


-- memory reading shit :(
local function readPtr(addr)
    if not addr or addr <= 4096 then return nil end
    local ok, v = pcall(memory_read, "uintptr_t", addr)
    v = ok and tonumber(v) or nil
    return (v and v > 4096) and v or nil
end
local function readFloat(addr)
    if not addr or addr <= 4096 then return 0.0 end
    local ok, v = pcall(memory_read, "float", addr)
    return (ok and tonumber(v)) or 0.0
end
local function readInt(addr)
    if not addr or addr <= 4096 then return 0 end
    local ok, v = pcall(memory_read, "int32", addr)
    if not ok then ok, v = pcall(memory_read, "int", addr) end
    return (ok and tonumber(v)) or 0
end
local function readByte(addr)
    if not addr or addr <= 4096 then return 0 end
    local ok, v = pcall(memory_read, "byte", addr)
    return (ok and tonumber(v)) or 0
end
local function instAddr(inst)
    if not inst then return nil end
    local ok, a = pcall(function() return inst.Address end)
    a = (ok and a) and tonumber(a) or nil
    return (a and a > 4096) and a or nil
end

-- GuiObject Position/Size UDim2 straight from memory.
local function readFramePos(frame)
    local a = instAddr(frame); if not a then return 0, 0, 0, 0 end
    local base = a + OFFSETS.FramePositionX
    return readFloat(base + 0x0), readInt(base + 0x4), readFloat(base + 0x8), readInt(base + 0xC)
end
local function readFrameSize(frame)
    local a = instAddr(frame); if not a then return 0, 0, 0, 0 end
    local base = a + OFFSETS.FrameSizeX
    return readFloat(base + 0x0), readInt(base + 0x4), readFloat(base + 0x8), readInt(base + 0xC)
end

local function isScreenGuiEnabled(gui)
    if not gui then return false end
    local ok, v = pcall(function() return gui.Enabled end)
    if ok and type(v) == "boolean" then return v end
    local a = instAddr(gui); if not a then return true end
    return readByte(a + OFFSETS.ScreenGuiEnabled) ~= 0
end

local function readMemString(strAddr)
    if not strAddr then return "" end
    local len = readInt(strAddr + OFFSETS.StringLength)
    if len <= 0 or len > 1000 then return "" end
    local dataAddr = strAddr
    if len > 15 then dataAddr = readPtr(strAddr) end   -- long strings are heap pointers
    if not dataAddr then return "" end
    local ok, s = pcall(memory_read, "string", dataAddr)
    return (ok and type(s) == "string") and s or ""
end

local function readGuiText(inst)
    if not inst then return "" end
    local ok, v = pcall(function() return inst.Text end)
    if ok and type(v) == "string" and v ~= "" then return v end
    local a = instAddr(inst)
    return a and readMemString(a + OFFSETS.TextLabelText) or ""
end

local function finite(v, lo, hi)
    if type(v) ~= "number" then return false end
    if v ~= v or v == math.huge or v == -math.huge then return false end
    if lo and v < lo then return false end
    if hi and v > hi then return false end
    return true
end

local function dbg(...) if CONFIG.debug_logging then print("[FM]", ...) end end

local function findChild(parent, name)
    if not parent then return nil end
    local ok, v = pcall(parent.FindFirstChild, parent, name)
    return ok and v or nil
end
local function getChildren(inst)
    if not inst then return {} end
    local ok, v = pcall(inst.GetChildren, inst)
    return (ok and v) or {}
end
local function getPlayerGui()
    local lp = getLP(); if not lp then return nil end
    return lp:FindFirstChildOfClass("PlayerGui") or findChild(lp, "PlayerGui")
end

-- A stale character model can share the player's name after a respawn, so
-- return every candidate and let callers search them all.
local function getCharacterModels()
    local lp = getLP(); if not lp then return {} end
    local out, seen = {}, {}
    local function add(m) if m and not seen[m] then seen[m] = true; out[#out + 1] = m end end
    add(lp.Character)
    add(findChild(Workspace, lp.Name))
    return out
end

local function getHRP()
    local lp = getLP()
    local char = lp and (lp.Character or findChild(Workspace, lp.Name))
    return char and findChild(char, "HumanoidRootPart")
end

local function selfPos()
    local hrp = getHRP()
    local ok, pos = pcall(function() return hrp and hrp.Position end)
    return ok and pos or nil
end

local function robloxActive()
    if type(isrbxactive) ~= "function" then return true end
    local ok, v = pcall(isrbxactive)
    return (not ok) or (v ~= false)
end

-- for input (enter and mouse)
local VK = { Enter = 0x0D, E = 0x45 }

local function tapKey(vk, holdMs)
    keypress(vk)
    task.spawn(function()
        wait((holdMs or 25) / 1000)
        keyrelease(vk)
    end)
end

local State 
local mouseHeld = false
local mousePressAssertAt = 0
local PRESS_REASSERT_MS = 110  
local _reeling = false
local _reelClosedAt = 0     
local _irApplied = false     -- for instant reel


local function holdMouse()
    if mouseHeld then
        if _reeling and (tick() * 1000 - mousePressAssertAt) >= PRESS_REASSERT_MS then
            mouse1press(); mousePressAssertAt = tick() * 1000
        end
        return
    end
    mouse1press(); mouseHeld = true; mousePressAssertAt = tick() * 1000
    if State and State.phase == "CASTING" then State.castPresses = (State.castPresses or 0) + 1 end
    if CONFIG.debug_logging then
        print("[FM] MOUSE DOWN  phase=" .. tostring(State and State.phase) .. (_reeling and "  (reel)" or ""))
    end
end

local function releaseMouse()
    if not mouseHeld then return end
    mouse1release(); mouseHeld = false
    if State and State.phase == "CASTING" then State.castReleases = (State.castReleases or 0) + 1 end
    if CONFIG.debug_logging then
        print("[FM] MOUSE UP    phase=" .. tostring(State and State.phase) .. (_reeling and "  (reel)" or ""))
    end
end

-- barely functions
local function getEquippedToolName()
    for _, char in ipairs(getCharacterModels()) do
        for _, c in ipairs(getChildren(char)) do
            if c.ClassName == "Tool" then return c.Name end
        end
    end
    return ""
end
local function isRodEquipped() return getEquippedToolName() ~= "" end

local function vkForSlot(s)
    s = tostring(s or "")
    local n = tonumber(s)
    if n and n >= 0 and n <= 9 then return 0x30 + n end
    if #s == 1 then
        local b = s:upper():byte()
        if b >= 65 and b <= 90 then return b end
    end
    return nil
end

-- i farted but this is for detecting the rod
local function findRodSlotKey()
    local pg = getPlayerGui()
    local hotbar = pg and findChild(findChild(pg, "backpack"), "hotbar")
    for _, slot in ipairs(getChildren(hotbar)) do
        if slot.ClassName == "ImageButton" and slot.Name == "ItemTemplate" then
            local nm = readGuiText(findChild(slot, "ItemName")):gsub("<[^>]+>", ""):lower()
            if nm:find("rod") or nm:find("waraxe") then
                for _, c in ipairs(getChildren(slot)) do
                    if c.ClassName == "TextLabel" then
                        local t = readGuiText(c):gsub("%s+", "")
                        if #t == 1 then return t end
                    end
                end
            end
        end
    end
    return nil
end

local function equipRod()
    if isRodEquipped() then return false end
    local key = CONFIG.equip_autodetect and findRodSlotKey() or nil
    local vk = vkForSlot((key and key ~= "") and key or CONFIG.equip_slot)
    if vk then tapKey(vk, 25); return true end
    return false
end

-- find reel gui 
local function getReelGui()
    local pg = getPlayerGui()
    return pg and findChild(pg, "reel")
end

local function isGuiVisible(inst)
    if not inst then return false end
    local ok, v = pcall(function() return inst.Visible end)
    if ok and type(v) == "boolean" then return v end
    local a = instAddr(inst); if not a then return true end
    return readByte(a + OFFSETS.FrameVisible) ~= 0
end

-- shake detection logic
local function shakeActive()
    if (tick() * 1000 - _reelClosedAt) < CONFIG.reel_stale_lockout_ms then return false end
    local pg = getPlayerGui(); if not pg then return false end
    local gui = findChild(pg, "shakeui")
    if not gui or not isScreenGuiEnabled(gui) then return false end
    local safe = findChild(gui, "safezone"); if not safe then return false end
    local btn  = findChild(safe, "button");  if not btn then return false end
    local ok, cls = pcall(function() return btn.ClassName end)
    return ok and cls == "ImageButton" and isGuiVisible(safe) and isGuiVisible(btn)
end

local _reelCache = { bar = nil, fish = nil, playerbar = nil }
local function parentIs(child, parent)
    if not child or not parent then return false end
    local ok, p = pcall(function() return child.Parent end)
    return ok and p == parent
end

-- extra validation for autofishing (if no gui then no fish)
local function getReelBarContext()
    local reel = getReelGui()
    if not reel or not isScreenGuiEnabled(reel) then
        _reelCache.bar, _reelCache.fish, _reelCache.playerbar = nil, nil, nil
        return nil
    end
    if _reelCache.bar and not (parentIs(_reelCache.bar, reel)
        and parentIs(_reelCache.fish, _reelCache.bar)
        and parentIs(_reelCache.playerbar, _reelCache.bar)) then
        _reelCache.bar, _reelCache.fish, _reelCache.playerbar = nil, nil, nil
    end
    if _reelCache.bar then return _reelCache end
    local bar = findChild(reel, "bar"); if not bar then return nil end
    local fish, pbar = findChild(bar, "fish"), findChild(bar, "playerbar")
    if not (fish and pbar) then return nil end
    _reelCache.bar, _reelCache.fish, _reelCache.playerbar = bar, fish, pbar
    return _reelCache
end

local function hasActiveFishingContext(ctx)
    ctx = ctx or getReelBarContext()
    return ctx ~= nil
end

-- Fisch tears the reel frames down a beat AFTER a catch, so right after a reel
-- closes they linger and read as a live reel. Trusting that bounced the
-- post-catch phases into REELING and clicked the dead minigame (the stray
-- post-catch click). This suppresses the reel for reel_stale_lockout_ms after
-- the last close; a genuine reel needs a fresh cast + bite, always past that.
-- updateReeling keeps using the raw context so real reeling stays responsive.
local function reelContextActive()
    if not getReelBarContext() then return false end
    return (tick() * 1000 - _reelClosedAt) >= CONFIG.reel_stale_lockout_ms
end

-- power/progress read state (grouped in one table — register budget)
local PW = { baseline = {}, active = {}, cacheVal = nil, cacheAt = 0, lastRaw = -1,
             progVal = nil, progAt = 0 }

local function getFishingCompletionPercent()
    local reel = getReelGui()
    local bar = reel and (_reelCache.bar or findChild(reel, "bar"))
    local pb = bar and findChild(findChild(bar, "progress"), "bar")
    if pb then
        local x = readFrameSize(pb)
        if finite(x, -0.05, 1.5) then
            local p = math.max(0.0, math.min(100.0, x * 100.0))
            PW.progVal, PW.progAt = p, tick() * 1000
            return p
        end
    end
    if PW.progVal and (tick() * 1000 - PW.progAt) <= 500 then return PW.progVal end
    return nil
end

-- BFS for every Frame named `name` under root (bounded)
local function collectFramesNamed(root, name)
    local out, queue, head = {}, { root }, 1
    while head <= #queue and head <= 4096 do
        local cur = queue[head]; head = head + 1
        for _, c in ipairs(getChildren(cur)) do
            if c.Name == name and c.ClassName == "Frame" then out[#out + 1] = c end
            queue[#queue + 1] = c
        end
    end
    return out
end

local function resolvePowerBars()
    local bars = {}
    for _, char in ipairs(getCharacterModels()) do
        local powerGui = findChild(findChild(char, "HumanoidRootPart"), "power")
        if powerGui then
            for _, b in ipairs(collectFramesNamed(powerGui, "bar")) do bars[#bars + 1] = b end
        end
    end
    return bars
end

-- Only a bar that CLIMBS from its cast-start baseline is the real charge — a
-- leftover bar from the last cast drains and would falsely read high.
local function readPowerBarPercent()
    local best, rawMax = nil, -1
    for _, b in ipairs(resolvePowerBars()) do
        local _, _, sy = readFrameSize(b)
        if finite(sy, -0.05, 1.5) then
            local p = math.max(0.0, math.min(100.0, sy * 100.0))
            if p > rawMax then rawMax = p end
            local a = instAddr(b) or 0
            if PW.baseline[a] == nil then PW.baseline[a] = p end
            if (p - PW.baseline[a]) > 1.0 then PW.active[a] = true end
            if PW.active[a] and (not best or p > best) then best = p end
        end
    end
    PW.lastRaw = rawMax
    if best then PW.cacheVal, PW.cacheAt = best, tick() * 1000; return best end
    if PW.cacheVal and (tick() * 1000 - PW.cacheAt) <= 400 then return PW.cacheVal end
    return nil
end

-- Power % to release at ("short" mode is time-based and never reaches this)
local function resolveCastThreshold()
    if CONFIG.cast_mode == "custom" then
        return math.max(1.0, math.min(100.0, (CONFIG.cast_power_custom or 96) + 0.0))
    end
    return 90.0
end

-- spam reel
local Controller = {}
Controller.__index = Controller
function Controller.new()
    return setmetatable({ lastPlayerbarPos = nil, lastFishPos = nil, pwmAcc = 0.0 }, Controller)
end
function Controller:reset()
    self.lastPlayerbarPos, self.lastFishPos, self.pwmAcc = nil, nil, 0.0
end
function Controller:metrics(ctx)
    ctx = ctx or getReelBarContext()
    if not ctx then return nil end
    local fishCenter = readFramePos(ctx.fish) + (readFrameSize(ctx.fish) / 2)
    local barCenter  = readFramePos(ctx.playerbar)
    if not finite(fishCenter, -0.5, 1.5) or not finite(barCenter, -0.5, 1.5) then return nil end
    return fishCenter, barCenter
end
function Controller:run(ctx)
    local fishPos, playerbarPos = self:metrics(ctx)
    if not fishPos then releaseMouse(); return end

    if self.lastPlayerbarPos == nil then self.lastPlayerbarPos = playerbarPos end
    if self.lastFishPos == nil then self.lastFishPos = fishPos end
    local playerbarVel = playerbarPos - self.lastPlayerbarPos
    local fishVel = fishPos - self.lastFishPos
    self.lastPlayerbarPos, self.lastFishPos = playerbarPos, fishPos

    local err  = fishPos - playerbarPos
    local edge = CONFIG.edge_boundary
    if playerbarPos < edge     then holdMouse();    return end
    if playerbarPos > 1 - edge then releaseMouse(); return end

    -- hard correction when we won't overshoot
    local predictedErr  = fishPos - (playerbarPos + playerbarVel * CONFIG.prediction_strength)
    local close         = CONFIG.close_threshold
    local sameSideAfter = (err * predictedErr) > 0
    local approaching   = (err * playerbarVel) > 0
    local remaining     = math.max(0.0, math.abs(err) - close)
    local brake         = math.abs(playerbarVel) * 8
    local needsPreSlow  = approaching and (brake >= remaining)

    if math.abs(err) > close and sameSideAfter and not needsPreSlow then
        if err > 0 then holdMouse() else releaseMouse() end
        return
    end

    local neutral = CONFIG.neutral_duty_cycle
    local targetDuty
    if needsPreSlow and brake > 0 then
        local urgency = 1.0 - math.min(1.0, remaining / brake)
        targetDuty = (err > 0) and neutral * (1.0 - urgency)
                                or neutral + ((1.0 - neutral) * urgency)
    else
        local adj = (CONFIG.proportional_gain * err)
                  + (CONFIG.derivative_gain   * fishVel)
                  - (CONFIG.velocity_damping  * playerbarVel)
        targetDuty = math.max(0.0, math.min(1.0, neutral + adj))
    end

    self.pwmAcc = self.pwmAcc + targetDuty
    if self.pwmAcc >= 1.0 then self.pwmAcc = self.pwmAcc - 1.0; holdMouse()
    else releaseMouse() end
end

local ctrl = Controller.new()

State = {
    running = false, phase = "IDLE", rod = "",
    caught = 0, lost = 0, timeouts = 0, recoveries = 0,
    powerPct = "", progressPct = "",
    wdSig = "", wdSignalAt = 0,
    castStartedAt = 0, castReleasedAt = 0, castBarSeen = false, justEquipped = false,
    castThreshold = 90.0, chargeLastPct = 0, chargeMotionAt = 0, castReleaseUntil = 0,
    castHoldAt = 0, frozenSince = 0, frozenRawVal = 0,
    lastShakedAt = 0, doneAt = 0,
    fishingLostAt = 0, completionReached = false, lastProgress = 0, maxProgress = 0,
    outcomeResolved = false, lastReelCaught = false,  
    shookCount = 0, castPresses = 0, castReleases = 0,
    assistState = "idle", assistReleased = false, assistShakeAt = 0, assistChargeAt = 0,
}

local PHASE_LABEL = { IDLE = "idle", CASTING = "casting", SHAKE = "shaking",
                      REELING = "reeling", DONE = "done" }

local function anyAssist()
    return CONFIG.auto_cast or CONFIG.auto_shake or CONFIG.auto_reel
end

local function resetCycleState()
    State.castStartedAt = 0; State.castReleasedAt = 0; State.castBarSeen = false
    State.chargeLastPct = 0; State.chargeMotionAt = 0; State.castReleaseUntil = 0
    State.castHoldAt = 0; State.frozenSince = 0; State.frozenRawVal = 0
    State.lastShakedAt = 0; State.doneAt = 0
    State.fishingLostAt = 0; State.completionReached = false
    State.lastProgress = 0; State.maxProgress = 0; State.outcomeResolved = false
    State.powerPct = ""; State.progressPct = ""
    State.shookCount = 0; State.castPresses = 0; State.castReleases = 0
    PW.baseline = {}; PW.active = {}; PW.cacheVal = nil; PW.lastRaw = -1
    _reeling = false
    _irApplied = false   -- cleared at cycle start only the IR watcher re-arms mid-reel
end

local function decideStartPhase()
    if reelContextActive() then return "REELING" end
    if shakeActive() then return "SHAKE" end
    return "CASTING"
end

local function startCycle()
    State.rod = getEquippedToolName()
    ctrl:reset()
    releaseMouse()
    resetCycleState()
    State.castThreshold = resolveCastThreshold()
    local ph = decideStartPhase()
    if ph == "CASTING" then
        State.castStartedAt = tick() * 1000
        State.castReleaseUntil = State.castStartedAt + CONFIG.cast_reinit_hold_ms
        if CONFIG.auto_equip and equipRod() then State.justEquipped = true end
    elseif ph == "SHAKE" then
        State.castReleasedAt = tick() * 1000  
    else
        State.fishingLostAt = 0
    end
    State.phase = ph
end

local function stopCycle(nextPhase)
    releaseMouse(); ctrl:reset(); resetCycleState()
    State.phase = nextPhase or "IDLE"
end

local function recordOutcome()
    if State.outcomeResolved then return end
    State.outcomeResolved = true
    State.lastReelCaught = State.completionReached 
    if State.completionReached then State.caught = State.caught + 1
    else State.lost = State.lost + 1 end
end

local FISHING_GRACE_MS = 100
local function endFishingOutcome()
    if State.fishingLostAt == 0 then State.fishingLostAt = tick() * 1000 end
    if (tick() * 1000 - State.fishingLostAt) >= FISHING_GRACE_MS then
        _reelClosedAt = tick() * 1000  
        recordOutcome(); stopCycle("DONE")
    end
end

-- Casting
local function updateCasting()
    State.progressPct = ""
    local now = tick() * 1000
    if not mouseHeld then
        if reelContextActive() then State.fishingLostAt = 0; State.phase = "REELING"; return end
        if shakeActive() then
            State.lastShakedAt = 0
            -- no cast happened: stamp the baseline or SHAKE's recast timeout never runs
            if State.castReleasedAt == 0 then State.castReleasedAt = now end
            State.phase = "SHAKE"
            return
        end
    elseif CONFIG.debug_logging and (reelContextActive() or shakeActive()) then
        dbg("suppressed stale reel/shake mid-charge (prevented stray click)")
    end

    local settle = CONFIG.pre_cast_delay_ms
    if State.justEquipped then settle = math.max(settle, CONFIG.equip_settle_ms) end
    if settle > 0 and State.castStartedAt ~= 0 and (now - State.castStartedAt) < settle then return end
    State.justEquipped = false
    if now < State.castReleaseUntil then releaseMouse(); pcall(mouse1release); return end

    holdMouse()
    if State.castStartedAt == 0 then State.castStartedAt = now end
    if State.castHoldAt == 0 then State.castHoldAt = now end

    if CONFIG.cast_mode == "short" then
        State.powerPct = "---"
        if (now - State.castHoldAt) >= CONFIG.cast_short_max_ms then
            releaseMouse(); State.castReleasedAt = now; State.phase = "SHAKE"
        end
        return
    end

    local pct = readPowerBarPercent()
    if pct == nil then
        State.powerPct = "0.0"
        local raw = PW.lastRaw or -1
        if raw >= 5.0 then
            if State.frozenSince == 0 or math.abs(raw - (State.frozenRawVal or raw)) > 3.0 then
                State.frozenSince = now; State.frozenRawVal = raw
            elseif (now - State.frozenSince) >= CONFIG.cast_frozen_ms then
                releaseMouse(); State.castReleasedAt = now; State.phase = "SHAKE"; return
            end
        else
            State.frozenSince = 0
        end
        if not State.castBarSeen and (now - State.castStartedAt) >= CONFIG.cast_nobar_ms then
            startCycle(); return
        end
        if (now - State.castStartedAt) >= CONFIG.cast_timeout_ms then
            State.timeouts = State.timeouts + 1
            if CONFIG.cast_on_timeout then startCycle() else stopCycle("IDLE") end
        end
        return
    end

    State.castBarSeen = true
    State.powerPct = string.format("%.1f", pct)

    if pct >= State.castThreshold then
        releaseMouse(); State.castReleasedAt = now; State.phase = "SHAKE"; return
    end

    -- charge-stall recovery: bar appears but stops climbing -> re-baseline
    if State.chargeMotionAt == 0 or pct >= State.chargeLastPct + 1.0 then
        State.chargeLastPct = pct; State.chargeMotionAt = now
    elseif (now - State.chargeMotionAt) >= CONFIG.cast_stall_ms then
        PW.baseline = {}; PW.active = {}; PW.cacheVal = nil
        State.chargeLastPct = 0; State.chargeMotionAt = now
        return
    end
    if (now - State.castStartedAt) >= CONFIG.cast_timeout_ms then
        State.timeouts = State.timeouts + 1
        if CONFIG.cast_on_timeout then startCycle() else stopCycle("IDLE") end
    end
end

-- Shake
local function updateShake()
    State.powerPct = ""; State.progressPct = ""
    releaseMouse() -- just incase :)

    if State.castReleasedAt ~= 0 and (tick() * 1000 - State.castReleasedAt) < 300 then
        pcall(mouse1release)
    end
    if reelContextActive() then State.fishingLostAt = 0; State.phase = "REELING"; return end

    local now = tick() * 1000
    -- post-cast settle so the bobber lands before we hammer Enter
    if State.castReleasedAt ~= 0 and (now - State.castReleasedAt) < CONFIG.post_cast_delay_ms then return end
    -- self-heal: nothing bit for a full cast timeout -> recast
    if State.castReleasedAt ~= 0 and (now - State.castReleasedAt) >= CONFIG.cast_timeout_ms then
        startCycle(); return
    end

    if State.lastShakedAt == 0 or (now - State.lastShakedAt) >= CONFIG.shake_interval_ms then
        tapKey(VK.Enter, 20)
        State.shookCount = (State.shookCount or 0) + 1
        State.lastShakedAt = now
    end
end

-- Reel
local function updateReeling()
    State.powerPct = ""
    -- key off the bar context, not the ScreenGui Enabled flag (Fisch leaves the
    -- reel ScreenGui enabled with no fish, which hung the macro)
    local ctx = getReelBarContext()

    local p = getFishingCompletionPercent()
    if p then
        State.progressPct = string.format("%.1f", p)
        State.lastProgress = p
        if p > State.maxProgress then State.maxProgress = p end
 
        if p >= CONFIG.reel_input_stop_pct then
            State.completionReached = true
        elseif State.completionReached and p < CONFIG.reel_input_stop_pct - 2.0 then
            State.completionReached = false
        end
    end

    if ctx then
        State.fishingLostAt = 0
        if _irApplied or State.completionReached then
            _reeling = false
            releaseMouse()
        else
            _reeling = true
            ctrl:run(ctx)
        end
        return
    end

    local wasIR = _irApplied -- can i just say i hate this
    _reeling = false
    releaseMouse(); ctrl:reset()
    _irApplied = false
    State.completionReached = State.completionReached or wasIR
        or (State.lastProgress or 0) >= CONFIG.completion_threshold
    endFishingOutcome()
end

-- Finished reeling
local function updateDone()
    if CONFIG.debug_logging and getReelBarContext() and not reelContextActive() then
        print("[FM] DONE: stale reel frames suppressed by lockout")
    end
    if reelContextActive() then State.doneAt = 0; State.fishingLostAt = 0; State.phase = "REELING"; return end
    if shakeActive() then
        State.doneAt = 0; State.lastShakedAt = 0
        State.castReleasedAt = tick() * 1000   -- baseline for SHAKE's settle/recast timeout
        State.phase = "SHAKE"
        return
    end
    local now = tick() * 1000
    if State.doneAt == 0 then State.doneAt = now end
    local waitMs = State.lastReelCaught and CONFIG.post_catch_delay_ms or CONFIG.post_lost_delay_ms
    if (now - State.doneAt) < waitMs then return end
    if State.running then startCycle() else stopCycle("IDLE") end
end

local phaseHandlers = { CASTING = updateCasting, SHAKE = updateShake, REELING = updateReeling, DONE = updateDone }


local Library, Window, autoToggle
local _settingToggle = false

local function setRunning(on)
    on = on and true or false
    if on == State.running then return end
    State.running = on
    if not on then stopCycle("IDLE") end
    local msg = on and "Auto Fish on" or ("Auto Fish off (" .. State.caught .. " caught)")
    if Library then
        pcall(function() Library:Notify({ Title = "Fisch Macro", Content = msg, Duration = 2 }) end)
    else
        notify(msg, "Fisch Macro", 2)
    end
    if autoToggle and not _settingToggle then
        _settingToggle = true
        pcall(function() autoToggle:SetValue(on) end)
        _settingToggle = false
    end
end

-- manual assists, could be buggy idk
local assistCtrl = Controller.new()
local _assistReeling = false

local function stopAssistReel()
    if not _assistReeling then return end
    assistCtrl:reset()
    mouse1release(); mouseHeld = false
    _assistReeling = false; _reeling = false
end

local function runAssists()
    State.assistState = "idle"

    -- reel a hooked fish (highest priority)
    if CONFIG.auto_reel then
        local ctx = getReelBarContext()
        local prog = ctx and getFishingCompletionPercent() or nil
        if ctx and not (prog and prog >= 99) then
            State.assistState = "reeling"
            State.progressPct = prog and string.format("%.1f", prog) or ""
            if _irApplied then stopAssistReel(); return end   -- IR: feed no input
            _assistReeling = true; _reeling = true
            assistCtrl:run(ctx)
            return
        end
        stopAssistReel()
    else
        stopAssistReel()
    end

    -- shake: spam Enter while the prompt's button is visible
    if CONFIG.auto_shake and shakeActive() then
        State.assistState = "shaking"
        local now = tick() * 1000
        if now - (State.assistShakeAt or 0) >= CONFIG.shake_interval_ms then
            tapKey(VK.Enter, 20)
            State.shookCount = (State.shookCount or 0) + 1
            State.assistShakeAt = now
        end
        return
    end

    -- cast: release on threshold, user has to initiate cast
    if CONFIG.auto_cast then
        if CONFIG.cast_mode == "short" then
            if #resolvePowerBars() > 0 then
                State.assistState = "casting"
                State.powerPct = "---"
                local now = tick() * 1000
                if State.assistChargeAt == 0 then State.assistChargeAt = now end
                if not State.assistReleased and (now - State.assistChargeAt) >= CONFIG.cast_short_max_ms then
                    mouse1release(); mouseHeld = false
                    State.assistReleased = true
                end
            else
                State.powerPct = ""
                State.assistChargeAt = 0
                State.assistReleased = false
            end
            return
        end
        local p = readPowerBarPercent()
        if p then
            State.assistState = "casting"
            State.powerPct = string.format("%.1f", p)
            if not State.assistReleased and p >= resolveCastThreshold() then
                mouse1release(); mouseHeld = false
                State.assistReleased = true
            end
        else
            State.powerPct = ""
            State.assistReleased = false
        end
    end
end

-- Status readout, debug log, watchdog, anti-AFK
local function currentStatus()
    local label = State.running and (PHASE_LABEL[State.phase] or State.phase)
                  or (State.assistState or "idle")
    if label == "casting" then
        return string.format("state(casting) power(%s) presses(%d) releases(%d)",
            State.powerPct ~= "" and State.powerPct or "0.0",
            State.castPresses or 0, State.castReleases or 0)
    elseif label == "shaking" then
        return string.format("state(shaking) shook=(%d)", State.shookCount or 0)
    elseif label == "reeling" then
        return string.format("state(reeling) progress(%s)",
            State.progressPct ~= "" and State.progressPct or "0.0")
    end
    return "state(" .. label .. ")"
end

local _dbgAt, _dbgLastPhase = 0, nil
local function debugTick()
    if not CONFIG.debug_logging then return end
    if State.phase ~= _dbgLastPhase then   -- unthrottled: catches brief bounces
        print("[FM] PHASE " .. tostring(_dbgLastPhase) .. " -> " .. tostring(State.phase))
        _dbgLastPhase = State.phase
    end
    local now = tick() * 1000
    if now - _dbgAt < 200 then return end
    _dbgAt = now
    print("[FM] " .. currentStatus())
end

local function watchdogResetTimer() 
    State.wdSig = ""; State.wdSignalAt = tick() * 1000
end

local function watchdogTick() -- another zerodeath classic
    if not CONFIG.watchdog_enabled then State.wdSignalAt = 0; return end
    local now = tick() * 1000
    local sig = string.format("%s|%d|%d|%d|%s|%d",
        State.phase, math.floor(State.maxProgress or 0), State.caught, State.lost,
        (State.powerPct ~= "" and State.powerPct or "0"), State.shookCount or 0)
    if sig ~= State.wdSig then
        State.wdSig = sig; State.wdSignalAt = now
        return
    end
    if State.wdSignalAt == 0 then State.wdSignalAt = now; return end
    if (now - State.wdSignalAt) >= CONFIG.watchdog_stall_ms then
        State.recoveries = (State.recoveries or 0) + 1
        dbg("watchdog: stall recovery #" .. State.recoveries)
        releaseMouse()
        startCycle()
        watchdogResetTimer()
    end
end

-- Anti-AFK (non-toggleable) 
local ANTIAFK_INTERVAL_MS = 9 * 60 * 1000
local _antiAfkAt = tick() * 1000
local function antiAfkTick()
    if State.running or anyAssist() then _antiAfkAt = tick() * 1000; return end
    if not robloxActive() then return end
    if (tick() * 1000 - _antiAfkAt) >= ANTIAFK_INTERVAL_MS then
        _antiAfkAt = tick() * 1000
        tapKey(0x7E, 20)
    end
end

local function displayName(part)
    local zn = findChild(part, "zonename")
    if zn then
        local ok, v = pcall(function() return zn.Value end)
        if ok and type(v) == "string" and v ~= "" then return v end
    end
    return part.Name
end

local function collectLocations(intoList, intoMap)
    local zones = findChild(Workspace, "zones")
    local function grab(groupName)
        for _, part in ipairs(getChildren(findChild(zones, groupName))) do
            local ok, isPart = pcall(function() return part:IsA("BasePart") end)
            if ok and isPart then
                local nm = displayName(part)
                if intoMap and intoMap[nm] == nil then intoMap[nm] = part.Position end
                if intoList then
                    local seen = false
                    for _, e in ipairs(intoList) do if e.name == nm then seen = true; break end end
                    if not seen then intoList[#intoList + 1] = { name = nm, pos = part.Position } end
                end
            end
        end
    end
    grab("player")
    if CONFIG.wp_include_fishing then grab("fishing") end
    return intoList, intoMap
end

local function collectChests()
    local list = {}
    local world = findChild(Workspace, "world")
    for _, folder in ipairs({ findChild(world, "chests"), findChild(world, "ActiveChestsFolder") }) do
        for _, ch in ipairs(getChildren(folder)) do
            local ok, isPart = pcall(function() return ch:IsA("BasePart") end)
            if ok and isPart then
                local okp, pos = pcall(function() return ch.Position end)
                if okp and pos then list[#list + 1] = { name = ch.Name, pos = pos } end
            end
        end
    end
    return list
end

-- esp name 
local function applyTextSize(tx, n)
    if pcall(function() tx.Size = n end) then return end
    pcall(function() tx.FontSize = n end)
end

local function newEsp(o)
    local E = { objects = {}, conn = nil, shown = false, list = {}, lastScan = 0 }
    local function ensure(n)
        while #E.objects < n do
            local sq = FM.draw("Square")
            sq.Filled = true; sq.Color = o.color; sq.Visible = false
            local tx = FM.draw("Text")
            tx.Color = o.textColor; tx.Center = true; tx.Outline = true; tx.Visible = false
            E.objects[#E.objects + 1] = { sq = sq, tx = tx }
        end
    end
    function E.rescan() E.lastScan = 0 end
    function E.hide()
        E.shown = false
        if E.conn then pcall(function() E.conn:Disconnect() end); E.conn = nil end
        for _, ob in ipairs(E.objects) do
            pcall(function() ob.sq.Visible = false; ob.tx.Visible = false end)
        end
    end
    function E.show()
        if E.shown then return end
        E.shown = true; E.lastScan = 0
        E.conn = FM.track(RunService.Heartbeat:Connect(function()
            local now = tick() * 1000
            if E.lastScan == 0 or (now - E.lastScan) >= (o.rescan and CONFIG[o.rescan] or 5000) then
                E.lastScan = now
                E.list = o.collect()
            end
            ensure(#E.list)
            local cp = selfPos()
            local size, tsize = CONFIG[o.size], CONFIG[o.text]
            local maxd, showd = CONFIG[o.maxd], CONFIG[o.dist]
            local half = size / 2
            for i, ob in ipairs(E.objects) do
                local e, drawn = E.list[i], false
                if e then
                    local dist
                    if cp then
                        local ok, d = pcall(function() return (e.pos - cp).Magnitude end)
                        if ok then dist = d end
                    end
                    if not (maxd > 0 and dist and dist > maxd) then
                        local screen, on = WorldToScreen(e.pos)
                        if on and screen then
                            ob.sq.Size = Vector2.new(size, size)
                            ob.sq.Position = Vector2.new(screen.X - half, screen.Y - half)
                            applyTextSize(ob.tx, tsize)
                            ob.tx.Text = (showd and dist)
                                and string.format("%s [%d]", e.name, math.floor(dist)) or e.name
                            ob.tx.Position = Vector2.new(screen.X, screen.Y - half - tsize - 2)
                            ob.sq.Visible = true; ob.tx.Visible = true
                            drawn = true
                        end
                    end
                end
                if not drawn then ob.sq.Visible = false; ob.tx.Visible = false end
            end
        end))
    end
    return E
end

local WP = newEsp({
    color = Color3.fromRGB(255, 0, 0), textColor = Color3.fromRGB(255, 255, 255),
    size = "wp_square_size", text = "wp_text_size",
    dist = "wp_show_distance", maxd = "wp_max_distance",
    collect = function() return (collectLocations({}, nil)) end,
})

local CHEST = newEsp({
    color = Color3.fromRGB(255, 215, 0), textColor = Color3.fromRGB(255, 235, 120),
    size = "chest_square_size", text = "chest_text_size",
    dist = "chest_show_distance", maxd = "chest_max_distance", rescan = "chest_rescan_ms",
    collect = function()
        local l = collectChests()
        for _, c in ipairs(l) do c.name = "Chest" end
        return l
    end,
})


-- Status HUD
local HUD = { lines = {}, shown = false, startAt = tick() }
function HUD.build()
    for _, t in ipairs(HUD.lines) do pcall(function() t:Remove() end) end
    HUD.lines = {}
    for i = 1, 5 do
        local tx = FM.draw("Text")
        tx.Color = Color3.fromRGB(255, 255, 255)
        applyTextSize(tx, CONFIG.hud_text_size)
        tx.Outline = true; tx.Center = false; tx.Visible = false
        HUD.lines[i] = tx
    end
end
function HUD.hide()
    HUD.shown = false
    for _, t in ipairs(HUD.lines) do pcall(function() t.Visible = false end) end
end
function HUD.show()
    if #HUD.lines == 0 then HUD.build() end
    HUD.shown = true
end
function HUD.tick()
    if not HUD.shown then return end
    local fphr = (State.caught or 0) / math.max(1 / 3600, (tick() - HUD.startAt) / 3600)
    local mode = State.running and (PHASE_LABEL[State.phase] or State.phase)
                 or (anyAssist() and (State.assistState or "assist") or "idle")
    local texts = {
        "Fisch Macro",
        "state: " .. tostring(mode),
        string.format("caught %d   lost %d", State.caught or 0, State.lost or 0),
        string.format("fish/hr %.0f   recover %d", fphr, State.recoveries or 0),
        "rod: " .. (State.rod ~= "" and State.rod or "none"),
    }
    local lh = CONFIG.hud_text_size + 4
    for i, t in ipairs(HUD.lines) do
        pcall(function()
            t.Text = texts[i] or ""
            t.Position = Vector2.new(CONFIG.hud_x, CONFIG.hud_y + (i - 1) * lh)
            t.Visible = true
        end)
    end
end


-- Webhook
local WEBHOOK = { startedSent = false, lastStatsAt = 0 }

function WEBHOOK.validUrl(u)
    return type(u) == "string" and (u:find("discord.com/api/webhooks/", 1, true)
        or u:find("discordapp.com/api/webhooks/", 1, true)) ~= nil
end

function WEBHOOK.post(content) -- W claude
    if not CONFIG.webhook_enabled then return false end
    local url = CONFIG.webhook_url
    if not WEBHOOK.validUrl(url) then return false end
    local ok, body = pcall(function()
        return HttpService:JSONEncode({ username = "Fisch Macro", content = content })
    end)
    if not ok then return false end
    local sent = pcall(function() game:HttpPost(url, body, Enum.HttpContentType.ApplicationJson) end)
    if not sent then sent = pcall(function() game:HttpPost(url, body, false, "application/json") end) end
    if not sent then sent = pcall(function() game:HttpPost(url, body) end) end
    return sent
end

function WEBHOOK.sendAsync(content) 
    task.spawn(function() pcall(WEBHOOK.post, content) end)
end

function WEBHOOK.leaderstat(names)
    local ls = findChild(getLP(), "leaderstats"); if not ls then return nil end
    for _, nm in ipairs(names) do
        local s = findChild(ls, nm)
        if s then
            local ok, v = pcall(function() return s.Value end)
            if ok and v ~= nil then return v end
        end
    end
    return nil
end

function WEBHOOK.username()
    local lp = getLP(); if not lp then return "?" end
    local nm = lp.Name or "?"
    local ok, dn = pcall(function() return lp.DisplayName end)
    if ok and type(dn) == "string" and dn ~= "" and dn ~= nm then return dn .. " (@" .. nm .. ")" end
    return nm
end

function WEBHOOK.stats()
    local phase = State.running and (PHASE_LABEL[State.phase] or State.phase)
                  or (anyAssist() and (State.assistState or "assist") or "idle")
    return string.format(
        "**Fisch Macro stats:**\nUser: %s\nStage: %s    Rod: %s\nCaught: %d    Lost: %d    Timeouts: %d",
        WEBHOOK.username(), phase, State.rod ~= "" and State.rod or "none",
        State.caught or 0, State.lost or 0, State.timeouts or 0)
end

function WEBHOOK.startup()
    local lvl   = WEBHOOK.leaderstat({ "Level", "Lvl", "level" })
    local money = WEBHOOK.leaderstat({ "Money", "Coins", "Cash", "C$", "Currency" })
    return string.format("**Fisch Macro started:**\nUser: %s\nLevel: %s\nMoney: %s",
        WEBHOOK.username(), lvl ~= nil and tostring(lvl) or "?",
        money ~= nil and tostring(money) or "?")
end

function WEBHOOK.maybeStartup()  
    if WEBHOOK.startedSent then return end
    if not (CONFIG.webhook_enabled and CONFIG.webhook_on_start and WEBHOOK.validUrl(CONFIG.webhook_url)) then return end
    WEBHOOK.startedSent = true
    WEBHOOK.sendAsync(WEBHOOK.startup())
end

function WEBHOOK.statsTick()
    if not (CONFIG.webhook_enabled and CONFIG.webhook_stats and WEBHOOK.validUrl(CONFIG.webhook_url)) then return end
    if (tick() - WEBHOOK.lastStatsAt) < CONFIG.webhook_interval_s then return end
    WEBHOOK.lastStatsAt = tick()
    WEBHOOK.sendAsync(WEBHOOK.stats())
end

-- Teleport locations
local TP = { _active = nil } -- **MASSIVE** thank you to wraith.xyz on discord for the locations that arent main islands
TP.locations = {
    ["Grand Reef"]                 = Vector3.new(-3577.17, 162.33, 503.51),
    ["Desolate Deep"]              = Vector3.new(-1512.57, -234.70, -2862.52),
    ["Glacial Grotto (Summit)"]    = Vector3.new(19990.91, 1142.24, 5550.10),
    ["Atlantis"]                   = Vector3.new(-4343.68, -602.31, 1813.18),
    ["Boreal Pines"]               = Vector3.new(21575.56, 141.52, 4137.94),
    ["Castaway Cliff"]             = Vector3.new(384.89, 207.49, -1818.55),
    ["Everturn Forest"]            = Vector3.new(2426.63, 149.82, -2500.87),
    ["Forsaken Shores"]            = Vector3.new(-2584.73, 167.55, 1608.71),
    ["Lost Jungle"]                = Vector3.new(-2707.33, 158.20, -2060.92),
    ["Moosewood"]                  = Vector3.new(486.56, 157.84, 268.30),
    ["Mushgrove"]                  = Vector3.new(2697.28, 140.33, -756.55),
    ["Roslit Bay"]                 = Vector3.new(-1486.62, 142.08, 704.40),
    ["Scoria Reach"]               = Vector3.new(-5108.09, 145.09, -1456.06),
    ["Snowcap Island"]             = Vector3.new(2687.71, 160.31, 2385.95),
    ["Statue of Sovereignty"]      = Vector3.new(17.04, 166.10, -1048.24),
    ["Sunstone Island"]            = Vector3.new(-986.11, 208.64, -1074.15),
    ["Terrapin"]                   = Vector3.new(-132.30, 188.15, 1952.43),
    ["Tidefall"]                   = Vector3.new(3133.05, -1081.10, 788.25),
    ["Treasure Island"]            = Vector3.new(8284, 195, -17093),
    ["Poseidon's Storm of Floods"] = Vector3.new(-8985.58, -3191.38, 780.49),
    ["Heaven"]                     = Vector3.new(1465.71, 8876.25, 1699.79),
    ["Hawaii"]                     = Vector3.new(-1346, 130, -39935),
    ["Abyssal Zenith"]             = Vector3.new(-13541, -11048, 154),
    ["Brine Pool"]                 = Vector3.new(-1795, -142, -3331),
    ["Ancient Archives"]           = Vector3.new(-3162.13, -747.21, 1701.17),
    ["Underground Music Venue"]    = Vector3.new(2037, -644, 2474),
    ["Enchanted Crevice"]          = Vector3.new(681.17, -754.03, -472.44),
    ["Luminescent Cavern"]         = Vector3.new(-1013, -313, -4038),
    ["Oscars Locker"]              = Vector3.new(213.22, -394.45, 3534.90),
    ["Cursed Isle"]                = Vector3.new(1860, 135, 1210),
    ["Zeus's Thunder of Chaos"]    = Vector3.new(-8878, -3539, 594),
    ["Living Garden"]              = Vector3.new(-2401, -316, -2771),
    ["Carrot Garden"]              = Vector3.new(3732, -1127, -1080),
    ["Northern Expedition"]        = Vector3.new(19512.69, 132.67, 5303.36),
    ["Above The Clouds"]           = Vector3.new(1489.51, 2601.67, -1718.30),
    ["Ancient Isle"]               = Vector3.new(6069, 224, 262),
    ["Mineshaft"]                  = Vector3.new(-684, -864, -74),
    ["Overgrowth Caves"]           = Vector3.new(20269.78, 273.20, 5557.13),
    ["Cryogenic Canal"]            = Vector3.new(19956.81, 635.28, 5717.43),
    ["Glacial Grotto (Cave)"]      = Vector3.new(20007.97, 1035.20, 5699.71),
    ["Harvesters Spike"]           = Vector3.new(-1254.81, 137.25, 1556.77),
    ["The Arch"]                   = Vector3.new(1005.03, 131.32, -1241.27),
    ["Haddock Rock"]               = Vector3.new(-464.45, 160.01, -454.63),
    ["Earmark Island"]             = Vector3.new(1272.97, 140.10, 542.90),
    ["Birch Cay"]                  = Vector3.new(1747.19, 143.00, -2449.68),
    ["Bellona's Frenzy of War"]    = Vector3.new(-8667.92, -2361.67, 757.59),
    ["Apollo's Song of Light"]     = Vector3.new(-8707.94, -2904.53, 731.84),
    ["Hades' Underworld of Indefinite"] = Vector3.new(-8649, -4243, 434),
    ["Olympian Fissure"]           = Vector3.new(-8830, -4243, -147),
    ["Challenger's Deep"]          = Vector3.new(-775, -3283, -675),
    ["Volcanic Vents"]             = Vector3.new(-3390, -2263, 3822),
    ["Calm Zone"]                  = Vector3.new(-4336, -11174, 3704),
    ["Veil of the Forsaken"]       = Vector3.new(-2361, -11184, -7073),
    ["Cultist Lair"]               = Vector3.new(4476, -1997, -4676),
    ["Crystal Cove"]               = Vector3.new(1364, -612, 2472),
    ["Keepers Altar"]              = Vector3.new(1296, -805, -296),
    ["Snowburrow"]                 = Vector3.new(2784, 141, 2557),
    ["Collapsed Ruins"]            = Vector3.new(3136, -1102, 1611),
    ["Crowned Ruins"]              = Vector3.new(3126, -1126, 2039),
    ["Coral Bastion"]              = Vector3.new(2544, -1098, 849),
    ["Sunken Reliquary"]           = Vector3.new(2950, -1102, 443),
    ["Roslit Volcano"]             = Vector3.new(-1893, 173, 314),
    ["Drylands"]                   = Vector3.new(-23986, 2685, -6224),
    ["Thalassar's Secret"]         = Vector3.new(2897, -579, 1177),
    ["Detonator's Rest"]           = Vector3.new(-1409, -902, -3493),
    ["Vertigo"]                    = Vector3.new(-107, -515, 1143),
    ["The Depths"]                 = Vector3.new(608, -712, 1230),
    ["Ghosts Tavern"]              = Vector3.new(268, 800, -6864),
    ["Aether"]                     = Vector3.new(-146, -654, 966),
    ["Crimson Cavern"]             = Vector3.new(-1035, -360, -4800),
    ["Forgotten Temple"]           = Vector3.new(-5286, -1759, -10000),
    ["The Laboratory"]             = Vector3.new(-1934, 224, -449),
    ["Shady Bazaar"]               = Vector3.new(-2941, -1029, 6178),
    ["Toxic Grove"]                = Vector3.new(-2745, -317, -2272),
    ["Mermaid Cove"]               = Vector3.new(-3870, -1286, 505),
    ["Meteor"]                     = Vector3.new(5733, 184, 625),
    ["Poseidons Temple"]           = Vector3.new(-3950, -550, 968),
    ["Zeus's Rod Room"]            = Vector3.new(-4294, -627, 2655),
    ["Heaven"]                     = Vector3.new(1459.48,  8876.25, -1717.73),
    ["Volcanic Depths (Pool)"]     = Vector3.new(-3345, -2026, 4084),
    ["Challangers Deep (Pool)"]    = Vector3.new(747, -3353, -1566),
    ["Nectar Den"]                 = Vector3.new(-2066, -327, -3125)
}

function TP.resolve(name)
    if TP.locations[name] then return TP.locations[name] end
    local low = string.lower(name or "")
    for k, v in pairs(TP.locations) do
        if string.lower(k) == low then return v end
    end
    return nil
end

function TP.matchName(q)
    if not q or q == "" then return nil end
    q = string.lower(q)
    local prefix, substr
    for k in pairs(TP.locations) do
        local lk = string.lower(k)
        if lk == q then return k end
        if not prefix and lk:sub(1, #q) == q then prefix = k end
        if not substr and lk:find(q, 1, true) then substr = k end
    end
    return prefix or substr
end

function TP.cancel() TP._active = nil end

function TP.toPos(x, y, z)
    TP.cancel()
    local hrp = getHRP()
    if not hrp then warn("[FM tp] no HumanoidRootPart"); return false end
    pcall(function() hrp.CFrame = CFrame.new(x, y, z) end)
    return true
end

function TP.to(name)
    local pos = TP.resolve(name)
    if not pos then warn("[FM tp] unknown location: " .. tostring(name)); return false end
    return TP.toPos(pos.X, pos.Y, pos.Z)
end

function TP.tween(name, speed)
    local pos = TP.resolve(name)
    if not pos then warn("[FM tp] unknown location: " .. tostring(name)); return false end
    local hrp = getHRP()
    if not hrp then warn("[FM tp] no HumanoidRootPart"); return false end
    TP._active = { target = pos, speed = tonumber(speed) or CONFIG.tp_speed, cur = hrp.Position }
    return true
end

function TP.step(dt)
    local a = TP._active
    if not a then return end
    local h = getHRP()
    if not h then TP._active = nil; return end
    local delta = a.target - a.cur
    local d = delta.Magnitude
    local step = math.max(2, a.speed * (dt or (1 / 60)))
    local goal
    if d <= step then
        goal = a.target; TP._active = nil
    else
        a.cur = a.cur + (delta / d) * step
        goal = a.cur
    end
    pcall(function() h.CFrame = CFrame.new(goal.X, goal.Y, goal.Z) end)
    pcall(function() h.AssemblyLinearVelocity = Vector3.new(0, 0, 0) end)
end

function TP.list()
    local names = {}
    for k in pairs(TP.locations) do names[#names + 1] = k end
    table.sort(names)
    print(string.format("[FM tp] %d locations:", #names))
    for _, n in ipairs(names) do print("   " .. n) end
    return names
end

-- npc scan
local NPC = { _list = {}, _lastScan = 0 }

function NPC.collect()
    local list, seen = {}, {}
    local function readablePos(inst)
        if not inst then return nil end
        local ok, pos = pcall(function()
            local p = inst.Position
            return (p and p.X ~= nil) and p or nil
        end)
        return ok and pos or nil
    end
    local function add(m)
        local pos = readablePos(findChild(m, "HumanoidRootPart")) or readablePos(findChild(m, "Head"))
        if not pos then
            for _, c in ipairs(getChildren(m)) do
                pos = readablePos(c)
                if pos then break end
            end
        end
        if not pos then return end
        local key = m.Name .. "@" .. math.floor(pos.X) .. "," .. math.floor(pos.Z)
        if not seen[key] then
            seen[key] = true
            list[#list + 1] = { name = m.Name, pos = pos }
        end
    end
    local function scan(container, depth)
        if not container or depth > 3 then return end
        for _, m in ipairs(getChildren(container)) do
            if findChild(m, "Humanoid") or findChild(m, "HumanoidRootPart") then
                add(m)
            elseif #getChildren(m) > 0 then
                scan(m, depth + 1)
            end
        end
    end
    scan(findChild(findChild(Workspace, "world"), "npcs"), 1)
    scan(findChild(Workspace, "npcs"), 1)
    pcall(function()
        for _, m in ipairs(game:GetService("CollectionService"):GetTagged("NewNpc")) do add(m) end
    end)
    return list
end

function NPC.snapshot(maxAgeMs)
    local now = tick() * 1000
    if (now - (NPC._lastScan or 0)) >= (maxAgeMs or 10000) then
        NPC._lastScan = now
        NPC._list = NPC.collect()
    end
    return NPC._list or {}
end

-- website scrape innacturate dont use bad bad bad
local Rod = {}
Rod.catalog = {
    -- Moosewood
    { name = "Flimsy Rod",     zone = "Moosewood", how = "Starter rod - you spawn with it" },
    { name = "Training Rod",   zone = "Moosewood", pos = Vector3.new(465, 150, 230), npc = "Marc Merchant", how = "Merchant - 300 C$" },
    { name = "Plastic Rod",    zone = "Moosewood", pos = Vector3.new(465, 150, 230), npc = "Marc Merchant", how = "Merchant - 900 C$" },
    { name = "Carbon Rod",     zone = "Moosewood", pos = Vector3.new(465, 150, 230), npc = "Marc Merchant", how = "Merchant - 2,000 C$" },
    { name = "Fast Rod",       zone = "Moosewood", pos = Vector3.new(465, 150, 230), npc = "Marc Merchant", how = "Merchant - 2,000 C$" },
    { name = "Long Rod",       zone = "Moosewood", pos = Vector3.new(465, 150, 230), npc = "Marc Merchant", how = "Merchant - 4,500 C$" },
    { name = "Lucky Rod",      zone = "Moosewood", pos = Vector3.new(465, 150, 230), npc = "Marc Merchant", how = "Merchant - 5,250 C$" },
    
    -- Roslit Bay
    { name = "Steady Rod",     zone = "Roslit Bay", pos = Vector3.new(-1515, 140, 765), npc = "Alfredrickus", how = "Blacksmith - 7,000 C$" },
    { name = "Fortune Rod",    zone = "Roslit Bay", pos = Vector3.new(-1515, 140, 765), npc = "Alfredrickus", how = "Blacksmith - 12,750 C$" },
    { name = "Rapid Rod",      zone = "Roslit Bay", pos = Vector3.new(-1515, 140, 765), npc = "Alfredrickus", how = "Merchant - 14,000 C$" },
    { name = "Magma Rod",      zone = "Roslit Bay", pos = Vector3.new(-1850, 165, 160), npc = "Orc", how = "Quest: give the Orc a Pufferfish (teleport lands at the Orc)" },
    { name = "Magnet Rod",     zone = "Terrapin Island", pos = Vector3.new(-195, 130, 1930), how = "Shipwright - 15,000 C$" },
    { name = "Reinforced Rod", zone = "Desolate Deep", pos = Vector3.new(-990, -245, -2695), how = "Secret merchant - 20,000 C$" },
    { name = "Trident Rod",    zone = "Desolate Deep", pos = Vector3.new(-990, -245, -2695), how = "Complete Bestiary + 5 Enchant Relics - 150,000 C$" },
    { name = "Nocturnal Rod",  zone = "Vertigo", how = "Merchant - 11,000 C$" },
    { name = "Aurora Rod",     zone = "Vertigo", how = "Buy Totem (500k), activate during whirlpool - 90,000 C$" },
    { name = "Fungal Rod",     zone = "Mushgrove Swamp", pos = Vector3.new(2670, 130, -710), npc = "Agaric", how = "Quest: show Agaric an Alligator (catchable at this spot)" },
    { name = "Rod of the Exalted One", zone = "Mushgrove Swamp", tp = "Mushgrove", how = "Place 7 mutated Enchant Relics on the altar" },
    { name = "Kings Rod",      zone = "Keeper's Altar (below the Statue)", pos = Vector3.new(-20, 135, -1130), how = "Sold at the Keeper's Altar - ~100,000 C$ (teleport lands at the elevator)" },
    { name = "Destiny Rod",    zone = "The Arch", pos = Vector3.new(980, 130, -1230), npc = "Caleia", how = "Caleia - 190,000 C$ (needs 70% Bestiary)" },
    { name = "Sunken Rod",     zone = "Forsaken Shores", how = "Find a treasure map, repair it, dig up the chest" },
    { name = "Scurvy Rod",     zone = "Forsaken Shores", pos = Vector3.new(-2825, 215, 1515), npc = "Jack Marrow", how = "Jack Marrow - 50,000 C$" },
    { name = "Rod of the Depths", zone = "The Depths", how = "Place relics on the altars + key - 750,000 C$" },
    { name = "Relic Rod",      zone = "Archaeological Site", tp = "Mineshaft", how = "Cave puzzle at the dig site - 8,000 C$" },
    { name = "Stone Rod",      zone = "Ancient Isle", pos = Vector3.new(5500, 143, -316), how = "Sold on the isle - 3,000 C$" },
    { name = "Phoenix Rod",    zone = "Ancient Isle", pos = Vector3.new(5925, 281, 883), how = "Inside the cave - 40,000 C$" },
    
    -- no fixed spot
    { name = "Mythical Rod",   zone = "Traveling Merchant (random spawn)", how = "110,000 C$ when the merchant is around" },
    { name = "Midas Rod",      zone = "Traveling Merchant (random spawn)", how = "55,000 C$ when the merchant is around" },
    { name = "No-Life Rod",    zone = "Anywhere", how = "Reach level 500" },
    { name = "Seraphic Rod",   zone = "Anywhere", how = "Reach level 1,000" },
    
    -- Northern Summit
    { name = "Arctic Rod",       zone = "Northern Summit", pos = Vector3.new(19575, 135, 5310), how = "Base-camp merchant table - 25,000 C$" },
    { name = "Avalanche Rod",    zone = "Northern Summit", pos = Vector3.new(19771, 415, 5415), how = "Camp near Overgrowth Cave - 35,000 C$" },
    { name = "Crystalized Rod",  zone = "Northern Summit", pos = Vector3.new(20296, 272, 5463), how = "35,000 C$ - needs 2 players + a Glass Diamond" },
    { name = "Ice Warpers Rod",  zone = "Glacial Grotto", tp = "Glacial Grotto (Summit)", how = "Unlock the 6 levers - 65,000 C$" },
    { name = "Summit Rod",       zone = "Northern Summit (peak)", pos = Vector3.new(20213.5, 736.7, 5713), how = "Crate at the top - 300,000 C$" },
    { name = "Heaven's Rod",     zone = "Heaven (above the Summit)", tp = "Heaven", how = "Energy Crystals + buttons - 1,750,000 C$" },
    
    -- Atlantis
    { name = "Champions Rod",       zone = "Atlantis", how = "Left of the Inn Keeper - 1,000,000 C$" },
    { name = "Depthseeker Rod",     zone = "Atlantis", how = "Merchant stall by the east bridge - 125,000 C$" },
    { name = "Tempest Rod",         zone = "Atlantis", how = "Mythological Clock room after the Sunken Trial - 1,850,000 C$" },
    { name = "Abyssal Specter Rod", zone = "Atlantis", how = "Clock room after the Ethereal Abyss Trial - 1,004,269 C$" },
    { name = "Poseidon Rod",        zone = "Poseidon's Temple (Atlantis)", tp = "Poseidon's Storm of Floods", how = "After Poseidon's trial - 1,555,555 C$" },
    { name = "Zeus Rod",            zone = "Zeus's Rod Room (Atlantis)", tp = "Zeus's Thunder of Chaos", how = "After Zeus's trial - 1,700,000 C$" },
    { name = "Kraken Rod",          zone = "Kraken Pool (Atlantis)", tp = "Atlantis", how = "All 4 trials + 5 clocks - 1,333,333 C$" },
    
    -- Mariana's Veil
    { name = "Volcanic Rod",       zone = "Volcanic Vents (Mariana's Veil)", pos = Vector3.new(-3175, -2030, 4020), how = "300,000 C$" },
    { name = "Challenger's Rod",   zone = "Challenger's Deep (Mariana's Veil)", pos = Vector3.new(740, -3350, -1530), how = "2,500,000 C$" },
    { name = "Rod of the Zenith",  zone = "Abyssal Zenith", how = "10,000,000 C$" },
    { name = "Ethereal Prism Rod", zone = "Calm Zone Rainbow Pond (Mariana's Veil)", pos = Vector3.new(-4360, -11170, 3710), how = "15,000,000 C$" },
    { name = "Leviathan's Fang Rod", zone = "Veil of the Forsaken", how = "Defeat the Scylla boss - 1,000,000 C$" },
    
    -- craftables (vault table at the Ancient Archives)
    { name = "Precision Rod",   zone = "Ancient Vault", tp = "Ancient Archives", how = "Craft - 7,000 C$ + materials" },
    { name = "Resourceful Rod", zone = "Ancient Vault", tp = "Ancient Archives", how = "Craft - 15,000 C$ + materials" },
    { name = "Wisdom Rod",      zone = "Ancient Vault", tp = "Ancient Archives", how = "Craft - 50,000 C$ + materials" },
    { name = "Krampus's Rod",   zone = "Ancient Vault", tp = "Ancient Archives", how = "Craft - 30,000 C$ + materials" },
    { name = "Seasons Rod",     zone = "Ancient Vault", tp = "Ancient Archives", how = "Level 145 - craft, 35,000 C$ + materials" },
    { name = "Riptide Rod",     zone = "Ancient Vault", tp = "Ancient Archives", how = "Level 200 - craft, 40,000 C$ + materials" },
    { name = "Voyager Rod",     zone = "Ancient Vault", tp = "Ancient Archives", how = "Level 400 - craft, 30,000 C$ + materials" },
    { name = "The Lost Rod",    zone = "Ancient Vault", tp = "Ancient Archives", how = "Level 450 - craft, 50,000 C$ + materials" },
    { name = "Celestial Rod",   zone = "Ancient Vault", tp = "Ancient Archives", how = "Level 500 - craft, 100,000 C$ + materials" },
    { name = "Rod of the Eternal King",   zone = "Ancient Vault", tp = "Ancient Archives", how = "Level 650 - craft, 250,000 C$ + materials" },
    { name = "Rod of the Forgotten Fang", zone = "Ancient Vault", tp = "Ancient Archives", how = "Level 750 - craft, 300,000 C$ + materials" },
    { name = "Rod of Time",     zone = "Ancient Vault", tp = "Ancient Archives", how = "Craft - special materials, no C$" },
    
    -- DRYLANDS update
    { name = "Marrow Rod",       zone = "Drylands", tp = "Ancient Archives", how = "Mysterious Marrow questline in the Drylands, then craft at the Ancient Archives" },
    { name = "Terrotrapper Rod", zone = "Drylands", how = "Obtained in the Drylands (walk there from behind the FischFest castle)" },
}

Rod.SRC_LABEL = {
    exact = "exact spot",
    hub   = "island hub (walk from there)",
    zone  = "zone center (live lookup)",
}

function Rod.zonePos(zoneName)
    if not zoneName or zoneName == "" then return nil end
    if not Rod._zmap or (tick() - (Rod._zmapAt or 0)) > 5 then
        local ok, _, map = pcall(collectLocations, nil, {})
        Rod._zmap = (ok and type(map) == "table") and map or {}
        Rod._zmapAt = tick()
    end
    local q = string.lower(zoneName)
    local sub = nil
    for nm, pos in pairs(Rod._zmap) do
        local ln = string.lower(nm)
        if ln == q then return pos end
        if not sub and (ln:find(q, 1, true) or q:find(ln, 1, true)) then sub = pos end
    end
    return sub
end

function Rod.pos(e)
    if e.pos then return e.pos, "exact" end
    local hub = TP.resolve(e.tp or e.zone)
    if hub then return hub, "hub" end
    local zp = Rod.zonePos(e.zone)
    if zp then return zp, "zone" end
    return nil, nil
end

function Rod.match(q)
    if not q or q == "" then return nil end
    q = string.lower(q)
    local prefix, substr, zoneHit
    for _, e in ipairs(Rod.catalog) do
        local ln = string.lower(e.name)
        if ln == q then return e end
        if not prefix and ln:sub(1, #q) == q then prefix = e end
        if not substr and ln:find(q, 1, true) then substr = e end
        if not zoneHit and string.lower(e.zone):find(q, 1, true) then zoneHit = e end
    end
    return prefix or substr or zoneHit
end

function Rod.liveCheck(e, pos)
    pos = pos or Rod.pos(e)
    if not pos then return nil, nil end
    local want = e.npc and string.lower(e.npc) or nil
    local bestD, bestName, namedPos
    for _, n in ipairs(NPC.snapshot()) do
        local ok, d = pcall(function() return (n.pos - pos).Magnitude end)
        if ok and d then
            if not bestD or d < bestD then bestD, bestName = d, n.name end
            if want and not namedPos and d <= 500 and string.lower(n.name):find(want, 1, true) then
                namedPos = n.pos
            end
        end
    end
    if namedPos then return namedPos, "verified - " .. e.npc .. " on site" end
    if bestD and bestD <= 60 then
        return nil, string.format("likely - %s [%d]", bestName, math.floor(bestD))
    end
    return nil, "unverified (too far)"
end

function Rod.describe(e)
    local _, src = Rod.pos(e)
    local _, live = Rod.liveCheck(e)
    return string.format("%s\nWhere: %s\nHow: %s\nTeleport: %s%s",
        e.name, e.zone, e.how,
        src and Rod.SRC_LABEL[src] or "n/a - no fixed spot",
        live and ("\nLive check: " .. live) or "")
end

function Rod.teleport(e, tween)
    local pos = Rod.pos(e)
    if not pos then
        notify(e.name .. " has no fixed spot (" .. e.zone .. ")", "Fisch Macro", 4)
        return false
    end
    local livePos = Rod.liveCheck(e)
    if livePos then pos = livePos end   -- land exactly on the streamed-in seller
    if tween then
        local hrp = getHRP()
        if not hrp then warn("[FM rods] no HumanoidRootPart"); return false end
        TP._active = { target = pos, speed = tonumber(CONFIG.tp_speed) or 250, cur = hrp.Position }
    else
        TP.toPos(pos.X, pos.Y, pos.Z)
    end
    return true
end

function CHEST.tpNearest()
    local list = collectChests()
    if #list == 0 then notify("No treasure chests up right now.", "Fisch Macro", 3); return false end
    local cp = selfPos()
    local best, bd
    for _, c in ipairs(list) do
        local d = 0
        if cp then
            local ok, m = pcall(function() return (c.pos - cp).Magnitude end)
            d = ok and m or 0
        end
        if not bd or d < bd then best, bd = c, d end
    end
    return best and TP.toPos(best.pos.X, best.pos.Y + 3, best.pos.Z) or false
end

function CHEST.tpNext()
    local list = collectChests()
    if #list == 0 then notify("No treasure chests up right now.", "Fisch Macro", 3); return false end
    CHEST._cycle = ((CHEST._cycle or 0) % #list) + 1
    local c = list[CHEST._cycle]
    return TP.toPos(c.pos.X, c.pos.Y + 3, c.pos.Z)
end

CHEST.run = { active = false, list = {}, i = 1, stage = "tp", nextAt = 0, visited = 0 }

function CHEST.runStart()
    local r = CHEST.run
    r.list = collectChests()
    r.i = 1; r.stage = "tp"; r.nextAt = 0; r.visited = 0
    r.active = #r.list > 0
    notify(r.active and string.format("Chest run: visiting %d chest(s)...", #r.list)
        or "Chest run: no chests found.", "Fisch Macro", 3)
end

function CHEST.runStop()
    if not CHEST.run.active then return end
    CHEST.run.active = false
    pcall(keyrelease, VK.E)
    notify(string.format("Chest run stopped (%d visited).", CHEST.run.visited), "Fisch Macro", 3)
end

function CHEST.runStep()
    local r = CHEST.run
    if not r.active then return end
    local now = tick() * 1000
    if now < r.nextAt then return end
    if r.i > #r.list then
        r.active = false
        notify(string.format("Chest run done: %d chest(s) visited.", r.visited), "Fisch Macro", 3)
        return
    end
    local pos = r.list[r.i].pos
    if r.stage == "tp" then
        TP.toPos(pos.X, pos.Y, pos.Z)
        r.stage = "press"; r.nextAt = now + 150   -- settle so the E prompt is in range
    else
        tapKey(VK.E, 150)
        r.visited = r.visited + 1; r.i = r.i + 1
        r.stage = "tp"; r.nextAt = now + 200
    end
end


local IR = { enabled = false, patched = false, lastLive = false }

-- Returns true once the minigame table was really patched: setgc returns the
-- overwrite count and a landed patch hits BOTH keys (>= 2).
function IR.tryPatch()
    local s = tonumber(CONFIG.instant_reel_speed) or 10
    local n = 0
    local ok = pcall(function()
        n = setgc({ progressefficiency = s, progressLossMultiplier = -s })
    end)
    if not ok then warn("[FM] setgc failed (instant reel)"); return false end
    dbg("instant reel: setgc overwrote " .. tostring(n) .. " value(s)")
    if n >= 2 then IR.patched = true end
    return IR.patched
end

function IR.setEnabled(v)
    IR.enabled = v and true or false
    if not IR.enabled or IR.patched then return end
    if hasActiveFishingContext() then
        task.spawn(function()   -- reel already open: apply right now
            if IR.tryPatch() then
                _irApplied = true
                notify("Instant reel active.", "Fisch Macro", 3)
            end
        end)
    else
        notify("Instant reel arms when your next reel opens.", "Fisch Macro", 4)
    end
end

function IR.step()
    local live = hasActiveFishingContext()
    if live and not IR.lastLive then
        -- reel just opened: patch now if armed (the minigame table exists right
        -- here; a scan that misses simply retries at the next reel open)
        if IR.enabled and not IR.patched and IR.tryPatch() then
            notify("Instant reel active.", "Fisch Macro", 3)
        end
        if IR.patched then _irApplied = true end   -- patched reel: feed no input
    elseif IR.lastLive and not live then
        if _irApplied then
            -- arm the stale-UI lockout NOW: an instant catch closes within a
            -- frame of the bite. Full-auto REELING consumes _irApplied itself,
            -- so only clear it here for assist/manual mode.
            _reelClosedAt = tick() * 1000
            if not (State.running and State.phase == "REELING") then _irApplied = false end
        end
    end
    IR.lastLive = live
end

local VC = { lastLive = false, MAX_ATTEMPTS = 3 }

VC.STATS = {
    -- barSize is the decompile-confirmed live reel key (= rod Control + 0.3);
    -- >= 1 pins the player bar across the whole track.
    { id = "control", title = "Control", on = false, value = 1, keys = {
        "barSize",
        "control", "Control", "rodControl", "RodControl",
        "controlMultiplier", "ControlMultiplier" } },
    -- HIGH resilience = calm/slow fish, but the flattened value must EXCEED
    -- the rod's stock or fish get FASTER (100 was below stock live) -> 1000.
    { id = "resilience", title = "Resilience", on = false, value = 1000, keys = {
        "resilience", "Resilience", "resilienceMultiplier", "ResilienceMultiplier",
        "resilienceModifier", "resiliencemodifier", "fishResilience", "FishResilience" } },
}

function VC.applyArmed() -- infuriation of the nation
    for _, st in ipairs(VC.STATS) do
        if st.on and not st.patched and (st.attempts or 0) < VC.MAX_ATTEMPTS then
            local vals = {}
            for _, k in ipairs(st.keys) do vals[k] = st.value end
            local count = 0
            local ok = pcall(function() count = setgc(vals) or 0 end)
            if not ok then warn("[FM] setgc failed (" .. st.title .. ")"); return end
            count = tonumber(count) or 0
            st.attempts = (st.attempts or 0) + 1
            if count > 0 then
                st.patched = true
                notify(st.title .. ": patched " .. count .. " value(s).", "Fisch Macro", 4)
            elseif st.attempts >= VC.MAX_ATTEMPTS then
                notify(st.title .. ": keys not found after " .. st.attempts
                    .. " reels - renamed by an update? Use fisch_stats Scanner/Dump.", "Fisch Macro", 6)
            else
                notify(st.title .. ": 0 landed - retrying at the next reel ("
                    .. st.attempts .. "/" .. VC.MAX_ATTEMPTS .. ").", "Fisch Macro", 4)
            end
            return  
        end
    end
end

function VC.setOn(st, v)
    st.on = v and true or false
    if not st.on or st.patched then return end
    st.attempts = 0   -- re-toggling re-arms a stat that ran out of attempts
    if hasActiveFishingContext() then
        task.spawn(VC.applyArmed)   -- minigame already open: apply right now
    else
        notify(st.title .. " applies when your next reel opens.", "Fisch Macro", 4)
    end
end

function VC.step()   -- reel-open watcher, driven from the main Heartbeat
    local live = hasActiveFishingContext()
    if live and not VC.lastLive then VC.applyArmed() end
    VC.lastLive = live
end

-- ui
do
    local ok = pcall(function()
        loadstring(game:HttpGet("https://scripts.wabisabi.mom/wabi-sabi-ui-lib.lua"))()
    end)
    Library = rawget(getfenv(0), "WabiSabi")
    if not ok or not Library then
        warn("[FM] UI library failed to load, running console-only")
        Library = nil
    end
end

if Library then -- build ui
    FM.lib = Library   -- so a re-run can unload this menu instead of stacking a second one
    Window = Library:CreateWindow({
        Title = "Fisch Macro", SubTitle = "Matcha",
        Size = Vector2.new(800, 700), Resize = true, Theme = "Dark",
    })

    local function bindToggle(sec, key, title, fn)
        sec:AddToggle({ Id = key, Title = title, Default = CONFIG[key],
            Callback = function(v) CONFIG[key] = v; if fn then fn(v) end end })
    end
    local function bindSlider(sec, key, title, min, max, round, fn)
        sec:AddSlider({ Id = key, Title = title, Min = min, Max = max,
            Default = CONFIG[key], Rounding = round or 0,
            Callback = function(v) CONFIG[key] = v; if fn then fn(v) end end })
    end

    -- ---- Main ----------------------------------------------------------------
    local MainTab = Window:AddTab({ Title = "Main", Icon = "fish" })
    local Status = MainTab:AddSection("Status")
    local statusPara = Status:AddParagraph({ Title = "Idle", Content = "Turn on Auto Fish for full auto." })

    local Macro = MainTab:AddSection("Macro")
    autoToggle = Macro:AddToggle({
        Id = "auto_fish", Title = "Auto Fish (full auto)", Default = false,
        Keybind = { Default = "F1", Mode = "Toggle" },
        Callback = function(v) if not _settingToggle then setRunning(v) end end,
    })
    Macro:AddButton({ Title = "Reset counters", Callback = function()
        State.caught = 0; State.lost = 0; State.timeouts = 0; State.recoveries = 0
        HUD.startAt = tick()
    end })
    Macro:AddToggle({ Id = "status_hud", Title = "Status HUD (on-screen)",
        Default = CONFIG.hud_show_on_load,
        Callback = function(v) if v then HUD.show() else HUD.hide() end end })
    bindToggle(Macro, "debug_logging", "Debug logging (console)")

    local Assist = MainTab:AddSection("Manual assists (only while Auto Fish is off)")
    Assist:AddParagraph({ Title = "", Content = "Help you fish by hand. Ignored while Auto Fish is on." })
    bindToggle(Assist, "auto_cast", "Auto cast (release at threshold)")
    bindToggle(Assist, "auto_shake", "Auto shake")
    bindToggle(Assist, "auto_reel", "Auto reel")

    -- ---- Cast ----------------------------------------------------------------
    local CastTab = Window:AddTab({ Title = "Cast", Icon = "wind" })
    local C = CastTab:AddSection("Casting")
    C:AddDropdown({ Id = "cast_mode", Title = "Cast power mode",
        Values = { "short", "long", "custom" }, Default = CONFIG.cast_mode,
        Callback = function(v) CONFIG.cast_mode = v; State.castThreshold = resolveCastThreshold() end })
    bindSlider(C, "cast_short_max_ms", "Short cast hold (ms)", 100, 1000)
    bindSlider(C, "cast_power_custom", "Custom power %", 1, 100, 0,
        function() State.castThreshold = resolveCastThreshold() end)
    bindSlider(C, "cast_timeout_ms", "Cast timeout (ms)", 3000, 30000)
    bindToggle(C, "cast_on_timeout", "Recast on timeout")
    bindSlider(C, "post_cast_delay_ms", "Post-cast delay (ms)", 0, 1000)
    bindSlider(C, "post_catch_delay_ms", "Post-catch delay before recast (ms)", 0, 5000)
    bindSlider(C, "post_lost_delay_ms", "Post-lost delay before recast (ms)", 0, 3000)
    bindSlider(C, "cast_stall_ms", "Recast if charge stalls (ms)", 800, 6000)
    bindSlider(C, "shake_interval_ms", "Shake interval (ms)", 10, 200)

    local Eq = CastTab:AddSection("Equip")
    bindToggle(Eq, "auto_equip", "Auto equip rod")
    bindToggle(Eq, "equip_autodetect", "Auto-detect rod slot")
    bindSlider(Eq, "equip_slot", "Rod hotbar slot", 1, 9)
    bindSlider(Eq, "equip_settle_ms", "Equip settle (ms)", 0, 1000)

    local Wd = CastTab:AddSection("Watchdog")
    Wd:AddParagraph({ Title = "", Content = "Auto-restarts the macro if it stalls. Auto Fish only." })
    bindToggle(Wd, "watchdog_enabled", "Enable watchdog")
    bindSlider(Wd, "watchdog_stall_ms", "Recover after stall (ms)", 5000, 60000)

    -- ---- Reel ----------------------------------------------------------------
    local ReelTab = Window:AddTab({ Title = "Reel", Icon = "sliders-horizontal" })
    local P = ReelTab:AddSection("Reel controller tuning")
    bindSlider(P, "proportional_gain",   "Proportional gain",   0, 5,   2)
    bindSlider(P, "derivative_gain",     "Derivative gain",     0, 5,   2)
    bindSlider(P, "velocity_damping",    "Velocity damping",    0, 80,  1)
    bindSlider(P, "neutral_duty_cycle",  "Neutral duty cycle",  0, 1,   2)
    bindSlider(P, "prediction_strength", "Prediction strength", 0, 20,  1)
    bindSlider(P, "close_threshold",     "Close threshold",     0, 0.1, 3)
    bindSlider(P, "edge_boundary",       "Edge boundary",       0, 0.3, 2)
    local Det = ReelTab:AddSection("Catch detection")
    bindSlider(Det, "completion_threshold", "Count as caught at progress % >=", 50, 99)

    -- ---- Value changer ---------------------------------------------------------
    local VTab = Window:AddTab({ Title = "Value changer", Icon = "zap" })
    local IRs = VTab:AddSection("Instant reel")
    IRs:AddToggle({ Id = "instant_reel", Title = "Enable instant reel (catch a fish first)", Default = false,
        Callback = function(v) IR.setEnabled(v) end })
    bindSlider(IRs, "instant_reel_speed", "Instant reel speed", 1, 50)

    -- Control / Resilience UI hidden 2026-07-09 (keys missing from GC after a
    -- game update — scan found no numeric hosts). The VC logic below stays
    -- live; uncomment to bring the toggles back once the new keys are known.
    -- local VCs = VTab:AddSection("Stats (applies when a reel opens)")
    -- for _, stat in ipairs(VC.STATS) do
    --     local st = stat
    --     VCs:AddToggle({ Id = "vc_t_" .. st.id, Title = st.title, Default = st.on,
    --         Callback = function(v) VC.setOn(st, v) end })
    --     VCs:AddInput({ Id = "vc_v_" .. st.id, Title = st.title .. " value", Finished = true,
    --         Default = tostring(st.value),
    --         Callback = function(t) local n = tonumber(t); if n then st.value = n end end })
    -- end

    -- ---- ESP -------------------------------------------------------------------
    local ETab = Window:AddTab({ Title = "ESP", Icon = "map-pin" })
    local W = ETab:AddSection("Waypoints")
    W:AddToggle({ Id = "wp_show", Title = "Show waypoints", Default = CONFIG.wp_show_on_load,
        Callback = function(v) if v then WP.show() else WP.hide() end end })
    bindToggle(W, "wp_include_fishing", "Include fishing spots", function() WP.rescan() end)
    bindToggle(W, "wp_show_distance", "Show distance")
    bindSlider(W, "wp_square_size", "Square size (px)", 2, 24)
    bindSlider(W, "wp_text_size", "Text size", 8, 28)
    bindSlider(W, "wp_max_distance", "Max distance (0 = all)", 0, 5000)

    -- ---- Treasure --------------------------------------------------------------
    do   -- block-scoped so the registers free at `end` (200-local budget)
        local TRTab = Window:AddTab({ Title = "Treasure", Icon = "map-pin" })
        local TC = TRTab:AddSection("Treasure chest ESP")
        TC:AddToggle({ Id = "chest_show", Title = "Show treasure chests",
            Default = CONFIG.chest_show_on_load,
            Callback = function(v) if v then CHEST.show() else CHEST.hide() end end })
        bindToggle(TC, "chest_show_distance", "Show distance")
        bindSlider(TC, "chest_square_size", "Square size (px)", 2, 24)
        bindSlider(TC, "chest_text_size", "Text size", 8, 28)
        bindSlider(TC, "chest_max_distance", "Max distance (0 = all)", 0, 5000)
        local TT = TRTab:AddSection("Chest teleport")
        TT:AddButton({ Title = "Teleport to nearest chest", Callback = function() CHEST.tpNearest() end })
        TT:AddButton({ Title = "Teleport to next chest (cycles)", Callback = function() CHEST.tpNext() end })
        TT:AddButton({ Title = "Collect all chests (teleport + E)", Callback = function() CHEST.runStart() end })
        TT:AddButton({ Title = "Stop chest run", Callback = function() CHEST.runStop() end })
    end

    -- ---- Teleport ------------------------------------------------------------
    do
        local TPTab = Window:AddTab({ Title = "Teleport", Icon = "navigation" })
        local T = TPTab:AddSection("Go to a location")
        T:AddParagraph({ Title = "", Content = "Teleports are use-at-your-own-risk." })
        local query = ""
        local matchPara = T:AddParagraph({ Title = "Match", Content = "Type a name below." })
        local function refreshMatch()
            local m = TP.matchName(query)
            pcall(function() matchPara:SetContent(m or ("no match for '" .. query .. "'")) end)
            return m
        end
        T:AddInput({ Id = "tp_search", Title = "Search location", Finished = false, Default = "",
            Callback = function(t) query = t or ""; refreshMatch() end })
        bindSlider(T, "tp_speed", "Tween speed (studs/sec)", 50, 1000)
        T:AddButton({ Title = "Tween to match", Callback = function()
            local m = refreshMatch(); if m then TP.tween(m, CONFIG.tp_speed) end end })
        T:AddButton({ Title = "Instant teleport to match", Callback = function()
            local m = refreshMatch(); if m then TP.to(m) end end })
        T:AddButton({ Title = "Cancel tween", Callback = function() TP.cancel() end })
        T:AddButton({ Title = "List all (console)", Callback = function() TP.list() end })
    end

    -- ---- Rods ----------------------------------------------------------------
    do
        local RodTab = Window:AddTab({ Title = "Rods", Icon = "map-pin" })
        local R = RodTab:AddSection("Find a rod")
        local rodQuery = ""
        local rodPara = R:AddParagraph({ Title = "Match", Content = "Type a rod or island name below." })
        local function refreshRod()
            local e = Rod.match(rodQuery)
            pcall(function()
                rodPara:SetContent(e and Rod.describe(e) or ("no match for '" .. rodQuery .. "'"))
            end)
            return e
        end
        R:AddInput({ Id = "rod_search", Title = "Search rod", Finished = false, Default = "",
            Callback = function(t) rodQuery = t or ""; refreshRod() end })
        R:AddButton({ Title = "Instant teleport to rod", Callback = function()
            local e = refreshRod(); if e then Rod.teleport(e, false) end end })
        R:AddButton({ Title = "Tween to rod", Callback = function()
            local e = refreshRod(); if e then Rod.teleport(e, true) end end })
    end

    -- ---- Webhook -------------------------------------------------------------
    local WHTab = Window:AddTab({ Title = "Webhook", Icon = "send" })
    local WH = WHTab:AddSection("Discord webhook")
    WH:AddParagraph({ Title = "", Content =
        "Paste your URL into webhook_url.txt in the Matcha workspace (this input "
        .. "can't paste), then hit Reload. Sends only while enabled." })
    local urlInput = WH:AddInput({ Id = "webhook_url", Title = "Your webhook URL",
        Finished = true, Default = CONFIG.webhook_url,
        Callback = function(t) CONFIG.webhook_url = t or "" end })
    WH:AddButton({ Title = "Reload URL from webhook_url.txt", Callback = function()
        local u = loadWebhookUrl()
        if u ~= "" then
            pcall(function() urlInput:SetValue(u) end)   -- fires the callback -> CONFIG
        else
            notify("webhook_url.txt is empty. Paste your webhook URL into it first.", "Fisch Macro", 5)
        end
    end })
    bindToggle(WH, "webhook_enabled", "Enable webhook")
    bindToggle(WH, "webhook_on_start", "Send startup message (name / level / money)")
    bindToggle(WH, "webhook_stats", "Send periodic stats")
    bindSlider(WH, "webhook_interval_s", "Stats interval (sec)", 30, 3600)
    WH:AddButton({ Title = "Send test stats now", Callback = function()
        WEBHOOK.sendAsync(WEBHOOK.stats()) end })

    -- ---- Settings ------------------------------------------------------------
    local SettingsTab = Window:AddTab({ Title = "Settings", Icon = "settings" })
    pcall(function() Window:BuildInterfaceSection(SettingsTab) end)
    pcall(function() Window:BuildConfigSection(SettingsTab) end)
    pcall(function() Library:LoadAutoloadConfig() end)
    do   -- a saved config can replay an empty webhook_url over the file URL
        local u = loadWebhookUrl()
        if u ~= "" then pcall(function() urlInput:SetValue(u) end) end
    end

    -- live status readout (mirrors the debug line + run counters)
    task.spawn(function()
        while Library and not Library.Unloaded and not FM.dead do
            pcall(function()
                statusPara:SetTitle(State.running and "auto fishing"
                    or (anyAssist() and "assisting" or "idle"))
                statusPara:SetContent(string.format(
                    "%s\nRod: %s\nCaught: %d    Lost: %d    Timeouts: %d    Recover: %d",
                    currentStatus(), State.rod ~= "" and State.rod or "none",
                    State.caught, State.lost, State.timeouts, State.recoveries))
            end)
            task.wait(0.1)
        end
    end)

    Library:OnUnload(function()
        setRunning(false)
        pcall(function() IR.setEnabled(false) end)
        pcall(HUD.hide); pcall(WP.hide); pcall(CHEST.hide)
    end)
end

-- something in this fucks up
if CONFIG.wp_show_on_load then pcall(WP.show) end
if CONFIG.hud_show_on_load then pcall(HUD.show) end
if CONFIG.chest_show_on_load then pcall(CHEST.show) end
if CONFIG.autostart then setRunning(true) end

FM.track(RunService.Heartbeat:Connect(function(dt)
    antiAfkTick()                 -- idle-kick guard (no-op while fishing)
    TP.step(dt)                   -- drive an in-progress teleport tween
    pcall(IR.step)                -- instant-reel session watcher
    pcall(VC.step)                -- control/resilience: one-shot apply at reel open
    pcall(CHEST.runStep)          -- chest-collection run
    debugTick()
    pcall(HUD.tick)
    pcall(WEBHOOK.maybeStartup)
    pcall(WEBHOOK.statsTick)

    if State.running then
        if not robloxActive() then releaseMouse(); watchdogResetTimer(); return end
        if State.phase == "IDLE" then startCycle() end
        local handler = phaseHandlers[State.phase]
        if handler then
            local ok, err = pcall(handler)
            if not ok then
                releaseMouse()
                warn("[FM] " .. State.phase .. ": " .. tostring(err))
            end
        end
        watchdogTick()
        return
    end

    if State.phase ~= "IDLE" then stopCycle("IDLE") end
    if anyAssist() and robloxActive() then
        if not pcall(runAssists) then stopAssistReel() end
    else
        stopAssistReel()
        State.assistState = "idle"
    end
end))

do
    local nLoc = 0
    for _ in pairs(TP.locations) do nLoc = nLoc + 1 end
    print(string.format("ready"))
end
notify(Library and "Fisch Macro loaded - F1 toggles Auto Fish."
    or "Fisch Macro loaded, but the UI failed to load", "Fisch Macro", 4)
