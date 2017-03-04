local levity
local scripting = require "levity.scripting"
local maputil = require "levity.maputil"
local audio = require "levity.audio"
local text = require "levity.text"
local stats = require "levity.stats"
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

function Map.setNextMap(levity, nextmapfile, nextmapdata)
	levity.nextmapfile = nextmapfile
	levity.nextmapdata = nextmapdata or {}
end

function Map.loadNextMap(levity)
	love.audio.stop()
	assert(levity.nextmapfile, "Next map not set. In main.lua call levity:setNextMap to set the first map")
	levity.mapfile = levity.nextmapfile

	if levity.map then
		if levity.map.scripts then
			levity.map.scripts:unrequireAll()
		end

		if levity.map.world then
			levity.map.world:destroy()
		end
	end
	levity.bank = audio.newBank()
	levity.fonts = text.newFonts()
	levity.stats = stats.newStats()
	levity.nextmapfile = nil
	collectgarbage()

	levity.map = sti(levity.mapfile, {"box2d"})
	levity.map.scripts = scripting.newMachine()
	levity.map.discardedobjects = {}
	levity.map.camera = {
		x = 0, y = 0,
		w = love.graphics.getWidth(), h = love.graphics.getHeight(),
		scale = 1,
		set = camera_set,
		zoom = camera_zoom
	}
	levity:initPhysics()

	levity.map.objecttypes = maputil.loadObjectTypesFile("objecttypes.xml")
	if levity.map.objecttypes then
		maputil.setObjectsDefaultProperties(levity.map.objects,
							levity.map.objecttypes)
	end

	local width = levity.map.width * levity.map.tilewidth
	local height = levity.map.height * levity.map.tileheight

	if levity.map.properties.staticsounds then
		levity.bank:load(levity.map.properties.staticsounds, "static")
	end
	if levity.map.properties.streamsounds then
		levity.bank:load(levity.map.properties.streamsounds, "stream")
	end
	if levity.map.properties.gravity then
		levity.map.world:setGravity(0, levity.map.properties.gravity)
	end

	for _, tileset in ipairs(levity.map.tilesets) do
		levity.map.tilesets[tileset.name] = tileset

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
				levity.map.tiles[commonanimationtilegid]

			commonanimation = commonanimationtile.animation

			for i = tileset.firstgid, lastgid do
				local tile = levity.map.tiles[i]
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
				levity.map.tiles[commoncollisiontilegid]

			commoncollision = commoncollisiontile.objectGroup

			for i = tileset.firstgid, lastgid do
				local tile = levity.map.tiles[i]
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

	for l = #levity.map.layers, 1, -1 do
		local layer = levity.map.layers[l]
		local layerdynamic = not layer.properties.static

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
			levity.map:removeLayer(l)

			layer = levity:addDynamicLayer(name, l)

			layer.offsetx = offsetx
			layer.offsety = offsety
			layer.properties = properties
			layer.draworder = draworder

			if levity.map.properties.delayinitobjects then
				for _, object in pairs(objects) do
					levity:setObjectLayer(object, layer)
				end
			else
				for _, object in pairs(objects) do
					levity:initObject(object, layer)
				end
			end
		end

		levity.map.scripts:newScript(layer.name, layer.properties.script)
	end

	levity.map:box2d_init(levity.map.world)

	levity.map.scripts:newScript(levity.mapfile, levity.map.properties.script)

	local intscale = math.min(math.floor(levity.map.camera.scale), MaxIntScale)
	levity.map:resize(levity.map.camera.w * intscale,
			levity.map.camera.h * intscale)
	levity.map.canvas:setFilter("linear", "linear")
	collectgarbage()

	levity.map.paused = false
	levity.maxdt = 1/16
	levity.timescale = 1
	return levity.map
end

local function collisionEvent(event, fixture, ...)
	local ud = fixture:getBody():getUserData()
	if ud then
		local id = ud.id
		if id then
			levity = require "levity"
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

function Map.initPhysics(levity)
	love.physics.setMeter(64)
	levity.map.world = love.physics.newWorld(0, 0)
	levity.map.world:setCallbacks(beginContact, endContact, preSolve, postSolve)
end

return Map
