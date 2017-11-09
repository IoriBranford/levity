love.filesystem.setRequirePath(
	"levity/pl/lua/?.lua;"..
	"levity/pl/lua/?/init.lua;"..
	love.filesystem.getRequirePath())

require("pl.strict").module("_G", _G)
class = require "pl.class"

local collectgarbage = collectgarbage

local love_graphics_getFont = love.graphics.getFont
local love_graphics_setNewFont = love.graphics.setNewFont
local love_graphics_clear = love.graphics.clear
local love_graphics_printf = love.graphics.printf
local love_graphics_getWidth = love.graphics.getWidth
local love_graphics_getHeight = love.graphics.getHeight

local audio = require "levity.audio"
local Bank_update = audio.newBank.update

local text = require "levity.text"
local stats = require "levity.stats"

local scripting = require "levity.scripting"
local Scripts_broadcast = scripting.newMachine.broadcast
local Scripts_send = scripting.newMachine.send
local Scripts_destroyIdScripts = scripting.newMachine.destroyIdScripts
local Scripts_clearLogs = scripting.newMachine.clearLogs
local Scripts_printLogs = scripting.newMachine.printLogs

local sti = require "levity.sti.sti"

local Map = require "levity.map"

local profile -- = require "levity.profile"

require "levity.xcoroutine"
require "levity.xmath"

---
-- @field map
-- @field camera
-- @field scripts
-- @field world
-- @field collisionrules
-- @field discardedobjects
-- @field bank
-- @field fonts
-- @field prefs
-- @field stats
-- @field timescale
-- @field maxdt
-- @field movetimer Time left until next move
-- @field movedt Time between each move
-- @field nextmapfile Will load and switch to this map on the next frame
-- @field nextmapdata
-- @table levity

local levity = {
	prefs = require "levity.prefs"
}
local levity_scripts

function levity:setNextMap(nextmapfile, nextmapdata)
	self.nextmapfile = nextmapfile
	self.nextmapdata = nextmapdata
end

local function collisionEvent(event, fixture, ...)
	local ud = fixture:getBody():getUserData()
	local id = ud and ud.id
	if id then
		Scripts_send(levity_scripts, id, event, fixture, ...)
	end
end

local function initPhysics(self)
	self.world = love.physics.newWorld(0, self.map.properties.gravity or 0)

	local function beginContact(fixture1, fixture2, contact)
		collisionEvent("beginContact", fixture1, fixture2, contact)
		collisionEvent("beginContact", fixture2, fixture1, contact)
	end

	local function endContact(fixture1, fixture2, contact)
		collisionEvent("endContact", fixture1, fixture2, contact)
		collisionEvent("endContact", fixture2, fixture1, contact)
	end

	local function preSolve(fixture1, fixture2, contact)
		collisionEvent("preSolve", fixture1, fixture2, contact)
		collisionEvent("preSolve", fixture2, fixture1, contact)
	end

	local function postSolve(fixture1, fixture2, contact,
				normal1, tangent1, normal2, tangent2)
		collisionEvent("postSolve", fixture1, fixture2, contact,
				normal1, tangent1, normal2, tangent2)
		collisionEvent("postSolve", fixture2, fixture1, contact,
				normal1, tangent1, normal2, tangent2)
	end

	self.world:setCallbacks(beginContact, endContact, preSolve, postSolve)

	self.map:box2d_init(self.world)

	for _, fixture in pairs(self.map.box2d_collision.body:getFixtureList()) do
		local fixturedata = fixture:getUserData()
		local fixtureproperties = fixturedata.properties
		local category = fixtureproperties.category

		if category then
			if type(category) == "string" then
				category = self.collisionrules["Category_"..category]
			end
			fixture:setCategory(category)
		end
	end
end

local function camera_set(camera, cx, cy, w, h)
	if w then
		camera.w = w
	end
	if h then
		camera.h = h
	end
	if w or h then
		camera:updateScale()
	end
	camera.x = (cx - camera.w * .5)
	camera.y = (cy - camera.h * .5)
end

local function camera_updateScale(camera)
	local r = levity.prefs.rotation
	local cosr = math.abs(math.cos(r))
	local sinr = math.abs(math.sin(r))
	local gw = love_graphics_getWidth()
	local gh = love_graphics_getHeight()
	local sw = gw*cosr + gh*sinr
	local sh = gh*cosr + gw*sinr
	camera.scale = math.min(sw/camera.w, sh/camera.h)
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

	if self.world then
		self.world:setCallbacks(nil, nil, nil, nil)
		for _, body in pairs(self.world:getBodyList()) do
			for _, fixture in pairs(body:getFixtureList()) do
				fixture:setUserData(nil)
			end
			body:setUserData(nil)
			body:destroy()
		end
		self.world:destroy()
	end

	if self.map then
		for _, object in pairs(self.map.objects) do
			object.body = nil
		end
		self:cleanupObjects(self.map.objects)
		sti:flush()
	end

	scripting.unloadScripts()
	scripting.endScriptLoading()

	self.bank = audio.newBank()
	self.fonts = text.newFonts()
	self.stats = stats.newStats()
	self.map = nil
	self.discardedobjects = {}
	self.camera = {
		x = 0, y = 0,
		w = love_graphics_getWidth(), h = love.graphics.getHeight(),
		scale = 1,
		r = 0,
		set = camera_set,
		zoom = camera_zoom,
		updateScale = camera_updateScale,
	}

	collectgarbage()

	self.map = Map(self.mapfile)
	self.map:loadFonts(self.fonts)
	self.map:loadSounds(self.bank)
	self.scripts = scripting.newMachine()
	levity_scripts = self.scripts

	initPhysics(self)

	scripting.beginScriptLoading()
	self.map:initScripts(levity_scripts)

	self.map:windowResized(love_graphics_getWidth(),
				love_graphics_getHeight(), self.camera)
	-- After initScripts because script is where camera size is set.

	self.maxdt = 1/16
	self.timescale = 1
	self.movetimer = 0
	self.movedt = 1/60
	collectgarbage()
end

function levity:discardObject(id)
	self.discardedobjects[id] = self.map.objects[id]
end

function levity:cleanupObjects(discardedobjects)
	self.map:cleanupObjects(discardedobjects)

	for id, _ in pairs(discardedobjects) do
		Scripts_destroyIdScripts(levity_scripts, id)
		discardedobjects[id] = nil
	end
end
local levity_cleanupObjects = levity.cleanupObjects

function levity:screenToCamera(x, y)
	local scale = self.camera.scale
	return	(x - love_graphics_getWidth() *.5)/scale + self.camera.w*.5,
		(y - love_graphics_getHeight()*.5)/scale + self.camera.h*.5
end

function levity:timerCorrectRoundingError(timer, time)
	local diff = math.abs(timer - time)
	if diff < self.movedt*.5 then
		timer = time
	end
	return timer
end

local NoFirstMapMessage =
"First map not set. In main.lua call levity:setNextMap to set the first map"

local Usage = {
	Desc =	"Levity 2D game engine\n",
	Version="  --version				Print LOVE version\n",
	Fused =	"  --fused				Force running in fused mode\n",
	Game =	"  <game>	(string)		Game assets location\n",
	Debug =	"  -debug				Debug in Zerobrane Studio\n",
	Prefs = [[
  --rotation	(number default 0)	Screen orientation in degrees clockwise
  --drawstats				Draw performance stats
  --drawbodies				Draw physical bodies
]],
	Map =	"  <map>	(string default %s)	Map file to start\n"
}

function love.load()
	if profile then
		profile.hookall()
		profile.start()
	end

	local version, err = love.filesystem.read("version")
	levity.version = version and ("ver "..version)

	local lapp = require "pl.lapp"
	lapp.slack = true

	assert(levity.nextmapfile, NoFirstMapMessage)

	local options = Usage.Desc..Usage.Version..Usage.Fused
	if not love.filesystem.isFused() then
		options = options .. Usage.Game
	end
	options = options .. Usage.Debug..Usage.Prefs
	options = options .. string.format(Usage.Map, levity.nextmapfile)

	local args = lapp (options)

	if args.debug then
		require("mobdebug").start()
		require("mobdebug").off()
	end

	if args.map then
		-- When fused we expect <map>,
		-- but if fused mode is fake we get <game> and <map>
		-- Also handles invalid <map> by falling back to default
		if not love.filesystem.exists(args.map) then
			args.map = args[1] or levity.nextmapfile
		end

		levity:setNextMap(args.map)
	end

	local prefs = levity.prefs
	prefs.init()
	prefs.rotation = math.rad(args.rotation)
	prefs.drawbodies = args.drawbodies
	prefs.drawstats = args.drawstats

	love_graphics_setNewFont(18)
	love.physics.setMeter(64)

	love.joystick.loadGamepadMappings("levity/gamecontrollerdb.txt")
	levity:loadNextMap()
end

function love.keypressed(key, u)
	Scripts_broadcast(levity_scripts, "keypressed", key, u)
	Scripts_broadcast(levity_scripts, "keypressed_"..key, u)
end

function love.keyreleased(key, u)
	Scripts_broadcast(levity_scripts, "keyreleased", key, u)
	Scripts_broadcast(levity_scripts, "keyreleased_"..key, u)
end

function love.touchpressed(touch, x, y, dx, dy, pressure)
	Scripts_broadcast(levity_scripts, "touchpressed", touch, x, y)
end

function love.touchmoved(touch, x, y, dx, dy, pressure)
	Scripts_broadcast(levity_scripts, "touchmoved", touch, x, y, dx, dy)
end

function love.touchreleased(touch, x, y, dx, dy, pressure)
	Scripts_broadcast(levity_scripts, "touchreleased", touch, x, y, dx, dy)
end

function love.joystickaxis(joystick, axis, value)
	Scripts_broadcast(levity_scripts, "joystickaxis", joystick, axis, value)
end

function love.joystickhat(joystick, hat, value)
	Scripts_broadcast(levity_scripts, "joystickhat", joystick, hat, value)
end

function love.joystickpressed(joystick, button)
	Scripts_broadcast(levity_scripts, "joystickpressed", joystick, button)
end

function love.joystickreleased(joystick, button)
	Scripts_broadcast(levity_scripts, "joystickreleased", joystick, button)
end

function love.gamepadaxis(joystick, axis, value)
	Scripts_broadcast(levity_scripts, "gamepadaxis", joystick, axis, value)
end

function love.gamepadpressed(joystick, button)
	Scripts_broadcast(levity_scripts, "gamepadpressed", joystick, button)
end

function love.gamepadreleased(joystick, button)
	Scripts_broadcast(levity_scripts, "gamepadreleased", joystick, button)
end

function love.mousepressed(x, y, button, istouch)
	if istouch then
		return
	end
	Scripts_broadcast(levity_scripts, "mousepressed", x, y, button, istouch)
end

function love.mousemoved(x, y, dx, dy, istouch)
	if istouch then
		return
	end
	Scripts_broadcast(levity_scripts, "mousemoved", x, y, dx, dy)
end

function love.mousereleased(x, y, button, istouch)
	if istouch then
		return
	end
	Scripts_broadcast(levity_scripts, "mousereleased", x, y, button, istouch)
end

function love.wheelmoved(x, y)
	Scripts_broadcast(levity_scripts, "wheelmoved", x, y)
end

function love.resize(w, h)
	levity.map:windowResized(w, h, levity.camera)
end

function love.update(dt)
	local map = levity.map
	local bank = levity.bank
	local world = levity.world
	local movedt = levity.movedt
	local timescale = levity.timescale
	local discardedobjects = levity.discardedobjects

	local movetimer = levity.movetimer
	while movetimer <= 0 do
		Scripts_clearLogs(levity_scripts)

		local movedt = movedt * timescale
		if map.paused then
		else
			Scripts_broadcast(levity_scripts, "beginMove", movedt)
			world:update(movedt)
			Scripts_broadcast(levity_scripts, "endMove", movedt)
			map:update(movedt, levity_scripts)
		end

		Scripts_printLogs(levity_scripts)

		levity_cleanupObjects(levity, discardedobjects)

		if map.paused then
			Bank_update(bank, 0)
		else
			Bank_update(bank, movedt)
		end

		movetimer = movetimer + movedt
	end

	collectgarbage("step", 1)

	if levity.prefs.drawstats then
		levity.stats:update(dt)
	end

	dt = math.min(dt, levity.maxdt)

	movetimer = movetimer - dt
	levity.movetimer = movetimer

	if levity.nextmapfile then
		Scripts_broadcast(levity_scripts, "nextMap",
			levity.nextmapfile, levity.nextmapdata)
		levity:loadNextMap()
	end
end

function love.draw()
	love_graphics_clear(0, 0, 0)
	if levity.nextmapfile then
		return
	end

	levity.map:draw(levity.camera, levity_scripts,
		levity.prefs.drawbodies and levity.world)

	if levity.prefs.drawstats then
		levity.stats:draw()
	end

	if levity.version then
		local font = love_graphics_getFont()
		local gw = love_graphics_getWidth()
		local gh = love_graphics_getHeight()
		local y = gh - font:getHeight()
		love_graphics_printf(levity.version, 0, y, gw, "right")
	end
end

function love.quit()
	if profile then
		love.filesystem.write("profile.txt", profile.report("time", 50))
	end
end

return levity
