--!nocheck
--[[
	AssetServiceDropIn Example

	Swaps game:GetService("AssetService") for client:getAssetService() and
	leaves the rest of the call site alone — same AudioSearchParams, same
	AudioPages iteration. Search runs against AudioScape's catalog instead of
	Roblox's keyword index; everything else on the service still forwards to
	the real thing.
]]

local ServerScriptService = game:GetService("ServerScriptService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

local AudioScape = require(ServerScriptService.Packages.AudioScape)

local apiKey = if RunService:IsStudio() then "your-test-key" else HttpService:GetSecret("AudioScapeKey")

local client = AudioScape.new(apiKey)

-- The one line that changes. Everything below is ordinary AssetService code.
local AssetService = client:getAssetService()

local params = Instance.new("AudioSearchParams")
params.SearchKeyword = "rainy night city jazz"
params.AudioSubType = Enum.AudioSubType.Music
params.MinDuration = 60

-- Native SearchAudioAsync throws rather than returning an error, and so does
-- the shim — keep the pcall you already had.
local ok, pages = pcall(function()
	return AssetService:SearchAudioAsync(params)
end)
if not ok then
	warn("Audio search failed:", pages)
	return
end

for _, audio in pages:GetCurrentPage() do
	-- Native fields, unchanged.
	print(string.format("%s — %s (%ds)", audio.Title, audio.Artist, audio.Duration))

	-- Extra fields the native API has no equivalent for.
	if audio.Bpm then
		print(string.format("    %s · %d BPM · score %.2f", audio.Genre, audio.Bpm, audio.Score))
	end
end

-- Paging is the same too.
if not pages.IsFinished then
	pages:AdvanceToNextPageAsync()
	print("Next page:", #pages:GetCurrentPage(), "more results")
end

-- Play the top result. AssetId is the string form, ready to concatenate.
local first = pages:GetCurrentPage()[1]
if first then
	local audioPlayer = Instance.new("AudioPlayer")
	audioPlayer.Asset = "rbxassetid://" .. first.AssetId
	audioPlayer.Parent = workspace

	local output = Instance.new("AudioDeviceOutput")
	output.Parent = workspace

	local wire = Instance.new("Wire")
	wire.SourceInstance = audioPlayer
	wire.TargetInstance = output
	wire.Parent = audioPlayer

	audioPlayer:Play()
end

-- Members we don't override forward to the real AssetService, so this still
-- works and still returns everything the engine gives you.
if first then
	local metadata = AssetService:GetAudioMetadataAsync({ "rbxassetid://" .. first.AssetId })
	print("Engine metadata:", metadata[1].Title, "by", metadata[1].Artist)
end
