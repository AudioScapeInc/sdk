--!strict
--[[
	SearchBox Example

	Connects a TextBox to AudioScape search. Type a query, press Enter,
	and results appear in the output. Replace the print statements with
	your own UI logic.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

local AudioScape = require(ReplicatedStorage.Packages.AudioScape)

-- Use a test key in Studio, Secrets Store in production
local apiKey = if RunService:IsStudio()
	then "your-test-key"
	else HttpService:GetSecret("AudioScapeKey")

local client = AudioScape.new(apiKey)

-- Wire up to a TextBox (e.g., in a ScreenGui)
local textBox = script.Parent :: TextBox

textBox.FocusLost:Connect(function(enterPressed: boolean)
	if not enterPressed then
		return
	end

	local query = textBox.Text
	if #query == 0 then
		return
	end

	local result, err = client:search({
		query = query,
		limit = 10,
	})

	if not result then
		warn("Search failed:", err)
		return
	end

	print("Found", result.meta.total, "tracks for:", query)

	for _, track in result.tracks do
		print(string.format("  %s - %s (ID: %s)", track.artist, track.name, track.asset_id))
	end
end)
