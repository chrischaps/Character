-- Procedural Audio Synthesizer
-- Generates organic sound effects without audio files

local Synth = {}
Synth.__index = Synth

-- Audio settings
local SAMPLE_RATE = 44100
local BIT_DEPTH = 16

function Synth.new()
    local self = setmetatable({}, Synth)

    -- Pre-generate sound sources
    self.sounds = {}
    self:generate_sounds()

    -- Sliding sound state
    self.slide_source = nil
    self.slide_volume = 0
    self.slide_target_volume = 0
    self.is_sliding = false

    return self
end

-- Basic waveform generators
function Synth.sine(phase)
    return math.sin(phase * 2 * math.pi)
end

function Synth.saw(phase)
    return 2 * (phase % 1) - 1
end

function Synth.square(phase, duty)
    duty = duty or 0.5
    return (phase % 1) < duty and 1 or -1
end

function Synth.noise()
    return math.random() * 2 - 1
end

function Synth.triangle(phase)
    local p = phase % 1
    return 4 * math.abs(p - 0.5) - 1
end

-- Envelope functions
function Synth.envelope_adsr(t, attack, decay, sustain, release, duration)
    if t < attack then
        return t / attack
    elseif t < attack + decay then
        return 1 - (1 - sustain) * ((t - attack) / decay)
    elseif t < duration - release then
        return sustain
    elseif t < duration then
        return sustain * (1 - (t - (duration - release)) / release)
    else
        return 0
    end
end

function Synth.envelope_exp_decay(t, decay_rate)
    return math.exp(-t * decay_rate)
end

function Synth.envelope_punch(t, duration)
    -- Quick attack, exponential decay
    local attack = 0.01
    if t < attack then
        return t / attack
    else
        return math.exp(-(t - attack) * 8) * (1 - (t / duration) * 0.5)
    end
end

-- Generate all sound effects
function Synth:generate_sounds()
    self.sounds.jump = self:create_jump_sound()
    self.sounds.land = self:create_land_sound()
    self.sounds.slide_loop = self:create_slide_loop()
end

-- Jump: Rising chirp with organic wobble
function Synth:create_jump_sound()
    local duration = 0.15
    local samples = math.floor(SAMPLE_RATE * duration)
    local data = love.sound.newSoundData(samples, SAMPLE_RATE, BIT_DEPTH, 1)

    for i = 0, samples - 1 do
        local t = i / SAMPLE_RATE
        local progress = t / duration

        -- Frequency rises from 280Hz to 580Hz with slight wobble
        local base_freq = 280 + progress * 300
        local wobble = math.sin(t * 45) * 15 * (1 - progress)
        local freq = base_freq + wobble

        -- Phase accumulation for smooth frequency changes
        local phase = t * freq

        -- Mix sine and triangle for warmth
        local wave = Synth.sine(phase) * 0.7 + Synth.triangle(phase * 1.5) * 0.3

        -- Add subtle noise texture
        local noise = Synth.noise() * 0.08 * (1 - progress)

        -- Envelope: quick attack, sustained, quick release
        local env = Synth.envelope_adsr(t, 0.008, 0.02, 0.7, 0.05, duration)

        -- Slight compression curve for punch
        local sample = (wave + noise) * env * 0.5
        sample = sample * math.abs(sample) ^ 0.3 * (sample > 0 and 1 or -1) * 0.7

        data:setSample(i, math.max(-1, math.min(1, sample)))
    end

    return love.audio.newSource(data, "static")
end

-- Land: Soft thump with body
function Synth:create_land_sound()
    local duration = 0.18
    local samples = math.floor(SAMPLE_RATE * duration)
    local data = love.sound.newSoundData(samples, SAMPLE_RATE, BIT_DEPTH, 1)

    for i = 0, samples - 1 do
        local t = i / SAMPLE_RATE
        local progress = t / duration

        -- Low frequency thump that drops
        local freq = 120 - progress * 60
        local phase = t * freq

        -- Mix of sine (body) and noise (texture)
        local body = Synth.sine(phase) * 0.6
        local sub = Synth.sine(phase * 0.5) * 0.3 -- Sub harmonic

        -- Filtered noise for impact texture
        local noise_raw = Synth.noise()
        local noise = noise_raw * 0.25 * math.exp(-t * 25)

        -- Punch envelope
        local env = Synth.envelope_punch(t, duration)

        local sample = (body + sub + noise) * env * 0.6

        data:setSample(i, math.max(-1, math.min(1, sample)))
    end

    return love.audio.newSource(data, "static")
end

-- Slide: Gentle looping texture
function Synth:create_slide_loop()
    local duration = 0.4  -- Loop length
    local samples = math.floor(SAMPLE_RATE * duration)
    local data = love.sound.newSoundData(samples, SAMPLE_RATE, BIT_DEPTH, 1)

    -- Pre-compute some randomness for consistent texture
    local noise_buffer = {}
    for i = 1, samples do
        noise_buffer[i] = math.random() * 2 - 1
    end

    -- Simple low-pass filter state
    local filtered = 0
    local filter_amount = 0.15

    for i = 0, samples - 1 do
        local t = i / SAMPLE_RATE
        local progress = t / duration

        -- Soft granular texture - multiple quiet sine grains
        local grain1 = Synth.sine(t * 180 + math.sin(t * 7) * 0.5) * 0.15
        local grain2 = Synth.sine(t * 220 + math.sin(t * 11) * 0.3) * 0.1
        local grain3 = Synth.triangle(t * 95) * 0.08

        -- Filtered noise for shuffle texture
        local raw_noise = noise_buffer[i + 1]
        filtered = filtered + (raw_noise - filtered) * filter_amount
        local noise = filtered * 0.12

        -- Combine layers
        local sample = grain1 + grain2 + grain3 + noise

        -- Gentle crossfade at loop points for seamless looping
        local fade_time = 0.05
        local fade = 1
        if t < fade_time then
            fade = t / fade_time
        elseif t > duration - fade_time then
            fade = (duration - t) / fade_time
        end

        sample = sample * fade * 0.35

        data:setSample(i, math.max(-1, math.min(1, sample)))
    end

    local source = love.audio.newSource(data, "static")
    source:setLooping(true)
    return source
end

-- Play jump sound with slight pitch variation
function Synth:play_jump(intensity)
    intensity = intensity or 1
    local source = self.sounds.jump:clone()
    -- Slight random pitch variation for organic feel
    source:setPitch(0.95 + math.random() * 0.1 + intensity * 0.1)
    source:setVolume(0.4 + intensity * 0.2)
    source:play()
    return source
end

-- Play landing sound with impact scaling
function Synth:play_land(impact)
    impact = impact or 1
    local source = self.sounds.land:clone()
    -- Lower pitch and higher volume for harder impacts
    source:setPitch(0.85 + (1 - impact) * 0.3 + math.random() * 0.05)
    source:setVolume(0.3 + impact * 0.4)
    source:play()
    return source
end

-- Start/update sliding sound
function Synth:start_slide()
    if not self.is_sliding then
        self.is_sliding = true
        self.slide_source = self.sounds.slide_loop:clone()
        self.slide_source:setVolume(0)
        self.slide_source:play()
    end
    self.slide_target_volume = 0.25
end

-- Stop sliding sound (fade out)
function Synth:stop_slide()
    self.slide_target_volume = 0
end

-- Update sliding sound volume and pitch based on speed
function Synth:update_slide(dt, speed)
    if self.slide_source then
        -- Smooth volume transitions
        local volume_speed = 8
        if self.slide_target_volume > self.slide_volume then
            self.slide_volume = math.min(self.slide_target_volume,
                self.slide_volume + volume_speed * dt)
        else
            self.slide_volume = math.max(self.slide_target_volume,
                self.slide_volume - volume_speed * dt)
        end

        self.slide_source:setVolume(self.slide_volume)

        -- Pitch varies with speed
        local base_pitch = 0.8
        local speed_factor = math.min(speed / 300, 1) * 0.4
        self.slide_source:setPitch(base_pitch + speed_factor + math.sin(love.timer.getTime() * 3) * 0.02)

        -- Stop source if faded out
        if self.slide_volume < 0.01 and self.slide_target_volume == 0 then
            self.slide_source:stop()
            self.is_sliding = false
        end
    end
end

-- Update called each frame
function Synth:update(dt)
    -- Handle any ongoing sound updates
    if self.is_sliding and self.slide_target_volume == 0 then
        self:update_slide(dt, 0)
    end
end

return Synth
