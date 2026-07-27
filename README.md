# AudioScape SDK for Roblox

A Luau SDK for the [AudioScape Developer API](https://developer.audioscape.ai) — search music and sound effects, browse the catalog, sync to beat-level track structure, and track analytics for your Roblox experiences.

> **Note:** This SDK uses `HttpService:RequestAsync()` and must run on the **server** (Script, not LocalScript). You must enable **Allow HTTP Requests** in your experience's Game Settings → Security.

## Installation

### Wally

Add to your `wally.toml`:

```toml
[server-dependencies]
AudioScape = "this-fifo/audioscape-sdk@0.17.0"
```

Then run:

```bash
wally install
```

The SDK's realm is `server`, so it must be declared under `[server-dependencies]` (Wally rejects server-realm packages placed under `[dependencies]`). Wally installs it to `ServerScriptService.Packages` (or your configured server packages location).

### Roblox Model

Download `AudioScape.rbxm` from the [latest release](https://github.com/AudioScapeInc/sdk/releases/latest) and drop it into `ServerStorage` or `ServerScriptService` in Roblox Studio.

### Manual

Copy the `src/` folder into your project under `ServerStorage` or `ServerScriptService`. If using Rojo, add it to your server-side project tree.

## Prerequisites

1. **Enable HTTP Requests** — In Roblox Studio, go to Game Settings → Security → Allow HTTP Requests and turn it **on**.
2. **API Key** — Get your key at [developer.audioscape.ai](https://developer.audioscape.ai). Use the [Roblox Secrets Store](https://create.roblox.com/docs/cloud-services/secret-stores) to securely store your key in production.

## Quick Start

```lua
local ServerStorage = game:GetService("ServerStorage")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

local AudioScape = require(ServerStorage.AudioScape)

local apiKey = if RunService:IsStudio()
    then "your-test-key"
    else HttpService:GetSecret("AudioScapeKey")

AudioScape.setApiKey(apiKey)
local player = AudioScape:createPlayer()

-- Search and play
local result, err = AudioScape:search({ query = "chill lo-fi beats", limit = 10 })
if result then
    player:queue(result.tracks)
    player:play()
end
```

The `AudioScapeMusicPlayer` handles Sound lifecycle, queue advancement, and analytics tracking automatically — no manual `trackPlay`/`trackStop` calls needed.

## Telemetry

The SDK automatically sends your game's Universe ID and Place ID with every request to help you track usage across your experiences. You can also pass an optional `playerId` to tie requests to specific players:

```lua
local result, err = AudioScape:search({
    query = "epic battle music",
    playerId = player.UserId,
})
```

## API

### `AudioScape.setApiKey(apiKey)`

Points the module at your API key. After this, call every method on `AudioScape` itself — there's no object to create or name.

```lua
AudioScape.setApiKey("your-api-key")
```

Accepts a plain string or the `Secret` userdata returned by `HttpService:GetSecret()`, which is what you should use in production so the key never exists as a string in your code.

### `AudioScape.new(apiKey)` *(advanced)*

Returns a separate object with its own key. You only need this if one server has to talk to AudioScape under more than one API key — otherwise use `setApiKey`.

```lua
local secondary = AudioScape.new("another-api-key")
local result = secondary:search({ query = "chill lo-fi" })
```

### `AudioScape.setEndpoints(options)` *(advanced)*

Points the SDK at a different API host. You only need this to develop against a locally-running API or a staging environment.

```lua
AudioScape.setEndpoints({
    baseUrl = "http://localhost:3000/developer",
    analyticsUrl = "http://localhost:3001/analytics",
})
```

| Option | Type | Default |
| --- | --- | --- |
| `baseUrl` | `string?` | `https://api.audioscape.ai/developer` |
| `analyticsUrl` | `string?` | `https://api.audioscape.ai/analytics` |

Omitted fields keep their current value, and it's safe to call before or after `setApiKey`. Trailing slashes are trimmed.

> **Note:** Roblox Studio can reach `http://localhost`, but a published Roblox server cannot. This is a development affordance, not a deployment mechanism.

### `AudioScape:search(options)`

Search the catalog using natural language, or look up specific tracks by asset ID.

```lua
local result, err = AudioScape:search({
    query = "epic orchestral battle music",  -- required (unless asset_ids set)
    limit = 20,                              -- optional (default: 20, max: 100)
    offset = 0,                              -- optional
    playerId = player.UserId,                -- optional
    filters = {                              -- optional
        -- Each entry accepts the canonical name ("Hip Hop / Rap"),
        -- the URL-safe slug ("hip-hop-rap", round-trip from track.genre_slug),
        -- or a legacy Roblox music_genre slug ("hip-hop") — all resolve to
        -- the same canonical taxonomy server-side.
        genres = { "Hip Hop / Rap", "Electronic" },
        duration = { min = 60, max = 180 },  -- seconds
        min_play_count = 100000,             -- min lifetime Roblox plays
        min_likes = 500,                     -- min lifetime Roblox likes
        created_after = "2024-01-01",        -- YYYY-MM-DD
    },
})
-- result = { tracks, artists, albums, meta }
-- result.tracks[i] = { asset_id, name, artist, album, genre, genre_slug, duration, bpm, ... }
```

`query` is required unless you pass `asset_ids` for a direct batch lookup
(see `AudioScape:lookup` below). Pass either one. When both are present, the API
prefers `asset_ids` and skips text search. `result.meta.search_method` will be
`"semantic"` / `"text"` / `"id"` / `"ids-batch"` depending on how the
request resolved.

**Result ordering:** pass `sort = "popular"` to rank by popularity (most-played first) or `sort = "recent"` for newest-first; omit `sort` (or use `"relevance"`) for the default best-match ordering. `result.meta.sort` echoes the applied ordering. (`sort` is ignored for `asset_ids` lookups.)

### `AudioScape:lookup(options)`

Resolve up to 100 known asset IDs in a single request. Returned tracks are in
input order, filters are bypassed, and IDs that didn't match (deleted,
delisted, non-public, or never existed) come back in `result.meta.missing_ids`.
Sugar over `AudioScape:search({ asset_ids = ... })`.

```lua
local result, err = AudioScape:lookup({
    asset_ids = { "1843209165", "9120386436", "1234567890" },
    playerId = player.UserId,  -- optional
})
-- result = { tracks, artists, albums, meta }
-- result.meta.missing_ids = { "1234567890" }  -- IDs that didn't resolve
```

### `AudioScape:similar(input, extras?)`

Find tracks that sound similar to a given track. `input` is anything that
carries an asset_id — a string, a Track from a previous response, a `Sound`,
or an `AudioPlayer`.

```lua
local result, err = AudioScape:similar({
    asset_id = "123456789",      -- required
    limit = 10,                  -- optional
    offset = 0,                  -- optional
    playerId = player.UserId,    -- optional
    filters = {                  -- optional
        genres = { "electronic" },
        duration = { min = 60, max = 180 },
    },
})
-- result = { tracks, meta }

-- Shorthand: pass a Track from a previous result
local result = AudioScape:similar(playlist.tracks[1], { limit = 10 })

-- Shorthand: pass a playing Sound directly
local result = AudioScape:similar(soundInstance)
```

### `AudioScape:browse(options)`

Browse by artist, album, genre, mood, or trending.

```lua
-- List all genres
local result, err = AudioScape:browse({ type = "genre" })
-- result = { items, meta }

-- Get tracks for a specific genre (defaults to popularity-ranked)
local result, err = AudioScape:browse({ type = "genre", name = "electronic", limit = 20 })
-- result = { tracks, meta }

-- Same drill-down, alpha sort to surface fresh uploads
local result, err = AudioScape:browse({ type = "genre", name = "electronic", sort = "alpha", limit = 20 })

-- Trending music (no name needed — returns the top tracks directly)
local result, err = AudioScape:browse({ type = "trending", limit = 50 })
-- result = { tracks, meta }
```

**Browse types:** `artist`, `album`, `genre`, `mood`, `trending`

**Sort (drill-down only):** `popular` (default — global popularity ranking, omits tracks with no engagement), `alpha` (track name A→Z), `recent` (newest first). Ignored for list mode and for `trending` (already popularity-ordered). Pick `alpha` or `recent` to surface tracks that haven't accumulated engagement yet.

Trending is a popularity-ranked list of music tracks refreshed daily, capped at 200 entries. Player engagement signals (plays, favorites, votes, queue adds, listen duration, plus custom events) are exponentially decayed over a 60-day window with a 30-day half-life, so recent activity dominates.

**Regional trending:** pass `region` on a `type = "trending"` call to get a list ranked by activity from a single part of the world instead of the global list. Use `region = "auto"` to auto-detect the region from your server's location, or pass an explicit `"americas"`, `"eu"`, or `"apac"`. Omit `region` for the global list (the default).

```lua
-- Auto-detected regional trending (falls back to global if unavailable)
local result, err = AudioScape:browse({ type = "trending", region = "auto", limit = 50 })

-- Explicit region
local result, err = AudioScape:browse({ type = "trending", region = "eu", limit = 50 })
```

> Regional trending must be enabled for your API key. Until then, `region` is ignored and you get the global list. Contact us via the [Developer Portal](https://developer.audioscape.ai) to enable it.

### `AudioScape:sfxBrowse(options)`

Browse the SFX catalog. v1 only supports `type = "trending"` — a popularity-ranked list of sound effects, refreshed daily on the same schedule as music trending.

```lua
local result, err = AudioScape:sfxBrowse({ type = "trending", limit = 50 })
-- result = { tracks, meta }
-- result.tracks = { { asset_id, name, description, category, subcategory, tags, duration, ... } }

-- Scope to a region (same options as music trending; requires regional
-- trending to be enabled for your API key — otherwise the global list)
local result, err = AudioScape:sfxBrowse({ type = "trending", region = "auto", limit = 50 })
```

### `AudioScape:sfxSearch(options)`

Search the sound effects catalog. Pass a free-text `query`, or browse a UCS category by passing `filters.categories` (the API synthesizes the query under the hood).

```lua
local result, err = AudioScape:sfxSearch({
    query = "metal sword impact short",  -- optional if filters.categories is set
    limit = 20,                          -- optional (default: 20, max: 100)
    offset = 0,                          -- optional
    playerId = player.UserId,            -- optional
    filters = {                          -- optional
        categories = { "WEAPON" },       -- UCS category names
        subcategories = { "SWORD" },     -- UCS subcategories
        duration = { min = 0, max = 1 }, -- seconds
        min_likes = 100,                 -- min lifetime Roblox likes
        created_after = "2024-01-01",    -- YYYY-MM-DD
    },
})
-- result = { tracks, categories, subcategories, meta }
```

**Result ordering:** like music search, pass `sort = "popular"` (most-popular first) or `sort = "recent"` (newest first); omit for the default relevance ordering.

### `AudioScape:sfxSimilar(input, extras?)`

Find sound effects acoustically similar to a given asset. Same polymorphic
input as `AudioScape:similar`.

```lua
local result, err = AudioScape:sfxSimilar({
    asset_id = "9120386436",     -- required
    limit = 10,                  -- optional
    offset = 0,                  -- optional
    playerId = player.UserId,    -- optional
    filters = {                  -- optional
        categories = { "AMBIENCE" },
        duration = { min = 0, max = 5 },
    },
})
-- result = { tracks, meta }

-- Or pass an SfxTrack / Sound / asset_id string:
local result = AudioScape:sfxSimilar(sfx.tracks[1], { limit = 10 })
```

### `AudioScape:getSfxTaxonomy()`

Fetch the full `broader_category → category → subcategory` hierarchy for building SFX picker UIs. Server-cached for 10 minutes, so polling is cheap.

```lua
local taxonomy, err = AudioScape:getSfxTaxonomy()
-- taxonomy.taxonomy = { { broader_category, categories = { { category, subcategories = { string } } } } }
```

### `AudioScape:getStructure(input, extras?)`

Fetch the beat grid and section structure for a track. Use this to sync
animations, lighting, or VFX to the music. Same polymorphic input as
`AudioScape:similar` — pass a string, a Track, a `Sound`, or an `AudioPlayer`.

```lua
local structure, err = AudioScape:getStructure({
    asset_id = "1843209165",  -- required
})
-- structure = { asset_id, duration, bpm, track_energy, beat_grid, sections, phrases }
-- structure.beat_grid = { times = { number }, downbeats = { number } }
-- structure.sections = { { start, end, label, energy, bar_start, bar_end, color } }
-- structure.phrases  = same shape as sections, but a coarser layer — fewer,
--                      longer segments. sections are the finer layer (more,
--                      shorter). Both carry the same label set.

-- Or pull structure straight from the playing Sound:
local structure = AudioScape:getStructure(soundInstance)
```

`label` values come from: `Intro`, `Verse`, `Chorus`, `Drop`, `Bridge`, `Climax`, `Outro`, `Main`, `Break`, `Build`, `Breakdown`, `Transition`, `Peak`. `energy` is `1`–`4`.

> **Note on AudioPlayer:** v0.11.0 auto-resolves `audioPlayer.Asset` (the legacy ContentId field). If your project uses the newer `audioPlayer.AudioContent` (a `Content` userdata), pass `audioPlayer.AudioContent.Uri` yourself for now.

### `AudioScape:beatAtTime(asset_id, t)`

Locate the closest beat to a time. Useful for snapping animations to the grid. Reuses the cached structure response, so repeat calls are free.

```lua
local beat, err = AudioScape:beatAtTime("1843209165", currentTime)
-- beat = { time, is_downbeat, bar }
```

### `AudioScape:sectionAtTime(asset_id, t, level?)`

Locate the section (or phrase, with `level = "phrase"`) covering a time. Trigger different effects on Verse vs Drop. `level` defaults to `"section"` (the finer layer); pass `"phrase"` for the coarser groupings — better for longer transitions like crossfades.

```lua
local section = AudioScape:sectionAtTime("1843209165", currentTime)
if section and section.label == "Drop" then
    workspace.CurrentCamera.FieldOfView = 70 + section.energy * 5
end
```

### `AudioScape:getPlaylist(options)`

Fetch a configured playlist and its tracks. Playlists are created in the [Developer Portal](https://developer.audioscape.ai/configure).

```lua
local result, err = AudioScape:getPlaylist({
    playlist_id = "station-electronic-1712...",  -- required
    playerId = player.UserId,                    -- optional
})
-- result = { playlist, tracks, meta }
-- result.playlist = { id, name, genre, playback_mode, track_count }
-- result.tracks = { { asset_id, name, artist, album, genre, duration, bpm, position, ... } }
```

### `AudioScape:listPlaylists(playerId?)`

List all playlists configured for your API key.

```lua
local result, err = AudioScape:listPlaylists(player.UserId)
-- result = { playlists, meta }
-- result.playlists = { { id, name, genre, playback_mode, track_count } }

if result then
    for _, playlist in result.playlists do
        print(playlist.name, "-", playlist.genre, "-", playlist.track_count, "tracks")
    end
end
```

## Drop-in for `AssetService`

If you already call `AssetService:SearchAudioAsync`, you can point it at AudioScape by changing one line. The `AudioSearchParams` you build and the `AudioPages` you iterate stay exactly the same.

```lua
-- Before
local AssetService = game:GetService("AssetService")

-- After
local AssetService = AudioScape:getAssetService()

-- Unchanged from here down
local params = Instance.new("AudioSearchParams")
params.SearchKeyword = "calm ambient"

local ok, pages = pcall(function()
    return AssetService:SearchAudioAsync(params)
end)
if ok then
    for _, audio in pages:GetCurrentPage() do
        print(audio.Title, "—", audio.Artist, audio.Duration .. "s")
    end
end
```

### `AudioScape:getAssetService(options?)`

Returns a stand-in for `AssetService`. `SearchAudioAsync` (and its deprecated `SearchAudio` alias) runs against AudioScape's catalog; **every other member forwards to the real service**, so unrelated calls like `GetAudioMetadataAsync`, `CreateEditableImage`, or `GetBundleDetailsAsync` behave exactly as before.

| Option | Type | Default | Description |
| --- | --- | --- | --- |
| `fallback` | `boolean?` | `true` | On an AudioScape error, fall through to the real `AssetService:SearchAudioAsync` instead of raising. Leave it on unless you'd rather see failures. |
| `limit` | `number?` | `30` | Results per page. Matches native's page size by default. |

**How `AudioSearchParams` maps.** `AudioSubType` picks the catalog — `Music` searches music, `SoundEffect` searches SFX. `SearchKeyword`, `Title`, `Artist`, and `Album` combine into the semantic query (AudioScape matches on meaning, not just keywords, and already handles artist matching). `Tag` becomes a genre filter for music or a category filter for SFX, and stands in as the query if you set nothing else. `MinDuration` / `MaxDuration` become a duration filter.

**Results** carry every field native returns — `Id`, `Title`, `Artist`, `Description`, `Duration`, `Tags`, `AudioType`, `IsEndorsed`, `CreateTime`, `UpdateTime`, and `Creator` — plus extra AudioScape fields native has no equivalent for:

| Field | Description |
| --- | --- |
| `AssetId` | The asset ID as a string, ready for `"rbxassetid://" .. audio.AssetId` |
| `Score` | Relevance score for the query (0–1) |
| `Genre` / `GenreSlug` | Canonical genre and its URL-safe slug (music only) |
| `Bpm` | Tempo, when known (music only) |

`IsEndorsed` is always `false` — that's Roblox's own endorsement flag and AudioScape doesn't track it. The field is present so code that reads it keeps working.

Pagination works as usual: `pages:GetCurrentPage()`, `pages:AdvanceToNextPageAsync()`, and `pages.IsFinished`. Like native, `SearchAudioAsync` raises on failure rather than returning an error — wrap it in `pcall`.

This also works from a LocalScript via `AudioScapeClient:getAssetService()` once you've called `AudioScape:enableClientAccess()` on the server.

## Sound Banks

A footstep that plays the identical clip every time reads as obviously synthetic — the "machine gun" effect. The usual fix is hand-picking five assets and calling `math.random`. A sound bank does it from the asset you already have.

```lua
local bank = AudioScape:createSoundBank({
    seeds = { footstep = "rbxassetid://1837879082" },
    kind = "sfx",
})
bank:resolveAsync()

-- Later, on every step:
sound.SoundId = "rbxassetid://" .. bank:pick("footstep")
```

`pick` never returns the same asset twice in a row.

### `AudioScape:createSoundBank(options)`

| Option | Type | Default | Description |
| --- | --- | --- | --- |
| `seeds` | `{ [string]: string }` | — | Named asset IDs, e.g. `{ footstep = "rbxassetid://123" }` |
| `kind` | `string?` | `"sfx"` | `"sfx"` expands through the sound-effects catalog, `"music"` through music |
| `poolSize` | `number?` | `8` | How many assets to end up with per seed |
| `mode` | `string?` | `"extend"` | `"extend"` keeps your asset in the pool and adds neighbours; `"replace"` uses neighbours only |
| `playerId` | `number?` | — | |

**Your asset is never silently swapped.** In the default `extend` mode it leads its own pool — we add to your choice rather than overriding it. `replace` exists for cases where you genuinely don't care which specific clip plays, and you have to ask for it.

### Methods

| Method | Description |
| --- | --- |
| `bank:resolveAsync()` | Build the pools. Returns `(ok, err)`. |
| `bank:pick(name)` | An asset ID from that pool, never the same one twice running |
| `bank:getPool(name)` | The whole pool as a list, e.g. to replicate to clients |
| `bank:reportUnavailable(assetId)` | Drop an asset that failed to load; later picks avoid it |
| `bank:flushPickCounts()` | Emit accumulated pick analytics |
| `bank:destroy()` | Flush and clear |

**Resolve once at startup.** Roblox caps a server at 500 HTTP requests per minute, so resolving per-play would exhaust the budget almost immediately. After `resolveAsync()`, every `pick` is a local table lookup with no request.

### Seeding from assets we don't have

If a seed isn't in AudioScape's catalog, the bank asks the engine what the asset *is* (`AssetService:GetAudioMetadataAsync`, which works for any Roblox audio ID) and searches on its title and artist to find an anchor. `bank.Pools[name].source` tells you which path was taken:

| `source` | Meaning |
| --- | --- |
| `catalog` | The seed itself is in our catalog |
| `bridged` | Matched through the engine's metadata for the seed |
| `none` | Couldn't resolve — the pool is just your seed |

`none` is a graceful degradation, not an error: you get back exactly the behaviour you had before adding the bank.

### Healing broken assets

A moderated or otherwise unavailable asset is a silent bug — it just doesn't play. Only a client can detect this: a headless server never fetches audio, so `GetAssetFetchStatus` stays `None` there forever. Watch it client-side and report back:

```lua
local ContentProvider = game:GetService("ContentProvider")

ContentProvider.AssetFetchFailed:Connect(function(assetId)
    reportFailureRemote:FireServer(assetId)  -- server calls bank:reportUnavailable
end)
```

Once reported, that asset is excluded from future picks. If every asset in a pool becomes unavailable, `pick` falls back to your original seed rather than returning `nil`.

### Analytics

Picks are far too frequent to report individually — a footstep loop would overrun the 500-event buffer in seconds. The bank counts locally and `flushPickCounts()` emits one `audio_pick` event per distinct asset carrying a `count`. `resolveAsync()` emits one `audio_resolve` per seed, and `reportUnavailable` emits `audio_unavailable`.

## Auditing your audio

### `AudioScape:auditAudio(options?)`

Walks your place for every `Sound` and `AudioPlayer`, collects the distinct asset IDs, and tells you which ones AudioScape's catalog knows about.

```lua
local audit, err = AudioScape:auditAudio()
if audit then
    print(audit.meta.distinct_assets .. " distinct audio assets in this place")
    for _, asset in audit.assets do
        print(string.format("%s — %d uses — %s", asset.asset_id, asset.uses, asset.sample_path))
    end
end
```

| Option | Type | Default |
| --- | --- | --- |
| `roots` | `{ Instance }?` | Workspace, ReplicatedStorage, ServerStorage, ServerScriptService, StarterGui, StarterPack, StarterPlayer, SoundService, Lighting |
| `playerId` | `number?` | — |

Results are ordered most-used first. Each entry gives:

| Field | Description |
| --- | --- |
| `asset_id` | The asset ID as a string |
| `uses` | How many instances reference it |
| `sample_path` | `GetFullName()` of the first instance found, so you can jump to it |
| `known` | Whether AudioScape's catalog has this asset |

`meta` carries `instances_scanned`, `distinct_assets`, `known`, and `unknown`.

`known = false` means we can't offer similarity or variations for that asset — it says nothing about whether the asset still plays. Sounds with an empty `SoundId` are counted in `instances_scanned` but skipped otherwise, since an unassigned template is normal.

This walks the data model, so treat it as a startup or development diagnostic rather than something to poll. On a large place, pass a narrower `roots` list.

## Music Player

The `AudioScapeMusicPlayer` manages audio playback — queue tracks, play, skip — and automatically fires `trackPlay`, `trackStop`, and `trackSkip` analytics events with accurate listen durations.

### `AudioScape:createPlayer(options?)`

Create an AudioScapeMusicPlayer instance.

```lua
local player = AudioScape:createPlayer({
    volume = 0.5,               -- optional (default: 0.5)
    parent = SoundService,      -- optional (default: SoundService)
    playerId = player.UserId,   -- optional, for per-player analytics
})
```

### `player:queue(tracks)`

Add tracks to the end of the play queue.

```lua
local result = AudioScape:search({ query = "upbeat summer" })
player:queue(result.tracks)
```

### `player:setQueue(tracks)`

Replace the queue with new tracks and stop current playback.

### `player:clearQueue()`

Clear the queue and stop playback.

### `player:play()`

Start playing from the current position in the queue.

### `player:stop()`

Stop the currently playing track. Fires a `stop` analytics event with listen duration.

### `player:skip()`

Skip to the next track. Fires a `skip` analytics event with how long the player listened.

```lua
-- Skip fires analytics automatically
player:skip()
```

### `player:playTrack(track)`

Play a single track immediately, replacing current playback.

```lua
local result = AudioScape:search({ query = "epic boss battle", limit = 1 })
player:playTrack(result.tracks[1])
```

### `player:setVolume(volume)`

Set playback volume (0 to 1).

### `player:setPlayerId(playerId)`

Set or change the player ID used for analytics.

### Callbacks

```lua
player.OnTrackChanged = function(track)
    if track then
        print("Now playing:", track.artist, "—", track.name)
    end
end

player.OnQueueFinished = function()
    print("Queue finished!")
end
```

### State

| Property | Type | Description |
|---|---|---|
| `player.NowPlaying` | `Track?` | Currently playing track, or nil |
| `player.IsPlaying` | `boolean` | Whether audio is currently playing |
| `player.Queue` | `{ Track }` | Current track queue |

---

## Calling from LocalScripts

`AudioScape` itself runs on the server — `HttpService` requires server context. To reach it from a LocalScript, enable access on the server and use the `AudioScapeClient` companion module on the client.

### Server Setup

Call `enableClientAccess()` once on the server to create the RemoteFunctions:

```lua
AudioScape.setApiKey(apiKey)
AudioScape:enableClientAccess()
```

This creates an `AudioScapeRemotes` folder in `ReplicatedStorage` with a RemoteFunction for each API method. Requests are rate-limited per player (1 request/second) and `playerId` is automatically set from the calling player.

### Client Usage

Place `AudioScapeClient.luau` in `ReplicatedStorage`. Then use it from any LocalScript:

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AudioScapeClient = require(ReplicatedStorage.AudioScapeClient)

local result, err = AudioScapeClient:search({ query = "chill beats", limit = 10 })
```

**Available methods on `AudioScapeClient`:** `search`, `lookup`, `similar`, `browse`, `sfxSearch`, `sfxSimilar`, `sfxBrowse`, `getSfxTaxonomy`, `getStructure`, `getPlaylist`, `listPlaylists`, `getAssetService`

> **Note:** `AudioScapeClient.luau` must be placed in `ReplicatedStorage` manually (or via the Studio plugin). The server SDK's Wally realm is `server`, so it installs to `ServerScriptService` — the client module is distributed separately.

---

## Analytics

Analytics are collected automatically — events are buffered in memory and flushed every 30 seconds (configurable). On game close, remaining events are flushed via `game:BindToClose`. No player PII is stored; `playerId` is used only for unique player counts.

> **Tip:** If you use `AudioScape:createPlayer()`, play/stop/skip events are tracked automatically. The manual tracking methods below are for custom integrations or events the player can't detect (votes, favorites, etc.).

### `AudioScape:configureAnalytics(config)`

Configure analytics batching behavior. Call before tracking events.

```lua
AudioScape:configureAnalytics({
    enabled = true,       -- default: true
    batchInterval = 30,   -- seconds between flushes (min: 5)
    maxBatchSize = 50,    -- events per flush (1-500)
    maxQueueSize = 500,   -- max buffered events (min: 10)
})
```

### `AudioScape:trackPlay(assetId, playerId?, duration?)`

Track a song play event.

```lua
AudioScape:trackPlay("rbxassetid://123456789", player.UserId, 120)
```

### `AudioScape:trackStop(assetId, playerId?, duration?)`

Track a song stop event (natural end or user action).

### `AudioScape:trackSkip(assetId, playerId?, duration?)`

Track a song skip event. Duration is how long the player listened before skipping.

### `AudioScape:trackVote(assetId, value, playerId?)`

Track a vote. Value must be `"up"` or `"down"`.

```lua
AudioScape:trackVote("rbxassetid://123456789", "up", player.UserId)
```

### `AudioScape:trackFavorite(assetId, playerId?)`

Track a favorite event.

### `AudioScape:trackUnfavorite(assetId, playerId?)`

Track an unfavorite event.

### `AudioScape:trackAddToQueue(assetId, playerId?)`

Track when a player adds a song to a queue, setlist, or playlist.

### `AudioScape:trackSearchClick(assetId, playerId?, metadata?)`

Track when a player clicks a search result.

### `AudioScape:trackCustom(eventType, assetId?, playerId?, metadata?)`

Track a custom event with any type name.

```lua
AudioScape:trackCustom("song_previewed", assetId, player.UserId, {
    source = "browse_genre",
    position = 3,
})
```

### `AudioScape:flushAnalytics()`

Force flush all buffered events immediately. Called automatically on game close.

## Rate Limits

Roblox enforces a limit of **500 HTTP requests per minute** per game server. Keep this in mind when designing your integration — consider caching results and debouncing player-triggered searches.

## Error Handling

All methods return `result, err`. On failure, `result` is `nil` and `err` is a descriptive string:

```lua
local result, err = AudioScape:search({ query = "test" })
if not result then
    warn("Search failed:", err)
    return
end
```

## Examples

See the [`examples/`](examples/) folder for complete usage examples:

- **MusicPlayerBasic.luau** — Search, queue, and play with auto-analytics
- **MusicPlayerPlaylist.luau** — Play a configured playlist with the AudioScapeMusicPlayer
- **ClientSearch.luau** — Search from a LocalScript using AudioScapeClient
- **SearchBox.luau** — Wire search to a TextBox input via RemoteEvent
- **BrowseGenres.luau** — List genres and play a random track
- **SimilarTrack.luau** — Auto-playlist using similar tracks
- **PlaylistStation.luau** — Fetch and play a configured station playlist
- **SfxImpactPool.luau** — Pre-fetch a variety pool of SFX clips and randomize per swing
- **StructureBeatSync.luau** — Schedule particle bursts on downbeats and punch the camera FOV on Drops
- **TrendingLobbyJukebox.luau** — Drop-in lobby music from `browse({ type = "trending" })` piped through the music player
- **TrendingSfxBoard.luau** — Lobby sound board built from `sfxBrowse({ type = "trending" })`
- **AssetServiceDropIn.luau** — Point existing `AssetService:SearchAudioAsync` code at AudioScape by changing one line

## Links

- [Developer Portal](https://developer.audioscape.ai)
- [API Documentation](https://developer.audioscape.ai/docs)
- [Discord](https://discord.gg/kVujTS7FP3)

## License

MIT
