--[[
    Uninstall script for YC-Client-Fork
]]

local function question(message)
    term.setCursorBlink(true)
    term.setTextColor(colors.yellow)
    write(message .. " [y/N]: ")
    term.setTextColor(colors.white)
    local input = read()
    if not input then
        return false
    end
    local answer = input:lower():gsub("%s+", "")
    return answer == "y" or answer == "yes"
end

if not question("Are you sure you want to uninstall YC-Client-Fork?") then
    print("Uninstall cancelled.")
    return
end

print("Uninstalling YC-Client-Fork...")

local files_to_delete = {
    "./yc-fork-client.lua",
    "./Yc-Fork-Client-Libs/serverapi.lua",
    "./Yc-Fork-Client-Libs/numberformatter.lua",
    "./Yc-Fork-Client-Libs/semver.lua",
    "./Yc-Fork-Client-Libs/argparse.lua",
    "./Yc-Fork-Client-Libs/string_pack.lua",
    "./Yc-Fork-Client-Libs/ui.lua",
    "./Yc-Fork-Client-Libs/uninstall.lua",
    "./ycfork_settings.txt",
    "/ycfork_settings.txt",
    "./ycfork_history.txt",
    "/ycfork_history.txt"
}

local dirs_to_delete = {
    "./Yc-Fork-Client-Libs",
}

for _, file_path in ipairs(files_to_delete) do
    local resolved_path = shell.resolve(file_path)
    if fs.exists(resolved_path) then
        fs.delete(resolved_path)
        term.setTextColor(colors.lightGray)
        print("Deleted " .. resolved_path)
        term.setTextColor(colors.white)
    end
end

for _, dir_path in ipairs(dirs_to_delete) do
    local resolved_path = shell.resolve(dir_path)
    if fs.exists(resolved_path) and #fs.list(resolved_path) == 0 then
        fs.delete(resolved_path)
        term.setTextColor(colors.lightGray)
        print("Deleted directory " .. resolved_path)
        term.setTextColor(colors.white)
    end
end

term.setTextColor(colors.lime)
print("YC-Client-Fork has been fully uninstalled.")
term.setTextColor(colors.white)
