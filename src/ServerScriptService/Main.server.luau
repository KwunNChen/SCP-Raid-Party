local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Remotes
local remotes = Instance.new("Folder")
remotes.Name = "Remotes"
local shiftUpdate = Instance.new("RemoteEvent")
shiftUpdate.Name = "ShiftUpdate"
shiftUpdate.Parent = remotes
remotes.Parent = ReplicatedStorage

local DataService = require(script.Parent.DataService)
local ShiftManager = require(script.Parent.ShiftManager)

DataService.Init()
ShiftManager.Start()
