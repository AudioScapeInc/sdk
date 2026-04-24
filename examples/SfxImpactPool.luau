--!nocheck
--[[
	SfxImpactPool Example

	Pre-fetches a pool of short metallic impact sounds at server start
	and plays a random one on every swing. Avoids the "same clip every
	time" feel that gives away looping audio.
]]

local ServerScriptService = game:GetService("ServerScriptService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

local AudioScape = require(ServerScriptService.Packages.AudioScape)

local apiKey = if RunService:IsStudio() then "your-test-key" else HttpService:GetSecret("AudioScapeKey")

local client = AudioScape.new(apiKey)

local result, err = client:sfxSearch({
	query = "metal sword impact short",
	limit = 10,
	filters = { duration = { min = 0, max = 1 } },
})
if not result then
	warn("Failed to fetch impact pool:", err)
	return
end

local impactIds = {}
for _, sfx in result.tracks do
	table.insert(impactIds, sfx.asset_id)
end

print(string.format("Loaded %d impact clips", #impactIds))

local function playRandomImpact(parent: Instance)
	local sound = Instance.new("Sound")
	sound.SoundId = "rbxassetid://" .. impactIds[math.random(#impactIds)]
	sound.Parent = parent
	sound:Play()
	sound.Ended:Once(function()
		sound:Destroy()
	end)
end

-- Demo: play one immediately
playRandomImpact(workspace)

-- In a real game, hook this into a weapon's swing event:
-- weapon.OnSwing:Connect(function(hitPart)
--     playRandomImpact(hitPart)
-- end)
