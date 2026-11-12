-- ============================================================
-- F15E_Jammer_Switches_Export.lua
-- Reads the F-15E TEWS panel switches (ICS ON/OFF + SET 1/2/3
-- MAN/AUTO) via GetDevice(0):get_argument_value(), and writes their
-- state to a file that the mission-side jammer script reads.
--
-- CONFIRMED via diagnostic testing: GetDevice(0) (not a named device
-- like EWS_JMR) is the correct way to read ANY cockpit argument value
-- externally via Export.lua, regardless of which internal "device"
-- conceptually drives that switch.
--
-- Argument numbers (from clickabledata.lua, TEWS Control Panel /
-- Right Console):
--   1465 = ICS ON/OFF Switch          (0 = OFF,  1 = ON)
--   1466 = ICS SET 1 MAN/AUTO Switch  (0 = MAN,  1 = AUTO)
--   1467 = ICS SET 2 MAN/AUTO Switch  (0 = MAN,  1 = AUTO)
--   1468 = ICS SET 3 MAN/AUTO Switch  (0 = MAN,  1 = AUTO)
--
-- State file format: one line "M,1,2,3,C" with 0/1 for each switch
-- (master, set1, set2, set3) and C = a monotonic integer counter of
-- CMD (chaff/flare) actuations, detected via LoGetSnares() (a drop
-- in the remaining chaff or flare count).
-- ============================================================

-- IMPORTANT: Export.lua loads several scripts in sequence in the same
-- Lua environment (Tacview, DCSDTC, ModernF15E, EMIS_LMT_MOD, and this
-- one). Each script MUST capture whatever LuaExportStart/Stop/
-- ActivityNextEvent was already defined by the PREVIOUS scripts and
-- call it from inside its own version - otherwise, whichever script
-- loads LAST silently overwrites everyone else's ticking function,
-- and all the earlier scripts stop being called entirely. This was
-- exactly the bug found on 2026-09-14: this file was overwriting
-- EMIS_LMT_Export.lua's LuaExportActivityNextEvent without chaining.
local PrevExportStart    = LuaExportStart
local PrevExportStop     = LuaExportStop
local PrevExportActivity = LuaExportActivityNextEvent

local STATE_FILE = lfs.writedir() .. "Scripts/F15E_Jammer_Switches_state.txt"
local CHECK_INTERVAL = 0.25
local lastCheck = 0
local lastWritten = nil

local ARGS = {
    master = 1465,
    set1   = 1466,
    set2   = 1467,
    set3   = 1468,
}

-- CMD (chaff/flare) button detection via LoGetSnares() - a real
-- Export.lua function that returns the aircraft's REMAINING chaff/
-- flare count. Since this is a shared aircraft-level count (not
-- seat-specific), any actuation by either the pilot OR the WSO shows
-- up the same way here - no need to tell them apart.
--
-- We use a MONOTONIC COUNTER (not a resettable latch) to avoid a race
-- between this script's write rate (0.25s) and the mission script's
-- read rate (1.0s) - the counter only ever grows, never resets on its
-- own, so the reader side just compares against the last value it
-- itself has seen.
--
-- KNOWN LIMIT, HANDLED: if chaff AND flare both reach ZERO, there's
-- no more "count drop" to detect - this method goes blind to presses
-- exactly when the crew needs it most. In that specific case, instead
-- of blocking the manual trigger, we treat it as a continuous signal
-- (bump the counter every cycle while chaff=0 and flare=0) - sets in
-- MAN become available just like AUTO for as long as that condition
-- lasts, since the crew has no other way to signal us and blocking
-- their self-defense would be worse than defaulting to available.
--
-- IMPORTANT: this fallback only kicks in after we've detected at
-- least ONE moment with chaff/flare > 0 (i.e. the aircraft actually
-- ran out DURING the flight). Without this guard, an aircraft loaded
-- WITHOUT any chaff/flare from the start (incomplete/empty loadout)
-- would have this fallback active the whole time, even with zero
-- real actuations - leaving MAN sets permanently behaving like AUTO
-- without the pilot doing anything.
local lastChaff, lastFlare = nil, nil
local everHadCountermeasures = false
local cmdPressCount = 0

local function checkCmdPress()
    local ok, snares = pcall(LoGetSnares)
    if not ok or not snares then return end
    if type(snares.chaff) ~= "number" or type(snares.flare) ~= "number" then return end

    if snares.chaff > 0 or snares.flare > 0 then
        everHadCountermeasures = true
    end

    if lastChaff == nil then lastChaff = snares.chaff end
    if lastFlare == nil then lastFlare = snares.flare end

    local outOfCountermeasures = everHadCountermeasures
        and snares.chaff <= 0 and snares.flare <= 0

    if snares.chaff < lastChaff or snares.flare < lastFlare or outOfCountermeasures then
        cmdPressCount = cmdPressCount + 1
    end

    lastChaff = snares.chaff
    lastFlare = snares.flare
end

local function readSwitches()
    local ok, result = pcall(function()
        local dev = GetDevice(0)
        if not dev then return nil end
        return {
            master = dev:get_argument_value(ARGS.master),
            set1   = dev:get_argument_value(ARGS.set1),
            set2   = dev:get_argument_value(ARGS.set2),
            set3   = dev:get_argument_value(ARGS.set3),
        }
    end)
    if ok then return result end
    return nil, result
end

-- Unconditional log (not filtered by anything) whenever the raw ICS
-- ON/OFF argument value changes - an extra diagnostic point,
-- independent of the mission script, to isolate whether an issue is
-- in this switch reading or in the state file being passed/read.
local lastMasterRaw = nil
local function logMasterChange(master)
    if master == nil then return end
    if lastMasterRaw ~= nil and math.abs(master - lastMasterRaw) > 0.01 then
        log.write("F15E_JMR_SW_EXPORT", log.INFO,
            string.format("ICS master raw changed from %.3f to %.3f", lastMasterRaw, master))
    end
    lastMasterRaw = master
end

local function toBit(v)
    if v == nil then return "1" end -- safe fallback: assume ON if not read
    if v >= 0.5 then return "1" end
    return "0"
end

-- For the SET 1/2/3 MAN/AUTO switches: physically, the DOWN position
-- is AUTO and the UP position is MAN (confirmed via a real cockpit
-- photo) - the raw value from get_argument_value() is the OPPOSITE
-- of what the "MAN/AUTO" name order suggested (raw near 1 = MAN, raw
-- near 0 = AUTO). This function inverts that on write, so the bit
-- stored in the file keeps meaning "1 = AUTO" consistently for the
-- mission script (which doesn't need to know about this physical
-- inversion).
local function toBitAutoDown(v)
    if v == nil then return "1" end -- safe fallback: assume AUTO if not read
    if v >= 0.5 then return "0" end  -- raw near 1 (MAN, up) -> bit "0"
    return "1"                        -- raw near 0 (AUTO, down) -> bit "1"
end

local function writeState(sw)
    local line = string.format("%s,%s,%s,%s,%d",
        toBit(sw.master), toBitAutoDown(sw.set1), toBitAutoDown(sw.set2), toBitAutoDown(sw.set3),
        cmdPressCount)
    if line == lastWritten then return end -- avoid unnecessary disk writes

    local f, err = io.open(STATE_FILE, "w")
    if not f then
        log.write("F15E_JMR_SW_EXPORT", log.ERROR, "Failed to write state file: " .. tostring(err))
        return
    end
    f:write(line)
    f:close()
    lastWritten = line
end

function LuaExportStart()
    if PrevExportStart then PrevExportStart() end
    log.write("F15E_JMR_SW_EXPORT", log.INFO, "F15E_Jammer_Switches_Export.lua started - file=" .. tostring(STATE_FILE))
end

function LuaExportStop()
    if PrevExportStop then PrevExportStop() end
end

function LuaExportActivityNextEvent(t)
    if t - lastCheck >= CHECK_INTERVAL then
        lastCheck = t
        checkCmdPress()
        local sw, err = readSwitches()
        if sw then
            logMasterChange(sw.master)
            writeState(sw)
        else
            log.write("F15E_JMR_SW_EXPORT", log.ERROR, "readSwitches failed: " .. tostring(err))
        end
    end

    local tNext = t + 0.05
    if PrevExportActivity then
        local ok, prevNext = pcall(PrevExportActivity, t)
        -- We don't adopt their returned time, just make sure they still run.
    end

    return tNext
end
