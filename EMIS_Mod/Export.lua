-- Data export script for DCS, version 1.2.
-- Copyright (C) 2006-2014, Eagle Dynamics.
-- See http://www.lua.org for Lua script system info 
-- We recommend to use the LuaSocket addon (http://www.tecgraf.puc-rio.br/luasocket) 
-- to use standard network protocols in Lua scripts.
-- LuaSocket 2.0 files (*.dll and *.lua) are supplied in the Scripts/LuaSocket folder
-- and in the installation folder of the DCS. 

-- Expand the functionality of following functions for your external application needs.
-- Look into Saved Games\DCS\Logs\dcs.log for this script errors, please.

-- Tacview
do
	local ok, err = pcall(function()
		local Tacviewlfs = require('lfs')
		dofile(Tacviewlfs.writedir() .. 'Scripts/TacviewGameExport.lua')
	end)
	if not ok then
		log.write("ExportMerge", log.ERROR, "Falha ao carregar Tacview: " .. tostring(err))
	end
end

-- Volanta (protegido - se o arquivo nao existir, so loga e segue em frente)
do
	local ok, err = pcall(function()
		dofile(lfs.writedir() .. "Scripts/DCS_Volanta.lua")
	end)
	if not ok then
		log.write("ExportMerge", log.ERROR, "Falha ao carregar Volanta (arquivo ausente?): " .. tostring(err))
	end
end

-- DCSDTC
do
	local ok, err = pcall(function()
		local DCSDTClfs = require('lfs')
		dofile(DCSDTClfs.writedir() .. 'Scripts/DCSDTC.lua')
	end)
	if not ok then
		log.write("ExportMerge", log.ERROR, "Falha ao carregar DCSDTC: " .. tostring(err))
	end
end

--[[ ModernF15E BEGIN EXPORT BLOCK ]]
-- Load Modern F-15E Export Script Safely
do
    local lfs_status, lfs_mod = pcall(require, 'lfs')
    if lfs_status and lfs_mod and type(lfs_mod.writedir) == "function" then
        local exportPath = lfs_mod.writedir() .. [[Scripts\ModernF15E_Export.lua]]
        local export_status, err = pcall(dofile, exportPath)
        if not export_status then
            log.write("ModernF15E", log.ERROR, "Failed to execute ModernF15E_Export.lua: " .. tostring(err))
        end
    else
        log.write("ModernF15E", log.ERROR, "Failed to load LuaFileSystem or invalid lfs.writedir()")
    end
end
--[[ ModernF15E END EXPORT BLOCK ]]

--[[ EMIS_LMT_MOD BEGIN EXPORT BLOCK ]]
do
    local lfs_status, lfs_mod = pcall(require, 'lfs')
    if lfs_status and lfs_mod and type(lfs_mod.writedir) == "function" then
        local exportPath = lfs_mod.writedir() .. [[Scripts\EMIS_LMT_Export.lua]]
        local export_status, err = pcall(dofile, exportPath)
        if not export_status then
            log.write("EMIS_LMT_MOD", log.ERROR, "Failed to execute EMIS_LMT_Export.lua: " .. tostring(err))
        end
    else
        log.write("EMIS_LMT_MOD", log.ERROR, "Failed to load LuaFileSystem or invalid lfs.writedir()")
    end
end
--[[ EMIS_LMT_MOD END EXPORT BLOCK ]]
