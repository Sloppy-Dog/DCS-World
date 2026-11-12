-- ============================================================
-- EMIS_LMT_Export.lua
-- Unofficial EMIS LIMIT mod for the F-15E (DCS World)
--
-- VERSION 1.0
--
-- Direct design: both the pilot's button (PTN_287) and the WSO's
-- button (PTN_1312) trigger the same logic directly (no relay between
-- seats). We tried a relay to the pilot's physical button in an
-- earlier iteration, hoping it would unblock radar/JTIDS when
-- triggered from the WSO seat - but the relay itself proved unreliable
-- (the command sometimes failed to register), so we reverted to this
-- simpler, more robust approach.
--
-- IMPORTANT - known radar/JTIDS limitation from the WSO seat: this is
-- not a wrong command/device/argument problem. It's a CREW
-- SYNCHRONIZATION (multicrew) restriction in the engine/module itself -
-- confirmed using a REAL physical switch (Cipher Text) commanding the
-- radar directly: even then, the radar only changes state when the
-- command is PROCESSED with the PILOT seat as the active control point
-- at that exact moment, no matter which button/device triggered the
-- command. This has no scripting workaround.
--
-- TF->LPI and the ICS switch do NOT have this restriction - they work
-- normally from either seat, including when triggered by the WSO.
--
-- Page navigation uses "hold" clicks (press, hold ~150ms, release)
-- instead of an instant press+release, which did not register on the
-- MPCDR page-switching buttons (PB11/PB4 etc). Confirmed by testing:
-- instant press+release fails, a 150ms hold works.
--
-- The TF LPI/NORM state is tracked in its OWN variable (EMIS.tfLpiOn),
-- independent of whichever page is currently displayed - since the
-- page can change between activation and deactivation, we can't infer
-- the state just by looking at the current page.
--
-- Navigation logic (from ANY page):
--   - Already on TF: just press the final button (PB9=LPI or PB6=NORM).
--   - On Menu 1 (identifiable by the ADI+ARMT labels): PB4, then final.
--   - On any other function page: PB11 (goes to M1), PB4, then final.
--   - On M2 or M3 (can't tell them apart by label, both read as
--     "UNKNOWN"): when we CAN read the result (WSO present), we retry
--     up to 3 times, checking after each PB11 whether we reached M1.
--     When we CANNOT read it (triggered by the pilot alone, nobody in
--     the WSO seat), we make only 1 attempt (no way to verify, and
--     multiple blind attempts risk cycling through the wrong menus).
--
-- Devices/commands confirmed by in-game testing:
--   GetDevice(0)  = read model arguments
--   GetDevice(1)  = RDRCTRL_AA    -> command 3476 (JTIDS knob)
--   GetDevice(3)  = AN_APG70      -> command 3471 (Radar Mode Selector)
--   GetDevice(40) = MPCD_RRIGHT   -> Button_XX commands
--   GetDevice(61) = ICS ON/OFF switch (right rear console) -> command 3921
--
-- Page fingerprints via list_indication (index is scanned, not fixed):
--   MENU (specifically M1): contains "ADI" and "ARMT"
--   ADI: "ADI_Indicator_Begins"      HSI: "HSI_Indicator_Begins"
--   ARMT: "PACS_PB01_LABEL"          TSD: "TSD_MAP_RENDER"
--   TF:   "TFR_PB1"                  TPOD: "NF_Video_Open"
--   TEWS: "TEWS_CENTER"
--
-- KNOWN LIMITATION: list_indication only returns data for the seat
-- currently being controlled. Flying solo as the pilot, the read fails
-- (returns "NOREAD") - in that case we operate blind, with a single
-- navigation attempt (see above). This only affects restoring the
-- exact MPCD_RRIGHT page on shutdown; it does not affect radar/JTIDS/
-- TF-LPI, which work fully from either seat.
-- ============================================================

local PrevExportStart    = LuaExportStart
local PrevExportStop     = LuaExportStop
local PrevExportActivity = LuaExportActivityNextEvent

-- ============================================================
-- OPTIONS - all player-configurable settings live here
-- ============================================================

-- Which rear MPCD should the mod use for the TF/LPI function?
-- By default, the mod uses MPCD_RRIGHT (the least-used one, in the
-- mod author's own experience). If you (or your WSO) prefer to use
-- MPCD_RLEFT instead, change the line below to "RLEFT".
local WSO_DISPLAY_CHOICE = "RRIGHT"  -- "RRIGHT" (default) or "RLEFT"

-- ============================================================
-- END OF OPTIONS - nothing below this line needs to be edited
-- ============================================================

-- ===== Confirmed constants =====
local RADAR_CMD  = 3471
local JTIDS_CMD  = 3476

-- ICS ON/OFF switch on the rear right console (PTN_1465, confirmed via
-- clickabledata.lua: default_2_position_tumb_animated).
-- Used to turn off the jammers indirectly (the separate jammer mod
-- watches this switch on its own).
local ICS_DEVICE = 61   -- CONFIRMED by in-game testing (direct value, not a toggle click)
local ICS_CMD    = 3921
local ICS_ARG    = 1465
local ICS_OFF_VALUE = 0.0  -- CONFIRMED by testing (reading showed ON=1, OFF=0)
local RADAR_STBY = 0.33
local JTIDS_OFF  = 0.00

local BUTTON_CMD = {
	[1]=3061,[2]=3062,[3]=3063,[4]=3064,[5]=3065,[6]=3066,[7]=3067,[8]=3068,
	[9]=3069,[10]=3070,[11]=3071,[12]=3072,[13]=3073,[14]=3074,[15]=3075,
	[16]=3076,[17]=3077,[18]=3078,[19]=3079,[20]=3080,
}
local PB_MENU_RETURN = 11
local PB_TF      = 4
local PB_TF_NORM = 6
local PB_TF_LPI  = 9

-- Both device IDs and self-identifying tags below are CONFIRMED by
-- testing (list_indication discovery method) - this table just maps
-- the OPTIONS choice above to the right values, no need to edit it.
local WSO_DISPLAY_PROFILES = {
	RRIGHT = { device = 40, tag = "MPCDR" },
	RLEFT  = { device = 37, tag = "MPCDL" },
}

local WSO_DISPLAY = WSO_DISPLAY_PROFILES[WSO_DISPLAY_CHOICE]
if WSO_DISPLAY == nil then
	log.write("EMIS_LMT_MOD", log.ERROR, "Invalid WSO_DISPLAY_CHOICE: " .. tostring(WSO_DISPLAY_CHOICE) .. " - using RRIGHT")
	WSO_DISPLAY = WSO_DISPLAY_PROFILES.RRIGHT
end

local MPCDR_DEVICE_INDEX = WSO_DISPLAY.device
local MPCD_SELF_TAG = WSO_DISPLAY.tag

local HOLD_TIME = 0.15   -- how long to "hold" the click (confirmed necessary)
local GAP_AFTER = 0.30   -- wait time after release, before the next click

local PAGE_FINGERPRINTS = {
	{name="ADI",  marker="ADI_Indicator_Begins"},
	{name="ARMT", marker="PACS_PB01_LABEL"},
	{name="HSI",  marker="HSI_Indicator_Begins"},
	{name="TF",   marker="TFR_PB1"},
	{name="TSD",  marker="TSD_MAP_RENDER"},
	{name="TPOD", marker="NF_Video_Open"},
	{name="TEWS", marker="TEWS_CENTER"},
}

-- ===== Timed command queue (chained) =====
local CommandQueue = {}
local QueueNextTime = nil

local function queueClear()
	CommandQueue = {}
	QueueNextTime = nil
end

local function queuePush(delay, fn)
	table.insert(CommandQueue, {delay = delay, fn = fn})
end

local function queueProcess(t)
	if #CommandQueue == 0 then return end
	if QueueNextTime == nil then
		QueueNextTime = t + CommandQueue[1].delay
		return
	end
	if t >= QueueNextTime then
		local item = table.remove(CommandQueue, 1)
		local ok, err = pcall(item.fn)
		if not ok then
			log.write("EMIS_LMT_MOD", log.ERROR, "Error running queue item: " .. tostring(err))
		end
		if #CommandQueue > 0 then
			QueueNextTime = t + CommandQueue[1].delay
		else
			QueueNextTime = nil
		end
	end
end

-- ===== Mod state =====
local EMIS = {
	active         = false,   -- EMIS LMT on/off
	tfLpiOn        = false,   -- LOGICAL LPI state, independent of the current page
	prevArg287     = 0,
	prevArg1312    = 0,
	lastToggleTime = nil,
	savedRadarArg  = nil,
	savedJtidsArg  = nil,
	savedIcsArg    = nil,
}

local TOGGLE_COOLDOWN = 0.4

function LuaExportStart()
	if PrevExportStart then PrevExportStart() end
	EMIS.active = false
	EMIS.tfLpiOn = false
	EMIS.prevArg287 = 0
	EMIS.prevArg1312 = 0
	queueClear()
	log.write("EMIS_LMT_MOD", log.INFO, "EMIS_LMT_Export.lua (v1.0) started")
end

function LuaExportStop()
	if PrevExportStop then PrevExportStop() end
end

local function sendCommand(deviceIndex, command, value)
	local okDev, dev = pcall(GetDevice, deviceIndex)
	if not okDev or dev == nil then
		log.write("EMIS_LMT_MOD", log.ERROR, string.format(
			"GetDevice(%d) failed while sending command %d", deviceIndex, command))
		return false
	end
	local okCall, err = pcall(function()
		dev:performClickableAction(command, value)
	end)
	if not okCall then
		log.write("EMIS_LMT_MOD", log.ERROR, string.format(
			"performClickableAction dev=%d cmd=%d failed: %s", deviceIndex, command, tostring(err)))
		return false
	end
	return true
end

-- Sends the command and SCHEDULES up to 4 follow-up checks (every
-- 0.3s): if the argument hasn't changed to the expected value, resend.
-- Some commands (found by testing) need several attempts to "stick",
-- depending on the context that triggered them.
local function sendCommandVerified(deviceIndex, command, argNumber, expectedValue, label, attemptsLeft)
	attemptsLeft = attemptsLeft or 2
	sendCommand(deviceIndex, command, expectedValue)
	queuePush(0.3, function()
		local d0 = GetDevice(0)
		if d0 == nil then return end
		local actual = d0:get_argument_value(argNumber)
		if actual == nil or math.abs(actual - expectedValue) > 0.05 then
			if attemptsLeft > 1 then
				log.write("EMIS_LMT_MOD", log.INFO, string.format(
					"%s did not confirm (value=%s, expected=%s) - resending (%d attempts left)",
					tostring(label), tostring(actual), tostring(expectedValue), attemptsLeft - 1))
				sendCommandVerified(deviceIndex, command, argNumber, expectedValue, label, attemptsLeft - 1)
			else
				log.write("EMIS_LMT_MOD", log.ERROR, string.format(
					"%s: out of attempts, could not confirm (value=%s, expected=%s)",
					tostring(label), tostring(actual), tostring(expectedValue)))
			end
		else
			log.write("EMIS_LMT_MOD", log.INFO, label .. ": confirmed OK")
		end
	end)
end

-- ===== ICS command: a direct value works fine (no toggle click
-- needed, contrary to what we initially suspected) =====
local function setIcsTarget(targetValue, label, attemptsLeft)
	attemptsLeft = attemptsLeft or 2
	local d0 = GetDevice(0)
	local current = d0 and d0:get_argument_value(ICS_ARG)
	if current == nil then
		log.write("EMIS_LMT_MOD", log.ERROR, label .. ": could not read the current ICS state")
		return
	end

	if math.abs(current - targetValue) <= 0.05 then
		log.write("EMIS_LMT_MOD", log.INFO, label .. ": already in the right state (" .. tostring(current) .. "), no click needed")
		return
	end

	log.write("EMIS_LMT_MOD", log.INFO, string.format("%s: sending GetDevice(%d) direct value = %s", label, ICS_DEVICE, tostring(targetValue)))
	sendCommand(ICS_DEVICE, ICS_CMD, targetValue)  -- direct value, not a toggle click

	queuePush(0.3, function()
		local d0b = GetDevice(0)
		local actual = d0b and d0b:get_argument_value(ICS_ARG)
		if actual ~= nil and math.abs(actual - targetValue) <= 0.05 then
			log.write("EMIS_LMT_MOD", log.INFO, label .. ": confirmed OK (direct value, device " .. ICS_DEVICE .. ")")
		else
			if attemptsLeft > 1 then
				log.write("EMIS_LMT_MOD", log.INFO, label .. ": did not confirm - trying again")
				setIcsTarget(targetValue, label, attemptsLeft - 1)
			else
				log.write("EMIS_LMT_MOD", log.ERROR, label .. ": out of attempts (value=" .. tostring(actual) .. ")")
			end
		end
	end)
end

local function pressButton(pbNumber)
	local cmd = BUTTON_CMD[pbNumber]
	if cmd == nil then return false end
	return sendCommand(MPCDR_DEVICE_INDEX, cmd, 1.0)
end

local function releaseButton(pbNumber)
	local cmd = BUTTON_CMD[pbNumber]
	if cmd == nil then return false end
	return sendCommand(MPCDR_DEVICE_INDEX, cmd, 0.0)
end

-- Returns one of the known page names (ADI/ARMT/HSI/TF/TSD/TPOD/TEWS),
-- "MENU" (specifically M1), "UNKNOWN" (found the MPCD tag but the page
-- doesn't match anything known - probably M2/M3), or "NOREAD" (the
-- MPCD tag wasn't found anywhere - nobody in the WSO seat to render it).
local function identifyCurrentPage()
	for i = 0, 40 do
		local okCall, content = pcall(list_indication, i)
		if okCall and content ~= nil and content ~= "" and content:find(MPCD_SELF_TAG, 1, true) then
			for _, page in ipairs(PAGE_FINGERPRINTS) do
				if content:find(page.marker, 1, true) then
					return page.name
				end
			end
			if content:find("ADI", 1, true) and content:find("ARMT", 1, true) then
				return "MENU"
			end
			return "UNKNOWN"
		end
	end
	return "NOREAD"
end

-- Chained click: presses NOW, releases after HOLD_TIME, and only then
-- (after GAP_AFTER) calls onDone. Each step only queues the next one
-- once the previous one finishes - avoids a queue-ordering bug.
local function chainClick(pbNumber, onDone)
	log.write("EMIS_LMT_MOD", log.INFO, "Clicking PB" .. string.format("%02d", pbNumber) .. " (hold)")
	pressButton(pbNumber)
	queuePush(HOLD_TIME, function()
		releaseButton(pbNumber)
		queuePush(GAP_AFTER, function()
			if onDone then onDone() end
		end)
	end)
end

-- Navigates to the TF page and presses the final button (targetPb:
-- PB_TF_LPI or PB_TF_NORM). Works from any page.
local function goToTfAndPress(targetPb, attemptsLeft)
	attemptsLeft = attemptsLeft or 3
	local current = identifyCurrentPage()
	log.write("EMIS_LMT_MOD", log.INFO, "goToTfAndPress: current page = " .. tostring(current))

	if current == "TF" then
		chainClick(targetPb, function()
			log.write("EMIS_LMT_MOD", log.INFO, "Done: PB" .. targetPb .. " sent directly on TF")
		end)
		return
	end

	if current == "MENU" then
		chainClick(PB_TF, function()
			chainClick(targetPb, function()
				log.write("EMIS_LMT_MOD", log.INFO, "Done: M1 -> TF -> PB" .. targetPb)
			end)
		end)
		return
	end

	if current == "NOREAD" then
		-- Nobody in the WSO seat to confirm - blind, single attempt,
		-- assuming the most common case (a function page, not M2/M3).
		chainClick(PB_MENU_RETURN, function()
			chainClick(PB_TF, function()
				chainClick(targetPb, function()
					log.write("EMIS_LMT_MOD", log.INFO, "Done (blind): PB11 -> PB4 -> PB" .. targetPb)
				end)
			end)
		end)
		return
	end

	-- current == "UNKNOWN": found the MPCD tag but the page doesn't
	-- match anything known (probably M2 or M3). We can verify and
	-- retry if needed.
	if attemptsLeft <= 0 then
		log.write("EMIS_LMT_MOD", log.ERROR, "goToTfAndPress: out of attempts, giving up")
		return
	end

	chainClick(PB_MENU_RETURN, function()
		local newState = identifyCurrentPage()
		log.write("EMIS_LMT_MOD", log.INFO, "After PB11: " .. tostring(newState))
		if newState == "MENU" then
			chainClick(PB_TF, function()
				chainClick(targetPb, function()
					log.write("EMIS_LMT_MOD", log.INFO, "Done: X -> M1 -> TF -> PB" .. targetPb)
				end)
			end)
		elseif newState == "TF" then
			chainClick(targetPb, function()
				log.write("EMIS_LMT_MOD", log.INFO, "Done: X -> TF directly -> PB" .. targetPb)
			end)
		else
			-- still not there (M2/M3 or a momentary NOREAD) - try again
			goToTfAndPress(targetPb, attemptsLeft - 1)
		end
	end)
end

local function activateEmisLmt(d0)
	EMIS.savedRadarArg = d0:get_argument_value(471)
	EMIS.savedJtidsArg = d0:get_argument_value(476)
	EMIS.savedIcsArg   = d0:get_argument_value(ICS_ARG)

	queueClear()
	queuePush(0.0, function() sendCommandVerified(3, RADAR_CMD, 471, RADAR_STBY, "Radar->STBY") end)
	queuePush(0.15, function() sendCommandVerified(1, JTIDS_CMD, 476, JTIDS_OFF, "JTIDS->OFF") end)
	queuePush(0.15, function() setIcsTarget(ICS_OFF_VALUE, "ICS->OFF") end)

	queuePush(0.3, function()
		EMIS.tfLpiOn = true
		goToTfAndPress(PB_TF_LPI, 3)
	end)

	log.write("EMIS_LMT_MOD", log.INFO, string.format(
		"EMIS LMT ACTIVATED. Radar was %s, JTIDS was %s, ICS was %s",
		tostring(EMIS.savedRadarArg), tostring(EMIS.savedJtidsArg), tostring(EMIS.savedIcsArg)))
end

local function deactivateEmisLmt(d0)
	queueClear()

	if EMIS.savedRadarArg ~= nil then
		local radarValue = EMIS.savedRadarArg
		queuePush(0.0, function() sendCommandVerified(3, RADAR_CMD, 471, radarValue, "Radar->restore") end)
	end
	if EMIS.savedJtidsArg ~= nil then
		local jtidsValue = EMIS.savedJtidsArg
		queuePush(0.15, function() sendCommandVerified(1, JTIDS_CMD, 476, jtidsValue, "JTIDS->restore") end)
	end
	if EMIS.savedIcsArg ~= nil then
		local icsValue = EMIS.savedIcsArg
		queuePush(0.15, function() setIcsTarget(icsValue, "ICS->restore") end)
	end

	queuePush(0.3, function()
		EMIS.tfLpiOn = false
		goToTfAndPress(PB_TF_NORM, 3)
	end)

	log.write("EMIS_LMT_MOD", log.INFO, "EMIS LMT DEACTIVATED. Restoring systems.")

	EMIS.savedRadarArg = nil
	EMIS.savedJtidsArg = nil
	EMIS.savedIcsArg = nil
end

local function emisTick(t)
	local d0 = GetDevice(0)
	if d0 == nil then return end

	local v287 = d0:get_argument_value(287)
	local v1312 = d0:get_argument_value(1312)
	if v287 == nil and v1312 == nil then return end
	v287 = v287 or 0
	v1312 = v1312 or 0

	local clickedFront = (v287 > 0.5 and EMIS.prevArg287 <= 0.5)
	local clickedRear  = (v1312 > 0.5 and EMIS.prevArg1312 <= 0.5)

	EMIS.prevArg287 = v287
	EMIS.prevArg1312 = v1312

	-- Both buttons trigger the same logic directly (no relay).
	-- Radar and JTIDS do not change when triggered from the WSO seat
	-- (a crew-synchronization restriction in the engine, already
	-- documented above) - but TF/LPI and ICS work normally from either
	-- seat.
	if clickedFront or clickedRear then
		if EMIS.lastToggleTime ~= nil and (t - EMIS.lastToggleTime) < TOGGLE_COOLDOWN then
			log.write("EMIS_LMT_MOD", log.INFO, "Click ignored (anti-chatter cooldown active)")
			queueProcess(t)
			return
		end
		EMIS.lastToggleTime = t

		EMIS.active = not EMIS.active
		local who = clickedFront and "PTN_287 (pilot)" or "PTN_1312 (WSO)"
		if EMIS.active then
			log.write("EMIS_LMT_MOD", log.INFO, "EMIS LMT ACTIVATED by " .. who)
			activateEmisLmt(d0)
		else
			log.write("EMIS_LMT_MOD", log.INFO, "EMIS LMT DEACTIVATED by " .. who)
			deactivateEmisLmt(d0)
		end
	end

	queueProcess(t)
end

function LuaExportActivityNextEvent(t)
	local tNext = t + 0.05

	local ok, err = pcall(emisTick, t)
	if not ok then
		log.write("EMIS_LMT_MOD", log.ERROR, "emisTick error: " .. tostring(err))
	end

	if PrevExportActivity then
		pcall(PrevExportActivity, t)
	end

	return tNext
end
