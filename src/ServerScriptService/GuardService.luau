-- Stealth guards: patrol -> (spotted) chase -> search -> patrol.
--
-- Detection model (server-side, per player):
--   * A guard "sees" a player if the player is inside the guard's view distance and field of view
--     and a raycast from the guard's head to the player is unobstructed.
--   * Seen players fill a 0..1 detection meter. It fills faster when close and when moving fast,
--     slower when standing still, and drains when nobody sees the player.
--   * At 1.0 the guard (and any guard that sees the player) starts a chase and the alert level rises.
--   * A chasing guard within CaptureDistance of a visible player fires `Captured`.
--
-- Known limitations (fine for the slice): no noise, no light/dark factor, guards glide because
-- server-made rigs have no walk animation yet, and detection uses body facing, not head turning.

local Players = game:GetService("Players")
local PathfindingService = game:GetService("PathfindingService")

local Config = {
	ViewDistance = 50,
	HalfFov = math.rad(55),
	ProximitySenseRange = 6, -- guards notice anything this close even outside their cone
	PatrolSpeed = 8,
	SearchSpeed = 10,
	ChaseSpeed = 15,
	DetectRate = 0.9, -- meter per second at point-blank while walking
	Decay = 0.3,
	LoseSightSeconds = 4,
	SearchSeconds = 6,
	CaptureDistance = 4.5,
	WaypointReachDistance = 4,
	PatrolPauseSeconds = 1.5,
	DecisionInterval = 0.35,
}

local function flatDistance(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

local function createRig(): Model
	local ok, model = pcall(function()
		local desc = Instance.new("HumanoidDescription")
		local dark = Color3.fromRGB(35, 40, 55)
		desc.HeadColor = Color3.fromRGB(190, 160, 130)
		desc.TorsoColor = dark
		desc.LeftArmColor = dark
		desc.RightArmColor = dark
		desc.LeftLegColor = dark
		desc.RightLegColor = dark
		return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
	end)
	if ok and model then
		return model
	end

	-- Fallback: a bare humanoid so the system still works if rig creation fails.
	local fallback = Instance.new("Model")
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 5, 2)
	root.Color = Color3.fromRGB(35, 40, 55)
	root.Parent = fallback
	Instance.new("Humanoid").Parent = fallback
	fallback.PrimaryPart = root
	return fallback
end

---------------------------------------------------------------------------
-- Guard
---------------------------------------------------------------------------

local Guard = {}
Guard.__index = Guard

function Guard.new(service, route: { Vector3 })
	local self = setmetatable({}, Guard)
	self.Service = service
	self.Route = route
	self.RouteIndex = 1
	self.State = "Patrol"
	self.Alive = true
	self.LastSeenPos = route[1]
	self.LastSeenTime = 0
	self.SearchPos = route[1]
	self.SearchUntil = 0

	self.Model = createRig()
	self.Model.Name = "Guard"
	self.Root = self.Model.PrimaryPart or self.Model:FindFirstChild("HumanoidRootPart")
	self.Humanoid = self.Model:FindFirstChildOfClass("Humanoid")
	self.Humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	self.Model:PivotTo(CFrame.new(route[1]))
	self.Model.Parent = workspace
	pcall(function()
		self.Root:SetNetworkOwner(nil)
	end)

	task.spawn(function()
		self:_run()
	end)
	return self
end

function Guard:_speedMultiplier(): number
	return 1 + 0.1 * self.Service.Alert.Level
end

function Guard:_step(target: Vector3, speed: number)
	self.Humanoid.WalkSpeed = speed
	local path = PathfindingService:CreatePath({ AgentRadius = 2, AgentHeight = 5, AgentCanJump = false })
	local ok = pcall(function()
		path:ComputeAsync(self.Root.Position, target)
	end)
	if ok and path.Status == Enum.PathStatus.Success then
		local waypoints = path:GetWaypoints()
		local nextWaypoint = waypoints[2] or waypoints[1]
		self.Humanoid:MoveTo(nextWaypoint.Position)
	else
		self.Humanoid:MoveTo(target)
	end
end

function Guard:StartChase(position: Vector3)
	self.State = "Chase"
	self.LastSeenPos = position
	self.LastSeenTime = os.clock()
end

function Guard:NotifySeen(position: Vector3)
	if self.State == "Chase" then
		self.LastSeenPos = position
		self.LastSeenTime = os.clock()
	end
end

function Guard:Investigate(position: Vector3)
	if self.State == "Patrol" then
		self.State = "Search"
		self.SearchPos = position
		self.SearchUntil = os.clock() + Config.SearchSeconds
	end
end

function Guard:_nearestRouteIndex(): number
	local best, bestDist = 1, math.huge
	for i, p in self.Route do
		local d = flatDistance(self.Root.Position, p)
		if d < bestDist then
			best, bestDist = i, d
		end
	end
	return best
end

function Guard:_run()
	while self.Alive and self.Model.Parent do
		local now = os.clock()
		local mult = self:_speedMultiplier()

		if self.State == "Patrol" then
			local target = self.Route[self.RouteIndex]
			if flatDistance(self.Root.Position, target) < Config.WaypointReachDistance then
				self.RouteIndex = self.RouteIndex % #self.Route + 1
				self.Humanoid:MoveTo(self.Root.Position)
				task.wait(Config.PatrolPauseSeconds)
			else
				self:_step(target, Config.PatrolSpeed)
			end
		elseif self.State == "Chase" then
			self:_step(self.LastSeenPos, Config.ChaseSpeed * mult)
			if now - self.LastSeenTime > Config.LoseSightSeconds then
				self.State = "Search"
				self.SearchPos = self.LastSeenPos
				self.SearchUntil = now + Config.SearchSeconds
			end
		elseif self.State == "Search" then
			if flatDistance(self.Root.Position, self.SearchPos) > Config.WaypointReachDistance then
				self:_step(self.SearchPos, Config.SearchSpeed * mult)
			else
				self.Humanoid:MoveTo(self.Root.Position)
				if now >= self.SearchUntil then
					self.RouteIndex = self:_nearestRouteIndex()
					self.State = "Patrol"
				end
			end
		end

		task.wait(Config.DecisionInterval)
	end
end

function Guard:Destroy()
	self.Alive = false
	if self.Model then
		self.Model:Destroy()
	end
end

---------------------------------------------------------------------------
-- Service
---------------------------------------------------------------------------

local GuardService = {}
GuardService.__index = GuardService

function GuardService.new(alert)
	local self = setmetatable({}, GuardService)
	self.Alert = alert
	self.Guards = {}
	self.Meters = {} -- [Player] = 0..1
	self._captured = Instance.new("BindableEvent")
	self.Captured = self._captured.Event
	self._running = false
	return self
end

function GuardService:Spawn(route: { Vector3 })
	local guard = Guard.new(self, route)
	table.insert(self.Guards, guard)
	return guard
end

function GuardService:_canSee(guard, hrp: BasePart, character: Model): boolean
	local head = guard.Model:FindFirstChild("Head") or guard.Root
	local eye = head.Position
	local delta = hrp.Position - eye
	local dist = delta.Magnitude
	if dist > Config.ViewDistance then
		return false
	end

	if dist > Config.ProximitySenseRange then
		local flat = Vector3.new(delta.X, 0, delta.Z)
		if flat.Magnitude > 0.01 then
			local cosAngle = math.clamp(guard.Root.CFrame.LookVector:Dot(flat.Unit), -1, 1)
			if math.acos(cosAngle) > Config.HalfFov then
				return false
			end
		end
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { guard.Model, character }
	return workspace:Raycast(eye, delta, params) == nil
end

function GuardService:_tick(dt: number)
	local anyChasing = false
	for _, guard in self.Guards do
		if guard.State == "Chase" then
			anyChasing = true
			break
		end
	end

	for _, player in Players:GetPlayers() do
		local character = player.Character
		local hrp = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local hum = character and character:FindFirstChildOfClass("Humanoid")
		if not (hrp and hum and hum.Health > 0) then
			continue
		end

		local seers = {}
		local bestRate = 0
		local horizontalSpeed = Vector3.new(hrp.AssemblyLinearVelocity.X, 0, hrp.AssemblyLinearVelocity.Z).Magnitude
		local moveFactor = horizontalSpeed < 1 and 0.4 or (horizontalSpeed <= 17 and 1 or 1.5)

		for _, guard in self.Guards do
			if guard.Alive and self:_canSee(guard, hrp, character) then
				table.insert(seers, guard)
				local dist = (hrp.Position - guard.Root.Position).Magnitude
				local proximity = math.clamp(1 - dist / Config.ViewDistance, 0.2, 1)
				bestRate = math.max(bestRate, Config.DetectRate * proximity * moveFactor)
			end
		end

		local previous = self.Meters[player] or 0
		local meter
		if #seers > 0 then
			meter = math.min(1, previous + bestRate * dt)
		else
			meter = math.max(0, previous - Config.Decay * dt)
		end
		self.Meters[player] = meter
		player:SetAttribute("Detection", math.floor(meter * 100) / 100)

		if meter >= 1 then
			local firstSpot = previous < 1
			for _, guard in seers do
				if guard.State ~= "Chase" then
					guard:StartChase(hrp.Position)
				else
					guard:NotifySeen(hrp.Position)
				end
				if (hrp.Position - guard.Root.Position).Magnitude <= Config.CaptureDistance then
					self._captured:Fire(player)
				end
			end
			if firstSpot then
				self.Alert:Raise()
				for _, guard in self.Guards do
					guard:Investigate(hrp.Position)
				end
			end
		end
	end

	self.Alert:Update(anyChasing, dt)
end

function GuardService:Start()
	if self._running then
		return
	end
	self._running = true
	task.spawn(function()
		local last = os.clock()
		while self._running do
			task.wait(0.1)
			local now = os.clock()
			self:_tick(now - last)
			last = now
		end
	end)
end

function GuardService:Destroy()
	self._running = false
	for _, guard in self.Guards do
		guard:Destroy()
	end
	table.clear(self.Guards)
	for _, player in Players:GetPlayers() do
		player:SetAttribute("Detection", 0)
	end
	table.clear(self.Meters)
	self._captured:Destroy()
end

return GuardService
