# AudioScape SDK for Roblox

A Luau SDK for the [AudioScape Developer API](https://developer.audioscape.ai) — search, browse, discover music, and track analytics for your Roblox experiences.

> **Note:** This SDK uses `HttpService:RequestAsync()` and must run on the **server** (Script, not LocalScript). You must enable **Allow HTTP Requests** in your experience's Game Settings → Security.

## Installation

### Wally

Add to your `wally.toml`:

```toml
[dependencies]
AudioScape = "this-fifo/audioscape-sdk@0.5.1"
```

Then run:

```bash
wally install
```

Since the SDK realm is `server`, Wally installs it to `ServerScriptService.Packages` (or your configured server packages location).

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

Search the catalog using natural language.

```lua
local result, err = client:search({
    query = "epic orchestral battle music",  -- required
    limit = 20,                              -- optional (default: 20, max: 100)
    offset = 0,                              -- optional
    playerId = player.UserId,                -- optional
    filters = {                              -- optional
        genres = { "electronic", "pop" },    -- Roblox music_genre slugs (lowercase)
        duration = { min = 60, max = 180 },  -- seconds
        min_play_count = 100000,             -- min lifetime Roblox plays
        min_likes = 500,                     -- min lifetime Roblox likes
        created_after = "2024-01-01",        -- YYYY-MM-DD
    },
})
-- result = { tracks, artists, albums, meta }
```

### `client:similar(options)`

Find tracks that sound similar to a given track.

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
```

### `client:browse(options)`

Browse by artist, album, genre, or mood.

```lua
-- List all genres
local result, err = client:browse({ type = "genre" })
-- result = { items, meta }

-- Get tracks for a specific genre
local result, err = client:browse({ type = "genre", name = "electronic", limit = 20 })
-- result = { tracks, meta }
```

**Browse types:** `artist`, `album`, `genre`, `mood`

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

**Available client methods:** `search`, `similar`, `browse`, `getPlaylist`, `listPlaylists`

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

## Links

- [Developer Portal](https://developer.audioscape.ai)
- [API Documentation](https://developer.audioscape.ai/docs)
- [Discord](https://discord.gg/kVujTS7FP3)

## License

MIT
