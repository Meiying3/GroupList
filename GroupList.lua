-- GroupList.lua

-- Defini en premier : OnSizeChanged peut se declencher pendant le chargement,
-- avant que minimap.lua soit execute.
function GetColumnEnabled(key)
    if GroupListDB and GroupListDB.columns and GroupListDB.columns[key] ~= nil then
        return GroupListDB.columns[key]
    end
    return true
end

-- Largeur fixe du contenu (toutes colonnes visibles)
local CONTENT_W   = 280
local CONTENT_H   = 400
local COL_ILV_X   = 155  -- position X colonne iLv
local COL_SCR_X   = 205  -- position X colonne Score
local COL_PAD     =   8  -- marge gauche texte
local GRIP_SIZE   =  16  -- taille du grip

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

-- ─── Cache inspect ───────────────────────────────────────
local ilvCache = {}          -- [guid] = ilv
local inspectQueue = {}      -- liste de units a inspecter
local inspectInProgress = false
local INSPECT_DELAY = 1.5    -- secondes entre chaque inspection

-- ─── Refresh manuel ──────────────────────────────────────
local function ManualRefresh()
    ilvCache = {}
    inspectQueue = {}
    inspectInProgress = false
    UpdateGroupList()
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
content:SetSize(CONTENT_W, CONTENT_H)
vScroll:SetScrollChild(content)

-- Decalage horizontal du content selon slider
hScroll:SetScript("OnValueChanged", function(self, val)
    content:SetPoint("TOPLEFT", vScroll, "TOPLEFT", -val, 0)
end)
content:SetPoint("TOPLEFT", vScroll, "TOPLEFT", 0, 0)

-- Met a jour la plage du slider horizontal quand la frame change de taille
local function UpdateHScroll()
    local vw = vScroll:GetWidth()
    local overflow = CONTENT_W - vw
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
hdrIlv:SetPoint("TOPLEFT", content, "TOPLEFT", COL_ILV_X, -2)
hdrIlv:SetText("iLv")
hdrIlv:SetTextColor(0.7, 0.7, 0.7)

local hdrScore = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
hdrScore:SetPoint("TOPLEFT", content, "TOPLEFT", COL_SCR_X, -2)
hdrScore:SetText("Cote M+")
hdrScore:SetTextColor(0.7, 0.7, 0.7)

-- ─── Cache iLv par GUID ──────────────────────────────────

local function GetSlotIlv(unit, slot)
    local link = GetInventoryItemLink(unit, slot)
    if not link then return nil end

    -- Methode 1 : iLv effectif depuis le lien (inclut upgrades crests) — Midnight 12.x
    if C_Item and C_Item.GetDetailedItemLevelInfo then
        local ilvl = C_Item.GetDetailedItemLevelInfo(link)
        if ilvl and ilvl > 0 then return ilvl end
    end

    -- Methode 2 : tooltip structure C_TooltipInfo (fonctionne pour les joueurs inspectes)
    if C_TooltipInfo and C_TooltipInfo.GetInventoryItem then
        local data = C_TooltipInfo.GetInventoryItem(unit, slot)
        if data and data.lines then
            for _, line in ipairs(data.lines) do
                if line.type == Enum.TooltipDataLineType.ItemLevel and line.itemLevel then
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
        if CheckInteractDistance(unit, 1) then
            ClearInspectPlayer()
            NotifyInspect(unit)
        else
            -- Hors de portee : remettre en fin de file et reessayer
            table.insert(inspectQueue, unit)
            C_Timer.After(2, ProcessInspectQueue)
        end
    else
        -- Joueur deconnecte ou inexistant : passer au suivant
        C_Timer.After(INSPECT_DELAY, ProcessInspectQueue)
    end
end

-- Quand l'inspection est prete, on lit les slots
local inspectFrame = CreateFrame("Frame")
inspectFrame:RegisterEvent("INSPECT_READY")
inspectFrame:SetScript("OnEvent", function(self, event, guid)
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
        -- Attendre 0.5s que WoW finisse de recevoir tous les slots avant de lire
        local capturedUnit = unit
        local capturedGuid = guid
        C_Timer.After(0.5, function()
            local ilv = CalcIlvFromSlots(capturedUnit)
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
    -- Joueur local : API native
    if UnitIsUnit(unit, "player") then
        local _, equipped = GetAverageItemLevel()
        if equipped and equipped > 0 then return math.floor(equipped) end
    end

    local guid = UnitGUID(unit)

    -- Cache disponible
    if guid and ilvCache[guid] then
        return ilvCache[guid]
    end

    -- Lancer une inspection asynchrone (seul moyen fiable pour les autres joueurs)
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
local ROW_H = 16
local ROW_START = -18  -- offset Y apres l'en-tete

function UpdateGroupList()  -- global (appele depuis minimap.lua et ManualRefresh)
    if collapsed then return end

    for i in ipairs(nameLabels) do
        nameLabels[i]:Hide()
        ilvLabels[i]:Hide()
        if scoreLabels[i] then scoreLabels[i]:Hide() end
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
            local name = (UnitName(u))
            if name then tinsert(members, { name = name, unit = u }) end
        end
    end

    -- Adapter la hauteur du content au nombre de membres
    content:SetHeight(math.max(CONTENT_H, ROW_H * (#members + 1) + 4))

    for i, m in ipairs(members) do
        local yOff = ROW_START - (i-1) * ROW_H

        -- Nom
        local nl = nameLabels[i]
        if not nl then
            nl = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            nl:SetWidth(COL_ILV_X - COL_PAD - 4)
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
        il:SetPoint("TOPLEFT", content, "TOPLEFT", COL_ILV_X, yOff)
        local ilv = GetUnitItemLevel(m.unit)
        local r, g, b = IlvColor(ilv)
        il:SetTextColor(r, g, b)
        il:SetText(ilv and tostring(ilv) or "?")
        il:SetShown(GetColumnEnabled("ilv"))

        -- Score M+
        local sl = scoreLabels[i]
        if not sl then
            sl = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            scoreLabels[i] = sl
        end
        sl:ClearAllPoints()
        sl:SetPoint("TOPLEFT", content, "TOPLEFT", COL_SCR_X, yOff)
        local score = GetUnitMythicScore(m.unit)
        local sr, sg, sb = ScoreColor(score)
        sl:SetTextColor(sr, sg, sb)
        sl:SetText(score and tostring(score) or "-")
        sl:SetShown(GetColumnEnabled("score"))
    end

    hdrIlv:SetShown(GetColumnEnabled("ilv"))
    hdrScore:SetShown(GetColumnEnabled("score"))
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

-- Commande slash /gl refresh
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
local ADDON_PREFIX = "GroupList"
C_ChatInfo.RegisterAddonMessagePrefix(ADDON_PREFIX)

local function BroadcastMyIlv()
    -- Envoyer son propre iLv exact au groupe
    local _, equipped = GetAverageItemLevel()
    if not equipped or equipped <= 0 then return end
    local ilv = math.floor(equipped)
    local channel = IsInRaid() and "RAID" or (IsInGroup() and "PARTY" or nil)
    if channel then
        C_ChatInfo.SendAddonMessage(ADDON_PREFIX, "ILV:"..ilv, channel)
    end
end

-- Frame de reception des messages addon
local commsFrame = CreateFrame("Frame")
commsFrame:RegisterEvent("CHAT_MSG_ADDON")
commsFrame:SetScript("OnEvent", function(self, event, prefix, message, channel, sender)
    if prefix ~= ADDON_PREFIX then return end
    local ilv = message:match("^ILV:(%d+)$")
    if ilv then
        -- Trouver le GUID du sender et mettre en cache
        local unitType = IsInRaid() and "raid" or "party"
        local count = GetNumGroupMembers()
        for i = 1, count do
            local unit = unitType..i
            local name = (UnitName(unit))
            -- Comparer le nom (sender peut etre "Nom-Royaume")
            local senderName = sender:match("^([^%-]+)")
            if name and (name == sender or name == senderName) then
                local guid = UnitGUID(unit)
                if guid then
                    ilvCache[guid] = tonumber(ilv)
                    UpdateGroupList()
                end
                break
            end
        end
    end
end)

-- ─── Evenements ───────────────────────────────────────────
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("GROUP_ROSTER_UPDATE")
frame:RegisterEvent("UNIT_CONNECTION")          -- joueur se connecte/deconnecte
frame:RegisterEvent("PLAYER_ENTERING_WORLD")    -- apres chargement de zone
frame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
frame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
frame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        RestoreLayout()
        UpdateGroupList()
        C_Timer.After(2, BroadcastMyIlv)  -- laisser le temps au groupe de charger
    elseif event == "PLAYER_EQUIPMENT_CHANGED" then
        C_Timer.After(1, BroadcastMyIlv)  -- partager le nouvel iLv apres changement
        C_Timer.After(1.3, function() UpdateGroupList() end)
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        refreshPending = true
    elseif event == "GROUP_ROSTER_UPDATE" then
        inspectQueue = {}
        inspectInProgress = false
        ilvCache = {}
        C_Timer.After(0.5, function()
            UpdateGroupList()
            BroadcastMyIlv()  -- re-broadcaster quand le groupe change
        end)
    else
        C_Timer.After(0.3, function()
            UpdateGroupList()
        end)
    end
end)