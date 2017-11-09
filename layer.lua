local pairs = pairs
local table_sort = table.sort
local table_insert = table.insert

local love_graphics_draw = love.graphics.draw

local Object = require "levity.object"
local Object_init = Object.init
local Object_updateAnimation = Object.updateAnimation
local Object___lt = Object.__lt
local Object_isOnCamera = Object.isOnCamera
local Object_draw = Object.draw

local scripting = require "levity.scripting"
local Scripts_send = scripting.newMachine.send

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
			Object_init(newobjects[i], layer, map)
		end
		for i = i0, i1 do
			Scripts_send(scripts, newobjects[i].id, "initQuery")
		end

		i0 = i1 + 1
		i1 = #newobjects

		assert(i1 <= LayerMaxNewObjects, LayerAddedTooManyObjectsMessage)
	end

	for i = #newobjects, 1, -1 do
		newobjects[i] = nil
	end

	for _, object in pairs(layer.spriteobjects) do
		local body = object.body
		if body then
			object.x = (body:getX())
			object.y = (body:getY())
			object.rotation = body:getAngle()
		end

		if object.animation then
			Object_updateAnimation(object, dt, map, scripts)
		end
	end

	if layer.visible and layer.draworder == "topdown" then
		table_sort(layer.spriteobjects, Object___lt)
	end
end

function Layer.draw(layer, map, camera, scripts)
	local spriteobjects = layer.spriteobjects
	for i = 1, #spriteobjects do
		local object = spriteobjects[i]
		if object.visible and Object_isOnCamera(object, camera) then
			local id = object.id
			if scripts then
				Scripts_send(scripts, id, "beginDraw")
			end
			Object_draw(object, map)
			if scripts then
				Scripts_send(scripts, id, "endDraw")
			end
		end
	end
end

function Layer.drawImage(layer, map, camera)
	if layer.image then
		love_graphics_draw(layer.image)
	end
end

function Layer.drawBatches(layer, map, camera)
	for _, batch in pairs(layer.batches) do
		love_graphics_draw(batch)
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
	local spriteobjects = {}
	layer.spriteobjects = spriteobjects
	if layer.objects then
		if layer.draworder == "topdown" then
			table_sort(layer.objects, Object___lt)
		end
		for _, object in pairs(layer.objects) do
			if object.gid or object.text then
				table_insert(spriteobjects, object)
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
