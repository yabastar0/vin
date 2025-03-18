local component = component or require("component")
local computer = computer or require("computer")
local gpu = component.proxy(component.list("gpu")())
local screen = component.list("screen")()

_G.KERNELVER = "vinkern 0.0.b"
_G.OSVER     = "vinsys 0.0.b"

Kernel = {}
Kernel.term = {}
Kernel.io = {}

if gpu and screen then gpu.bind(screen) end

local w, h = gpu.getResolution()

Kernel.cursor = {
    ["pos"] = {1, 1},
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

local runlevel = "S"
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
    gpu.set(1,position[2] + 1, "Kernel recovered after error: ")
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
function Kernel.term.setGPU(setGPU) if setGPU then gpu = setGPU; w, h = gpu.getResolution() end end
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

function Kernel.io.print(msg)
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
        Kernel.io.writeChar(string.sub(msg,i,i))
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

if not interAddr then
    safeError("No Internet Card found! Please install one.")
else
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
