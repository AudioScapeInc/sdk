--!strict
-- Unit test for the resolveAssetId helper. Direct exercise via __internal.
-- Covers the string and table arms; the Instance arm (Sound/AudioPlayer) is
-- exercised by the Open Cloud smoke instead — Lune's typeof returns "table"
-- for the mockGame Instance stubs, so the Instance branch is unreachable
-- here. The negative case below confirms a Sound-*shaped* table cannot sneak
-- through the table arm via the wrong branch.

local mockHttp = require("./_harness/mockHttp")
local loadSdk = require("./_harness/loadSdk").loadSdk

local http = mockHttp.new()
local sdk = loadSdk({ http = http })
local resolveAssetId = (sdk :: any).__internal.resolveAssetId

-- nil
assert(resolveAssetId(nil) == nil, "nil input → nil")

-- string forms
assert(resolveAssetId("1234") == "1234", "bare numeric string round-trips")
assert(resolveAssetId("rbxassetid://1234") == "1234", "rbxassetid URI peels to numeric")
assert(resolveAssetId("rbxassetid://0") == "0", "zero asset id allowed (resolveAssetId is purely structural)")
assert(resolveAssetId("rbxasset://path") == nil, "non-numeric URI → nil")
assert(resolveAssetId("") == nil, "empty string → nil")
assert(resolveAssetId("not-an-id") == nil, "no digits → nil")

-- table forms
assert(resolveAssetId({ asset_id = "x9" }) == "x9", "table.asset_id read verbatim (no regex)")
assert(resolveAssetId({ asset_id = "" }) == nil, "table.asset_id empty → nil")
assert(resolveAssetId({ asset_id = nil :: any }) == nil, "table.asset_id nil → nil")
assert(resolveAssetId({}) == nil, "table without asset_id → nil")
assert(
	resolveAssetId({ asset_id = "abc", playerId = 123 }) == "abc",
	"options-table form (extra fields) returns asset_id verbatim"
)

-- Negative case: Sound-shaped table must NOT be treated as an Instance.
-- In Lune `typeof` returns "table" for plain tables; the branch order in
-- resolveAssetId means the table arm runs and reads .asset_id (which the
-- Sound shape doesn't have) → nil. In real Roblox `typeof` would return
-- "Instance" and the SoundId regex would fire — that path is covered by
-- the Open Cloud smoke. This guards against a regression where the table
-- branch accidentally accepts ClassName/SoundId-shaped objects.
assert(
	resolveAssetId({ ClassName = "Sound", SoundId = "rbxassetid://9999" }) == nil,
	"Sound-shaped plain table → nil (Lune typeof returns 'table'; no asset_id field)"
)

-- Likewise for AudioPlayer-shaped plain table
assert(
	resolveAssetId({ ClassName = "AudioPlayer", Asset = "rbxassetid://9999" }) == nil,
	"AudioPlayer-shaped plain table → nil"
)

-- non-table, non-string inputs
assert(resolveAssetId(42 :: any) == nil, "number → nil")
assert(resolveAssetId(true :: any) == nil, "boolean → nil")
