# Changelog

## v0.16.0

### Added

- **`region` option on `client:browse` and `client:sfxBrowse` trending lists.** Pass `region` on a `type = "trending"` call to get a list ranked by activity from a single part of the world instead of the global list. Accepts `"auto"` (auto-detect from the server's location) or an explicit `"americas"`, `"eu"`, or `"apac"`. Omit `region` for the global list (the default), so existing call sites are unchanged. Also accepted on `client:search` for region-scoped results.
  - Regional trending must be enabled for your API key. Until then, `region` is ignored and you get the global list — no error, no breakage.
  - Mirrored on `AudioScapeClient` (LocalScript-side) over the existing `Browse`, `SfxBrowse`, and `Search` RemoteFunctions; the server forwards the field unchanged.
- **`sort` option on `client:search` and `client:sfxSearch`.** Pass `sort = "popular"` to order results by popularity (most-played) or `sort = "recent"` for newest-first, instead of the default `"relevance"` (best semantic match). Omit `sort` for relevance, so existing call sites are unchanged. `result.meta.sort` echoes the applied ordering. Mirrored on `AudioScapeClient` over the `Search` / `SfxSearch` RemoteFunctions.

## v0.15.0

### Changed

- **`AudioScapeMusicPlayer` now uses the new Roblox Audio API (`AudioPlayer` + `AudioDeviceOutput` + `Wire`) instead of legacy `Sound`.** Public method surface is unchanged — `queue`, `setQueue`, `clearQueue`, `play`, `stop`, `skip`, `setVolume`, `setPlayerId`, `playTrack`, `destroy`, the `OnTrackChanged` / `OnQueueFinished` callbacks, and the `NowPlaying` / `IsPlaying` / `Queue` fields all behave the same. The internal `AudioPlayer` is now reachable via the new `player:getAudioPlayer()` accessor so consumers can wire effect chains or drive volume tweens through `TweenService`.

### Added

- **`player:getAudioPlayer()`** — returns the current `AudioPlayer` Instance, or `nil` if not playing. Use for `TweenService`-driven volume animation (e.g. lobby-music crossfades) or for wiring custom effect chains (filters, reverbs) downstream of the player's output.
- **`PlayerOptions.output`** — pass a custom `AudioDeviceOutput` / `AudioEmitter` Instance to opt out of the default auto-created `AudioDeviceOutput`. Useful for spatial setups where the player should feed an `AudioEmitter` on a part instead of a global device output. When omitted, the SDK auto-creates an `AudioDeviceOutput` parented to `options.parent` (defaults to `SoundService`) for the drop-in story.

### Notes

- Requires a Roblox client that supports the new audio API (`AudioPlayer` / `AudioDeviceOutput` / `Wire`). No legacy `Sound` fallback is provided.
- The auto-created `AudioDeviceOutput` is owned by the player and destroyed in `:destroy()`. A caller-provided `options.output` is left in place on destroy — the caller owns its lifecycle.

## v0.14.1

### Changed

- Internal comments on the GET helpers and call sites no longer claim the API "still accepts the equivalent POST" — that's no longer true. No public API or behavior changes.

## v0.14.0

### Added

- **`max_score` and `dedupe` options on `client:similar` and `client:sfxSimilar`.** Both methods now accept two optional filters for dropping near-duplicate matches of the seed asset from the results. `max_score` (number, 0..1) drops results whose `score` field is at or above the threshold. `dedupe` (boolean) is a shortcut that enables a sensible default threshold without picking a number — most callers will reach for this. If both are set, `max_score` wins.
  - Particularly useful with SFX libraries that contain many uploads of the same generic clip (footsteps, ticks, short impacts), where the strongest similarity matches can be exact duplicates of the seed sound.
  - Accepted on the `extras` bag (`client:similar(asset_id, { dedupe = true })`) and on the legacy options-table form (`client:similar({ asset_id = "...", max_score = 0.9 })`).
  - Mirrored on `AudioScapeClient` (LocalScript-side) over the existing `Similar` and `SfxSimilar` RemoteFunctions; the server forwards the new fields unchanged.
  - `dedupe = false` is omitted from the wire request — no point sending the no-op default; keeps edge caches clean.

## v0.13.0

### Added

- **`sort` option on `client:browse`** drill-downs (any call with `name = ...`). Accepts `"popular"` (the new default — global popularity ranking, omits tracks with no engagement), `"alpha"` (track name A→Z), or `"recent"` (newest first). Server defaults to `popular` when omitted, so existing call sites that pass `{ type = "genre", name = "..." }` now return popularity-ranked tracks instead of alphabetical. Pick `alpha` or `recent` to surface tracks that haven't accumulated engagement. Ignored for list mode (`type = "genre"` with no `name`) and for `type = "trending"` (already popularity-ordered). The companion server-side `Browse` RemoteFunction handler in `AudioScapeClient` forwards the field unchanged.

### Notes

- This release flips the default ordering for drill-down browse responses. If you were relying on alphabetical order for `client:browse({ type = "artist" | "album" | "genre" | "mood", name = ... })`, pass `sort = "alpha"` explicitly. Trending and list-mode responses are unchanged.

## v0.12.0

### Added

- **`client:lookup({ asset_ids = { ... } })`.** Batch asset-ID lookup of up to 100 numeric strings. Filters are bypassed server-side, returned tracks preserve input order, and `meta.missing_ids: { string }?` lists IDs that didn't match (deleted, delisted, non-public, never existed). Sugar over `client:search` — equivalent to `client:search({ asset_ids = ... })`. Mirrored on `AudioScapeClient` (LocalScript-side) over the existing `Search` RemoteFunction; the server-side handler now accepts the `asset_ids`-only shape too.
- **`asset_ids` option on `client:search`.** Same wire path as `client:lookup`; use this when you already have a `client:search` call site and want to reuse it for a known-ID lookup. `query` becomes optional when `asset_ids` is set; one or the other is required. The single-numeric-string and comma-delimited-numeric-string short-circuits on `query` (e.g. `query = "12345"` or `query = "12345,67890"`) keep working — the explicit `asset_ids` array is the recommended path because it never falls through to text search on miss.
- **`Track.genre_slug` and `PlaylistTrack.genre_slug`.** URL-safe identifier paired with `genre` (e.g. `{ genre = "Hip Hop / Rap", genre_slug = "hip-hop-rap" }`). Round-trippable into `client:browse({ type = "genre", name = ... })` or `SearchOptions.filters.genres` without URL-encoding.
- **`SearchResult.meta.missing_ids: { string }?`.** Only present on asset-ID lookup responses (single via `query`, batch via `asset_ids`). Omitted when every requested ID resolved.
- **`SearchResult.meta.search_method`** can now also be `"id"` (single-ID short-circuit on `query`) or `"ids-batch"` (explicit `asset_ids`) in addition to the existing `"semantic"` / `"text"`.
- **`AudioScape.BrowseGenreItem` typed export** for items returned by `client:browse({ type = "genre" })`. Fields: `name` (canonical), `slug` (URL-safe), `display_name`, `track_count`. `BrowseListResult.items` itself stays permissively typed (`{ [string]: any }`) so artist/album/mood items aren't forced through a discriminated union; consumers cast genre items manually:

  ```lua
  local result = client:browse({ type = "genre" })
  for _, item in result.items do
      local genre = item :: AudioScape.BrowseGenreItem
      print(genre.display_name, "→", genre.slug)
  end
  ```

### Changed

- **`track.genre` is now uniformly the AudioScape canonical taxonomy across every endpoint.** Previously `client:search`, `client:similar`, and `client:getPlaylist` returned the lowercase Roblox `music_genre` slug (e.g. `"electronic"`) while `client:browse` returned the canonical name (e.g. `"Electronic"`). Now every track-returning endpoint returns the canonical form (e.g. `"Hip Hop / Rap"`, `"Electronic"`, `"R&B / Soul / Funk"`). **Heads-up:** code that compares `track.genre` against a lowercase string (e.g. `if track.genre == "electronic" then ...`) needs to update — either compare against the canonical form, or compare against `track.genre_slug` (new in this release). Code that displays `track.genre` as a label only sees prettier output, no change required.
- **`SearchOptions.filters.genres` and `SimilarOptions.filters.genres` accept any of four shapes**, all resolved server-side to canonical. The shapes: AudioScape canonical (`"Hip Hop / Rap"`), AudioScape URL-safe slug (`"hip-hop-rap"`, the new `track.genre_slug`), off-case canonical (`"hip hop / rap"`), or the legacy Roblox `music_genre` slug (`"hip-hop"`). Existing call sites continue to work; new code can round-trip `track.genre_slug` straight back in.
- **`client:browse({ type = "genre" })` items now expose `slug`** alongside `name` / `display_name` / `track_count`. Drill-downs (`client:browse({ type = "genre", name = ... })`) accept the slug, the canonical name, or off-case canonical — all resolve to the same set of tracks.

### Notes

- Three previously-hidden genres now appear in the `client:browse({ type = "genre" })` list response: **Hardstyle**, **Breakcore**, and **Jersey Club**. Filter-side and drill-down support was already in place; this release only changes their visibility in the browse list.
- The `client:search` validation message changed: was `"search requires a non-empty query string"`, now `"search requires either a non-empty query string or a non-empty asset_ids array"`. Code that pattern-matches on the exact error string needs updating.

## v0.11.0

### Added

- **Polymorphic input on `client:similar`, `client:sfxSimilar`, `client:getStructure`.** Each method now accepts an asset_id string (`"1234"` or `"rbxassetid://1234"`), a Track / PlaylistTrack / SfxTrack table from a previous response, a `Sound` instance (peels `SoundId`), or an `AudioPlayer` instance (peels `Asset`). The legacy options-table form (`{ asset_id, limit, ... }`) keeps working unchanged. New optional second positional arg `extras` carries `limit` / `offset` / `filters` / `playerId` for the non-table forms (`client:similar(sound, { limit = 10 })`). Resolves the "I just got a track from getPlaylist, why am I parsing it back into asset_id" papercut. Companion `AudioScapeClient` (LocalScript-side) gets the same treatment — wire format unchanged, resolution happens client-side.
- `tests/install-snippet.spec.luau` Lune doctest — reads README.md and wally.toml at test time and asserts (1) the install snippet uses `[server-dependencies]`, not `[dependencies]`, and (2) the version pin in the README matches `wally.toml`. Catches the install-bug class going forward without needing a Wally consumer-fixture (Wally 0.3.2 has no path-dep support).

### Fixed

- README install snippet now correctly uses `[server-dependencies]`. The SDK declares `realm = "server"`; Wally's `Realm::is_dependency_valid` rejects server-realm packages placed under `[dependencies]` (the shared section). Consumers following the old README copy hit an install-time error. Reported by Juriaan (Velibor). Thanks Juriaan!

### Notes

- `audioPlayer.Asset` is the auto-resolved field on AudioPlayer in v0.11.0 (the legacy ContentId, still widely used). The newer `.AudioContent` is a `Content` userdata and isn't auto-unwrapped — pass `audioPlayer.AudioContent.Uri` yourself for that path. Will revisit in a future release if customers ask.

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
