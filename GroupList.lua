-- GroupList.lua

-- Defini en premier : OnSizeChanged peut se declencher pendant le chargement,
-- avant que minimap.lua soit execute.
function GetColumnEnabled(key)
    if GroupListDB and GroupListDB.columns and GroupListDB.columns[key] ~= nil then
        return GroupListDB.columns[key]
    end
    -- Colonnes combat activees par defaut (temporaire pour tests)
    if key == "dmg" or key == "heal" or key == "int" or key == "dtk" then
        return true
    end
    return true
end

-- Positions des colonnes
local CONTENT_H    = 400
local COL_NAME_END = 155  -- x ou commencent les colonnes optionnelles
local COL_PAD      =   8  -- marge gauche texte
local GRIP_SIZE    =  16  -- taille du grip

-- Definition des colonnes optionnelles (ordre et largeur fixes)
local COL_DEFS = {
    { key = "ilv",   w = 50 },
    { key = "score", w = 50 },
    { key = "dmg",   w = 65 },
    { key = "heal",  w = 65 },
    { key = "int",   w = 65 },
    { key = "dtk",   w = 75 },
}

-- Calcule les positions X de chaque colonne selon celles qui sont activees.
-- Les colonnes desactivees sont sautees : les suivantes se serrent a gauche.
-- La position stockee pour une colonne desactivee est celle qu'elle reprendrait si reactivee.
local function ComputeColPositions()
    local pos = {}
    local x = COL_NAME_END
    for _, col in ipairs(COL_DEFS) do
        pos[col.key] = x
        if GetColumnEnabled(col.key) then x = x + col.w end
    end
    pos._width = x
    return pos
end

-- ─── Frame principale ─────────────────────────────────────
local frame = CreateFrame("Frame", "GroupListFrame", UIParent, "BackdropTemplate")
frame:SetSize(310, 200)
frame:SetPoint("CENTER", UIParent, "CENTER")
frame:SetMovable(true)
frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton")
frame:SetScript("OnDragStart", frame.StartMoving)
frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
frame:SetResizable(true)
frame:SetResizeBounds(120, 80)
frame:SetBackdrop({
    bgFile   = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    edgeSize = 12,
    insets   = { left=3, right=3, top=3, bottom=3 },
})
frame:SetBackdropColor(0, 0, 0, 0.7)
frame:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)

-- ─── Titre ────────────────────────────────────────────────
local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
title:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -8)
title:SetText("Groupe")
title:SetTextColor(1, 0.82, 0)

-- ─── En-tetes colonnes (dans le content, pas la frame) ────
-- Les en-tetes seront dans le content pour scroller avec les donnees

-- ─── Separateur ───────────────────────────────────────────
local sep = frame:CreateTexture(nil, "ARTWORK")
sep:SetColorTexture(0.4, 0.4, 0.4, 0.5)
sep:SetPoint("TOPLEFT",  frame, "TOPLEFT",  6, -34)
sep:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -6, -34)
sep:SetHeight(1)

-- ─── Grip resize (coin bas-gauche) ────────────────────────
-- On place le grip dans le coin, la pointe vers le bas-gauche.
-- La texture native WoW pointe vers le bas-droit,
-- on la retourne horizontalement via SetTexCoord.
local grip = CreateFrame("Button", nil, frame)
grip:SetSize(GRIP_SIZE, GRIP_SIZE)
grip:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
grip:SetFrameLevel(frame:GetFrameLevel() + 10)

local gripTex = grip:CreateTexture(nil, "OVERLAY")
gripTex:SetAllPoints(grip)
gripTex:SetTexture("Interface/ChatFrame/UI-ChatIM-SizeGrabber-Up")
-- Miroir horizontal : inverse U gauche<->droite pour pointer bas-gauche
gripTex:SetTexCoord(1, 0, 0, 1)

local gripHL = grip:CreateTexture(nil, "HIGHLIGHT")
gripHL:SetAllPoints(grip)
gripHL:SetTexture("Interface/ChatFrame/UI-ChatIM-SizeGrabber-Highlight")
gripHL:SetTexCoord(1, 0, 0, 1)

grip:SetScript("OnMouseDown", function(self, button)
    if button == "LeftButton" then
        frame:StartSizing("BOTTOMLEFT")
    end
end)
grip:SetScript("OnMouseUp", function()
    frame:StopMovingOrSizing()
end)

-- ─── Cache inspect + broadcast ──────────────────────────
local ilvCache = {}          -- [guid] = ilv (calcule via inspect, approximatif)
local broadcastCache = {}    -- [guid] = ilv (auto-reporte via addon message = valeur exacte)
local inspectQueue = {}      -- liste de units a inspecter
local inspectInProgress = false
local inspectGeneration = 0
local INSPECT_DELAY = 1.5    -- secondes entre chaque inspection
local combatCleared = false  -- true = colonnes combat masquees jusqu'au prochain combat
-- Forward declarations (definis dans la section communication plus bas)
local BroadcastMyIlv
local RequestGroupIlv


local function FormatNum(n)
    n = math.floor(n)
    if n >= 1000000000 then return string.format("%.1fG", n / 1000000000)
    elseif n >= 1000000 then return string.format("%.1fM", n / 1000000)
    elseif n >= 1000    then return string.format("%.0fK", n / 1000)
    else return tostring(n) end
end

local function FormatCombatCell(val, total)
    if not val or val == 0 then return "-" end
    local pct = total > 0 and math.floor(val / total * 100 + 0.5) or 0
    return FormatNum(val) .. " " .. pct .. "%"
end

local function ComputeContentWidth()
    return math.max(ComputeColPositions()._width + 10, COL_NAME_END + 50)
end

-- ─── Refresh manuel ──────────────────────────────────────
local function ManualRefresh()
    ilvCache = {}
    broadcastCache = {}
    inspectQueue = {}
    inspectInProgress = false
    UpdateGroupList()
    C_Timer.After(0.5, function()
        BroadcastMyIlv()
        RequestGroupIlv()
    end)
end

-- ─── Bouton reduire / agrandir ────────────────────────────
local collapsed = false

local btn = CreateFrame("Button", nil, frame)
btn:SetSize(18, 18)
btn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)

local btnText = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
btnText:SetAllPoints(btn)
btnText:SetText("-")
btn:SetFontString(btnText)

btn:SetScript("OnClick", function()
    collapsed = not collapsed
    if collapsed then
        frame:SetHeight(24)
        btnText:SetText("+")
    else
        frame:SetHeight(200)
        btnText:SetText("-")
        UpdateGroupList()
    end
end)

-- Bouton refresh (icone fleche circulaire)
local refreshBtn = CreateFrame("Button", nil, frame)
refreshBtn:SetSize(18, 18)
refreshBtn:SetPoint("TOPRIGHT", btn, "TOPLEFT", -2, 0)

local refreshTex = refreshBtn:CreateTexture(nil, "ARTWORK")
refreshTex:SetAllPoints(refreshBtn)
refreshTex:SetTexture("Interface/Buttons/UI-RefreshButton")

local refreshHL = refreshBtn:CreateTexture(nil, "HIGHLIGHT")
refreshHL:SetAllPoints(refreshBtn)
refreshHL:SetTexture("Interface/Buttons/UI-RefreshButton")
refreshHL:SetVertexColor(1, 1, 0.5)

refreshBtn:SetScript("OnClick", function()
    ManualRefresh()
end)

refreshBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:SetText("Rafraichir les donnees", 1, 1, 1)
    GameTooltip:Show()
end)
refreshBtn:SetScript("OnLeave", function()
    GameTooltip:Hide()
end)

-- Bouton poubelle (effacer donnees combat Details!)
local trashBtn = CreateFrame("Button", nil, frame)
trashBtn:SetSize(18, 18)
trashBtn:SetPoint("TOPRIGHT", refreshBtn, "TOPLEFT", -2, 0)

local trashTex = trashBtn:CreateTexture(nil, "ARTWORK")
local trashHL  = trashBtn:CreateTexture(nil, "HIGHLIGHT")

-- Cherche une icone poubelle dans l'atlas WoW
local trashAtlasCandidates = {
    "transmog-icon-remove",
    "voidstorage-icon-deposit",
    "crafting-icon-recraft",
    "auctionhouse-icon-removeitem",
}
local trashAtlasFound = false
for _, name in ipairs(trashAtlasCandidates) do
    if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name) then
        trashTex:SetAtlas(name, false)
        trashTex:SetAllPoints(trashBtn)
        trashTex:SetVertexColor(1, 0.85, 0)
        trashHL:SetAtlas(name, false)
        trashHL:SetAllPoints(trashBtn)
        trashHL:SetVertexColor(1, 1, 0.5)
        trashAtlasFound = true
        break
    end
end
if not trashAtlasFound then
    -- Fallback : croix jaune, agrandie pour matcher visuellement le bouton refresh
    trashTex:SetTexture("Interface/Buttons/UI-Panel-MinimizeButton-Up")
    trashTex:SetSize(26, 26)
    trashTex:SetPoint("CENTER", trashBtn, "CENTER")
    trashTex:SetVertexColor(1, 0.85, 0)
    trashHL:SetTexture("Interface/Buttons/UI-Panel-MinimizeButton-Up")
    trashHL:SetSize(26, 26)
    trashHL:SetPoint("CENTER", trashBtn, "CENTER")
    trashHL:SetVertexColor(1, 1, 0.5)
end

trashBtn:SetScript("OnClick", function()
    combatCleared = true
    UpdateGroupList()
end)

trashBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:SetText("Effacer les donnees de combat", 1, 1, 1)
    GameTooltip:Show()
end)
trashBtn:SetScript("OnLeave", function()
    GameTooltip:Hide()
end)

-- ─── ScrollFrame horizontal + vertical ────────────────────
-- Container qui occupe toute la zone sous les en-tetes
local scrollArea = CreateFrame("Frame", nil, frame)
scrollArea:SetPoint("TOPLEFT",     frame, "TOPLEFT",   4, -38)
scrollArea:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -4, 4)

-- Scrollbar verticale
local vScroll = CreateFrame("ScrollFrame", nil, scrollArea, "UIPanelScrollFrameTemplate")
vScroll:SetPoint("TOPLEFT",     scrollArea, "TOPLEFT",   0,   0)
vScroll:SetPoint("BOTTOMRIGHT", scrollArea, "BOTTOMRIGHT", -18, 18)

-- Scrollbar horizontale manuelle (sans template pour eviter SetVerticalScroll)
local hScroll = CreateFrame("Slider", "GroupListHScroll", scrollArea)
hScroll:SetOrientation("HORIZONTAL")
hScroll:SetPoint("BOTTOMLEFT",  scrollArea, "BOTTOMLEFT",  GRIP_SIZE, 0)
hScroll:SetPoint("BOTTOMRIGHT", scrollArea, "BOTTOMRIGHT", -18, 0)
hScroll:SetHeight(14)
hScroll:SetMinMaxValues(0, 0)
hScroll:SetValue(0)
hScroll:SetValueStep(10)
hScroll:SetObeyStepOnDrag(true)

-- Fond de la scrollbar
local hScrollBg = hScroll:CreateTexture(nil, "BACKGROUND")
hScrollBg:SetAllPoints(hScroll)
hScrollBg:SetColorTexture(0.1, 0.1, 0.1, 0.8)

-- Thumb (curseur)
local hThumb = hScroll:CreateTexture(nil, "OVERLAY")
hThumb:SetSize(32, 12)
hThumb:SetColorTexture(0.5, 0.5, 0.5, 0.8)
hScroll:SetThumbTexture(hThumb)

-- Content (largeur fixe = toutes colonnes)
local content = CreateFrame("Frame", nil, vScroll)
content:SetSize(COL_NAME_END + 50, CONTENT_H)
vScroll:SetScrollChild(content)

-- Decalage horizontal du content selon slider
hScroll:SetScript("OnValueChanged", function(self, val)
    content:SetPoint("TOPLEFT", vScroll, "TOPLEFT", -val, 0)
end)
content:SetPoint("TOPLEFT", vScroll, "TOPLEFT", 0, 0)

-- Met a jour la plage du slider horizontal quand la frame change de taille
local function UpdateHScroll()
    local vw = vScroll:GetWidth()
    local overflow = content:GetWidth() - vw
    if overflow > 0 then
        hScroll:SetMinMaxValues(0, overflow)
        hScroll:Show()
    else
        hScroll:SetMinMaxValues(0, 0)
        hScroll:SetValue(0)
        hScroll:Hide()
    end
end

frame:SetScript("OnSizeChanged", function()
    UpdateHScroll()
    if not collapsed then UpdateGroupList() end
end)

-- ─── En-tetes dans le content ────────────────────────────
local hdrName = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
hdrName:SetPoint("TOPLEFT", content, "TOPLEFT", COL_PAD, -2)
hdrName:SetText("Nom")
hdrName:SetTextColor(0.7, 0.7, 0.7)

local hdrIlv = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
hdrIlv:SetText("iLv")
hdrIlv:SetTextColor(0.7, 0.7, 0.7)

local hdrScore = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
hdrScore:SetText("Cote M+")
hdrScore:SetTextColor(0.7, 0.7, 0.7)

local hdrDmg = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
hdrDmg:SetText("Dmg")
hdrDmg:SetTextColor(1.0, 0.5, 0.3)

local hdrHeal = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
hdrHeal:SetText("Soins")
hdrHeal:SetTextColor(0.3, 1.0, 0.3)

local hdrInt = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
hdrInt:SetText("Int")
hdrInt:SetTextColor(0.3, 0.7, 1.0)

local hdrDtk = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
hdrDtk:SetText("DmgSub")
hdrDtk:SetTextColor(1.0, 0.3, 0.3)

-- ─── Cache iLv par GUID ──────────────────────────────────

local function GetSlotIlv(unit, slot)
    local link = GetInventoryItemLink(unit, slot)
    if not link then return nil end

    -- Methode 1 : iLv effectif depuis le lien (bonus IDs — crests, crafted)
    if C_Item and C_Item.GetDetailedItemLevelInfo then
        local ilvl = C_Item.GetDetailedItemLevelInfo(link)
        if ilvl and ilvl > 0 then return ilvl end
    end

    -- Methode 2 : tooltip depuis le lien (independant du unit/slot, lit les bonus IDs)
    -- NB: GetInventoryItem(unit, slot) ne fonctionne pas pour les joueurs inspectes sur Midnight
    if C_TooltipInfo and C_TooltipInfo.GetHyperlink then
        local data = C_TooltipInfo.GetHyperlink(link)
        if data and data.lines then
            for _, line in ipairs(data.lines) do
                if line.itemLevel and line.itemLevel > 0 then
                    return line.itemLevel
                end
            end
        end
    end

    -- Fallback : iLv de base sans upgrades
    local _, _, _, baseIlv = GetItemInfo(link)
    if baseIlv and baseIlv > 0 then return baseIlv end

    return nil
end

-- Slots vides = iLv minimum des slots equipes, diviseur fixe 16 (logique WoW)
local function CalcIlvFromSlots(unit)
    local total, count, minIlv = 0, 0, 9999
    for slot = 1, 17 do
        if slot ~= 4 then
            local ilv = GetSlotIlv(unit, slot)
            if ilv and ilv > 0 then
                total = total + ilv
                count = count + 1
                if ilv < minIlv then minIlv = ilv end
            end
        end
    end
    if count == 0 then return nil end
    local missing = 16 - count
    if missing > 0 and minIlv < 9999 then
        total = total + (minIlv * missing)
    end
    return math.floor(total / 16 + 0.5)
end

-- Traite la file d'inspection une unite a la fois
local function ProcessInspectQueue()
    if #inspectQueue == 0 then
        inspectInProgress = false
        return
    end
    inspectInProgress = true
    local unit = table.remove(inspectQueue, 1)
    if UnitExists(unit) and UnitIsConnected(unit) then
        inspectGeneration = inspectGeneration + 1
        local gen = inspectGeneration
        ClearInspectPlayer()
        NotifyInspect(unit)
        -- Si INSPECT_READY ne se declenche pas (hors portee, etc.), avancer la file
        C_Timer.After(5, function()
            if gen == inspectGeneration then
                ProcessInspectQueue()
            end
        end)
    else
        -- Joueur deconnecte ou inexistant : passer au suivant
        C_Timer.After(INSPECT_DELAY, ProcessInspectQueue)
    end
end

-- Quand l'inspection est prete, on lit l'iLv
local inspectFrame = CreateFrame("Frame")
inspectFrame:RegisterEvent("INSPECT_READY")
inspectFrame:SetScript("OnEvent", function(self, event, guid)
    inspectGeneration = inspectGeneration + 1
    -- Chercher l'unit correspondant au GUID
    local unit = nil
    local unitType = IsInRaid() and "raid" or "party"
    local count = GetNumGroupMembers()
    for i = 1, count do
        local u = unitType..i
        if UnitGUID(u) == guid then
            unit = u
            break
        end
    end
    if unit then
        local capturedUnit = unit
        local capturedGuid = guid
        C_Timer.After(0.5, function()
            -- C_PaperDollInfo.GetInspectItemLevel retourne l'iLv exact (upgrades inclus),
            -- equivalent de GetAverageItemLevel() pour le joueur local
            local ilv
            if C_PaperDollInfo and C_PaperDollInfo.GetInspectItemLevel then
                local v = C_PaperDollInfo.GetInspectItemLevel(capturedUnit)
                if v and v > 0 then ilv = math.floor(v) end
            end
            -- Fallback si l'API n'est pas disponible
            if not ilv then
                ilv = CalcIlvFromSlots(capturedUnit)
            end
            if ilv then
                ilvCache[capturedGuid] = ilv
                UpdateGroupList()
            end
        end)
    end
    -- Passer au suivant dans la file
    C_Timer.After(INSPECT_DELAY, ProcessInspectQueue)
end)

local function QueueInspect(unit)
    if UnitIsUnit(unit, "player") then return end
    -- Eviter les doublons dans la file
    for _, u in ipairs(inspectQueue) do
        if u == unit then return end
    end
    table.insert(inspectQueue, unit)
    if not inspectInProgress then
        ProcessInspectQueue()
    end
end

-- ─── API iLv ──────────────────────────────────────────────
local function GetUnitItemLevel(unit)
    -- Joueur local : API native (toujours exact)
    if UnitIsUnit(unit, "player") then
        local _, equipped = GetAverageItemLevel()
        if equipped and equipped > 0 then return math.floor(equipped) end
    end

    local guid = UnitGUID(unit)

    -- Broadcast addon (iLv exact auto-reporte par le membre lui-meme)
    if guid and broadcastCache[guid] then
        return broadcastCache[guid]
    end

    -- Cache inspect (approximatif — iLv base si le membre n'a pas l'addon)
    if guid and ilvCache[guid] then
        return ilvCache[guid]
    end

    -- Lancer une inspection asynchrone
    QueueInspect(unit)
    return nil
end

-- ─── API Score M+ ─────────────────────────────────────────
local function GetUnitMythicScore(unit)
    -- Joueur local : API directe
    if UnitIsUnit(unit, "player") then
        if C_ChallengeMode and C_ChallengeMode.GetOverallDungeonScore then
            local s = C_ChallengeMode.GetOverallDungeonScore()
            if s and s > 0 then return s end
        end
        return nil
    end

    -- Autres joueurs : C_PlayerInfo.GetPlayerMythicPlusRatingSummary (Midnight 12.x)
    if C_PlayerInfo and C_PlayerInfo.GetPlayerMythicPlusRatingSummary then
        local guid = UnitGUID(unit)
        if guid then
            local summary = C_PlayerInfo.GetPlayerMythicPlusRatingSummary(unit)
            if summary and summary.currentSeasonScore and summary.currentSeasonScore > 0 then
                return summary.currentSeasonScore
            end
        end
    end

    -- Fallback : ancienne API (TWW / pre-Midnight)
    if C_ChallengeMode and C_ChallengeMode.GetDungeonScoreForPlayer then
        local s = C_ChallengeMode.GetDungeonScoreForPlayer(unit)
        if s and s > 0 then return s end
    end

    return nil
end

-- ─── Couleurs ─────────────────────────────────────────────
local function IlvColor(ilv)
    if not ilv then return 0.62, 0.62, 0.62 end
    if ilv >= 285 then return 1.00, 0.50, 0.00 end  -- Orange  (Mythique / top)
    if ilv >= 275 then return 0.64, 0.21, 0.93 end  -- Violet  (Epique)
    if ilv >= 260 then return 0.00, 0.44, 0.87 end  -- Bleu    (Rare)
    if ilv >= 220 then return 0.12, 1.00, 0.00 end  -- Vert    (Normal)
    return 0.62, 0.62, 0.62                          -- Gris    (Bas)
end

local function ScoreColor(score)
    if not score then return 0.62, 0.62, 0.62 end
    if score >= 3800 then return 1.00, 0.50, 0.00 end  -- Orange  (Elite)
    if score >= 3000 then return 0.64, 0.21, 0.93 end  -- Violet  (Epique)
    if score >= 2000 then return 0.00, 0.44, 0.87 end  -- Bleu    (Rare)
    if score >= 1000 then return 0.12, 1.00, 0.00 end  -- Vert    (Normal)
    return 0.62, 0.62, 0.62                             -- Gris    (Bas)
end

-- ─── Labels ───────────────────────────────────────────────
local nameLabels  = {}
local ilvLabels   = {}
local scoreLabels = {}
local dmgLabels   = {}
local healLabels  = {}
local intLabels   = {}
local dtkLabels   = {}
local ROW_H = 16
local ROW_START = -18  -- offset Y apres l'en-tete

-- Details! indexe les acteurs distants avec le suffixe "-Royaume" (nom
-- source du combat log) alors que UnitName() renvoie le nom seul pour les
-- membres du groupe sur un autre royaume connecte. On tente donc les deux.
local function GetDetailsActor(dc, container, m)
    if not dc then return nil end
    local a = dc:GetActor(container, m.name)
    if a then return a end
    if m.realm then
        return dc:GetActor(container, m.name .. "-" .. m.realm)
    end
    return nil
end

function UpdateGroupList()  -- global (appele depuis minimap.lua et ManualRefresh)
    if collapsed then return end

    for i in ipairs(nameLabels) do
        nameLabels[i]:Hide()
        ilvLabels[i]:Hide()
        if scoreLabels[i] then scoreLabels[i]:Hide() end
        if dmgLabels[i]   then dmgLabels[i]:Hide()   end
        if healLabels[i]  then healLabels[i]:Hide()  end
        if intLabels[i]   then intLabels[i]:Hide()   end
        if dtkLabels[i]   then dtkLabels[i]:Hide()   end
    end

    local members = {}
    local unit  = IsInRaid() and "raid" or "party"
    local count = GetNumGroupMembers()

    if count == 0 then
        tinsert(members, { name = (UnitName("player")), unit = "player" })
    else
        if not IsInRaid() then
            tinsert(members, { name = (UnitName("player")), unit = "player" })
        end
        for i = 1, count do
            local u    = unit..i
            local name, realm = UnitName(u)
            if name then
                tinsert(members, { name = name, realm = (realm ~= "" and realm) or nil, unit = u })
            end
        end
    end

    -- Adapter la hauteur + largeur du content
    content:SetHeight(math.max(CONTENT_H, ROW_H * (#members + 1) + 4))
    local colPos = ComputeColPositions()
    content:SetWidth(math.max(colPos._width + 10, COL_NAME_END + 50))

    -- Repositionner les en-tetes selon les colonnes activees
    hdrIlv:ClearAllPoints()
    hdrIlv:SetPoint("TOPLEFT", content, "TOPLEFT", colPos["ilv"], -2)
    hdrIlv:SetShown(GetColumnEnabled("ilv"))
    hdrScore:ClearAllPoints()
    hdrScore:SetPoint("TOPLEFT", content, "TOPLEFT", colPos["score"], -2)
    hdrScore:SetShown(GetColumnEnabled("score"))
    hdrDmg:ClearAllPoints()
    hdrDmg:SetPoint("TOPLEFT", content, "TOPLEFT", colPos["dmg"], -2)
    hdrDmg:SetShown(GetColumnEnabled("dmg"))
    hdrHeal:ClearAllPoints()
    hdrHeal:SetPoint("TOPLEFT", content, "TOPLEFT", colPos["heal"], -2)
    hdrHeal:SetShown(GetColumnEnabled("heal"))
    hdrInt:ClearAllPoints()
    hdrInt:SetPoint("TOPLEFT", content, "TOPLEFT", colPos["int"], -2)
    hdrInt:SetShown(GetColumnEnabled("int"))
    hdrDtk:ClearAllPoints()
    hdrDtk:SetPoint("TOPLEFT", content, "TOPLEFT", colPos["dtk"], -2)
    hdrDtk:SetShown(GetColumnEnabled("dtk"))

    -- Donnees Details! : container 1 = degats, container 2 = soins, container 4 = misc (interruptions)
    local dc = (not combatCleared) and Details and Details:GetCurrentCombat() or nil
    local totalDmg  = dc and dc:GetTotal(1) or 0
    local totalHeal = dc and dc:GetTotal(2) or 0
    local totalDtk  = 0
    local totalInt  = 0
    if dc then
        for _, m in ipairs(members) do
            local a1 = GetDetailsActor(dc, 1, m)
            local a4 = GetDetailsActor(dc, 4, m)
            if a1 then totalDtk = totalDtk + (a1.damage_taken or 0) end
            if a4 then totalInt = totalInt + math.floor(a4.interrupt or 0) end
        end
    end

    local showIlv  = GetColumnEnabled("ilv")
    local showScr  = GetColumnEnabled("score")
    local showDmg  = GetColumnEnabled("dmg")
    local showHeal = GetColumnEnabled("heal")
    local showInt  = GetColumnEnabled("int")
    local showDtk  = GetColumnEnabled("dtk")

    for i, m in ipairs(members) do
        local yOff = ROW_START - (i-1) * ROW_H
        local guid = UnitGUID(m.unit)
        local da1  = GetDetailsActor(dc, 1, m)
        local da2  = GetDetailsActor(dc, 2, m)
        local da4  = GetDetailsActor(dc, 4, m)

        -- Nom
        local nl = nameLabels[i]
        if not nl then
            nl = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            nl:SetWidth(COL_NAME_END - COL_PAD - 4)
            nl:SetJustifyH("LEFT")
            nl:SetNonSpaceWrap(false)
            nameLabels[i] = nl
        end
        nl:ClearAllPoints()
        nl:SetPoint("TOPLEFT", content, "TOPLEFT", COL_PAD, yOff)
        nl:SetText(m.name)
        nl:Show()

        -- iLv
        local il = ilvLabels[i]
        if not il then
            il = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            ilvLabels[i] = il
        end
        il:ClearAllPoints()
        il:SetPoint("TOPLEFT", content, "TOPLEFT", colPos["ilv"], yOff)
        local ilv = GetUnitItemLevel(m.unit)
        local r, g, b = IlvColor(ilv)
        il:SetTextColor(r, g, b)
        il:SetText(ilv and tostring(ilv) or "?")
        il:SetShown(showIlv)

        -- Score M+
        local sl = scoreLabels[i]
        if not sl then
            sl = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            scoreLabels[i] = sl
        end
        sl:ClearAllPoints()
        sl:SetPoint("TOPLEFT", content, "TOPLEFT", colPos["score"], yOff)
        local score = GetUnitMythicScore(m.unit)
        local sr, sg, sb = ScoreColor(score)
        sl:SetTextColor(sr, sg, sb)
        sl:SetText(score and tostring(score) or "-")
        sl:SetShown(showScr)

        -- Degats
        local dl = dmgLabels[i]
        if not dl then
            dl = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            dmgLabels[i] = dl
        end
        dl:ClearAllPoints()
        dl:SetPoint("TOPLEFT", content, "TOPLEFT", colPos["dmg"], yOff)
        dl:SetTextColor(1.0, 0.6, 0.3)
        dl:SetText(FormatCombatCell(da1 and da1.total, totalDmg))
        dl:SetShown(showDmg)

        -- Soins
        local hl = healLabels[i]
        if not hl then
            hl = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            healLabels[i] = hl
        end
        hl:ClearAllPoints()
        hl:SetPoint("TOPLEFT", content, "TOPLEFT", colPos["heal"], yOff)
        hl:SetTextColor(0.3, 1.0, 0.3)
        hl:SetText(FormatCombatCell(da2 and da2.total, totalHeal))
        hl:SetShown(showHeal)

        -- Interruptions
        local xl = intLabels[i]
        if not xl then
            xl = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            intLabels[i] = xl
        end
        xl:ClearAllPoints()
        xl:SetPoint("TOPLEFT", content, "TOPLEFT", colPos["int"], yOff)
        xl:SetTextColor(0.4, 0.8, 1.0)
        local intVal = da4 and math.floor(da4.interrupt or 0) or 0
        xl:SetText(FormatCombatCell(intVal > 0 and intVal or nil, totalInt))
        xl:SetShown(showInt)

        -- Degats subis
        local tkl = dtkLabels[i]
        if not tkl then
            tkl = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            dtkLabels[i] = tkl
        end
        tkl:ClearAllPoints()
        tkl:SetPoint("TOPLEFT", content, "TOPLEFT", colPos["dtk"], yOff)
        tkl:SetTextColor(1.0, 0.3, 0.3)
        tkl:SetText(FormatCombatCell(da1 and da1.damage_taken, totalDtk))
        tkl:SetShown(showDtk)
    end
    UpdateHScroll()
end


-- ─── Cache items ──────────────────────────────────────────
local refreshPending = false
local refreshFrame   = CreateFrame("Frame")
refreshFrame:SetScript("OnUpdate", function()
    if refreshPending then
        refreshPending = false
        UpdateGroupList()
    end
end)

-- ─── Sauvegarde position / taille ────────────────────────
local function SaveLayout()
    GroupListDB = GroupListDB or {}
    local point, _, relPoint, x, y = frame:GetPoint()
    GroupListDB.point        = point
    GroupListDB.relPoint     = relPoint
    GroupListDB.x            = x
    GroupListDB.y            = y
    GroupListDB.width        = frame:GetWidth()
    GroupListDB.height       = frame:GetHeight()
    GroupListDB.minimapAngle = minimapAngle
    GroupListDB.hidden       = not frame:IsShown()
end

local function RestoreLayout()
    if not GroupListDB then return end
    if GroupListDB.width  then frame:SetWidth(GroupListDB.width)   end
    if GroupListDB.height then frame:SetHeight(GroupListDB.height) end
    if GroupListDB.point  then
        frame:ClearAllPoints()
        frame:SetPoint(GroupListDB.point, UIParent, GroupListDB.relPoint, GroupListDB.x, GroupListDB.y)
    end
    if GroupListDB.minimapAngle then
        minimapAngle = GroupListDB.minimapAngle
        UpdateMinimapPos()
    end
    if GroupListDB.hidden then
        frame:Hide()
    end
    RefreshCheckboxes()
end

-- Sauvegarde apres drag ou resize
frame:HookScript("OnDragStop", SaveLayout)
grip:HookScript("OnMouseUp",   SaveLayout)

-- Commande slash /gl
SLASH_GROUPLIST1 = "/gl"
SlashCmdList["GROUPLIST"] = function(msg)
    local cmd = msg:lower()
    if cmd == "refresh" then
        ManualRefresh()
        print("|cff00ff00GroupList:|r Donnees rafraichies.")
    elseif cmd == "show" then
        frame:Show()
        GroupListDB = GroupListDB or {}
        GroupListDB.hidden = false
        UpdateGroupList()
    elseif cmd == "hide" then
        frame:Hide()
        GroupListDB = GroupListDB or {}
        GroupListDB.hidden = true
    else
        print("|cff00ff00GroupList:|r /gl refresh | /gl show | /gl hide")
    end
end

-- ─── Communication addon (partage iLv entre membres) ─────
-- Format message : "ILV:<ilv>:<guid>"  →  iLv exact auto-reporte
--                  "REQ_ILV"           →  demande de re-broadcast
local ADDON_PREFIX = "GroupList"
C_ChatInfo.RegisterAddonMessagePrefix(ADDON_PREFIX)

BroadcastMyIlv = function()
    local _, equipped = GetAverageItemLevel()
    if not equipped or equipped <= 0 then return end
    local ilv = math.floor(equipped)
    local guid = UnitGUID("player")
    local channel = IsInRaid() and "RAID" or (IsInGroup() and "PARTY" or nil)
    if channel then
        C_ChatInfo.SendAddonMessage(ADDON_PREFIX, "ILV:" .. ilv .. ":" .. guid, channel)
    end
end

RequestGroupIlv = function()
    local channel = IsInRaid() and "RAID" or (IsInGroup() and "PARTY" or nil)
    if channel then
        C_ChatInfo.SendAddonMessage(ADDON_PREFIX, "REQ_ILV", channel)
    end
end

local commsFrame = CreateFrame("Frame")
commsFrame:RegisterEvent("CHAT_MSG_ADDON")
commsFrame:SetScript("OnEvent", function(self, event, prefix, message)
    if prefix ~= ADDON_PREFIX then return end
    if message == "REQ_ILV" then
        -- Un membre demande les iLv : repondre avec un leger delai aleatoire pour eviter les floods
        C_Timer.After(math.random() * 2, BroadcastMyIlv)
        return
    end
    local ilv, senderGuid = message:match("^ILV:(%d+):(.+)$")
    if ilv and senderGuid then
        broadcastCache[senderGuid] = tonumber(ilv)
        UpdateGroupList()
    end
end)

-- ─── Evenements ───────────────────────────────────────────
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("GROUP_ROSTER_UPDATE")
frame:RegisterEvent("UNIT_CONNECTION")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
frame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        RestoreLayout()
        UpdateGroupList()
        C_Timer.After(2, function()
            BroadcastMyIlv()
            RequestGroupIlv()
        end)
    elseif event == "PLAYER_EQUIPMENT_CHANGED" then
        C_Timer.After(1, BroadcastMyIlv)
        C_Timer.After(1.3, function() UpdateGroupList() end)
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        refreshPending = true
    elseif event == "GROUP_ROSTER_UPDATE" then
        inspectQueue = {}
        inspectInProgress = false
        ilvCache = {}
        C_Timer.After(0.5, function()
            UpdateGroupList()
            BroadcastMyIlv()
            RequestGroupIlv()
        end)
    elseif event == "PLAYER_REGEN_ENABLED" then
        combatCleared = false
        C_Timer.After(0.5, function() UpdateGroupList() end)
    else
        C_Timer.After(0.3, function() UpdateGroupList() end)
    end
end)