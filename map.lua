local pairs = pairs
local ipairs = ipairs
local tonumber = tonumber

local math_floor = math.floor
local math_pi = math.pi
local string_sub = string.sub
local string_find = string.find

local love_math_decompress = love.math.decompress
local love_graphics_setCanvas = love.graphics.setCanvas
local love_graphics_clear = love.graphics.clear
local love_graphics_push = love.graphics.push
local love_graphics_pop = love.graphics.pop
local love_graphics_translate = love.graphics.translate
local love_graphics_scale = love.graphics.scale
local love_graphics_setColor = love.graphics.setColor
local love_graphics_getColor = love.graphics.getColor
local love_graphics_getWidth = love.graphics.getWidth
local love_graphics_getHeight = love.graphics.getHeight
local love_graphics_draw = love.graphics.draw
local love_graphics_points = love.graphics.points
local love_graphics_line = love.graphics.line
local love_graphics_circle = love.graphics.circle
local love_graphics_polygon = love.graphics.polygon
local love_graphics_newSpriteBatch = love.graphics.newSpriteBatch
local love_graphics_newParticleSystem = love.graphics.newParticleSystem

local prefs = require "levity.prefs"
local scripting = require "levity.scripting"
local Scripts_send = scripting.newMachine.send

local maputil = require "levity.maputil"
local maputil_setObjectsDefaultProperties = maputil.setObjectsDefaultProperties

local sti = require "levity.sti.sti"
local Layer = require "levity.layer"
local Layer_init = Layer.init
local Layer_update = Layer.update

local Object = require "levity.object"
local Object_init = Object.init
local Object_setLayer = Object.setLayer

local Tiles = require "levity.tiles"
local Tiles_getGidFlip = Tiles.getGidFlip
local Tiles_getUnflippedGid = Tiles.getUnflippedGid

local CanvasMaxScale = 4

--- @table Map
-- @field objecttypes
-- @field paused

local Map = {
}
Map.__index = Map
-- Still want STI Map functions, so do not use class or metatable.

local TilesetMissingField = "Tileset %s has no %s named %s"

function Map.getTileGid(map, tilesetid, row, column)
	local tileset = map.tilesets[tilesetid]
	if not tileset then
		return nil
	end

	local tileid

	if not column then
		tileid = row
		if type(tileid) == "string" then
			tileid = tileset.namedtiles[tileid]
		elseif type(tileid) == "table" then
			local rowstype = tileset.properties.rowstype or "row"
			local colstype = tileset.properties.colstype or "column"
			row = tileid[rowstype] or 0
			column = tileid[colstype] or 0
		end
	end

	if column and row then
		if type(column) == "string" then
			local c = tileset.namedcols[column]
			if not c then
				error(TilesetMissingField:format(tileset.name, "column", column))
			end
			column = c
		end

		if type(row) == "string" then
			local r = tileset.namedrows[row]
			if not r then
				error(TilesetMissingField:format(tileset.name, "row", row))
			end
			row = r
		end

		tileid = row * tileset.tilecolumns + column
	end

	return tileset.firstgid + tileid
end

function Map.getTileRowName(map, gid)
	gid = Tiles_getUnflippedGid(gid)
	local tileset = map.tilesets[map.tiles[gid].tileset]
	local tileid = gid - tileset.firstgid
	local row = tileid / tileset.tilecolumns
	return tileset.rownames[row] or math_floor(row)
end

function Map.getTileColumnName(map, gid)
	gid = Tiles_getUnflippedGid(gid)
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
	local tiles = map.tiles
	for _, gid in ipairs(gids) do
		local tile = tiles[gid]
		local tileset = map.tilesets[tile.tileset]
		local name = tile.properties and tile.properties.name
		names[#names + 1] = {
			tileset = tileset.name,
			tile = name,
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

function Map.newSpriteBatch(map, tileset, size, usage)
	size = size or 32
	usage = usage or "dynamic"
	local tileset = map.tilesets[tileset]
	local image = tileset.image

	local spritebatch = love_graphics_newSpriteBatch(image, size, usage)
	return spritebatch
end

function Map.addBatchSprite(map, batch, gid, x, y, r, sx, sy, ox, oy, kx, ky)
	local tile = map.tiles[gid]
	local tileset = map.tilesets[tile.tileset]
	local quad = tile.quad
	return batch:add(quad, x, y, r, sx, sy,
			(ox or 0) - tile.offset.x,
			(oy or 0) - tile.offset.y + tileset.tileheight,
			kx, ky)
end

function Map.setBatchSprite(map, batch, i, gid, x, y, r, sx, sy, ox, oy, kx, ky)
	if not gid or gid <= 0 then
		batch:set(i, 0, 0, 0, 0, 0)
	else
		local tile = map.tiles[gid]
		local tileset = map.tilesets[tile.tileset]
		local quad = tile.quad
		batch:set(i, quad, x, y, r, sx, sy,
			(ox or 0) - tile.offset.x,
			(oy or 0) - tile.offset.y + tileset.tileheight,
			kx, ky)
	end
end

function Map.newParticleSystem(map, gid, buffersize)
	buffersize = buffersize or 256
	gid = Tiles.getUnflippedGid(gid)
	local tile = map.tiles[gid]
	local tilesetid = tile.tileset
	local tileset = map.tilesets[tilesetid]
	local image = tileset.image

	local particles = love_graphics_newParticleSystem(image, buffersize)

	particles:setParticleLifetime(1)
	particles:setEmissionRate(0)
	particles:setSpread(2*math_pi)
	particles:setSpeed(60)
	map:setParticlesGid(particles, gid)
	return particles
end

function Map.setParticlesGid(map, particles, gid)
	gid = Tiles.getUnflippedGid(gid)
	local tile = map.tiles[gid]
	local tilesetid = tile.tileset
	local tileset = map.tilesets[tilesetid]
	particles:setTexture(tileset.image)

	local animation = tile.animation
	if animation then
		local quads = {}
		for i = 1, #animation do
			local frame = animation[i]
			local frametile = map.tiles[tileset.firstgid
							+ frame.tileid]
			quads[#quads+1] = frametile.quad
		end
		particles:setQuads(unpack(quads))
	else
		particles:setQuads(tile.quad)
	end
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

function Map.cleanupObjects(map, discardedobjects)
	local objects = map.objects
	for id, object in pairs(discardedobjects) do
		Object_setLayer(object, nil)

		if object.body then
			-- Body:destroy sends endContact,
			-- so user data might still be needed.
			-- LOVE 0.10.3 will fix the leak.
			-- https://bitbucket.org/rude/love/issues/1273
			--for _, fixture in pairs(object.body:getFixtureList()) do
			--	fixture:setUserData(nil)
			--end
			--object.body:setUserData(nil)
			object.body:destroy()
		end

		objects[id] = nil
	end
end

function Map.update(map, dt, scripts)
	for _, layer in ipairs(map.layers) do
		layer:update(dt, map, scripts)
	end
end

local VisibleFixtures = {}

function Map.draw(map, camera, scripts, world)
	local canvas = map.canvas
	if canvas then
		love_graphics_setCanvas(canvas)
		love_graphics_clear(0, 0, 0, 1, canvas)
	end

	local cx, cy = camera.x, camera.y
	local cw, ch = camera.w, camera.h
	local ccx, ccy = cx+cw*.5, cy+ch*.5

	local scale = camera.scale
	local intscale = math_floor(scale)

	love_graphics_push()
	--love_graphics_scale(intscale, intscale)
	--love_graphics_translate(-cx, -cy)
	love_graphics_translate(-math_floor(cx * intscale),
				-math_floor(cy * intscale))

	if scripts then
		Scripts_send(scripts, map.name, "beginDraw")
	end
	for _, layer in ipairs(map.layers) do
		if layer.visible and layer.opacity > 0 then
			if scripts then
				Scripts_send(scripts, layer.name, "beginDraw")
			end

			love_graphics_push()
			love_graphics_translate(
				math_floor(layer.offsetx*intscale),
				math_floor(layer.offsety*intscale))
			love_graphics_scale(intscale, intscale)

			local r,g,b,a = love_graphics_getColor()
			love_graphics_setColor(r, g, b, a * layer.opacity)

			if scripts then
				Scripts_send(scripts, layer.name, "drawUnder")
			end

			layer:draw(map, camera, scripts)

			if scripts then
				Scripts_send(scripts, layer.name, "drawOver")
			end

			love_graphics_setColor(r,g,b,a)

			love_graphics_pop()

			if scripts then
				Scripts_send(scripts, layer.name, "endDraw")
			end
		end
	end
	if scripts then
		Scripts_send(scripts, map.name, "endDraw")
	end

	if world then
		world:queryBoundingBox(cx, cy, cx+cw, cy+ch,
			function(fixture)
				VisibleFixtures[#VisibleFixtures+1] = fixture
				return true
			end)

		love_graphics_scale(intscale, intscale)

		for _, fixture in ipairs(VisibleFixtures) do
			local body = fixture:getBody()
			love_graphics_circle("line", body:getX(), body:getY(),
						intscale)

			local bodycx, bodycy = body:getWorldCenter()
			love_graphics_line(bodycx - intscale, bodycy,
					bodycx + intscale, bodycy)
			love_graphics_line(bodycx, bodycy - intscale,
					bodycx, bodycy + intscale)

			local shape = fixture:getShape()
			if shape:getType() == "circle" then
				local x, y = body:getWorldPoint(
					shape:getPoint())
				love_graphics_circle("line", x, y,
					shape:getRadius())
				love_graphics_points(x, y)
			elseif shape:getType() == "polygon" then
				love_graphics_polygon("line",
					body:getWorldPoints(shape:getPoints()))
			elseif shape:getType() == "chain" then
				love_graphics_line(
					body:getWorldPoints(shape:getPoints()))
			end
		end

		while #VisibleFixtures > 0 do
			VisibleFixtures[#VisibleFixtures] = nil
		end
	end

	love_graphics_pop()

	if canvas then
		love_graphics_setCanvas()
		local canvasscale = scale / intscale
		love_graphics_draw(canvas,
					love_graphics_getWidth()*.5,
					love_graphics_getHeight()*.5,
					prefs.rotation,
					canvasscale, canvasscale,
					canvas:getWidth()*.5,
					canvas:getHeight()*.5)
	end
end

local function initTileset(tileset, tiles)
	tileset.tilecolumns =
		math_floor(tileset.imagewidth / tileset.tilewidth)

	tileset.namedtiles = {}
	tileset.namedrows = {}
	tileset.namedcols = {}
	tileset.rownames = {}
	tileset.columnnames = {}
	--tileset.tilenames = {}

	for p, v in pairs(tileset.properties) do
		if string_find(p, "rowname") == 1 then
			local num = tonumber(string_sub(p, 8))
			tileset.rownames[num] = v
			tileset.namedrows[v] = num
		elseif string_find(p, "colname") == 1 then
			local num = tonumber(string_sub(p, 8))
			tileset.columnnames[num] = v
			tileset.namedcols[v] = num
		elseif string_find(p, "row_") == 1 then
			local name = string_sub(p, 5)
			tileset.rownames[v] = name
			tileset.namedrows[name] = v
		elseif string_find(p, "column_") == 1 then
			local name = string_sub(p, 8)
			tileset.columnnames[v] = name
			tileset.namedcols[name] = v
		end
	end

	for _, tile in pairs(tileset.tiles) do
		if tile.properties then
			local name = tile.properties.name
			if name then
				--tileset.tilenames[tile.id] = name
				tileset.namedtiles[name] = tile.id
			end
		end
	end

	local lastgid = tileset.firstgid + tileset.tilecount - 1

	local commonanimation = tileset.properties.commonanimation

	if commonanimation then
		local commonanimationtilegid =
			tileset.firstgid + commonanimation
		local commonanimationtile =
			tiles[commonanimationtilegid]

		commonanimation = commonanimationtile.animation

		for i = tileset.firstgid, lastgid do
			local tile = tiles[i]
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
			tiles[commoncollisiontilegid]

		commoncollision = commoncollisiontile.objectGroup

		for i = tileset.firstgid, lastgid do
			local tile = tiles[i]
			if not tile.objectGroup then
				tile.objectGroup = commoncollision
			end
		end
	end
end

function Map.initScripts(map, scripts)
	local layers = map.layers
	for i = 1, #layers do
		local layer = layers[i]

		if layer.objects then
			for _, object in pairs(layer.objects) do
				local script = object.properties.script
				if script then
					require(script)
				end
			end

			if layer.type == "dynamiclayer"
			and not map.properties.delayinitobjects then
				for _, object in pairs(layer.objects) do
					Object_init(object, layer, map)
				end
			end
		end

		scripts:newScript(layer.name, layer.properties.script, layer)
	end

	scripts:newScript(map.name, map.properties.script, map)

	if not map.properties.delayinitobjects then
		for _, object in pairs(map.objects) do
			Scripts_send(scripts, object.id, "initQuery")
		end
		for i = 1, #layers do
			Scripts_send(scripts, layers[i].name, "initQuery")
		end
		Scripts_send(scripts, map.name, "initQuery")
	end
end

function Map.windowResized(map, w, h, camera)
	camera:updateScale()
	local intscale = math_floor(camera.scale)
	map:resize(camera.w * intscale, camera.h * intscale)
	map.canvas:setFilter("linear", "linear")
end

local function incIdProperties(properties, incid)
	for pn, pv in pairs(properties) do
		if type(pv) == "number" and string_sub(pn, -2) == "id" then
			properties[pn] = pv + incid
		end
	end
end

local function mergeMaps(map1, map2)
	--Bump gids
	local lasttileset1 = map1.tilesets[#map1.tilesets]
	local incgid = lasttileset1.firstgid + lasttileset1.tilecount - 1

	--Bump object ids
	local incid = map1.nextobjectid - 1

	--Next object id
	map1.nextobjectid = incid + map2.nextobjectid

	local tilesets1 = map1.tilesets
	local tilesets2 = map2.tilesets
	for i = 1, #tilesets2 do
		local tileset2 = tilesets2[i]
		--Tileset firstgids
		tileset2.firstgid = tileset2.firstgid + incgid
		tilesets1[#tilesets1 + 1] = tileset2
	end

	--Object id references in properties
	incIdProperties(map2.properties, incid)
	for pn, pv in pairs(map2.properties) do
		map1.properties[pn] = pv
	end

	local layers1 = map1.layers
	local layers2 = map2.layers
	for i = 1, #layers2 do
		local layer2 = layers2[i]

		--Object id references in properties
		incIdProperties(layer2.properties, incid)

		if layer2.objects then
			for _, object2 in pairs(layer2.objects) do
				--Tile object gids
				if object2.gid then
					object2.gid = object2.gid + incgid
				end

				--Object ids
				object2.id = object2.id + incid

				--Object id references in properties
				incIdProperties(object2.properties, incid)
			end
		end

		--Tile layer gids
		local data = layer2.data

		if layer2.encoding == "base64" then
			local utils = require "sti.sti.utils"
			require "ffi"

			local fd  = love.filesystem.newFileData(data, "data",
							"base64"):getString()

			local compression = layer2.compression
			if compression == "zlib" or compression == "gzip" then
				fd = love_math_decompress(fd, compression)
			end

			data = utils.get_decompressed_data(fd)

			layer2.data = data
			layer2.encoding = nil
		end

		if data then
			for i = 1, #data do
				data[i] = data[i] + incgid
			end
		end

		layers1[#layers1 + 1] = layer2
	end

	return map1
end

function Map.loadFonts(map, fonts)
	local layers = map.layers
	for l = 1, #layers do
		local objects = layers[l].objects
		if objects then
			for _, object in pairs(objects) do
				local textfont = object.properties.textfont
				local textfontsize = object.properties.textfontsize
				if textfont then
					fonts:load(textfont, textfontsize)
				end
			end
		end
	end
end

function Map.loadSounds(map, bank)
	if map.properties.staticsounds then
		bank:load(map.properties.staticsounds, "static")
	end
	if map.properties.streamsounds then
		bank:load(map.properties.streamsounds, "stream")
	end
end

local function newMap(mapfile)
	local map1 = love.filesystem.load(mapfile)()
	if map1.properties.overlaymap then
		local map2 = love.filesystem.load(map1.properties.overlaymap)()
		map1 = mergeMaps(map1, map2)
	end

	for _, layer in ipairs(map1.layers) do
		if layer.objects and layer.properties.static ~= true then
			layer.type = "dynamiclayer"
		end
	end

	local map = sti(map1, {"box2d"})
	for fname, f in pairs(Map) do
		if fname ~= "__call" then
			map[fname] = f
		end
	end

	map.name = mapfile
	map.paused = false

	local tiles = map.tiles

	local objecttypes = maputil.loadObjectTypesFile("objecttypes.xml")
	map.objecttypes = objecttypes

	if objecttypes then
		maputil.setObjectTypesBases(map.objecttypes)

		for _, layer in ipairs(map.layers) do
			if layer.objects then
				maputil_setObjectsDefaultProperties(
					layer.objects, objecttypes)
			end
		end

		for t, properties in pairs(objecttypes) do
			for k, v in pairs(properties) do
				if string_sub(k, -2) == "id"
				and (v == 0 or v == "") then
					properties[k] = nil
				end
			end
		end

		for i = 1, #tiles do
			local tile = tiles[i]
			local objectgroup = tile.objectGroup
			if objectgroup then
				maputil_setObjectsDefaultProperties(
					objectgroup.objects, objecttypes)
			end
		end
	end

	local width = map.width * map.tilewidth
	local height = map.height * map.tileheight

	local tilesets = map.tilesets
	for _, tileset in ipairs(map.tilesets) do
		tilesets[tileset.name] = tileset
		initTileset(tileset, tiles)
	end

	setmetatable(tiles, {
		__index = function(tiles, gid)
			error("There is no tile with gid "..gid
				.." (out of "..#tiles.." tiles)")
		end
	})

	local setObjectCoordinates = map.setObjectCoordinates
	local objects = map.objects
	for _, layer in ipairs(map.layers) do
		if layer.type == "dynamiclayer" then
			setObjectCoordinates(map, layer)
			Layer_init(layer)
			for _, object in pairs(layer.objects) do
				objects[object.id] = object
			end
		elseif layer.type == "tilelayer" then
			layer.draw = Layer.drawBatches
		elseif layer.type == "imagelayer" then
			layer.draw = Layer.drawImage
		end
	end

	return map
end

return newMap
