--!nonstrict
-- © 2026 The WordProcess contributors.
-- WordProcess is licensed under the MIT open source license. See the COPYING
-- file in this distribution for the full text.

-- Pure geometry calculation for a classic textual (WordStar-style) vertical
-- scrollbar: an up arrow, a track, a movable thumb and a down arrow, all
-- sharing a single fixed column. Kept independent of any document, screen
-- or frontend state so it's cheap to unit test and safe to share between
-- every frontend, which all draw the thumb/track themselves using their
-- normal character-grid primitives.
--
-- total          -- total number of navigable units in the document (e.g.
--                   wrapped lines). May be 0 (empty document).
-- first_visible  -- 1-based index of the first visible unit.
-- visible        -- number of units actually shown in the viewport.
-- height         -- total rows available for the whole scrollbar column,
--                   including the two arrow rows.
--
-- Returns a table with:
--   track_height -- rows available for the track, i.e. height - 2 (>= 0)
--   thumb_start  -- 0-based row within the track where the thumb begins
--   thumb_size   -- number of rows the thumb occupies
--   full         -- true if the whole document is visible (thumb fills
--                   the whole track)
--
-- Invariant: thumb_start + thumb_size <= track_height, always.

function ComputeScrollbarGeometry(total, first_visible, visible, height)
	total = math.max(total or 0, 0)
	visible = math.max(visible or 0, 0)
	first_visible = first_visible or 1

	local track_height = math.max((height or 0) - 2, 0)

	if (track_height <= 0) or (total <= 0) or (visible <= 0) or (visible >= total) then
		return {
			track_height = track_height,
			thumb_start = 0,
			thumb_size = track_height,
			full = true,
		}
	end

	-- Thumb size is proportional to how much of the document is visible,
	-- with a floor of one row so it never disappears.
	local thumb_size = math.floor((visible / total) * track_height)
	if thumb_size < 1 then
		thumb_size = 1
	elseif thumb_size > track_height then
		thumb_size = track_height
	end

	-- Thumb position is proportional to how far through the document the
	-- viewport currently is, clamped so it can never run off either end
	-- of the track.
	local max_first = math.max(total - visible, 1)
	local scrolled = first_visible - 1
	if scrolled < 0 then
		scrolled = 0
	elseif scrolled > max_first then
		scrolled = max_first
	end

	local max_start = track_height - thumb_size
	local thumb_start = 0
	if max_start > 0 then
		thumb_start = math.floor((scrolled / max_first) * max_start + 0.5)
		if thumb_start < 0 then
			thumb_start = 0
		elseif thumb_start > max_start then
			thumb_start = max_start
		end
	end

	return {
		track_height = track_height,
		thumb_start = thumb_start,
		thumb_size = thumb_size,
		full = false,
	}
end
