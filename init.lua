love.filesystem.setRequirePath(
	"levity/pl/lua/?.lua;"..
	"levity/pl/lua/?/init.lua;"..
	love.filesystem.getRequirePath())

require "levity.xcoroutine"
require "levity.xmath"
require "levity.class"

local MaxIntScale = 4

--- @table levity
-- @field map
-- @field bank
-- @field fonts
-- @field stats
-- @field timescale
-- @field maxdt
-- @field drawbodies
-- @field nextmapfile Will load and switch to this map on the next frame
-- @field nextmapdata

local levity = {}
for _, modulename in pairs({"map", "layer", "object", "tiles"}) do
	for fname, f in pairs(require("levity."..modulename)) do
		levity[fname] = f
	end
end

function levity:update(dt)
	dt = math.min(dt, self.maxdt)
	dt = dt*self.timescale

	self.map.scripts:clearLogs()

	if self.map.paused then
		self.bank:update(0)
	else
		self.map.scripts:broadcast("beginMove", dt)
		self.map.world:update(dt)
		self.map.scripts:broadcast("endMove", dt)

		for _, layer in ipairs(self.map.layers) do
			layer:update(dt)
		end
		self.map.scripts:printLogs()

		self.bank:update(dt)
	end

	self:cleanupObjects()
	collectgarbage("step", 1)

	self.stats:update(dt)

	if self.nextmapfile then
		levity.map.scripts:broadcast("nextMap",
			self.nextmapfile, self.nextmapdata)
		self:loadNextMap()
	end
end

function levity:draw()
	love.graphics.clear(0, 0, 0)
	if self.nextmapfile then
		return
	end

	local cx, cy = self.map.camera.x, self.map.camera.y
	local cw, ch = self.map.camera.w, self.map.camera.h
	local ccx, ccy = cx+cw*.5, cy+ch*.5

	local scale = self.map.camera.scale
	local intscale = math.min(math.floor(scale), MaxIntScale)

	--self.map:setDrawRange(cx, cy, cw, ch)

	local canvas = self.map.canvas
	love.graphics.setCanvas(canvas)
	love.graphics.clear(0, 0, 0, 1, canvas)
	love.graphics.push()
	love.graphics.translate(-(cx * intscale),
				-(cy * intscale))
	love.graphics.scale(intscale, intscale)
	self.map.scripts:call(self.mapfile, "beginDraw")
	for _, layer in ipairs(self.map.layers) do
		if layer.visible and layer.opacity > 0 then
			self.map:drawLayer(layer)
		end
	end
	self.map.scripts:call(self.mapfile, "endDraw")
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
		self.map.world:queryBoundingBox(cx, cy, cx+cw, cy+ch,
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
	local scale = self.map.camera.scale
	return	(x - love.graphics.getWidth() *.5)/scale + self.map.camera.w*.5,
		(y - love.graphics.getHeight()*.5)/scale + self.map.camera.h*.5
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
	levity.map.scripts:broadcast("keypressed", key, u)
	levity.map.scripts:broadcast("keypressed_"..key, u)
end

function love.keyreleased(key, u)
	levity.map.scripts:broadcast("keyreleased", key, u)
	levity.map.scripts:broadcast("keyreleased_"..key, u)
end

function love.touchpressed(touch, x, y, dx, dy, pressure)
	levity.map.scripts:broadcast("touchpressed", touch, x, y)
end

function love.touchmoved(touch, x, y, dx, dy, pressure)
	levity.map.scripts:broadcast("touchmoved", touch, x, y, dx, dy)
end

function love.touchreleased(touch, x, y, dx, dy, pressure)
	levity.map.scripts:broadcast("touchreleased", touch, x, y, dx, dy)
end

function love.joystickaxis(joystick, axis, value)
	levity.map.scripts:broadcast("joystickaxis", joystick, axis, value)
end

function love.joystickpressed(joystick, button)
	levity.map.scripts:broadcast("joystickpressed", joystick, button)
end

function love.joystickreleased(joystick, button)
	levity.map.scripts:broadcast("joystickreleased", joystick, button)
end

function love.gamepadaxis(joystick, axis, value)
	levity.map.scripts:broadcast("gamepadaxis", joystick, axis, value)
end

function love.gamepadpressed(joystick, button)
	levity.map.scripts:broadcast("gamepadpressed", joystick, button)
end

function love.gamepadreleased(joystick, button)
	levity.map.scripts:broadcast("gamepadreleased", joystick, button)
end

function love.mousepressed(x, y, button, istouch)
	if istouch then
		return
	end
	levity.map.scripts:broadcast("mousepressed", x, y, button, istouch)
end

function love.mousemoved(x, y, dx, dy, istouch)
	if istouch then
		return
	end
	levity.map.scripts:broadcast("mousemoved", x, y, dx, dy)
end

function love.mousereleased(x, y, button, istouch)
	if istouch then
		return
	end
	levity.map.scripts:broadcast("mousereleased", x, y, button, istouch)
end

function love.wheelmoved(x, y)
	levity.map.scripts:broadcast("wheelmoved", x, y)
end

function love.resize(w, h)
	local camera = levity.map.camera
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
