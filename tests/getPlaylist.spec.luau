--!strict
-- getPlaylist / listPlaylists go over GET (v0.21.0) so CloudFront can cache
-- them at the edge. Covers the wire format: method, path, query string,
-- headers, no JSON body, and the pre-flight playlist_id validation.

local serde = require("@lune/serde")
local mockHttp = require("./_harness/mockHttp")
local loadSdk = require("./_harness/loadSdk").loadSdk

local http = mockHttp.new()
local sdk = loadSdk({ http = http })
local client = (sdk :: any).new("test-key")

-- getPlaylist: GET /v1/playlist?playlist_id=...
http:queueResponse({
	Success = true,
	StatusCode = 200,
	Body = serde.encode("json", {
		playlist = { id = "kpop", name = "K-Pop", genre = "pop", playback_mode = "shuffle", track_count = 0 },
		tracks = {},
		meta = {},
	}),
})
local result, err = client:getPlaylist({ playlist_id = "kpop", playerId = 12345 })
assert(result and not err, "getPlaylist should succeed; err: " .. tostring(err))
assert(#http.requests == 1, "exactly one HTTP call")

local recorded = http.requests[1]
assert(recorded.method == "GET", "getPlaylist uses GET, got " .. recorded.method)
assert(recorded.url:find("/v1/playlist?", 1, true), "URL is /v1/playlist with a query string; got " .. recorded.url)
assert(recorded.url:find("playlist_id=kpop", 1, true), "playlist_id in query; got " .. recorded.url)
assert(recorded.body == nil, "GET sends no body")
assert(recorded.headers and recorded.headers["x-api-key"] == "test-key", "x-api-key set")
assert(recorded.headers and recorded.headers["X-Player-Id"] == "12345", "X-Player-Id forwarded")
assert(recorded.headers and recorded.headers["Content-Type"] == nil, "no Content-Type on GET")

-- playlist_id is URL-encoded, not JSON-encoded
http:reset()
http:queueResponse({ Success = true, StatusCode = 200, Body = "{}" })
client:getPlaylist({ playlist_id = "top100 weekly/theblock" })
recorded = http.requests[1]
assert(
	recorded.url:find("playlist_id=top100%20weekly%2Ftheblock", 1, true),
	"playlist_id url-encoded; got " .. recorded.url
)

-- pre-flight: empty / non-string playlist_id rejected without HTTP
http:reset()
local rejected, badErr = client:getPlaylist({ playlist_id = "" })
assert(
	rejected == nil and badErr and badErr:find("non-empty playlist_id", 1, true),
	"empty id rejected; got " .. tostring(badErr)
)
assert(#http.requests == 0, "no HTTP for invalid playlist_id")

-- listPlaylists: GET /v1/playlist?action=list
http:reset()
http:queueResponse({ Success = true, StatusCode = 200, Body = serde.encode("json", { playlists = {}, meta = {} }) })
local list, listErr = client:listPlaylists(777)
assert(list and not listErr, "listPlaylists should succeed; err: " .. tostring(listErr))
recorded = http.requests[1]
assert(recorded.method == "GET", "listPlaylists uses GET, got " .. recorded.method)
assert(recorded.url:find("/v1/playlist?action=list", 1, true), "action=list in query; got " .. recorded.url)
assert(recorded.body == nil, "GET sends no body")
assert(recorded.headers and recorded.headers["X-Player-Id"] == "777", "X-Player-Id forwarded")

-- listPlaylists without a player: header omitted
http:reset()
http:queueResponse({ Success = true, StatusCode = 200, Body = "{}" })
client:listPlaylists()
recorded = http.requests[1]
assert(recorded.headers and recorded.headers["X-Player-Id"] == nil, "no X-Player-Id without a player")

-- 5xx still maps to the shared server-error message
do
	http:reset()
	http:queueResponse({ Success = false, StatusCode = 503, Body = "" })
	local r, e = client:getPlaylist({ playlist_id = "kpop" })
	assert(r == nil and e == "Server error — try again later (503)", "got: " .. tostring(e))
end
