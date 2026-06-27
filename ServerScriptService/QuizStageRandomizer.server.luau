-- Server script that fills each quiz stage with one correct meme and two decoys.
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
--local DECAL_ROTATIONS = { 0, 90, 180, 270 }

local rng = Random.new(os.time() + math.floor(os.clock() * 1000000))

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

-- Removes old decals before a new meme image is applied to an answer panel.
local function clearPanelDecals(panel)
	for _, child in ipairs(panel:GetChildren()) do
		if child:IsA("Decal") then
			child:Destroy()
		end
	end
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
local function configureStage(stage, memePool)
	local selectedMemes = shuffle(memePool)
	local correctMeme = selectedMemes[1]
	local stageMemes = { selectedMemes[1], selectedMemes[2], selectedMemes[3] }
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
syncMemePoolFromCatalog()

local memePool = getMemePool()
local stages = getStages()

for _, stage in ipairs(stages) do
	configureStage(stage, memePool)
end

print(string.format("QuizStageRandomizer configured %d stages with %d memes.", #stages, #memePool))
