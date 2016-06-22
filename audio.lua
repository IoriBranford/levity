--- @module audio

require "class"

local Bank = class(function(self)
	self.sounds = {}
end)

--- Load list of audio files
-- @param soundlist Comma-separated list of audio files
-- @param type "static" for sfx or "stream" for music/ambience (default "stream")
function Bank:load(soundlist, type)
	for soundfile in (soundlist..','):gmatch("(.-),%s-") do
		local sound = self.sounds[soundfile]
		if not sound or sound:getType() ~= type then
			if not love.filesystem.exists(soundfile) then
				print("WARNING: Missing sound file "..soundfile)
				return
			end
			sound = love.audio.newSource(soundfile, type)
			self.sounds[soundfile] = sound
		end
	end
end

--- Play an audio file
-- @param soundfile
-- @return Sound source now playing the audio
function Bank:play(soundfile)
	local sound = self.sounds[soundfile]
	local source = nil
	if sound then
		if sound:getType() == "stream" then
			if sound:isPlaying() then
				sound:rewind()
			else
				sound:play()
			end
			source = sound
		else
			source = sound:clone()
			source:play()
		end
	end
	return source
end

local audio = {
	newBank = Bank
}

return audio
