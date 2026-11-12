-- ============================================================
-- F15E_Jammer_AutoLoader.lua
-- Hook loader for F15E_Auto_Jammer.lua
--
-- Install to:
--   Saved Games\DCS\Scripts\Hooks\
--
-- Jammer file:
--   Saved Games\DCS\Scripts\F15E_Auto_Jammer.lua
--
-- The Hook:
--   1) reads the file using IO (allowed inside the Hook);
--   2) waits for the simulation to actually be running;
--   3) injects the script's CONTENT into the Mission Environment
--      using net.dostring_in("mission", "a_do_script(...)").
--
-- Does not use dofile() in the Mission Environment, because IO/LFS
-- are sanitized in that environment by default.
-- ============================================================

local JAMMER_SCRIPT_PATH =
    (lfs.writedir() .. "Scripts/F15E_Auto_Jammer.lua"):gsub("\\", "/")

local state = {
    missionLoaded = false,
    simStarted = false,
    injected = false,
    attempt = 0,
    lastAttempt = -1000,
}

-- Picks a Lua long-string delimiter that does not appear in the payload.
local function makeLongString(s)
    for n = 0, 20 do
        local eq = string.rep("=", n)
        local closeToken = "]" .. eq .. "]"
        if not string.find(s, closeToken, 1, true) then
            return "[" .. eq .. "[" .. s .. "]" .. eq .. "]"
        end
    end
    return nil
end

local function readJammer()
    local f, err = io.open(JAMMER_SCRIPT_PATH, "r")
    if not f then
        return nil, "Jammer file not found: " ..
            JAMMER_SCRIPT_PATH .. " | error=" .. tostring(err)
    end

    local code = f:read("*a")
    f:close()

    if type(code) ~= "string" or code == "" then
        return nil, "Jammer file is empty or could not be read."
    end

    return code
end

local function injectJammer()
    if state.injected then
        return true
    end

    local now = os.clock()

    -- Avoids hammering the Mission Environment if something goes wrong.
    if now - state.lastAttempt < 2 then
        return false
    end

    state.lastAttempt = now
    state.attempt = state.attempt + 1

    local code, err = readJammer()
    if not code then
        log.write(
            "F15E_JAMMER_LOADER",
            log.ERROR,
            "Failed to read jammer file: " .. tostring(err)
        )
        return false
    end

    local wrapped = makeLongString(code)
    if not wrapped then
        log.write(
            "F15E_JAMMER_LOADER",
            log.ERROR,
            "Could not create a safe delimiter for the script."
        )
        return false
    end

    -- IMPORTANT:
    -- a_do_script() must run inside the Mission Environment.
    -- The jammer code is sent over as a single string.
    local injectCode =
        "if not _G.F15E_JAMMER_LOADED then " ..
        "local ok_, err_ = pcall(function() " ..
        "_G.F15E_JAMMER_LOADED = true; " ..
        "a_do_script(" .. wrapped .. ")" ..
        " end); " ..
        "if not ok_ then " ..
        "env.info('F15E_JAMMER: error during a_do_script: ' .. tostring(err_)); " ..
        "_G.F15E_JAMMER_LOADED = nil; " ..
        "end " ..
        "end"

    local ok, result = pcall(function()
        return net.dostring_in("mission", injectCode)
    end)

    if not ok then
        log.write(
            "F15E_JAMMER_LOADER",
            log.ERROR,
            "net.dostring_in failed: " .. tostring(result)
        )
        return false
    end

    -- In some DCS versions the return value may not carry an error
    -- even when the script has not actually been processed yet. The
    -- payload writes its own log line when it starts up.
    log.write(
        "F15E_JAMMER_LOADER",
        log.INFO,
        "F15E_JAMMER payload sent to the Mission Environment. attempt=" ..
            tostring(state.attempt) ..
            " return=" .. tostring(result)
    )

    state.injected = true
    return true
end

local callbacks = {}

function callbacks.onMissionLoadBegin()
    state.missionLoaded = false
    state.simStarted = false
    state.injected = false
    state.attempt = 0
    state.lastAttempt = -1000

    log.write(
        "F15E_JAMMER_LOADER",
        log.INFO,
        "onMissionLoadBegin - preparing autoload"
    )
end

function callbacks.onMissionLoadEnd()
    state.missionLoaded = true

    log.write(
        "F15E_JAMMER_LOADER",
        log.INFO,
        "onMissionLoadEnd - mission loaded; waiting for simulation frame"
    )
end

function callbacks.onSimulationStart()
    state.simStarted = true

    log.write(
        "F15E_JAMMER_LOADER",
        log.INFO,
        "onSimulationStart - ready to inject"
    )
end

function callbacks.onSimulationFrame()
    if not state.missionLoaded then
        return
    end

    if not state.simStarted then
        -- Some versions/flows may not fire in exactly the expected
        -- order; the frame itself already confirms the simulation is
        -- active.
        state.simStarted = true
    end

    if not state.injected then
        injectJammer()
    end
end

function callbacks.onSimulationStop()
    state.missionLoaded = false
    state.simStarted = false
    state.injected = false

    log.write(
        "F15E_JAMMER_LOADER",
        log.INFO,
        "onSimulationStop - autoloader state reset"
    )
end

local ok, err = pcall(function()
    DCS.setUserCallbacks(callbacks)
end)

if ok then
    log.write(
        "F15E_JAMMER_LOADER",
        log.INFO,
        "F15E_Jammer_AutoLoader loaded successfully"
    )
else
    log.write(
        "F15E_JAMMER_LOADER",
        log.ERROR,
        "DCS.setUserCallbacks failed: " .. tostring(err)
    )
end
