--[[
YC-Client-Fork
]]

local _VERSION = "0.1.2"

local function is_lib(libs, lib)
    for i = 1, #libs do
        local value = libs[i]
        if value == lib or value .. ".lua" == lib then
            return true, value
        end
    end
    return false
end

local libs = { "serverapi", "numberformatter", "semver", "argparse", "string_pack" }
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

    local notified = false
    local eof = false

    local function producer()
        while true do
            local min_cursor = write_index
            local has_active = false

            for _, dev in ipairs(audiodevices) do
                if not dev.dead then
                    if not dev.cursor then dev.cursor = write_index end
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
                os.pullEvent("chunk_consumed")
            else
                local chunk = buffer:next()

                if buffer.filler.chunkindex == 1 then
                    buffer.size = math.ceil(1024 / (#chunk / 16))
                end

                if chunk == "" then
                    eof = true
                    os.queueEvent("new_audio_chunk")
                    return
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
        local current_chunk_to_write = 1
        while true do
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
                os.pullEvent("new_audio_chunk")
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
                    os.pullEvent("speaker_audio_empty")
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

    parallel.waitForAll(producer, device_scanner, speaker_driver, table.unpack(consumers))
end

-- #region playback controll vars
local back_buffer = {}
local max_back = settings.get("youcube.max_back") or 32
local queue = {}
local restart = false
-- #endregion

-- keys
local skip_key = settings.get("youcube.keys.skip") or keys.d
local restart_key = settings.get("youcube.keys.restart") or keys.r
local back_key = settings.get("youcube.keys.back") or keys.a

local function play(url)
    -- Refresh audio devices at the start of each track
    audiodevices = get_audiodevices()

    local exit_reason = "finished"

    print("Requesting media ...")
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

    local buffer_x, buffer_y

    local function announce_playing()
        local cur_x, cur_y = term.getCursorPos()
        if buffer_x and buffer_y then
            term.setCursorPos(buffer_x, buffer_y)
            term.clearLine()
        end
        term.write("Playing: ")
        term.setTextColor(colors.lime)
        print(data.title)
        term.setTextColor(colors.white)
        if buffer_x and buffer_y then
            term.setCursorPos(cur_x, cur_y)
        end
    end

    if args.no_audio then
        announce_playing()
    else
        buffer_x, buffer_y = term.getCursorPos()
        term.write("Buffering: ")
        term.setTextColor(colors.lightGray)
        print(data.title)
        term.setTextColor(colors.white)
    end

    if data.like_count then
        print("Likes: " .. libs.numberformatter.compact(data.like_count))
    end

    if data.view_count then
        print("Views: " .. libs.numberformatter.compact(data.view_count))
    end

    if not args.no_video then
        -- wait, that the user can see the video info
        sleep(2)
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

    local function fill_buffers()
        while true do
            os.queueEvent("youcube:fill_buffers")

            local event = os.pullEventRaw()

            if event == "terminate" then
                libs.serverapi.reset_term()
            end

            if not args.no_audio then
                audio_buffer:fill()
            end

            if args.verbose then
                term.setCursorPos(1, ({ term.getSize() })[2])
                term.clearLine()
                term.write("Audio_Buffer: " .. #audio_buffer.buffer)
            end

            if not args.no_video then
                video_buffer:fill()
            end
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
            local _, key = os.pullEvent("key")

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
            end

            if key == restart_key then
                if not args.no_video then
                    libs.serverapi.reset_term()
                end
                exit_reason = "restart"
                break
            end

             if key == back_key then
                 if not args.no_video then
                     libs.serverapi.reset_term()
                 end
                 exit_reason = "back"
                 break
            end
        end
    end

    -- Reverting parallel structure to allow hotkeys to interrupt playback
    parallel.waitForAny(fill_buffers, _play_media, _hotkey_handler)

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
        end
    end
end

local function main()
    serverapi:detect_bestest_server(args.server, args.verbose)
    pcall(update_checker)

    while true do
        if not args.URL or args.URL == "" then
            if not args.no_video then
                libs.serverapi.reset_term()
            end
            local queued = serverapi:get_queued_media()
            if queued and queued.url then
                args.URL = queued.url
            else
                print("Enter a URL or search term (YouTube/Spotify/live streams supported). Controls: R=repeat, A=previous, D=next.")
                write_colored("URL/Search: ", colors.lightGray)
                parallel.waitForAny(
                    function()
                        args.URL = read()
                    end,
                    function()
                        while true do
                            local msg = serverapi:receive("play")
                            if msg and msg.url then
                                args.URL = msg.url
                                break
                            end
                        end
                    end
                )
            end
            term.setTextColor(colors.white)
            if not args.URL or args.URL:match("^%s*$") then
                break
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
    end

    serverapi.websocket.close()

    if not args.no_video then
        libs.serverapi.reset_term()
    end

    os.queueEvent("youcube:playback_ended")
end

main()
