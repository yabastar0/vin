_G.term = {}
local gpu       = component.proxy(component.list("gpu")())

if _G.CanDisplay then
    function term.setTextColor(color) if gpu then gpu.setForeground(color) end end
    function term.getTextColor() if gpu then return gpu.getForeground() end end
    function term.setBackground(color) if gpu then gpu.setBackground(color) end end
    function term.getBackground() if gpu then return gpu.getBackground() end end
    function term.get(x, y) if gpu then return gpu.get(x, y) end end
    function term.set(x, y, value) if gpu then return gpu.set(x, y, value) end end
    function term.copy(x, y, w, h, tx, ty) if gpu then return gpu.copy(x, y, w, h, tx, ty) end end
    function term.fill(x, y, w, h, char) if gpu then return gpu.fill(x, y, w, h, char) end end
    function term.getGPU() if gpu then return gpu end end

    function term.setGPU(setGPU)
        if setGPU then
            gpu = setGPU; _G.Res[1], _G.Res[2] = gpu.getResolution()
        end
    end

    function term.scrollUp()
        term.copy(1, 2, _G.Res[1], _G.Res[2] - 1, 0, -1)
        term.fill(1, _G.Res[2], _G.Res[1], 1, " ")
    end

    function term.clear()
        term.fill(1, 1, _G.Res[2], _G.Res[1], " ")
    end

    function term.clearLine(line)
        if line then
            term.fill(1, line, 1, _G.Res[1], " ")
        else
            term.fill(1, Kernel.cursor.pos[2], 1, _G.Res[1], " ")
        end
    end
end
