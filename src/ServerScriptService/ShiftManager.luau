-- State machine: Intermission -> Briefing -> Active (-> Extraction) -> Results -> loop.
--
-- Workspace setup expected (tag with CollectionService):
--   LobbySpawn     parts where players appear between shifts
--   FacilitySpawn  parts where the team starts a shift
--   ExtractZone    one part marking the extraction area
--   plus the objective/anomaly tags from Config.ObjectivePool and AnomalySpawner

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Config = require(ReplicatedStorage.Shared.Config)
local DataService = require(script.Parent.DataService)
local ObjectiveTracker = require(script.Parent.ObjectiveTracker)
local AnomalySpawner = require(script.Parent.AnomalySpawner)
local RuleDirector = require(script.Parent.RuleDirector)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local ShiftUpdate = Remotes:WaitForChild("ShiftUpdate") -- (kind: string, payload: any)

local ShiftManager = {}

local function broadcast(kind: string, payload: any)
	ShiftUpdate:FireAllClients(kind, payload)
end

local function randomTagged(tag: string): BasePart?
	local list = CollectionService:GetTagged(tag)
	if #list == 0 then
		return nil
	end
	return list[math.random(#list)]
end

-- Respawn a player at a tagged spawn. Returns the character.
local function spawnAt(player: Player, tag: string)
	player:LoadCharacter()
	local char = player.Character or player.CharacterAdded:Wait()
	local spawn = randomTagged(tag)
	if spawn then
		char:PivotTo(spawn.CFrame + Vector3.new(math.random(-3, 3), 4, math.random(-3, 3)))
	end
	return char
end

local function countdown(kind: string, seconds: number)
	for s = seconds, 1, -1 do
		broadcast(kind, { seconds = s })
		task.wait(1)
	end
end

local function playersInZone(zone: BasePart): { Player }
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
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

local function averageClearance(list: { Player }): number
	local total, n = 0, 0
	for _, p in list do
		local d = DataService.Get(p)
		if d then
			total += d.Clearance
			n += 1
		end
	end
	return n > 0 and math.max(1, math.round(total / n)) or 1
end

local function pickLore(player: Player)
	local d = DataService.Get(player)
	if not d then
		return nil
	end
	local options = {}
	for _, lore in Config.Lore do
		if lore.minClearance <= d.Clearance and not table.find(d.LoreUnlocked, lore.id) then
			table.insert(options, lore)
		end
	end
	if #options == 0 then
		return nil
	end
	local chosen = options[math.random(#options)]
	DataService.UnlockLore(player, chosen.id)
	return chosen
end

local function runShift(participants: { Player })
	local R = Config.Rewards
	local state = {} -- [Player] = { alive, extracted }
	local deathConns = {}

	for _, p in participants do
		state[p] = { alive = true, extracted = false }
	end

	local clearance = averageClearance(participants)
	local tracker = ObjectiveTracker.new(clearance)
	tracker.Changed:Connect(function()
		broadcast("Objectives", tracker:Snapshot())
		if tracker.Complete then
			broadcast("ExtractionOpen", {})
		end
	end)

	local function alivePlayers()
		local out = {}
		for p, s in state do
			if s.alive and not s.extracted and p.Parent then
				table.insert(out, p)
			end
		end
		return out
	end

	local ctx = {
		alivePlayers = alivePlayers,
		announce = function(msg)
			broadcast("Announcement", { text = msg })
		end,
	}
	local director = AnomalySpawner.new(clearance, ctx)
	local rules = RuleDirector.new(clearance, ctx)

	-- Move everyone to the facility and watch for deaths.
	for _, p in participants do
		local char = spawnAt(p, "FacilitySpawn")
		local hum = char:FindFirstChildOfClass("Humanoid")
		if hum then
			table.insert(
				deathConns,
				hum.Died:Connect(function()
					if state[p] then
						state[p].alive = false
					end
				end)
			)
		end
	end
	local leaveConn = Players.PlayerRemoving:Connect(function(p)
		if state[p] then
			state[p].alive = false
		end
	end)

	broadcast("Briefing", {
		seconds = Config.Shift.BriefingSeconds,
		objectives = tracker:Snapshot(),
		rules = rules:PostedTexts(), -- enforcement status is intentionally not sent
	})
	task.wait(Config.Shift.BriefingSeconds)
	rules:Start()

	-- Active phase
	local zone = randomTagged("ExtractZone")
	local startTime = os.clock()
	local escalated = false
	while true do
		local elapsed = os.clock() - startTime
		local remaining = Config.Shift.DurationSeconds - elapsed
		if remaining <= 0 then
			break
		end
		broadcast("Timer", { remaining = math.floor(remaining) })

		director:Step(elapsed)
		rules:Step(elapsed, Config.Shift.DurationSeconds)

		if tracker.Complete and not escalated then
			escalated = true
			director:SetIntensity(Config.Shift.ExtractionIntensity)
		end

		if tracker.Complete and zone then
			for _, p in playersInZone(zone) do
				local s = state[p]
				if s and s.alive and not s.extracted then
					s.extracted = true
					broadcast("Extracted", { name = p.Name })
				end
			end
		end

		if #alivePlayers() == 0 then
			break -- everyone extracted, dead, or gone
		end
		task.wait(1)
	end

	director:StopAll()
	rules:StopAll()
	leaveConn:Disconnect()
	for _, c in deathConns do
		c:Disconnect()
	end

	-- Rewards
	local done = tracker:TotalDone()
	for _, p in participants do
		local s = state[p]
		if p.Parent and DataService.Get(p) then
			local extracted = s.extracted
			local mult = extracted and 1 or R.FailMultiplier
			local credits = (R.BaseCredits + done * R.CreditsPerObjective + (extracted and R.ExtractBonusCredits or 0)) * mult
			local xp = (R.BaseXP + done * R.XPPerObjective + (extracted and R.ExtractBonusXP or 0)) * mult
			DataService.AddCredits(p, credits)
			local levelsGained = DataService.AddXP(p, xp)
			local d = DataService.Get(p)
			d.ShiftsCompleted += 1
			local lore = nil
			if extracted then
				d.Extractions += 1
				lore = pickLore(p)
			end
			ShiftUpdate:FireClient(p, "Results", {
				extracted = extracted,
				credits = math.floor(credits),
				xp = math.floor(xp),
				levelsGained = levelsGained,
				clearance = d.Clearance,
				lore = lore and { title = lore.title, text = lore.text } or nil,
				objectives = tracker:Snapshot(),
			})
		end
	end

	tracker:Cleanup()
	task.wait(Config.Shift.ResultsSeconds)
end

function ShiftManager.Start()
	Players.CharacterAutoLoads = false

	-- Late joiners wait in the lobby until the next shift.
	local function onPlayerAdded(player: Player)
		DataService.WaitFor(player)
		if player.Parent then
			spawnAt(player, "LobbySpawn")
		end
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, p in Players:GetPlayers() do
		task.spawn(onPlayerAdded, p)
	end

	task.spawn(function()
		while true do
			-- Wait for enough players with loaded data.
			repeat
				task.wait(1)
				local ready = 0
				for _, p in Players:GetPlayers() do
					if DataService.Get(p) then
						ready += 1
					end
				end
			until ready >= Config.Shift.MinPlayers

			countdown("Intermission", Config.Shift.IntermissionSeconds)

			local participants = {}
			for _, p in Players:GetPlayers() do
				if DataService.Get(p) then
					table.insert(participants, p)
				end
			end

			if #participants >= Config.Shift.MinPlayers then
				runShift(participants)
				for _, p in Players:GetPlayers() do
					if p.Parent then
						task.spawn(spawnAt, p, "LobbySpawn")
					end
				end
			end
		end
	end)
end

return ShiftManager
