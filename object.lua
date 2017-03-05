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

function Object.init(object, layer)
	object = setmetatable(object, Object)

	local map = layer.map

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

	local bodytype
	if not object.properties.static then
		bodytype = "dynamic"
	end

	Object.setLayer(object, layer)

	local shape = nil
	if object.gid then
		object:setGid(object.gid, true, bodytype)
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

		object.body = love.physics.newBody(map.world,
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

	map.objects[object.id] = object
	map.scripts:newScript(object.id, object.properties.script, object)
end

function Object.setGid(object, gid, animated, bodytype, applyfixtures)
	local map = object.layer.map
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
		object.body = love.physics.newBody(map.world,
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

	local tileset = map.tilesets[object.tile.tileset]
	local tilewidth = tileset.tilewidth
	local tileheight = tileset.tileheight

	local function addFixture(shapeobj)
		local shapecx = shapeobj.x + shapeobj.width*.5
		local shapecy = -tileheight + shapeobj.y + shapeobj.height*.5

		local flipx, flipy = Tiles.getGidFlip(gid)
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

function Object.setLayer(object, layer)
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

return Object
