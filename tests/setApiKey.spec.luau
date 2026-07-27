--!strict
-- Unit tests for the module-as-object entry point.
--
-- `AudioScape.setApiKey(key)` then `AudioScape:search{...}` is the documented
-- path: there's no object to name, so it can't be named something that
-- collides with Roblox's own client/server vocabulary. `AudioScape.new(key)`
-- stays supported for multiple keys and for test isolation.

local serde = require("@lune/serde")
local mockHttp = require("./_harness/mockHttp")
local loadSdk = require("./_harness/loadSdk").loadSdk

-- mockHttp types `headers` as optional; every request the SDK makes sets it,
-- so read it through a cast rather than nil-checking at each call site.
local function keyUsed(http: any, index: number): any
	local recorded: any = http.requests[index]
	return recorded.headers["x-api-key"]
end

local function emptyResponse(): mockHttp.Response
	return {
		Success = true,
		StatusCode = 200,
		Body = serde.encode("json", {
			tracks = {},
			artists = {},
			albums = {},
			meta = { total = 0, limit = 20, offset = 0, search_method = "semantic" },
		}),
	}
end

-- 1. setApiKey + methods called on the module itself
do
	local http = mockHttp.new()
	local AudioScape: any = loadSdk({ http = http })

	AudioScape.setApiKey("module-key")
	http:queueResponse(emptyResponse())

	local result, err = AudioScape:search({ query = "chill lo-fi" })
	assert(result and not err, "search on the module works; err: " .. tostring(err))
	assert(#http.requests == 1, "one request issued")
	assert(keyUsed(http, 1) == "module-key", "key from setApiKey is used")
end

-- 2. The colon form is tolerated too — a very easy mistake to make, and
--    silently binding the module table as the key would be a nasty failure.
do
	local http = mockHttp.new()
	local AudioScape: any = loadSdk({ http = http })

	AudioScape:setApiKey("colon-key")
	http:queueResponse(emptyResponse())

	AudioScape:search({ query = "test" })
	assert(keyUsed(http, 1) == "colon-key", "colon-call form binds the real key")
end

-- 3. Secret userdata passes through untouched (HttpService:GetSecret)
do
	local http = mockHttp.new()
	local AudioScape: any = loadSdk({ http = http })

	local secret = newproxy(false)
	AudioScape.setApiKey(secret)
	http:queueResponse(emptyResponse())

	AudioScape:search({ query = "test" })
	assert(keyUsed(http, 1) == secret, "Secret userdata is forwarded, not stringified")
end

-- 4. Validation still applies on the singleton path
do
	local http = mockHttp.new()
	local AudioScape: any = loadSdk({ http = http })

	local ok, err = pcall(function()
		AudioScape.setApiKey(nil)
	end)
	assert(not ok, "nil key rejected")
	assert(tostring(err):find("setApiKey", 1, true), "error names the caller; got: " .. tostring(err))

	local okEmpty, errEmpty = pcall(function()
		AudioScape.setApiKey("")
	end)
	assert(not okEmpty, "empty-string key rejected")
	assert(tostring(errEmpty):find("non%-empty"), "error explains why; got: " .. tostring(errEmpty))
end

-- 5. new() still works and is independent of the module's own key
do
	local http = mockHttp.new()
	local AudioScape: any = loadSdk({ http = http })

	AudioScape.setApiKey("module-key")
	local separate = AudioScape.new("separate-key")

	http:queueResponse(emptyResponse())
	separate:search({ query = "a" })
	assert(keyUsed(http, 1) == "separate-key", "instance uses its own key")

	http:queueResponse(emptyResponse())
	AudioScape:search({ query = "b" })
	assert(keyUsed(http, 2) == "module-key", "module keeps its own key")
end

-- 6. Re-keying preserves queued analytics rather than dropping them, and
--    doesn't spawn a second flush loop.
do
	local http = mockHttp.new()
	local AudioScape: any = loadSdk({ http = http })

	AudioScape.setApiKey("first-key")
	AudioScape:trackPlay("12345", 1, 30)
	assert(#AudioScape._analyticsBuffer == 1, "one event queued")

	AudioScape.setApiKey("second-key")
	assert(#AudioScape._analyticsBuffer == 1, "queued events survive a re-key")

	http:queueResponse({ Success = true, StatusCode = 200, Body = "{}" })
	AudioScape:flushAnalytics()
	assert(#AudioScape._analyticsBuffer == 0, "buffer drains after flush")
	assert(keyUsed(http, 1) == "second-key", "flush uses the new key")
end

-- 7. The AssetService shim works off the module too
do
	local http = mockHttp.new()
	local AudioScape: any = loadSdk({ http = http })

	AudioScape.setApiKey("module-key")
	http:queueResponse({
		Success = true,
		StatusCode = 200,
		Body = serde.encode("json", {
			tracks = { { asset_id = "42", name = "Test", artist = "A", duration = 10 } },
			artists = {},
			albums = {},
			meta = { total = 1, limit = 30, offset = 0, search_method = "semantic" },
		}),
	})

	local AssetService = AudioScape:getAssetService()
	local pages = AssetService:SearchAudioAsync({
		SearchKeyword = "test",
		Title = "",
		Artist = "",
		Album = "",
		Tag = "",
		MinDuration = 0,
		MaxDuration = 2147483647,
		AudioSubType = "Music",
	})
	assert(pages:GetCurrentPage()[1].Title == "Test", "shim works when reached from the module")
end
