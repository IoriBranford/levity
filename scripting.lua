-- @module scripting

require "levity.class"

local Machine = class(function(self)
	self.scripts = {}
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
	if id then
		self.scripts[id] = nil
	end
end

function Machine:call(id, event, ...)
	local script = self.scripts[id]
	if script then
		if script[event] then
			return script[event](script, ...)
		end
	end
end

function Machine:broadcast(event, ...)
	for _, script in pairs(self.scripts) do
		if script[event] then
			script[event](script, ...)
		end
	end
end

local scripting = {
	newMachine = Machine
}

return scripting
