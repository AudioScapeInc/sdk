--!strict
-- Regression for issue #3 — reserved keyword in Section type field.
-- Asserts that `src/init.luau` parses + loads without errors. This is the
-- single check that, had it existed in v0.7.0 CI, would have prevented the
-- bug from shipping for four releases.

local fs = require("@lune/fs")
local luau = require("@lune/luau")

local source = fs.readFile("src/init.luau")
-- luau.compile throws a descriptive error on parse failures, including the
-- reserved-keyword case (`end: number` vs `["end"]: number`).
local bytecode = luau.compile(source)
assert(typeof(bytecode) == "string" and #bytecode > 0, "expected non-empty bytecode")

-- Loading the chunk verifies the bytecode is well-formed (the chunk function
-- itself isn't called — that requires a Roblox env, covered by later specs).
local chunk = luau.load(bytecode)
assert(typeof(chunk) == "function", "expected loaded chunk to be callable")
