require "class"

local Stats = class(function(self)
	self:reset()
end)

function Stats:reset()
	self.fps = 0
	self.mem = 0
	self.timer = 0
	self.rate = 1
	self.framect = 0
	self.timer = 0
	self.rate = 1
	self.framect = 0
end

function Stats:update(dt)
	self.timer = self.timer + dt
	self.framect = self.framect + 1
	while self.timer > self.rate do
		self.fps = math.floor(self.framect/self.rate)
		self.mem = math.floor(collectgarbage('count'))
		self.timer = self.timer - self.rate
		self.framect = 0
	end
end

function Stats:draw()
	local font = love.graphics.getFont()
	local width = love.graphics:getWidth()
	local canvas = love.graphics.getCanvas()
	if canvas then
		width = canvas:getWidth()
	end

	love.graphics.printf(self.fps.."fps", 0, 0, width, "right")
	love.graphics.printf(self.mem.." kb", 0, font:getHeight(),
				width, "right")
end

local stats = {
	newStats = Stats
}

return stats
