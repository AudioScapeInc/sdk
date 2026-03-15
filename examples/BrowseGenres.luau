--!strict
--[[
	BrowseGenres Example

	Lists all available genres, picks one, fetches its tracks,
	and plays a random track via SoundService.
]]

local ServerScriptService = game:GetService("ServerScriptService")
local SoundService = game:GetService("SoundService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

local AudioScape = require(ServerScriptService.Packages.AudioScape)

local apiKey = if RunService:IsStudio()
	then "your-test-key"
	else HttpService:GetSecret("AudioScapeKey")

local client = AudioScape.new(apiKey)

-- Step 1: List all genres
local genres, err = client:browse({ type = "genre" })
if not genres then
	warn("Failed to list genres:", err)
	return
end

print("Available genres:")
for _, genre in genres.items do
	print(string.format("  %s — %d tracks", genre.display_name, genre.track_count))
end

-- Step 2: Pick a genre and get its tracks
local picked = genres.items[math.random(#genres.items)]
print("\nBrowsing:", picked.display_name)

local tracks, trackErr = client:browse({
	type = "genre",
	name = picked.name,
	limit = 10,
})

if not tracks then
	warn("Failed to get genre tracks:", trackErr)
	return
end

-- Step 3: Play a random track
local track = tracks.tracks[math.random(#tracks.tracks)]
print(string.format("Playing: %s - %s", track.artist, track.name))

local sound = Instance.new("Sound")
sound.SoundId = "rbxassetid://" .. track.asset_id
sound.Parent = SoundService
sound:Play()
