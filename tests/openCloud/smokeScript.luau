--!strict
-- Server-side smoke suite run inside Roblox via Open Cloud Luau Execution.
-- This is the project's ONLY integration layer (Lune specs cover pure logic).
-- Covers every HTTP-hitting public method against the real AudioScape API
-- through the real Roblox engine (real HttpService, AudioPlayer +
-- AudioDeviceOutput + Wire, RemoteFunction, workspace:GetServerTimeNow).
--
-- Returns { ok, results, fixtures } where results is a list of per-step
-- { name, ok, value?, err? }. The harness surfaces the per-step list and
-- exits non-zero if any step failed.

local HttpService = game:GetService("HttpService")
local SerializationService = game:GetService("SerializationService")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

type StepResult = {
	name: string,
	ok: boolean,
	value: any?,
	err: string?,
}

type Fixtures = {
	music_asset_id: string?,
	music_asset_id_with_structure: string?,
	sfx_asset_id: string?,
	playlist_id: string?,
}

-- Dynamic require of a deserialized ModuleScript — luau-lsp can't statically
-- resolve the target, so we cast `require` to `any` and treat the result as
-- `any` (the smoke tests runtime behavior, not static types).
local args: any = ({ ... })[1]
local sdkInstance: Instance = SerializationService:DeserializeInstancesAsync(args.BinaryInput)[1]
sdkInstance.Parent = ServerStorage
local AudioScape: any = (require :: any)(sdkInstance)

local results: { StepResult } = {}
-- `fn: () -> ...any` — varargs return type accepts 0-or-more returned
-- values. Lets callbacks with no explicit return (like `instantiate`)
-- and callbacks that return various shapes (numbers, tables, strings) all
-- satisfy strict typing uniformly.
local function step(name: string, fn: () -> ...any)
	local ok, value = pcall(fn)
	if ok then
		table.insert(results, { name = name, ok = true, value = value })
	else
		table.insert(results, { name = name, ok = false, err = tostring(value) })
	end
end

-- Construction uses the AUDIOSCAPE_KEY Roblox Secret (set on the test place).
-- The SDK accepts Secret userdata directly, and HttpService substitutes it
-- into the auth header at send time — the key never materialises as a string.
local client: any = nil
step("instantiate", function()
	client = AudioScape.new(HttpService:GetSecret("AUDIOSCAPE_KEY"))
	assert(client, "AudioScape.new returned nil")
end)

-- If instantiate failed, every subsequent step's `client:*` call errors on
-- nil deref — each one's pcall catches it and records a step failure. The
-- harness sees N step failures instead of 1 fatal, which is noisier but
-- keeps the return shape consistent and well-typed.

-- Fixtures discovered at test time. Dogfooding this rather than hardcoding
-- ids means fixture rot is impossible: if browse/sfxBrowse ever break, the
-- smoke fails loudly on those steps instead of mysteriously-later downstream.
local fixtures: Fixtures = {
	music_asset_id = nil,
	music_asset_id_with_structure = nil,
	sfx_asset_id = nil,
	playlist_id = nil,
}

step("browse_trending", function()
	local r, err = client:browse({ type = "trending", limit = 10 })
	assert(r, "browse failed: " .. tostring(err))
	assert(#r.tracks > 0, "trending returned 0 tracks")
	local first = r.tracks[1]
	assert(typeof(first.asset_id) == "string" and #first.asset_id > 0, "first track has asset_id")
	assert(typeof(first.duration) == "number" and first.duration > 0, "first track has positive duration")
	-- v0.12.0 contract: every tracks-returning endpoint emits genre_slug paired
	-- with the canonical genre. Both must be non-empty strings — track.genre is
	-- now the AudioScape canonical taxonomy uniformly across endpoints.
	assert(typeof(first.genre) == "string" and #first.genre > 0, "first track has canonical genre")
	assert(typeof(first.genre_slug) == "string" and #first.genre_slug > 0, "first track has genre_slug")
	fixtures.music_asset_id = first.asset_id
	return #r.tracks
end)

-- v0.12.0 contract: BrowseGenreItem exposes slug alongside name/display_name/
-- track_count. Locks in the new field on the browse-list shape (separate from
-- the per-track genre_slug verified above).
step("browse_genre_list", function()
	local r, err = client:browse({ type = "genre", limit = 5 })
	assert(r, "browse genre list failed: " .. tostring(err))
	assert(typeof(r.items) == "table" and #r.items > 0, "genre list returned items")
	local first = r.items[1]
	assert(typeof(first.name) == "string" and #first.name > 0, "BrowseGenreItem.name present")
	assert(typeof(first.slug) == "string" and #first.slug > 0, "BrowseGenreItem.slug present (v0.12.0)")
	assert(typeof(first.display_name) == "string" and #first.display_name > 0, "BrowseGenreItem.display_name present")
	assert(typeof(first.track_count) == "number", "BrowseGenreItem.track_count is a number")
	return #r.items
end)

-- v0.13.0 contract: drill-down accepts `sort` and the response echoes it in
-- meta. `popular` is the server-side default; we exercise an explicit value
-- (alpha) to prove the param round-trips, then verify default-omitted falls
-- back to popular ordering. Genre picked from the list above to avoid
-- fixture rot.
step("browse_genre_sort", function()
	local genreList, listErr = client:browse({ type = "genre", limit = 1 })
	assert(genreList and genreList.items[1], "needs a genre slug from browse_genre_list: " .. tostring(listErr))
	local slug = genreList.items[1].slug

	local alpha, alphaErr = client:browse({ type = "genre", name = slug, sort = "alpha", limit = 3 })
	assert(alpha, "browse alpha sort failed: " .. tostring(alphaErr))
	assert(alpha.meta.sort == "alpha", "meta.sort echoes 'alpha'; got " .. tostring(alpha.meta.sort))

	local default, defaultErr = client:browse({ type = "genre", name = slug, limit = 3 })
	assert(default, "browse default sort failed: " .. tostring(defaultErr))
	assert(default.meta.sort == "popular", "meta.sort defaults to 'popular'; got " .. tostring(default.meta.sort))
	return slug
end)

step("sfxBrowse_trending", function()
	local r, err = client:sfxBrowse({ type = "trending", limit = 5 })
	assert(r, "sfxBrowse failed: " .. tostring(err))
	assert(r.meta.type == "trending", "meta.type echoes 'trending'; got " .. tostring(r.meta.type))
	if #r.tracks > 0 then
		fixtures.sfx_asset_id = r.tracks[1].asset_id
	end
	-- Pre-flight: invalid type rejected without HTTP
	local rejected, badErr = client:sfxBrowse({ type = "not-a-type" })
	assert(rejected == nil, "invalid sfxBrowse type rejected pre-flight")
	assert(badErr and badErr:find("trending", 1, true), "err mentions trending; got: " .. tostring(badErr))
	return #r.tracks
end)

step("search_music", function()
	local r, err = client:search({ query = "chill", limit = 5 })
	assert(r, "search failed: " .. tostring(err))
	assert(typeof(r.meta.search_method) == "string", "meta.search_method is a string")
	return { total = r.meta.total, returned = #r.tracks, method = r.meta.search_method }
end)

step("search_sfx", function()
	local r, err = client:sfxSearch({ query = "explosion", limit = 5 })
	assert(r, "sfxSearch failed: " .. tostring(err))
	-- Pre-flight: missing both query and category filter rejected without HTTP
	local rejected, badErr = client:sfxSearch({})
	assert(rejected == nil, "empty sfxSearch options rejected pre-flight")
	assert(
		badErr and badErr:find("query string or filters.categories", 1, true),
		"err mentions valid input shape; got: " .. tostring(badErr)
	)
	return { total = r.meta.total, returned = #r.tracks }
end)

-- v0.12.0 contract: client:lookup batches up to 100 asset_ids and surfaces
-- IDs that didn't resolve in meta.missing_ids. Pairs a real ID (from the
-- trending fixture) with a deliberately-bogus one — the bogus ID must come
-- back in missing_ids and not as a track.
step("lookup_batch", function()
	local realAsset = fixtures.music_asset_id
	assert(realAsset, "needs music_asset_id from browse_trending")
	-- 1-digit IDs don't exist in the catalog (asset IDs are much longer);
	-- safe sentinel for "guaranteed missing".
	local bogus = "1"
	local r, err = client:lookup({ asset_ids = { realAsset, bogus } })
	assert(r, "lookup failed: " .. tostring(err))
	assert(typeof(r.tracks) == "table", "lookup returns a tracks list")
	assert(#r.tracks == 1, "exactly one track resolved (the real one); got " .. tostring(#r.tracks))
	assert(r.tracks[1].asset_id == realAsset, "the resolved track is the real one")
	assert(
		r.meta.search_method == "ids-batch",
		"meta.search_method is 'ids-batch'; got " .. tostring(r.meta.search_method)
	)
	assert(typeof(r.meta.missing_ids) == "table", "meta.missing_ids surfaces")
	local sawBogus = false
	for _, id in r.meta.missing_ids do
		if id == bogus then
			sawBogus = true
			break
		end
	end
	assert(sawBogus, "bogus id appears in meta.missing_ids")

	-- Pre-flight validation: empty options rejected without HTTP.
	local rejected, badErr = client:lookup({} :: any)
	assert(rejected == nil, "empty lookup options rejected pre-flight")
	assert(
		badErr and badErr:find("non-empty asset_ids array", 1, true),
		"err mentions asset_ids; got: " .. tostring(badErr)
	)

	return { resolved = #r.tracks, missing = #r.meta.missing_ids }
end)

step("similar_music", function()
	local asset = fixtures.music_asset_id
	assert(asset, "needs music_asset_id from browse_trending")
	local r, err = client:similar({ asset_id = asset, limit = 5 })
	assert(r, "similar failed: " .. tostring(err))
	-- Pre-flight: empty asset_id rejected without HTTP. Error message mentions
	-- the four accepted shapes (string / table / Sound / AudioPlayer) since
	-- v0.11.0's polymorphic input.
	local rejected, badErr = client:similar({ asset_id = "" })
	assert(rejected == nil, "empty similar asset_id rejected pre-flight")
	assert(
		badErr and badErr:find("track table, a Sound, or an AudioPlayer", 1, true),
		"err mentions four accepted shapes; got: " .. tostring(badErr)
	)
	return #r.tracks
end)

step("similar_sfx", function()
	local asset = fixtures.sfx_asset_id
	if not asset then
		return "skipped — no sfx fixture available"
	end
	local r, err = client:sfxSimilar({ asset_id = asset, limit = 5 })
	assert(r, "sfxSimilar failed: " .. tostring(err))
	return #r.tracks
end)

step("getSfxTaxonomy", function()
	local r, err = client:getSfxTaxonomy()
	assert(r, "getSfxTaxonomy failed: " .. tostring(err))
	assert(typeof(r.meta.broader_category_count) == "number", "meta.broader_category_count is a number")
	assert(#r.taxonomy > 0, "taxonomy is non-empty")
	return {
		groups = r.meta.broader_category_count,
		categories = r.meta.category_count,
		subcategories = r.meta.subcategory_count,
	}
end)

-- getStructure has a ~97% coverage SLO upstream (a small fraction of tracks
-- lag the analysis pipeline), so we walk trending until we find one with
-- non-empty sections. Catches the issue-#3 regression (Section["end"] field).
step("getStructure", function()
	local pool, poolErr = client:browse({ type = "trending", limit = 10 })
	assert(pool, "browse for structure-walker failed: " .. tostring(poolErr))
	local pickedAsset: string? = nil
	local pickedResult: any = nil
	for _, track in pool.tracks do
		local r, err = client:getStructure({ asset_id = track.asset_id })
		if r and not err and #r.sections > 0 then
			pickedAsset = track.asset_id
			pickedResult = r
			break
		end
	end
	assert(pickedAsset and pickedResult, "no trending track had non-empty sections within the walk window")
	fixtures.music_asset_id_with_structure = pickedAsset

	local first = pickedResult.sections[1]
	assert(typeof(first.start) == "number", "section.start is a number")
	-- Issue-#3 regression: the API field is `end` and the Luau type quotes it as
	-- ["end"]. Both wire-decode and type alignment must work for this to pass.
	assert(typeof(first["end"]) == "number", 'section["end"] is a number (issue #3)')
	assert(first["end"] > first.start, "section end > start")
	return { asset_id = pickedAsset, sections = #pickedResult.sections }
end)

step("sectionAtTime", function()
	local asset = fixtures.music_asset_id_with_structure
	assert(asset, "needs a structured track")
	local r, err = client:getStructure({ asset_id = asset })
	assert(r and r.sections[1], "re-fetch for sectionAtTime failed: " .. tostring(err))
	local probe = r.sections[1].start + 0.1
	local section, sErr = client:sectionAtTime(asset, probe)
	assert(section, "sectionAtTime returned nil: " .. tostring(sErr))
	return "ok"
end)

-- v0.11.0 polymorphic input: pass a real Sound instance to getStructure.
-- Exercises the typeof == "Instance" arm of resolveAssetId — Lune mocks
-- can't reach this path because mockGame's Instance.new returns a table.
step("getStructure_from_sound", function()
	local asset = fixtures.music_asset_id_with_structure
	assert(asset, "needs a structured track from earlier getStructure step")
	local sound = Instance.new("Sound")
	sound.SoundId = "rbxassetid://" .. asset
	local r, err = client:getStructure(sound)
	sound:Destroy()
	assert(r, "getStructure(sound) failed: " .. tostring(err))
	assert(r.asset_id == asset, "resolved asset_id matches Sound.SoundId; got " .. tostring(r.asset_id))
	return "ok"
end)

-- Same Instance arm via similar() — proves the cross-method consistency.
step("similar_from_sound", function()
	local asset = fixtures.music_asset_id
	assert(asset, "needs music_asset_id from browse_trending")
	local sound = Instance.new("Sound")
	sound.SoundId = "rbxassetid://" .. asset
	local r, err = client:similar(sound, { limit = 3 })
	sound:Destroy()
	assert(r, "similar(sound) failed: " .. tostring(err))
	assert(typeof(r.tracks) == "table", "tracks present")
	return #r.tracks
end)

-- Table-arm wire-format coverage end-to-end through the real requestGet
-- URL builder. Pass a Track row from browse_trending directly — it carries
-- many fields beyond asset_id, so this also confirms extras-merge precedence
-- (extras passed → wins over track's own incidental fields).
step("similar_from_track", function()
	local pool, poolErr = client:browse({ type = "trending", limit = 3 })
	assert(pool and #pool.tracks > 0, "browse for track-pass failed: " .. tostring(poolErr))
	local track = pool.tracks[1]
	local r, err = client:similar(track, { limit = 5 })
	assert(r, "similar(track, extras) failed: " .. tostring(err))
	return { seed_asset_id = track.asset_id, returned = #r.tracks }
end)

step("listPlaylists", function()
	local r, err = client:listPlaylists()
	assert(r, "listPlaylists failed: " .. tostring(err))
	assert(typeof(r.meta.total) == "number" and r.meta.total >= 0, "meta.total is a number")
	if #r.playlists > 0 then
		fixtures.playlist_id = r.playlists[1].id
	end
	return { total = r.meta.total, returned = #r.playlists }
end)

step("getPlaylist", function()
	local id = fixtures.playlist_id
	if not id then
		return "skipped — no playlists in this universe"
	end
	local r, err = client:getPlaylist({ playlist_id = id })
	assert(r, "getPlaylist failed: " .. tostring(err))
	assert(r.playlist.id == id, "returned id matches requested")
	assert(#r.tracks == r.playlist.track_count, "tracks length matches track_count")
	return { id = r.playlist.id, name = r.playlist.name, tracks = #r.tracks }
end)

-- Analytics: enqueue one event per public track method, force-flush, assert
-- drain. Exercises workspace:GetServerTimeNow under real engine (catches the
-- class of bug fixed in 64ad673 where the Lune mock returned os.clock()).
-- Events tag with game.GameId/PlaceId — which are the real test universe/place
-- here, so they land in the test universe's analytics (expected + harmless).
step("analytics_flush", function()
	local asset = fixtures.music_asset_id
	assert(asset, "needs music_asset_id from browse_trending")
	local player = "smoke-openCloud"
	client:trackPlay(asset, player, 0)
	client:trackStop(asset, player, 0)
	client:trackSkip(asset, player, 0)
	client:trackVote(asset, "up", player)
	client:trackFavorite(asset, player)
	client:trackUnfavorite(asset, player)
	client:trackAddToQueue(asset, player)
	client:trackSearchClick(asset, player, { query = "smoke test" })
	client:trackCustom("smoke_openCloud_ping", asset, player, { source = "tests/openCloud/smoke" })
	assert(#client._analyticsBuffer == 9, "expected 9 events queued; got " .. #client._analyticsBuffer)
	client:flushAnalytics()
	assert(#client._analyticsBuffer == 0, "flushAnalytics did not drain buffer")
	return "9 events posted"
end)

-- createPlayer instantiates a real AudioPlayer + AudioDeviceOutput + Wire and
-- connects AudioPlayer.Ended. Not testable in Lune (the mock can't model the
-- audio API faithfully). v0.15.0 migrated this off legacy Sound — this step
-- is the gate that catches engine-level regressions (Asset vs AudioContent,
-- Wire parenting, etc.) at PR time.
step("createPlayer", function()
	-- Picked values exactly representable in float32 (0.5, 0.25) so reads off
	-- AudioPlayer.Volume round-trip cleanly to the Lua double we set — no
	-- tolerance check needed.
	local player = client:createPlayer({ volume = 0.5 })
	assert(player, "createPlayer returned nil")
	assert(typeof(player.playTrack) == "function", "player.playTrack is not a function")
	assert(typeof(player.getAudioPlayer) == "function", "player.getAudioPlayer is not a function (v0.15.0)")

	assert(fixtures.music_asset_id, "needs music_asset_id from browse_trending")
	player:playTrack({
		asset_id = fixtures.music_asset_id,
		name = "smoke",
		artist = "smoke",
		album = "smoke",
		genre = "smoke",
		duration = 30,
	})

	-- Give the engine a moment to start decoding the asset.
	task.wait(2)

	local ap = player:getAudioPlayer()
	assert(ap, "getAudioPlayer returned nil while a track is queued")
	assert(ap:IsA("AudioPlayer"), "underlying instance is " .. ap.ClassName .. ", expected AudioPlayer")
	assert(ap.Asset == "rbxassetid://" .. fixtures.music_asset_id, "AudioPlayer.Asset mismatch: " .. tostring(ap.Asset))
	assert(ap.IsPlaying, "AudioPlayer.IsPlaying is false after 2s")
	assert(ap.TimePosition > 0, "AudioPlayer.TimePosition did not advance (got " .. tostring(ap.TimePosition) .. ")")
	assert(ap.Volume == 0.5, "AudioPlayer.Volume = " .. tostring(ap.Volume) .. ", expected 0.5")

	local wire
	for _, child in ap:GetChildren() do
		if child:IsA("Wire") then
			wire = child
			break
		end
	end
	assert(wire, "Wire not parented to AudioPlayer")
	assert(wire.SourceInstance == ap, "Wire.SourceInstance is not the AudioPlayer")
	assert(
		wire.TargetInstance and wire.TargetInstance:IsA("AudioDeviceOutput"),
		"Wire.TargetInstance is not an AudioDeviceOutput"
	)

	player:setVolume(0.25)
	assert(ap.Volume == 0.25, "setVolume did not propagate to live AudioPlayer.Volume: " .. tostring(ap.Volume))

	player:stop()
	assert(player:getAudioPlayer() == nil, "getAudioPlayer should be nil after stop()")
	assert(player.IsPlaying == false, "IsPlaying should be false after stop()")

	player:destroy()
	return "ok"
end)

-- enableClientAccess creates ReplicatedStorage.AudioScapeRemotes (Folder)
-- with one RemoteFunction per public method. Lune doesn't model
-- RemoteFunction at all, so this is net new coverage.
step("enableClientAccess", function()
	client:enableClientAccess()
	local folder = ReplicatedStorage:FindFirstChild("AudioScapeRemotes")
	assert(folder and folder:IsA("Folder"), "AudioScapeRemotes Folder not created")
	local remotes = {}
	for _, child in folder:GetChildren() do
		if child:IsA("RemoteFunction") then
			table.insert(remotes, child.Name)
		end
	end
	assert(#remotes > 0, "no RemoteFunctions in AudioScapeRemotes")
	return remotes
end)

local allOk = true
for _, r in results do
	if not r.ok then
		allOk = false
		break
	end
end

return {
	ok = allOk,
	results = results,
	fixtures = fixtures,
}
