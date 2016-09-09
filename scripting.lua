-- @module scripting

require "levity.class"

local Machine = class(function(self)
	self.scripts = {}
	self.logs = {}
	self.classes = {}
end)

function Machine:requireScript(name)
	local scriptclass = self.classes[name]
	if not scriptclass then
		scriptclass = love.filesystem.load(name..".lua")()
		self.classes[name] = scriptclass
	end
	return scriptclass
end

--- Start a new instance of a script
-- @param id A key by which to reference the script instance
-- @param name Name of script
-- @return The new script instance
function Machine:newScript(id, name, ...)
	local script
	if name then
		local scriptclass = self:requireScript(name)
		script = scriptclass(id, ...)
		self.scripts[id] = script
	end
	return script
end

--- Destroy a script instance
-- @param id The key for identifying the instance
function Machine:destroyScript(id)
	self.scripts[id] = nil
	self.logs[id] = nil
end

function Machine:call(id, event, ...)
	local script = self.scripts[id]
	if script then
		if script[event] then
			local log = self.logs[id]
			if log then
				log[#log + 1] = { event, ... }
			end
			return script[event](script, ...)
		end
	end
end

function Machine:broadcast(event, ...)
	for id, script in pairs(self.scripts) do
		if script[event] then
			local log = self.logs[id]
			if log then
				log[#log + 1] = { event, ... }
			end
			script[event](script, ...)
		end
	end
end

function Machine:startLog(id)
	self.logs[id] = {}
end

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
