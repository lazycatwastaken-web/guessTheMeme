-- Server startup script that runs the shared panel/sound sync once.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Load the sync module from ReplicatedStorage so this script stays tiny.
local MemePanelSync = require(ReplicatedStorage:WaitForChild("MemePanelSync"))

-- Build or refresh all generated meme panels, then report how many were handled.
local syncedCount = MemePanelSync.sync()
print(string.format("MemePanelAutoSync synced %d meme panels.", syncedCount))
