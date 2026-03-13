--!strict
--[[
	SimilarTrack Example

	Finds tracks that sound similar to the currently playing sound
	and queues the next one. Great for building auto-playlists.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

local AudioScape = require(ReplicatedStorage.Packages.AudioScape)

local apiKey = if RunService:IsStudio()
	then "your-test-key"
	else HttpService:GetSecret("AudioScapeKey")

local client = AudioScape.new(apiKey)

local function getAssetId(sound: Sound): string?
	local match = string.match(sound.SoundId, "%d+")
	return match
end

local function playNext(currentAssetId: string)
	local result, err = client:similar({
		asset_id = currentAssetId,
		limit = 5,
	})

	if not result or #result.tracks == 0 then
		warn("Could not find similar tracks:", err or "no results")
		return
	end

	-- Pick a random similar track
	local next = result.tracks[math.random(#result.tracks)]
	print(string.format("Up next: %s - %s", next.artist, next.name))

	local sound = Instance.new("Sound")
	sound.SoundId = "rbxassetid://" .. next.asset_id
	sound.Parent = SoundService

	-- When this track ends, find the next similar one
	sound.Ended:Once(function()
		sound:Destroy()
		playNext(next.asset_id)
	end)

	sound:Play()
end

-- Start with any Sound already in SoundService
local currentSound = SoundService:FindFirstChildWhichIsA("Sound") :: Sound?
if currentSound then
	local assetId = getAssetId(currentSound)
	if assetId then
		currentSound.Ended:Once(function()
			playNext(assetId)
		end)
		print("Waiting for current track to end, then auto-playing similar tracks...")
	end
else
	warn("No Sound found in SoundService. Add a Sound to get started.")
end
