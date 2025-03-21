local component = component or require("component")
local computer  = computer or require("computer")
local gpu       = component.proxy(component.list("gpu")())
local screen    = component.list("screen")()

_G.KERNELVER    = "vinkern 0.0.b"
_G.OSVER        = "vinsys 0.0.b"

Kernel          = {}
Kernel.term     = {}
Kernel.io       = {}

Kernel.stfs     = "/lib/modules/kernel/drivers/fs/standardfs/stfs.ko"

if gpu and screen then gpu.bind(screen) end

local w, h = gpu.getResolution()

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

local runlevel
local old_shutdown = computer.shutdown

Kernel.panic = error
error = function(err)
    Kernel.term.setTextColor(0xFF0000)
    Kernel.io.print(err)
    Kernel.io.print(debug.traceback())
    Kernel.term.setTextColor(0xFFFFFF)
end

local safeError = function(err)
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

local function safeCall(func)
    return function(...)
        local success, result = pcall(func, ...)
        if not success then
            safeError(result)
        end
        return result
    end
end

function computer.runlevel() return runlevel end

function Kernel.busySleep(seconds)
    local target = computer.uptime() + seconds
    while computer.uptime() < target do end
end

function Kernel.sleep(seconds)
    local target = computer.uptime() + seconds
    while computer.uptime() < target do computer.pullSignal(0) end
end

function computer.shutdown(reboot)
    if reboot then
        runlevel = 6
    else
        runlevel = 0
    end
    computer.pushSignal("shutdown")
    Kernel.sleep(0.1)
    old_shutdown(reboot)
end

computer.shutdown = safeCall(computer.shutdown)

function Kernel.term.setTextColor(color) if gpu then gpu.setForeground(color) end end

function Kernel.term.getTextColor() if gpu then return gpu.getForeground() end end

function Kernel.term.setBackground(color) if gpu then gpu.setBackground(color) end end

function Kernel.term.getBackground() if gpu then return gpu.getBackground() end end

function Kernel.term.get(x, y) if gpu then return gpu.get(x, y) end end

function Kernel.term.set(x, y, value) if gpu then return gpu.set(x, y, value) end end

function Kernel.term.copy(x, y, w, h, tx, ty) if gpu then return gpu.copy(x, y, w, h, tx, ty) end end

function Kernel.term.fill(x, y, w, h, char) if gpu then return gpu.fill(x, y, w, h, char) end end

function Kernel.term.getGPU() if gpu then return gpu end end

function Kernel.term.setGPU(setGPU)
    if setGPU then
        gpu = setGPU; w, h = gpu.getResolution()
    end
end

function Kernel.term.scrollUp()
    Kernel.term.copy(1, 2, w, h - 1, 0, -1)
    Kernel.term.fill(1, h, w, 1, " ")
end

function Kernel.term.clear()
    Kernel.term.fill(1, 1, h, w, " ")
end

function Kernel.term.clearLine(line)
    if line then
        Kernel.term.fill(1, line, 1, w, " ")
    else
        Kernel.term.fill(1, Kernel.cursor.pos[2], 1, w, " ")
    end
end

function Kernel.io.print(...)
    local msg = table.concat({ ... }, " ")
    msg = tostring(msg)
    local position = Kernel.cursor.pos

    for line in string.gmatch(msg, "([^\n]*)\n?") do
        if gpu and screen then
            Kernel.term.set(position[1], position[2], line)

            if position[2] == h then
                Kernel.term.scrollUp()
                position[1] = 1
            else
                Kernel.cursor.pos[2] = position[2] + 1
            end
        end
    end
end

Kernel.io.print = safeCall(Kernel.io.print)

function Kernel.io.write(msg)
    msg = tostring(msg)
    local position = Kernel.cursor.pos

    if gpu and screen then
        Kernel.term.set(position[1], position[2], msg)
        Kernel.cursor.pos[1] = position[1] + #msg
    end
end

Kernel.io.write = safeCall(Kernel.io.write)

function Kernel.io.writeChar(char)
    local position = Kernel.cursor.pos
    if #char == 1 then
        Kernel.term.set(position[1], position[2], char)
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

local function serialize_impl(t, tracking, indent, opts)
    local sType = type(t)
    if sType == "table" then
        if tracking[t] ~= nil then
            if tracking[t] == false then
                error("Cannot serialize table with repeated entries")
            else
                error("Cannot serialize table with recursive entries")
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
        error("Cannot serialize type " .. sType)
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

            gpu.setForeground(savedBackground)
            gpu.setBackground(savedForeground)

            gpu.set(position[1], position[2], savedChar)

            gpu.setBackground(savedBackground)
            gpu.setForeground(savedForeground)
        else
            gpu.setForeground(savedForeground)
            gpu.setBackground(savedBackground)
            gpu.set(position[1], position[2], savedChar)
        end
        Kernel.cursor.visible = not Kernel.cursor.visible
    else
        if isVisible then
            savedChar, savedForeground, savedBackground = gpu.get(position[1], position[2])
            gpu.setForeground(savedBackground)
            gpu.setBackground(savedForeground)
            gpu.set(position[1], position[2], savedChar)
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

Kernel.SignalSystem.push = safeCall(computer.pushSignal)

Kernel.SignalSystem.listen("key_down", function(_, _, key)
    Kernel.io.print(("Key pressed: " .. string.char(key)) or "Unknown key")
end)


local fsAddress = nil
if not component.filesystem then
    for address in component.list("filesystem") do
        Kernel.io.print("Found filesystem: " .. address)
        if not fsAddress then
            fsAddress = address
        end
    end

    if not fsAddress then
        error("No filesystem component found! Please ensure a drive is attached.")
    end

    Kernel.io.print("Using filesystem with address: " .. fsAddress)
else
    Kernel.io.print("Filesystem already available at: " .. component.filesystem.address)
end

local fsObj = component.proxy(fsAddress)
component.filesystem = fsObj

local stfsHandle = fsObj.open(Kernel.stfs, "r")

local script = ""
while true do
    local chunk = fsObj.read(stfsHandle, 1024)
    if not chunk then break end
    script = script .. chunk
end

fsObj.close(stfsHandle)

local func, err = load(script, "=" .. Kernel.stfs, "t", _ENV)
if not func then
    error("Error loading: " .. err)
end

func()
