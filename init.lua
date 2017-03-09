love.filesystem.setRequirePath(
	"levity/pl/lua/?.lua;"..
	"levity/pl/lua/?/init.lua;"..
	love.filesystem.getRequirePath())

require("pl.strict").module("_G", _G)

local audio = require "levity.audio"
local text = require "levity.text"
local stats = require "levity.stats"

local Map = require "levity.map"

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

function levity:setNextMap(nextmapfile, nextmapdata)
	self.nextmapfile = nextmapfile
	self.nextmapdata = nextmapdata or {}
end

function levity:loadNextMap()
	love.audio.stop()

	self.mapfile = self.nextmapfile
	self.nextmapfile = nil

	if self.map then
		self.map:destroy()
	end
	self.bank = audio.newBank()
	self.fonts = text.newFonts()
	self.stats = stats.newStats()
	self.map = nil
	collectgarbage()

	self.map = Map(self.mapfile)
	self.map:initScripts()

	self.maxdt = 1/16
	self.timescale = 1
	collectgarbage()
end

function levity:update(dt)
	dt = math.min(dt, self.maxdt)
	dt = dt*self.timescale

	self.map:update(dt)

	if self.map.paused then
		self.bank:update(0)
	else
		self.bank:update(dt)
	end

	collectgarbage("step", 1)

	self.stats:update(dt)
end

function levity:draw()
	love.graphics.clear(0, 0, 0)
	if self.nextmapfile then
		return
	end

	local canvas = self.map.canvas
	love.graphics.setCanvas(canvas)
	love.graphics.clear(0, 0, 0, 1, canvas)
	self.map:draw()

	love.graphics.setCanvas()
	local scale = self.map.camera.scale
	local intscale = math.min(math.floor(scale), MaxIntScale)
	local canvasscale = scale / intscale
	love.graphics.draw(canvas,
				love.graphics.getWidth()*.5,
				love.graphics.getHeight()*.5,
				0, canvasscale, canvasscale,
				canvas:getWidth()*.5,
				canvas:getHeight()*.5)

	if self.drawbodies then
		local cx, cy = self.map.camera.x, self.map.camera.y
		local cw, ch = self.map.camera.w, self.map.camera.h
		love.graphics.push()
		love.graphics.scale(scale, scale)
		love.graphics.translate(-cx, -cy)
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
		love.graphics.pop()
	end

	self.stats:draw()
end

function levity:screenToCamera(x, y)
	local scale = self.map.camera.scale
	return	(x - love.graphics.getWidth() *.5)/scale + self.map.camera.w*.5,
		(y - love.graphics.getHeight()*.5)/scale + self.map.camera.h*.5
end

local NoFirstMapMessage =
"First map not set. In main.lua call levity:setNextMap to set the first map"

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

	love.graphics.setNewFont(18)
	love.physics.setMeter(64)

	assert(levity.nextmapfile, NoFirstMapMessage)
	love.joystick.loadGamepadMappings("levity/gamecontrollerdb.txt")
	levity:loadNextMap()
end

function love.keypressed(key, u)
	levity.map:broadcast("keypressed", key, u)
	levity.map:broadcast("keypressed_"..key, u)
end

function love.keyreleased(key, u)
	levity.map:broadcast("keyreleased", key, u)
	levity.map:broadcast("keyreleased_"..key, u)
end

function love.touchpressed(touch, x, y, dx, dy, pressure)
	levity.map:broadcast("touchpressed", touch, x, y)
end

function love.touchmoved(touch, x, y, dx, dy, pressure)
	levity.map:broadcast("touchmoved", touch, x, y, dx, dy)
end

function love.touchreleased(touch, x, y, dx, dy, pressure)
	levity.map:broadcast("touchreleased", touch, x, y, dx, dy)
end

function love.joystickaxis(joystick, axis, value)
	levity.map:broadcast("joystickaxis", joystick, axis, value)
end

function love.joystickpressed(joystick, button)
	levity.map:broadcast("joystickpressed", joystick, button)
end

function love.joystickreleased(joystick, button)
	levity.map:broadcast("joystickreleased", joystick, button)
end

function love.gamepadaxis(joystick, axis, value)
	levity.map:broadcast("gamepadaxis", joystick, axis, value)
end

function love.gamepadpressed(joystick, button)
	levity.map:broadcast("gamepadpressed", joystick, button)
end

function love.gamepadreleased(joystick, button)
	levity.map:broadcast("gamepadreleased", joystick, button)
end

function love.mousepressed(x, y, button, istouch)
	if istouch then
		return
	end
	levity.map:broadcast("mousepressed", x, y, button, istouch)
end

function love.mousemoved(x, y, dx, dy, istouch)
	if istouch then
		return
	end
	levity.map:broadcast("mousemoved", x, y, dx, dy)
end

function love.mousereleased(x, y, button, istouch)
	if istouch then
		return
	end
	levity.map:broadcast("mousereleased", x, y, button, istouch)
end

function love.wheelmoved(x, y)
	levity.map:broadcast("wheelmoved", x, y)
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

	if levity.nextmapfile then
		levity.map:broadcast("nextMap",
			levity.nextmapfile, levity.nextmapdata)
		levity:loadNextMap()
	end
end

function love.draw()
	levity:draw()
end

function love.quit()
end

return levity
