local SoundService = game:GetService("SoundService")

local panelsFolder = workspace:WaitForChild("MemeTestPanels")
local soundsFolder = SoundService:WaitForChild("MemeSounds")

local connectedPrompts = {}
local currentSound = nil

local function connectPanel(panel)
	if not panel:IsA("BasePart") then
		return
	end

	local prompt = panel:FindFirstChild("PlaySoundPrompt")
	if not prompt or connectedPrompts[prompt] then
		return
	end
	connectedPrompts[prompt] = true

	prompt.Triggered:Connect(function()
		local soundName = prompt:GetAttribute("MemeSoundName")
			or panel:GetAttribute("MemeSoundName")
		if not soundName then
			return
		end

		local sound = soundsFolder:FindFirstChild(soundName)
		if not sound or sound.SoundId == "" then
			return
		end

		if currentSound then
			currentSound:Stop()
			currentSound.TimePosition = 0
		end

		sound:Stop()
		sound.TimePosition = 0
		currentSound = sound
		SoundService:PlayLocalSound(sound)
	end)
end

for _, panel in ipairs(panelsFolder:GetChildren()) do
	connectPanel(panel)
end

panelsFolder.ChildAdded:Connect(connectPanel)
