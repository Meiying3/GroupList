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
    return true
end

-- ─── Panneau Parametres ──────────────────────────────────
local settingsFrame = CreateFrame("Frame", "GroupListSettingsFrame", UIParent, "BackdropTemplate")
settingsFrame:SetSize(210, 130)
settingsFrame:SetMovable(true)
settingsFrame:EnableMouse(true)
settingsFrame:RegisterForDrag("LeftButton")
settingsFrame:SetScript("OnDragStart", settingsFrame.StartMoving)
settingsFrame:SetScript("OnDragStop", settingsFrame.StopMovingOrSizing)
settingsFrame:SetBackdrop({
    bgFile   = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    edgeSize = 12,
    insets   = { left=3, right=3, top=3, bottom=3 },
})
settingsFrame:SetBackdropColor(0, 0, 0, 0.85)
settingsFrame:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
settingsFrame:Hide()

local settingsTitle = settingsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
settingsTitle:SetPoint("TOPLEFT", settingsFrame, "TOPLEFT", 10, -8)
settingsTitle:SetText("GroupList \226\128\148 Colonnes")
settingsTitle:SetTextColor(1, 0.82, 0)

local settingsCloseBtn = CreateFrame("Button", nil, settingsFrame)
settingsCloseBtn:SetSize(18, 18)
settingsCloseBtn:SetPoint("TOPRIGHT", settingsFrame, "TOPRIGHT", -4, -4)
local settingsCloseTex = settingsCloseBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
settingsCloseTex:SetAllPoints(settingsCloseBtn)
settingsCloseTex:SetText("X")
settingsCloseBtn:SetFontString(settingsCloseTex)
settingsCloseBtn:SetScript("OnClick", function() settingsFrame:Hide() end)

local columnCheckboxes = {}

local function CreateColumnCheckbox(label, key, yOffset, disabled)
    local name = "GroupListCB_" .. key
    local cb = CreateFrame("CheckButton", name, settingsFrame, "UICheckButtonTemplate")
    cb:SetSize(22, 22)
    cb:SetPoint("TOPLEFT", settingsFrame, "TOPLEFT", 8, yOffset)
    local lbl = cb.Text or _G[name .. "Text"]
    if lbl then
        lbl:SetText(label)
        lbl:SetTextColor(disabled and 0.5 or 1, disabled and 0.5 or 1, disabled and 0.5 or 1)
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
    return cb
end

CreateColumnCheckbox("Item Level (iLv)",       "ilv",   -28, false)
CreateColumnCheckbox("Cote Mythique+",          "score", -54, false)
CreateColumnCheckbox("Score de Raid (a venir)", "raid",  -80, true)

function RefreshCheckboxes()  -- global (appele depuis RestoreLayout)
    for key, cb in pairs(columnCheckboxes) do
        if key ~= "raid" then
            cb:SetChecked(GetColumnEnabled(key))
        end
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
        if settingsFrame:IsShown() then
            settingsFrame:Hide()
        else
            settingsFrame:ClearAllPoints()
            settingsFrame:SetPoint("BOTTOMLEFT", minimapBtn, "TOPLEFT", 0, 5)
            settingsFrame:Show()
        end
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