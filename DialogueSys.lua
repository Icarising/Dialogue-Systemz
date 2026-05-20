--// Discord: V | Roblox: Iamnoahbtw / Icarising

--[[
    NPC Dialogue System Overview
    
    Object-oriented dialogue system built around a single session dialouge class.
    One instance is created when a player interacts with an NPC and destroyed
    when the conversation ends. Systems included:
    
  • Scriptable camera with over-the-shoulder framing and wall avoidance
  • Raycasted NPC facing — NPC only tracks player if line of sight is clear
  • Typewriter text rendering via Defaultio's RichText module
  • Audio pooler to loop over sounds over and over
  • PathfindingService NPC movement with waypoint timeout guards
  • DepthOfFieldEffect for cinematic focus
  • BindableEvent-based choice system that yields until player selects
  • CollectionService tagging so other systems know when a player is busy
  • TweenService to smoothly rotate NPC to default position when done with dialogue
  • State machine (IDLE → TYPING → WAITING → CHOOSING → CLOSED)
     
    if there isn't enough API usage/comments as per stated beforehand please give me examples of what I could add/what would be accepted for my future  reference ty
--]]

local Dialogue = {}
Dialogue.__index = Dialogue

--// Services

local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local PathfindingService = game:GetService("PathfindingService")
local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")

--// Modules

local RichText = require(script:WaitForChild("RichText"))

--// Remotes

local QuestRemote = ReplicatedStorage:WaitForChild("Events"):WaitForChild("RemoteEvents"):WaitForChild("Quest")

--// Constants

local CameraOffset = Vector3.new(5, 4, 0) --// over-the-shoulder offset applied behind the player relative to NPC direction
local MaxDistance = 25 --// studs; dialogue auto-closes beyond this

local OpenTween = TweenInfo.new(0.6, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local ChoiceTween = TweenInfo.new(0.25, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)

local BasicStyle = "<AnimateStyle=Fade>"
local BasicFrequency = "<AnimateStepFrequency=2>"

--// State machine, what the dialogue system is currently doing, typing, waiting, etc

local States = {
    Idle = "IDLE",
    Typing = "TYPING",
    Waiting = "WAITING",
    Choosing = "CHOOSING",
    Closed = "CLOSED",
}

--// Shared global raycast params table 

local Params = RaycastParams.new()
Params.FilterType = Enum.RaycastFilterType.Exclude

--// SoundPool
--// Pre-allocates N sounds and cycles through them 
--// Avoids creating/destroying a Sound every character tick during typewriter 

local SoundPool = {}
SoundPool.__index = SoundPool

function SoundPool.new(size)
    local self = setmetatable({}, SoundPool)
    self.Index = 1
    self.Sounds = {}

    for _ = 1, size do
        local s = Instance.new("Sound")
        s.SoundId = "rbxassetid://5416573471"
        s.Volume = 0.5
        s.PlaybackSpeed = math.random(95, 115) / 100 --// slight random pitch spread so clicks feel organic
        s.Parent = workspace
        table.insert(self.Sounds, s)
    end

    return self
end

function SoundPool:Play(speed)
    local s = self.Sounds[self.Index]
    s.PlaybackSpeed = speed or 1
    s.TimePosition = 0 --// always restart so overlapping calls don't skip the attack
    s:Play()

    self.Index = (self.Index % #self.Sounds) + 1
end

local GlobalSoundPool = SoundPool.new(10)

--// Connection helpers
--// Every connection registers through these so Destroy() tears them all down
--// in one pass without hunting for scattered local variables.

local function trackConnection(tbl, conn)
    table.insert(tbl, conn)
end

local function disconnectAll(tbl)
    for _, c in ipairs(tbl) do c:Disconnect() end
    table.clear(tbl)
end

--// Definines dalogue class and its functions

type DialogueClass = {
    UI: ScreenGui,
    DialogueFrame: Frame,
    NameLabel: TextLabel,
    ChoicesHolder: Frame,
    Player: Player,
    Character: Model?,
    NPC: Model?,
    Destroyed: boolean,
    State: string,
    CurrentSpeaker: string,
    Connections: {RBXScriptConnection},
    TypeThread: thread?,

    SetSpeaker: (self: DialogueClass, name: string) -> (),
    Say: (self: DialogueClass, text: string, choices: {string}?) -> number?,
    Sequence: (self: DialogueClass, lines: {string}) -> (),
    Show: (self: DialogueClass) -> (),
    Hide: (self: DialogueClass) -> (),
    Destroy: (self: DialogueClass) -> (),
}

--// Constructor

function Dialogue.new(player: Player, guiParent: PlayerGui, npc: Model): DialogueClass
    local self = setmetatable({}, Dialogue)

    self.Player = player
    self.Character = player.Character
    self.NPC = npc

    --// Record NPC's starting CFrame so _resetNPC can tween it back exactly after the scene
    local root = npc:WaitForChild("HumanoidRootPart")
    self.rpos = root.CFrame

    self.Destroyed = false
    self.Walking = false
    self.State = States.Idle
    self.CurrentSpeaker = ""
    self.Connections = {}

    self.UI = script:WaitForChild("Holder"):Clone()
    self.UI.Parent = guiParent
    self.DialogueFrame = self.UI.Dialogue
    self.NameLabel = self.UI.NameBox.NameLabel
    self.ChoicesHolder = self.UI.Choices

    --// CollectionService tag lets other see if character in dialogue state 
    CollectionService:AddTag(self.Character, "InDialogue")

    self:Show()
    self:_setupCamera()
    self:_startDistanceCheck()
    self:_createDepthEffect()

    return self
end


--// Depth of Field
--// Tweens FarIntensity from 0 → 0.45 on open so background geometry gradually
--// blurs, keeping visual focus on the characters during the scene.
function Dialogue:_createDepthEffect()
    local dof = Instance.new("DepthOfFieldEffect")
    dof.FarIntensity = 0
    dof.NearIntensity = 0
    dof.InFocusRadius = 14
    dof.FocusDistance = 20
    dof.Parent = Lighting

    TweenService:Create(dof, TweenInfo.new(0.35), { FarIntensity = 0.45 }):Play()
    self.DepthEffect = dof
end

--// Raycast helpers
--// Both share the same sParams table instance and update FilterDescendantsInstances per-call so we always exclude the two characters involved.

--// Returns true if nothing blocking the pate

local function hasLineOfSight(origin: Vector3, target: Vector3, exclude: {Instance}): boolean
    Params.FilterDescendantsInstances = exclude
    local result = workspace:Raycast(origin, target - origin, Params)
    return result == nil
end

--// Returns the RaycastResult for the first wall between origin and target, or nil if clear.
--// Used by the camera to find geometry it needs to push away from.
local function findWallObstruction(origin: Vector3, target: Vector3, exclude: {Instance})
    Params.FilterDescendantsInstances = exclude
    return workspace:Raycast(origin, target - origin, Params)
end


--// Overrides the default camera for cinematic over-the-shoulder framing.
--// Each RenderStepped frame:
--// finds ideal position behind/above the player facing the NPC.
--// Raycasts player ideal position if a wall is hit, the camera is  pushed to just in front of the hit point so it never clips
--// Lerps toward the final position using an alpha that increases over time for a smooth tween when dialogue opens.

function Dialogue:_setupCamera()
    local camera = workspace.CurrentCamera
    if not self.NPC or not self.Character then return end

    local npcRoot = self.NPC.PrimaryPart
    local charRoot = self.Character.PrimaryPart
    if not npcRoot or not charRoot then return end

    camera.CameraType = Enum.CameraType.Scriptable

    local alpha = 0
    local exclude = { self.Character, self.NPC }

    local conn
    conn = RunService.RenderStepped:Connect(function(dt)
        if self.Destroyed then conn:Disconnect() return end
        if not npcRoot.Parent or not charRoot.Parent then return end

        alpha = math.clamp(alpha + dt * 4, 0, 1)

        --// ill not take y value into account so as to not tilkt/pdown
        local flatDir = Vector3.new(
            npcRoot.Position.X - charRoot.Position.X,
            0,
            npcRoot.Position.Z - charRoot.Position.Z
        ).Unit

        local idealPos = charRoot.Position + (-flatDir * 6) + CameraOffset

        --// If wall sits between the player and the ideal camera spot, slide the camera forward to just in front of the wall (.5 studs)
        local wallHit = findWallObstruction(charRoot.Position, idealPos, exclude)
        local finalPos = idealPos

        if wallHit then
            local padding = (charRoot.Position - wallHit.Position).Unit * 0.5
            finalPos = wallHit.Position + padding
        end

        local target = CFrame.lookAt(finalPos, npcRoot.Position + Vector3.new(0, 2, 0))
        camera.CFrame = camera.CFrame:Lerp(target, alpha)
    end)

    trackConnection(self.Connections, conn)
end

function Dialogue:_resetCamera()
    local camera = workspace.CurrentCamera
    camera.CameraType = Enum.CameraType.Custom

    local hum = self.Character and self.Character:FindFirstChildOfClass("Humanoid")
    if hum then camera.CameraSubject = hum end
end

--// NPC Facing
--// Rotates the NPC toward the player each frame, but only when:
--// The NPC isn't walking (avoids fighting the pathfinding system)
--// There's clear line of sight (NPC won't stare through walls)

function Dialogue:_trackPlayer()
    if not self.Character or not self.NPC then return end

    local c = self.Character.PrimaryPart
    local n = self.NPC.PrimaryPart
    if not c or not n then return end

    if self.Walking then return end

    local eyeOffset = Vector3.new(0, 1.5, 0)
    local los = hasLineOfSight(n.Position + eyeOffset, c.Position + eyeOffset, { self.NPC, self.Character })

    if los then
        local dir = (c.Position - n.Position).Unit
        n.CFrame = CFrame.lookAt(n.Position, n.Position + Vector3.new(dir.X, 0, dir.Z))
    end
end


--// Distance Monitorusing runservice to check distance every physics step, if too far, close dialogue

function Dialogue:_startDistanceCheck()
    local conn
    conn = RunService.Heartbeat:Connect(function()
        if self.Destroyed then conn:Disconnect() return end
        if not self.Character or not self.NPC then return end

        local c = self.Character.PrimaryPart
        local n = self.NPC.PrimaryPart
        if not c or not n then return end

        self:_trackPlayer()

        if (c.Position - n.Position).Magnitude > MaxDistance then
            self:Hide()
        end
    end)

    trackConnection(self.Connections, conn)
end

--// UI / Speaker

function Dialogue:SetSpeaker(name)
    self.CurrentSpeaker = name
end

--// Typewriter Audio
--// Spawns a looping thread that fires a pooled sound every 0.04s while typing.
--// Cancelled the moment state changes so audio never outlives the text.

function Dialogue:_beginTypewrite(speed)
    self.TypeThread = task.spawn(function()
        while task.wait(0.04 / speed) do
            if self.State ~= States.Typing then break end
            GlobalSoundPool:Play(speed)
        end
    end)
end

function Dialogue:_stopTypewrite()
    if self.TypeThread then
        task.cancel(self.TypeThread)
        self.TypeThread = nil
    end
end

--// Input Wait
--// BindableEvent as a one-shot signal so the thread truly yields with zero
--// busy-wait overhead instead of polling a boolean flag.

function Dialogue:_waitForInput()
    local bind = Instance.new("BindableEvent")
    local conn

    conn = UserInputService.InputBegan:Connect(function(input, gp)
        if gp then return end

        local ok =
            input.KeyCode == Enum.KeyCode.Space
            or input.KeyCode == Enum.KeyCode.ButtonA
            or input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch

        if ok then
            conn:Disconnect()
            bind:Fire()
        end
    end)

    bind.Event:Wait()
    bind:Destroy()
end


--// NPC Pathfinding
--// PathfindingService so the NPC navigates around obstacles.
--// Each waypoint has a 2s timeout guard so a stall can't freeze it forever.

function Dialogue:moveNPCTo(pos)
    local hum = self.NPC:FindFirstChildOfClass("Humanoid")
    local root = self.NPC:FindFirstChild("HumanoidRootPart")
    if not hum or not root then return end

    if self.Walking then self.CancelMove = true end

    self.Walking = true
    self.CancelMove = false

    local path = PathfindingService:CreatePath()
    path:ComputeAsync(root.Position, pos)

    if path.Status ~= Enum.PathStatus.Success then
        hum:MoveTo(pos)
        hum.MoveToFinished:Wait(2)
        self.Walking = false
        return
    end

    for _, wp in ipairs(path:GetWaypoints()) do
        if self.CancelMove then
            self.Walking = false
            return
        end

        if wp.Action == Enum.PathWaypointAction.Jump then
            hum.Jump = true
        end

        hum:MoveTo(wp.Position)

        local finished = false
        local conn
        conn = hum.MoveToFinished:Connect(function()
            finished = true
            conn:Disconnect()
        end)

        local timev = os.clock()
        while not finished do
            if os.clock() - timev > 2 then conn:Disconnect() break end
            task.wait()
        end
    end

    self.Walking = false
end


--// Choice System
--// Builds buttons from the options table, fades them in, then statlls on a BindableEvent until the player clicks one

function Dialogue:_makeChoice(options)
    self.State = States.Choosing

    local buttons = {}
    local conns = {}
    local bind = Instance.new("BindableEvent")

    for i, v in ipairs(options) do
        local b = script.ChoiceBox:Clone()
        b.Parent = self.ChoicesHolder
        b.NameLabel.Text = v
        b.BackgroundTransparency = 1

        TweenService:Create(b, ChoiceTween, { BackgroundTransparency = 0.1 }):Play()

        conns[i] = b.MouseButton1Click:Connect(function()
            GlobalSoundPool:Play(1)
            bind:Fire(i)
        end)

        table.insert(buttons, b)
    end

    local res = bind.Event:Wait()

    for _, c in ipairs(conns) do c:Disconnect() end
    for _, b in ipairs(buttons) do
        TweenService:Create(b, ChoiceTween, { BackgroundTransparency = 1 }):Play()
        Debris:AddItem(b, 0.3)
    end

    bind:Destroy()
    return res
end

function Dialogue:Show()
    TweenService:Create(self.UI, TweenInfo.new(.5,Enum.EasingStyle.Back), { Position = UDim2.fromScale(0.082, 0.415) }  ):Play()
end

--// Say, makes  a line through RichText, runs typewriter SFX in a side thread,
--// lets the player skip the reveal early, then branches to choices or waits
--// for a plain advance input before returning control to the caller.

function Dialogue:Say(text, choices)
    if self.Destroyed then return end

    self.State = States.Typing
    self.NameLabel.Text = self.CurrentSpeaker
    self:_beginTypewrite(1)

    local obj = RichText:New(self.DialogueFrame, BasicStyle .. BasicFrequency .. text)
    local done = false

    --// Side thread listens for skip input independently so the animation isn't blocked
    task.spawn(function()
        self:_waitForInput()
        if not done then obj:Show() end
    end)

    obj:Animate(true)
    done = true
    self:_stopTypewrite()

    local result

    if choices then
        result = self:_makeChoice(choices)
    else
        self.State = States.Waiting
        self:_waitForInput()
    end

    obj:Hide()
    self.State = States.Idle

    return result
end

--// Runs multiple lines in sequence without the caller repeating Say() calls
function Dialogue:Sequence(lines)
    for _, v in ipairs(lines) do
        self:Say(v)
    end
end

function Dialogue:_acceptQuest(id)
    QuestRemote:FireServer({ QuestId = id })
end

--// Tweens the NPC back to its pre-dialogue CFrame so it doesn't stay wherever pathfinding left it
function Dialogue:_resetNPC()
    local root = self.NPC and self.NPC:FindFirstChild("HumanoidRootPart")
    if not root then return end

    TweenService:Create(root,TweenInfo.new(1.2, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),{CFrame = self.rpos}):Play()
end

function Dialogue:Destroy()
    if self.Destroyed then return end

    self.Destroyed = true
    self.State = States.Closed

    self:_stopTypewrite()
    self:_resetCamera()
    self:_resetNPC()
    disconnectAll(self.Connections)

    if self.Character then
        CollectionService:RemoveTag(self.Character, "InDialogue")
    end

    if self.DepthEffect then
        local t = TweenService:Create(self.DepthEffect, TweenInfo.new(0.25), { FarIntensity = 0 })
        t:Play()
        t.Completed:Once(function()
            if self.DepthEffect then self.DepthEffect:Destroy() end
        end)
    end

    if self.UI then self.UI:Destroy() end
    table.clear(self)
    setmetatable(self, nil)
end

function Dialogue:Hide()
    if self.Destroyed then return end

    local t = TweenService:Create(self.UI, OpenTween, { Position = UDim2.fromScale(0.082, 1.2) })
    t:Play()
    t.Completed:Once(function()
        self:Destroy()
    end)
end

--// Dialogue Handlers maps an npC tag to its full conversaion function.

local LookUps = {

    ["IcarisingWALK"] = function(d: DialogueClass)
        d:SetSpeaker("Icarising")

        --// Wmove the NPC between a few random nearby points while talkin
        
        local origin = d.NPC.PrimaryPart.Position
        task.spawn(function()
            for _ = 1, 3 do
                d:moveNPCTo(origin + Vector3.new(math.random(-20, 20), 0, math.random(-20, 20)))
                task.wait(1)
            end
        end)

        d:Sequence({
            "I just walk around sometimes.",
            "Helps me think, or something like that...",
            "Then I like magically teleport back to my original spot, I have powers like that.",
            "My teleportation and floating is a secret untold method you'll never know...",
            "Well actually, maybe I can teach you someday, but scram for now, loser."
        })

        d:Hide()
    end,

    ["L1EGACY"] = function(dialogue: DialogueClass)
        dialogue:SetSpeaker("L1EGACY")

        dialogue:Sequence({
            "Hey, I have a favour to ask.",
            "I've been stuck here beating my bum husband for a while now.",
            "I'm busy beating him so I can't go to the market and get milk.",
        })

        local choice = dialogue:Say(
            "Can you grab milk from the market for me?",
            { "Sure.", "No." }
        )

        if choice == 1 then
            dialogue:Say("Thanks. Come back when you're done.")
            dialogue:_acceptQuest("MilkDelivery")
        else
            dialogue:Say("Alright then. I'll ask someone else.")
        end

        dialogue:Hide()
    end,

    ["Icarising"] = function(dialogue: DialogueClass)
        dialogue:SetSpeaker("Icarising")

        dialogue:Sequence({
            "Things around here have been rough lately.",
            "Mainly because my wife keeps beating me.",
            "Please help me.",
        })

        dialogue:Hide()
    end,
}

Dialogue.LookUps = LookUps

return Dialogue
