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
			scripts:send(newobjects[i].id, "initQuery")
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
	local spriteobjects = layer.spriteobjects
	for i = 1, #spriteobjects do
		local object = spriteobjects[i]
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
end

function Layer.drawImage(layer, map, camera)
	if layer.image then
		love.graphics.draw(layer.image)
	end
end

function Layer.drawBatches(layer, map, camera)
	for _, batch in pairs(layer.batches) do
		love.graphics.draw(batch)
	end
end

function Layer.init(layer)
	--TODO: Why doesn't setting metatable work here?
	--setmetatable(layer, Layer)
	for fname, f in pairs(Layer) do
		if fname ~= "__call" then
			layer[fname] = f
		end
	end

	layer.type = "dynamiclayer"
	layer.newobjects = {}
	-- why newobjects is necessary:
	-- http://www.lua.org/manual/5.1/manual.html#pdf-next
	-- "The behavior of next [and therefore pairs] is undefined if, during
	-- the traversal, you assign any value to a non-existent field in the
	-- table [i.e. a new object]."
	layer.spriteobjects = {}
	if layer.objects then
		if layer.draworder == "topdown" then
			table.sort(layer.objects, Object.__lt)
		end
		for _, object in pairs(layer.objects) do
			if object.gid or object.text then
				table.insert(layer.spriteobjects, object)
			end
			object.layer = layer
		end
	end

	layer.objects = layer.objects or {}
	layer.offsetx = layer.offsetx or 0
	layer.offsety = layer.offsety or 0
end

function Layer.__call(_, map, name, i)
	local layer = map:addCustomLayer(name, i)
	Layer.init(layer)
	return layer
end

return Layer
