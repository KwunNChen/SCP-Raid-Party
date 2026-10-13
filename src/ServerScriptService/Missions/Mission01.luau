-- A campaign mission is just data. Add Mission02, Mission03, ... in this folder.
-- Layout is 28 columns x 7 rows. See MapBuilder for the legend.

local WALL = string.rep("#", 28)

return {
	Name = "First Night",
	Briefing = "Take the Prototype Core from the vault and get back to the extraction point. Stay out of sight.",

	Layout = {
		WALL,
		"#PP.#...L....#.....L.......#",
		"#PP.#...1....#....3......VV#",
		"#" .. string.rep(".", 26) .. "#",
		"#EEE#...2....#.....4.......#",
		"#EEE#........#.............#",
		WALL,
	},

	-- Each guard patrols its waypoints (digits from the layout) in order, looping.
	Guards = {
		{ route = { 1, 2 } },
		{ route = { 3, 4 } },
	},
}
