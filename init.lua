love.filesystem.setRequirePath(
	"levity/pl/lua/?.lua;"..
	"levity/pl/lua/?/init.lua;"..
	love.filesystem.getRequirePath())

require "levity.xcoroutine"
require "levity.xmath"
require "levity.class"

local maputil = require "levity.maputil"
local scripting = require "levity.scripting"
local audio = require "levity.audio"
local text = require "levity.text"
local stats = require "levity.stats"

local bit = require "bit"
local sti = require "sti.sti"

local FlipXBit = 0x80000000
local FlipYBit = 0x40000000

local MaxIntScale = 4

--- @table levity
-- @field machine
-- @field world
-- @field map
-- @field bank
-- @field fonts
-- @field camera
-- @field stats
-- @field timescale
-- @field maxdt
-- @field discardedobjects
-- @field drawbodies
-- @field mappaused
-- @field nextmapfile Will load and switch to this map on the next frame
-- @field nextmapdata

local levity = {}

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

local function dynamicObject_updateAnimation(object, dt)
	local animation = object.animation

	local advanceframe = false
	local looped = false
	object.anitime = object.anitime + dt * 1000 * object.anitimescale
	while object.anitime > (animation[object.aniframe].duration) do
		advanceframe = true
		object.anitime  = object.anitime -
		(animation[object.aniframe].duration)
		object.aniframe = object.aniframe + 1
		if object.aniframe > #animation then
			looped = true
			object.aniframe = 1
		end
	end

	if advanceframe then
		local tileid = (animation[object.aniframe].tileid)
		object.tile = levity:getMapTile(object.tile.tileset, tileid)
	end

	if looped then
		levity.machine:call(object.id, "loopedAnimation")
	end
end

local function dynamicObjectLayer_addObject(self, object)
	self.newobjects[#self.newobjects + 1] = object
end

local LayerMaxNewObjects = 256
local LayerAddedTooManyObjectsMessage = 
[[Tried to add too many (]]..LayerMaxNewObjects..[[) objects at a time to one
layer. Avoid recursive object creation in object init functions.]]

local function objectIsAbove(object1, object2)
	return object1.y < object2.y
end

local function dynamicObjectLayer_update(self, dt)
	local numnewobj = #self.newobjects
	for i = 1, numnewobj do
		levity:initObject(self.newobjects[i], self)
		numnewobj = #self.newobjects
		assert(numnewobj <= LayerMaxNewObjects,
			LayerAddedTooManyObjectsMessage)
	end

	for i = 1, #self.newobjects do
		self.newobjects[i] = nil
	end

	for _, object in pairs(self.spriteobjects) do
		local body = object.body
		if body then
			object.x = (body:getX())
			object.y = (body:getY())
			object.rotation = body:getAngle()
		end

		if object.animation then
			dynamicObject_updateAnimation(object, dt)
		end
	end

	if self.draworder == "topdown" then
		table.sort(self.spriteobjects, objectIsAbove)
	end
end

local function dynamicObjectLayer_draw(self)
	local machine = levity.machine
	local camw = levity.camera.w
	local camh = levity.camera.h
	local camcx = levity.camera.x + camw*.5
	local camcy = levity.camera.y + camh*.5
	local tilesets = levity.map.tilesets
	local fonts = levity.fonts

	local function draw(object)
		if object.visible == false then
			return
		end

		if math.abs(self.offsetx + object.x - camcx) > camw or
		math.abs(self.offsety + object.y - camcy) > camh then
			return
		end

		machine:call(object.id, "beginDraw")

		local left = object.x
		local top = object.y
		local right = left + (object.width or 0)
		local bottom = top + (object.height or 0)
		if object.tile then
			local tile = object.tile
			local tileset = tilesets[tile.tileset]
			local x = object.x
			local y = object.y
			local ox = -tile.offset.x
			local oy = -tile.offset.y + tileset.tileheight
			local sx, sy = 1, 1
			local flipx, flipy = levity:getGidFlip(object.gid)
			if flipx then
				ox = tileset.tilewidth - ox
				sx = -1
			end
			if flipy then
				oy = tileset.tileheight - oy
				sy = -1
			end
			left = x - ox
			top = y - oy
			right = left + tileset.tilewidth
			bottom = top + tileset.tileheight

			love.graphics.draw(tileset.image, tile.quad, x, y,
				object.rotation, sx, sy, ox, oy)
		elseif object.body then
			local body = object.body
			for j, fixture in ipairs(body:getFixtureList()) do
				local l, t, r, b = fixture:getBoundingBox()
				left = math.min(left, l)
				top = math.min(top, t)
				right = math.max(right, r)
				bottom = math.max(bottom, b)

				local shape = fixture:getShape()
				if shape:getType() == "circle" then
					local x, y = body:getWorldPoint(
						shape:getPoint())
					love.graphics.circle("line", x, y,
						shape:getRadius())
				elseif shape:getType() == "polygon" then
					love.graphics.polygon("line",
					body:getWorldPoints(shape:getPoints()))
				elseif shape:getType() == "chain" then
					love.graphics.line(
					body:getWorldPoints(shape:getPoints()))
				end
			end
		end

		local text = object.properties.text
		if text then
			local textfont = object.properties.textfont
			if textfont then
				fonts:use(textfont)
			end

			local textalign = object.properties.textalign or "center"

			love.graphics.printf(text, left, top, right - left,
						textalign)--, object.rotation)
		end

		machine:call(object.id, "endDraw")
	end

	machine:call(self.name, "beginDraw")
	love.graphics.push()
	love.graphics.translate(self.offsetx, self.offsety)
	for _, object in ipairs(self.spriteobjects) do
		draw(object)
	end
	love.graphics.pop()
	machine:call(self.name, "endDraw")
end

function levity:setNextMap(nextmapfile, nextmapdata)
	self.nextmapfile = nextmapfile
	self.nextmapdata = nextmapdata or {}
end

--- @table DynamicLayer
-- @field type "dynamiclayer"
-- @field newobjects
-- @field objects
-- @field spriteobjects
-- @field addObject dynamicObjectLayer_addObject
-- @field update dynamicObjectLayer_update
-- @field draw dynamicObjectLayer_draw
-- @see ObjectLayer

function levity:loadNextMap()
	love.audio.stop()
	assert(self.nextmapfile, "Next map not set. In main.lua call levity:setNextMap to set the first map")
	self.mapfile = self.nextmapfile

	if self.machine then
		self.machine:unrequireAll()
	end
	self.machine = scripting.newMachine()

	if self.world then
		self.world:destroy()
	end
	self.world = nil
	self.map = nil
	self.bank = audio.newBank()
	self.fonts = text.newFonts()
	self.camera = {
		x = 0, y = 0,
		w = love.graphics.getWidth(), h = love.graphics.getHeight(),
		scale = 1,
		set = camera_set,
		zoom = camera_zoom
	}
	self.stats = stats.newStats()
	self.nextmapfile = nil
	self.discardedobjects = {}
	collectgarbage()

	self:initPhysics()

	self.map = sti(self.mapfile, {"box2d"})

	self.map.objecttypes = maputil.loadObjectTypesFile("objecttypes.xml")
	if self.map.objecttypes then
		maputil.setObjectsDefaultProperties(self.map.objects,
							self.map.objecttypes)
	end

	local width = self.map.width * self.map.tilewidth
	local height = self.map.height * self.map.tileheight

	if self.map.properties.staticsounds then
		self.bank:load(self.map.properties.staticsounds, "static")
	end
	if self.map.properties.streamsounds then
		self.bank:load(self.map.properties.streamsounds, "stream")
	end
	if self.map.properties.gravity then
		self.world:setGravity(0, self.map.properties.gravity)
	end

	for _, tileset in ipairs(self.map.tilesets) do
		self.map.tilesets[tileset.name] = tileset

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
				self.map.tiles[commonanimationtilegid]

			commonanimation = commonanimationtile.animation

			for i = tileset.firstgid, lastgid do
				local tile = self.map.tiles[i]
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
				self.map.tiles[commoncollisiontilegid]

			commoncollision = commoncollisiontile.objectGroup

			for i = tileset.firstgid, lastgid do
				local tile = self.map.tiles[i]
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

	for l = #self.map.layers, 1, -1 do
		local layer = self.map.layers[l]
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
			self.map:removeLayer(l)

			layer = self:addDynamicLayer(name, l)

			layer.offsetx = offsetx
			layer.offsety = offsety
			layer.properties = properties
			layer.draworder = draworder

			if self.map.properties.delayinitobjects then
				for _, object in pairs(objects) do
					self:setObjectLayer(object, layer)
				end
			else
				for _, object in pairs(objects) do
					self:initObject(object, layer)
				end
			end
		end

		self.machine:newScript(layer.name, layer.properties.script)
	end

	self.map:box2d_init(self.world)

	self.machine:newScript(self.mapfile, self.map.properties.script)

	local intscale = math.min(math.floor(self.camera.scale), MaxIntScale)
	self.map:resize(self.camera.w * intscale,
			self.camera.h * intscale)
	self.map.canvas:setFilter("linear", "linear")
	collectgarbage()

	self.mappaused = false
	self.maxdt = 1/16
	self.timescale = 1
	return self.map
end

local function collisionEvent(event, fixture, ...)
	local ud = fixture:getBody():getUserData()
	if ud then
		local id = ud.id
		if id then
			levity.machine:call(id, event, fixture, ...)
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

function levity:initPhysics()
	love.physics.setMeter(64)
	self.world = love.physics.newWorld(0, 0)
	self.world:setCallbacks(beginContact, endContact, preSolve, postSolve)
end

function levity:getTileGid(tilesetid, row, column)
	local tileset = self.map.tilesets[tilesetid]
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

function levity:getTileRowName(gid)
	gid = self:getUnflippedGid(gid)
	local tileset = self.map.tilesets[self.map.tiles[gid].tileset]
	local tileid = gid - tileset.firstgid
	local row = tileid / tileset.tilecolumns
	return tileset.rownames[row] or math.floor(row)
end

function levity:getTileColumnName(gid)
	gid = self:getUnflippedGid(gid)
	local tileset = self.map.tilesets[self.map.tiles[gid].tileset]
	local tileid = gid - tileset.firstgid
	local column = tileid % tileset.tilecolumns
	return tileset.columnnames[column] or column
end

function levity:getMapTileset(tilesetid)
	return self.map.tilesets[tilesetid]
end

function levity:getMapTileGid(tilesetid, tileid)
	return tileid + self.map.tilesets[tilesetid].firstgid
end

function levity:getMapTile(tilesetid, tileid)
	return self.map.tiles[tileid + self.map.tilesets[tilesetid].firstgid]
end

function levity:getTilesetImage(tilesetid)
	return self.map.tilesets[tilesetid].image
end

--- Convert list of map-specific gids to map-agnostic names
-- @param gids list
-- @return List of name tables: { {tileset, row, column}, ... }
function levity:tileGidsToNames(gids)
	if not gids then
		return nil
	end
	local names = {}
	for _, gid in ipairs(gids) do
		local tileset = self.map.tilesets[self.map.tiles[gid].tileset]

		names[#names + 1] = {
			tileset = tileset.name,
			row = self:getTileRowName(gid),
			column = self:getTileColumnName(gid)
		}
	end
	return names
end

--- Convert name tables to gids for current map
-- @param names list returned by tileGidsToNames
-- @return List of tile gids
function levity:tileNamesToGids(names)
	if not names then
		return nil
	end
	local gids = {}
	for _, name in ipairs(names) do
		gids[#gids + 1] = self:getTileGid(name.tileset,
						name.row, name.column)
	end
	return gids
end

function levity:updateTilesetAnimations(tileset, dt)
	if type(tileset) ~= "table" then
		tileset = self.map.tilesets[tileset]
	end
	self:updateTileAnimations(tileset.firstgid, tileset.tilecount, dt)
end

function levity:updateTileAnimations(firstgid, numtiles, dt)
	local tiles = self.map.tiles
	local tilesets = self.map.tilesets
	local tileinstances = self.map.tileInstances

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
--- @table DynamicObject
-- @field body
-- @field layer
-- @field tile Can be different from gid while animating
-- @field animation
-- @field anitime in milliseconds
-- @field anitimescale
-- @field aniframe
-- @see Object

function levity:setObjectGid(object, gid, animated, bodytype, applyfixtures)
	local newtile = self.map.tiles[self:getUnflippedGid(gid)]
	local newtileset = self.map.tilesets[newtile.tileset]
	if applyfixtures == nil then
		applyfixtures = object.body == nil or
			newtile.tileset ~= object.tile.tileset or
			(newtileset.properties.commoncollision == nil and
			gid ~= object.gid)
	end

	if animated == nil then
		animated = true
	end
	object.gid = gid
	object.tile = newtile

	if animated and object.tile.animation then
		object.animation = object.tile.animation
		object.anitime = 0
		object.anitimescale = 1
		object.aniframe = 1
	else
		object.animation = nil
		object.anitime = nil
		object.anitimescale = nil
		object.aniframe = nil
	end

	if object.body then
		if applyfixtures then
			for _, fixture in pairs(object.body:getFixtureList()) do
				fixture:destroy()
			end
			object.body:getUserData().fixtures = nil
		end
		if bodytype then
			object.body:setType(bodytype)
		end
	else
		object.body = love.physics.newBody(self.world,
						object.x, object.y, bodytype)
		object.body:setAngle(math.rad(object.rotation))
		object.body:setUserData({
			id = object.id,
			object = object,
			properties = object.properties,
			fixtures = nil
		})
	end

	local bodyud = object.body:getUserData()

	local tileset = self.map.tilesets[object.tile.tileset]
	local tilewidth = tileset.tilewidth
	local tileheight = tileset.tileheight

	local function addFixture(shapeobj)
		local shapecx = shapeobj.x + shapeobj.width*.5
		local shapecy = -tileheight + shapeobj.y + shapeobj.height*.5

		local flipx, flipy = self:getGidFlip(gid)
		if flipx then
			local ox = object.tile.offset.x
			shapecx = 2 * ox + tilewidth - shapecx
		end
		if flipy then
			local oy = object.tile.offset.y
			shapecy = 2 * oy + tileheight - shapecy
		end

		local shape
		if shapeobj.shape == "rectangle" then
			shape = love.physics.newRectangleShape(
				shapecx, shapecy,
				shapeobj.width, shapeobj.height)
		elseif shapeobj.shape == "ellipse" then
			shape = love.physics.newCircleShape(
				shapecx, shapecy,
				(shapeobj.width + shapeobj.height) * .25)
		end

		if shape then
			local fixture = love.physics.newFixture(
						object.body, shape)
			fixture:setSensor(shapeobj.properties.sensor == true)
			local fixtureud = {
				--id = shapeobj.id,
				--need Tiled issue fixed:
				--github.com/bjorn/tiled/issues/1052
				object = shapeobj,
				properties = shapeobj.properties
			}
			fixture:setUserData(fixtureud)

			if shapeobj.name ~= "" then
				if not bodyud.fixtures then
					bodyud.fixtures = {}
				end
				bodyud.fixtures[shapeobj.name] = fixture
			end
		end
	end

	local objectgroup = object.tile.objectGroup
	if applyfixtures and objectgroup then
		for i, shapeobj in ipairs(objectgroup.objects) do
			if shapeobj.properties.collidable == true then
				addFixture(shapeobj)
			end
		end
	end
end

function levity:newObjectId()
	local id = self.map.nextobjectid
	self.map.nextobjectid = self.map.nextobjectid + 1
	return id
end

function levity:initObject(object, layer)
	if object.visible == nil then
		object.visible = true
	end
	object.rotation = object.rotation or 0
	object.properties = object.properties or {}
	if self.map.objecttypes then
		maputil.setObjectDefaultProperties(object, self.map.objecttypes)
	end

	if not object.id then
		object.id = self:newObjectId()
	end

	local bodytype
	if not object.properties.static then
		bodytype = "dynamic"
	end

	local shape = nil
	if object.gid then
		self:setObjectGid(object, object.gid, true, bodytype)
	else
		local angle = math.rad(object.rotation)
		if object.shape == "rectangle" then
			shape = love.physics.newRectangleShape(
				object.width * .5, object.height * .5,
				object.width, object.height)
		elseif object.shape == "ellipse" then
			-- workaround for worldcenter always matching position
			-- in this case, for some reason
			local halfw, halfh = object.width*.5, object.height*.5
			local cos = math.cos(angle)
			local sin = math.sin(angle)
			object.x, object.y =
				object.x + halfw*cos - halfh*sin,
				object.y + halfw*sin + halfh*cos
			shape = love.physics.newCircleShape(0, 0,
				(object.width + object.height) * .25)
		elseif object.shape == "polyline" then
			local points = {}
			for _, point in ipairs(object.polyline) do
				-- sti converts them to world points
				table.insert(points, point.x - object.x)
				table.insert(points, point.y - object.y)
			end
			shape = love.physics.newChainShape(
				object.properties.loop or false, points)
		end

		object.body = love.physics.newBody(self.world,
							object.x, object.y,
							bodytype)
		object.body:setAngle(angle)
		local userdata = {
			id = object.id,
			object = object,
			properties = object.properties
		}
		object.body:setUserData(userdata)

		local collidable =
			object.properties.collidable == true or
			layer.properties.collidable == true
		if shape and collidable then
			local fixture = love.physics.newFixture(object.body, shape)
			fixture:setUserData(userdata)
			fixture:setSensor(object.properties.sensor == true)
		end
	end

	local textfont = object.properties.textfont
	if textfont then
		self.fonts:load(textfont)
	end

	self:setObjectLayer(object, layer)
	self.map.objects[object.id] = object
	self.machine:newScript(object.id, object.properties.script)
end

function levity:addDynamicLayer(name, i)
	local layer = self.map:addCustomLayer(name, i)
	layer.type = "dynamiclayer"
	layer.newobjects = {}
	-- why newobjects is necessary:
	-- http://www.lua.org/manual/5.1/manual.html#pdf-next
	-- "The behavior of next [and therefore pairs] is undefined if, during
	-- the traversal, you assign any value to a non-existent field in the
	-- table [i.e. a new object]."
	layer.objects = {}
	layer.spriteobjects = {}
	layer.addObject = dynamicObjectLayer_addObject
	layer.update = dynamicObjectLayer_update
	layer.draw = dynamicObjectLayer_draw
	layer.offsetx = 0
	layer.offsety = 0
	return layer
end

function levity:setObjectLayer(object, layer)
	local function removeObject(objects)
		for i, o in pairs(objects) do
			if o == object then
				table.remove(objects, i)
				return
			end
		end
	end

	local oldlayer = object.layer
	if oldlayer == layer then
		return
	end

	if oldlayer then
		removeObject(oldlayer.objects, object)
		if oldlayer.spriteobjects then
			if object.gid or object.properties.text then
				removeObject(oldlayer.spriteobjects, object)
			end
		end
	end

	if layer then
		table.insert(layer.objects, object)
		if object.gid or object.properties.text then
			table.insert(layer.spriteobjects, object)
		end
	end
	object.layer = layer
end

function levity:getGidFlip(gid)
	if not gid then
		return false, false
	end
	return bit.band(gid, FlipXBit) ~= 0,
		bit.band(gid, FlipYBit) ~= 0
end

function levity:getUnflippedGid(gid)
	if not gid then
		return 0
	end

	return bit.band(gid, bit.bnot(bit.bor(FlipXBit, FlipYBit)))
end

function levity:setGidFlip(gid, flipx, flipy)
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

function levity:discardObject(id)
	self.discardedobjects[id] = self.map.objects[id]
end

function levity:cleanupObjects()
	for id, object in pairs(self.discardedobjects) do
		self:setObjectLayer(object, nil)

		if object.body then
			object.body:destroy()
		end

		self.machine:destroyScript(id)

		self.map.objects[id] = nil
	end

	for id, _ in pairs(self.discardedobjects) do
		self.discardedobjects[id] = nil
	end
end

function levity:update(dt)
	dt = math.min(dt, self.maxdt)
	dt = dt*self.timescale

	self.machine:clearLogs()

	if self.mappaused then
		self.bank:update(0)
	else
		self.machine:broadcast("beginMove", dt)
		self.world:update(dt)
		self.machine:broadcast("endMove", dt)

		for _, layer in ipairs(self.map.layers) do
			layer:update(dt)
		end
		self.machine:printLogs()

		self.bank:update(dt)
	end

	self:cleanupObjects()
	collectgarbage("step", 1)

	self.stats:update(dt)

	if self.nextmapfile then
		levity.machine:broadcast("nextMap",
			self.nextmapfile, self.nextmapdata)
		self:loadNextMap()
	end
end

function levity:draw()
	love.graphics.clear(0, 0, 0)
	if self.nextmapfile then
		return
	end

	local cx, cy = self.camera.x, self.camera.y
	local cw, ch = self.camera.w, self.camera.h
	local ccx, ccy = cx+cw*.5, cy+ch*.5

	local scale = self.camera.scale
	local intscale = math.min(math.floor(scale), MaxIntScale)

	--self.map:setDrawRange(cx, cy, cw, ch)

	local canvas = self.map.canvas
	love.graphics.setCanvas(canvas)
	love.graphics.clear(0, 0, 0, 1, canvas)
	love.graphics.push()
	love.graphics.translate(-(cx * intscale),
				-(cy * intscale))
	love.graphics.scale(intscale, intscale)
	self.machine:call(self.mapfile, "beginDraw")
	for _, layer in ipairs(self.map.layers) do
		if layer.visible and layer.opacity > 0 then
			self.map:drawLayer(layer)
		end
	end
	self.machine:call(self.mapfile, "endDraw")
	love.graphics.pop()
	love.graphics.setCanvas()

	local canvasscale = scale / intscale
	love.graphics.draw(canvas,
				love.graphics.getWidth()*.5,
				love.graphics.getHeight()*.5,
				0, canvasscale, canvasscale,
				canvas:getWidth()*.5,
				canvas:getHeight()*.5)

	love.graphics.push()
	love.graphics.scale(scale, scale)
	love.graphics.translate(-cx, -cy)
	if self.drawbodies then
		local fixtures = {}
		self.world:queryBoundingBox(cx, cy, cx+cw, cy+ch,
		function(fixture)
			table.insert(fixtures, fixture)
			return true
		end)

		for _, fixture in ipairs(fixtures) do
			local body = fixture:getBody()
			love.graphics.circle("line", body:getX(), body:getY(), 2)
			local bodycx, bodycy = body:getWorldCenter()
			love.graphics.line(bodycx - 2, bodycy, bodycx + 2, bodycy)
			love.graphics.line(bodycx, bodycy - 2, bodycx, bodycy + 2)

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
	end
	love.graphics.pop()

	self.stats:draw()
end

function levity:screenToCamera(x, y)
	local scale = self.camera.scale
	return	(x - love.graphics.getWidth() *.5)/scale + self.camera.w*.5,
		(y - love.graphics.getHeight()*.5)/scale + self.camera.h*.5
end

function love.load()
	for a, ar in ipairs(arg) do
		if ar == "-debug" then
			require("mobdebug").start()
			require("mobdebug").off()
		else
			local c1, c2 = ar:find("-map=")
			if c1 == 1 then
				local mapfile = ar:sub(c2+1)
				levity:setNextMap(mapfile)
			end
		end
	end

	love.joystick.loadGamepadMappings("levity/gamecontrollerdb.txt")
	levity:loadNextMap()

	love.graphics.setNewFont(18)
end

function love.keypressed(key, u)
	levity.machine:broadcast("keypressed", key, u)
	levity.machine:broadcast("keypressed_"..key, u)
end

function love.keyreleased(key, u)
	levity.machine:broadcast("keyreleased", key, u)
	levity.machine:broadcast("keyreleased_"..key, u)
end

function love.touchpressed(touch, x, y, dx, dy, pressure)
	levity.machine:broadcast("touchpressed", touch, x, y)
end

function love.touchmoved(touch, x, y, dx, dy, pressure)
	levity.machine:broadcast("touchmoved", touch, x, y, dx, dy)
end

function love.touchreleased(touch, x, y, dx, dy, pressure)
	levity.machine:broadcast("touchreleased", touch, x, y, dx, dy)
end

function love.joystickaxis(joystick, axis, value)
	levity.machine:broadcast("joystickaxis", joystick, axis, value)
end

function love.joystickpressed(joystick, button)
	levity.machine:broadcast("joystickpressed", joystick, button)
end

function love.joystickreleased(joystick, button)
	levity.machine:broadcast("joystickreleased", joystick, button)
end

function love.gamepadaxis(joystick, axis, value)
	levity.machine:broadcast("gamepadaxis", joystick, axis, value)
end

function love.gamepadpressed(joystick, button)
	levity.machine:broadcast("gamepadpressed", joystick, button)
end

function love.gamepadreleased(joystick, button)
	levity.machine:broadcast("gamepadreleased", joystick, button)
end

function love.mousepressed(x, y, button, istouch)
	if istouch then
		return
	end
	levity.machine:broadcast("mousepressed", x, y, button, istouch)
end

function love.mousemoved(x, y, dx, dy, istouch)
	if istouch then
		return
	end
	levity.machine:broadcast("mousemoved", x, y, dx, dy)
end

function love.mousereleased(x, y, button, istouch)
	if istouch then
		return
	end
	levity.machine:broadcast("mousereleased", x, y, button, istouch)
end

function love.wheelmoved(x, y)
	levity.machine:broadcast("wheelmoved", x, y)
end

function love.resize(w, h)
	local camera = levity.camera
	local scale = math.min(w/camera.w, h/camera.h)
	local intscale = math.min(math.floor(scale), MaxIntScale)
	if intscale ~= math.floor(camera.scale) then
		levity.map:resize(camera.w * intscale, camera.h * intscale)
	end
	camera.scale = scale
end

function love.update(dt)
	levity:update(dt)
end

function love.draw()
	levity:draw()
end

function love.quit()
end

return levity
