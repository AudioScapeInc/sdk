--!strict
-- Unit test for sectionAtTime — covers the post-fix `section["end"]` read
-- (issue #3 regression coverage at the call site).

local mockHttp = require("./_harness/mockHttp")
local loadSdk = require("./_harness/loadSdk").loadSdk

local sdk = loadSdk({ http = mockHttp.new() })
local client = (sdk :: any).new("test-key")

-- Wire up a fixture mirroring the API wire format (note: `end` is the field name).
local function injectStructure(assetId: string, sections: { any }, phrases: { any }?)
	(client :: any)._structureCache[assetId] = {
		asset_id = assetId,
		duration = 60,
		sections = sections,
		phrases = phrases or {},
	}
end

injectStructure("trackA", {
	{ start = 0, ["end"] = 16, label = "intro" },
	{ start = 16, ["end"] = 32, label = "verse" },
	{ start = 32, ["end"] = 48, label = "chorus" },
})

-- exact start boundary → that section
local section, err = client:sectionAtTime("trackA", 0)
assert(section and not err, "expected hit at t=0")
assert(section.label == "intro", "t=0 → intro, got " .. tostring(section.label))

-- mid-section
section = client:sectionAtTime("trackA", 8)
assert(section and section.label == "intro", "t=8 → intro")

-- exact end boundary belongs to the NEXT section (half-open: [start, end))
section = client:sectionAtTime("trackA", 16)
assert(
	section and section.label == "verse",
	"t=16 → verse (start of next), got " .. tostring(section and section.label)
)

-- past last section → nil
section, err = client:sectionAtTime("trackA", 100)
assert(section == nil and err == nil, "t=100 past last section → nil, nil")

-- before any section starts (gap before t=0 doesn't exist here, but verify nil for negative time)
section = client:sectionAtTime("trackA", -1)
assert(section == nil, "negative t before any section → nil")

-- empty sections
injectStructure("trackB", {})
section, err = client:sectionAtTime("trackB", 5)
assert(section == nil and err == nil, "empty sections → nil, nil")

-- phrase level
injectStructure("trackC", {}, {
	{ start = 0, ["end"] = 8, label = "phrase-1" },
	{ start = 8, ["end"] = 16, label = "phrase-2" },
})
section = client:sectionAtTime("trackC", 4, "phrase")
assert(section and section.label == "phrase-1", "phrase-level lookup at t=4")

-- regression — directly verify the section table exposes ["end"] (not nil)
injectStructure("trackD", { { start = 0, ["end"] = 10, label = "only" } })
section = client:sectionAtTime("trackD", 5)
assert(section, "expected section at t=5")
assert(section["end"] == 10, 'section["end"] should be readable post-fix; got ' .. tostring(section["end"]))
assert(section.start == 0, "section.start should be readable")
