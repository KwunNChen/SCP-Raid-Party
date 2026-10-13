-- Minimal DataStore wrapper: load with retry, autosave, save on leave / shutdown.
-- For production consider ProfileStore (session locking); this is enough for an MVP.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local STORE_NAME = "PlayerData_v1"
local AUTOSAVE_SECONDS = 120
local RETRIES = 3

local store = DataStoreService:GetDataStore(STORE_NAME)

local TEMPLATE = {
	Credits = 0,
	ClearanceXP = 0,
	Clearance = 1,
	ShiftsCompleted = 0,
	Extractions = 0,
	Owned = {},
	LoreUnlocked = {},
}

local DataService = {}
local profiles: { [Player]: any } = {}
local loadFailed: { [Player]: boolean } = {}

local function deepCopy(t)
	local out = {}
	for k, v in t do
		out[k] = type(v) == "table" and deepCopy(v) or v
	end
	return out
end

local function reconcile(data, template)
	for k, v in template do
		if data[k] == nil then
			data[k] = type(v) == "table" and deepCopy(v) or v
		end
	end
	return data
end

local function withRetry(fn)
	local ok, result
	for attempt = 1, RETRIES do
		ok, result = pcall(fn)
		if ok then
			return true, result
		end
		task.wait(attempt)
	end
	return false, result
end

local function load(player: Player)
	local key = "Player_" .. player.UserId
	local ok, data = withRetry(function()
		return store:GetAsync(key)
	end)
	if not ok then
		warn("[DataService] load failed for", player.Name, data)
		loadFailed[player] = true
		player:Kick("Could not load your data. Please rejoin.")
		return
	end
	profiles[player] = reconcile(data or {}, TEMPLATE)
end

local function save(player: Player)
	local data = profiles[player]
	if not data or loadFailed[player] then
		return
	end
	local key = "Player_" .. player.UserId
	local ok, err = withRetry(function()
		return store:UpdateAsync(key, function()
			return data
		end)
	end)
	if not ok then
		warn("[DataService] save failed for", player.Name, err)
	end
end

function DataService.Get(player: Player)
	return profiles[player]
end

function DataService.WaitFor(player: Player)
	while player.Parent and not profiles[player] and not loadFailed[player] do
		task.wait(0.1)
	end
	return profiles[player]
end

function DataService.AddCredits(player: Player, amount: number)
	local d = profiles[player]
	if d then
		d.Credits += math.floor(amount)
	end
end

-- Returns number of levels gained.
function DataService.AddXP(player: Player, amount: number): number
	local d = profiles[player]
	if not d then
		return 0
	end
	d.ClearanceXP += math.floor(amount)
	local gained = 0
	while d.Clearance < Config.MaxClearance and d.ClearanceXP >= Config.XPForLevel(d.Clearance) do
		d.ClearanceXP -= Config.XPForLevel(d.Clearance)
		d.Clearance += 1
		gained += 1
	end
	return gained
end

function DataService.UnlockLore(player: Player, id: string): boolean
	local d = profiles[player]
	if not d or table.find(d.LoreUnlocked, id) then
		return false
	end
	table.insert(d.LoreUnlocked, id)
	return true
end

function DataService.Spend(player: Player, amount: number): boolean
	local d = profiles[player]
	if not d or d.Credits < amount then
		return false
	end
	d.Credits -= amount
	return true
end

function DataService.Init()
	Players.PlayerAdded:Connect(load)
	for _, p in Players:GetPlayers() do
		task.spawn(load, p)
	end

	Players.PlayerRemoving:Connect(function(player)
		save(player)
		profiles[player] = nil
		loadFailed[player] = nil
	end)

	task.spawn(function()
		while true do
			task.wait(AUTOSAVE_SECONDS)
			for player in profiles do
				task.spawn(save, player)
			end
		end
	end)

	game:BindToClose(function()
		local pending = 0
		for player in profiles do
			pending += 1
			task.spawn(function()
				save(player)
				pending -= 1
			end)
		end
		while pending > 0 do
			task.wait()
		end
	end)
end

return DataService
