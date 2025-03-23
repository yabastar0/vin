local currentPath = "/"
local io = Kernel.io

local function helpPage()
    io.print("Available commands:")
    io.print("ls","cd","pwd","mkdir","rm","cp","mv","touch","cat","head","tail","free","ping","wget","help")
end

local function shellLoop()
    io.print("vinsh shell")
    while true do
        term.setTextColor(0x00AAFF)
        io.write(currentPath)
        term.setTextColor(0xFFFFFF)
        io.write("#")
        local cmd = io.read()
        io.print("")
        local tokens = {}
        for t in cmd:gmatch("%S+") do table.insert(tokens, t) end

        if tokens[1] == "ls" then
            local usePath
            if tokens[2] then usePath = stfs.combine(currentPath, tokens[2]) else usePath = currentPath end

            if (not stfs.exists(stfs.primary, currentPath)) or (not stfs.isDirectory(stfs.primary, currentPath)) then
                currentPath = "/"
            end

            if (not stfs.exists(stfs.primary, usePath)) or (not stfs.isDirectory(stfs.primary, usePath)) then
                io.print("Extended path", tokens[2], "is not valid")
                usePath = currentPath
            end

            local ls = stfs.list(stfs.primary, usePath)

            local directories = {}
            local files = {}

            for _, pth in ipairs(ls) do
                if stfs.isDirectory(stfs.primary, stfs.combine(usePath, pth)) then
                    table.insert(directories, pth)
                else
                    table.insert(files, pth)
                end
            end

            for _, dir in ipairs(directories) do
                term.setTextColor(0x0000CF)
                io.print(dir)
                term.setTextColor(0xCCCCCC)
            end

            for _, file in ipairs(files) do
                io.print(file)
            end
            term.setTextColor(0xFFFFFF)
        elseif tokens[1] == "cd" then
            local usePath
            if tokens[2] then usePath = stfs.combine(currentPath, tokens[2]) else usePath = currentPath end
            if (not stfs.exists(stfs.primary, currentPath)) or (not stfs.isDirectory(stfs.primary, currentPath)) then
                currentPath = "/"
            end

            if (not stfs.exists(stfs.primary, usePath)) or (not stfs.isDirectory(stfs.primary, usePath)) then
                io.print("Path", tokens[2], "is not valid")
                usePath = currentPath
            end

            currentPath = usePath .. "/"
        elseif tokens[1] == "pwd" then
            io.print(currentPath)
        elseif tokens[1] == "mkdir" then
            stfs.mkDir(stfs.primary, stfs.combine(currentPath,tokens[2]))
        elseif tokens[1] == "rm" then
            stfs.remove(stfs.primary, stfs.combine(currentPath,tokens[2]))
        elseif tokens[1] == "cp" then
            if stfs.exists(stfs.primary, stfs.combine(currentPath,tokens[3])) then
                io.print("The specified path already exists. Continue? [y/n]:")
                local ans = io.read()
                if string.lower(ans) ~= "y" then
                    goto continue
                end
            end

            local file = stfs.open(stfs.primary, stfs.combine(currentPath,tokens[2]), "r")
            local data = file:readAll()
            file:close()

            local writeFile = stfs.open(stfs.primary, stfs.combine(currentPath,tokens[3]), "w")
            writeFile:write(data)
            writeFile:close()
        elseif tokens[1] == "mv" then
            if stfs.exists(stfs.primary, stfs.combine(currentPath,tokens[3])) then
                io.print("The specified path already exists. Continue? [y/n]:")
                local ans = io.read()
                if string.lower(ans) ~= "y" then
                    goto continue
                end
            end

            local file = stfs.open(stfs.primary, stfs.combine(currentPath,tokens[2]), "r")
            local data = file:readAll()
            file:close()
            stfs.remove(stfs.primary, stfs.combine(currentPath,tokens[2]))

            local writeFile = stfs.open(stfs.primary, stfs.combine(currentPath,tokens[3]), "w")
            writeFile:write(data)
            writeFile:close()
        elseif tokens[1] == "touch" then
            stfs.touch(stfs.primary, stfs.combine(currentPath,tokens[2]))
        elseif tokens[1] == "cat" then
            local file = stfs.open(stfs.primary, stfs.combine(currentPath,tokens[2]), "r")
            local data = file:readAll()
            file:close()
            io.print(data)
        elseif tokens[1] == "head" then
            local file = stfs.open(stfs.primary, stfs.combine(currentPath,tokens[3]), "r")
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
            local file = stfs.open(stfs.primary, stfs.combine(currentPath,tokens[3]), "r")
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
            io.print("Due to the way OC works, this is only accurate to 5 ms")
            if not Kernel.hasInternet then
                io.print("You are not connected to the internet")
                goto continue
            end
            local interAddr = component.list("internet")()
            local internet = component.proxy(interAddr)

            for _ = 1, 4 do
                local start = computer.uptime()
                local handle = internet.request(tokens[2])

                if not handle then
                    io.print("Failed to make request")
                    goto continue
                end
                local endt = computer.uptime()

                io.print("ping @", (math.floor(((endt - start) * 1000) + 0.5)) / 1000, "seconds")
                Kernel.sleep(1)
            end
        elseif tokens[1] == "wget" then
            assert(tokens[2], "Must provide a URL")
            assert(tokens[3], "Must provide destination path")
            if not Kernel.hasInternet then
                io.print("You are not connected to the internet")
                goto continue
            end
            if stfs.exists(stfs.primary, stfs.combine(currentPath,tokens[3])) then
                io.print("The specified path already exists. Continue? [y/n]:")
                local ans = io.read()
                if string.lower(ans) ~= "y" then
                    goto continue
                end
            end

            local data = Kernel.http({ "get", stfs.combine(currentPath,tokens[2]) })

            local file = stfs.open(stfs.primary, stfs.combine(currentPath,tokens[3]), "w")
            file:write(data)
            file:close()
        elseif stfs.exists(stfs.primary, stfs.combine(currentPath,tokens[1])) then
            Kernel.getScript(stfs.combine(currentPath,tokens[1]))()
        else
            helpPage()
        end
        ::continue::
    end
end

while true do
    local _,err = pcall(shellLoop)
    io.print(err)
end
