--!nocheck
--[[
	StructureBeatSync Example

	Fetches the beat grid + section structure for a track and schedules
	particle bursts on every downbeat. Also demonstrates querying the
	current section at runtime to drive different effects on Drops vs
	Verses.
]]

local ServerScriptService = game:GetService("ServerScriptService")
local SoundService = game:GetService("SoundService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

local AudioScape = require(ServerScriptService.Packages.AudioScape)

local apiKey = if RunService:IsStudio() then "your-test-key" else HttpService:GetSecret("AudioScapeKey")

AudioScape.setApiKey(apiKey)

local ASSET_ID = "1843209165"

local structure, err = AudioScape:getStructure({ asset_id = ASSET_ID })
if not structure then
	warn("Failed to fetch structure:", err)
	return
end

print(
	string.format("Track: %s BPM, energy=%d, %d sections", structure.bpm, structure.track_energy, #structure.sections)
)

-- A particle emitter you've configured in the Explorer
local emitter = workspace:FindFirstChild("BeatEmitter") :: ParticleEmitter?

-- Schedule a burst on every downbeat
if emitter and structure.beat_grid then
	for _, t in structure.beat_grid.downbeats do
		task.delay(t, function()
			emitter:Emit(20)
		end)
	end
end

-- Start the audio so the scheduled bursts line up
local sound = Instance.new("Sound")
sound.SoundId = "rbxassetid://" .. ASSET_ID
sound.Parent = SoundService
sound:Play()

-- During playback, use sectionAtTime to drive runtime effects
local camera = workspace.CurrentCamera
task.spawn(function()
	while sound.IsPlaying do
		local section = AudioScape:sectionAtTime(ASSET_ID, sound.TimePosition)
		if section and section.label == "Drop" and section.energy then
			camera.FieldOfView = 70 + section.energy * 5
		else
			camera.FieldOfView = 70
		end
		task.wait(0.25)
	end
end)
