--[[
YC-Client-Fork
]]

local _VERSION = "2.00.001"

local function is_lib(libs, lib)
    for i = 1, #libs do
        local value = libs[i]
        if value == lib or value .. ".lua" == lib then
            return true, value
        end
    end
    return false
end

local libs = { "serverapi", "numberformatter", "semver", "argparse", "string_pack", "ui" }
local lib_paths = { ".", "./Yc-Fork-Client-Libs", "./apis", "./modules", "/", "/lib", "/apis", "/modules", "/Yc-Fork-Client-Libs" }

-- LevelOS Support
if _G.lOS then
    lib_paths[#lib_paths + 1] = "/Program_Files/Yc-Fork-Client-Libs"
end

local function load_lib(lib)
    if require then
        return require(lib:gsub(".lua", ""))
    end
    return dofile(lib)
end

for i_path = 1, #lib_paths do
    local path = lib_paths[i_path]
    if fs.exists(path) then
        local files = fs.list(path)
        for i_file = 1, #files do
            local found, lib = is_lib(libs, files[i_file])
            if found and lib ~= nil and libs[lib] == nil then
                libs[lib] = load_lib(path .. "/" .. files[i_file])
            end
        end
    end
end

for i = 1, #libs do
    local lib = libs[i]
    if libs[lib] == nil then
        error(('Library "%s" not found.'):format(lib))
    end
end

-- args --

local function get_program_name()
    if arg then
        return arg[0]
    end
    return fs.getName(shell.getRunningProgram()):gsub("[\\.].*$", "")
end

-- stylua: ignore start

local parser = libs.argparse {
    help_max_width = ({ term.getSize() })[1],
    name = get_program_name()
}
    :description "Official Yc-Fork-Client for accessing media from services like Youtube, Spotify, Twitch, etc."

parser:argument "URL"
    :args "*"
    :description "URL or search term."

parser:flag "-v" "--verbose"
    :description "Enables verbose output."
    :target "verbose"
    :action "store_true"

parser:option "-V" "--volume"
    :description "Sets the volume of the audio. A value from 0-300 (default 300)"
    :target "volume"

parser:option "-s" "--server"
    :description "The server that YC should use."
    :target "server"
    :args(1)

parser:flag "--nv" "--no-video"
    :description "Disables video."
    :target "no_video"
    :action "store_true"

parser:flag "--na" "--no-audio"
    :description "Disables audio."
    :target "no_audio"
    :action "store_true"

parser:flag "--sh" "--shuffle"
    :description "Shuffles audio before playing"
    :target "shuffle"
    :action "store_true"

parser:flag "-l" "--loop"
    :description "Loops the media."
    :target "loop"
    :action "store_true"

parser:flag "--lp" "--loop-playlist"
    :description "Loops the playlist."
    :target "loop_playlist"
    :action "store_true"

parser:option "--fps"
    :description "Force sanjuuni to use a specified frame rate"
    :target "force_fps"

parser:flag(nil, "--debug")
    :description "Enables debug logging for device connections."
    :target "debug"
    :action "store_true"

-- stylua: ignore end

local args = parser:parse({ ... })

local function debug_log(color, message)
    if args.debug then
        term.setTextColor(color)
        print(message)
        term.setTextColor(colors.white)
    end
end

if args.force_fps then
    args.force_fps = tonumber(args.force_fps)
end

if args.volume then
    args.volume = tonumber(args.volume)
    if args.volume == nil then
        parser:error("Volume must be a number")
    end
else
    args.volume = 300
end

if args.volume > 300 then
    parser:error("Volume cant be over 300 (this will be 3.0 in mc with the speaker)")
end

if args.volume < 0 then
    parser:error("Volume cant be below 0")
end
args.volume = args.volume / 100

if #args.URL > 0 then
    args.URL = table.concat(args.URL, " ")
else
    args.URL = nil
end

if args.no_video and args.no_audio then
    parser:error("Nothing will happen, when audio and video is disabled!")
end

-- CraftOS-PC support --

if periphemu then
    periphemu.create("top", "speaker")
    -- Fuck the max websocket message police
    config.set("http_max_websocket_message", 2 ^ 30)
end

local function get_audiodevices()
    local audiodevices = {}

    for _, name in ipairs(peripheral.getNames()) do
        if peripheral.getType(name) == "speaker" then
            local speaker = peripheral.wrap(name)
            local dev = libs.serverapi.Speaker.new(speaker)
            dev.name = name
            audiodevices[#audiodevices + 1] = dev
        elseif peripheral.getType(name) == "tape_drive" then
            local tape = peripheral.wrap(name)
            local dev = libs.serverapi.Tape.new(tape)
            dev.name = name
            audiodevices[#audiodevices + 1] = dev
        end
    end

    if #audiodevices == 0 then
        -- Disable audio when no audiodevice is found
        args.no_audio = true
        return audiodevices
    end

    -- Validate audiodevices
    local last_error
    local valid_audiodevices = {}

    for i = 1, #audiodevices do
        local audiodevice = audiodevices[i]
        local _error = audiodevice:validate()
        if _error == nil then
            valid_audiodevices[#valid_audiodevices + 1] = audiodevice
        else
            last_error = _error
        end
    end

    if #valid_audiodevices == 0 then
        error(last_error)
    end

    return valid_audiodevices
end

-- main --

local serverapi = libs.serverapi.API.new()
serverapi.client_version = _VERSION
local audiodevices = get_audiodevices()

-- update check --

local function get_versions()
    local url = "https://raw.githubusercontent.com/YC-Fork/YC-Server-Fork/main/versions.json"

    -- Check if the URL is valid
    local ok, err = http.checkURL(url)
    if not ok then
        printError("Invalid Update URL.", '"' .. url .. '" ', err)
        return
    end

    local response, http_err = http.get(url, nil, true)
    if not response then
        printError('Failed to retreat data from update URL. "' .. url .. '" (' .. http_err .. ")")
        return
    end

    local sResponse = response.readAll()
    response.close()

    return textutils.unserialiseJSON(sResponse)
end

local function write_colored(text, color)
    term.setTextColor(color)
    term.write(text)
end

local function new_line()
    local w, h = term.getSize()
    local x, y = term.getCursorPos()
    if y + 1 <= h then
        term.setCursorPos(1, y + 1)
    else
        term.setCursorPos(1, h)
        term.scroll(1)
    end
end

local function write_outdated(current, latest)
    if libs.semver(current) ^ libs.semver(latest) then
        term.setTextColor(colors.yellow)
    else
        term.setTextColor(colors.red)
    end

    term.write(current)
    write_colored(" -> ", colors.lightGray)
    write_colored(latest, colors.lime)
    term.setTextColor(colors.white)
    new_line()
end

local function can_update(name, current, latest)
    if libs.semver(current) < libs.semver(latest) then
        term.write(name .. " ")
        write_outdated(current, latest)
    end
end

local function update_checker()
    local versions = get_versions()
    if versions == nil then
        return
    end

    local client_version = versions.yc_fork_client and versions.yc_fork_client.version
    if client_version then
        can_update("yc-fork-client", _VERSION, client_version)
    end

    local handshake = serverapi:handshake()
    local server_version = versions.yc_fork_server and versions.yc_fork_server.version
    if server_version and libs.semver(handshake.server.version) < libs.semver(server_version) then
        print("Tell the server owner to update their server!")
        write_outdated(handshake.server.version, server_version)
    end
end

local function play_audio(buffer, title, on_first_chunk)
    for i = 1, #audiodevices do
        local audiodevice = audiodevices[i]
        audiodevice:reset()
        audiodevice:setLabel(title)
        audiodevice:setVolume(args.volume)
        audiodevice.cursor = 1
        audiodevice.dead = false
    end

    local decoder = libs.serverapi.get_decoder()
    local chunks = {}
    local write_index = 1
    local cleaned_up_until = 1
    local current_chunk_to_write = 1
    local seek_reset_requested = false

    local notified = false
    local eof = false

    local function producer()
        while true do
            local min_cursor = write_index
            local has_active = false

            for _, dev in ipairs(audiodevices) do
                if not dev.dead then
                    if not dev.cursor or dev.cursor > write_index then dev.cursor = write_index end
                    if dev.cursor < min_cursor then
                        min_cursor = dev.cursor
                    end
                    has_active = true
                end
            end

            if not has_active then
                min_cursor = write_index
            end

            for i = cleaned_up_until, min_cursor - 1 do
                chunks[i] = nil
            end
            cleaned_up_until = min_cursor

            if write_index - min_cursor > 8 then -- Increased buffer slightly for stability
                sleep(0.05)
            else
                local chunk = buffer:next()

                if chunk == "" then
                    eof = true
                    os.queueEvent("new_audio_chunk")
                    return
                end

                if buffer.filler.chunkindex == 1 then
                    buffer.size = math.ceil(1024 / (#chunk / 16))
                end

                if not notified then
                    notified = true
                    if on_first_chunk then
                        on_first_chunk()
                    end
                end

                local pcm
                if decoder then
                    pcm = decoder(chunk)
                end

                chunks[write_index] = { chunk = chunk, pcm = pcm }
                write_index = write_index + 1
                os.queueEvent("new_audio_chunk")
            end
        end
    end

    local consumers = {}
    -- Only create individual consumers for Tape drives
    for i = 1, #audiodevices do
        local audiodevice = audiodevices[i]
        if audiodevice.tape then
            consumers[#consumers + 1] = function()
                while true do
                    if audiodevice.dead then return end

                    if not peripheral.isPresent(audiodevice.name) then
                        audiodevice.dead = true
                        debug_log(colors.red, "Tape drive disconnected: " .. (audiodevice.name or "unknown"))
                        return
                    end

                    if not audiodevice.cursor then audiodevice.cursor = 1 end

                    if write_index - audiodevice.cursor > 5 then
                        audiodevice.cursor = write_index - 1
                    end

                    if audiodevice.cursor < write_index then
                        local data = chunks[audiodevice.cursor]
                        if data then
                            audiodevice:write(data.chunk, data.pcm)
                        end
                        audiodevice.cursor = audiodevice.cursor + 1
                        os.queueEvent("chunk_consumed")
                    else
                        if eof then
                            audiodevice:play()
                            return
                        end
                        os.pullEvent("new_audio_chunk")
                    end
                end
            end
        end
    end

    -- Super consumer for all speakers (handles dynamic addition)
    local function speaker_driver()
        current_chunk_to_write = 1
        while true do
            if seek_reset_requested then
                seek_reset_requested = false
                current_chunk_to_write = 1
            end
            if eof then
                local all_caught_up = true
                for _, dev in ipairs(audiodevices) do
                    if dev.speaker and not dev.dead and dev.cursor < write_index then
                        all_caught_up = false
                        break
                    end
                end
                if all_caught_up then return end
            end

            if current_chunk_to_write >= write_index then
                sleep(0.05)
                if eof and current_chunk_to_write >= write_index then return end
                goto continue_driver_loop
            end

            local data = chunks[current_chunk_to_write]
            if not data then
                current_chunk_to_write = cleaned_up_until
                debug_log(colors.yellow, "Speaker driver lagging, resyncing to chunk " .. current_chunk_to_write)
                goto continue_driver_loop
            end

            local pcm_buffer = data.pcm
            if not pcm_buffer and decoder then
                pcm_buffer = decoder(data.chunk)
                data.pcm = pcm_buffer
            end

            local all_speakers_wrote_chunk = false
            while not all_speakers_wrote_chunk do
                all_speakers_wrote_chunk = true
                local has_active_speakers = false

                for _, dev in ipairs(audiodevices) do
                    if dev.speaker and not dev.dead then
                        has_active_speakers = true
                        if dev.cursor == current_chunk_to_write then
                            if not peripheral.isPresent(dev.name) then
                                dev.dead = true
                                debug_log(colors.red, "Speaker disconnected: " .. (dev.name or "unknown"))
                            else
                                if dev.speaker.playAudio(pcm_buffer, dev.volume) then
                                    dev.cursor = dev.cursor + 1
                                else
                                    all_speakers_wrote_chunk = false
                                end
                            end
                        end
                    end
                end

                if not has_active_speakers then
                    break
                end

                if not all_speakers_wrote_chunk then
                    sleep(0.05)
                end
            end

            os.queueEvent("chunk_consumed")
            current_chunk_to_write = current_chunk_to_write + 1

            ::continue_driver_loop::
        end
    end

    local function device_scanner()
        while not eof do
            sleep(5)
            if eof then return end
            local current_peripherals = peripheral.getNames()
            local current_speakers = {}
            local current_tapes = {}

            for _, name in ipairs(current_peripherals) do
                if peripheral.getType(name) == "speaker" then
                    current_speakers[name] = true
                elseif peripheral.getType(name) == "tape_drive" then
                    current_tapes[name] = true
                end
            end

            local function find_min_cursor()
                local min_c = write_index
                local has_active = false
                for _, d in ipairs(audiodevices) do
                    if not d.dead and d.cursor and d.cursor < min_c then
                        min_c = d.cursor
                        has_active = true
                    end
                end
                if has_active then return min_c else return math.max(1, write_index - 1) end
            end

            for name, _ in pairs(current_speakers) do
                local known = false
                for _, dev in ipairs(audiodevices) do
                    if dev.name == name then
                        known = true
                        if dev.dead then
                            dev.speaker = peripheral.wrap(name)
                            dev.dead = false
                            dev.cursor = find_min_cursor()
                            debug_log(colors.green, "Speaker reconnected: " .. name)
                        end
                        break
                    end
                end
                if not known then
                    local speaker = peripheral.wrap(name)
                    local dev = libs.serverapi.Speaker.new(speaker)
                    dev.name = name
                    if not dev:validate() then
                        dev:setLabel(title)
                        dev:setVolume(args.volume)
                        dev.cursor = find_min_cursor()
                        table.insert(audiodevices, dev)
                        debug_log(colors.green, "New speaker detected! (Joining now)")
                    end
                end
            end

             for name, _ in pairs(current_tapes) do
                local known = false
                for _, dev in ipairs(audiodevices) do
                    if dev.name == name then
                        known = true
                        if dev.dead then
                             dev.tape = peripheral.wrap(name)
                             dev.dead = false
                             dev.cursor = find_min_cursor()
                             debug_log(colors.green, "Tape drive reconnected: " .. name)
                        end
                        break
                    end
                end
                if not known then
                    local tape = peripheral.wrap(name)
                    local dev = libs.serverapi.Tape.new(tape)
                    dev.name = name
                    if not dev:validate() then
                        dev:setLabel(title)
                        dev:setVolume(args.volume)
                        dev.cursor = find_min_cursor()
                        table.insert(audiodevices, dev)
                        debug_log(colors.green, "New tape drive detected! (Will join next track)")
                    end
                end
            end
        end
    end

    local function seek_listener()
        while not eof do
            os.pullEvent("youcube:seek_reset")
            chunks = {}
            write_index = 1
            cleaned_up_until = 1
            current_chunk_to_write = 1
            seek_reset_requested = true
            for _, dev in ipairs(audiodevices) do
                dev.cursor = 1
            end
            if decoder and dfpwm and type(dfpwm.make_decoder) == "function" then
                decoder = dfpwm.make_decoder()
            end
        end
    end

    parallel.waitForAll(producer, device_scanner, speaker_driver, seek_listener, table.unpack(consumers))
end

-- #region playback controll vars
local back_buffer = {}
local max_back = settings.get("youcube.max_back") or 32
local queue = {}
local restart = false
-- #endregion

-- Settings Helper ─────────────────────────────────────────────────────────────

local function load_settings()
    local settings_data = {
        nickname = "",
        queue_via_dashboard = true
    }

    -- Legacy migration from /youcube_nickname.txt
    if fs.exists("/youcube_nickname.txt") then
        local f = fs.open("/youcube_nickname.txt", "r")
        if f then
            local nick = f.readAll():gsub("^%s*(.-)%s*$", "%1")
            f.close()
            if nick and nick ~= "" then
                settings_data.nickname = nick
            end
        end
        pcall(fs.delete, "/youcube_nickname.txt")
        local sf = fs.open("/ycfork_settings.txt", "w")
        if sf then
            sf.write(textutils.serialiseJSON(settings_data))
            sf.close()
        end
        return settings_data
    end

    if fs.exists("/ycfork_settings.txt") then
        local f = fs.open("/ycfork_settings.txt", "r")
        if f then
            local content = f.readAll()
            f.close()
            local parsed = textutils.unserialiseJSON(content)
            if type(parsed) == "table" then
                if parsed.nickname ~= nil then settings_data.nickname = tostring(parsed.nickname) end
                if parsed.queue_via_dashboard ~= nil then settings_data.queue_via_dashboard = (parsed.queue_via_dashboard == true) end
            end
        end
    end

    return settings_data
end

-- LevelOS-inspired UI Drawing Helpers ─────────────────────────────────────────

local function get_render_targets()
    local targets = { term }
    local mon = peripheral.find("monitor")
    if mon then table.insert(targets, mon) end
    return targets
end

local function draw_idle_screen(server_url, client_id, nickname, queue_via_dashboard)
    local targets = get_render_targets()
    pcall(function() serverapi:send({ action = "idle" }) end)
    libs.ui.draw_idle_screen(targets, server_url, client_id, nickname, _VERSION, queue_via_dashboard)
end

local function draw_audio_player_screen(data, args, scroll_pos, status_msg, elapsed_secs)
    local targets = get_render_targets()
    local nickname = load_settings().nickname
    libs.ui.draw_audio_screen(targets, data, args, scroll_pos, status_msg, _VERSION, serverapi.client_id, nickname, elapsed_secs)
end



-- keys
local skip_key = settings.get("youcube.keys.skip") or keys.d
local restart_key = settings.get("youcube.keys.restart") or keys.r
local back_key = settings.get("youcube.keys.back") or keys.a
local stop_key = settings.get("youcube.keys.stop") or keys.q

local function play(url)
    -- Refresh audio devices at the start of each track
    audiodevices = get_audiodevices()

    local exit_reason = "finished"

    -- Render initial loading state to keep UI active during buffering
    if args.no_video then
        draw_audio_player_screen({ title = "Loading track..." }, args)
    end
    local function request_media_once()
        if not args.no_video then
            serverapi:request_media(url, term.getSize())
        else
            serverapi:request_media(url)
        end

        local data
        local x, y = term.getCursorPos()

        while true do
            data = serverapi:receive()
            if data.action == "status" then
                os.queueEvent("youcube:status", data)
                term.setCursorPos(x, y)
                term.clearLine()
                term.write("Status: ")
                write_colored(data.message, colors.green)
                term.setTextColor(colors.white)
            elseif data.action == "error" then
                return nil, data
            else
                new_line()
            end

            if data.action == "media" then
                return data, nil
            end
        end
    end

    local data, err = request_media_once()
    if err and err.message == "Live video is not supported." and not args.no_video then
        args.no_video = true
        data, err = request_media_once()
    end
    if err then
        printError("Server Error: " .. err.message)
        return nil, "error"
    end

    if args.no_video then
        draw_audio_player_screen(data, args)
    else
        buffer_x, buffer_y = term.getCursorPos()
        term.write("Buffering Video: ")
        term.setTextColor(colors.lightGray)
        print(data.title)
        term.setTextColor(colors.white)
    end

    if not args.no_video then
        -- wait so the user can see the video title info before video starts
        sleep(1.5)
    end

    local video_buffer = libs.serverapi.Buffer.new(
        libs.serverapi.VideoFiller.new(serverapi, data.id, term.getSize()),
        60 -- Most videos run on 30 fps, so we store 2s of video.
    )

    local audio_buffer = libs.serverapi.Buffer.new(
        libs.serverapi.AudioFiller.new(serverapi, data.id),
        --[[
            We want to buffer 1024 chunks.
            One chunks is 16 bits.
            The server (with default settings) sends 32 chunks at once.
        ]]
        32
    )

    if args.verbose then
        term.clear()
        term.setCursorPos(1, 1)
        term.write("[DEBUG MODE]")
    end

    local start_time = os.clock()
    local function announce_playing()
        start_time = os.clock()
        pcall(function() serverapi:send({ action = "seek_notify", timestamp = 0 }) end)
    end

    local function fill_buffers()
        while true do
            if exit_reason ~= "finished" then
                return
            end

            if not args.no_audio then
                audio_buffer:fill()
            end

            if not args.no_video then
                video_buffer:fill()
            end

            if args.verbose then
                term.setCursorPos(1, ({ term.getSize() })[2])
                term.clearLine()
                term.write("Audio_Buffer: " .. #audio_buffer.buffer)
            end

            sleep(0.05)
        end
    end

    local function _play_video()
        if not args.no_video then
            local string_unpack
            if not string.unpack then
                string_unpack = libs.string_pack.unpack
            end

            os.queueEvent("youcube:vid_playing", data)
            libs.serverapi.play_vid(video_buffer, args.force_fps, string_unpack)
            os.queueEvent("youcube:vid_eof", data)
        end
    end

    local function _play_audio()
        if not args.no_audio then
            os.queueEvent("youcube:audio_playing", data)
            play_audio(audio_buffer, data.title, announce_playing)
            os.queueEvent("youcube:audio_eof", data)
        end
    end

    local function _play_media()
        os.queueEvent("youcube:playing")
        parallel.waitForAll(_play_video, _play_audio)
    end

    local function _hotkey_handler()
        while true do
            local event, key, p2, p3 = os.pullEvent()

            if event == "key" then
                if key == skip_key then
                    back_buffer[#back_buffer + 1] = url --finished playing, push the value to the back buffer
                    if #back_buffer > max_back then
                        table.remove(back_buffer, 1) --remove it from the front of the buffer
                    end
                    if not args.no_video then
                        libs.serverapi.reset_term()
                    end
                    exit_reason = "skip"
                    break
                elseif key == restart_key then
                    if not args.no_video then
                        libs.serverapi.reset_term()
                    end
                    exit_reason = "restart"
                    break
                elseif key == back_key then
                    if not args.no_video then
                        libs.serverapi.reset_term()
                    end
                    exit_reason = "back"
                    break
                elseif key == stop_key then
                    if not args.no_video then
                        libs.serverapi.reset_term()
                    end
                    exit_reason = "stop"
                    break
                end
            elseif event == "mouse_click" or event == "monitor_touch" then
                local action, param = libs.ui.resolve_click(event, key, p2, p3, true)
                if action == "seek" and param and data and data.duration and data.duration > 0 then
                    local max_seek = math.max(0, data.duration - 2)
                    local target_time = math.max(0, math.min(max_seek, param * data.duration))
                    local target_chunk = math.floor((target_time * 6000) / 16384)
                    if audio_buffer then
                        audio_buffer.buffer = {}
                        if audio_buffer.filler then
                            audio_buffer.filler.chunkindex = math.max(0, target_chunk)
                        end
                    end
                    start_time = os.clock() - target_time
                    os.queueEvent("youcube:seek_reset")
                    pcall(function() serverapi:send({ action = "seek_notify", timestamp = target_time }) end)
                    draw_audio_player_screen(data, args, 0, "Seeking...", target_time)
                elseif action == "vol_down" then
                    local new_v = math.max(0.0, (args.volume or 1.0) - 0.3)
                    os.queueEvent("youcube:set_volume", new_v)
                elseif action == "vol_up" then
                    local new_v = math.min(3.0, (args.volume or 1.0) + 0.3)
                    os.queueEvent("youcube:set_volume", new_v)
                elseif action == "stop" then
                    if not args.no_video then libs.serverapi.reset_term() end
                    exit_reason = "stop"
                    break
                elseif action == "skip" then
                    back_buffer[#back_buffer + 1] = url
                    if #back_buffer > max_back then table.remove(back_buffer, 1) end
                    if not args.no_video then libs.serverapi.reset_term() end
                    exit_reason = "skip"
                    break
                elseif action == "back" then
                    if not args.no_video then libs.serverapi.reset_term() end
                    exit_reason = "back"
                    break
                elseif action == "restart" then
                    if not args.no_video then libs.serverapi.reset_term() end
                    exit_reason = "restart"
                    break
                end
            elseif event == "youcube:stop_command" then
                if not args.no_video then
                    libs.serverapi.reset_term()
                end
                exit_reason = "stop"
                break
            elseif event == "youcube:skip_command" then
                back_buffer[#back_buffer + 1] = url
                if #back_buffer > max_back then
                    table.remove(back_buffer, 1)
                end
                if not args.no_video then
                    libs.serverapi.reset_term()
                end
                exit_reason = "skip"
                break
            elseif event == "websocket_message" then
                local content = p2 or key
                if type(content) == "string" and content:sub(1, 1) == "{" then
                    local data_msg = textutils.unserialiseJSON(content)
                    if data_msg then
                        if data_msg.action == "stop" then
                            if not args.no_video then libs.serverapi.reset_term() end
                            exit_reason = "stop"
                            break
                        elseif data_msg.action == "skip" then
                            back_buffer[#back_buffer + 1] = url
                            if #back_buffer > max_back then table.remove(back_buffer, 1) end
                            if not args.no_video then libs.serverapi.reset_term() end
                            exit_reason = "skip"
                            break
                        elseif data_msg.action == "restart" then
                            if not args.no_video then libs.serverapi.reset_term() end
                            exit_reason = "restart"
                            break
                        elseif data_msg.action == "seek" and data_msg.timestamp ~= nil then
                            if not data.is_live and data.duration and data.duration > 0 then
                                local max_seek = math.max(0, data.duration - 2)
                                local target_time = math.max(0, math.min(max_seek, tonumber(data_msg.timestamp) or 0))
                                local target_chunk = math.floor((target_time * 6000) / 16384)
                                if audio_buffer then
                                    audio_buffer.buffer = {}
                                    if audio_buffer.filler then
                                        audio_buffer.filler.chunkindex = math.max(0, target_chunk)
                                    end
                                end
                                if video_buffer then
                                    video_buffer.buffer = {}
                                    if video_buffer.filler then
                                        local target_frame = math.floor(target_time * (args.force_fps or 30))
                                        video_buffer.filler.frameindex = math.max(0, target_frame)
                                    end
                                end
                                start_time = os.clock() - target_time
                                os.queueEvent("youcube:seek_reset")
                                draw_audio_player_screen(data, args, 0, "Seeking...", target_time)
                            end
                        elseif data_msg.volume ~= nil then
                            os.queueEvent("youcube:set_volume", data_msg.volume)
                        end
                    end
                end
            elseif event == "youcube:set_volume" then
                local new_vol = key -- second return value from pullEvent is the volume
                if type(new_vol) == "number" then
                    args.volume = new_vol
                    for _, dev in ipairs(audiodevices) do
                        if dev.speaker and not dev.dead then
                            dev.volume = new_vol
                        end
                    end
                    if args.no_video then
                        draw_audio_player_screen(data, args)
                    else
                        print("Volume: " .. math.floor(new_vol / 3.0 * 100 + 0.5) .. "%")
                    end
                end
            elseif event == "youcube:restart_command" then
                if not args.no_video then libs.serverapi.reset_term() end
                exit_reason = "restart"
                break
            elseif event == "youcube:stop_command" then
                if not args.no_video then libs.serverapi.reset_term() end
                exit_reason = "stop"
                break
            elseif event == "youcube:skip_command" then
                back_buffer[#back_buffer + 1] = url
                if #back_buffer > max_back then table.remove(back_buffer, 1) end
                if not args.no_video then libs.serverapi.reset_term() end
                exit_reason = "skip"
                break
            end
        end
    end

    local function _ui_ticker()
        local tick = 0
        while true do
            sleep(0.35)
            tick = tick + 1
            if args.no_video then
                local elapsed = os.clock() - start_time
                draw_audio_player_screen(data, args, tick, nil, elapsed)
            end
        end
    end

    -- Run everything in parallel; any coroutine finishing stops all others.
    parallel.waitForAny(fill_buffers, _play_media, _hotkey_handler, _ui_ticker)

    if serverapi.pending_command then
        exit_reason = serverapi.pending_command
        serverapi.pending_command = nil
    end

    if exit_reason == "finished" then
        back_buffer[#back_buffer + 1] = url
        if #back_buffer > max_back then
            table.remove(back_buffer, 1)
        end
    end

    return data.playlist_videos, exit_reason
end

local function shuffle_playlist(playlist)
    local shuffled = {}
    for i = 1, #queue do
        local pos = math.random(1, #shuffled + 1)
        shuffled[pos] = queue[i]
    end
    return shuffled
end

local function play_playlist(playlist)
    queue = playlist
    if args.shuffle then
        queue = shuffle_playlist(queue)
    end
    while #queue ~= 0 do
        local pl = table.remove(queue, 1)

        local _, reason = play(pl)

        if reason == "restart" then
             table.insert(queue, 1, pl)
        elseif reason == "back" then
             table.insert(queue, 1, pl)
             local prev = table.remove(back_buffer)
             if prev then
                 table.insert(queue, 1, prev)
             end
        elseif reason == "stop" then
             queue = {}
             break
        end
    end
end

local function draw_reconnect_screen(server_url, client_id, nickname, mode, seconds_left)
    local targets = get_render_targets()
    libs.ui.draw_reconnect_screen(targets, server_url, client_id, nickname, _VERSION, mode, seconds_left)
end

local function ensure_connected(force_mode)
    local initial_mode = force_mode or "unreachable"
    while true do
        local ok = pcall(function()
            if serverapi.websocket and type(serverapi.websocket.send) == "function" then
                return true
            end
            serverapi:detect_bestest_server(args.server, args.verbose, args.volume)
        end)

        if ok and serverapi.websocket then
            return true
        end

        local settings_data = load_settings()
        local nickname = settings_data.nickname
        local server_url = serverapi.server_url or args.server or "Server"
        local client_id = serverapi.client_id or "unknown"

        for cd = 5, 1, -1 do
            draw_reconnect_screen(server_url, client_id, nickname, initial_mode, cd)
            
            local timer_id = os.startTimer(1)
            while true do
                local event, p1, p2, p3 = os.pullEvent()
                if event == "timer" and p1 == timer_id then
                    break
                elseif event == "key" then
                    if p1 == keys.q or p1 == keys.x then
                        error("Terminated")
                    end
                elseif event == "mouse_click" or event == "monitor_touch" then
                    local click_x, click_y = p2, p3
                    local targets = get_render_targets()
                    local w, h = targets[1].getSize()
                    if click_x >= w - 11 and click_y == h then
                        error("Terminated")
                    end
                end
            end
        end
    end
end

local function main()
    ensure_connected("unreachable")
    pcall(update_checker)

    local default_no_video = args.no_video
    local default_no_audio = args.no_audio

    while true do
        local run_ok, run_err = pcall(function()
            ensure_connected("lost")
            if not args.URL or args.URL == "" then
                args.no_video = default_no_video
                args.no_audio = default_no_audio
                if not args.no_video then
                    libs.serverapi.reset_term()
                end
                local queued = serverapi:get_queued_media()
                if queued and queued.url then
                    args.URL = queued.url
                    if queued.no_video ~= nil then
                        args.no_video = queued.no_video
                    end
                else
                    local settings_data = load_settings()
                    local nickname = settings_data.nickname
                    local server_url = serverapi.server_url or (serverapi.websocket and serverapi.websocket.url) or args.server or "Server"
                    local client_id = serverapi.client_id or "unknown"
                    draw_idle_screen(server_url, client_id, nickname, settings_data.queue_via_dashboard)

                    parallel.waitForAny(
                        function()
                            args.URL = read()
                        end,
                        function()
                            while true do
                                sleep(2)
                                local q = serverapi:get_queued_media()
                                if q and q.url then
                                    args.URL = q.url
                                    if q.no_video ~= nil then
                                        args.no_video = q.no_video
                                    end
                                    break
                                end
                            end
                        end
                    )
                end
                term.setTextColor(colors.white)
                if not args.URL or args.URL:match("^%s*$") then
                    return "exit"
                end
            end

            local current_url = args.URL
            while current_url do
                local playlist_videos, reason = play(current_url)

                if reason == "restart" or (reason == "finished" and args.loop == true) then
                    -- loop again with the same url
                elseif reason == "back" then
                    local prev = table.remove(back_buffer)
                    if prev then
                        current_url = prev
                    else
                        print("No previous track in history.")
                    end
                else
                    -- reason is "skip" or "finished"
                    if playlist_videos then
                        if args.loop_playlist == true then
                            while true do
                                play_playlist(playlist_videos)
                            end
                        else
                            play_playlist(playlist_videos)
                        end
                    end
                    current_url = nil
                end
            end

            args.URL = nil
        end)

        if not run_ok then
            if tostring(run_err):find("Terminated") then
                error("Terminated")
            end
            serverapi.websocket = nil
            args.URL = nil
            ensure_connected("lost")
        end
    end

    if serverapi and serverapi.websocket then
        pcall(function() serverapi.websocket.close() end)
    end

    if not args.no_video then
        libs.serverapi.reset_term()
    end

    os.queueEvent("youcube:playback_ended")
end

local ok, err = pcall(main)

if serverapi and serverapi.websocket then
    pcall(function() serverapi.websocket.close() end)
end

if not args.no_video then
    pcall(function() libs.serverapi.reset_term() end)
end

if not ok then
    if err == "Terminated" then
        printError("Terminated")
    else
        error(err, 0)
    end
end
