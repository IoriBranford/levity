local Fonts = class()
function Fonts:_init()
	self.fonts = {}
end

function Fonts:load(fontfiles, size)
	local function load(fontfile, size)
		local font = self.fonts[fontfile..size]
		if not font then
			if love.filesystem.exists(fontfile) then
				font = love.graphics.newFont(fontfile, size)
				font:setFilter("nearest", "nearest")
				self.fonts[fontfile..size] = font
			else
				print("WARNING: Missing font file "..fontfile)
			end
		end
	end

	if type(fontfiles) == "table" then
		for _, fontfile in pairs(fontfiles) do
			load(fontfile, size)
		end
	elseif type(fontfiles) == "string" then
		for fontfile in (fontfiles..','):gmatch("%s*(.-)%s*,%s*") do
			load(fontfile, size)
		end
	end
end

function Fonts:use(fontfile, size)
	local font = self.fonts[fontfile..size]
	if font then
		love.graphics.setFont(font)
	end
end

local text = {
	newFonts = Fonts
}

return text
