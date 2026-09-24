-- minimap.lua
-- Bouton minimap + panneau parametres

-- ─── Angle de position sur la minimap ────────────────────
minimapAngle = 225  -- global (lu/ecrit par SaveLayout et RestoreLayout)

-- ─── Bouton Minimap ──────────────────────────────────────
local minimapBtn = CreateFrame("Button", "GroupListMinimapBtn", Minimap)
minimapBtn:SetSize(32, 32)
minimapBtn:SetFrameLevel(8)
minimapBtn:SetHighlightTexture("Interface/Minimap/UI-Minimap-ZoomButton-Highlight")

local minimapIcon = minimapBtn:CreateTexture(nil, "BACKGROUND")
minimapIcon:SetTexture("Interface/Icons/Achievement_GuildPerk_EverybodysFriend")
minimapIcon:SetSize(20, 20)
minimapIcon:SetPoint("CENTER")

function UpdateMinimapPos()  -- global (appele depuis RestoreLayout)
    local angle = math.rad(minimapAngle)
    local r = (Minimap:GetWidth() / 2) + 10
    minimapBtn:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * r, math.sin(angle) * r)
end

UpdateMinimapPos()

local minimapDragging = false

minimapBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
minimapBtn:RegisterForDrag("LeftButton")
minimapBtn:SetScript("OnDragStart", function(self)
    minimapDragging = true
    self:SetScript("OnUpdate", function()
        local mx, my = Minimap:GetCenter()
        local scale = UIParent:GetEffectiveScale()
        local cx, cy = GetCursorPosition()
        minimapAngle = math.deg(math.atan2(cy / scale - my, cx / scale - mx))
        UpdateMinimapPos()
    end)
end)

minimapBtn:SetScript("OnDragStop", function(self)
    minimapDragging = false
    self:SetScript("OnUpdate", nil)
    GroupListDB = GroupListDB or {}
    GroupListDB.minimapAngle = minimapAngle
end)

-- ─── Colonne activee / desactivee ────────────────────────
function GetColumnEnabled(key)  -- global (appele depuis UpdateGroupList)
    if GroupListDB and GroupListDB.columns and GroupListDB.columns[key] ~= nil then
        return GroupListDB.columns[key]
    end
    if key == "dmg" or key == "heal" or key == "int" or key == "dtk" then
        return true
    end
    return true
end

-- ─── Fenetre Parametres (style DBM) ──────────────────────
local settingsWin = CreateFrame("Frame", "GroupListSettingsFrame", UIParent, "BackdropTemplate")
settingsWin:SetSize(580, 400)
settingsWin:SetPoint("CENTER")
settingsWin:SetMovable(true)
settingsWin:EnableMouse(true)
settingsWin:RegisterForDrag("LeftButton")
settingsWin:SetScript("OnDragStart", settingsWin.StartMoving)
settingsWin:SetScript("OnDragStop", settingsWin.StopMovingOrSizing)
settingsWin:SetFrameStrata("DIALOG")
settingsWin:SetBackdrop({
    bgFile   = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    edgeSize = 16,
    insets   = { left=4, right=4, top=4, bottom=4 },
})
settingsWin:SetBackdropColor(0.05, 0.05, 0.05, 0.97)
settingsWin:SetBackdropBorderColor(0.45, 0.35, 0.1, 1)
settingsWin:Hide()

-- Barre de titre
local winTitleBar = settingsWin:CreateTexture(nil, "BACKGROUND")
winTitleBar:SetColorTexture(0.08, 0.05, 0.0, 1)
winTitleBar:SetPoint("TOPLEFT",  settingsWin, "TOPLEFT",   5, -5)
winTitleBar:SetPoint("TOPRIGHT", settingsWin, "TOPRIGHT", -5, -5)
winTitleBar:SetHeight(28)

local winTitle = settingsWin:CreateFontString(nil, "OVERLAY", "GameFontNormal")
winTitle:SetPoint("LEFT", settingsWin, "TOPLEFT", 14, -19)
winTitle:SetText("GroupList \226\128\148 Parametres")
winTitle:SetTextColor(1, 0.82, 0)

local glVer = C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata("GroupList", "Version") or ""
if glVer ~= "" then
    local winVerText = settingsWin:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    winVerText:SetPoint("LEFT", winTitle, "RIGHT", 8, -1)
    winVerText:SetText("v" .. glVer)
    winVerText:SetTextColor(0.5, 0.5, 0.5)
end

local winCloseBtn = CreateFrame("Button", nil, settingsWin)
winCloseBtn:SetSize(26, 26)
winCloseBtn:SetPoint("TOPRIGHT", settingsWin, "TOPRIGHT", -7, -7)
local winCloseFS = winCloseBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
winCloseFS:SetAllPoints(winCloseBtn)
winCloseFS:SetText("X")
winCloseFS:SetTextColor(0.65, 0.12, 0.12)
winCloseBtn:SetFontString(winCloseFS)
winCloseBtn:SetScript("OnEnter", function() winCloseFS:SetTextColor(1, 0.25, 0.25) end)
winCloseBtn:SetScript("OnLeave", function() winCloseFS:SetTextColor(0.65, 0.12, 0.12) end)
winCloseBtn:SetScript("OnClick", function() settingsWin:Hide() end)

local winTitleSep = settingsWin:CreateTexture(nil, "ARTWORK")
winTitleSep:SetColorTexture(0.5, 0.38, 0.1, 1)
winTitleSep:SetPoint("TOPLEFT",  settingsWin, "TOPLEFT",   5, -33)
winTitleSep:SetPoint("TOPRIGHT", settingsWin, "TOPRIGHT", -5, -33)
winTitleSep:SetHeight(1)

-- Panneau gauche
local NAV_W = 155
local navBg = settingsWin:CreateTexture(nil, "BACKGROUND")
navBg:SetColorTexture(0.0, 0.0, 0.0, 0.45)
navBg:SetPoint("TOPLEFT",    settingsWin, "TOPLEFT",    5, -34)
navBg:SetPoint("BOTTOMLEFT", settingsWin, "BOTTOMLEFT", 5,  34)
navBg:SetWidth(NAV_W)

local navDivider = settingsWin:CreateTexture(nil, "ARTWORK")
navDivider:SetColorTexture(0.5, 0.38, 0.1, 0.6)
navDivider:SetPoint("TOPLEFT",    settingsWin, "TOPLEFT",    5 + NAV_W, -34)
navDivider:SetPoint("BOTTOMLEFT", settingsWin, "BOTTOMLEFT", 5 + NAV_W,  34)
navDivider:SetWidth(1)

-- Barre de bas
local winBottomBar = settingsWin:CreateTexture(nil, "BACKGROUND")
winBottomBar:SetColorTexture(0.08, 0.05, 0.0, 1)
winBottomBar:SetPoint("BOTTOMLEFT",  settingsWin, "BOTTOMLEFT",   5, 5)
winBottomBar:SetPoint("BOTTOMRIGHT", settingsWin, "BOTTOMRIGHT", -5, 5)
winBottomBar:SetHeight(28)

local winBottomSep = settingsWin:CreateTexture(nil, "ARTWORK")
winBottomSep:SetColorTexture(0.5, 0.38, 0.1, 1)
winBottomSep:SetPoint("BOTTOMLEFT",  settingsWin, "BOTTOMLEFT",   5, 33)
winBottomSep:SetPoint("BOTTOMRIGHT", settingsWin, "BOTTOMRIGHT", -5, 33)
winBottomSep:SetHeight(1)

local winFermerBtn = CreateFrame("Button", nil, settingsWin, "UIPanelButtonTemplate")
winFermerBtn:SetSize(80, 22)
winFermerBtn:SetPoint("BOTTOMRIGHT", settingsWin, "BOTTOMRIGHT", -10, 9)
winFermerBtn:SetText("Fermer")
winFermerBtn:SetScript("OnClick", function() settingsWin:Hide() end)

-- ─── Systeme de pages ────────────────────────────────────
local settingsPages = {}
local CONTENT_X = 5 + NAV_W + 10

local function ShowSettingsPage(id)
    for pid, pg in pairs(settingsPages) do pg:SetShown(pid == id) end
end

local function NewSettingsPage()
    local f = CreateFrame("Frame", nil, settingsWin)
    f:SetPoint("TOPLEFT",     settingsWin, "TOPLEFT",     CONTENT_X, -40)
    f:SetPoint("BOTTOMRIGHT", settingsWin, "BOTTOMRIGHT", -10, 38)
    f:Hide()
    return f
end

-- ─── Navigation ──────────────────────────────────────────
local navActiveBtn = nil
local navY = -38

local function NavSetActive(btn)
    if navActiveBtn then
        navActiveBtn.selTex:Hide()
        navActiveBtn.selBar:Hide()
        navActiveBtn.lbl:SetTextColor(0.82, 0.82, 0.82)
    end
    navActiveBtn = btn
    if btn then
        btn.selTex:Show()
        btn.selBar:Show()
        btn.lbl:SetTextColor(1, 0.88, 0.35)
    end
end

local function NavHeader(text)
    local fs = settingsWin:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("TOPLEFT", settingsWin, "TOPLEFT", 10, navY - 7)
    fs:SetWidth(NAV_W - 10)
    fs:SetText(text)
    fs:SetTextColor(1, 0.52, 0.08)
    navY = navY - 24
end

local function NavItem(text, pageId)
    local btn = CreateFrame("Button", nil, settingsWin)
    btn:SetSize(NAV_W - 2, 26)
    btn:SetPoint("TOPLEFT", settingsWin, "TOPLEFT", 5, navY)
    navY = navY - 26

    local hoverTex = btn:CreateTexture(nil, "BACKGROUND")
    hoverTex:SetAllPoints(btn)
    hoverTex:SetColorTexture(0.22, 0.16, 0.0, 0.55)
    hoverTex:Hide()

    btn.selTex = btn:CreateTexture(nil, "BACKGROUND")
    btn.selTex:SetAllPoints(btn)
    btn.selTex:SetColorTexture(0.1, 0.2, 0.42, 0.85)
    btn.selTex:Hide()

    btn.selBar = btn:CreateTexture(nil, "ARTWORK")
    btn.selBar:SetWidth(3)
    btn.selBar:SetPoint("TOPLEFT",    btn, "TOPLEFT",    0, 0)
    btn.selBar:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 0, 0)
    btn.selBar:SetColorTexture(1, 0.72, 0.08, 1)
    btn.selBar:Hide()

    btn.lbl = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    btn.lbl:SetPoint("LEFT", btn, "LEFT", 14, 0)
    btn.lbl:SetText(text)
    btn.lbl:SetTextColor(0.82, 0.82, 0.82)

    btn:SetScript("OnEnter", function(s) if s ~= navActiveBtn then hoverTex:Show() end end)
    btn:SetScript("OnLeave", function()  hoverTex:Hide() end)
    btn:SetScript("OnClick", function(s)
        NavSetActive(s)
        ShowSettingsPage(pageId)
    end)
    return btn
end

NavHeader("Affichage")
local navBtnColonnes = NavItem("Colonnes", "colonnes")
navY = navY - 6
NavHeader("General")
local navBtnGeneral  = NavItem("Options",  "general")

-- ─── Page Colonnes ────────────────────────────────────────
local pageColonnes = NewSettingsPage()
settingsPages["colonnes"] = pageColonnes

local function PageSectionTitle(parent, text, yOff)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", 4, yOff)
    fs:SetText(text)
    fs:SetTextColor(1, 0.82, 0)
    local sep = parent:CreateTexture(nil, "ARTWORK")
    sep:SetColorTexture(0.5, 0.38, 0.1, 0.5)
    sep:SetPoint("TOPLEFT",  parent, "TOPLEFT",  4, yOff - 18)
    sep:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, yOff - 18)
    sep:SetHeight(1)
    return yOff - 22
end

local function PageSubHeader(parent, text, yOff)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", 4, yOff)
    fs:SetText(text)
    fs:SetTextColor(0.75, 0.65, 0.35)
    return yOff - 18
end

local columnCheckboxes = {}

local function PageCheckbox(parent, label, key, yOff, disabled)
    local name = "GroupListSettingsCB_" .. key
    local cb = CreateFrame("CheckButton", name, parent, "UICheckButtonTemplate")
    cb:SetSize(22, 22)
    cb:SetPoint("TOPLEFT", parent, "TOPLEFT", 4, yOff)
    local lbl = cb.Text or _G[name .. "Text"]
    if lbl then
        lbl:SetText(label)
        lbl:SetTextColor(disabled and 0.45 or 0.92, disabled and 0.45 or 0.92, disabled and 0.45 or 0.92)
    end
    if disabled then
        cb:Disable()
    else
        cb:SetScript("OnClick", function(self)
            GroupListDB = GroupListDB or {}
            GroupListDB.columns = GroupListDB.columns or {}
            GroupListDB.columns[key] = self:GetChecked()
            UpdateGroupList()
        end)
    end
    columnCheckboxes[key] = cb
    return yOff - 24
end

local cy = -4
cy = PageSectionTitle(pageColonnes, "Colonnes affichees", cy)
cy = PageSubHeader(pageColonnes, "Statistiques de groupe", cy)
cy = PageCheckbox(pageColonnes, "Item Level (iLv)",         "ilv",   cy, false)
cy = PageCheckbox(pageColonnes, "Cote Mythique+",           "score", cy, false)
cy = PageCheckbox(pageColonnes, "Score de Raid (a venir)",  "raid",  cy, true)
cy = cy - 6
cy = PageSubHeader(pageColonnes, "Donnees de combat (Details!)", cy)
cy = PageCheckbox(pageColonnes, "Degats + % groupe",        "dmg",  cy, false)
cy = PageCheckbox(pageColonnes, "Soins + % groupe",         "heal", cy, false)
cy = PageCheckbox(pageColonnes, "Interruptions + %",        "int",  cy, false)
cy = PageCheckbox(pageColonnes, "Degats subis + %",         "dtk",  cy, false)

-- ─── Page General ─────────────────────────────────────────
local pageGeneral = NewSettingsPage()
settingsPages["general"] = pageGeneral

local gy = -4
gy = PageSectionTitle(pageGeneral, "Options generales", gy)

local resetPosBtn = CreateFrame("Button", nil, pageGeneral, "UIPanelButtonTemplate")
resetPosBtn:SetSize(180, 24)
resetPosBtn:SetPoint("TOPLEFT", pageGeneral, "TOPLEFT", 4, gy - 6)
resetPosBtn:SetText("Reinitialiser la position")
resetPosBtn:SetScript("OnClick", function()
    GroupListFrame:ClearAllPoints()
    GroupListFrame:SetPoint("CENTER", UIParent, "CENTER")
    if GroupListDB then GroupListDB.x = nil GroupListDB.y = nil end
end)

local aboutText = pageGeneral:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
aboutText:SetPoint("BOTTOMLEFT", pageGeneral, "BOTTOMLEFT", 4, 4)
local verStr = C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata("GroupList", "Version") or "?"
aboutText:SetText("GroupList v" .. verStr .. "  |  WoW Midnight 12.x  |  Details! requis pour les colonnes combat")
aboutText:SetTextColor(0.45, 0.45, 0.45)

-- ─── Ouverture : affiche toujours la page Colonnes ────────
local function OpenSettingsWin()
    if settingsWin:IsShown() then
        settingsWin:Hide()
    else
        settingsWin:Show()
        NavSetActive(navBtnColonnes)
        ShowSettingsPage("colonnes")
    end
end

function RefreshCheckboxes()  -- global (appele depuis RestoreLayout)
    for key, cb in pairs(columnCheckboxes) do
        if key ~= "raid" then cb:SetChecked(GetColumnEnabled(key)) end
    end
end

-- ─── Scripts bouton minimap ───────────────────────────────
minimapBtn:SetScript("OnClick", function(self, button)
    if minimapDragging then return end
    if button == "LeftButton" then
        if GroupListFrame:IsShown() then
            GroupListFrame:Hide()
            GroupListDB = GroupListDB or {}
            GroupListDB.hidden = true
        else
            GroupListFrame:Show()
            GroupListDB = GroupListDB or {}
            GroupListDB.hidden = false
            UpdateGroupList()
        end
    elseif button == "RightButton" then
        OpenSettingsWin()
    end
end)

minimapBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText("GroupList", 1, 0.82, 0)
    GameTooltip:AddLine("|cffffff00Clic gauche|r: Afficher / masquer", 1, 1, 1)
    GameTooltip:AddLine("|cffffff00Clic droit|r: Parametres", 1, 1, 1)
    GameTooltip:AddLine("|cffffff00Drag|r: Deplacer le bouton", 1, 1, 1)
    GameTooltip:Show()
end)

minimapBtn:SetScript("OnLeave", function()
    GameTooltip:Hide()
end)