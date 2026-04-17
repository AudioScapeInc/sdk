# Changelog

## v0.7.0

### Added

- `client:getStructure({ asset_id })` — fetch beat grid + section/phrase structure for a track. Response includes `bpm`, `track_energy`, downbeats, and labelled sections (Intro/Verse/Chorus/Drop/Bridge/Climax/Outro/etc.) with energy 1–4
- `client:beatAtTime(asset_id, t)` — find the closest beat to a given time. Useful for syncing animations or VFX
- `client:sectionAtTime(asset_id, t, level?)` — find the section (or phrase) covering a time. Lets you trigger different effects on Verse vs Drop
- `AudioScapeClient.getStructure(options)` exposed on the client-side companion (RemoteFunction `GetStructure`)
- New types: `StructureOptions`, `StructureResult`, `BeatGrid`, `Section`, `BeatHit`
- Structure responses are cached client-side per `asset_id` so repeated `beatAtTime`/`sectionAtTime` calls are free

## v0.6.0

### Added

- `SearchOptions.filters` extended with `min_play_count`, `min_likes`, and `created_after` for popularity and recency filtering
- `SimilarOptions.filters` added — supports `genres` and `duration` (mirrors search filter shape)

## v0.5.1

### Fixed

- Analytics events are no longer silently dropped on retryable HTTP errors (429, 5xx) — they are re-queued for the next flush
- Added exponential backoff to the analytics flush loop (30s → 60s → 120s → … capped at 5 min), resets on success
- `flushAnalytics()` and `game:BindToClose` flush no longer infinite-loop when the server is unreachable
- Re-queued events now respect `maxQueueSize` instead of growing unboundedly

## v0.4.0

### Added

- `client:getPlaylist(options)` — fetch a configured station playlist and its tracks
- `client:listPlaylists(playerId?)` — list all playlists configured for your API key
- New types: `PlaylistOptions`, `PlaylistInfo`, `PlaylistTrack`, `PlaylistResult`, `ListPlaylistsResult`
- Example: `PlaylistStation.luau` — fetch and play a configured station playlist

## v0.3.0

### Added

- Analytics batching and automatic flush on game close
- `client:configureAnalytics(config)` for tuning batch settings
- `client:flushAnalytics()` for on-demand flush
- Event tracking methods: `trackPlay`, `trackStop`, `trackSkip`, `trackVote`, `trackFavorite`, `trackUnfavorite`, `trackAddToQueue`, `trackSearchClick`, `trackCustom`

## v0.2.2

### Fixed

- Resolved edge case where `HttpService:RequestAsync` could silently drop headers

## v0.2.0

### Added

- `client:browse(options)` — browse by artist, album, genre, or mood
- `client:similar(options)` — find similar tracks by asset ID

## v0.1.0

### Added

- Initial release
- `AudioScape.new(apiKey)` client constructor
- `client:search(options)` — natural language music search
