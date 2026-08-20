--!nonstrict
loadfile("tests/testsuite.lua")()

local function AssertScrollbar(want, total, first_visible, visible, height)
	local got = ComputeScrollbarGeometry(total, first_visible, visible, height)
	AssertEquals(want.track_height, got.track_height)
	AssertEquals(want.thumb_start, got.thumb_start)
	AssertEquals(want.thumb_size, got.thumb_size)
	AssertEquals(want.full, got.full)
end

-- 1. Empty document.
AssertScrollbar(
	{track_height = 8, thumb_start = 0, thumb_size = 8, full = true},
	0, 1, 0, 10)

-- 2. One line, tiny viewport.
AssertScrollbar(
	{track_height = 8, thumb_start = 0, thumb_size = 8, full = true},
	1, 1, 1, 10)

-- 3. Document smaller than the viewport.
AssertScrollbar(
	{track_height = 18, thumb_start = 0, thumb_size = 18, full = true},
	5, 1, 5, 20)

-- 4. Document exactly the size of the viewport.
AssertScrollbar(
	{track_height = 18, thumb_start = 0, thumb_size = 18, full = true},
	20, 1, 20, 20)

-- 5. Document larger than the viewport (basic sanity: not full, thumb fits).
do
	local got = ComputeScrollbarGeometry(1000, 1, 20, 22)
	AssertEquals(false, got.full)
	AssertEquals(20, got.track_height)
	if got.thumb_size < 1 then
		error("thumb_size must never be smaller than 1 row")
	end
end

-- 6. Start of the document: thumb pinned to the top of the track.
AssertScrollbar(
	{track_height = 18, thumb_start = 0, thumb_size = 9, full = false},
	40, 1, 20, 20)

-- 7. Middle of the document: thumb roughly centred in the track.
do
	-- 200 lines, viewport shows 20, currently showing lines 91-110
	-- (halfway through the 181 possible starting positions).
	local got = ComputeScrollbarGeometry(200, 91, 20, 20)
	AssertEquals(false, got.full)
	local max_start = got.track_height - got.thumb_size
	local mid = math.floor(max_start / 2 + 0.5)
	-- Allow +/-1 row of rounding slack either side of the true centre.
	if math.abs(got.thumb_start - mid) > 1 then
		error(string.format(
			"expected thumb_start near the middle of the track (~%d), got %d",
			mid, got.thumb_start))
	end
end

-- 8. End of the document: thumb pinned to the bottom of the track.
do
	local got = ComputeScrollbarGeometry(40, 21, 20, 20)
	AssertEquals(false, got.full)
	AssertEquals(got.track_height - got.thumb_size, got.thumb_start)
end

-- 9. Document with thousands of lines.
do
	local got = ComputeScrollbarGeometry(50000, 25001, 40, 42)
	AssertEquals(false, got.full)
	AssertEquals(40, got.track_height)
	if (got.thumb_start < 0) or (got.thumb_start + got.thumb_size > got.track_height) then
		error("thumb ran outside the track on a large document")
	end
end

-- 10. Minimal viewport heights: never crash, never produce a negative
-- track, thumb always contained.
for _, h in ipairs({0, 1, 2, 3}) do
	local got = ComputeScrollbarGeometry(100, 50, 5, h)
	if got.track_height < 0 then
		error("track_height went negative for height="..h)
	end
	if (got.thumb_start < 0) or (got.thumb_start + got.thumb_size > got.track_height) then
		error("thumb overran the track for height="..h)
	end
end

-- 11. Resizing the viewport: recomputing from scratch for a taller
-- viewport should never shrink the reported track below what fits.
do
	local small = ComputeScrollbarGeometry(500, 100, 10, 12)
	local big = ComputeScrollbarGeometry(500, 100, 30, 32)
	if big.track_height <= small.track_height then
		error("track_height should grow when the viewport grows")
	end
end

-- 12. thumb_start + thumb_size must never exceed track_height, across a
-- wide sweep of positions and document/viewport sizes.
for _, total in ipairs({0, 1, 2, 10, 37, 200, 10000}) do
	for _, visible in ipairs({0, 1, 5, 20, 50}) do
		for _, height in ipairs({0, 1, 2, 3, 5, 20, 80}) do
			for _, first in ipairs({1, 2, 17, total, total + 1, total * 2}) do
				local got = ComputeScrollbarGeometry(total, first, visible, height)
				if got.thumb_start + got.thumb_size > got.track_height then
					error(string.format(
						"thumb overran track: total=%d first=%d visible=%d height=%d "..
						"-> thumb_start=%d thumb_size=%d track_height=%d",
						total, first, visible, height,
						got.thumb_start, got.thumb_size, got.track_height))
				end
				if got.thumb_start < 0 then
					error("thumb_start went negative")
				end
			end
		end
	end
end
