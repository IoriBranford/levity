local levity
local Layer = require "levity.layer"
local Object = require "levity.object"
local maputil = require "levity.maputil"
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

local function collisionEvent(event, fixture, ...)
	local ud = fixture:getBody():getUserData()
	if ud then
		local id = ud.id
		if id then
			levity.map.scripts:call(id, event, fixture, ...)
		end
	end
end

local function beginContact(fixture1, fixture2, contact)
	collisionEvent("beginContact", fixture1, fixture2, contact)
	collisionEvent("beginContact", fixture2, fixture1, contact)
end

local function endContact(fixture1, fixture2, contact)
	collisionEvent("endContact", fixture1, fixture2, contact)
	collisionEvent("endContact", fixture2, fixture1, contact)
end

local function preSolve(fixture1, fixture2, contact)
	collisionEvent("preSolve", fixture1, fixture2, contact)
	collisionEvent("preSolve", fixture2, fixture1, contact)
end

local function postSolve(fixture1, fixture2, contact,
			normal1, tangent1, normal2, tangent2)
	collisionEvent("postSolve", fixture1, fixture2, contact,
				normal1, tangent1, normal2, tangent2)
	collisionEvent("postSolve", fixture2, fixture1, contact,
				normal1, tangent1, normal2, tangent2)
end

function Map.load(mapfile)
	levity = require "levity" --TEMP

	local map = sti(mapfile, {"box2d"})
	map.discardedobjects = {}
	map.camera = {
		x = 0, y = 0,
		w = love.graphics.getWidth(), h = love.graphics.getHeight(),
		scale = 1,
		set = camera_set,
		zoom = camera_zoom
	}
	love.physics.setMeter(64)
	map.world = love.physics.newWorld(0, 0)
	map.world:setCallbacks(beginContact, endContact, preSolve, postSolve)

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

			layer = Layer.addDynamicLayer(name, l, map)
			for _, object in pairs(objects) do
				Object.setObjectLayer(object, layer)
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
		Object.setObjectLayer(object, nil)

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

return Map
