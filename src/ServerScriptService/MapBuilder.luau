-- Turns an ASCII layout into blockout geometry. No modeling needed.
--
-- Legend:
--   #  wall            (space) void
--   .  floor           P  player spawn
--   E  extraction area (all E cells form one zone)
--   V  objective area  (all V cells form one objective with a ProximityPrompt)
--   L  ceiling lamp    1-9 guard waypoint (referenced by Mission.Guards routes)
-- Everything that is not '#' or ' ' gets a floor and ceiling.

local CollectionService = game:GetService("CollectionService")

local MapBuilder = {}

local CELL = 8 -- studs per grid cell
local WALL_HEIGHT = 12

local WALL_COLOR = Color3.fromRGB(58, 60, 64)
local FLOOR_COLOR = Color3.fromRGB(38, 40, 43)

local function newPart(parent: Instance, name: string, size: Vector3, position: Vector3, color: Color3, material: Enum.Material?)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Position = position
	p.Anchored = true
	p.Color = color
	p.Material = material or Enum.Material.Concrete
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- Calls fn(startCol, endCol) for each run of consecutive characters matching pred.
local function forEachRun(line: string, pred: (string) -> boolean, fn: (number, number) -> ())
	local start: number? = nil
	for col = 1, #line + 1 do
		local ch = col <= #line and line:sub(col, col) or ""
		if ch ~= "" and pred(ch) then
			start = start or col
		elseif start then
			fn(start, col - 1)
			start = nil
		end
	end
end

local function isWall(ch: string): boolean
	return ch == "#"
end

local function isFloor(ch: string): boolean
	return ch ~= "#" and ch ~= " "
end

function MapBuilder.build(layout: { string }, origin: Vector3?)
	origin = origin or Vector3.zero
	local base = origin :: Vector3

	local folder = Instance.new("Folder")
	folder.Name = "MissionMap"

	local result = {
		Folder = folder,
		PlayerSpawns = {} :: { Vector3 },
		Waypoints = {} :: { [number]: Vector3 },
		Objective = nil :: BasePart?,
		ExtractZone = nil :: BasePart?,
	}

	local boxes: { [string]: { minC: number, maxC: number, minR: number, maxR: number } } = {}

	-- Merged walls, floors and ceilings (one part per horizontal run keeps part count low).
	for row, line in layout do
		local z = (row - 0.5) * CELL

		forEachRun(line, isWall, function(s, e)
			local width = (e - s + 1) * CELL
			local x = (s - 1 + e) / 2 * CELL
			newPart(folder, "Wall", Vector3.new(width, WALL_HEIGHT, CELL), base + Vector3.new(x, WALL_HEIGHT / 2, z), WALL_COLOR)
		end)

		forEachRun(line, isFloor, function(s, e)
			local width = (e - s + 1) * CELL
			local x = (s - 1 + e) / 2 * CELL
			newPart(folder, "Floor", Vector3.new(width, 1, CELL), base + Vector3.new(x, -0.5, z), FLOOR_COLOR)
			newPart(folder, "Ceiling", Vector3.new(width, 1, CELL), base + Vector3.new(x, WALL_HEIGHT + 0.5, z), WALL_COLOR)
		end)
	end

	-- Special cells.
	for row, line in layout do
		for col = 1, #line do
			local ch = line:sub(col, col)
			local center = base + Vector3.new((col - 0.5) * CELL, 0, (row - 0.5) * CELL)

			if ch == "P" then
				table.insert(result.PlayerSpawns, center + Vector3.new(0, 3, 0))
			elseif ch == "L" then
				local lamp = newPart(folder, "Lamp", Vector3.new(3, 0.5, 3), center + Vector3.new(0, WALL_HEIGHT - 0.25, 0), Color3.fromRGB(255, 240, 200), Enum.Material.Neon)
				local light = Instance.new("PointLight")
				light.Range = 30
				light.Brightness = 1.4
				light.Color = Color3.fromRGB(255, 225, 170)
				light.Parent = lamp
				CollectionService:AddTag(lamp, "FacilityLight")
			elseif tonumber(ch) then
				result.Waypoints[tonumber(ch) :: number] = center + Vector3.new(0, 3, 0)
			end

			if ch == "V" or ch == "E" then
				local box = boxes[ch]
				if not box then
					boxes[ch] = { minC = col, maxC = col, minR = row, maxR = row }
				else
					box.minC = math.min(box.minC, col)
					box.maxC = math.max(box.maxC, col)
					box.minR = math.min(box.minR, row)
					box.maxR = math.max(box.maxR, row)
				end
			end
		end
	end

	local function boxCenter(box)
		return base + Vector3.new((box.minC - 1 + box.maxC) / 2 * CELL, 0, (box.minR - 1 + box.maxR) / 2 * CELL)
	end

	local vBox = boxes.V
	if vBox then
		local obj = newPart(folder, "Objective", Vector3.new(3, 3, 3), boxCenter(vBox) + Vector3.new(0, 2.5, 0), Color3.fromRGB(255, 190, 60), Enum.Material.Neon)
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Take"
		prompt.ObjectText = "Prototype Core"
		prompt.HoldDuration = 1.5
		prompt.MaxActivationDistance = 8
		prompt.Parent = obj
		result.Objective = obj
	end

	local eBox = boxes.E
	if eBox then
		local size = Vector3.new((eBox.maxC - eBox.minC + 1) * CELL, 8, (eBox.maxR - eBox.minR + 1) * CELL)
		local zone = newPart(folder, "ExtractZone", size, boxCenter(eBox) + Vector3.new(0, 4, 0), Color3.fromRGB(80, 200, 120))
		zone.Transparency = 1
		zone.CanCollide = false
		CollectionService:AddTag(zone, "ExtractZone")
		result.ExtractZone = zone
	end

	folder.Parent = workspace
	return result
end

return MapBuilder
