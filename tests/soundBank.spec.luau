--!strict
-- Unit tests for AudioScapeSoundBank.
--
-- The bridging path (GetAudioMetadataAsync for seeds our catalog doesn't
-- hold) needs a real engine and is covered in the Open Cloud smoke instead;
-- everything here is pool construction and pick behaviour, which is pure.

local serde = require("@lune/serde")
local mockHttp = require("./_harness/mockHttp")
local loadSdk = require("./_harness/loadSdk").loadSdk

local function lookupResponse(knownIds: { string }): mockHttp.Response
	local tracks = {}
	for _, id in knownIds do
		table.insert(tracks, { asset_id = id, name = "Seed " .. id })
	end
	return {
		Success = true,
		StatusCode = 200,
		Body = serde.encode("json", {
			tracks = tracks,
			artists = {},
			albums = {},
			meta = { total = #tracks, limit = 100, offset = 0, search_method = "ids-batch" },
		}),
	}
end

local function similarResponse(ids: { string }): mockHttp.Response
	local tracks = {}
	for _, id in ids do
		table.insert(tracks, { asset_id = id, name = "Neighbour " .. id })
	end
	return {
		Success = true,
		StatusCode = 200,
		Body = serde.encode("json", {
			tracks = tracks,
			meta = { total = #tracks, limit = 8, offset = 0 },
		}),
	}
end

local function newSdk(): (any, any)
	local http = mockHttp.new()
	local sdk = loadSdk({ http = http })
	local AudioScape: any = sdk
	AudioScape.setApiKey("test-key")
	return AudioScape, http
end

-- 1. extend mode keeps the developer's own asset at the head of the pool
do
	local AudioScape, http = newSdk()
	http:queueResponse(lookupResponse({ "111" }))
	http:queueResponse(similarResponse({ "222", "333", "444" }))

	local bank = AudioScape:createSoundBank({ seeds = { footstep = "rbxassetid://111" } })
	local ok, err = bank:resolveAsync()
	assert(ok, "resolve failed: " .. tostring(err))

	local pool = bank:getPool("footstep")
	assert(pool[1] == "111", "the seed leads the pool in extend mode; got " .. tostring(pool[1]))
	assert(#pool == 4, "seed plus 3 neighbours; got " .. tostring(#pool))
	assert(bank.Pools.footstep.source == "catalog", "seed was in the catalog, so source is 'catalog'")
	assert(bank.IsResolved, "IsResolved set after a successful resolve")
end

-- 2. replace mode drops the seed — the opt-in behaviour, never the default
do
	local AudioScape, http = newSdk()
	http:queueResponse(lookupResponse({ "111" }))
	http:queueResponse(similarResponse({ "222", "333" }))

	local bank = AudioScape:createSoundBank({
		seeds = { footstep = "rbxassetid://111" },
		mode = "replace",
	})
	bank:resolveAsync()

	local pool = bank:getPool("footstep")
	assert(#pool == 2, "pool is neighbours only; got " .. tostring(#pool))
	for _, id in pool do
		assert(id ~= "111", "seed excluded in replace mode")
	end
end

-- 3. poolSize caps the result
do
	local AudioScape, http = newSdk()
	http:queueResponse(lookupResponse({ "111" }))
	http:queueResponse(similarResponse({ "222", "333", "444", "555", "666" }))

	local bank = AudioScape:createSoundBank({ seeds = { s = "111" }, poolSize = 3 })
	bank:resolveAsync()
	assert(#bank:getPool("s") == 3, "pool capped at poolSize; got " .. tostring(#bank:getPool("s")))
end

-- 4. Nothing to expand from: fall back to the seed rather than to silence
do
	local AudioScape, http = newSdk()
	-- Seed unknown to the catalog. Bridging calls GetAudioMetadataAsync, which
	-- the mock has no AssetService for, so it pcalls out and yields no anchor.
	http:queueResponse(lookupResponse({}))

	local bank = AudioScape:createSoundBank({ seeds = { s = "999" }, mode = "replace" })
	local ok = bank:resolveAsync()
	assert(ok, "resolve succeeds even when nothing can be expanded")

	local pool = bank:getPool("s")
	assert(#pool == 1 and pool[1] == "999", "falls back to the seed; got " .. tostring(pool[1]))
	assert(bank.Pools.s.source == "none", "source reports 'none' when unresolvable")
end

-- 5. pick never returns the same asset twice in a row — the whole point
do
	local AudioScape, http = newSdk()
	http:queueResponse(lookupResponse({ "111" }))
	http:queueResponse(similarResponse({ "222", "333" }))

	local bank = AudioScape:createSoundBank({ seeds = { s = "111" } })
	bank:resolveAsync()

	local previous: string? = nil
	for i = 1, 200 do
		local pick = bank:pick("s")
		assert(pick, "pick returned nil on iteration " .. tostring(i))
		assert(pick ~= previous, "immediate repeat at iteration " .. tostring(i) .. ": " .. tostring(pick))
		previous = pick
	end
end

-- 6. A single-asset pool has no choice but to repeat; it must not error
do
	local AudioScape, http = newSdk()
	http:queueResponse(lookupResponse({}))

	local bank = AudioScape:createSoundBank({ seeds = { s = "999" } })
	bank:resolveAsync()
	assert(bank:pick("s") == "999", "single-asset pool returns the only asset")
	assert(bank:pick("s") == "999", "and keeps returning it rather than nil")
end

-- 7. Unknown pool name returns nil rather than throwing
do
	local AudioScape, http = newSdk()
	http:queueResponse(lookupResponse({}))
	local bank = AudioScape:createSoundBank({ seeds = { s = "1" } })
	bank:resolveAsync()
	assert(bank:pick("nope") == nil, "unknown pool name yields nil")
	assert(#bank:getPool("nope") == 0, "unknown pool yields an empty list")
end

-- 8. reportUnavailable removes an asset from future picks
do
	local AudioScape, http = newSdk()
	http:queueResponse(lookupResponse({ "111" }))
	http:queueResponse(similarResponse({ "222", "333" }))

	local bank = AudioScape:createSoundBank({ seeds = { s = "111" } })
	bank:resolveAsync()

	assert(bank:reportUnavailable("222"), "first report returns true")
	assert(not bank:reportUnavailable("222"), "reporting the same asset twice is a no-op")

	for i = 1, 60 do
		assert(bank:pick("s") ~= "222", "unavailable asset never picked (iteration " .. tostring(i) .. ")")
	end
end

-- 9. Every asset unavailable → fall back to the seed rather than nil
do
	local AudioScape, http = newSdk()
	http:queueResponse(lookupResponse({ "111" }))
	http:queueResponse(similarResponse({ "222" }))

	local bank = AudioScape:createSoundBank({ seeds = { s = "111" } })
	bank:resolveAsync()
	bank:reportUnavailable("111")
	bank:reportUnavailable("222")
	assert(bank:pick("s") == "111", "falls back to the seed when the pool is exhausted")
end

-- 10. Picks aggregate into one event per asset. Emitting per pick would
--     overrun the 500-event analytics buffer during any footstep loop.
do
	local AudioScape, http = newSdk()
	http:queueResponse(lookupResponse({ "111" }))
	http:queueResponse(similarResponse({ "222" }))

	local bank = AudioScape:createSoundBank({ seeds = { s = "111" } })
	bank:resolveAsync()

	-- resolveAsync emits one audio_resolve event per seed.
	local afterResolve = #AudioScape._analyticsBuffer
	assert(afterResolve == 1, "one audio_resolve event; got " .. tostring(afterResolve))

	for _ = 1, 100 do
		bank:pick("s")
	end
	assert(
		#AudioScape._analyticsBuffer == afterResolve,
		"picking queues nothing on its own; got " .. tostring(#AudioScape._analyticsBuffer)
	)

	bank:flushPickCounts()
	local events = AudioScape._analyticsBuffer
	local total = 0
	local pickEvents = 0
	for _, event in events do
		if event.type == "audio_pick" then
			pickEvents += 1
			total += event.metadata.count
		end
	end
	assert(pickEvents <= 2, "at most one event per distinct asset; got " .. tostring(pickEvents))
	assert(total == 100, "counts sum to the number of picks; got " .. tostring(total))

	-- Flushing twice must not double-report.
	bank:flushPickCounts()
	local after = 0
	for _, event in AudioScape._analyticsBuffer do
		if event.type == "audio_pick" then
			after += 1
		end
	end
	assert(after == pickEvents, "a second flush emits nothing new")
end

-- 11. Replace mode must NOT drop a seed we could not resolve from our own
--     catalog. A bridged seed may be audio private to that experience: the
--     game has permission for its own asset where a substitute might not, so
--     silently swapping it out is the one outcome worse than not helping.
do
	local http = mockHttp.new()
	-- A fake engine so the seed can actually bridge — without it the bank
	-- falls through to source "none", which is a different branch (case 4).
	local sdk = loadSdk({
		http = http,
		services = {
			AssetService = {
				GetAudioMetadataAsync = function(_, idList: { string })
					local out = {}
					for _, contentId in idList do
						table.insert(out, {
							AssetId = string.match(contentId, "%d+"),
							Title = "Private Track",
							Artist = "Owner",
							Duration = 30,
						})
					end
					return out
				end,
			},
		},
	})
	local AudioScape: any = sdk
	AudioScape.setApiKey("test-key")

	http:queueResponse(lookupResponse({})) -- seed absent from the catalog
	http:queueResponse(lookupResponse({ "555" })) -- bridging search finds an anchor
	http:queueResponse(similarResponse({ "222", "333" }))

	local bank = AudioScape:createSoundBank({
		seeds = { private = "999" },
		kind = "music",
		mode = "replace",
	})
	local ok, err = bank:resolveAsync()
	assert(ok, "resolve failed: " .. tostring(err))

	assert(bank.Pools.private.source == "bridged", "seed bridged; got " .. bank.Pools.private.source)

	local pool = bank:getPool("private")
	assert(pool[1] == "999", "the unresolved seed still leads the pool in replace mode; got " .. tostring(pool[1]))
	assert(#pool > 1, "neighbours were still added around it")
end

-- 12. Replace mode DOES drop a seed we resolved from our own catalog — the
--     opt-in behaviour is intact for assets we can vouch for.
do
	local AudioScape, http = newSdk()
	http:queueResponse(lookupResponse({ "111" })) -- seed IS in the catalog
	http:queueResponse(similarResponse({ "222", "333" }))

	local bank = AudioScape:createSoundBank({ seeds = { s = "111" }, mode = "replace" })
	bank:resolveAsync()

	assert(bank.Pools.s.source == "catalog", "resolved from catalog")
	for _, id in bank:getPool("s") do
		assert(id ~= "111", "a catalog-resolved seed is still replaced")
	end
end

-- 13. Validation
do
	local AudioScape, http = newSdk()
	http:queueResponse(lookupResponse({}))

	local okKind = pcall(function()
		AudioScape:createSoundBank({ seeds = { s = "1" }, kind = "podcast" })
	end)
	assert(not okKind, "invalid kind rejected")

	local okMode = pcall(function()
		AudioScape:createSoundBank({ seeds = { s = "1" }, mode = "obliterate" })
	end)
	assert(not okMode, "invalid mode rejected")

	local okSeed = pcall(function()
		AudioScape:createSoundBank({ seeds = { s = "not-an-id" } })
	end)
	assert(not okSeed, "unusable seed id rejected")
end
