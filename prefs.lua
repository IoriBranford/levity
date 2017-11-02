---User preferences
--@field drawstats Draw performance stats (boolean)
--@field drawbodies Draw physics bodies (boolean)
--@field rotation Orientation of the screen (float, degrees in file, radians internally)
--@table Prefs

local prefsmodule = {
	prefs = {}
}
function prefsmodule.init()
	local prefs = {
		drawbodies = false,
		drawstats = false,
		rotation = 0
	}
	--- Lock out against creating new prefs
	setmetatable(prefs, {
		__index = function (prefs, key)
			print("prefs: Unknown pref "..key)
		end,

		__newindex = function (prefs, key, value)
			print("prefs: Unknown pref "..key)
		end
	})
	prefsmodule.prefs = prefs
end

--- Fall through to actual prefs table
setmetatable(prefsmodule, {
	__index = function(prefsmodule, key)
		return prefsmodule.prefs[key]
	end,

	__newindex = function(prefsmodule, key, value)
		prefsmodule.prefs[key] = value
	end
})

prefsmodule.init()
return prefsmodule
