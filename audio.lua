--- @module audio

local MusicEmu = require "levity.MusicEmu"

local Bank = class()
function Bank:_init()
	self.sounds = {}
	self.currentmusic = nil
	self.timetonextmusic = 0
	self.nextmusicfile = nil
end

--- Load list of audio files
-- @param sounds Table or comma-separated audio file list
-- @param type "static" for sfx or "stream" for music/ambience (default "stream")
function Bank:load(soundfiles, typ)
	local function load(soundfile)
		local sound = self.sounds[soundfile]
		if not sound or sound:getType() ~= typ then
			if love.filesystem.exists(soundfile) then
				if typ == "emu" then
					if MusicEmu then
						sound = MusicEmu(soundfile)
					end
				else
					sound = love.audio.newSource(soundfile, typ)
				end

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
		for soundfile in (soundfiles..','):gmatch("%s*(.-)%s*,%s*") do
			load(soundfile)
		end
	end

end

--- Play an audio file
-- @param soundfile
-- @return Sound source now playing the audio
function Bank:play(soundfile, track)
	local sound = self.sounds[soundfile]
	local source = nil
	if sound then
		local typ = sound:getType()
		if typ == "emu" then
			sound:start(track)
			source = sound
			self.currentmusic = source
		elseif typ == "stream" then
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

function Bank:update(dt)
	if self.currentmusic then
		if self.currentmusic.update then
			self.currentmusic:update()
		end

		if self.timetonextmusic > 0 then
			self.timetonextmusic = self.timetonextmusic - dt
			if self.timetonextmusic <= 0 then
				self.currentmusic = self:play(self.nextmusicfile)
				self.nextmusicfile = nil
			end
		end
	end
end

function Bank:changeMusic(nextfile, nextfiletype, fadetime)
	self:load(nextfile, nextfiletype)

	if fadetime and self.currentmusic and self.currentmusic.fade then
		self.currentmusic:fade()
		self.timetonextmusic = fadetime
		self.nextmusicfile = nextfile
	else
		if self.currentmusic then
			self.currentmusic:pause()
		end
		self.currentmusic = self:play(nextfile)
	end
end

local audio = {
	newBank = Bank
}

return audio
