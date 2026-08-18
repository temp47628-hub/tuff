local M = {}
local sounds = {}
local trackPaths = {} -- NEW: Store file paths so we can reload them
local currentMusic = nil
local camNode = 0

local songNameByKey = {}
local previousVolume = 1
local lastMenu = nil
local lastSubmenu = nil

local function init()
    -- Logic from doorChime.lua: Define the driver node
    camNode = beamstate.nodeNameMap["driver"] or 0

    electrics.values['audi6_volume'] = 1
    electrics.values['mmiMenu'] = 1
    electrics.values['audi6_musicPaused'] = 1

    local files = {}
    local supportedExtensions = {"ogg", "mp3"}

    for _, ext in ipairs(supportedExtensions) do
        local foundFiles = FS:findFiles("/art/sound/audi6/music", "*." .. ext, 0, false, false)
        for _, f in ipairs(foundFiles) do
            table.insert(files, f)
        end
    end

    table.sort(files)

    electrics.values['audi6_nrOfSongs'] = #files
    electrics.values['current_music_index'] = 1

    for i, f in ipairs(files) do
        local filename = f:match("([^/]+)%.[^%.]+$")
        local musicKey = "music" .. i
        
        -- Store the path and name for later use
        trackPaths[musicKey] = f 
        songNameByKey[musicKey] = filename

        -- Create initial sources (optional now, but good for preload)
        local uniqueName = "audi6_music" .. i .. "_" .. tostring(os.time())
        sounds[musicKey] = obj:createSFXSource(f, "AudioGui", uniqueName, -1)
    end
    
    electrics.values['audi6_currentSongName'] = songNameByKey["music1"] or ""
    electrics.values['music1_state'] = 1
end

local function playMusic(music)
    -- MUTE + STOP absolutely everything first
    for key, sfx in pairs(sounds) do
        if sfx then
            obj:setVolumePitch(sfx, 0, 1)
            obj:stopSFX(sfx)
        end
    end

    -- FORCE RESET: Recreate the SFX source for the selected track.
    -- This guarantees it starts from 00:00.
    if trackPaths[music] then
        -- Generate a new unique name to prevent caching issues
        local uniqueName = "audi6_music_" .. music .. "_" .. tostring(os.clock())
        
        -- Overwrite the old handle with a fresh one
        sounds[music] = obj:createSFXSource(trackPaths[music], "AudioGui", uniqueName, -1)
    end

    -- Now start only the selected track
    if sounds[music] then
        obj:setVolumePitch(sounds[music], electrics.values['audi6_volume'] or 1, 1)
        obj:playSFX(sounds[music])
        
        currentMusic = music
        electrics.values['audi6_currentSongName'] = songNameByKey[music] or ""
    end
end

local function togglePower()
    local newState = 1 - (electrics.values.screen2_state or 0)
    electrics.values.screen2_state = newState
    
    if newState == 1 then
        for i = 1, (electrics.values.audi6_nrOfSongs or 0) do
            electrics.values['music'..i..'_state'] = 0
        end
        guihooks.message('MMI Turned Off', 2)
    else
        guihooks.message('MMI Turned On', 2)
    end
end

local function toggleMute()
    local vol = electrics.values.audi6_volume or 0
    if vol > 0 then
        previousVolume = vol
        electrics.values.audi6_volume = 0
        guihooks.message('Audio Muted', 2)
    else
        electrics.values.audi6_volume = previousVolume or 1
        guihooks.message('Audio Unmuted', 2)
    end
end

local function adjustVolume(change)
    local vol = electrics.values.audi6_volume or 0
    vol = math.max(0, math.min(5, vol + change))
    electrics.values.audi6_volume = vol
    guihooks.message('Volume: ' .. (vol * 2), 2)
end

local function togglePause()
    local paused = 1 - (electrics.values.audi6_musicPaused or 0)
    electrics.values.audi6_musicPaused = paused
    guihooks.message(paused == 1 and 'Music Paused' or 'Music Playing', 2)
end

local function changeTrack(offset)
    local total = electrics.values['audi6_nrOfSongs'] or 0
    if total <= 0 then
        return
    end

    local current = electrics.values['current_music_index'] or 1
    local nextIndex = (current + offset - 1) % total + 1

    -- Stop absolutely everything
    for key, sfx in pairs(sounds) do
        if sfx then
            obj:stopSFX(sfx)
        end
    end

    -- Force unpause
    electrics.values['audi6_musicPaused'] = 0

    -- Update states
    electrics.values['music' .. current .. '_state'] = 0
    electrics.values['current_music_index'] = nextIndex
    electrics.values['music' .. nextIndex .. '_state'] = 1
    electrics.values['screen2_state'] = 0

    -- Reset currentMusic so update() detects the change
    currentMusic = nil

    guihooks.message(offset > 0 and "Next Track" or "Previous Track", 2)
end

local function update(dt)
    local musicoffActive = electrics.values['screen2_state'] == 1
    local userPaused = electrics.values['audi6_musicPaused'] == 1
    local ignitionLevel = (electrics.values['ignitionLevel'] or 0) > 0

    local shouldFreeze = musicoffActive or userPaused or not ignitionLevel

    local menu = electrics.values['mmiMenu']
    local submenu = electrics.values['submenu'] or 0

    if menu ~= lastMenu or submenu ~= lastSubmenu then
        lastMenu = menu
        lastSubmenu = submenu
    end

    if currentMusic and sounds[currentMusic] then
        if shouldFreeze then
            obj:setVolumePitch(sounds[currentMusic], 0, 1)
        else
            obj:setVolumePitch(sounds[currentMusic], electrics.values['audi6_volume'] or 1, 1)
        end
    end

    if ignitionLevel and not userPaused then
        local activeMusic = "music" .. (electrics.values['current_music_index'] or 1)
        if electrics.values[activeMusic .. '_state'] == 1 and currentMusic ~= activeMusic then
            playMusic(activeMusic)
        end
    end
end

M.togglePower = togglePower
M.toggleMute = toggleMute
M.adjustVolume = adjustVolume
M.togglePause = togglePause
M.changeTrack = changeTrack 
M.onInit = init
M.updateGFX = update
return M