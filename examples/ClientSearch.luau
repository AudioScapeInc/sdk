--!strict
--[[
	Client Search Example

	Demonstrates how to search from a LocalScript using AudioScapeClient.
	Requires enableClientAccess() to be called on the server.

	Setup:
	1. Place AudioScapeClient.luau in ReplicatedStorage
	2. Add a TextBox named "SearchInput" inside a ScreenGui in StarterGui
	3. Use the server script below to enable client access
	4. Use the client script below in a LocalScript inside the ScreenGui
]]

-- === SERVER SCRIPT (ServerScriptService) ===

--[[
local ServerStorage = game:GetService("ServerStorage")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

local AudioScape = require(ServerStorage.AudioScape)

local apiKey = if RunService:IsStudio()
	then "your-test-key"
	else HttpService:GetSecret("AudioScapeKey")

local client = AudioScape.new(apiKey)
client:enableClientAccess()
]]

-- === CLIENT SCRIPT (LocalScript in ScreenGui) ===

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local AudioScapeClient = require(ReplicatedStorage:WaitForChild("AudioScapeClient"))
local client = AudioScapeClient.new()

local player = Players.LocalPlayer
local gui = player.PlayerGui:WaitForChild("ScreenGui")
local searchInput = gui:WaitForChild("SearchInput") :: TextBox

searchInput.FocusLost:Connect(function(enterPressed)
	if not enterPressed or searchInput.Text == "" then
		return
	end

	local result, err = client:search({ query = searchInput.Text, limit = 10 })
	if not result then
		warn("Search failed:", err)
		return
	end

	for _, track in result.tracks do
		print(string.format("%s — %s (%s)", track.artist, track.name, track.genre))
	end
end)
