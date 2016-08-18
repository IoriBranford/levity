local sqrt = math.sqrt

function math.dot(x1, y1, x2, y2)
	return x1*x2 + y1*y2
end
local dot = math.dot

function math.hypotsq(x, y)
	return dot(x, y, x, y)
end
local hypotsq = math.hypotsq

function math.hypot(x, y)
	return sqrt(hypotsq(x, y))
end

function math.rectsisect(x1, y1, w1, h1, x2, y2, w2, h2)
	local r1 = x1 + w1
	local r2 = x2 + w2
	local b1 = y1 + h1
	local b2 = y2 + h2

	if r1 < x2 or r2 < x1 or b1 < y2 or b2 < y1 then
		return false
	end

	return true
end
