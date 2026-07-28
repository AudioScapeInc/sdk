--!nocheck
--[[
	TrendingSfxBoard Example

	Lobby "sound board": fetch today's trending SFX and render a button per
	clip. Tap to preview. Great for discovery surfaces, creator menus, or
	a "what's hot" panel in your hub.
]]

local ServerScriptService = game:GetService("ServerScriptService")
local SoundService = game:GetService("SoundService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local AudioScape = require(ServerScriptService.Packages.AudioScape)

local apiKey = if RunService:IsStudio() then "your-test-key" else HttpService:GetSecret("AudioScapeKey")

AudioScape.setApiKey(apiKey)

local result, err = AudioScape:sfxBrowse({ type = "trending", limit = 25 })
if not result then
	warn("Trending SFX fetch failed:", err)
	return
end

local function buildBoard(player: Player)
	local gui = Instance.new("ScreenGui")
	gui.Name = "TrendingSfxBoard"
	gui.ResetOnSpawn = false
	gui.Parent = player:WaitForChild("PlayerGui")

	local list = Instance.new("ScrollingFrame")
	list.Size = UDim2.fromOffset(260, 420)
	list.Position = UDim2.new(1, -280, 0.5, -210)
	list.BackgroundTransparency = 0.2
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new()
	list.Parent = gui

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 4)
	layout.Parent = list

	for _, sfx in result.tracks do
		local button = Instance.new("TextButton")
		button.Text = sfx.name
		button.Size = UDim2.new(1, -8, 0, 32)
		button.TextXAlignment = Enum.TextXAlignment.Left
		button.Parent = list

		button.Activated:Connect(function()
			local sound = Instance.new("Sound")
			sound.SoundId = "rbxassetid://" .. sfx.asset_id
			sound.Parent = SoundService
			sound:Play()
			sound.Ended:Once(function()
				sound:Destroy()
			end)
		end)
	end
end

Players.PlayerAdded:Connect(buildBoard)
for _, player in Players:GetPlayers() do
	buildBoard(player)
end
