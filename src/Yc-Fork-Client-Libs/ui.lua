--[[
YC-Fork UI Library v2.00.001
Handles responsive terminal and monitor UI rendering, scaling, and click resolution.
]]

local UI = {}

-- Helper to format seconds to M:SS or H:MM:SS
local function format_duration(seconds)
    if not seconds or type(seconds) ~= "number" or seconds < 0 then return nil end
    local s = math.floor(seconds)
    local hrs = math.floor(s / 3600)
    local mins = math.floor((s % 3600) / 60)
    local secs = s % 60
    if hrs > 0 then
        return string.format("%d:%02d:%02d", hrs, mins, secs)
    else
        return string.format("%d:%02d", mins, secs)
    end
end

-- Helper to format view/like counts into clean compact strings (e.g. 371.4M, 1.2k)
local function format_compact(num)
    if not num or type(num) ~= "number" then return nil end
    local n = math.abs(num)
    if n >= 1000000000 then
        return string.format("%.1fB", n / 1000000000):gsub("%.0B", "B")
    elseif n >= 1000000 then
        return string.format("%.1fM", n / 1000000):gsub("%.0M", "M")
    elseif n >= 1000 then
        return string.format("%.1fk", n / 1000):gsub("%.0k", "k")
    else
        return tostring(math.floor(n))
    end
end

-- Renders the top header bar (Rows 1 & 2) with vibrant colors
local function render_header_bar(tgt, version, client_id, nickname, server_url)
    local w, h = tgt.getSize()
    local is_color = tgt.isColor()

    if is_color then
        -- Row 1: App Title (Black) & Version (Dark Gray) on vibrant Aqua/Cyan background
        tgt.setCursorPos(1, 1)
        tgt.setBackgroundColor(colors.cyan)
        tgt.write(string.rep(" ", w))
        tgt.setCursorPos(2, 1)
        tgt.setTextColor(colors.black)
        tgt.write(string.char(14) .. " YC-Fork Player")
        tgt.setTextColor(colors.gray)
        tgt.write(" v" .. tostring(version or "2.00.001"))

        -- Row 2: Client ID (White) & Server URL (Cyan) on Dark Gray background
        tgt.setCursorPos(1, 2)
        tgt.setBackgroundColor(colors.gray)
        tgt.write(string.rep(" ", w))

        tgt.setCursorPos(2, 2)
        tgt.setTextColor(colors.white)
        local client_str = "Client: " .. tostring(client_id or "unknown")
        if nickname and nickname ~= "" then
            client_str = client_str .. " (" .. nickname .. ")"
        end
        tgt.write(client_str)

        local raw_server = tostring(server_url or "Server")
        if raw_server and raw_server ~= "" and raw_server ~= "Server" then
            local display_server = raw_server:gsub("^wss?://", ""):gsub("^https?://", "")
            local sep_x = 2 + #client_str + 2
            if sep_x + #display_server <= w - 1 then
                tgt.setCursorPos(sep_x - 1, 2)
                tgt.setTextColor(colors.lightGray)
                tgt.write("| ")
                tgt.setTextColor(colors.cyan)
                tgt.write(display_server)
            end
        end
    else
        tgt.setCursorPos(1, 1)
        tgt.write("=== YC-Fork Player v" .. tostring(version or "2.00.001") .. " ===\n")
    end
end

-- Renders the idle screen to a specific target
function UI.render_idle_to_target(tgt, server_url, client_id, nickname, version, queue_via_dashboard)
    if not tgt then return end
    local w, h = tgt.getSize()
    tgt.setBackgroundColor(colors.black)
    tgt.clear()

    render_header_bar(tgt, version, client_id, nickname, server_url)

    -- Prompt instruction card (Black background)
    tgt.setBackgroundColor(colors.black)
    
    tgt.setCursorPos(2, 4)
    tgt.setTextColor(colors.yellow)
    tgt.write("READY TO PLAY!")

    tgt.setCursorPos(2, 5)
    tgt.setTextColor(colors.white)
    local line1 = "Enter YouTube/Spotify URL"
    if #line1 > w - 3 then line1 = line1:sub(1, w - 3) end
    tgt.write(line1)

    tgt.setCursorPos(2, 6)
    tgt.setTextColor(colors.lightGray)
    local line2 = "or search query below:"
    if #line2 > w - 3 then line2 = line2:sub(1, w - 3) end
    tgt.write(line2)

    tgt.setCursorPos(2, 8)
    tgt.setTextColor(colors.lime)
    tgt.write("URL/Search > ")
    tgt.setTextColor(colors.white)
end

-- Renders the active media audio player screen to a specific target
function UI.render_audio_to_target(tgt, data, args, scroll_pos, status_msg, version, client_id, nickname, elapsed_secs)
    if not tgt then return end
    local w, h = tgt.getSize()
    local is_color = tgt.isColor()

    if tgt.setCursorBlink then tgt.setCursorBlink(false) end
    tgt.setBackgroundColor(colors.black)
    tgt.clear()

    if is_color then
        -- 1. Header Bar (Rows 1 & 2)
        local s_url = (args and args.server)
        if not s_url or s_url == "" or s_url == "Server" then
            local sapi = package.loaded["serverapi"] or _G.serverapi
            if sapi and sapi.server_url then s_url = sapi.server_url end
        end
        render_header_bar(tgt, version, client_id, nickname, s_url)

        -- 2. Now Playing Banner (Rows 3 & 4 in Purple/Navy)
        tgt.setBackgroundColor(colors.purple)
        tgt.setTextColor(colors.white)
        tgt.setCursorPos(1, 3)
        tgt.write(string.rep(" ", w))
        tgt.setCursorPos(1, 4)
        tgt.write(string.rep(" ", w))

        -- Row 3: NOW PLAYING Header
        tgt.setCursorPos(2, 3)
        tgt.setTextColor(colors.yellow)
        tgt.write("NOW PLAYING:")

        -- Row 4: Track Title on its OWN line (with scrolling marquee)
        tgt.setCursorPos(2, 4)
        tgt.setTextColor(colors.white)
        local raw_title = (data and data.title) or "Loading Track..."
        local max_title_w = math.max(10, w - 3)
        local display_title = raw_title

        if #raw_title > max_title_w then
            local padded = raw_title .. "   *   " .. raw_title
            local idx = ((scroll_pos or 0) % (#raw_title + 7)) + 1
            display_title = padded:sub(idx, idx + max_title_w - 1)
        end
        tgt.write(display_title)

        -- 3. Metadata Row (Row 5 - Channel / Likes / Views formatted cleanly)
        tgt.setBackgroundColor(colors.black)
        tgt.setCursorPos(2, 5)
        tgt.setTextColor(colors.lightGray)
        local meta_parts = {}
        if data and data.channel then table.insert(meta_parts, "By: " .. tostring(data.channel)) end
        if data and data.view_count then
            local fmt_views = format_compact(data.view_count)
            if fmt_views then table.insert(meta_parts, "Views: " .. fmt_views) end
        end
        if data and data.like_count then
            local fmt_likes = format_compact(data.like_count)
            if fmt_likes then table.insert(meta_parts, "Likes: " .. fmt_likes) end
        end
        
        local meta_str = table.concat(meta_parts, "  |  ")
        local max_meta_w = math.max(10, w - 3)
        local display_meta = meta_str

        if #meta_str > max_meta_w then
            local padded = meta_str .. "   *   " .. meta_str
            local idx = ((scroll_pos or 0) % (#meta_str + 7)) + 1
            display_meta = padded:sub(idx, idx + max_meta_w - 1)
        end
        tgt.write(display_meta)

        -- 4. Progress Bar & Duration Row (Row 6 - Clickable for Seek/Skip!)
        tgt.setCursorPos(2, 6)
        tgt.setTextColor(colors.lightGray)
        tgt.write("Progress: ")

        local duration = data and data.duration
        local elapsed = elapsed_secs or 0
        local bar_w = math.max(4, math.min(14, w - 28))

        if duration and type(duration) == "number" and duration > 0 then
            local pct = math.min(1.0, math.max(0.0, elapsed / duration))
            local filled = math.floor(pct * bar_w)
            tgt.setTextColor(colors.lime)
            tgt.write("[" .. string.rep("=", filled) .. (filled < bar_w and ">" or "") .. string.rep("-", math.max(0, bar_w - filled - 1)) .. "] ")
            tgt.setTextColor(colors.white)
            tgt.write(format_duration(elapsed) .. " / " .. format_duration(duration))
        else
            tgt.setTextColor(colors.cyan)
            tgt.write("[" .. string.rep("=", bar_w) .. "] ")
            tgt.setTextColor(colors.white)
            tgt.write(format_duration(elapsed) or "0:00")
        end

        -- 5. Volume Bar Row (Row 7 - with [-] and [+] buttons)
        tgt.setCursorPos(2, 7)
        tgt.setTextColor(colors.lightGray)
        tgt.write("Volume:   ")
        tgt.setTextColor(colors.red)
        tgt.write("[-] ")

        local vol_pct = math.floor(((args and args.volume) or 1.0) / 3.0 * 100 + 0.5)
        local vol_bar_w = math.max(4, math.min(12, w - 26))
        if vol_bar_w > 0 then
            local filled = math.floor(vol_pct / 100 * vol_bar_w)
            tgt.setTextColor(colors.lime)
            tgt.write("[" .. string.rep("=", filled) .. string.rep("-", vol_bar_w - filled) .. "] ")
        end
        tgt.setTextColor(colors.green)
        tgt.write("[+] ")
        tgt.setTextColor(colors.white)
        tgt.write(vol_pct .. "%")

        -- 6. Status Row (Row 8)
        tgt.setCursorPos(2, 8)
        tgt.setTextColor(colors.lightGray)
        tgt.write("Status:   ")
        tgt.setTextColor(colors.lime)
        tgt.write(status_msg or "Playing Audio")

        -- 7. Bottom Control Buttons Bar (Dynamically centered for width w)
        local btn_y = math.max(1, h - 1)
        tgt.setCursorPos(1, btn_y)
        tgt.setBackgroundColor(colors.black)
        tgt.write(string.rep(" ", w))
        tgt.setCursorPos(1, h)
        tgt.write(string.rep(" ", w))

        local is_wide = w >= 48
        local is_med = w >= 34
        local btn_defs = {
            { text = (is_wide and " Stop (Q) " or (is_med and " Stop " or " [Q] ")), bg = colors.red, fg = colors.white },
            { text = (is_wide and " Skip (D) " or (is_med and " Skip " or " [D] ")), bg = colors.lime, fg = colors.black },
            { text = (is_wide and " Back (A) " or (is_med and " Back " or " [A] ")), bg = colors.blue, fg = colors.white },
            { text = (is_wide and " Repeat (R) " or (is_med and " Repeat " or " [R] ")), bg = colors.orange, fg = colors.black },
        }

        local total_len = 0
        for _, b in ipairs(btn_defs) do total_len = total_len + #b.text end

        local gap = math.max(1, math.floor((w - total_len) / 5))
        local cur_x = math.max(1, math.floor((w - (total_len + gap * 3)) / 2))

        for _, b in ipairs(btn_defs) do
            if cur_x + #b.text - 1 <= w then
                tgt.setCursorPos(cur_x, btn_y)
                tgt.setBackgroundColor(b.bg)
                tgt.setTextColor(b.fg)
                tgt.write(b.text)
                cur_x = cur_x + #b.text + gap
            end
        end

        tgt.setBackgroundColor(colors.black)
        tgt.setTextColor(colors.white)
    else
        tgt.setCursorPos(1, 1)
        tgt.write("Playing: " .. (data and data.title or "Audio") .. "\n")
        tgt.write("Volume: " .. math.floor(((args and args.volume) or 1.0) / 3.0 * 100 + 0.5) .. "%\n")
        tgt.write("Controls: [Q] Stop | [D] Skip | [A] Back | [R] Repeat\n")
    end
end

-- Draw idle screen on all connected targets
function UI.draw_idle_screen(targets, server_url, client_id, nickname, version, queue_via_dashboard)
    for _, tgt in ipairs(targets) do
        if tgt and type(tgt.getSize) == "function" then
            if tgt ~= term and tgt.setTextScale then
                pcall(tgt.setTextScale, tgt, 0.5)
            end
            UI.render_idle_to_target(tgt, server_url, client_id, nickname, version, queue_via_dashboard)
        end
    end
end

-- Draw audio player screen on all connected targets
function UI.draw_audio_screen(targets, data, args, scroll_pos, status_msg, version, client_id, nickname, elapsed_secs)
    if args and not args.no_video then return end -- Keep video 100% clean

    for _, tgt in ipairs(targets) do
        if tgt and type(tgt.getSize) == "function" then
            if tgt ~= term and tgt.setTextScale then
                pcall(tgt.setTextScale, tgt, 0.5)
            end
            UI.render_audio_to_target(tgt, data, args, scroll_pos, status_msg, version, client_id, nickname, elapsed_secs)
        end
    end
end

-- Resolves a click event (mouse_click or monitor_touch) to an action
function UI.resolve_click(event, p1, p2, p3, is_playing)
    if event ~= "mouse_click" and event ~= "monitor_touch" then return nil end

    local w, h
    local click_x, click_y = p2, p3

    if event == "mouse_click" then
        w, h = term.getSize()
    elseif event == "monitor_touch" then
        local side = p1
        local mon = peripheral.wrap(side) or peripheral.find("monitor")
        if mon then
            w, h = mon.getSize()
        else
            w, h = term.getSize()
        end
    end

    if not w or not h then return nil end

    -- Progress Bar Row (Row 6) - Click to Seek!
    if is_playing and click_y == 6 then
        local bar_w = math.max(4, math.min(14, w - 28))
        local bar_start = 12
        if click_x >= bar_start and click_x <= bar_start + bar_w + 1 then
            local rel_x = click_x - bar_start
            local ratio = math.max(0.0, math.min(1.0, rel_x / math.max(1, bar_w)))
            return "seek", ratio
        end
    end

    -- Volume Buttons on Row 7 (Dynamically calculated based on target width w)
    if is_playing and click_y == 7 then
        local vol_bar_w = math.max(4, math.min(12, w - 26))
        local plus_x = 16 + vol_bar_w + 3

        -- [-] Button (x = 11 .. 15)
        if click_x >= 11 and click_x <= 15 then
            return "vol_down"
        -- [+] Button (x = plus_x - 1 .. plus_x + 4)
        elseif click_x >= plus_x - 1 and click_x <= plus_x + 4 then
            return "vol_up"
        end
    end

    -- Bottom Control Buttons (Row h-1 or Row h)
    if is_playing and click_y >= h - 1 then
        local is_wide = w >= 48
        local is_med = w >= 34
        local btn_specs = {
            { len = (is_wide and 10 or (is_med and 6 or 5)), action = "stop" },
            { len = (is_wide and 10 or (is_med and 6 or 5)), action = "skip" },
            { len = (is_wide and 10 or (is_med and 6 or 5)), action = "back" },
            { len = (is_wide and 12 or (is_med and 8 or 5)), action = "restart" },
        }

        local total_len = (is_wide and 42 or (is_med and 26 or 20))
        local gap = math.max(1, math.floor((w - total_len) / 5))
        local cx = math.max(1, math.floor((w - (total_len + gap * 3)) / 2))

        for _, b in ipairs(btn_specs) do
            if click_x >= cx and click_x <= cx + b.len - 1 then
                return b.action
            end
            cx = cx + b.len + gap
        end
    end

    return nil
end

function UI.draw_reconnect_screen(targets, server_url, client_id, nickname, version, mode, seconds_left)
    for _, tgt in ipairs(targets or { term }) do
        local w, h = tgt.getSize()
        tgt.setBackgroundColor(colors.black)
        tgt.clear()

        -- Row 1: App Title (Black) & Version (Dark Gray) on vibrant Aqua/Cyan background
        tgt.setCursorPos(1, 1)
        tgt.setBackgroundColor(colors.cyan)
        tgt.write(string.rep(" ", w))
        tgt.setCursorPos(2, 1)
        tgt.setTextColor(colors.black)
        tgt.write(string.char(14) .. " YC-Fork Player")
        tgt.setTextColor(colors.gray)
        tgt.write(" v" .. tostring(version or "2.00.001"))

        -- Row 2: Client ID (White) & Server URL (Cyan) on Dark Gray background
        tgt.setCursorPos(1, 2)
        tgt.setBackgroundColor(colors.gray)
        tgt.write(string.rep(" ", w))

        tgt.setCursorPos(2, 2)
        tgt.setTextColor(colors.white)
        local client_str = "Client: " .. tostring(client_id or "unknown")
        if nickname and nickname ~= "" then
            client_str = client_str .. " (" .. nickname .. ")"
        end
        tgt.write(client_str)

        local raw_server = tostring(server_url or "Server")
        if raw_server and raw_server ~= "" and raw_server ~= "Server" then
            local display_server = raw_server:gsub("^wss?://", ""):gsub("^https?://", "")
            local sep_x = 2 + #client_str + 2
            if sep_x + #display_server <= w - 1 then
                tgt.setCursorPos(sep_x - 1, 2)
                tgt.setTextColor(colors.lightGray)
                tgt.write("| ")
                tgt.setTextColor(colors.cyan)
                tgt.write(display_server)
            end
        end

        -- Reconnect Card Header (Row 4 - Red Background)
        tgt.setBackgroundColor(colors.red)
        tgt.setCursorPos(1, 4)
        tgt.clearLine()
        tgt.setTextColor(colors.white)
        
        local title_msg = "[!] SERVER UNREACHABLE"
        if mode == "lost" then
            title_msg = "[!] CONNECTION TO SERVER LOST"
        end
        
        tgt.setCursorPos(math.max(2, math.floor((w - #title_msg) / 2)), 4)
        tgt.write(title_msg)

        -- Reconnect Card Body (Row 5 - Gray Background)
        tgt.setBackgroundColor(colors.gray)
        tgt.setCursorPos(1, 5)
        tgt.clearLine()
        tgt.setTextColor(colors.yellow)

        local sub_msg = "Retrying in " .. tostring(seconds_left or 5) .. "s..."
        tgt.setCursorPos(math.max(2, math.floor((w - #sub_msg) / 2)), 5)
        tgt.write(sub_msg)

        -- Bottom Exit Button (Row h - Right Aligned Red Button)
        local btn_str = " Exit (Q) "
        tgt.setBackgroundColor(colors.black)
        tgt.setCursorPos(1, h)
        tgt.clearLine()
        tgt.setCursorPos(math.max(1, w - #btn_str), h)
        tgt.setBackgroundColor(colors.red)
        tgt.setTextColor(colors.white)
        tgt.write(btn_str)
    end
end

return UI
