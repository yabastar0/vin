_G.shell = {}
_G.shell.currentPath = "/"
_G.shell.path = {}

local io = Kernel.io

local MOUNT_PREFIX_LENGTH = 4

local function getDrive()
    local tokens = stfs.getTokens(shell.currentPath)
    if tokens[1] == "mnt" and tokens[2] then
        local drivePrefix = tokens[2]:sub(1, MOUNT_PREFIX_LENGTH)
        for _, drive in ipairs(stfs.getDrives()) do
            if drive.addr:sub(1, MOUNT_PREFIX_LENGTH) == drivePrefix then
                return drive
            end
        end
    end
    return stfs.primary
end

local function getCorrectPath(drive, path)
    if path:sub(1, 1) == "/" then
        local tokens = stfs.getTokens(path)
        if tokens[1] == "mnt" then
            if #tokens == 1 then
                return stfs.primary, "/mnt/"
            elseif tokens[2] then
                local drivePrefix = tokens[2]:sub(1, MOUNT_PREFIX_LENGTH)
                for _, driven in ipairs(stfs.getDrives()) do
                    if driven.addr:sub(1, MOUNT_PREFIX_LENGTH) == drivePrefix then
                        local newPath = "/" ..
                                            (table.concat(tokens, "/", 3) or "")
                        return driven, newPath ~= "/" and newPath or "/"
                    end
                end
            end
        end
        return stfs.primary, path
    else
        local combinedPath = stfs.combine(shell.currentPath, path)
        return getCorrectPath(drive, combinedPath)
    end
end

if stfs.exists(stfs.primary, "/etc/profile") then
    Kernel.getScript("/etc/profile")()
else
    stfs.touch(stfs.primary, "/etc/profile")
end

local function savePath()
    local file = stfs.open(stfs.primary, "/etc/profile", "w")
    file:write("_G.shell.path = " ..
                   Kernel.serialize(_G.shell.path, {compact = true}))
    file:close()
end

local function helpPage()
    io.print("Available commands:")
    io.print("ls       - List directory contents")
    io.print("cd       - Change directory")
    io.print("pwd      - Print working directory")
    io.print("mkdir    - Create a directory")
    io.print("rm       - Remove a file or directory")
    io.print("cp       - Copy a file")
    io.print("mv       - Move/rename a file")
    io.print("touch    - Create an empty file")
    io.print("cat      - Display file contents")
    io.print("head     - Show first lines of a file (head <lines> <file>)")
    io.print("tail     - Show last lines of a file (tail <lines> <file>)")
    io.print("free     - Show memory usage")
    io.print("ping     - Ping a network host")
    io.print("wget     - Download a file from the web (wget <url> <dest>)")
    io.print("clr/clear- Clear the screen")
    io.print("uname    - Show system information")
    io.print("alias    - Create a command alias (alias <path> <name>)")
    io.print("unalias  - Remove a command alias (unalias <name>)")
    io.print("aliases  - List all command aliases")
    io.print("help     - Show this help page")
end

local function shellLoop()
    io.print("vinsh shell")
    while true do
        term.setTextColor(0x00AAFF)
        io.write(shell.currentPath)
        term.setTextColor(0xFFFFFF)
        io.write("#")
        local cmd = io.read()
        io.print("")
        local tokens = {}
        for t in cmd:gmatch("%S+") do table.insert(tokens, t) end

        if tokens[1] ~= "" and tokens[1] ~= nil then
            if tokens[1] == "ls" then
                local usePath
                if tokens[2] then
                    usePath = stfs.combine(shell.currentPath, tokens[2])
                else
                    usePath = shell.currentPath
                end

                if usePath == "/mnt/" or usePath == "/mnt" then
                    local drives = stfs.getDrives()
                    for _, drive in ipairs(drives) do
                        if drive ~= stfs.primary then
                            term.setTextColor(0x0000F0)
                            io.print(drive.addr:sub(1, MOUNT_PREFIX_LENGTH))
                            term.setTextColor(0xFFFFFF)
                        end
                    end
                    goto continue
                end

                local drive = getDrive()
                local targetDrive, targetPath = getCorrectPath(drive, usePath)

                if not stfs.exists(targetDrive, targetPath) then
                    io.print("Path", targetPath, "does not exist")
                    goto continue
                end

                if not stfs.isDirectory(targetDrive, targetPath) then
                    io.print(targetPath, "is not a directory")
                    goto continue
                end

                local ls = stfs.list(targetDrive, targetPath)

                local directories = {}
                local files = {}

                for _, pth in ipairs(ls) do
                    if stfs.isDirectory(targetDrive, stfs.combine(targetPath, pth)) then
                        table.insert(directories, pth)
                    else
                        table.insert(files, pth)
                    end
                end

                for _, dir in ipairs(directories) do
                    term.setTextColor(0x0F2FFF)
                    io.print(dir)
                    term.setTextColor(0xFFFFFF)
                end

                for _, file in ipairs(files) do io.print(file) end
                term.setTextColor(0xFFFFFF)
            elseif tokens[1] == "cd" then
                local newPath = tokens[2] or "/"
                local drive = getDrive()
                local targetDrive, targetPath = getCorrectPath(drive, newPath)

                if not stfs.exists(targetDrive, targetPath) then
                    io.print("Path", targetPath, "does not exist")
                    goto continue
                end

                if not stfs.isDirectory(targetDrive, targetPath) then
                    io.print(targetPath, "is not a directory")
                    goto continue
                end

                if targetDrive ~= stfs.primary then
                    shell.currentPath = "/mnt/" .. targetDrive.addr ..
                                            targetPath:sub(2)
                else
                    shell.currentPath = targetPath
                end
            elseif tokens[1] == "pwd" then
                io.print(shell.currentPath)
            elseif tokens[1] == "mkdir" then
                local drive = getDrive()
                local targetDrive, targetPath = getCorrectPath(drive, tokens[2])
                stfs.mkDir(targetDrive, targetPath)
            elseif tokens[1] == "rm" then
                local drive = getDrive()
                local targetDrive, targetPath = getCorrectPath(drive, tokens[2])
                stfs.remove(targetDrive, targetPath)
            elseif tokens[1] == "cp" then
                local drive = getDrive()
                local srcDrive, srcPath = getCorrectPath(drive, tokens[2])
                local dstDrive, dstPath = getCorrectPath(drive, tokens[3])

                if stfs.exists(dstDrive, dstPath) then
                    io.print("The specified path already exists. Continue? [y/n]:")
                    local ans = io.read()
                    if string.lower(ans) ~= "y" then goto continue end
                end

                local file = stfs.open(srcDrive, srcPath, "r")
                local data = file:readAll()
                file:close()

                local writeFile = stfs.open(dstDrive, dstPath, "w")
                writeFile:write(data)
                writeFile:close()
            elseif tokens[1] == "mv" then
                local drive = getDrive()
                local srcDrive, srcPath = getCorrectPath(drive, tokens[2])
                local dstDrive, dstPath = getCorrectPath(drive, tokens[3])

                if stfs.exists(dstDrive, dstPath) then
                    io.print("The specified path already exists. Continue? [y/n]:")
                    local ans = io.read()
                    if string.lower(ans) ~= "y" then goto continue end
                end

                local file = stfs.open(srcDrive, srcPath, "r")
                local data = file:readAll()
                file:close()
                stfs.remove(srcDrive, srcPath)

                local writeFile = stfs.open(dstDrive, dstPath, "w")
                writeFile:write(data)
                writeFile:close()
            elseif tokens[1] == "touch" then
                local drive = getDrive()
                local targetDrive, targetPath = getCorrectPath(drive, tokens[2])
                stfs.touch(targetDrive, targetPath)
            elseif tokens[1] == "cat" then
                local drive = getDrive()
                local targetDrive, targetPath = getCorrectPath(drive, tokens[2])
                local file = stfs.open(targetDrive, targetPath, "r")
                local data = file:readAll()
                file:close()
                io.print(data)
            elseif tokens[1] == "head" then
                local drive = getDrive()
                local targetDrive, targetPath = getCorrectPath(drive, tokens[3])
                local file = stfs.open(targetDrive, targetPath, "r")
                if not file then
                    io.print("Could not read file")
                    goto continue
                end

                local bufferSize = 1024
                local buffer = ""
                for _ = 1, tonumber(tokens[2]) do
                    while true do
                        if #buffer == 0 then
                            buffer = file:read(bufferSize)
                            if not buffer then break end
                        end
                        local newlinePos = buffer:find("\n")
                        if newlinePos then
                            local line = buffer:sub(1, newlinePos - 1)
                            buffer = buffer:sub(newlinePos + 1)
                            io.print(line)
                            break
                        else
                            io.print(buffer)
                            buffer = ""
                        end
                    end
                end

                file:close()
            elseif tokens[1] == "tail" then
                local drive = getDrive()
                local targetDrive, targetPath = getCorrectPath(drive, tokens[3])
                local file = stfs.open(targetDrive, targetPath, "r")
                if not file then
                    io.print("Could not read file")
                    goto continue
                end

                local bufferSize = 1024
                local maxLines = tonumber(tokens[2])
                local lines = {}
                local lineCount = 0
                local buffer = ""

                while true do
                    local chunk = file:read(bufferSize)
                    if not chunk then break end
                    buffer = buffer .. chunk
                    while true do
                        local newlinePos = buffer:find("\n")
                        if not newlinePos then break end
                        local line = buffer:sub(1, newlinePos - 1)
                        buffer = buffer:sub(newlinePos + 1)
                        lineCount = lineCount + 1
                        lines[lineCount % maxLines + 1] = line
                    end
                end

                if buffer ~= "" then
                    lineCount = lineCount + 1
                    lines[lineCount % maxLines + 1] = buffer
                end

                local start = math.max(1, lineCount - maxLines + 1)
                for i = start, lineCount do
                    io.print(lines[(i - 1) % maxLines + 1])
                end

                file:close()
            elseif tokens[1] == "free" then
                io.print(computer.freeMemory(), "/", computer.totalMemory())
            elseif tokens[1] == "ping" then
                local interAddr = component.list("internet")()
                if not interAddr then
                    io.print("You are not connected to the internet")
                    goto continue
                end
                local internet = component.proxy(interAddr)
                io.print("Due to the way OC works, this is only accurate to 5 ms")
                for _ = 1, 4 do
                    local start = computer.uptime()
                    local handle = internet.request(tokens[2])

                    if not handle then
                        handle = internet.request("https://" .. tokens[2])
                    end

                    if not handle then
                        handle = internet.request("http://" .. tokens[2])
                    end

                    if not handle then
                        io.print("Failed to make request")
                        goto continue
                    end
                    local endt = computer.uptime()

                    io.print("ping @",
                            (math.floor(((endt - start) * 1000) + 0.5)) / 1000,
                            "seconds")
                    Kernel.sleep(1)
                end
            elseif tokens[1] == "wget" then
                assert(tokens[2], "Must provide a URL")
                assert(tokens[3], "Must provide destination path")
                if not Kernel.hasInternet then
                    io.print("You are not connected to the internet")
                    goto continue
                end

                local drive = getDrive()
                local targetDrive, targetPath = getCorrectPath(drive, tokens[3])

                if stfs.exists(targetDrive, targetPath) then
                    io.print("The specified path already exists. Continue? [y/n]:")
                    local ans = io.read()
                    if string.lower(ans) ~= "y" then goto continue end
                end

                local data = Kernel.http({"get", tokens[2]})

                local file = stfs.open(targetDrive, targetPath, "w")
                file:write(data)
                file:close()
            elseif tokens[1] == "clr" or tokens[1] == "clear" then
                term.clear()
            elseif tokens[1] == "uname" then
                io.print(_G.KERNELVER)
                io.print(_G.OSVER)
                io.print(computer.freeMemory(), "/", computer.totalMemory(),
                        "memory free")
                io.print("Address", computer.address())
                io.print("Uptime", computer.uptime() .. "s")
            elseif tokens[1] == "alias" then
                if not tokens[2] or not tokens[3] then
                    io.print("Usage: alias <path> <name>")
                    goto continue
                end

                for i, entry in ipairs(_G.shell.path) do
                    if entry[2] == tokens[3] then
                        local drive = getDrive()
                        local targetDrive, targetPath =
                            getCorrectPath(drive, tokens[2])
                        if not stfs.exists(targetDrive, targetPath) then
                            io.print("Path", tokens[2], "does not exist")
                            goto continue
                        end
                        _G.shell.path[i][1] = stfs.resolve(targetPath)
                        savePath()
                        io.print("Updated alias", tokens[3], "=>",
                                _G.shell.path[i][1])
                        goto continue
                    end
                end

                local drive = getDrive()
                local targetDrive, targetPath = getCorrectPath(drive, tokens[2])

                if not stfs.exists(targetDrive, targetPath) then
                    io.print("Path", tokens[2], "does not exist")
                    goto continue
                end

                local resolvedPath = stfs.resolve(targetPath)

                table.insert(_G.shell.path, {resolvedPath, tokens[3]})
                savePath()
                io.print("Created alias", tokens[3], "=>", resolvedPath)
            elseif tokens[1] == "unalias" then
                if not tokens[2] then
                    io.print("Usage: unalias <name>")
                    goto continue
                end

                for i = #_G.shell.path, 1, -1 do
                    if _G.shell.path[i][2] == tokens[2] then
                        table.remove(_G.shell.path, i)
                        savePath()
                        io.print("Removed alias", tokens[2])
                        goto continue
                    end
                end

                io.print("Alias", tokens[2], "not found")
            elseif tokens[1] == "aliases" then
                if #_G.shell.path == 0 then
                    io.print("No aliases defined")
                    goto continue
                end

                io.print("Current aliases:")
                for _, entry in ipairs(_G.shell.path) do
                    io.print(string.format("  %-10s => %s", entry[2], entry[1]))
                end
            elseif stfs.exists(stfs.primary,
                            stfs.combine(shell.currentPath, tokens[1])) then
                Kernel.getScript(stfs.combine(shell.currentPath, tokens[1]))()
            else
                if tokens[1] ~= "" and tokens[1] ~= nil then
                    local foundAlias = false
                    for _, entry in ipairs(_G.shell.path) do
                        local aliasName, aliasPath = entry[2], entry[1]
                        if aliasName == tokens[1] then
                            local drive = getDrive()
                            local targetDrive, targetPath =
                                getCorrectPath(drive, aliasPath)

                            targetPath = targetPath:gsub("//+", "/")

                            if stfs.exists(targetDrive, targetPath) then
                                Kernel.getScript(targetPath)()
                            else
                                io.print("Alias target", targetPath, "not found")
                            end
                            foundAlias = true
                            break
                        end
                    end

                    if not foundAlias then
                        local drive = getDrive()
                        local targetDrive, targetPath = getCorrectPath(drive, tokens[1])

                        targetPath = targetPath:gsub("//+", "/")

                        if stfs.exists(targetDrive, targetPath) then
                            Kernel.getScript(targetPath)()
                        else
                            helpPage()
                        end
                    end
                end
            end
        end
        ::continue::
    end
end

while true do
    local _, err = pcall(shellLoop)
    io.print(err)
end
