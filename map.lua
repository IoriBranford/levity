local levity
local scripting = require "levity.scripting"
local maputil = require "levity.maputil"
local sti = require "sti.sti"
local Layer = require "levity.layer"
local Object = require "levity.object"
local Tiles = require "levity.tiles"

local CanvasMaxScale = 4

--- @table Map
-- @field objecttypes
-- @field scripts
-- @field world
-- @field camera
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

	if map.overlaymap then
		map.overlaymap:cleanupObjects()
	end
end

function Map.broadcast(map, event, ...)
	map.scripts:broadcast(event, ...)
	if map.overlaymap then
		map.overlaymap:broadcast(event, ...)
	end
end

function Map.update(map, dt)
	map.scripts:clearLogs()

	if map.paused then
	else
		map.scripts:broadcast("beginMove", dt)
		map.world:update(dt)
		map.scripts:broadcast("endMove", dt)

		for _, layer in ipairs(map.layers) do
			layer:update(dt, map)
		end
		map.scripts:printLogs()
	end

	map:cleanupObjects()

	if map.overlaymap then
		map.overlaymap:update(dt)
	end
end

local VisibleFixtures = {}

function Map.draw(map)
	if map.canvas then
		love.graphics.setCanvas(map.canvas)
		love.graphics.clear(0, 0, 0, 1, map.canvas)
	end

	local cx, cy = map.camera.x, map.camera.y
	local cw, ch = map.camera.w, map.camera.h
	local ccx, ccy = cx+cw*.5, cy+ch*.5

	local scale = map.camera.scale
	local intscale = math.min(math.floor(scale), CanvasMaxScale)

	love.graphics.push()
	love.graphics.translate(-math.floor(cx * intscale),
				-math.floor(cy * intscale))
	love.graphics.scale(intscale, intscale)

	map.scripts:call(map.name, "beginDraw")
	for _, layer in ipairs(map.layers) do
		if layer.visible and layer.opacity > 0 then
			map.scripts:call(layer.name, "beginDraw")
			local r,g,b,a = love.graphics.getColor()
			love.graphics.setColor(r, g, b, a * layer.opacity)
			layer:draw(map)
			love.graphics.setColor(r,g,b,a)
			map.scripts:call(layer.name, "endDraw")
		end
	end
	map.scripts:call(map.name, "endDraw")

	if levity.drawbodies then
		map.world:queryBoundingBox(cx, cy, cx+cw, cy+ch,
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

	if map.overlaymap then
		map.overlaymap:draw()
	end

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

function Map.destroy(map)
	if map.overlaymap then
		map.overlaymap:destroy()
	end
	map.world:setCallbacks()
	map.world:destroy()
	scripting.unloadScripts()
	sti:flush()
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
	camera.x = (cx - camera.w * .5)
	camera.y = (cy - camera.h * .5)
end

local function camera_zoom(camera, vz)
	local aspect = camera.w / camera.h
	camera:set(camera.x - vz*aspect*.5,
		camera.y - vz*.5,
		camera.w + vz*aspect,
		camera.h + vz)
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

function Map.collisionEvent(map, event, fixture, ...)
	local ud = fixture:getBody():getUserData()
	if ud then
		local id = ud.id
		if id then
			map.scripts:call(id, event, fixture, ...)
		end
	end
end

local function initPhysics(map)
	map.world = love.physics.newWorld(0, map.properties.gravity or 0)

	local function beginContact(fixture1, fixture2, contact)
		map:collisionEvent("beginContact", fixture1, fixture2, contact)
		map:collisionEvent("beginContact", fixture2, fixture1, contact)
	end

	local function endContact(fixture1, fixture2, contact)
		map:collisionEvent("endContact", fixture1, fixture2, contact)
		map:collisionEvent("endContact", fixture2, fixture1, contact)
	end

	local function preSolve(fixture1, fixture2, contact)
		map:collisionEvent("preSolve", fixture1, fixture2, contact)
		map:collisionEvent("preSolve", fixture2, fixture1, contact)
	end

	local function postSolve(fixture1, fixture2, contact,
				normal1, tangent1, normal2, tangent2)
		map:collisionEvent("postSolve", fixture1, fixture2, contact,
				normal1, tangent1, normal2, tangent2)
		map:collisionEvent("postSolve", fixture2, fixture1, contact,
				normal1, tangent1, normal2, tangent2)
	end

	map.world:setCallbacks(beginContact, endContact, preSolve, postSolve)

	map:box2d_init(map.world)
end

function Map.initScripts(map)
	map.scripts = scripting.newMachine()

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

		map.scripts:newScript(layer.name, layer.properties.script, layer)
	end

	map.scripts:newScript(map.name, map.properties.script, map)

	scripting.endScriptLoading()

	if map.overlaymap then
		map.overlaymap:initScripts()
	end
end

function Map.windowResized(map, w, h)
	local camera = map.camera
	local scale = math.min(w/camera.w, h/camera.h)
	local intscale = math.min(math.floor(scale), CanvasMaxScale)
	map:resize(camera.w * intscale, camera.h * intscale)
	map.canvas:setFilter("linear", "linear")
	camera.scale = scale
end

local function newMap(mapfile)
	levity = require "levity"

	local map = sti(mapfile, {"box2d"})
	for fname, f in pairs(Map) do
		map[fname] = f
	end

	map.name = mapfile
	map.discardedobjects = {}
	map.camera = {
		x = 0, y = 0,
		w = love.graphics.getWidth(), h = love.graphics.getHeight(),
		scale = 1,
		set = camera_set,
		zoom = camera_zoom
	}
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
				local textfont = object.properties.textfont
				if textfont then
					levity.fonts:load(textfont)
				end

				Object.setLayer(object, layer)
			end

			layer.visible = visible
			layer.offsetx = offsetx
			layer.offsety = offsety
			layer.properties = properties
			layer.draworder = draworder
		end
	end

	initPhysics(map)

	if map.properties.staticsounds then
		levity.bank:load(map.properties.staticsounds, "static")
	end
	if map.properties.streamsounds then
		levity.bank:load(map.properties.streamsounds, "stream")
	end

	if map.properties.overlaymap then
		map.overlaymap = newMap(map.properties.overlaymap)
		map.overlaymap.canvas = nil
	end

	return map
end

return newMap
