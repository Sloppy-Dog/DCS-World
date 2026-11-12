F-15E AUTO JAMMER - MOD (Scripts + Hooks)
=========================================================================

INSTALLATION
------------
1. Close DCS World.
2. Copy the "Scripts" folder from this package into:
       Saved Games\DCS\
   (or "Saved Games\DCS.openbeta\", depending on your install)

   Expected result after copying:
       Saved Games\DCS\Scripts\F15E_Auto_Jammer.lua
       Saved Games\DCS\Scripts\Hooks\F15E_Jammer_AutoLoader.lua

   If a "Scripts" folder already exists, just add these two files
   inside it (no need to delete anything already there).

3. Start DCS normally and fly any mission with the F-15ESE.
   The jammer activates on its own - no menu, no toggle - automatic
   from the moment the mission loads.

HOW TO CONFIRM IT INSTALLED CORRECTLY
----------------------------------------
IMPORTANT: the log line "F15E_JAMMER_LOADER: ...payload sent..." only
confirms that the net.dostring_in CALL did not error out - it does
NOT confirm the jammer actually started running inside the mission.

The real proof is these TWO lines, coming from INSIDE
F15E_Auto_Jammer.lua itself (look for "F15E_JAMMER:" without
"_LOADER"):
    F15E_JAMMER: script loaded in the mission environment, ...
    F15E_JAMMER: F-15E player detected (groupId=...) - ...

If both lines show up, the jammer is really running. If only the
"_LOADER" log appears and these two never show up, use the fallback
below.

IF SOMETHING FAILS (guaranteed fallback)
-------------------------------------------
We've stress-tested this auto-load method a lot and it has shown some
instability on certain setups (silent failure, or a "trigger nil"
error). If "F15E_JAMMER: script loaded..." never shows up in the log,
use the manual method, which has worked without exception in every
test so far:
  1. Open the mission in the Mission Editor.
  2. Go to Triggers > add a trigger (e.g. type "4 MISSION START"),
     action "DO SCRIPT FILE", pointing to
     Saved Games\DCS\Scripts\F15E_Auto_Jammer.lua.
  3. Save the mission.
The jammer's behavior itself is identical either way - only HOW it
gets loaded changes.

STATUS MESSAGES (ON/OFF on screen)
-------------------------------------
Controlled directly in the F15E_Auto_Jammer.lua file, near the top:

    local STATUS_MESSAGES_MODE = "ON"  -- "ON" or "OFF"

Defaults to "ON" during the beta phase. To disable, change it to
"OFF", save the file, and reload the mission (or restart DCS). There
is no F10 menu for this anymore - just that one line in the script.

COCKPIT SWITCH CONTROL (TEWS panel - Right Console)
--------------------------------------------------------
The jammer can now be controlled by the physical TEWS panel switches:
ICS ON/OFF (master) + SET 1/2/3 MAN/AUTO. Each set only operates when
its switch is in AUTO and the master is ON. In MAN/OFF, the
corresponding set is fully stopped (no heat cost, no suppression at
all).

To enable this, besides the usual two files, you need to:

1. Copy Scripts\F15E_Jammer_Switches_Export.lua (from this package) to
   Saved Games\DCS\Scripts\F15E_Jammer_Switches_Export.lua

2. Add this block to YOUR OWN Export.lua
   (Saved Games\DCS\Scripts\Export.lua) - if you already have similar
   blocks (Tacview, ModernF15E, etc.), just add this one alongside
   them, without deleting the others:

    --[[ F15E_JAMMER_SWITCHES BEGIN EXPORT BLOCK ]]
    do
        local lfs_status, lfs_mod = pcall(require, 'lfs')
        if lfs_status and lfs_mod and type(lfs_mod.writedir) == "function" then
            local exportPath = lfs_mod.writedir() .. [[Scripts\F15E_Jammer_Switches_Export.lua]]
            local export_status, err = pcall(dofile, exportPath)
            if not export_status then
                log.write("F15E_JMR_SW_EXPORT", log.ERROR, "Failed to execute F15E_Jammer_Switches_Export.lua: " .. tostring(err))
            end
        else
            log.write("F15E_JMR_SW_EXPORT", log.ERROR, "Failed to load LuaFileSystem or invalid lfs.writedir()")
        end
    end
    --[[ F15E_JAMMER_SWITCHES END EXPORT BLOCK ]]

IMPORTANT: copy this block from an actual file (text editor), never
from example text pasted directly out of chat/log output - pasting
log output by mistake breaks the whole file (this actually happened
during this mod's development).

How to confirm it's working: open dcs.log and look for
"F15E_JMR_SW_EXPORT: F15E_Jammer_Switches_Export.lua started". The
state file lives at
Saved Games\DCS\Scripts\F15E_Jammer_Switches_state.txt - its content
should change (e.g. from "1,0,0,0" to "1,1,0,0") as you move the TEWS
panel switches in flight.

If you don't install this part, the jammer keeps working exactly as
before (everything always on, automatic) - this is an optional,
backward-compatible feature.

MANUAL TRIGGER IN MAN (CMD chaff/flare button)
--------------------------------------------------
If a set is in MAN, it stays idle until the crew (pilot OR WSO)
presses CMD (the stick's chaff/flare button, up or down). This lets
you stay in emission silence while still having reactive self-defense
when you actually need it.

Duration after triggering:
    Set 1 (Offensive) - 60 seconds
    Set 2 (Spot-on)   - for as long as the "lock" lasts (drops off
                         once the priority threat is gone, no fixed
                         timer)
    Set 3 (Defensive) - 60 seconds

Status messages append "(MANUAL)" when the trigger came from CMD, to
tell it apart from AUTO during testing.

This uses the SAME F15E_Jammer_Switches_Export.lua (already includes
LoGetSnares()-based detection - remaining chaff/flare count) - no
additional install step beyond what's already described above.

EDGE CASE: no chaff/flare left (count at zero)
--------------------------------------------------------
If chaff AND flare both reach zero, there's no more "count drop" left
to detect the CMD press. In that case, sets in MAN become
continuously available (as if in AUTO) for as long as that condition
lasts - the crew has no other way to signal us, and blocking their
self-defense would be worse than defaulting to available. Returns to
normal behavior as soon as chaff or flare is rearmed/restocked.

UNINSTALLING
------------
Delete these files:
    Saved Games\DCS\Scripts\F15E_Auto_Jammer.lua
    Saved Games\DCS\Scripts\Hooks\F15E_Jammer_AutoLoader.lua
    Saved Games\DCS\Scripts\F15E_Jammer_Switches_Export.lua (if installed)
    Saved Games\DCS\Scripts\F15E_Jammer_Switches_state.txt (if present)
And remove the F15E_JAMMER_SWITCHES block from your Export.lua, if added.
