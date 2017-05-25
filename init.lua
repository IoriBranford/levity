love.filesystem.setRequirePath(
	"levity/pl/lua/?.lua;"..
	"levity/pl/lua/?/init.lua;"..
	love.filesystem.getRequirePath())

require("pl.strict").module("_G", _G)

local audio = require "levity.audio"
local text = require "levity.text"
local stats = require "levity.stats"
local scripting = require "levity.scripting"
local sti = require "sti.sti"

local Map = require "levity.map"

require "levity.xcoroutine"
require "levity.xmath"
require "levity.class"

--- @table levity
-- @field map
-- @field camera
-- @field scripts
-- @field world
-- @field collisionrules
-- @field discardedobjects
-- @field bank
-- @field fonts
-- @field stats
-- @field timescale
-- @field maxdt
-- @field movetimer Time left until next move
-- @field movedt Time between each move
-- @field drawbodies
-- @field nextmapfile Will load and switch to this map on the next frame
-- @field nextmapdata

local levity = {}

function levity:setNextMap(nextmapfile, nextmapdata)
	self.nextmapfile = nextmapfile
	self.nextmapdata = nextmapdata
end

local function collisionEvent(scripts, event, fixture, ...)
	local ud = fixture:getBody():getUserData()
	if ud then
		local id = ud.id
		if id then
			scripts:send(id, event, fixture, ...)
		end
	end
end

local function initPhysics(self)
	self.world = love.physics.newWorld(0, self.map.properties.gravity or 0)

	local scripts = self.scripts

	local function beginContact(fixture1, fixture2, contact)
		collisionEvent(scripts, "beginContact", fixture1, fixture2, contact)
		collisionEvent(scripts, "beginContact", fixture2, fixture1, contact)
	end

	local function endContact(fixture1, fixture2, contact)
		collisionEvent(scripts, "endContact", fixture1, fixture2, contact)
		collisionEvent(scripts, "endContact", fixture2, fixture1, contact)
	end

	local function preSolve(fixture1, fixture2, contact)
		collisionEvent(scripts, "preSolve", fixture1, fixture2, contact)
		collisionEvent(scripts, "preSolve", fixture2, fixture1, contact)
	end

	local function postSolve(fixture1, fixture2, contact,
				normal1, tangent1, normal2, tangent2)
		collisionEvent(scripts, "postSolve", fixture1, fixture2, contact,
				normal1, tangent1, normal2, tangent2)
		collisionEvent(scripts, "postSolve", fixture2, fixture1, contact,
				normal1, tangent1, normal2, tangent2)
	end

	self.world:setCallbacks(beginContact, endContact, preSolve, postSolve)

	self.map:box2d_init(self.world)
end

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
	camera.x = (cx - camera.w * .5)
	camera.y = (cy - camera.h * .5)
end

local function camera_zoom(camera, vz)
	local aspect = camera.w / camera.h
	camera:set(camera.x - vz*aspect*.5,
		camera.y - vz*.5,
		camera.w + vz*aspect,
		camera.h + vz)
end

function levity:loadNextMap()
	love.audio.stop()

	self.mapfile = self.nextmapfile
	self.nextmapfile = nil

	if self.map and self.scripts then
		self:cleanupObjects(self.map.objects)
		sti:flush()
	end

	if self.world then
		for _, body in pairs(self.world:getBodyList()) do
			for _, fixture in pairs(body:getFixtureList()) do
				fixture:setUserData(nil)
			end
			body:setUserData(nil)
		end
		self.world:setCallbacks(nil, nil, nil, nil)
		self.world:destroy()
	end

	scripting.unloadScripts()

	self.bank = audio.newBank()
	self.fonts = text.newFonts()
	self.stats = stats.newStats()
	self.map = nil
	self.discardedobjects = {}
	self.camera = {
		x = 0, y = 0,
		w = love.graphics.getWidth(), h = love.graphics.getHeight(),
		scale = 1,
		set = camera_set,
		zoom = camera_zoom
	}

	collectgarbage()

	self.map = Map(self.mapfile)
	self.map:loadFonts(self.fonts)
	self.map:loadSounds(self.bank)
	self.scripts = scripting.newMachine()
	initPhysics(self)
	self.map:initScripts(self.scripts)

	self.map:windowResized(love.graphics.getWidth(),
				love.graphics.getHeight(), self.camera)
	-- After initScripts because script is where camera size is set.

	self.maxdt = 1/16
	self.timescale = 1
	self.movetimer = 0
	self.movedt = 1/60
	collectgarbage()
end

function levity:update(dt)
	dt = math.min(dt, self.maxdt)
	--dt = dt*self.timescale

	while self.movetimer <= 0 do
		self.scripts:clearLogs()

		local movedt = self.movedt * self.timescale
		if self.map.paused then
		else
			self.scripts:broadcast("beginMove", movedt)
			self.world:update(movedt)
			self.scripts:broadcast("endMove", movedt)
			self.map:update(movedt, self.scripts)
		end

		self.scripts:printLogs()

		self:cleanupObjects(self.discardedobjects)

		if self.map.paused then
			self.bank:update(0)
		else
			self.bank:update(movedt)
		end

		self.movetimer = self.movetimer + self.movedt
	end

	collectgarbage("step", 1)

	self.stats:update(dt)

	self.movetimer = self.movetimer - dt
end

function levity:discardObject(id)
	self.discardedobjects[id] = self.map.objects[id]
end

function levity:cleanupObjects(discardedobjects)
	local scripts = self.scripts

	self.map:cleanupObjects(discardedobjects)

	for id, _ in pairs(discardedobjects) do
		scripts:destroyIdScripts(id)
		discardedobjects[id] = nil
	end
end

function levity:draw()
	love.graphics.clear(0, 0, 0)
	if self.nextmapfile then
		return
	end

	self.map:draw(self.camera, self.scripts, self.drawbodies and self.world)

	self.stats:draw()
end

function levity:screenToCamera(x, y)
	local scale = self.camera.scale
	return	(x - love.graphics.getWidth() *.5)/scale + self.camera.w*.5,
		(y - love.graphics.getHeight()*.5)/scale + self.camera.h*.5
end

local NoFirstMapMessage =
"First map not set. In main.lua call levity:setNextMap to set the first map"

local Usage = {
	Desc =	"Levity 2D game engine\n",
	Game =	"  <game> (string)			Game location\n",
	Debug =	"  -debug				Debugging in Zerobrane Studio\n",
	Map =	"  <map>	 (string default %s)	Map file to start\n"
}

function love.load()
	local lapp = require "pl.lapp"
	lapp.slack = true

	assert(levity.nextmapfile, NoFirstMapMessage)

	local options = Usage.Desc
	if not love.filesystem.isFused() then
		options = options .. Usage.Game
	end
	options = options .. Usage.Debug
	options = options .. string.format(Usage.Map, levity.nextmapfile)

	local args = lapp (options)

	if args.debug then
		require("mobdebug").start()
		require("mobdebug").off()
	end

	if args.map then
		levity:setNextMap(args.map)
	end

	love.graphics.setNewFont(18)
	love.physics.setMeter(64)

	love.joystick.loadGamepadMappings("levity/gamecontrollerdb.txt")
	levity:loadNextMap()
end

function love.keypressed(key, u)
	levity.scripts:broadcast("keypressed", key, u)
	levity.scripts:broadcast("keypressed_"..key, u)
end

function love.keyreleased(key, u)
	levity.scripts:broadcast("keyreleased", key, u)
	levity.scripts:broadcast("keyreleased_"..key, u)
end

function love.touchpressed(touch, x, y, dx, dy, pressure)
	levity.scripts:broadcast("touchpressed", touch, x, y)
end

function love.touchmoved(touch, x, y, dx, dy, pressure)
	levity.scripts:broadcast("touchmoved", touch, x, y, dx, dy)
end

function love.touchreleased(touch, x, y, dx, dy, pressure)
	levity.scripts:broadcast("touchreleased", touch, x, y, dx, dy)
end

function love.joystickaxis(joystick, axis, value)
	levity.scripts:broadcast("joystickaxis", joystick, axis, value)
end

function love.joystickpressed(joystick, button)
	levity.scripts:broadcast("joystickpressed", joystick, button)
end

function love.joystickreleased(joystick, button)
	levity.scripts:broadcast("joystickreleased", joystick, button)
end

function love.gamepadaxis(joystick, axis, value)
	levity.scripts:broadcast("gamepadaxis", joystick, axis, value)
end

function love.gamepadpressed(joystick, button)
	levity.scripts:broadcast("gamepadpressed", joystick, button)
end

function love.gamepadreleased(joystick, button)
	levity.scripts:broadcast("gamepadreleased", joystick, button)
end

function love.mousepressed(x, y, button, istouch)
	if istouch then
		return
	end
	levity.scripts:broadcast("mousepressed", x, y, button, istouch)
end

function love.mousemoved(x, y, dx, dy, istouch)
	if istouch then
		return
	end
	levity.scripts:broadcast("mousemoved", x, y, dx, dy)
end

function love.mousereleased(x, y, button, istouch)
	if istouch then
		return
	end
	levity.scripts:broadcast("mousereleased", x, y, button, istouch)
end

function love.wheelmoved(x, y)
	levity.scripts:broadcast("wheelmoved", x, y)
end

function love.resize(w, h)
	levity.map:windowResized(w, h, levity.camera)
end

function love.update(dt)
	levity:update(dt)

	if levity.nextmapfile then
		levity.scripts:broadcast("nextMap",
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
