local scripting = require "levity.scripting"
local audio = require "levity.audio"
local stats = require "levity.stats"

local bit = require "bit"
local sti = require "sti"

local FlipXBit = 0x80000000
local FlipYBit = 0x40000000

--- @table levity
-- @field machine
-- @field world
-- @field map
-- @field bank
-- @field camera
-- @field stats
-- @field drawbodies
-- @field nextmapfile Will load and switch to this map on the next frame

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
	camera.x = (cx - camera.w / 2)
	camera.y = (cy - camera.h / 2)
end

local function camera_zoom(camera, vz)
	local aspect = camera.w / camera.h
	camera:set(camera.x - vz*aspect/2,
		camera.y - vz/2,
		camera.w + vz*aspect,
		camera.h + vz)
end

local function dynamicObject_updateAnimation(object, dt)
	local animation = object.animation

	local advanceframe = false
	local looped = false
	object.anitime = object.anitime + dt * 1000
	while object.anitime > tonumber(animation[object.aniframe].duration) do
		advanceframe = true
		object.anitime  = object.anitime -
		tonumber(animation[object.aniframe].duration)
		object.aniframe = object.aniframe + 1
		if object.aniframe > #animation then
			looped = true
			object.aniframe = 1
		end
	end

	if advanceframe then
		local tileid = tonumber(animation[object.aniframe].tileid)
		object.tile = levity:getMapTile(object.tile.tileset, tileid)
	end

	if looped then
		levity.machine:call(object.id, "loopedAnimation")
	end
end

local function dynamicObjectLayer_update(self, dt)
	for _, object in pairs(self.drawableobjects) do
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
end

local function dynamicObjectLayer_draw(self)
	local levitymaptilewidth = levity.map.tilewidth
	local camw = levity.camera.w
	local camh = levity.camera.h
	local camcx = levity.camera.x + camw/2
	local camcy = levity.camera.y + camh/2

	local function draw(object)
		if object.visible == false then
			return
		end

		if math.abs(self.offsetx + object.x - camcx) > camw or
		math.abs(self.offsety + object.y - camcy) > camh then
			return
		end

		levity.machine:call(object.id, "beginDraw")

		if object.tile then
			local tile = object.tile
			local ox = -tile.offset.x - levitymaptilewidth
			-- an sti issue
			local oy = -tile.offset.y
			local sx, sy = 1, 1
			local flipx, flipy = levity:getGidFlip(object.gid)
			if flipx then
				ox = ox + object.width
				sx = -sx
			end
			if flipy then
				oy = oy - object.height
				sy = -sy
			end

			love.graphics.draw(
				levity:getTilesetImage(tile.tileset),
				tile.quad,
				object.x, object.y, object.rotation, sx, sy,
				ox, oy)
		elseif object.body then
			local body = object.body
			for j, fixture in ipairs(body:getFixtureList()) do
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
			local textalign = object.properties.textalign
			if not textalign then
				textalign = "center"
			end
			love.graphics.printf(text, object.x, object.y, 
				object.width, textalign, object.rotation)
		end

		levity.machine:call(object.id, "endDraw")
	end

	levity.machine:call(self.name, "beginDraw")
	love.graphics.push()
	love.graphics.translate(self.offsetx, self.offsety)
	for _, object in pairs(self.objects) do
		draw(object)
	end
	love.graphics.pop()
	levity.machine:call(self.name, "endDraw")
end

function levity:setNextMap(nextmapfile)
	self.nextmapfile = nextmapfile
end

--- @table DynamicLayer
-- @field type "dynamiclayer"
-- @field objects
-- @field drawableobjects
-- @field update dynamicObjectLayer_update
-- @field draw dynamicObjectLayer_draw
-- @see ObjectLayer

function levity:loadNextMap()
	love.audio.stop()
	assert(self.nextmapfile, "Next map not set. In main.lua call levity:setNextMap to set the first map")
	self.mapfile = self.nextmapfile

	self.machine = scripting.newMachine()
	self.world = nil
	self.map = nil
	self.bank = audio.newBank()
	self.camera = {
		x = 0, y = 0,
		w = love.graphics.getWidth(), h = love.graphics.getHeight(),
		scale = 1,
		set = camera_set,
		zoom = camera_zoom
	}
	self.stats = stats.newStats()
	self.nextmapfile = nil
	collectgarbage()

	self:initPhysics()

	self.map = sti.new(self.mapfile, {"box2d"})
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

	for i = 1, #self.map.tilesets, 1 do
		local tileset = self.map.tilesets[i]
		self.map.tilesets[tileset.name] = tileset
	end

	for _, tileset in ipairs(self.map.tilesets) do
		local commonanimation = tileset.properties.commonanimation

		if commonanimation then
			local commonanimationtilegid =
				tileset.firstgid + commonanimation
			local commonanimationtile =
				self.map.tiles[commonanimationtilegid]

			commonanimation = commonanimationtile.animation or nil
		end

		local commoncollision = tileset.properties.commoncollision

		if commoncollision then
			local commoncollisiontilegid =
				tileset.firstgid + commoncollision
			local commoncollisiontile =
				self.map.tiles[commoncollisiontilegid]

			commoncollision = commoncollisiontile.objectGroup or nil
		end

		if commonanimation or commoncollision then
			for i = tileset.firstgid, tileset.firstgid + tileset.tilecount - 1, 1 do
				local tile = self.map.tiles[i]

				if commonanimation and not tile.animation then
					tile.animation = {}
					for _, frame in ipairs(commonanimation) do
						local tileid = tile.id + tonumber(frame.tileid)

						table.insert(tile.animation, {
							tileid = tostring(tileid),
							duration = frame.duration
						})
					end
				end

				if commoncollision and not tile.objectGroup then
					tile.objectGroup = commoncollision
				end
			end
		end
	end

	for l = #self.map.layers, 1, -1 do
		local layer = self.map.layers[l]
		local layerdynamic = (layer.properties.dynamic == true)
		if not layerdynamic and layer.objects then
			for _, object in ipairs(layer.objects) do
				layerdynamic = layerdynamic or
					(object.properties.dynamic == true)
				if layerdynamic then
					break
				end
			end
		end

		if layer.objects and layerdynamic then
			local name = layer.name
			local objects = layer.objects
			local offsetx = layer.offsetx
			local offsety = layer.offsety
			local properties = layer.properties
			self.map:removeLayer(l)
			layer = self.map:addCustomLayer(name, l)
			layer.type = "dynamiclayer"
			layer.offsetx = offsetx
			layer.offsety = offsety
			layer.properties = properties
			layer.objects = {}
			layer.drawableobjects = {}
			layer.update = dynamicObjectLayer_update
			layer.draw = dynamicObjectLayer_draw

			for _, object in ipairs(objects) do
				local bodytype
				if layerdynamic
				or (object.properties.dynamic == true) then
					if object.properties.dynamic ~= false
					then
						bodytype = "dynamic"
					end
				end
				self:addObject(object, layer, bodytype)
			end

			self.map:setObjectData(layer)
		end

		self.machine:newScript(layer.name, layer.properties.script)
	end

	self.map:box2d_init(self.world)

	self.machine:newScript(self.mapfile, self.map.properties.script)

	local intscale = math.floor(self.camera.scale)
	self.map:resize(self.camera.w * intscale,
			self.camera.h * intscale)
	self.map.canvas:setFilter("linear", "linear")
	collectgarbage()
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

function levity:getMapTileset(tilesetid)
	return self.map.tilesets[tilesetid]
end

function levity:getMapTileGid(tilesetid, tileid)
	return tileid + self:getMapTileset(tilesetid).firstgid
end

function levity:getMapTile(tilesetid, tileid)
	return self.map.tiles[self:getMapTileGid(tilesetid, tileid)]
end

function levity:getTilesetImage(tilesetid)
	return self.map.tilesets[tilesetid].image
end

--- @table DynamicObject
-- @field body
-- @field layer
-- @field tile Can be different from gid while animating
-- @field animation
-- @field anitime in milliseconds
-- @field aniframe
-- @field destroy = true to destroy at end of update
-- @see Object

function levity:setObjectGid(object, gid, bodytype, layer)
	local newtile = self.map.tiles[self:getUnflippedGid(gid)]
	local newtileset = self.map.tilesets[newtile.tileset]
	local fixtureschanged = object.body == nil or
		newtile.tileset ~= object.tile.tileset or
		(newtileset.properties.commoncollision == nil and
			gid ~= object.gid)

	object.gid = gid
	object.tile = newtile

	if object.tile.animation then
		object.animation = object.tile.animation
		object.anitime = 0
		object.aniframe = 1
	end

	if object.body then
		if fixtureschanged then
			for _, fixture in ipairs(object.body:getFixtureList()) do
				fixture:destroy()
			end
			object.body:getUserData().fixtures = nil
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
		local shapecx = shapeobj.x + shapeobj.width/2
		local shapecy = -tileheight + shapeobj.y + shapeobj.height/2

		local flipx, flipy = self:getGidFlip(gid)
		if flipx then
			local ox = object.tile.offset.x + self.map.tilewidth
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
				(shapeobj.width + shapeobj.height) / 4)
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
	if fixtureschanged and objectgroup then
		for i, shapeobj in ipairs(objectgroup.objects) do
			addFixture(shapeobj)
		end
	end
end

function levity:addObject(object, layer, bodytype)
	if not object.id then
		object.id = self.map.nextobjectid
		self.map.nextobjectid = self.map.nextobjectid + 1
	end

	local shape = nil
	if object.gid then
		self:setObjectGid(object, object.gid, bodytype, layer)
		table.insert(layer.drawableobjects, object)
	else
		if object.shape == "rectangle" then
			shape = love.physics.newRectangleShape(
				object.width / 2, object.height / 2,
				object.width, object.height)
		elseif object.shape == "ellipse" then
			shape = love.physics.newCircleShape(
				object.width / 2, object.height / 2,
				(object.width + object.height) / 4)
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

		object.body = love.physics.newBody(self.world, object.x, object.y, bodytype)
		object.body:setAngle(math.rad(object.rotation))
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

	self.map.objects[object.id] = object
	self.machine:newScript(object.id, object.properties.script)

	table.insert(layer.objects, object)
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

function levity:destroyObjects()
	for _, layer in ipairs(self.map.layers) do
		if layer.type == "dynamiclayer" and layer.objects then
			for o = #layer.objects, 1, -1 do
				local object = layer.objects[o]
				if object.destroy then
					if object.body then
						object.body:destroy()
					end

					if object.id and object.id > 0 then
						self.machine:destroyScript(object.id)
						self.map.objects[object.id] = nil
					end

					table.remove(layer.objects, o)
				end
			end
			for o = #layer.drawableobjects, 1, -1 do
				local object = layer.drawableobjects[o]
				if object.destroy then
					table.remove(layer.drawableobjects, o)
				end
			end
		end
	end
end

function levity:update(dt)
	self.machine:broadcast("beginMove", dt)
	self.world:update(dt)
	self.machine:broadcast("endMove", dt)

	self.map:update(dt)

	self:destroyObjects()
	collectgarbage("step", 1)

	self.stats:update(dt)

	if self.nextmapfile then
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
	local ccx, ccy = cx+cw/2, cy+ch/2

	local scale = self.camera.scale
	local intscale = math.floor(scale)

	self.map:setDrawRange(cx, cy, cw, ch)

	local canvas = self.map.canvas
	love.graphics.setCanvas(canvas)
	love.graphics.clear(0, 0, 0, 1, canvas)
	love.graphics.push()
	love.graphics.translate(math.floor(-cx * intscale),
				math.floor(-cy * intscale))
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
				love.graphics.getWidth()/2,
				love.graphics.getHeight()/2,
				0, canvasscale, canvasscale,
				canvas:getWidth()/2,
				canvas:getHeight()/2)

	love.graphics.push()
	love.graphics.scale(scale, scale)
	love.graphics.translate(-cx, -cy)
	if self.drawbodies then
		for i, body in ipairs(self.world:getBodyList()) do
			if math.abs(body:getX() - ccx) < cw
			and math.abs(body:getY() - ccy) < ch then
				love.graphics.circle("line", body:getX(), body:getY(), 2)
				for j, fixture in ipairs(body:getFixtureList()) do
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
		end
	end
	love.graphics.pop()

	self.stats:draw()
end

function love.load()
	for a, ar in ipairs(arg) do
		if ar == "-debug" then
			require("mobdebug").start()
		else
			local c1, c2 = ar:find("-map=")
			if c1 == 1 then
				local mapfile = ar:sub(c2+1)
				levity:setNextMap(mapfile)
			end
		end
	end

	levity:loadNextMap()

	--love.mouse.setRelativeMode(true)
	love.mouse.setVisible(false)
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
	local intscale = math.floor(scale)
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
