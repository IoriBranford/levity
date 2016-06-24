--- @module audio

require "class"

local Bank = class(function(self)
	self.sounds = {}
end)

--- Load list of audio files
-- @param sounds Table or comma-separated audio file list
-- @param type "static" for sfx or "stream" for music/ambience (default "stream")
function Bank:load(soundfiles, typ)
	function load(soundfile)
		local sound = self.sounds[soundfile]
		if not sound or sound:getType() ~= typ then
			if love.filesystem.exists(soundfile) then
				sound = love.audio.newSource(soundfile, typ)
				self.sounds[soundfile] = sound
			else
				print("WARNING: Missing sound file "..soundfile)
			end
		end
	end

	if type(soundfiles) == "table" then
		for _, soundfile in pairs(soundfiles) do
			load(soundfile)
		end
	elseif type(soundfiles) == "string" then
		for soundfile in (soundfiles..','):gmatch("(.-),%s-") do
			load(soundfile)
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
