local levity

local pairs = pairs
local ipairs = ipairs
local tonumber = tonumber

local math_abs = math.abs
local math_rad = math.rad
local math_min = math.min
local math_max = math.max
local math_cos = math.cos
local math_sin = math.sin

local love_graphics_draw = love.graphics.draw
local love_graphics_printf = love.graphics.printf
local love_graphics_setColor = love.graphics.setColor
local love_graphics_getColor = love.graphics.getColor
local love_physics_newBody = love.physics.newBody
local love_physics_newFixture = love.physics.newFixture

local maputil = require "levity.maputil"
local maputil_setObjectDefaultProperties = maputil.setObjectDefaultProperties

local scripting = require "levity.scripting"
local Scripts_send = scripting.newMachine.send
local Scripts_newScript = scripting.newMachine.newScript

local Tiles = require "levity.tiles"
local Tiles_getGidFlip = Tiles.getGidFlip
local Tiles_getUnflippedGid = Tiles.getUnflippedGid

--- @table DynamicObject
-- @field body
-- @field layer
-- @field tile Can be different from gid while animating
-- @field animation
-- @field anitime in milliseconds
-- @field anitimescale
-- @field aniframe
-- @see Object

local Object = {}
Object.__index = Object
function Object.__lt(object1, object2)
	local dy = object1.y - object2.y
	return dy < 0 or (dy == 0 and object1.id < object2.id)
end

local function addFixture(body, shape, object)
	local fixture = love_physics_newFixture(body, shape)
	fixture:setSensor(object.properties.sensor == true)
	fixture:setUserData({
		id = object.id,
		object = object,
		properties = object.properties
	})

	local collisionrules = levity.collisionrules
	local category = object.properties.category
	if category and collisionrules then
		if type(category) == "string" then
			category = levity.collisionrules["Category_"..category]
		end
		fixture:setCategory(category)
	end

	return fixture
end

local function addTileFixture(object, shapeobj, tileset)
	local tilewidth = tileset.tilewidth
	local tileheight = tileset.tileheight

	local shapecx = shapeobj.x + shapeobj.width*.5
	local shapecy = -tileheight + shapeobj.y + shapeobj.height*.5

	local flipx, flipy = Tiles_getGidFlip(object.gid)
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
		shape = love.physics.newRectangleShape(shapecx, shapecy,
			shapeobj.width, shapeobj.height)
	elseif shapeobj.shape == "ellipse" then
		shape = love.physics.newCircleShape(shapecx, shapecy,
			(shapeobj.width + shapeobj.height) * .25)
	end

	local fixture = addFixture(object.body, shape, shapeobj)

	if shapeobj.name ~= "" then
		local bodyud = object.body:getUserData()
		if not bodyud.fixtures then
			bodyud.fixtures = {}
		end
		bodyud.fixtures[shapeobj.name] = fixture
	end
end

function Object.setGid(object, gid, map, animated, bodytype, applyfixtures)
	local newtile = map.tiles[Tiles_getUnflippedGid(gid)]
	local newtileset = map.tilesets[newtile.tileset]
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

	local body = object.body
	if body then
		if applyfixtures then
			for _, fixture in pairs(body:getFixtureList()) do
				fixture:destroy()
			end
			body:getUserData().fixtures = nil
		end
		if bodytype and bodytype ~= body:getType() then
			body:setType(bodytype)
		end
	else
		body = love.physics.newBody(levity.world,
						object.x, object.y, bodytype)
		body:setAngle(math_rad(object.rotation))
		body:setUserData({
			id = object.id,
			object = object,
			properties = object.properties,
			fixtures = nil
		})
		object.body = body
	end

	local objectgroup = object.tile.objectGroup
	if applyfixtures and objectgroup then
		local objects = objectgroup.objects
		for i = 1, #objects do
			local shapeobj = objects[i]
			if shapeobj.properties.collidable == true then
				addTileFixture(object, shapeobj, newtileset)
			end
		end
	end
end
local Object_setGid = Object.setGid

local function removeObject(objects, object)
	for i, o in pairs(objects) do
		if o == object then
			table.remove(objects, i)
			return
		end
	end
end

function Object.setLayer(object, layer)
	local oldlayer = object.layer
	if oldlayer == layer then
		return
	end

	if oldlayer then
		removeObject(oldlayer.objects, object)
		if oldlayer.spriteobjects then
			if object.gid or object.text then
				removeObject(oldlayer.spriteobjects, object)
			end
		end
	end

	if layer then
		table.insert(layer.objects, object)
		if object.gid or object.text then
			table.insert(layer.spriteobjects, object)
		end
	end
	object.layer = layer
end
local Object_setLayer = Object.setLayer

function Object.init(object, layer, map)
	levity = levity or require "levity"
	object = setmetatable(object, Object)

	if object.visible == nil then
		object.visible = true
	end
	object.rotation = object.rotation or 0
	local properties = object.properties or {}
	object.properties = properties

	if map.objecttypes then
		maputil_setObjectDefaultProperties(object, map.objecttypes)
	end

	local id = object.id or map:newObjectId()
	object.id = id

	local bodytype = properties.static and "static" or "dynamic"

	Object_setLayer(object, layer)

	if object.gid then
		Object_setGid(object, object.gid, map, true, bodytype)
	else
		local angle = math_rad(object.rotation)
		local body = love_physics_newBody(levity.world,
							object.x, object.y,
							bodytype)
		object.body = body

		body:setAngle(angle)
		local userdata = {
			id = id,
			object = object,
			properties = properties
		}
		body:setUserData(userdata)

		local collidable =
			properties.collidable == true or
			layer.properties.collidable == true

		if collidable then
			local shape = nil
			if object.shape == "rectangle" then
				shape = love.physics.newRectangleShape(
					object.width * .5, object.height * .5,
					object.width, object.height)
			elseif object.shape == "ellipse" then
				-- workaround for worldcenter always matching position
				-- in this case, for some reason
				local halfw, halfh = object.width*.5, object.height*.5
				local cos = math_cos(angle)
				local sin = math_sin(angle)
				object.x, object.y =
					object.x + halfw*cos - halfh*sin,
					object.y + halfw*sin + halfh*cos
				shape = love.physics.newCircleShape(0, 0,
					(object.width + object.height) * .25)
			elseif object.shape == "polyline" or object.shape == "polygon" then
				local points = {}
				local poly = object.polygon or object.polyline
				for _, point in ipairs(poly) do
					-- sti converts them to world points
					table.insert(points, point.x - object.x)
					table.insert(points, point.y - object.y)
				end
				shape = love.physics.newChainShape(object.polygon, points)
			end

			if shape then
				addFixture(body, shape, object)
			end
		end
	end

	map.objects[id] = object
	Scripts_newScript(levity.scripts, id, properties.script, object)
end

function Object.updateAnimation(object, dt, map, scripts)
	local animation = object.animation

	local advanceframe = false
	local looped = false
	local anitime = object.anitime
	local aniframe = object.aniframe
	anitime = anitime + dt * 1000 * object.anitimescale
	while anitime > (animation[aniframe].duration) do
		advanceframe = true
		anitime  = anitime - (animation[aniframe].duration)
		aniframe = aniframe + 1
		if aniframe > #animation then
			looped = true
			aniframe = 1
		end
	end
	object.anitime = anitime
	object.aniframe = aniframe

	if advanceframe then
		local tileid = (animation[aniframe].tileid)
		object.tile = map:getTile(object.tile.tileset, tileid)
	end

	if looped then
		Scripts_send(scripts, object.id, "loopedAnimation")
	end
end

function Object.isOnCamera(object, camera)
	local camw = camera.w
	local camh = camera.h
	local camcx = camera.x + camw*.5
	local camcy = camera.y + camh*.5
	local layer = object.layer

	return not (math_abs(layer.offsetx + object.x - camcx) > camw
			or math_abs(layer.offsety + object.y - camcy) > camh)
end

function Object.draw(object, map)
	local left = object.x
	local top = object.y
	local right = left + (object.width or 0)
	local bottom = top + (object.height or 0)
	local tile = object.tile
	if tile then
		local tilesets = map.tilesets
		local tileset = tilesets[tile.tileset]
		local tw = tileset.tilewidth
		local th = tileset.tileheight
		local x = left
		local y = top
		local offset = tile.offset
		local ox = -offset.x
		local oy = -offset.y + th
		local sx, sy = 1, 1
		local flipx, flipy = Tiles_getGidFlip(object.gid)
		if flipx then
			ox = tw - ox
			sx = -1
		end
		if flipy then
			oy = th - oy
			sy = -1
		end
		left = x - ox
		top = y - oy
		right = left + tw
		bottom = top + th

		love_graphics_draw(tileset.image, tile.quad, x, y,
			object.rotation, sx, sy, ox, oy)
	elseif object.body then
		local body = object.body
		for j, fixture in ipairs(body:getFixtureList()) do
			local l, t, r, b = fixture:getBoundingBox()
			left = math_min(left, l)
			top = math_min(top, t)
			right = math_max(right, r)
			bottom = math_max(bottom, b)

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

	local text = object.text
	if text then
		local properties = object.properties
		local textfont = properties.textfont
		local textfontsize = properties.textfontsize
		if textfont then
			levity = levity or require "levity" --TEMP
			textfont = levity.fonts:use(textfont, textfontsize)
		end

		local textalign = object.halign or "left"
		local textcolor = object.color or properties.textcolor
		local r0,g0,b0,a0
		if textcolor then
			r0,g0,b0,a0 = love_graphics_getColor()
			local a,r,g,b = 255, 255, 255, 255
			if type(textcolor) == "string" then
				a,r,g,b = textcolor:match("#(%x%x)(%x%x)(%x%x)(%x%x)")
				r = tonumber("0x"..r)
				g = tonumber("0x"..g)
				b = tonumber("0x"..b)
				a = tonumber("0x"..a)
			elseif type(textcolor) == "table" then
				r, g, b, a = textcolor[1], textcolor[2],
					textcolor[3], textcolor[4] or a
			end
			love_graphics_setColor(r, g, b, a)
		end

		local offsety = 0
		local valign = object.valign
		if valign then
			offsety = object.height - textfont:getHeight()
			if valign == "center" then
				offsety = offsety / 2
			end
		end
		love_graphics_printf(text, left, top + offsety, right - left,
					textalign)--, object.rotation)

		if textcolor then
			love_graphics_setColor(r0, g0, b0, a0)
		end
	end
end

return Object
