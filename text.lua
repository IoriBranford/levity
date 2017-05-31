local Fonts = class()
function Fonts:_init()
	self.fonts = {}
end

function Fonts:load(fontfiles)
	local function load(fontfile)
		local font = self.fonts[fontfile]
		if not font then
			if love.filesystem.exists(fontfile) then
				font = love.graphics.newFont(fontfile)
				font:setFilter("nearest", "nearest")
				self.fonts[fontfile] = font
			else
				print("WARNING: Missing font file "..fontfile)
			end
		end
	end

	if type(fontfiles) == "table" then
		for _, fontfile in pairs(fontfiles) do
			load(fontfile)
		end
	elseif type(fontfiles) == "string" then
		for fontfile in (fontfiles..','):gmatch("(.-),%s-") do
			load(fontfile)
		end
	end

end

function Fonts:use(fontfile)
	local font = self.fonts[fontfile]
	if font then
		love.graphics.setFont(font)
	end
end

local text = {
	newFonts = Fonts
}

return text
