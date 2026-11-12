-- ============================================================
-- EMIS_LMT_Hook.lua
-- Roda no ambiente de Hooks do DCS (Saved Games\DCS\Scripts\Hooks\),
-- que TEM acesso a net.dostring_in - diferente do Export.lua.
--
-- Fica de olho no arquivo escrito pelo EMIS_LMT_Export.lua e, quando
-- o estado muda, manda o comando pra exibir/esconder a imagem dentro
-- do ambiente de missao (via net.dostring_in("server", ...)).
--
-- Tecnica do "clearview": ao ligar, mostra a imagem de verdade por um
-- tempo bem longo. Ao desligar, mostra uma imagem TRANSPARENTE por
-- so 1 segundo, com clearview=true - isso substitui/apaga a imagem
-- anterior, e como e transparente, o jogador nao percebe nada na tela
-- durante esse 1 segundo.
-- ============================================================

local STATE_FILE = lfs.writedir() .. "Scripts/EMIS_MOD_state.txt"
local IMG_FOLDER = lfs.writedir() .. "Scripts/EMIS_MOD/"
local IMG_ACESA = (IMG_FOLDER .. "emis_lmt_acesa.png"):gsub("\\", "/")
local IMG_TRANSPARENTE = (IMG_FOLDER .. "transparente.png"):gsub("\\", "/")

local lastKnownState = nil
local frameCounter = 0
local CHECK_EVERY_N_FRAMES = 15  -- ~4x por segundo a 60fps

local function readStateFile()
	local f = io.open(STATE_FILE, "r")
	if not f then return nil end
	local content = f:read("*all")
	f:close()
	if content == "1" then return true end
	if content == "0" then return false end
	return nil
end

local function sendToMission(luaCode)
	if net and net.dostring_in then
		local ok, err = pcall(net.dostring_in, "server", luaCode)
		if not ok then
			log.write("EMIS_LMT_HOOK", log.ERROR, "dostring_in falhou: " .. tostring(err))
		end
	else
		log.write("EMIS_LMT_HOOK", log.ERROR, "net.dostring_in nao disponivel neste ambiente tambem!")
	end
end

local function showLightOn()
	-- tenta outPicture; se nao existir, cai pro outText como fallback
	local code = [[
		local ok = pcall(function()
			trigger.action.outPicture(']] .. IMG_ACESA .. [[', 99999, true)
		end)
		if not ok then
			trigger.action.outText("EMIS LMT", 99999, true)
		end
	]]
	sendToMission(code)
end

local function showLightOff()
	local code = [[
		local ok = pcall(function()
			trigger.action.outPicture(']] .. IMG_TRANSPARENTE .. [[', 1, true)
		end)
		if not ok then
			trigger.action.outText("", 1, true)
		end
	]]
	sendToMission(code)
end

local function onCheck()
	frameCounter = frameCounter + 1
	if frameCounter < CHECK_EVERY_N_FRAMES then return end
	frameCounter = 0

	local ok, state = pcall(readStateFile)
	if not ok or state == nil then return end

	if state ~= lastKnownState then
		lastKnownState = state
		if state then
			log.write("EMIS_LMT_HOOK", log.INFO, "Estado mudou para LIGADO - exibindo imagem")
			showLightOn()
		else
			log.write("EMIS_LMT_HOOK", log.INFO, "Estado mudou para DESLIGADO - apagando imagem")
			showLightOff()
		end
	end
end

local PrevOnSimulationFrame = nil
if DCS and DCS.setUserCallbacks then
	local handlers = {}

	function handlers.onSimulationFrame()
		local ok, err = pcall(onCheck)
		if not ok then
			log.write("EMIS_LMT_HOOK", log.ERROR, "onCheck erro: " .. tostring(err))
		end
	end

	DCS.setUserCallbacks(handlers)
	log.write("EMIS_LMT_HOOK", log.INFO, "EMIS_LMT_Hook.lua iniciado")
else
	log.write("EMIS_LMT_HOOK", log.ERROR, "DCS.setUserCallbacks nao disponivel - Hook nao pode iniciar")
end
