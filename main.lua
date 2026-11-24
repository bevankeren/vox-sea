--[[
    BeverlyHub | Vox Seas Hub - Auto Shipwreck, Side Quest & Auto Farm Level (BeverlyLIB Edition v3.1)
    Features:
      - UI BeverlyLIB (Auto Farm, Side Quests, Level Farm, Settings) + Fallback UI
      - Auto Shipwreck & Treasure Hunt v2.2 lengkap (Notif Rarity Chest, Kalkulasi Cuan, Smart Parkir Pulau Jauh, Auto-Haggle +15%)
      - Auto Side Quest (Khusus One-Time / Progression Side Quests Lv 5-310, skip repeatable)
      - Auto Farm Level (Lv 1-500, 38 Grinding Quests, Instant RepeatQuest, Auto Haki, Auto Skill Z/X/C/V, Auto Stats, Pilihan Posisi Serang)
      - Auto-abandon parkir Treasure Hunt otomatis saat QuestLimit di mode Side Quest & Level Farm
      - Generalized Realm & PrivateAreas Navigator (Pawnshop, WitchHouse, Prison Lift, Volcano Interior, Rustfall SkyLift, Phantom Ruins)
      - Velocity-clamped Heartbeat stepper (0 speed spike / anti SwimSystem conflict) + seamless multi-segmen tween
      - Generalized Heartbeat CFrame lock combat engine (anti-rock raycast, hover/back lock, HP-delta stuck detector, target skip, low-HP regen)
      - Anti-AFK (anti kick 20 menit), FPS Booster non-destruktif, & Black Screen (Disable 3D Rendering)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CoreGui = game:GetService("CoreGui")
local Lighting = game:GetService("Lighting")
local VirtualUser = game:GetService("VirtualUser")

local LocalPlayer = Players.LocalPlayer

-- Capture executor thread identity sebelum pemanggilan modul/UI agar aman dari capability issue
local executorIdentity = type(getthreadidentity) == "function" and getthreadidentity() or 8
local function restoreExecutorContext()
    if type(setthreadidentity) == "function" then
        pcall(setthreadidentity, executorIdentity)
    end
end

-- Load game modules
local ElysiumModules = require(ReplicatedStorage:WaitForChild("Elysium"):WaitForChild("Modules"))
local MainModules = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("MainModules"))

local Network = ElysiumModules.Network
local DataStoreClient = ElysiumModules.DataStore.IsClient
local TreasureHuntUtils = MainModules.TreasureHuntUtils
local ChestsUtils = MainModules.ChestsUtils
local QuestsUtils = MainModules.QuestsUtils
local QuestsInfo = MainModules.QuestsInfo
local ToolsInfo = MainModules.ToolsInfo
local ToolsUtils = MainModules.ToolsUtils
local InterestPoints = MainModules.InterestPoints
local HaggleUtils = MainModules.HaggleUtils

local QuestSystemClient = require(
    ReplicatedStorage:WaitForChild("Modules")
        :WaitForChild("Essentials")
        :WaitForChild("QuestSystem")
).IsClient

local PrivateAreasClient = require(
    ReplicatedStorage:WaitForChild("Modules")
        :WaitForChild("Essentials")
        :WaitForChild("InteractionSystem")
        :WaitForChild("InteractionSystem Client")
        :WaitForChild("PrivateAreas Client")
)

local DiggingClient = nil
pcall(function()
    DiggingClient = require(
        ReplicatedStorage:WaitForChild("Modules")
            :WaitForChild("Addons")
            :WaitForChild("QuestHandlers")
            :WaitForChild("QuestHandlers Client")
            :WaitForChild("Customs Client")
            :WaitForChild("Multiple Islands")
            :WaitForChild("Treasure Hunt")
            :WaitForChild("Digging")
    )
end)

local MinigamesClient = nil
pcall(function()
    MinigamesClient = require(
        ReplicatedStorage:WaitForChild("Modules")
            :WaitForChild("Addons")
            :WaitForChild("MinigamesSystem")
            :WaitForChild("MinigamesSystem Client")
    )
end)

-- Capture intent mode sebelum cleanup instance lama agar re-execute dengan VoxSeasConfig tetap hormati setting caller
local preExistingCfg = getgenv().VoxSeasConfig or getgenv().AutoShipwreckConfig
local preReqLevelFarm = type(preExistingCfg) == "table" and preExistingCfg.LevelFarmEnabled == true or false
local preReqSideQuest = type(preExistingCfg) == "table" and (not preReqLevelFarm) and preExistingCfg.SideQuestEnabled == true or false
local preReqShipwreck = type(preExistingCfg) == "table" and (not preReqLevelFarm) and (not preReqSideQuest) and (preExistingCfg.ShipwreckEnabled == true or preExistingCfg.Enabled == true) or false

-- Unique RunId agar instance lama otomatis berhenti total saat re-execute
local RunId = tostring(os.clock()) .. "_" .. tostring(math.random(100000, 999999))
getgenv()._AutoShipwreckRunId = RunId
getgenv()._VoxSeasRunId = RunId

if getgenv()._VoxSeasCleanup then
    pcall(getgenv()._VoxSeasCleanup)
elseif getgenv()._AutoShipwreckCleanup then
    pcall(getgenv()._AutoShipwreckCleanup)
end
restoreExecutorContext()

-- Config (mendukung getgenv().VoxSeasConfig sekaligus kompatibel dengan getgenv().AutoShipwreckConfig)
local SharedConfig = getgenv().VoxSeasConfig or getgenv().AutoShipwreckConfig or {}
getgenv().VoxSeasConfig = SharedConfig
getgenv().AutoShipwreckConfig = SharedConfig
local Config = SharedConfig

Config.LevelFarmEnabled = preReqLevelFarm
Config.SideQuestEnabled = preReqSideQuest
Config.ShipwreckEnabled = preReqShipwreck
Config.Enabled = Config.ShipwreckEnabled or Config.SideQuestEnabled or Config.LevelFarmEnabled

if Config.TweenSpeed == nil then Config.TweenSpeed = 400 end -- velocity-clamped Heartbeat stepper
if Config.CarryTweenSpeed == nil then Config.CarryTweenSpeed = 128 end -- aman tanpa spike SwimSystem
if Config.CarrySafeY == nil or (Config._Version ~= "2.2" and Config._Version ~= "3.0" and Config._Version ~= "3.1" and Config.CarrySafeY == 2) then
    Config.CarrySafeY = 6 -- di atas SwimSystem SurfaceMargin (DefaultBoneHeight 1.11 + 1.5 + wave) agar bebas Devil Fruit sink/PlatformStand
end
if Config.AirTravelY == nil then Config.AirTravelY = 25 end
if Config.NpcInteractRange == nil then Config.NpcInteractRange = 12 end
if Config.ChestSearchRadius == nil then Config.ChestSearchRadius = 450 end
if Config.ChestWaitTimeout == nil then Config.ChestWaitTimeout = 15 end
if Config.AutoHaggle == nil then Config.AutoHaggle = true end
if Config.NotifyChestRarity == nil then Config.NotifyChestRarity = true end
if Config.MaxTreasureHuntDist == nil then Config.MaxTreasureHuntDist = 3600 end -- 3600 parkir #2..#10 (sisa #1 3.3k + Shipwreck)
if Config.ParkFarTreasureHunts == nil then Config.ParkFarTreasureHunts = true end
if Config.LoopDelay == nil then Config.LoopDelay = 0.35 end
if Config.AntiAFK == nil then Config.AntiAFK = true end
if Config.FPSBoost == nil then Config.FPSBoost = true end
if Config.BlackScreen3D == nil then Config.BlackScreen3D = false end
if Config.SideQuestIsland == nil or Config.SideQuestIsland == "Semua Pulau" then Config.SideQuestIsland = "All Islands" end
if Config.SideQuestTarget == nil or Config.SideQuestTarget == "Auto Semua Eligible" then Config.SideQuestTarget = "Auto (All Eligible)" end
Config.SideQuestAutoAbandonTH = true
Config.SideQuestIncludeMinigames = true
if Config.LevelFarmMode == nil then Config.LevelFarmMode = "Auto Best Quest" end
if Config.LevelFarmTarget == nil or Config.LevelFarmTarget == "Auto (Sesuai Level)" then Config.LevelFarmTarget = "Auto (Best XP)" end
if Config.LevelFarmAttackPos == nil or Config.LevelFarmAttackPos == "Belakang (Stabil)" then
    Config.LevelFarmAttackPos = "Behind"
elseif Config.LevelFarmAttackPos == "Atas (Aman)" then
    Config.LevelFarmAttackPos = "Above"
end
Config.LevelFarmUseRepeat = true
if Config.LevelFarmIncludeBoss == nil then Config.LevelFarmIncludeBoss = false end
Config.LevelFarmAutoHaki = true
if Config.LevelFarmAutoSkills == nil then Config.LevelFarmAutoSkills = true end
Config.LevelFarmAutoAbandonTH = true
Config.LevelFarmStopAtMax = true
if Config.LevelFarmAutoStats == nil then Config.LevelFarmAutoStats = false end
if Config.LevelFarmStatTarget == nil then Config.LevelFarmStatTarget = "Sword" end
if Config.WebhookEnabled == nil then Config.WebhookEnabled = false end
if Config.WebhookUrl == nil then Config.WebhookUrl = "" end
if Config.WebhookPingId == nil then Config.WebhookPingId = "" end
if Config.WebhookOnLevelUp == nil then Config.WebhookOnLevelUp = true end
if Config.WebhookOnRareChest == nil then Config.WebhookOnRareChest = true end
if Config.WebhookOnSideQuest == nil then Config.WebhookOnSideQuest = true end
if Config.WebhookOnMaxLevel == nil then Config.WebhookOnMaxLevel = true end
if Config.WebhookSummaryMin == nil then Config.WebhookSummaryMin = 0 end
Config.AutoHaggle = true
Config.NotifyChestRarity = true
Config.ParkFarTreasureHunts = true
Config.AutoAbandonTreasureHunt = false
Config._Version = "3.3"

local function getActiveMode()
    if Config.LevelFarmEnabled then return "LevelFarm" end
    if Config.SideQuestEnabled then return "SideQuest" end
    if Config.ShipwreckEnabled then return "Shipwreck" end
    return "None"
end

local function isActive(expectedMode)
    if getgenv()._AutoShipwreckRunId ~= RunId then
        return false
    end
    if expectedMode == "Shipwreck" then
        return Config.ShipwreckEnabled == true
    elseif expectedMode == "SideQuest" then
        return Config.SideQuestEnabled == true
    elseif expectedMode == "LevelFarm" then
        return Config.LevelFarmEnabled == true
    end
    return Config.ShipwreckEnabled == true or Config.SideQuestEnabled == true or Config.LevelFarmEnabled == true
end

-- Formatting helpers
local function formatNumber(n)
    local val = math.floor(tonumber(n) or 0)
    local sign = val < 0 and "-" or ""
    local s = tostring(math.abs(val))
    local formatted = s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
    return sign .. formatted
end

local function formatDuration(sec)
    local s = math.max(0, math.floor(tonumber(sec) or 0))
    local h = math.floor(s / 3600)
    local m = math.floor((s % 3600) / 60)
    local rem = s % 60
    if h > 0 then
        return string.format("%02d:%02d:%02d", h, m, rem)
    end
    return string.format("%02d:%02d", m, rem)
end

-- DataStore / Gold helpers
local function getDataStore()
    return DataStoreClient:Get()
end

local function getGold()
    local ds = getDataStore()
    if ds and ds.Monetization and ds.Monetization.Gold then
        return math.floor(ds.Monetization.Gold)
    end
    return 0
end

-- Rarity colors
local RARITY_COLORS = {
    Common = Color3.fromRGB(185, 190, 200),
    Uncommon = Color3.fromRGB(45, 225, 130),
    Rare = Color3.fromRGB(60, 175, 255),
    Epic = Color3.fromRGB(215, 80, 250),
    Legendary = Color3.fromRGB(255, 200, 45),
}

-- Telemetry & Profit Stats
local Stats = {
    RunId = RunId,
    UI = "Loading",
    StartTime = os.clock(),
    StartGold = getGold(),
    StartAntiTp = LocalPlayer:GetAttribute("AntiTeleportReverts") or 0,
    ConsecutiveChests = 0,
    TotalChestsSold = 0,
    ShipwrecksSold = 0,
    TreasureHuntsSold = 0,
    MapsBought = 0,
    HagglesWon = 0,
    GrossChestGold = 0,
    MapsSpent = 0,
    NetProfit = 0,
    GoldPerMin = 0,
    GoldPerHour = 0,
    ChestGoldEarned = 0,
    Failures = 0,
    LastChestTime = nil,
    LastChestRarity = nil,
    LastStatus = "Starting...",
    LastError = nil,
    UIUpdateError = nil,
    NotifyError = nil,
    UIPulseCount = 0,
    RarityNotifCount = 0,
    RarityCounts = {
        Common = 0,
        Uncommon = 0,
        Rare = 0,
        Epic = 0,
        Legendary = 0,
    },
    Events = {},
}
getgenv()._AutoShipwreckStats = Stats
getgenv()._AutoShipwreckLastError = nil

-- Side Quest Stats & Telemetry
local SQStats = {
    SessionCompleted = 0,
    SessionGoldStart = getGold(),
    SessionGoldEarned = 0,
    AbandonedTH = 0,
    SkippedCount = 0,
    CurrentQuest = "-",
    CurrentObjective = "-",
    LastStatus = "Idle",
    CompletedList = {},
    SkippedQuests = {}, -- [questName] = { untilTime = os.clock()+..., reason = "..." }
}
getgenv()._VoxSeasSQStats = SQStats

local function logEvent(msg)
    local elapsed = math.floor(os.clock() - Stats.StartTime)
    table.insert(Stats.Events, string.format("[%ds] %s", elapsed, tostring(msg)))
    if #Stats.Events > 30 then
        table.remove(Stats.Events, 1)
    end
end

local ActiveMoveToken = 0
local NoclipConn = nil
local NoclipOrigCollide = {}
local NoclipCachedChar = nil
local NoclipCachedParts = {}
local NoclipDescConn = nil
local CombatLockConn = nil
local AntiAFKConn = nil
local AntiAFKRunning = false
local FPSBoostActive = false
local FPSBoostDescConn = nil
local FPSBoostSaved = {
    Lighting = {},
    Effects = {},
    Terrain = {},
    Parts = {},
    Visuals = {},
}
local BlackScreenGui = nil
local BlackScreenLabel = nil
local BlackScreenToggle = nil
local UIAlive = true
local CurrentChestRarity = nil

-- UI References
local Library = nil
local Window = nil
local FallbackGui = nil
local RunToggle = nil
local SideQuestToggle = nil
local StatusLabel = nil
local GoldLabel = nil
local ProfitLabel = nil
local RateLabel = nil
local ProgressLabel = nil
local RarityLabel = nil
local SQStatusLabel = nil
local SQProgressLabel = nil
local SQDetailLabel = nil
local SQRemainingLabel = nil
local FallbackStatsLabel = nil
local FallbackStatusLabel = nil
local FallbackToggleBtn = nil
local syncingToggle = false

local getParkedFarTreasureHunts
local getTotalFarTreasureHunts
local SQ = {}
local LF = { UI = {} }
local WH = { UI = {} }
local setNoclip
local clearBodyVelocity
local getCharacterParts
local cachedParkedCount = 0
local cachedTotalFarCount = 9
local lastParkedRefresh = 0

local function isLoopAlive()
    restoreExecutorContext()
    if not UIAlive or getgenv()._AutoShipwreckRunId ~= RunId then
        return false
    end
    if Library then
        return Library.ScreenGui ~= nil and Library.ScreenGui.Parent ~= nil
    end
    if FallbackGui then
        return FallbackGui.Parent ~= nil
    end
    return false
end

local function notifyRarity(title, desc, rarity, duration)
    if not Config.NotifyChestRarity then return end
    restoreExecutorContext()
    local r = RARITY_COLORS[rarity] and rarity or "Common"
    local color = RARITY_COLORS[r]
    if Library and Library.Notify then
        local okN, errN = pcall(function()
            Library:Notify({
                Title = title,
                Description = desc,
                TitleColor = color,
                Icon = title:find("Terjual") and "coins" or "package",
                IconColor = color,
                Time = duration or ((r == "Epic" or r == "Legendary") and 6 or 4),
            })
        end)
        if okN then
            Stats.RarityNotifCount = (Stats.RarityNotifCount or 0) + 1
        else
            Stats.NotifyError = tostring(errN)
        end
        restoreExecutorContext()
    end
end

local function notifyInfo(title, desc, duration)
    restoreExecutorContext()
    if Library and Library.Notify then
        pcall(function()
            Library:Notify({
                Title = title,
                Description = desc,
                Icon = "info",
                Time = duration or 4,
            })
        end)
        restoreExecutorContext()
    end
end

local function detectRarityByGold(gainedGold)
    if type(gainedGold) ~= "number" or gainedGold <= 0 or not ChestsUtils or not ChestsUtils.Rarities then
        return nil
    end
    local mult = tonumber(LocalPlayer:GetAttribute("RewardMultiplierGold")) or 1
    if mult <= 0 then mult = 1 end
    local bestRarity, bestDiff = nil, math.huge
    for rName, info in pairs(ChestsUtils.Rarities) do
        if type(info) == "table" and type(info.SellPrice) == "number" then
            local base = info.SellPrice * mult
            local d1 = math.abs(gainedGold - base)
            local d2 = math.abs(gainedGold - math.floor(base * 1.15))
            local d3 = math.abs(gainedGold - info.SellPrice)
            local d4 = math.abs(gainedGold - math.floor(info.SellPrice * 1.15))
            local d = math.min(d1, d2, d3, d4)
            if d < bestDiff then
                bestDiff = d
                bestRarity = rName
            end
        end
    end
    if bestRarity and bestDiff <= 30 then
        return bestRarity
    end
    return nil
end

local function detectChestRarity(chestModel, gainedGold, fallbackRarity)
    if chestModel then
        local ok, r = pcall(function()
            return chestModel:GetAttribute("Rarity") or ChestsUtils.GetRarity(chestModel)
        end)
        if ok and type(r) == "string" and RARITY_COLORS[r] then
            return r
        end
    end

    local char = LocalPlayer.Character
    if char and ChestsUtils and ChestsUtils.GetCarriedChest then
        local okC, carried = pcall(ChestsUtils.GetCarriedChest, char)
        if okC and carried then
            local okR, r = pcall(function()
                return carried:GetAttribute("Rarity") or ChestsUtils.GetRarity(carried)
            end)
            if okR and type(r) == "string" and RARITY_COLORS[r] then
                return r
            end
        end
    end

    local byGold = detectRarityByGold(gainedGold)
    if byGold then
        return byGold
    end

    if fallbackRarity and RARITY_COLORS[fallbackRarity] then
        return fallbackRarity
    end
    return "Common"
end

local function escapeRichText(str)
    return tostring(str or ""):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")
end

local function updateBlackScreenText()
    if not BlackScreenLabel or not BlackScreenGui or not BlackScreenGui.Enabled then
        return
    end
    local curGold = getGold()
    local netSign = Stats.NetProfit >= 0 and "+" or ""
    pcall(function()
        BlackScreenLabel.Text = string.format(
            "%s   |   <font color=\"#FFD24C\">Gold: %s G (%s%s G)</font>",
            escapeRichText(Stats.LastStatus),
            formatNumber(curGold),
            netSign,
            formatNumber(Stats.NetProfit)
        )
    end)
end

local function updateStatsUI()
    local elapsed = math.max(1, os.clock() - Stats.StartTime)
    Stats.NetProfit = Stats.GrossChestGold - Stats.MapsSpent
    local curGold = getGold()
    local walletDelta = curGold - Stats.StartGold

    if elapsed >= 5 then
        Stats.GoldPerMin = math.floor(Stats.NetProfit / (elapsed / 60))
    else
        Stats.GoldPerMin = 0
    end
    Stats.GoldPerHour = Stats.GoldPerMin * 60

    local now = os.clock()
    if (now - lastParkedRefresh) >= 1.0 then
        lastParkedRefresh = now
        cachedParkedCount = getParkedFarTreasureHunts and #getParkedFarTreasureHunts() or 0
        cachedTotalFarCount = getTotalFarTreasureHunts and getTotalFarTreasureHunts() or 9
    end
    local parkedCount = cachedParkedCount
    local totalFarCount = cachedTotalFarCount
    local antiTpDelta = (LocalPlayer:GetAttribute("AntiTeleportReverts") or 0) - Stats.StartAntiTp

    restoreExecutorContext()
    updateBlackScreenText()

    if Library then
        local function safeSet(lbl, text)
            if not lbl then return end
            local okL, errL = pcall(function()
                restoreExecutorContext()
                lbl:SetText(text)
            end)
            if not okL then
                Stats.UIUpdateError = tostring(errL)
            end
        end

        local deltaSign = walletDelta >= 0 and "+" or ""
        local netSign = Stats.NetProfit >= 0 and "+" or ""
        local gpmSign = Stats.GoldPerMin >= 0 and "+" or ""

        safeSet(GoldLabel, string.format(
            "Wallet: %s G  (%s%s G)",
            formatNumber(curGold),
            deltaSign,
            formatNumber(walletDelta)
        ))
        safeSet(ProfitLabel, string.format(
            "Net Profit: %s%s G\nSales +%s G  •  Maps -%s G",
            netSign,
            formatNumber(Stats.NetProfit),
            formatNumber(Stats.GrossChestGold),
            formatNumber(Stats.MapsSpent)
        ))
        safeSet(RateLabel, string.format(
            "Rate: %s%s G/m  •  %s%s G/hr  •  %s",
            gpmSign,
            formatNumber(Stats.GoldPerMin),
            gpmSign,
            formatNumber(Stats.GoldPerHour),
            formatDuration(elapsed)
        ))
        safeSet(ProgressLabel, string.format(
            "Chests: %d (SW %d | TH %d)  •  Haggles: %d\nParked: %d/%d  •  Fails: %d  •  AntiTP: %d",
            Stats.TotalChestsSold,
            Stats.ShipwrecksSold,
            Stats.TreasureHuntsSold,
            Stats.HagglesWon,
            parkedCount,
            totalFarCount,
            Stats.Failures,
            antiTpDelta
        ))
        local rc = Stats.RarityCounts
        safeSet(RarityLabel, string.format(
            "Rarities: C %d • U %d • R %d • E %d • L %d",
            rc.Common or 0,
            rc.Uncommon or 0,
            rc.Rare or 0,
            rc.Epic or 0,
            rc.Legendary or 0
        ))

        if SQ.GetOverview and (SQProgressLabel or SQDetailLabel or SQRemainingLabel) then
            local ov = SQ.GetOverview()
            safeSet(SQProgressLabel, string.format(
                "Completed: %d / %d  (+%d session)\nEarned: +%s G  •  Skipped: %d  •  AntiTP: %d",
                ov.completed,
                ov.total,
                SQStats.SessionCompleted,
                formatNumber(SQStats.SessionGoldEarned),
                ov.skipped,
                antiTpDelta
            ))
            safeSet(SQDetailLabel, string.format(
                "Active: %s\nObjective: %s",
                tostring(SQStats.CurrentQuest or "-"),
                tostring(SQStats.CurrentObjective or "-")
            ))
            safeSet(SQRemainingLabel, string.format(
                "Remaining (%d): %s",
                ov.eligibleCount,
                ov.previewText
            ))
        end

        if LF.UpdateUI then
            pcall(LF.UpdateUI, safeSet, antiTpDelta)
        end

        if Window then
            local okW, errW = pcall(function()
                restoreExecutorContext()
                local activeMode = getActiveMode()
                local runningNow = activeMode ~= "None"
                local statusStr = tostring(Stats.LastStatus)
                if activeMode == "SideQuest" then
                    statusStr = "[SQ] " .. tostring(SQStats.LastStatus)
                elseif activeMode == "LevelFarm" and LF.Stats then
                    statusStr = "[LF] " .. tostring(LF.Stats.LastStatus)
                end
                if runningNow and Window.ReportScriptHeartbeat then
                    Window:ReportScriptHeartbeat(statusStr)
                elseif Window.SetScriptStatus then
                    Window:SetScriptStatus(runningNow and "Running" or "Idle", statusStr)
                end
            end)
            if not okW then
                Stats.UIUpdateError = tostring(errW)
            end
        end
        Stats.UIPulseCount = (Stats.UIPulseCount or 0) + 1
    elseif FallbackStatsLabel then
        pcall(function()
            local netSign = Stats.NetProfit >= 0 and "+" or ""
            FallbackStatsLabel.Text = string.format(
                "Mode:%s | Sold:%d | SQ:%d | LF:%d | Cuan:%s%sG",
                getActiveMode(),
                Stats.TotalChestsSold,
                SQStats.SessionCompleted,
                (LF.Stats and LF.Stats.QuestsCompleted) or 0,
                netSign,
                formatNumber(Stats.NetProfit)
            )
        end)
    end
end

local function setStatus(text)
    restoreExecutorContext()
    local s = tostring(text)
    local curMode = getActiveMode()
    Stats.LastStatus = s
    if curMode == "SideQuest" then
        SQStats.LastStatus = s
    elseif curMode == "LevelFarm" and LF.Stats then
        LF.Stats.LastStatus = s
    end
    if StatusLabel then
        pcall(function()
            restoreExecutorContext()
            StatusLabel:SetText("Status: " .. Stats.LastStatus)
        end)
    elseif FallbackStatusLabel then
        pcall(function()
            FallbackStatusLabel.Text = "Status: " .. Stats.LastStatus
        end)
    end
    if SQStatusLabel and curMode == "SideQuest" then
        pcall(function()
            restoreExecutorContext()
            SQStatusLabel:SetText("Status: " .. SQStats.LastStatus)
        end)
    end
    if LF.UI and LF.UI.StatusLabel and curMode == "LevelFarm" and LF.Stats then
        pcall(function()
            restoreExecutorContext()
            LF.UI.StatusLabel:SetText("Status: " .. LF.Stats.LastStatus)
        end)
    end
    updateBlackScreenText()
    updateStatsUI()
end

local function setSQStatus(text)
    restoreExecutorContext()
    SQStats.LastStatus = tostring(text)
    Stats.LastStatus = "[SQ] " .. SQStats.LastStatus
    if SQStatusLabel then
        pcall(function()
            restoreExecutorContext()
            SQStatusLabel:SetText("Status: " .. SQStats.LastStatus)
        end)
    end
    if StatusLabel then
        pcall(function()
            restoreExecutorContext()
            StatusLabel:SetText("Status: " .. Stats.LastStatus)
        end)
    elseif FallbackStatusLabel then
        pcall(function()
            FallbackStatusLabel.Text = "Status: " .. Stats.LastStatus
        end)
    end
    updateBlackScreenText()
    updateStatsUI()
end

local function cancelInFlightActions()
    ActiveMoveToken = ActiveMoveToken + 1
    if CombatLockConn then
        CombatLockConn:Disconnect()
        CombatLockConn = nil
    end
    if setNoclip then setNoclip(false) end
    if getCharacterParts and clearBodyVelocity then
        local _, _, hrp = getCharacterParts()
        clearBodyVelocity(hrp)
    end
    if DiggingClient then
        pcall(DiggingClient.Cancel)
    end
end

local function setActiveMode(mode)
    restoreExecutorContext()
    local nextShip = (mode == "Shipwreck")
    local nextSQ = (mode == "SideQuest")
    local nextLF = (mode == "LevelFarm")
    local changed = (Config.ShipwreckEnabled ~= nextShip)
        or (Config.SideQuestEnabled ~= nextSQ)
        or (Config.LevelFarmEnabled ~= nextLF)

    Config.ShipwreckEnabled = nextShip
    Config.SideQuestEnabled = nextSQ
    Config.LevelFarmEnabled = nextLF
    Config.Enabled = nextShip or nextSQ or nextLF

    if changed then
        cancelInFlightActions()
    end

    if RunToggle and RunToggle.Value ~= nextShip then
        syncingToggle = true
        pcall(function()
            restoreExecutorContext()
            RunToggle:SetValue(nextShip)
        end)
        syncingToggle = false
    end
    if SideQuestToggle and SideQuestToggle.Value ~= nextSQ then
        syncingToggle = true
        pcall(function()
            restoreExecutorContext()
            SideQuestToggle:SetValue(nextSQ)
        end)
        syncingToggle = false
    end
    if LF.UI and LF.UI.Toggle and LF.UI.Toggle.Value ~= nextLF then
        syncingToggle = true
        pcall(function()
            restoreExecutorContext()
            LF.UI.Toggle:SetValue(nextLF)
        end)
        syncingToggle = false
    end
    if FallbackToggleBtn then
        pcall(function()
            if Config.Enabled then
                FallbackToggleBtn.BackgroundColor3 = Color3.fromRGB(46, 170, 95)
                FallbackToggleBtn.Text = "Running [" .. getActiveMode() .. "] (Click to Stop)"
            else
                FallbackToggleBtn.BackgroundColor3 = Color3.fromRGB(185, 65, 65)
                FallbackToggleBtn.Text = "Stopped (Click to Start Shipwreck)"
            end
        end)
    end
    if Window then
        pcall(function()
            restoreExecutorContext()
            local statusStr = tostring(Stats.LastStatus)
            if nextSQ then
                statusStr = "[SQ] " .. tostring(SQStats.LastStatus)
            elseif nextLF and LF.Stats then
                statusStr = "[LF] " .. tostring(LF.Stats.LastStatus)
            end
            if Window.SetScriptStatus then
                Window:SetScriptStatus(Config.Enabled and "Running" or "Idle", statusStr)
            end
            if Config.Enabled and Window.ReportScriptHeartbeat then
                Window:ReportScriptHeartbeat(statusStr)
            end
        end)
    end
end

local function setRunning(state)
    if state then
        setActiveMode("Shipwreck")
    elseif Config.ShipwreckEnabled then
        setActiveMode("None")
    else
        setActiveMode("None")
    end
end

local function resetProfitStats()
    Stats.StartTime = os.clock()
    Stats.StartGold = getGold()
    Stats.StartAntiTp = LocalPlayer:GetAttribute("AntiTeleportReverts") or 0
    Stats.ConsecutiveChests = 0
    Stats.TotalChestsSold = 0
    Stats.ShipwrecksSold = 0
    Stats.TreasureHuntsSold = 0
    Stats.MapsBought = 0
    Stats.HagglesWon = 0
    Stats.GrossChestGold = 0
    Stats.MapsSpent = 0
    Stats.NetProfit = 0
    Stats.GoldPerMin = 0
    Stats.GoldPerHour = 0
    Stats.ChestGoldEarned = 0
    Stats.Failures = 0
    Stats.UIUpdateError = nil
    Stats.NotifyError = nil
    Stats.RarityNotifCount = 0
    Stats.LastChestRarity = nil
    Stats.RarityCounts = {
        Common = 0,
        Uncommon = 0,
        Rare = 0,
        Epic = 0,
        Legendary = 0,
    }
    Stats.Events = {}
    logEvent("Profit & stats reset")
    updateStatsUI()
    notifyInfo("Kalkulasi Direset", "Penghitungan cuan & statistik dimulai ulang dari sekarang.", 3.5)
end

-- UI Parent helper (shared by Black Screen, BeverlyLIB cleanup & Fallback UI)
local function getUIParent()
    if gethui then
        local ok, hui = pcall(gethui)
        if ok and hui then return hui end
    end
    return LocalPlayer:WaitForChild("PlayerGui")
end

-- Anti-AFK (dual-layer: disable existing Idled kicks + VirtualUser heartbeat)
local function setAntiAFK(enabled, preserveConfig)
    local state = enabled == true
    if not preserveConfig then
        Config.AntiAFK = state
    end
    if AntiAFKConn then
        pcall(function() AntiAFKConn:Disconnect() end)
        AntiAFKConn = nil
    end
    AntiAFKRunning = state
    if not state then return end

    if type(getconnections) == "function" then
        pcall(function()
            for _, conn in ipairs(getconnections(LocalPlayer.Idled)) do
                if conn.Disable then
                    conn:Disable()
                end
            end
        end)
    end

    AntiAFKConn = LocalPlayer.Idled:Connect(function()
        if not Config.AntiAFK or getgenv()._AutoShipwreckRunId ~= RunId then return end
        pcall(function()
            VirtualUser:CaptureController()
            VirtualUser:ClickButton2(Vector2.new())
        end)
        logEvent("Anti-AFK triggered")
    end)

    -- Backup nudge tiap 10 menit agar pasti aman dari kick 20 menit
    local myRun = RunId
    task.spawn(function()
        while AntiAFKRunning and Config.AntiAFK and getgenv()._AutoShipwreckRunId == myRun and UIAlive do
            for _ = 1, 600 do
                if not (AntiAFKRunning and Config.AntiAFK and getgenv()._AutoShipwreckRunId == myRun and UIAlive) then
                    return
                end
                task.wait(1)
            end
            pcall(function()
                VirtualUser:CaptureController()
                VirtualUser:ClickButton2(Vector2.new())
            end)
        end
    end)
end

-- FPS Booster (non-destruktif & bisa dikembalikan, aman untuk PrivateAreas/Chests/NPC)
local function applyFPSBoostToInstance(inst, isMapDescendant)
    if not inst or not inst.Parent then return end
    if inst:IsA("ParticleEmitter") or inst:IsA("Trail") or inst:IsA("Beam")
        or inst:IsA("Fire") or inst:IsA("Smoke") or inst:IsA("Sparkles")
        or inst:IsA("PointLight") or inst:IsA("SpotLight") or inst:IsA("SurfaceLight") then
        if FPSBoostSaved.Visuals[inst] == nil then
            FPSBoostSaved.Visuals[inst] = inst.Enabled
        end
        inst.Enabled = false
    elseif isMapDescendant then
        if inst:IsA("BasePart") then
            if FPSBoostSaved.Parts[inst] == nil then
                FPSBoostSaved.Parts[inst] = {
                    CastShadow = inst.CastShadow,
                    Material = inst.Material,
                    Reflectance = inst.Reflectance,
                }
            end
            inst.CastShadow = false
            if inst.Material ~= Enum.Material.ForceField then
                inst.Material = Enum.Material.SmoothPlastic
            end
            inst.Reflectance = 0
        elseif inst:IsA("Decal") or inst:IsA("Texture") then
            if FPSBoostSaved.Visuals[inst] == nil then
                FPSBoostSaved.Visuals[inst] = inst.Transparency
            end
            inst.Transparency = 1
        end
    elseif inst:IsA("BasePart") and inst.CastShadow then
        if FPSBoostSaved.Parts[inst] == nil then
            FPSBoostSaved.Parts[inst] = { CastShadow = true }
        end
        inst.CastShadow = false
    end
end

local function setFPSBoost(enabled, preserveConfig)
    local state = enabled == true
    if not preserveConfig then
        Config.FPSBoost = state
    end
    if state then
        if FPSBoostActive then return end
        FPSBoostActive = true

        -- Lighting
        pcall(function()
            if FPSBoostSaved.Lighting.GlobalShadows == nil then
                FPSBoostSaved.Lighting.GlobalShadows = Lighting.GlobalShadows
                FPSBoostSaved.Lighting.FogEnd = Lighting.FogEnd
            end
            Lighting.GlobalShadows = false
            Lighting.FogEnd = 9e9
        end)

        for _, eff in ipairs(Lighting:GetChildren()) do
            if eff:IsA("PostEffect") then
                if FPSBoostSaved.Effects[eff] == nil then
                    FPSBoostSaved.Effects[eff] = eff.Enabled
                end
                eff.Enabled = false
            elseif eff:IsA("Atmosphere") then
                if FPSBoostSaved.Effects[eff] == nil then
                    FPSBoostSaved.Effects[eff] = eff.Density
                end
                eff.Density = 0
            end
        end

        -- Terrain & Rendering quality
        pcall(function()
            local terrain = workspace.Terrain
            if terrain then
                if FPSBoostSaved.Terrain.WaterWaveSize == nil then
                    FPSBoostSaved.Terrain.WaterWaveSize = terrain.WaterWaveSize
                    FPSBoostSaved.Terrain.WaterWaveSpeed = terrain.WaterWaveSpeed
                    FPSBoostSaved.Terrain.WaterReflectance = terrain.WaterReflectance
                    FPSBoostSaved.Terrain.WaterTransparency = terrain.WaterTransparency
                end
                terrain.WaterWaveSize = 0
                terrain.WaterWaveSpeed = 0
                terrain.WaterReflectance = 0
                terrain.WaterTransparency = 0
            end
        end)
        pcall(function()
            settings().Rendering.QualityLevel = Enum.QualityLevel.Level01
        end)

        -- Batched async scan agar tidak lag spike saat dinyalakan
        local myRun = RunId
        task.spawn(function()
            local targets = {
                { root = workspace:FindFirstChild("Map"), isMap = true },
                { root = workspace:FindFirstChild("Playability"), isMap = false },
            }
            local processed = 0
            for _, entry in ipairs(targets) do
                if entry.root then
                    for _, desc in ipairs(entry.root:GetDescendants()) do
                        if not FPSBoostActive or getgenv()._AutoShipwreckRunId ~= myRun then return end
                        pcall(applyFPSBoostToInstance, desc, entry.isMap)
                        processed = processed + 1
                        if processed % 450 == 0 then
                            task.wait()
                        end
                    end
                end
            end
        end)

        if FPSBoostDescConn then
            pcall(function() FPSBoostDescConn:Disconnect() end)
            FPSBoostDescConn = nil
        end
        local mapFolder = workspace:FindFirstChild("Map")
        FPSBoostDescConn = workspace.DescendantAdded:Connect(function(desc)
            if not FPSBoostActive or getgenv()._AutoShipwreckRunId ~= RunId then return end
            local isMap = mapFolder ~= nil and desc:IsDescendantOf(mapFolder)
            if isMap or desc:IsA("ParticleEmitter") or desc:IsA("Trail") or desc:IsA("Beam")
                or desc:IsA("Fire") or desc:IsA("Smoke") or desc:IsA("Sparkles")
                or desc:IsA("PointLight") or desc:IsA("SpotLight") or desc:IsA("SurfaceLight") then
                pcall(applyFPSBoostToInstance, desc, isMap)
            end
        end)
    else
        if not FPSBoostActive then return end
        FPSBoostActive = false
        if FPSBoostDescConn then
            pcall(function() FPSBoostDescConn:Disconnect() end)
            FPSBoostDescConn = nil
        end

        pcall(function()
            if FPSBoostSaved.Lighting.GlobalShadows ~= nil then
                Lighting.GlobalShadows = FPSBoostSaved.Lighting.GlobalShadows
            end
            if FPSBoostSaved.Lighting.FogEnd ~= nil then
                Lighting.FogEnd = FPSBoostSaved.Lighting.FogEnd
            end
        end)
        for eff, prev in pairs(FPSBoostSaved.Effects) do
            pcall(function()
                if eff and eff.Parent then
                    if eff:IsA("Atmosphere") then
                        eff.Density = prev
                    else
                        eff.Enabled = prev
                    end
                end
            end)
        end
        pcall(function()
            local terrain = workspace.Terrain
            if terrain and FPSBoostSaved.Terrain.WaterWaveSize ~= nil then
                terrain.WaterWaveSize = FPSBoostSaved.Terrain.WaterWaveSize
                terrain.WaterWaveSpeed = FPSBoostSaved.Terrain.WaterWaveSpeed
                terrain.WaterReflectance = FPSBoostSaved.Terrain.WaterReflectance
                terrain.WaterTransparency = FPSBoostSaved.Terrain.WaterTransparency
            end
        end)
        for inst, prev in pairs(FPSBoostSaved.Visuals) do
            pcall(function()
                if inst and inst.Parent then
                    if inst:IsA("Decal") or inst:IsA("Texture") then
                        inst.Transparency = prev
                    else
                        inst.Enabled = prev
                    end
                end
            end)
        end
        for part, prev in pairs(FPSBoostSaved.Parts) do
            pcall(function()
                if part and part.Parent then
                    if prev.CastShadow ~= nil then part.CastShadow = prev.CastShadow end
                    if prev.Material ~= nil then part.Material = prev.Material end
                    if prev.Reflectance ~= nil then part.Reflectance = prev.Reflectance end
                end
            end)
        end
        FPSBoostSaved = { Lighting = {}, Effects = {}, Terrain = {}, Parts = {}, Visuals = {} }
    end
end

-- Black Screen + Disable 3D Rendering (layar hitam penuh, hanya 1 kalimat status + gold)
local function ensureBlackScreenGui()
    if BlackScreenGui and BlackScreenGui.Parent then
        return BlackScreenGui
    end
    restoreExecutorContext()
    local uiParent = getUIParent()
    local old = uiParent:FindFirstChild("BeverlyVoxBlackScreen")
    if old then old:Destroy() end

    local gui = Instance.new("ScreenGui")
    gui.Name = "BeverlyVoxBlackScreen"
    gui.IgnoreGuiInset = true
    gui.ResetOnSpawn = false
    gui.DisplayOrder = 995 -- tepat di bawah BeverlyLIB (998) agar RightShift menu tetap muncul di atas layar hitam
    gui.Enabled = false
    gui.Parent = uiParent

    local bg = Instance.new("Frame")
    bg.Name = "BlackBg"
    bg.Size = UDim2.fromScale(1, 1)
    bg.Position = UDim2.fromScale(0, 0)
    bg.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    bg.BorderSizePixel = 0
    bg.Parent = gui

    local lbl = Instance.new("TextLabel")
    lbl.Name = "OneLineStatus"
    lbl.AnchorPoint = Vector2.new(0.5, 0.5)
    lbl.Position = UDim2.fromScale(0.5, 0.5)
    lbl.Size = UDim2.new(0.92, 0, 0, 42)
    lbl.BackgroundTransparency = 1
    lbl.RichText = true
    lbl.Font = Enum.Font.GothamSemibold
    lbl.TextSize = 18
    lbl.TextColor3 = Color3.fromRGB(235, 238, 245)
    lbl.TextXAlignment = Enum.TextXAlignment.Center
    lbl.TextYAlignment = Enum.TextYAlignment.Center
    lbl.TextTruncate = Enum.TextTruncate.AtEnd
    lbl.Text = "Starting... | Gold: 0 G"
    lbl.Parent = bg

    local exitBtn = Instance.new("TextButton")
    exitBtn.Name = "Restore3DBtn"
    exitBtn.AnchorPoint = Vector2.new(0.5, 1)
    exitBtn.Position = UDim2.new(0.5, 0, 1, -24)
    exitBtn.Size = UDim2.fromOffset(230, 26)
    exitBtn.BackgroundTransparency = 1
    exitBtn.Font = Enum.Font.Gotham
    exitBtn.TextSize = 12
    exitBtn.TextColor3 = Color3.fromRGB(95, 100, 112)
    exitBtn.TextXAlignment = Enum.TextXAlignment.Center
    exitBtn.Text = "RightShift: Menu  •  Klik: Show 3D"
    exitBtn.Parent = bg

    exitBtn.MouseButton1Click:Connect(function()
        if BlackScreenToggle and BlackScreenToggle.SetValue then
            pcall(function()
                restoreExecutorContext()
                BlackScreenToggle:SetValue(false)
            end)
        else
            Config.BlackScreen3D = false
            pcall(function() RunService:Set3dRenderingEnabled(true) end)
            gui.Enabled = false
        end
        if Library and Library.Toggle then
            pcall(function()
                restoreExecutorContext()
                Library:Toggle(true)
            end)
        end
    end)

    BlackScreenGui = gui
    BlackScreenLabel = lbl
    return gui
end

local function setBlackScreen(enabled)
    restoreExecutorContext()
    Config.BlackScreen3D = enabled == true
    if Config.BlackScreen3D then
        local gui = ensureBlackScreenGui()
        gui.Enabled = true
        updateBlackScreenText()
        -- Sembunyikan menu BeverlyLIB otomatis agar layar langsung hitam penuh (RightShift tetap bisa buka menu)
        if Library and Library.Toggle then
            pcall(function()
                restoreExecutorContext()
                Library:Toggle(false)
            end)
        end
        pcall(function()
            RunService:Set3dRenderingEnabled(false)
        end)
    else
        pcall(function()
            RunService:Set3dRenderingEnabled(true)
        end)
        if BlackScreenGui and BlackScreenGui.Parent then
            BlackScreenGui.Enabled = false
        end
    end
end

-- Character & Movement helpers
getCharacterParts = function()
    local char = LocalPlayer.Character
    if not char then return nil, nil, nil end
    local hum = char:FindFirstChildOfClass("Humanoid")
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hum or not hrp or hum.Health <= 0 then
        return nil, nil, nil
    end
    return char, hum, hrp
end

local function isCarryingChest()
    local char = LocalPlayer.Character
    return char ~= nil and char:GetAttribute("CarriedChest") ~= nil
end

local function refreshNoclipParts(char)
    if NoclipCachedChar == char then return end
    if NoclipDescConn then
        pcall(function() NoclipDescConn:Disconnect() end)
        NoclipDescConn = nil
    end
    NoclipCachedChar = char
    NoclipCachedParts = {}
    NoclipOrigCollide = {}
    if not char then return end
    for _, inst in ipairs(char:GetDescendants()) do
        if inst:IsA("BasePart") then
            table.insert(NoclipCachedParts, inst)
            NoclipOrigCollide[inst] = inst.CanCollide
        end
    end
    NoclipDescConn = char.DescendantAdded:Connect(function(inst)
        if inst:IsA("BasePart") and NoclipCachedChar == char then
            table.insert(NoclipCachedParts, inst)
            if NoclipOrigCollide[inst] == nil then
                NoclipOrigCollide[inst] = inst.CanCollide
            end
        end
    end)
end

setNoclip = function(enabled)
    if enabled then
        if NoclipConn then return end
        refreshNoclipParts(LocalPlayer.Character)
        NoclipConn = RunService.Stepped:Connect(function()
            local char = LocalPlayer.Character
            if not char then return end
            if char ~= NoclipCachedChar then
                refreshNoclipParts(char)
            end
            for i = #NoclipCachedParts, 1, -1 do
                local part = NoclipCachedParts[i]
                if not part or not part.Parent then
                    table.remove(NoclipCachedParts, i)
                elseif part.CanCollide then
                    part.CanCollide = false
                end
            end
        end)
    else
        if NoclipConn then
            NoclipConn:Disconnect()
            NoclipConn = nil
        end
        if NoclipDescConn then
            pcall(function() NoclipDescConn:Disconnect() end)
            NoclipDescConn = nil
        end
        for part, orig in pairs(NoclipOrigCollide) do
            if part and part.Parent and part:IsA("BasePart") then
                pcall(function() part.CanCollide = orig end)
            end
        end
        NoclipOrigCollide = {}
        NoclipCachedParts = {}
        NoclipCachedChar = nil
    end
end

clearBodyVelocity = function(hrp)
    if not hrp then return end
    local bv = hrp:FindFirstChild("_ShipwreckBV")
    if bv then bv:Destroy() end
end

local function ensureBodyVelocity(hrp)
    local bv = hrp:FindFirstChild("_ShipwreckBV")
    if not bv then
        bv = Instance.new("BodyVelocity")
        bv.Name = "_ShipwreckBV"
        bv.MaxForce = Vector3.new(1e6, 1e6, 1e6)
        bv.Velocity = Vector3.zero
        bv.Parent = hrp
    end
    return bv
end

local function neutralizeSwimFight(hum, hrp)
    if hum and hum.PlatformStand then
        hum.PlatformStand = false
    end
    if hrp then
        local sv = hrp:FindFirstChild("SwimVelocity")
        if sv then sv:Destroy() end
        local so = hrp:FindFirstChild("SwimOrientation")
        if so then so:Destroy() end
    end
end

-- Velocity-clamped Heartbeat stepper: nol speed spike (bebas snap 262 st/s TweenService saat lag/SwimSystem)
local function tweenSegment(targetPos, speedOverride, stopRange, abortIfDropChest, keepPhysics)
    local char, hum, hrp = getCharacterParts()
    while not char do
        if not isActive() then return false end
        task.wait(0.2)
        char, hum, hrp = getCharacterParts()
    end

    local arriveRange = stopRange or 5
    if (hrp.Position - targetPos).Magnitude <= arriveRange then
        return true
    end

    local speed = speedOverride or Config.TweenSpeed
    local myToken = ActiveMoveToken + 1
    ActiveMoveToken = myToken

    setNoclip(true)
    local bv = ensureBodyVelocity(hrp)

    local finished = false
    local aborted = false
    local curPos = hrp.Position

    local moveConn
    moveConn = RunService.Heartbeat:Connect(function(rawDt)
        if finished or aborted then return end
        if ActiveMoveToken ~= myToken or not isActive() then
            aborted = true
            return
        end
        if abortIfDropChest and not isCarryingChest() then
            aborted = true
            return
        end
        local c, h, r = getCharacterParts()
        if not c or not r then
            aborted = true
            return
        end

        neutralizeSwimFight(h, r)

        -- Jika server melakukan revert cukup jauh, ikuti posisi aktual agar tidak terjadi snap teleport besar
        if (r.Position - curPos).Magnitude > 18 then
            curPos = r.Position
        end

        local diff = targetPos - curPos
        local dist = diff.Magnitude
        if dist <= arriveRange then
            finished = true
            return
        end

        local dt = math.min(rawDt, 0.05) -- clamp 50ms agar frame hitch tidak pernah memicu speed spike
        local stepLen = math.min(dist, speed * dt)
        curPos = curPos + diff.Unit * stepLen

        r.CFrame = CFrame.new(curPos)
        r.AssemblyLinearVelocity = Vector3.zero
        r.AssemblyAngularVelocity = Vector3.zero

        if (curPos - targetPos).Magnitude <= arriveRange then
            finished = true
        end
    end)

    while not finished and not aborted do
        if ActiveMoveToken ~= myToken or not isActive() then
            aborted = true
            break
        end
        task.wait(0.03)
    end

    if moveConn then
        moveConn:Disconnect()
    end

    if not keepPhysics or aborted or not isActive() then
        if bv and bv.Parent then
            bv:Destroy()
        end
        local _, _, curHrp = getCharacterParts()
        if curHrp then clearBodyVelocity(curHrp) end
        setNoclip(false)
    end

    return finished and not aborted and isActive()
end

local function tweenTo(targetPos, isCarry, stopRange)
    local _, _, hrp = getCharacterParts()
    if not hrp then return false end

    local startPos = hrp.Position
    local flatDist = Vector2.new(targetPos.X - startPos.X, targetPos.Z - startPos.Z).Magnitude
    local safeY = isCarry and Config.CarrySafeY or Config.AirTravelY
    local speed = isCarry and Config.CarryTweenSpeed or Config.TweenSpeed

    -- Jangan pakai AirTravelY saat berada di interior bawah tanah (Y < -400) atau pulau langit (Y > 700)
    local bothUnderground = startPos.Y < -400 and targetPos.Y < -400
    local bothSky = startPos.Y > 700 and targetPos.Y > 700

    if not bothUnderground and not bothSky and flatDist > 120 then
        if isCarry then
            if math.abs(startPos.Y - safeY) > 3 then
                if not tweenSegment(Vector3.new(startPos.X, safeY, startPos.Z), speed, 4, true, true) then
                    return false
                end
            end
            if not tweenSegment(Vector3.new(targetPos.X, safeY, targetPos.Z), speed, 6, true, true) then
                return false
            end
        elseif startPos.Y < 10 or targetPos.Y < 10 then
            local cruiseY = math.max(safeY, math.min(startPos.Y, targetPos.Y))
            if cruiseY < safeY then cruiseY = safeY end
            if math.abs(startPos.Y - cruiseY) > 3 then
                if not tweenSegment(Vector3.new(startPos.X, cruiseY, startPos.Z), speed, 4, false, true) then
                    return false
                end
            end
            if not tweenSegment(Vector3.new(targetPos.X, cruiseY, targetPos.Z), speed, 6, false, true) then
                return false
            end
        end
    end

    return tweenSegment(targetPos, speed, stopRange, isCarry, false)
end

-- Pawnshop & Generalized PrivateAreas / Realm Navigation helpers
local cachedPawnshopArea = nil
local cachedPawnEnterPart = nil
local cachedPawnLeavePart = nil
local cachedPawnbrokerModel = nil

local function findPrivateAreaModel(islandName, areaName)
    local ignoreList = workspace:FindFirstChild("IgnoreList")
    local intFolder = ignoreList and ignoreList:FindFirstChild("Int")
    local priv = intFolder and intFolder:FindFirstChild("PrivateAreas")
    local island = priv and priv:FindFirstChild(islandName)
    return island and island:FindFirstChild(areaName) or nil
end

local function getPrivateAreaDoorPos(areaModel, kind)
    if not areaModel then return nil end
    local sub = areaModel:FindFirstChild(kind)
    local ent = sub and sub:FindFirstChild("Entrance")
    if ent and ent:IsA("BasePart") then
        return ent.Position
    end
    return nil
end

local function getPawnshopPrivateArea()
    if cachedPawnshopArea and cachedPawnshopArea.Parent then
        return cachedPawnshopArea
    end
    cachedPawnshopArea = findPrivateAreaModel("Harbor Island", "Pawnshop")
    return cachedPawnshopArea
end

local function getPawnshopEnterPos()
    if cachedPawnEnterPart and cachedPawnEnterPart.Parent then
        return cachedPawnEnterPart.Position
    end
    local ps = getPawnshopPrivateArea()
    local enter = ps and ps:FindFirstChild("Enter")
    local entrance = enter and enter:FindFirstChild("Entrance")
    if entrance and entrance:IsA("BasePart") then
        cachedPawnEnterPart = entrance
        return entrance.Position
    end
    return Vector3.new(5658, 40, 3213)
end

local function getPawnshopLeavePos()
    if cachedPawnLeavePart and cachedPawnLeavePart.Parent then
        return cachedPawnLeavePart.Position
    end
    local ps = getPawnshopPrivateArea()
    local leave = ps and ps:FindFirstChild("Leave")
    local entrance = leave and leave:FindFirstChild("Entrance")
    if entrance and entrance:IsA("BasePart") then
        cachedPawnLeavePart = entrance
        return entrance.Position
    end
    return Vector3.new(5690, -807, 2808)
end

local function getPawnbrokerPos()
    if cachedPawnbrokerModel and cachedPawnbrokerModel.Parent then
        return cachedPawnbrokerModel:GetPivot().Position
    end
    local ignoreList = workspace:FindFirstChild("IgnoreList")
    local intFolder = ignoreList and ignoreList:FindFirstChild("Int")
    local npcs = intFolder and intFolder:FindFirstChild("NPCs")
    local shops = npcs and npcs:FindFirstChild("Shops")
    local central = shops and shops:FindFirstChild("Central Town")
    local pawn = central and central:FindFirstChild("Pawnbroker")
    if pawn then
        cachedPawnbrokerModel = pawn
        return pawn:GetPivot().Position
    end
    return Vector3.new(5708.45, -809.5, 2813)
end

local function isInPawnshop()
    local _, _, hrp = getCharacterParts()
    if not hrp then return false end
    if hrp.Position.Y >= -500 then return false end
    local pPos = getPawnbrokerPos()
    return Vector2.new(hrp.Position.X - pPos.X, hrp.Position.Z - pPos.Z).Magnitude < 300
end

local function triggerPrivateAreaDoorUntil(predicateFn, doorPos, isCarry)
    local t0 = os.clock()
    local nudged = false
    while (os.clock() - t0) < 5.0 do
        if not isActive() then return false end
        if predicateFn() then
            return true
        end
        local areaId = PrivateAreasClient.Current
        if areaId then
            Network:FireServer("PrivateAreas", "EnterArea", areaId)
            local w0 = os.clock()
            while (os.clock() - w0) < 3.5 do
                if not isActive() then return false end
                if predicateFn() then
                    return true
                end
                task.wait(0.12)
            end
        elseif not nudged and doorPos and (os.clock() - t0) > 1.0 then
            nudged = true
            local speed = isCarry and Config.CarryTweenSpeed or Config.TweenSpeed
            tweenSegment(doorPos + Vector3.new(0, 1, 0), speed, 2, isCarry)
        end
        task.wait(0.12)
    end
    return predicateFn()
end

local function triggerCurrentDoor(expectInside, doorPos, isCarry)
    return triggerPrivateAreaDoorUntil(function()
        return isInPawnshop() == expectInside
    end, doorPos, isCarry)
end

local function leavePawnshop()
    if not isInPawnshop() then return true end
    setStatus("Keluar lewat pintu Pawnshop...")
    local leavePos = getPawnshopLeavePos()
    if not tweenSegment(leavePos, Config.TweenSpeed, 4) then return false end
    return triggerCurrentDoor(false, leavePos, false)
end

-- Realm classifier untuk interior bawah tanah (Y < -500) & pulau langit
local REALM_DEFS = {
    Pawnshop = {
        kind = "PrivateArea",
        island = "Harbor Island",
        area = "Pawnshop",
        center = Vector3.new(5700, -808, 2812),
        radius = 350,
        enterFallback = Vector3.new(5658, 40, 3213),
        leaveFallback = Vector3.new(5691, -806, 2809),
    },
    WitchHouse = {
        kind = "PrivateArea",
        island = "Forbidden Island",
        area = "WitchHouse",
        center = Vector3.new(6105, -571, -4641),
        radius = 350,
        enterFallback = Vector3.new(6282, 132, -5187),
        leaveFallback = Vector3.new(6091, -570, -4641),
    },
    PrisonInterior = {
        kind = "PrisonLift",
        center = Vector3.new(11200, -1450, 1150),
        radius = 3200,
        enterZone = "Enter_PrisonLift_PI",
        enterFallback = Vector3.new(10992, 33, 995),
        leaveZone = "Leave_PrisonLift_PI",
        leaveFallback = Vector3.new(11784, -1344, 1160),
    },
    PhantomRuins = {
        kind = "TempleRun",
        center = Vector3.new(-8314, -1215, 13650),
        radius = 1800,
        enterFallback = Vector3.new(-8348.8, 102.6, 13927.4),
        leaveFallback = Vector3.new(-8313.9, -1215.6, 14421.3),
    },
    VolcanoInterior = {
        kind = "PrivateArea",
        island = "Volcano Island",
        area = "VolcanoInterior",
        center = Vector3.new(-17950, -9550, 10800),
        radius = 2500,
        enterFallback = Vector3.new(-16992.5, 339.7, 10178.3),
        leaveFallback = Vector3.new(-18123.1, -9502.4, 10274.1),
    },
}

local function classifyPosRealm(pos)
    if not pos then return "Surface" end
    if pos.Y < -400 then
        for rName, def in pairs(REALM_DEFS) do
            if Vector2.new(pos.X - def.center.X, pos.Z - def.center.Z).Magnitude <= def.radius then
                return rName
            end
        end
        return "OtherInterior"
    end
    return "Surface"
end

local function getCurrentRealm()
    local _, _, hrp = getCharacterParts()
    if not hrp then return "Surface" end
    return classifyPosRealm(hrp.Position)
end

local function findQuestZonePart(zoneName)
    local ignoreList = workspace:FindFirstChild("IgnoreList")
    local data = ignoreList and ignoreList:FindFirstChild("Data")
    local quests = data and data:FindFirstChild("Quests")
    local zones = quests and quests:FindFirstChild("Zones")
    if not zones then return nil end
    return zones:FindFirstChild(zoneName, true)
end

local function triggerQuestZoneUseRaw(zoneName, pos, expectFn)
    if not tweenTo(pos + Vector3.new(0, 1.5, 0), false, 4) then
        return false
    end
    -- settle singkat agar validasi jarak server lolos
    local tWait = os.clock()
    while (os.clock() - tWait) < 1.2 do
        if not isActive() then return false end
        local sp = LocalPlayer:GetAttribute("ServerPosition")
        if typeof(sp) == "Vector3" and (sp - pos).Magnitude <= 14 then
            break
        end
        task.wait(0.08)
    end

    for attempt = 1, 3 do
        if not isActive() then return false end
        if expectFn and expectFn() then return true end
        Network:FireServer("QuestZones", zoneName, "Use")
        local w0 = os.clock()
        while (os.clock() - w0) < 3.0 do
            if not isActive() then return false end
            if expectFn and expectFn() then return true end
            task.wait(0.12)
        end
        if attempt < 3 then
            tweenSegment(pos + Vector3.new(0, 1.5, 0), Config.TweenSpeed, 3)
        end
    end
    return expectFn and expectFn() or false
end

local function leaveCurrentInterior(isCarry)
    local realm = getCurrentRealm()
    if realm == "Surface" then return true end

    if realm == "Pawnshop" then
        return leavePawnshop()
    end

    local def = REALM_DEFS[realm]
    if def and def.kind == "PrivateArea" then
        local areaModel = findPrivateAreaModel(def.island, def.area)
        local leavePos = getPrivateAreaDoorPos(areaModel, "Leave") or def.leaveFallback
        setStatus("Keluar dari " .. realm .. "...")
        if not tweenSegment(leavePos + Vector3.new(0, 1.5, 0), isCarry and Config.CarryTweenSpeed or Config.TweenSpeed, 4, isCarry) then
            return false
        end
        return triggerPrivateAreaDoorUntil(function()
            return getCurrentRealm() == "Surface"
        end, leavePos, isCarry)
    elseif def and def.kind == "PrisonLift" then
        local zPart = findQuestZonePart(def.leaveZone)
        local leavePos = (zPart and zPart:IsA("BasePart")) and zPart.Position or def.leaveFallback
        setStatus("Naik lift keluar Prison Interior...")
        return triggerQuestZoneUseRaw(def.leaveZone, leavePos, function()
            return getCurrentRealm() == "Surface"
        end)
    elseif def and def.kind == "TempleRun" then
        setStatus("Keluar dari Phantom Ruins...")
        local leavePos = def.leaveFallback
        if not tweenSegment(leavePos + Vector3.new(0, 2, 0), Config.TweenSpeed, 5) then return false end
        for _ = 1, 3 do
            if not isActive() then return false end
            if getCurrentRealm() == "Surface" then return true end
            Network:FireServer("MinigamesService", "TempleRun", { GameAction = "Leave" })
            local w0 = os.clock()
            while (os.clock() - w0) < 2.5 do
                if not isActive() then return false end
                if getCurrentRealm() == "Surface" then return true end
                task.wait(0.12)
            end
        end
        return getCurrentRealm() == "Surface"
    else
        -- Scan semua PrivateAreas.Leave terdekat untuk keluar dari interior lain
        local _, _, hrp = getCharacterParts()
        if not hrp then return false end
        local ignoreList = workspace:FindFirstChild("IgnoreList")
        local priv = ignoreList and ignoreList:FindFirstChild("Int") and ignoreList.Int:FindFirstChild("PrivateAreas")
        local bestLeave, bestDist = nil, math.huge
        if priv then
            for _, island in ipairs(priv:GetChildren()) do
                for _, area in ipairs(island:GetChildren()) do
                    local lp = getPrivateAreaDoorPos(area, "Leave")
                    if lp and lp.Y < -400 then
                        local d = (lp - hrp.Position).Magnitude
                        if d < bestDist then
                            bestDist = d
                            bestLeave = lp
                        end
                    end
                end
            end
        end
        if bestLeave and bestDist < 600 then
            setStatus("Keluar dari interior...")
            if not tweenSegment(bestLeave + Vector3.new(0, 1.5, 0), Config.TweenSpeed, 4) then return false end
            return triggerPrivateAreaDoorUntil(function()
                return getCurrentRealm() == "Surface"
            end, bestLeave, false)
        end
    end
    return getCurrentRealm() == "Surface"
end

local function enterInteriorRealm(realmName, isCarry)
    if getCurrentRealm() == realmName then return true end
    if getCurrentRealm() ~= "Surface" then
        if not leaveCurrentInterior(isCarry) then return false end
        task.wait(0.2)
    end

    local def = REALM_DEFS[realmName]
    if not def then return false end

    if def.kind == "PrivateArea" then
        local areaModel = findPrivateAreaModel(def.island, def.area)
        local enterPos = getPrivateAreaDoorPos(areaModel, "Enter") or def.enterFallback
        setStatus("Menuju pintu " .. realmName .. "...")
        if not tweenTo(enterPos + Vector3.new(0, 2, 0), isCarry, 5) then return false end
        setStatus("Masuk ke " .. realmName .. "...")
        return triggerPrivateAreaDoorUntil(function()
            return getCurrentRealm() == realmName
        end, enterPos, isCarry)
    elseif def.kind == "PrisonLift" then
        local zPart = findQuestZonePart(def.enterZone)
        local enterPos = (zPart and zPart:IsA("BasePart")) and zPart.Position or def.enterFallback
        setStatus("Menuju lift Prison Interior...")
        return triggerQuestZoneUseRaw(def.enterZone, enterPos, function()
            return getCurrentRealm() == "PrisonInterior"
        end)
    elseif def.kind == "TempleRun" then
        local enterPos = def.enterFallback
        setStatus("Menuju pintu Phantom Ruins...")
        if not tweenTo(enterPos + Vector3.new(0, 2, 0), false, 5) then return false end
        task.wait(0.35)
        for _ = 1, 3 do
            if not isActive() then return false end
            if getCurrentRealm() == "PhantomRuins" then return true end
            Network:FireServer("MinigamesService", "TempleRun", { GameAction = "Enter" })
            local w0 = os.clock()
            while (os.clock() - w0) < 3.0 do
                if not isActive() then return false end
                if getCurrentRealm() == "PhantomRuins" then return true end
                task.wait(0.12)
            end
        end
        return getCurrentRealm() == "PhantomRuins"
    end
    return false
end

-- Navigasi pintar lintas permukaan, interior PrivateAreas, PrisonLift, & Rustfall SkyLift
local function navigateToPos(targetPos, isCarry, stopRange)
    if not targetPos then return false end
    local curRealm = getCurrentRealm()
    local targetRealm = classifyPosRealm(targetPos)

    if curRealm ~= targetRealm then
        if curRealm ~= "Surface" then
            if not leaveCurrentInterior(isCarry) then return false end
            task.wait(0.2)
        end
        if targetRealm ~= "Surface" then
            if not enterInteriorRealm(targetRealm, isCarry) then return false end
            task.wait(0.25)
        end
    end

    -- Optimasi naik ke Rustfall (Y ~ 1350-1600) lewat SkyLift jika masih di permukaan laut
    local _, _, hrp = getCharacterParts()
    if hrp and targetRealm == "Surface" and not isCarry
        and hrp.Position.Y < 400
        and targetPos.Y > 1100 and targetPos.Y < 2000
        and Vector2.new(targetPos.X - 6900, targetPos.Z - 9200).Magnitude < 2500
    then
        local skyLift = findPrivateAreaModel("Rustfall", "SkyLift")
        local liftEnter = getPrivateAreaDoorPos(skyLift, "Enter") or Vector3.new(6638, 24, 10673)
        if tweenTo(liftEnter + Vector3.new(0, 2, 0), false, 5) then
            triggerPrivateAreaDoorUntil(function()
                local _, _, hNow = getCharacterParts()
                return hNow ~= nil and hNow.Position.Y > 1000
            end, liftEnter, false)
            task.wait(0.25)
        end
    end

    if targetRealm ~= "Surface" then
        return tweenSegment(targetPos, isCarry and Config.CarryTweenSpeed or Config.TweenSpeed, stopRange or 5, isCarry, false)
    end
    return tweenTo(targetPos, isCarry, stopRange or 5)
end

-- Quest & Chest query helpers
local function getShipwreckPosition(questName)
    local pt = TreasureHuntUtils.GetShipwreckPoint(LocalPlayer.UserId, questName)
    restoreExecutorContext()
    if not pt then return nil end
    local site = pt:GetAttribute("Site")
    if typeof(site) == "Vector3" then
        return site
    end
    return pt.Position
end

local function getActiveShipwrecks()
    local ds = getDataStore()
    if not ds then return {} end
    local ok, res = pcall(TreasureHuntUtils.GetActiveShipwrecks, ds)
    if not ok or type(res) ~= "table" then
        return {}
    end
    if #res > 1 then
        local _, _, hrp = getCharacterParts()
        local refPos = (hrp and not isInPawnshop()) and hrp.Position or getPawnshopEnterPos()
        local dists = {}
        for _, name in ipairs(res) do
            local p = getShipwreckPosition(name)
            dists[name] = p and Vector2.new(p.X - refPos.X, p.Z - refPos.Z).Magnitude or 999999
        end
        table.sort(res, function(a, b)
            return dists[a] < dists[b]
        end)
    end
    return res
end

local function getTreasureHuntDistance(questName)
    local pt = TreasureHuntUtils.GetPoint(questName)
    restoreExecutorContext()
    if not pt then return math.huge end
    local pawnPos = getPawnshopEnterPos()
    return Vector2.new(pt.Position.X - pawnPos.X, pt.Position.Z - pawnPos.Z).Magnitude
end

local function isFarTreasureHunt(questName)
    return Config.ParkFarTreasureHunts == true
        and getTreasureHuntDistance(questName) > (Config.MaxTreasureHuntDist or 3600)
end

getTotalFarTreasureHunts = function()
    if not Config.ParkFarTreasureHunts then return 0 end
    local maxDist = Config.MaxTreasureHuntDist or 3600
    local pawnPos = getPawnshopEnterPos()
    local pts = TreasureHuntUtils.GetPoints()
    restoreExecutorContext()
    local total = 0
    for _, pt in ipairs(pts) do
        local d = Vector2.new(pt.Position.X - pawnPos.X, pt.Position.Z - pawnPos.Z).Magnitude
        if d > maxDist then
            total = total + 1
        end
    end
    return total
end

getParkedFarTreasureHunts = function()
    local ds = getDataStore()
    local out = {}
    if not ds or not ds.Quests or not ds.Quests.Actives then return out end
    local progress = QuestSystemClient:GetProgress()
    local dists = {}
    for questName in pairs(ds.Quests.Actives) do
        if type(questName) == "string" and questName:find("Treasure Hunt") and not questName:find("Shipwreck") then
            local d = getTreasureHuntDistance(questName)
            if Config.ParkFarTreasureHunts == true and d > (Config.MaxTreasureHuntDist or 3600) then
                local guard = QuestsUtils.IsObjectiveActive(progress, TreasureHuntUtils.GetGuardObjectiveId(questName))
                local unearth = QuestsUtils.IsObjectiveActive(progress, TreasureHuntUtils.GetUnearthObjectiveId(questName))
                if not guard and not unearth then
                    dists[questName] = d
                    table.insert(out, questName)
                end
            end
        end
    end
    table.sort(out, function(a, b)
        return dists[a] < dists[b]
    end)
    return out
end

local function getActiveTreasureHunts()
    local ds = getDataStore()
    local out = {}
    if not ds or not ds.Quests or not ds.Quests.Actives then return out end
    local progress = QuestSystemClient:GetProgress()
    local _, _, hrp = getCharacterParts()
    local refPos = (hrp and not isInPawnshop()) and hrp.Position or getPawnshopEnterPos()
    local scores = {}

    for questName in pairs(ds.Quests.Actives) do
        if type(questName) == "string" and questName:find("Treasure Hunt") and not questName:find("Shipwreck") then
            local guard = QuestsUtils.IsObjectiveActive(progress, TreasureHuntUtils.GetGuardObjectiveId(questName))
            local unearth = QuestsUtils.IsObjectiveActive(progress, TreasureHuntUtils.GetUnearthObjectiveId(questName))
            if not isFarTreasureHunt(questName) or guard or unearth then
                local stagePenalty = unearth and 0 or (guard and 100000 or 200000)
                local pt = TreasureHuntUtils.GetPoint(questName)
                restoreExecutorContext()
                local dist = pt and Vector2.new(pt.Position.X - refPos.X, pt.Position.Z - refPos.Z).Magnitude or 99999
                scores[questName] = stagePenalty + dist
                table.insert(out, questName)
            end
        end
    end

    table.sort(out, function(a, b)
        return scores[a] < scores[b]
    end)

    return out
end

local function getFreeShipwreck()
    local ds = getDataStore()
    if not ds then return nil end
    local ok, res = pcall(TreasureHuntUtils.GetFreeShipwreck, ds)
    if ok then
        return res
    end
    return nil
end

local function hasAvailableMapQuest()
    local ds = getDataStore()
    if not ds then return false end
    if getFreeShipwreck() ~= nil then return true end
    local actives = ds.Quests and ds.Quests.Actives or {}
    local pts = TreasureHuntUtils.GetPoints()
    restoreExecutorContext()
    for _, pt in ipairs(pts) do
        if not actives[pt.Name] then
            return true
        end
    end
    return false
end

local function hasIntroMapQuest()
    local ds = getDataStore()
    return ds ~= nil and ds.Quests ~= nil and ds.Quests.Actives ~= nil
        and ds.Quests.Actives["The Pawnbroker's Map"] ~= nil
end

local RARITY_RANK = { Common = 1, Uncommon = 2, Rare = 3, Epic = 4, Legendary = 5 }

local function findNearestChest(centerPos, radius)
    local chestsFolder = ChestsUtils.GetFolder()
    if not chestsFolder then return nil end

    local maxDist = radius or Config.ChestSearchRadius
    local bestChest = nil
    local bestRank = -1
    local bestDist = math.huge

    for _, chest in ipairs(chestsFolder:GetChildren()) do
        if chest:IsA("Model") and tonumber(chest.Name) ~= nil then
            local questOwner = chest:GetAttribute("QuestOwner")
            local sellable = chest:GetAttribute("Sellable")
            if (questOwner == nil or questOwner == LocalPlayer.UserId) and sellable ~= false then
                local pos = chest:GetPivot().Position
                local flatDist = Vector2.new(pos.X - centerPos.X, pos.Z - centerPos.Z).Magnitude
                if flatDist <= maxDist then
                    local rarity = detectChestRarity(chest)
                    local rank = RARITY_RANK[rarity] or 0
                    if rank > bestRank or (rank == bestRank and flatDist < bestDist) then
                        bestRank = rank
                        bestDist = flatDist
                        bestChest = chest
                    end
                end
            end
        end
    end

    return bestChest
end

-- Instant CarryChest + Rarity Notification
local function grabChestFast(chest, sourceKind)
    if not chest or not chest.Parent then return false end
    local chestId = tonumber(chest.Name)
    if not chestId then return false end

    local detectedRarity = detectChestRarity(chest)

    setStatus(("Tween ke [%s] Chest & carry..."):format(detectedRarity))
    local chestPos = chest:GetPivot().Position
    if not tweenTo(chestPos + Vector3.new(0, 1.5, 0), false, 8) then
        return false
    end

    Network:FireServer("Chests", "CarryChest", chestId, false)

    local grabStart = os.clock()
    local lastRetry = os.clock()
    while not isCarryingChest() and (os.clock() - grabStart) < 4 do
        if not isActive() or not chest.Parent then break end
        local _, _, hrp = getCharacterParts()
        if hrp then
            local curChestPos = chest:GetPivot().Position
            if (hrp.Position - curChestPos).Magnitude > 11 then
                tweenSegment(curChestPos + Vector3.new(0, 1.5, 0), Config.TweenSpeed, 7)
            end
        end
        if (os.clock() - lastRetry) >= 0.2 then
            Network:FireServer("Chests", "CarryChest", chestId, false)
            lastRetry = os.clock()
        end
        task.wait(0.08)
    end

    if isCarryingChest() then
        CurrentChestRarity = detectChestRarity(chest) or detectedRarity
        Stats.LastChestRarity = CurrentChestRarity
        local priceEst = ChestsUtils and ChestsUtils.Rarities and ChestsUtils.Rarities[CurrentChestRarity] and ChestsUtils.Rarities[CurrentChestRarity].SellPrice or 0
        notifyRarity(
            ("[%s] Chest Didapat!"):format(CurrentChestRarity),
            ("Sumber: %s | Est: +%s G\nMembawa ke Pawnbroker..."):format(tostring(sourceKind or "World"), formatNumber(priceEst)),
            CurrentChestRarity,
            (CurrentChestRarity == "Epic" or CurrentChestRarity == "Legendary") and 5 or 3.5
        )
        return true
    end

    return false
end

local function goToPawnbroker(isCarry)
    if not isInPawnshop() then
        local enterPos = getPawnshopEnterPos()
        setStatus(isCarry and "Membawa chest ke pintu Pawnshop..." or "Tween ke pintu Pawnshop...")
        if not tweenTo(enterPos + Vector3.new(0, 2, 0), isCarry, 5) then
            return false
        end
        if isCarry and not isCarryingChest() then
            return false
        end
        setStatus("Masuk pintu Pawnshop...")
        if not triggerCurrentDoor(true, enterPos, isCarry) then
            return false
        end
        task.wait(0.2)
    end

    if isCarry and not isCarryingChest() then
        return false
    end

    local pawnPos = getPawnbrokerPos()
    local _, _, hrp = getCharacterParts()
    if hrp and (hrp.Position - pawnPos).Magnitude <= Config.NpcInteractRange then
        return true
    end
    setStatus("Mendekati Pawnbroker...")
    return tweenSegment(pawnPos + Vector3.new(0, 2, 4), isCarry and Config.CarryTweenSpeed or Config.TweenSpeed, 6, isCarry)
end

local function sellCarriedChest(sourceKind)
    if not isCarryingChest() then return false end
    local chestAttr = LocalPlayer.Character and LocalPlayer.Character:GetAttribute("CarriedChest")
    local preSellRarity = detectChestRarity(nil)
    if CurrentChestRarity and preSellRarity == "Common" then
        -- Pastikan jika carried chest model tidak punya Rarity attribute, tetap pakai yang ditangkap saat pickup
        local carriedModel = LocalPlayer.Character and ChestsUtils and ChestsUtils.GetCarriedChest and ChestsUtils.GetCarriedChest(LocalPlayer.Character)
        if not (carriedModel and carriedModel:GetAttribute("Rarity")) then
            preSellRarity = CurrentChestRarity
        end
    end

    if not goToPawnbroker(true) then
        if not isCarryingChest() then
            CurrentChestRarity = nil
            Stats.ConsecutiveChests = 0
            Stats.Failures = Stats.Failures + 1
            logEvent("DROP: Chest #" .. tostring(chestAttr) .. " lepas saat perjalanan!")
            updateStatsUI()
        end
        return false
    end

    local haggleAccepted = false
    if Config.AutoHaggle and HaggleUtils and HaggleUtils.IsCoolingDown and not HaggleUtils.IsCoolingDown(nil, "Pawnbroker") then
        setStatus("Haggle harga chest (+15%)...")
        local okH, hRes = pcall(function()
            return Network:SafeInvokeServer(3, "Elysium_Converse", "Pawnbroker", "HaggleChest")
        end)
        if okH and hRes == "Accepted" then
            haggleAccepted = true
            Stats.HagglesWon = Stats.HagglesWon + 1
            logEvent("Haggle ACCEPTED (+15%)!")
        end
    end

    local goldBefore = getGold()
    setStatus("Menjual chest ke Pawnbroker...")
    Network:FireServer("Elysium_Converse", "Pawnbroker", "Sell", "Solo")

    local t0 = os.clock()
    local retried = false
    while isCarryingChest() and (os.clock() - t0) < 4.5 do
        if not isActive() then return false end
        if not retried and (os.clock() - t0) >= 1.6 then
            retried = true
            Network:FireServer("Elysium_Converse", "Pawnbroker", "Sell", "Solo")
        end
        task.wait(0.1)
    end

    if not isCarryingChest() then
        -- Tunggu replikasi DataStore Gold agar hasil jual terbaca akurat (bukan 0G)
        local g0 = os.clock()
        while getGold() <= goldBefore and (os.clock() - g0) < 2.5 do
            if not isActive() then break end
            task.wait(0.08)
        end

        local goldAfter = getGold()
        local gained = math.max(0, goldAfter - goldBefore)

        -- Jika gold tidak bertambah dan karakter keluar Pawnshop / mati -> chest lepas, jangan dihitung terjual!
        if gained == 0 and (not isInPawnshop() or not getCharacterParts()) then
            CurrentChestRarity = nil
            Stats.ConsecutiveChests = 0
            Stats.Failures = Stats.Failures + 1
            logEvent("DROP: Chest #" .. tostring(chestAttr) .. " lepas saat proses jual (0G)")
            updateStatsUI()
            return false
        end

        local finalRarity = preSellRarity
        if gained > 0 then
            finalRarity = detectChestRarity(nil, gained, preSellRarity)
        elseif ChestsUtils and ChestsUtils.Rarities and ChestsUtils.Rarities[finalRarity] then
            gained = ChestsUtils.Rarities[finalRarity].SellPrice
        end

        CurrentChestRarity = nil
        Stats.LastChestRarity = finalRarity
        Stats.RarityCounts[finalRarity] = (Stats.RarityCounts[finalRarity] or 0) + 1
        Stats.ConsecutiveChests = Stats.ConsecutiveChests + 1
        Stats.TotalChestsSold = Stats.TotalChestsSold + 1
        Stats.GrossChestGold = Stats.GrossChestGold + gained
        Stats.ChestGoldEarned = Stats.GrossChestGold
        Stats.NetProfit = Stats.GrossChestGold - Stats.MapsSpent
        Stats.LastChestTime = os.clock()
        if sourceKind == "Shipwreck" then
            Stats.ShipwrecksSold = Stats.ShipwrecksSold + 1
        elseif sourceKind == "TreasureHunt" then
            Stats.TreasureHuntsSold = Stats.TreasureHuntsSold + 1
        end

        logEvent(string.format("SOLD #%d [%s] (%s) +%dG | Net=%s%dG | Streak=%d",
            Stats.TotalChestsSold,
            finalRarity,
            tostring(sourceKind or "Carry"),
            gained,
            Stats.NetProfit >= 0 and "+" or "",
            Stats.NetProfit,
            Stats.ConsecutiveChests
        ))
        updateStatsUI()

        notifyRarity(
            ("[%s] Chest Sold"):format(finalRarity),
            ("+%s G%s (%s)\nNet Profit: %s%s G"):format(
                formatNumber(gained),
                haggleAccepted and " • Haggle +15%" or "",
                tostring(sourceKind or "Carry"),
                Stats.NetProfit >= 0 and "+" or "",
                formatNumber(Stats.NetProfit)
            ),
            finalRarity,
            (finalRarity == "Epic" or finalRarity == "Legendary") and 6 or 4.5
        )
        if WH.NotifyChest then
            WH.NotifyChest(finalRarity, gained, tostring(sourceKind or "Carry"), haggleAccepted == true)
        end
        return true
    end

    Stats.ConsecutiveChests = 0
    Stats.Failures = Stats.Failures + 1
    logEvent("FAIL: Sell chest timeout")
    updateStatsUI()
    return false
end

local function buyAnyMap()
    if not goToPawnbroker(false) then return false, "MoveFailed" end

    local abandonCount = 0
    for attempt = 1, 12 do
        if not isActive() then return false, "Stopped" end

        local intro = hasIntroMapQuest()
        local goldBeforeBuy = getGold()
        if not intro and goldBeforeBuy < TreasureHuntUtils.MapPrice then
            return false, "NotEnoughGold"
        end

        setStatus(("Membeli map (#%d) dari Pawnbroker..."):format(attempt))
        local arg = intro and "IntroMap" or "Map"
        local ok, res = pcall(function()
            return Network:SafeInvokeServer(5, "Elysium_Converse", "Pawnbroker", arg)
        end)

        if not ok then
            return false, "InvokeError"
        end
        if res == "QuestLimit" then
            local parked = getParkedFarTreasureHunts()
            -- Batasi maksimal 2 abandon per siklus beli agar tidak boros gold jika slot penuh quest non-TH
            if #parked > 0 and abandonCount < 2 then
                abandonCount = abandonCount + 1
                setStatus("QuestLimit -> abandon parked: " .. parked[1])
                logEvent("QuestLimit -> abandon parked: " .. parked[1])
                Network:FireServer("Quests", "Abandon", parked[1])
                task.wait(0.45)
                continue
            end
            return false, "QuestLimit"
        end
        if type(res) ~= "string" then
            return false, "NoMapReturned"
        end

        -- Hitung biaya map aktual setelah replikasi DataStore
        local cost = 0
        if not intro then
            local w0 = os.clock()
            while getGold() >= goldBeforeBuy and (os.clock() - w0) < 1.0 do
                if not isActive() then break end
                task.wait(0.08)
            end
            local diff = goldBeforeBuy - getGold()
            cost = (diff > 0 and diff <= TreasureHuntUtils.MapPrice * 2) and diff or TreasureHuntUtils.MapPrice
        end

        Stats.MapsBought = Stats.MapsBought + 1
        Stats.MapsSpent = Stats.MapsSpent + cost
        Stats.NetProfit = Stats.GrossChestGold - Stats.MapsSpent
        logEvent(string.format("Bought map: %s (-%dG)", tostring(res), cost))
        updateStatsUI()

        if res:find("Treasure Hunt") and not res:find("Shipwreck") and isFarTreasureHunt(res) then
            local dist = getTreasureHuntDistance(res)
            setStatus(("Parkir map jauh: %s (%d st)"):format(res, math.floor(dist)))
            logEvent(("Parked far map: %s (%d studs)"):format(res, math.floor(dist)))
            updateStatsUI()
            task.wait(0.3)
            continue
        end

        task.wait(0.3)
        return true, res
    end

    return false, "MaxParkAttempts"
end

local function collectShipwreckChest(questName)
    setStatus("Menunggu titik shipwreck: " .. questName)
    local wreckPos = nil
    local t0 = os.clock()
    while not wreckPos and (os.clock() - t0) < 8 do
        if not isActive() then return false end
        wreckPos = getShipwreckPosition(questName)
        if not wreckPos then task.wait(0.2) end
    end

    if not wreckPos then
        setStatus("Titik shipwreck tidak ditemukan")
        return false
    end

    if isInPawnshop() then
        if not leavePawnshop() then return false end
        task.wait(0.2)
    end

    setStatus("Tween ke lokasi shipwreck...")
    if not tweenTo(wreckPos + Vector3.new(0, 3, 0), false, 12) then
        return false
    end

    setStatus("Mencari chest di shipwreck...")
    local chest = nil
    local waitStart = os.clock()
    while not chest and (os.clock() - waitStart) < Config.ChestWaitTimeout do
        if not isActive() then return false end
        chest = findNearestChest(wreckPos, Config.ChestSearchRadius)
        if not chest then
            task.wait(0.15)
        end
    end

    if not chest then
        setStatus("Chest shipwreck tidak muncul (timeout)")
        Stats.ConsecutiveChests = 0
        Stats.Failures = Stats.Failures + 1
        logEvent("FAIL: Shipwreck chest timeout (" .. questName .. ")")
        updateStatsUI()
        return false
    end

    return grabChestFast(chest, "Shipwreck")
end

-- Smart weapon selector: khusus Class == "Default" (Sword/Melee), utamakan non-Combat
local function isDefaultMeleeTool(tool)
    if not tool or not tool:IsA("Tool") then return false end
    if not tool:GetAttribute("CombatTool") then return false end
    -- Nama asli di Vox Seas memang "Fishing Road", tetap filter "Fishing Rod" juga sebagai antisipasi update
    if tool.Name == "Navigator\xE2\x80\x99s Map" or tool.Name == "Fishing Road" or tool.Name == "Fishing Rod" then
        return false
    end
    local ok, info = pcall(function()
        return ToolsInfo:Get(tool.Name, true)
    end)
    if ok and info then
        return info.Class == "Default"
    end
    return tool.Name == "Combat"
end

local function listDefaultWeaponNames()
    local names = { "Auto (Best)" }
    local seen = {}
    local function scan(container)
        if not container then return end
        for _, t in ipairs(container:GetChildren()) do
            if isDefaultMeleeTool(t) and not seen[t.Name] then
                seen[t.Name] = true
                table.insert(names, t.Name)
            end
        end
    end
    scan(LocalPlayer.Character)
    scan(LocalPlayer:FindFirstChildOfClass("Backpack"))
    return names
end

local function equipCombatTool()
    local char, hum = getCharacterParts()
    if not char or not hum then return nil end

    local preferred = Config.PreferredWeapon
    if preferred then
        local equipped = char:FindFirstChild(preferred)
        if equipped and equipped:IsA("Tool") then return equipped end
        local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
        local inBag = backpack and backpack:FindFirstChild(preferred)
        if inBag and inBag:IsA("Tool") then
            hum:EquipTool(inBag)
            task.wait(0.1)
            return inBag
        end
    end

    for _, t in ipairs(char:GetChildren()) do
        if isDefaultMeleeTool(t) then
            return t
        end
    end

    local fallbackCombat = nil
    local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
    if backpack then
        for _, t in ipairs(backpack:GetChildren()) do
            if isDefaultMeleeTool(t) then
                if t.Name ~= "Combat" then
                    hum:EquipTool(t)
                    task.wait(0.1)
                    return t
                else
                    fallbackCombat = t
                end
            end
        end
    end

    if fallbackCombat then
        hum:EquipTool(fallbackCombat)
        task.wait(0.1)
        return fallbackCombat
    end

    return nil
end

local function isEnemyAlive(model, allowUnrendered)
    if not model or not model.Parent then return false end
    if model:GetAttribute("Dead") == true then return false end
    if not allowUnrendered and model:GetAttribute("Render") == false then return false end
    local hum = model:FindFirstChildOfClass("Humanoid")
    local hrp = model:FindFirstChild("HumanoidRootPart")
    if not hum or not hrp or hum.Health <= 0 then return false end
    local st = hum:GetState()
    if st == Enum.HumanoidStateType.Dead then
        return false
    end
    return true
end

local function matchesTreasureSkeleton(orig, seaPrefix, num)
    if type(orig) ~= "string" then return false end
    if not orig:find("Treasure Skeleton", 1, true) then return false end
    if num then
        if seaPrefix and orig == (seaPrefix .. " Treasure Skeleton " .. num) then
            return true
        end
        return orig:match("Treasure Skeleton%s*(%d+)$") == num
    end
    return true
end

local function findTreasureGuards(questName, digPos, allowUnrendered, maxRadius, skippedTargets)
    local enemys = workspace:FindFirstChild("Playability") and workspace.Playability:FindFirstChild("Enemys")
    if not enemys then return {} end

    local seaPrefix = string.match(questName, "^(.-)%s+Treasure Hunt")
    local num = string.match(questName, "(%d+)$")
    local radius = maxRadius or 260
    local list = {}
    local now = os.clock()

    for _, model in ipairs(enemys:GetChildren()) do
        if model:IsA("Model")
            and not (skippedTargets and skippedTargets[model] and skippedTargets[model] > now)
            and isEnemyAlive(model, allowUnrendered)
        then
            local orig = model:GetAttribute("OriginalName")
            local hrp = model:FindFirstChild("HumanoidRootPart")
            if hrp then
                local matchName = (allowUnrendered and maxRadius)
                    and matchesTreasureSkeleton(orig, seaPrefix, num)
                    or (type(orig) == "string" and orig:find("Treasure Skeleton", 1, true) ~= nil)
                local nearDig = (hrp.Position - digPos).Magnitude <= radius
                if matchName and nearDig then
                    table.insert(list, model)
                end
            end
        end
    end

    if #list == 0 and not maxRadius and not allowUnrendered then
        for _, model in ipairs(enemys:GetChildren()) do
            if model:IsA("Model")
                and not (skippedTargets and skippedTargets[model] and skippedTargets[model] > now)
                and isEnemyAlive(model, false)
            then
                local orig = model:GetAttribute("OriginalName")
                local hrp = model:FindFirstChild("HumanoidRootPart")
                if hrp and matchesTreasureSkeleton(orig, seaPrefix, num) and (hrp.Position - digPos).Magnitude <= 750 then
                    table.insert(list, model)
                end
            end
        end
    end

    local _, _, myHrp = getCharacterParts()
    if myHrp and #list > 1 then
        local myPos = myHrp.Position
        local dists = {}
        for _, m in ipairs(list) do
            local h = m:FindFirstChild("HumanoidRootPart")
            dists[m] = h and (h.Position - myPos).Magnitude or 999999
        end
        table.sort(list, function(a, b)
            return dists[a] < dists[b]
        end)
    end

    return list
end

local function parseServerPosition()
    local sp = LocalPlayer:GetAttribute("ServerPosition")
    if typeof(sp) == "Vector3" then return sp end
    if type(sp) == "string" then
        local x, y, z = string.match(sp, "([%-%d%.]+),%s*([%-%d%.]+),%s*([%-%d%.]+)")
        if x and y and z then
            return Vector3.new(tonumber(x), tonumber(y), tonumber(z))
        end
    end
    return nil
end

local function waitServerSettleNear(targetPos, maxDist, maxWait)
    local t0 = os.clock()
    local limit = maxWait or 1.5
    local radius = maxDist or 12
    while (os.clock() - t0) < limit do
        if not isActive() then return false end
        local sp = parseServerPosition()
        if sp and (sp - targetPos).Magnitude <= radius then
            return true
        end
        task.wait(0.08)
    end
    return true
end

local function performDig(questName, pt, objectiveId)
    if pt then
        waitServerSettleNear(pt.Position, 12, 1.5)
    else
        task.wait(0.35)
    end

    setStatus("Menggali X (" .. questName .. ")...")
    if DiggingClient and pt then
        pcall(DiggingClient.Begin, pt)
    end
    Network:FireServer("QuestCustoms", "Treasure Hunt", "StartDig", questName)

    local t0 = os.clock()
    local waitTime = (TreasureHuntUtils.DigDuration or 3.167) + 0.25
    while (os.clock() - t0) < waitTime do
        if not isActive() then
            if DiggingClient then pcall(DiggingClient.Cancel) end
            return false
        end
        if objectiveId and not QuestsUtils.IsObjectiveActive(QuestSystemClient:GetProgress(), objectiveId) then
            if DiggingClient then pcall(DiggingClient.Cancel) end
            return true
        end
        task.wait(0.08)
    end

    if DiggingClient then
        pcall(DiggingClient.Complete)
    end
    Network:FireServer("QuestCustoms", "Treasure Hunt", "Dig", questName)

    if objectiveId then
        local c0 = os.clock()
        local retried = false
        while QuestsUtils.IsObjectiveActive(QuestSystemClient:GetProgress(), objectiveId) and (os.clock() - c0) < 1.8 do
            if not isActive() then return false end
            if not retried and (os.clock() - c0) >= 0.8 then
                retried = true
                Network:FireServer("QuestCustoms", "Treasure Hunt", "Dig", questName)
            end
            task.wait(0.1)
        end
        return not QuestsUtils.IsObjectiveActive(QuestSystemClient:GetProgress(), objectiveId)
    end

    task.wait(0.3)
    return true
end

-- Generalized Heartbeat CFrame Lock Combat Engine (dipakai bersama oleh Treasure Hunt, Side Quest & Level Farm)
local function engageEnemies(opts)
    local shouldContinue = opts.shouldContinue
    local findTargets = opts.findTargets
    local anchorPos = opts.anchorPos
    local getProgressKey = opts.getProgressKey
    local isTargetValid = opts.isTargetValid
    local statusFn = opts.statusFn or setStatus
    local attackMode = opts.attackMode
    local useAutoHaki = opts.autoHaki == true
    local useAutoSkills = opts.autoSkills == true
    local timeout = opts.timeout or 90
    local statusPrefix = opts.statusPrefix or "Melawan Musuh"
    local waitStatus = opts.waitStatus or "Menunggu musuh..."
    local safeRegenHpPct = opts.safeRegenHpPct or 0.25

    local tool = equipCombatTool()
    local fightStart = os.clock()
    local noTargetSince = nil
    local patrolIdx = 0

    setNoclip(true)

    local currentTarget = nil
    local targetStart = 0
    local lastTargetHp = nil
    local skippedTargets = {}
    local cachedLockOffset = nil
    local lastOffsetCheck = 0
    local angleBias = 0

    local lastProgressVal = getProgressKey and getProgressKey() or nil
    local lastProgressTime = os.clock()

    local rayParams = RaycastParams.new()
    rayParams.FilterType = Enum.RaycastFilterType.Exclude
    local cachedFilterChar = nil
    local function refreshRayFilter()
        local char = LocalPlayer.Character
        if char ~= cachedFilterChar then
            cachedFilterChar = char
            local exclude = {}
            if char then table.insert(exclude, char) end
            local play = workspace:FindFirstChild("Playability")
            local enemys = play and play:FindFirstChild("Enemys")
            if enemys then table.insert(exclude, enemys) end
            local ignoreList = workspace:FindFirstChild("IgnoreList")
            if ignoreList then table.insert(exclude, ignoreList) end
            rayParams.FilterDescendantsInstances = exclude
        end
    end
    refreshRayFilter()

    local function computeSafeLockOffset(tHrp, bias)
        refreshRayFilter()
        local tPos = tHrp.Position
        local tOrigin = Vector3.new(tPos.X, tPos.Y + 1.5, tPos.Z)
        if attackMode == "Above" or attackMode == "Atas (Aman)" then
            if workspace:Raycast(tOrigin, Vector3.new(0, 5.8, 0), rayParams) == nil then
                return Vector3.new(0, 5.4, 0)
            end
        end
        local back = -tHrp.CFrame.LookVector
        local flatBack = Vector3.new(back.X, 0, back.Z)
        if flatBack.Magnitude < 0.05 then
            flatBack = Vector3.new(0, 0, 1)
        else
            flatBack = flatBack.Unit
        end
        local flatRight = Vector3.new(-flatBack.Z, 0, flatBack.X)
        local dirs = {
            flatBack,
            flatRight,
            -flatRight,
            (flatBack + flatRight).Unit,
            (flatBack - flatRight).Unit,
            -flatBack,
            (-flatBack + flatRight).Unit,
            (-flatBack - flatRight).Unit,
        }
        local shift = bias % 8
        for i = 1, 8 do
            local dir = dirs[((i - 1 + shift) % 8) + 1]
            if workspace:Raycast(tOrigin, dir * 4.0, rayParams) == nil then
                return Vector3.new(dir.X * 3.4, 0.3, dir.Z * 3.4)
            end
        end
        if workspace:Raycast(tOrigin, Vector3.new(0, 4.2, 0), rayParams) == nil then
            return Vector3.new(0, 3.8, 0)
        end
        return Vector3.new(0, 2.5, 0)
    end

    if CombatLockConn then
        CombatLockConn:Disconnect()
        CombatLockConn = nil
    end

    CombatLockConn = RunService.Heartbeat:Connect(function(rawDt)
        if not isActive() then return end
        local _, myHumNow, hrpNow = getCharacterParts()
        if not hrpNow then return end
        if not currentTarget or not currentTarget.Parent then return end
        local tHrp = currentTarget:FindFirstChild("HumanoidRootPart") or currentTarget.PrimaryPart
        if not tHrp then return end

        neutralizeSwimFight(myHumNow, hrpNow)

        local tPos = tHrp.Position
        if (hrpNow.Position - tPos).Magnitude > 28 then return end

        local offset = cachedLockOffset or Vector3.new(0, 0.3, 3.4)
        local lockPos = tPos + offset
        local delta = lockPos - hrpNow.Position
        local stepPos = lockPos
        if delta.Magnitude > 7 then
            local dt = math.min(rawDt, 0.05)
            local stepLen = math.min(delta.Magnitude, (Config.TweenSpeed or 400) * dt)
            stepPos = hrpNow.Position + delta.Unit * stepLen
        end

        if math.abs(offset.X) < 0.1 and math.abs(offset.Z) < 0.1 then
            hrpNow.CFrame = CFrame.lookAt(stepPos, tPos, Vector3.new(0, 0, 1))
        else
            hrpNow.CFrame = CFrame.lookAt(stepPos, Vector3.new(tPos.X, stepPos.Y, tPos.Z))
        end
        hrpNow.AssemblyLinearVelocity = Vector3.zero
        hrpNow.AssemblyAngularVelocity = Vector3.zero
    end)

    local lastSwing = 0
    local skillWaitStart = nil

    while isActive()
        and shouldContinue()
        and (os.clock() - fightStart) < timeout
    do
        if getProgressKey then
            local curVal = getProgressKey()
            if curVal ~= lastProgressVal then
                lastProgressVal = curVal
                lastProgressTime = os.clock()
                angleBias = 0
            end
        end

        if currentTarget and currentTarget.Parent then
            local tHum = currentTarget:FindFirstChildOfClass("Humanoid")
            if tHum then
                if lastTargetHp == nil or tHum.Health < lastTargetHp - 0.5 then
                    lastTargetHp = tHum.Health
                    lastProgressTime = os.clock()
                end
            end
        end

        local _, myHum, myHrp = getCharacterParts()
        if not myHrp or not myHum then
            currentTarget = nil
            lastTargetHp = nil
            cachedLockOffset = nil
            task.wait(0.25)
            continue
        end

        if myHum.MaxHealth > 0 and (myHum.Health / myHum.MaxHealth) < safeRegenHpPct then
            currentTarget = nil
            lastTargetHp = nil
            cachedLockOffset = nil
            statusFn("Low HP, healing...")
            tweenSegment(myHrp.Position + Vector3.new(0, 40, 0), Config.TweenSpeed, 4, false, true)
            task.wait(3)
            continue
        end

        ensureBodyVelocity(myHrp)
        if useAutoHaki and LF.EnsureHaki then
            LF.EnsureHaki()
        end

        local timedOutTarget = currentTarget ~= nil and (os.clock() - targetStart) > 18
        if timedOutTarget then
            skippedTargets[currentTarget] = os.clock() + 10
        end
        local invalidTarget = currentTarget ~= nil and isTargetValid and not isTargetValid(currentTarget)

        if not currentTarget or not isEnemyAlive(currentTarget, false) or timedOutTarget or invalidTarget then
            local targets = findTargets(false, nil, skippedTargets)
            if #targets == 0 and next(skippedTargets) ~= nil then
                skippedTargets = {}
                targets = findTargets(false, nil, nil)
            end
            if #targets == 0 then
                currentTarget = nil
                lastTargetHp = nil
                cachedLockOffset = nil
                noTargetSince = noTargetSince or os.clock()
                statusFn(waitStatus)
                local waitDur = os.clock() - noTargetSince
                if waitDur > 4.0 then
                    local unrendered = findTargets(true, 750, nil)
                    if #unrendered > 0 then
                        patrolIdx = (patrolIdx % #unrendered) + 1
                        local uHrp = unrendered[patrolIdx]:FindFirstChild("HumanoidRootPart") or unrendered[patrolIdx].PrimaryPart
                        if uHrp then
                            tweenSegment(uHrp.Position + Vector3.new(0, 6, 0), Config.TweenSpeed, 12, false, true)
                            task.wait(0.45)
                            continue
                        end
                    end
                elseif waitDur > 2.0 and anchorPos then
                    if (myHrp.Position - anchorPos).Magnitude > 22 then
                        tweenSegment(anchorPos + Vector3.new(0, 6, 0), Config.TweenSpeed, 12, false, true)
                    end
                end
                task.wait(0.2)
                continue
            else
                noTargetSince = nil
                patrolIdx = 0
                currentTarget = targets[1]
                targetStart = os.clock()
                lastProgressTime = os.clock()
                local tHum = currentTarget:FindFirstChildOfClass("Humanoid")
                lastTargetHp = tHum and tHum.Health or nil
                angleBias = 0
                local newHrp = currentTarget:FindFirstChild("HumanoidRootPart") or currentTarget.PrimaryPart
                cachedLockOffset = newHrp and computeSafeLockOffset(newHrp, angleBias) or Vector3.new(0, 0.3, 3.4)
                lastOffsetCheck = os.clock()
                statusFn(("%s (%d nearby)"):format(statusPrefix, #targets))
            end
        end

        local tHrp = currentTarget and (currentTarget:FindFirstChild("HumanoidRootPart") or currentTarget.PrimaryPart)
        if tHrp then
            if (os.clock() - lastProgressTime) > 4.0 then
                angleBias = (angleBias + 1) % 8
                pcall(function() myHum:UnequipTools() end)
                task.wait(0.06)
                tool = equipCombatTool()
                cachedLockOffset = computeSafeLockOffset(tHrp, angleBias) + Vector3.new(0, 1.2, 0)
                lastOffsetCheck = os.clock()
                lastProgressTime = os.clock()
            elseif not cachedLockOffset or (os.clock() - lastOffsetCheck) >= 0.2 then
                cachedLockOffset = computeSafeLockOffset(tHrp, angleBias)
                lastOffsetCheck = os.clock()
            end

            if (myHrp.Position - tHrp.Position).Magnitude > 24 then
                local savedTarget = currentTarget
                currentTarget = nil
                tweenSegment(tHrp.Position + Vector3.new(0, 2, 3.5), Config.TweenSpeed, 7, false, true)
                currentTarget = savedTarget
                cachedLockOffset = computeSafeLockOffset(tHrp, angleBias)
                lastOffsetCheck = os.clock()
            end

            local charNow = LocalPlayer.Character
            if not tool or tool.Parent ~= charNow then
                tool = equipCombatTool()
            end

            local wantSkill = false
            if useAutoSkills and LF.HasReadySkill and (myHrp.Position - tHrp.Position).Magnitude <= 14 then
                wantSkill = LF.HasReadySkill()
            end

            if wantSkill then
                skillWaitStart = skillWaitStart or os.clock()
                local fired = LF.CastCombatSkill and LF.CastCombatSkill(currentTarget) or false
                if fired then
                    skillWaitStart = nil
                    lastSwing = os.clock() + 0.12
                elseif (os.clock() - skillWaitStart) > 0.55 then
                    -- Fallback ke M1 jika state belum kunjung clear agar combat tidak pernah stall
                    skillWaitStart = nil
                    if (os.clock() - lastSwing) >= 0.14 and tool and tool.Parent == charNow then
                        tool:Activate()
                        lastSwing = os.clock()
                    end
                end
            else
                skillWaitStart = nil
                if (os.clock() - lastSwing) >= 0.14 then
                    if tool and tool.Parent == charNow then
                        tool:Activate()
                    end
                    lastSwing = os.clock()
                end
            end
        end

        task.wait(0.05)
    end

    if CombatLockConn then
        CombatLockConn:Disconnect()
        CombatLockConn = nil
    end
    local _, _, endHrp = getCharacterParts()
    clearBodyVelocity(endHrp)
    setNoclip(false)
    return not shouldContinue()
end

-- Wrapper kompatibel untuk Treasure Hunt Skeleton Guards
local function clearAllGuards(questName, digPos, guardObjId)
    return engageEnemies({
        shouldContinue = function()
            return isActive("Shipwreck") and QuestsUtils.IsObjectiveActive(QuestSystemClient:GetProgress(), guardObjId)
        end,
        findTargets = function(allowUnrendered, maxRadius, skippedTargets)
            return findTreasureGuards(questName, digPos, allowUnrendered, maxRadius, skippedTargets)
        end,
        anchorPos = digPos,
        getProgressKey = function()
            local prog = QuestSystemClient:GetProgress()
            return prog and prog.ObjectiveIds and prog.ObjectiveIds[guardObjId]
        end,
        timeout = 75,
        statusPrefix = "Melawan Skeleton",
        waitStatus = "Menunggu Skeleton guard...",
    })
end

local function collectTreasureHuntChest(questName)
    local pt = TreasureHuntUtils.GetPoint(questName)
    restoreExecutorContext()
    if not pt then
        setStatus("Titik Treasure Hunt tidak ditemukan: " .. questName)
        return false
    end
    local digPos = pt.Position

    if isInPawnshop() then
        if not leavePawnshop() then return false end
        task.wait(0.2)
    end

    local digObjId = TreasureHuntUtils.GetObjectiveId(questName)
    local guardObjId = TreasureHuntUtils.GetGuardObjectiveId(questName)
    local unearthObjId = TreasureHuntUtils.GetUnearthObjectiveId(questName)

    if QuestsUtils.IsObjectiveActive(QuestSystemClient:GetProgress(), digObjId) then
        setStatus("Tween ke pulau Treasure Hunt: " .. questName)
        if not tweenTo(digPos + Vector3.new(0, 1, 0), false, 2.5) then
            return false
        end
        local digOk = false
        for _ = 1, 2 do
            if not isActive() then return false end
            if performDig(questName, pt, digObjId) then
                digOk = true
                break
            end
            tweenSegment(digPos + Vector3.new(0, 1, 0), Config.TweenSpeed, 2)
        end
        if not digOk then
            setStatus("Gagal gali pertama: " .. questName)
            return false
        end
    end

    if QuestsUtils.IsObjectiveActive(QuestSystemClient:GetProgress(), guardObjId) then
        local _, _, hrp = getCharacterParts()
        if hrp and (hrp.Position - digPos).Magnitude > 160 then
            setStatus("Tween ke area Skeleton: " .. questName)
            if not tweenTo(digPos + Vector3.new(0, 3, 0), false, 15) then
                return false
            end
        end
        clearAllGuards(questName, digPos, guardObjId)
    end

    if QuestsUtils.IsObjectiveActive(QuestSystemClient:GetProgress(), unearthObjId) then
        setStatus("Tween ke titik X untuk Unearth...")
        if not tweenTo(digPos + Vector3.new(0, 1, 0), false, 2.5) then return false end
        local unearthOk = false
        for _ = 1, 2 do
            if not isActive() then return false end
            if performDig(questName, pt, unearthObjId) then
                unearthOk = true
                break
            end
            tweenSegment(digPos + Vector3.new(0, 1, 0), Config.TweenSpeed, 2)
        end
        if not unearthOk then
            setStatus("Gagal unearth: " .. questName)
            return false
        end
    end

    local progressNow = QuestSystemClient:GetProgress()
    if QuestsUtils.IsObjectiveActive(progressNow, digObjId)
        or QuestsUtils.IsObjectiveActive(progressNow, guardObjId)
        or QuestsUtils.IsObjectiveActive(progressNow, unearthObjId) then
        return false
    end

    setStatus("Mencari chest hasil galian...")
    local chest = nil
    local waitStart = os.clock()
    while not chest and (os.clock() - waitStart) < Config.ChestWaitTimeout do
        if not isActive() then return false end
        chest = findNearestChest(digPos, 150)
        if not chest then task.wait(0.15) end
    end

    if not chest then
        setStatus("Chest galian tidak muncul (timeout)")
        Stats.ConsecutiveChests = 0
        Stats.Failures = Stats.Failures + 1
        logEvent("FAIL: TreasureHunt chest timeout (" .. questName .. ")")
        updateStatsUI()
        return false
    end

    return grabChestFast(chest, "TreasureHunt")
end

-- ============================================================================
-- AUTO SIDE QUEST ENGINE (KHUSUS ONE-TIME / PROGRESSION SIDE QUESTS LV 5 - 310)
-- ============================================================================
do
local function getPlayerLevel()
    local ds = getDataStore()
    if ds and ds.Statistics and type(ds.Statistics.Level) == "number" then
        return ds.Statistics.Level
    end
    return tonumber(LocalPlayer:GetAttribute("Level")) or 1
end

local function isQuestCompleted(questName)
    local ok, res = pcall(QuestsUtils.QuestIsCompleted, LocalPlayer, questName)
    restoreExecutorContext()
    return ok and res ~= nil
end

local function isQuestActive(questName)
    local ds = getDataStore()
    return ds ~= nil and ds.Quests ~= nil and ds.Quests.Actives ~= nil
        and ds.Quests.Actives[questName] ~= nil
end

local function isObjectiveActive(objId)
    local prog = QuestSystemClient:GetProgress()
    return QuestsUtils.IsObjectiveActive(prog, objId) == true
end

local function isObjectiveDoneForQuest(questName, objId)
    if isQuestCompleted(questName) then return true end
    local ds = getDataStore()
    local active = ds and ds.Quests and ds.Quests.Actives and ds.Quests.Actives[questName]
    if not active then return false end
    local map = QuestsUtils.GetQuestsByObjectiveId and QuestsUtils.GetQuestsByObjectiveId(objId)
    local list = map and map[questName]
    local entry = list and list[1]
    if entry then
        local sq = active[entry.SubQuestIndex]
        local cur = sq and sq[entry.ObjectiveIndex]
        if type(cur) == "number" and cur >= (entry.Goal or 1) then
            return true
        end
        local qInfo = QuestsInfo and QuestsInfo[questName]
        if qInfo and QuestsUtils.GetCurrentSubQuestIndex then
            local curIdx = QuestsUtils.GetCurrentSubQuestIndex(active, qInfo)
            if curIdx > entry.SubQuestIndex then
                return true
            end
        end
        return false
    end
    return not isObjectiveActive(objId)
end

local function getOwnedToolAmount(toolName)
    if ToolsUtils and ToolsUtils.GetOwnedAmount then
        local ok, amt = pcall(ToolsUtils.GetOwnedAmount, nil, toolName)
        restoreExecutorContext()
        if ok and type(amt) == "number" then
            return amt
        end
    end
    local char = LocalPlayer.Character
    local bp = LocalPlayer:FindFirstChildOfClass("Backpack")
    if (char and char:FindFirstChild(toolName)) or (bp and bp:FindFirstChild(toolName)) then
        return 1
    end
    return 0
end

local function resolveInterestPointPos(ipKey, fallbackPos)
    if ipKey and InterestPoints and InterestPoints.Points then
        local val = InterestPoints.Points[ipKey]
        if typeof(val) == "Vector3" then
            return val
        elseif typeof(val) == "Instance" then
            local ok, pv = pcall(function() return val:GetPivot().Position end)
            if ok and pv then return pv end
        elseif type(val) == "table" and typeof(val.Position) == "Vector3" then
            return val.Position
        end
    end
    return fallbackPos
end

local function resolveZonePos(zoneName, fallbackPos)
    local part = findQuestZonePart(zoneName)
    if part then
        if part:IsA("BasePart") then
            return part.Position
        end
        local ok, pv = pcall(function() return part:GetPivot().Position end)
        if ok and pv then return pv end
    end
    return fallbackPos
end

local function resolveObjectiveDynamicPos(questName, objId, fallbackPos)
    local qInfo = QuestsInfo and QuestsInfo[questName]
    if qInfo and qInfo.SubQuests then
        for _, sq in ipairs(qInfo.SubQuests) do
            for _, ob in pairs(sq.Objectives or {}) do
                if ob.ObjectiveID == objId then
                    local fn = ob.InterestPoint or ob.Point
                    if type(fn) == "function" then
                        local ok, res = pcall(fn, LocalPlayer)
                        restoreExecutorContext()
                        if ok and res ~= nil then
                            if typeof(res) == "Vector3" then
                                return res
                            elseif typeof(res) == "Instance" then
                                local okP, pv = pcall(function() return res:GetPivot().Position end)
                                if okP and pv then return pv end
                            elseif type(res) == "string" then
                                local ipPos = resolveInterestPointPos(res, nil)
                                if ipPos then return ipPos end
                            end
                        end
                    end
                end
            end
        end
    end
    return resolveZonePos(objId, fallbackPos)
end

-- Auto-abandon 1 Treasure Hunt (utamakan parkir jauh) jika slot quest penuh saat mengambil Side Quest
local function tryAbandonTreasureHuntForSideQuest()
    if not Config.SideQuestAutoAbandonTH then return false end
    local parked = getParkedFarTreasureHunts()
    if #parked > 0 then
        local victim = parked[#parked] -- parkir terjauh dulu
        setSQStatus("QuestLimit -> abandon parkir TH: " .. victim)
        logEvent("SQ QuestLimit -> abandon parked TH: " .. victim)
        Network:FireServer("Quests", "Abandon", victim)
        SQStats.AbandonedTH = SQStats.AbandonedTH + 1
        task.wait(0.55)
        updateStatsUI()
        return true
    end

    local ds = getDataStore()
    local actives = ds and ds.Quests and ds.Quests.Actives
    if actives then
        local candidate = nil
        for qName in pairs(actives) do
            if type(qName) == "string" and (qName:find("Treasure Hunt") or qName:find("Shipwreck")) then
                candidate = qName
                if not qName:find("Shipwreck") then break end
            end
        end
        if candidate then
            setSQStatus("QuestLimit -> abandon TH aktif: " .. candidate)
            logEvent("SQ QuestLimit -> abandon active TH: " .. candidate)
            Network:FireServer("Quests", "Abandon", candidate)
            SQStats.AbandonedTH = SQStats.AbandonedTH + 1
            task.wait(0.55)
            updateStatsUI()
            return true
        end
    end

    return false
end

local function runConverseAction(converseName, action, ipKey, fallbackPos, checkDoneFn, allowAbandon)
    local npcPos = resolveInterestPointPos(ipKey, fallbackPos)
    if not npcPos then return false end

    if not navigateToPos(npcPos + Vector3.new(0, 1.5, 0), false, 8) then
        return false
    end
    waitServerSettleNear(npcPos, 12, 1.8)

    local abandonedOnce = false
    for attempt = 1, 3 do
        if not isActive("SideQuest") then return false end
        if checkDoneFn and checkDoneFn() then return true end

        if action ~= nil then
            Network:FireServer("Elysium_Converse", converseName, action)
        else
            Network:FireServer("Elysium_Converse", converseName)
        end

        local w0 = os.clock()
        while (os.clock() - w0) < 2.2 do
            if not isActive("SideQuest") then return false end
            if checkDoneFn and checkDoneFn() then return true end
            task.wait(0.1)
        end

        if allowAbandon and not abandonedOnce and checkDoneFn and not checkDoneFn() then
            if tryAbandonTreasureHuntForSideQuest() then
                abandonedOnce = true
                continue
            end
        end

        if attempt < 3 then
            npcPos = resolveInterestPointPos(ipKey, fallbackPos) or npcPos
            navigateToPos(npcPos + Vector3.new(0, 1.5, 2), false, 5)
            waitServerSettleNear(npcPos, 10, 1.0)
        end
    end

    return checkDoneFn and checkDoneFn() or false
end

local function runQuestZoneObjective(questName, objId, fallbackPos, holdSec, allowAbandon)
    local function done()
        return isObjectiveDoneForQuest(questName, objId)
    end
    if done() then return true end

    local zPos = resolveZonePos(objId, fallbackPos)
    if not zPos then return false end

    if not navigateToPos(zPos + Vector3.new(0, 1.2, 0), false, 3.5) then
        return false
    end
    waitServerSettleNear(zPos, 10, 1.8)

    local waitDur = holdSec or 2.2
    local abandonedOnce = false
    for attempt = 1, 3 do
        if not isActive("SideQuest") then return false end
        if done() then return true end

        Network:FireServer("QuestZones", objId, "Start")

        local t0 = os.clock()
        while (os.clock() - t0) < waitDur do
            if not isActive("SideQuest") then return false end
            if done() then return true end
            task.wait(0.1)
        end

        Network:FireServer("QuestZones", objId, "Use")

        local c0 = os.clock()
        local retriedUse = false
        while (os.clock() - c0) < 2.5 do
            if not isActive("SideQuest") then return false end
            if done() then return true end
            if not retriedUse and (os.clock() - c0) >= 1.2 then
                retriedUse = true
                Network:FireServer("QuestZones", objId, "Use")
            end
            task.wait(0.1)
        end

        if allowAbandon and not abandonedOnce and not done() then
            if tryAbandonTreasureHuntForSideQuest() then
                abandonedOnce = true
                continue
            end
        end

        if attempt < 3 then
            zPos = resolveZonePos(objId, fallbackPos) or zPos
            navigateToPos(zPos + Vector3.new(0, 1.0, 0), false, 2.5)
            waitServerSettleNear(zPos, 8, 1.2)
        end
    end

    return done()
end

local function runReachZoneObjective(questName, objId, fallbackPos)
    local function done()
        return isObjectiveDoneForQuest(questName, objId)
    end
    if done() then return true end

    local zPos = resolveZonePos(objId, fallbackPos)
    if not zPos then return false end

    if not navigateToPos(zPos + Vector3.new(0, 2, 0), false, 3.5) then
        return false
    end
    waitServerSettleNear(zPos, 10, 2.0)

    local offsets = {
        Vector3.new(0, 1.5, 0),
        Vector3.new(3, 1.5, 0),
        Vector3.new(-3, 1.5, 0),
        Vector3.new(0, 1.5, 3),
        Vector3.new(0, 1.5, -3),
    }
    local t0 = os.clock()
    local idx = 1
    while (os.clock() - t0) < 7.0 do
        if not isActive("SideQuest") then return false end
        if done() then return true end
        local off = offsets[idx]
        idx = (idx % #offsets) + 1
        tweenSegment(zPos + off, Config.TweenSpeed, 2)
        task.wait(0.45)
    end
    return done()
end

local function findSideQuestEnemies(enemyNames, anchorPos, allowUnrendered, maxRadius, skippedTargets)
    local enemys = workspace:FindFirstChild("Playability") and workspace.Playability:FindFirstChild("Enemys")
    if not enemys then return {} end

    local radius = maxRadius or 380
    local list = {}
    local now = os.clock()

    local function matchesName(model)
        local orig = model:GetAttribute("OriginalName")
        local mName = model.Name
        for _, targetName in ipairs(enemyNames) do
            if orig == targetName or mName == targetName then
                return true
            end
            if type(orig) == "string" and orig:find(targetName, 1, true) then
                return true
            end
            if type(mName) == "string" and mName:find(targetName, 1, true) then
                return true
            end
        end
        return false
    end

    for _, model in ipairs(enemys:GetChildren()) do
        if model:IsA("Model")
            and not (skippedTargets and skippedTargets[model] and skippedTargets[model] > now)
            and isEnemyAlive(model, allowUnrendered)
            and matchesName(model)
        then
            local hrp = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
            if hrp and (not anchorPos or (hrp.Position - anchorPos).Magnitude <= radius) then
                table.insert(list, model)
            end
        end
    end

    local _, _, myHrp = getCharacterParts()
    if myHrp and #list > 1 then
        local myPos = myHrp.Position
        local dists = {}
        for _, m in ipairs(list) do
            local h = m:FindFirstChild("HumanoidRootPart") or m.PrimaryPart
            dists[m] = h and (h.Position - myPos).Magnitude or 999999
        end
        table.sort(list, function(a, b)
            return dists[a] < dists[b]
        end)
    end
    return list
end

local function runCombatObjective(questName, objIds, enemyNames, anchorPos, timeoutSec)
    local function anyObjActive()
        if isQuestCompleted(questName) then return false end
        for _, id in ipairs(objIds) do
            if isObjectiveActive(id) then
                return true
            end
        end
        return false
    end
    if not anyObjActive() then return true end

    if anchorPos then
        local _, _, hrp = getCharacterParts()
        if not hrp or (hrp.Position - anchorPos).Magnitude > 140 then
            if not navigateToPos(anchorPos + Vector3.new(0, 4, 0), false, 15) then
                return false
            end
        end
    end

    return engageEnemies({
        shouldContinue = function()
            return isActive("SideQuest") and anyObjActive()
        end,
        findTargets = function(allowUnrendered, maxRadius, skippedTargets)
            return findSideQuestEnemies(enemyNames, anchorPos, allowUnrendered, maxRadius, skippedTargets)
        end,
        anchorPos = anchorPos,
        getProgressKey = function()
            local prog = QuestSystemClient:GetProgress()
            local sum = 0
            if prog and prog.ObjectiveIds then
                for _, id in ipairs(objIds) do
                    sum = sum + (tonumber(prog.ObjectiveIds[id]) or 0)
                end
            end
            return sum
        end,
        timeout = timeoutSec or 110,
        statusPrefix = "SQ Combat (" .. questName .. ")",
        waitStatus = "Menunggu musuh (" .. table.concat(enemyNames, "/") .. ")...",
    })
end

-- Handler khusus: The Runaway Cat (WildlifeSystem PetCat)
local function runRunawayCatQuest()
    if isQuestCompleted("The Runaway Cat") then return true end
    SQStats.CurrentObjective = "Pet_RooftopCat_SQ"
    setSQStatus("Mencari Solmar Rooftop Cat...")

    local function getCatModelAndPos()
        local ignore = workspace:FindFirstChild("IgnoreList")
        local wild = ignore and ignore:FindFirstChild("Wildlife")
        local misc = wild and wild:FindFirstChild("Miscellaneous")
        local catRoot = misc and misc:FindFirstChild("Solmar Rooftop Cat")
        if catRoot then
            local catModel = catRoot:FindFirstChild("Cat") or catRoot
            local bodyPart = nil
            local catSub = catModel:FindFirstChild("CAT")
            if catSub then
                bodyPart = catSub:FindFirstChild("Cat")
            end
            if not bodyPart then
                bodyPart = catModel:FindFirstChildWhichIsA("BasePart", true)
            end
            if bodyPart and bodyPart:IsA("BasePart") then
                return catModel, bodyPart.Position
            end
        end
        local dynPos = resolveObjectiveDynamicPos("The Runaway Cat", "Pet_RooftopCat_SQ", nil)
        return catRoot, dynPos
    end

    local catModel, catPos = getCatModelAndPos()
    if not catPos then
        -- Terbang ke pusat desa Solmar agar kucing rooftop ter-stream
        if not navigateToPos(Vector3.new(20, 48, 420), false, 15) then
            return false
        end
        local w0 = os.clock()
        while not catPos and (os.clock() - w0) < 6.0 do
            if not isActive("SideQuest") then return false end
            catModel, catPos = getCatModelAndPos()
            if not catPos then task.wait(0.25) end
        end
    end

    if not catModel or not catPos then
        return false
    end

    local abandonedOnce = false
    for attempt = 1, 3 do
        if not isActive("SideQuest") then return false end
        if isQuestCompleted("The Runaway Cat") then return true end
        catModel, catPos = getCatModelAndPos()
        if not catModel or not catPos then return false end

        setSQStatus("Mendekati & elus Solmar Rooftop Cat...")
        if not navigateToPos(catPos + Vector3.new(0, 1.5, 2), false, 4) then
            return false
        end
        waitServerSettleNear(catPos, 8, 1.5)

        -- Model yang diregistrasi WildlifeSystem.Cats bisa catModel ("Cat") atau parent-nya
        Network:FireServer("WildlifeSystem", "PetCat", catModel)
        if catModel.Parent and catModel.Parent.Name == "Solmar Rooftop Cat" then
            task.wait(0.2)
            if not isQuestCompleted("The Runaway Cat") then
                Network:FireServer("WildlifeSystem", "PetCat", catModel.Parent)
            end
        end

        local w0 = os.clock()
        while (os.clock() - w0) < 5.0 do
            if not isActive("SideQuest") then return false end
            if isQuestCompleted("The Runaway Cat") then return true end
            task.wait(0.15)
        end

        if not abandonedOnce and not isQuestCompleted("The Runaway Cat") then
            if tryAbandonTreasureHuntForSideQuest() then
                abandonedOnce = true
            end
        end
    end

    return isQuestCompleted("The Runaway Cat")
end

-- Handler khusus: The Great Show (DodgeMinigame — auto-dodge 60/60 tepat di hit window)
local function runGreatShowDodge()
    if not isObjectiveActive("Dodge_Tomatoes_SQ") then return true end
    SQStats.CurrentObjective = "Dodge_Tomatoes_SQ"
    setSQStatus("Memulai Dodge Minigame (Bobo)...")

    local clownPos = resolveInterestPointPos("Character_Tomato Clown", Vector3.new(-7504.6, 152.0, -9453.7))
    if not navigateToPos(clownPos + Vector3.new(0, 1.5, 0), false, 8) then
        return false
    end
    waitServerSettleNear(clownPos, 12, 1.8)

    local function findDodgeUpvalues(dmModule)
        if type(debug) ~= "table" or type(debug.getupvalues) ~= "function" or not dmModule or type(dmModule.Start) ~= "function" then
            return nil, nil, nil
        end
        local handlePress = nil
        local okU, ups = pcall(debug.getupvalues, dmModule.Start)
        if okU and type(ups) == "table" then
            for _, v in pairs(ups) do
                if type(v) == "function" then
                    local okN, fnName = pcall(function()
                        return debug.info and debug.info(v, "n") or nil
                    end)
                    if okN and fnName == "HandlePress" then
                        handlePress = v
                        break
                    end
                end
            end
        end
        if not handlePress then
            return nil, nil, nil
        end
        local notesTbl, startClock = nil, nil
        local okH, hUps = pcall(debug.getupvalues, handlePress)
        if okH and type(hUps) == "table" then
            local now = os.clock()
            for _, v in pairs(hUps) do
                if type(v) == "table" and #v >= 5 and type(v[1]) == "table" and v[1].Arrival ~= nil then
                    notesTbl = v
                elseif type(v) == "number" and v > 0 and math.abs(now - v) < 120 then
                    startClock = v
                end
            end
        end
        return handlePress, notesTbl, startClock
    end

    for attempt = 1, 2 do
        if not isActive("SideQuest") then return false end
        if not isObjectiveActive("Dodge_Tomatoes_SQ") then return true end

        -- Pastikan tidak ada sesi Dodge lama yang menggantung
        if MinigamesClient and MinigamesClient.Active and MinigamesClient.Active.Name == "Dodge" then
            pcall(function() MinigamesClient:StopActive({ reason = "RESTART" }) end)
            task.wait(0.3)
        end

        Network:FireServer("Elysium_Converse", "TomatoClown", "StartShow")

        local sessionId = nil
        local dmModule = nil
        local w0 = os.clock()
        while (os.clock() - w0) < 6.0 do
            if not isActive("SideQuest") then return false end
            if not isObjectiveActive("Dodge_Tomatoes_SQ") then return true end
            if MinigamesClient and MinigamesClient.Active and MinigamesClient.Active.Name == "Dodge" and MinigamesClient.Active.Id then
                sessionId = MinigamesClient.Active.Id
                dmModule = MinigamesClient.Active.Module
                break
            end
            task.wait(0.08)
        end

        if sessionId and dmModule then
            setSQStatus("Auto-Dodge Tomatoes (Bobo)...")
            local runStart = os.clock()
            local dodgedClicks = 0
            local lastRefresh = 0
            local handlePress, notesTbl, startClock = findDodgeUpvalues(dmModule)

            -- Mainkan seluruh jadwal note secara presisi agar server menerima End dengan durasi & skor resmi
            while isActive("SideQuest")
                and isObjectiveActive("Dodge_Tomatoes_SQ")
                and (os.clock() - runStart) < 75
            do
                local activeNow = MinigamesClient and MinigamesClient.Active
                if not activeNow or activeNow.Name ~= "Dodge" or activeNow.Id ~= sessionId then
                    break
                end

                if (not handlePress or not notesTbl or not startClock) and (os.clock() - lastRefresh) >= 0.25 then
                    lastRefresh = os.clock()
                    handlePress, notesTbl, startClock = findDodgeUpvalues(dmModule)
                end

                if handlePress and notesTbl and startClock then
                    local elapsed = os.clock() - startClock
                    for _, note in ipairs(notesTbl) do
                        if note.Spawned and not note.Resolved and note.Arrival then
                            local diff = math.abs(elapsed - note.Arrival)
                            if diff <= 0.14 then
                                local key = note.Key or note.Side
                                if key then
                                    pcall(handlePress, key)
                                    dodgedClicks = dodgedClicks + 1
                                end
                            end
                        end
                    end
                    if dodgedClicks > 0 and dodgedClicks % 15 == 0 then
                        setSQStatus(("Auto-Dodge Tomatoes (%d/%d)..."):format(math.min(dodgedClicks, #notesTbl), #notesTbl))
                    end
                end

                task.wait(0.02)
            end

            -- Beri waktu singkat setelah FinishSequence agar server memproses End & update objective
            local e0 = os.clock()
            while (os.clock() - e0) < 8.0 do
                if not isActive("SideQuest") then return false end
                if not isObjectiveActive("Dodge_Tomatoes_SQ") then
                    return true
                end
                task.wait(0.15)
            end
        end
    end

    return not isObjectiveActive("Dodge_Tomatoes_SQ")
end

-- Handler khusus: The Phantom Tablet (TempleRun / Soru)
local function runPhantomTabletQuest()
    local qName = "The Phantom Tablet"
    if isQuestCompleted(qName) then return true end

    local monkPos = resolveInterestPointPos("Character_Mysterious Monk", Vector3.new(-7249.0, 81.3, 10952.5))
    if not isQuestActive(qName) then
        SQStats.CurrentObjective = "Accept (Mysterious Monk)"
        setSQStatus("Mengambil The Phantom Tablet...")
        if not runConverseAction("MysteriousMonk", "Accept", "Character_Mysterious Monk", monkPos, function()
            return isQuestActive(qName) or isQuestCompleted(qName)
        end, true) then
            return false
        end
    end

    -- Stage 1: Pull 3 Levers
    local leverFallbacks = {
        Vector3.new(-6978.7, 82.9, 10950.4),
        Vector3.new(-7879.6, 81.8, 10965.3),
        Vector3.new(-6792.7, 139.4, 11758.9),
    }
    for i = 1, 3 do
        local objId = "Pull_PhantomLever_SQ_" .. tostring(i)
        if isObjectiveActive(objId) then
            SQStats.CurrentObjective = objId
            setSQStatus(("Menarik Phantom Lever %d/3..."):format(i))
            local lPos = resolveObjectiveDynamicPos(qName, objId, leverFallbacks[i])
            if not navigateToPos(lPos + Vector3.new(0, 1.5, 0), false, 4) then return false end
            waitServerSettleNear(lPos, 10, 1.8)
            for attempt = 1, 3 do
                if not isActive("SideQuest") then return false end
                if not isObjectiveActive(objId) then break end
                Network:FireServer("MinigamesService", "TempleRun", { GameAction = "Pull", Index = i })
                local w0 = os.clock()
                while (os.clock() - w0) < 2.5 do
                    if not isActive("SideQuest") then return false end
                    if not isObjectiveActive(objId) then break end
                    task.wait(0.1)
                end
                if attempt < 3 and isObjectiveActive(objId) then
                    tweenSegment(lPos + Vector3.new(0, 1.5, 0), Config.TweenSpeed, 3)
                end
            end
            if isObjectiveActive(objId) then return false end
        end
    end

    -- Stage 2: Talk to Mysterious Monk
    if isObjectiveActive("Talk_MysteriousMonk_SQ") then
        SQStats.CurrentObjective = "Talk_MysteriousMonk_SQ"
        setSQStatus("Bicara kembali ke Mysterious Monk...")
        if not runConverseAction("MysteriousMonk", "Talk", "Character_Mysterious Monk", monkPos, function()
            return not isObjectiveActive("Talk_MysteriousMonk_SQ")
        end, false) then
            return false
        end
    end

    -- Stage 3: Enter Phantom Ruins
    if isObjectiveActive("Enter_PhantomRuins_SQ") or (
        (isObjectiveActive("Take_PhantomTablet_SQ") or isObjectiveActive("Investigate_PhantomRuins_SQ") or isObjectiveActive("Escape_PhantomRuins_SQ"))
        and getCurrentRealm() ~= "PhantomRuins"
    ) then
        SQStats.CurrentObjective = "Enter_PhantomRuins_SQ"
        setSQStatus("Masuk ke Phantom Ruins...")
        if not enterInteriorRealm("PhantomRuins", false) then return false end
        task.wait(0.4)
    end

    -- Stage 4: Take Phantom Tablet
    if isObjectiveActive("Take_PhantomTablet_SQ") then
        SQStats.CurrentObjective = "Take_PhantomTablet_SQ"
        setSQStatus("Mengambil Phantom Tablet...")
        local tabPos = resolveObjectiveDynamicPos(qName, "Take_PhantomTablet_SQ", Vector3.new(-8313.9, -1215.8, 12925.8))
        if not navigateToPos(tabPos + Vector3.new(0, 2, 0), false, 4) then return false end
        waitServerSettleNear(tabPos, 10, 1.8)
        for _ = 1, 3 do
            if not isActive("SideQuest") then return false end
            if not isObjectiveActive("Take_PhantomTablet_SQ") then break end
            Network:FireServer("MinigamesService", "TempleRun", { GameAction = "Take" })
            local w0 = os.clock()
            while (os.clock() - w0) < 3.0 do
                if not isActive("SideQuest") then return false end
                if not isObjectiveActive("Take_PhantomTablet_SQ") then break end
                task.wait(0.12)
            end
        end
        if isObjectiveActive("Take_PhantomTablet_SQ") then return false end
    end

    -- Stage 5: Activate Temple Run
    if isObjectiveActive("Investigate_PhantomRuins_SQ") then
        SQStats.CurrentObjective = "Investigate_PhantomRuins_SQ"
        setSQStatus("Memicu trap Temple Run...")
        local actPos = Vector3.new(-8313.9, -1212.0, 12978.0)
        if not navigateToPos(actPos, false, 4) then return false end
        waitServerSettleNear(actPos, 10, 1.5)
        for _ = 1, 3 do
            if not isActive("SideQuest") then return false end
            if not isObjectiveActive("Investigate_PhantomRuins_SQ") then break end
            Network:FireServer("MinigamesService", "TempleRun", { GameAction = "Activate" })
            local w0 = os.clock()
            while (os.clock() - w0) < 3.0 do
                if not isActive("SideQuest") then return false end
                if not isObjectiveActive("Investigate_PhantomRuins_SQ") then break end
                task.wait(0.12)
            end
        end
    end

    -- Stage 6: Escape Phantom Ruins (lari/tween aman di Y=-1206 sampai garis finish lalu End + Leave)
    if isObjectiveActive("Escape_PhantomRuins_SQ") then
        SQStats.CurrentObjective = "Escape_PhantomRuins_SQ"
        setSQStatus("Kabur dari Temple Run...")

        local runId = nil
        local w0 = os.clock()
        while (os.clock() - w0) < 4.0 do
            if MinigamesClient and MinigamesClient.Active and MinigamesClient.Active.Name == "TempleRun" then
                runId = MinigamesClient.Active.Id
                break
            end
            task.wait(0.1)
        end

        local finishPos = Vector3.new(-8313.99, -1205.0, 14335.0)
        if not tweenSegment(finishPos, math.min(Config.TweenSpeed or 400, 320), 6, false, false) then
            return false
        end
        waitServerSettleNear(finishPos, 16, 1.8)

        runId = (MinigamesClient and MinigamesClient.Active and MinigamesClient.Active.Id) or runId
        for _ = 1, 3 do
            if not isActive("SideQuest") then return false end
            if isQuestCompleted(qName) or not isObjectiveActive("Escape_PhantomRuins_SQ") then break end
            Network:FireServer("MinigamesService", "TempleRun", { GameAction = "End", id = runId })
            local e0 = os.clock()
            while (os.clock() - e0) < 3.0 do
                if not isActive("SideQuest") then return false end
                if isQuestCompleted(qName) or not isObjectiveActive("Escape_PhantomRuins_SQ") then break end
                task.wait(0.12)
            end
        end
    end

    -- Pastikan keluar dari Phantom Ruins agar karakter kembali ke permukaan
    if getCurrentRealm() == "PhantomRuins" then
        leaveCurrentInterior(false)
    end

    return isQuestCompleted(qName)
end

-- Katalog lengkap 25 One-Time / Progression Side Quests (IsRepeatable == false, Lv 5 - Lv 310)
local SIDE_QUEST_CATALOG = {
    {
        name = "The Runaway Cat",
        island = "Solmar Island",
        minLevel = 5,
        autoStart = true,
        customRunner = runRunawayCatQuest,
    },
    {
        name = "Flowers for the Dead",
        island = "Forbidden Island",
        minLevel = 15,
        start = { converse = "MourningWoman", action = "Accept", ip = "Character_Woman in Mourning", pos = Vector3.new(6578, 89, -4630) },
        steps = {
            { kind = "ZoneUse", id = "Collect_GraveFlower_SQ_Red", pos = Vector3.new(6326.8, 122.9, -5189.5), hold = 2.0 },
            { kind = "ZoneUse", id = "Collect_GraveFlower_SQ_Blue", pos = Vector3.new(5819.4, 19.4, -5190.9), hold = 2.0 },
            { kind = "ZoneUse", id = "Collect_GraveFlower_SQ_Green", pos = Vector3.new(6777.1, 23.8, -4373.6), hold = 2.0 },
            { kind = "Converse", id = "Talk_MourningWoman_SQ", converse = "MourningWoman", action = "Deliver", ip = "Character_Woman in Mourning", pos = Vector3.new(6578, 89, -4630) },
        },
    },
    {
        name = "The Great Show",
        island = "Circus Town",
        minLevel = 50,
        isMinigame = true,
        prereqNotActive = { "Circus Town 4" },
        start = { converse = "CircusRingmaster", action = "Accept", ip = "Character_Circus Ringmaster", pos = Vector3.new(-7487.4, 152.0, -9489.0) },
        steps = {
            { kind = "Custom", id = "Dodge_Tomatoes_SQ", fn = runGreatShowDodge },
            { kind = "Converse", id = "Talk_TomatoClownReward_SQ", converse = "TomatoClown", action = "Reward", ip = "Character_Tomato Clown", pos = Vector3.new(-7504.6, 152.0, -9453.7) },
        },
    },
    {
        name = "The Lost Inscriptions",
        island = "Golden Dunes",
        minLevel = 85,
        start = { converse = "CuriousMan", action = "Accept", ip = "Character_Curious Man", pos = Vector3.new(-7146.5, 42.6, 10676.0) },
        steps = {
            { kind = "ZoneUse", id = "Read_LostInscription_SQ_1", pos = Vector3.new(-5545.5, 128.7, 13299.9), hold = 2.2 },
            { kind = "ZoneUse", id = "Read_LostInscription_SQ_2", pos = Vector3.new(-6196.8, 126.8, 13450.8), hold = 2.2 },
            { kind = "ZoneUse", id = "Read_LostInscription_SQ_3", pos = Vector3.new(-5532.3, 127.7, 13708.8), hold = 2.2 },
        },
    },
    {
        name = "The Phantom Tablet",
        island = "Golden Dunes",
        minLevel = 85,
        isMinigame = true,
        customRunner = runPhantomTabletQuest,
    },
    {
        name = "The Missing Performer",
        island = "Golden Dunes",
        minLevel = 95,
        start = { converse = "WorriedBrother", action = "Accept", ip = "Character_Worried Brother", pos = Vector3.new(-6993.3, 136.2, 11048.7) },
        steps = {
            { kind = "Converse", id = "Talk_CircusJuggler_SQ", converse = "CircusJuggler", action = "Talk", ip = "Character_Circus Juggler", pos = Vector3.new(-7631.1, 151.9, -9212.9) },
            { kind = "Converse", id = "Talk_WorriedBrotherReturn_SQ", converse = "WorriedBrother", action = "Report", ip = "Character_Worried Brother", pos = Vector3.new(-6993.3, 136.2, 11048.7) },
        },
    },
    {
        name = "The Thirsty Merchant",
        island = "Golden Dunes",
        minLevel = 105,
        start = { converse = "ThirstyMerchant", action = "Accept", ip = "Character_Thirsty Merchant", pos = Vector3.new(-6895.0, 95.4, 12808.0) },
        steps = {
            { kind = "ZoneUse", id = "Fill_WaterBucket_SQ", pos = Vector3.new(-6450.0, 72.0, 12430.0), hold = 2.2 },
            { kind = "ReachZone", id = "Return_MerchantCamp_SQ", pos = Vector3.new(-6900.0, 100.0, 12800.0) },
            { kind = "ReachZone", id = "Follow_MerchantTracks_SQ", pos = Vector3.new(-6952.0, 84.0, 13045.0) },
            { kind = "Combat", ids = { "Defeat_Dune Raider", "Defeat_Dune Raider Chief" }, enemies = { "Dune Raider Chief", "Dune Raider" }, anchor = Vector3.new(-6901.0, 97.0, 13108.0), timeout = 120 },
            { kind = "Converse", id = "Talk_ThirstyMerchantWater_SQ", converse = "ThirstyMerchant", action = "GiveWater", ip = "Character_Thirsty Merchant Ambush", pos = Vector3.new(-6901.0, 84.8, 13108.0) },
        },
    },
    {
        name = "The Impossible Ice",
        island = "Frost Island",
        minLevel = 120,
        start = { converse = "FrostIceMerchant", action = "Accept", ip = "Character_Frost Ice Merchant", pos = Vector3.new(-17779.9, 26.1, 357.5) },
        steps = {
            {
                kind = "Converse",
                id = "Talk_DunesIceBuyer_SQ",
                converse = "DunesIceBuyer",
                action = "Deliver",
                ip = "Character_Dunes Ice Buyer",
                pos = Vector3.new(-8361.9, 42.6, 11714.2),
                requireItem = "Frost Ice Block",
                recoverConverse = { converse = "FrostIceMerchant", action = "Replace", ip = "Character_Frost Ice Merchant", pos = Vector3.new(-17779.9, 26.1, 357.5) },
            },
        },
    },
    {
        name = "Frozen Catch",
        island = "Frost Island",
        minLevel = 130,
        autoStart = true,
        steps = {
            { kind = "ZoneUse", id = "Break_FrozenFish_SQ_1", pos = Vector3.new(-18120.7, 97.4, -728.5), hold = 2.6, allowAbandon = true },
            { kind = "ZoneUse", id = "Break_FrozenFish_SQ_2", pos = Vector3.new(-18429.6, 160.9, -1629.9), hold = 2.6, allowAbandon = true },
            { kind = "ZoneUse", id = "Break_FrozenFish_SQ_3", pos = Vector3.new(-18667.4, 154.6, -1357.0), hold = 2.6, allowAbandon = true },
        },
    },
    {
        name = "The Snowman",
        island = "Frost Island",
        minLevel = 140,
        start = { converse = "SnowmanKid", action = "Accept", ip = "Character_Snowman Kid", pos = Vector3.new(-18384.0, 98.5, -618.0) },
        steps = {
            { kind = "ZoneUse", id = "Collect_SnowPile_SQ_1", pos = Vector3.new(-18420.0, 101.7, -598.0), hold = 2.0 },
            { kind = "ZoneUse", id = "Collect_SnowPile_SQ_2", pos = Vector3.new(-18406.0, 101.7, -664.0), hold = 2.0 },
            { kind = "ZoneUse", id = "Collect_SnowPile_SQ_3", pos = Vector3.new(-18352.0, 101.7, -680.0), hold = 2.0 },
            { kind = "ZoneUse", id = "Collect_SnowmanStick_SQ_1", pos = Vector3.new(-18346.5, 101.7, -604.0), hold = 2.0 },
            { kind = "ZoneUse", id = "Collect_SnowmanStick_SQ_2", pos = Vector3.new(-18332.0, 101.7, -687.0), hold = 2.0 },
            { kind = "ZoneUse", id = "Collect_CoalStones_SQ", pos = Vector3.new(-18310.0, 101.7, -759.0), hold = 2.0 },
            { kind = "ZoneUse", id = "Collect_Carrot_SQ", pos = Vector3.new(-18282.0, 101.7, -644.0), hold = 2.0 },
            { kind = "ZoneUse", id = "Build_Snowman_SQ", pos = Vector3.new(-18384.0, 101.7, -627.0), hold = 2.8 },
            { kind = "Converse", id = "Talk_SnowmanKid_SQ", converse = "SnowmanKid", action = "Finish", ip = "Character_Snowman Kid", pos = Vector3.new(-18384.0, 98.5, -618.0) },
        },
    },
    {
        name = "The Witch's Potion",
        island = "Forbidden Island",
        minLevel = 145,
        prereqCompleted = { "Forbidden Island 3" },
        start = { converse = "Witch", action = "AcceptPotion", ip = "Character_Witch", pos = Vector3.new(6114.5, -571.6, -4641.4) },
        steps = {
            { kind = "ZoneUse", id = "Collect_MoonFlower_SQ", pos = Vector3.new(-7636.0, 139.4, 3240.0), hold = 2.2 },
            {
                kind = "Converse",
                id = "Talk_WitchPotion_SQ",
                converse = "Witch",
                action = "DeliverMoonflower",
                ip = "Character_Witch",
                pos = Vector3.new(6114.5, -571.6, -4641.4),
                requireItem = "Moonflower",
                recoverZone = { id = "Collect_MoonFlower_SQ", pos = Vector3.new(-7636.0, 139.4, 3240.0), hold = 2.2 },
            },
        },
    },
    {
        name = "The Lost Explorer",
        island = "Skull Island",
        minLevel = 150,
        autoStart = true,
        steps = {
            { kind = "Converse", id = "Talk_LostExplorer_SQ", converse = "LostExplorer", action = "Guide", ip = "Character_Lost Explorer", pos = Vector3.new(-6390.3, 62.7, 3721.7), allowAbandon = true },
            { kind = "Converse", id = "Talk_ShipCaptain_SQ", converse = "ShipCaptain", action = "Rescue", ip = "Character_Ship Captain", pos = Vector3.new(-83.2, 23.9, 405.8) },
        },
    },
    {
        name = "Ocean Cleanup",
        island = "Shark Park",
        minLevel = 155,
        start = { converse = "GarbageCollector", action = "Accept", ip = "Character_Garbage Collector", pos = Vector3.new(864.7, 22.4, 5914.9) },
        steps = {
            { kind = "ZoneUse", id = "Collect_BeachTrash_SQ_1", pos = Vector3.new(358.2, 8.3, 6157.2), hold = 2.0 },
            { kind = "ZoneUse", id = "Collect_BeachTrash_SQ_2", pos = Vector3.new(849.5, 22.4, 5910.3), hold = 2.0 },
            { kind = "ZoneUse", id = "Collect_BeachTrash_SQ_3", pos = Vector3.new(338.0, 12.0, 6548.4), hold = 2.0 },
            { kind = "ZoneUse", id = "Collect_BeachTrash_SQ_4", pos = Vector3.new(1382.4, 12.6, 6087.8), hold = 2.0 },
            { kind = "ZoneUse", id = "Collect_BeachTrash_SQ_5", pos = Vector3.new(225.3, 10.6, 6926.0), hold = 2.0 },
            { kind = "Converse", id = "Talk_GarbageCollector_SQ", converse = "GarbageCollector", action = "Deliver", ip = "Character_Garbage Collector", pos = Vector3.new(864.7, 22.4, 5914.9) },
        },
    },
    {
        name = "Sea Delivery",
        island = "Shark Park",
        minLevel = 165,
        start = { converse = "HarborShippingMerchant", action = "Accept", ip = "Character_Harbor Shipping Merchant", pos = Vector3.new(1395.6, 20.8, 5993.0) },
        steps = {
            {
                kind = "Converse",
                id = "Talk_SolmarDockClerk_SQ",
                converse = "SolmarDockClerk",
                action = "Deliver",
                ip = "Character_Solmar Dock Clerk",
                pos = Vector3.new(-6.5, 23.5, 383.6),
                requireItem = "Sealed Shipping Crate",
                recoverConverse = { converse = "HarborShippingMerchant", action = "Replace", ip = "Character_Harbor Shipping Merchant", pos = Vector3.new(1395.6, 20.8, 5993.0) },
            },
        },
    },
    {
        name = "The Seven Seas Messenger",
        island = "Shark Park",
        minLevel = 175,
        start = { converse = "SeaPostman", action = "Accept", ip = "Character_Sea Postman", pos = Vector3.new(1198.6, 20.8, 5976.6) },
        steps = {
            { kind = "ZoneUse", id = "Post_SeaMail_SQ_Solmar", pos = Vector3.new(277.4, 18.8, 518.8), hold = 2.0 },
            { kind = "ZoneUse", id = "Post_SeaMail_SQ_Forbidden", pos = Vector3.new(5575.3, 14.5, -4547.2), hold = 2.0 },
            { kind = "ZoneUse", id = "Post_SeaMail_SQ_Circus", pos = Vector3.new(-7131.1, 21.2, -8755.6), hold = 2.0 },
            { kind = "ZoneUse", id = "Post_SeaMail_SQ_Dunes", pos = Vector3.new(-7154.5, 42.5, 10676.0), hold = 2.0 },
            { kind = "ZoneUse", id = "Post_SeaMail_SQ_Frost", pos = Vector3.new(-17732.8, 26.3, 302.5), hold = 2.0 },
        },
    },
    {
        name = "The Wheat Harvest",
        island = "Rustfall",
        minLevel = 185,
        start = { converse = "RustfallOldFarmer", action = "Accept", ip = "Character_Rustfall Old Farmer", pos = Vector3.new(6993.2, 1426.7, 8788.5) },
        steps = {
            { kind = "ZoneUse", id = "Harvest_Wheat_SQ_1", pos = Vector3.new(6925.3, 1430.3, 8889.9), hold = 2.0 },
            { kind = "ZoneUse", id = "Harvest_Wheat_SQ_2", pos = Vector3.new(6929.5, 1429.4, 8879.2), hold = 2.0 },
            { kind = "ZoneUse", id = "Harvest_Wheat_SQ_3", pos = Vector3.new(6933.5, 1429.4, 8886.4), hold = 2.0 },
            { kind = "ZoneUse", id = "Harvest_Wheat_SQ_4", pos = Vector3.new(6938.8, 1430.3, 8875.1), hold = 2.0 },
            { kind = "ZoneUse", id = "Harvest_Wheat_SQ_5", pos = Vector3.new(6942.9, 1428.8, 8891.0), hold = 2.0 },
            { kind = "ZoneUse", id = "Harvest_Wheat_SQ_6", pos = Vector3.new(6943.6, 1431.5, 8871.1), hold = 2.0 },
            { kind = "Converse", id = "Talk_OldFarmerDeliver_SQ", converse = "RustfallOldFarmer", action = "Deliver", ip = "Character_Rustfall Old Farmer", pos = Vector3.new(6993.2, 1426.7, 8788.5) },
        },
    },
    {
        name = "The Broken Mill",
        island = "Rustfall",
        minLevel = 200,
        autoStart = true,
        steps = {
            { kind = "ZoneUse", id = "Collect_MillGear_SQ_1", pos = Vector3.new(6955.7, 1516.5, 8737.1), hold = 2.2, allowAbandon = true },
            { kind = "ZoneUse", id = "Collect_MillGear_SQ_2", pos = Vector3.new(6991.6, 1428.2, 8920.8), hold = 2.2, allowAbandon = true },
            { kind = "ZoneUse", id = "Connect_MillTank_SQ", pos = Vector3.new(7147.2, 1429.1, 8912.5), hold = 2.2, allowAbandon = true },
            { kind = "ZoneUse", id = "Pull_MillLever_SQ", pos = Vector3.new(7147.1, 1429.2, 8901.6), hold = 1.8 },
        },
    },
    {
        name = "The Lost Key",
        island = "Prison",
        minLevel = 235,
        autoStart = true,
        steps = {
            { kind = "ZoneUse", id = "Collect_LostKey_SQ", pos = Vector3.new(10720.1, 164.6, 847.1), hold = 2.0, allowAbandon = true },
            {
                kind = "Converse",
                id = "Talk_PrisonKeymaster_SQ",
                converse = "PrisonKeymaster",
                action = "Return",
                ip = "Character_Prison Keymaster",
                pos = Vector3.new(10688.4, 30.5, 1006.0),
                requireItem = "Lost Cell Key",
                recoverConverse = { converse = "PrisonKeymaster", action = "Lost", ip = "Character_Prison Keymaster", pos = Vector3.new(10688.4, 30.5, 1006.0) },
                recoverZone = { id = "Collect_LostKey_SQ", pos = Vector3.new(10720.1, 164.6, 847.1), hold = 2.0 },
            },
        },
    },
    {
        name = "The Prisoner's Letter",
        island = "Prison",
        minLevel = 245,
        start = { converse = "ShackledPrisoner", action = "Accept", ip = "Character_Shackled Prisoner", pos = Vector3.new(11939.0, -1346.1, 1096.7) },
        steps = {
            {
                kind = "Converse",
                id = "Talk_PrisonerSister_SQ",
                converse = "PrisonerSister",
                action = "Deliver",
                ip = "Character_Prisoner's Sister",
                pos = Vector3.new(-94.0, 23.9, 494.1),
                requireItem = "Prisoner's Letter",
                recoverConverse = { converse = "ShackledPrisoner", action = "Replace", ip = "Character_Shackled Prisoner", pos = Vector3.new(11939.0, -1346.1, 1096.7) },
            },
            {
                kind = "Converse",
                id = "Talk_ShackledPrisonerReply_SQ",
                converse = "ShackledPrisoner",
                action = "Deliver",
                ip = "Character_Shackled Prisoner",
                pos = Vector3.new(11939.0, -1346.1, 1096.7),
                requireItem = "Sister's Reply",
                recoverConverse = { converse = "PrisonerSister", action = "Rewrite", ip = "Character_Prisoner's Sister", pos = Vector3.new(-94.0, 23.9, 494.1) },
            },
        },
    },
    {
        name = "The Contraband",
        island = "Prison",
        minLevel = 260,
        prereqCompleted = { "Prison Island 3" },
        start = { converse = "CargoPorter", action = "Accept", ip = "Character_Cargo Porter Prisoner", pos = Vector3.new(11818.0, -1346.1, 1170.0) },
        steps = {
            { kind = "ZoneUse", id = "Collect_ConfiscatedParcel_SQ", pos = Vector3.new(11784.0, -1459.1, 1013.0), hold = 2.2 },
            {
                kind = "Converse",
                id = "Talk_ContrabandPrisoner_SQ",
                converse = "CargoPorter",
                action = "Deliver",
                ip = "Character_Cargo Porter Prisoner",
                pos = Vector3.new(11818.0, -1346.1, 1170.0),
                requireItem = "Confiscated Parcel",
                recoverConverse = { converse = "CargoPorter", action = "Lost", ip = "Character_Cargo Porter Prisoner", pos = Vector3.new(11818.0, -1346.1, 1170.0) },
                recoverZone = { id = "Collect_ConfiscatedParcel_SQ", pos = Vector3.new(11784.0, -1459.1, 1013.0), hold = 2.2 },
            },
        },
    },
    {
        name = "The Champion's Armor",
        island = "Valoria Island",
        minLevel = 270,
        start = { converse = "ValoriaBlacksmith", action = "AcceptArmor", ip = "Character_Valoria Island Blacksmith", pos = Vector3.new(330.7, 120.4, -8653.6) },
        steps = {
            { kind = "ZoneUse", id = "Collect_ChampionArmor_SQ_1", pos = Vector3.new(963.5, 118.9, -8496.0), hold = 2.0 },
            { kind = "ZoneUse", id = "Collect_ChampionArmor_SQ_2", pos = Vector3.new(917.0, 233.7, -8576.0), hold = 2.0 },
            { kind = "ZoneUse", id = "Collect_ChampionArmor_SQ_3", pos = Vector3.new(280.0, 118.5, -8616.0), hold = 2.0 },
            { kind = "Converse", id = "Talk_ValoriaBlacksmithDeliver_SQ", converse = "ValoriaBlacksmith", action = "DeliverArmor", ip = "Character_Valoria Island Blacksmith", pos = Vector3.new(330.7, 120.4, -8653.6) },
        },
    },
    {
        name = "The Rookie Gladiator",
        island = "Valoria Island",
        minLevel = 280,
        start = { converse = "RookieGladiator", action = "Accept", ip = "Character_Rookie Gladiator", pos = Vector3.new(322.0, 116.5, -8612.0) },
        steps = {
            { kind = "Combat", ids = { "Defeat_Coliseum Training Dummy" }, enemies = { "Coliseum Training Dummy" }, anchor = Vector3.new(322.0, 116.5, -8612.0), timeout = 90 },
            { kind = "Converse", id = "Talk_RookieGladiatorReady_SQ", converse = "RookieGladiator", action = "Ready", ip = "Character_Rookie Gladiator", pos = Vector3.new(322.0, 116.5, -8612.0) },
            { kind = "Combat", ids = { "Defeat_Lucan the Rookie" }, enemies = { "Lucan the Rookie" }, anchor = Vector3.new(322.0, 116.5, -8612.0), timeout = 110 },
            { kind = "Converse", id = "Talk_RookieGladiatorThanks_SQ", converse = "RookieGladiator", action = "Thanks", ip = "Character_Rookie Gladiator", pos = Vector3.new(322.0, 116.5, -8612.0) },
        },
    },
    {
        name = "Message to the Skies",
        island = "Rustfall",
        minLevel = 290,
        start = { converse = "RustfallMessenger", action = "Accept", ip = "Character_Rustfall Messenger", pos = Vector3.new(7004.6, 1441.0, 9503.5) },
        steps = {
            {
                kind = "Converse",
                id = "Talk_SkyPalaceGuardian_SQ",
                converse = "SkyPalaceGuardian",
                action = "Deliver",
                ip = "Character_Sky Palace Guardian",
                pos = Vector3.new(8033.0, 3819.4, 9083.0),
                requireItem = "Sealed Sky Scroll",
                recoverConverse = { converse = "RustfallMessenger", action = "Replace", ip = "Character_Rustfall Messenger", pos = Vector3.new(7004.6, 1441.0, 9503.5) },
            },
        },
    },
    {
        name = "Celestial Feathers",
        island = "Windhaven",
        minLevel = 300,
        start = { converse = "WindhavenScholar", action = "Accept", ip = "Character_Windhaven Scholar", pos = Vector3.new(6483.3, 3423.5, 10195.2) },
        steps = {
            { kind = "ZoneUse", id = "Collect_CelestialFeather_SQ_1", pos = Vector3.new(6739.7, 3637.8, 9943.0), hold = 2.0 },
            { kind = "ZoneUse", id = "Collect_CelestialFeather_SQ_2", pos = Vector3.new(7288.1, 3717.6, 10229.4), hold = 2.0 },
            { kind = "ZoneUse", id = "Collect_CelestialFeather_SQ_3", pos = Vector3.new(7249.9, 3480.4, 9603.2), hold = 2.0 },
            { kind = "ZoneUse", id = "Collect_CelestialFeather_SQ_4", pos = Vector3.new(8045.2, 3818.9, 9096.2), hold = 2.0 },
            { kind = "ZoneUse", id = "Collect_CelestialFeather_SQ_5", pos = Vector3.new(8075.4, 3673.7, 10197.6), hold = 2.0 },
            { kind = "Converse", id = "Talk_WindhavenScholarDeliver_SQ", converse = "WindhavenScholar", action = "Deliver", ip = "Character_Windhaven Scholar", pos = Vector3.new(6483.3, 3423.5, 10195.2) },
        },
    },
    {
        name = "The Hidden Clock",
        island = "Windhaven",
        minLevel = 310,
        autoStart = true,
        steps = {
            { kind = "ZoneUse", id = "Pull_ClockLever_SQ", pos = Vector3.new(6724.4, 3612.6, 9953.6), hold = 2.2, allowAbandon = true },
            { kind = "ZoneUse", id = "Take_ClockStash_SQ", pos = Vector3.new(6734.5, 3612.6, 9963.8), hold = 2.6 },
        },
    },
}

local function listSideQuestIslands()
    local list = { "All Islands" }
    local seen = {}
    for _, q in ipairs(SIDE_QUEST_CATALOG) do
        if not seen[q.island] then
            seen[q.island] = true
            table.insert(list, q.island)
        end
    end
    return list
end

local function listSideQuestTargetNames()
    local list = { "Auto (All Eligible)" }
    for _, q in ipairs(SIDE_QUEST_CATALOG) do
        table.insert(list, q.name)
    end
    return list
end

local function isSideQuestSkipped(questName)
    local sk = SQStats.SkippedQuests[questName]
    if not sk then return false end
    if os.clock() >= sk.untilTime then
        SQStats.SkippedQuests[questName] = nil
        return false
    end
    return true
end

local function markSideQuestSkipped(questName, reason, durationSec)
    SQStats.SkippedQuests[questName] = {
        untilTime = os.clock() + (durationSec or 180),
        reason = tostring(reason or "Failed"),
    }
    logEvent("SQ SKIP: " .. questName .. " (" .. tostring(reason) .. ")")
end

local function isSideQuestEligible(def, ignoreFilter)
    if isQuestCompleted(def.name) then return false, "Completed" end
    if not Config.SideQuestIncludeMinigames and def.isMinigame then
        return false, "MinigameDisabled"
    end
    local qInfo = QuestsInfo and QuestsInfo[def.name]
    local reqLvl = (qInfo and qInfo.MinLevel) or def.minLevel or 1
    if getPlayerLevel() < reqLvl then
        return false, "Level<" .. tostring(reqLvl)
    end
    if def.prereqCompleted then
        for _, reqQ in ipairs(def.prereqCompleted) do
            if not isQuestCompleted(reqQ) then
                return false, "Prereq:" .. reqQ
            end
        end
    end
    if def.prereqNotActive then
        for _, blkQ in ipairs(def.prereqNotActive) do
            if isQuestActive(blkQ) then
                return false, "BlockedBy:" .. blkQ
            end
        end
    end
    if not ignoreFilter then
        if Config.SideQuestTarget and Config.SideQuestTarget ~= "Auto (All Eligible)" and Config.SideQuestTarget ~= "Auto Semua Eligible" then
            if def.name ~= Config.SideQuestTarget then
                return false, "TargetFilter"
            end
        elseif Config.SideQuestIsland and Config.SideQuestIsland ~= "All Islands" and Config.SideQuestIsland ~= "Semua Pulau" then
            if def.island ~= Config.SideQuestIsland then
                return false, "IslandFilter"
            end
        end
    end
    return true, "Eligible"
end

SQ.GetOverview = function()
    local total = #SIDE_QUEST_CATALOG
    local completed = 0
    local eligible = {}
    local skipped = 0
    for _, def in ipairs(SIDE_QUEST_CATALOG) do
        if isQuestCompleted(def.name) then
            completed = completed + 1
        elseif isSideQuestSkipped(def.name) then
            skipped = skipped + 1
        elseif isSideQuestEligible(def, false) then
            table.insert(eligible, def.name)
        end
    end
    local preview = {}
    for i = 1, math.min(4, #eligible) do
        table.insert(preview, eligible[i])
    end
    local previewText = #preview > 0 and table.concat(preview, ", ") .. (#eligible > 4 and (" (+" .. tostring(#eligible - 4) .. ")") or "") or "Tidak ada / Semua selesai"
    return {
        total = total,
        completed = completed,
        eligibleCount = #eligible,
        skipped = skipped,
        previewText = previewText,
    }
end

SQ.ListIslands = listSideQuestIslands
SQ.ListTargets = listSideQuestTargetNames

local function pickNextSideQuest()
    local activeCandidate = nil
    local freshCandidate = nil
    for _, def in ipairs(SIDE_QUEST_CATALOG) do
        if not isSideQuestSkipped(def.name) and isSideQuestEligible(def, false) then
            if isQuestActive(def.name) then
                if not activeCandidate then
                    activeCandidate = def
                end
            elseif not freshCandidate then
                freshCandidate = def
            end
        end
    end
    return activeCandidate or freshCandidate
end

local function executeSideQuest(def)
    local qName = def.name
    SQStats.CurrentQuest = qName .. " (" .. def.island .. ")"
    SQStats.CurrentObjective = "Memulai..."
    local goldBefore = getGold()

    if def.customRunner then
        local okRun = def.customRunner()
        if okRun and isQuestCompleted(qName) then
            local gained = math.max(0, getGold() - goldBefore)
            SQStats.SessionCompleted = SQStats.SessionCompleted + 1
            SQStats.SessionGoldEarned = SQStats.SessionGoldEarned + gained
            table.insert(SQStats.CompletedList, qName)
            logEvent(("SQ DONE: %s (+%dG)"):format(qName, gained))
            notifyInfo("Side Quest Done", ("%s (%s)\n+%s G"):format(qName, def.island, formatNumber(gained)), 4)
            if WH.NotifySideQuest then
                WH.NotifySideQuest(qName, def.island, gained)
            end
            return true
        end
        return false
    end

    -- 1. Accept jika bukan autoStart dan belum aktif
    if not def.autoStart and def.start and not isQuestActive(qName) then
        SQStats.CurrentObjective = "Accept (" .. def.start.converse .. ")"
        setSQStatus("Mengambil Side Quest: " .. qName)
        local okAccept = runConverseAction(
            def.start.converse,
            def.start.action,
            def.start.ip,
            def.start.pos,
            function()
                return isQuestActive(qName) or isQuestCompleted(qName)
            end,
            true
        )
        if not okAccept then
            return false
        end
        task.wait(0.25)
    end

    -- 2. Eksekusi setiap step secara berurutan (otomatis melewati step yang sudah selesai)
    for _, step in ipairs(def.steps or {}) do
        if not isActive("SideQuest") then return false end
        if isQuestCompleted(qName) then break end

        if step.kind == "ZoneUse" then
            if not isObjectiveDoneForQuest(qName, step.id) then
                SQStats.CurrentObjective = step.id
                setSQStatus(("SQ %s -> %s"):format(qName, step.id))
                if not runQuestZoneObjective(qName, step.id, step.pos, step.hold, step.allowAbandon == true) then
                    return false
                end
            end
        elseif step.kind == "ReachZone" then
            if not isObjectiveDoneForQuest(qName, step.id) then
                SQStats.CurrentObjective = step.id
                setSQStatus(("SQ %s -> menuju zona %s"):format(qName, step.id))
                if not runReachZoneObjective(qName, step.id, step.pos) then
                    return false
                end
            end
        elseif step.kind == "Combat" then
            local needFight = false
            for _, cid in ipairs(step.ids) do
                if isObjectiveActive(cid) then
                    needFight = true
                    break
                end
            end
            if needFight then
                SQStats.CurrentObjective = table.concat(step.enemies, ", ")
                setSQStatus(("SQ %s -> lawan %s"):format(qName, SQStats.CurrentObjective))
                if not runCombatObjective(qName, step.ids, step.enemies, step.anchor, step.timeout) then
                    return false
                end
            end
        elseif step.kind == "Converse" then
            if not isObjectiveDoneForQuest(qName, step.id) then
                -- Recovery otomatis jika item pengiriman hilang dari inventory
                if step.requireItem and getOwnedToolAmount(step.requireItem) < 1 then
                    setSQStatus(("Item '%s' hilang -> mengambil ulang..."):format(step.requireItem))
                    if step.recoverConverse then
                        runConverseAction(
                            step.recoverConverse.converse,
                            step.recoverConverse.action,
                            step.recoverConverse.ip,
                            step.recoverConverse.pos,
                            function()
                                return getOwnedToolAmount(step.requireItem) >= 1 or step.recoverZone ~= nil
                            end,
                            false
                        )
                    end
                    if step.recoverZone and getOwnedToolAmount(step.requireItem) < 1 then
                        runQuestZoneObjective(qName, step.recoverZone.id, step.recoverZone.pos, step.recoverZone.hold, false)
                    end
                end

                SQStats.CurrentObjective = step.id
                setSQStatus(("SQ %s -> bicara %s"):format(qName, step.converse))
                local okTalk = runConverseAction(
                    step.converse,
                    step.action,
                    step.ip,
                    step.pos,
                    function()
                        return isObjectiveDoneForQuest(qName, step.id)
                    end,
                    step.allowAbandon == true
                )
                if not okTalk then
                    return false
                end
            end
        elseif step.kind == "Custom" then
            if not isObjectiveDoneForQuest(qName, step.id) then
                SQStats.CurrentObjective = step.id
                if not step.fn() then
                    return false
                end
            end
        end

        task.wait(0.2)
    end

    -- Tunggu sebentar sinkronisasi completion DataStore
    local c0 = os.clock()
    while not isQuestCompleted(qName) and (os.clock() - c0) < 2.5 do
        if not isActive("SideQuest") then return false end
        task.wait(0.15)
    end

    if isQuestCompleted(qName) then
        local gained = math.max(0, getGold() - goldBefore)
        SQStats.SessionCompleted = SQStats.SessionCompleted + 1
        SQStats.SessionGoldEarned = SQStats.SessionGoldEarned + gained
        table.insert(SQStats.CompletedList, qName)
        logEvent(("SQ DONE: %s (+%dG)"):format(qName, gained))
        notifyInfo("Side Quest Done", ("%s (%s)\n+%s G"):format(qName, def.island, formatNumber(gained)), 4)
        if WH.NotifySideQuest then
            WH.NotifySideQuest(qName, def.island, gained)
        end
        return true
    end

    return false
end

SQ.Step = function()
    local nextQuest = pickNextSideQuest()
    if not nextQuest then
        SQStats.CurrentQuest = "-"
        SQStats.CurrentObjective = "-"
        setSQStatus("Semua One-Time Side Quest eligible selesai!")
        notifyInfo("Auto Side Quest", "Semua One-Time Side Quest yang memenuhi syarat sudah selesai!", 5)
        setActiveMode("None")
        return
    end

    local ok = executeSideQuest(nextQuest)
    if not ok and isActive("SideQuest") then
        markSideQuestSkipped(nextQuest.name, "Gagal/Timeout di " .. tostring(SQStats.CurrentObjective), 180)
        setSQStatus("Skip sementara: " .. nextQuest.name)
        task.wait(0.5)
    else
        task.wait(Config.LoopDelay)
    end
end
end -- end Auto Side Quest scope

-- ============================================================================
-- AUTO FARM LEVEL ENGINE (GRINDING QUESTS LV 1 - 500 + INSTANT REPEAT + HAKI/SKILL/STATS)
-- ============================================================================
do
local BalancingFeatures = MainModules.BalancingFeatures
local SkillUtils = MainModules.SkillUtils
local PowersLock = MainModules.PowersLock
local SkillsRegistry = nil
local RepeatQuestMod = nil
local PlayerStates = nil
local VirtualInputManager = nil

pcall(function()
    SkillsRegistry = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Skills"))
end)
pcall(function()
    RepeatQuestMod = require(
        ReplicatedStorage:WaitForChild("Modules")
            :WaitForChild("Essentials")
            :WaitForChild("QuestSystem")
            :WaitForChild("QuestSystem Client")
            :WaitForChild("RepeatQuest")
    )
end)
pcall(function()
    PlayerStates = ElysiumModules.States.Player()
end)
pcall(function()
    VirtualInputManager = game:GetService("VirtualInputManager")
end)
restoreExecutorContext()

local function getPlayerLevelAndXP()
    local ds = getDataStore()
    local st = ds and ds.Statistics
    local lvl = (st and tonumber(st.Level)) or 1
    local xp = (st and tonumber(st.XP)) or 0
    local maxLvl = (BalancingFeatures and tonumber(BalancingFeatures.MaxLevel)) or 500
    local maxXp = 1
    if BalancingFeatures and BalancingFeatures.GetStatisticsMaxXP then
        local ok, v = pcall(BalancingFeatures.GetStatisticsMaxXP, BalancingFeatures, nil, lvl)
        if ok and tonumber(v) and tonumber(v) > 0 then
            maxXp = tonumber(v)
        end
    end
    return lvl, xp, maxXp, maxLvl
end

local function estimateCumulativeXP(lvl, xp)
    if not BalancingFeatures or not BalancingFeatures.GetStatisticsMaxXP then
        return xp
    end
    local total = xp or 0
    for i = 1, math.max(0, (lvl or 1) - 1) do
        local ok, v = pcall(BalancingFeatures.GetStatisticsMaxXP, BalancingFeatures, nil, i)
        if ok and tonumber(v) then
            total = total + tonumber(v)
        end
    end
    return total
end

local initLvl, initXp = getPlayerLevelAndXP()
local LFStats = {
    StartTime = os.clock(),
    StartLevel = initLvl,
    StartCumXP = estimateCumulativeXP(initLvl, initXp),
    QuestsCompleted = 0,
    RepeatUses = 0,
    SkillsCast = 0,
    AbandonedTH = 0,
    StatsSpent = 0,
    CurrentQuest = "-",
    CurrentObjective = "-",
    LastStatus = "Idle",
}
LF.Stats = LFStats
getgenv()._VoxSeasLFStats = LFStats

function LF.SetStatus(text)
    restoreExecutorContext()
    LFStats.LastStatus = tostring(text)
    Stats.LastStatus = "[LF] " .. LFStats.LastStatus
    if LF.UI and LF.UI.StatusLabel then
        pcall(function()
            restoreExecutorContext()
            LF.UI.StatusLabel:SetText("Status: " .. LFStats.LastStatus)
        end)
    end
    if StatusLabel then
        pcall(function()
            restoreExecutorContext()
            StatusLabel:SetText("Status: " .. Stats.LastStatus)
        end)
    elseif FallbackStatusLabel then
        pcall(function()
            FallbackStatusLabel.Text = "Status: " .. Stats.LastStatus
        end)
    end
    updateBlackScreenText()
    updateStatsUI()
end

local function extractPositionAny(v)
    if typeof(v) == "Vector3" then return v end
    if typeof(v) == "CFrame" then return v.Position end
    if typeof(v) == "Instance" then
        if v:IsA("BasePart") then return v.Position end
        if v:IsA("Model") then return v:GetPivot().Position end
        if v:IsA("Vector3Value") then return v.Value end
        if v:IsA("CFrameValue") then return v.Value.Position end
    end
    if type(v) == "table" then
        if typeof(v.Position) == "Vector3" then return v.Position end
        if typeof(v.CFrame) == "CFrame" then return v.CFrame.Position end
    end
    return nil
end

local grindingCatalogCache = nil
local function getGrindingCatalog()
    if grindingCatalogCache then
        return grindingCatalogCache
    end
    local list = {}
    for qName, qData in pairs(QuestsInfo or {}) do
        if type(qData) == "table" and (qData.GrindingQuest == true or (type(qData.Arguments) == "table" and qData.Arguments.Type == "GrindingQuest")) then
            local args = qData.Arguments or {}
            local giver = tostring(args.Giver or "")
            local island = giver:gsub("%s*Quest Giver$", "")
            if island == "" then island = "Unknown" end
            local objs = {}
            local sub1 = type(qData.SubQuests) == "table" and qData.SubQuests[1]
            if type(sub1) == "table" and type(sub1.Objectives) == "table" then
                for idx, o in ipairs(sub1.Objectives) do
                    local oid = tostring(o.ObjectiveID or "")
                    local enemyName = oid:gsub("^Defeat_", "")
                    table.insert(objs, {
                        index = idx,
                        id = oid,
                        enemyName = enemyName,
                        goal = tonumber(o.Goal) or 1,
                        rawObj = o,
                    })
                end
            end
            local minLvl = tonumber(qData.MinLevel) or 1
            local maxLvl = tonumber(args.MaxLevel) or minLvl
            local xpReward = tonumber(qData.Rewards and qData.Rewards.Experience) or 0
            local goldReward = tonumber(qData.Rewards and qData.Rewards.Gold) or 0
            local display = tostring(qData.DisplayName or qData.Title or qName)
            local label = string.format("[Lv %d-%d] %s (%s)%s", minLvl, maxLvl, display, island, args.IsBoss and " [BOSS]" or "")
            table.insert(list, {
                name = tostring(qName),
                display = display,
                label = label,
                minLvl = minLvl,
                maxLvl = maxLvl,
                isBoss = args.IsBoss == true,
                giver = giver,
                island = island,
                xp = xpReward,
                gold = goldReward,
                objectives = objs,
            })
        end
    end
    table.sort(list, function(a, b)
        if a.minLvl ~= b.minLvl then return a.minLvl < b.minLvl end
        return a.name < b.name
    end)
    grindingCatalogCache = list
    return list
end

function LF.ListQuests()
    local vals = { "Auto (Best XP)" }
    for _, q in ipairs(getGrindingCatalog()) do
        table.insert(vals, q.label)
    end
    return vals
end

local function isBossOnCooldown(enemyName)
    if not enemyName or enemyName == "" then return false end
    local il = workspace:FindFirstChild("IgnoreList")
    local data = il and il:FindFirstChild("Data")
    local br = data and data:FindFirstChild("BossRespawns")
    if not br then return false end
    local entry = br:FindFirstChild(enemyName)
    if not entry then return false end
    local respawnAt = entry:GetAttribute("RespawnAt")
    if type(respawnAt) == "number" and respawnAt > workspace:GetServerTimeNow() then
        return true
    end
    return false
end

local function pickTargetQuest()
    local catalog = getGrindingCatalog()
    local lvl = getPlayerLevelAndXP()
    local targetLabel = Config.LevelFarmTarget or "Auto (Best XP)"
    local mode = Config.LevelFarmMode or "Auto Best Quest"
    local isAutoTarget = (targetLabel == "Auto (Best XP)" or targetLabel == "Auto (Sesuai Level)")

    if mode == "Manual Quest" or not isAutoTarget then
        for _, q in ipairs(catalog) do
            if q.label == targetLabel or q.name == targetLabel or q.display == targetLabel then
                if mode == "No Quest (Mob Only)" or lvl >= q.minLvl then
                    return q
                end
            end
        end
    end

    -- Auto Best Quest: pilih quest terbuka dengan XP tertinggi (tiebreaker: MinLevel tertinggi)
    local best = nil
    for _, q in ipairs(catalog) do
        if lvl >= q.minLvl then
            local skipBoss = false
            if q.isBoss then
                if not Config.LevelFarmIncludeBoss then
                    skipBoss = true
                else
                    local bossEnemy = q.objectives[1] and q.objectives[1].enemyName
                    if isBossOnCooldown(bossEnemy) then
                        skipBoss = true
                    end
                end
            end
            if not skipBoss then
                if not best or q.xp > best.xp or (q.xp == best.xp and q.minLvl > best.minLvl) then
                    best = q
                end
            end
        end
    end
    return best or catalog[1]
end

local function resolveGiverPos(giverName)
    if not giverName or giverName == "" then return nil end
    local pts = InterestPoints and InterestPoints.Points
    if type(pts) == "table" then
        local direct = pts["Character_" .. giverName] or pts[giverName]
        local pos = extractPositionAny(direct)
        if pos then return pos end
    end
    local play = workspace:FindFirstChild("Playability")
    local npcs = play and play:FindFirstChild("NPCs")
    if npcs then
        local m = npcs:FindFirstChild(giverName, true)
        if m then
            local p = extractPositionAny(m)
            if p then return p end
        end
    end
    return nil
end

local function resolveEnemySpawnPos(enemyName, rawObj)
    -- 1. Cari langsung di IgnoreList.Data.EnemyGroups (termasuk group Wide=true seperti PrisonGuardsGrinding_Group)
    local il = workspace:FindFirstChild("IgnoreList")
    local data = il and il:FindFirstChild("Data")
    local eg = data and data:FindFirstChild("EnemyGroups")
    if eg and enemyName and enemyName ~= "" then
        local needle = "," .. enemyName .. ","
        local bestPos, bestScore = nil, math.huge
        local _, _, myHrp = getCharacterParts()
        local myPos = myHrp and myHrp.Position or Vector3.zero
        for _, d in ipairs(eg:GetDescendants()) do
            if d:IsA("BasePart") then
                local attr = d:GetAttribute("Enemies")
                if type(attr) == "string" and attr:find(needle, 1, true) then
                    local sub = d:FindFirstChild(enemyName)
                    local pos = (sub and sub:IsA("BasePart")) and sub.Position or d.Position
                    local dist = (pos - myPos).Magnitude
                    local score = (sub and sub:IsA("BasePart")) and dist or (dist + 50000)
                    if score < bestScore then
                        bestScore = score
                        bestPos = pos
                    end
                end
            end
        end
        if bestPos then return bestPos end
    end

    -- 2. Fallback ke Objective.InterestPoint()
    if rawObj and rawObj.InterestPoint then
        local res = nil
        if type(rawObj.InterestPoint) == "function" then
            local ok, v = pcall(rawObj.InterestPoint, LocalPlayer)
            if ok then res = v end
        else
            res = rawObj.InterestPoint
        end
        local pos = extractPositionAny(res)
        if pos then return pos end
        if type(res) == "string" and InterestPoints and InterestPoints.Points then
            local p = extractPositionAny(InterestPoints.Points[res])
            if p then return p end
        end
    end

    -- 3. Fallback ke musuh hidup saat ini di workspace.Playability.Enemys
    local play = workspace:FindFirstChild("Playability")
    local enemys = play and play:FindFirstChild("Enemys")
    if enemys then
        for _, m in ipairs(enemys:GetChildren()) do
            if m:IsA("Model") and m:GetAttribute("OriginalName") == enemyName then
                local h = m:FindFirstChild("HumanoidRootPart") or m.PrimaryPart
                if h then return h.Position end
            end
        end
    end
    return nil
end

local lastBusoTry = 0
local lastKenbTry = 0
function LF.EnsureHaki()
    if not Config.LevelFarmAutoHaki then return end
    local char = LocalPlayer.Character
    if not char then return end
    if PowersLock and PowersLock.IsLocked then
        local okL, locked = pcall(PowersLock.IsLocked, char)
        if okL and locked then return end
    end
    local ds = getDataStore()
    local ab = ds and ds.Abilitys
    if type(ab) ~= "table" then return end
    local now = os.clock()

    if (tonumber(ab.Busoshoku) or 0) > 0 and char:GetAttribute("Busoshoku") == nil and (now - lastBusoTry) >= 2.5 then
        lastBusoTry = now
        pcall(function()
            Network:FireServer("Busoshoku", "Toggle")
        end)
    end
    if (tonumber(ab.Kenbushoku) or 0) > 0
        and char:GetAttribute("Kenbushoku") == nil
        and char:GetAttribute("BreakKenbushoku") == nil
        and (now - lastKenbTry) >= 3.5
    then
        lastKenbTry = now
        pcall(function()
            Network:FireServer("Kenbushoku", "Toggle")
        end)
    end
end

local SKILL_KEYS = { "Z", "X", "C", "V" }
local StateUtils = MainModules.StateUtils
local skillHoldFn = nil
local skillReleaseFn = nil
local skillCtrlScanned = false
local lastSkillTry = 0
local skillRotateIdx = 0

local function resolveSkillHandlers()
    if skillHoldFn and skillReleaseFn then
        return true
    end
    if skillCtrlScanned then
        return false
    end
    skillCtrlScanned = true
    if type(getgc) == "function" then
        for _, fn in ipairs(getgc(false)) do
            if type(fn) == "function" then
                local okInfo, src, name = pcall(debug.info, fn, "sn")
                if okInfo and type(src) == "string" and src:sub(-19) == "SkillsSystem Client" then
                    if name == "Hold" then
                        skillHoldFn = fn
                    elseif name == "Release" then
                        skillReleaseFn = fn
                    end
                    if skillHoldFn and skillReleaseFn then
                        break
                    end
                end
            end
        end
    end
    return (skillHoldFn ~= nil and skillReleaseFn ~= nil)
end

local function findNextReadySkill()
    if not Config.LevelFarmAutoSkills then return nil, nil, nil end
    if not SkillsRegistry or not ToolsUtils then return nil, nil, nil end
    if (os.clock() - lastSkillTry) < 0.75 then return nil, nil, nil end
    if not resolveSkillHandlers() then return nil, nil, nil end

    local char = LocalPlayer.Character
    if not char then return nil, nil, nil end
    local okTool, curTool = pcall(ToolsUtils.GetCurrentTool, ToolsUtils, char)
    if not okTool or not curTool then return nil, nil, nil end

    for step = 1, #SKILL_KEYS do
        local idx = ((skillRotateIdx + step - 1) % #SKILL_KEYS) + 1
        local key = SKILL_KEYS[idx]
        local okSk, skill = pcall(SkillsRegistry.GetByKey, SkillsRegistry, curTool.Name, key)
        if okSk and type(skill) == "table" and skill.Id then
            local ready = true
            if PlayerStates and PlayerStates.IsAllInactive then
                local okSt, inact = pcall(PlayerStates.IsAllInactive, PlayerStates, {
                    skill.Id .. "_Cooldown",
                    skill.Id .. "_Holding",
                    "ArenaFrozen",
                    "JumpOnly",
                })
                if okSt and not inact then
                    ready = false
                end
            end
            if ready and SkillUtils then
                local okV, valid = pcall(SkillUtils.ValidateSkill, LocalPlayer, skill)
                local okR, reqOk = pcall(SkillUtils.UsageRequeriments, LocalPlayer, skill)
                if (okV and not valid) or (okR and not reqOk) then
                    ready = false
                end
            end
            if ready then
                return key, skill, idx
            end
        end
    end
    return nil, nil, nil
end

function LF.HasReadySkill()
    local key = findNextReadySkill()
    return key ~= nil
end

function LF.CastCombatSkill(targetModel)
    local key, skill, idx = findNextReadySkill()
    if not key or not skill then return false end

    -- Tunggu M1 state ("Client") & DefaultStates benar-benar clear agar SkillsSystem Client.Hold() selalu diterima
    if PlayerStates and PlayerStates.IsAllInactive and StateUtils and StateUtils.CombineStates then
        local combined = StateUtils.CombineStates(StateUtils.DefaultStates, {
            skill.Id .. "_Cooldown",
            "ArenaFrozen",
            "JumpOnly",
        })
        local okDef, canCast = pcall(PlayerStates.IsAllInactive, PlayerStates, combined)
        if okDef and not canCast then
            return false
        end
    end

    skillRotateIdx = idx
    lastSkillTry = os.clock()
    local holdDur = math.max(0.16, (skill.Settings and tonumber(skill.Settings.MinTime) or 0) + 0.06)
    local okHold = pcall(skillHoldFn, key)
    local actuallyHeld = okHold and PlayerStates and PlayerStates.IsActive and (
        PlayerStates:IsActive(skill.Id .. "_Holding")
        or PlayerStates:IsActive(skill.Id .. "_Cooldown")
        or PlayerStates:IsActive("Client")
    )
    if actuallyHeld then
        LFStats.SkillsCast = (LFStats.SkillsCast or 0) + 1
        task.delay(holdDur, function()
            pcall(skillReleaseFn, key)
            restoreExecutorContext()
        end)
        restoreExecutorContext()
        return true
    end
    restoreExecutorContext()
    return false
end

local lastStatUpgrade = 0
local function getAvailableStatPoints()
    if not BalancingFeatures or not BalancingFeatures.CalculateStatPoints or not BalancingFeatures.GetDistributedPoints then
        return 0
    end
    local lvl = getPlayerLevelAndXP()
    local okD, dist = pcall(BalancingFeatures.GetDistributedPoints, BalancingFeatures, LocalPlayer)
    if not okD or not tonumber(dist) then return 0 end
    local okA, avail = pcall(BalancingFeatures.CalculateStatPoints, lvl, tonumber(dist))
    if not okA or not tonumber(avail) then return 0 end
    return math.max(0, math.floor(tonumber(avail)))
end

function LF.AutoAllocateStats()
    if not Config.LevelFarmAutoStats then return end
    local now = os.clock()
    if (now - lastStatUpgrade) < 1.5 then return end

    local statName = Config.LevelFarmStatTarget or "Sword"
    local ds = getDataStore()
    local st = ds and ds.Statistics
    if not st then return end
    local _, _, _, maxLvl = getPlayerLevelAndXP()
    local curVal = tonumber(st[statName]) or 1
    local avail = getAvailableStatPoints()
    local spend = math.min(avail, math.max(0, maxLvl - curVal))
    if spend >= 1 then
        lastStatUpgrade = now
        Network:FireServer("StatisticsData", "UpgradeStats", { [statName] = spend })
        LFStats.StatsSpent = LFStats.StatsSpent + spend
        logEvent(("LF AutoStat +%d %s"):format(spend, statName))
    end
end

local function getActiveGrindingQuest()
    local ds = getDataStore()
    local actives = ds and ds.Quests and ds.Quests.Actives
    if type(actives) ~= "table" then return nil, nil end
    for qName, qProg in pairs(actives) do
        local info = QuestsInfo and QuestsInfo[qName]
        if type(info) == "table" and info.GrindingQuest == true then
            return qName, qProg
        end
    end
    return nil, nil
end

local function tryAbandonTreasureHuntForLF()
    if not Config.LevelFarmAutoAbandonTH then return false end
    local parked = getParkedFarTreasureHunts()
    if #parked > 0 then
        local victim = parked[#parked]
        LF.SetStatus("QuestLimit -> abandon parkir TH: " .. victim)
        logEvent("LF QuestLimit -> abandon parked TH: " .. victim)
        Network:FireServer("Quests", "Abandon", victim)
        LFStats.AbandonedTH = LFStats.AbandonedTH + 1
        task.wait(0.55)
        return true
    end
    local ds = getDataStore()
    local actives = ds and ds.Quests and ds.Quests.Actives
    if actives then
        for qName in pairs(actives) do
            if type(qName) == "string" and (qName:find("Treasure Hunt") or qName:find("Shipwreck")) then
                LF.SetStatus("QuestLimit -> abandon TH aktif: " .. qName)
                logEvent("LF QuestLimit -> abandon active TH: " .. qName)
                Network:FireServer("Quests", "Abandon", qName)
                LFStats.AbandonedTH = LFStats.AbandonedTH + 1
                task.wait(0.55)
                return true
            end
        end
    end
    return false
end

local function getIncompleteObjectives(qEntry, activeProg)
    local incomplete = {}
    local parts = {}
    local sub1 = type(activeProg) == "table" and activeProg[1] or {}
    for _, obj in ipairs(qEntry.objectives) do
        local cur = math.min(tonumber(sub1[obj.index]) or 0, obj.goal)
        table.insert(parts, string.format("%s %d/%d", obj.enemyName, cur, obj.goal))
        if cur < obj.goal then
            table.insert(incomplete, obj)
        end
    end
    return incomplete, table.concat(parts, ", ")
end

local function findAliveGrindingTargets(neededSet, allowUnrendered, maxRadius, skippedTargets)
    local play = workspace:FindFirstChild("Playability")
    local enemys = play and play:FindFirstChild("Enemys")
    if not enemys then return {} end
    local _, _, myHrp = getCharacterParts()
    local myPos = myHrp and myHrp.Position or nil
    local radius = maxRadius or 900
    local now = os.clock()
    local list = {}

    for _, m in ipairs(enemys:GetChildren()) do
        if m:IsA("Model")
            and not (skippedTargets and skippedTargets[m] and skippedTargets[m] > now)
            and isEnemyAlive(m, allowUnrendered)
        then
            local orig = m:GetAttribute("OriginalName")
            if type(orig) == "string" and neededSet[orig] then
                local h = m:FindFirstChild("HumanoidRootPart") or m.PrimaryPart
                if h and (not myPos or (h.Position - myPos).Magnitude <= radius) then
                    table.insert(list, m)
                end
            end
        end
    end

    if myPos and #list > 1 then
        local dists = {}
        for _, m in ipairs(list) do
            local h = m:FindFirstChild("HumanoidRootPart") or m.PrimaryPart
            dists[m] = h and (h.Position - myPos).Magnitude or 999999
        end
        table.sort(list, function(a, b) return dists[a] < dists[b] end)
    end
    return list
end

local function acceptGrindingQuest(qEntry)
    -- 1. Fast Path: Instant RepeatQuest (tanpa balik ke NPC Quest Giver!)
    if Config.LevelFarmUseRepeat and RepeatQuestMod
        and RepeatQuestMod.QuestName == qEntry.name
        and (tonumber(RepeatQuestMod.ExpiresAt) or 0) > (workspace:GetServerTimeNow() + 0.4)
    then
        LF.SetStatus("Instant Repeat: " .. qEntry.display)
        Network:FireServer("Quests", "Repeat")
        local t0 = os.clock()
        while (os.clock() - t0) < 1.8 do
            if not isActive("LevelFarm") then return false end
            local activeName = getActiveGrindingQuest()
            if activeName == qEntry.name then
                LFStats.RepeatUses = LFStats.RepeatUses + 1
                logEvent("LF Instant Repeat: " .. qEntry.name)
                return true
            end
            task.wait(0.1)
        end
    end

    -- 2. Normal Path: Terbang ke NPC Quest Giver lalu AcceptGrinding
    local giverPos = resolveGiverPos(qEntry.giver)
    if not giverPos then
        LF.SetStatus("Can't find " .. qEntry.giver)
        task.wait(1)
        return false
    end

    LF.SetStatus("Heading to " .. qEntry.island .. "...")
    if not navigateToPos(giverPos + Vector3.new(0, 1.5, 0), false, 8) then
        return false
    end
    waitServerSettleNear(giverPos, 16, 1.5)

    local abandonedOnce = false
    for attempt = 1, 3 do
        if not isActive("LevelFarm") then return false end
        local activeName = getActiveGrindingQuest()
        if activeName == qEntry.name then
            return true
        end
        LF.SetStatus("Accepting " .. qEntry.display .. "...")
        Network:FireServer("Quests", "AcceptGrinding", qEntry.name)
        local t0 = os.clock()
        while (os.clock() - t0) < 1.6 do
            if not isActive("LevelFarm") then return false end
            local cur = getActiveGrindingQuest()
            if cur == qEntry.name then
                logEvent("LF Accepted: " .. qEntry.name)
                return true
            end
            task.wait(0.1)
        end
        if not abandonedOnce and tryAbandonTreasureHuntForLF() then
            abandonedOnce = true
        elseif attempt < 3 then
            tweenSegment(giverPos + Vector3.new(0, 1.5, 0), Config.TweenSpeed, 6)
            task.wait(0.25)
        end
    end
    return getActiveGrindingQuest() == qEntry.name
end

function LF.Step()
    local lvl, _, _, maxLvl = getPlayerLevelAndXP()
    if Config.LevelFarmStopAtMax and lvl >= maxLvl then
        LFStats.CurrentQuest = "MAX LEVEL"
        LFStats.CurrentObjective = ("Lv. %d / %d"):format(lvl, maxLvl)
        LF.SetStatus(("Reached Max Level (%d)!"):format(maxLvl))
        notifyInfo("Level Farm", ("You hit Max Level (%d)!"):format(maxLvl), 6)
        if WH.NotifyMaxLevel then
            WH.NotifyMaxLevel(lvl)
        end
        setActiveMode("None")
        return
    end

    LF.AutoAllocateStats()
    LF.EnsureHaki()

    local targetQ = pickTargetQuest()
    if not targetQ then
        LF.SetStatus("No quest available")
        task.wait(1.5)
        return
    end

    LFStats.CurrentQuest = targetQ.display
    local mode = Config.LevelFarmMode or "Auto Best Quest"
    local noQuestMode = (mode == "No Quest (Mob Only)")

    if not noQuestMode then
        local activeName, activeProg = getActiveGrindingQuest()
        if activeName and activeName ~= targetQ.name then
            LF.SetStatus("Switching quest...")
            Network:FireServer("Quests", "Abandon", activeName)
            local t0 = os.clock()
            while (os.clock() - t0) < 1.5 do
                if not isActive("LevelFarm") then return end
                if getActiveGrindingQuest() == nil then break end
                task.wait(0.1)
            end
            activeName, activeProg = getActiveGrindingQuest()
        end

        if activeName ~= targetQ.name then
            if not acceptGrindingQuest(targetQ) then
                task.wait(0.8)
                return
            end
            activeName, activeProg = getActiveGrindingQuest()
        end

        if activeName ~= targetQ.name then
            task.wait(0.5)
            return
        end

        local incomplete, progText = getIncompleteObjectives(targetQ, activeProg)
        LFStats.CurrentObjective = progText
        if #incomplete == 0 then
            task.wait(0.25)
            return
        end

        local function buildNeededSet()
            local curActive, curProg = getActiveGrindingQuest()
            if curActive ~= targetQ.name then
                return nil, ""
            end
            local inc, txt = getIncompleteObjectives(targetQ, curProg)
            LFStats.CurrentObjective = txt
            local set = {}
            for _, o in ipairs(inc) do
                set[o.enemyName] = true
            end
            return set, txt, inc
        end

        local neededSet, _, incList = buildNeededSet()
        if not neededSet or #incList == 0 then
            task.wait(0.2)
            return
        end

        -- Cek apakah sudah ada mob target di sekitar; jika belum, navigasi ke spot spawn objektif pertama
        local nearby = findAliveGrindingTargets(neededSet, false, 180, nil)
        local primaryObj = incList[1]
        local spawnPos = resolveEnemySpawnPos(primaryObj.enemyName, primaryObj.rawObj)
        if #nearby == 0 and spawnPos then
            LF.SetStatus("Heading to " .. primaryObj.enemyName .. "...")
            if not navigateToPos(spawnPos + Vector3.new(0, 3, 0), false, 18) then
                return
            end
        end

        local wasActiveBefore = true
        engageEnemies({
            shouldContinue = function()
                if not isActive("LevelFarm") then return false end
                local curLvl = getPlayerLevelAndXP()
                if Config.LevelFarmStopAtMax and curLvl >= maxLvl then return false end
                LF.AutoAllocateStats()
                local setNow, _, incNow = buildNeededSet()
                if not setNow or #incNow == 0 then
                    return false
                end
                -- Jika kita pindah objective & tidak ada mob tersisa dekat sini, keluar engageEnemies agar LF.Step navigasi ke spot objektif berikutnya
                local closeAny = findAliveGrindingTargets(setNow, false, 260, nil)
                if #closeAny == 0 then
                    local nextObj = incNow[1]
                    local nextPos = resolveEnemySpawnPos(nextObj.enemyName, nextObj.rawObj)
                    local _, _, hNow = getCharacterParts()
                    if nextPos and hNow and (hNow.Position - nextPos).Magnitude > 220 then
                        return false
                    end
                end
                return true
            end,
            findTargets = function(allowUnrendered, maxRadius, skippedTargets)
                local setNow = buildNeededSet()
                if not setNow then return {} end
                return findAliveGrindingTargets(setNow, allowUnrendered, maxRadius or 450, skippedTargets)
            end,
            isTargetValid = function(model)
                local setNow = buildNeededSet()
                if not setNow then return false end
                local orig = model:GetAttribute("OriginalName")
                return type(orig) == "string" and setNow[orig] == true
            end,
            anchorPos = spawnPos,
            getProgressKey = function()
                local _, txt = buildNeededSet()
                return txt
            end,
            timeout = 110,
            statusPrefix = "Farming " .. targetQ.display,
            waitStatus = "Waiting for " .. primaryObj.enemyName .. " respawn...",
            attackMode = Config.LevelFarmAttackPos,
            autoHaki = Config.LevelFarmAutoHaki,
            autoSkills = Config.LevelFarmAutoSkills,
            statusFn = LF.SetStatus,
        })

        -- Cek apakah quest selesai -> tunggu singkat RepeatOffered agar tick berikut langsung Instant Repeat
        if wasActiveBefore and isActive("LevelFarm") and getActiveGrindingQuest() ~= targetQ.name then
            LFStats.QuestsCompleted = LFStats.QuestsCompleted + 1
            LF.AutoAllocateStats()
            logEvent(("LF Done #%d: %s"):format(LFStats.QuestsCompleted, targetQ.display))
            LF.SetStatus(("Done #%d • Repeating..."):format(LFStats.QuestsCompleted))
            if Config.LevelFarmUseRepeat and RepeatQuestMod then
                local w0 = os.clock()
                while (os.clock() - w0) < 0.7 do
                    if not isActive("LevelFarm") then return end
                    if RepeatQuestMod.QuestName == targetQ.name then
                        break
                    end
                    task.wait(0.06)
                end
            end
        end
    else
        -- Mode No Quest (Mob Only): langsung bunuh mob dari targetQ tanpa ambil quest
        local allSet = {}
        local names = {}
        for _, o in ipairs(targetQ.objectives) do
            allSet[o.enemyName] = true
            table.insert(names, o.enemyName)
        end
        LFStats.CurrentObjective = "Mob Only: " .. table.concat(names, ", ")
        local firstObj = targetQ.objectives[1]
        local spawnPos = firstObj and resolveEnemySpawnPos(firstObj.enemyName, firstObj.rawObj) or nil
        local nearby = findAliveGrindingTargets(allSet, false, 180, nil)
        if #nearby == 0 and spawnPos then
            LF.SetStatus("Menuju spot " .. firstObj.enemyName .. "...")
            if not navigateToPos(spawnPos + Vector3.new(0, 3, 0), false, 18) then
                return
            end
        end
        engageEnemies({
            shouldContinue = function()
                if not isActive("LevelFarm") then return false end
                if Config.LevelFarmMode ~= "No Quest (Mob Only)" then return false end
                LF.AutoAllocateStats()
                return true
            end,
            findTargets = function(allowUnrendered, maxRadius, skippedTargets)
                return findAliveGrindingTargets(allSet, allowUnrendered, maxRadius or 450, skippedTargets)
            end,
            anchorPos = spawnPos,
            timeout = 90,
            statusPrefix = "Farm Mob",
            waitStatus = "Menunggu respawn mob...",
            attackMode = Config.LevelFarmAttackPos,
            autoHaki = Config.LevelFarmAutoHaki,
            autoSkills = Config.LevelFarmAutoSkills,
            statusFn = LF.SetStatus,
        })
    end

    task.wait(Config.LoopDelay)
end

function LF.ResetStats()
    local lvl, xp = getPlayerLevelAndXP()
    LFStats.StartTime = os.clock()
    LFStats.StartLevel = lvl
    LFStats.StartCumXP = estimateCumulativeXP(lvl, xp)
    LFStats.QuestsCompleted = 0
    LFStats.RepeatUses = 0
    LFStats.SkillsCast = 0
    LFStats.AbandonedTH = 0
    LFStats.StatsSpent = 0
    updateStatsUI()
end

function LF.UpdateUI(safeSet, antiTpDelta)
    if not LF.UI then return end
    local lvl, xp, maxXp, maxLvl = getPlayerLevelAndXP()
    local pct = maxXp > 0 and math.clamp((xp / maxXp) * 100, 0, 100) or 0
    local cumNow = estimateCumulativeXP(lvl, xp)
    local gainedXP = math.max(0, cumNow - (LFStats.StartCumXP or cumNow))
    local gainedLvl = math.max(0, lvl - (LFStats.StartLevel or lvl))
    local elapsed = math.max(1, os.clock() - (LFStats.StartTime or os.clock()))
    local xpPerMin = elapsed >= 5 and math.floor(gainedXP / (elapsed / 60)) or 0

    local ds = getDataStore()
    local st = ds and ds.Statistics or {}
    local availPts = getAvailableStatPoints()

    local activeName, activeProg = getActiveGrindingQuest()
    local previewQuest = LFStats.CurrentQuest
    local previewObj = LFStats.CurrentObjective
    if getActiveMode() ~= "LevelFarm" then
        local autoQ = pickTargetQuest()
        previewQuest = autoQ and autoQ.display or "-"
        if activeName and activeProg then
            for _, q in ipairs(getGrindingCatalog()) do
                if q.name == activeName then
                    local _, txt = getIncompleteObjectives(q, activeProg)
                    previewQuest = q.display
                    previewObj = txt
                    break
                end
            end
        else
            previewObj = autoQ and ("+" .. formatNumber(autoQ.xp) .. " XP  •  +" .. formatNumber(autoQ.gold) .. " G") or "-"
        end
    end

    safeSet(LF.UI.LevelLabel, string.format(
        "Lv. %d / %d  (+%d)\n%s / %s XP  (%.1f%%)",
        lvl, maxLvl, gainedLvl, formatNumber(xp), formatNumber(maxXp), pct
    ))
    safeSet(LF.UI.QuestLabel, string.format(
        "Quest: %s\n%s",
        tostring(previewQuest or "-"),
        tostring(previewObj or "-")
    ))
    safeSet(LF.UI.RateLabel, string.format(
        "%d Quests  •  %d Repeats  •  %d Skills\n+%s XP (%s/m)  •  AntiTP: %d",
        LFStats.QuestsCompleted,
        LFStats.RepeatUses,
        LFStats.SkillsCast or 0,
        formatNumber(gainedXP),
        formatNumber(xpPerMin),
        antiTpDelta or 0
    ))
    safeSet(LF.UI.PointsLabel, string.format(
        "%d pts available  (Spent: %d)\nStr %d • End %d • Swd %d • Gun %d • DF %d",
        availPts,
        LFStats.StatsSpent,
        tonumber(st.Strength) or 1,
        tonumber(st.Endurance) or 1,
        tonumber(st.Sword) or 1,
        tonumber(st.Gun) or 1,
        tonumber(st.DevilFruit) or 1
    ))
end
end -- end Auto Farm Level scope

-- ============================================================================
-- DISCORD WEBHOOK ENGINE
-- ============================================================================
do
local HttpService = game:GetService("HttpService")
local httpRequest = (type(request) == "function" and request)
    or (type(http_request) == "function" and http_request)
    or (type(syn) == "table" and type(syn.request) == "function" and syn.request)
    or (type(fluxus) == "table" and type(fluxus.request) == "function" and fluxus.request)
    or nil

local RARITY_EMBED_COLORS = {
    Common = 0xB9BEC8,
    Uncommon = 0x2DE182,
    Rare = 0x3CAFFF,
    Epic = 0xD750FA,
    Legendary = 0xFFC82D,
}

local WHState = {
    SentCount = 0,
    LastStatus = "Not tested",
    LastLevel = nil,
    LastSummaryTime = os.clock(),
    LastSendTime = 0,
}
WH.State = WHState
getgenv()._VoxSeasWHState = WHState

local function setWHStatus(text)
    WHState.LastStatus = tostring(text)
    if WH.UI and WH.UI.StatusLabel then
        pcall(function()
            restoreExecutorContext()
            WH.UI.StatusLabel:SetText("Status: " .. WHState.LastStatus)
        end)
    end
end

local function isValidWebhookUrl(url)
    if type(url) ~= "string" then return false end
    local trimmed = url:gsub("^%s+", ""):gsub("%s+$", "")
    return trimmed:match("^https://[%w%.%-]*discord%.com/api/webhooks/%d+/[%w%-%_]+") ~= nil
        or trimmed:match("^https://[%w%.%-]*discordapp%.com/api/webhooks/%d+/[%w%-%_]+") ~= nil
end

local function formatPing(shouldPing)
    if not shouldPing then return nil end
    local raw = tostring(Config.WebhookPingId or ""):gsub("%D", "")
    if #raw >= 15 then
        return "<@" .. raw .. ">"
    end
    return nil
end

local function getPlayerLevelSafe()
    local ds = getDataStore()
    return (ds and ds.Statistics and tonumber(ds.Statistics.Level)) or 1
end

local function postEmbed(title, description, color, fields, shouldPing, isTest, cb)
    local url = tostring(Config.WebhookUrl or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if not isTest and not Config.WebhookEnabled then
        return false, "Webhook disabled"
    end
    if not isValidWebhookUrl(url) then
        local msg = "Invalid Discord webhook URL"
        if isTest then setWHStatus(msg) end
        return false, msg
    end
    if not httpRequest then
        local msg = "Executor HTTP request unavailable"
        if isTest then setWHStatus(msg) end
        return false, msg
    end
    if not isTest and (os.clock() - WHState.LastSendTime) < 1.5 then
        return false, "Rate limited"
    end
    WHState.LastSendTime = os.clock()

    local payload = {
        username = "Fluffy Hub • Vox Seas",
        content = formatPing(shouldPing),
        embeds = {
            {
                title = title,
                description = description,
                color = color or 0x5865F2,
                fields = fields or {},
                footer = {
                    text = string.format("%s • Lv.%d • %s G", LocalPlayer.Name, getPlayerLevelSafe(), formatNumber(getGold())),
                },
                timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
            },
        },
    }

    task.spawn(function()
        restoreExecutorContext()
        local okEnc, body = pcall(HttpService.JSONEncode, HttpService, payload)
        if not okEnc then
            setWHStatus("Encode error")
            if cb then pcall(cb, false, "Encode error") end
            return
        end
        local okReq, res = pcall(httpRequest, {
            Url = url,
            Method = "POST",
            Headers = { ["Content-Type"] = "application/json" },
            Body = body,
        })
        if not okReq then
            local errMsg = "Request failed"
            setWHStatus(errMsg)
            if cb then pcall(cb, false, tostring(res)) end
            return
        end
        local code = type(res) == "table" and tonumber(res.StatusCode) or 0
        if code >= 200 and code < 300 then
            WHState.SentCount = WHState.SentCount + 1
            local stamp = os.date("%H:%M:%S")
            setWHStatus(string.format("Sent (%d) • %s  (Total: %d)", code, stamp, WHState.SentCount))
            if cb then pcall(cb, true, code) end
        else
            local errMsg = string.format("HTTP %d", code)
            setWHStatus("Failed (" .. errMsg .. ")")
            if cb then pcall(cb, false, errMsg) end
        end
    end)
    return true
end

function WH.SendTest()
    local ok, err = postEmbed(
        "Webhook Connected",
        "Fluffy Hub • Vox Seas webhook is working properly.",
        0x57F287,
        {
            { name = "Player", value = LocalPlayer.Name, inline = true },
            { name = "Level", value = tostring(getPlayerLevelSafe()), inline = true },
            { name = "Gold", value = formatNumber(getGold()) .. " G", inline = true },
        },
        true,
        true,
        function(success, info)
            if success then
                notifyInfo("Webhook", "Test embed sent (HTTP " .. tostring(info) .. ").", 3)
            else
                notifyInfo("Webhook", "Test failed: " .. tostring(info), 4)
            end
        end
    )
    if not ok and err then
        notifyInfo("Webhook", err, 3.5)
    end
end

function WH.NotifyLevelUp(oldLvl, newLvl)
    if not Config.WebhookEnabled or not Config.WebhookOnLevelUp then return end
    local qName = (LF.Stats and LF.Stats.CurrentQuest) or "-"
    local qDone = (LF.Stats and LF.Stats.QuestsCompleted) or 0
    postEmbed(
        string.format("Level Up!  Lv.%d → Lv.%d", oldLvl, newLvl),
        nil,
        0xFEE75C,
        {
            { name = "Quest", value = tostring(qName), inline = true },
            { name = "Session Quests", value = tostring(qDone), inline = true },
            { name = "Gold", value = formatNumber(getGold()) .. " G", inline = true },
        },
        false,
        false
    )
end

function WH.NotifyMaxLevel(lvl)
    if not Config.WebhookEnabled or not Config.WebhookOnMaxLevel then return end
    postEmbed(
        string.format("Max Level Reached! (Lv.%d)", lvl),
        "Auto Farm Level stopped automatically.",
        0x9B59B6,
        {
            { name = "Session Quests", value = tostring((LF.Stats and LF.Stats.QuestsCompleted) or 0), inline = true },
            { name = "Gold", value = formatNumber(getGold()) .. " G", inline = true },
        },
        true,
        false
    )
end

function WH.NotifyChest(rarity, gainedGold, sourceKind, haggled)
    if not Config.WebhookEnabled or not Config.WebhookOnRareChest then return end
    if rarity ~= "Rare" and rarity ~= "Epic" and rarity ~= "Legendary" then return end
    local netSign = Stats.NetProfit >= 0 and "+" or ""
    postEmbed(
        string.format("[%s] Chest Sold", rarity),
        nil,
        RARITY_EMBED_COLORS[rarity] or 0x3CAFFF,
        {
            { name = "Payout", value = "+" .. formatNumber(gainedGold) .. " G" .. (haggled and " (Haggle +15%)" or ""), inline = true },
            { name = "Source", value = tostring(sourceKind), inline = true },
            { name = "Net Profit", value = netSign .. formatNumber(Stats.NetProfit) .. " G", inline = true },
        },
        rarity == "Legendary" or rarity == "Epic",
        false
    )
end

function WH.NotifySideQuest(questName, island, rewardGold)
    if not Config.WebhookEnabled or not Config.WebhookOnSideQuest then return end
    local ov = SQ.GetOverview and SQ.GetOverview() or nil
    postEmbed(
        "Side Quest Completed",
        string.format("**%s** (%s)", tostring(questName), tostring(island or "-")),
        0x2ECC71,
        {
            { name = "Reward", value = "+" .. formatNumber(rewardGold) .. " G", inline = true },
            { name = "Progress", value = ov and string.format("%d / %d", ov.completed, ov.total) or tostring(SQStats.SessionCompleted), inline = true },
        },
        false,
        false
    )
end

function WH.NotifySummary()
    if not Config.WebhookEnabled then return end
    local mode = getActiveMode()
    if mode == "None" then return end
    local fields = {
        { name = "Mode", value = mode, inline = true },
        { name = "Level", value = tostring(getPlayerLevelSafe()), inline = true },
        { name = "Gold", value = formatNumber(getGold()) .. " G", inline = true },
    }
    if mode == "LevelFarm" and LF.Stats then
        table.insert(fields, { name = "Quests Done", value = tostring(LF.Stats.QuestsCompleted), inline = true })
        table.insert(fields, { name = "Skills Cast", value = tostring(LF.Stats.SkillsCast or 0), inline = true })
    elseif mode == "Shipwreck" then
        local netSign = Stats.NetProfit >= 0 and "+" or ""
        table.insert(fields, { name = "Chests Sold", value = tostring(Stats.TotalChestsSold), inline = true })
        table.insert(fields, { name = "Net Profit", value = netSign .. formatNumber(Stats.NetProfit) .. " G", inline = true })
    elseif mode == "SideQuest" then
        table.insert(fields, { name = "SQ Done", value = tostring(SQStats.SessionCompleted), inline = true })
    end
    postEmbed("Session Summary", nil, 0x5865F2, fields, false, false)
end

function WH.Tick()
    local curLvl = getPlayerLevelSafe()
    if WHState.LastLevel == nil then
        WHState.LastLevel = curLvl
    elseif curLvl > WHState.LastLevel then
        local prev = WHState.LastLevel
        WHState.LastLevel = curLvl
        if getActiveMode() == "LevelFarm" then
            WH.NotifyLevelUp(prev, curLvl)
        end
    end

    local intervalMin = tonumber(Config.WebhookSummaryMin) or 0
    if Config.WebhookEnabled and intervalMin > 0 and getActiveMode() ~= "None" then
        if (os.clock() - WHState.LastSummaryTime) >= (intervalMin * 60) then
            WHState.LastSummaryTime = os.clock()
            WH.NotifySummary()
        end
    end
end
end -- end Discord Webhook scope

-- Cleanup hook (aman dipanggil dari OnUnload maupun re-execute)
local cleanupDone = false
local function cleanup(fromLibraryUnload)
    if cleanupDone then return end
    cleanupDone = true
    UIAlive = false
    Config.Enabled = false
    Config.ShipwreckEnabled = false
    Config.SideQuestEnabled = false
    Config.LevelFarmEnabled = false
    ActiveMoveToken = ActiveMoveToken + 1
    if CombatLockConn then
        CombatLockConn:Disconnect()
        CombatLockConn = nil
    end
    setAntiAFK(false, true)
    pcall(function() RunService:Set3dRenderingEnabled(true) end)
    if BlackScreenGui and BlackScreenGui.Parent then
        pcall(function() BlackScreenGui:Destroy() end)
    end
    BlackScreenGui = nil
    BlackScreenLabel = nil
    if FPSBoostActive then
        pcall(setFPSBoost, false, true)
    end
    setNoclip(false)
    local _, _, hrp = getCharacterParts()
    clearBodyVelocity(hrp)
    if DiggingClient then
        pcall(DiggingClient.Cancel)
    end
    if not fromLibraryUnload and Library then
        restoreExecutorContext()
        pcall(function() Library:Unload() end)
        pcall(function()
            if Library.ScreenGui and Library.ScreenGui.Parent then
                Library.ScreenGui:Destroy()
            end
        end)
        restoreExecutorContext()
    end
    if FallbackGui and FallbackGui.Parent then
        pcall(function() FallbackGui:Destroy() end)
    end
end

getgenv()._AutoShipwreckCleanup = function()
    cleanup(false)
end
getgenv()._VoxSeasCleanup = getgenv()._AutoShipwreckCleanup

-- Build BeverlyLIB UI (dengan fallback UI sederhana jika HttpGet gagal)
local function buildBeverlyLIB()
    restoreExecutorContext()
    local repo = "https://raw.githubusercontent.com/bevankeren/BeverlyLIB/main/"
    local src = game:HttpGet(repo .. "Library.lua")
    restoreExecutorContext()
    local chunk, compileErr = loadstring(src)
    assert(chunk, tostring(compileErr or "BeverlyLIB loadstring failed"))
    local lib = chunk()
    restoreExecutorContext()
    assert(lib and lib.CreateWindow, "BeverlyLIB CreateWindow unavailable")
    Library = lib

    local ThemeManager, SaveManager = nil, nil
    pcall(function()
        restoreExecutorContext()
        local tmChunk = loadstring(game:HttpGet(repo .. "addons/ThemeManager.lua"))
        if tmChunk then ThemeManager = tmChunk() end
        restoreExecutorContext()
    end)
    pcall(function()
        restoreExecutorContext()
        local smChunk = loadstring(game:HttpGet(repo .. "addons/SaveManager.lua"))
        if smChunk then SaveManager = smChunk() end
        restoreExecutorContext()
    end)

    -- Safe synchronous GetTextBounds agar tidak yield dan tidak menurunkan thread identity
    local textService = game:GetService("TextService")
    function Library:GetTextBounds(text, font, size, width)
        restoreExecutorContext()
        local scale = self.DPIScale or 1
        local cam = workspace.CurrentCamera
        local defaultWidth = (cam and cam.ViewportSize.X > 64) and (cam.ViewportSize.X - 32) or 1200
        local rawText = tostring(text or "")
        local plainText = rawText:gsub("<[^>]+>", "")
        width = width or defaultWidth
        local bounds = textService:GetTextSize(plainText, (size or 14) * scale, Enum.Font.Gotham, Vector2.new(width * scale, 10000))
        return math.ceil(bounds.X / scale) + 2, math.ceil(bounds.Y / scale)
    end

    if Library.ScreenGui then
        Library.ScreenGui.Enabled = true
        pcall(function()
            Library.ScreenGui:SetAttribute("FluffyHubOwner", "VoxSeas")
        end)
    end

    local win = Library:CreateWindow({
        Title = "Fluffy Hub",
        Version = "Vox Seas v3.3",
        Icon = nil,
        TabLayout = "Side",
        SideTabsWidth = 156,
        IconRail = true,
        AdaptiveColumns = true,
        ScriptStatus = true,
        ScriptHeartbeatTimeout = 15,
        DisableSearch = true,
        GlobalSearch = false,
        Username = true,
        Badge = "Vox Seas",
        Footer = "",
        FooterLeft = "RightShift to toggle",
        FooterRight = "v3.3",
        Size = UDim2.fromOffset(740, 515),
        Center = true,
        AutoShow = true,
        CornerRadius = 10,
        ToggleButtonIcon = "layout-grid",
        Resizable = true,
        NotifySide = "Right",
        ToggleKeybind = Enum.KeyCode.RightShift,
    })
    Window = win

    local farmCat = win.AddCategory and win:AddCategory("Farm") or win
    local utilCat = win.AddCategory and win:AddCategory("Tools") or win
    local sysCat = win.AddCategory and win:AddCategory("System") or win

    -- Tab 1: Level Farm (Instant Repeat, Auto Haki, QuestLimit & Max-Level stop built-in)
    local lfTab = farmCat:AddTab("Level Farm", "swords", "Auto leveling Lv 1–500 with instant repeat & auto skills")
    local lfCtrlBox = lfTab:AddGroupbox({ Side = "Left", Name = "Leveling", IconName = "swords" })
    LF.UI.Toggle = lfCtrlBox:AddToggle("VSLevelFarmEnabled", {
        Text = "Auto Farm Level",
        Default = Config.LevelFarmEnabled,
        Callback = function(value)
            if syncingToggle or cleanupDone then return end
            setActiveMode(value and "LevelFarm" or "None")
            LF.SetStatus(value and "Starting..." or "Idle")
        end,
    })
    lfCtrlBox:AddDropdown("VSLFTarget", {
        Text = "Quest",
        Values = LF.ListQuests(),
        Default = Config.LevelFarmTarget or "Auto (Best XP)",
        Callback = function(value)
            if cleanupDone then return end
            Config.LevelFarmTarget = value
            Config.LevelFarmMode = (value == "Auto (Best XP)" or value == "Auto (Sesuai Level)")
                and "Auto Best Quest"
                or "Manual Quest"
            updateStatsUI()
        end,
    })
    lfCtrlBox:AddDropdown("VSLFAttackPos", {
        Text = "Attack Position",
        Values = { "Behind", "Above" },
        Default = Config.LevelFarmAttackPos or "Behind",
        Callback = function(value)
            if cleanupDone then return end
            Config.LevelFarmAttackPos = value
        end,
    })
    lfCtrlBox:AddToggle("VSLFAutoSkills", {
        Text = "Auto Skills (Z / X / C / V)",
        Default = Config.LevelFarmAutoSkills,
        Callback = function(value)
            if cleanupDone then return end
            Config.LevelFarmAutoSkills = value
        end,
    })
    lfCtrlBox:AddToggle("VSLFIncludeBoss", {
        Text = "Include Boss Quests",
        Default = Config.LevelFarmIncludeBoss,
        Callback = function(value)
            if cleanupDone then return end
            Config.LevelFarmIncludeBoss = value
            updateStatsUI()
        end,
    })
    lfCtrlBox:AddDivider("Status")
    LF.UI.StatusLabel = lfCtrlBox:AddLabel("VSLFStatusLabel", {
        Text = "Status: Idle",
        DoesWrap = true,
    })

    local lfStatBox = lfTab:AddGroupbox({ Side = "Right", Name = "Progress", IconName = "trending-up" })
    LF.UI.LevelLabel = lfStatBox:AddLabel("VSLFLevelLabel", { Text = "Lv. -", DoesWrap = true })
    LF.UI.QuestLabel = lfStatBox:AddLabel("VSLFQuestLabel", { Text = "Quest: -", DoesWrap = true })
    LF.UI.RateLabel = lfStatBox:AddLabel("VSLFRateLabel", { Text = "0 Quests", DoesWrap = true })
    lfStatBox:AddDivider("Auto Stats")
    lfStatBox:AddToggle("VSLFAutoStats", {
        Text = "Auto Spend Points",
        Default = Config.LevelFarmAutoStats,
        Callback = function(value)
            if cleanupDone then return end
            Config.LevelFarmAutoStats = value
            if value then
                LF.AutoAllocateStats()
                updateStatsUI()
            end
        end,
    })
    lfStatBox:AddDropdown("VSLFStatTarget", {
        Text = "Stat",
        Values = { "Sword", "Strength", "Endurance", "Gun", "DevilFruit" },
        Default = Config.LevelFarmStatTarget or "Sword",
        Callback = function(value)
            if cleanupDone then return end
            Config.LevelFarmStatTarget = value
        end,
    })
    LF.UI.PointsLabel = lfStatBox:AddLabel("VSLFPointsLabel", { Text = "-", DoesWrap = true })
    lfStatBox:AddDivider()
    lfStatBox:AddButton({
        Text = "Reset Session",
        Func = function()
            LF.ResetStats()
            notifyInfo("Level Farm", "Session stats reset.", 2.5)
        end,
    })

    -- Tab 2: Shipwreck & Treasure Hunt (Auto Haggle +15%, Rarity Alerts & Far-Island Parking built-in)
    local farmTab = farmCat:AddTab("Shipwreck", "compass", "Auto Shipwreck & Treasure Hunt with auto-haggle")
    local ctrlBox = farmTab:AddGroupbox({ Side = "Left", Name = "Shipwreck & Treasure", IconName = "anchor" })
    RunToggle = ctrlBox:AddToggle("VSAutoEnabled", {
        Text = "Auto Shipwreck",
        Default = Config.ShipwreckEnabled,
        Callback = function(value)
            if syncingToggle or cleanupDone then return end
            setActiveMode(value and "Shipwreck" or "None")
            setStatus(value and "Starting..." or "Idle")
        end,
    })
    ctrlBox:AddLabel("VSSWBuiltIn", {
        Text = "Auto-Haggle (+15%), Rarity Alerts, and Smart Far-Island Parking are built in.",
        DoesWrap = true,
    })
    ctrlBox:AddDivider("Status")
    StatusLabel = ctrlBox:AddLabel("VSStatusLabel", {
        Text = "Status: Idle",
        DoesWrap = true,
    })

    local statBox = farmTab:AddGroupbox({ Side = "Right", Name = "Session Profit", IconName = "coins" })
    GoldLabel = statBox:AddLabel("VSGoldLabel", { Text = "Wallet: -", DoesWrap = true })
    ProfitLabel = statBox:AddLabel("VSProfitLabel", { Text = "Net Profit: -", DoesWrap = true })
    RateLabel = statBox:AddLabel("VSRateLabel", { Text = "Rate: -", DoesWrap = true })
    ProgressLabel = statBox:AddLabel("VSProgressLabel", { Text = "Chests: 0", DoesWrap = true })
    RarityLabel = statBox:AddLabel("VSRarityLabel", { Text = "Rarities: -", DoesWrap = true })
    statBox:AddDivider()
    statBox:AddButton({
        Text = "Reset Session",
        Func = function()
            resetProfitStats()
        end,
    })

    -- Tab 3: Side Quests (Minigame solvers & QuestLimit handling built-in)
    local sqTab = farmCat:AddTab("Side Quests", "scroll-text", "Auto one-time progression side quests")
    local sqCtrlBox = sqTab:AddGroupbox({ Side = "Left", Name = "One-Time Quests", IconName = "scroll-text" })
    SideQuestToggle = sqCtrlBox:AddToggle("VSSideQuestEnabled", {
        Text = "Auto Side Quests",
        Default = Config.SideQuestEnabled,
        Callback = function(value)
            if syncingToggle or cleanupDone then return end
            setActiveMode(value and "SideQuest" or "None")
            setSQStatus(value and "Starting..." or "Idle")
        end,
    })
    sqCtrlBox:AddDropdown("VSSQIsland", {
        Text = "Island",
        Values = SQ.ListIslands(),
        Default = Config.SideQuestIsland or "All Islands",
        Callback = function(value)
            if cleanupDone then return end
            Config.SideQuestIsland = value
            updateStatsUI()
        end,
    })
    sqCtrlBox:AddDropdown("VSSQTarget", {
        Text = "Quest",
        Values = SQ.ListTargets(),
        Default = Config.SideQuestTarget or "Auto (All Eligible)",
        Callback = function(value)
            if cleanupDone then return end
            Config.SideQuestTarget = value
            updateStatsUI()
        end,
    })
    sqCtrlBox:AddDivider("Status")
    SQStatusLabel = sqCtrlBox:AddLabel("VSSQStatusLabel", {
        Text = "Status: Idle",
        DoesWrap = true,
    })

    local sqStatBox = sqTab:AddGroupbox({ Side = "Right", Name = "Progress", IconName = "check-circle" })
    SQProgressLabel = sqStatBox:AddLabel("VSSQProgressLabel", { Text = "Completed: -", DoesWrap = true })
    SQDetailLabel = sqStatBox:AddLabel("VSSQDetailLabel", { Text = "Active: -", DoesWrap = true })
    SQRemainingLabel = sqStatBox:AddLabel("VSSQRemainingLabel", { Text = "Remaining: -", DoesWrap = true })
    sqStatBox:AddDivider()
    sqStatBox:AddButton({
        Text = "Reset Skipped",
        Func = function()
            SQStats.SkippedQuests = {}
            updateStatsUI()
            notifyInfo("Side Quests", "Skipped list cleared.", 2.5)
        end,
    })
    sqStatBox:AddButton({
        Text = "Reset Session",
        Func = function()
            SQStats.SessionCompleted = 0
            SQStats.SessionGoldStart = getGold()
            SQStats.SessionGoldEarned = 0
            SQStats.AbandonedTH = 0
            SQStats.CompletedList = {}
            SQStats.SkippedQuests = {}
            updateStatsUI()
            notifyInfo("Side Quests", "Session stats reset.", 2.5)
        end,
    })

    -- Tab 4: Utility (Weapon, travel speed & performance tools)
    local utilityTab = utilCat:AddTab("Utility", "wrench", "Weapon, travel speed & client performance")
    local speedBox = utilityTab:AddGroupbox({ Side = "Left", Name = "Combat & Travel", IconName = "gauge" })
    local weaponValues = listDefaultWeaponNames()
    local defaultWeapon = Config.PreferredWeapon or "Auto (Best)"
    speedBox:AddDropdown("VSWeapon", {
        Text = "Weapon",
        Values = weaponValues,
        Default = defaultWeapon,
        Callback = function(value)
            if cleanupDone then return end
            if value == "Auto (Best)" or value == "Auto (Terbaik)" then
                Config.PreferredWeapon = nil
            else
                Config.PreferredWeapon = value
            end
        end,
    })
    speedBox:AddButton({
        Text = "Refresh Weapons",
        Func = function()
            local opts = listDefaultWeaponNames()
            local dd = Library.Options and Library.Options.VSWeapon
            if dd and dd.SetValues then
                dd:SetValues(opts)
            end
            notifyInfo("Weapons", "Found " .. tostring(#opts - 1) .. " weapons.", 2.5)
        end,
    })
    speedBox:AddDivider()
    speedBox:AddSlider("VSTweenSpeed", {
        Text = "Fly Speed",
        Default = Config.TweenSpeed,
        Min = 100,
        Max = 440,
        Rounding = 0,
        Suffix = " st/s",
        Callback = function(value)
            if cleanupDone then return end
            Config.TweenSpeed = value
        end,
    })
    speedBox:AddSlider("VSCarrySpeed", {
        Text = "Carry Speed",
        Default = Config.CarryTweenSpeed,
        Min = 80,
        Max = 145,
        Rounding = 0,
        Suffix = " st/s",
        Callback = function(value)
            if cleanupDone then return end
            Config.CarryTweenSpeed = value
        end,
    })

    local perfBox = utilityTab:AddGroupbox({ Side = "Right", Name = "Performance", IconName = "zap" })
    perfBox:AddToggle("VSAntiAFK", {
        Text = "Anti-AFK",
        Default = Config.AntiAFK,
        Callback = function(value)
            if cleanupDone then return end
            setAntiAFK(value)
        end,
    })
    perfBox:AddToggle("VSFPSBoost", {
        Text = "FPS Booster",
        Default = Config.FPSBoost,
        Callback = function(value)
            if cleanupDone then return end
            setFPSBoost(value)
        end,
    })
    BlackScreenToggle = perfBox:AddToggle("VSBlackScreen3D", {
        Text = "Black Screen",
        Default = Config.BlackScreen3D,
        Callback = function(value)
            if cleanupDone then return end
            setBlackScreen(value)
        end,
    })

    -- Tab 5: Webhook (Discord notifications & periodic summaries)
    local whTab = utilCat:AddTab("Webhook", "bell", "Discord notifications for level ups, rare chests & summaries")
    local whMainBox = whTab:AddGroupbox({ Side = "Left", Name = "Discord Webhook", IconName = "send" })
    whMainBox:AddToggle("VSWebhookEnabled", {
        Text = "Enable Webhook",
        Default = Config.WebhookEnabled,
        Callback = function(value)
            if cleanupDone then return end
            Config.WebhookEnabled = value
        end,
    })
    whMainBox:AddInput("VSWebhookUrl", {
        Text = "Webhook URL",
        Default = Config.WebhookUrl or "",
        Placeholder = "https://discord.com/api/webhooks/...",
        ClearTextOnFocus = false,
        Finished = true,
        Callback = function(value)
            if cleanupDone then return end
            Config.WebhookUrl = tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
        end,
    })
    whMainBox:AddInput("VSWebhookPingId", {
        Text = "Ping User ID (Optional)",
        Default = Config.WebhookPingId or "",
        Placeholder = "Discord numeric user ID",
        ClearTextOnFocus = false,
        Finished = true,
        Callback = function(value)
            if cleanupDone then return end
            Config.WebhookPingId = tostring(value or ""):gsub("%D", "")
        end,
    })
    whMainBox:AddButton({
        Text = "Test Webhook",
        Func = function()
            if WH.SendTest then WH.SendTest() end
        end,
    })
    whMainBox:AddDivider("Status")
    WH.UI.StatusLabel = whMainBox:AddLabel("VSWHStatusLabel", {
        Text = "Status: " .. tostring((WH.State and WH.State.LastStatus) or "Not tested"),
        DoesWrap = true,
    })

    local whEvtBox = whTab:AddGroupbox({ Side = "Right", Name = "Events", IconName = "bell-ring" })
    whEvtBox:AddToggle("VSWHLevelUp", {
        Text = "Level Up",
        Default = Config.WebhookOnLevelUp,
        Callback = function(value)
            if cleanupDone then return end
            Config.WebhookOnLevelUp = value
        end,
    })
    whEvtBox:AddToggle("VSWHRareChest", {
        Text = "Rare+ Chest Sold",
        Default = Config.WebhookOnRareChest,
        Callback = function(value)
            if cleanupDone then return end
            Config.WebhookOnRareChest = value
        end,
    })
    whEvtBox:AddToggle("VSWHSideQuest", {
        Text = "Side Quest Done",
        Default = Config.WebhookOnSideQuest,
        Callback = function(value)
            if cleanupDone then return end
            Config.WebhookOnSideQuest = value
        end,
    })
    whEvtBox:AddToggle("VSWHMaxLevel", {
        Text = "Max Level Reached",
        Default = Config.WebhookOnMaxLevel,
        Callback = function(value)
            if cleanupDone then return end
            Config.WebhookOnMaxLevel = value
        end,
    })
    whEvtBox:AddDivider()
    whEvtBox:AddSlider("VSWHSummaryMin", {
        Text = "Summary Interval",
        Default = Config.WebhookSummaryMin or 0,
        Min = 0,
        Max = 60,
        Rounding = 0,
        Suffix = " min",
        FormatDisplayValue = function(_, v)
            if v == 0 then return "Off" end
            return tostring(v) .. " min"
        end,
        Callback = function(value)
            if cleanupDone then return end
            Config.WebhookSummaryMin = value
            if WH.State then WH.State.LastSummaryTime = os.clock() end
        end,
    })

    -- Tab 6: Settings (Config System via SaveManager, Themes via ThemeManager, Menu Controls)
    local settingsTab = sysCat:AddTab("Settings", "settings", "Configs, themes & menu controls")
    local menuBox = settingsTab:AddGroupbox({ Side = "Left", Name = "Menu", IconName = "sliders-horizontal" })
    menuBox:AddDropdown("VSTabLayout", {
        Text = "Tab Layout",
        Values = { "Side", "Top" },
        Default = (win.GetTabLayout and win:GetTabLayout()) or "Side",
        Callback = function(value)
            if cleanupDone then return end
            if win.SetTabLayout then pcall(win.SetTabLayout, win, value) end
        end,
    })
    menuBox:AddDropdown("VSDPIScale", {
        Text = "DPI Scale",
        Values = { "75%", "90%", "100%", "110%", "125%" },
        Default = "100%",
        Callback = function(value)
            if cleanupDone then return end
            local num = tonumber((tostring(value):gsub("%%", "")))
            if num and Library.SetDPIScale then pcall(Library.SetDPIScale, Library, num) end
        end,
    })
    menuBox:AddToggle("VSAlwaysOnTop", {
        Text = "Always On Top",
        Default = false,
        Callback = function(value)
            if cleanupDone then return end
            if win.SetAlwaysOnTop then pcall(win.SetAlwaysOnTop, win, value) end
        end,
    })
    menuBox:AddLabel("Menu Keybind"):AddKeyPicker("MenuKeybind", {
        Default = "RightShift",
        NoUI = true,
        Text = "Menu Keybind",
    })
    if Library.Options and Library.Options.MenuKeybind then
        Library.ToggleKeybind = Library.Options.MenuKeybind
    end
    menuBox:AddDivider()
    menuBox:AddButton({
        Text = "Unload Hub",
        DoubleClick = true,
        Func = function()
            pcall(function() Library:Unload() end)
        end,
    })

    if ThemeManager then
        pcall(function()
            restoreExecutorContext()
            ThemeManager:SetLibrary(Library)
            ThemeManager:SetFolder("FluffyHub")
            ThemeManager:ApplyToTab(settingsTab, "paintbrush")
            restoreExecutorContext()
        end)
    end
    if SaveManager then
        pcall(function()
            restoreExecutorContext()
            SaveManager:SetLibrary(Library)
            SaveManager:IgnoreThemeSettings()
            SaveManager:SetIgnoreIndexes({ "MenuKeybind", "VSAutoEnabled", "VSSideQuestEnabled", "VSLevelFarmEnabled" })
            SaveManager:SetFolder("FluffyHub/VoxSeas")
            SaveManager:BuildConfigSection(settingsTab, "folder-cog")
            SaveManager:LoadAutoloadConfig()
            restoreExecutorContext()
        end)
    end

    Library:OnUnload(function()
        cleanup(true)
    end)

    pcall(function()
        restoreExecutorContext()
        local activeMode = getActiveMode()
        win:SetScriptStatus(activeMode ~= "None" and "Running" or "Idle", Stats.LastStatus)
        if activeMode ~= "None" and win.ReportScriptHeartbeat then
            win:ReportScriptHeartbeat(Stats.LastStatus)
        end
    end)
    updateStatsUI()
    notifyInfo("Fluffy Hub", "Vox Seas v3.3 ready.", 3)
end

local function buildFallbackUI()
    pcall(function()
        local oldCore = CoreGui:FindFirstChild("BeverlyVoxShipwreckUI")
        if oldCore then oldCore:Destroy() end
    end)
    local uiParent = getUIParent()
    local old = uiParent:FindFirstChild("BeverlyVoxShipwreckUI")
    if old then old:Destroy() end

    local gui = Instance.new("ScreenGui")
    gui.Name = "BeverlyVoxShipwreckUI"
    gui.ResetOnSpawn = false
    gui.Parent = uiParent
    FallbackGui = gui

    local frame = Instance.new("Frame")
    frame.Size = UDim2.fromOffset(300, 132)
    frame.Position = UDim2.new(0, 20, 0.5, -66)
    frame.BackgroundColor3 = Color3.fromRGB(20, 22, 28)
    frame.BorderSizePixel = 0
    frame.Active = true
    frame.Draggable = true
    frame.Parent = gui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent = frame

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, -16, 0, 22)
    title.Position = UDim2.fromOffset(8, 6)
    title.BackgroundTransparency = 1
    title.Text = "Fluffy Hub | Vox Seas (Fallback)"
    title.TextColor3 = Color3.fromRGB(240, 240, 255)
    title.Font = Enum.Font.GothamBold
    title.TextSize = 12
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Parent = frame

    local statsLbl = Instance.new("TextLabel")
    statsLbl.Size = UDim2.new(1, -16, 0, 18)
    statsLbl.Position = UDim2.fromOffset(8, 28)
    statsLbl.BackgroundTransparency = 1
    statsLbl.Text = "Streak:0 | Sold:0 | Cuan:+0G"
    statsLbl.TextColor3 = Color3.fromRGB(130, 225, 165)
    statsLbl.Font = Enum.Font.GothamMedium
    statsLbl.TextSize = 11
    statsLbl.TextXAlignment = Enum.TextXAlignment.Left
    statsLbl.Parent = frame
    FallbackStatsLabel = statsLbl

    local status = Instance.new("TextLabel")
    status.Size = UDim2.new(1, -16, 0, 32)
    status.Position = UDim2.fromOffset(8, 48)
    status.BackgroundTransparency = 1
    status.Text = "Status: Starting..."
    status.TextColor3 = Color3.fromRGB(180, 195, 220)
    status.Font = Enum.Font.Gotham
    status.TextSize = 11
    status.TextWrapped = true
    status.TextXAlignment = Enum.TextXAlignment.Left
    status.Parent = frame
    FallbackStatusLabel = status

    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, -16, 0, 30)
    btn.Position = UDim2.fromOffset(8, 90)
    btn.BackgroundColor3 = Color3.fromRGB(46, 170, 95)
    btn.TextColor3 = Color3.fromRGB(255, 255, 255)
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 12
    btn.Text = "Running (Click to Stop)"
    btn.Parent = frame
    FallbackToggleBtn = btn

    local btnCorner = Instance.new("UICorner")
    btnCorner.CornerRadius = UDim.new(0, 6)
    btnCorner.Parent = btn

    btn.MouseButton1Click:Connect(function()
        local nextState = not Config.Enabled
        setRunning(nextState)
        setStatus(nextState and "Resumed" or "Stopped by user")
    end)
end

-- Bersihkan sisa fallback UI lama lalu muat BeverlyLIB
pcall(function()
    local oldCore = CoreGui:FindFirstChild("BeverlyVoxShipwreckUI")
    if oldCore then oldCore:Destroy() end
end)
pcall(function()
    local p = getUIParent():FindFirstChild("BeverlyVoxShipwreckUI")
    if p then p:Destroy() end
end)

local okUI, uiErr = pcall(buildBeverlyLIB)
if okUI then
    Stats.UI = "BeverlyLIB"
else
    if Library then
        pcall(function() Library:Unload() end)
        Library = nil
        Window = nil
    end
    Stats.UI = "NativeFallback"
    Stats.UIError = tostring(uiErr)
    buildFallbackUI()
    updateStatsUI()
end
restoreExecutorContext()

-- Aktifkan Anti-AFK, FPS Booster & Black Screen sesuai Config
if Config.AntiAFK then
    setAntiAFK(true)
end
if Config.FPSBoost then
    setFPSBoost(true)
end
if Config.BlackScreen3D then
    setBlackScreen(true)
end

-- 1-second UI refresher + ScriptStatus heartbeat + Webhook watcher
task.spawn(function()
    while isLoopAlive() do
        updateStatsUI()
        if WH.Tick then
            pcall(WH.Tick)
        end
        task.wait(1)
    end
end)

-- Main dual-mode loop (Auto Shipwreck & Auto Side Quest saling eksklusif)
task.spawn(function()
    local function stepShipwreck()
        -- 1. Jika sedang bawa chest, langsung ke pintu Pawnshop & jual
        if isCarryingChest() then
            sellCarriedChest("Carried")
            task.wait(Config.LoopDelay)
            return
        end

        -- 2. Cek quest aktif: utamakan quest yang sudah di tahap Unearth/Guard, lalu Shipwreck, lalu TH terdekat
        local activeShipwrecks = getActiveShipwrecks()
        local activeHunts = getActiveTreasureHunts()

        if #activeHunts > 0 then
            local progress = QuestSystemClient:GetProgress()
            local firstHunt = activeHunts[1]
            local isProgressed = QuestsUtils.IsObjectiveActive(progress, TreasureHuntUtils.GetUnearthObjectiveId(firstHunt))
                or QuestsUtils.IsObjectiveActive(progress, TreasureHuntUtils.GetGuardObjectiveId(firstHunt))
            if isProgressed then
                if collectTreasureHuntChest(firstHunt) then
                    sellCarriedChest("TreasureHunt")
                end
                task.wait(Config.LoopDelay)
                return
            end
        end

        if #activeShipwrecks > 0 then
            if collectShipwreckChest(activeShipwrecks[1]) then
                sellCarriedChest("Shipwreck")
            end
            task.wait(Config.LoopDelay)
            return
        end

        if #activeHunts > 0 then
            if collectTreasureHuntChest(activeHunts[1]) then
                sellCarriedChest("TreasureHunt")
            end
            task.wait(Config.LoopDelay)
            return
        end

        -- 3. Tidak ada quest map aktif -> cek apakah masih ada quest map available & beli
        if not hasAvailableMapQuest() then
            setStatus("Semua map selesai / tidak ada quest map lagi")
            setActiveMode("None")
            return
        end

        local okBuy, result = buyAnyMap()
        if not okBuy then
            if result == "QuestLimit" or result == "NoMapReturned" or result == "NotEnoughGold" or result == "MaxParkAttempts" then
                setStatus("Berhenti: " .. tostring(result))
                setActiveMode("None")
            else
                setStatus("Gagal beli map: " .. tostring(result))
                task.wait(1.5)
            end
            return
        end

        task.wait(Config.LoopDelay)
    end

    while isLoopAlive() do
        local mode = getActiveMode()
        if mode == "None" then
            task.wait(0.3)
            continue
        end
        local runner = (mode == "LevelFarm") and LF.Step
            or ((mode == "SideQuest") and SQ.Step or stepShipwreck)
        local ok, err = xpcall(runner, debug.traceback)
        if not ok then
            Stats.ConsecutiveChests = 0
            Stats.Failures = Stats.Failures + 1
            Stats.LastError = tostring(err)
            getgenv()._AutoShipwreckLastError = tostring(err)
            logEvent("ERROR [" .. mode .. "]: " .. tostring(err):sub(1, 90))
            if mode == "LevelFarm" then
                LF.SetStatus("Error: " .. tostring(err):sub(1, 65))
            elseif mode == "SideQuest" then
                setSQStatus("Error: " .. tostring(err):sub(1, 65))
            else
                setStatus("Error: " .. tostring(err):sub(1, 65))
            end
            task.wait(2)
        end
    end
end)
