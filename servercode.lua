
--// SERVERRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRR


local Moves = { --// moves id
	Skating = 11659342027;
	Spear = 11663369297;
	Spikes = 11668805687;
	Age = 11668805687;
	
}

--// set stuff

local IdleId = 11533126658
local TS = game:GetService("TweenService")
local Rep = game:GetService("ReplicatedStorage")
local CS = require(Rep.RevampedCSModule)
local Basics = require(Rep.CombatBasics)
local FX = Rep:WaitForChild("Fruits")
local Swords = FX:WaitForChild("Assets")
local Main = Swords:WaitForChild("Ice")
local Danim = nil

function SetIdle()
	--// CoreMoment
end
--// back to used stuff

local ZAnim = nil
local RushAnim = 11644498439

script.Parent.OnServerEvent:Connect(function(plr,act)
	
	local c = plr.Character
	local root = c.HumanoidRootPart
	local hum = c:FindFirstChildOfClass("Humanoid")
    if hum.Health <= 0 then return end 
    --// return if dead 
	if act == "Z" then
        if CS:HasTag(c,"A") or CS:HasTag(c,"Surfin") or  CS:HasTag(c,"S") or CS:HasTag(c,"IEx") or plr.Cooldowns:FindFirstChild("Ice surf") then return end --//if stun or cd stop function
        
		Rep.Remotes.CFX:FireClient(plr,"ShakeCam","Vibration")--// camshake

		Basics.SkillCD(plr,"Ice surf",35)
		local staphed = false
		local Anim = Basics.MakeAnim(hum,Moves.Skating)
		Anim:Play()
		
		task.delay(.9,function() 
			if staphed == true then Anim:Stop()  return end --// stop anim if stopped after .9
			Anim:AdjustSpeed(0)
			Anim.TimePosition = .9 --// freeze anim
			repeat task.wait(.1) until CS:HasTag(c,"Surfin") ==false
			Anim:AdjustSpeed(1)
			Anim:Stop() --//stop anim
        end)
        
        --// stun states
        
		CS:AddTag(c,"JP0")
		CS:AddTag(c,"A")
		CS:AddTag(c,"CR")
        CS:AddTag(c,"Surfin")
        
		Rep.Remotes.CFX:FireAllClients("ModuleAction","Ice","Skate",{c}) --// cleint fx
		
		repeat task.wait(.05) 
			local S = Basics.MakeSound(632919727,root,0,1,false,2)
			S:Play()
			
			game.Debris:AddItem(S,S.TimeLength)
        until CS:HasTag(c,"Surfin") == false
        --// stop surf
        
		staphed = true
		CS:RemoveTag(c,"CR")
		CS:RemoveTag(c,"Surfin")
		CS:RemoveTag(c,"A")
		CS:RemoveTag(c,"JP0")
	elseif act == "SurfR" then
		CS:RemoveTag(c,"Surfin") --// stop sruf
	elseif act == "SpearX" then
		CS:RemoveTag(c,"Spearin") --// stop spear
	elseif act == "X" then
		if CS:HasTag(c,"A") or CS:HasTag(c,"Spearin") or  CS:HasTag(c,"S") or CS:HasTag(c,"IEx") or plr.Cooldowns:FindFirstChild("Ice spear") then return end --// cds

		Basics.SkillCD(plr,"Ice spear",7.75)
		
		local staphed = false
		local Anim = Basics.MakeAnim(hum,Moves.Spear)
		Anim:Play()

        
        --// add stun states
		CS:AddTag(c,"JP0")
		CS:AddTag(c,"A")
		CS:AddTag(c,"WS0")
		CS:AddTag(c,"CR")
		CS:AddTag(c,"Spearcin") --// Client sided crap for fx
		CS:AddTag(c,"Spearin")
		

		Rep.Remotes.CFX:FireAllClients("ModuleAction","Ice","Spearit",{c}) --// client fx 
		
		local S = Basics.MakeSound(632919727,c,0,2)
		S:Play()

		game.Debris:AddItem(S,S.TimeLength)
		task.wait(1.2)

		
		Anim.TimePosition = 1.2
		Anim:AdjustSpeed(0)
		Anim.TimePosition = 1.2

		task.wait(.1)
		
	
        repeat task.wait(.01) until CS:HasTag(c,"Spearin") ==false or CS:HasTag(c,"IEx") == true --// checks till player is not spearin
        
        Anim:AdjustSpeed(1)	
        --// remove stun states
		CS:RemoveTag(c,"JP0")
		CS:RemoveTag(c,"A")
		CS:RemoveTag(c,"WS0")
		CS:RemoveTag(c,"CR")
		CS:RemoveTag(c,"Spearin")

		CS:RemoveTag(c,"Spearcin")

		local S = Basics.MakeSound(747238556,c,0,2)
		S:Play()

		game.Debris:AddItem(S,S.TimeLength)

		
		local S = Basics.MakeSound(9039298484,c,0,2)
		S:Play()

		game.Debris:AddItem(S,S.TimeLength)
        task.wait(.03)
        --// effects
        
		local Spear = Main.IceStick:Clone()
		Spear.CanCollide = false
		Spear.Massless = true
		Spear.Anchored = true
		Spear.Transparency = 0
		Spear.Size = Vector3.new(4.6,.35,.15)
		Spear.Parent = workspace.FX
		Spear.CFrame =  root.CFrame * CFrame.new(1.5,.5,-5) * CFrame.Angles(0,math.rad(90),0) 
		
		for i,v in pairs(Spear.Summon:GetChildren()) do --// replay cool effect for shoot this time
			v:Emit(v:GetAttribute("EmitCount") or 10)
		end

		
		if CS:HasTag(c,"IEx") then return Spear:Destroy() end
		Rep.Remotes.CFX:FireClient(plr,"ShakeCam","Explosion") --// function

		TS:Create(Spear,TweenInfo.new(1),{CFrame =  root.CFrame * CFrame.new(1.5,.5,-100) * CFrame.Angles(0,math.rad(90),0);Transparency = .5;}):Play()
		game.Debris:AddItem(Spear,1.02)
		Spear:FindFirstChildOfClass("Trail").Enabled = true
		
        local comp = false
        --// projectile hitbox
		for i = 1,100 do
			if comp == true then break end
			local Params = OverlapParams.new()
			Params.FilterType = Enum.RaycastFilterType.Blacklist
			Params.FilterDescendantsInstances = {workspace.FX,workspace.Camera,c,Spear}
			
			local hb = workspace:GetPartBoundsInBox(Spear.CFrame,Vector3.new(5,10,20),Params)

			for i,v in pairs(hb) do
				if v.Name == "HumanoidRootPart" and Basics.Attackable(v.Parent) then --// check humrp only so hitbox activates once and if humanoid is attackable
					local c2 = v.Parent
					local Damaged =  Basics.Damage(plr,c2,Basics.CalculateDmg(17.5,hum,c2:FindFirstChildOfClass("Humanoid")),"Projectile",true,1,2) --// see if damaged and calc damage based on buffs/debuffs
					if Damaged == true then
						local S = Basics.MakeSound(5961220911,c2,0,3.25) --// sfx
						S:Play()
						Spear:Destroy() --// destroy spear immediatley
						comp = true --// stop function from running again
						
					
						game.Debris:AddItem(S,S.TimeLength)
						
						v.Anchored = false
						
						local IceParticle = Main.IceTile:Clone() --// ice stun effect
						IceParticle.Anchored = false
						IceParticle.CanCollide = false
						IceParticle.Massless = true
						IceParticle.Parent = c2
						IceParticle.Transparency = .5
						IceParticle.Size = Vector3.new(6,6,6)
						IceParticle.CFrame = v.CFrame
						
						local W = Instance.new("Weld",v)
						W.Part0 = v
						W.Part1 = IceParticle --// weld stun
						
				
						v.Anchored = false
                        
                        --// knobckaback
						local BV = Instance.new("BodyVelocity",v)
						BV.MaxForce = Vector3.new(20000,20000,20000)
						BV.Velocity = root.CFrame.LookVector * 50 + Vector3.new(math.random(-25,25),math.random(5,25),0)
						BV.P = 17000
						
                        game.Debris:AddItem(BV,.35)
                        
						for i,v in pairs(IceParticle:FindFirstChildOfClass("Attachment"):GetChildren()) do
							v:Emit(20)
						end
						
                        
                        --// add stun for 2 seconds and cleanup after 2 seconds
						CS:AddTag(c2,"WS0")
						CS:AddTag(c2,"JP0")
						CS:AddTag(c2,"S")
                        task.delay(2,function() CS:RemoveTag(c2,"WS0")   CS:RemoveTag(c2,"JP0") CS:RemoveTag(c2,"S") W:Destroy()  IceParticle:Destroy() end)
                        
						local FX = Rep:WaitForChild("FX"):WaitForChild("Hit"):FindFirstChildOfClass("Attachment"):Clone()
						FX.Parent = v
						for i,v in pairs(FX:GetChildren()) do v:Emit(12) end --// hitfx
						game.Debris:AddItem(FX,3)
					end

				end
			end
			
			task.wait(.01)
		end
		
	elseif act == "C" then
		if CS:HasTag(c,"A") or CS:HasTag(c,"Spearin") or  CS:HasTag(c,"S") or CS:HasTag(c,"IEx") or plr.Cooldowns:FindFirstChild("Spike surge") then return end
        --// cds n stuf
        
		Basics.SkillCD(plr,"Spike surge",15.775)
		
		local S = Basics.MakeSound(747238556,c,0,2)
		S:Play()
		
		game.Debris:AddItem(S,S.TimeLength)
		local staphed = false
		local Anim = Basics.MakeAnim(hum,Moves.Spikes)
		Anim:Play()


		CS:AddTag(c,"JP0")
		CS:AddTag(c,"A")
		CS:AddTag(c,"WS0")
		
		task.wait(.750) --// after .75 seconds do move
		task.delay(.5,function()
		CS:RemoveTag(c,"JP0") CS:RemoveTag(c,"A") CS:RemoveTag(c,"WS0") 
		end)
		
		local S = Basics.MakeSound(6860710840,c,0,2)
		S:Play()
		
		game.Debris:AddItem(S,S.TimeLength)
		
		local FX = Main.IceSpik.Summon:Clone()
		FX.Parent = c.Torso
		
		for i,v in pairs(FX:GetChildren()) do
			v:Emit(v:GetAttribute("EmitCount"))
		end
		
		
		local S = Basics.MakeSound(632919727,root,0,2,false,2)
		S:Play()

		game.Debris:AddItem(S,S.TimeLength)
        
        --// ice tile effect on ground
        
		local Tile = Main.IceTile:Clone()
		Tile.Parent = workspace.FX
		Tile.Size = Vector3.new(0,0,0)
		Tile.Transparency = 1
		Tile.CFrame = root.CFrame * CFrame.new(0,-3,0)
		Tile.Anchored = true
		Tile.CanCollide = true
		Tile.Massless = true
		Tile.Name = "IceTileSurf"
		TS:Create(Tile,TweenInfo.new(.65,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Size = Vector3.new(17.5 * 2,1,17.5 * 1.4);Transparency = 0;Orientation = Tile.Orientation + Vector3.new(0,math.rad(170),0)}):Play()

		game.Debris:AddItem(Tile,2.75)

		for i,v in pairs(Tile:FindFirstChildOfClass("Attachment"):GetChildren()) do v:Emit(v:GetAttribute("EmitCount")/2) end


		task.delay(2.63,function()
			TS:Create(Tile,TweenInfo.new(.65,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Size = Vector3.new(0,0,0);Transparency = 1;Orientation = Tile.Orientation + Vector3.new(0,math.rad(-210),0)}):Play()
		end)
		
		local Main = game:GetService("ReplicatedStorage"):WaitForChild("Fruits"):WaitForChild("Assets"):WaitForChild("Ice")

		Rep.Remotes.CFX:FireClient(plr,"ShakeCam","Explosion")
		Rep.Remotes.CFX:FireClient(plr,"ShakeCam","Vibration")

		for i = 1,7 do
			local val = math.random(-8,-3)
		
            
            --// mini tiles
			local Tile = Main.IceTile:Clone()
			Tile.Parent = workspace.FX
			Tile.Size = Vector3.new(0,0,0)
			Tile.Transparency = 1
			Tile.CFrame = root.CFrame * CFrame.new(math.random(-6,6),-3.05,val)
			Tile.Anchored = true
			Tile.CanCollide = true
			Tile.Massless = true
			Tile.Name = "IceTileSurf"
			TS:Create(Tile,TweenInfo.new(.65,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Size = Vector3.new(10,1,10.0);Transparency = 0;Orientation = Tile.Orientation + Vector3.new(0,math.rad(170),0)}):Play()

			game.Debris:AddItem(Tile,2.75)

			for i,v in pairs(Tile:FindFirstChildOfClass("Attachment"):GetChildren()) do v:Emit(v:GetAttribute("EmitCount")/2) end


			local S = Basics.MakeSound(632919727,Tile,0,1.2,false,2)
			S:Play()

			game.Debris:AddItem(S,S.TimeLength)

			task.delay(2.13,function()
				TS:Create(Tile,TweenInfo.new(.65,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Size = Vector3.new(0,0,0);Transparency = 1;Orientation = Tile.Orientation + Vector3.new(0,math.rad(-210),0)}):Play()
			end)
			
		
            --// grow ice 
            
				local Spher = Main.IceoPSer:Clone()
				Spher.Anchored = true
				Spher.CanCollide = false
				Spher.Transparency = 1
				Spher.Massless = true
				Spher.Size = Vector3.new(0,0,0)
				Spher.Material = "Ice"
				Spher.Parent = workspace.FX

				Spher.CFrame = Tile.CFrame * CFrame.new(0,5,0) * CFrame.Angles(math.rad(math.random(-40,-25)),0,0)
				
			for i,v in pairs(Spher.Spike1:GetChildren()) do
					v:Emit(v:GetAttribute("EmitCount"))
				end
			

			local S = Basics.MakeSound(747238556,Spher,0,1,false,1.5)
			S:Play()

			game.Debris:AddItem(S,S.TimeLength)
			
				game.Debris:AddItem(Spher,2.2)
				--[[Spher.Orientation = Vector3.new(0,0,-40)]]			
				task.delay(1.65,function()
				game:GetService("TweenService"):Create(Spher,TweenInfo.new(.5,Enum.EasingStyle.Back),{Size = Vector3.new(5,0,5);Transparency = 1;Orientation = Spher.Orientation + Vector3.new(0,0,0);CFrame = Spher.CFrame * CFrame.new(0,-5,0)}):Play()

				end)
				game:GetService("TweenService"):Create(Spher,TweenInfo.new(.5,Enum.EasingStyle.Back),{Size = Vector3.new(5,math.random(15,25),5);Transparency = .15;Orientation = Spher.Orientation + Vector3.new(0,0,0)}):Play()

		
			local HB = Instance.new("Part")
			HB.Transparency = 1
			HB.Anchored = true
			HB.CanCollide = false
			HB.Parent = workspace.FX
			HB.Name = "HB"
			HB.Size = Vector3.new(20,20,20)
			HB.CFrame = root.CFrame * CFrame.new(0,0,-4)

			local Params = OverlapParams.new()
			Params.FilterType = Enum.RaycastFilterType.Blacklist
			Params.FilterDescendantsInstances = {workspace.FX,workspace.Camera,c,HB}
            --// htbox function
            
			for i,v in pairs(workspace:GetPartsInPart(HB,Params)) do
				if v.Name == "HumanoidRootPart" and Basics.Attackable(v.Parent) then
					local c2 = v.Parent
					local Damaged =  Basics.Damage(plr,c2,Basics.CalculateDmg(7.5,hum,c2:FindFirstChildOfClass("Humanoid")),"Projectile",true,1,2)
                    if Damaged == true then
                        --// same as before play sound weld ice effect and add stun
                        
						local S = Basics.MakeSound(5961220911,c2,0,3.25)
						S:Play()



						game.Debris:AddItem(S,S.TimeLength)

						v.Anchored = false

						local IceParticle = Main.IceTile:Clone()
						IceParticle.Anchored = false
						IceParticle.CanCollide = false
						IceParticle.Massless = true
						IceParticle.Parent = c2
						IceParticle.Transparency = .5
						IceParticle.Size = Vector3.new(6,6,6)
						IceParticle.CFrame = v.CFrame

						local W = Instance.new("Weld",v)
						W.Part0 = v
						W.Part1 = IceParticle


						v.Anchored = false

						local BV = Instance.new("BodyVelocity",v)
						BV.MaxForce = Vector3.new(20000,20000,20000)
						BV.Velocity = Vector3.new(math.random(-100,100),math.random(100,200),math.random(-100,100))
						BV.P = 13000

						game.Debris:AddItem(BV,.75)
						for i,v in pairs(IceParticle:FindFirstChildOfClass("Attachment"):GetChildren()) do
							v:Emit(20)
						end


						CS:AddTag(c2,"WS0")
						CS:AddTag(c2,"JP0")
						CS:AddTag(c2,"S")
						task.delay(2,function() CS:RemoveTag(c2,"WS0") CS:RemoveTag(c2,"JP0") CS:RemoveTag(c2,"S") W:Destroy()  IceParticle:Destroy() end)
						local FX = Rep:WaitForChild("FX"):WaitForChild("Hit"):FindFirstChildOfClass("Attachment"):Clone()
						FX.Parent = v
						for i,v in pairs(FX:GetChildren()) do v:Emit(12) end
						game.Debris:AddItem(FX,3)
					end

				end

			end
			HB:Destroy()
			
			task.wait(.0475) --// rerun it 
	
				end
		
			
	
	elseif act == "V" then
		--// ice age
		
		
		if CS:HasTag(c,"A") or CS:HasTag(c,"Spearin") or  CS:HasTag(c,"S") or CS:HasTag(c,"IEx") or plr.Cooldowns:FindFirstChild("Ice age") then return end
        --// cds n stuff
        --// exact same layout as before
        
        
		Basics.SkillCD(plr,"Ice age",50)

		local S = Basics.MakeSound(747238556,c,0,2)
		S:Play()

		game.Debris:AddItem(S,S.TimeLength)
		local staphed = false
		local Anim = Basics.MakeAnim(hum,Moves.Spikes)
		Anim:Play()


		CS:AddTag(c,"JP0")
		CS:AddTag(c,"A")
		CS:AddTag(c,"WS0")

		task.wait(.750)
		task.delay(.5,function()
			CS:RemoveTag(c,"JP0") CS:RemoveTag(c,"A") CS:RemoveTag(c,"WS0") 
		end)

		local S = Basics.MakeSound(6860710840,c,0,2)
		S:Play()

		game.Debris:AddItem(S,S.TimeLength)

		local FX = Main.IceSpik.Summon:Clone()
		FX.Parent = c.Torso

		for i,v in pairs(FX:GetChildren()) do
			v:Emit(v:GetAttribute("EmitCount"))
		end


		local S = Basics.MakeSound(632919727,root,0,2,false,2)
		S:Play()

		game.Debris:AddItem(S,S.TimeLength)

		local Tile = Main.IceTile:Clone()
		Tile.Parent = workspace.FX
		Tile.Size = Vector3.new(0,0,0)
		Tile.Transparency = 1
		Tile.CFrame = root.CFrame * CFrame.new(0,-3,0)
		Tile.Anchored = true
		Tile.CanCollide = true
		Tile.Massless = true
		Tile.Name = "IceTileSurf"
		TS:Create(Tile,TweenInfo.new(.65,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Size = Vector3.new(95,1,95);Transparency = 0;Orientation = Tile.Orientation + Vector3.new(0,math.rad(170),0)}):Play()

		game.Debris:AddItem(Tile,2.75)

		for i,v in pairs(Tile:FindFirstChildOfClass("Attachment"):GetChildren()) do v:Emit(v:GetAttribute("EmitCount")/2) end


		task.delay(2.63,function()
			TS:Create(Tile,TweenInfo.new(.65,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Size = Vector3.new(0,0,0);Transparency = 1;Orientation = Tile.Orientation + Vector3.new(0,math.rad(-210),0)}):Play()
		end)



		Rep.Remotes.CFX:FireClient(plr,"ShakeCam","Explosion") --/ cam shake
		Rep.Remotes.CFX:FireClient(plr,"ShakeCam","Vibration")

		coroutine.resume(coroutine.create(function()

		for i = 1,12 do --// effects
			local rot = 30 * i --// rotation from 30 to 360
			local val = -2.5
			local val = -4.5
			local rad = -30
		
			for i = 1,5 do --// increase size of size cubes and distance from character per ice cube scaled off i
				local Sizze = 5 * i
				local Pos = 10 * i

				local Spher = Main.IceCub:Clone()
				Spher.Anchored = true
				Spher.CanCollide = false
				Spher.Transparency = 1
				Spher.Massless = true
				Spher.Size = Vector3.new(0,0,0)
				Spher.Material = "Ice"
				Spher.Reflectance = 3
				Spher.Color = Color3.fromRGB(150,195,219)
				Spher.Parent = workspace.FX
				Spher.CFrame = root.CFrame* CFrame.Angles(math.rad(0),math.rad(rot),0) * CFrame.new(0,0,-Pos) * CFrame.Angles(math.rad(math.random(-360,360)),math.rad(math.random(-360,360)),math.rad(math.random(-360,360))) --// random angles cuz cool
				
				local Spike1 = Main.IceTile.Explosion:Clone()
				Spike1.Name = "Spike1"
				Spike1.Parent = Spher
				
				for i,v in pairs(Spher.Spike1:GetChildren()) do
					v:Emit(v:GetAttribute("EmitCount")/2)
				end

				game.Debris:AddItem(Spher,2)
				--[[Spher.Orientation = Vector3.new(0,0,-40)]]			
				task.delay(1.5,function() --// cleanup n stuff
					game:GetService("TweenService"):Create(Spher,TweenInfo.new(.49,Enum.EasingStyle.Back),{Size = Vector3.new(0,0,0);Transparency = 1}):Play()

					end)
					
					--// tween effecs
				game:GetService("TweenService"):Create(Spher,TweenInfo.new(.5,Enum.EasingStyle.Back),{Size = Vector3.new(Sizze,Sizze,Sizze);Transparency = .15}):Play()

			end
			end
			
		end))
        
        --// one giant hitbox with better damgage
        
		local HB = Instance.new("Part")
		HB.Transparency = 1
		HB.Anchored = true
		HB.CanCollide = false
		HB.CastShadow = false
		HB.Parent = workspace.FX
		HB.Name = "HB"
		HB.Size = Vector3.new(100,50,100)
		HB.CFrame = root.CFrame * CFrame.new(0,0,0)

		local Params = OverlapParams.new()
		Params.FilterType = Enum.RaycastFilterType.Blacklist
		Params.FilterDescendantsInstances = {workspace.FX,workspace.Camera,c,HB}

		for i,v in pairs(workspace:GetPartsInPart(HB,Params)) do
			if v.Name == "HumanoidRootPart" and Basics.Attackable(v.Parent) then
				local c2 = v.Parent
				local Damaged =  Basics.Damage(plr,c2,Basics.CalculateDmg(35,hum,c2:FindFirstChildOfClass("Humanoid")),"Projectile",true,1,2)
				if Damaged == true then
					local S = Basics.MakeSound(5961220911,c2,0,3.25)
					S:Play()



					game.Debris:AddItem(S,S.TimeLength)

					v.Anchored = false
					
					v.Anchored = false

					local BV = Instance.new("BodyVelocity",v)
					BV.MaxForce = Vector3.new(20000,20000,20000)
					BV.Velocity = root.CFrame.LookVector * 50 + Vector3.new(math.random(-25,25),-50,0)
					BV.P = 17000
					
					game.Debris:AddItem(BV,.35)
					
					local IceParticle = Main.IceTile:Clone()
					IceParticle.Anchored = false
					IceParticle.CanCollide = false
					IceParticle.Massless = true
					IceParticle.Parent = c2
					IceParticle.Transparency = .5
					IceParticle.Size = Vector3.new(6,6,6)
					IceParticle.CFrame = v.CFrame

					local W = Instance.new("Weld",v)
					W.Part0 = v
					W.Part1 = IceParticle


					v.Anchored = false

					for i,v in pairs(IceParticle:FindFirstChildOfClass("Attachment"):GetChildren()) do
						v:Emit(20)
					end


					CS:AddTag(c2,"S")
					task.delay(2,function() CS:RemoveTag(c2,"S") W:Destroy()  IceParticle:Destroy() end)
					local FX = Rep:WaitForChild("FX"):WaitForChild("Hit"):FindFirstChildOfClass("Attachment"):Clone()
					FX.Parent = v
					for i,v in pairs(FX:GetChildren()) do v:Emit(12) end
					game.Debris:AddItem(FX,3)
				end

			end

		end
		HB:Destroy()
		











	elseif act == "E" then --// ui list stuff 
		
		local Cooldowns = {
			{Key = "Z",MoveName = "Ice surf"};
			{Key = "X",MoveName = "Ice spear"};
			{Key = "C",MoveName = "Spike surge"};
			{Key = "V",MoveName = "Ice age"};

			}
		Rep.Remotes.UI2:FireClient(plr,"Cooldowns","Ice-Ice","Enable",Cooldowns)

	elseif act == "UE" then
		Rep.Remotes.UI2:FireClient(plr,"Cooldowns","Ice-Ice","Disable")

		end
end)
