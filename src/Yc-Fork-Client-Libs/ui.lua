local ui = {}

function ui.make_ui_handler(data, audiodevices, back_key, stop_key, skip_key, initial_volume)
    local ui_volume = initial_volume or 1.0

    return function()
        -- Find first attached monitor
        local mon = nil
        local mon_name = nil
        for _, pname in ipairs(peripheral.getNames()) do
            if peripheral.getType(pname) == "monitor" then
                mon = peripheral.wrap(pname)
                mon_name = pname
                break
            end
        end
        if mon and mon.setTextScale then
            pcall(mon.setTextScale, mon, 0.5)
        end

        local has_colour = term.isColour()

        -- Volume helper
        local function apply_vol(v)
            ui_volume = math.max(0.0, math.min(3.0, v))
            for _, dev in ipairs(audiodevices) do
                if dev.speaker and not dev.dead then
                    dev.volume = ui_volume
                end
            end
        end

        -- Monitor UI buttons
        local mon_btns = {}

        local function mon_btn(x, y, w, h, action, bg, fg, label)
            mon_btns[#mon_btns + 1] = {x=x, y=y, w=w, h=h, action=action}
            if mon then
                mon.setBackgroundColor(bg)
                mon.setTextColor(fg)
                for row = y, y + h - 1 do
                    mon.setCursorPos(x, row)
                    mon.write(string.rep(" ", w))
                end
                local mid = y + math.floor(h / 2)
                local lx = x + math.floor((w - #label) / 2)
                mon.setCursorPos(math.max(x, lx), mid)
                mon.write(label:sub(1, w))
            end
        end

        local function draw_monitor()
            if not mon then return end
            mon_btns = {}
            local mw, mh = mon.getSize()

            mon.setBackgroundColor(colors.black)
            mon.clear()

            -- Header
            mon.setBackgroundColor(colors.purple)
            mon.setCursorPos(1, 1)
            mon.write(string.rep(" ", mw))
            mon.setCursorPos(2, 1)
            mon.setTextColor(colors.white)
            mon.write(string.char(14) .. " YC-Fork")

            -- Title
            mon.setBackgroundColor(colors.gray)
            mon.setCursorPos(1, 2)
            mon.write(string.rep(" ", mw))
            mon.setCursorPos(2, 2)
            mon.setTextColor(colors.white)
            local title_str = (data and data.title) or "Nothing playing"
            if #title_str > mw - 2 then title_str = title_str:sub(1, mw - 5) .. "..." end
            mon.write(title_str)

            -- Control buttons row
            local brow = 4
            local gap = 1
            local bw = math.floor((mw - 2 * gap) / 3) - 1
            local bh = 2
            local bx = 1
            mon_btn(bx,      brow, bw, bh, "back", colors.blue,   colors.white, "< Back")
            mon_btn(bx+bw+1, brow, bw, bh, "stop", colors.red,    colors.white, "[ Stop ]")
            mon_btn(bx+bw*2+2, brow, mw-(bx+bw*2+1), bh, "skip", colors.lime, colors.black, "Skip >")

            -- Volume label
            local vrow = brow + bh + 2
            local vol_pct = math.floor(ui_volume / 3.0 * 100 + 0.5)
            mon.setBackgroundColor(colors.black)
            mon.setTextColor(colors.lightGray)
            mon.setCursorPos(1, vrow)
            mon.write(" Volume: ")
            mon.setTextColor(colors.white)
            mon.write(vol_pct .. "%  ")

            -- Volume bar
            local vbar_row = vrow + 1
            mon_btn(1, vbar_row, 3, 1, "vol_down", colors.gray, colors.white, "[-]")
            mon_btn(mw - 2, vbar_row, 3, 1, "vol_up", colors.gray, colors.white, "[+]")

            local bar_x1 = 4
            local bar_x2 = mw - 3
            local bar_w  = bar_x2 - bar_x1 + 1
            local filled = math.floor(vol_pct / 100 * bar_w)
            mon_btns[#mon_btns + 1] = {x=bar_x1, y=vbar_row, w=bar_w, h=1, action="vol_slider"}
            mon.setCursorPos(bar_x1, vbar_row)
            mon.setBackgroundColor(colors.purple)
            mon.setTextColor(colors.white)
            mon.write(string.rep("\127", filled))
            mon.setBackgroundColor(colors.gray)
            mon.write(string.rep(" ", bar_w - filled))
        end

        -- Terminal control bar
        local term_btns = {}

        local function draw_term_bar()
            if not has_colour then return end
            term_btns = {}
            local tw, th = term.getSize()
            local by = th
            local cx, cy = term.getCursorPos()

            local function tbtn(tx, lbl, bg, fg, action)
                term.setCursorPos(tx, by)
                term.setBackgroundColor(bg)
                term.setTextColor(fg)
                term.write(lbl)
                term_btns[#term_btns + 1] = {x=tx, y=by, w=#lbl, action=action}
                return tx + #lbl + 1
            end

            term.setCursorPos(1, by)
            term.setBackgroundColor(colors.gray)
            term.write(string.rep(" ", tw))

            local x = 1
            x = tbtn(x, " < ", colors.blue, colors.white, "back")
            x = tbtn(x, " X ", colors.red,  colors.white, "stop")
            x = tbtn(x, " > ", colors.lime, colors.black, "skip")
            x = tbtn(x, "[-]", colors.gray, colors.white, "vol_down")

            local bar_x = x
            local bar_w  = math.min(12, tw - x - 8)
            if bar_w > 0 then
                local vol_pct = math.floor(ui_volume / 3.0 * 100 + 0.5)
                local filled  = math.floor(vol_pct / 100 * bar_w)
                term.setCursorPos(bar_x, by)
                term.setBackgroundColor(colors.purple)
                term.write(string.rep("=", filled))
                term.setBackgroundColor(colors.gray)
                term.write(string.rep("-", bar_w - filled))
                term_btns[#term_btns + 1] = {x=bar_x, y=by, w=bar_w, action="vol_slider"}
                x = bar_x + bar_w + 1
            end

            x = tbtn(x, "[+]", colors.gray, colors.white, "vol_up")

            term.setCursorPos(x, by)
            term.setBackgroundColor(colors.gray)
            term.setTextColor(colors.lightGray)
            local vol_pct = math.floor(ui_volume / 3.0 * 100 + 0.5)
            term.write(vol_pct .. "%")

            term.setBackgroundColor(colors.black)
            term.setTextColor(colors.white)
            term.setCursorPos(cx, cy)
        end

        draw_monitor()
        draw_term_bar()

        local redraw_timer = os.startTimer(1)

        while true do
            local evt, a, b, c = os.pullEvent()

            if evt == "monitor_touch" and a == mon_name then
                local mx, my = b, c
                for _, btn in ipairs(mon_btns) do
                    if my >= btn.y and my < btn.y + btn.h
                    and mx >= btn.x and mx < btn.x + btn.w then
                        if btn.action == "back" then
                            os.queueEvent("key", back_key)
                        elseif btn.action == "stop" then
                            os.queueEvent("youcube:stop_command")
                        elseif btn.action == "skip" then
                            os.queueEvent("youcube:skip_command")
                        elseif btn.action == "vol_down" then
                            apply_vol(ui_volume - 0.3)
                            draw_monitor()
                            draw_term_bar()
                        elseif btn.action == "vol_up" then
                            apply_vol(ui_volume + 0.3)
                            draw_monitor()
                            draw_term_bar()
                        elseif btn.action == "vol_slider" then
                            local frac = (mx - btn.x) / btn.w
                            apply_vol(frac * 3.0)
                            draw_monitor()
                            draw_term_bar()
                        end
                        break
                    end
                end

            elseif evt == "mouse_click" then
                local mx, my = b, c
                for _, btn in ipairs(term_btns) do
                    if my == btn.y and mx >= btn.x and mx < btn.x + btn.w then
                        if btn.action == "back" then
                            os.queueEvent("key", back_key)
                        elseif btn.action == "stop" then
                            os.queueEvent("youcube:stop_command")
                        elseif btn.action == "skip" then
                            os.queueEvent("youcube:skip_command")
                        elseif btn.action == "vol_down" then
                            apply_vol(ui_volume - 0.3)
                            draw_monitor()
                            draw_term_bar()
                        elseif btn.action == "vol_up" then
                            apply_vol(ui_volume + 0.3)
                            draw_monitor()
                            draw_term_bar()
                        elseif btn.action == "vol_slider" then
                            local frac = (mx - btn.x) / btn.w
                            apply_vol(frac * 3.0)
                            draw_monitor()
                            draw_term_bar()
                        end
                        break
                    end
                end

            elseif evt == "youcube:set_volume" then
                apply_vol(a)
                draw_monitor()
                draw_term_bar()

            elseif evt == "timer" and a == redraw_timer then
                draw_term_bar()
                redraw_timer = os.startTimer(1)
            end
        end
    end
end

return ui
