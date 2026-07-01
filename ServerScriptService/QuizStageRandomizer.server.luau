-- Server script that fills each quiz stage with one correct meme and two decoys.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

-- Reuse the shared ReplicatedStorage sync so NewGenMemes stays the source of truth.
local MemePanelSync = require(ReplicatedStorage:WaitForChild("MemePanelSync"))

-- Workspace naming conventions used to find stages, buttons, panels, and decals.
local MEME_POOL_FOLDER_NAME = "MemeTestPanels"
local STAGE_NAME_PATTERN = "^Frame(%d+)$"
local BUTTON_NAME_PATTERN = "Button%d"
local PANEL_NAME_PATTERN = "BlackPanel%d"
local MEME_DECAL_NAME = "MemeDecal"
local LEADERSTATS_NAME = "leaderstats"
local STAGE_STAT_NAME = "Stage"
local STARTING_STAGE = 1
local STAGE_SPAWNS_FOLDER_NAME = "StageSpawns"
local STAGE_SPAWN_NAME_PATTERN = "StageSpawn%d"
local STAGE_SPAWN_SIZE = Vector3.new(6, 1, 6)
local STAGE_SPAWN_X_OFFSET_FROM_BUTTON = 12
local CHARACTER_SPAWN_HEIGHT_OFFSET = 4
--local DECAL_ROTATIONS = { 0, 90, 180, 270 }

local rng = Random.new(os.time() + math.floor(os.clock() * 1000000))
local killbrickConnections = {}
local stageSpawns = {}
local playerConnections = {}

local function getOrCreateStageStat(player)
	local leaderstats = player:FindFirstChild(LEADERSTATS_NAME)
	if not leaderstats then
		leaderstats = Instance.new("Folder")
		leaderstats.Name = LEADERSTATS_NAME
		leaderstats.Parent = player
	end

	local stageStat = leaderstats:FindFirstChild(STAGE_STAT_NAME)
	if not stageStat then
		stageStat = Instance.new("IntValue")
		stageStat.Name = STAGE_STAT_NAME
		stageStat.Value = STARTING_STAGE
		stageStat.Parent = leaderstats
	end

	return stageStat
end

local function getStageSpawn(stageNumber)
	return stageSpawns[stageNumber]
end

local function updatePlayerRespawnLocation(player)
	local stageStat = getOrCreateStageStat(player)
	local stageSpawn = getStageSpawn(stageStat.Value)

	if stageSpawn and stageSpawn:IsA("SpawnLocation") then
		player.RespawnLocation = stageSpawn
	else
		player.RespawnLocation = nil
	end
end

local function spawnCharacterAtPlayerStage(player, character)
	updatePlayerRespawnLocation(player)

	local stageStat = getOrCreateStageStat(player)
	local stageSpawn = getStageSpawn(stageStat.Value)
	if not stageSpawn then
		return
	end

	local rootPart = character:WaitForChild("HumanoidRootPart", 5)
	if not rootPart then
		return
	end

	character:PivotTo(stageSpawn.CFrame + Vector3.new(0, CHARACTER_SPAWN_HEIGHT_OFFSET, 0))
end

local function setupPlayerStats(player)
	local stageStat = getOrCreateStageStat(player)
	updatePlayerRespawnLocation(player)

	if not playerConnections[player] then
		playerConnections[player] = {
			stageStat:GetPropertyChangedSignal("Value"):Connect(function()
				updatePlayerRespawnLocation(player)
			end),

			player.CharacterAdded:Connect(function(character)
				task.defer(spawnCharacterAtPlayerStage, player, character)
			end),
		}
	end

	if player.Character then
		task.defer(spawnCharacterAtPlayerStage, player, player.Character)
	end
end

local function cleanupPlayerConnections(player)
	local connections = playerConnections[player]
	if not connections then
		return
	end

	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end
	playerConnections[player] = nil
end

-- Copies a simple array so shuffling does not mutate the original source list.
local function copyArray(array)
	local copy = {}
	for index, value in ipairs(array) do
		copy[index] = value
	end
	return copy
end

-- Returns a shuffled copy of an array using the script's seeded Random object.
local function shuffle(array)
	local shuffled = copyArray(array)
	for index = #shuffled, 2, -1 do
		local swapIndex = rng:NextInteger(1, index)
		shuffled[index], shuffled[swapIndex] = shuffled[swapIndex], shuffled[index]
	end
	return shuffled
end

local function getMemeKey(meme)
	return meme.index or meme.sourcePanelName
end

local function createMemeDrawBag(memePool)
	local remainingMemes = {}

	local function refill(excludedKeys)
		local refillCandidates = {}
		for _, meme in ipairs(memePool) do
			if not excludedKeys or not excludedKeys[getMemeKey(meme)] then
				table.insert(refillCandidates, meme)
			end
		end

		if #refillCandidates == 0 then
			refillCandidates = copyArray(memePool)
		end

		remainingMemes = shuffle(refillCandidates)
	end

	local function draw(excludedKeys)
		if #remainingMemes == 0 then
			refill(excludedKeys)
		end

		for index = #remainingMemes, 1, -1 do
			local meme = remainingMemes[index]
			if not excludedKeys or not excludedKeys[getMemeKey(meme)] then
				table.remove(remainingMemes, index)
				return meme
			end
		end

		refill(excludedKeys)
		return table.remove(remainingMemes)
	end

	refill()

	return {
		draw = draw,
	}
end

local function drawStageMemes(memeDrawBag)
	local stageMemes = {}
	local selectedKeys = {}

	for _ = 1, 3 do
		local meme = memeDrawBag.draw(selectedKeys)
		table.insert(stageMemes, meme)
		selectedKeys[getMemeKey(meme)] = true
	end

	return stageMemes
end

-- Refreshes generated meme panels/sounds from ReplicatedStorage.NewGenMemes before randomizing.
local function syncMemePoolFromCatalog()
	local syncedCount = MemePanelSync.sync()
	print(string.format("QuizStageRandomizer synced %d meme panels from NewGenMemes.", syncedCount))
end

-- Reads the generated meme panels and turns their decals/attributes into quiz options.
local function getMemePool()
	local memePoolFolder = Workspace:WaitForChild(MEME_POOL_FOLDER_NAME)
	local memes = {}

	for _, panel in ipairs(memePoolFolder:GetChildren()) do
		if panel:IsA("BasePart") then
			local decal = panel:FindFirstChild(MEME_DECAL_NAME)
			if decal and decal:IsA("Decal") and decal.Texture ~= "" then
				table.insert(memes, {
					decal = decal,
					index = panel:GetAttribute("MemeIndex"),
					name = panel:GetAttribute("MemeName") or panel.Name,
					soundName = panel:GetAttribute("MemeSoundName"),
					sourcePanelName = panel.Name,
				})
			end
		end
	end

	table.sort(memes, function(left, right)
		local leftIndex = left.index or math.huge
		local rightIndex = right.index or math.huge
		if leftIndex == rightIndex then
			return left.sourcePanelName < right.sourcePanelName
		end
		return leftIndex < rightIndex
	end)

	assert(#memes >= 3, "QuizStageRandomizer needs at least 3 meme panels in Workspace.MemeTestPanels")
	return memes
end

-- Finds the three answer display panels inside a stage model.
local function getStagePanels(stage)
	local panels = {}

	for optionNumber = 1, 3 do
		local panel = stage:FindFirstChild(string.format(PANEL_NAME_PATTERN, optionNumber))
		if not panel or not panel:IsA("BasePart") then
			return nil
		end

		table.insert(panels, {
			part = panel,
			optionNumber = optionNumber,
		})
	end

	return panels
end

-- Discovers valid Frame# stage models and keeps them ordered by stage number.
local function getStages()
	local stages = {}

	for _, child in ipairs(Workspace:GetChildren()) do
		local stageNumber = tonumber(child.Name:match(STAGE_NAME_PATTERN))
		if stageNumber and child:IsA("Model") then
			local panels = getStagePanels(child)
			if panels then
				table.insert(stages, {
					model = child,
					number = stageNumber,
					panels = panels,
				})
			else
				warn(string.format("%s was skipped because it does not have BlackPanel1, BlackPanel2, and BlackPanel3", child.Name))
			end
		end
	end

	table.sort(stages, function(left, right)
		return left.number < right.number
	end)

	return stages
end

local function getOrCreateStageSpawnsFolder()
	local folder = Workspace:FindFirstChild(STAGE_SPAWNS_FOLDER_NAME)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = STAGE_SPAWNS_FOLDER_NAME
		folder.Parent = Workspace
	end

	return folder
end

local function findStageSpawn(stage, spawnsFolder)
	local spawnName = string.format(STAGE_SPAWN_NAME_PATTERN, stage.number)
	local existingSpawn = spawnsFolder:FindFirstChild(spawnName)
	if existingSpawn and existingSpawn:IsA("BasePart") then
		return existingSpawn
	end

	existingSpawn = stage.model:FindFirstChild(spawnName, true)
	if existingSpawn and existingSpawn:IsA("BasePart") then
		return existingSpawn
	end

	existingSpawn = Workspace:FindFirstChild(spawnName)
	if existingSpawn and existingSpawn:IsA("BasePart") then
		return existingSpawn
	end

	return nil
end

local function getButtonForStage(stageNumber)
	return Workspace:FindFirstChild(string.format(BUTTON_NAME_PATTERN, stageNumber))
end

local function getButtonCFrame(button)
	if button:IsA("BasePart") then
		return button.CFrame
	end

	local press = button:FindFirstChild("Press", true)
	if press and press:IsA("BasePart") then
		return press.CFrame
	end

	if button:IsA("Model") then
		return button:GetPivot()
	end

	return nil
end

local function raycastStageSpawnHeight(position, ignoredInstances)
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = ignoredInstances

	local rayOrigin = position + Vector3.new(0, 30, 0)
	local rayResult = Workspace:Raycast(rayOrigin, Vector3.new(0, -80, 0), raycastParams)
	if rayResult then
		return rayResult.Position.Y + (STAGE_SPAWN_SIZE.Y / 2)
	end

	return position.Y
end

local function getStageSpawnCFrame(stage, spawnsFolder)
	local button = getButtonForStage(stage.number)
	if not button then
		warn(string.format("Stage %d does not have %s, so no spawn point was created.", stage.number, string.format(BUTTON_NAME_PATTERN, stage.number)))
		return nil
	end

	local buttonCFrame = getButtonCFrame(button)
	if not buttonCFrame then
		warn(string.format("%s does not have a usable BasePart or pivot for spawn placement.", button.Name))
		return nil
	end

	local buttonPosition = buttonCFrame.Position
	local spawnPosition = buttonPosition + Vector3.new(STAGE_SPAWN_X_OFFSET_FROM_BUTTON, 0, 0)
	local ignoredInstances = { button, spawnsFolder }
	spawnPosition = Vector3.new(
		spawnPosition.X,
		raycastStageSpawnHeight(spawnPosition, ignoredInstances),
		spawnPosition.Z
	)

	return CFrame.lookAt(spawnPosition, Vector3.new(buttonPosition.X, spawnPosition.Y, buttonPosition.Z))
end

local function configureStageSpawn(stage, spawnsFolder)
	local stageSpawn = findStageSpawn(stage, spawnsFolder)
	local spawnCFrame = getStageSpawnCFrame(stage, spawnsFolder)
	if not spawnCFrame then
		return nil
	end

	if not stageSpawn then
		stageSpawn = Instance.new("SpawnLocation")
		stageSpawn.Name = string.format(STAGE_SPAWN_NAME_PATTERN, stage.number)
		stageSpawn.Anchored = true
		stageSpawn.Enabled = true
		stageSpawn.Neutral = true
		stageSpawn.AllowTeamChangeOnTouch = false
		stageSpawn.Duration = 0
		stageSpawn.Parent = spawnsFolder
	end

	stageSpawn.CanCollide = false
	stageSpawn.Size = STAGE_SPAWN_SIZE
	stageSpawn.Transparency = 1
	stageSpawn.CFrame = spawnCFrame
	stageSpawn:SetAttribute("QuizStageNumber", stage.number)
	stageSpawns[stage.number] = stageSpawn
	return stageSpawn
end

local function configureStageSpawns(stages)
	local spawnsFolder = getOrCreateStageSpawnsFolder()
	for _, stage in ipairs(stages) do
		configureStageSpawn(stage, spawnsFolder)
	end
end

-- Removes old decals before a new meme image is applied to an answer panel.
local function clearPanelDecals(panel)
	for _, child in ipairs(panel:GetChildren()) do
		if child:IsA("Decal") then
			child:Destroy()
		end
	end
end

local function getHumanoidFromHit(hit)
	local character = hit and hit:FindFirstAncestorWhichIsA("Model")
	if not character then
		return nil
	end

	return character:FindFirstChildWhichIsA("Humanoid")
end

local function getPlayerFromHit(hit)
	local character = hit and hit:FindFirstAncestorWhichIsA("Model")
	if not character then
		return nil
	end

	return Players:GetPlayerFromCharacter(character)
end

local function advancePlayerStageFromPanel(player, panel)
	local stageNumber = panel:GetAttribute("QuizStageNumber")
	if typeof(stageNumber) ~= "number" then
		return
	end

	local stageStat = getOrCreateStageStat(player)
	if stageStat.Value == stageNumber then
		stageStat.Value += 1
		updatePlayerRespawnLocation(player)
	end
end

local function configurePanelCollisionAndHazard(panel, isCorrect)
	panel.CanCollide = false
	panel.CanTouch = true
	panel:SetAttribute("IsKillbrick", not isCorrect)

	if killbrickConnections[panel] then
		return
	end

	killbrickConnections[panel] = panel.Touched:Connect(function(hit)
		if panel:GetAttribute("IsKillbrick") ~= true then
			local player = getPlayerFromHit(hit)
			if player then
				advancePlayerStageFromPanel(player, panel)
			end
			return
		end

		local humanoid = getHumanoidFromHit(hit)
		if humanoid and humanoid.Health > 0 then
			humanoid.Health = 0
		end
	end)
end

-- Stores quiz metadata on panels, decals, buttons, and prompts for other scripts.
local function setMemeAttributes(instance, meme, isCorrect, stageNumber, optionNumber)
	instance:SetAttribute("QuizStageNumber", stageNumber)
	instance:SetAttribute("QuizOptionNumber", optionNumber)
	instance:SetAttribute("MemeName", meme.name)
	instance:SetAttribute("MemeIndex", meme.index)
	instance:SetAttribute("MemeSoundName", meme.soundName)
	instance:SetAttribute("SourceMemePanelName", meme.sourcePanelName)
	instance:SetAttribute("IsCorrectMeme", isCorrect)
end

-- Clones one meme decal onto an answer panel and labels it as correct or decoy.
local function applyMemeToPanel(panelInfo, meme, isCorrect, stageNumber)
	local panel = panelInfo.part
	clearPanelDecals(panel)
	configurePanelCollisionAndHazard(panel, isCorrect)

	local decal = meme.decal:Clone()

	decal.Name = MEME_DECAL_NAME
	decal.Parent = panel

	setMemeAttributes(panel, meme, isCorrect, stageNumber, panelInfo.optionNumber)
	setMemeAttributes(decal, meme, isCorrect, stageNumber, panelInfo.optionNumber)
end

-- Writes the correct answer details onto the stage and its matching button model.
local function setStageAttributes(stage, correctMeme, correctPanelInfo)
	stage.model:SetAttribute("QuizStageNumber", stage.number)
	stage.model:SetAttribute("CorrectMemeName", correctMeme.name)
	stage.model:SetAttribute("CorrectMemeIndex", correctMeme.index)
	stage.model:SetAttribute("CorrectMemeSoundName", correctMeme.soundName)
	stage.model:SetAttribute("CorrectPanelName", correctPanelInfo.part.Name)
	stage.model:SetAttribute("CorrectOptionNumber", correctPanelInfo.optionNumber)
	stage.model:SetAttribute("CorrectSourceMemePanelName", correctMeme.sourcePanelName)

	local button = Workspace:FindFirstChild(string.format(BUTTON_NAME_PATTERN, stage.number))
	if not button then
		return
	end

	button:SetAttribute("QuizStageNumber", stage.number)
	button:SetAttribute("CorrectMemeName", correctMeme.name)
	button:SetAttribute("CorrectMemeIndex", correctMeme.index)
	button:SetAttribute("CorrectMemeSoundName", correctMeme.soundName)
	button:SetAttribute("CorrectPanelName", correctPanelInfo.part.Name)
	button:SetAttribute("CorrectOptionNumber", correctPanelInfo.optionNumber)
	button:SetAttribute("CorrectSourceMemePanelName", correctMeme.sourcePanelName)

	local press = button:FindFirstChild("Press")
	if press then
		press:SetAttribute("QuizStageNumber", stage.number)
		press:SetAttribute("CorrectMemeName", correctMeme.name)
		press:SetAttribute("CorrectMemeIndex", correctMeme.index)
		press:SetAttribute("CorrectMemeSoundName", correctMeme.soundName)
		press:SetAttribute("CorrectPanelName", correctPanelInfo.part.Name)
		press:SetAttribute("CorrectOptionNumber", correctPanelInfo.optionNumber)
		press:SetAttribute("CorrectSourceMemePanelName", correctMeme.sourcePanelName)
	end
end

-- Picks three memes for a stage, shuffles their panel positions, and records the answer.
local function configureStage(stage, memeDrawBag)
	local stageMemes = drawStageMemes(memeDrawBag)
	local correctMeme = stageMemes[1]
	local shuffledPanels = shuffle(stage.panels)
	local correctPanelInfo = nil

	for index, panelInfo in ipairs(shuffledPanels) do
		local meme = stageMemes[index]
		local isCorrect = meme == correctMeme
		if isCorrect then
			correctPanelInfo = panelInfo
		end

		applyMemeToPanel(panelInfo, meme, isCorrect, stage.number)
	end

	setStageAttributes(stage, correctMeme, correctPanelInfo)
end

-- Build the source meme list, randomize every discovered stage, and log the result.
Players.PlayerAdded:Connect(setupPlayerStats)
Players.PlayerRemoving:Connect(cleanupPlayerConnections)

syncMemePoolFromCatalog()

local memePool = getMemePool()
local stages = getStages()
local memeDrawBag = createMemeDrawBag(memePool)

for _, stage in ipairs(stages) do
	configureStage(stage, memeDrawBag)
end

configureStageSpawns(stages)

for _, player in ipairs(Players:GetPlayers()) do
	setupPlayerStats(player)
end

print(string.format("QuizStageRandomizer configured %d stages with %d memes.", #stages, #memePool))
