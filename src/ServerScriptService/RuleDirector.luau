-- Rule system: each shift posts a few rules over the PA. Some are enforced, some are decoys.
-- Mid-shift amendments can revoke or add enforcement. Enforcement is done by server polling.
--
-- ctx = { alivePlayers = () -> {Player}, announce = (string) -> () }
-- Optional workspace tag: RuleZoneMaintenance (parts marking the Maintenance Corridor).

local CollectionService = game:GetService("CollectionService")

local function insideBox(part: BasePart, position: Vector3): boolean
	local rel = part.CFrame:PointToObjectSpace(position)
	local half = part.Size / 2
	return math.abs(rel.X) <= half.X and math.abs(rel.Y) <= half.Y and math.abs(rel.Z) <= half.Z
end

local function hrpOf(player: Player): BasePart?
	return player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function humOf(player: Player): Humanoid?
	return player.Character and player.Character:FindFirstChildOfClass("Humanoid")
end

-- Each rule: Text, MinClearance, Enforce(ctx) -> stop()
local Rules = {}

Rules.NoJump = {
	Text = "Do not jump.",
	MinClearance = 1,
	Enforce = function(ctx)
		local running = true
		local cooldown = {}
		task.spawn(function()
			while running do
				for _, p in ctx.alivePlayers() do
					local hum = humOf(p)
					if hum and hum:GetState() == Enum.HumanoidStateType.Jumping then
						if os.clock() - (cooldown[p] or 0) > 1 then
							cooldown[p] = os.clock()
							hum:TakeDamage(20)
						end
					end
				end
				task.wait(0.1)
			end
		end)
		return function()
			running = false
		end
	end,
}

Rules.KeepMoving = {
	Text = "Do not stand still.",
	MinClearance = 1,
	Enforce = function(ctx)
		local running = true
		local still, last = {}, {}
		task.spawn(function()
			while running do
				task.wait(0.5)
				for _, p in ctx.alivePlayers() do
					local hrp, hum = hrpOf(p), humOf(p)
					if hrp and hum then
						local prev = last[p]
						still[p] = (prev and (hrp.Position - prev).Magnitude < 1) and (still[p] or 0) + 0.5 or 0
						last[p] = hrp.Position
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

Rules.MaintenanceCorridor = {
	Text = "Stay out of the Maintenance Corridor while the PA is playing.",
	MinClearance = 2,
	Enforce = function(ctx)
		local running = true
		task.spawn(function()
			while running do
				task.wait(1)
				for _, zone in CollectionService:GetTagged("RuleZoneMaintenance") do
					for _, p in ctx.alivePlayers() do
						local hrp, hum = hrpOf(p), humOf(p)
						if hrp and hum and insideBox(zone, hrp.Position) then
							hum:TakeDamage(10)
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

---------------------------------------------------------------------------

local RuleDirector = {}
RuleDirector.__index = RuleDirector

local function shuffle(list)
	for i = #list, 2, -1 do
		local j = math.random(i)
		list[i], list[j] = list[j], list[i]
	end
	return list
end

function RuleDirector.new(clearance: number, ctx)
	local self = setmetatable({}, RuleDirector)
	self.Ctx = ctx
	self.Posted = {} -- { id, text, enforced, stop }
	self._amended = false

	local eligible = {}
	for id, def in Rules do
		if def.MinClearance <= clearance then
			table.insert(eligible, id)
		end
	end
	shuffle(eligible)

	local count = math.min(#eligible, 2 + math.floor(clearance / 3))
	local anyEnforced = false
	for i = 1, count do
		local enforced = math.random() > 0.3
		anyEnforced = anyEnforced or enforced
		table.insert(self.Posted, { id = eligible[i], text = Rules[eligible[i]].Text, enforced = enforced })
	end
	if #self.Posted > 0 and not anyEnforced then
		self.Posted[1].enforced = true -- at least one rule must be real
	end

	return self
end

function RuleDirector:_enforce(rule)
	if rule.enforced and not rule.stop then
		rule.stop = Rules[rule.id].Enforce(self.Ctx)
	end
end

function RuleDirector:_revoke(rule)
	rule.enforced = false
	if rule.stop then
		rule.stop()
		rule.stop = nil
	end
end

-- Texts only. Enforcement status is deliberately NOT sent to clients.
function RuleDirector:PostedTexts(): { string }
	local out = {}
	for i, r in self.Posted do
		table.insert(out, i .. ". " .. r.text)
	end
	return out
end

function RuleDirector:Start()
	self.Ctx.announce("STATION RULES IN EFFECT. COMPLY.")
	for _, r in self.Posted do
		self:_enforce(r)
	end
end

-- Call every second with elapsed shift seconds and total shift length.
function RuleDirector:Step(elapsed: number, total: number)
	if self._amended or elapsed < total * 0.5 or #self.Posted == 0 then
		return
	end
	self._amended = true

	local pick = math.random(#self.Posted)
	local rule = self.Posted[pick]
	if rule.enforced then
		self:_revoke(rule)
		self.Ctx.announce(("AMENDMENT: Rule %d is revoked."):format(pick))
	else
		rule.enforced = true
		self:_enforce(rule)
		self.Ctx.announce(("AMENDMENT: Rule %d now applies."):format(pick))
	end
end

function RuleDirector:StopAll()
	for _, r in self.Posted do
		if r.stop then
			r.stop()
			r.stop = nil
		end
	end
end

return RuleDirector
