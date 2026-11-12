-- ============================================================
-- F15E_Auto_Jammer.lua
-- VERSION: v1.17 (EN)
-- ============================================================
-- CHANGELOG:
--   v1.0 - Base jammer: 3 sets (Offensive/Spot-on/Defensive), range
--          70% of the EA-18G, tier-based priority table, packaged
--          as a mod (Hook auto-load + DO SCRIPT FILE fallback).
--   v1.1 - Added 6 ON/OFF status messages (Offensive, Spot-on with
--          the threat name, Defensive) for beta testing.
--   v1.2 - Added an F10 > Other menu to toggle the status messages
--          on/off (proved unreliable in testing).
--   v1.3 - F10 menu removed; replaced by the manual
--          STATUS_MESSAGES_MODE ("ON"/"OFF") flag at the top of the
--          file.
--   v1.4 - Range reduced from 70% to 60% of the EA-18G, to reflect
--          the difference in electrical power budget dedicated to
--          EW between the two aircraft (see the comment on
--          F15_RANGE_SCALE, below). Effectiveness (success chance
--          of each set) remains at the original values.
--   v1.5 - Added an AIR domain (air threats - fighters/bombers) to
--          Sets 1 and 2, with ABSOLUTE priority over the SAM domain
--          (ground + naval, unified). Added naval SAM systems
--          (Kirov, Slava, Neustrashimy, Krivak, Grisha, Tarantul,
--          Project 22160/TorM2KM) and new ground types (1L13 EWR,
--          SON_9) to the priority table, extracted from a real test
--          mission (.miz) without needing to fly it. Suppression on
--          aircraft uses AI.Option.Air (analogous to the
--          AI.Option.Ground already used for SAMs).
--   v1.6 - Added the Chinese HQ-7 (mobile SHORAD, 3 units: LN_SP,
--          STR_SP, LN_P) and ZSU-23-4 Shilka (radar-guided AAA) to
--          the priority table, tier 1 - same short-range/older-
--          generation point-defense category as
--          CHAP_PantsirS1/2S6 Tunguska.
--   v1.7 - Added a priority table for BLUE units (Patriot, NASAMS,
--          Hawk, various EWRs, Ticonderoga, Arleigh Burke, Perry,
--          Western fighters across several generations), extracted
--          from a real test mission. CONFIRMED (no code change
--          needed): Sets 1 and 2 already only attack the coalition
--          OPPOSITE the player's, via enemySide()/scanEmitters()/
--          scanAirThreats() - if the F-15E is NEUTRAL, enemySide()
--          returns nil and both scans come back empty, so Sets 1/2
--          attack no one. Set 3 (defensive) already was, and remains,
--          coalition-agnostic - it only protects the player from any
--          missile that has them as its target, regardless of who
--          fired it.
--   v1.8 - Added thermal management (0-100% heat system, analogous to
--          the EA-18G/_Timberwolf_'s MRAD, adapted for the F-15E's
--          FIXED internal system). Each set contributes a different
--          heating rate when active (Set 1 slow - lasts ~33min
--          continuous, like DCS's native jammers; Set 2 moderate -
--          ~6-7min; Set 3 fast - ~2min, "full throttle" against a
--          direct threat). At 80% heat it enters automatic LOW POWER
--          (effectiveness drops: hold -30%, target resistance +0.15,
--          range -15%). At 100%, the ENTIRE system locks out for 90s
--          (faithful to the original EA-18G - confirmed with the user
--          that Set 3 also stops in this scenario, not exempt).
--          Cools at -0.60%/s when no set is active.
--   v1.9 - Added control via physical cockpit switches (TEWS panel,
--          Right Console): ICS ON/OFF (master) + SET 1/2/3 MAN/AUTO.
--          Each set only operates automatically when its switch is in
--          AUTO and the master is ON; in MAN/OFF the corresponding set
--          is fully stopped (no heat cost, no suppression at all).
--          Reads the state via F15E_Jammer_Switches_Export.lua
--          (Export.lua, uses GetDevice(0):get_argument_value() -
--          confirmed as the correct method after diagnostic testing,
--          since named devices like EWS_JMR aren't externally
--          accessible that way). If the state file doesn't exist
--          (Export not installed), defaults to everything on -
--          identical to previous versions' behavior, so it doesn't
--          break anyone who hasn't set up the switches yet.
--   v1.10 - Added manual triggering of MAN sets via the stick's CMD
--          (chaff/flare) button, for both pilot and WSO. Detected via
--          LoGetSnares() (Export.lua) - any drop in the remaining
--          chaff OR flare count counts as an actuation (doesn't tell
--          seats apart, since the count is shared aircraft-wide). No
--          change in AUTO. In MAN, the corresponding set only
--          activates when CMD is pressed: Set 1 and Set 3 stay active
--          for a fixed 60s; Set 2 stays armed for as long as
--          runSpotOn() keeps finding a valid target (duration = "for
--          as long as the lock lasts", no fixed timer) - once the
--          target is gone, it disarms and needs a fresh CMD press to
--          re-engage. Status messages append "(MANUAL)" when the
--          trigger came from CMD, to tell it apart from AUTO during
--          testing.
--   v1.11 - Fixed an edge case in manual triggering
--          (F15E_Jammer_Switches_Export.lua only, no change to the
--          main file): if chaff AND flare both reach ZERO, "count
--          drop" detection goes blind (there's nothing left to drop).
--          In that case, sets in MAN become continuously available,
--          just like AUTO, for as long as that condition lasts - the
--          crew has no other way to signal us, and blocking their
--          self-defense would be worse than defaulting to available.
--          Returns to normal behavior (requires CMD) as soon as
--          chaff or flare is rearmed/restocked.
--   v1.12 - Fixed a critical bug: SWITCH_STATE_FILE called
--          lfs.writedir() directly, unprotected, at script startup.
--          If 'lfs' is sanitized (not unsanitized in
--          MissionScripting.lua, or reset by a DCS update), this
--          broke the ENTIRE script with "attempt to index global
--          'lfs' (a nil value)" before the jammer even started
--          running. Now wrapped in pcall - if lfs isn't available,
--          SWITCH_STATE_FILE stays nil and only cockpit-switch
--          reading gets disabled (the jammer keeps working normally,
--          fully automatic, as before v1.9).
--   v1.13 - Diagnostics: added an unconditional log (doesn't depend
--          on DEBUG_MESSAGES) whenever S.swMaster changes value, to
--          investigate a report that turning off the ICS switch
--          doesn't stop the jammer (it keeps running until the
--          thermal limit). The gate logic in jamCycle looks correct
--          on code review - this log will confirm whether the value
--          read from the switch matches what the pilot actually did,
--          before changing anything else.
--   v1.14 - Fixed a real bug in F15E_Jammer_Switches_Export.lua (no
--          change in this file): the v1.11 "chaff/flare depleted"
--          fallback didn't distinguish "ran out during the flight"
--          from "the aircraft never had chaff/flare from the start"
--          - in that second case, the fallback stayed permanently
--          active from second one, even with zero real actuations.
--          Now requires at least ONE reading with chaff/flare > 0
--          before allowing the fallback. Also added an unconditional
--          log in Export.lua itself whenever the raw ICS ON/OFF
--          value changes - a second diagnostic point, independent of
--          the log already in this mission script, to investigate a
--          report that turning off the ICS master doesn't stop the
--          jammer (it wasn't the chaff/flare bug - user confirmed a
--          loaded loadout and the specific master switch).
--   v1.15 - Additional diagnostics: testing confirmed the Export.lua
--          log ("ICS master raw changed") fires correctly
--          (1.000 -> 0.000 -> 1.000), but the corresponding log in
--          the mission script NEVER fired - meaning the problem is
--          between the file write and the mission-side read, not in
--          reading the switch itself. Added: (1) a log of the
--          resolved SWITCH_STATE_FILE path in both scripts (to rule
--          out both sides pointing at different files, e.g. separate
--          DCS/DCS.openbeta installs); (2) a periodic log (1x/s) of
--          the raw content the mission script reads from the file,
--          even when the read fails or the pattern doesn't match -
--          to directly compare against Export.lua's write logs and
--          find where the information gets lost.
--   v1.16 - CONFIRMED AND RESOLVED: root cause was
--          MissionScripting.lua (game install folder) sanitizing
--          'io'/'lfs' again in the MISSION environment (likely reset
--          by a DCS update). Export.lua was never affected (runs
--          unsandboxed, always had io/lfs) - only the mission script
--          was. User confirmed reopening MissionScripting.lua and
--          re-commenting the lines - the log showed
--          SWITCH_STATE_FILE stopping being nil and the ICS master
--          syncing perfectly (<1s latency) across 6 consecutive
--          toggles. Removed the verbose "read from file" log (1x/s,
--          only used for this diagnostic) - kept just the
--          state-change log, much lighter for long sessions.
--   v1.17 - Fixed a real bug in F15E_Jammer_Switches_Export.lua (no
--          change in this file): the 0/1 convention for the SET
--          1/2/3 MAN/AUTO switches was inverted - physically, DOWN
--          is AUTO and UP is MAN (confirmed via a real cockpit
--          photo), but the code assumed the opposite (based on the
--          "MAN/AUTO" name order). This caused two reported
--          symptoms, both from the SAME cause: (1) the "(MANUAL)"
--          message appearing with the switch in AUTO; (2) CMD
--          manually triggering the jammer even with the switch in
--          AUTO, when it should be fully independent of chaff/flare
--          in that case. Fixed by inverting the raw-to-bit
--          translation written to the state file (toBitAutoDown()) -
--          the mission script keeps interpreting "1 = AUTO"
--          normally, with no need to know about the physical
--          inversion.
-- ============================================================

-- ============================================================
-- Automatic/seamless radar jammer for the F-15ESE (S4+).
-- Based on the technique used by "Growler_AEA_with_MRAD.lua" (by
-- _Timberwolf_), adapted for fully automatic operation (no F10 menu,
-- no manual toggle) with 3 simultaneous "sets" (programs):
--
--   SET 1 - OFFENSIVE : suppresses enemy SEARCH radars (SAM SR) and
--                        ALL enemy aircraft within range,
--                        prioritizing ones that haven't locked onto
--                        anyone yet.
--   SET 2 - SPOT-ON    : focuses on the SINGLE highest-priority
--                        threat at the moment (see the priority
--                        formula below), with stronger and more
--                        frequent suppression than Set 1.
--                        DOMAIN PRIORITY: any AIR threat within range
--                        automatically beats any SAM, ground or
--                        naval, regardless of tier/distance - only
--                        when no enemy aircraft is within range does
--                        the tier/distance formula decide between
--                        SAMs.
--   SET 3 - DEFENSIVE  : probabilistic disruption of radar-guided
--                        missiles fired at the player (already covers
--                        launches from both SAMs AND aircraft, no
--                        distinction needed - DCS's shot event is the
--                        same for both).
--
-- THERMAL MANAGEMENT (cuts across all 3 sets): a single 0-100% heat
-- accumulator, fed by whichever set is active (different rates - Set
-- 1 very slow, Set 2 moderate, Set 3 fast). At 80% it enters LOW
-- POWER (effectiveness drops); at 100% the ENTIRE system locks out
-- for 90s, Set 3 included - see HEAT_RATE_* below.
--
-- API LIMITATION (DCS Mission Scripting Environment): the game does
-- not expose "this specific radar/aircraft is locked onto this
-- specific aircraft". Because of that, just like the original
-- Growler script, we use the presence of the SAM SR attribute as
-- "searching" and SAM TR/STR as "likely locking" as a proxy for the
-- SAM domain; for the AIR domain, since aircraft have no such
-- attribute distinction, any enemy aircraft within range is treated
-- as eligible in both sets. The jamming effect itself is applied via
-- a temporary ROE = WEAPON_HOLD on the target's AI controller
-- (AI.Option.Ground for SAMs, AI.Option.Air for aircraft - the same
-- standard "soft-kill" technique used in DCS mission scripts), with a
-- resistance (ECCM) chance based on the threat's danger tier.
--
-- PRIORITY FORMULA (Set 2 - Spot-on, WITHIN each domain):
--   score = tierWeight[tier] / max(rangeNm, 1)
-- This makes distance dominate the outcome when the range difference
-- is large (a much closer SA-6 beats a farther SA-21, as specified),
-- while tier still breaks ties between threats at similar distances.
-- The tier weights (TIER_WEIGHT) are adjustable below.
-- ============================================================

-- ============================================================
-- CONFIG
-- ============================================================

local ELIGIBLE_TYPES = {["F-15ESE"] = true}

local JAM_TICK_SEC          = 2.0   -- main jamming cycle interval
local PLAYER_CHECK_SEC      = 2.0   -- player check interval
local SCAN_EVERY_N_TICKS    = 2     -- full scan every N ticks (reduces cost)
local MAX_EMITTERS_CONSIDERED = 180

-- ============================================================
-- OPERATING RANGE
-- ============================================================
-- 60% of the effective range of the original EA-18G script
-- (_Timberwolf_), which already applies its own internal 0.7
-- multiplier on top of a 70 NM base. This 60% factor is ADDITIONAL,
-- applied on top of that.
--
-- Rationale (electrical power budget available for EW):
--   EA-18G: 130 kVA of internal AIRCRAFT generation + 82 kW per
--   ALQ-99 pod (2 pods = additional generation DEDICATED exclusively
--   to jamming, added on top of the internal supply).
--   F-15E: 150 kVA of TOTAL internal generation, but no dedicated
--   extra generation for EW - that power is shared with the radar,
--   avionics, and the aircraft's other systems.
-- In other words, even though the F-15E has more total generation,
-- the EA-18G has far more power AVAILABLE specifically for jamming
-- (shared internal + dedicated pod generation). The 60% factor
-- emulates that difference in power budget available for EW.
local F15_RANGE_SCALE = 0.60
local EA18G_BASE_NM   = 70   -- same tuned base as the original script
local EA18G_RANGE_MUL = 0.7  -- EA-18G's internal multiplier

-- Defensive (missile disruption)
local MISSILE_DISRUPT_RANGE_NM   = 10
local MISSILE_DISRUPT_CHANCE     = 0.50
local MISSILE_DISRUPT_DELAY_MAX  = 5.0

-- ============================================================
-- THERMAL MANAGEMENT (heat system analogous to the EA-18G/
-- _Timberwolf_'s MRAD, adapted for the F-15E's FIXED internal system -
-- no pod selection like the Growler). Single 0-100% accumulator, fed
-- by whichever of the 3 sets is active, with two response tiers just
-- like the original in spirit:
--   80%  -> automatic LOW POWER (effectiveness drops, stays active)
--   100% -> OVERHEAT (the ENTIRE system locks out for
--           HEAT_LOCKOUT_SEC, faithful to the original EA-18G - Set 3
--           also stops, a choice explicitly confirmed with the user)
-- ============================================================

-- Heating rate (%/second) PER ACTIVE SET. Small values = lasts a
-- long time (Set 1, like DCS's native jammers today); large values =
-- heats up fast (Set 3, "full throttle" against a direct threat).
-- Contributions ADD UP if more than one set is active at once.
local HEAT_RATE_OFFENSIVE = 0.05   -- Set 1: ~33 min continuous to 100%
local HEAT_RATE_SPOTON    = 0.25   -- Set 2: ~6-7 min continuous
local HEAT_RATE_DEFENSIVE = 0.80   -- Set 3: ~2 min continuous

local HEAT_COOL_RATE = 0.60  -- cooling (%/s) when no set is active

local HEAT_LOW_POWER_THRESHOLD    = 80  -- % - enters Low Power
local HEAT_LOW_POWER_HYSTERESIS   = 5   -- % - must drop to 75% to exit Low Power (avoids flapping)
local HEAT_OVERHEAT_THRESHOLD     = 100 -- % - locks everything out
local HEAT_LOCKOUT_SEC            = 90  -- seconds of total lockout after overheating

-- Modifiers applied under LOW POWER (same philosophy as the
-- Growler's powerMods()): reduces suppression strength/duration,
-- increases the target's resistance chance, reduces range.
local LOW_POWER_HOLD_MUL   = 0.70
local LOW_POWER_RESIST_ADD = 0.15
local LOW_POWER_RANGE_MUL  = 0.85

-- ============================================================
-- COCKPIT SWITCHES (TEWS panel - Right Console)
-- ============================================================
-- Reads the state file written by F15E_Jammer_Switches_Export.lua
-- (runs in the Export.lua environment - the only place a cockpit
-- argument value can be read externally, see GetDevice(0) in that
-- file). Format: one line "M,1,2,3,C" with 0/1 for each switch and
-- C = a CMD actuation counter:
--   M = ICS ON/OFF (master - if OFF, all 3 sets shut down together)
--   1 = ICS SET 1 MAN/AUTO (Offensive only runs in AUTO)
--   2 = ICS SET 2 MAN/AUTO (Spot-on only runs in AUTO)
--   3 = ICS SET 3 MAN/AUTO (Defensive only runs in AUTO)
--   C = monotonic integer counter of CMD (chaff/flare) button
--       actuations, detected via LoGetSnares() - any set in MAN can
--       be manually triggered by pressing CMD (up or down, pilot or
--       WSO - the count is shared aircraft-wide, doesn't tell them
--       apart).
--
-- If the file doesn't exist (testers who haven't installed the
-- matching Export.lua yet), the jammer defaults to everything ON -
-- identical to previous versions' behavior, so it doesn't break
-- anyone who hasn't set up the switches yet.
--
-- IMPORTANT: lfs may be sanitized (not unsanitized in
-- MissionScripting.lua, or reset by a DCS update) - in that case,
-- SWITCH_STATE_FILE stays nil and updateSwitchState() just bails out
-- immediately, without breaking the rest of the jammer (which doesn't
-- depend on io/lfs anywhere else).
local SWITCH_STATE_FILE = nil
do
    local ok, path = pcall(function()
        return lfs.writedir() .. "Scripts/F15E_Jammer_Switches_state.txt"
    end)
    if ok then SWITCH_STATE_FILE = path end
    pcall(function()
        env.info("F15E_JAMMER: SWITCH_STATE_FILE resolved to " .. tostring(SWITCH_STATE_FILE))
    end)
end
local SWITCH_POLL_SEC = 1.0

-- Duration of the manual trigger (MAN + CMD) for Sets 1 and 3, in
-- seconds. Set 2 has no fixed duration - it stays armed for as long
-- as runSpotOn() keeps finding a valid target (see jamCycle).
local MANUAL_TRIGGER_DURATION_SEC = 60

-- Debug messages (NOT shown to the player by default - seamless)
local DEBUG_MESSAGES = false
local DEBUG_TO_UNIT  = false  -- if true, sends debug text to the player (testing use)

-- ============================================================
-- STATUS MESSAGES (BETA TEST) - MANUAL CONTROL
-- ============================================================
-- Change "ON" to "OFF" on the line below to disable the 6 status
-- messages (Offensive/Spot/Defensive ON and OFF) on the player's
-- screen. You need to save the file and reload the mission (or
-- restart DCS) for the change to take effect.
--
-- Default during the test phase: "ON"
--
local STATUS_MESSAGES_MODE = "ON"  -- "ON" or "OFF"
-- ============================================================

local STATUS_MESSAGES_ENABLED = (tostring(STATUS_MESSAGES_MODE):upper() == "ON")
local STATUS_MSG_DURATION_SEC = 6

-- ============================================================
-- PRIORITY TABLE (exact typeName -> danger tier)
-- Built from real data captured via F15E_EW_Diagnostic_FileLog.lua
-- and debrief.log (DCS's real unit naming, which does NOT follow a
-- single consistent pattern - hence exact-match, not regex).
--
-- Tier 4 = most modern/dangerous (S-400, S-300V4, S-300VM)
-- Tier 3 = S-300PMU1/PMU2
-- Tier 2 = S-300PS, S-300V, SA-11 Buk
-- Tier 1 = S-200, Kub, S-75, S-125 (legacy)
-- EXCLUDED = decoys / non-threats (never jammed, never prioritized)
-- ============================================================

local TIER_WEIGHT = {[1]=1.0, [2]=1.4, [3]=1.9, [4]=2.5}
local DEFAULT_TIER = 1  -- unknown typeName falls back here (assumed a threat, not ignored)

local PRIORITY_TIER = {
    -- ---- Tier 4: S-400 ----
    ["S-400 51P6A (40N6E) ln"]   = 4,
    ["S-400 51P6A (9M96E2) ln"]  = 4,
    ["S-400 51P6A ln"]           = 4,
    ["S-400 55K6 cp"]            = 4,
    ["S-400 91N6E sr"]           = 4,
    ["S-400 92N6E mast tr"]      = 4,
    ["S-400 92N6E tr"]           = 4,
    ["S-400 96L6E mast sr"]      = 4,
    ["S-400 96L6E sr"]           = 4,

    -- ---- Tier 4: S-300V4 / S-300VM ----
    ["S-300V4 9A82M-2E ln"]      = 4,
    ["S-300V4 9A83M-2E ln"]      = 4,
    ["S-300V4 9A84M-2E ln"]      = 4,
    ["S-300V4 9S15MDE sr"]       = 4,
    ["S-300V4 9S19M-1E sr"]      = 4,
    ["S-300V4 9S32M-1E tr"]      = 4,
    ["S-300V4 9S457-2E cp"]      = 4,
    ["S-300VM 9A82ME ln"]        = 4,
    ["S-300VM 9A83ME ln"]        = 4,
    ["S-300VM 9S15M2 sr"]        = 4,
    ["S-300VM 9S19M2 sr"]        = 4,
    ["S-300VM 9S32ME tr"]        = 4,
    ["S-300VM 9S457ME cp"]       = 4,

    -- ---- Tier 3: S-300PMU1 / PMU2 ----
    ["S-300PMU2 40B6M tr"]       = 3,
    ["S-300PMU2 54K6E2 cp"]      = 3,
    ["S-300PMU2 5P85SE2 ln"]     = 3,
    ["S-300PMU2 64H6E2 sr"]      = 3,
    ["S-300PMU2 92H6E tr"]       = 3,
    ["S-300PMU1 30N6E tr"]       = 3,
    ["S-300PMU1 40B6M tr"]       = 3,
    ["S-300PMU1 40B6MD sr"]      = 3,
    ["S-300PMU1 54K6 cp"]        = 3,
    ["S-300PMU1 5P85CE ln"]      = 3,
    ["S-300PMU1 5P85DE ln"]      = 3,
    ["S-300PMU1 64N6E sr"]       = 3,

    -- ---- Tier 2: S-300PS / S-300V (legacy) / SA-11 Buk ----
    ["S-300PS 30N6 TRAILER tr"]      = 2,
    ["S-300PS 40B6M tr"]             = 2,
    ["S-300PS 40B6MD sr"]            = 2,
    ["S-300PS 54K6 cp"]              = 2,
    ["S-300PS 5P85C ln"]             = 2,
    ["S-300PS 5P85D ln"]             = 2,
    ["S-300PS 5P85DE ln"]            = 2,
    ["S-300PS 5P85_1_mod ln"]        = 2,
    ["S-300PS 64H6E MOD sr"]         = 2,
    ["S-300PS 64H6E sr"]             = 2,
    ["S-300PS SA-10B 30N6 MAST tr"]  = 2,
    ["S-300PS SA-10B 54K6 cp"]       = 2,
    ["S-300PS SA-10B 76N6E sr"]      = 2,
    ["S-300V 9A82 ln"]               = 2,
    ["S-300V 9A83 ln"]               = 2,
    ["S-300V 9S15 sr"]               = 2,
    ["S-300V 9S19 sr"]               = 2,
    ["S-300V 9S32 tr"]               = 2,
    ["S-300V 9S457 cp"]              = 2,
    ["SA-11 Buk CC 9S470M1"]         = 2,
    ["SA-11 Buk LN 9A310M1"]         = 2,
    ["SA-11 Buk SR 9S18M1"]          = 2,

    -- ---- Tier 1: legacy (S-200, Kub, S-75, S-125) and short range ----
    ["RLS_19J6"]           = 1,  -- S-200 "Tin Shield" SR
    ["RPC_5N62V"]          = 1,  -- S-200 "Square Pair" TR
    ["Kub 1S91 str"]       = 1,
    ["Kub 2P25 ln"]        = 1,
    ["SNR_75V"]            = 1,  -- S-75 "Fan Song" TR
    ["S_75M_Volhov"]       = 1,
    ["p-19 s-125 sr"]      = 1,
    ["CHAP_PantsirS1"]     = 1,  -- short-range point defense
    ["2S6 Tunguska"]       = 1,
    ["ZSU-23-4 Shilka"]    = 1,  -- radar-guided AAA (Gun Dish), very short range, older generation

    -- ---- Tier 1: Chinese HQ-7 (mobile SHORAD, based on the French Crotale) ----
    ["HQ-7_LN_SP"]  = 1,  -- self-propelled launcher
    ["HQ-7_STR_SP"] = 1,  -- self-propelled search/track radar
    ["HQ-7_LN_P"]   = 1,  -- towed launcher

    -- ---- EXCLUDED: not real threats, never targeted ----
    ["34Ya6E Gazetchik E decoy"] = -1,
    ["SA-14 Strela-3 manpad"]    = -1,  -- MANPAD: out of scope for this jammer

    -- ---- Additional ground units (extracted from a real test mission) ----
    ["1L13 EWR"] = 1,  -- early warning radar, no fire-control capability
    ["SON_9"]    = 1,  -- fire-control radar (paired with KS-19), legacy

    -- ================================================================
    -- SAM DOMAIN - NAVAL (shipborne systems, same SAM SR/TR/STR
    -- attributes as ground systems - handled in the SAME list)
    -- ================================================================
    ["PIOTR"]                        = 4,  -- Kirov-class, S-300F/FM Fort
    ["MOSCOW"]                       = 4,  -- Slava-class, S-300F Fort
    ["NEUSTRASH"]                    = 3,  -- Neustrashimy-class, Kinzhal/Shtil
    ["REZKY"]                        = 2,  -- Krivak-class, SA-N-4 Osa-M
    ["ALBATROS"]                     = 2,  -- Krivak/Grisha-class, SA-N-4
    ["CHAP_Project22160_TorM2KM"]    = 2,  -- Tor-M2KM module (comparable to Pantsir/Tunguska)
    ["MOLNIYA"]                      = 1,  -- Tarantul-class, minimal air defense
    ["CHAP_Project22160"]            = 1,  -- base version, no relevant SAM module
    ["BDK-775"]                      = 1,  -- Ropucha-class (landing ship), no relevant SAM

    -- ================================================================
    -- AIR DOMAIN - air threats (extracted from a real test mission)
    -- Tier here reflects the air-to-air/BVR danger to the F-15E, not
    -- ground-radar sophistication like the SAM domain.
    -- ================================================================
    -- Tier 4: 4+ gen/long-range interceptor, most dangerous radar/BVR
    ["MiG-31"] = 4,  -- Zaslon radar, long-range BVR interceptor
    ["Su-30"]  = 4,  -- advanced multirole

    -- Tier 3: 4th generation (air superiority/multirole fighter)
    ["MiG-29 Fulcrum"] = 3,
    ["MiG-29S"]        = 3,
    ["Su-27"]          = 3,
    ["Su-33"]          = 3,

    -- Tier 2: advanced 3rd generation
    ["MiG-23MLD"] = 2,
    ["MiG-25PD"]  = 2,

    -- Tier 1: older 1st-3rd generation, no relevant BVR capability
    ["MiG-15bis"]    = 1,
    ["MiG-15bis_FC"] = 1,
    ["MiG-19P"]      = 1,
    ["MiG-21Bis"]    = 1,

    -- Tier 1: bombers/AWACS - not fighters, low direct air-to-air threat
    ["Tu-142"]  = 1,
    ["Tu-160"]  = 1,
    ["Tu-22M3"] = 1,
    ["Tu-95MS"] = 1,
    ["A-50"]    = 1,

    -- ================================================================
    -- SAM DOMAIN - BLUE (ground and naval, extracted from a real test
    -- mission). Same single table - coalition filtering is already
    -- done in enemySide()/scanEmitters()/scanAirThreats(), so the tier
    -- here applies regardless of which side operates the system.
    -- ================================================================
    ["Patriot str"] = 4,
    ["Patriot EPP"] = 4,
    ["Patriot ECS"] = 4,
    ["Patriot AMG"] = 4,
    ["Patriot cp"]  = 4,
    ["Patriot ln"]  = 4,

    ["NASAMS_Command_Post"]    = 3,
    ["NASAMS_LN_B"]            = 3,
    ["NASAMS_LN_C"]            = 3,
    ["NASAMS_Radar_MPQ64F1"]   = 3,

    ["Hawk pcp"]  = 2,
    ["Hawk sr"]   = 2,
    ["Hawk cwar"] = 2,
    ["Hawk tr"]   = 2,
    ["Hawk ln"]   = 2,

    ["EWR 1L119 Nebo-SVU"]       = 1,  -- early warning radar, no fire-control
    ["EWR 55G6U NEBO-U"]         = 1,
    ["EWR P-37 BAR LOCK"]        = 1,
    ["EWR Generic radar tower"]  = 1,
    ["FPS-117"]                  = 1,
    ["HEMTT_C-RAM_Phalanx"]      = 1,  -- very short range point defense, radar-guided
    ["Vulcan"]                   = 1,  -- M163, radar-guided short-range AAA

    ["M1097 Avenger"] = -1,  -- Stinger is infrared-guided, out of scope (like the SA-14)

    ["TICONDEROG"]           = 4,  -- Aegis + SM-2/6
    ["USS_Arleigh_Burke_IIa"]= 4,  -- Aegis + SM-2/6
    ["PERRY"]                = 2,  -- Mk13/SM-1, older

    -- ================================================================
    -- AIR DOMAIN - BLUE (extracted from a real test mission)
    -- ================================================================
    ["F-14A-135-GR-Early"] = 4,  -- AWG-9/Phoenix, very long-range BVR

    ["F-16C_50"]       = 3,
    ["F-16C bl.52d"]   = 3,
    ["F-15ESE"]        = 3,
    ["F-15C"]          = 3,
    ["F/A-18C"]        = 3,
    ["FA-18C_hornet"]  = 3,

    ["F-4E-45MC"]      = 2,
    ["Mirage-F1B"]     = 2,
    ["Mirage-F1BE"]    = 2,
    ["Mirage-F1CE"]    = 2,
    ["Mirage-F1CR"]    = 2,
    ["Mirage-F1EE"]    = 2,
    ["Mirage-F1M-CE"]  = 2,
    ["Mirage-F1M-EE"]  = 2,
    ["AJS37"]          = 2,
    ["F-16A MLU"]      = 2,
    ["F-16A"]          = 2,
    ["F-16C bl.50"]    = 3,

    ["F-5E"]         = 1,
    ["F-5E-3_FC"]    = 1,
    ["F-86F Sabre"]  = 1,
    ["F-86F_FC"]     = 1,

    ["E-2C"] = 1,  -- AWACS, not a fighter
    ["E-3A"] = 1,  -- AWACS, not a fighter
}

-- ============================================================
-- GLOBAL STATE
-- ============================================================

local S = {
    player = nil,
    groupId = nil,
    tickCount = 0,
    eccmBlock = {},        -- [unitKey] = timestamp until which it resists
    trackedMissiles = {},  -- [key] = weapon
    missileRolls = {},     -- [key] = true once disruption has been rolled

    -- ON/OFF state of each set, so a message is only sent on
    -- TRANSITION (not every cycle).
    offState = false,
    spotState = false,
    spotTargetKey = nil,
    defState = false,
    loggedOtherType = false,

    -- Thermal management
    heat = 0,          -- 0-100%
    lowPower = false,
    overheated = false,
    lockoutUntil = 0,

    -- Cockpit switches (default = everything on, until the file is
    -- read for the first time - compatible with versions without the
    -- switches' Export.lua installed)
    swMaster = true,
    sw1 = true,
    sw2 = true,
    sw3 = true,
    lastSwitchCheck = 0,

    -- Manual trigger (MAN + CMD)
    lastCmdPressCount = nil,  -- nil = haven't read the counter yet (avoids arming everything on first poll)
    manualUntil1 = 0,         -- timestamp until which Set 1 manual stays active
    manualArmed2 = false,     -- Set 2 manual: stays true for as long as the "lock" lasts
    manualUntil3 = 0,         -- timestamp until which Set 3 manual stays active
}

-- ============================================================
-- UTIL
-- ============================================================

local function safe(f, default)
    local ok, v = pcall(f)
    if ok then return v end
    return default
end

local function nmToM(nm) return nm * 1852 end
local function mToNm(m) return m / 1852 end

local function dist2D(a, b)
    local dx = a.x - b.x
    local dz = a.z - b.z
    return math.sqrt(dx*dx + dz*dz)
end

local function clamp(x, a, b)
    if x < a then return a end
    if x > b then return b end
    return x
end

local _rand = math.random

local function randf(a, b) return a + _rand() * (b - a) end

local function dbg(text)
    if not DEBUG_MESSAGES then return end
    if DEBUG_TO_UNIT and S.groupId then
        trigger.action.outTextForGroup(S.groupId, "[F15E JMR] " .. text, 3)
    end
end

local function unitKey(u)
    local ok, id = pcall(function() return u:getID() end)
    if ok and id then return tostring(id) end
    return tostring(u)
end

local function tierForUnit(u)
    local tn = safe(function() return u:getTypeName() end, nil)
    if not tn then return DEFAULT_TIER end
    local t = PRIORITY_TIER[tn]
    if t == nil then return DEFAULT_TIER end
    return t
end

local function isExcluded(u)
    local tn = safe(function() return u:getTypeName() end, nil)
    return tn ~= nil and PRIORITY_TIER[tn] == -1
end

local function displayName(u)
    local d = safe(function() return u:getDesc() end, nil)
    if d and d.displayName and d.displayName ~= "" then return d.displayName end
    return safe(function() return u:getTypeName() end, "?")
end

local function describeThreat(u, tier, rangeNm, domain)
    local tag = (domain == "AIR") and "AIR" or "SAM"
    return string.format("%s (%s, tier %d, %.0f NM)", displayName(u), tag, tier, rangeNm)
end

-- Standard DCS text message for the whole crew (pilot + WSO), sent
-- only on the state TRANSITION of each set.
local function reportStatus(kind, isOn, extra)
    if not STATUS_MESSAGES_ENABLED or not S.groupId then return end

    local label
    if kind == "OFFENSIVE" then
        local suffix = (isOn and extra) and " (MANUAL)" or ""
        label = (isOn and "EW: OFFENSIVE JAMMING ON" or "EW: OFFENSIVE JAMMING OFF") .. suffix
    elseif kind == "SPOT" then
        if isOn then
            label = "EW: SPOT JAMMING ON - " .. tostring(extra)
        else
            label = "EW: SPOT JAMMING OFF"
        end
    elseif kind == "DEFENSIVE" then
        local suffix = (isOn and extra) and " (MANUAL)" or ""
        label = (isOn and "EW: MISSILE DEFEAT ACTIVE" or "EW: MISSILE DEFEAT OFF") .. suffix
    elseif kind == "LOWPOWER" then
        label = isOn and "EW: THERMAL LOW POWER" or "EW: THERMAL NORMAL"
    elseif kind == "OVERHEAT" then
        label = isOn and "EW: THERMAL OVERHEAT - JAMMER OFFLINE" or "EW: THERMAL SYSTEM READY"
    else
        label = kind .. (isOn and " ON" or " OFF")
    end

    trigger.action.outTextForGroup(S.groupId, label, STATUS_MSG_DURATION_SEC)
end

local function hasAttr(u, a)
    return safe(function() return u:hasAttribute(a) end, false)
end

-- ============================================================
-- PLAYER TRACKING (same logic as the diagnostic script)
-- ============================================================

local function findPlayer()
    for _, side in ipairs({coalition.side.BLUE, coalition.side.RED}) do
        local groups = safe(function()
            return coalition.getGroups(side, Group.Category.AIRPLANE)
        end, {})
        for _, g in ipairs(groups or {}) do
            local units = safe(function() return g:getUnits() end, {})
            for _, u in ipairs(units or {}) do
                local alive = safe(function() return u:isExist() and u:getLife() > 0 end, false)
                local pname = safe(function() return u:getPlayerName() end, nil)
                local tn = safe(function() return u:getTypeName() end, "?")
                if alive and pname then
                    if ELIGIBLE_TYPES[tn] then
                        return u
                    elseif not S.loggedOtherType then
                        -- Helps diagnose if the F-15E's typeName changed
                        -- in a patch and no longer matches
                        -- ELIGIBLE_TYPES.
                        env.info("F15E_JAMMER: player found in a non-eligible aircraft typeName='" .. tn .. "'")
                        S.loggedOtherType = true
                    end
                end
            end
        end
    end
    return nil
end

local function updatePlayer()
    S.player = findPlayer()
    if not S.player then
        S.groupId = nil
        return false
    end
    local g = safe(function() return S.player:getGroup() end, nil)
    S.groupId = g and safe(function() return g:getID() end, nil)
    return true
end

local function enemySide()
    local c = safe(function() return S.player:getCoalition() end, nil)
    if c == coalition.side.BLUE then return coalition.side.RED end
    if c == coalition.side.RED then return coalition.side.BLUE end
end

-- ============================================================
-- RANGE (60% of the EA-18G's effective range)
-- ============================================================

local function maxJamRangeNm()
    -- Reproduces the EA-18G's base formula (base * EA18G_RANGE_MUL)
    -- and applies the additional F-15E-specific factor on top. Under
    -- LOW POWER (partial overheat), range also drops.
    local ea18gEffective = EA18G_BASE_NM * EA18G_RANGE_MUL
    local r = ea18gEffective * F15_RANGE_SCALE
    if S.lowPower then
        r = r * LOW_POWER_RANGE_MUL
    end
    return r
end

-- ============================================================
-- EMITTER SCAN (SAM domain: ground + naval unified)
-- ============================================================

local function unitIsEmitter(u)
    if not u or not safe(function() return u:isExist() end, false) then return false end
    if isExcluded(u) then return false end
    return hasAttr(u, "SAM SR") or hasAttr(u, "SAM TR") or hasAttr(u, "SAM STR")
end

local function scanEmitters()
    local emitters = {}
    local side = enemySide()
    if not side then return emitters end

    -- Ground and naval systems use the SAME SAM SR/TR/STR attributes
    -- in DCS - that's why they go in the same list, only the searched
    -- category differs.
    for _, catg in ipairs({Group.Category.GROUND, Group.Category.SHIP}) do
        local groups = safe(function()
            return coalition.getGroups(side, catg)
        end, {})

        for _, g in ipairs(groups or {}) do
            local units = safe(function() return g:getUnits() end, {})
            for _, u in ipairs(units or {}) do
                if unitIsEmitter(u) then
                    emitters[#emitters+1] = u
                    if #emitters >= MAX_EMITTERS_CONSIDERED then return emitters end
                end
            end
        end
    end
    return emitters
end

-- ============================================================
-- AIR THREAT SCAN (AIR domain: enemy fighters/bombers)
-- Aircraft have no SAM SR/TR/STR attribute - any enemy aircraft
-- within range is eligible; the tier in PRIORITY_TIER decides the
-- weight/danger of each specific type.
-- ============================================================

local function scanAirThreats()
    local airThreats = {}
    local side = enemySide()
    if not side then return airThreats end

    local groups = safe(function()
        return coalition.getGroups(side, Group.Category.AIRPLANE)
    end, {})

    for _, g in ipairs(groups or {}) do
        local units = safe(function() return g:getUnits() end, {})
        for _, u in ipairs(units or {}) do
            if u and safe(function() return u:isExist() end, false) then
                airThreats[#airThreats+1] = u
                if #airThreats >= MAX_EMITTERS_CONSIDERED then return airThreats end
            end
        end
    end
    return airThreats
end

-- ============================================================
-- SUPPRESSION (temporary ROE WEAPON_HOLD) - mechanism shared by
-- Sets 1 and 2, with different parameters (strength/frequency).
-- Supports two domains: "SAM" (ground/naval, AI.Option.Ground) and
-- "AIR" (enemy aircraft, AI.Option.Air) - same soft-kill technique,
-- different ROE API depending on the controller type.
-- ============================================================

local function safeSetWeaponHold(u)
    return safe(function()
        local ctrl = u:getController()
        if not ctrl then return false end
        ctrl:setOption(AI.Option.Ground.id.ROE, AI.Option.Ground.val.ROE.WEAPON_HOLD)
        return true
    end, false)
end

local function safeSetOpenFire(u)
    return safe(function()
        local ctrl = u:getController()
        if not ctrl then return false end
        ctrl:setOption(AI.Option.Ground.id.ROE, AI.Option.Ground.val.ROE.OPEN_FIRE)
        return true
    end, false)
end

local function safeSetAirWeaponHold(u)
    return safe(function()
        local ctrl = u:getController()
        if not ctrl then return false end
        ctrl:setOption(AI.Option.Air.id.ROE, AI.Option.Air.val.ROE.WEAPON_HOLD)
        return true
    end, false)
end

local function safeSetAirOpenFire(u)
    return safe(function()
        local ctrl = u:getController()
        if not ctrl then return false end
        ctrl:setOption(AI.Option.Air.id.ROE, AI.Option.Air.val.ROE.OPEN_FIRE)
        return true
    end, false)
end

-- Applies suppression with a resistance (ECCM) chance based on tier.
-- setLabel: "OFF" (set 1) or "SPT" (set 2), for debug purposes only.
-- domain: "SAM" (default) or "AIR" - decides which ROE API to use.
local function applySuppression(now, target, tier, holdMin, holdMax, resistBase, setLabel, domain)
    domain = domain or "SAM"
    local tkey = unitKey(target)
    local blkUntil = S.eccmBlock[tkey] or 0
    if now < blkUntil then
        dbg(string.format("[%s/%s] ECCM REACQ still active (%.1fs) tgt=%s", setLabel, domain, blkUntil - now, tkey))
        return
    end

    local roll = _rand()
    if roll < resistBase then
        -- the radar/RWR resisted this pulse: blocks further attempts for a while
        local block = randf(3, 8)
        if tier >= 3 then block = randf(6, 10) end
        S.eccmBlock[tkey] = now + block
        dbg(string.format("[%s/%s] RESIST roll=%.2f<thr=%.2f tier=%d -> reacq %.1fs", setLabel, domain, roll, resistBase, tier, block))
        return
    end

    local hold = randf(holdMin, holdMax)
    local applied
    if domain == "AIR" then
        applied = safeSetAirWeaponHold(target)
    else
        applied = safeSetWeaponHold(target)
    end
    if not applied then return end
    dbg(string.format("[%s/%s] SUPPRESS OK tier=%d hold=%.1fs", setLabel, domain, tier, hold))

    timer.scheduleFunction(function(param, t)
        local u = param
        if u and safe(function() return u:isExist() end, false) then
            if domain == "AIR" then
                safeSetAirOpenFire(u)
            else
                safeSetOpenFire(u)
            end
        end
        return nil
    end, target, now + hold)
end

-- Applies the LOW POWER modifiers (if active) to the resistance
-- chance and hold duration, before calling applySuppression. Used by
-- Sets 1 and 2 (Set 3 has its own equivalent adjustment inside
-- runDefensive, since it doesn't use applySuppression).
local function lowPowerAdjust(resist, holdMin, holdMax)
    if not S.lowPower then return resist, holdMin, holdMax end
    local r = clamp(resist + LOW_POWER_RESIST_ADD, 0, 0.95)
    return r, holdMin * LOW_POWER_HOLD_MUL, holdMax * LOW_POWER_HOLD_MUL
end

-- ============================================================
-- SET 1 - OFFENSIVE: SEARCH radars (SAM SR) + all air threats within
-- range (aircraft have no searching/locked distinction in the DCS
-- API, so any one within range is eligible for this set's weak/broad
-- pulse).
-- ============================================================

local function runOffensive(now, emitters, airThreats, maxR)
    local jp = safe(function() return S.player:getPoint() end, nil)
    if not jp then return false end

    local anyActive = false

    -- SAM domain (ground + naval) - search radars only (SAM SR)
    for _, e in ipairs(emitters) do
        if hasAttr(e, "SAM SR") and safe(function() return e:isExist() end, false) then
            local ep = safe(function() return e:getPoint() end, nil)
            if ep then
                local rangeNm = mToNm(dist2D(jp, ep))
                if rangeNm <= maxR then
                    anyActive = true
                    local tier = tierForUnit(e)
                    -- Offensive: weaker/spaced-out pulse, covers several
                    -- emitters "sweeping" at the same time.
                    local resist = clamp(0.35 + (tier - 1) * 0.10, 0.10, 0.85)
                    local hMin, hMax
                    resist, hMin, hMax = lowPowerAdjust(resist, 2, 5)
                    applySuppression(now, e, tier, hMin, hMax, resist, "OFF", "SAM")
                end
            end
        end
    end

    -- AIR domain - any enemy aircraft within range
    for _, a in ipairs(airThreats) do
        if safe(function() return a:isExist() end, false) then
            local ap = safe(function() return a:getPoint() end, nil)
            if ap then
                local rangeNm = mToNm(dist2D(jp, ap))
                if rangeNm <= maxR then
                    anyActive = true
                    local tier = tierForUnit(a)
                    local resist = clamp(0.35 + (tier - 1) * 0.10, 0.10, 0.85)
                    local hMin, hMax
                    resist, hMin, hMax = lowPowerAdjust(resist, 2, 5)
                    applySuppression(now, a, tier, hMin, hMax, resist, "OFF", "AIR")
                end
            end
        end
    end

    return anyActive
end

-- ============================================================
-- SET 2 - SPOT-ON: single highest-priority target.
-- DOMAIN PRIORITY: any AIR threat within range automatically beats
-- any SAM, ground or naval, regardless of tier/distance - as
-- specified. Only when no aircraft is within range does the
-- tier/distance formula decide between SAMs
-- (score = tierWeight[tier] / max(rangeNm, 1)).
-- ============================================================

local function bestByScore(jp, maxR, list, filterFn)
    local best, bestScore, bestRange, bestTier = nil, -1, nil, nil

    for _, e in ipairs(list) do
        if filterFn(e) and safe(function() return e:isExist() end, false) then
            local ep = safe(function() return e:getPoint() end, nil)
            if ep then
                local rangeNm = mToNm(dist2D(jp, ep))
                if rangeNm <= maxR then
                    local tier = tierForUnit(e)
                    local w = TIER_WEIGHT[tier] or TIER_WEIGHT[DEFAULT_TIER]
                    local score = w / math.max(rangeNm, 1)
                    if score > bestScore then
                        best, bestScore, bestRange, bestTier = e, score, rangeNm, tier
                    end
                end
            end
        end
    end

    return best, bestTier, bestRange
end

local function runSpotOn(now, emitters, airThreats, maxR)
    local jp = safe(function() return S.player:getPoint() end, nil)
    if not jp then return nil end

    -- AIR domain first - wins whenever any eligible target exists.
    local bestAir, airTier, airRange = bestByScore(jp, maxR, airThreats, function() return true end)
    if bestAir then
        local resist = clamp(0.20 + (airTier - 1) * 0.08, 0.05, 0.60)
        local hMin, hMax
        resist, hMin, hMax = lowPowerAdjust(resist, 4, 8)
        applySuppression(now, bestAir, airTier, hMin, hMax, resist, "SPT", "AIR")
        dbg(string.format("SPOT-ON [AIR] target=%s tier=%d rng=%.1fNM", unitKey(bestAir), airTier, airRange))
        return bestAir, airTier, airRange, "AIR"
    end

    -- No aircraft in range - fall back to the SAM domain (ground + naval)
    local bestSam, samTier, samRange = bestByScore(jp, maxR, emitters, function(e)
        return hasAttr(e, "SAM TR") or hasAttr(e, "SAM STR")
    end)
    if bestSam then
        local resist = clamp(0.20 + (samTier - 1) * 0.08, 0.05, 0.60)
        local hMin, hMax
        resist, hMin, hMax = lowPowerAdjust(resist, 4, 8)
        applySuppression(now, bestSam, samTier, hMin, hMax, resist, "SPT", "SAM")
        dbg(string.format("SPOT-ON [SAM] target=%s tier=%d rng=%.1fNM", unitKey(bestSam), samTier, samRange))
        return bestSam, samTier, samRange, "SAM"
    end

    return nil
end

-- ============================================================
-- SET 3 - DEFENSIVE: missile disruption against the player
-- ============================================================

local function isRadarGuided(weapon)
    local tn = safe(function() return weapon:getTypeName() end, "")
    tn = string.upper(tn or "")
    if string.find(tn, "AIM%-9") or string.find(tn, "R%-73") or string.find(tn, "IR") then
        return false
    end
    return true
end

local function missileKey(w) return tostring(w) end

local function scheduleMissileKill(weapon, now)
    local delay = randf(0.0, MISSILE_DISRUPT_DELAY_MAX)
    timer.scheduleFunction(function(param, t)
        local w = param
        if w and safe(function() return w:isExist() end, false) then
            safe(function() w:destroy() end, nil)
        end
        return nil
    end, weapon, now + delay)
end

local JammerEventHandler = {}
function JammerEventHandler:onEvent(e)
    if not e or e.id ~= world.event.S_EVENT_SHOT then return end
    if not e.weapon or not safe(function() return e.weapon:isExist() end, false) then return end
    if not isRadarGuided(e.weapon) then return end

    -- Only tracks missiles whose target is the player itself (Set 3 is
    -- strictly defensive and does not touch missiles fired at other
    -- aircraft/units).
    local tgt = safe(function() return e.weapon:getTarget() end, nil)
    if not tgt or not S.player then return end
    local tgtIsPlayer = safe(function() return tgt:getID() == S.player:getID() end, false)
    if not tgtIsPlayer then return end

    S.trackedMissiles[missileKey(e.weapon)] = e.weapon
    dbg("MSL LAUNCH detected against the player")

    -- If the system is overheated, the master switch is off, or SET 3
    -- is in MAN with no manual window open (neither AUTO nor a CMD
    -- press within the last 60s), we still track the missile
    -- (bookkeeping), but don't announce "DEFENSIVE ON" - the system
    -- is genuinely offline at this moment.
    local set3Active = S.sw3 or (timer.getTime() < S.manualUntil3)
    if not S.overheated and S.swMaster and set3Active and not S.defState then
        S.defState = true
        reportStatus("DEFENSIVE", true, not S.sw3)
    end
end
world.addEventHandler(JammerEventHandler)

local function runDefensive(now)
    if not S.player then return end
    local jp = safe(function() return S.player:getPoint() end, nil)
    if not jp then return end

    -- Low Power also reduces Set 3's range and success chance, at the
    -- same proportion as Sets 1/2.
    local rangeNm = MISSILE_DISRUPT_RANGE_NM
    local chance = MISSILE_DISRUPT_CHANCE
    if S.lowPower then
        rangeNm = rangeNm * LOW_POWER_RANGE_MUL
        chance = clamp(chance - LOW_POWER_RESIST_ADD, 0, 1)
    end

    for key, w in pairs(S.trackedMissiles) do
        if w and safe(function() return w:isExist() end, false) then
            local wp = safe(function() return w:getPoint() end, nil)
            if wp then
                local rngNm = mToNm(dist2D(jp, wp))
                if rngNm <= rangeNm and not S.missileRolls[key] then
                    S.missileRolls[key] = true
                    local roll = _rand()
                    if roll <= chance then
                        dbg("MSL DISRUPT scheduled")
                        scheduleMissileKill(w, now)
                    else
                        dbg("MSL DISRUPT failed - pilot must defend")
                    end
                end
            end
        else
            S.trackedMissiles[key] = nil
            S.missileRolls[key] = nil
        end
    end

    -- All tracked missiles have resolved (destroyed, impacted, or
    -- otherwise ceased to exist) - Defensive goes back to OFF.
    if S.defState and next(S.trackedMissiles) == nil then
        S.defState = false
        reportStatus("DEFENSIVE", false)
    end
end

-- ============================================================
-- COCKPIT SWITCHES - reads the state file written by
-- F15E_Jammer_Switches_Export.lua (Export.lua) and updates
-- S.swMaster/sw1/sw2/sw3. If the file doesn't exist or can't be
-- read, keeps the last known state (or the "everything on" default).
-- ============================================================

local function updateSwitchState(now)
    if not SWITCH_STATE_FILE then return end  -- lfs unavailable in this environment
    if now - S.lastSwitchCheck < SWITCH_POLL_SEC then return end
    S.lastSwitchCheck = now

    local fOk, f, ferr = pcall(io.open, SWITCH_STATE_FILE, "r")
    if not fOk or not f then
        env.info("F15E_JAMMER: could not open " .. tostring(SWITCH_STATE_FILE) .. " error=" .. tostring(ferr))
        return
    end

    local content = safe(function()
        local c = f:read("*a")
        f:close()
        return c
    end, nil)
    if not content then return end

    -- Periodic log (once per poll, 1x/s) of the raw content read -
    -- temporary diagnostic point to compare against Export.lua's
    -- write logs and find where the information gets lost.
    -- (verbose log removed after confirming it works - v1.15 had
    -- this on for diagnostics, now resolved)

    local m, s1, s2, s3, cmdCount = content:match("(%d),(%d),(%d),(%d),(%d+)")
    if not m then
        env.info("F15E_JAMMER: content didn't match expected pattern -> '" .. tostring(content) .. "'")
        return
    end

    local prevMaster = S.swMaster
    S.swMaster = (m == "1")
    S.sw1 = (s1 == "1")
    S.sw2 = (s2 == "1")
    S.sw3 = (s3 == "1")

    -- Unconditional log (doesn't depend on DEBUG_MESSAGES) whenever
    -- the master switch changes state - helps diagnose whether the
    -- switch reading matches what the pilot actually did.
    if S.swMaster ~= prevMaster then
        env.info(string.format(
            "F15E_JAMMER: ICS master changed to %s (raw='%s', full line='%s')",
            tostring(S.swMaster), m, content))
    end

    -- CMD press detection via the monotonic counter (avoids a race
    -- between the Export script's write rate and our read rate).
    -- Only compares after the first read, so we don't "arm"
    -- everything off a stale value the moment the mission loads.
    local count = tonumber(cmdCount)
    if count then
        if S.lastCmdPressCount == nil then
            S.lastCmdPressCount = count
        elseif count > S.lastCmdPressCount then
            S.lastCmdPressCount = count
            if S.swMaster then
                -- Each set in MAN gets armed/refreshed by this press;
                -- sets in AUTO are unaffected (they already work
                -- automatically, independent of CMD).
                if not S.sw1 then S.manualUntil1 = now + MANUAL_TRIGGER_DURATION_SEC end
                if not S.sw2 then S.manualArmed2 = true end
                if not S.sw3 then S.manualUntil3 = now + MANUAL_TRIGGER_DURATION_SEC end
                dbg("CMD pressed - arming sets in MAN")
            end
        end
    end
end

-- ============================================================
-- THERMAL MANAGEMENT - accumulates heat per active set, applies LOW
-- POWER and OVERHEAT (locks everything out, faithful to the original
-- EA-18G - confirmed with the user that Set 3 also stops during
-- lockout).
-- ============================================================

local function updateHeat(now)
    -- Already locked out: just wait it out, cooling down.
    if S.overheated then
        if now >= S.lockoutUntil then
            S.overheated = false
            S.lowPower = false
            reportStatus("OVERHEAT", false)
        else
            S.heat = clamp(S.heat - HEAT_COOL_RATE * JAM_TICK_SEC, 0, 100)
            return
        end
    end

    local rate = 0
    if S.offState then rate = rate + HEAT_RATE_OFFENSIVE end
    if S.spotState then rate = rate + HEAT_RATE_SPOTON end
    if S.defState then rate = rate + HEAT_RATE_DEFENSIVE end
    if rate <= 0 then rate = -HEAT_COOL_RATE end

    S.heat = clamp(S.heat + rate * JAM_TICK_SEC, 0, 100)

    if DEBUG_MESSAGES then
        dbg(string.format("HEAT %.1f%% low=%s over=%s", S.heat, tostring(S.lowPower), tostring(S.overheated)))
    end

    if S.heat >= HEAT_OVERHEAT_THRESHOLD then
        S.overheated = true
        S.lockoutUntil = now + HEAT_LOCKOUT_SEC
        reportStatus("OVERHEAT", true)

        -- Single shared system - everything locks out together,
        -- including Set 3.
        if S.offState then
            S.offState = false
            reportStatus("OFFENSIVE", false)
        end
        if S.spotState then
            S.spotState = false
            S.spotTargetKey = nil
            reportStatus("SPOT", false)
        end
        if S.defState then
            S.defState = false
            reportStatus("DEFENSIVE", false)
        end

        S.lowPower = false
        return
    end

    if S.heat >= HEAT_LOW_POWER_THRESHOLD then
        if not S.lowPower then
            S.lowPower = true
            reportStatus("LOWPOWER", true)
        end
    elseif S.heat < (HEAT_LOW_POWER_THRESHOLD - HEAT_LOW_POWER_HYSTERESIS) then
        if S.lowPower then
            S.lowPower = false
            reportStatus("LOWPOWER", false)
        end
    end
end

-- ============================================================
-- MAIN LOOP
-- ============================================================

local function jamCycle(now)
    if not S.player or not safe(function() return S.player:isExist() end, false) then return end

    S.tickCount = S.tickCount + 1

    updateSwitchState(now)

    -- System fully locked out due to overheating - faithful to the
    -- original EA-18G, nothing runs (not even Set 3) until the
    -- cooldown finishes.
    if S.overheated then
        updateHeat(now)
        return
    end

    -- Master switch (ICS ON/OFF) off - all 3 sets stop together,
    -- same behavior as overheat, but without triggering a thermal
    -- lockout (it's just the pilot switching the system off).
    if not S.swMaster then
        if S.offState then S.offState = false; reportStatus("OFFENSIVE", false) end
        if S.spotState then S.spotState = false; S.spotTargetKey = nil; reportStatus("SPOT", false) end
        if S.defState then S.defState = false; reportStatus("DEFENSIVE", false) end
        updateHeat(now)
        return
    end

    -- Each set is active if: (a) its switch is in AUTO, or (b) it's
    -- in MAN but was manually triggered via CMD and that trigger
    -- window is still valid (Sets 1/3: fixed 60s; Set 2: for as long
    -- as the "lock" lasts, see below).
    local set1Active = S.sw1 or (now < S.manualUntil1)
    local set3Active = S.sw3 or (now < S.manualUntil3)

    if (S.tickCount % SCAN_EVERY_N_TICKS) ~= 0 then
        -- still runs the defensive set every tick (missiles are
        -- urgent), if Set 3 is active (AUTO or within its manual window)
        if set3Active then
            runDefensive(now)
        elseif S.defState then
            S.defState = false
            reportStatus("DEFENSIVE", false)
        end
        updateHeat(now)
        return
    end

    local maxR = maxJamRangeNm()
    local emitters = scanEmitters()
    local airThreats = scanAirThreats()

    -- Set 1: AUTO always runs; in MAN, only runs within the 60s
    -- window opened by the last CMD press.
    local offActive = false
    if set1Active then
        offActive = runOffensive(now, emitters, airThreats, maxR)
    end

    -- Set 2: AUTO always runs; in MAN, only runs while S.manualArmed2
    -- is true (armed by the last CMD press). If no valid target is
    -- found this cycle, it disarms - the "duration" is the lock
    -- itself, no fixed timer.
    local spotTarget, spotTier, spotRange, spotDomain
    local set2Active = S.sw2 or S.manualArmed2
    if set2Active then
        spotTarget, spotTier, spotRange, spotDomain = runSpotOn(now, emitters, airThreats, maxR)
        if not S.sw2 and spotTarget == nil then
            S.manualArmed2 = false  -- the "lock" is gone, needs a fresh CMD to rearm
        end
    end

    if set3Active then
        runDefensive(now)
    elseif S.defState then
        S.defState = false
        reportStatus("DEFENSIVE", false)
    end

    -- --------------------------------------------------------------
    -- ON/OFF messages - only on state transition (not every cycle)
    -- --------------------------------------------------------------

    if offActive ~= S.offState then
        S.offState = offActive
        reportStatus("OFFENSIVE", offActive, not S.sw1)
    end

    local spotOn = spotTarget ~= nil
    if spotOn ~= S.spotState then
        S.spotState = spotOn
        if spotOn then
            S.spotTargetKey = unitKey(spotTarget)
            local desc = describeThreat(spotTarget, spotTier, spotRange, spotDomain)
            if not S.sw2 then desc = desc .. " (MANUAL)" end
            reportStatus("SPOT", true, desc)
        else
            S.spotTargetKey = nil
            reportStatus("SPOT", false)
        end
    elseif spotOn then
        -- Still ON, but the priority target changed (e.g. a more
        -- dangerous/closer threat took over, or an aircraft entered
        -- range and took priority over a SAM) - re-announce with the
        -- new name.
        local newKey = unitKey(spotTarget)
        if newKey ~= S.spotTargetKey then
            S.spotTargetKey = newKey
            local desc = describeThreat(spotTarget, spotTier, spotRange, spotDomain)
            if not S.sw2 then desc = desc .. " (MANUAL)" end
            reportStatus("SPOT", true, desc)
        end
    end

    updateHeat(now)
end

-- ============================================================
-- STATUS MESSAGES - controlled by the STATUS_MESSAGES_MODE flag at
-- the top of the file (ON/OFF). No F10 menu - direct script editing,
-- kept simple for the testing phase.
-- ============================================================

local function mainLoop(_, time)
    local wasTracking = S.player ~= nil
    updatePlayer()
    if S.player and not wasTracking then
        env.info("F15E_JAMMER: F-15E player detected (groupId=" .. tostring(S.groupId) .. ") - auto jammer active")
        dbg("F-15E player detected - auto jammer active")
    end

    if S.player then
        jamCycle(time)
    end

    return time + JAM_TICK_SEC
end

env.info("F15E_JAMMER: script loaded in the mission environment, searching for the F-15E")
timer.scheduleFunction(mainLoop, {}, timer.getTime() + 1)
