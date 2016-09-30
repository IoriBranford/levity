require "levity.class"

local Stats = class(function(self)
	self:reset()
end)

function Stats:reset()
	self.fps = 0
	self.mem = 0
	self.gfxstats = love.graphics.getStats()

	self.timer = 0
	self.rate = 1
end

function Stats:update(dt)
	self.timer = self.timer + dt
	while self.timer > self.rate do
		self.fps = love.timer.getFPS()
		self.mem = math.floor(collectgarbage('count'))
		self.gfxstats = love.graphics.getStats()

		self.timer = self.timer - self.rate
	end
end

function Stats:draw()
	local font = love.graphics.getFont()
	local width = love.graphics:getWidth()
	local canvas = love.graphics.getCanvas()
	if canvas then
		width = canvas:getWidth()
	end

	local y = 0
	love.graphics.printf(self.fps.."fps", 0, y, width, "right")
	y = y + font:getHeight()
	love.graphics.printf(self.mem.." kb", 0, y, width, "right")
	y = y + font:getHeight()

	for stat, value in pairs(self.gfxstats) do
		love.graphics.printf(value..' '..stat, 0, y, width, "right")
		y = y + font:getHeight()
	end
end

local stats = {
	newStats = Stats
}

return stats
