# AudioScape SDK for Roblox

A Luau SDK for the [AudioScape Developer API](https://developer.audioscape.ai) — search, browse, and discover music for your Roblox experiences.

> **Note:** This SDK uses `HttpService:RequestAsync()` and must run on the **server** (Script, not LocalScript). You must enable **Allow HTTP Requests** in your experience's Game Settings → Security.

## Installation

### Wally

Add to your `wally.toml`:

```toml
[dependencies]
AudioScape = "this-fifo/audioscape-sdk@0.2.0"
```

Then run:

```bash
wally install
```

Since the SDK realm is `server`, Wally installs it to `ServerScriptService.Packages` (or your configured server packages location).

### Roblox Model

Download `AudioScape.rbxm` from the [latest release](https://github.com/AudioScapeInc/sdk/releases/latest) and drop it into `ServerStorage` or `ServerScriptService` in Roblox Studio.

### Manual

Copy `src/init.luau` into your project under `ServerStorage` or `ServerScriptService`. If using Rojo, add it to your server-side project tree.

## Prerequisites

1. **Enable HTTP Requests** — In Roblox Studio, go to Game Settings → Security → Allow HTTP Requests and turn it **on**.
2. **API Key** — Get your key at [developer.audioscape.ai](https://developer.audioscape.ai). Use the [Roblox Secrets Store](https://create.roblox.com/docs/cloud-services/secret-stores) to securely store your key in production.

## Quick Start

```lua
local ServerStorage = game:GetService("ServerStorage")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

local AudioScape = require(ServerStorage.AudioScape)

-- Use a test key in Studio, Secrets Store in production
local apiKey = if RunService:IsStudio()
    then "your-test-key"
    else HttpService:GetSecret("AudioScapeKey")

local client = AudioScape.new(apiKey)

-- Search for music
local result, err = client:search({ query = "chill lo-fi beats", limit = 10 })
if result then
    for _, track in result.tracks do
        print(track.artist, "-", track.name)
    end
end
```

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
        genres = { "electronic", "pop" },
        duration = { min = 60, max = 180 },
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

- **SearchBox.luau** — Wire search to a TextBox input
- **BrowseGenres.luau** — List genres and play a random track
- **SimilarTrack.luau** — Auto-playlist using similar tracks

## Links

- [Developer Portal](https://developer.audioscape.ai)
- [API Documentation](https://developer.audioscape.ai/docs)
- [Discord](https://discord.gg/kVujTS7FP3)

## License

MIT
