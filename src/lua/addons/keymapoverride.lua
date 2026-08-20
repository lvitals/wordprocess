--!nonstrict
-- © 2015 David Given.
-- WordProcess is licensed under the MIT open source license. See the COPYING
-- file in this distribution for the full text.

local keyoverrides = {}

local commanddefaults = {
	COMMAND_H = "ZL", COMMAND_J = "ZD", COMMAND_K = "ZU", COMMAND_L = "ZR",
	COMMAND_B = "ZWL", COMMAND_W = "ZWR",
	COMMAND_LEFTBRACKET = "ZPTAB", COMMAND_RIGHTBRACKET = "ZNTAB",
	COMMAND_A = "ZH", COMMAND_E = "ZE",
	COMMAND_U = "ZPGUP", COMMAND_D = "ZPGDN",
	COMMAND_T = "ZBD", COMMAND_G = "ZED",
	COMMAND_X = "ZDNC", COMMAND_SHIFT_X = "ZDPC",
	COMMAND_SHIFT_D = "ZDPARA", COMMAND_QUESTION = "Hkeys",
}

local navigationdefaults = {
	NAV_H="ZL", NAV_J="ZD", NAV_K="ZU", NAV_L="ZR",
	NAV_B="ZWL", NAV_W="ZWR",
	NAV_LEFTBRACKET="ZPTAB", NAV_RIGHTBRACKET="ZNTAB",
	NAV_A="ZH", NAV_E="ZE", NAV_U="ZPGUP", NAV_D="ZPGDN",
	NAV_T="ZBD", NAV_G="ZED", NAV_X="ZDNC",
	NAV_SHIFT_X="ZDPC", NAV_SHIFT_D="ZDPARA", NAV_QUESTION="Hkeys",
}

for key, binding in pairs(commanddefaults) do
	keyoverrides[key] = binding
end
for key, binding in pairs(navigationdefaults) do
	keyoverrides[key] = binding
end

local directdefaults = {
	AH="Hkeys",
	AN="ZMODE",
	["A^H"]="ZL", ["A^J"]="ZD", ["A^K"]="ZU", ["A^L"]="ZR",
	["A^B"]="ZWL", ["A^W"]="ZWR", ["A^I"]="ZPTAB", ["A^O"]="ZNTAB",
	["A^A"]="ZH", ["A^E"]="ZE", ["A^U"]="ZPGUP", ["A^D"]="ZPGDN",
	["A^T"]="ZBD", ["A^G"]="ZED", ["A^X"]="ZDNC",
	["AS^X"]="ZDPC", ["AS^D"]="ZDPARA",
}
for key, binding in pairs(directdefaults) do
	keyoverrides[key] = binding
end

function OverrideKey(key, binding)
	if not binding then
		error("you tried to map something I don't recognise to "..key)
	end
	keyoverrides[key] = binding
end

function CheckOverrideTable(key)
	return keyoverrides[key]
end

function GetCommandLayerBindings()
	local keys = {"H", "J", "K", "L", "B", "W", "LEFTBRACKET",
		"RIGHTBRACKET", "A", "E", "U", "D", "T", "G", "X",
		"SHIFT_X", "SHIFT_D", "QUESTION"}
	local result = {}
	for _, key in ipairs(keys) do
		result[#result+1] = {key = key, binding = keyoverrides["COMMAND_"..key]}
	end
	return result
end

function GetNavigationModeBindings()
	local keys = {"H", "J", "K", "L", "B", "W", "LEFTBRACKET",
		"RIGHTBRACKET", "A", "E", "U", "D", "T", "G", "X",
		"SHIFT_X", "SHIFT_D", "QUESTION"}
	local result = {}
	for _, key in ipairs(keys) do
		result[#result+1] = {key=key, binding=keyoverrides["NAV_"..key]}
	end
	return result
end
