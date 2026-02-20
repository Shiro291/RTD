local replicatedstorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")

-- Use user's preferred library
local library = loadstring(game:HttpGet('https://raw.githubusercontent.com/Shiro291/RTD/refs/heads/main/library'))()

local bytenet = require(replicatedstorage:WaitForChild("Teawork"):WaitForChild("Shared"):WaitForChild("Services"):WaitForChild("ByteNetworking"))

-- Internal Module State (Encapsulated)
local api = {}
local state = {
    timer = 0,
    waveinfo = 1,
    isroundover = false,
    totalplacedtowers = 0,
    firsttower = 1,
    TimerConnection = nil,
    Window = nil,
    Logs = nil,
    LogLabel = nil
}

--// Helper Functions
local function updatelog(text)
    if state.Logs then
        state.Logs:AppendText(DateTime.now():FormatLocalTime("HH:mm:ss", "en-us") .. ":", text)
        state.LogLabel:SetText("Last Log: " .. text)
    end
    
    -- Notification for major events
    if text:match("started") or text:match("restart") or text:match("Skipping") then
        StarterGui:SetCore("SendNotification", {
            Title = "Macro Player",
            Text = text,
            Duration = 3
        })
    end
end

local function waitTime(time, wave)
    while state.waveinfo < wave and not state.isroundover do
        task.wait(0.05)
    end
    
    if time <= 0 then return not state.isroundover end
    
    while state.timer < time and not state.isroundover do
        task.wait(0.05)
    end
    return not state.isroundover
end

--// API Methods
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

-- Early exit for loadstring usage check
if game.PlaceId ~= 124069847780670 then return api end

-- Initialize UI only if we are in the game place
function api:InitUI()
    if state.Window then return end -- Already init
    
    state.Window = library:CreateWindow({
        Title = "Macro Player",
        Size = UDim2.new(0, 350, 0, 370),
        Position = UDim2.new(0.5, 0, 0, 70),
        NoResize = false
    })
    state.Window:Center()

    local logtab = state.Window:CreateTab({
        Name = "Player",
        Visible = true
    })

    state.LogLabel = logtab:Label({
        Label = "Last Log: Ready"
    })
    
    -- Minimal Mode Button
    logtab:Button({
        Text = "Minimize UI",
        Callback = function()
            state.Window:SetVisible(false)
            StarterGui:SetCore("SendNotification", {
                Title = "Macro Player",
                Text = "UI Minimized. Press RightControl to toggle (if keybind set) or rejoin to reset.",
                Duration = 5
            })
        end
    })

    local logstab = state.Window:CreateTab({
        Name = "Logs",
        Visible = true
    })
    
    state.Logs = logstab:Console({
        Text = "",
        ReadOnly = true,
        MaxLines = 200
    })
    
    state.Window:ShowTab(logtab)
end

function api:Start()
    self:InitUI()
    bytenet.Timescale.SetTimescale.send(2)

    local mapinfo = replicatedstorage.RoundInfo
    state.waveinfo = mapinfo:GetAttribute("Wave") or 1
    state.timer = 0
    
    -- Cleanup previous connection
    if state.TimerConnection then state.TimerConnection:Disconnect() end

    mapinfo:GetAttributeChangedSignal("Wave"):Connect(function()
        state.waveinfo = mapinfo:GetAttribute("Wave")
    end)

    local roundresultui = game:GetService("Players").LocalPlayer.PlayerGui.GameUI.RoundResult
    roundresultui:GetPropertyChangedSignal("Visible"):Connect(function()
        state.isroundover = roundresultui.Visible
        if state.isroundover and state.TimerConnection then
            state.TimerConnection:Disconnect()
            state.TimerConnection = nil
        end
    end)
    
    updatelog("Macro started")
    
    -- Use Heartbeat for consistent timing
    state.TimerConnection = RunService.Heartbeat:Connect(function(dt)
        if not state.isroundover then
            state.timer = state.timer + (dt * 2) 
        end
    end)
end

function api:Loop(func)
    if game.PlaceId ~= 124069847780670 then return end 
    task.spawn(function()
        while not state.isroundover do
            func()
            task.wait(0.03)
        end
    end)
end

function api:Difficulty(diff)
    updatelog("Voted difficulty " .. tostring(diff))
    bytenet.DifficultyVote.Vote.send(diff)
    
    local mapinfo = replicatedstorage.RoundInfo
    while #mapinfo:GetAttribute("Difficulty") == 0 do task.wait(0.05) end 
    
    -- Reset timer
    state.timer = 0
    state.waveinfo = 1
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
        state.totalplacedtowers = state.totalplacedtowers + 1
        
        updatelog("Placed Tower " .. tostring(tower))
        bytenet.Towers.PlaceTower.invoke({["Position"] = position, ["Rotation"] = 0, ["TowerID"] = tower})
    end
end

function api:Upgrade(tower, time, wave)
    if waitTime(time, wave) then
        updatelog("Upgraded Tower " .. tostring(tower))
        
        local realindex = state.firsttower + (tower - 1)
        bytenet.Towers.UpgradeTower.invoke(realindex)
    end
end

function api:SetTarget(tower, target, time, wave)
    if waitTime(time, wave) then
        updatelog("Changed Tower " .. tostring(tower) .. " Target to " .. tostring(target))
    
        local realindex = state.firsttower + (tower - 1)
        bytenet.Towers.SetTargetMode.send({["UID"] = (realindex), ["TargetMode"] = target})
    end
end

function api:Sell(tower, time, wave)
    if waitTime(time, wave) then
        updatelog("Sold Tower " .. tostring(tower)) 
        
        local realindex = state.firsttower + (tower - 1)
        bytenet.Towers.SellTower.invoke(realindex)
    end
end

function api:PlayAgain()
    while not state.isroundover do task.wait(0.1) end
    
    state.firsttower = 1 
    state.totalplacedtowers = 0
    
    state.timer = 0
    state.waveinfo = 1
    
    if state.TimerConnection then state.TimerConnection:Disconnect() end
    state.TimerConnection = nil

    task.wait(1)
    
    bytenet.RoundResult.VoteForRestart.send(true)
    updatelog("Voted for restart")
end

return api