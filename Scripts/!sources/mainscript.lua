Global( "g_lastAoPanelParams", nil )

local ListInClassMode = false
local ListButton = mainForm:GetChildChecked( "ListButton", false )

local m_currentMenu = nil

-- rename state (declared here: used by HideMainMenu)
local RenameBuildIndex = nil
local RenameMenuIndex = nil

local m_menuDesc = GetWdgDesc("SaveBuildTemplate")
local m_quickBtnDesc = GetWdgDesc("QuickBuildButton")
local m_quickLabelEditDesc = GetWdgDesc("QuickLabelEdit")

----------------------------------------------------------------------------------------------------
-- AOPanel support

local IsAOPanelEnabled = true
local IsBtnInAOPanelNow = false
function onAOPanelStart( params )
	if IsAOPanelEnabled then
		local SetVal = { val = userMods.ToWString( ListInClassMode and "Sc" or "S" ) }
		local params = { header = SetVal, ptype = "button", size = 32 }
		userMods.SendEvent( "AOPANEL_SEND_ADDON",
			{ name = common.GetAddonName(), sysName = common.GetAddonName(), param = params } )

		ListButton:Show( false )
		IsBtnInAOPanelNow = true
	end
end

function onAOPanelLeftClick( params )
	if params.sender == common.GetAddonName() then
		g_lastAoPanelParams = params
		onShowList(params)
	else
		HideMainMenu()
	end
end

function onAOPanelRightClick( params )
	if params.sender == common.GetAddonName() then
		local SetVal = { val = userMods.ToWString( ListInClassMode and "S" or "Sc" )}
		userMods.SendEvent( "AOPANEL_UPDATE_ADDON", { sysName = common.GetAddonName(), header = SetVal } )
		ListInClassMode = not ListInClassMode
		userMods.SetAvatarConfigSection( "LastListMode", {value = ListInClassMode} )
		HideMainMenu()
	end
end

function RightClick(param)
	ListInClassMode = not ListInClassMode
	userMods.SetAvatarConfigSection( "LastListMode", {value = ListInClassMode} )
	ListButton:SetVal("button_label", userMods.ToWString( ListInClassMode and "Sc" or "S" ))
	HideMainMenu()
end

function onAOPanelChange( params )
	if params.state == ADDON_STATE_NOT_LOADED and string.find(params.name, "AOPanel") then
		ListButton:Show( true )
		IsBtnInAOPanelNow = false
	end
end


----------------------------------------------------------------------------------------------------
-- Quick build buttons (draggable on-screen buttons that load a single build)
-- build.quickId (number) - stable id of the build, assigned on first pin, never reused
-- pins follow the addon storage mode (/statsaveglobal, /statsaveavatar): global or per character config "QuickButtons"
-- pin: quickId -> { pinned = true, label, posX, posY, highPosX, highPosY }

local m_quickButtons = {} -- quickId -> widget
local m_quickButtonsHidden = false
local m_pins = {}
local QUICK_BTN_PREFIX = "QuickBuild"
local QUICK_ID_COUNTER = "QuickIdCounter"

local function SavePins()
	if IsSaveGlobal() then
		userMods.SetGlobalConfigSection( "QuickButtons", m_pins )
	else
		userMods.SetAvatarConfigSection( "QuickButtons", m_pins )
	end
end

local function LoadPins()
	if IsSaveGlobal() then
		m_pins = userMods.GetGlobalConfigSection( "QuickButtons" ) or {}
	else
		m_pins = userMods.GetAvatarConfigSection( "QuickButtons" ) or {}
	end
end

local function GetQuickButtonWidth(aName)
	-- counts chars both for utf-8 and cp1251 strings (skip utf-8 continuation bytes)
	local cnt = 0
	for i = 1, string.len(aName) do
		local b = string.byte(aName, i)
		if b < 128 or b > 191 then
			cnt = cnt + 1
		end
	end
	return math.min(math.max(cnt * 8 + 24, 32), 240)
end

-- global counter, so an id of a deleted build is never given to another one
local function GetFreeQuickId()
	local maxId = GetConfig( QUICK_ID_COUNTER ) or 0
	for _, build in ipairs(BuildsTable) do
		if type(build) == "table" and build.quickId and build.quickId > maxId then
			maxId = build.quickId
		end
	end
	maxId = maxId + 1
	SetConfig( QUICK_ID_COUNTER, maxId )
	return maxId
end

local function FindBuildByQuickId(aQuickId)
	for _, build in ipairs(BuildsTable) do
		if type(build) == "table" and build.quickId == aQuickId then
			return build
		end
	end
end

function IsBuildPinned(aBuild)
	return aBuild.quickId ~= nil and m_pins[aBuild.quickId] ~= nil
end

-- custom label of the button, or build name
local function GetQuickLabel(aBuild)
	local pin = aBuild.quickId and m_pins[aBuild.quickId]
	return pin and pin.label or aBuild.name or ""
end

local function UpdateQuickButtonLabel(aWdg, aBuild)
	local label = GetQuickLabel(aBuild)
	aWdg:SetVal("button_label", userMods.ToWString(label))
	local place = aWdg:GetPlacementPlain()
	place.sizeX = GetQuickButtonWidth(label)
	aWdg:SetPlacementPlain(place)
end

function CreateQuickButton(aBuild)
	if not IsBuildPinned(aBuild) or m_quickButtons[aBuild.quickId] then
		return
	end
	local pin = m_pins[aBuild.quickId]
	local wdg = mainForm:CreateChildByDesc(m_quickBtnDesc)
	wdg:SetName(QUICK_BTN_PREFIX..aBuild.quickId)
	UpdateQuickButtonLabel(wdg, aBuild)
	local place = wdg:GetPlacementPlain()
	if pin.posX then
		place.posX = pin.posX
		place.posY = pin.posY
		place.highPosX = pin.highPosX or place.highPosX
		place.highPosY = pin.highPosY or place.highPosY
	else
		-- default position: under the main button, stacked by count
		place.posX = 0
		place.posY = 34 * (GetTableSize(m_quickButtons) + 1)
	end
	wdg:SetPlacementPlain(place)
	-- position is stored in the pin (not in LibDnD config), so it is removed together with the pin
	DnD.Init(wdg, wdg, false)
	DnD.SetDropCallback(wdg, function(aPlace)
		local currPin = m_pins[aBuild.quickId]
		if currPin then
			currPin.posX = aPlace.posX
			currPin.posY = aPlace.posY
			currPin.highPosX = aPlace.highPosX
			currPin.highPosY = aPlace.highPosY
			SavePins()
		end
	end)
	m_quickButtons[aBuild.quickId] = wdg
	wdg:Show(not m_quickButtonsHidden)
end

function DestroyQuickButton(aQuickId)
	local wdg = aQuickId and m_quickButtons[aQuickId]
	if wdg then
		if IsQuickLabelEditing(aQuickId) then
			CancelQuickLabelEdit()
		end
		DnD.Remove(wdg)
		wdg:DestroyWidget()
		m_quickButtons[aQuickId] = nil
	end
end

function RefreshQuickButton(aBuild)
	local wdg = aBuild.quickId and m_quickButtons[aBuild.quickId]
	if wdg then
		UpdateQuickButtonLabel(wdg, aBuild)
	end
end

-- called before a build is deleted
function UnpinBuild(aBuild)
	if aBuild.quickId then
		DestroyQuickButton(aBuild.quickId)
		if m_pins[aBuild.quickId] then
			m_pins[aBuild.quickId] = nil
			SavePins()
		end
	end
end

function ToggleQuickButton(aBuild)
	if IsBuildPinned(aBuild) then
		UnpinBuild(aBuild)
	else
		if not aBuild.quickId then
			aBuild.quickId = GetFreeQuickId()
			SaveBuildsTable()
		end
		m_pins[aBuild.quickId] = { pinned = true }
		SavePins()
		CreateQuickButton(aBuild)
	end
	onShowList(g_lastAoPanelParams)
	onShowList(g_lastAoPanelParams)
end

-- removes positions saved by LibDnD in the first version of quick buttons
local function CleanupLegacyDnDConfig()
	local cfg = GetConfig()
	if not cfg then
		return
	end
	local changed = false
	for key in pairs(cfg) do
		if type(key) == "string" and string.find(key, "^DnD:.*%."..QUICK_BTN_PREFIX.."%d+$") then
			cfg[key] = nil
			changed = true
		end
	end
	if changed then
		userMods.SetGlobalConfigSection( common.GetAddonName(), cfg )
	end
end

function CreateAllQuickButtons()
	CleanupLegacyDnDConfig()
	LoadPins()
	-- drop pins of builds deleted on another character
	local changed = false
	for quickId in pairs(m_pins) do
		if not FindBuildByQuickId(quickId) then
			m_pins[quickId] = nil
			changed = true
		end
	end
	if changed then
		SavePins()
	end
	for _, build in ipairs(BuildsTable) do
		if type(build) == "table" then
			CreateQuickButton(build)
		end
	end
end

----------------------------------------------------------------------------------------------------
-- Quick button label editing (right click on the button)

local m_labelEdit = nil      -- edit widget
local m_labelEditId = nil    -- quickId of the button being edited
local LABEL_EDIT_WIDTH = 200

local function GetQuickIdByWidget(aWdg)
	return tonumber(string.match(aWdg:GetName(), "^"..QUICK_BTN_PREFIX.."(%d+)$"))
end

function IsQuickLabelEditing(aQuickId)
	return m_labelEditId ~= nil and (aQuickId == nil or m_labelEditId == aQuickId)
end

-- clears state before destroying: losing focus triggers onQuickLabelFocus
local function CloseQuickLabelEdit()
	local quickId = m_labelEditId
	local edit = m_labelEdit
	m_labelEditId = nil
	m_labelEdit = nil
	if edit and edit:IsValid() then
		edit:DestroyWidget()
	end
	-- restore normal label and width
	local build = quickId and FindBuildByQuickId(quickId)
	if build then
		RefreshQuickButton(build)
	end
end

function CancelQuickLabelEdit()
	if IsQuickLabelEditing() then
		CloseQuickLabelEdit()
	end
end

local function AcceptQuickLabelEdit()
	if not IsQuickLabelEditing() then
		return
	end
	local pin = m_pins[m_labelEditId]
	local build = FindBuildByQuickId(m_labelEditId)
	if pin and build and m_labelEdit and m_labelEdit:IsValid() then
		local text = userMods.FromWString( m_labelEdit:GetText() )
		text = string.gsub( string.gsub( text, "^%s+", "" ), "%s+$", "" )
		if text == "" or text == build.name then
			pin.label = nil
		else
			pin.label = text
		end
		SavePins()
	end
	CloseQuickLabelEdit()
end

function onQuickBuildRightClick(params)
	if DnD:IsDragging() then
		return
	end
	local quickId = GetQuickIdByWidget(params.widget)
	local build = quickId and FindBuildByQuickId(quickId)
	if not build then
		return
	end
	if IsQuickLabelEditing() then
		local sameButton = IsQuickLabelEditing(quickId)
		AcceptQuickLabelEdit()
		if sameButton then
			return
		end
	end
	HideMainMenu()

	local btn = m_quickButtons[quickId]
	btn:SetVal("button_label", common.GetEmptyWString())
	local place = btn:GetPlacementPlain()
	place.sizeX = math.max(place.sizeX, LABEL_EDIT_WIDTH)
	btn:SetPlacementPlain(place)

	local edit = mainForm:CreateChildByDesc(m_quickLabelEditDesc)
	local editPlace = edit:GetPlacementPlain()
	editPlace.posX = place.posX + 8
	editPlace.posY = place.posY
	editPlace.sizeX = place.sizeX - 16
	editPlace.sizeY = place.sizeY
	edit:SetPlacementPlain(editPlace)
	edit:SetText(userMods.ToWString(GetQuickLabel(build)))
	edit:Show(true)
	edit:Enable(true)
	edit:SetFocus(true)

	m_labelEdit = edit
	m_labelEditId = quickId
end

function onQuickLabelAccept(params)
	AcceptQuickLabelEdit()
end

function onQuickLabelCancel(params)
	CancelQuickLabelEdit()
end

function onQuickLabelFocus(params)
	if not params.active then
		AcceptQuickLabelEdit()
	end
end

----------------------------------------------------------------------------------------------------

function ShowQuickButtons(aShow)
	if not aShow then
		CancelQuickLabelEdit()
	end
	m_quickButtonsHidden = not aShow
	for _, wdg in pairs(m_quickButtons) do
		wdg:Show(aShow)
	end
end

function onQuickBuild(params)
	if DnD:IsDragging() then
		return
	end
	if IsQuickLabelEditing() then
		AcceptQuickLabelEdit()
	end
	local quickId = GetQuickIdByWidget(params.widget)
	local build = quickId and FindBuildByQuickId(quickId)
	if build then
		HideMainMenu()
		LoadBuild(build)
	end
end

----------------------------------------------------------------------------------------------------

local ClassMenu = nil
local Localization = getLocale()

function onSaveBuild( params )
	local wtEdit = params.widget:GetParent():GetChildChecked( "BuildNameEdit", false )
	local text = userMods.FromWString( wtEdit:GetText() )

	if text ~= "" then
		SaveCurrentBuild( text )
		onShowList(g_lastAoPanelParams)
		onShowList(g_lastAoPanelParams)
	end
end


function getBuildIndex( build )
	for i = 1, table.getn( BuildsTable ) do
		if BuildsTable[i] == build then
			return i
		end
	end
end

function getBuildIndexByClass( aBuild )
	local cnt = 1
	for _, currBuild in ipairs( BuildsTable ) do
		if aBuild.class == currBuild.class then 
			if currBuild == aBuild then
				return cnt
			end
			cnt = cnt + 1
		end
	end
end

function HideMainMenu()
	RenameBuildIndex = nil
	RenameMenuIndex = nil
	if ClassMenu and ClassMenu:IsValid() then
		DestroyMenu( ClassMenu )
		ClassMenu = nil 
	end
end

local UNKNOWN_CLASS = "?"

local function GetBuildClassKey(aBuild)
	return aBuild.class or UNKNOWN_CLASS
end

-- sorted list of classes that have at least one build
local function GetBuildClasses()
	local found = {}
	local classes = {}
	for _, v in ipairs( BuildsTable ) do
		if type(v) == "table" then
			local classKey = GetBuildClassKey(v)
			if not found[classKey] then
				found[classKey] = true
				table.insert( classes, classKey )
			end
		end
	end
	table.sort( classes )
	return classes
end

function CreateSubMenu(ClassName)
	local SubMenu = {}
	for _, v in ipairs( BuildsTable ) do
		if type(v) == "table" then
			local build = v
			if ClassName == nil or GetBuildClassKey(v) == ClassName then
				local MenuName = v.name 
				
				local buildSubMenu = {
					{ name = Localization["rename"],
						onActivate = function() onRenameBuild( build ) end },
					{ name = Localization["delete"],
						onActivate = function() UnpinBuild( build ); DeleteBuild( getBuildIndex( build ) ); onShowList(g_lastAoPanelParams); onShowList(g_lastAoPanelParams) end },
					{ name = Localization["update"],
						onActivate = function() UpdateBuild( getBuildIndex( build ) ) end },
				}
				table.insert( buildSubMenu, {
					name = IsBuildPinned( build ) and Localization["quickBtnRemove"] or Localization["quickBtnAdd"],
					onActivate = function() ToggleQuickButton( build ) end } )
					
				table.insert( SubMenu, {
					name = userMods.ToWString( MenuName ),
					isDNDEnabled = true,
					associateBuild = build,
					onActivate = 
					function() 
						LoadBuild( build ) 
						HideMainMenu()
					end,
					submenu = buildSubMenu
				})
			end
		end
	end
	return SubMenu
end

function onShowList( params )
	if DnD:IsDragging() then
		return
	end
	m_currentMenu = nil
	if not ClassMenu or not ClassMenu:IsValid() then
		local menu = {}
		
		if ListInClassMode then
			for _, classKey in ipairs( GetBuildClasses() ) do
				local SubMenus = CreateSubMenu(classKey)
				if table.getn(SubMenus) > 0 then table.insert( menu, { name = userMods.ToWString(classKey), submenu = SubMenus } ) end
			end
		else
			menu = CreateSubMenu(nil)
		end

		table.insert( menu, { createWidget = function(aParent) return aParent:CreateChildByDesc( m_menuDesc ) end } )

		if ListButton:IsVisible() then
			local pos = ListButton:GetPlacementPlain()
			ClassMenu = ShowMenu( { x = pos.posX, y = pos.posY + pos.sizeY }, menu )
		else
			ClassMenu = ShowMenu( { x = params and params.x or 0, y = 32 }, menu )
		end
		SetSaveEditFocus( true )
		m_currentMenu = menu
	else
		HideMainMenu()
	end
end

----------------------------------------------------------------------------------------------------
-- Renaming

-- menu that holds build items: top menu, or opened class submenu in class mode
function GetBuildsMenuWidget()
	if not ClassMenu or not ClassMenu:IsValid() then
		return nil
	end
	if ListInClassMode then
		local child = GetChildMenu(ClassMenu)
		return child and child:IsValid() and child or nil
	end
	return ClassMenu
end

function SetSaveEditFocus(aFocus)
	if ClassMenu and ClassMenu:IsValid() then
		ClassMenu:GetChildChecked( "SaveBuildTemplate", false ):GetChildChecked( "BuildNameEdit", false ):SetFocus( aFocus )
	end
end

function GetMenuItems()
	local menu = GetBuildsMenuWidget()
	local children = menu and menu:GetNamedChildren() or {}
	table.sort( children,
		function( a, b )
			if a:GetName() == "ItemEditTemplate" then return false end
			if b:GetName() == "ItemEditTemplate" then return true end
			return a:GetPlacementPlain().posY < b:GetPlacementPlain().posY
		end )
	return children
end

function onRenameBuild( build )
	if RenameBuildIndex then
		onRenameCancel()
	end

	local menu = GetBuildsMenuWidget()
	local buildIndex = getBuildIndex( build )
	local menuIndex = ListInClassMode and getBuildIndexByClass(build) or buildIndex
	local item = menuIndex and GetMenuItems()[ menuIndex ]
	if not menu or not buildIndex or not item then
		return
	end
	RenameBuildIndex = buildIndex
	RenameMenuIndex = menuIndex

	item:Show( false )
	local edit = menu:GetChildChecked( "ItemEditTemplate", false )
	edit:SetText( userMods.ToWString( build.name ) )
	edit:SetPlacementPlain( item:GetPlacementPlain() )
	edit:Show( true )
	edit:Enable( true )
	edit:SetFocus( true )
	SetSaveEditFocus( false )
end

function onRenameCancel( params )
	if not RenameBuildIndex then
		return
	end
	local menuIndex = RenameMenuIndex
	-- reset before focus change: losing focus triggers onRenameFocus -> onRenameAccept
	RenameBuildIndex = nil
	RenameMenuIndex = nil

	local menu = GetBuildsMenuWidget()
	if not menu then
		return
	end
	local item = GetMenuItems()[ menuIndex ]
	if item then
		item:Show( true )
	end
	local edit = menu:GetChildChecked( "ItemEditTemplate", false )
	edit:Show( false )
	edit:Enable( false )

	SetSaveEditFocus( true )
end

function onRenameAccept( params )
	if not RenameBuildIndex then
		return
	end
	local build = BuildsTable[ RenameBuildIndex ]
	RenameBuildIndex = nil
	RenameMenuIndex = nil

	local menu = GetBuildsMenuWidget()
	if not menu or not build then
		return
	end
	local edit = menu:GetChildChecked( "ItemEditTemplate", false )
	local newName = userMods.FromWString( edit:GetText() )
	if newName ~= "" then
		build.name = newName
		RefreshQuickButton( build )
		SaveBuildsTable()
	end

	onShowList(g_lastAoPanelParams)
	onShowList(g_lastAoPanelParams)
end

function onRenameFocus( params )
	if not params.active then
		onRenameAccept( params )
	end
end

----------------------------------------------------------------------------------------------------
-- DnD support
local DraggedItem = nil
local SettingsIndexDragFrom = nil
local SettingsIndexDragTo = nil
local MenuIndexDragFrom = nil
local MenuIndexDragTo = nil

function IsDragging()
	return DraggedItem ~= nil
end

local function GetClassSubMenu(className)
	for _, classMenu in pairs(m_currentMenu) do
		if classMenu.name == className then
			return classMenu.submenu
		end
	end
end

function GetAssociateWithMenuClassName(wdg)
	if ListInClassMode then
		local searchingID = wdg:GetInstanceId()
		for _, classMenu in pairs(m_currentMenu) do
			for _, element in ipairs(classMenu.submenu) do
				if element.wdgInstanceId == searchingID then
					return classMenu.name
				end
			end
		end
	end
end

function GetAssociateWithMenuBuild(wdg)
	local searchingID = wdg:GetInstanceId()
	if not ListInClassMode then
		for _, element in ipairs(m_currentMenu) do
			if element.wdgInstanceId == searchingID then
				return element.associateBuild
			end
		end
	else
		for _, classMenu in pairs(m_currentMenu) do
			for _, element in ipairs(classMenu.submenu) do
				if element.wdgInstanceId == searchingID then
					return element.associateBuild
				end
			end
		end
	end
end

function GetAssociateWithMenuPosBuild(pos, className)
	if not ListInClassMode then
		return m_currentMenu[pos].associateBuild
	else
		return GetClassSubMenu(className)[pos].associateBuild
	end
end

function GetMenuBuildElementCnt(className)
	if not ListInClassMode then
		return table.getn(m_currentMenu) - 1
	else
		return table.getn(GetClassSubMenu(className))
	end
end


function OnDndPick( params )
	if not IsMyMenuPicked(params.srcId) then
		return
	end
	DraggedItem = params.srcWidget:GetParent()
		
	local children = GetMenuItems()
	if children then
		SettingsIndexDragFrom = getBuildIndex(GetAssociateWithMenuBuild(DraggedItem))

		for i, w in ipairs( children ) do
			if w:GetInstanceId() == DraggedItem:GetInstanceId() then
				MenuIndexDragFrom = i
			end
		end
		if RenameBuildIndex then
			onRenameCancel()
		end

		common.RegisterEventHandler( OnDndDragTo, "EVENT_DND_DRAG_TO" )
		common.RegisterEventHandler( OnDndEnd, "EVENT_DND_DROP_ATTEMPT" )
		common.RegisterEventHandler( OnDndCancelled, "EVENT_DND_DRAG_CANCELLED" )
		DraggedItem:DNDConfirmPickAttempt()
	end
end

function OnDndDragTo( params )
	if not DraggedItem then 
		return
	end
	local posConverter = common.GetPosConverterParams()
	local cursorY = params.posY * posConverter.fullVirtualSizeY / posConverter.realSizeY
	cursorY = cursorY - DraggedItem:GetParent():GetPlacementPlain().posY

	local children = GetMenuItems()
	local childrenPos = {}
	local dragIndex = nil

	local height = 16
	for i, w in ipairs( children ) do
		if w:GetInstanceId() == DraggedItem:GetInstanceId() then
			dragIndex = i
		end
		childrenPos[ i ] = w:GetPlacementPlain()
		childrenPos[ i ].posY = height
		height = height + childrenPos[ i ].sizeY
	end

	local dragTo = dragIndex
	if cursorY < childrenPos[dragIndex].posY then
		while dragTo > 1 and cursorY < childrenPos[dragTo].posY do
			dragTo = dragTo - 1
		end
	else
		while dragTo < GetMenuBuildElementCnt(GetAssociateWithMenuClassName(DraggedItem)) and cursorY > childrenPos[dragTo].posY + childrenPos[dragTo].sizeY do
			dragTo = dragTo + 1
		end
	end
	MenuIndexDragTo = dragTo
	SettingsIndexDragTo = getBuildIndex(GetAssociateWithMenuPosBuild(dragTo, GetAssociateWithMenuClassName(DraggedItem)))

	table.insert( children, dragTo, table.remove( children, dragIndex ) )

	for i, w in ipairs( children ) do
		w:PlayMoveEffect( w:GetPlacementPlain(), childrenPos[i], 100, EA_MONOTONOUS_INCREASE )
	end
end

function OnDndCancelled( params )
	common.UnRegisterEventHandler( OnDndDragTo, "EVENT_DND_DRAG_TO" )
	common.UnRegisterEventHandler( OnDndEnd, "EVENT_DND_DROP_ATTEMPT" )
	common.UnRegisterEventHandler( OnDndCancelled, "EVENT_DND_DRAG_CANCELLED" )
	if DraggedItem then
		DraggedItem:DNDConfirmDropAttempt()
	end
	
	DraggedItem = nil
	SettingsIndexDragFrom = nil
	SettingsIndexDragTo = nil
	MenuIndexDragFrom = nil
	MenuIndexDragTo = nil
end

function ApplyChangePosition()
	local removingItem = table.remove( BuildsTable, SettingsIndexDragFrom )
	table.insert( BuildsTable, SettingsIndexDragTo, removingItem )
	if not ListInClassMode then
		removingItem = table.remove( m_currentMenu, MenuIndexDragFrom )
		table.insert( m_currentMenu, MenuIndexDragTo, removingItem )
	else
		local subMenu = GetClassSubMenu(GetAssociateWithMenuClassName(DraggedItem))
		removingItem = table.remove( subMenu, MenuIndexDragFrom )
		table.insert( subMenu, MenuIndexDragTo, removingItem )
	end
end

function OnDndEnd( params )
	local backupSettings = table.clone(BuildsTable)
	local someBroken = false
	if SettingsIndexDragFrom ~= nil and SettingsIndexDragTo ~= nil 
		and SettingsIndexDragTo <= GetTableSize(BuildsTable)
		and SettingsIndexDragFrom > 0 and SettingsIndexDragTo > 0
		and SettingsIndexDragFrom ~= SettingsIndexDragTo 
	then
		if pcall(ApplyChangePosition) then
			SaveBuildsTable()
		else
			--был случай когда "залип" одиночный клик и затем как-то при тасканиях потерлись билды
			--поэтому обернул проверками для сохранения данных
			someBroken = true
		end
	end
	
	OnDndCancelled(params)
	
	if someBroken then
		BuildsTable = backupSettings
		onShowList(g_lastAoPanelParams)
		onShowList(g_lastAoPanelParams)
	end
end

local function OnEventSecondTimer()
	if LastActivityTime ~= 0 and IsLoadingNow then
		local elapsedTime = GetTimestamp() - LastActivityTime
		--прошло больше 10 секунд после последнего EVENT_GAME_ITEM_CHANGED
		if elapsedTime > 10000 then
			StopLoadBuild()
		end
	end
end

local function OnSlashCommand(aParams)
	if userMods.FromWString(aParams.text) == "/statsaveglobal" or userMods.FromWString(aParams.text) == "\\statsaveglobal" then
		SetSaveGlobal(true)
		common.StateReloadManagedAddon(common.GetAddonSysName())
	end
	if userMods.FromWString(aParams.text) == "/statsaveavatar" or userMods.FromWString(aParams.text) == "\\statsaveavatar" then
		SetSaveGlobal(false)
		common.StateReloadManagedAddon(common.GetAddonSysName())
	end
end

local function onInterfaceToggle(aParams)
	if aParams.toggleTarget == ENUM_InterfaceToggle_Target_All then
		if not IsBtnInAOPanelNow then
			ListButton:Show( not aParams.hide )
		end
		ShowQuickButtons( not aParams.hide )
	end
end

----------------------------------------------------------------------------------------------------

function Init()
	local LastListMode = userMods.GetAvatarConfigSection( "LastListMode" )
	ListInClassMode = LastListMode and LastListMode.value
	ListButton:SetVal("button_label", userMods.ToWString( ListInClassMode and "Sc" or "S" )) 
	
	LoadBuildsTable()

	DnD.Init( ListButton, ListButton, true )

	common.RegisterEventHandler( onAOPanelStart, "AOPANEL_START" )
	common.RegisterEventHandler( onAOPanelLeftClick, "AOPANEL_BUTTON_LEFT_CLICK" )
	common.RegisterEventHandler( onAOPanelRightClick, "AOPANEL_BUTTON_RIGHT_CLICK" )
	common.RegisterEventHandler( onAOPanelChange, "EVENT_ADDON_LOAD_STATE_CHANGED" )
	
	common.RegisterEventHandler( onInterfaceToggle, "EVENT_INTERFACE_TOGGLE" )

	common.RegisterReactionHandler( onSaveBuild, "SaveBuildReaction" )
	common.RegisterReactionHandler( onShowList, "ShowBuildsReaction" )
	common.RegisterReactionHandler( RightClick, "RIGHT_CLICK" )
	common.RegisterReactionHandler( onRenameCancel, "RenameCancelReaction" )
	common.RegisterReactionHandler( onRenameAccept, "RenameBuildReaction" )
	common.RegisterReactionHandler( onRenameFocus, "RenameFocusChanged" )
	common.RegisterReactionHandler( onQuickBuild, "QuickBuildReaction" )
	common.RegisterReactionHandler( onQuickBuildRightClick, "QuickBuildRightClick" )
	common.RegisterReactionHandler( onQuickLabelAccept, "QuickLabelAcceptReaction" )
	common.RegisterReactionHandler( onQuickLabelCancel, "QuickLabelCancelReaction" )
	common.RegisterReactionHandler( onQuickLabelFocus, "QuickLabelFocusChanged" )

	common.RegisterEventHandler( OnDndPick, "EVENT_DND_PICK_ATTEMPT" )
	
	common.RegisterEventHandler( OnItemChanged, "EVENT_GAME_ITEM_CHANGED")

	common.RegisterEventHandler(OnEventSecondTimer, "EVENT_SECOND_TIMER")
	common.RegisterEventHandler( OnSlashCommand, "EVENT_UNKNOWN_SLASH_COMMAND" )
	
	InitMenu()
	
	CreateAllQuickButtons()
end

Init()

