-- ============================================================
-- EMIS_LMT_Export.lua
-- Mod nao-oficial de EMIS LIMIT para o F-15E (DCS World)
--
-- VERSAO DEFINITIVA
--
-- v6 - Relay do WSO pro piloto: em vez do WSO comandar o radar
-- diretamente (o que falha de forma consistente), o clique do WSO
-- (PTN_1312) RETRANSMITE um clique real no botao fisico do piloto
-- (PTN_287, via GetDevice(57)/comando 3018 = UFCCTRL_FRONT/UFC_EMIS_LMT).
--
-- IMPORTANTE - descoberta final sobre essa limitacao: nao e um problema
-- de comando/device/argumento errado. E uma restricao de SINCRONIZACAO
-- DE TRIPULACAO (multicrew) do proprio motor/modulo - confirmada com
-- uma chave fisica REAL (Cipher Text) comandando o radar diretamente:
-- mesmo assim, o radar so muda de estado quando o comando e PROCESSADO
-- com o assento do PILOTO como ponto de controle ativo no momento exato,
-- nao importa qual botao/dispositivo disparou o comando.
--
-- Na pratica, isso significa:
--   - Voo solo (voce controla os dois assentos sozinho): o relay so
--     funciona se voce estiver fisicamente no assento do piloto no
--     momento em que o botao retransmitido "solta" (volta ao repouso).
--     Clicando do WSO e ficando la, o radar NAO muda.
--   - Multiplayer real (um piloto humano de verdade ocupando o assento
--     dianteiro continuamente): o WSO aciona o relay, e como o piloto
--     esta la o tempo todo, o comando deve ser processado corretamente
--     quando o botao retransmitido soltar - a expectativa e que funcione
--     nesse cenario. Ainda nao testado com um segundo jogador real;
--     vale confirmar quando houver oportunidade.
--
-- JTIDS->OFF e TF->LPI nao tem essa restricao - funcionam plenamente
-- de qualquer assento, inclusive voo solo.
--
-- v4/v5 - Corrige a navegacao de pagina usando cliques com "hold"
-- real (pressiona, mantem ~150ms, solta) em vez de aperta+solta
-- instantaneo, que nao registrava nos botoes de troca de pagina do
-- MPCDR (PB11/PB4 etc). Confirmado por teste: instantaneo falha, hold
-- de 150ms funciona.
--
-- Estado do LPI/NORM do TF e mantido numa variavel PROPRIA (EMIS.tfLpiOn),
-- independente da tela que estiver sendo mostrada no momento - conforme
-- descrito pelo usuario, a tela pode mudar entre a ativacao e a
-- desativacao, entao nao da pra inferir o estado so olhando a tela atual.
--
-- Logica de navegacao (a partir de QUALQUER tela):
--   - Se ja esta em TF: so aperta o botao final (PB9=LPI ou PB6=NORM).
--   - Se esta no Menu 1 (identificavel pelos rotulos ADI+ARMT): PB4, depois o final.
--   - Se esta em qualquer outra tela de funcao: PB11 (vai pro M1), PB4, final.
--   - Se esta em M2 ou M3 (nao temos como diferenciar por rotulo, caem
--     em "UNKNOWN"): quando conseguimos LER o resultado (WSO presente),
--     tentamos ate 3 vezes, verificando apos cada PB11 se chegamos ao M1.
--     Quando NAO conseguimos ler (disparado do piloto sozinho, sem
--     ninguem no WSO), fazemos so 1 tentativa (nao da pra verificar e
--     multiplas tentativas as cegas correm risco de ciclar os menus
--     errado).
--
-- Devices/comandos confirmados por teste em jogo:
--   GetDevice(0)  = leitura de argumentos do modelo
--   GetDevice(1)  = RDRCTRL_AA    -> comando 3476 (JTIDS knob)
--   GetDevice(3)  = AN_APG70      -> comando 3471 (Radar Mode Selector)
--   GetDevice(40) = MPCD_RRIGHT   -> comandos Button_XX
--   GetDevice(57) = UFCCTRL_FRONT -> comando 3018 (UFC_EMIS_LMT, relay)
--
-- Fingerprints de pagina via list_indication (indice escaneado, nao fixo):
--   MENU (M1 especificamente): contem "ADI" e "ARMT"
--   ADI: "ADI_Indicator_Begins"      HSI: "HSI_Indicator_Begins"
--   ARMT: "PACS_PB01_LABEL"          TSD: "TSD_MAP_RENDER"
--   TF:   "TFR_PB1"                  TPOD: "NF_Video_Open"
--   TEWS: "TEWS_CENTER"
--
-- LIMITACAO CONHECIDA: list_indication só retorna dados do assento
-- que estiver sendo controlado no momento. Voando sozinho como piloto,
-- a leitura falha (retorna "NOREAD") - nesse caso operamos as cegas,
-- com uma unica tentativa de navegacao (ver acima). Isso so afeta a
-- restauracao exata da pagina do MPCD_RRIGHT ao desligar, nao afeta
-- radar/JTIDS/TF-LPI, que funcionam plenamente dos dois assentos.
-- ============================================================

local PrevExportStart    = LuaExportStart
local PrevExportStop     = LuaExportStop
local PrevExportActivity = LuaExportActivityNextEvent

-- ===== Constantes confirmadas =====
local RADAR_CMD  = 3471
local JTIDS_CMD  = 3476

-- Chave ICS ON/OFF do console direito traseiro (PTN_1465, confirmado
-- via clickabledata.lua: default_2_position_tumb_animated).
-- Usada para desligar os jammers indiretamente (o mod de jammer,
-- separado, detecta essa chave por conta propria).
local ICS_DEVICE = 62   -- devices.EWS_JMR no devices.lua - CONFIRMADO por teste (varredura 58-65)
local ICS_CMD    = 3921
local ICS_ARG    = 1465
local ICS_OFF_VALUE = 0.0  -- CONFIRMADO por teste (leitura mostrou ON=1, OFF=0)
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

-- ============================================================
-- CONFIGURACAO DO JOGADOR - escolha qual MPCD traseiro usar
-- ============================================================
-- Por padrao, o mod usa o MPCD_RRIGHT (o menos usado, na experiencia
-- de quem criou o mod). Se voce (ou seu WSO) preferir usar o
-- MPCD_RLEFT para essa funcao, mude a linha abaixo para "RLEFT".
--
-- IMPORTANTE: a etiqueta ("tag") do MPCD_RLEFT usada em WSO_PROFILES
-- abaixo ("MPCDL") e uma SUPOSICAO, seguindo o mesmo padrao de nomes
-- do MPCD_RRIGHT ("MPCDR") - ainda precisa ser confirmada por teste
-- antes de usar essa opcao com confianca (ver metodologia de
-- descoberta que usamos antes, com list_indication).
local WSO_DISPLAY_CHOICE = "RRIGHT"  -- "RRIGHT" (padrao) ou "RLEFT"

local WSO_DISPLAY_PROFILES = {
	RRIGHT = { device = 40, tag = "MPCDR" },  -- confirmado por teste
	RLEFT  = { device = 37, tag = "MPCDL" },  -- device confirmado pelo usuario; tag a confirmar
}

local WSO_DISPLAY = WSO_DISPLAY_PROFILES[WSO_DISPLAY_CHOICE]
if WSO_DISPLAY == nil then
	log.write("EMIS_LMT_MOD", log.ERROR, "WSO_DISPLAY_CHOICE invalido: " .. tostring(WSO_DISPLAY_CHOICE) .. " - usando RRIGHT")
	WSO_DISPLAY = WSO_DISPLAY_PROFILES.RRIGHT
end

local MPCDR_DEVICE_INDEX = WSO_DISPLAY.device
local MPCD_SELF_TAG = WSO_DISPLAY.tag

local HOLD_TIME = 0.15   -- tempo "segurando" o clique (confirmado necessario)
local GAP_AFTER = 0.30   -- tempo de espera apos soltar, antes do proximo clique

-- ===== Ponte pro Hook (arquivo de estado) =====
-- Export.lua nao tem acesso a "net"/dostring_in, entao escrevemos um
-- arquivo simples que um script separado (em Scripts/Hooks/) fica lendo,
-- e que TEM acesso a net.dostring_in pra mandar a imagem de verdade.
local STATE_FILE = lfs.writedir() .. "Scripts/EMIS_MOD_state.txt"

local function writeEmisState(isActive)
	local ok, err = pcall(function()
		local f = io.open(STATE_FILE, "w")
		if f then
			f:write(isActive and "1" or "0")
			f:close()
		end
	end)
	if not ok then
		log.write("EMIS_LMT_MOD", log.ERROR, "Falha ao escrever arquivo de estado: " .. tostring(err))
	end
end

local PAGE_FINGERPRINTS = {
	{name="ADI",  marker="ADI_Indicator_Begins"},
	{name="ARMT", marker="PACS_PB01_LABEL"},
	{name="HSI",  marker="HSI_Indicator_Begins"},
	{name="TF",   marker="TFR_PB1"},
	{name="TSD",  marker="TSD_MAP_RENDER"},
	{name="TPOD", marker="NF_Video_Open"},
	{name="TEWS", marker="TEWS_CENTER"},
}

-- ===== Fila de comandos temporizada (encadeada) =====
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
			log.write("EMIS_LMT_MOD", log.ERROR, "Erro executando item da fila: " .. tostring(err))
		end
		if #CommandQueue > 0 then
			QueueNextTime = t + CommandQueue[1].delay
		else
			QueueNextTime = nil
		end
	end
end

-- ===== Estado do mod =====
local EMIS = {
	active         = false,   -- EMIS LMT ligado/desligado
	tfLpiOn        = false,   -- estado LOGICO do LPI, independente da tela
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
	log.write("EMIS_LMT_MOD", log.INFO, "EMIS_LMT_Export.lua (v4 - hold real) iniciado")
end

function LuaExportStop()
	if PrevExportStop then PrevExportStop() end
end

local function sendCommand(deviceIndex, command, value)
	local okDev, dev = pcall(GetDevice, deviceIndex)
	if not okDev or dev == nil then
		log.write("EMIS_LMT_MOD", log.ERROR, string.format(
			"GetDevice(%d) falhou ao enviar comando %d", deviceIndex, command))
		return false
	end
	local okCall, err = pcall(function()
		dev:performClickableAction(command, value)
	end)
	if not okCall then
		log.write("EMIS_LMT_MOD", log.ERROR, string.format(
			"performClickableAction dev=%d cmd=%d falhou: %s", deviceIndex, command, tostring(err)))
		return false
	end
	return true
end

-- Envia o comando e AGENDA ate 4 conferencias seguidas (a cada 0.3s): se o
-- argumento nao tiver mudado pro valor esperado, reenvia de novo. Alguns
-- comandos (constatado experimentalmente) precisam de varias tentativas
-- pra "pegar", dependendo do contexto de quem disparou o comando.
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
					"%s nao confirmou (valor=%s, esperado=%s) - reenviando (restam %d tentativas)",
					tostring(label), tostring(actual), tostring(expectedValue), attemptsLeft - 1))
				sendCommandVerified(deviceIndex, command, argNumber, expectedValue, label, attemptsLeft - 1)
			else
				log.write("EMIS_LMT_MOD", log.ERROR, string.format(
					"%s: esgotou tentativas, nao foi possivel confirmar (valor=%s, esperado=%s)",
					tostring(label), tostring(actual), tostring(expectedValue)))
			end
		else
			log.write("EMIS_LMT_MOD", log.INFO, label .. ": confirmado OK")
		end
	end)
end

-- ===== Alternancia pro switch do ICS (default_2_position_tumb_animated) =====
-- Diferente do radar/JTIDS (multiposition_switch, aceita "definir o
-- valor X" direto), esse switch de 2 posicoes parece funcionar como
-- um CLIQUE de alternancia: mandar 1.0 alterna o estado atual, mandar
-- 0.0 nao gera clique nenhum (confirmado por teste: OFF sempre falhava,
-- restaurar sempre funcionava - os dois mandavam valores diferentes,
-- mas só o que mandava 1.0 realmente clicava). Entao: primeiro lemos o
-- estado atual, e SO clicamos (sempre com 1.0) se precisar mudar.
local function setIcsTarget(targetValue, label, attemptsLeft)
	attemptsLeft = attemptsLeft or 2
	local d0 = GetDevice(0)
	local current = d0 and d0:get_argument_value(ICS_ARG)
	if current == nil then
		log.write("EMIS_LMT_MOD", log.ERROR, label .. ": nao foi possivel ler o estado atual do ICS")
		return
	end

	if math.abs(current - targetValue) <= 0.05 then
		log.write("EMIS_LMT_MOD", log.INFO, label .. ": ja estava no estado certo (" .. tostring(current) .. "), nenhum clique necessario")
		return
	end

	sendCommand(ICS_DEVICE, ICS_CMD, 1.0)  -- sempre 1.0 = clique de alternancia

	queuePush(0.3, function()
		local d0b = GetDevice(0)
		local actual = d0b and d0b:get_argument_value(ICS_ARG)
		if actual ~= nil and math.abs(actual - targetValue) <= 0.05 then
			log.write("EMIS_LMT_MOD", log.INFO, label .. ": confirmado OK (via clique de alternancia)")
		else
			if attemptsLeft > 1 then
				log.write("EMIS_LMT_MOD", log.INFO, label .. ": nao confirmou apos o clique - tentando de novo")
				setIcsTarget(targetValue, label, attemptsLeft - 1)
			else
				log.write("EMIS_LMT_MOD", log.ERROR, label .. ": esgotou tentativas (valor=" .. tostring(actual) .. ")")
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

-- Retorna um dos nomes conhecidos (ADI/ARMT/HSI/TF/TSD/TPOD/TEWS),
-- "MENU" (especificamente M1), "UNKNOWN" (achou o MPCDR mas a tela
-- nao bate com nada conhecido - provavelmente M2/M3), ou "NOREAD"
-- (nao achou o MPCDR em lugar nenhum - ninguem no WSO pra renderizar).
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

-- Clique encadeado: pressiona AGORA, solta apos HOLD_TIME, e so entao
-- (apos GAP_AFTER) chama onDone. Cada etapa so enfileira a proxima
-- quando a anterior termina - evita bug de ordem na fila.
local function chainClick(pbNumber, onDone)
	log.write("EMIS_LMT_MOD", log.INFO, "Clique PB" .. string.format("%02d", pbNumber) .. " (hold)")
	pressButton(pbNumber)
	queuePush(HOLD_TIME, function()
		releaseButton(pbNumber)
		queuePush(GAP_AFTER, function()
			if onDone then onDone() end
		end)
	end)
end

-- Navega ate a pagina TF e aperta o botao final (targetPb: PB_TF_LPI ou
-- PB_TF_NORM). Funciona a partir de qualquer tela.
local function goToTfAndPress(targetPb, attemptsLeft)
	attemptsLeft = attemptsLeft or 3
	local current = identifyCurrentPage()
	log.write("EMIS_LMT_MOD", log.INFO, "goToTfAndPress: pagina atual = " .. tostring(current))

	if current == "TF" then
		chainClick(targetPb, function()
			log.write("EMIS_LMT_MOD", log.INFO, "Concluido: PB" .. targetPb .. " enviado direto no TF")
		end)
		return
	end

	if current == "MENU" then
		chainClick(PB_TF, function()
			chainClick(targetPb, function()
				log.write("EMIS_LMT_MOD", log.INFO, "Concluido: M1 -> TF -> PB" .. targetPb)
			end)
		end)
		return
	end

	if current == "NOREAD" then
		-- Ninguem no WSO pra confirmar - as cegas, 1 unica tentativa,
		-- assumindo o caso mais comum (tela de funcao, nao M2/M3).
		chainClick(PB_MENU_RETURN, function()
			chainClick(PB_TF, function()
				chainClick(targetPb, function()
					log.write("EMIS_LMT_MOD", log.INFO, "Concluido (as cegas): PB11 -> PB4 -> PB" .. targetPb)
				end)
			end)
		end)
		return
	end

	-- current == "UNKNOWN": achamos o MPCDR mas a tela nao bate com
	-- nada conhecido (provavelmente M2 ou M3). Da pra verificar e
	-- repetir se precisar.
	if attemptsLeft <= 0 then
		log.write("EMIS_LMT_MOD", log.ERROR, "goToTfAndPress: esgotou tentativas, desistindo")
		return
	end

	chainClick(PB_MENU_RETURN, function()
		local newState = identifyCurrentPage()
		log.write("EMIS_LMT_MOD", log.INFO, "Apos PB11: " .. tostring(newState))
		if newState == "MENU" then
			chainClick(PB_TF, function()
				chainClick(targetPb, function()
					log.write("EMIS_LMT_MOD", log.INFO, "Concluido: X -> M1 -> TF -> PB" .. targetPb)
				end)
			end)
		elseif newState == "TF" then
			chainClick(targetPb, function()
				log.write("EMIS_LMT_MOD", log.INFO, "Concluido: X -> TF direto -> PB" .. targetPb)
			end)
		else
			-- ainda nao chegou (M2/M3 ou NOREAD momentaneo) - tenta de novo
			goToTfAndPress(targetPb, attemptsLeft - 1)
		end
	end)
end

local function activateEmisLmt(d0)
	EMIS.savedRadarArg = d0:get_argument_value(471)
	EMIS.savedJtidsArg = d0:get_argument_value(476)
	EMIS.savedIcsArg   = d0:get_argument_value(ICS_ARG)

	writeEmisState(true)

	queueClear()
	queuePush(0.0, function() sendCommandVerified(3, RADAR_CMD, 471, RADAR_STBY, "Radar->STBY") end)
	queuePush(0.15, function() sendCommandVerified(1, JTIDS_CMD, 476, JTIDS_OFF, "JTIDS->OFF") end)
	queuePush(0.15, function() setIcsTarget(ICS_OFF_VALUE, "ICS->OFF") end)

	queuePush(0.3, function()
		EMIS.tfLpiOn = true
		goToTfAndPress(PB_TF_LPI, 3)
	end)

	log.write("EMIS_LMT_MOD", log.INFO, string.format(
		"EMIS LMT ATIVADO. Radar era %s, JTIDS era %s, ICS era %s",
		tostring(EMIS.savedRadarArg), tostring(EMIS.savedJtidsArg), tostring(EMIS.savedIcsArg)))
end

local function deactivateEmisLmt(d0)
	writeEmisState(false)

	queueClear()

	if EMIS.savedRadarArg ~= nil then
		local radarValue = EMIS.savedRadarArg
		queuePush(0.0, function() sendCommandVerified(3, RADAR_CMD, 471, radarValue, "Radar->restaurar") end)
	end
	if EMIS.savedJtidsArg ~= nil then
		local jtidsValue = EMIS.savedJtidsArg
		queuePush(0.15, function() sendCommandVerified(1, JTIDS_CMD, 476, jtidsValue, "JTIDS->restaurar") end)
	end
	if EMIS.savedIcsArg ~= nil then
		local icsValue = EMIS.savedIcsArg
		queuePush(0.15, function() setIcsTarget(icsValue, "ICS->restaurar") end)
	end

	queuePush(0.3, function()
		EMIS.tfLpiOn = false
		goToTfAndPress(PB_TF_NORM, 3)
	end)

	log.write("EMIS_LMT_MOD", log.INFO, "EMIS LMT DESATIVADO. Restaurando sistemas.")

	EMIS.savedRadarArg = nil
	EMIS.savedJtidsArg = nil
	EMIS.savedIcsArg = nil
end

-- ===== Relay do WSO pro botao fisico do piloto =====
-- Confirmado por teste: GetDevice(57) = UFCCTRL_FRONT, comando 3018 =
-- UFC_EMIS_LMT. O radar so aceita STBY de forma confiavel quando o
-- clique "vem" do PTN_287 de verdade - entao, em vez de o WSO acionar
-- os sistemas diretamente, ele "aperta" o botao do piloto por fora, e
-- deixamos nosso proprio monitoramento de arg287 detectar isso como
-- se fosse um clique real do piloto (caminho ja comprovado confiavel).
local UFC_FRONT_DEVICE = 57
local UFC_EMIS_CMD = 3018

local function relayRearToFront()
	log.write("EMIS_LMT_MOD", log.INFO, "WSO acionou - retransmitindo pro botao do piloto (PTN_287)")
	sendCommand(UFC_FRONT_DEVICE, UFC_EMIS_CMD, 1.0)
	-- nao precisa de "soltar": o botao tem retorno automatico proprio
	-- (mesmo comportamento ja observado desde o inicio da investigacao)
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

	-- Clique do WSO: so retransmite pro piloto, nao ativa nada direto.
	-- Usa o MESMO cooldown, pra nao retransmitir varias vezes por causa
	-- de tremulacao no argumento do botao do WSO.
	if clickedRear then
		if EMIS.lastToggleTime == nil or (t - EMIS.lastToggleTime) >= TOGGLE_COOLDOWN then
			EMIS.lastToggleTime = t
			relayRearToFront()
		end
		queueProcess(t)
		return
	end

	if clickedFront then
		if EMIS.lastToggleTime ~= nil and (t - EMIS.lastToggleTime) < TOGGLE_COOLDOWN then
			log.write("EMIS_LMT_MOD", log.INFO, "Clique ignorado (cooldown anti-tremulacao ativo)")
			queueProcess(t)
			return
		end
		EMIS.lastToggleTime = t

		EMIS.active = not EMIS.active
		if EMIS.active then
			log.write("EMIS_LMT_MOD", log.INFO, "EMIS LMT ACIONADO (PTN_287, direto ou via relay do WSO)")
			activateEmisLmt(d0)
		else
			log.write("EMIS_LMT_MOD", log.INFO, "EMIS LMT DESACIONADO (PTN_287, direto ou via relay do WSO)")
			deactivateEmisLmt(d0)
		end
	end

	queueProcess(t)
end

function LuaExportActivityNextEvent(t)
	local tNext = t + 0.05

	local ok, err = pcall(emisTick, t)
	if not ok then
		log.write("EMIS_LMT_MOD", log.ERROR, "emisTick erro: " .. tostring(err))
	end

	if PrevExportActivity then
		pcall(PrevExportActivity, t)
	end

	return tNext
end
