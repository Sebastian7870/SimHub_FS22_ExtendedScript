--
-- Utilities by Sebastian7870
-- author: Sebastian7870
-- date: 28.05.2024
-- 
-- V1.0.0.0
--


S7870_Tools = {}
S7870_Tools.modName = "Unknown ModName (S7870_Tools)"
S7870_Tools.Debug = true


-- Init
function S7870_Tools:init(modName)
    S7870_Tools.modName = modName
end


-- local functions
local function PrintMessage(message)
    print(string.format("%s: %s", S7870_Tools.modName, message))
end


-- global functions
function LogMessage(message)
	if message ~= nil then
		PrintMessage(message)
	end
end


function LogDebugMessage(message)
	if S7870_Tools.Debug then
		if message ~= nil then
			PrintMessage(message)
		end
	end
end