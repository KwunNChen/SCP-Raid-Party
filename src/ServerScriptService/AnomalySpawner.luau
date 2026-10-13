-- The "Director": schedules anomalies on a rising curve and runs each one.
-- An anomaly's Start(ctx) returns a stop() function.
-- ctx = { alivePlayers = () -> {Player}, announce = (string) -> () }

local CollectionService = game:GetService("CollectionService")
local ServerStorage = game:GetService("ServerStorage")
local Players = game:GetService("Players")

local Anomalies = {}

-- 1. Power Surge: lights flicker, then die, then restore.
Anomalies.PowerSurge = {
	Name = "Power Surge",
	MinClearance = 1,
	Weight = 3,
	Duration = 18,
	Start = function(ctx)
		local lights, original = {}, {}
		for _, inst in CollectionService:GetTagged("FacilityLight") do
			for _, d in inst:GetDescendants() do
				if d:IsA("Light") then
					table.insert(lights, d)
					original[d] = d.Enabled
				end
			end
			if inst:IsA("Light") then
				table.insert(lights, inst)
				original[inst] = inst.Enabled
			end
		end

		ctx.announce("POWER FLUCTUATION DETECTED")
		local running = true
		task.spawn(function()
			local t0 = os.clock()
			while running do
				local elapsed = os.clock() - t0
				local dark = elapsed > 4
				for _, l in lights do
					l.Enabled = not dark and math.random() > 0.5
				end
				task.wait(dark and 0.5 or 0.08)
			end
		end)

		return function()
			running = false
			for l, was in original do
				if l.Parent then
					l.Enabled = was
				end
			end
		end
	end,
}

-- 2. Restless (rule): do not stand still.
Anomalies.Restless = {
	Name = "Restless",
	MinClearance = 2,
	Weight = 2,
	Duration = 40,
	Start = function(ctx)
		ctx.announce("RULE UPDATE: DO NOT STAND STILL")
		local running = true
		local still = {} -- [Player] = seconds
		local lastPos = {}
		task.spawn(function()
			while running do
				task.wait(0.5)
				for _, p in ctx.alivePlayers() do
					local hrp = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
					local hum = p.Character and p.Character:FindFirstChildOfClass("Humanoid")
					if hrp and hum then
						local prev = lastPos[p]
						if prev and (hrp.Position - prev).Magnitude < 1 then
							still[p] = (still[p] or 0) + 0.5
						else
							still[p] = 0
						end
						lastPos[p] = hrp.Position
						if still[p] >= 4 then
							hum:TakeDamage(15)
						end
					end
				end
			end
		end)
		return function()
			running = false
		end
	end,
}

-- 3. Wanderer: slow entity that hunts the nearest player.
-- Provide a rig at ServerStorage.Anomalies.Wanderer; a placeholder is built if missing.
local function buildPlaceholder()
	local model = Instance.new("Model")
	model.Name = "Wanderer"
	local hrp = Instance.new("Part")
	hrp.Name = "HumanoidRootPart"
	hrp.Size = Vector3.new(2, 5, 2)
	hrp.Color = Color3.new(0.05, 0.05, 0.05)
	hrp.Material = Enum.Material.Neon
	hrp.Parent = model
	local hum = Instance.new("Humanoid")
	hum.WalkSpeed = 10
	hum.Parent = model
	model.PrimaryPart = hrp
	return model
end

Anomalies.Wanderer = {
	Name = "Wanderer",
	MinClearance = 3,
	Weight = 2,
	Duration = 45,
	Start = function(ctx)
		local anomalyFolder = ServerStorage:FindFirstChild("Anomalies")
		local template = anomalyFolder and anomalyFolder:FindFirstChild("Wanderer")
		local model = template and template:Clone() or buildPlaceholder()

		local spawns = CollectionService:GetTagged("AnomalySpawn")
		local spawn = #spawns > 0 and spawns[math.random(#spawns)] or nil
		local origin = spawn and spawn.CFrame or CFrame.new(0, 10, 0)
		model:PivotTo(origin + Vector3.new(0, 3, 0))
		model.Parent = workspace

		local hrp = model.PrimaryPart or model:FindFirstChild("HumanoidRootPart")
		local hum = model:FindFirstChildOfClass("Humanoid")
		if hrp then
			pcall(function()
				hrp:SetNetworkOwner(nil)
			end)
		end

		ctx.announce("CONTAINMENT BREACH: ENTITY LOOSE")
		local running = true
		task.spawn(function()
			local lastHit = 0
			while running and hrp and hum and model.Parent do
				local nearest, best = nil, math.huge
				for _, p in ctx.alivePlayers() do
					local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
					if root then
						local dist = (root.Position - hrp.Position).Magnitude
						if dist < best then
							nearest, best = p, dist
						end
					end
				end
				if nearest then
					local root = nearest.Character.HumanoidRootPart
					hum:MoveTo(root.Position)
					if best < 5 and os.clock() - lastHit > 1.5 then
						lastHit = os.clock()
						local th = nearest.Character:FindFirstChildOfClass("Humanoid")
						if th then
							th:TakeDamage(25)
						end
					end
				end
				task.wait(0.25)
			end
		end)

		return function()
			running = false
			model:Destroy()
		end
	end,
}

---------------------------------------------------------------------------

-- 4. Stillwalker: moves only while no player is looking at it. Needs no animation.
-- Note: the server has no camera data, so "looking" is approximated from body facing + line of sight.
local function isObserved(entityRoot: BasePart, players: { Player }): boolean
	for _, p in players do
		local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
		if root then
			local toEntity = entityRoot.Position - root.Position
			if toEntity.Magnitude < 150 and root.CFrame.LookVector:Dot(toEntity.Unit) > 0.35 then
				local params = RaycastParams.new()
				params.FilterDescendantsInstances = { p.Character, entityRoot.Parent }
				if not workspace:Raycast(root.Position, toEntity, params) then
					return true
				end
			end
		end
	end
	return false
end

Anomalies.Stillwalker = {
	Name = "Stillwalker",
	MinClearance = 2,
	Weight = 2,
	Duration = 50,
	Start = function(ctx)
		local anomalyFolder = ServerStorage:FindFirstChild("Anomalies")
		local template = anomalyFolder and anomalyFolder:FindFirstChild("Stillwalker")
		local model = template and template:Clone() or buildPlaceholder()
		model.Name = "Stillwalker"

		local spawns = CollectionService:GetTagged("AnomalySpawn")
		local spawn = #spawns > 0 and spawns[math.random(#spawns)] or nil
		model:PivotTo((spawn and spawn.CFrame or CFrame.new(0, 10, 0)) + Vector3.new(0, 3, 0))
		model.Parent = workspace

		local hrp = model.PrimaryPart or model:FindFirstChild("HumanoidRootPart")
		local hum = model:FindFirstChildOfClass("Humanoid")
		if hrp then
			pcall(function()
				hrp:SetNetworkOwner(nil)
			end)
		end

		ctx.announce("DO NOT TURN YOUR BACK ON THE FIGURE")
		local running = true
		task.spawn(function()
			local lastHit = 0
			while running and hrp and hum and model.Parent do
				local players = ctx.alivePlayers()
				if isObserved(hrp, players) then
					hum.WalkSpeed = 0
					hum:MoveTo(hrp.Position)
				else
					hum.WalkSpeed = 16
					local nearest, best = nil, math.huge
					for _, p in players do
						local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
						if root then
							local dist = (root.Position - hrp.Position).Magnitude
							if dist < best then
								nearest, best = p, dist
							end
						end
					end
					if nearest then
						hum:MoveTo(nearest.Character.HumanoidRootPart.Position)
						if best < 5 and os.clock() - lastHit > 2 then
							lastHit = os.clock()
							local th = nearest.Character:FindFirstChildOfClass("Humanoid")
							if th then
								th:TakeDamage(40)
							end
						end
					end
				end
				task.wait(0.15)
			end
		end)

		return function()
			running = false
			model:Destroy()
		end
	end,
}

local AnomalySpawner = {}
AnomalySpawner.__index = AnomalySpawner

function AnomalySpawner.new(clearance: number, ctx)
	local self = setmetatable({}, AnomalySpawner)
	self.Clearance = clearance
	self.Ctx = ctx
	self.Intensity = 1
	self.Active = {} -- { id, stop, endsAt }
	self._nextAt = 40 -- seconds into the shift
	return self
end

function AnomalySpawner:SetIntensity(mult: number)
	self.Intensity = mult
end

function AnomalySpawner:_isActive(id: string): boolean
	for _, a in self.Active do
		if a.id == id then
			return true
		end
	end
	return false
end

function AnomalySpawner:_pick()
	local pool, total = {}, 0
	for id, def in Anomalies do
		if def.MinClearance <= self.Clearance and not self:_isActive(id) then
			table.insert(pool, { id = id, def = def })
			total += def.Weight
		end
	end
	if total == 0 then
		return nil
	end
	local roll = math.random() * total
	for _, entry in pool do
		roll -= entry.def.Weight
		if roll <= 0 then
			return entry
		end
	end
	return pool[#pool]
end

-- Call once per second (or per tick) with seconds elapsed in the shift.
function AnomalySpawner:Step(elapsed: number)
	local now = os.clock()
	for i = #self.Active, 1, -1 do
		local a = self.Active[i]
		if now >= a.endsAt then
			a.stop()
			table.remove(self.Active, i)
		end
	end

	if elapsed >= self._nextAt then
		local entry = self:_pick()
		if entry then
			local stop = entry.def.Start(self.Ctx)
			table.insert(self.Active, { id = entry.id, stop = stop, endsAt = now + entry.def.Duration })
		end
		local interval = math.max(18, 50 - self.Clearance * 3) / self.Intensity
		self._nextAt = elapsed + interval
	end
end

function AnomalySpawner:StopAll()
	for _, a in self.Active do
		a.stop()
	end
	table.clear(self.Active)
end

return AnomalySpawner
