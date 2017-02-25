-- @module scripting

require "levity.class"

local Machine = class(function(self)
	self.eventscripts = {}
	self.logs = {}
	self.classes = {}
end)

--- Get a script class, loading it if not loaded already
-- @name of the class (not file name or path)
-- @return The script class
--function Machine:requireScript(name)
--	local scriptclass = self.classes[name]
--	if not scriptclass then
--		scriptclass = love.filesystem.load(name..".lua")()
--		self.classes[name] = scriptclass
--	end
--	return scriptclass
--end

--- Clean up all script classes
function Machine:unrequireAll()
	for name, _ in pairs(self.classes) do
		package.loaded[name] = nil
	end
end

--- Make a script start responding to a type of event
-- @param script
-- @param id of script
-- @param event Type of event
-- @param func Response function
function Machine:scriptAddEventFunc(script, id, event, func)
	if not self.eventscripts[event] then
		self.eventscripts[event] = {}
	end

	self.eventscripts[event][id] = script
	script[event] = func
end

--- Make a script stop responding to a type of event
-- @param script
-- @param id of script
-- @param event Type of event
function Machine:scriptRemoveEventFunc(script, id, event)
	if not self.eventscripts[event] then
		return
	end

	self.eventscripts[event][id] = nil
	script[event] = nil
end

--- Start a new instance of a script
-- @param id A key by which to reference the script instance
-- @param name Name of script class
-- @return The new script instance
function Machine:newScript(id, name, ...)
	local script
	if name then
		local scriptclass = require(name)
			--self:requireScript(name)
		self.classes[name] = scriptclass
		script = scriptclass(id, ...)

		for event, func in pairs(scriptclass) do
			if type(func) == "function" then
				if not self.eventscripts[event] then
					self.eventscripts[event] = {}
				end
				self.eventscripts[event][id] = script
			end
		end
	end
	return script
end

--- Destroy a script instance
-- @param id The key for identifying the instance
function Machine:destroyScript(id)
	for event, scripts in pairs(self.eventscripts) do
		scripts[id] = nil
	end
	self.logs[id] = nil
end

--- Send event to one script
-- @param id of script
-- @param event Type of event
-- @param ... Additional params
-- @return Whatever the script returns
function Machine:call(id, event, ...)
	local scripts = self.eventscripts[event]
	if not scripts then
		return
	end

	local script = scripts[id]
	if script then
		--assert(script[event], "No function "..event.." in script "..id)
		local log = self.logs[id]
		if log then
			log[#log + 1] = { event, ... }
		end
		return script[event](script, ...)
	end
end

--- Send event to all interested scripts
-- @param event Type of event
-- @param ... Additional params
function Machine:broadcast(event, ...)
	local scripts = self.eventscripts[event]
	if not scripts then
		return
	end

	for id, script in pairs(scripts) do
		--assert(script[event], "No function "..event.." in script "..id)
		local log = self.logs[id]
		if log then
			log[#log + 1] = { event, ... }
		end
		script[event](script, ...)
	end
end

--- Start logging events for a script
-- @param id of script
function Machine:startLog(id)
	self.logs[id] = {}
end

--- Print all events logged so far
function Machine:printLogs()
	for id, log in pairs(self.logs) do
		for i = 1, #log, 1 do
			print(unpack(log[i]))
		end
		if #log > 0 then
			print("--")
		end
	end
end

--- Delete all events logged so far
function Machine:clearLogs()
	for id, log in pairs(self.logs) do
		for i = #log, 1, -1 do
			log[i] = nil
		end
	end
end

local scripting = {
	newMachine = Machine
}

return scripting
