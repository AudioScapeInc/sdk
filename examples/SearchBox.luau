--!strict
--[[
	SearchBox Example (Server Script)

	Listens for search requests from clients via a RemoteEvent,
	runs the search on the server, and returns results.

	Setup:
	1. Create a RemoteEvent named "SearchRequest" in ReplicatedStorage
	2. Place this Script in ServerScriptService
	3. On the client, fire the RemoteEvent with the query string:
	     ReplicatedStorage.SearchRequest:FireServer("chill beats")
]]

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

local AudioScape = require(ServerScriptService.Packages.AudioScape)

local apiKey = if RunService:IsStudio()
	then "your-test-key"
	else HttpService:GetSecret("AudioScapeKey")

local client = AudioScape.new(apiKey)

local searchEvent = ReplicatedStorage:WaitForChild("SearchRequest") :: RemoteEvent

searchEvent.OnServerEvent:Connect(function(player: Player, query: unknown)
	if type(query) ~= "string" or #(query :: string) == 0 then
		return
	end

	local result, err = client:search({
		query = query :: string,
		limit = 10,
		playerId = player.UserId,
	})

	if not result then
		warn("Search failed for", player.Name, ":", err)
		return
	end

	print(string.format("[%s] searched '%s' — %d results", player.Name, query, result.meta.total))

	for _, track in result.tracks do
		print(string.format("  %s - %s (ID: %s)", track.artist, track.name, track.asset_id))
	end

	-- TODO: Send results back to client via RemoteEvent or RemoteFunction
end)
