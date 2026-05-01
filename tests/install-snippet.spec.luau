--!strict
-- Doctest for the README install snippet. Catches two regression classes
-- without needing a real Wally consumer-fixture (Wally 0.3.2 has no path-dep
-- support, so we can't run `wally install` against an in-tree fixture):
--
--   1. The AudioScape package line MUST appear under [server-dependencies],
--      not [dependencies] — Wally rejects server-realm packages placed in
--      the shared section. Reported by Juriaan v0.10.1, fixed v0.11.0.
--   2. The version pinned in the README install snippet MUST match the
--      version in wally.toml. Manual sync slipped at v0.9.1 ("README install
--      snippet bumped to 0.9.1" was a manual fix in CHANGELOG).
--
-- Lune-only test; reads files via @lune/fs.

local fs = require("@lune/fs")

local readme = fs.readFile("README.md")
local manifest = fs.readFile("wally.toml")

-- 1a. README must contain a [server-dependencies] section.
assert(
	readme:find("%[server%-dependencies%]"),
	"README.md must contain a [server-dependencies] section (SDK realm = server)"
)

-- 1b. Find the AudioScape install line. Capture the section it sits under.
-- The README install block is fenced as a ```toml code block. We walk the
-- file, track the last section header we saw, and assert the AudioScape
-- line's section is [server-dependencies].
local lastSection: string? = nil
local foundUnderServer = false
local foundUnderShared = false
for line in readme:gmatch("[^\n]+") do
	local section = line:match("^%[(.-)%]$")
	if section then
		lastSection = section
	end
	-- Match "AudioScape = \"this-fifo/audioscape-sdk@..."" — the install line.
	if line:match('AudioScape%s*=%s*"this%-fifo/audioscape%-sdk@') then
		if lastSection == "server-dependencies" then
			foundUnderServer = true
		elseif lastSection == "dependencies" then
			foundUnderShared = true
		end
	end
end

assert(foundUnderServer, "README.md install snippet must declare AudioScape under [server-dependencies]")
assert(
	not foundUnderShared,
	"README.md install snippet MUST NOT declare AudioScape under [dependencies] — "
		.. "the SDK is realm=server and Wally rejects this combination at install time"
)

-- 2. Version pin in README must match wally.toml version.
local readmeVersion = readme:match('AudioScape%s*=%s*"this%-fifo/audioscape%-sdk@([^"]+)"')
assert(readmeVersion, "could not extract version pin from README install snippet")

local manifestVersion = manifest:match('version%s*=%s*"([^"]+)"')
assert(manifestVersion, "could not extract version from wally.toml [package]")

assert(
	readmeVersion == manifestVersion,
	string.format(
		"README install snippet pins @%s but wally.toml is %s — they must match",
		readmeVersion,
		manifestVersion
	)
)
