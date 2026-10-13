-- Stage 0 test harness: builds Mission01, spawns guards, runs one stealth mission on a loop.
-- IMPORTANT: disable Main.server.luau while testing this. Both want control of player spawning.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")

local MapBuilder = require(script.Parent.MapBuilder)
local AlertManager = require(script.Parent.AlertManager)
local GuardService = require(script.Parent.GuardService)
local Mission = require(script.Parent.Missions.Mission01)

local LOCKDOWN_FAIL_SECONDS = 40
local END_SCREEN_SECONDS = 5

local message = Instance.new("RemoteEvent")
message.Name = "Stage0Message"
message.Parent = ReplicatedStorage

local function say(text: string)
	message:FireAllClients(text)
end

-- Dark atmosphere. Lamps in the map are the only real light sources.
Lighting.ClockTime = 0
Lighting.Brightness = 0
Lighting.Ambient = Color3.fromRGB(8, 8, 12)
Lighting.OutdoorAmbient = Color3.fromRGB(8, 8, 12)
Lighting.EnvironmentDiffuseScale = 0
Lighting.EnvironmentSpecularScale = 0
Lighting.FogEnd = 400
Lighting.FogColor = Color3.fromRGB(5, 5, 8)

local function playersInZone(zone: BasePart): { Player }
	local roots = {}
	for _, p in Players:GetPlayers() do
		local hrp = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
		if hrp then
			table.insert(roots, hrp)
		end
	end
	if #roots == 0 then
		return {}
	end
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = roots
	local found = {}
	for _, part in workspace:GetPartsInPart(zone, params) do
		local p = Players:GetPlayerFromCharacter(part.Parent)
		if p and not table.find(found, p) then
			table.insert(found, p)
		end
	end
	return found
end

-- Returns "success" or "fail".
local function runMission(): string
	local built = MapBuilder.build(Mission.Layout)
	local alert = AlertManager.new()
	local guards = GuardService.new(alert)

	for _, g in Mission.Guards do
		local route = {}
		for _, id in g.route do
			table.insert(route, built.Waypoints[id])
		end
		guards:Spawn(route)
	end

	local function sendToSpawn(player: Player)
		player:LoadCharacter()
		local char = player.Character or player.CharacterAdded:Wait()
		local spawns = built.PlayerSpawns
		char:PivotTo(CFrame.new(spawns[math.random(#spawns)]))
		player:SetAttribute("Detection", 0)
	end

	for _, p in Players:GetPlayers() do
		task.spawn(sendToSpawn, p)
	end
	local joinConn = Players.PlayerAdded:Connect(sendToSpawn)

	local result: string? = nil
	local hasObjective = false

	local prompt = built.Objective and built.Objective:FindFirstChildOfClass("ProximityPrompt")
	local promptConn
	if prompt then
		promptConn = prompt.Triggered:Connect(function()
			hasObjective = true
			built.Objective:Destroy()
			say("Core secured. Get to the extraction point.")
		end)
	end

	local capturedConn = guards.Captured:Connect(function(player)
		if not result then
			result = "fail"
			say(player.Name .. " was caught.")
		end
	end)

	local lockdownConn = alert.Lockdown:Connect(function()
		say("SITE LOCKDOWN. Extract within " .. LOCKDOWN_FAIL_SECONDS .. " seconds.")
		task.delay(LOCKDOWN_FAIL_SECONDS, function()
			if not result then
				result = "fail"
				say("Lockdown complete. Mission failed.")
			end
		end)
	end)

	say(Mission.Name .. ": " .. Mission.Briefing)
	guards:Start()

	while not result do
		task.wait(0.5)
		if hasObjective and built.ExtractZone then
			local inside = playersInZone(built.ExtractZone)
			if #inside > 0 and #inside == #Players:GetPlayers() then
				result = "success"
				say("Extracted. Mission complete.")
			end
		end
	end

	-- Cleanup
	joinConn:Disconnect()
	capturedConn:Disconnect()
	lockdownConn:Disconnect()
	if promptConn then
		promptConn:Disconnect()
	end
	guards:Destroy()
	alert:Destroy()
	task.wait(END_SCREEN_SECONDS)
	built.Folder:Destroy()
	return result
end

while true do
	repeat
		task.wait(1)
	until #Players:GetPlayers() > 0
	runMission()
end
