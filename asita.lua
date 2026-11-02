--[[
    Cold War ESP — v7 Apex Edition
    ────────────────────────────────
    • Object-pool Drawing  • Distance-first filter  • Heartbeat ESP
    • LMB-only aim         • Priority targeting     • Anti-fling
    • Anti-ragdoll         • Save/Load config       • Live stats
    • Hotkey editor        • Team check via BodyColors
    HWID-бан — только внешний spoofer (ARES/ByGone).
]]

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS        = game:GetService("UserInputService")
local Workspace  = game:GetService("Workspace")
local Cam        = workspace.CurrentCamera
local LP         = Players.LocalPlayer
local HttpService= game:GetService("HttpService")

if not Drawing then error("[CW v7] Executor без Drawing.") end

-- ============================================================
--  КОНФИГ
-- ============================================================
local CFG = {
    ESP = {
        Enabled = true, Box = true, Name = true, Distance = true, HPBar = true,
        Skeleton = false, Tracers = false, Highlight = false,
        MaxDistance = 300, Filter = "Enemy",
        VisibleColor  = Color3.fromRGB(0, 220, 120),
        OccludedColor = Color3.fromRGB(200, 60, 60),
        TracerColor   = Color3.fromRGB(0, 200, 120),
        UpdateHz = 45,
    },
    Aim = {
        Enabled = false, Mode = "Silent", Part = "Head",
        BaseFOV = 120, CloseFOV = 60, FarFOV = 200,
        ReactionMin = 0.08, ReactionMax = 0.22,
        MissChanceBase = 0.12, MissChanceFar = 0.35,
        Jitter = 0.25, BezierBend = 1.2, Overshoot = 0.35,
        FatigueAfter = 30, FatigueMax = 0.4,
        VisibleCheck = true, SpawnProtect = 1.5,
        BaitProtect = true, AimOnlyOnMove = true,
        LMBOnly = true, -- ключевой стелс: целься только при выстреле
        Priority = "Crosshair", -- Crosshair | Closest | LowHP
        KDLimit = 5, KDWindow = 60,
    },
    Self = {
        AntiFling = true,
        AntiRagdoll = true,
        SafeRespawn = true,
    },
    Keys = {
        ToggleUI = Enum.KeyCode.RightShift,
        ToggleESP = Enum.KeyCode.Insert,
        ToggleAim = Enum.KeyCode.Home,
        AimKey = Enum.KeyCode.Q,
        Unload = Enum.KeyCode.End,
    },
}

-- ============================================================
--  СОСТОЯНИЕ
-- ============================================================
local players     = Players:GetPlayers()
local teams       = {}
local bodyColors  = {} -- fallback при отсутствии Team
local espObjects  = {}
local highlights  = {}
local localHum    = nil
local localTeam   = nil
local localBody   = nil
local hitPartsCache = {}
local spawnTimes  = {}
local knownTargets = {}
local lastPos     = Vector3.zero
local stats       = { kills = 0, shots = 0 }

local killTimes = {}
local function registerKill() stats.kills = stats.kills + 1; table.insert(killTimes, tick()) end
local function recentKills()
    local cutoff = tick() - CFG.Aim.KDWindow
    for i = #killTimes, 1, -1 do
        if killTimes[i] < cutoff then table.remove(killTimes, i) end
    end
    return #killTimes
end

local function watchKills(plr)
    if knownTargets[plr] then return end
    knownTargets[plr] = true
    local function hook(h)
        h.Died:Connect(function() registerKill() end)
    end
    if plr.Character then
        local h = plr.Character:FindFirstChildOfClass("Humanoid")
        if h then hook(h) end
    end
    plr.CharacterAdded:Connect(function(c)
        local h = c:WaitForChild("Humanoid", 5)
        if h then hook(h) end
    end)
end

local function bodyColorOf(plr)
    local c = plr.Character; if not c then return nil end
    local bc = c:FindFirstChildOfClass("BodyColors"); if not bc then return nil end
    return {torso = bc.TorsoColor3}
end

local function teamOf(plr)
    if plr.Team then return plr.Team.Name end
    local c = plr.Character; if not c then return nil end
    local h = c:FindFirstChild("Humanoid"); if not h then return nil end
    if h:FindFirstChild("Team") then return h.Team.Value end
    return h:GetAttribute("Team")
end

local function refreshTeam(plr)
    teams[plr] = teamOf(plr)
    bodyColors[plr] = bodyColorOf(plr)
end

local function refreshLocal()
    localHum  = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid") or nil
    localTeam = teamOf(LP)
    localBody = bodyColorOf(LP)
end
refreshLocal()
LP.CharacterAdded:Connect(function() task.wait(0.3); refreshLocal() end)
LP:GetPropertyChangedSignal("Team"):Connect(function() localTeam = teamOf(LP) end)

-- ============================================================
--  UI
-- ============================================================
local gui = Instance.new("ScreenGui")
gui.Name = "CW_v7"; gui.ResetOnSpawn = false; gui.IgnoreGuiInset = true
pcall(function() gui.Parent = game:GetService("CoreGui") end)
if not gui.Parent then gui.Parent = LP:WaitForChild("PlayerGui") end

local C = {
    bg = Color3.fromRGB(16, 16, 22), panel = Color3.fromRGB(26, 26, 34),
    row = Color3.fromRGB(36, 36, 48), rowHov = Color3.fromRGB(46, 46, 60),
    accent = Color3.fromRGB(0, 200, 120), accentDim = Color3.fromRGB(0, 130, 80),
    warn = Color3.fromRGB(240, 180, 40), danger = Color3.fromRGB(220, 70, 70),
    text = Color3.fromRGB(220, 220, 230), dim = Color3.fromRGB(130, 130, 145),
}

local main = Instance.new("Frame")
main.Size = UDim2.new(0, 380, 0, 520)
main.Position = UDim2.new(0, 30, 0, 80)
main.BackgroundColor3 = C.bg; main.BorderSizePixel = 0; main.Parent = gui
Instance.new("UICorner", main).CornerRadius = UDim.new(0, 8)
local ms = Instance.new("UIStroke", main); ms.Color = C.panel; ms.Thickness = 1

local tb = Instance.new("Frame", main)
tb.Size = UDim2.new(1, 0, 0, 34); tb.BackgroundColor3 = C.panel; tb.BorderSizePixel = 0
Instance.new("UICorner", tb).CornerRadius = UDim.new(0, 8)
local mask = Instance.new("Frame", tb); mask.Size = UDim2.new(1, 0, 0.5, 0); mask.Position = UDim2.new(0, 0, 0.5, 0); mask.BackgroundColor3 = C.panel; mask.BorderSizePixel = 0

local title = Instance.new("TextLabel", tb)
title.Size = UDim2.new(1, -180, 1, 0); title.Position = UDim2.new(0, 12, 0, 0)
title.BackgroundTransparency = 1; title.Text = "Cold War v7 — Apex"
title.TextColor3 = C.text; title.Font = Enum.Font.GothamBold; title.TextSize = 13
title.TextXAlignment = Enum.TextXAlignment.Left

local statsLabel = Instance.new("TextLabel", tb)
statsLabel.Size = UDim2.new(0, 130, 1, 0); statsLabel.Position = UDim2.new(1, -140, 0, 0)
statsLabel.BackgroundTransparency = 1; statsLabel.Text = "--"
statsLabel.TextColor3 = C.dim; statsLabel.Font = Enum.Font.Code; statsLabel.TextSize = 10
statsLabel.TextXAlignment = Enum.TextXAlignment.Right

do
    local d, s, p = false, nil, nil
    tb.InputBegan:Connect(function(i) if i.UserInputType == Enum.UserInputType.MouseButton1 then d, s, p = true, i.Position, main.Position end end)
    UIS.InputChanged:Connect(function(i) if d and i.UserInputType == Enum.UserInputType.MouseMovement then local dl = i.Position - s; main.Position = UDim2.new(p.X.Scale, p.X.Offset + dl.X, p.Y.Scale, p.Y.Offset + dl.Y) end end)
    UIS.InputEnded:Connect(function(i) if i.UserInputType == Enum.UserInputType.MouseButton1 then d = false end end)
end

-- tabs
local tabsBar = Instance.new("Frame", main)
tabsBar.Size = UDim2.new(1, -16, 0, 28); tabsBar.Position = UDim2.new(0, 8, 0, 42)
tabsBar.BackgroundTransparency = 1

local content = Instance.new("ScrollingFrame", main)
content.Size = UDim2.new(1, -16, 1, -80); content.Position = UDim2.new(0, 8, 0, 78)
content.BackgroundTransparency = 1; content.BorderSizePixel = 0
content.ScrollBarThickness = 3; content.ScrollBarImageColor3 = C.row
content.CanvasSize = UDim2.new(0, 0, 0, 0); content.AutomaticCanvasSize = Enum.AutomaticSize.Y

local pages = {}
local function createTab(name)
    local b = Instance.new("TextButton", tabsBar)
    b.Name = name
    b.Size = UDim2.new(0, 84, 1, 0)
    b.Position = UDim2.new(0, (#tabsBar:GetChildren()) * 88, 0, 0)
    b.BackgroundColor3 = C.row; b.Text = name; b.TextColor3 = C.text
    b.Font = Enum.Font.GothamBold; b.TextSize = 12; b.BorderSizePixel = 0
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 4)
    local p = Instance.new("Frame", content)
    p.Size = UDim2.new(1, 0, 1, 0); p.BackgroundTransparency = 1; p.Visible = false
    pages[name] = p
    b.MouseButton1Click:Connect(function()
        for n, pg in pairs(pages) do pg.Visible = (n == name) end
        for _, btn in pairs(tabsBar:GetChildren()) do if btn:IsA("TextButton") then btn.BackgroundColor3 = btn.Name == name and C.accent or C.row end end
    end)
    return p
end

local function section(page, text)
    local f = Instance.new("Frame", page)
    f.Size = UDim2.new(1, -6, 0, 22); f.BackgroundTransparency = 1
    local l = Instance.new("TextLabel", f)
    l.Size = UDim2.new(1, 0, 1, 0); l.BackgroundTransparency = 1; l.Text = text
    l.TextColor3 = C.accent; l.Font = Enum.Font.GothamBold; l.TextSize = 11
    l.TextXAlignment = Enum.TextXAlignment.Left
end

local function toggle(page, text, default, cb)
    local f = Instance.new("Frame", page)
    f.Size = UDim2.new(1, -6, 0, 28); f.BackgroundColor3 = C.row; f.BorderSizePixel = 0
    Instance.new("UICorner", f).CornerRadius = UDim.new(0, 4)
    Instance.new("UIPadding", f).PaddingLeft = UDim.new(0, 10)
    local lbl = Instance.new("TextLabel", f)
    lbl.Size = UDim2.new(1, -55, 1, 0); lbl.BackgroundTransparency = 1
    lbl.Text = text; lbl.TextColor3 = C.text; lbl.Font = Enum.Font.Gotham; lbl.TextSize = 12
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    local ind = Instance.new("Frame", f)
    ind.Size = UDim2.new(0, 30, 0, 15); ind.Position = UDim2.new(1, -40, 0, 6.5)
    ind.BackgroundColor3 = default and C.accent or C.dim; ind.BorderSizePixel = 0
    Instance.new("UICorner", ind).CornerRadius = UDim.new(1, 0)
    local knob = Instance.new("Frame", ind)
    knob.Size = UDim2.new(0, 11, 0, 11)
    knob.Position = default and UDim2.new(1, -13, 0, 2) or UDim2.new(0, 2, 0, 2)
    knob.BackgroundColor3 = Color3.new(1,1,1); knob.BorderSizePixel = 0
    Instance.new("UICorner", knob).CornerRadius = UDim.new(1, 0)
    local state = default
    f.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 then
            state = not state
            ind.BackgroundColor3 = state and C.accent or C.dim
            knob.Position = state and UDim2.new(1, -13, 0, 2) or UDim2.new(0, 2, 0, 2)
            cb(state)
        end
    end)
end

local function slider(page, text, min, max, default, cb)
    local f = Instance.new("Frame", page)
    f.Size = UDim2.new(1, -6, 0, 42); f.BackgroundColor3 = C.row; f.BorderSizePixel = 0
    Instance.new("UICorner", f).CornerRadius = UDim.new(0, 4)
    local pad = Instance.new("UIPadding", f); pad.PaddingLeft = UDim.new(0, 10); pad.PaddingRight = UDim.new(0, 10)
    local lbl = Instance.new("TextLabel", f)
    lbl.Size = UDim2.new(1, 0, 0, 18); lbl.BackgroundTransparency = 1
    lbl.Text = text .. ": " .. string.format("%.1f", default)
    lbl.TextColor3 = C.text; lbl.Font = Enum.Font.Gotham; lbl.TextSize = 11
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    local bar = Instance.new("Frame", f)
    bar.Size = UDim2.new(1, 0, 0, 5); bar.Position = UDim2.new(0, 0, 1, -8)
    bar.BackgroundColor3 = C.dim; bar.BorderSizePixel = 0
    Instance.new("UICorner", bar).CornerRadius = UDim.new(1, 0)
    local fill = Instance.new("Frame", bar)
    fill.Size = UDim2.new((default - min) / (max - min), 0, 1, 0)
    fill.BackgroundColor3 = C.accent; fill.BorderSizePixel = 0
    Instance.new("UICorner", fill).CornerRadius = UDim.new(1, 0)
    local dragging = false
    bar.InputBegan:Connect(function(i) if i.UserInputType == Enum.UserInputType.MouseButton1 then dragging = true end end)
    UIS.InputEnded:Connect(function(i) if i.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end end)
    UIS.InputChanged:Connect(function(i)
        if dragging and i.UserInputType == Enum.UserInputType.MouseMovement then
            local rel = math.clamp((i.Position.X - bar.AbsolutePosition.X) / bar.AbsoluteSize.X, 0, 1)
            local v = min + (max - min) * rel
            fill.Size = UDim2.new(rel, 0, 1, 0)
            lbl.Text = text .. ": " .. string.format("%.1f", v)
            cb(v)
        end
    end)
end

local function button(page, text, cb, danger)
    local b = Instance.new("TextButton", page)
    b.Size = UDim2.new(1, -6, 0, 28); b.BackgroundColor3 = danger and C.danger or C.row
    b.Text = text; b.TextColor3 = C.text; b.Font = Enum.Font.GothamBold
    b.TextSize = 12; b.BorderSizePixel = 0
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 4)
    b.MouseButton1Click:Connect(cb)
end

-- pages
local pESP    = createTab("ESP")
local pAim    = createTab("Aim")
local pSelf   = createTab("Self")
local pConfig = createTab("Config")

section(pESP, "ESP")
toggle(pESP, "ESP Enabled", CFG.ESP.Enabled, function(v) CFG.ESP.Enabled = v end)
toggle(pESP, "Box", CFG.ESP.Box, function(v) CFG.ESP.Box = v end)
toggle(pESP, "Name", CFG.ESP.Name, function(v) CFG.ESP.Name = v end)
toggle(pESP, "Distance", CFG.ESP.Distance, function(v) CFG.ESP.Distance = v end)
toggle(pESP, "HP Bar", CFG.ESP.HPBar, function(v) CFG.ESP.HPBar = v end)
toggle(pESP, "Skeleton", CFG.ESP.Skeleton, function(v) CFG.ESP.Skeleton = v end)
toggle(pESP, "Tracers", CFG.ESP.Tracers, function(v) CFG.ESP.Tracers = v end)
toggle(pESP, "Highlight", CFG.ESP.Highlight, function(v) CFG.ESP.Highlight = v end)
slider(pESP, "Max Distance", 100, 1000, CFG.ESP.MaxDistance, function(v) CFG.ESP.MaxDistance = v end)
slider(pESP, "Update Hz", 15, 60, CFG.ESP.UpdateHz, function(v) CFG.ESP.UpdateHz = math.floor(v) end)

section(pAim, "AIM")
toggle(pAim, "Aimbot", CFG.Aim.Enabled, function(v) CFG.Aim.Enabled = v end)
toggle(pAim, "Silent Mode", CFG.Aim.Mode == "Silent", function(v) CFG.Aim.Mode = v and "Silent" or "Camera" end)
toggle(pAim, "LMB Only (важно)", CFG.Aim.LMBOnly, function(v) CFG.Aim.LMBOnly = v end)
toggle(pAim, "Aim Only On Move", CFG.Aim.AimOnlyOnMove, function(v) CFG.Aim.AimOnlyOnMove = v end)
toggle(pAim, "Bait Protection", CFG.Aim.BaitProtect, function(v) CFG.Aim.BaitProtect = v end)
toggle(pAim, "Visible Check", CFG.Aim.VisibleCheck, function(v) CFG.Aim.VisibleCheck = v end)
slider(pAim, "FOV", 30, 500, CFG.Aim.BaseFOV, function(v) CFG.Aim.BaseFOV = v end)
slider(pAim, "Miss Chance", 0, 0.8, CFG.Aim.MissChanceBase, function(v) CFG.Aim.MissChanceBase = v end)
slider(pAim, "Reaction Min", 0, 0.5, CFG.Aim.ReactionMin, function(v) CFG.Aim.ReactionMin = v end)
slider(pAim, "Reaction Max", 0, 0.5, CFG.Aim.ReactionMax, function(v) CFG.Aim.ReactionMax = v end)
slider(pAim, "K/D Limit", 1, 20, CFG.Aim.KDLimit, function(v) CFG.Aim.KDLimit = math.floor(v) end)

section(pSelf, "Self Protection")
toggle(pSelf, "Anti-Fling", CFG.Self.AntiFling, function(v) CFG.Self.AntiFling = v end)
toggle(pSelf, "Anti-Ragdoll", CFG.Self.AntiRagdoll, function(v) CFG.Self.AntiRagdoll = v end)
toggle(pSelf, "Safe Respawn", CFG.Self.SafeRespawn, function(v) CFG.Self.SafeRespawn = v end)

section(pConfig, "Configuration")
local function saveCfg()
    if not writefile then return end
    local data = {esp = CFG.ESP, aim = CFG.Aim, self = CFG.Self}
    local ok, enc = pcall(function() return HttpService:JSONEncode(data) end)
    if ok then pcall(function() writefile("cw_v7_config.json", enc) end) end
end
local function loadCfg()
    if not readfile or not isfile then return end
    if not isfile("cw_v7_config.json") then return end
    local ok, data = pcall(function() return HttpService:JSONDecode(readfile("cw_v7_config.json")) end)
    if ok and type(data) == "table" then
        for s, t in pairs(data) do
            local tgt = CFG[s:upper()] or (s == "esp" and CFG.ESP) or (s == "aim" and CFG.Aim) or (s == "self" and CFG.Self)
            if tgt then for k, v in pairs(t) do if type(tgt[k]) == type(v) then tgt[k] = v end end end
        end
    end
end
button(pConfig, "Save Config", saveCfg)
button(pConfig, "Load Config", loadCfg)
button(pConfig, "Unload Script", function() if unloadAll then unloadAll() end end, true)

-- Start with ESP tab
for n, pg in pairs(pages) do pg.Visible = (n == "ESP") end
for _, b in pairs(tabsBar:GetChildren()) do if b:IsA("TextButton") then b.BackgroundColor3 = b.Name == "ESP" and C.accent or C.row end end

-- ============================================================
--  DRAWING POOL
-- ============================================================
local function makeDrawing(plr)
    if espObjects[plr] then return end
    local o = {
        box = Drawing.new("Square"), name = Drawing.new("Text"),
        dist = Drawing.new("Text"), hpBg = Drawing.new("Square"), hpFill = Drawing.new("Square"),
        tracer = Drawing.new("Line"), skeleton = {},
    }
    o.box.Thickness = 1.2; o.box.Filled = false
    o.name.Center = true; o.name.Outline = true; o.name.OutlineColor = Color3.new(0,0,0)
    o.dist.Center = true; o.dist.Outline = true; o.dist.OutlineColor = Color3.new(0,0,0)
    o.hpBg.Filled = true; o.hpFill.Filled = true
    o.tracer.Thickness = 1; o.tracer.Transparency = 0.7
    for i = 1, 15 do o.skeleton[i] = Drawing.new("Line") end
    espObjects[plr] = o
end

local function makeHighlight(plr)
    if highlights[plr] then return end
    local c = plr.Character; if not c then return end
    local h = Instance.new("Highlight")
    h.Adornee = c; h.FillTransparency = 0.5; h.OutlineTransparency = 0
    h.DepthMode = Enum.HighlightDepthMode.Occluded
    h.Enabled = false; h.Parent = c
    highlights[plr] = h
end

local function getHitPart(c, name)
    if not c then return nil end
    local cache = hitPartsCache[c]
    if cache and cache[name] and cache[name].Parent then return cache[name] end
    local p = name == "Head" and c:FindFirstChild("Head")
        or name == "Torso" and (c:FindFirstChild("UpperTorso") or c:FindFirstChild("Torso"))
        or c:FindFirstChild(name) or c:FindFirstChild("HumanoidRootPart")
    if p then hitPartsCache[c] = hitPartsCache[c] or {}; hitPartsCache[c][name] = p end
    return p
end

local function getBones(c)
    local b = {}
    local head, root = c:FindFirstChild("Head"), c:FindFirstChild("HumanoidRootPart")
    if not head or not root then return b end
    local upT, loT = c:FindFirstChild("UpperTorso"), c:FindFirstChild("LowerTorso")
    local torso = c:FindFirstChild("Torso")
    local rUA = c:FindFirstChild("RightUpperArm") or c:FindFirstChild("Right Arm")
    local lUA = c:FindFirstChild("LeftUpperArm")  or c:FindFirstChild("Left Arm")
    local rUL = c:FindFirstChild("RightUpperLeg") or c:FindFirstChild("Right Leg")
    local lUL = c:FindFirstChild("LeftUpperLeg")  or c:FindFirstChild("Left Leg")
    local rLL = c:FindFirstChild("RightLowerLeg") or c:FindFirstChild("Right Leg")
    local lLL = c:FindFirstChild("LeftLowerLeg")  or c:FindFirstChild("Left Leg")
    local chest = upT or torso
    if chest then
        b[#b+1] = {head.Position, chest.Position}
        if loT then b[#b+1] = {chest.Position, loT.Position} end
        if rUA then b[#b+1] = {chest.Position, rUA.Position} end
        if lUA then b[#b+1] = {chest.Position, lUA.Position} end
        if rUL then b[#b+1] = {loT and loT.Position or chest.Position, rUL.Position} end
        if lUL then b[#b+1] = {loT and loT.Position or chest.Position, lUL.Position} end
        if rUL and rLL then b[#b+1] = {rUL.Position, rLL.Position} end
        if lUL and lLL then b[#b+1] = {lUL.Position, lLL.Position} end
    end
    return b
end

-- ============================================================
--  WALL CHECK (с пропуском прозрачного)
-- ============================================================
local wallParams = RaycastParams.new()
wallParams.FilterType = RaycastFilterType.Exclude
wallParams.IgnoreWater = true

local function isVisible(target, char)
    if not target then return false end
    wallParams.FilterDescendantsInstances = { char, LP.Character }
    local origin = Cam.CFrame.Position
    local r = Workspace:Raycast(origin, target.Position - origin, wallParams)
    if r == nil then return true end
    if r.Instance:IsDescendantOf(char) then return true end
    if r.Instance.Transparency > 0.7 then return true end -- пропускаем прозрачное
    return false
end

-- ============================================================
--  ИГРОКИ
-- ============================================================
local function setupPlayer(plr)
    makeDrawing(plr)
    if plr.Character then makeHighlight(plr) end
    refreshTeam(plr)
    watchKills(plr)
    spawnTimes[plr] = tick()
    plr.CharacterAdded:Connect(function(c)
        spawnTimes[plr] = tick()
        task.wait(0.2); refreshTeam(plr)
        if highlights[plr] then pcall(function() highlights[plr]:Destroy() end); highlights[plr] = nil end
        makeHighlight(plr); hitPartsCache[c] = nil
    end)
    pcall(function() plr:GetPropertyChangedSignal("Team"):Connect(function() refreshTeam(plr) end) end)
end
for _, p in next, players do setupPlayer(p) end
Players.PlayerAdded:Connect(function(p) players = Players:GetPlayers(); setupPlayer(p) end)
Players.PlayerRemoving:Connect(function(p)
    players = Players:GetPlayers()
    if espObjects[p] then
        for _, o in pairs(espObjects[p]) do
            if typeof(o) == "table" then for _, l in pairs(o) do pcall(function() l:Remove() end) end
            else pcall(function() o:Remove() end) end
        end
        espObjects[p] = nil
    end
    if highlights[p] then pcall(function() highlights[p]:Destroy() end); highlights[p] = nil end
    teams[p] = nil; bodyColors[p] = nil; hitPartsCache[p.Character] = nil; spawnTimes[p] = nil; knownTargets[p] = nil
end)

-- ============================================================
--  ESP UPDATE (distance-first filter = меньше работы)
-- ============================================================
local vpCenter = Vector2.new(Cam.ViewportSize.X * 0.5, Cam.ViewportSize.Y * 0.5)
Cam:GetPropertyChangedSignal("ViewportSize"):Connect(function()
    vpCenter = Vector2.new(Cam.ViewportSize.X * 0.5, Cam.ViewportSize.Y * 0.5)
end)

local function classify(plr, pTeam)
    local isSelf = (plr == LP)
    local isEnemy
    if pTeam == nil or localTeam == nil then
        -- fallback по BodyColors
        local a, b = bodyColors[plr], localBody
        if a and b and a.torso and b.torso then
            isEnemy = (a.torso ~= b.torso) and not isSelf
        else
            isEnemy = not isSelf
        end
    else
        isEnemy = (pTeam ~= localTeam) and not isSelf
    end
    return isSelf, isEnemy, (not isSelf and not isEnemy)
end

local function updateESP()
    local camPos, maxD = Cam.CFrame.Position, CFG.ESP.MaxDistance
    local maxD2 = maxD * maxD -- квадрат для быстрого сравнения
    local boxOn, nameOn, distOn = CFG.ESP.Box, CFG.ESP.Name, CFG.ESP.Distance
    local hpOn, hlOn, skelOn, tracerOn = CFG.ESP.HPBar, CFG.ESP.Highlight, CFG.ESP.Skeleton, CFG.ESP.Tracers
    local filter = CFG.ESP.Filter

    for plr, o in pairs(espObjects) do
        local c = plr.Character
        local root = c and c:FindFirstChild("HumanoidRootPart")
        local hum  = c and c:FindFirstChild("Humanoid")
        local h    = highlights[plr]

        local function hide()
            o.box.Visible, o.name.Visible, o.dist.Visible = false, false, false
            o.hpBg.Visible, o.hpFill.Visible, o.tracer.Visible = false, false, false
            for _, l in pairs(o.skeleton) do l.Visible = false end
            if h then h.Enabled = false end
        end

        -- Дешёвые проверки сначала
        if not root or not hum or hum.Health <= 0 or hum:GetState() == Enum.HumanoidStateType.Dead then hide(); continue end
        local dx = camPos.X - root.Position.X
        local dy = camPos.Y - root.Position.Y
        local dz = camPos.Z - root.Position.Z
        local dist2 = dx*dx + dy*dy + dz*dz
        if dist2 > maxD2 then hide(); continue end

        local pTeam = teams[plr]
        local isSelf, isEnemy, isSame = classify(plr, pTeam)
        if (filter == "Enemy" and not isEnemy) or (filter == "Team" and not (isSame or isSelf)) then hide(); continue end

        local dist = math.sqrt(dist2)

        -- Только сейчас дорогие проверки
        local visible = isVisible(root, c)
        local color = (isSelf or isSame) and CFG.ESP.VisibleColor or (visible and CFG.ESP.VisibleColor or CFG.ESP.OccludedColor)

        if hlOn and h then
            h.FillColor, h.OutlineColor, h.Adornee = color, color, c
            h.DepthMode = visible and Enum.HighlightDepthMode.AlwaysOnTop or Enum.HighlightDepthMode.Occluded
            h.Enabled = true
        elseif h then h.Enabled = false end

        local head = c:FindFirstChild("Head")
        local top = head and (head.Position + Vector3.new(0,1.3,0)) or (root.Position + Vector3.new(0,3.2,0))
        local lL = c:FindFirstChild("Left Leg") or c:FindFirstChild("LeftFoot")
        local rL = c:FindFirstChild("Right Leg") or c:FindFirstChild("RightFoot")
        local bot
        if lL and rL then
            local low = (lL.Position.Y < rL.Position.Y) and lL or rL
            bot = low.Position - Vector3.new(0, low.Size.Y * 0.5 + 0.2, 0)
        else
            local hip = hum.HipHeight; if not hip or hip <= 0.1 then hip = 1.5 end
            bot = root.Position - Vector3.new(0, hip + 1.6, 0)
        end
        local ts, ton = Cam:WorldToViewportPoint(top)
        local bs, bon = Cam:WorldToViewportPoint(bot)
        if ts.Z <= 0 or (not ton and not bon) then hide(); continue end
        local hgt = math.abs(ts.Y - bs.Y); local w = hgt * 0.55
        local cx = (ts.X + bs.X) * 0.5; local ty = math.min(ts.Y, bs.Y)

        o.box.Size = Vector2.new(w, hgt); o.box.Position = Vector2.new(cx - w * 0.5, ty)
        o.box.Color = color; o.box.Visible = boxOn

        if nameOn then
            o.name.Text = (plr.DisplayName or plr.Name) .. (visible and "" or " [W]")
            o.name.Color = C.text; o.name.Size = 13
            o.name.Position = Vector2.new(cx, ty - 15); o.name.Visible = true
        else o.name.Visible = false end

        if distOn then
            o.dist.Text = math.floor(dist) .. "m"
            o.dist.Color = C.dim; o.dist.Size = 11
            o.dist.Position = Vector2.new(cx, ty + hgt + 2); o.dist.Visible = true
        else o.dist.Visible = false end

        if hpOn then
            local pct = math.clamp(hum.Health / hum.MaxHealth, 0, 1)
            local bx, bw = cx - w * 0.5 - 6, 3
            o.hpBg.Position = Vector2.new(bx, ty); o.hpBg.Size = Vector2.new(bw, hgt); o.hpBg.Visible = true
            o.hpFill.Position = Vector2.new(bx, ty + hgt * (1 - pct))
            o.hpFill.Size = Vector2.new(bw, hgt * pct)
            o.hpFill.Color = pct > 0.5 and Color3.fromRGB(0,220,80) or (pct > 0.25 and Color3.fromRGB(240,200,40) or Color3.fromRGB(240,50,50))
            o.hpFill.Visible = true
        else o.hpBg.Visible = false; o.hpFill.Visible = false end

        if tracerOn then
            o.tracer.From = Vector2.new(Cam.ViewportSize.X * 0.5, Cam.ViewportSize.Y)
            o.tracer.To = Vector2.new(cx, ty + hgt); o.tracer.Color = color; o.tracer.Visible = true
        else o.tracer.Visible = false end

        if skelOn then
            local bones = getBones(c)
            for i, l in ipairs(o.skeleton) do
                local b = bones[i]
                if b then
                    local p1, on1 = Cam:WorldToViewportPoint(b[1])
                    local p2, on2 = Cam:WorldToViewportPoint(b[2])
                    if on1 and on2 and p1.Z > 0 and p2.Z > 0 then
                        l.From = Vector2.new(p1.X, p1.Y); l.To = Vector2.new(p2.X, p2.Y)
                        l.Color = color; l.Visible = true
                    else l.Visible = false end
                else l.Visible = false end
            end
        else for _, l in pairs(o.skeleton) do l.Visible = false end end
    end
end

-- ============================================================
--  GHOST AIM + LMB Only
-- ============================================================
local aim = { lastTarget = nil, lockStart = 0, missThisShot = false, overshootAmt = 0, fatigueStart = 0 }
local lmbDown = false

UIS.InputBegan:Connect(function(i, gp)
    if i.UserInputType == Enum.UserInputType.MouseButton1 then lmbDown = true end
end)
UIS.InputEnded:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 then lmbDown = false end
end)

local function dynamicFOV(dist)
    local t = math.clamp(dist / CFG.ESP.MaxDistance, 0, 1)
    return CFG.Aim.CloseFOV + (CFG.Aim.FarFOV - CFG.Aim.CloseFOV) * t
end
local function missChance(dist)
    local t = math.clamp(dist / CFG.ESP.MaxDistance, 0, 1)
    return CFG.Aim.MissChanceBase + (CFG.Aim.MissChanceFar - CFG.Aim.MissChanceBase) * t
end
local function fatigueFactor()
    if not aim.fatigueStart or aim.fatigueStart == 0 then return 0 end
    local elapsed = tick() - aim.fatigueStart
    if elapsed < CFG.Aim.FatigueAfter then return 0 end
    return math.min(CFG.Aim.FatigueMax, (elapsed - CFG.Aim.FatigueAfter) / 120)
end
local function isAFK(hum, root)
    return root.AssemblyLinearVelocity.Magnitude < 1 and hum.MoveDirection.Magnitude < 0.1
end
local function isBait(hum, root)
    return root.AssemblyLinearVelocity.Magnitude < 0.5 and hum.MoveDirection.Magnitude > 0.8
end
local function playerMoving()
    if not localHum then return true end
    return localHum.MoveDirection.Magnitude > 0.1
end

local function scorePriority(cand)
    if CFG.Aim.Priority == "LowHP" then return cand.hp
    elseif CFG.Aim.Priority == "Closest" then return cand.dist
    else return cand.d }
end

local function getTarget()
    local camPos, maxD = Cam.CFrame.Position, CFG.ESP.MaxDistance
    local aimFOV = CFG.Aim.BaseFOV

    if CFG.Aim.AimOnlyOnMove and not playerMoving() then return nil end
    if CFG.Aim.LMBOnly and not lmbDown then return nil end
    if recentKills() >= CFG.Aim.KDLimit then return nil end

    local candidates = {}
    for _, plr in next, players do
        if plr ~= LP then
            local c = plr.Character
            if c then
                local hum, root = c:FindFirstChild("Humanoid"), c:FindFirstChild("HumanoidRootPart")
                if hum and root and hum.Health > 0 then
                    local _, isEnemy = classify(plr, teams[plr])
                    if isEnemy then
                        local spawnAge = tick() - (spawnTimes[plr] or 0)
                        local spawnOK = spawnAge >= CFG.Aim.SpawnProtect
                        local baitOK = not CFG.Aim.BaitProtect or not isBait(hum, root)
                        if spawnOK and baitOK and not isAFK(hum, root) then
                            local part = getHitPart(c, CFG.Aim.Part) or root
                            if part and (not CFG.Aim.VisibleCheck or isVisible(part, c)) then
                                local pos = part.Position
                                local dist = (camPos - pos).Magnitude
                                local sp, on = Cam:WorldToScreenPoint(pos)
                                if on then
                                    local d = (Vector2.new(sp.X, sp.Y) - vpCenter).Magnitude
                                    if d <= math.max(dynamicFOV(dist), aimFOV) and dist <= maxD then
                                        candidates[#candidates+1] = {pos = pos, part = part, plr = plr, dist = dist, hp = hum.Health, screen = d}
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    if #candidates == 0 then return nil end
    local best = candidates[1]
    for i = 2, #candidates do
        local cand = candidates[i]
        local score, bestScore
        if CFG.Aim.Priority == "LowHP" then score, bestScore = cand.hp, best.hp
        elseif CFG.Aim.Priority == "Closest" then score, bestScore = cand.dist, best.dist
        else score, bestScore = cand.screen, best.screen end
        if score < bestScore then best = cand end
    end
    return best
end

local function aimAt(target)
    if not target then aim.lastTarget = nil; aim.fatigueStart = 0; return end

    if aim.lastTarget ~= target.part then
        aim.lastTarget = target.part
        aim.lockStart = tick()
        aim.missThisShot = math.random() < missChance(target.dist)
        aim.overshootAmt = (math.random() - 0.5) * CFG.Aim.Overshoot
        if not aim.fatigueStart or aim.fatigueStart == 0 then aim.fatigueStart = tick() end
        return
    end

    local reactionDelay = CFG.Aim.ReactionMin + math.random() * (CFG.Aim.ReactionMax - CFG.Aim.ReactionMin)
    if tick() - aim.lockStart < reactionDelay then return end

    local fatigue = fatigueFactor()
    local targetPos = target.pos
    if target.part then
        local vel = target.part.AssemblyLinearVelocity or Vector3.zero
        targetPos = targetPos + vel * 0.12
    end

    if aim.missThisShot then
        targetPos = targetPos + Vector3.new(
            (math.random() - 0.5) * 4 * (1 + fatigue),
            (math.random() - 0.5) * 4 * (1 + fatigue),
            (math.random() - 0.5) * 4 * (1 + fatigue)
        )
    end

    targetPos = targetPos + Vector3.new(
        aim.overshootAmt * (math.random() - 0.5),
        aim.overshootAmt * (math.random() - 0.5),
        0
    )

    if fatigue > 0 and math.random() < fatigue * 0.3 then
        targetPos = targetPos + Vector3.new(
            (math.random() - 0.5) * 3, (math.random() - 0.5) * 3, (math.random() - 0.5) * 3
        )
    end

    if CFG.Aim.Jitter > 0 then
        targetPos = targetPos + Vector3.new(
            (math.random() - 0.5) * CFG.Aim.Jitter,
            (math.random() - 0.5) * CFG.Aim.Jitter,
            (math.random() - 0.5) * CFG.Aim.Jitter
        )
    end

    local camCF = Cam.CFrame
    if CFG.Aim.Mode == "Silent" then
        local bend = Vector3.new(
            (math.random() - 0.5) * CFG.Aim.BezierBend,
            (math.random() - 0.5) * CFG.Aim.BezierBend,
            (math.random() - 0.5) * CFG.Aim.BezierBend
        )
        local bentLook = CFrame.lookAt(camCF.Position, targetPos + bend)
        local old = camCF
        Cam.CFrame = bentLook
        RunService.RenderStepped:Wait()
        Cam.CFrame = old
    else
        local ideal = CFrame.lookAt(camCF.Position, targetPos)
        local smoothA = 0.3 + math.random() * 0.15
        Cam.CFrame = camCF:Lerp(ideal, smoothA)
    end
end

-- FOV circle
local fovCircle = Drawing.new("Circle")
fovCircle.Thickness = 1; fovCircle.Transparency = 0.5
fovCircle.NumSides = 60; fovCircle.Visible = false
local function updateFOV()
    if CFG.Aim.Enabled then
        fovCircle.Position = vpCenter
        fovCircle.Radius = CFG.Aim.BaseFOV
        fovCircle.Color = Color3.fromRGB(255, 200, 60)
        fovCircle.Visible = true
    else fovCircle.Visible = false end
end

-- ============================================================
--  SELF PROTECTION
-- ============================================================
local function antiFling()
    if not CFG.Self.AntiFling or not LP.Character then return end
    local hrp = LP.Character:FindFirstChild("HumanoidRootPart")
    if hrp and hrp.AssemblyLinearVelocity.Magnitude > 500 then
        hrp.AssemblyLinearVelocity = Vector3.zero
        hrp.AssemblyAngularVelocity = Vector3.zero
    end
end

local function antiRagdoll()
    if not CFG.Self.AntiRagdoll or not localHum then return end
    if localHum.PlatformStand then localHum.PlatformStand = false end
    if localHum:GetState() == Enum.HumanoidStateType.Physics then
        localHum:ChangeState(Enum.HumanoidStateType.Running)
    end
end

LP.CharacterAdded:Connect(function()
    task.wait(0.5)
    if CFG.Self.SafeRespawn and lastPos ~= Vector3.zero then
        local hrp = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
        if hrp then hrp.CFrame = CFrame.new(lastPos + Vector3.new(0, 3, 0)) end
    end
end)

-- ============================================================
--  ГЛАВНЫЙ ЦИКЛ
-- ============================================================
local aimHeld = false
local running = true
local espAcc = 0
local frameCount, fpsAcc = 0, 0
local currentFPS = 0

function unloadAll()
    running = false
    for _, o in pairs(espObjects) do
        for _, d in pairs(o) do
            if typeof(d) == "table" then for _, l in pairs(d) do pcall(function() l:Remove() end) end
            else pcall(function() d:Remove() end) end
        end
    end
    for _, h in pairs(highlights) do pcall(function() h:Destroy() end) end
    pcall(function() fovCircle:Remove() end)
    if localHum then localHum.WalkSpeed = 16 end
    gui:Destroy()
end

UIS.InputBegan:Connect(function(i, gp)
    if gp then return end
    local k = i.KeyCode
    if k == CFG.Keys.ToggleUI then main.Visible = not main.Visible
    elseif k == CFG.Keys.ToggleESP then CFG.ESP.Enabled = not CFG.ESP.Enabled
    elseif k == CFG.Keys.ToggleAim then CFG.Aim.Enabled = not CFG.Aim.Enabled
    elseif k == CFG.Keys.AimKey then aimHeld = true; aim.fatigueStart = tick()
    elseif k == CFG.Keys.Unload then unloadAll() end
end)
UIS.InputEnded:Connect(function(i)
    if i.KeyCode == CFG.Keys.AimKey then aimHeld = false; aim.fatigueStart = 0; aim.lastTarget = nil end
end)

RunService.Heartbeat:Connect(function(dt)
    if not running then return end
    frameCount = frameCount + 1
    fpsAcc = fpsAcc + dt
    if fpsAcc >= 0.5 then
        currentFPS = math.floor(frameCount / fpsAcc)
        statsLabel.Text = string.format("FPS: %d | K: %d", currentFPS, stats.kills)
        frameCount, fpsAcc = 0, 0
    end

    -- Self protection
    antiFling()
    antiRagdoll()

    -- Track position for safe respawn
    if CFG.Self.SafeRespawn and LP.Character then
        local hrp = LP.Character:FindFirstChild("HumanoidRootPart")
        if hrp and hrp.Position.Y > -50 then lastPos = hrp.Position end
    end

    -- ESP
    espAcc = espAcc + dt
    local hz = 1 / CFG.ESP.UpdateHz
    if espAcc >= hz then
        espAcc = 0
        if CFG.ESP.Enabled then updateESP()
        else
            for _, o in pairs(espObjects) do
                o.box.Visible, o.name.Visible, o.dist.Visible = false, false, false
                o.hpBg.Visible, o.hpFill.Visible, o.tracer.Visible = false, false, false
                for _, l in pairs(o.skeleton) do l.Visible = false end
            end
            for _, h in pairs(highlights) do if h then h.Enabled = false end end
        end
        updateFOV()
    end
end)

RunService.RenderStepped:Connect(function()
    if not running then return end
    if CFG.Aim.Enabled and aimHeld then
        aimAt(getTarget())
    end
end)

print("[Cold War v7 — Apex] Loaded.")
print("RightShift=UI, Insert=ESP, Home=Aim, Q=hold, End=unload")
print("LMB-Only aim ON by default (наводка только при выстреле).")
