local Config = {}

Config.Shift = {
	MinPlayers = 1,
	IntermissionSeconds = 20,
	BriefingSeconds = 8,
	DurationSeconds = 360,
	ResultsSeconds = 12,
	ExtractionIntensity = 1.5,
}

Config.Rewards = {
	BaseCredits = 25,
	CreditsPerObjective = 15,
	ExtractBonusCredits = 40,
	BaseXP = 20,
	XPPerObjective = 15,
	ExtractBonusXP = 40,
	FailMultiplier = 0.25,
}

Config.MaxClearance = 10

function Config.XPForLevel(level: number): number
	return 100 + level * 60
end

-- Objective pool. `tag` is a CollectionService tag; every tagged instance needs a ProximityPrompt
-- (as the instance itself or a descendant).
Config.ObjectivePool = {
	{ id = "DataCore", label = "Recover Data Cores", tag = "ObjDataCore", minClearance = 1, min = 2, max = 4 },
	{ id = "Console", label = "Restore Consoles", tag = "ObjConsole", minClearance = 3, min = 1, max = 2 },
	{ id = "Valve", label = "Reset Coolant Valves", tag = "ObjValve", minClearance = 1, min = 1, max = 2 },
}

-- Lore files. Add more here; one is unlocked per extracted shift.
Config.Lore = {
	{ id = "L001", title = "Orientation Memo", minClearance = 1, text = "Welcome to Site Halden. Do not ask who the previous shift was." },
	{ id = "L002", title = "Terminal Log 0417", minClearance = 1, text = "03:12 - Door 6 reported open. Door 6 has no hinges." },
	{ id = "L003", title = "Audio Memo: R. Ames", minClearance = 2, text = "[static] ...if you can hear this, the count was always one more than the roster." },
	{ id = "L004", title = "Incident Report H-9", minClearance = 3, text = "Cause of blackout: unknown. Cause of the silence afterward: unknown." },
}

return Config
