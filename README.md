# AudioScape SDK for Roblox

A Luau SDK for the [AudioScape Developer API](https://developer.audioscape.ai) — search music and sound effects, browse the catalog, sync to beat-level track structure, and track analytics for your Roblox experiences.

> **Note:** This SDK uses `HttpService:RequestAsync()` and must run on the **server** (Script, not LocalScript). You must enable **Allow HTTP Requests** in your experience's Game Settings → Security.

## Installation

### Wally

Add to your `wally.toml`:

```toml
[server-dependencies]
AudioScape = "this-fifo/audioscape-sdk@0.15.0"
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

local client = AudioScape.new(apiKey)
local player = client:createPlayer()

-- Search and play
local result, err = client:search({ query = "chill lo-fi beats", limit = 10 })
if result then
    player:queue(result.tracks)
    player:play()
end
```

The `AudioScapeMusicPlayer` handles Sound lifecycle, queue advancement, and analytics tracking automatically — no manual `trackPlay`/`trackStop` calls needed.

## Telemetry

The SDK automatically sends your game's Universe ID and Place ID with every request to help you track usage across your experiences. You can also pass an optional `playerId` to tie requests to specific players:

```lua
local result, err = client:search({
    query = "epic battle music",
    playerId = player.UserId,
})
```

## API

### `AudioScape.new(apiKey: string)`

Creates a new client instance.

```lua
local client = AudioScape.new("your-api-key")
```

### `client:search(options)`

Search the catalog using natural language, or look up specific tracks by asset ID.

```lua
local result, err = client:search({
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
(see `client:lookup` below). Pass either one. When both are present, the API
prefers `asset_ids` and skips text search. `result.meta.search_method` will be
`"semantic"` / `"text"` / `"id"` / `"ids-batch"` depending on how the
request resolved.

### `client:lookup(options)`

Resolve up to 100 known asset IDs in a single request. Returned tracks are in
input order, filters are bypassed, and IDs that didn't match (deleted,
delisted, non-public, or never existed) come back in `result.meta.missing_ids`.
Sugar over `client:search({ asset_ids = ... })`.

```lua
local result, err = client:lookup({
    asset_ids = { "1843209165", "9120386436", "1234567890" },
    playerId = player.UserId,  -- optional
})
-- result = { tracks, artists, albums, meta }
-- result.meta.missing_ids = { "1234567890" }  -- IDs that didn't resolve
```

### `client:similar(input, extras?)`

Find tracks that sound similar to a given track. `input` is anything that
carries an asset_id — a string, a Track from a previous response, a `Sound`,
or an `AudioPlayer`.

```lua
local result, err = client:similar({
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
local result = client:similar(playlist.tracks[1], { limit = 10 })

-- Shorthand: pass a playing Sound directly
local result = client:similar(soundInstance)
```

### `client:browse(options)`

Browse by artist, album, genre, mood, or trending.

```lua
-- List all genres
local result, err = client:browse({ type = "genre" })
-- result = { items, meta }

-- Get tracks for a specific genre (defaults to popularity-ranked)
local result, err = client:browse({ type = "genre", name = "electronic", limit = 20 })
-- result = { tracks, meta }

-- Same drill-down, alpha sort to surface fresh uploads
local result, err = client:browse({ type = "genre", name = "electronic", sort = "alpha", limit = 20 })

-- Trending music (no name needed — returns the top tracks directly)
local result, err = client:browse({ type = "trending", limit = 50 })
-- result = { tracks, meta }
```

**Browse types:** `artist`, `album`, `genre`, `mood`, `trending`

**Sort (drill-down only):** `popular` (default — global popularity ranking, omits tracks with no engagement), `alpha` (track name A→Z), `recent` (newest first). Ignored for list mode and for `trending` (already popularity-ordered). Pick `alpha` or `recent` to surface tracks that haven't accumulated engagement yet.

Trending is a popularity-ranked list of music tracks refreshed daily, capped at 200 entries. Player engagement signals (plays, favorites, votes, queue adds, listen duration, plus custom events) are exponentially decayed over a 60-day window with a 30-day half-life, so recent activity dominates.

### `client:sfxBrowse(options)`

Browse the SFX catalog. v1 only supports `type = "trending"` — a popularity-ranked list of sound effects, refreshed daily on the same schedule as music trending.

```lua
local result, err = client:sfxBrowse({ type = "trending", limit = 50 })
-- result = { tracks, meta }
-- result.tracks = { { asset_id, name, description, category, subcategory, tags, duration, ... } }
```

### `client:sfxSearch(options)`

Search the sound effects catalog. Pass a free-text `query`, or browse a UCS category by passing `filters.categories` (the API synthesizes the query under the hood).

```lua
local result, err = client:sfxSearch({
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

### `client:sfxSimilar(input, extras?)`

Find sound effects acoustically similar to a given asset. Same polymorphic
input as `client:similar`.

```lua
local result, err = client:sfxSimilar({
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
local result = client:sfxSimilar(sfx.tracks[1], { limit = 10 })
```

### `client:getSfxTaxonomy()`

Fetch the full `broader_category → category → subcategory` hierarchy for building SFX picker UIs. Server-cached for 10 minutes, so polling is cheap.

```lua
local taxonomy, err = client:getSfxTaxonomy()
-- taxonomy.taxonomy = { { broader_category, categories = { { category, subcategories = { string } } } } }
```

### `client:getStructure(input, extras?)`

Fetch the beat grid and section structure for a track. Use this to sync
animations, lighting, or VFX to the music. Same polymorphic input as
`client:similar` — pass a string, a Track, a `Sound`, or an `AudioPlayer`.

```lua
local structure, err = client:getStructure({
    asset_id = "1843209165",  -- required
})
-- structure = { asset_id, duration, bpm, track_energy, beat_grid, sections, phrases }
-- structure.beat_grid = { times = { number }, downbeats = { number } }
-- structure.sections = { { start, end, label, energy, bar_start, bar_end, color } }
-- structure.phrases  = same shape as sections, but a coarser layer — fewer,
--                      longer segments. sections are the finer layer (more,
--                      shorter). Both carry the same label set.

-- Or pull structure straight from the playing Sound:
local structure = client:getStructure(soundInstance)
```

`label` values come from: `Intro`, `Verse`, `Chorus`, `Drop`, `Bridge`, `Climax`, `Outro`, `Main`, `Break`, `Build`, `Breakdown`, `Transition`, `Peak`. `energy` is `1`–`4`.

> **Note on AudioPlayer:** v0.11.0 auto-resolves `audioPlayer.Asset` (the legacy ContentId field). If your project uses the newer `audioPlayer.AudioContent` (a `Content` userdata), pass `audioPlayer.AudioContent.Uri` yourself for now.

### `client:beatAtTime(asset_id, t)`

Locate the closest beat to a time. Useful for snapping animations to the grid. Reuses the cached structure response, so repeat calls are free.

```lua
local beat, err = client:beatAtTime("1843209165", currentTime)
-- beat = { time, is_downbeat, bar }
```

### `client:sectionAtTime(asset_id, t, level?)`

Locate the section (or phrase, with `level = "phrase"`) covering a time. Trigger different effects on Verse vs Drop. `level` defaults to `"section"` (the finer layer); pass `"phrase"` for the coarser groupings — better for longer transitions like crossfades.

```lua
local section = client:sectionAtTime("1843209165", currentTime)
if section and section.label == "Drop" then
    workspace.CurrentCamera.FieldOfView = 70 + section.energy * 5
end
```

### `client:getPlaylist(options)`

Fetch a configured playlist and its tracks. Playlists are created in the [Developer Portal](https://developer.audioscape.ai/configure).

```lua
local result, err = client:getPlaylist({
    playlist_id = "station-electronic-1712...",  -- required
    playerId = player.UserId,                    -- optional
})
-- result = { playlist, tracks, meta }
-- result.playlist = { id, name, genre, playback_mode, track_count }
-- result.tracks = { { asset_id, name, artist, album, genre, duration, bpm, position, ... } }
```

### `client:listPlaylists(playerId?)`

List all playlists configured for your API key.

```lua
local result, err = client:listPlaylists(player.UserId)
-- result = { playlists, meta }
-- result.playlists = { { id, name, genre, playback_mode, track_count } }

if result then
    for _, playlist in result.playlists do
        print(playlist.name, "-", playlist.genre, "-", playlist.track_count, "tracks")
    end
end
```

## Music Player

The `AudioScapeMusicPlayer` manages audio playback — queue tracks, play, skip — and automatically fires `trackPlay`, `trackStop`, and `trackSkip` analytics events with accurate listen durations.

### `client:createPlayer(options?)`

Create an AudioScapeMusicPlayer instance.

```lua
local player = client:createPlayer({
    volume = 0.5,               -- optional (default: 0.5)
    parent = SoundService,      -- optional (default: SoundService)
    playerId = player.UserId,   -- optional, for per-player analytics
})
```

### `player:queue(tracks)`

Add tracks to the end of the play queue.

```lua
local result = client:search({ query = "upbeat summer" })
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
local result = client:search({ query = "epic boss battle", limit = 1 })
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

## Client Access

The SDK runs on the server (HttpService requires server context). To call AudioScape from LocalScripts, enable client access on the server and use the `AudioScapeClient` companion module.

### Server Setup

Call `enableClientAccess()` once on the server to create the RemoteFunctions:

```lua
local client = AudioScape.new(apiKey)
client:enableClientAccess()
```

This creates an `AudioScapeRemotes` folder in `ReplicatedStorage` with a RemoteFunction for each API method. Requests are rate-limited per player (1 request/second) and `playerId` is automatically set from the calling player.

### Client Usage

Place `AudioScapeClient.luau` in `ReplicatedStorage`. Then use it from any LocalScript:

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AudioScapeClient = require(ReplicatedStorage.AudioScapeClient)

local client = AudioScapeClient.new()
local result, err = client:search({ query = "chill beats", limit = 10 })
```

**Available client methods:** `search`, `lookup`, `similar`, `browse`, `sfxSearch`, `sfxSimilar`, `sfxBrowse`, `getSfxTaxonomy`, `getStructure`, `getPlaylist`, `listPlaylists`

> **Note:** `AudioScapeClient.luau` must be placed in `ReplicatedStorage` manually (or via the Studio plugin). The server SDK's Wally realm is `server`, so it installs to `ServerScriptService` — the client module is distributed separately.

---

## Analytics

Analytics are collected automatically — events are buffered in memory and flushed every 30 seconds (configurable). On game close, remaining events are flushed via `game:BindToClose`. No player PII is stored; `playerId` is used only for unique player counts.

> **Tip:** If you use `client:createPlayer()`, play/stop/skip events are tracked automatically. The manual tracking methods below are for custom integrations or events the player can't detect (votes, favorites, etc.).

### `client:configureAnalytics(config)`

Configure analytics batching behavior. Call before tracking events.

```lua
client:configureAnalytics({
    enabled = true,       -- default: true
    batchInterval = 30,   -- seconds between flushes (min: 5)
    maxBatchSize = 50,    -- events per flush (1-500)
    maxQueueSize = 500,   -- max buffered events (min: 10)
})
```

### `client:trackPlay(assetId, playerId?, duration?)`

Track a song play event.

```lua
client:trackPlay("rbxassetid://123456789", player.UserId, 120)
```

### `client:trackStop(assetId, playerId?, duration?)`

Track a song stop event (natural end or user action).

### `client:trackSkip(assetId, playerId?, duration?)`

Track a song skip event. Duration is how long the player listened before skipping.

### `client:trackVote(assetId, value, playerId?)`

Track a vote. Value must be `"up"` or `"down"`.

```lua
client:trackVote("rbxassetid://123456789", "up", player.UserId)
```

### `client:trackFavorite(assetId, playerId?)`

Track a favorite event.

### `client:trackUnfavorite(assetId, playerId?)`

Track an unfavorite event.

### `client:trackAddToQueue(assetId, playerId?)`

Track when a player adds a song to a queue, setlist, or playlist.

### `client:trackSearchClick(assetId, playerId?, metadata?)`

Track when a player clicks a search result.

### `client:trackCustom(eventType, assetId?, playerId?, metadata?)`

Track a custom event with any type name.

```lua
client:trackCustom("song_previewed", assetId, player.UserId, {
    source = "browse_genre",
    position = 3,
})
```

### `client:flushAnalytics()`

Force flush all buffered events immediately. Called automatically on game close.

## Rate Limits

Roblox enforces a limit of **500 HTTP requests per minute** per game server. Keep this in mind when designing your integration — consider caching results and debouncing player-triggered searches.

## Error Handling

All methods return `result, err`. On failure, `result` is `nil` and `err` is a descriptive string:

```lua
local result, err = client:search({ query = "test" })
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

## Links

- [Developer Portal](https://developer.audioscape.ai)
- [API Documentation](https://developer.audioscape.ai/docs)
- [Discord](https://discord.gg/kVujTS7FP3)

## License

MIT
