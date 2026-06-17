--// Discord: V | Roblox: Iamnoahbtw / Icarising

--[[
    NPC Dialogue System Overview
    
    Object-oriented dialogue system built around a class called dialogue.
    One instance is created when a player interacts with an NPC and destroyed when the conversation ends. 
    Includes:

  • Lock on type camera when in dialogue
  • NPC only tracks player if line of sight is clear
  • Typewriter text rendering via Defaultio's RichText module
  • Audio pooler to loop over sounds over and over instead of constantly creating new ones
  • PathfindingService with NPC movement with waypoints to let npcs move around during dialogue, resets back when finished.
  • BindableEvent based input system that stops dialogue till the function is fired, handling all input
  • CollectionService tagging so other systems know when a player is busy with dialogue
  • TweenService to smoothly rotate NPC to default position when done with dialogue
  • State handling, idle, typing, choosing, etc
     
    if there isn't enough API usage/comments as per stated beforehand please give me examples of what I could add/what would be accepted for my future referenc ty
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

--// Remotes, dont do anything because its a demo place

local QuestRemote = ReplicatedStorage:WaitForChild("Events"):WaitForChild("RemoteEvents"):WaitForChild("Quest")

--// Constants

local CameraOffset = Vector3.new(5, 4, 0) --// camera offset 
local MaxDistance = 25 --// if player is 25 studs from the npc, the dialogue box will close

local OpenTween = TweenInfo.new(0.6, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local ChoiceTween = TweenInfo.new(0.25, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)

local BasicStyle = "<AnimateStyle=Fade>" --// Text will fade in using the rich text module
local BasicFrequency = "<AnimateStepFrequency=2>" --// text will animate every 2 text character at once

--// State machine, what the dialogue system is currently doing, typing, waiting, etc

local States = {
    Idle = "IDLE",
    Typing = "TYPING",
    Waiting = "WAITING",
    Choosing = "CHOOSING",
    Closed = "CLOSED",
}

--// raycast params table used for both raycasting functions

local Params = RaycastParams.new()
Params.FilterType = Enum.RaycastFilterType.Exclude

--// SoundPool, makes an X amount of sounds and loops through them, avoids making a new sound and adding it every time because we loop through the same few sounds over and over again saving memory

local SoundPool = {}
SoundPool.__index = SoundPool

function SoundPool.new(size)
    --// creates a soundpool metatable
    --// adds "size" amount of sounds into the table
    --// index is the tracking variable for whatever sound its on in the list
    
    local self = setmetatable({}, SoundPool)
    self.Index = 1
    self.Sounds = {}

    for _ = 1, size do
        local s = Instance.new("Sound")
        s.SoundId = "rbxassetid://5416573471"
        s.Volume = 0.5
        s.PlaybackSpeed = math.random(95, 115) / 100 --// randomize speed for talking variation so its not constant
        s.Parent = workspace
        table.insert(self.Sounds, s)
    end

    return self
end

function SoundPool:Play(speed)
    local s = self.Sounds[self.Index]
    s.PlaybackSpeed = speed or 1
    s.TimePosition = 0 --// start at 0 incase an overlap occurs
    s:Play()

    self.Index = (self.Index % #self.Sounds) + 1 --// use modulus to calculate next sound using the remainder
end

local GlobalSoundPool = SoundPool.new(10)

--// Connection handles

local function trackConnection(tbl, conn)
    table.insert(tbl, conn) --// insert into the table of connections
end

local function disconnectAll(tbl)
    for _, c in ipairs(tbl) do c:Disconnect() end --// disconnect all connections in table
    table.clear(tbl) --// clear the table to set connections to nil
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

--// Constructor ffunction

function Dialogue.new(player: Player, guiParent: PlayerGui, npc: Model): DialogueClass
    local self = setmetatable({}, Dialogue)

    self.Player = player
    self.Character = player.Character
    self.NPC = npc

    --// Record npc starting cframe so when dialogue ends they reset to that position.
    
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

    --// CollectionService tag lets other scripts see if character is inn dialogue state 
    CollectionService:AddTag(self.Character, "InDialogue")

    self:Show()
    self:_setupCamera()
    self:_startDistanceCheck()
    self:_createDepthEffect()

    return self
end


--// Depth of Field effect to focus in on the character and npc and blur out everything else
--// slowly fades in with tweenservice

function Dialogue:_createDepthEffect()
    local dof = Instance.new("DepthOfFieldEffect")
    dof.FarIntensity = 0
    dof.NearIntensity = 0
    dof.InFocusRadius = 14
    dof.FocusDistance = 20
    dof.Parent = Lighting

    TweenService:Create(dof, TweenInfo.new(3.5), { FarIntensity = 0.45 }):Play()
    self.DepthEffect = dof
end

--// Raycast functions

local function hasLineOfSight(origin: Vector3, target: Vector3, exclude: {Instance}): boolean
    Params.FilterDescendantsInstances = exclude
    local result = workspace:Raycast(origin, target - origin, Params)
    return result == nil --// if nothing is in path between the origin and direction then true
end

local function findWallObstruction(origin: Vector3, target: Vector3, exclude: {Instance})
    Params.FilterDescendantsInstances = exclude
    return workspace:Raycast(origin, target - origin, Params) --// returns the ray
end


--// Lock on camera system, each frame:
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

        --// ill not take y value into account so as to not tilkt/updown
        local flatDir = Vector3.new(
            npcRoot.Position.X - charRoot.Position.X,
            0,
            npcRoot.Position.Z - charRoot.Position.Z
        ).Unit

        local idealPos = charRoot.Position + (-flatDir * 6) + CameraOffset

        --// If wall sits between the player and the ideal camera spot adjust move the camerain front of the wall slightly
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

function Dialogue:_trackPlayer()
    if not self.Character or not self.NPC then return end

    local c = self.Character.PrimaryPart
    local n = self.NPC.PrimaryPart
    if not c or not n then return end

    if self.Walking then return end --// if the npc is walking do not track the palyer as that would interfere with the pathfinding

    local eyeOffset = Vector3.new(0, 1.5, 0)
    local los = hasLineOfSight(n.Position + eyeOffset, c.Position + eyeOffset, { self.NPC, self.Character })

    if los then --// if the player character isnt behind a wall or something then face the character
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

        if (c.Position - n.Position).Magnitude > MaxDistance then --// wow hes beyond the max distance close the dialogue
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

        if ok then --// if the input is one of the above then disconnect the input function and fire the event
            conn:Disconnect()
            bind:Fire()
        end
    end)

    bind.Event:Wait() --// waits for event to fire before continuing
    bind:Destroy()
end


--// NPC Pathfinding

function Dialogue:moveNPCTo(pos)
    local hum = self.NPC:FindFirstChildOfClass("Humanoid")
    local root = self.NPC:FindFirstChild("HumanoidRootPart")
    if not hum or not root then return end

    if self.Walking then self.CancelMove = true end --// if they are already moving beforehand stop the last move to function called

    self.Walking = true
    self.CancelMove = false

    local path = PathfindingService:CreatePath()
    path:ComputeAsync(root.Position, pos)

    if path.Status ~= Enum.PathStatus.Success then --// if the plarth doesnt work just move to the position and wait
        hum:MoveTo(pos)
        hum.MoveToFinished:Wait(2)
        self.Walking = false
        return
    end

    for _, wp in ipairs(path:GetWaypoints()) do --// go through each waypoint the path made
        if self.CancelMove then  --// if true stop this functon
            self.Walking = false
            return
        end

        if wp.Action == Enum.PathWaypointAction.Jump then
            hum.Jump = true --// they jump if they need jump
        end

        hum:MoveTo(wp.Position)

        local finished = false
        local conn
        conn = hum.MoveToFinished:Connect(function() 
            finished = true
            conn:Disconnect()
        end)

        local timev = os.clock()
        while not finished do --// if the timer is above 2 seconds break this and move on to the next waypoint
            if os.clock() - timev > 2 then conn:Disconnect() break end
            task.wait()
        end
    end

    self.Walking = false --// they are no longer walking
end


--// Choice System
--// add buttons from the options table, wait for player input to see what they picked and continue

function Dialogue:_makeChoice(options)
    self.State = States.Choosing

    local buttons = {}
    local conns = {}
    local bind = Instance.new("BindableEvent")

    for i, v in ipairs(options) do
        local b = script.ChoiceBox:Clone() 
        b.Parent = self.ChoicesHolder --// parent choice to frame
        b.NameLabel.Text = v
        b.BackgroundTransparency = 1

        TweenService:Create(b, ChoiceTween, { BackgroundTransparency = 0.1 }):Play()

        conns[i] = b.MouseButton1Click:Connect(function() --// whatever i is, is the choice value, so 1,2,3,4
            GlobalSoundPool:Play(1)
            bind:Fire(i) --// player clicked choice i
        end)

        table.insert(buttons, b)
    end

    local res = bind.Event:Wait() --// returns the choice player picked

    --// disconnections all buttons functions, removes buttons from existance
    for _, c in ipairs(conns) do c:Disconnect() end
    for _, b in ipairs(buttons) do
        TweenService:Create(b, ChoiceTween, { BackgroundTransparency = 1 }):Play()
        Debris:AddItem(b, 0.3)
    end

    bind:Destroy()
    return res
end

function Dialogue:Show() --// tween dialogue up into view
    TweenService:Create(self.UI, TweenInfo.new(.5,Enum.EasingStyle.Back), { Position = UDim2.fromScale(0.082, 0.415) }  ):Play()
end

--// Say
--// lets the player skip the reveal early, then branches to choices or waits
--// for a plain advance input before returning control to the caller.

function Dialogue:Say(text, choices)
    if self.Destroyed then return end

    self.State = States.Typing
    self.NameLabel.Text = self.CurrentSpeaker
    self:_beginTypewrite(1) --// start sounds

    local obj = RichText:New(self.DialogueFrame, BasicStyle .. BasicFrequency .. text)
    local done = false

    
    task.spawn(function() --// wait for the next input, if the  text animation isnt done yet skip it.
        self:_waitForInput()
        if not done then obj:Show() end
    end)

    obj:Animate(true)
    done = true
    self:_stopTypewrite() --// remove sounds when animating is done

    local result

    if choices then --// if there is a choice table let the player choose one and return the result
        result = self:_makeChoice(choices)
    else
        self.State = States.Waiting
        self:_waitForInput() --// if there is no choice then simply wait for input again to progress
    end

    obj:Hide() --// hide the current text when done with
    self.State = States.Idle

    return result
end


function Dialogue:Sequence(lines)
    for _, v in ipairs(lines) do --// Runs multiple lines in sequence without having to repeatedly call :Say over and over
        self:Say(v)
    end
end

function Dialogue:_acceptQuest(id) --// doesnt do anything because mock place
    QuestRemote:FireServer({ QuestId = id })
end


function Dialogue:_resetNPC()
    --// Tweens NPC back to original position so if it went off somewhere with pathfinding it goes back and to make it face the drection it was originally facing
    local root = self.NPC and self.NPC:FindFirstChild("HumanoidRootPart")
    if not root then return end

    TweenService:Create(root,TweenInfo.new(1.2, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),{CFrame = self.rpos}):Play()
end

function Dialogue:Destroy() --// remove everything from the function
    if self.Destroyed then return end

    self.Destroyed = true
    self.State = States.Closed
--// stop camera, stop typewrting, make the npc go back, remove all existing connections, remove the dialogue tag from character,etc

    self:_stopTypewrite()
    self:_resetCamera()
    self:_resetNPC()
    disconnectAll(self.Connections)

    if self.Character then
        CollectionService:RemoveTag(self.Character, "InDialogue")
    end

    if self.DepthEffect then
        local t = TweenService:Create(self.DepthEffect, TweenInfo.new(2.25), { FarIntensity = 0 })
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

    local t = TweenService:Create(self.UI, OpenTween, { Position = UDim2.fromScale(0.082, 1.2) }) --// go back down out of view
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
