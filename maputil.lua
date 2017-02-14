local pl = require "levity.pl.lua.pl.import_into"()

local MapUtil = {}

local ObjectTypesTemplate = [[
<objecttypes>
{{<objecttype name="$_">
{{<property name="$_" type="$type" default="$value"/>}}
 </objecttype>}}
</objecttypes>
]]

--- XML file into object types table
-- @param filename
-- @return Table in the form { Type = { Property = Value, ... }, ... }
function MapUtil.loadObjectTypesFile(filename)
	local status, err
	local file = love.filesystem.newFile(filename)
	if not file then
		return false
	end

	status, err = file:open("r")
	if not status then
		print(err)
		return false
	end

	local text, size = file:read()
	file:close()

	local doc = pl.xml.parse(text, false)
	local objecttypes = doc:match(ObjectTypesTemplate)
	for type, properties in pairs(objecttypes) do
		for property, value in pairs(properties) do
			if value.value == "true" then
				properties[property] = true
			elseif value.value == "false" then
				properties[property] = false
			elseif value.type == "int" or value.type == "float" then
				properties[property] = tonumber(value.value)
			end
		end
	end
	--pl.pretty.dump(objecttypes)
	return objecttypes
end

--- Set object's properties to fall back to object type's default properties
--@param object
--@param objecttypes returned from loadObjectTypesFile
function MapUtil.setObjectDefaultProperties(object, objecttypes)
	local mt = {}
	function mt.__index(properties, name)
		local defaultproperties = objecttypes[object.type]
		if not defaultproperties then
			return nil
		end

		return defaultproperties[name]
	end

	setmetatable(object.properties, mt)
end

--- Set multiple objects' default properties
--@param objects array
--@param objecttypes returned from loadObjectTypesFile
function MapUtil.setObjectsDefaultProperties(objects, objecttypes)
	for _, object in pairs(objects) do
		MapUtil.setObjectDefaultProperties(object, objecttypes)
	end
end

return MapUtil
