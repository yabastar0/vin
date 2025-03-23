local component = component or require("component")
local computer  = computer or require("computer")

_G.KERNELVER    = "vinkern 0.0.b"
_G.OSVER        = "vinsys 0.0.b"

Kernel          = {}
Kernel.io       = {}

Kernel.stfs     = "/lib/modules/kernel/drivers/fs/standardfs/stfs.ko"

_G.HasGPU       = false
_G.HasScreen    = false
_G.Res          = {}

local gpu       = component.proxy(component.list("gpu")())
local screen    = component.list("screen")()

if gpu then HasGPU = true end
if screen then HasScreen = true end
if gpu and screen then
    gpu.bind(screen); CanDisplay = true
end

local w, h = gpu.getResolution()
_G.Res = { w, h }

Kernel.cursor = {
    ["pos"] = { 1, 1 },
    ["visible"] = false,
    ["active"] = true
}

function Kernel.setCursorPos(x, y)
    Kernel.cursor.pos[1] = x; Kernel.cursor.pos[2] = y
end

function Kernel.getCursorPos()
    return Kernel.cursor.pos
end

function Kernel.setCursor(val)
    Kernel.cursor.active = val
end

local function valifyCursor()
    Kernel.cursor.pos[1] = Kernel.cursor.pos[1] or 1
    Kernel.cursor.pos[2] = Kernel.cursor.pos[2] or 1
end

Kernel.panic = error
_ENV.error = function(err)
    if _G.HasGPU then
        gpu.setForeground(0xFF0000)
        Kernel.io.print(err)
        Kernel.io.print(debug.traceback())
        gpu.setForeground(0xFFFFFF)
    end
end

local safeError = function(err)
    if _G.HasGPU then
        local oldGPU = gpu
        gpu = component.proxy(component.list("gpu")())
        valifyCursor()
        local position = Kernel.cursor.pos

        gpu.setBackground(0x000000)
        gpu.setForeground(0xFFFFFF)
        gpu.set(1, position[2] + 1, "Kernel recovered after error: ")
        gpu.setForeground(0xFF0000)
        gpu.set(1 + #("Kernel recovered after error: "), position[2] + 1, err)
        gpu.setForeground(0xFFFFFF)

        Kernel.cursor.pos[1] = 1
        Kernel.cursor.pos[2] = position[2] + 2

        gpu.setForeground(0xFFFFFF)
        gpu = oldGPU
    end
end

local function safeCall(func)
    return function(...)
        local success, result = pcall(func, ...)
        if not success then
            safeError(result)
        end
        return result
    end
end

function Kernel.busySleep(seconds)
    local target = computer.uptime() + seconds
    while computer.uptime() < target do end
end

function Kernel.sleep(seconds)
    local target = computer.uptime() + seconds
    while computer.uptime() < target do computer.pullSignal(0) end
end

function Kernel.io.print(...)
    local msg = table.concat({ ... }, " ")
    msg = tostring(msg)
    local position = Kernel.cursor.pos

    for line in string.gmatch(msg, "([^\n]*)\n?") do
        if _G.CanDisplay then
            gpu.set(position[1], position[2], tostring(line))

            if position[2] == _G.Res[2] then
                gpu.copy(1, 2, _G.Res[1], _G.Res[2] - 1, 0, -1)
                gpu.fill(1, _G.Res[2], _G.Res[1], 1, " ")
                Kernel.cursor.pos[1] = 1
            else
                Kernel.cursor.pos[2] = position[2] + 1
                Kernel.cursor.pos[1] = 1
            end
        end
    end
end

Kernel.io.print = safeCall(Kernel.io.print)

function Kernel.io.write(msg)
    msg = tostring(msg)
    local position = Kernel.cursor.pos

    if _G.CanDisplay then
        gpu.set(position[1], position[2], msg)
        Kernel.cursor.pos[1] = position[1] + #msg
    end
end

Kernel.io.write = safeCall(Kernel.io.write)

function Kernel.io.writeChar(char)
    local position = Kernel.cursor.pos
    if #char == 1 and _G.CanDisplay then
        gpu.set(position[1], position[2], char)
        Kernel.cursor.pos[1] = position[1] + 1
    end
end

Kernel.io.writeChar = safeCall(Kernel.io.writeChar)

function Kernel.io.slowWrite(msg, delay)
    for i = 1, #msg do
        Kernel.io.writeChar(string.sub(msg, i, i))
        Kernel.sleep(delay)
    end
end

Kernel.io.slowWrite = safeCall(Kernel.io.slowWrite)

function Kernel.io.status(t, msg)
    if t == "ok" then
        local exForeground = gpu.getForeground()
        Kernel.io.write("[")
        gpu.setForeground(0x00CC11)
        Kernel.io.write(" ok ")
        gpu.setForeground(exForeground)
        Kernel.io.write("] ")
        Kernel.io.print(msg)
    elseif t == "warn" then
        local exForeground = gpu.getForeground()
        Kernel.io.write("[")
        gpu.setForeground(0xFF7700)
        Kernel.io.write("warn")
        gpu.setForeground(exForeground)
        Kernel.io.write("] ")
        Kernel.io.print(msg)
    elseif t == "err" then
        local exForeground = gpu.getForeground()
        Kernel.io.write("[")
        gpu.setForeground(0x9F0000)
        Kernel.io.write("warn")
        gpu.setForeground(exForeground)
        Kernel.io.write("] ")
        Kernel.io.print(msg)
    elseif t == "info" then
        Kernel.io.write("[info] ")
        Kernel.io.print(msg)
    end
end

Kernel.io.status = safeCall(Kernel.io.status)

local function serialize_impl(t, tracking, indent, opts)
    local sType = type(t)
    if sType == "table" then
        if tracking[t] ~= nil then
            if tracking[t] == false then
                Kernel.io.status("err", "Cannot serialize table with repeated entries")
            else
                Kernel.io.status("err", "Cannot serialize table with recursive entries")
            end
        end
        tracking[t] = true

        local result
        if next(t) == nil then
            result = "{}"
        else
            local open, sub_indent, open_key, close_key, equal, comma = "{\n",
                indent ..
                "  ",
                "[ ",
                " ] = ",
                " = ",
                ",\n"
            if opts.compact then
                open, sub_indent, open_key, close_key, equal, comma = "{", "",
                    "[", "]=",
                    "=", ","
            end

            result = open
            local seen_keys = {}

            for _, v in ipairs(t) do
                result = result .. sub_indent ..
                    serialize_impl(v, tracking, sub_indent, opts) ..
                    comma
            end

            for k, v in pairs(t) do
                if not seen_keys[k] then
                    local sEntry
                    if type(k) == "string" and
                        string.match(k, "^[%a_][%a%d_]*$") then
                        sEntry = k .. equal ..
                            serialize_impl(v, tracking, sub_indent,
                                opts) .. comma
                    else
                        sEntry = open_key ..
                            serialize_impl(k, tracking, sub_indent,
                                opts) .. close_key ..
                            serialize_impl(v, tracking, sub_indent,
                                opts) .. comma
                    end
                    result = result .. sub_indent .. sEntry
                end
            end
            result = result .. indent .. "}"
        end

        if opts.allow_repetitions then
            tracking[t] = nil
        else
            tracking[t] = false
        end
        return result
    elseif sType == "string" then
        return string.format("%q", t)
    elseif sType == "number" then
        if t ~= t then
            return "0/0"
        elseif t == math.huge then
            return "1/0"
        elseif t == -math.huge then
            return "-1/0"
        else
            return tostring(t)
        end
    elseif sType == "boolean" or sType == "nil" then
        return tostring(t)
    else
        Kernel.io.status("err", "Cannot serialize type " .. sType)
    end
end

function Kernel.serialize(t, opts)
    opts = opts or {}
    opts.compact = opts.compact or false
    opts.allow_repetitions = opts.allow_repetitions or false

    local tracking = {}
    local indent = ""

    return serialize_impl(t, tracking, indent, opts)
end

Kernel.serialize = safeCall(Kernel.serialize)

function Kernel.deserialize(str)
    local func = load("return " .. str, "unserialize", "t", {})
    if func then
        local ok, result = pcall(func)
        if ok then return result end
    end
    return nil
end

function Kernel.inTable(value, tbl)
    for _, v in ipairs(tbl) do
        if v == value then return true end
    end
    return false
end

local savedChar, savedForeground, savedBackground

function Kernel.updateCursor()
    local isActive = Kernel.cursor.active
    local isVisible = Kernel.cursor.visible
    local position = Kernel.cursor.pos
    if isActive then
        if not isVisible then
            savedChar, savedForeground, savedBackground = gpu.get(position[1], position[2])
            if _G.CanDisplay then
                gpu.setForeground(savedBackground)
                gpu.setBackground(savedForeground)

                gpu.set(position[1], position[2], savedChar)

                gpu.setBackground(savedBackground)
                gpu.setForeground(savedForeground)
            end
        else
            if _G.CanDisplay then
                gpu.setForeground(savedForeground)
                gpu.setBackground(savedBackground)
                gpu.set(position[1], position[2], savedChar)
            end
        end
        Kernel.cursor.visible = not Kernel.cursor.visible
    else
        if isVisible then
            if _G.CanDisplay then
                savedChar, savedForeground, savedBackground = gpu.get(position[1], position[2])
                gpu.setForeground(savedBackground)
                gpu.setBackground(savedForeground)
                gpu.set(position[1], position[2], savedChar)
            end
            Kernel.cursor.visible = not Kernel.cursor.visible
        end
    end
end

Kernel.updateCursor = safeCall(Kernel.updateCursor)


local interAddr = component.list("internet")()
Kernel.hasInternet = false
local internet

if interAddr then
    Kernel.hasInternet = true
    internet = component.proxy(interAddr)
end

function Kernel.http(request)
    local rType = request[1]
    local url = request[2]
    local postData = request[3]

    if not url or type(url) ~= "string" then
        return
    end

    if rType == "get" then
        local handle = internet.request(url)
        if not handle then return end

        local result = ""
        while true do
            local chunk = handle.read()
            if not chunk then break end
            result = result .. chunk
        end

        handle.close()
        return result
    elseif rType == "post" then
        local handle = internet.request(url, postData)
        if not handle then return end

        local result = ""
        while true do
            local chunk = handle.read()
            if not chunk then break end
            result = result .. chunk
        end

        handle.close()
        return result
    elseif rType == "request" then
        local handle = internet.request(url, postData)
        return handle or nil
    elseif rType == "checkURLAsync" then
        return internet.isHttpEnabled() and internet.request(url) ~= nil
    elseif rType == "checkURL" then
        return internet.isHttpEnabled() and (internet.request(url) ~= nil)
    else
        return
    end
end

Kernel.http = safeCall(Kernel.http)

Kernel.keyboard = {
    pressedChars = {},
    pressedCodes = {},
    keys = {}
}

local keyList = {
    { "c",    0x2E }, { "d", 0x20 }, { "q", 0x10 }, { "w", 0x11 },
    { "back", 0x0E }, { "delete", 0xD3 }, { "down", 0xD0 }, { "enter", 0x1C },
    { "home",   0xC7 }, { "lcontrol", 0x1D }, { "left", 0xCB }, { "lmenu", 0x38 },
    { "lshift", 0x2A }, { "pageDown", 0xD1 }, { "rcontrol", 0x9D }, { "right", 0xCD },
    { "rmenu", 0xB8 }, { "rshift", 0x36 }, { "space", 0x39 }, { "tab", 0x0F },
    { "up",    0xC8 }, { "end", 0xCF }, { "numpadenter", 0x9C }
}

for i = 1, 9 do table.insert(keyList, { tostring(i), 0x01 + i }) end
for i, char in ipairs({ "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z" }) do
    table.insert(keyList, { char, 0x1D + i })
end

for _, key in ipairs({
    { "apostrophe", 0x28 }, { "at", 0x91 }, { "backslash", 0x2B }, { "capital", 0x3A },
    { "comma",      0x33 }, { "equals", 0x0D }, { "grave", 0x29 }, { "lbracket", 0x1A },
    { "minus",    0x0C }, { "numlock", 0x45 }, { "pause", 0xC5 }, { "period", 0x34 },
    { "rbracket", 0x1B }, { "scroll", 0x46 }, { "semicolon", 0x27 }, { "slash", 0x35 },
    { "stop",   0x95 }, { "underline", 0x93 },
    { "pageUp", 0xC9 }, { "pageDown", 0xD1 }, { "insert", 0xD2 }, { "delete", 0xD3 },
    { "f1", 0x3B }, { "f2", 0x3C }, { "f3", 0x3D }, { "f4", 0x3E },
    { "f5", 0x3F }, { "f6", 0x40 }, { "f7", 0x41 }, { "f8", 0x42 },
    { "f9",      0x43 }, { "f10", 0x44 }, { "f11", 0x57 }, { "f12", 0x58 },
    { "numpad0", 0x52 }, { "numpad1", 0x4F }, { "numpad2", 0x50 },
    { "numpad3", 0x51 }, { "numpad4", 0x4B }, { "numpad5", 0x4C },
    { "numpad6", 0x4D }, { "numpad7", 0x47 }, { "numpad8", 0x48 },
    { "numpad9",   0x49 }, { "numpadmul", 0x37 }, { "numpaddiv", 0xB5 },
    { "numpadsub", 0x4A }, { "numpadadd", 0x4E }, { "numpaddecimal", 0x53 },
    { "numpadcomma", 0xB3 }, { "numpadequals", 0x8D }
}) do
    table.insert(keyList, key)
end

for _, key in ipairs(keyList) do
    Kernel.keyboard.keys[key[1]] = key[2]
end

setmetatable(Kernel.keyboard.keys, {
    __index = function(tbl, k)
        if type(k) ~= "number" then return end
        for name, value in pairs(tbl) do
            if value == k then
                return name
            end
        end
    end
})

function Kernel.keyboard.isAltDown()
    return Kernel.keyboard.pressedCodes[Kernel.keyboard.keys.lmenu] or
        Kernel.keyboard.pressedCodes[Kernel.keyboard.keys.rmenu]
end

function Kernel.keyboard.isControl(char)
    return type(char) == "number" and (char < 0x20 or (char >= 0x7F and char <= 0x9F))
end

function Kernel.keyboard.isControlDown()
    return Kernel.keyboard.pressedCodes[Kernel.keyboard.keys.lcontrol] or
        Kernel.keyboard.pressedCodes[Kernel.keyboard.keys.rcontrol]
end

function Kernel.keyboard.isKeyDown(charOrCode)
    if type(charOrCode) == "string" then
        return Kernel.keyboard.pressedChars[utf8 and utf8.codepoint(charOrCode) or charOrCode:byte()]
    elseif type(charOrCode) == "number" then
        return Kernel.keyboard.pressedCodes[charOrCode]
    end
end

function Kernel.keyboard.isShiftDown()
    return Kernel.keyboard.pressedCodes[Kernel.keyboard.keys.lshift] or
        Kernel.keyboard.pressedCodes[Kernel.keyboard.keys.rshift]
end

Kernel.keyboard.getShiftedChar = function(chr, capsLockActive)
    local shiftMap = {
        [49] = '!',
        [50] = '@',
        [51] = '#',
        [52] = '$',
        [53] = '%',
        [54] = '^',
        [55] = '&',
        [56] = '*',
        [57] = '(',
        [48] = ')',
        [45] = '_',
        [61] = '+',
        [91] = '{',
        [93] = '}',
        [92] = '|',
        [59] = ':',
        [39] = '"',
        [44] = '<',
        [46] = '>',
        [47] = '?',
        [96] = '~'
    }

    if chr >= 97 and chr <= 122 then
        if capsLockActive then
            return string.char(chr - 32)
        else
            return string.char(chr)
        end
    end

    if shiftMap[chr] then
        return shiftMap[chr]
    end

    return string.char(chr)
end

Kernel.SignalSystem = {}
local handlers = {}
local handlerIDCounter = 0
local lastInterrupt = -math.huge

Kernel.SignalSystem.handlers = handlers

local function checkInterrupt(uptime)
    if uptime - lastInterrupt > 1 and Kernel.keyboard.isControlDown() and Kernel.keyboard.isKeyDown(Kernel.keyboard.keys.c) then
        lastInterrupt = uptime
        if Kernel.keyboard.isAltDown() then
            require("process").info().data.signal("interrupted", 0)
            return true, nil
        end
        return true, "interrupted"
    end
    return false, nil
end

function Kernel.SignalSystem.register(key, callback, interval, times, opt_handlers)
    if type(callback) ~= "function" then error("Callback must be a function") end
    local t_interval = interval or math.huge
    local t_times = times or 1
    local currentUptime = computer.uptime()
    local handler = {
        key = key,
        times = t_times,
        callback = callback,
        interval = t_interval,
        timeout = currentUptime + t_interval,
    }
    opt_handlers = opt_handlers or handlers

    handlerIDCounter = handlerIDCounter + 1
    local id = handlerIDCounter
    opt_handlers[id] = handler
    return id
end

Kernel.SignalSystem.register = safeCall(Kernel.SignalSystem.register)

local _pullSignal = computer.pullSignal
setmetatable(handlers, { __call = function(_, ...) return _pullSignal(...) end })

computer.pullSignal = function(seconds)
    seconds = seconds or math.huge
    local math_min = math.min
    local uptime = computer.uptime
    local deadline = uptime() + seconds

    repeat
        local now = uptime()
        local interrupt, interruptSignal = checkInterrupt(now)
        if interrupt then
            if interruptSignal then
                Kernel.SignalSystem.push(interruptSignal, lastInterrupt)
            end
        end

        local closest = deadline
        for _, handler in pairs(handlers) do
            closest = math_min(handler.timeout, closest)
        end

        local waitTime = closest - now
        local event_data = table.pack(handlers(waitTime))
        local signal = event_data[1]

        local handlersCopy = {}
        for id, handler in pairs(handlers) do
            handlersCopy[id] = handler
        end

        for id, handler in pairs(handlersCopy) do
            if (handler.key == nil or handler.key == signal) or uptime() >= handler.timeout then
                handler.times = handler.times - 1
                handler.timeout = handler.timeout + handler.interval
                if handler.times <= 0 and handlers[id] == handler then
                    handlers[id] = nil
                end
                local result, message = pcall(handler.callback, table.unpack(event_data, 1, event_data.n))
                if not result then
                    pcall(Kernel.SignalSystem.onError, message)
                elseif message == false and handlers[id] == handler then
                    handlers[id] = nil
                end
            end
        end

        if signal then
            return table.unpack(event_data, 1, event_data.n)
        end
    until uptime() >= deadline
end

local function createPlainFilter(name, ...)
    local filter = table.pack(...)
    if name == nil and filter.n == 0 then return nil end
    return function(...)
        local signal = table.pack(...)
        if name and not (type(signal[1]) == "string" and signal[1]:match(name)) then return false end
        for i = 1, filter.n do
            if filter[i] ~= nil and filter[i] ~= signal[i + 1] then return false end
        end
        return true
    end
end

function Kernel.SignalSystem.listen(name, callback)
    if type(name) ~= "string" then error("Event name must be a string") end
    if type(callback) ~= "function" then error("Callback must be a function") end
    for _, handler in pairs(handlers) do
        if handler.key == name and handler.callback == callback then
            return false
        end
    end
    return Kernel.SignalSystem.register(name, callback, math.huge, math.huge)
end

Kernel.SignalSystem.listen = safeCall(Kernel.SignalSystem.listen)

function Kernel.SignalSystem.pull(...)
    local args = table.pack(...)
    if type(args[1]) == "string" then
        return Kernel.SignalSystem.pullFiltered(createPlainFilter(...))
    else
        local seconds = args[1]
        if seconds ~= nil and type(seconds) ~= "number" then error("First argument must be a number or nil") end
        return Kernel.SignalSystem.pullFiltered(seconds, createPlainFilter(select(2, ...)))
    end
end

Kernel.SignalSystem.pull = safeCall(Kernel.SignalSystem.pull)

function Kernel.SignalSystem.pullFiltered(...)
    local args = table.pack(...)
    local seconds, filter = math.huge
    if type(args[1]) == "function" then
        filter = args[1]
    else
        seconds = args[1]
        filter = args[2]
        if seconds ~= nil and type(seconds) ~= "number" then error("First argument must be a number or nil") end
        if filter ~= nil and type(filter) ~= "function" then error("Second argument must be a function or nil") end
    end

    local deadline = computer.uptime() + seconds
    repeat
        local waitTime = deadline - computer.uptime()
        if waitTime <= 0 then break end
        local signal = table.pack(computer.pullSignal(waitTime))
        if signal.n > 0 and (not filter or filter(table.unpack(signal, 1, signal.n))) then
            return table.unpack(signal, 1, signal.n)
        end
    until false
end

function Kernel.io.read()
    Kernel.cursor.active = true
    local fullText = ""
    local tPos = 0
    local shiftActive = false
    local capsLockActive = false

    while true do
        local evt, _, chr, code = computer.pullSignal(0.5)
        if evt == "key_down" then
            if code == 42 or code == 54 then
                shiftActive = true
            end

            if code == 58 then
                capsLockActive = not capsLockActive
            end

            if chr == 13 then
                break
            end

            if chr == 8 then
                if tPos > 0 then
                    Kernel.cursor.active = false
                    Kernel.updateCursor()

                    fullText = string.sub(fullText, 1, tPos - 1) .. string.sub(fullText, tPos + 1)
                    tPos = tPos - 1
                    Kernel.cursor.pos[1] = Kernel.cursor.pos[1] - 1

                    if _G.CanDisplay then
                        gpu.set(Kernel.cursor.pos[1], Kernel.cursor.pos[2], " ")

                        local remainingText = string.sub(fullText, tPos + 1)
                        gpu.set(Kernel.cursor.pos[1] + 1, Kernel.cursor.pos[2], remainingText)
                    end

                    Kernel.cursor.active = true
                    Kernel.updateCursor()
                end
            --[[
            elseif code == 203 then
                if tPos > 0 then
                    tPos = tPos - 1
                    Kernel.cursor.pos[1] = Kernel.cursor.pos[1] - 1
                end
            elseif code == 205 then
                if tPos < #fullText then
                    tPos = tPos + 1
                    Kernel.cursor.pos[1] = Kernel.cursor.pos[1] + 1
                end
            ]]
            elseif chr ~= nil and chr >= 32 and chr <= 126 then
                Kernel.cursor.active = false
                Kernel.updateCursor()

                local char
                if shiftActive or capsLockActive then
                    char = Kernel.keyboard.getShiftedChar(chr, capsLockActive)
                else
                    char = string.char(chr)
                end

                fullText = string.sub(fullText, 1, tPos) .. char .. string.sub(fullText, tPos + 1)
                tPos = tPos + 1

                if _G.CanDisplay then
                    gpu.set(Kernel.cursor.pos[1], Kernel.cursor.pos[2], char)
                end
                Kernel.cursor.pos[1] = Kernel.cursor.pos[1] + 1

                Kernel.cursor.active = true
                Kernel.updateCursor()
            end
        elseif evt == "key_up" then
            if code == 42 or code == 54 then
                shiftActive = false
            end
        end

        Kernel.updateCursor()
    end

    Kernel.cursor.active = false
    Kernel.updateCursor()
    return fullText
end

local fsAddress = nil

if component.filesystem then
    local defaultFS = component.proxy(component.filesystem.address)
    if defaultFS and defaultFS.exists(Kernel.stfs) then
        fsAddress = component.filesystem.address
        Kernel.io.status("info", "Using default filesystem with " .. Kernel.stfs .. ": " .. fsAddress)
    end
end

function Kernel.getScript(path)
    if not fsAddress then
        for retry = 1, 3 do
            for address in component.list("filesystem") do
                Kernel.io.status("info", "Testing filesystem: " .. address)
                local success, fs = pcall(component.proxy, address)
                if success and fs and fs.exists(path) then
                    fsAddress = address
                    Kernel.io.status("ok", "Found valid filesystem: " .. fsAddress)
                    break
                end
            end
            if fsAddress then break end
            Kernel.io.status("warn", "No suitable filesystem found, retry " .. retry .. "/3")
            Kernel.sleep(1)
        end
    end

    if not fsAddress then
        Kernel.io.status("err", "No filesystem containing " .. path .. " found!")
    end

    local fsObj
    for _ = 1, 3 do
        fsObj = component.proxy(fsAddress)
        if fsObj then break end
        Kernel.io.status("warn", "Failed to get filesystem proxy, retrying...")
        Kernel.sleep(1)
    end

    if not fsObj then
        Kernel.panic("Critical error: Cannot access filesystem!")
    end

    Kernel.io.status("info", "Loading: " .. path)

    local fHandle = fsObj.open(path, "r")
    if not fHandle then
        Kernel.io.status("warn", "Script " .. path .. " is empty or failed to load")
        local func, _ = load("", "=" .. path, "t", _ENV)
        return func
    end

    local scriptT = {}
    while true do
        local chunk = fsObj.read(fHandle, 1024)
        if not chunk then break end
        table.insert(scriptT, chunk)
    end
    local script = table.concat(scriptT)

    fsObj.close(fHandle)

    if script == "" then
        Kernel.io.status("warn", "Script " .. path .. " is empty or failed to load")
    end

    local func, err = load(script, "=" .. path, "t", _ENV)
    if not func then
        Kernel.io.status("err", "Error loading: " .. err)
    end
    return func
end

Kernel.getScript(Kernel.stfs)()

local drivers = stfs.list(stfs.primary, "/lib/modules/kernel/drivers/")

for _, path in ipairs(drivers) do
    local oldPath = path
    path = "/lib/modules/kernel/drivers/" .. path
    if stfs.isDirectory(stfs.primary, path) then goto continue end
    Kernel.io.status("info", "Driver detected:" .. oldPath)
    Kernel.getScript(path)()
    Kernel.io.status("ok", "Driver loaded")
    ::continue::
end

Kernel.getScript("/lib/vininit/vininit.lua")()
