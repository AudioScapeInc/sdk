--!strict
-- Lune test runner. Discovers `*.spec.luau` under `tests/`, runs each, reports
-- totals, exits non-zero on any failure. Integration coverage lives separately
-- under tests/openCloud/ (real Roblox engine via Open Cloud Luau Execution).

local fs = require("@lune/fs")
local process = require("@lune/process")

local function findSpecs(dir: string, out: { string }): { string }
	for _, entry in ipairs(fs.readDir(dir)) do
		local path = dir .. "/" .. entry
		if fs.isDir(path) then
			findSpecs(path, out)
		elseif path:match("%.spec%.luau$") then
			table.insert(out, path)
		end
	end
	return out
end

local specs = findSpecs("tests", {})
table.sort(specs)

local pass, fail = 0, 0
type Failure = { spec: string, err: string }
local failures: { Failure } = {}

for _, specPath in ipairs(specs) do
	-- Lune's require is relative to the requiring file. tests/run.luau lives
	-- in tests/, so we strip that prefix.
	local rel = "./" .. specPath:gsub("^tests/", ""):gsub("%.luau$", "")
	local ok, err = pcall(require, rel)
	if ok then
		pass += 1
		print(string.format("✓ %s", specPath))
	else
		fail += 1
		table.insert(failures, { spec = specPath, err = tostring(err) })
		print(string.format("✗ %s", specPath))
	end
end

print(string.format("\n%d passed, %d failed", pass, fail))

if fail > 0 then
	for _, f in ipairs(failures) do
		print(string.format("\n--- %s ---\n%s", f.spec, f.err))
	end
	process.exit(1)
end
