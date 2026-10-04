-- Local Studio launch helper only: starts an ordinary solo play session. No test hooks, teleports or rewards.
local RunService = game:GetService("RunService")
assert(RunService:IsStudio())
if not RunService:IsEdit() then
	while true do
		task.wait(5)
	end
end
print("BLACKOUTBAY_PRIVATE_PLAY_OPENING")
game:GetService("StudioTestService"):ExecutePlayModeAsync({ privatePlay = true })
print("BLACKOUTBAY_PRIVATE_PLAY_STOPPED")
