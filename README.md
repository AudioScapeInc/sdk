# AudioScape SDK for Roblox

A Luau SDK for the [AudioScape Developer API](https://developer.audioscape.ai) — search, browse, and discover music for your Roblox experiences.

## Installation

Add to your `wally.toml`:

```toml
[dependencies]
AudioScape = "audioscape/sdk@0.1.0"
```

Then run:

```bash
wally install
```

## Quick Start

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

local AudioScape = require(ReplicatedStorage.Packages.AudioScape)

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
    asset_id = "123456789",  -- required
    limit = 10,              -- optional
    offset = 0,              -- optional
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

## API Key

Get your API key at [developer.audioscape.ai](https://developer.audioscape.ai). Use the [Roblox Secrets Store](https://create.roblox.com/docs/cloud-services/secret-stores) to securely store your key in production:

```lua
local apiKey = if RunService:IsStudio()
    then "your-test-key"
    else HttpService:GetSecret("AudioScapeKey")
```

## Links

- [Developer Portal](https://developer.audioscape.ai)
- [API Documentation](https://developer.audioscape.ai/docs)
- [Discord](https://discord.gg/kVujTS7FP3)

## License

MIT
