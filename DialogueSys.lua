--// Made by V / iamnoahbtw(Icarising)
--// Discord: V
--// Roblox: Iamnoahbtw / Icarising

local Dialogue = {}
Dialogue.__index = Dialogue

--// services

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local PathfindingService = game:GetService("PathfindingService")
local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")

--// modules

local RichText = require(script:WaitForChild("RichText"))

--// remotes

local Events = ReplicatedStorage:WaitForChild("Events")
local Remotes = Events:WaitForChild("RemoteEvents")
local QuestRemote = Remotes:WaitForChild("Quest")

--// CONSTANTS OGGMGMGGM

local CAMERA_OFFSET = Vector3.new(5, 4, 0)
local MAX_DISTANCE = 25

local OPEN_TWEEN = TweenInfo.new(0.6, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local CHOICE_TWEEN = TweenInfo.new(0.25, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)

local BASIC_STYLE = "<AnimateStyle=Fade>"
local BASIC_FREQUENCY = "<AnimateStepFrequency=2>"

--// STATES ( VERY IMPORTANT AND TUFF STATES OMG)

local STATES = {
    IDLE = "IDLE",
    TYPING = "TYPING",
    WAITING = "WAITING",
    CHOOSING = "CHOOSING",
    CLOSED = "CLOSED"
}

--// sound pool and class
--// this is so we can iterate through like 10 sounds over and over instead of making a new one each time 

--// class type definition

export type DialogueClass = {
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
    Say: (
        self: DialogueClass,
        text: string,
        choices: {string}?
    ) -> number?,

    Sequence: (
        self: DialogueClass,
        lines: {string}
    ) -> (),

    Show: (self: DialogueClass) -> (),
    Hide: (self: DialogueClass) -> (),
    Destroy: (self: DialogueClass) -> ()
}

local SoundPool = {}
SoundPool.__index = SoundPool

function SoundPool.new(size)
    local self = setmetatable({}, SoundPool)

    self.Index = 1
    self.Sounds = {}

    for _ = 1, size do
        local sound = Instance.new("Sound")
        sound.SoundId = "rbxassetid://5416573471"
        sound.Volume = 0.5
        sound.PlaybackSpeed = math.random(95,115)/100 --// add a bit of variation to the typing sound effect
        sound.Parent = workspace
        table.insert(self.Sounds, sound)
    end

    return self
end

function SoundPool:Play(speed)
    local sound = self.Sounds[self.Index]
    sound.PlaybackSpeed = speed or 1
    sound.TimePosition = 0
    sound:Play()

    self.Index += 1
    if self.Index > #self.Sounds then --// if index is out of bounds, reset it
        self.Index = 1
    end
end

local GlobalSoundPool = SoundPool.new(10)

--// connection functions

local function trackConnection(tbl, connection)
    table.insert(tbl, connection) --// add connection to ocnnections list
end

local function disconnectConnections(tbl) --// remove connections form conncetions list and clear the table 
    for _, c in ipairs(tbl) do
        c:Disconnect()
    end
    table.clear(tbl)
end

--// constructor function

function Dialogue.new(player: Player, guiParent: PlayerGui, npc: Model) : DialogueClass
    --// sets up the dialogue class and all its different variables, like what state it is in, current speaker, npc and player, etc
    
    local self = setmetatable({}, Dialogue)

    self.Player = player
    self.Character = player.Character
    self.NPC = npc

    local root = npc:WaitForChild("HumanoidRootPart")
    self.rpos = root.CFrame

    self.Destroyed = false
    self.Walking = false
    self.State = STATES.IDLE
    self.CurrentSpeaker = ""
    self.Connections = {}

    self.UI = script:WaitForChild("Holder"):Clone()
    self.UI.Parent = guiParent

    self.DialogueFrame = self.UI.Dialogue
    self.NameLabel = self.UI.NameBox.NameLabel
    self.ChoicesHolder = self.UI.Choices

    CollectionService:AddTag(self.Character, "InDialogue")

    self:Show()
    self:_setupCamera()
    self:_startDistanceCheck()
    self:_createDepthEffect()

    return self
end

--// depth of field focusing on the player and npc and blurring out everything else cuz its kinda cool and tuff

function Dialogue:_createDepthEffect()
    local dof = Instance.new("DepthOfFieldEffect")

    dof.FarIntensity = 0
    dof.NearIntensity = 0
    dof.InFocusRadius = 14
    dof.FocusDistance = 20
    dof.Parent = Lighting

    local tween = TweenService:Create(
        dof,
        TweenInfo.new(0.35),
        { FarIntensity = 0.45 }
    )

    tween:Play()
    self.DepthEffect = dof
end
--// camera lock-on system
--// overrides default Roblox camera to create a controlled cinematic dialogue view where player is focused on npc

function Dialogue:_setupCamera()

    local camera = workspace.CurrentCamera

    --//  we only run camera logic when both are valid
    if not self.NPC or not self.Character then return end

    local npcRoot = self.NPC.PrimaryPart
    local charRoot = self.Character.PrimaryPart
    if not npcRoot or not charRoot then return end

    --// switch to scriptable so Roblox default camera does not interfere
    camera.CameraType = Enum.CameraType.Scriptable

    local alpha = 0

    local connection
    connection = RunService.RenderStepped:Connect(function(dt)

        if self.Destroyed then connection:Disconnect() return end
        if not npcRoot.Parent or not charRoot.Parent then return end

        --// alpha controls smooth interpolation speed toward target camera position
        alpha = math.clamp(alpha + dt * 4, 0, 1)

        --// flat direction calculates horizontal vector from player to NPC
        --// Y axis is removed so camera does not tilt up/down when jumping or height differs
        local flatDirection = Vector3.new(
            npcRoot.Position.X - charRoot.Position.X,
            0,
            npcRoot.Position.Z - charRoot.Position.Z
        ).Unit

        --// offset pushes camera behind player depending on where npc is
        --// this is for an over the shoulder typa view
        local offset = (-flatDirection * 6) + CAMERA_OFFSET
        local cameraPosition = charRoot.Position + offset

        --// lookAt ensures camera always faces slightly above NPC torso/head area
        local target = CFrame.lookAt(
            cameraPosition,
            npcRoot.Position + Vector3.new(0, 2, 0)
        )

        --// lerp blends current camera toward target for smooth movement
        camera.CFrame = camera.CFrame:Lerp(target, alpha)
    end)

    --// store connection so it can be cleaned up when dialogue ends
    trackConnection(self.Connections, connection)
end


--// reset camera back to default Roblox control system

function Dialogue:_resetCamera()

    local camera = workspace.CurrentCamera
    camera.CameraType = Enum.CameraType.Custom

    --// restore camera control back to humanoid so player regains normal movement feel
    local hum = self.Character and self.Character:FindFirstChildOfClass("Humanoid")
    if hum then
        camera.CameraSubject = hum
    end
end


--// npc faces player during dialogue for immersion

function Dialogue:_trackPlayer()

    if not self.Character or not self.NPC then return end

    local c = self.Character.PrimaryPart
    local n = self.NPC.PrimaryPart
    if not c or not n then return end
    
    local dir = (c.Position - n.Position).Unit
    --// constructs look target so npc only rotates on Y axis and doesnt look up or down cuz thatd be bad
    local look = n.Position + Vector3.new(dir.X, 0, dir.Z)

    --// cant face player while walking
    if not self.Walking then
        n.CFrame = CFrame.lookAt(n.Position, look)
    end
end

--// distance check loop
--// continuously checks player-NPC distance to automatically close dialogue when out of range

function Dialogue:_startDistanceCheck()

    local connection

    connection = RunService.Heartbeat:Connect(function()

        --// make sure the class is still alive and the char and npc is 2
        if self.Destroyed then connection:Disconnect() return end
        if not self.Character or not self.NPC then return end

        local c = self.Character.PrimaryPart
        local n = self.NPC.PrimaryPart
        if not c or not n then return end

        --// keeps NPC facing player during active dialogue loop wow
        self:_trackPlayer()
        --// auto-close triggers when player  far away from npc
        if (c.Position - n.Position).Magnitude > MAX_DISTANCE then
            self:Hide()
        end
    end)

    trackConnection(self.Connections, connection)
end


--// UI pop up anim

function Dialogue:Show()

    TweenService:Create(
        self.UI,
        OPEN_TWEEN,
        { Position = UDim2.fromScale(0.082, 0.415) }
    ):Play()
end


function Dialogue:SetSpeaker(name)
    self.CurrentSpeaker = name --// whoever it is will appear when dialogue is called
end


--// typewriter audio system
--// runs independently of text animation so we can sync if player wants to click to skip text earier

function Dialogue:_beginTypewrite(speed)

    self.TypeThread = task.spawn(function()

        while task.wait(0.04 / speed) do
            if self.State ~= STATES.TYPING then break end --// if not typing just stsop
            GlobalSoundPool:Play(speed)
        end
    end)
end


function Dialogue:_stopTypewrite()
    if self.TypeThread then --// stop the thread yes
        task.cancel(self.TypeThread)
        self.TypeThread = nil
    end
end


--// input handler for advancing dialogue
--// supports all consoles

function Dialogue:_waitForInput()

    local bind = Instance.new("BindableEvent")

    local conn
    conn = UserInputService.InputBegan:Connect(function(input, gp)

        --// ignores UI-consuming inputs to prevent accidental skips
        if gp then return end

        local valid =
            input.KeyCode == Enum.KeyCode.Space
            or input.KeyCode == Enum.KeyCode.ButtonA
            or input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch

        if valid then
            conn:Disconnect()
            bind:Fire()
        end
    end)

    bind.Event:Wait()
    bind:Destroy()
end


--// npc path movement system
--// uses PathfindingService so npc can jump and walk around stuff if needed

function Dialogue:moveNPCTo(pos)

    local hum = self.NPC:FindFirstChildOfClass("Humanoid")
    local root = self.NPC:FindFirstChild("HumanoidRootPart")
    if not hum or not root then return end

    --// prevents overlapping movement calls from multiple dialogue states
    if self.Walking then
        self.CancelMove = true
    end

    self.Walking = true
    self.CancelMove = false

    local path = PathfindingService:CreatePath()
    path:ComputeAsync(root.Position, pos)

    --// fallback ensures NPC still moves even if path generation fails
    if path.Status ~= Enum.PathStatus.Success then
        hum:MoveTo(pos)
        hum.MoveToFinished:Wait(2)
        self.Walking = false
        return
    end

    for _, wp in ipairs(path:GetWaypoints()) do

        --// allows external interruption (cutscenes/dialogue state changes)
        if self.CancelMove then
            self.Walking = false
            return
        end

        --// handles vertical traversal like stairs or ledges
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

        local start = os.clock()

        while not finished do
            if os.clock() - start > 2 then
                conn:Disconnect()
                break
            end
            task.wait()
        end
    end

    self.Walking = false
end


--// choice system
--// lets player make a choice WOW

function Dialogue:_makeChoice(options)

    self.State = STATES.CHOOSING

    local buttons, conns = {}, {}

    --// bindable event that allows to see what button is pressed and stalls script till button is pressed
    local bind = Instance.new("BindableEvent")

    for i, v in ipairs(options) do

        local b = script.ChoiceBox:Clone()
        b.Parent = self.ChoicesHolder
        b.NameLabel.Text = v

        --// starts invisible so tween can smoothly introduce UI elements and its cool
        b.BackgroundTransparency = 1

        TweenService:Create(
            b,
            CHOICE_TWEEN,
            { BackgroundTransparency = 0.1 }
        ):Play()

        --// each button maps directly to an index return value
        conns[i] = b.MouseButton1Click:Connect(function()

            GlobalSoundPool:Play(1)
            bind:Fire(i) --// i is the choice the player made, so 1,2,3 etc
        end)

        table.insert(buttons, b)
    end

    --// stops execution until player makes a selection
    local res = bind.Event:Wait()

    --// disconnect things
    for _, c in ipairs(conns) do c:Disconnect() end
    for _, b in ipairs(buttons) do --// fading out buttons
        TweenService:Create(
            b,
            CHOICE_TWEEN,
            { BackgroundTransparency = 1 }
        ):Play()

        Debris:AddItem(b, 0.3)
    end

    return res
end


--// main dialogue function
--// handles text rendering, typewriter audio, skipping logic, choices, etc

function Dialogue:Say(text, choices)

    if self.Destroyed then return end

    self.State = STATES.TYPING
    self.NameLabel.Text = self.CurrentSpeaker --// sets name label to current speaker
    self:_beginTypewrite(1) --// begin sfx

    --// RichText handles per-character animation for each text label and stuff like coloring, animation style, etc.
    local obj = RichText:New(
        self.DialogueFrame,
        BASIC_STYLE .. BASIC_FREQUENCY .. text
    )

    local done = false

    --// separate thread listens for input so player can skip reveal animation and doesnt stop script
    task.spawn(function()
        self:_waitForInput()
        --// ensures full text is revealed if player skips mid-animation
        if not done then
            obj:Show()
        end
    end)

    --// begins animated reveal of text
    obj:Animate(true)
    --// marks animation as completed so skip logic doesn’t re-trigger reveal
    done = true

    self:_stopTypewrite()

    local result

    --// branching logic: either continue linear dialogue or enter choice state and see what choice the player made to branch dialogue off
    if choices then
        result = self:_makeChoice(choices)
    else
        self.State = STATES.WAITING
        self:_waitForInput()
    end

    --// hides text box before next dialogue step begins
    obj:Hide()
    self.State = STATES.IDLE

    return result
end


--// dialogue sequence if multiplie lines so i dont have to call say over and over

function Dialogue:Sequence(lines)
    for _, v in ipairs(lines) do
        self:Say(v)
    end
end


function Dialogue:_acceptQuest(id) --// doesent do anything because this is a demo place
    QuestRemote:FireServer({ QuestId = id })
end

--// npc reset (tweened)

function Dialogue:_resetNPC() --// return npc back to where there were before talkking to player
    local root = self.NPC and self.NPC:FindFirstChild("HumanoidRootPart")
    if not root then return end

    TweenService:Create(
        root,
        TweenInfo.new(1.2, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
        { CFrame = self.rpos }
    ):Play()
end

--// cleanup
--// removes all effects, hides ui, removes connections, removes depth of field, etc, clears ttales

function Dialogue:Destroy()
    if self.Destroyed then return end

    self.Destroyed = true
    self.State = STATES.CLOSED

    self:_stopTypewrite()
    self:_resetCamera()
    self:_resetNPC()

    disconnectConnections(self.Connections)

    if self.Character then
        CollectionService:RemoveTag(self.Character, "InDialogue")
    end

    if self.DepthEffect then
        local t = TweenService:Create(self.DepthEffect, TweenInfo.new(0.25), { FarIntensity = 0 })
        t:Play()
        t.Completed:Once(function()
            if self and self.DepthEffect then
                self.DepthEffect:Destroy()
            end
        end)
    end

    if self.UI then self.UI:Destroy() end
    table.clear(self)
    setmetatable(self, nil)
end

function Dialogue:Hide()
    if self.Destroyed then return end

    local t = TweenService:Create(self.UI, OPEN_TWEEN, {
        Position = UDim2.fromScale(0.082, 1.2)
    })

    t:Play()
    t.Completed:Once(function()
        self:Destroy()
    end)
end


local LookUps = {
    --// dialogue handler
    ["IcarisingWALK"] = function(d : DialogueClass)

        d:SetSpeaker("Icarising") --// set speaker

        --// small roaming behavior to make NPC feel alive
        --// pathing between random nearby points

        local root = d.NPC.PrimaryPart
        local origin = root.Position

        task.spawn(function()
            for _ = 1, 3 do
                local offset = Vector3.new(
                    math.random(-20,20),
                    0,
                    math.random(-20,20)
                )

                d:moveNPCTo(origin + offset)
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
    
    ["L1EGACY"] = function(dialogue : DialogueClass)

        dialogue:SetSpeaker("L1EGACY") --// set the speaker name

        dialogue:Sequence({
            "Hey, I have a favour to ask.",
            "I've been stuck here beating my bum husband for a while now.",
            "I'm busy beating him so I can't go to the market and get milk."
        }) --// go through dialogue in order

        local choice =
            dialogue:Say(
                "Can you grab milk from the market for me?",
                {
                    "Sure.",
                    "No."
                }
            )

        if choice == 1 then

            dialogue:Say"Thanks. Come back when you're done."
            dialogue:_acceptQuest"MilkDelivery"     

        else

            dialogue:Say"Alright then. I'll ask someone else."

        end

        dialogue:Hide()
    end,

    ["Icarising"] = function(dialogue : DialogueClass)

        dialogue:SetSpeaker("Icarising")
        dialogue:Sequence({
            "Things around here have been rough lately.",
            "Mainly because my wife keeps beating me.",
            "Please help me.",
        })

        dialogue:Hide()
    end
}


Dialogue.LookUps = LookUps

return Dialogue
