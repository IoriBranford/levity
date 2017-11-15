--[[
	QueueableSource.lua

	Provides a QueueableSource object, pseudo-inheriting from Source.
	See http://love2d.org/wiki/Source for better documentation on
	most methods except queue and new.

	From love-microphone https://github.com/LPGhatguy/love-microphone

	Copyright (c) 2014 Lucien Greathouse (LPGhatguy)

	This software is provided 'as-is', without any express or implied
	warranty. In no event will the authors be held liable for any damages
	arising from the use of this software.

	Permission is granted to anyone to use this software for any purpose,
	including commercial applications, and to alter it and redistribute it
	freely, subject to the following restrictions:

	1. The origin of this software must not be misrepresented; you must not
	claim that you wrote the original software. If you use this software in
	a product, an acknowledgment in the product documentation would be
	appreciated but is not required.

	2. Altered source versions must be plainly marked as such, and must not
	be misrepresented as being the original software.

	3. This notice may not be removed or altered from any source
	distribution.
]]

local ffi = require("ffi")
local al = require("levity.openal")

local QueueableSource = {}
local typecheck = {
	Object = true,
	QueueableSource = true
}

--[[
	alFormat getALFormat(SoundData data)
		data: The SoundData to query.

	Returns the correct alFormat enum value for the given SoundData.
]]
local function getALFormat(data)
	local stereo = data:getChannels() == 2
	local deep = data:getBitDepth() == 16

	if (stereo) then
		if (deep) then
			return al.AL_FORMAT_STEREO16
		else
			return al.AL_FORMAT_STEREO8
		end
	end

	if (deep) then
		return al.AL_FORMAT_MONO16
	else
		return al.AL_FORMAT_MONO8
	end
end

--[[
	QueueableSource QueueableSource:new(uint bufferCount=16)
		bufferCount: The number of buffers to use to hold queued sounds.

	Creates a new QueueableSource object.
]]
function QueueableSource:new(bufferCount)
	if (bufferCount) then
		if (type(bufferCount) ~= "number" or bufferCount % 1 ~= 0 or bufferCount < 0) then
			return nil, "Invalid argument #1: bufferCount must be a positive integer if given."
		end
	else
		bufferCount = 16
	end

	local new = {}

	for key, value in pairs(self) do
		if (key ~= "new") then
			new[key] = value
		end
	end

	local pBuffers = ffi.new("ALuint[?]", bufferCount)
	al.alGenBuffers(bufferCount, pBuffers)

	local freeBuffers = {}
	for i = 0, bufferCount - 1 do
		table.insert(freeBuffers, pBuffers[i])
	end

	local pSource = ffi.new("ALuint[1]")
	al.alGenSources(1, pSource)
	al.alSourcei(pSource[0], al.AL_LOOPING, 0)

	new._bufferCount = bufferCount
	new._pBuffers = pBuffers
	new._freeBuffers = freeBuffers
	new._source = pSource[0]
	new._pAvailable = ffi.new("ALint[1]")
	new._pBufferHolder = ffi.new("ALuint[16]")

	local wrapper = newproxy(true)
	getmetatable(wrapper).__index = new
	getmetatable(wrapper).__gc = function(self)
		al.alSourceStop(new._source)
		al.alSourcei(new._source, al.AL_BUFFER, 0)
		al.alDeleteSources(1, pSource)
		al.alDeleteBuffers(bufferCount, pBuffers)
	end

	return wrapper
end

--[[
	string QueueableSource:type()

	Returns the string name of the class, "QueueableSource".
]]
function QueueableSource:type()
	return "QueueableSource"
end

--[[
	bool QueueableSource:typeOf(string type)
		type: The type to check against.

	Returns whether the object matches the given type.
]]
function QueueableSource:typeOf(type)
	return typecheck[type]
end

--[[
	void QueueableSource:queue(SoundData data) (Success)
	(void, string) QueueableSource:queue(SoundData data) (Failure)
		data: The SoundData to queue for playback.

	Queues a new SoundData to play.

	Will fail and return nil and an error message if no buffers were available.
]]
function QueueableSource:queue(data)
	self:step()

	if (#self._freeBuffers == 0) then
		return nil, "No free buffers were available to playback the given audio."
	end

	local top = table.remove(self._freeBuffers, 1)

	al.alBufferData(top, getALFormat(data), data:getPointer(), data:getSize(), data:getSampleRate())
	al.alSourceQueueBuffers(self._source, 1, ffi.new("ALuint[1]", top))
end

--[[
	void QueueableSource:step()

	Opens up queues that have been used.
	Called automatically by queue.
]]
function QueueableSource:step()
	al.alGetSourcei(self._source, al.AL_BUFFERS_PROCESSED, self._pAvailable)

	if (self._pAvailable[0] > 0) then
		al.alSourceUnqueueBuffers(self._source, self._pAvailable[0], self._pBufferHolder)

		for i = 0, self._pAvailable[0] - 1 do
			table.insert(self._freeBuffers, self._pBufferHolder[i])
		end
	end
end

--[[
	void QueueableSource:clear()

	Stops playback and clears all queued data.
]]
function QueueableSource:clear()
	self:pause()

	for i = 0, self._bufferCount - 1 do
		al.alSourceUnqueueBuffers(self._source, self._bufferCount, self._pBuffers)
		table.insert(self._freeBuffers, self._pBuffers[i])
	end
end

--[[
	uint QueueableSource:getFreeBufferCount()

	Returns the number of free buffers for queueing sounds with this QueueableSource.
]]
function QueueableSource:getFreeBufferCount()
	return #self._freeBuffers
end

--[[
	void QueueableSource:play()

	Begins playing audio.
]]
function QueueableSource:play()
	if (not self:isPlaying()) then
		al.alSourcePlay(self._source)
	end
end

--[[
	bool QueueableSource:isPlaying()

	Returns whether the source is playing audio.
]]
function QueueableSource:isPlaying()
	local state = ffi.new("ALint[1]")

	al.alGetSourcei(self._source, al.AL_SOURCE_STATE, state)

	return (state[0] == al.AL_PLAYING)
end

--[[
	void QueueableSource:pause()

	Stops playing audio.
]]
function QueueableSource:pause()
	if (not self:isPaused()) then
		al.alSourcePause(self._source)
	end
end

--[[
	void QueueableSource:isPaused()

	Returns whether the source is paused.
]]
function QueueableSource:isPaused()
	local state = ffi.new("ALint[1]")

	al.alGetSourcei(self._source, al.AL_SOURCE_STATE, state)

	return (state[0] == al.AL_PAUSED)
end

--[[
	void QueueableSource:SetVolume(number volume)

	Sets the volume of the source.
]]
function QueueableSource:setVolume(volume)
	al.alSourcef(self._source, al.AL_GAIN, volume)
end

return QueueableSource
