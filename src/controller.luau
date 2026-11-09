-- Arsenal Controls: client controller. SlimeUI is supplied by build.py.
-- Default aim activation: Always. Right Shift toggles the window; F8 stops all features.
local VERSION = "1.0.0-beta.1"
local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local Run = game:GetService("RunService")
local me = Players.LocalPlayer
local env = (getgenv and getgenv()) or _G
-- Refuse unsupported games before replacing an existing controller.
if not Run:IsClient() or not me then
	warn("[Arsenal Controls] A local Roblox client is required.")
	return
end
if game.GameId ~= 111958650 then
	warn("[Arsenal Controls] This release supports the Arsenal universe only.")
	return
end
local deadline = os.clock() + 15
local function modulesPresent()
	local client = game:GetService("ReplicatedFirst"):FindFirstChild("Client")
	local utility = client and client:FindFirstChild("Utility")
	local modules = game:GetService("ReplicatedStorage"):FindFirstChild("Modules")
	return utility
		and utility:FindFirstChild("Input")
		and utility:FindFirstChild("State")
		and modules
		and modules:FindFirstChild("GeneralFunctions")
end
while not modulesPresent() and os.clock() < deadline do
	task.wait(0.1)
end
if not modulesPresent() then
	warn("[Arsenal Controls] Supported client modules did not become available. Rejoin and retry.")
	return
end
if type(env.ArsenalControls) == "table" and type(env.ArsenalControls.Destroy) == "function" then
	pcall(env.ArsenalControls.Destroy)
end
-- Upgrade compatibility for earlier development builds.
if type(env.SimpleAimPanel) == "function" then
	pcall(env.SimpleAimPanel)
end
env.SimpleAimPanelAPI = nil

local DEFAULTS = table.freeze({
	enabled = false,
	team = true,
	lock = true,
	esp = false,
	wall = true,
	autofire = false,
	autoplay = false,
	norecoil = false,
	infammo = false,
	silent = false,
	fov = 150,
	smooth = 0.15,
	aimAlways = true,
	fly = false,
	noclip = false,
	speedEnabled = false,
	speed = 36,
	flySpeed = 60,
})
local settings = table.clone(DEFAULTS)

local statusState = { phase = "idle", target = "none" }
local avoidedTargets = {}
local playerList = Players:GetPlayers()
local records = {}
local function record(player)
	local char = player.Character
	local r = records[player]
	local now = os.clock()
	if not r or r.character ~= char or now >= r.expires then
		local stats = player:FindFirstChild("NRPBS")
		local state = player:FindFirstChild("Status")
		r = {
			character = char,
			expires = now + 0.25,
			health = stats and stats:FindFirstChild("Health"),
			active = state and state:FindFirstChild("Alive"),
			humanoid = char and char:FindFirstChildOfClass("Humanoid"),
			head = char and char:FindFirstChild("Head"),
			root = char and char:FindFirstChild("HumanoidRootPart"),
			shield = char and char:FindFirstChildOfClass("ForceField"),
		}
		records[player] = r
	end
	return r
end
local function livingPlayer(player)
	local r = record(player)
	return not (r.active and not r.active.Value)
		and not (r.health and r.health.Value <= 0)
		and r.humanoid ~= nil
		and r.humanoid.Parent ~= nil
		and r.humanoid.Health > 0
end
local connections, alive, holding, target = {}, true, false, nil
local function connect(signal, callback)
	local c = signal:Connect(callback)
	table.insert(connections, c)
	return c
end
connect(Players.PlayerAdded, function(p)
	if not table.find(playerList, p) then
		table.insert(playerList, p)
	end
end)
connect(Players.PlayerRemoving, function(p)
	records[p] = nil
	local i = table.find(playerList, p)
	if i then
		table.remove(playerList, i)
	end
end)
local function make(class, props)
	local instance = Instance.new(class)
	for key, value in pairs(props) do
		instance[key] = value
	end
	return instance
end

if type(env.SimpleFlightCleanup) == "function" then
	pcall(env.SimpleFlightCleanup)
end
local aimRotation, aimPart
local cleanup, stopAll, stopMotion, resetSettings, fail
local gameInput, gameState, adapterError
local silentHead, castModule, castOriginal, castWrapper
local syncCast = function() end
local cachedSelection, nextSelection = nil, 0
local stopAutomation = function() end
local toggleRefresh, controls = {}, {}

local Window = SlimeUI:CreateWindow({
	Title = "Arsenal Controls",
	Subtitle = "Public beta " .. VERSION,
	Theme = "Dark",
	ReducedMotion = true,
	Accent = Color3.fromRGB(100, 235, 170),
	Size = Vector2.new(820, 550),
	Logo = "",
	Loader = false,
	Folder = "ArsenalControls",
	SettingsTab = false,
	ToggleKey = Enum.KeyCode.RightShift,
	Blur = false,
})
local gui, panel = Window.Gui, Window.Gui:FindFirstChild("Window")
local libraryDestroy = Window.Destroy
Window.Destroy = function(self)
	if cleanup then
		cleanup()
	else
		libraryDestroy(self)
	end
end
local function text(parent, value, position, size)
	return make("TextLabel", {
		Parent = parent,
		Text = value,
		Position = position,
		Size = size,
		BackgroundTransparency = 1,
		TextColor3 = Color3.fromRGB(230, 234, 245),
		Font = Enum.Font.Gotham,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
end
local setSetting
setSetting = function(key, value)
	if not alive then
		return
	end
	local needsInput = key == "autofire" or key == "autoplay" or key == "norecoil" or key == "infammo"
	if value and ((needsInput and not gameState) or (key == "silent" and not castWrapper)) then
		if controls[key] then
			controls[key]:Set(false, true)
		end
		Window:Notify("Feature unavailable", "The weapon adapter is not ready. Check status or rejoin.", 4)
		return
	end
	settings[key] = value
	if key == "silent" or key == "enabled" then
		nextSelection = 0
	end
	if key == "aimAlways" and controls.activation then
		controls.activation:Set(value and "Always" or "Hold right mouse", true)
	end
	if key == "enabled" and value then
		settings.silent = false
	end
	if key == "silent" and value then
		settings.enabled = false
	end
	if key == "fly" and value then
		settings.autoplay = false
	end
	if key == "autoplay" and value then
		settings.fly = false
	end
	stopAutomation()
	syncCast()
	for _, refresh in pairs(toggleRefresh) do
		refresh()
	end
	if stopMotion and not (settings.fly or settings.noclip or settings.speedEnabled) then
		stopMotion()
	end
end
local function toggle(tab, name, key, description)
	local control = tab:Toggle({
		Name = name,
		Description = description,
		Default = settings[key],
		Callback = function(on)
			if alive then
				setSetting(key, on)
			end
		end,
	})
	controls[key] = control
	toggleRefresh[key] = function()
		if not Window.Destroyed and control.Value ~= settings[key] then
			control:Set(settings[key], true)
		end
	end
end
local function slider(tab, name, key, low, high, increment, suffix)
	controls[key] = tab:Slider({
		Name = name,
		Min = low,
		Max = high,
		Default = settings[key],
		Increment = increment,
		Suffix = suffix or "",
		Callback = function(value)
			if alive then
				settings[key] = value
			end
		end,
	})
end
local aimTab = Window:Tab("Aim", "crosshair", "Camera aiming and target selection")
aimTab:Section("Camera aim")
toggle(aimTab, "Camera aim", "enabled", "Turns the camera toward a valid enemy.")
controls.activation = aimTab:Dropdown({
	Name = "Activation",
	Options = { "Always", "Hold right mouse" },
	Default = "Always",
	Callback = function(value)
		settings.aimAlways = value == "Always"
		stopAutomation()
	end,
})
toggle(aimTab, "Target lock", "lock", "Keeps a valid visible target selected.")
toggle(aimTab, "Team check", "team")
toggle(aimTab, "Wall check", "wall")
slider(aimTab, "FOV radius", "fov", 30, 500, 1, " px")
slider(aimTab, "Smoothing time", "smooth", 0, 0.5, 0.01, " s")
aimTab:Section("Silent aim")
toggle(aimTab, "Silent aim (beta)", "silent", "Experimental. Enabling this switches camera aim off.")
aimTab:Paragraph(
	"Controls",
	"Right Shift: show/hide. F8: stop all features. Camera aim and silent aim are separate modes."
)
local combat = Window:Tab("Combat", "swords", "Normal firing and automated movement")
toggle(combat, "Auto fire", "autofire", "Fires on alignment while camera aim or silent aim is active.")
toggle(combat, "Autoplay", "autoplay", "Navigates, aims and fires. Disables flight.")
toggle(combat, "No recoil", "norecoil")
toggle(combat, "Client ammo refill (beta)", "infammo", "Experimental client state; server acceptance is unverified.")
combat:Button("Stop all features (F8)", function()
	if stopAll then
		stopAll()
	end
end)
local visual = Window:Tab("Visual", "eye", "Highlights and status")
toggle(visual, "Player ESP", "esp")
local statusLabel = visual:Label("Connecting weapon input...")
local lastStatus
local status = setmetatable({}, {
	__newindex = function(_, key, value)
		if key == "Text" and value ~= lastStatus and not Window.Destroyed then
			lastStatus = value
			statusLabel:Set(value)
		end
	end,
})
local movement = Window:Tab("Movement", "move", "Local movement controls")
toggle(movement, "Fly", "fly", "WASD to move, Space up, Left Ctrl down. Disables autoplay.")
slider(movement, "Fly speed", "flySpeed", 10, 150, 1, " studs/s")
toggle(movement, "Noclip", "noclip", "Disables your character's part collisions while enabled.")
toggle(movement, "Speed override", "speedEnabled")
slider(movement, "Walk speed", "speed", 16, 120, 1, " studs/s")
movement:Button("Reset movement", function()
	settings.fly, settings.noclip, settings.speedEnabled = false, false, false
	if stopMotion then
		stopMotion()
	end
	for _, key in ipairs({ "fly", "noclip", "speedEnabled" }) do
		toggleRefresh[key]()
	end
end)
movement:Paragraph("Movement", "Flight and noclip do not prevent damage. The server may correct movement changes.")
local about = Window:Tab("About", "info", "Version, credits and reset")
about:Paragraph(
	"Arsenal Controls " .. VERSION,
	"Community public beta. Tested on Madium for Windows. Other executors are unverified."
)
about:Paragraph(
	"Credits",
	"Interface: SlimeUI by SlimexDev, MIT license. This build includes a pinned, locally modified copy."
)
about:Paragraph(
	"Beta features",
	"Silent aim is limited to hitscan. Client ammo refill does not guarantee unlimited server-accepted shots. Autoplay paths are map-dependent."
)
about:Button("Reset settings", function()
	if resetSettings then
		resetSettings()
	end
end)
about:Button("Unload", function()
	if cleanup then
		cleanup()
	end
end)
local accent = Color3.fromRGB(100, 235, 170)
local circle = make("Frame", {
	Parent = gui,
	AnchorPoint = Vector2.new(0.5, 0.5),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	Visible = false,
})
make("UICorner", { Parent = circle, CornerRadius = UDim.new(1, 0) })
make("UIStroke", { Parent = circle, Color = accent, Thickness = 1, Transparency = 0.25 })
local focused = true
connect(UIS.InputBegan, function(input)
	if input.KeyCode == Enum.KeyCode.F8 and stopAll then
		stopAll()
	end
	if input.UserInputType == Enum.UserInputType.MouseButton2 and not UIS:GetFocusedTextBox() then
		holding = true
	end
end)
connect(UIS.InputEnded, function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton2 then
		holding = false
		stopAutomation()
	end
end)
connect(UIS.WindowFocusReleased, function()
	focused = false
	holding = false
	stopAutomation()
end)
connect(UIS.WindowFocused, function()
	focused = true
end)
-- Local highlights and labels, refreshed independently from aiming.
local espFolder = make("Folder", { Name = "ArsenalControlsESP", Parent = workspace })
local espEntries = {}
local function sameTeam(player)
	return not me.Neutral and not player.Neutral and me.Team ~= nil and player.Team == me.Team
end
local function removeESP(player)
	local entry = espEntries[player]
	if entry then
		entry.highlight:Destroy()
		entry.billboard:Destroy()
		espEntries[player] = nil
	end
end
connect(Players.PlayerRemoving, removeESP)
local espElapsed = 0
local function updateESP(dt)
	espElapsed = espElapsed + dt
	if espElapsed < 0.25 then
		return
	end
	espElapsed = 0
	if not settings.esp then
		if next(espEntries) then
			for player in pairs(espEntries) do
				removeESP(player)
			end
		end
		return
	end
	for _, player in ipairs(playerList) do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local show = settings.esp
			and player ~= me
			and humanoid
			and livingPlayer(player)
			and root
			and root:IsA("BasePart")
			and not (settings.team and sameTeam(player))
		if not show then
			removeESP(player)
		else
			local entry = espEntries[player]
			if entry and entry.character ~= character then
				removeESP(player)
				entry = nil
			end
			if not entry then
				local highlight = make("Highlight", {
					Parent = espFolder,
					Adornee = character,
					DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
					FillTransparency = 1,
					OutlineTransparency = 0.1,
				})
				local billboard = make("BillboardGui", {
					Parent = espFolder,
					Adornee = root,
					AlwaysOnTop = true,
					Size = UDim2.fromOffset(200, 44),
					StudsOffset = Vector3.new(0, 3.5, 0),
				})
				local caption = text(billboard, "", UDim2.fromOffset(0, 0), UDim2.fromScale(1, 1))
				caption.TextXAlignment = Enum.TextXAlignment.Center
				caption.TextStrokeTransparency = 0.25
				caption.TextSize = 13
				entry = { character = character, highlight = highlight, billboard = billboard, caption = caption }
				espEntries[player] = entry
			end
			local color = sameTeam(player) and Color3.fromRGB(100, 200, 255) or Color3.fromRGB(255, 100, 110)
			if entry.color ~= color then
				entry.color = color
				entry.highlight.FillColor = color
				entry.highlight.OutlineColor = color
				entry.caption.TextColor3 = color
			end
			local camera = workspace.CurrentCamera
			local distance = camera and (camera.CFrame.Position - root.Position).Magnitude or 0
			local stats = player:FindFirstChild("NRPBS")
			local hp = stats and stats:FindFirstChild("Health")
			local caption = string.format(
				"%s (@%s)\n%d studs | %d HP",
				player.DisplayName,
				player.Name,
				distance,
				hp and hp.Value or humanoid.Health
			)
			if entry.caption.Text ~= caption then
				entry.caption.Text = caption
			end
		end
	end
end
connect(Run.Heartbeat, function(dt)
	if not alive then
		return
	end
	local ok, err = pcall(updateESP, dt)
	if not ok and fail then
		fail("ESP", err)
	end
end)

local recoilValue, recoilOriginal
local function restoreRecoil()
	if recoilValue and recoilValue.Parent and recoilValue.Value == 0 then
		recoilValue.Value = recoilOriginal
	end
	recoilValue, recoilOriginal = nil, nil
end
local function updateWeaponOptions()
	local gun = gameState and rawget(gameState, "gun")
	local value = gun and gun:FindFirstChild("RecoilControl")
	if not settings.norecoil or value ~= recoilValue then
		restoreRecoil()
	end
	if settings.norecoil and value and (value:IsA("NumberValue") or value:IsA("IntValue")) then
		if not recoilValue then
			recoilValue, recoilOriginal = value, value.Value
		end
		value.Value = 0
	end
	if
		settings.infammo
		and gameState
		and gun
		and livingPlayer(me)
		and rawget(gameState, "deployed")
		and not rawget(gameState, "reloading")
		and not gun:FindFirstChild("Melee")
	then
		local capacity = gun:FindFirstChild("Ammo")
		if capacity and type(capacity.Value) == "number" and capacity.Value > 0 then
			local count = math.clamp(capacity.Value, 1, 999)
			local key = rawget(gameState, "equipped") == "secondary" and "ammo2count" or "ammocount"
			rawset(gameState, key, count)
		end
	end
end
-- Use the live game's already loaded modules, never the decompiled copies.
task.spawn(function()
	local ok, result = pcall(function()
		local client = game:GetService("ReplicatedFirst"):FindFirstChild("Client")
		assert(client and client:FindFirstChild("Utility"), "Arsenal client not found")
		local utility = client.Utility
		local input = require(utility.Input)
		local state = require(utility.State)
		assert(type(input.Trigger) == "function" and input.Binds.Mouse1, "Weapon input changed")
		return { input, state }
	end)
	if not alive then
		return
	end
	if ok then
		gameInput, gameState = result[1], result[2]
	else
		adapterError = tostring(result)
		warn("[Arsenal Controls] " .. adapterError)
	end
end)

local function validEnemy(player)
	if player == me or (settings.team and sameTeam(player)) or not livingPlayer(player) then
		return
	end
	local r = record(player)
	if not r.head or not r.head.Parent or not r.root or not r.root.Parent or r.shield then
		return
	end
	return r.head, r.root
end
local sightParams = RaycastParams.new()
sightParams.FilterType = Enum.RaycastFilterType.Exclude
local sightMemo = {}
local filterCharacter, filterCamera, filterExpiry
local function clearSight(camera, head)
	local now = os.clock()
	local origin, position = camera.CFrame.Position, head.Position
	local cached = sightMemo[head]
	if
		cached
		and now < cached.expires
		and (origin - cached.origin).Magnitude < 2
		and (position - cached.position).Magnitude < 2
	then
		return cached.clear
	end
	if filterCharacter ~= me.Character or filterCamera ~= camera or not filterExpiry or now >= filterExpiry then
		filterCharacter, filterCamera, filterExpiry = me.Character, camera, now + 0.5
		local exclude = filterCharacter and { filterCharacter, camera } or { camera }
		local map = workspace:FindFirstChild("Map")
		if map and map:FindFirstChild("Clips") then
			table.insert(exclude, map.Clips)
		end
		sightParams.FilterDescendantsInstances = exclude
		-- Bound memory to the current scene; entries contain character parts.
		table.clear(sightMemo)
	end

	local hit = workspace:Raycast(origin, position - origin, sightParams)
	local clear = not hit or hit.Instance:IsDescendantOf(head.Parent)
	sightMemo[head] = { expires = now + 0.065, origin = origin, position = position, clear = clear }
	return clear
end
local function eligible(player, camera)
	local head = validEnemy(player)
	if not head then
		return
	end
	local point, onScreen = camera:WorldToViewportPoint(head.Position)
	if not onScreen or point.Z <= 0 then
		return
	end
	local distance = (Vector2.new(point.X, point.Y) - camera.ViewportSize / 2).Magnitude
	if distance > settings.fov or (settings.wall and not clearSight(camera, head)) then
		return
	end
	return head, distance
end

local nextSilentScan = 0
local function refreshSilentTarget(camera, paused)
	if paused or not settings.silent then
		silentHead = nil
		return
	end
	if os.clock() < nextSilentScan then
		return
	end
	nextSilentScan = os.clock() + 0.065
	if settings.lock and silentHead and silentHead.Parent then
		local player = Players:GetPlayerFromCharacter(silentHead.Parent)
		if player and eligible(player, camera) and clearSight(camera, silentHead) then
			return
		end
	end
	silentHead = nil
	local closest = math.huge
	for _, player in ipairs(playerList) do
		local head, distance = eligible(player, camera)
		if head and distance < closest and clearSight(camera, head) then
			silentHead, closest = head, distance
		end
	end
end

-- Replace only the shared exported cast entry, leaving the global raycast APIs
-- untouched. Restrict redirection to initial hitscan rays from the firing module.
task.spawn(function()
	local ok, err = pcall(function()
		local module = require(game:GetService("ReplicatedStorage").Modules.GeneralFunctions)
		assert(type(module.cast) == "function", "Hitscan cast unavailable")
		if not alive then
			return
		end
		castModule, castOriginal = module, module.cast
		castWrapper = function(ray, ...)
			if not alive or not settings.silent then
				return castOriginal(ray, ...)
			end
			local camera = workspace.CurrentCamera
			local gun = gameState and rawget(gameState, "gun")
			local head = silentHead
			if
				alive
				and settings.silent
				and camera
				and head
				and head.Parent
				and gun
				and not gun:FindFirstChild("Projectile")
				and not gun:FindFirstChild("Melee")
				and typeof(ray) == "Ray"
				and (ray.Origin - camera.CFrame.Position).Magnitude < 8
			then
				local source = debug.info(2, "s")
				if source and source:find("Client.Game.BulletsAndProjectiles", 1, true) then
					local player = Players:GetPlayerFromCharacter(head.Parent)
					local valid = player and eligible(player, camera)
					local delta = head.Position - ray.Origin
					if
						valid
						and clearSight(camera, head)
						and delta.Magnitude > 0
						and delta.Magnitude <= ray.Direction.Magnitude
					then
						ray = Ray.new(ray.Origin, delta.Unit * ray.Direction.Magnitude)
					end
				end
			end
			return castOriginal(ray, ...)
		end
		if settings.silent then
			module.cast = castWrapper
		end
	end)
	if not ok and alive then
		statusState.silentError = tostring(err)
		warn("[Arsenal Controls] Silent aim unavailable: " .. tostring(err))
	end
end)

syncCast = function()
	if not castModule then
		return
	end
	if settings.silent and castModule.cast == castOriginal then
		castModule.cast = castWrapper
	elseif not settings.silent and castModule.cast == castWrapper then
		castModule.cast = castOriginal
	end
end
local ownsFire, nextTrigger, nextReload = false, 0, 0
local function releaseFire()
	if ownsFire and gameInput then
		-- Leave a physically held mouse button under the player's control.
		if not UIS:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then
			pcall(gameInput.Trigger, gameInput.Binds.Mouse1, false)
		end
	end
	ownsFire = false
end
local movementOwned, waypoints, waypointIndex = false, {}, 1
local navTarget, navPosition, navVersion, navPending, nextPath = nil, nil, 0, false, 0
local progressPosition, progressTime, stuckCount, noPathCount = nil, 0, 0, 0
local navigationLook
local pathBudget = 0
local function stopMovement()
	if not movementOwned and navTarget == nil and #waypoints == 0 then
		return
	end
	if movementOwned then
		local h = me.Character and me.Character:FindFirstChildOfClass("Humanoid")
		if h then
			h:Move(Vector3.zero, false)
		end
	end
	movementOwned = false
	navVersion = navVersion + 1
	navTarget, navPosition, waypoints, waypointIndex = nil, nil, {}, 1
	navigationLook, progressPosition, stuckCount, noPathCount = nil, nil, 0, 0
end
stopAutomation = function()
	cachedSelection, nextSelection = nil, 0
	releaseFire()
	stopMovement()
	target = nil
	aimRotation, aimPart = nil, nil
	statusState.target = "none"
end
connect(me.CharacterRemoving, function()
	stopAutomation()
	if stopMotion then
		stopMotion()
	end
end)
local function driveTo(player, enemyRoot, h, root, visible)
	local distance = (enemyRoot.Position - root.Position).Magnitude
	local gun = gameState and rawget(gameState, "gun")
	local stopDistance = gun and gun:FindFirstChild("Melee") and 4 or 22
	if distance <= stopDistance and visible then
		if movementOwned then
			h:Move(Vector3.zero, false)
		end
		movementOwned = false
		statusState.phase = "engaging"
		return
	end
	if navTarget ~= player then
		stopMovement()
		navTarget = player
		nextPath = 0
	end
	if not progressPosition then
		progressPosition, progressTime = root.Position, os.clock()
	end
	if os.clock() - progressTime > 1.8 then
		if movementOwned and (root.Position - progressPosition).Magnitude < 2 then
			stuckCount = stuckCount + 1
			h.Jump = true
			nextPath = 0
			if stuckCount >= 3 then
				avoidedTargets[player] = os.clock() + 15
				target = nil
				stopMovement()
				return
			end
		else
			stuckCount = 0
		end
		progressPosition, progressTime = root.Position, os.clock()
	end
	if not navPending and os.clock() >= nextPath and os.clock() >= pathBudget then
		pathBudget = os.clock() + 0.9
		navPending = true

		nextPath = os.clock() + 1.2
		local version, destination = navVersion, enemyRoot.Position
		task.spawn(function()
			local workerOK, workerError = pcall(function()
				local path = game:GetService("PathfindingService")
					:CreatePath({ AgentRadius = 2, AgentHeight = 5, AgentCanJump = true, WaypointSpacing = 5 })
				local ok = pcall(path.ComputeAsync, path, root.Position, destination)
				if not alive or navVersion ~= version or not root.Parent then
					return
				end
				local fallback
				if not ok or path.Status ~= Enum.PathStatus.Success then
					-- Some map sections have disconnected navigation meshes. Try a
					-- short, collision-checked detour instead of waiting in place.
					local params = RaycastParams.new()
					params.FilterType = Enum.RaycastFilterType.Exclude
					local exclude = { workspace.CurrentCamera }
					for _, p in ipairs(playerList) do
						if p.Character then
							table.insert(exclude, p.Character)
						end
					end
					params.FilterDescendantsInstances = exclude
					params.RespectCanCollide = true
					local delta = Vector3.new(destination.X - root.Position.X, 0, destination.Z - root.Position.Z)
					local best = math.huge
					if delta.Magnitude > 1 then
						local basis = CFrame.lookAt(Vector3.zero, delta.Unit)
						for _, angle in ipairs({ 0, 45, -45, 90, -90, 135, -135 }) do
							local direction = (basis * CFrame.Angles(0, math.rad(angle), 0)).LookVector
							local point = root.Position + direction * 12
							local obstacle = workspace:Raycast(root.Position, direction * 14, params)
							local floor =
								workspace:Raycast(point + Vector3.new(0, 3, 0), Vector3.new(0, -10, 0), params)
							if
								not obstacle
								and floor
								and floor.Normal.Y > 0.5
								and math.abs(floor.Position.Y - (root.Position.Y - 3)) < 5
							then
								local score = (point - destination).Magnitude + math.abs(angle) * 0.02
								if score < best then
									best, fallback = score, point
								end
							end
						end
					end
				end
				if alive and settings.autoplay and navVersion == version then
					navPosition = destination
					statusState.pathStatus = ok and tostring(path.Status) or "compute error"
					if ok and path.Status == Enum.PathStatus.Success then
						waypoints, waypointIndex = path:GetWaypoints(), 2
						noPathCount = 0
					elseif fallback then
						waypoints, waypointIndex = { { Position = fallback, Action = Enum.PathWaypointAction.Walk } }, 1
						noPathCount = 0
					else
						waypoints, waypointIndex = {}, 1
						noPathCount = noPathCount + 1
						if noPathCount >= 2 and not visible then
							avoidedTargets[player] = os.clock() + 15
						end
					end
				end
			end)
			navPending = false
			if not workerOK and alive and navVersion == version and fail then
				fail("Navigation", workerError)
			end
		end)
	end
	local waypoint = waypoints[waypointIndex]
	if waypoint and (root.Position - waypoint.Position).Magnitude < 4 then
		waypointIndex = waypointIndex + 1
		waypoint = waypoints[waypointIndex]
	end
	-- Only walk directly when the target is visible; otherwise wait for a path.
	local destination = waypoint and waypoint.Position or (visible and enemyRoot.Position)
	navigationLook = destination
	statusState.phase = destination and "navigating" or "finding path"
	local delta = destination and Vector3.new(destination.X - root.Position.X, 0, destination.Z - root.Position.Z)
	h:Move(delta and delta.Magnitude > 1 and delta.Unit or Vector3.zero, false)
	movementOwned = true
	if waypoint and waypoint.Action == Enum.PathWaypointAction.Jump then
		h.Jump = true
	end
	if not waypoint then
		navPosition = nil
	end
end
local function updateFire(head, camera, requested)
	statusState.fireReason = "idle"
	if not requested or not gameInput or not gameState then
		releaseFire()
		return
	end
	if not head then
		statusState.fireReason = "no target"
		releaseFire()
		return
	end
	if not clearSight(camera, head) then
		statusState.fireReason = "blocked"
		releaseFire()
		return
	end
	local gun = rawget(gameState, "gun")
	if not gun or rawget(gameState, "died") or rawget(gameState, "roundend") or rawget(gameState, "equipping") then
		releaseFire()
		return
	end
	local direction = head.Position - camera.CFrame.Position
	local silentShot = settings.silent
		and castWrapper
		and silentHead == head
		and not gun:FindFirstChild("Projectile")
		and not gun:FindFirstChild("Melee")
	if
		direction.Magnitude <= 0
		or (not silentShot and camera.CFrame.LookVector:Dot(direction.Unit) < math.cos(math.rad(2)))
	then
		statusState.fireReason = "aligning"
		releaseFire()
		return
	end
	if rawget(gameState, "reloading") then
		statusState.fireReason = "reloading"
		releaseFire()
		return
	end
	local equipped = rawget(gameState, "equipped")
	local ammo = rawget(gameState, equipped == "secondary" and "ammo2count" or "ammocount")
	if not gun:FindFirstChild("Melee") and type(ammo) == "number" and ammo <= 0 then
		statusState.fireReason = "empty"
		releaseFire()
		if os.clock() >= nextReload then
			nextReload = os.clock() + 1.5
			pcall(gameInput.Trigger, gameInput.Binds.Reload, true)
		end
		return
	end
	if UIS:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then
		return
	end
	if os.clock() >= nextTrigger then
		nextTrigger = os.clock() + 0.08
		local ok, err = pcall(gameInput.Trigger, gameInput.Binds.Mouse1, true)
		if ok then
			ownsFire = true

			statusState.fireReason = "triggered"
		else
			adapterError = tostring(err)
			releaseFire()
		end
	end
end

local flightRoot, flightHumanoid, flightRotate, flightAttachment, flightVelocity, flightOrientation
local speedHumanoid, savedSpeed
local collisions = {}
local function stopFlight()
	if flightVelocity then
		flightVelocity:Destroy()
	end
	if flightOrientation then
		flightOrientation:Destroy()
	end
	if flightAttachment then
		flightAttachment:Destroy()
	end
	if flightHumanoid and flightHumanoid.Parent then
		flightHumanoid.AutoRotate = flightRotate
	end
	if flightRoot and flightRoot.Parent then
		flightRoot.AssemblyLinearVelocity = Vector3.zero
	end
	flightRoot, flightHumanoid, flightAttachment, flightVelocity, flightOrientation = nil, nil, nil, nil, nil
end
local function restoreCollisions()
	for part, value in pairs(collisions) do
		if part.Parent and part.CanCollide == false then
			part.CanCollide = value
		end
	end
	table.clear(collisions)
end
local function restoreSpeed()
	if speedHumanoid and speedHumanoid.Parent then
		speedHumanoid.WalkSpeed = savedSpeed
	end
	speedHumanoid, savedSpeed = nil, nil
end
stopMotion = function()
	-- Restore each independent override even if another restoration fails.
	pcall(stopFlight)
	pcall(restoreCollisions)
	pcall(restoreSpeed)
end
local motionCharacter, motionParts, motionExpiry = nil, {}, 0
local function updateMotion()
	local char = me.Character
	local h = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not h or not root or not livingPlayer(me) then
		stopMotion()
		return
	end
	if settings.speedEnabled then
		if speedHumanoid ~= h then
			restoreSpeed()
			speedHumanoid, savedSpeed = h, h.WalkSpeed
		end
		if h.WalkSpeed ~= settings.speed then
			h.WalkSpeed = settings.speed
		end
	else
		restoreSpeed()
	end
	if settings.noclip then
		if motionCharacter ~= char or os.clock() >= motionExpiry then
			motionCharacter, motionExpiry = char, os.clock() + 0.25
			table.clear(motionParts)
			for _, part in ipairs(char:GetDescendants()) do
				if part:IsA("BasePart") then
					table.insert(motionParts, part)
				end
			end
		end
		for _, part in ipairs(motionParts) do
			if part.Parent then
				if collisions[part] == nil then
					collisions[part] = part.CanCollide
				end
				if part.CanCollide then
					part.CanCollide = false
				end
			end
		end
	else
		restoreCollisions()
	end
	if not settings.fly or root.Anchored or h.Sit then
		stopFlight()
		return
	end
	if flightRoot ~= root then
		stopFlight()
		flightRoot, flightHumanoid, flightRotate = root, h, h.AutoRotate
		flightAttachment = make("Attachment", { Name = "ArsenalControlsFlightAttachment", Parent = root })
		flightVelocity = make("LinearVelocity", {
			Name = "ArsenalControlsFlightVelocity",
			Attachment0 = flightAttachment,
			RelativeTo = Enum.ActuatorRelativeTo.World,
			MaxForce = math.huge,
			VectorVelocity = Vector3.zero,
			Parent = root,
		})
		flightOrientation = make("AlignOrientation", {
			Name = "ArsenalControlsFlightOrientation",
			Mode = Enum.OrientationAlignmentMode.OneAttachment,
			Attachment0 = flightAttachment,
			MaxTorque = math.huge,
			Responsiveness = 25,
			CFrame = root.CFrame.Rotation,
			Parent = root,
		})
		h.AutoRotate = false
	end
	local camera = workspace.CurrentCamera
	local move = Vector3.zero
	if focused and not UIS:GetFocusedTextBox() and camera then
		if UIS:IsKeyDown(Enum.KeyCode.W) then
			move += camera.CFrame.LookVector
		end
		if UIS:IsKeyDown(Enum.KeyCode.S) then
			move -= camera.CFrame.LookVector
		end
		if UIS:IsKeyDown(Enum.KeyCode.D) then
			move += camera.CFrame.RightVector
		end
		if UIS:IsKeyDown(Enum.KeyCode.A) then
			move -= camera.CFrame.RightVector
		end
		if UIS:IsKeyDown(Enum.KeyCode.Space) then
			move += Vector3.yAxis
		end
		if UIS:IsKeyDown(Enum.KeyCode.LeftControl) then
			move -= Vector3.yAxis
		end
		local forward = Vector3.new(camera.CFrame.LookVector.X, 0, camera.CFrame.LookVector.Z)
		if forward.Magnitude > 0.001 then
			flightOrientation.CFrame = CFrame.lookAt(Vector3.zero, forward.Unit)
		end
	end
	flightVelocity.VectorVelocity = move.Magnitude > 0 and move.Unit * settings.flySpeed or Vector3.zero
end
-- Apply movement once before physics.
connect(Run.PreSimulation, function()
	if alive and (settings.fly or settings.noclip or settings.speedEnabled) then
		local ok, err = pcall(updateMotion)
		if not ok then
			settings.fly, settings.noclip, settings.speedEnabled = false, false, false
			stopMotion()
			for _, key in ipairs({ "fly", "noclip", "speedEnabled" }) do
				toggleRefresh[key]()
			end
			if fail then
				fail("Movement", err)
			end
		end
	end
end)
local function applyAim(camera, position, dt, part)
	local delta = position - camera.CFrame.Position
	if delta.Magnitude < 0.01 then
		return
	end
	if aimPart ~= part or not aimRotation then
		aimRotation, aimPart = camera.CFrame.Rotation, part
	end
	local desired = CFrame.lookAt(Vector3.zero, delta.Unit)
	local alpha = settings.smooth <= 0 and 1 or 1 - math.exp(-dt / settings.smooth)
	aimRotation = aimRotation:Lerp(desired, alpha)
	camera.CFrame = CFrame.new(camera.CFrame.Position) * aimRotation
end

local renderName = "ArsenalControlsCamera_" .. tostring(me.UserId)
cleanup = function()
	if not alive then
		return
	end
	alive = false
	pcall(stopAutomation)
	silentHead = nil
	pcall(restoreRecoil)
	pcall(function()
		if castModule and castModule.cast == castWrapper then
			castModule.cast = castOriginal
		end
	end)
	Run:UnbindFromRenderStep(renderName)
	for _, connection in ipairs(connections) do
		pcall(connection.Disconnect, connection)
	end
	table.clear(connections)
	pcall(function()
		espFolder:Destroy()
	end)
	table.clear(espEntries)
	if stopMotion then
		pcall(stopMotion)
	end
	table.clear(records)
	table.clear(sightMemo)
	table.clear(avoidedTargets)
	pcall(libraryDestroy, Window)
	if type(env.ArsenalControls) == "table" and env.ArsenalControls.Destroy == cleanup then
		env.ArsenalControls = nil
	end
end
Run:UnbindFromRenderStep(renderName)
local nextStatus = 0
local function renderStep(dt)
	if not alive then
		return
	end
	local camera = workspace.CurrentCamera
	if not camera then
		stopAutomation()
		return
	end
	local position = UDim2.fromOffset(camera.ViewportSize.X / 2, camera.ViewportSize.Y / 2)
	if circle.Position ~= position then
		circle.Position = position
	end
	local size = UDim2.fromOffset(settings.fov * 2, settings.fov * 2)
	if circle.Size ~= size then
		circle.Size = size
	end
	circle.Visible = (settings.enabled or settings.silent) and not settings.autoplay
	local h = me.Character and me.Character:FindFirstChildOfClass("Humanoid")
	local root = me.Character and me.Character:FindFirstChild("HumanoidRootPart")
	local aimHeld = settings.aimAlways or holding or UIS:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)
	if
		aimRotation
		and camera.CameraType == Enum.CameraType.Custom
		and livingPlayer(me)
		and ((settings.enabled and aimHeld) or settings.autoplay)
	then
		camera.CFrame = CFrame.new(camera.CFrame.Position) * aimRotation
	end
	local mouse = UIS:GetMouseLocation()
	local overPanel = panel
		and Window.Visible
		and panel.Visible
		and mouse.X >= panel.AbsolutePosition.X
		and mouse.X <= panel.AbsolutePosition.X + panel.AbsoluteSize.X
		and mouse.Y >= panel.AbsolutePosition.Y
		and mouse.Y <= panel.AbsolutePosition.Y + panel.AbsoluteSize.Y
		and UIS.MouseBehavior ~= Enum.MouseBehavior.LockCenter
	local paused = not focused
		or UIS:GetFocusedTextBox()
		or not h
		or not livingPlayer(me)
		or not root
		or camera.CameraType ~= Enum.CameraType.Custom
		or overPanel
		or me:GetAttribute("BossRushDowned")
	if
		gameState
		and (rawget(gameState, "died") or rawget(gameState, "roundend") or rawget(gameState, "deployed") == false)
	then
		paused = true
	end
	statusState.pauseReason = not focused and "unfocused"
		or UIS:GetFocusedTextBox() and "typing"
		or not livingPlayer(me) and "dead"
		or not root and "no character"
		or camera.CameraType ~= Enum.CameraType.Custom and "camera/menu"
		or overPanel and "pointer over UI"
		or gameState and rawget(gameState, "deployed") == false and "not deployed"
		or gameState and rawget(gameState, "roundend") and "round ended"
		or "none"
	if settings.norecoil or settings.infammo or recoilValue then
		updateWeaponOptions()
	end
	refreshSilentTarget(camera, paused)
	if os.clock() >= nextStatus then
		nextStatus = os.clock() + 0.3
		status.Text = adapterError and "Stopped: see console for details"
			or not gameInput and "Connecting weapon input..."
			or paused and ("Paused: " .. statusState.pauseReason)
			or settings.autoplay and ("Autoplay: " .. statusState.phase)
			or settings.enabled and ("Camera aim: " .. (aimHeld and (statusState.target or "searching") or "hold right mouse"))
			or "Weapon input ready"
	end
	statusState.paused = not not paused
	if
		paused
		or (
			not settings.autoplay
			and not (settings.enabled and aimHeld)
			and not (settings.silent and settings.autofire)
		)
	then
		statusState.phase = "idle"
		stopAutomation()
		return
	end
	local head, enemyRoot
	local cached = cachedSelection
	local liveHead = cached and validEnemy(cached.player)
	if cached and liveHead == cached.head and os.clock() < nextSelection and cached.mode == settings.autoplay then
		target, head, enemyRoot = cached.player, cached.head, cached.root
		if settings.autoplay then
			driveTo(target, enemyRoot, h, root, clearSight(camera, head))
		end
	elseif not cached and os.clock() < nextSelection then
		target = nil
	else
		if settings.autoplay then
			-- Combat selection is independent of the navigation goal. Do not keep
			-- chasing an occluded lock while a visible enemy can be engaged.
			local combatPlayer, combatHead, combatRoot
			if settings.lock and target then
				local candidate, r = validEnemy(target)
				if candidate and clearSight(camera, candidate) then
					combatPlayer, combatHead, combatRoot = target, candidate, r
				end
			end
			if not combatHead then
				local closestVisible = math.huge
				for _, player in ipairs(playerList) do
					local candidate, r = validEnemy(player)
					if candidate and clearSight(camera, candidate) then
						local distance = (r.Position - root.Position).Magnitude
						if distance < closestVisible then
							combatPlayer, combatHead, combatRoot, closestVisible = player, candidate, r, distance
						end
					end
				end
			end
			if combatHead then
				target, head, enemyRoot = combatPlayer, combatHead, combatRoot
				statusState.selection = "combat"
			else
				statusState.selection = "navigation"
				if target and avoidedTargets[target] and avoidedTargets[target] > os.clock() then
					target = nil
				end
				if settings.lock and target then
					head, enemyRoot = validEnemy(target)
				end
				if not head then
					target = nil
					local closest = math.huge
					for _, player in ipairs(playerList) do
						local candidate, r = validEnemy(player)
						local distance = r and (r.Position - root.Position).Magnitude
						if candidate and not (avoidedTargets[player] and avoidedTargets[player] > os.clock()) then
							local score = distance + (clearSight(camera, candidate) and 0 or 60)
							if score < closest then
								target, head, enemyRoot, closest = player, candidate, r, score
							end
						end
					end
				end
			end
			if head then
				driveTo(target, enemyRoot, h, root, clearSight(camera, head))
			else
				stopMovement()
			end
		else
			stopMovement()
			if settings.silent and not settings.enabled and silentHead then
				head = silentHead
				target = Players:GetPlayerFromCharacter(head.Parent)
			else
				if settings.lock and target then
					head = eligible(target, camera)
				end
				if not head then
					target = nil
					local closest = math.huge
					for _, player in ipairs(playerList) do
						local candidate, distance = eligible(player, camera)
						if candidate and distance < closest then
							target, head, closest = player, candidate, distance
						end
					end
				end
			end
		end

		cachedSelection = head and { player = target, head = head, root = enemyRoot, mode = settings.autoplay } or nil
		nextSelection = os.clock() + 0.065
	end
	statusState.target = target and target.Name or "none"
	if head then
		-- Autoplay may steer toward enemies beyond the manual FOV to navigate.
		if settings.autoplay and not clearSight(camera, head) then
			if navigationLook then
				local look = Vector3.new(navigationLook.X, camera.CFrame.Position.Y, navigationLook.Z)
				if (look - camera.CFrame.Position).Magnitude > 1 then
					applyAim(camera, look, dt, "navigation")
				end
			end
		elseif (not settings.silent or settings.autoplay) and (not settings.wall or clearSight(camera, head)) then
			applyAim(camera, head.Position, dt, head)
		end
	end
	if not head then
		aimRotation, aimPart = nil, nil
	end
	updateFire(head, camera, settings.autoplay or settings.autofire)
end
Run:BindToRenderStep(renderName, Enum.RenderPriority.Last.Value + 1, function(dt)
	local ok, err = pcall(renderStep, dt)
	if not ok and fail then
		fail("Controller", err)
	end
end)
stopAll = function()
	holding = false
	for _, key in ipairs({
		"enabled",
		"autoplay",
		"autofire",
		"silent",
		"norecoil",
		"infammo",
		"fly",
		"noclip",
		"speedEnabled",
		"esp",
	}) do
		settings[key] = false
		if toggleRefresh[key] then
			toggleRefresh[key]()
		end
	end
	silentHead = nil
	pcall(stopAutomation)
	pcall(restoreRecoil)
	pcall(syncCast)
	pcall(stopMotion)
	for player in pairs(espEntries) do
		pcall(removeESP, player)
	end
	circle.Visible = false
end

resetSettings = function()
	stopAll()
	for key, value in pairs(DEFAULTS) do
		settings[key] = value
		local control = controls[key]
		if control and control.Value ~= value then
			control:Set(value, true)
		end
	end
	controls.activation:Set(settings.aimAlways and "Always" or "Hold right mouse", true)
	adapterError = nil
end
local lastFailure
fail = function(context, err)
	if not alive then
		return
	end
	local message = tostring(context) .. ": " .. tostring(err)
	pcall(stopAll)
	adapterError = message
	if message ~= lastFailure then
		lastFailure = message
		warn("[Arsenal Controls " .. VERSION .. "] " .. message)
		pcall(
			Window.Notify,
			Window,
			"Features stopped",
			"An error occurred. Check the console, reset settings or rejoin.",
			5
		)
	end
end
connect(gui.Destroying, function()
	if alive then
		cleanup()
	end
end)
env.ArsenalControls = { Version = VERSION, Stop = stopAll, Destroy = cleanup }
