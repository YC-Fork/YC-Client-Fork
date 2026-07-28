--[[- Lua library for accessing [YC-Fork's API](https://github.com/YC-Fork/YC-Server-Fork)
    @module serverapi
]]

--[[
    serverapi.lua - YC-Fork Server API Client Library
]]

--[[- "wrapper" for accessing [YC-Fork's API](https://github.com/YC-Fork/YC-Server-Fork)
    @type API
    @usage Example:

        local serverapi  = require("serverapi")
        local api         = serverapi.API.new()
        api:detect_bestest_server()
        api:request_media(url)
        local data = api.websocket.receive()
]]
local API = {}

local function is_compatible_version(v1, v2)
    if not v1 or not v2 then return false end
    if tostring(v1) == tostring(v2) then return true end
    local m1, min1 = tostring(v1):match("^(%d+)%.(%d+)")
    local m2, min2 = tostring(v2):match("^(%d+)%.(%d+)")
    if m1 and m2 and min1 and min2 then
        return tonumber(m1) == tonumber(m2) and tonumber(min1) == tonumber(min2)
    end
    return false
end

--- Create's a new API instance.
-- @param websocket [Websocket](https://tweaked.cc/module/http.html#ty:Websocket) The websocket.
-- @return API instance
function API.new(websocket)
    return setmetatable({
        websocket = websocket,
        client_version = "2.01.024",
    }, { __index = API })
end

-- Server for YC-Fork. If there are any issues please make a ticket at https://github.com/YC-Fork/YC-Server-Fork
local servers = {
    "wss://ycfork.beltboys.nl"
}

if settings then
    local server = settings.get("youcube.server")
    if server then
        table.insert(servers, 1, server)
    end
end

local function websocket_with_timeout(_url, _headers, _timeout)
    if http.websocketAsync then
        local websocket, websocket_error = http.websocketAsync(_url, _headers)
        if not websocket then
            return false, websocket_error
        end

        local timerID = os.startTimer(_timeout)

        while true do
            local event, param1, param2 = os.pullEvent()

            -- TODO: Close web-socket when the connection succeeds after the timeout
            if event == "websocket_success" and param1 == _url then
                return param2
            elseif event == "websocket_failure" and param1 == _url then
                return false, param2
            elseif event == "timer" and param1 == timerID then
                return false, "Timeout"
            end
        end
    end

    -- use websocket without timeout
    -- when the CC version dos not support websocketAsync
    return http.websocket(_url, _headers)
end

--- Connects to a YC-Fork Server
function API:detect_bestest_server(_server, _verbose, volume)
    if _server then
        self.server_url = _server
        table.insert(servers, 1, _server)
    else
        self.server_url = self.server_url or servers[1]
    end

    for i = 1, #servers do
        local server = servers[i]
        local ok, err = http.checkURL(server:gsub("^ws://", "http://"):gsub("^wss://", "https://"))

        if ok then
            if _verbose then
                print("Trying to connect to:", server)
            end
            local websocket, websocket_error = websocket_with_timeout(server, nil, 5)

            if websocket ~= false then
                self.websocket = websocket
                self.server_url = server
                local handshake = self:handshake(volume)
                if handshake.action ~= "handshake" then
                    self.websocket.close()
                    error("Server rejected connection due to version mismatch")
                end
                if self.client_version and handshake.server and handshake.server.version then
                    if not is_compatible_version(handshake.server.version, self.client_version) then
                        self.websocket.close()
                        error("Server version mismatch (Server: " .. tostring(handshake.server.version) .. ", Client: " .. tostring(self.client_version) .. ")")
                    end
                end
                self.client_id = handshake.client_id
                if _verbose then
                    term.write("Connected: ")
                    term.setTextColor(colors.blue)
                    print(server)
                    term.setTextColor(colors.white)
                    if self.client_id then
                        local nickname = ""
                        if fs.exists("/youcube_nickname.txt") then
                            local f = fs.open("/youcube_nickname.txt", "r")
                            if f then
                                nickname = f.readAll():gsub("^%s*(.-)%s*$", "%1")
                                f.close()
                            end
                        end
                        term.write("Client id: ")
                        term.setTextColor(colors.lightGray)
                        local id_str = self.client_id
                        if nickname ~= "" then
                            id_str = id_str .. " (" .. nickname .. ")"
                        end
                        print(id_str)
                        term.setTextColor(colors.white)
                    end
                end
                break
            elseif i == #servers then
                error(websocket_error)
            elseif _verbose then
                print(websocket_error)
            end
        elseif i == #servers then
            error(err)
        elseif _verbose then
            print(err)
        end
    end
end

--- Receive data from The YC-Fork Server
-- @tparam string filter action filter
-- @treturn table retval data
function API:receive(filter)
    local status, retval = pcall(self.websocket.receive)
    if not status then
        error("websocket_closed")
    end

    if retval == nil then
        error("Outdated Yc-Fork-Client, please update: https://github.com/YC-Fork/YC-Client-Fork")
    end

    local data, err = textutils.unserialiseJSON(retval)

    if data == nil then
        error("Failed to parse message\n" .. err)
    end

    -- Extract volume from any incoming packet payload
    if data.volume ~= nil then
        os.queueEvent("youcube:set_volume", data.volume)
    end

    if data.action == "kick" then
        local reason = data.reason or "Kicked by administrator"
        error("kicked: " .. reason)
    end

    if data.action == "stop" or data.action == "skip" or data.action == "restart" then
        self.pending_command = data.action
        local evt = "youcube:" .. data.action .. "_command"
        os.queueEvent(evt)
        -- Return a fake EOF response so any active buffer loops exit immediately
        if filter == "chunk" then
            return { action = "chunk", chunk = "" }
        elseif filter == "vid" then
            return { action = "vid", lines = {} }
        else
            return { action = filter or data.action }
        end
    end

    if filter then
        if data.action == "error" then
            return data
        end
        if data.action ~= filter then
            return self:receive(filter)
        end
    end

    return data
end

--- Send data to The YC-Fork Server
-- @tparam table data data to send
function API:send(data)
    if not self.websocket then error("websocket_closed") end
    local status, retval = pcall(self.websocket.send, textutils.serialiseJSON(data))
    if not status then
        error("websocket_closed")
    end
end

--[[- [Base64](https://wikipedia.org/wiki/Base64) functions
    @type Base64
]]
local Base64 = {}

local b64str = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

-- based on https://github.com/MCJack123/sanjuuni/blob/c64f8725a9f24dec656819923457717dfb964515/raw-player.lua
--- Decode base64 string
-- @tparam string str base64 string
-- @treturn string string decoded string
function Base64.decode(str)
    local retval = ""
    for s in str:gmatch("....") do
        if s:sub(3, 4) == "==" then
            retval = retval
                .. string.char(
                    bit32.bor(
                        bit32.lshift(b64str:find(s:sub(1, 1)) - 1, 2),
                        bit32.rshift(b64str:find(s:sub(2, 2)) - 1, 4)
                    )
                )
        elseif s:sub(4, 4) == "=" then
            local n = (b64str:find(s:sub(1, 1)) - 1) * 4096
                + (b64str:find(s:sub(2, 2)) - 1) * 64
                + (b64str:find(s:sub(3, 3)) - 1)
            retval = retval .. string.char(bit32.extract(n, 10, 8)) .. string.char(bit32.extract(n, 2, 8))
        else
            local n = (b64str:find(s:sub(1, 1)) - 1) * 262144
                + (b64str:find(s:sub(2, 2)) - 1) * 4096
                + (b64str:find(s:sub(3, 3)) - 1) * 64
                + (b64str:find(s:sub(4, 4)) - 1)
            retval = retval
                .. string.char(bit32.extract(n, 16, 8))
                .. string.char(bit32.extract(n, 8, 8))
                .. string.char(bit32.extract(n, 0, 8))
        end
    end
    return retval
end

--- Request a `16 * 1024` bit chunk
-- @tparam number chunkindex The chunkindex
-- @tparam string id Media id
-- @treturn bytes chunk `16 * 1024` bit chunk
function API:get_chunk(chunkindex, id)
    self:send({
        ["action"] = "get_chunk",
        ["chunkindex"] = chunkindex,
        ["id"] = id,
    })
    return Base64.decode(self:receive("chunk").chunk)
end

--- Get 32vid
-- @tparam number line The line to return
-- @tparam string id Media id
-- @tparam number width Video width
-- @tparam number height Video height
-- @treturn string line one line of the given 32vid
function API:get_vid(tracker, id, width, height)
    self:send({
        ["action"] = "get_vid",
        ["tracker"] = tracker,
        ["id"] = id,
        ["width"] = width * 2,
        ["height"] = height * 3,
    })
    return self:receive("vid")
end

--- Request media
-- @tparam string url Url or Search Term
--@treturn table json response
function API:request_media(url, width, height)
    local request = {
        ["action"] = "request_media",
        ["url"] = url,
    }
    if width and height then
        request.width = width * 2
        request.height = height * 3
    end
    self:send(request)
    --return self:receive({ ["media"] = true, ["status"] = true })
end

--- Get queued media from the server
-- @treturn table json response
function API:get_queued_media()
    self:send({
        ["action"] = "get_queued_media",
    })
    return self:receive("play")
end

--- Handshake - get Server capabilities and version
--@treturn table json response
function API:handshake(volume)
    local nickname = ""
    if fs.exists("/youcube_nickname.txt") then
        local f = fs.open("/youcube_nickname.txt", "r")
        if f then
            nickname = f.readAll():gsub("^%s*(.-)%s*$", "%1")
            f.close()
        end
        pcall(fs.delete, "/youcube_nickname.txt")
        local sf = fs.open("/ycfork_settings.txt", "w")
        if sf then
            sf.write(textutils.serialiseJSON({ nickname = nickname, queue_via_dashboard = true }))
            sf.close()
        end
    elseif fs.exists("/ycfork_settings.txt") then
        local f = fs.open("/ycfork_settings.txt", "r")
        if f then
            local content = f.readAll()
            f.close()
            local parsed = textutils.unserialiseJSON(content)
            if type(parsed) == "table" and parsed.nickname then
                nickname = tostring(parsed.nickname)
            end
        end
    end

    self:send({
        ["action"] = "handshake",
        ["client_version"] = self.client_version,
        ["nickname"] = nickname,
        ["volume"] = volume,
    })
    return self:receive("handshake")
end

--[[- Abstraction for Audio Devices
    @type AudioDevice
]]
local AudioDevice = {}

--- Create's a new AudioDevice instance.
-- @tparam table object Base values
-- @treturn AudioDevice instance
function AudioDevice.new(object)
    -- @type AudioDevice
    local self = object or {}

    function self:validate() end

    function self:setLabel(lable) end

    function self:write(chunk) end

    function self:play() end

    function self:reset() end

    function self:setVolume(volume) end

    return self
end

--[[- @{AudioDevice} from a Speaker
    @type Speaker
    @usage Example:

        local serverapi  = require("serverapi")
        local speaker     = peripheral.find("speaker")
        local audiodevice = serverapi.Speaker.new(speaker)
]]
local Speaker = {}

local decoder
local status, dfpwm = pcall(require, "cc.audio.dfpwm")

if status then
    decoder = dfpwm.make_decoder()
end

local function get_decoder()
    if dfpwm then
        return dfpwm.make_decoder()
    end
end

--- Create's a new Tape instance.
-- @tparam speaker speaker The speaker
-- @treturn AudioDevice|Speaker instance
function Speaker.new(speaker)
    local self = AudioDevice.new({ speaker = speaker })

    function self:validate()
        if not decoder then
            return "This ComputerCraft version dos not support DFPWM"
        end
    end

    function self:setVolume(volume)
        self.volume = volume
    end

    function self:write(chunk, pcm)
        local buffer = pcm
        if not buffer then
            buffer = decoder(chunk)
        end
        while not self.speaker.playAudio(buffer, self.volume) do
            os.pullEvent("speaker_audio_empty")
        end
    end

    return self
end

--[[- @{AudioDevice} from a [Computronics tape_drive](https://wiki.vexatos.com/wiki:computronics:tape)
    @type Tape
    @usage Example:

        local serverapi  = require("serverapi")
        local tape_drive  = peripheral.find("tape_drive")
        local audiodevice = serverapi.Tape.new(tape_drive)
]]
local Tape = {}

--- Create's a new Tape instance.
-- @tparam tape tape The tape_drive
-- @treturn AudioDevice|Tape instance
function Tape.new(tape)
    local self = AudioDevice.new({ tape = tape })

    function self:validate()
        if not self.tape.isReady() then
            return "You need to insert a tape"
        end
    end

    function self:setVolume(volume)
        if volume then
            self.tape.setVolume(volume)
        end
    end

    function self:play(chunk)
        self.tape.seek(-self.tape.getSize())
        self.tape.play()
    end

    function self:write(chunk)
        self.tape.write(chunk)
    end

    function self:setLabel(lable)
        self.tape.setLabel(lable)
    end

    function self:reset()
        -- based on https://github.com/Vexatos/Computronics/blob/b0ade53cab10529dbe91ebabfa882d1b4b21fa90/src/main/resources/assets/computronics/lua/peripheral/tape_drive/programs/tape_drive/tape#L109-L123
        local size = self.tape.getSize()
        self.tape.stop()
        self.tape.seek(-size)
        self.tape.stop()
        self.tape.seek(-90000)
        local s = string.rep(string.char(170), 8192)
        for i = 1, size + 8191, 8192 do
            self.tape.write(s)
        end
        self.tape.seek(-size)
        self.tape.seek(-90000)
    end

    return self
end

--[[- Abstract object for filling a @{Buffer}
    @type Filler
]]
local Filler = {}

--- Create's a new Filler instance.
-- @treturn Filler instance
function Filler.new()
    local self = {}
    function self:next() end

    return self
end

--[[- @{Filler} for Audio
    @type AudioFiller
]]
local AudioFiller = {}

--- Create's a new AudioFiller instance.
-- @tparam API serverapi API object
-- @tparam string id Media id
-- @treturn AudioFiller|Filler instance
function AudioFiller.new(serverapi, id)
    local self = {
        id = id,
        chunkindex = 0,
        serverapi = serverapi,
    }

    function self:next()
        local response = self.serverapi:get_chunk(self.chunkindex, self.id)
        self.chunkindex = self.chunkindex + 1
        return response
    end

    return self
end

--[[- @{Filler} for Video
    @type VideoFiller
]]
local VideoFiller = {}

--- Create's a new VideoFiller instance.
-- @tparam API serverapi API object
-- @tparam string id Media id
-- @tparam number width Video width
-- @tparam number height Video height
-- @treturn VideoFiller|Filler instance
function VideoFiller.new(serverapi, id, width, height)
    local self = {
        id = id,
        width = width,
        height = height,
        tracker = 0,
        serverapi = serverapi,
    }

    function self:next()
        local response = self.serverapi:get_vid(self.tracker, self.id, self.width, self.height)
        if not response or not response.lines or response.action == "error" then
            return {}
        end
        local valid_lines = {}
        for i = 1, #response.lines do
            local line = response.lines[i]
            if line and line ~= "" then
                valid_lines[#valid_lines + 1] = line
                self.tracker = self.tracker + #line + 1
            end
        end
        return valid_lines
    end

    return self
end

--[[- Buffers Data
    @type Buffer
]]
local Buffer = {}

--- Create's a new Buffer instance.
-- @tparam Filler filler filler instance
-- @tparam number size buffer limit
-- @treturn Buffer instance
function Buffer.new(filler, size)
    local self = {
        filler = filler,
        size = size,
    }
    self.buffer = {}

    function self:next()
        while #self.buffer == 0 do
            sleep(0.05)
        end -- Wait until next is available
        local next = self.buffer[1]
        table.remove(self.buffer, 1)
        return next
    end

    function self:fill()
        if #self.buffer < self.size then
            local next = filler:next()
            if type(next) == "table" then
                if #next == 0 then
                    return false
                end
                for i = 1, #next do
                    if next[i] and next[i] ~= "" then
                        self.buffer[#self.buffer + 1] = next[i]
                    end
                end
            elseif next and next ~= "" then
                self.buffer[#self.buffer + 1] = next
            end
            return true
        end
        return false
    end

    return self
end

local function get_video_targets()
    local targets = { term }
    if peripheral and peripheral.getNames then
        for _, name in ipairs(peripheral.getNames()) do
            if peripheral.getType(name) == "monitor" then
                local mon = peripheral.wrap(name)
                if mon then
                    table.insert(targets, mon)
                end
            end
        end
    end
    return targets
end

local CC_STANDARD_PALETTE = {
    [0] = { 240 / 255, 240 / 255, 240 / 255 },
    [1] = { 242 / 255, 178 / 255, 54 / 255 },
    [2] = { 229 / 255, 127 / 255, 205 / 255 },
    [3] = { 153 / 255, 178 / 255, 242 / 255 },
    [4] = { 222 / 255, 222 / 255, 108 / 255 },
    [5] = { 127 / 255, 204 / 255, 25 / 255 },
    [6] = { 242 / 255, 178 / 255, 204 / 255 },
    [7] = { 76 / 255, 76 / 255, 76 / 255 },
    [8] = { 153 / 255, 153 / 255, 153 / 255 },
    [9] = { 76 / 255, 153 / 255, 178 / 255 },
    [10] = { 178 / 255, 102 / 255, 229 / 255 },
    [11] = { 51 / 255, 102 / 255, 204 / 255 },
    [12] = { 127 / 255, 102 / 255, 76 / 255 },
    [13] = { 87 / 255, 169 / 255, 58 / 255 },
    [14] = { 204 / 255, 76 / 255, 76 / 255 },
    [15] = { 17 / 255, 17 / 255, 17 / 255 },
}

local function reset_term()
    local targets = get_video_targets()
    for _, tgt in ipairs(targets) do
        for i = 0, 15 do
            pcall(tgt.setPaletteColor, 2 ^ i, CC_STANDARD_PALETTE[i][1], CC_STANDARD_PALETTE[i][2], CC_STANDARD_PALETTE[i][3])
        end
        tgt.setBackgroundColor(colors.black)
        tgt.setTextColor(colors.white)
        tgt.clear()
        tgt.setCursorPos(1, 1)
    end
end

local HEX_LOOKUP = {}
for i = 0, 15 do
    HEX_LOOKUP[i] = string.format("%x", i)
end

--[[- Create's a new Buffer instance.

    Based on [sanjuuni/raw-player.lua](https://github.com/MCJack123/sanjuuni/blob/c64f8725a9f24dec656819923457717dfb964515/raw-player.lua)
    and [sanjuuni/websocket-player.lua](https://github.com/MCJack123/sanjuuni/blob/30dcabb4b56f1eb32c88e1bce384b0898367ebda/websocket-player.lua)
    @tparam Buffer buffer filled with frames
]]
local function play_vid(buffer, force_fps, string_unpack)
    if not string_unpack then
        string_unpack = string.unpack
    end
    local targets = get_video_targets()
    local Fwidth, Fheight = term.getSize()
    local tracker = 0

    if buffer:next() ~= "32Vid 1.1" then
        error("Unsupported file")
    end

    local fps = tonumber(buffer:next())
    if force_fps then
        fps = force_fps
    end

    -- Keep custom dynamic buffer size if already configured smaller to avoid memory choke
    if buffer.size > 20 then
        buffer.size = math.ceil(fps) * 2
    end

    local first, second = buffer:next(), buffer:next()

    if second == "" or second == nil then
        fps = 0
    end
    for _, tgt in ipairs(targets) do
        tgt.clear()
    end

    local start = os.epoch("utc")
    local frame_count = 0
    while true do
        frame_count = frame_count + 1
        local frame
        if first then
            frame, first = first, nil
        elseif second then
            frame, second = second, nil
        else
            frame = buffer:next()
        end
        if frame == "" or frame == nil then
            break
        end
        local mode = frame:match("^!CP([CD])")
        if not mode then
            error("Invalid file")
        end
        local b64data
        if mode == "C" then
            local len = tonumber(frame:sub(5, 8), 16)
            b64data = frame:sub(9, len + 8)
        else
            local len = tonumber(frame:sub(5, 16), 16)
            b64data = frame:sub(17, len + 16)
        end
        local data = Base64.decode(b64data)
        -- TODO: maybe verify checksums?
        assert(data:sub(1, 4) == "\0\0\0\0" and data:sub(9, 16) == "\0\0\0\0\0\0\0\0", "Invalid file")
        local width, height = string_unpack("HH", data, 5)
        local c, n, pos = string_unpack("c1B", data, 17)
        local text = {}
        for y = 1, height do
            local row_chars = {}
            for x = 1, width do
                row_chars[x] = c
                n = n - 1
                if n == 0 then
                    c, n, pos = string_unpack("c1B", data, pos)
                end
            end
            text[y] = table.concat(row_chars)
        end
        c = c:byte()
        for y = 1, height do
            local fg_chars, bg_chars = {}, {}
            for x = 1, width do
                fg_chars[x] = HEX_LOOKUP[bit32.band(c, 0x0F)]
                bg_chars[x] = HEX_LOOKUP[bit32.rshift(c, 4)]
                n = n - 1
                if n == 0 then
                    c, n, pos = string_unpack("BB", data, pos)
                end
            end
            local fg = table.concat(fg_chars)
            local bg = table.concat(bg_chars)
            for _, tgt in ipairs(targets) do
                tgt.setCursorPos(1, y)
                tgt.blit(text[y], fg, bg)
            end
        end
        pos = pos - 2
        local r, g, b
        for i = 0, 15 do
            r, g, b, pos = string_unpack("BBB", data, pos)
            for _, tgt in ipairs(targets) do
                tgt.setPaletteColor(2 ^ i, r / 255, g / 255, b / 255)
            end
        end
        if fps == 0 then
            read()
            break
        else
            while os.epoch("utc") < start + (frame_count + 1) / fps * 1000 do
                sleep(1 / fps)
            end
        end
    end
    reset_term()
end

return {
    --- "Metadata" - [YC-Forke API](https://commandcracker.github.io/YC-Forke/) Version
    _API_VERSION = "0.0.0-poc.1.0.0",
    --- "Metadata" - Library Version
    _VERSION = "0.0.0-poc.1.4.2",
    --- "Metadata" - Description
    _DESCRIPTION = "Library for accessing YC-Fork's API",
    --- "Metadata" - Homepage / Url
    _URL = "https://github.com/Commandcracker/YC-Forke",
    --- "Metadata" - License
    _LICENSE = "GPL-3.0",
    API = API,
    AudioDevice = AudioDevice,
    Speaker = Speaker,
    Tape = Tape,
    Base64 = Base64,
    Filler = Filler,
    AudioFiller = AudioFiller,
    VideoFiller = VideoFiller,
    Buffer = Buffer,
    play_vid = play_vid,
    reset_term = reset_term,
    get_decoder = get_decoder,
}
