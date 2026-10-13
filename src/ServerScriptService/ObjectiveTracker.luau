-- Builds a randomized task list for one shift and tracks team progress.
-- Tagged objective instances (see Config.ObjectivePool) need a ProximityPrompt.
-- Instances not chosen for this shift are stashed in ServerStorage and restored on Cleanup.

local CollectionService = game:GetService("CollectionService")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local ObjectiveTracker = {}
ObjectiveTracker.__index = ObjectiveTracker

local function findPrompts(instance: Instance): { ProximityPrompt }
	local prompts = {}
	if instance:IsA("ProximityPrompt") then
		table.insert(prompts, instance)
	end
	for _, d in instance:GetDescendants() do
		if d:IsA("ProximityPrompt") then
			table.insert(prompts, d)
		end
	end
	return prompts
end

local function shuffle(list)
	for i = #list, 2, -1 do
		local j = math.random(i)
		list[i], list[j] = list[j], list[i]
	end
	return list
end

function ObjectiveTracker.new(clearance: number)
	local self = setmetatable({}, ObjectiveTracker)
	self.Objectives = {}
	self._stash = {} -- [instance] = original parent
	self._connections = {}
	self._changed = Instance.new("BindableEvent")
	self.Changed = self._changed.Event
	self.Complete = false

	local stashFolder = ServerStorage:FindFirstChild("ObjectiveStash")
	if not stashFolder then
		stashFolder = Instance.new("Folder")
		stashFolder.Name = "ObjectiveStash"
		stashFolder.Parent = ServerStorage
	end
	self._stashFolder = stashFolder

	-- Choose 2-3 objective types eligible for this clearance.
	local eligible = {}
	for _, def in Config.ObjectivePool do
		if def.minClearance <= clearance and #CollectionService:GetTagged(def.tag) > 0 then
			table.insert(eligible, def)
		end
	end
	shuffle(eligible)

	for i = 1, math.min(#eligible, 3) do
		local def = eligible[i]
		local instances = shuffle(CollectionService:GetTagged(def.tag))
		local count = math.min(math.random(def.min, def.max), #instances)
		local objective = { id = def.id, label = def.label, required = count, done = 0 }
		table.insert(self.Objectives, objective)

		for n, inst in instances do
			if n <= count then
				self:_arm(inst, objective)
			else
				self._stash[inst] = inst.Parent
				inst.Parent = stashFolder
			end
		end
	end

	return self
end

function ObjectiveTracker:_arm(inst: Instance, objective)
	local highlight = Instance.new("Highlight")
	highlight.FillTransparency = 1
	highlight.OutlineColor = Color3.fromRGB(255, 200, 80)
	highlight.Parent = inst
	self._stash[highlight] = false -- marker: destroy on cleanup

	for _, prompt in findPrompts(inst) do
		prompt.Enabled = true
		local conn
		conn = prompt.Triggered:Connect(function(player)
			conn:Disconnect()
			prompt.Enabled = false
			highlight:Destroy()
			objective.done += 1
			self:_refresh(player)
		end)
		table.insert(self._connections, conn)
	end
end

function ObjectiveTracker:_refresh(player: Player?)
	local all = true
	for _, o in self.Objectives do
		if o.done < o.required then
			all = false
		end
	end
	self.Complete = all
	self._changed:Fire(player)
end

function ObjectiveTracker:TotalDone(): number
	local n = 0
	for _, o in self.Objectives do
		n += o.done
	end
	return n
end

function ObjectiveTracker:Snapshot()
	local out = {}
	for _, o in self.Objectives do
		table.insert(out, { label = o.label, done = o.done, required = o.required })
	end
	return out
end

function ObjectiveTracker:Cleanup()
	for _, c in self._connections do
		c:Disconnect()
	end
	for inst, parent in self._stash do
		if parent == false then
			if inst.Parent then
				inst:Destroy()
			end
		else
			inst.Parent = parent
		end
	end
	for _, o in self.Objectives do
		-- re-enable prompts for next shift's selection pass
		o.done = 0
	end
	self._changed:Destroy()
end

return ObjectiveTracker
