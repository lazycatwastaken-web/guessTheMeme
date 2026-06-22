local soundService = game:GetService("SoundService")

local sound = soundService.tempTestSound
local part = game.Workspace:WaitForChild("testPart")
local prompt = part.ProximityPrompt


prompt.Triggered:Connect(function()
	soundService:PlayLocalSound(sound)
end)
