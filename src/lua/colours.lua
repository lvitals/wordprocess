--!nonstrict
-- © 2022 David Given.
-- WordProcess is licensed under the MIT open source license. See the COPYING
-- file in this distribution for the full text.

local table_insert = table.insert
local table_remove = table.remove
local string_char = string.char

local function MakeDark()
	-- VS Code Dark Modern palette, shared with vix's dark-modern theme.
	local ink = {0.800, 0.800, 0.800}          -- #cccccc
	local paper = {0.122, 0.122, 0.122}        -- #1f1f1f
	local headerfg = {0.337, 0.612, 0.839}     -- #569cd6
	local headerbg = {0.169, 0.176, 0.180}     -- #2b2d2e
	-- Neutral terminal-style black/grey rather than an RGB accent colour,
	-- so it renders correctly (not as a mismatched blue/cyan) on the
	-- native Linux console and other limited-colour terminals, where it
	-- snaps straight onto the standard ANSI black and light-grey entries.
	local statusbg = {0.000, 0.000, 0.000}     -- #000000 (ANSI black)
	local statusfg = {0.753, 0.753, 0.753}     -- #c0c0c0 (ANSI light grey)

	return {
		Desktop      = {0.094, 0.094, 0.094}, -- #181818
		Paper        = paper,
		MarkerFG     = {0.522, 0.522, 0.522}, -- #858585
		MisspeltFG   = {0.820, 0.412, 0.412}, -- #d16969
		ScrollbarFG  = {0.776, 0.776, 0.776}, -- #c6c6c6
		ScrollbarBG  = {0.094, 0.094, 0.094}, -- #181818
		StatusbarBG  = statusbg,
		StatusbarFG  = statusfg,
		MessageBG    = statusbg,
		MessageFG    = statusfg,
		StyleFG      = {0.522, 0.522, 0.522}, -- #858585
		ControlFG    = ink,
		ControlBG    = {0.094, 0.094, 0.094}, -- #181818
		H1_BG        = headerbg,
		H1_FG        = headerfg,
		H2_BG        = headerbg,
		H2_FG        = headerfg,
		H3_BG        = paper,
		H3_FG        = headerfg,
		H4_BG        = paper,
		H4_FG        = headerfg,
		LN_BG        = paper,
		LN_FG        = ink,
		LB_BG        = paper,
		LB_FG        = ink,
		L_BG         = paper,
		L_FG         = ink,
		PRE_BG       = paper,
		PRE_FG       = ink,
		P_BG		 = paper,
		P_FG         = ink,
		Q_BG         = paper,
		Q_FG         = ink,
		RAW_BG       = paper,
		RAW_FG       = ink,
		V_BG         = paper,
		V_FG         = ink,
	}
end

local function MakeLight()
	local ink = {0, 0, 0}
	local paper = {0.760, 0.760, 0.730}
	local headerfg = {0.14, 0.22, 0.40}
	local headerbg = {0.66, 0.66, 0.66}

	return {
		Desktop      = {0.510, 0.500, 0.470},
		Paper        = paper,
		MarkerFG     = {0.250, 0.250, 0.250},
		MisspeltFG   = {0.700, 0.200, 0.200},
		ScrollbarFG  = {0.200, 0.200, 0.200},
		ScrollbarBG  = {0.850, 0.850, 0.850},
		StatusbarBG  = {0.140, 0.220, 0.400},
		StatusbarFG  = {0.800, 0.700, 0.200},
		MessageBG    = {0.140, 0.220, 0.400},
		MessageFG    = {0.800, 0.700, 0.200},
		StyleFG      = {0.200, 0.200, 0.200},
		ControlFG    = {0.200, 0.200, 0.200},
		ControlBG    = {0.850, 0.850, 0.850},
		H1_BG        = headerbg,
		H1_FG        = headerfg,
		H2_BG        = headerbg,
		H2_FG        = headerfg,
		H3_BG        = paper,
		H3_FG        = ink,
		H4_BG        = paper,
		H4_FG        = ink,
		LN_BG        = paper,
		LN_FG        = ink,
		LB_BG        = paper,
		LB_FG        = ink,
		L_BG         = paper,
		L_FG         = ink,
		PRE_BG       = paper,
		PRE_FG       = ink,
		P_BG         = paper,
		P_FG         = ink,
		Q_BG         = paper,
		Q_FG         = ink,
		RAW_BG       = paper,
		RAW_FG       = ink,
		V_BG         = paper,
		V_FG         = ink,
	}
end

local function MakeClassic()
	local ink = {0.8, 0.8, 0.8}
	local white = {1, 1, 1}
	local black = {0, 0, 0}
	local blue = {0.337, 0.612, 0.839}

	return {
		Desktop      = black,
		Paper        = black,
		MarkerFG     = white,
		MisspeltFG   = {0.820, 0.412, 0.412},
		ScrollbarFG  = {0.776, 0.776, 0.776}, -- #c6c6c6
		ScrollbarBG  = black,
		StatusbarFG  = black,
		StatusbarBG  = white,
		MessageFG    = black,
		MessageBG    = white,
		StyleFG      = {0.500, 0.500, 0.500},
		ControlFG    = white,
		ControlBG    = black,
		H1_BG        = black,
		H1_FG        = blue,
		H2_BG        = black,
		H2_FG        = blue,
		H3_BG        = black,
		H3_FG        = blue,
		H4_BG        = black,
		H4_FG        = blue,
		LN_BG        = black,
		LN_FG        = ink,
		LB_BG        = black,
		LB_FG        = ink,
		L_BG         = black,
		L_FG         = ink,
		PRE_BG       = black,
		PRE_FG       = ink,
		P_BG         = black,
		P_FG         = ink,
		Q_BG         = black,
		Q_FG         = ink,
		RAW_BG       = black,
		RAW_FG       = ink,
		V_BG         = black,
		V_FG         = ink,
	}
end

local Palettes= {
	Dark = MakeDark(),
	Light = MakeLight(),
	Classic = MakeClassic(),
}

-----------------------------------------------------------------------------
-- Gets the list of themes.

function GetThemes()
	local t = {}
	for n, _ in pairs(Palettes) do
		t[#t+1] = n
	end
	return t
end

-----------------------------------------------------------------------------
-- Configures the current theme.

function SetTheme(theme)
	Palette = Palettes[theme] or {}
end

-----------------------------------------------------------------------------
-- Actually sets a style for drawing.

function SetColour(fg, bg)
	if not fg then
		fg = {1.0, 1.0, 1.0}
	end
	assert(fg)

	if not bg then
		bg = {0.0, 0.0, 0.0}
	end
	assert(bg)

	wg.setcolour(fg, bg)
end
