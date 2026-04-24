--!strict
--[[
	AudioScapeMusicPlayer — drop-in audio playback with auto-analytics.

	Manages a queue of tracks, handles Sound lifecycle, and automatically
	fires play/stop/skip analytics events through the AudioScape client.

	Usage:
		local player = client:createPlayer()
		player:queue(result.tracks)
		player:play()
		player:skip()  -- auto-tracks skip with listen duration
]]

local SoundService = game:GetService("SoundService")

export type Track = {
	asset_id: string,
	name: string,
	artist: string,
	album: string,
	genre: string,
	duration: number,
	bpm: number?,
	score: number?,
	position: number?,
	created_at: string?,
	updated_at: string?,
}

export type PlayerOptions = {
	parent: Instance?,
	volume: number?,
	playerId: number?,
}

-- Minimal interface for the analytics client dependency.
type AnalyticsClient = {
	trackPlay: (self: any, assetId: string, playerId: (number | string)?, duration: number?) -> (),
	trackStop: (self: any, assetId: string, playerId: (number | string)?, duration: number?) -> (),
	trackSkip: (self: any, assetId: string, playerId: (number | string)?, duration: number?) -> (),
}

local AudioScapeMusicPlayer = {}
AudioScapeMusicPlayer.__index = AudioScapeMusicPlayer

export type MusicPlayerInstance = typeof(setmetatable(
	{} :: {
		_client: AnalyticsClient,
		_parent: Instance,
		_volume: number,
		_playerId: number?,
		_queue: { Track },
		_index: number,
		_sound: Sound?,
		_playing: boolean,
		_advancing: boolean,
		_startedAt: number,
		_endedConnection: RBXScriptConnection?,

		NowPlaying: Track?,
		IsPlaying: boolean,
		Queue: { Track },

		OnTrackChanged: ((track: Track?) -> ())?,
		OnQueueFinished: (() -> ())?,
	},
	AudioScapeMusicPlayer
))

function AudioScapeMusicPlayer.new(client: AnalyticsClient, options: PlayerOptions?): MusicPlayerInstance
	local opts: PlayerOptions = options or {}

	local self = setmetatable({
		_client = client,
		_parent = opts.parent or SoundService,
		_volume = math.clamp(opts.volume or 0.5, 0, 1),
		_playerId = opts.playerId,
		_queue = {},
		_index = 0,
		_sound = nil,
		_playing = false,
		_advancing = false,
		_startedAt = 0,
		_endedConnection = nil,

		-- Public state
		NowPlaying = nil,
		IsPlaying = false,
		Queue = {},

		-- Callbacks
		OnTrackChanged = nil,
		OnQueueFinished = nil,
	}, AudioScapeMusicPlayer)

	-- Flush final analytics on game shutdown
	game:BindToClose(function()
		self:destroy()
	end)

	return self
end

-- Clean up the player, firing a final stop event for any in-progress track.
function AudioScapeMusicPlayer.destroy(self: MusicPlayerInstance)
	if self._playing and self.NowPlaying then
		local duration = self:_getListenDuration()
		self._client:trackStop(self.NowPlaying.asset_id, self._playerId, duration)
	end
	self:_cleanupSound()
end

-- Add tracks to the end of the queue.
function AudioScapeMusicPlayer.queue(self: MusicPlayerInstance, tracks: { Track })
	for _, track in tracks do
		table.insert(self._queue, track)
	end
	self.Queue = self._queue
end

-- Replace the queue with new tracks. Stops current playback.
function AudioScapeMusicPlayer.setQueue(self: MusicPlayerInstance, tracks: { Track })
	self:stop()
	self._queue = {}
	for _, track in tracks do
		table.insert(self._queue, track)
	end
	self._index = 0
	self.Queue = self._queue
end

-- Clear the queue and stop playback.
function AudioScapeMusicPlayer.clearQueue(self: MusicPlayerInstance)
	self:stop()
	self._queue = {}
	self._index = 0
	self.Queue = self._queue
	-- stop() handles NowPlaying cleanup when playing; handle the idle case
	if self.NowPlaying then
		self.NowPlaying = nil
		if self.OnTrackChanged then
			self.OnTrackChanged(nil)
		end
	end
end

-- Start or resume playback. Plays the next track in the queue.
function AudioScapeMusicPlayer.play(self: MusicPlayerInstance)
	if self._playing then
		return
	end

	if self._index >= #self._queue then
		-- Queue finished or empty, start from the beginning
		if #self._queue == 0 then
			return
		end
		self._index = 0
	end

	self._index += 1
	self:_playTrackAtIndex(self._index)
end

-- Stop the currently playing track. Fires a stop analytics event.
function AudioScapeMusicPlayer.stop(self: MusicPlayerInstance)
	if not self._playing or not self._sound then
		return
	end

	local duration = self:_getListenDuration()
	local track = self.NowPlaying

	self:_cleanupSound()

	if track then
		self._client:trackStop(track.asset_id, self._playerId, duration)
	end
end

-- Skip to the next track. Fires a skip analytics event with listen duration.
function AudioScapeMusicPlayer.skip(self: MusicPlayerInstance)
	if not self._playing then
		return
	end

	self._advancing = true

	local duration = self:_getListenDuration()
	local track = self.NowPlaying

	self:_cleanupSound()

	if track then
		self._client:trackSkip(track.asset_id, self._playerId, duration)
	end

	-- Advance to next track
	if self._index < #self._queue then
		self._index += 1
		self._advancing = false
		self:_playTrackAtIndex(self._index)
	else
		-- End of queue
		self._playing = false
		self.IsPlaying = false
		self.NowPlaying = nil
		self._advancing = false
		if self.OnTrackChanged then
			self.OnTrackChanged(nil)
		end
		if self.OnQueueFinished then
			self.OnQueueFinished()
		end
	end
end

-- Set playback volume (0 to 1).
function AudioScapeMusicPlayer.setVolume(self: MusicPlayerInstance, volume: number)
	self._volume = math.clamp(volume, 0, 1)
	if self._sound then
		self._sound.Volume = self._volume
	end
end

-- Set the player ID for analytics tracking.
function AudioScapeMusicPlayer.setPlayerId(self: MusicPlayerInstance, playerId: number?)
	self._playerId = playerId
end

-- Play a single track immediately, replacing current playback.
-- Does not affect the queue.
function AudioScapeMusicPlayer.playTrack(self: MusicPlayerInstance, track: Track)
	self:_cleanupSound()
	self._queue = { track }
	self._index = 1
	self.Queue = self._queue
	self:_playTrackAtIndex(1)
end

--[[ ──────────────────────────────────────────
     Internal helpers
     ────────────────────────────────────────── ]]

function AudioScapeMusicPlayer._playTrackAtIndex(self: MusicPlayerInstance, index: number)
	local track = self._queue[index]
	if not track then
		return
	end

	-- Clean up any existing sound
	self:_cleanupSound()

	-- Create new Sound
	local sound = Instance.new("Sound")
	sound.SoundId = "rbxassetid://" .. track.asset_id
	sound.Volume = self._volume
	sound.Parent = self._parent
	self._sound = sound

	-- Update state
	self._playing = true
	self._startedAt = workspace:GetServerTimeNow()
	self.NowPlaying = track
	self.IsPlaying = true

	-- Fire callback
	if self.OnTrackChanged then
		self.OnTrackChanged(track)
	end

	-- Track play event
	self._client:trackPlay(track.asset_id, self._playerId, track.duration)

	-- Listen for track end
	self._endedConnection = sound.Ended:Connect(function()
		-- Guard against re-entrant advancement (e.g. skip() already handling this)
		if self._advancing then
			return
		end
		self._advancing = true

		local listenDuration = self:_getListenDuration()

		self:_cleanupSound()

		-- Track stop (natural end)
		self._client:trackStop(track.asset_id, self._playerId, listenDuration)

		-- Advance to next track
		if self._index < #self._queue then
			self._index += 1
			self._advancing = false
			self:_playTrackAtIndex(self._index)
		else
			-- Queue finished
			self._playing = false
			self.IsPlaying = false
			self.NowPlaying = nil
			self._advancing = false
			if self.OnTrackChanged then
				self.OnTrackChanged(nil)
			end
			if self.OnQueueFinished then
				self.OnQueueFinished()
			end
		end
	end)

	sound:Play()
end

function AudioScapeMusicPlayer._cleanupSound(self: MusicPlayerInstance)
	if self._endedConnection then
		self._endedConnection:Disconnect()
		self._endedConnection = nil
	end
	if self._sound then
		self._sound:Stop()
		self._sound:Destroy()
		self._sound = nil
	end
	self._playing = false
	self.IsPlaying = false
end

function AudioScapeMusicPlayer._getListenDuration(self: MusicPlayerInstance): number
	if self._startedAt == 0 then
		return 0
	end
	return workspace:GetServerTimeNow() - self._startedAt
end

return AudioScapeMusicPlayer
