-- Minimal debug HUD for Stage 0: detection meter, alert level, mission messages.
-- Replace with real UI later (see the roblox-dev:roblox-ui skill).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

local gui = Instance.new("ScreenGui")
gui.Name = "DebugHUD"
gui.ResetOnSpawn = false
gui.Parent = player:WaitForChild("PlayerGui")

local function makeLabel(position: UDim2, size: UDim2, textSize: number): TextLabel
	local label = Instance.new("TextLabel")
	label.Position = position
	label.Size = size
	label.BackgroundTransparency = 0.5
	label.BackgroundColor3 = Color3.new(0, 0, 0)
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextSize = textSize
	label.Font = Enum.Font.Code
	label.Text = ""
	label.Parent = gui
	return label
end

local status = makeLabel(UDim2.new(0, 12, 0, 12), UDim2.new(0, 320, 0, 34), 18)
local banner = makeLabel(UDim2.new(0.5, -300, 0, 60), UDim2.new(0, 600, 0, 40), 18)
banner.Visible = false

local bannerToken = 0
local remote = ReplicatedStorage:WaitForChild("Stage0Message")
remote.OnClientEvent:Connect(function(text: string)
	bannerToken += 1
	local token = bannerToken
	banner.Text = text
	banner.Visible = true
	task.delay(6, function()
		if token == bannerToken then
			banner.Visible = false
		end
	end)
end)

RunService.RenderStepped:Connect(function()
	local detection = math.floor((player:GetAttribute("Detection") or 0) * 100)
	local alert = ReplicatedStorage:GetAttribute("AlertLevel") or 0
	status.Text = ("Detection: %d%%   Alert: %d"):format(detection, alert)
end)
