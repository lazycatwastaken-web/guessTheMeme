-- Simple local test script that plays a temporary sound from a test part prompt.
local soundService = game:GetService("SoundService")

-- Test references expected to exist in SoundService and Workspace.
local sound = soundService.tempTestSound
local part = game.Workspace:WaitForChild("testPart")
local prompt = part.ProximityPrompt


-- When the prompt is triggered, play the sound only for the local player.
prompt.Triggered:Connect(function()
	soundService:PlayLocalSound(sound)
end)
