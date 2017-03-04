local bit = require "bit"

local FlipXBit = 0x80000000
local FlipYBit = 0x40000000

local Tiles = {}

function Tiles.getTileGid(levity, tilesetid, row, column)
	local tileset = levity.map.tilesets[tilesetid]
	if not tileset then
		return nil
	end

	local tileid

	if not column then
		tileid = row
		if type(tileid) == "string" then
			tileid = tileset.namedtileids[tileid]
		end
	elseif row then
		if type(column) == "string" then
			column = tileset.namedcols[column]
		end

		if type(row) == "string" then
			row = tileset.namedrows[row]
		end

		tileid = row * tileset.tilecolumns + column
	end

	return tileset.firstgid + tileid
end

function Tiles.getTileRowName(levity, gid)
	gid = levity:getUnflippedGid(gid)
	local tileset = levity.map.tilesets[levity.map.tiles[gid].tileset]
	local tileid = gid - tileset.firstgid
	local row = tileid / tileset.tilecolumns
	return tileset.rownames[row] or math.floor(row)
end

function Tiles.getTileColumnName(levity, gid)
	gid = levity:getUnflippedGid(gid)
	local tileset = levity.map.tilesets[levity.map.tiles[gid].tileset]
	local tileid = gid - tileset.firstgid
	local column = tileid % tileset.tilecolumns
	return tileset.columnnames[column] or column
end

function Tiles.getMapTileset(levity, tilesetid)
	return levity.map.tilesets[tilesetid]
end

function Tiles.getMapTileGid(levity, tilesetid, tileid)
	return tileid + levity.map.tilesets[tilesetid].firstgid
end

function Tiles.getMapTile(levity, tilesetid, tileid)
	return levity.map.tiles[tileid + levity.map.tilesets[tilesetid].firstgid]
end

function Tiles.getTilesetImage(levity, tilesetid)
	return levity.map.tilesets[tilesetid].image
end

--- Convert list of map-specific gids to map-agnostic names
-- @param gids list
-- @return List of name tables: { {tileset, row, column}, ... }
function Tiles.tileGidsToNames(levity, gids)
	if not gids then
		return nil
	end
	local names = {}
	for _, gid in ipairs(gids) do
		local tileset = levity.map.tilesets[levity.map.tiles[gid].tileset]

		names[#names + 1] = {
			tileset = tileset.name,
			row = levity:getTileRowName(gid),
			column = levity:getTileColumnName(gid)
		}
	end
	return names
end

--- Convert name tables to gids for current map
-- @param names list returned by tileGidsToNames
-- @return List of tile gids
function Tiles.tileNamesToGids(levity, names)
	if not names then
		return nil
	end
	local gids = {}
	for _, name in ipairs(names) do
		gids[#gids + 1] = levity:getTileGid(name.tileset,
						name.row, name.column)
	end
	return gids
end

function Tiles.updateTilesetAnimations(levity, tileset, dt)
	if type(tileset) ~= "table" then
		tileset = levity.map.tilesets[tileset]
	end
	levity:updateTileAnimations(tileset.firstgid, tileset.tilecount, dt)
end

function Tiles.updateTileAnimations(levity, firstgid, numtiles, dt)
	local tiles = levity.map.tiles
	local tilesets = levity.map.tilesets
	local tileinstances = levity.map.tileInstances

	for gid = firstgid, firstgid + numtiles - 1 do
		local tile = tiles[gid]
		if tile and tile.animation then
			local update = false
			tile.time = tile.time + dt * 1000

			while tile.time > (tile.animation[tile.frame].duration) do
				update     = true
				tile.time  = tile.time  - (tile.animation[tile.frame].duration)
				tile.frame = tile.frame + 1

				if tile.frame > #tile.animation then tile.frame = 1 end
			end

			if update and tileinstances[tile.gid] then
				for _, j in pairs(tileinstances[tile.gid]) do
					local t = tiles[(tile.animation[tile.frame].tileid) + tilesets[tile.tileset].firstgid]
					j.batch:set(j.id, t.quad, j.x, j.y, j.r, tile.sx, tile.sy, 0, j.oy)
				end
			end
		end
	end
end

function Tiles.getGidFlip(levity, gid)
	if not gid then
		return false, false
	end
	return bit.band(gid, FlipXBit) ~= 0,
		bit.band(gid, FlipYBit) ~= 0
end

function Tiles.getUnflippedGid(levity, gid)
	if not gid then
		return 0
	end

	return bit.band(gid, bit.bnot(bit.bor(FlipXBit, FlipYBit)))
end

function Tiles.setGidFlip(levity, gid, flipx, flipy)
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
