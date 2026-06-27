-- Local client script that plays meme sounds when panel or answer prompts are triggered.
local SoundService = game:GetService("SoundService")

-- Generated folders that contain the synced meme panels and Sound instances.
local panelsFolder = workspace:WaitForChild("MemeTestPanels")
local soundsFolder = SoundService:WaitForChild("MemeSounds")

-- Connection tracking prevents duplicate prompt listeners as objects replicate in.
local connectedPrompts = {}
local watchedButtons = {}

-- Rewinds the selected sound and plays it locally.
local function playMemeSound(soundName)
	if not soundName then
		return
	end
	
	for _, sound in soundsFolder:GetChildren() do
		sound:Stop()
	end

	local sound = soundsFolder:FindFirstChild(soundName)
	if not sound or sound.SoundId == "" then
		return
	end
	

	sound:Stop()
	sound.TimePosition = 0
	sound:Play()
end

-- Hooks one ProximityPrompt to a callback that resolves which meme sound to play.
local function connectPrompt(prompt, getSoundName)
	if not prompt or connectedPrompts[prompt] then
		return
	end
	connectedPrompts[prompt] = true

	prompt.Triggered:Connect(function()
		playMemeSound(getSoundName())
	end)
end

-- Connects generated meme test panels that carry a PlaySoundPrompt.
local function connectPanel(panel)
	if not panel:IsA("BasePart") then
		return
	end

	local prompt = panel:FindFirstChild("PlaySoundPrompt")
	if not prompt then
		return
	end

	connectPrompt(prompt, function()
		return prompt:GetAttribute("MemeSoundName")
			or panel:GetAttribute("MemeSoundName")
	end)
end

-- Connects quiz button prompts and reads the correct meme sound from their attributes.
local function connectButton(button)
	if not button:IsA("Model") or not button.Name:match("^Button%d+$") then
		return
	end

	if not watchedButtons[button] then
		watchedButtons[button] = true
		button.ChildAdded:Connect(function()
			task.defer(function()
				connectButton(button)
			end)
		end)
	end

	local press = button:FindFirstChild("Press")
	if not press then
		return
	end

	local prompt = press:FindFirstChildWhichIsA("ProximityPrompt")
	if not prompt then
		return
	end

	connectPrompt(prompt, function()
		return prompt:GetAttribute("CorrectMemeSoundName")
			or press:GetAttribute("CorrectMemeSoundName")
			or button:GetAttribute("CorrectMemeSoundName")
	end)
end

-- Initial pass over objects that already exist when the client script starts.
for _, panel in ipairs(panelsFolder:GetChildren()) do
	connectPanel(panel)
end

for _, child in ipairs(workspace:GetChildren()) do
	connectButton(child)
end

-- Watch for new panels and buttons that replicate after the initial pass.
panelsFolder.ChildAdded:Connect(connectPanel)
workspace.ChildAdded:Connect(connectButton)

-- Catch prompts that appear under existing button models after their parent arrived.
workspace.DescendantAdded:Connect(function(descendant)
	if not descendant:IsA("ProximityPrompt") then
		return
	end

	local press = descendant.Parent
	local button = press and press.Parent
	if press and press.Name == "Press" and button then
		connectButton(button)
	end
end)

-- Short retry window for late-replicating button children during spawn.
task.spawn(function()
	for _ = 1, 5 do
		task.wait(1)
		for _, child in ipairs(workspace:GetChildren()) do
			connectButton(child)
		end
	end
end)
