--[[
    ⚔️ Blade Ball Hub v2.0
    Features: Auto Parry + Bezier Avoidance + Target System
              Auto Ability + Protect from Cooldown
              Spam Parry | Farm Suite | Look Tracker | Ability ESP
    Compatible: Solara Executor
]]

-- ════════════════════════════════
-- SERVICES
-- ════════════════════════════════
local Players         = game:GetService("Players")
local RunService      = game:GetService("RunService")
local TweenService    = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local lp     = Players.LocalPlayer
local camera = workspace.CurrentCamera

-- ════════════════════════════════
-- SETTINGS
-- ════════════════════════════════
local S = {
    -- ⚔️ Auto Parry
    AutoParry            = true,
    PlayGrabAnim         = true,
    ParryTrainingBalls   = true,
    AvoidCurvedBezier    = true,
    AutoSpamParry        = true,
    SpamThreshold        = 12,       -- studs — start spam at this distance

    -- Targeting
    Target               = "Vulnerable", -- "Nearest" | "Specific" | "Vulnerable"
    TargetSpecific       = "",
    AvoidDangerous       = true,

    -- Direction
    CurveDir             = "Normal", -- "Normal" | "Inverted" | "Accelerated"
    CurveAtTarget        = true,

    -- ⚔️ Auto Ability
    AutoAbility          = true,
    ProtectFromCooldown  = true,

    -- ⚔️ Spam Parry (manual toggle)
    SpamParry            = false,

    -- 📦 Farm
    AutoCollectRewards   = true,
    CollectBattlepass    = true,
    CollectClassic       = true,
    CollectLegacy        = true,
    AutoCollectRelics    = false,
    AutoOpenCrates       = true,
    OpenSwordCrates      = true,
    OpenExplosionCrates  = true,
    AutoSpinWheels       = true,
    SpinDefault          = true,
    SpinBattlepass       = true,
    CollectCodes         = true,

    -- 👁️ Visuals
    LookTracker          = true,
    AbilityESP           = true,
}

-- Abilities that mark a player as dangerous
local DANGEROUS = {
    "forcefield","time hole","timehole","infinity",
    "slashes of fury","slashesoffury","singularity"
}

-- Known redeem codes
local CODES = {
    "BLADEBALL","ANNIVERSARY","BBFALL","BBALL2024",
    "RELEASE","UPDATE","NEWBLADE","1MILLION",
    "SORRY","FIXEDSTATS","BBHYPE","CIRCUIT",
    "SPOOKY","HALLOWEEN","FROST","WINTER",
    "SPRING","SUMMER","NEWMAP","REVAMP",
    "BBUPDATE","BBNEW","CRATES","SPINNER"
}

-- ════════════════════════════════
-- CHARACTER REFS
-- ════════════════════════════════
local char, hrp, humanoid

local function refreshChar()
    char     = lp.Character
    hrp      = char and char:FindFirstChild("HumanoidRootPart")
    humanoid = char and char:FindFirstChild("Humanoid")
end

refreshChar()
lp.CharacterAdded:Connect(function(c)
    char     = c
    hrp      = c:WaitForChild("HumanoidRootPart")
    humanoid = c:WaitForChild("Humanoid")
end)

-- ════════════════════════════════
-- REMOTE FINDER (cached)
-- ════════════════════════════════
local _remoteCache = {}

local function findRemote(keys)
    local ck = table.concat(keys,"_")
    if _remoteCache[ck] then return _remoteCache[ck] end
    for _, obj in ipairs(game:GetDescendants()) do
        if obj:IsA("RemoteEvent") or obj:IsA("RemoteFunction") then
            local n = obj.Name:lower()
            for _, k in ipairs(keys) do
                if n:find(k) then
                    _remoteCache[ck] = obj
                    return obj
                end
            end
        end
    end
end

-- ════════════════════════════════
-- BALL DETECTION
-- ════════════════════════════════
local ballHistory = {}

local function findBall()
    local b = workspace:FindFirstChild("Ball")
    if b and b:IsA("BasePart") then return b end
    for _, v in ipairs(workspace:GetDescendants()) do
        if v:IsA("BasePart") and v.Name == "Ball" and v.Size.Magnitude < 8 then
            return v
        end
    end
end

local function isBezierCurved()
    if #ballHistory < 6 then return false end
    local s = ballHistory[1]
    local e = ballHistory[#ballHistory]
    local dir = (e - s)
    if dir.Magnitude < 0.01 then return false end
    dir = dir.Unit
    local maxDev = 0
    for i = 2, #ballHistory - 1 do
        local p = ballHistory[i]
        local proj = s + dir * (p - s):Dot(dir)
        local dev = (p - proj).Magnitude
        if dev > maxDev then maxDev = dev end
    end
    return maxDev > 2.5
end

-- ════════════════════════════════
-- TARGETING
-- ════════════════════════════════
local parryTimestamps = {}
local PARRY_CD = 0.75

local function isDangerous(plr)
    if not plr.Character then return false end
    if plr.Character:FindFirstChildOfClass("ForceField") then return true end
    for _, obj in ipairs(plr.Character:GetDescendants()) do
        local n = obj.Name:lower()
        for _, d in ipairs(DANGEROUS) do
            if n:find(d) then return true end
        end
    end
    return false
end

local function isVulnerable(plr)
    local ts = parryTimestamps[plr.UserId]
    return not ts or (tick() - ts > PARRY_CD)
end

local function getTarget()
    if not hrp then return nil end
    local pool = {}
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr == lp then continue end
        if not plr.Character then continue end
        local ohrp = plr.Character:FindFirstChild("HumanoidRootPart")
        if not ohrp then continue end
        if S.AvoidDangerous and isDangerous(plr) then continue end
        table.insert(pool, plr)
    end

    if S.Target == "Specific" and S.TargetSpecific ~= "" then
        for _, p in ipairs(pool) do
            if p.Name == S.TargetSpecific then return p end
        end
    end

    if S.Target == "Vulnerable" then
        local vpool = {}
        for _, p in ipairs(pool) do
            if isVulnerable(p) then table.insert(vpool, p) end
        end
        if #vpool > 0 then pool = vpool end
    end

    table.sort(pool, function(a, b)
        local da = (hrp.Position - a.Character.HumanoidRootPart.Position).Magnitude
        local db = (hrp.Position - b.Character.HumanoidRootPart.Position).Magnitude
        return da < db
    end)

    return pool[1]
end

-- ════════════════════════════════
-- GRAB ANIMATION
-- ════════════════════════════════
local grabTrack = nil
local GRAB_ANIM_ID = "rbxassetid://13170172810"

local function playGrabAnim()
    if not S.PlayGrabAnim or not humanoid then return end
    local animator = humanoid:FindFirstChildOfClass("Animator")
    if not animator then return end
    if not grabTrack then
        local a = Instance.new("Animation")
        a.AnimationId = GRAB_ANIM_ID
        grabTrack = animator:LoadAnimation(a)
        grabTrack.Priority = Enum.AnimationPriority.Action
    end
    if not grabTrack.IsPlaying then grabTrack:Play() end
end

-- ════════════════════════════════
-- AUTO PARRY
-- ════════════════════════════════
local lastParry   = 0
local parryRemote = nil
local MIN_PARRY_INTERVAL = 0.28

local function doParry()
    local now = tick()
    if now - lastParry < MIN_PARRY_INTERVAL then return false end

    if not parryRemote then
        parryRemote = findRemote({"parr","deflect","block","swing","hit"})
    end
    if not parryRemote then return false end

    local args = {}
    local target = getTarget()
    if target and target.Character and S.CurveAtTarget and S.CurveDir ~= "Normal" then
        args[1] = target.Character.HumanoidRootPart.Position
    end

    pcall(function()
        if #args > 0 then parryRemote:FireServer(table.unpack(args))
        else parryRemote:FireServer() end
    end)

    lastParry = now
    parryTimestamps[lp.UserId] = now
    playGrabAnim()
    return true
end

-- ════════════════════════════════
-- AUTO ABILITY
-- ════════════════════════════════
local lastAbility    = 0
local ABILITY_CD     = 1.0
local PACKET_TIME    = 0.08
local abilityRemote  = nil

local function doAbility()
    local now = tick()
    if now - lastAbility < ABILITY_CD then return end
    if not abilityRemote then
        abilityRemote = findRemote({"ability","skill","power","activate","use"})
    end
    if abilityRemote then
        pcall(function() abilityRemote:FireServer() end)
        lastAbility = now
    end
end

local function checkProtect(ball)
    if not S.ProtectFromCooldown or not ball or not hrp then return end
    local spd = ball.AssemblyLinearVelocity.Magnitude
    if spd < 1 then return end
    local dist = (hrp.Position - ball.Position).Magnitude
    local reach = dist / spd
    if reach < PACKET_TIME + 0.06 then
        if tick() - lastParry > MIN_PARRY_INTERVAL + 0.1 then
            doAbility()
        end
    end
end

-- ════════════════════════════════
-- FARM
-- ════════════════════════════════
local function collectRewards()
    for _, obj in ipairs(game:GetDescendants()) do
        if obj:IsA("RemoteEvent") then
            local n = obj.Name:lower()
            if S.CollectBattlepass and n:find("battlepass") then
                pcall(function() obj:FireServer() end)
            end
            if S.CollectClassic and n:find("classic") then
                pcall(function() obj:FireServer() end)
            end
            if S.CollectLegacy and n:find("legacy") then
                pcall(function() obj:FireServer() end)
            end
        end
    end
    for _, g in ipairs(lp.PlayerGui:GetDescendants()) do
        if (g:IsA("TextButton") or g:IsA("ImageButton")) then
            local n = g.Name:lower()
            if n:find("claim") or n:find("collect") then
                pcall(function() g.Activated:Fire() end)
            end
        end
    end
end

local function collectRelics()
    if not hrp then return end
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("BasePart") and obj.Name:lower():find("relic") then
            pcall(function() hrp.CFrame = obj.CFrame + Vector3.new(0,3,0) end)
            task.wait(0.15)
        end
    end
end

local function openCrates()
    for _, obj in ipairs(game:GetDescendants()) do
        if obj:IsA("RemoteEvent") then
            local n = obj.Name:lower()
            if S.OpenSwordCrates and n:find("sword") and n:find("crate") then
                pcall(function() obj:FireServer() end) task.wait(0.2)
            end
            if S.OpenExplosionCrates and n:find("explosion") and n:find("crate") then
                pcall(function() obj:FireServer() end) task.wait(0.2)
            end
        end
    end
end

local function spinWheels()
    for _, obj in ipairs(game:GetDescendants()) do
        if obj:IsA("RemoteEvent") then
            local n = obj.Name:lower()
            if S.SpinDefault and n:find("wheel") and not n:find("battle") then
                pcall(function() obj:FireServer() end) task.wait(0.3)
            end
            if S.SpinBattlepass and n:find("wheel") and n:find("battle") then
                pcall(function() obj:FireServer() end) task.wait(0.3)
            end
        end
    end
end

local redeemed = {}
local function redeemCodes()
    local rem = findRemote({"redeem","code","coupon","promo"})
    if not rem then return end
    for _, code in ipairs(CODES) do
        if not redeemed[code] then
            pcall(function() rem:FireServer(code) end)
            redeemed[code] = true
            task.wait(0.4)
        end
    end
end

-- ════════════════════════════════
-- LOOK TRACKER (Drawing)
-- ════════════════════════════════
local lookLines = {}

local function updateLookTracker()
    for plrName, line in pairs(lookLines) do
        if not Players:FindFirstChild(plrName) then
            pcall(function() line.Visible = false end)
            lookLines[plrName] = nil
        end
    end

    if not S.LookTracker then
        for _, l in pairs(lookLines) do pcall(function() l.Visible = false end) end
        return
    end

    for _, plr in ipairs(Players:GetPlayers()) do
        if plr == lp or not plr.Character then continue end
        local head = plr.Character:FindFirstChild("Head")
        if not head then continue end

        if not lookLines[plr.Name] then
            local l = Drawing.new("Line")
            l.Thickness = 2
            l.Color = Color3.fromRGB(255, 140, 0)
            l.Transparency = 0.6
            l.Visible = true
            lookLines[plr.Name] = l
        end

        local line = lookLines[plr.Name]
        local sp, onScreen = camera:WorldToViewportPoint(head.Position)
        local ep, epOnScreen = camera:WorldToViewportPoint(head.Position + head.CFrame.LookVector * 6)

        if onScreen and epOnScreen then
            line.From = Vector2.new(sp.X, sp.Y)
            line.To   = Vector2.new(ep.X, ep.Y)
            line.Visible = true
        else
            line.Visible = false
        end
    end
end

-- Look at Soul: teleport to target's camera origin
local function lookAtSoul(targetName)
    local target = Players:FindFirstChild(targetName)
    if not target or not target.Character or not hrp then return end
    local h = target.Character:FindFirstChild("Head")
    if h then hrp.CFrame = h.CFrame * CFrame.new(0, 0, -3) end
end

-- ════════════════════════════════
-- ABILITY ESP (Drawing)
-- ════════════════════════════════
local espLabels = {}

local function updateAbilityESP()
    for plrName, lbl in pairs(espLabels) do
        if not Players:FindFirstChild(plrName) then
            pcall(function() lbl.Visible = false end)
            espLabels[plrName] = nil
        end
    end

    if not S.AbilityESP then
        for _, l in pairs(espLabels) do pcall(function() l.Visible = false end) end
        return
    end

    for _, plr in ipairs(Players:GetPlayers()) do
        if plr == lp or not plr.Character then continue end
        local ohrp = plr.Character:FindFirstChild("HumanoidRootPart")
        if not ohrp then continue end

        if not espLabels[plr.Name] then
            local l = Drawing.new("Text")
            l.Size = 13
            l.Font = Drawing.Fonts.UI
            l.Outline = true
            l.Color = Color3.fromRGB(255, 215, 0)
            l.Visible = true
            espLabels[plr.Name] = l
        end

        local lbl = espLabels[plr.Name]
        local wpos = ohrp.Position + Vector3.new(0, 3.8, 0)
        local sp, onScreen = camera:WorldToViewportPoint(wpos)

        if onScreen then
            -- Attempt to read ability name from character
            local abilityName = "Unknown"
            for _, obj in ipairs(plr.Character:GetDescendants()) do
                if obj:IsA("Tool") then abilityName = obj.Name break end
                if obj:IsA("StringValue") and obj.Name:lower():find("ability") then
                    abilityName = obj.Value break
                end
            end

            -- Cooldown display
            local cdStr = ""
            local ts = parryTimestamps[plr.UserId]
            if ts then
                local elapsed = tick() - ts
                if elapsed < PARRY_CD then
                    cdStr = string.format(" [CD %.1fs]", PARRY_CD - elapsed)
                end
            end

            lbl.Text = abilityName .. cdStr
            lbl.Position = Vector2.new(sp.X - 30, sp.Y)
            lbl.Visible = true
        else
            lbl.Visible = false
        end
    end
end

-- ════════════════════════════════
-- GUI
-- ════════════════════════════════
local sg = Instance.new("ScreenGui")
sg.Name = "BBHubV2"
sg.ResetOnSpawn = false
sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
local ok = pcall(function() sg.Parent = game:GetService("CoreGui") end)
if not ok then sg.Parent = lp.PlayerGui end

local Win = Instance.new("Frame")
Win.Size = UDim2.new(0, 290, 0, 480)
Win.Position = UDim2.new(0, 16, 0.5, -240)
Win.BackgroundColor3 = Color3.fromRGB(11, 11, 17)
Win.BorderSizePixel = 0
Win.Active = true
Win.Draggable = true
Win.ClipDescendants = true
Win.Parent = sg
Instance.new("UICorner", Win).CornerRadius = UDim.new(0, 10)

-- Title
local TB = Instance.new("Frame")
TB.Size = UDim2.new(1, 0, 0, 38)
TB.BackgroundColor3 = Color3.fromRGB(70, 20, 170)
TB.BorderSizePixel = 0
TB.Parent = Win
Instance.new("UICorner", TB).CornerRadius = UDim.new(0, 10)

local TL = Instance.new("TextLabel")
TL.Size = UDim2.new(1, -10, 1, 0)
TL.Position = UDim2.new(0, 10, 0, 0)
TL.BackgroundTransparency = 1
TL.Text = "⚔️  Blade Ball Hub  v2.0"
TL.TextColor3 = Color3.fromRGB(255, 255, 255)
TL.TextSize = 13
TL.Font = Enum.Font.GothamBold
TL.TextXAlignment = Enum.TextXAlignment.Left
TL.Parent = TB

-- Scroll
local Scroll = Instance.new("ScrollingFrame")
Scroll.Size = UDim2.new(1, 0, 1, -60)
Scroll.Position = UDim2.new(0, 0, 0, 42)
Scroll.BackgroundTransparency = 1
Scroll.BorderSizePixel = 0
Scroll.ScrollBarThickness = 3
Scroll.ScrollBarImageColor3 = Color3.fromRGB(100, 40, 200)
Scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
Scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
Scroll.Parent = Win

local LL = Instance.new("UIListLayout")
LL.SortOrder = Enum.SortOrder.LayoutOrder
LL.Padding = UDim.new(0, 3)
LL.Parent = Scroll

local LP = Instance.new("UIPadding")
LP.PaddingLeft = UDim.new(0, 7)
LP.PaddingRight = UDim.new(0, 7)
LP.PaddingTop = UDim.new(0, 5)
LP.Parent = Scroll

local _order = 0
local function nextOrder() _order = _order + 1 return _order end

local function mkSection(txt)
    local f = Instance.new("TextLabel")
    f.Size = UDim2.new(1, 0, 0, 22)
    f.BackgroundColor3 = Color3.fromRGB(70, 20, 170)
    f.TextColor3 = Color3.fromRGB(255, 255, 255)
    f.Text = "  " .. txt
    f.TextSize = 11
    f.Font = Enum.Font.GothamBold
    f.TextXAlignment = Enum.TextXAlignment.Left
    f.BorderSizePixel = 0
    f.LayoutOrder = nextOrder()
    f.Parent = Scroll
    Instance.new("UICorner", f).CornerRadius = UDim.new(0, 5)
end

local function mkToggle(label, key, indent)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, 0, 0, 30)
    row.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
    row.BorderSizePixel = 0
    row.LayoutOrder = nextOrder()
    row.Parent = Scroll
    Instance.new("UICorner", row).CornerRadius = UDim.new(0, 6)

    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(0.73, 0, 1, 0)
    lbl.Position = UDim2.new(0, indent and 18 or 10, 0, 0)
    lbl.BackgroundTransparency = 1
    lbl.Text = label
    lbl.TextColor3 = indent and Color3.fromRGB(180,180,180) or Color3.fromRGB(220,220,220)
    lbl.TextSize = 11
    lbl.Font = Enum.Font.Gotham
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Parent = row

    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(0, 40, 0, 18)
    btn.Position = UDim2.new(1, -48, 0.5, -9)
    btn.BackgroundColor3 = S[key] and Color3.fromRGB(80,30,180) or Color3.fromRGB(50,50,62)
    btn.Text = ""
    btn.BorderSizePixel = 0
    btn.Parent = row
    Instance.new("UICorner", btn).CornerRadius = UDim.new(1,0)

    local knob = Instance.new("Frame")
    knob.Size = UDim2.new(0, 13, 0, 13)
    knob.Position = S[key] and UDim2.new(1,-16,0.5,-6.5) or UDim2.new(0,3,0.5,-6.5)
    knob.BackgroundColor3 = Color3.fromRGB(255,255,255)
    knob.BorderSizePixel = 0
    knob.Parent = btn
    Instance.new("UICorner", knob).CornerRadius = UDim.new(1,0)

    btn.MouseButton1Click:Connect(function()
        S[key] = not S[key]
        local on = S[key]
        TweenService:Create(btn, TweenInfo.new(0.15), {
            BackgroundColor3 = on and Color3.fromRGB(80,30,180) or Color3.fromRGB(50,50,62)
        }):Play()
        TweenService:Create(knob, TweenInfo.new(0.15), {
            Position = on and UDim2.new(1,-16,0.5,-6.5) or UDim2.new(0,3,0.5,-6.5)
        }):Play()
    end)
end

-- Build sections
mkSection("⚔️  Combat")
mkToggle("Auto Parry",                "AutoParry",           false)
mkToggle("Play Grab Animation",       "PlayGrabAnim",        true)
mkToggle("Parry Training Balls",      "ParryTrainingBalls",  true)
mkToggle("Avoid Curved Bezier",       "AvoidCurvedBezier",   true)
mkToggle("Auto Spam Parry",           "AutoSpamParry",       true)
mkToggle("Avoid Dangerous Players",   "AvoidDangerous",      true)
mkToggle("Auto Ability",              "AutoAbility",         false)
mkToggle("Protect from Cooldown",     "ProtectFromCooldown", true)
mkToggle("Spam Parry (manual)",       "SpamParry",           false)

mkSection("📦  Farm")
mkToggle("Auto Collect Rewards",      "AutoCollectRewards",  false)
mkToggle("Battlepass Rewards",        "CollectBattlepass",   true)
mkToggle("Classic Rewards",           "CollectClassic",      true)
mkToggle("Legacy Rewards",            "CollectLegacy",       true)
mkToggle("Auto Collect Relics",       "AutoCollectRelics",   false)
mkToggle("Auto Open Crates",          "AutoOpenCrates",      false)
mkToggle("Sword Crates",              "OpenSwordCrates",     true)
mkToggle("Explosion Crates",          "OpenExplosionCrates", true)
mkToggle("Auto Spin Wheels",          "AutoSpinWheels",      false)
mkToggle("Default Wheel",             "SpinDefault",         true)
mkToggle("Battlepass Wheel",          "SpinBattlepass",      true)
mkToggle("Collect Codes",             "CollectCodes",        false)

mkSection("👁️  Visuals")
mkToggle("Look Tracker",              "LookTracker",         false)
mkToggle("Ability ESP",               "AbilityESP",          false)

-- Status bar
local SB = Instance.new("Frame")
SB.Size = UDim2.new(1, 0, 0, 20)
SB.Position = UDim2.new(0, 0, 1, -20)
SB.BackgroundColor3 = Color3.fromRGB(18, 18, 26)
SB.BorderSizePixel = 0
SB.Parent = Win

local ST = Instance.new("TextLabel")
ST.Size = UDim2.new(1, -10, 1, 0)
ST.Position = UDim2.new(0, 10, 0, 0)
ST.BackgroundTransparency = 1
ST.Text = "● Active"
ST.TextColor3 = Color3.fromRGB(100, 220, 100)
ST.TextSize = 10
ST.Font = Enum.Font.Gotham
ST.TextXAlignment = Enum.TextXAlignment.Left
ST.Parent = SB

-- ════════════════════════════════
-- FARM TIMERS
-- ════════════════════════════════
task.spawn(function()
    task.wait(2)
    if S.CollectCodes then pcall(redeemCodes) end
end)

task.spawn(function()
    while true do
        task.wait(6)
        if S.AutoCollectRewards  then pcall(collectRewards) end
        if S.AutoCollectRelics   then pcall(collectRelics)  end
    end
end)

task.spawn(function()
    while true do
        task.wait(35)
        if S.AutoOpenCrates  then pcall(openCrates)  end
        if S.AutoSpinWheels  then pcall(spinWheels)  end
    end
end)

-- ════════════════════════════════
-- BALL HISTORY TRACKER
-- ════════════════════════════════
task.spawn(function()
    while true do
        task.wait(0.05)
        local b = findBall()
        if b and b.Parent then
            table.insert(ballHistory, b.Position)
            if #ballHistory > 10 then table.remove(ballHistory, 1) end
        else
            ballHistory = {}
        end
    end
end)

-- ════════════════════════════════
-- MAIN LOOP
-- ════════════════════════════════
local frame = 0

RunService.Heartbeat:Connect(function()
    frame = frame + 1

    if not char or not hrp then refreshChar() return end

    local ball = findBall()

    -- ── Auto Parry ──
    if S.AutoParry and ball and ball.Parent then
        local dist = (hrp.Position - ball.Position).Magnitude

        -- Training ball check
        local isTrain = false
        if ball.Parent and ball.Parent.Name:lower():find("train") then isTrain = true end
        if isTrain and not S.ParryTrainingBalls then goto skipParry end

        -- Bezier avoidance
        if S.AvoidCurvedBezier and isBezierCurved() then
            ST.Text = "⚠ Curved — avoiding"
            ST.TextColor3 = Color3.fromRGB(255, 170, 0)
            goto skipParry
        end

        if dist <= 24 then
            if S.AutoSpamParry and dist <= S.SpamThreshold then
                -- Spam burst
                doParry()
                task.wait(0.04)
                doParry()
                ST.Text = "⚡ Spam parry! dist: " .. math.floor(dist)
                ST.TextColor3 = Color3.fromRGB(255, 80, 80)
            else
                local parried = doParry()
                if parried then
                    ST.Text = "✓ Parried! dist: " .. math.floor(dist)
                    ST.TextColor3 = Color3.fromRGB(100, 220, 100)
                end
            end
        end

        ::skipParry::

        -- Protect from cooldown
        if S.AutoAbility then
            checkProtect(ball)
        end
    end

    -- ── Manual Spam Parry ──
    if S.SpamParry then
        doParry()
    end

    -- ── Visuals (every 3 frames) ──
    if frame % 3 == 0 then
        pcall(updateLookTracker)
        pcall(updateAbilityESP)
    end
end)

-- Load notification
pcall(function()
    game:GetService("StarterGui"):SetCore("SendNotification", {
        Title   = "⚔️ Blade Ball Hub",
        Text    = "Loaded! Auto Parry active.",
        Duration = 4,
    })
end)

print("[BBHub v2.0] Ready.")
