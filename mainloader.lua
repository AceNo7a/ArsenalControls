-- Resolve main first, then fetch an immutable script URL to avoid stale raw files.
local repository = "AceNo7a/ArsenalControls"
local http = game:GetService("HttpService")
local ok, reference = pcall(function()
	return http:JSONDecode(
		game:HttpGet("https://api.github.com/repos/" .. repository .. "/git/ref/heads/main?t=" .. tostring(os.time()))
	)
end)
assert(ok, "Arsenal Controls: cannot resolve latest release (network error or GitHub rate limit)")
local commit = type(reference) == "table" and reference.object
local sha = type(commit) == "table" and commit.type == "commit" and commit.sha
assert(type(sha) == "string" and #sha == 40 and sha:match("^%x+$"), "Arsenal Controls: invalid release reference")
local source =
	game:HttpGet("https://raw.githubusercontent.com/" .. repository .. "/" .. sha .. "/dist/ArsenalControls.lua")
local chunk, compileError = loadstring(source, "ArsenalControls@" .. sha)
assert(chunk, "Arsenal Controls: downloaded script could not compile: " .. tostring(compileError))
return chunk()
