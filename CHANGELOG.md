# Changelog

## v0.10.1

### Changed

- `client:similar(...)` and `client:sfxSimilar(...)` now hit the API over **GET** instead of POST — same migration as `browse`/`sfxBrowse`/`getSfxTaxonomy` in v0.10.0, same caching rationale (CloudFront edge cache, ~30 ms warm-cache reads). Public method signatures, options, and return shapes are unchanged. The API still accepts the equivalent POST for older SDK clients during migration; no breakage from upgrading. The internal `buildQuery()` helper now JSON-encodes table values (e.g. `filters`) into a single querystring parameter

### Fixed

- `Section.end` field annotation now uses `["end"]` quoting — `end` is a reserved Luau keyword, and the unquoted form prevented `require()` of the SDK from parsing on any Luau analyzer or runtime. Affected every release from `v0.7.0` (when `getStructure` shipped) through `v0.10.0`. Consumers reading the field must use `section["end"]` (the API wire format already returns `end`, so this matches what's on the response). Reported in #3 by Sean (Rhythm Run / OffGridDude). Thanks Sean!
- Tightened a few pre-existing type-narrowing holes in `AudioScapeMusicPlayer` and `AudioScape.createPlayer` that the new analyzer surfaced — no behavior change

### Internal

- New QA toolchain: StyLua (format), selene (lint), `luau-lsp analyze` (parse + type check), Lune unit tests, and an Open Cloud Luau Execution smoke suite — all wired into a GitHub Actions CI job that runs on every PR. The SDK module is now `require`-checked end-to-end on every push, so the issue #3 class of bug can't ship again
- Rokit (`rokit.toml`) pins every tool version so contributors get the same toolchain as CI
- 25 checks total: 10 Lune unit specs + 15 Open Cloud smoke steps. The smoke suite runs the SDK *inside* the real Roblox engine via Open Cloud Luau Execution — every HTTP-hitting public method plus engine-only paths (`Sound.Ended` connect, `RemoteFunction` tree, real `workspace:GetServerTimeNow`) exercised against the live API in ~5s. Dogfooded fixtures (IDs discovered at test time via the SDK's own browse/sfxBrowse endpoints) mean no env-var maintenance for assets. AudioScape key is retrieved via `HttpService:GetSecret` — never materialises as a plain string in source
- CI smoke job is gated behind a GitHub environment (`openCloud-smoke`) with required-reviewer protection — a maintainer must approve each run before the Roblox/AudioScape secrets are exposed to the runner
- See `CONTRIBUTING.md` for local setup + the manual Studio checklist for audio playback and BindToClose shutdown flush (Luau Execution doesn't fire BindToClose callbacks)

## v0.10.0

### Changed

- `client:browse(...)`, `client:sfxBrowse(...)`, and `client:getSfxTaxonomy()` now hit the API over **GET** instead of POST. Public method signatures, options, and return shapes are unchanged — but responses are now eligible for CloudFront edge caching, so identical calls served from a nearby edge return in ~30 ms anywhere globally instead of round-tripping to us-east-2 every time. Cache keys are per-API-key, so customers stay isolated. The API still accepts the equivalent POST for SDK <0.10.0 clients during migration; no breakage from upgrading
- TTL at the edge is 5 min default / 1 hour ceiling. Trending lists and canonical-genre drill-downs are invalidated automatically when the underlying refresh crons run, so changes surface within seconds rather than waiting on TTL expiry

### Internal

- New `requestGet()` helper alongside `request()` (POST). Asymmetric naming is intentional and isolated; the two will fold into a single method-aware helper at v1.0.0

## v0.9.1

### Added

- `examples/TrendingLobbyJukebox.luau` — daily-trending music piped through `AudioScapeMusicPlayer` with a now-playing label
- `examples/TrendingSfxBoard.luau` — lobby sound board built from `client:sfxBrowse({ type = "trending" })`

### Docs

- README install snippet bumped to `0.9.1`; trending music description tightened
- CHANGELOG copy polish on the v0.9.0 entry

## v0.9.0

### Added

- `client:browse({ type = "trending", limit, offset })` — popularity-ranked list of music tracks. No `name` required; returns `{ tracks, meta }` directly. Refreshed daily; player engagement signals (plays, favorites, votes, queue adds, listen duration, plus custom events) are exponentially decayed over a 60-day window
- `client:sfxBrowse({ type = "trending", limit, offset })` — popularity-ranked list of sound effects. Mirrors `browse()` but returns `SfxTrack`-shaped entries from the SFX catalog
- `AudioScapeClient.sfxBrowse(options)` exposed on the client-side companion (RemoteFunction `SfxBrowse`)
- New types: `SfxBrowseOptions`, `SfxBrowseResult`

## v0.8.0

### Added

- `client:sfxSearch({ query?, filters?, limit?, offset? })` — search the sound effects catalog. Pass a free-text `query`, or pass `filters.categories` (with optional `filters.subcategories`) to browse a category — the API injects a curated query under the hood
- `client:sfxSimilar({ asset_id, filters?, limit?, offset? })` — find sound effects acoustically similar to a given asset
- `client:getSfxTaxonomy()` — fetch the broader-category → category → subcategory hierarchy for building SFX picker UIs (10-minute server cache, so polling is cheap)
- `AudioScapeClient.sfxSearch(options)`, `AudioScapeClient.sfxSimilar(options)`, and `AudioScapeClient.getSfxTaxonomy()` exposed on the client-side companion (RemoteFunctions `SfxSearch`, `SfxSimilar`, `GetSfxTaxonomy`)
- New types: `SfxSearchOptions`, `SfxSimilarOptions`, `SfxTrack`, `SfxSearchResult`, `SfxSimilarResult`, `SfxTaxonomyResult`, `SfxTaxonomyGroup`, `SfxTaxonomyCategory`

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
