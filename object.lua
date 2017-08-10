local levity
local maputil = require "levity.maputil"
local Tiles = require "levity.tiles"

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
	local fixture = love.physics.newFixture(body, shape)
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

function Object.init(object, layer, map)
	levity = levity or require "levity"
	object = setmetatable(object, Object)

	if object.visible == nil then
		object.visible = true
	end
	object.rotation = object.rotation or 0
	object.properties = object.properties or {}
	if map.objecttypes then
		maputil.setObjectDefaultProperties(object, map.objecttypes)
	end

	if not object.id then
		object.id = map:newObjectId()
	end

	local bodytype = object.properties.static and "static" or "dynamic"

	Object.setLayer(object, layer)

	if object.gid then
		object:setGid(object.gid, map, true, bodytype)
	else
		local angle = math.rad(object.rotation)
		object.body = love.physics.newBody(levity.world,
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
				local cos = math.cos(angle)
				local sin = math.sin(angle)
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
				addFixture(object.body, shape, object)
			end
		end
	end

	map.objects[object.id] = object
	levity.scripts:newScript(object.id, object.properties.script, object)
end

local function addTileFixture(object, shapeobj, tileset)
	local tilewidth = tileset.tilewidth
	local tileheight = tileset.tileheight

	local shapecx = shapeobj.x + shapeobj.width*.5
	local shapecy = -tileheight + shapeobj.y + shapeobj.height*.5

	local flipx, flipy = Tiles.getGidFlip(object.gid)
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
	local newtile = map.tiles[Tiles.getUnflippedGid(gid)]
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

	if object.body then
		if applyfixtures then
			for _, fixture in pairs(object.body:getFixtureList()) do
				fixture:destroy()
			end
			object.body:getUserData().fixtures = nil
		end
		if bodytype and bodytype ~= object.body:getType() then
			object.body:setType(bodytype)
		end
	else
		object.body = love.physics.newBody(levity.world,
						object.x, object.y, bodytype)
		object.body:setAngle(math.rad(object.rotation))
		object.body:setUserData({
			id = object.id,
			object = object,
			properties = object.properties,
			fixtures = nil
		})
	end

	local objectgroup = object.tile.objectGroup
	if applyfixtures and objectgroup then
		for i, shapeobj in ipairs(objectgroup.objects) do
			if shapeobj.properties.collidable == true then
				addTileFixture(object, shapeobj, newtileset)
			end
		end
	end
end

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

function Object.updateAnimation(object, dt, map, scripts)
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
		object.tile = map:getTile(object.tile.tileset, tileid)
	end

	if looped then
		scripts:send(object.id, "loopedAnimation")
	end
end

function Object.isOnCamera(object, camera)
	local camw = camera.w
	local camh = camera.h
	local camcx = camera.x + camw*.5
	local camcy = camera.y + camh*.5
	local layer = object.layer

	return not (math.abs(layer.offsetx + object.x - camcx) > camw
			or math.abs(layer.offsety + object.y - camcy) > camh)
end

function Object.draw(object, map)
	local left = object.x
	local top = object.y
	local right = left + (object.width or 0)
	local bottom = top + (object.height or 0)
	if object.tile then
		local tile = object.tile
		local tilesets = map.tilesets
		local tileset = tilesets[tile.tileset]
		local x = object.x
		local y = object.y
		local ox = -tile.offset.x
		local oy = -tile.offset.y + tileset.tileheight
		local sx, sy = 1, 1
		local flipx, flipy = Tiles.getGidFlip(object.gid)
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
		local textfontsize = object.properties.textfontsize
		if textfont then
			levity = levity or require "levity" --TEMP
			levity.fonts:use(textfont, textfontsize)
		end

		local textalign = object.properties.textalign or "center"
		local textcolor = object.properties.textcolor
		local r0,g0,b0,a0
		if textcolor then
			r0,g0,b0,a0 = love.graphics.getColor()
			local a,r,g,b = textcolor:match("#(%x%x)(%x%x)(%x%x)(%x%x)")
			love.graphics.setColor(
						tonumber("0x"..r),
						tonumber("0x"..g),
						tonumber("0x"..b),
						tonumber("0x"..a))
		end

		love.graphics.printf(text, left, top, right - left,
					textalign)--, object.rotation)

		if textcolor then
			love.graphics.setColor(r0, g0, b0, a0)
		end
	end
end

return Object
