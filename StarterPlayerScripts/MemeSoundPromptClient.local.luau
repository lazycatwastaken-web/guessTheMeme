-- Local client script that plays meme sounds when panel or answer prompts are triggered.
local Players = game:GetService("Players")
local SoundService = game:GetService("SoundService")
local ImageIDs = require(game.ReplicatedStorage:WaitForChild("ScreenGuiPics"))

-- Generated folders that contain the synced meme panels and Sound instances.
local localPlayer = Players.LocalPlayer
local panelsFolder = workspace:WaitForChild("MemeTestPanels")
local soundsFolder = SoundService:WaitForChild("MemeSounds")

-- Connection tracking prevents duplicate prompt listeners as objects replicate in.
local connectedPrompts = {}
local connectedStagePanels = {}
local watchedButtons = {}

local function stopMemeSounds()
	for _, sound in soundsFolder:GetChildren() do
		if sound:IsA("Sound") then
			sound:Stop()
			sound.TimePosition = 0
		end
	end
end

-- Rewinds the selected sound and plays it locally.
local function playMemeSound(soundName)
	if not soundName then
		return
	end
	
	stopMemeSounds()

	local sound = soundsFolder:FindFirstChild(soundName)
	if not sound or sound.SoundId == "" then
		return
	end
	

	sound:Play()
end

local function hitBelongsToLocalCharacter(hit)
	local character = localPlayer.Character
	return character and hit and hit:IsDescendantOf(character)
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

local function connectStagePanel(panel)
	if not panel:IsA("BasePart") or not panel.Name:match("^BlackPanel%d+$") then
		return
	end

	local stage = panel.Parent
	if not stage or not stage:IsA("Model") or not stage.Name:match("^Frame%d+$") then
		return
	end

	if connectedStagePanels[panel] then
		return
	end
	connectedStagePanels[panel] = true

	panel.Touched:Connect(function(hit)
		if hitBelongsToLocalCharacter(hit) then
			stopMemeSounds()
		end
		print("Connect Stage Panel function triggered")
		--Displays random image on screen
		local images = {}
		for _, image in ImageIDs do
			table.insert(images, image.id)
		end
		local randomImage = images[math.random(1, #images)]
		local screenGui = localPlayer:WaitForChild("PlayerGui"):WaitForChild("ScreenGui")
		local imageLabel = screenGui:WaitForChild("Jumpscare")
		imageLabel.Image = "rbxassetid://" .. randomImage
		imageLabel.Visible = true
		task.delay(2, function()
			imageLabel.Visible = false
		end)
	end)
end

local function connectStagePanelsIn(instance)
	if instance:IsA("BasePart") then
		connectStagePanel(instance)
		return
	end

	for _, descendant in ipairs(instance:GetDescendants()) do
		connectStagePanel(descendant)
	end
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
	connectStagePanelsIn(child)
end

-- Watch for new panels and buttons that replicate after the initial pass.
panelsFolder.ChildAdded:Connect(connectPanel)
workspace.ChildAdded:Connect(function(child)
	connectButton(child)
	connectStagePanelsIn(child)
end)

-- Catch prompts that appear under existing button models after their parent arrived.
workspace.DescendantAdded:Connect(function(descendant)
	connectStagePanel(descendant)

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
			connectStagePanelsIn(child)
		end
	end
end)
