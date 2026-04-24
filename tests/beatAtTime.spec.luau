--!strict
-- Unit test for beatAtTime — binary search over the beat grid.

local mockHttp = require("./_harness/mockHttp")
local loadSdk = require("./_harness/loadSdk").loadSdk

local sdk = loadSdk({ http = mockHttp.new() })
local client = (sdk :: any).new("test-key")

-- Build a 16-beat fixture at 0.5s spacing, downbeats every 4 beats.
local times: { number } = {}
local downbeats: { number } = {}
for i = 1, 16 do
	local t = (i - 1) * 0.5
	table.insert(times, t)
	if (i - 1) % 4 == 0 then
		table.insert(downbeats, t)
	end
end

local function injectStructure(assetId: string, structure: any)
	(client :: any)._structureCache[assetId] = structure
end

injectStructure("withGrid", {
	asset_id = "withGrid",
	duration = 8,
	beat_grid = { times = times, downbeats = downbeats },
	sections = {},
	phrases = {},
})

-- Each scenario in its own `do` block — luau-lsp narrows literal-equality
-- assertions and would otherwise carry that narrow across cases.
do
	-- exact-match on first beat
	local hit, err = client:beatAtTime("withGrid", 0)
	assert(hit and not err, "expected hit at t=0")
	assert(hit.index == 1, "first beat → index 1, got " .. hit.index)
	assert(hit.time == 0, "first beat time")
	assert(hit.is_downbeat == true, "first beat is a downbeat")
	assert(hit.beat_num == 1, "first beat → beat_num 1")
end

do
	-- exact-match mid-grid (beat 5 = second downbeat)
	local hit, err = client:beatAtTime("withGrid", 2.0)
	assert(hit and not err, "expected hit at t=2.0")
	assert(hit.index == 5, "beat at t=2.0 should be index 5, got " .. hit.index)
	assert(hit.is_downbeat == true, "beat at t=2.0 is downbeat #2")
	assert(hit.beat_num == 1, "downbeat → beat_num 1")
end

do
	-- between two beats — closer to next
	local hit = client:beatAtTime("withGrid", 0.30)
	assert(hit and hit.index == 2, "t=0.30 closer to beat 2 (t=0.5), got index " .. hit.index)
	assert(hit.is_downbeat == false, "beat 2 is not a downbeat")
	assert(hit.beat_num == 2, "beat 2 (1 after downbeat) → beat_num 2")
end

do
	-- between two beats — closer to prev (tie-break favors earlier)
	local hit = client:beatAtTime("withGrid", 0.25)
	assert(hit and hit.index == 1, "t=0.25 ties → favors earlier beat 1, got index " .. hit.index)
end

do
	-- after last beat → clamps to last beat
	local hit = client:beatAtTime("withGrid", 100)
	assert(hit and hit.index == 16, "t=100 clamps to last beat (index 16), got " .. hit.index)
	assert(hit.beat_num == 4, "beat 16 = 3 beats after downbeat → beat_num 4")
end

do
	-- before first beat → clamps to first
	local hit = client:beatAtTime("withGrid", -1)
	assert(hit and hit.index == 1, "negative t clamps to first beat")
end

-- empty beat_grid → returns nil
injectStructure("emptyGrid", {
	asset_id = "emptyGrid",
	duration = 0,
	beat_grid = { times = {}, downbeats = {} },
	sections = {},
	phrases = {},
})
do
	local hit, err = client:beatAtTime("emptyGrid", 0)
	assert(hit == nil and err == nil, "empty grid returns nil, nil")
end

-- missing beat_grid entirely
injectStructure("noGrid", {
	asset_id = "noGrid",
	duration = 0,
	sections = {},
	phrases = {},
})
do
	local hit, err = client:beatAtTime("noGrid", 0)
	assert(hit == nil and err == nil, "missing beat_grid returns nil, nil")
end
