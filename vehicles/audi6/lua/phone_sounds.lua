local M = {}
local volume, pitch = 2, 1

local SOUNDS = {
    dial        = "/art/sound/audi6/phone/dial.ogg",
    endcall     = "/art/sound/audi6/phone/endcall.ogg",
    male        = "/art/sound/audi6/phone/male_greeting.ogg",
    female      = "/art/sound/audi6/phone/female_greeting.ogg",
    audiservice = "/art/sound/audi6/phone/audiservice.ogg",
}

-- To add a new contact sound: add path to SOUNDS, add contact name here.
local CONTACT_SOUNDS = {
    AUDISERVICE = "audiservice",
}

local sfx = {}

local function isInside()
    local camPos   = obj:getCameraPosition()
    local vehPos   = obj:getPosition()
    local velocity = obj:getVelocity()
    if not camPos or not vehPos then return false end
    return (camPos + velocity * 0.04):distance(vehPos) < 2.0
end

local function play(key)
    if isInside() and sfx[key] then
        obj:stopSFX(sfx[key])
        sfx[key] = obj:createSFXSource(SOUNDS[key], "AudioGui", "phone_" .. key .. "_" .. tostring(os.clock()), -1)
        obj:setVolumePitch(sfx[key], volume, pitch)
        obj:playSFX(sfx[key])
    end
end

local function stop(key)
    if sfx[key] then
        obj:setVolumePitch(sfx[key], 0, pitch)
        obj:stopSFX(sfx[key])
    end
end

function M.playDialSound()           play("dial")                                     end
function M.playEndCallSound()        play("endcall")                                  end
function M.playGreetingSound(gender) play(gender == "female" and "female" or "male")  end
function M.playContactSound(key)     play(key)                                        end
function M.getContactSound(name)     return CONTACT_SOUNDS[name]                      end

function M.stopDialSound()
    stop("dial")
end

function M.stopGreetingSound()
    stop("male")
    stop("female")
    for _, key in pairs(CONTACT_SOUNDS) do stop(key) end
end

local function init()
    for key, path in pairs(SOUNDS) do
        sfx[key] = obj:createSFXSource(path, "AudioGui", "phone_" .. key, -1)
    end
end

M.onInit = init
return M