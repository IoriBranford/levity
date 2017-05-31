local Stats = class()
function Stats:_init()
	self:reset()
end

function Stats:reset()
	self.timer = 0
	self.rate = 1
end

function Stats:update(dt)
	self.timer = self.timer + dt
	while self.timer > self.rate do
		-- nothing yet
		self.timer = self.timer - self.rate
	end
end

function Stats:draw()
	local font = love.graphics.getFont()
	local width
	local canvas = love.graphics.getCanvas()
	if canvas then
		width = canvas:getWidth()
	else
		width = love.graphics:getWidth()
	end

	local fps = love.timer.getFPS()
	local mem = math.floor(collectgarbage('count'))
	local gfxstats = love.graphics.getStats()
	local y = 0
	love.graphics.printf(fps.."fps", 0, y, width, "right")
	y = y + font:getHeight()
	love.graphics.printf(mem.." kb", 0, y, width, "right")
	y = y + font:getHeight()

	for stat, value in pairs(gfxstats) do
		love.graphics.printf(value..' '..stat, 0, y, width, "right")
		y = y + font:getHeight()
	end
end

local stats = {
	newStats = Stats
}

return stats
