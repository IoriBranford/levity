-- @module scripting

local pairs = pairs
local setmetatable = setmetatable

local LockMT = {}

local function broadcast__newindex(t,k,v)
	if v then
		error("Cannot add new script that receives current broadcasting event\n"..
			require("pl.pretty").write(v))
	end
end

local function send__newindex(t,k,v)
	if v then
		error("Cannot add new script for current receiving id\n"..
			require("pl.pretty").write(v))
	end
end

local _alleventsscripts
local _allidsscripts
local _scriptlogs
--local _allclasses

local Machine = class()
function Machine:_init()
	_alleventsscripts = {}
	_allidsscripts = {}
	_scriptlogs = nil
	--_allclasses = {}
end

--- Get a script class, loading it if not loaded already
-- @name of the class (not file name or path)
-- @return The script class
--function Machine:requireScript(name)
--	local scriptclass = _allclasses[name]
--	if not scriptclass then
--		scriptclass = love.filesystem.load(name..".lua")()
--		_allclasses[name] = scriptclass
--	end
--	return scriptclass
--end

--- Make a script start responding to a type of event
-- @param script
-- @param id of script
-- @param event Type of event
-- @param func Response function
function Machine:scriptAddEventFunc(script, id, event, func)
	local eventscripts = _alleventsscripts[event]
	if not eventscripts then
		eventscripts = {}
		_alleventsscripts[event] = eventscripts
	end

	eventscripts[script] = script
	script[event] = func
end

local function Pass()
end

--- Make a script stop responding to a type of event
-- @param script
-- @param id of script
-- @param event Type of event
function Machine:scriptRemoveEventFunc(script, id, event)
	local eventscripts = _alleventsscripts[event]
	if not eventscripts then
		return
	end

	eventscripts[script] = nil
	script[event] = nil		-- clear func in script table
	if script[event] ~= nil then	-- still has func in class metatable
		script[event] = Pass
	end
end

--- Start a new instance of a script
-- @param id A key by which to reference the script instance
-- @param name Name of script class
-- @return The new script instance
function Machine:newScript(id, name, object, ...)
	local script
	if name then
		local scriptclass = require(name)
			--self:requireScript(name)
		--_allclasses[name] = scriptclass
		script = scriptclass(object, ...)

		local idscripts = _allidsscripts[id]
		if not idscripts then
			idscripts = {}
			_allidsscripts[id] = idscripts
		end
		idscripts[script] = script

		local _alleventsscripts = _alleventsscripts
		for event, func in pairs(scriptclass) do
			if type(func) == "function" then
				local eventscripts = _alleventsscripts[event]
				if not eventscripts then
					eventscripts = {}
					_alleventsscripts[event] = eventscripts
				end
				eventscripts[script] = script
			end
		end
	end
	return script
end

--- Destroy a script instance
-- @param id The key for identifying the instance
function Machine:destroyIdScripts(id)
	local idscripts = _allidsscripts[id]
	if not idscripts then
		return
	end

	if _scriptlogs then
		for _, script in pairs(idscripts) do
			_scriptlogs[script] = nil
		end
	end

	for _, script in pairs(idscripts) do
		for _, eventscripts in pairs(_alleventsscripts) do
			eventscripts[script] = nil
		end
	end
	_allidsscripts[id] = nil
end

function Machine:destroyScript(script, id)
	if not script then
		return
	end
	if id then
		local idscripts = _allidsscripts[id]
		if idscripts then
			idscripts[script] = nil
		end
	else
		for _, idscripts in pairs(_allidsscripts) do
			idscripts[script] = nil
		end
	end
	for event, scripts in pairs(_alleventsscripts) do
		scripts[script] = nil
	end
end

function Machine:call(id, event, ...)
	local idscripts = _allidsscripts[id]
	if not idscripts then
		return
	end

	LockMT.__newindex = send__newindex
	setmetatable(idscripts, LockMT)
	for _, script in pairs(idscripts) do
		local func = script[event]
		if func then
			if _scriptlogs then
				local log = _scriptlogs[script]
				if log then
					log[#log + 1] = { event, ... }
				end
			end
			return func(script, ...)
		end
	end
	setmetatable(idscripts, nil)
end

local function log(scripts, event, ...)
	for _, script in pairs(scripts) do
		local log = _scriptlogs[script]
		if log then
			log[#log + 1] = { event, ... }
		end
	end
end

--- Send event to one id's scripts
-- @param id of script
-- @param event Type of event
-- @param ... Additional params
function Machine:send(id, event, ...)
	local idscripts = _allidsscripts[id]
	if not idscripts then
		return
	end

	if _scriptlogs then
		log(idscripts, event, ...)
	end

	LockMT.__newindex = send__newindex
	setmetatable(idscripts, LockMT)
	for _, script in pairs(idscripts) do
		local func = script[event]
		if func then
			func(script, ...)
		end
	end
	setmetatable(idscripts, nil)
end

--- Send event to all interested scripts
-- @param event Type of event
-- @param ... Additional params
function Machine:broadcast(event, ...)
	local eventscripts = _alleventsscripts[event]
	if not eventscripts then
		return
	end

	if _scriptlogs then
		log(idscripts, event, ...)
	end

	LockMT.__newindex = broadcast__newindex
	setmetatable(eventscripts, LockMT)
	for _, script in pairs(eventscripts) do
		script[event](script, ...)
	end
	setmetatable(eventscripts, nil)
end

--- Start logging events for a script
-- @param id of script
function Machine:startLog(script)
	_scriptlogs = _scriptlogs or {}
	_scriptlogs[script] = {}
end

--- Print all events logged so far
function Machine:printLogs()
	if _scriptlogs then
		for script, log in pairs(_scriptlogs) do
			for i = 1, #log, 1 do
				print(unpack(log[i]))
			end
			if #log > 0 then
				print("--")
			end
		end
	end
end

--- Delete all events logged so far
function Machine:clearLogs()
	_scriptlogs = nil
end

local scripting = {
	newMachine = Machine,
	loaded = {}
}

local baseRequire = require

local function scriptRequire(name)
	if not package.loaded[name] then
		scripting.loaded[name] = scripting.loaded[name]
					or baseRequire(name)
	end
	return package.loaded[name]
end

function scripting.beginScriptLoading()
	baseRequire = require
	require = scriptRequire
end

function scripting.endScriptLoading()
	require = baseRequire
end

function scripting.unloadScripts()
	for n, _ in pairs(scripting.loaded) do
		package.loaded[n] = nil
		scripting.loaded[n] = nil
	end
end

return scripting
