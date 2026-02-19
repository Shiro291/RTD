local replicatedstorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- Use the library URL from user
local library = loadstring(game:HttpGet('https://raw.githubusercontent.com/Shiro291/RTD/refs/heads/main/library'))()

local bytenet = require(replicatedstorage:WaitForChild("Teawork"):WaitForChild("Shared"):WaitForChild("Services"):WaitForChild("ByteNetworking"))

local api = {}

--// Internal State
local towers = bytenet.Towers
local mapinfo = replicatedstorage.RoundInfo
local roundresultui = game:GetService("Players").LocalPlayer.PlayerGui.GameUI.RoundResult

local env = getgenv()
env.StratName = "Strat"
env.timer = 0
env.waveinfo = 1
env.isroundover = false
env.totalplacedtowers = 0
-- Correct starting value for firsttower
env.firsttower = 1

--// Fixed Timer Logic
local TimerConnection = nil

function api:Loadout(towers_list)
    if game.PlaceId ~= 98936097545088 then return end
    for i, towerId in ipairs(towers_list) do
        bytenet.Inventory.EquipTower.invoke({["TowerID"] = towerId, ["Slot"] = i})
        task.wait(0.5)
    end
end

function api:Map(map, modifiers)
    if game.PlaceId ~= 98936097545088 then return end
    bytenet.MatchmakingNew.CreateSingleplayer.invoke({
        ["Gamemode"] = "Standard", 
        ["MapID"] = map, 
        ["Modifiers"] = modifiers
    })
end

-- Allow returning for loadstring usage
if game.PlaceId ~= 124069847780670 then return api end

--// Helper Functions
local function updatelog(text)
    -- Assuming this function exists in the macro scope or is global
    -- If not, we can print or ignore
    if getgenv().updatelog then getgenv().updatelog(text) end
    -- print("[Macro]: " .. text)
end

local function waitTime(time, wave)
    while env.waveinfo < wave and not env.isroundover do
        task.wait(0.05)
    end
    -- Use a small tolerance for "instant" actions if time is 0
    if time <= 0 then return not env.isroundover end
    
    -- Using env.timer which is updated by Heartbeat
    while env.timer < time and not env.isroundover do
        task.wait(0.05)
    end
    return not env.isroundover
end

function api:Start()
    bytenet.Timescale.SetTimescale.send(2)

    env.waveinfo = mapinfo:GetAttribute("Wave") or 1
    env.timer = 0
    
    -- Cleanup previous connection
    if TimerConnection then TimerConnection:Disconnect() end

    mapinfo:GetAttributeChangedSignal("Wave"):Connect(function()
        env.waveinfo = mapinfo:GetAttribute("Wave")
    end)

    roundresultui:GetPropertyChangedSignal("Visible"):Connect(function()
        env.isroundover = roundresultui.Visible
        if env.isroundover and TimerConnection then
            TimerConnection:Disconnect()
            TimerConnection = nil
        end
    end)
    
    updatelog("Game Started")
    
    -- Use Heartbeat for consistent timing
    -- 2x speed means we increment timer by dt * 2
    TimerConnection = RunService.Heartbeat:Connect(function(dt)
        if not env.isroundover then
            -- Check if game is paused? For now assume always running
            env.timer = env.timer + (dt * 2) 
        end
    end)
end

function api:Loop(func)
    if game.PlaceId ~= 124069847780670 then return end 
    task.spawn(function()
        while not env.isroundover do
            func()
            task.wait(0.03)
        end
    end)
end

function api:Difficulty(diff)
    updatelog("Voted difficulty " .. tostring(diff))
    bytenet.DifficultyVote.Vote.send(diff)
    
    while #mapinfo:GetAttribute("Difficulty") == 0 do task.wait(0.05) end 
    
    -- Reset timer on difficulty select (actual game start)
    env.timer = 0
    env.waveinfo = 1
    task.wait(0.1)
end

function api:Ready(time, wave)
    if waitTime(time, wave) then 
        updatelog("Sent ready vote") 
        bytenet.ReadyVote.Vote.send(true) 
    end
end

function api:Skip(time, wave)
    if waitTime(time, wave) then 
        updatelog("Skipping Wave " .. tostring(wave)) 
        replicatedstorage:WaitForChild("ByteNetReliable"):FireServer(buffer.fromstring("\148\001")) 
    end
end

function api:AutoSkip(enable, time, wave)
    if waitTime(time, wave) then 
        updatelog("AutoSkip set to " .. tostring(enable)) 
        bytenet.SkipWave.ToggleAutoSkip.send(enable) 
    end
end

function api:Place(tower, position, time, wave)
    if waitTime(time, wave) then    
        env.totalplacedtowers = env.totalplacedtowers + 1
        
        updatelog("Placed Tower " .. tostring(tower))
        towers.PlaceTower.invoke({["Position"] = position, ["Rotation"] = 0, ["TowerID"] = tower})
    end
end

function api:Upgrade(tower, time, wave)
    if waitTime(time, wave) then
        updatelog("Upgraded Tower " .. tostring(tower))
        
        -- Correctly calculate real index based on current session's first tower
        local realindex = env.firsttower + (tower - 1)
        towers.UpgradeTower.invoke(realindex)
    end
end

function api:SetTarget(tower, target, time, wave)
    if waitTime(time, wave) then
        updatelog("Changed Tower " .. tostring(tower) .. " Target to " .. tostring(target))
    
        local realindex = env.firsttower + (tower - 1)
        towers.SetTargetMode.send({["UID"] = (realindex), ["TargetMode"] = target})
    end
end

function api:Sell(tower, time, wave)
    if waitTime(time, wave) then
        updatelog("Sold Tower " .. tostring(tower)) 
        
        local realindex = env.firsttower + (tower - 1)
        towers.SellTower.invoke(realindex)
    end
end

function api:PlayAgain()
    while not env.isroundover do task.wait(0.1) end
    
    -- Fix for Tower Index Drift
    -- If the game resets the map/towers on restart, we should reset our counters
    env.firsttower = 1 
    env.totalplacedtowers = 0
    
    env.timer = 0
    env.waveinfo = 1
    
    -- Reset connection
    if TimerConnection then TimerConnection:Disconnect() end
    TimerConnection = nil

    task.wait(1)
    
    bytenet.RoundResult.VoteForRestart.send(true)
    updatelog("Voted for restart")
end

return api