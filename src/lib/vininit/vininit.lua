local execinitlist = stfs.list(stfs.primary, "/etc/init/")

for _,path in ipairs(execinitlist) do
    Kernel.getScript(path)()
end

Kernel.getScript("/bin/sh.lua")()
