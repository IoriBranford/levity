local Object = require "levity.object"
local Tiles = require "levity.tiles"

--- @table DynamicLayer
-- @field type "dynamiclayer"
-- @field newobjects
-- @field objects
-- @field spriteobjects
-- @see ObjectLayer

local Layer = {}
Layer.__index = Layer

function Layer.addObject(layer, object)
	layer.newobjects[#layer.newobjects + 1] = object
end

local LayerMaxNewObjects = 256
local LayerAddedTooManyObjectsMessage =
[[Tried to add too many (]]..LayerMaxNewObjects..[[) objects at a time to one
layer. Avoid recursive object creation in object init functions.]]

function Layer.update(layer, dt, map, scripts)
	local newobjects = layer.newobjects
	local i0 = 1
	local i1 = #newobjects

	while i0 <= i1 do
		for i = i0, i1 do
			Object.init(newobjects[i], layer, map)
		end
		for i = i0, i1 do
			scripts:send(newobjects[i].id, "start")
		end

		i0 = i1 + 1
		i1 = #layer.newobjects

		assert(i1 <= LayerMaxNewObjects, LayerAddedTooManyObjectsMessage)
	end

	for i = #layer.newobjects, 1, -1 do
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
			object:updateAnimation(dt, map, scripts)
		end
	end

	if layer.visible and layer.draworder == "topdown" then
		table.sort(layer.spriteobjects, Object.__lt)
	end
end

function Layer.draw(layer, map, camera, scripts)
	love.graphics.push()
	love.graphics.translate(layer.offsetx, layer.offsety)
	for _, object in ipairs(layer.spriteobjects) do
		if object.visible and Object.isOnCamera(object, camera) then
			if scripts then
				scripts:send(object.id, "beginDraw")
			end
			Object.draw(object, map)
			if scripts then
				scripts:send(object.id, "endDraw")
			end
		end
	end
	love.graphics.pop()
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

	return layer
end

return newLayer
