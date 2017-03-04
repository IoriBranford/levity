local bit = require "bit"

local FlipXBit = 0x80000000
local FlipYBit = 0x40000000

local Tiles = {}

function Tiles.getGidFlip(gid)
	if not gid then
		return false, false
	end
	return bit.band(gid, FlipXBit) ~= 0,
		bit.band(gid, FlipYBit) ~= 0
end

function Tiles.getUnflippedGid(gid)
	if not gid then
		return 0
	end

	return bit.band(gid, bit.bnot(bit.bor(FlipXBit, FlipYBit)))
end

function Tiles.setGidFlip(gid, flipx, flipy)
	if not gid then
		return 0
	end

	if flipx == true then
		gid = bit.bor(gid, FlipXBit)
	else
		gid = bit.band(gid, bit.bnot(FlipXBit))
	end

	if flipy == true then
		gid = bit.bor(gid, FlipYBit)
	else
		gid = bit.band(gid, bit.bnot(FlipYBit))
	end

	return gid
end

return Tiles
