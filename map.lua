local scripting = require "levity.scripting"
local maputil = require "levity.maputil"
local sti = require "sti.sti"
local Layer = require "levity.layer"
local Object = require "levity.object"
local Tiles = require "levity.tiles"

local CanvasMaxScale = 4

--- @table Map
-- @field objecttypes
-- @field discardedobjects
-- @field paused

local Map = {
}
-- Still want STI Map functions, so do not use class or metatable.

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

function Map.newSpriteBatch(map, tileset, size, usage)
	size = size or 32
	usage = usage or "dynamic"
	local tileset = map.tilesets[tileset]
	local image = tileset.image

	local spritebatch = love.graphics.newSpriteBatch(image, size, usage)
	return spritebatch
end

function Map.addBatchSprite(map, batch, gid, x, y, r, sx, sy, ox, oy, kx, ky)
	local tile = map.tiles[gid]
	local quad = tile.quad
	return batch:add(quad, x, y, r, sx, sy, ox, oy, kx, ky)
end

function Map.setBatchSprite(map, batch, i, gid, x, y, r, sx, sy, ox, oy, kx, ky)
	if not gid or gid <= 0 then
		batch:set(i, 0, 0, 0, 0, 0)
	else
		local tile = map.tiles[gid]
		local quad = tile.quad
		batch:set(i, quad, x, y, r, sx, sy, ox, oy, kx, ky)
	end
end

function Map.newParticleSystem(map, gid, buffersize)
	buffersize = buffersize or 256
	gid = Tiles.getUnflippedGid(gid)
	local tile = map.tiles[gid]
	local tilesetid = tile.tileset
	local tileset = map.tilesets[tilesetid]
	local image = tileset.image

	local particles = love.graphics.newParticleSystem(image, buffersize)

	particles:setParticleLifetime(1)
	particles:setEmissionRate(0)
	particles:setSpread(2*math.pi)
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

function Map.discardObject(map, id)
	map.discardedobjects[id] = map.objects[id]
end

function Map.cleanupObjects(map, scripts)
	for id, object in pairs(map.discardedobjects) do
		Object.setLayer(object, nil)

		if object.body then
			for _, fixture in pairs(object.body:getFixtureList()) do
				fixture:setUserData(nil)
			end
			object.body:setUserData(nil)
			object.body:destroy()
		end

		scripts:destroyIdScripts(id)

		map.objects[id] = nil
	end

	for id, _ in pairs(map.discardedobjects) do
		map.discardedobjects[id] = nil
	end
end

function Map.update(map, dt, scripts)
	for _, layer in ipairs(map.layers) do
		layer:update(dt, map, scripts)
	end
end

local VisibleFixtures = {}

function Map.draw(map, camera, scripts, world)
	if map.canvas then
		love.graphics.setCanvas(map.canvas)
		love.graphics.clear(0, 0, 0, 1, map.canvas)
	end

	local cx, cy = camera.x, camera.y
	local cw, ch = camera.w, camera.h
	local ccx, ccy = cx+cw*.5, cy+ch*.5

	local scale = camera.scale
	local intscale = math.min(math.floor(scale), CanvasMaxScale)

	love.graphics.push()
	love.graphics.translate(-math.floor(cx * intscale),
				-math.floor(cy * intscale))
	love.graphics.scale(intscale, intscale)

	if scripts then
		scripts:send(map.name, "beginDraw")
	end
	for _, layer in ipairs(map.layers) do
		if layer.visible and layer.opacity > 0 then
			if scripts then
				scripts:send(layer.name, "beginDraw")
			end
			local r,g,b,a = love.graphics.getColor()
			love.graphics.setColor(r, g, b, a * layer.opacity)

			layer:draw(map, camera, scripts)

			love.graphics.setColor(r,g,b,a)
			if scripts then
				scripts:send(layer.name, "endDraw")
			end
		end
	end
	if scripts then
		scripts:send(map.name, "endDraw")
	end

	if world then
		world:queryBoundingBox(cx, cy, cx+cw, cy+ch,
			function(fixture)
				VisibleFixtures[#VisibleFixtures+1] = fixture
				return true
			end)

		for _, fixture in ipairs(VisibleFixtures) do
			local body = fixture:getBody()
			love.graphics.circle("line", body:getX(), body:getY(),
						intscale)

			local bodycx, bodycy = body:getWorldCenter()
			love.graphics.line(bodycx - intscale, bodycy,
					bodycx + intscale, bodycy)
			love.graphics.line(bodycx, bodycy - intscale,
					bodycx, bodycy + intscale)

			local shape = fixture:getShape()
			if shape:getType() == "circle" then
				local x, y = body:getWorldPoint(
					shape:getPoint())
				love.graphics.circle("line", x, y,
					shape:getRadius())
				love.graphics.points(x, y)
			elseif shape:getType() == "polygon" then
				love.graphics.polygon("line",
					body:getWorldPoints(shape:getPoints()))
			elseif shape:getType() == "chain" then
				love.graphics.line(
					body:getWorldPoints(shape:getPoints()))
			end
		end

		while #VisibleFixtures > 0 do
			VisibleFixtures[#VisibleFixtures] = nil
		end
	end

	love.graphics.pop()

	if map.canvas then
		love.graphics.setCanvas()
		local canvasscale = scale / intscale
		love.graphics.draw(map.canvas,
					love.graphics.getWidth()*.5,
					love.graphics.getHeight()*.5,
					0, canvasscale, canvasscale,
					map.canvas:getWidth()*.5,
					map.canvas:getHeight()*.5)
	end
end

function Map.destroy(map, scripts)
	map.discardedobjects = map.objects
	map:cleanupObjects(scripts)
	sti:flush()
end

local function initTileset(tileset, tiles)
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
	scripting.beginScriptLoading()
	for i = 1, #map.layers do
		local layer = map.layers[i]

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
					Object.init(object, layer, map)
				end
			end
		end

		scripts:newScript(layer.name, layer.properties.script, layer)
	end

	scripts:newScript(map.name, map.properties.script, map)

	scripting.endScriptLoading()
end

function Map.windowResized(map, w, h, camera)
	local scale = math.min(w/camera.w, h/camera.h)
	local intscale = math.min(math.floor(scale), CanvasMaxScale)
	map:resize(camera.w * intscale, camera.h * intscale)
	map.canvas:setFilter("linear", "linear")
	camera.scale = scale
end

local function incIdProperties(properties, incid)
	for pn, pv in pairs(properties) do
		if type(pv) == "number" and pn:sub(-2) == "id" then
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

	local tilesets1 = {}
	local tilesets2 = map2.tilesets
	for i = 1, #map1.tilesets do
		local tileset1 = map1.tilesets[i]
		tilesets1[tileset1.name] = tileset1
	end
	for i = 1, #tilesets2 do
		local tileset2 = tilesets2[i]
		if not tilesets1[tileset2.name] then
			--Tileset firstgids
			tileset2.firstgid = tileset2.firstgid + incgid
			map1.tilesets[#map1.tilesets + 1] = tileset2
		end
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
				fd = love.math.decompress(fd, compression)
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
	for l = 1, #map.layers do
		local objects = map.layers[l].objects
		if objects then
			for _, object in pairs(objects) do
				local textfont = object.properties.textfont
				if textfont then
					fonts:load(textfont)
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

	local map = sti(map1, {"box2d"})
	for fname, f in pairs(Map) do
		map[fname] = f
	end

	map.name = mapfile
	map.discardedobjects = {}
	map.paused = false

	map.objecttypes = maputil.loadObjectTypesFile("objecttypes.xml")
	if map.objecttypes then
		maputil.setObjectsDefaultProperties(map.objects,
							map.objecttypes)
		local tiles = map.tiles
		for i = 1, #tiles do
			local tile = tiles[i]
			local objectgroup = tile.objectGroup
			if objectgroup then
				maputil.setObjectsDefaultProperties(
					objectgroup.objects, map.objecttypes)
			end
		end
	end

	local width = map.width * map.tilewidth
	local height = map.height * map.tileheight

	for _, tileset in ipairs(map.tilesets) do
		map.tilesets[tileset.name] = tileset
		initTileset(tileset, map.tiles)
	end

	for l = #map.layers, 1, -1 do
		local layer = map.layers[l]
		local layerdynamic = (layer.properties.static ~= true)

		if layer.objects and layerdynamic then
			local name = layer.name
			local visible = layer.visible
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

			layer.visible = visible
			layer.offsetx = offsetx
			layer.offsety = offsety
			layer.properties = properties
			layer.draworder = draworder
		end
	end

	return map
end

return newMap
