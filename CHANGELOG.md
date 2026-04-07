# Changelog

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
