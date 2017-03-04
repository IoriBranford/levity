local Object = require "levity.object"
local Tiles = require "levity.tiles"

--- @table DynamicLayer
-- @field type "dynamiclayer"
-- @field newobjects
-- @field objects
-- @field spriteobjects
-- @field addObject dynamicObjectLayer_addObject
-- @field update dynamicObjectLayer_update
-- @field draw dynamicObjectLayer_draw
-- @field map
-- @see ObjectLayer

local Layer = {}
Layer.__index = Layer

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
		object.tile = object.layer.map:getTile(object.tile.tileset, tileid)
	end

	if looped then
		object.layer.map.scripts:call(object.id, "loopedAnimation")
	end
end

function Layer.addObject(layer, object)
	layer.newobjects[#layer.newobjects + 1] = object
end

local LayerMaxNewObjects = 256
local LayerAddedTooManyObjectsMessage = 
[[Tried to add too many (]]..LayerMaxNewObjects..[[) objects at a time to one
layer. Avoid recursive object creation in object init functions.]]

local function objectIsAbove(object1, object2)
	return object1.y < object2.y
end

function Layer.update(layer, dt)
	local numnewobj = #layer.newobjects
	for i = 1, numnewobj do
		Object.init(layer.newobjects[i], layer)
		numnewobj = #layer.newobjects
		assert(numnewobj <= LayerMaxNewObjects,
			LayerAddedTooManyObjectsMessage)
	end

	for i = 1, #layer.newobjects do
		layer.newobjects[i] = nil
	end

	for _, object in pairs(layer.spriteobjects) do
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

	if layer.draworder == "topdown" then
		table.sort(layer.spriteobjects, objectIsAbove)
	end
end

local levity
function Layer.draw(layer)
	levity = levity or require "levity" --TEMP
	local scripts = layer.map.scripts
	local camw = layer.map.camera.w
	local camh = layer.map.camera.h
	local camcx = layer.map.camera.x + camw*.5
	local camcy = layer.map.camera.y + camh*.5
	local tilesets = layer.map.tilesets
	local fonts = levity.fonts

	local function dynamicObject_draw(object)
		if object.visible == false then
			return
		end

		if math.abs(layer.offsetx + object.x - camcx) > camw or
		math.abs(layer.offsety + object.y - camcy) > camh then
			return
		end

		scripts:call(object.id, "beginDraw")

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
			if textfont then
				fonts:use(textfont)
			end

			local textalign = object.properties.textalign or "center"

			love.graphics.printf(text, left, top, right - left,
						textalign)--, object.rotation)
		end

		scripts:call(object.id, "endDraw")
	end

	scripts:call(layer.name, "beginDraw")
	love.graphics.push()
	love.graphics.translate(layer.offsetx, layer.offsety)
	for _, object in ipairs(layer.spriteobjects) do
		dynamicObject_draw(object)
	end
	love.graphics.pop()
	scripts:call(layer.name, "endDraw")
end

local function newLayer(map, name, i)
	local layer = map:addCustomLayer(name, i)
	--TODO: Why doesn't setting metatable work here?
	--setmetatable(layer, Layer)
	for fname, f in pairs(Layer) do
		layer[fname] = f
	end

	layer.type = "dynamiclayer"
	layer.newobjects = {}
	-- why newobjects is necessary:
	-- http://www.lua.org/manual/5.1/manual.html#pdf-next
	-- "The behavior of next [and therefore pairs] is undefined if, during
	-- the traversal, you assign any value to a non-existent field in the
	-- table [i.e. a new object]."
	layer.objects = {}
	layer.spriteobjects = {}
	layer.offsetx = 0
	layer.offsety = 0
	layer.map = map

	return layer
end

return newLayer
