-- Standard Tool integration. Games using custom weapons need a separate adapter.
local ToolAdapter = {}

function ToolAdapter.new(player, input, clock)
	clock = clock or os.clock
	local self = {}
	local activeTool, releaseAt = nil, 0
	local nextShot, nextEquip, retryAt = 0, 0, 0

	local function manualInput()
		return input:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
	end

	function self:Release()
		local tool = activeTool
		activeTool, releaseAt = nil, 0
		if tool and tool.Parent and not manualInput() then
			pcall(tool.Deactivate, tool)
		end
	end

	function self:GetTool(autoEquip)
		local character = player.Character
		if not character then
			return nil
		end
		local equipped = character:FindFirstChildOfClass("Tool")
		if equipped then
			return equipped
		end
		local now = clock()
		if not autoEquip or now < nextEquip then
			return nil
		end
		nextEquip = now + 0.5
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		local backpack = player:FindFirstChildOfClass("Backpack")
		local tool = backpack and backpack:FindFirstChildOfClass("Tool")
		if humanoid and humanoid.Health > 0 and tool then
			pcall(humanoid.EquipTool, humanoid, tool)
			if tool.Parent == character then
				return tool
			end
		end
		return nil
	end

	function self:Step(autoEquip, interval, mode)
		local now = clock()
		if manualInput() then
			self:Release()
			return "manual input"
		end
		local tool = self:GetTool(autoEquip)
		if activeTool and (activeTool ~= tool or (mode ~= "Hold" and now >= releaseAt)) then
			self:Release()
		end
		if not tool then
			return "equip a Tool"
		end
		if activeTool == tool then
			return "holding Tool"
		end
		if tool.RequiresHandle and not tool:FindFirstChild("Handle") then
			return "Tool needs a Handle"
		end
		if not tool.Enabled then
			return "Tool cooldown"
		end
		if now < retryAt or now < nextShot then
			return "Tool interval"
		end
		local ok = pcall(tool.Activate, tool)
		if not ok then
			-- A failing custom Tool should not generate a per-frame retry storm.
			retryAt = now + 1
			pcall(tool.Deactivate, tool)
			return "Tool activation failed"
		end
		activeTool = tool
		releaseAt = now + 0.04
		nextShot = now + math.clamp(interval, 0.05, 1)
		return "Tool activated"
	end

	return self
end

return ToolAdapter
