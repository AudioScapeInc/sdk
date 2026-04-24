--!strict
-- Open Cloud Luau Execution smoke harness.
--
-- Pipeline:
--   1. `rojo build default.project.json` → .rbxm of the SDK module tree
--   2. POST to create a binary-input slot for this universe (returns uploadUri)
--   3. PUT the .rbxm bytes to uploadUri
--   4. POST to create a luau-execution-session-task with binaryInput = slot path
--   5. Poll until terminal, fetch logs (with retry window for post-shutdown
--      BindToClose callbacks), assert on returned `{ ok, results }` + sentinel
--
-- The AudioScape API key is NOT passed through here — it lives as a
-- Roblox Secret ("AUDIOSCAPE_KEY") on the test place, retrieved by the
-- smoke script via HttpService:GetSecret. The harness only needs the
-- Roblox Open Cloud API key + the test universe/place IDs.
--
-- Run:
--   set -a; source .env.integration; set +a; lune run tests/openCloud/smoke.luau

local fs = require("@lune/fs")
local net = require("@lune/net")
local process = require("@lune/process")
local serde = require("@lune/serde")
local taskLib = require("@lune/task")

local function getEnv(name: string): string
	local v = process.env[name]
	if not v or #v == 0 then
		print(string.format("[smoke] %s not set — source .env.integration first", name))
		process.exit(1)
		error("unreachable", 0)
	end
	return v
end

local roKey = getEnv("ROBLOX_API_KEY")
local universeId = getEnv("ROBLOX_TEST_UNIVERSE_ID")
local placeId = getEnv("ROBLOX_TEST_PLACE_ID")

local base = "https://apis.roblox.com/cloud/v2"
local getHeaders: { [string]: string } = { ["x-api-key"] = roKey }
local postJsonHeaders: { [string]: string } = {
	["x-api-key"] = roKey,
	["Content-Type"] = "application/json",
}
local octetHeaders: { [string]: string } = { ["Content-Type"] = "application/octet-stream" }

local started = os.time()
local function elapsed(): number
	return os.time() - started
end

-- 1. Build the SDK as a .rbxm via Rojo.
print("[smoke] (1/5) rojo build")
local rbxmPath = "/tmp/audioscape-smoke.rbxm"
local buildRes = process.exec("rojo", { "build", "default.project.json", "-o", rbxmPath })
assert(buildRes.ok, "rojo build failed: " .. buildRes.stderr)

local rbxmBytes = fs.readFile(rbxmPath)
print(string.format("[smoke]      built %d bytes", #rbxmBytes))

-- 2. Allocate a binary-input slot. Endpoint requires `size` so the API can
-- pre-sign an upload URL of the right capacity.
print("[smoke] (2/5) create binary-input slot")
local createBinUrl = string.format("%s/universes/%s/luau-execution-session-task-binary-inputs", base, universeId)
local createBinRes = net.request({
	url = createBinUrl,
	method = "POST",
	headers = postJsonHeaders,
	body = serde.encode("json", { size = #rbxmBytes }),
})
assert(
	createBinRes.ok,
	string.format("create binary input failed: HTTP %d %s", createBinRes.statusCode, createBinRes.body)
)
local binBody: any = serde.decode("json", createBinRes.body)
print(string.format("[smoke]      slot path: %s", tostring(binBody.path)))

-- 3. PUT the bytes to the pre-signed URI. No x-api-key here — the URI is
-- already authorized via signing.
print("[smoke] (3/5) upload bytes")
local uploadRes = net.request({
	url = binBody.uploadUri,
	method = "PUT",
	headers = octetHeaders,
	body = rbxmBytes,
})
assert(uploadRes.ok, string.format("upload failed: HTTP %d %s", uploadRes.statusCode, uploadRes.body))

-- 4. Submit the task with the bundled SDK attached as binaryInput.
-- No key substitution — the smoke script retrieves AUDIOSCAPE_KEY from
-- the place's Secret store at runtime via HttpService:GetSecret.
print("[smoke] (4/5) submit task")
local scriptSource = fs.readFile("tests/openCloud/smokeScript.luau")
local createTaskUrl = string.format("%s/universes/%s/places/%s/luau-execution-session-tasks", base, universeId, placeId)
local taskRes = net.request({
	url = createTaskUrl,
	method = "POST",
	headers = postJsonHeaders,
	body = serde.encode("json", {
		script = scriptSource,
		binaryInput = binBody.path,
	}),
})
assert(taskRes.ok, string.format("create task failed: HTTP %d %s", taskRes.statusCode, taskRes.body))
local taskBody: any = serde.decode("json", taskRes.body)
print(string.format("[smoke]      task path: %s", tostring(taskBody.path)))

-- 6. Poll until terminal.
print(string.format("[smoke] (5/5) poll until terminal (started %ds in)", elapsed()))
local pollUrl = base .. "/" .. taskBody.path
local maxWait = 5 * 60
local lastState: string? = nil
local final: any = nil
while true do
	if elapsed() > maxWait then
		print(string.format("[smoke] timed out after %ds", maxWait))
		process.exit(1)
	end
	taskLib.wait(2)
	local pollRes = net.request({
		url = pollUrl,
		method = "GET",
		headers = getHeaders,
	})
	if not pollRes.ok then
		print(string.format("[smoke] poll HTTP %d: %s", pollRes.statusCode, pollRes.body))
		process.exit(1)
	end
	local body: any = serde.decode("json", pollRes.body)
	local state = tostring(body.state)
	if state ~= lastState then
		print(string.format("[smoke]      state=%s (%ds)", state, elapsed()))
		lastState = state
	end
	if state == "COMPLETE" or state == "FAILED" or state == "CANCELLED" then
		final = body
		break
	end
end

-- Fetch server-side print() output for diagnostics. Empirically, logs only
-- capture output emitted while the script is executing — BindToClose
-- callbacks don't fire in Luau Execution sessions, so prints from them
-- never appear.
local logsRes = net.request({
	url = pollUrl .. "/logs",
	method = "GET",
	headers = getHeaders,
})
local result = final.output and final.output.results and final.output.results[1]
if logsRes.ok then
	local logsBody: any = serde.decode("json", logsRes.body)
	local pages = logsBody.luauExecutionSessionTaskLogs or {}
	local hasAnyMessages = false
	for _, page in pages do
		if #(page.messages or {}) > 0 then
			hasAnyMessages = true
			break
		end
	end
	if hasAnyMessages then
		print("\n[smoke] === server logs ===")
		for _, page in pages do
			for _, msg in (page.messages or {}) do
				print("  " .. tostring(msg))
			end
		end
	end
end

print("\n[smoke] === final task ===")
print(string.format("  state: %s", tostring(final.state)))
if final.error then
	print(string.format("  error: %s", serde.encode("json", final.error)))
end

if final.state ~= "COMPLETE" then
	print(string.format("\n[smoke] FAIL after %ds (task state %s)", elapsed(), tostring(final.state)))
	process.exit(1)
end

if not result then
	print("[smoke] FAIL — task COMPLETE but no output result returned")
	process.exit(1)
end

print("\n[smoke] === smoke results ===")
print(serde.encode("json", result, true))

if result.ok then
	print(string.format("\n[smoke] PASS in %ds", elapsed()))
else
	print(string.format("\n[smoke] FAIL in %ds — see results above", elapsed()))
	process.exit(1)
end
