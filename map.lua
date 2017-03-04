local Layer = require "levity.layer"
local Object = require "levity.object"
local Tiles = require "levity.tiles"
local maputil = require "maputil"
local sti = require "sti.sti"

local MaxIntScale = 4

--- @table Map
-- @field objecttypes
-- @field scripts
-- @field world
-- @field camera
-- @field discardedobjects
-- @field paused

local Map = {}

function Map.getTileGid(map, tilesetid, row, column)
	local tileset = map.tilesets[tilesetid]
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

function Map.getTileRowName(map, gid)
	gid = Tiles.getUnflippedGid(gid)
	local tileset = map.tilesets[map.tiles[gid].tileset]
	local tileid = gid - tileset.firstgid
	local row = tileid / tileset.tilecolumns
	return tileset.rownames[row] or math.floor(row)
end

function Map.getTileColumnName(map, gid)
	gid = Tiles.getUnflippedGid(gid)
	local tileset = map.tilesets[map.tiles[gid].tileset]
	local tileid = gid - tileset.firstgid
	local column = tileid % tileset.tilecolumns
	return tileset.columnnames[column] or column
end

function Map.getTileset(map, tilesetid)
	return map.tilesets[tilesetid]
end

function Map.getTile(map, tilesetid, tileid)
	return map.tiles[tileid + map.tilesets[tilesetid].firstgid]
end

function Map.getTilesetImage(map, tilesetid)
	return map.tilesets[tilesetid].image
end

--- Convert list of map-specific gids to map-agnostic names
-- @param gids list
-- @return List of name tables: { {tileset, row, column}, ... }
function Map.tileGidsToNames(map, gids)
	if not gids then
		return nil
	end
	local names = {}
	for _, gid in ipairs(gids) do
		local tileset = map.tilesets[map.tiles[gid].tileset]

		names[#names + 1] = {
			tileset = tileset.name,
			row = map:getTileRowName(gid),
			column = map:getTileColumnName(gid)
		}
	end
	return names
end

--- Convert name tables to gids for current map
-- @param names list returned by tileGidsToNames
-- @return List of tile gids
function Map.tileNamesToGids(map, names)
	if not names then
		return nil
	end
	local gids = {}
	for _, name in ipairs(names) do
		gids[#gids + 1] = map:getTileGid(name.tileset,
						name.row, name.column)
	end
	return gids
end

function Map.updateTilesetAnimations(map, tileset, dt)
	if type(tileset) ~= "table" then
		tileset = map.tilesets[tileset]
	end
	map:updateTileAnimations(tileset.firstgid, tileset.tilecount, dt)
end

function Map.updateTileAnimations(map, firstgid, numtiles, dt)
	local tiles = map.tiles
	local tilesets = map.tilesets
	local tileinstances = map.tileInstances

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

function Map.newObjectId(map)
	local id = map.nextobjectid
	map.nextobjectid = map.nextobjectid + 1
	return id
end

function Map.discardObject(map, id)
	map.discardedobjects[id] = map.objects[id]
end

function Map.cleanupObjects(map)
	for id, object in pairs(map.discardedobjects) do
		Object.setLayer(object, nil)

		if object.body then
			object.body:destroy()
		end

		map.scripts:destroyScript(id)

		map.objects[id] = nil
	end

	for id, _ in pairs(map.discardedobjects) do
		map.discardedobjects[id] = nil
	end
end

local function camera_set(camera, cx, cy, w, h)
	if w then
		camera.w = w
	end
	if h then
		camera.h = h
	end
	if w or h then
		local gw = love.graphics.getWidth()
		local gh = love.graphics.getHeight()
		camera.scale = math.min(gw/camera.w, gh/camera.h)
	end
	camera.x = math.floor(cx - camera.w * .5)
	camera.y = math.floor(cy - camera.h * .5)
end

local function camera_zoom(camera, vz)
	local aspect = camera.w / camera.h
	camera:set(camera.x - vz*aspect*.5,
		camera.y - vz*.5,
		camera.w + vz*aspect,
		camera.h + vz)
end

local function newMap(mapfile)
	local map = sti(mapfile, {"box2d"})
	for fname, f in pairs(Map) do
		map[fname] = f
	end

	map.discardedobjects = {}
	map.camera = {
		x = 0, y = 0,
		w = love.graphics.getWidth(), h = love.graphics.getHeight(),
		scale = 1,
		set = camera_set,
		zoom = camera_zoom
	}

	map.objecttypes = maputil.loadObjectTypesFile("objecttypes.xml")
	if map.objecttypes then
		maputil.setObjectsDefaultProperties(map.objects,
							map.objecttypes)
	end

	local width = map.width * map.tilewidth
	local height = map.height * map.tileheight

	if map.properties.gravity then
		map.world:setGravity(0, map.properties.gravity)
	end

	for _, tileset in ipairs(map.tilesets) do
		map.tilesets[tileset.name] = tileset

		tileset.tilecolumns =
			math.floor(tileset.imagewidth / tileset.tilewidth)

		tileset.namedtileids = {}
		tileset.namedrows = {}
		tileset.namedcols = {}
		tileset.rownames = {}
		tileset.columnnames = {}
		--tileset.tilenames = {}

		for p, v in pairs(tileset.properties) do
			if string.find(p, "rowname") == 1 then
				local num = tonumber(string.sub(p, 8))
				tileset.rownames[num] = v
				tileset.namedrows[v] = num
			elseif string.find(p, "colname") == 1 then
				local num = tonumber(string.sub(p, 8))
				tileset.columnnames[num] = v
				tileset.namedcols[v] = num
			elseif string.find(p, "row_") == 1 then
				local name = string.sub(p, 5)
				tileset.rownames[v] = name
				tileset.namedrows[name] = v
			elseif string.find(p, "column_") == 1 then
				local name = string.sub(p, 8)
				tileset.columnnames[v] = name
				tileset.namedcols[name] = v
			end
		end

		for _, tile in pairs(tileset.tiles) do
			if tile.properties then
				local name = tile.properties.name
				if name then
					--tileset.tilenames[tile.id] = tilename
					tileset.namedtileids[name] = tile.id
				end
			end
		end

		local lastgid = tileset.firstgid + tileset.tilecount - 1

		local commonanimation = tileset.properties.commonanimation

		if commonanimation then
			local commonanimationtilegid =
				tileset.firstgid + commonanimation
			local commonanimationtile =
				map.tiles[commonanimationtilegid]

			commonanimation = commonanimationtile.animation

			for i = tileset.firstgid, lastgid do
				local tile = map.tiles[i]
				if not tile.animation then
					tile.animation = {}
					for _, frame in ipairs(commonanimation) do
						local tileid = tile.id + (frame.tileid)

						table.insert(tile.animation, {
							tileid = tostring(tileid),
							duration = frame.duration
						})
					end
				end
			end
		end

		local commoncollision = tileset.properties.commoncollision

		if commoncollision then
			local commoncollisiontilegid =
				tileset.firstgid + commoncollision
			local commoncollisiontile =
				map.tiles[commoncollisiontilegid]

			commoncollision = commoncollisiontile.objectGroup

			for i = tileset.firstgid, lastgid do
				local tile = map.tiles[i]
				if not tile.objectGroup then
					tile.objectGroup = commoncollision
				end
			end
		end

		if tileset.properties.font then
			tileset.properties.font =
				love.graphics.newImageFont(tileset.image,
					tileset.properties.fontglyphs)
		end
	end

	for l = #map.layers, 1, -1 do
		local layer = map.layers[l]
		layer.map = map
		local layerdynamic = (layer.properties.static ~= true)

		if layer.objects and layerdynamic then
			local name = layer.name
			local objects = layer.objects
			local offsetx = layer.offsetx
			local offsety = layer.offsety
			local properties = layer.properties
			local draworder = layer.draworder

			for _, object in pairs(objects) do
				object.layer = nil
			end
			map:removeLayer(l)

			layer = Layer(map, name, l)
			for _, object in pairs(objects) do
				Object.setLayer(object, layer)
			end

			layer.offsetx = offsetx
			layer.offsety = offsety
			layer.properties = properties
			layer.draworder = draworder
		end
	end

	local intscale = math.min(math.floor(map.camera.scale), MaxIntScale)
	map:resize(map.camera.w * intscale, map.camera.h * intscale)
	map.canvas:setFilter("linear", "linear")

	map.paused = false

	return map
end

return newMap
