--!strict
-- Minimal HttpService stand-in for Lune-based unit tests. Records every
-- RequestAsync call and lets specs configure responses. JSONEncode/Decode
-- delegate to @lune/serde for real round-tripping.

local serde = require("@lune/serde")

export type Recorded = {
	url: string,
	method: string,
	headers: { [string]: any }?,
	body: any,
}

export type Response = {
	Success: boolean,
	StatusCode: number,
	StatusMessage: string?,
	Headers: { [string]: string }?,
	Body: string,
}

local MockHttp = {}
MockHttp.__index = MockHttp

export type MockHttp = typeof(setmetatable(
	{} :: {
		requests: { Recorded },
		responses: { Response | (request: Recorded) -> Response },
		error: string?,
	},
	MockHttp
))

local function urlEncodeChar(c: string): string
	return string.format("%%%02X", string.byte(c))
end

function MockHttp.JSONEncode(_self: MockHttp, value: any): string
	return serde.encode("json", value)
end

function MockHttp.JSONDecode(_self: MockHttp, source: string): any
	return serde.decode("json", source)
end

function MockHttp.UrlEncode(_self: MockHttp, value: string): string
	return (value:gsub("[^%w%-_.~]", urlEncodeChar))
end

function MockHttp.RequestAsync(self: MockHttp, opts: any): Response
	local recorded: Recorded = {
		url = opts.Url,
		method = opts.Method or "GET",
		headers = opts.Headers,
		body = opts.Body,
	}
	table.insert(self.requests, recorded)

	if self.error then
		error(self.error)
	end

	local response = table.remove(self.responses, 1)
	if response == nil then
		return {
			Success = true,
			StatusCode = 200,
			StatusMessage = "OK",
			Headers = {},
			Body = "{}",
		}
	end
	if type(response) == "function" then
		return response(recorded)
	end
	return response
end

function MockHttp.queueResponse(self: MockHttp, response: Response | (request: Recorded) -> Response)
	table.insert(self.responses, response)
end

function MockHttp.queueError(self: MockHttp, message: string)
	self.error = message
end

function MockHttp.reset(self: MockHttp)
	self.requests = {}
	self.responses = {}
	self.error = nil
end

local function new(): MockHttp
	return setmetatable({
		requests = {},
		responses = {},
		error = nil,
	}, MockHttp)
end

return {
	new = new,
}
