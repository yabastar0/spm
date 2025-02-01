-- spm by subOct

local args = { ... }

local flags = {}
local data = {}
local base = "https://raw.githubusercontent.com/yabastar0/spm/refs/heads/main"

local function err_print(text)
    io.write("[ ")
    local old_fg = term.getTextColor()
    term.setTextColor(colors.red)
    io.write("E")
    term.setTextColor(old_fg)
    io.write(" ] ")
    print(text)
end

local function work_print(text)
    io.write("[ ")
    local old_fg = term.getTextColor()
    term.setTextColor(colors.green)
    io.write("OK")
    term.setTextColor(old_fg)
    io.write(" ] ")
    print(text)
end

local json = false
local function checkJSON()
    if not fs.exists("var/lib/spm/json.lua") then
        err_print("JSON interpreter not found. Run 'spm verify' to verify your installation.")
        error("", 0)
    else
        if json == false then
            json = require("var/lib/spm/json")
        end
    end
end

local libdef = false
local function check_libdef()
    if not fs.exists("var/lib/spm/libdef.lua") then
        err_print("libdef.lua not found. Run 'spm verify' to verify your installation.")
        error("", 0)
    else
        if libdef == false then
            libdef = require("var/lib/spm/libdef")
        end
    end
end

local function parse_archive(tmpjdata)
    if not tmpjdata or not tmpjdata.fs then
        err_print("Invalid archive data: missing 'fs' key")
        error("", 0)
    end

    for dirpath, files in pairs(tmpjdata.fs) do
        fs.makeDir(dirpath)

        for _, file in ipairs(files) do
            local filepath = fs.combine(dirpath, file.filename)

            local tmp = fs.open(filepath, "w")
            if file.content then
                tmp.write(file.content)
            elseif file.content_link then
                shell.run("wget "..file.content_link.." tmp/parsetmp")
                work_print("Retreived content link "..file.content_link)
                local tmpparse = fs.open("tmp/parsetmp","r")
                local tmpparsedat = tmpparse.readAll()
                tmpparse.close()
                fs.delete("tmp/parsetmp")
                tmp.write(tmpparsedat)
            end
            tmp.close()
        end
    end
end

for _, arg in ipairs(args) do
    if arg:sub(1, 1) == "-" then
        table.insert(flags, #flags + 1, arg:sub(2))
    else
        table.insert(data, #data + 1, arg)
    end
end

local function need(dt, de, more)
    if more then
        if #dt == 1 then
            return false
        end
    else
        if not (textutils.serialise(dt) == textutils.serialise(de)) then
            return false
        end
    end
    return true
end

local function resolve_dependencies(packages, package_name, resolved, seen)
    if seen[package_name] then
        return
    end
    seen[package_name] = true

    local package
    for _, pkg in ipairs(packages) do
        if pkg.name == package_name then
            package = pkg
            break
        end
    end

    if not package then
        err_print("Package not found: " .. package_name)
        error("", 0)
    end

    if not resolved[package_name] then
        resolved[package_name] = package
    end

    for _, dep in ipairs(package.dependencies or {}) do
        if type(dep) == "table" and dep.name then
            resolve_dependencies(packages, dep.name, resolved, seen)
        else
            err_print("Invalid dependency format in package: " .. package.name)
        end
    end    
end

local function get_package_dependencies(fdat, package_name)
    local resolved = {}
    local seen = {}
    resolve_dependencies(fdat, package_name, resolved, seen)

    return resolved
end

if need(data, { "verify" }) then
    print("SPM verification")
    local urls = {
        ["https://raw.githubusercontent.com/yabastar0/spm/refs/heads/main/meta.json"] = { "var/lib/spm/lists/meta.json", "meta.json" },
        ["https://raw.githubusercontent.com/rxi/json.lua/refs/heads/master/json.lua"] = { "var/lib/spm/json.lua", "json.lua" },
        ["https://raw.githubusercontent.com/MCJack123/CC-Archive/refs/heads/master/LibDeflate.lua"] = {"var/lib/spm/libdef.lua", "libdef.lua"}
    }
    local t_size = 0
    local missing = 0
    for url, loc in pairs(urls) do
        if not fs.exists(loc[1]) then
            missing = missing + 1
            local response, _ = http.head(url, "")

            if response then
                local headers = response.getResponseHeaders()
                response.close()

                if headers["Content-Length"] then
                    t_size = t_size + tonumber(headers["Content-Length"])
                end
            end
        end
    end

    if not fs.isDir("tmp") then
        fs.makeDir("tmp")
    end

    if not fs.isDir("var") then
        fs.makeDir("var")
    end

    if not fs.isDir("var/lib") then
        fs.makeDir("var/lib")
    end

    if not fs.isDir("var/lib/spm") then
        fs.makeDir("var/lib/spm")
    end

    if not fs.isDir("var/lib/spm/lists") then
        fs.makeDir("var/lib/spm/lists")
    end

    if missing > 0 then
        print(tostring(missing) .. " missing file(s).")
        local t_str
        if t_size > 1999 then
            t_str = tostring(math.floor((t_size / 1024) * 100) / 100) .. "kB"
        else
            t_str = tostring(math.floor(t_size * 100) / 100) .. "B"
        end

        local ans = ""
        repeat
            print("")
            io.write("Install missing files? [" .. t_str .. "] (y/n): ")
            ans = io.read()
        until ans == "y" or ans == "n"

        if ans == "y" then
            for url, loc in pairs(urls) do
                print("Installing " .. loc[2] .. "...")
                shell.run("wget " .. url .. " " .. loc[1])
                work_print(loc[2] .. " installed!")
            end
        end
    end
    print("Verified.")
elseif need(data, { "help" }) then
    print([[spm -- Starlight package manager

    Available commands:

    verify        // Verifies spm. Run this first

    help          // Displays this menu

    download      // Downloads a package. Alias 'install', 'ins'
        -s        // Downloads silently

    delete        // Deletes a package. Alias 'del'

    update        // Updates a package. Alias 'up'
        -a        // Updates all packages

    list          // Lists all packages
    ]])
elseif need(data, { "list" }) then
    checkJSON()

    if not fs.exists("var/lib/spm/lists/meta.json") then
        err_print("meta.json not found. Run 'spm verify' to download it.")
        error("", 0)
    end

    local tmp = fs.open("var/lib/spm/lists/meta.json", "r")
    local fdat = tmp.readAll()
    tmp.close()

    local metadata = json.decode(fdat)

    if not metadata or not metadata.packages then
        err_print("Invalid meta.json file. Missing 'packages' key.")
        error("", 0)
    end

    for _, v in pairs(metadata.packages) do
        print("Name: " .. v.name)
        print("Version: " .. v.version .. "\n")
    end
elseif need(data, { "download" }, true) then
    checkJSON()
    check_libdef()

    if not fs.exists("var/lib/spm/lists/meta.json") then
        err_print("meta.json not found. Run 'spm verify' to download it.")
        error("", 0)
    end

    local tmp = fs.open("var/lib/spm/lists/meta.json", "r")
    local fdat = tmp.readAll()
    tmp.close()
    local metadata = json.decode(fdat)

    if not metadata or not metadata.packages then
        err_print("Invalid meta.json file. Missing 'packages' key.")
        error("", 0)
    end

    local package_name = data[2]
    if not package_name then
        err_print("No package specified. Usage: spm download <package-name>")
        error("", 0)
    end
    local dependencies = get_package_dependencies(metadata.packages, package_name)

    local required_installs = {}

    for name, package in pairs(dependencies) do
        table.insert(required_installs, {
            name = name,
            version = package.version,
            source = package.source
        })
    end

    print("Required packages: ")
    for _, install in ipairs(required_installs) do
        print("  Package: " .. install.name .. " (Version: " .. install.version .. ", Source: " .. install.source .. ")")
    end

    local t_size = 0
    for _,install in ipairs(required_installs) do
        if not fs.exists("tmp/"..(install.source)) then
            local response, _ = http.head(base..(install.source), "")

            if response then
                local headers = response.getResponseHeaders()
                response.close()

                if headers["Content-Length"] then
                    t_size = t_size + tonumber(headers["Content-Length"])
                end
            end
        end
    end
    local t_str
    if t_size > 1999 then
        t_str = tostring(math.floor((t_size / 1024) * 100) / 100) .. "kB"
    else
        t_str = tostring(math.floor(t_size * 100) / 100) .. "B"
    end

    local ans = ""
    repeat
        print("")
        io.write("Install missing packages? [" .. t_str .. "] (y/n): ")
        ans = io.read()
    until ans == "y" or ans == "n"

    if ans == "y" then
        for _,install in ipairs(required_installs) do
            print("Installing " .. install.name .. " " .. install.version .. "...")
            shell.run("wget " .. base .. install.source .. " tmp/"..install.source)
            local tmp = fs.open("tmp/"..install.source,"r")
            local tmpdata = tmp.readAll()
            tmp.close()
            local ngzdata = libdef:DecompressGzip(tmpdata)
            local tmpjdata = json.decode(ngzdata)
            parse_archive(tmpjdata)
            work_print(install.name .. " installed!")
        end
    end
else
    print("Command not expected")
end
