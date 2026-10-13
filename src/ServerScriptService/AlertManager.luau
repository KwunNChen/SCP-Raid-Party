-- Global alert level for the site: 0 (calm) to 3 (lockdown).
-- Rises when guards spot a player, decays after a calm period. Lockdown does not decay.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MAX_LEVEL = 3
local RAISE_COOLDOWN = 6 -- seconds between level increases
local CALM_SECONDS_PER_DROP = 30

local AlertManager = {}
AlertManager.__index = AlertManager

function AlertManager.new()
	local self = setmetatable({}, AlertManager)
	self.Level = 0
	self._lastRaise = -math.huge
	self._calmFor = 0
	self._lockdown = Instance.new("BindableEvent")
	self.Lockdown = self._lockdown.Event
	ReplicatedStorage:SetAttribute("AlertLevel", 0)
	return self
end

function AlertManager:_set(level: number)
	self.Level = level
	ReplicatedStorage:SetAttribute("AlertLevel", level)
end

function AlertManager:Raise()
	local now = os.clock()
	if now - self._lastRaise < RAISE_COOLDOWN or self.Level >= MAX_LEVEL then
		return
	end
	self._lastRaise = now
	self._calmFor = 0
	self:_set(self.Level + 1)
	if self.Level == MAX_LEVEL then
		self._lockdown:Fire()
	end
end

-- Call every tick. `anyChasing` is true while any guard is in the Chase state.
function AlertManager:Update(anyChasing: boolean, dt: number)
	if anyChasing then
		self._calmFor = 0
		return
	end
	if self.Level == 0 or self.Level >= MAX_LEVEL then
		return
	end
	self._calmFor += dt
	if self._calmFor >= CALM_SECONDS_PER_DROP then
		self._calmFor = 0
		self:_set(self.Level - 1)
	end
end

function AlertManager:Destroy()
	self._lockdown:Destroy()
	ReplicatedStorage:SetAttribute("AlertLevel", 0)
end

return AlertManager
