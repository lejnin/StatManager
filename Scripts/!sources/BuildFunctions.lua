
-- StatBuilds - table: index (int) -> build
-- 	build - table of:
-- 		name - build name, string
-- 		stats - table: TalentKey( row, line ) -> stattype
--								(dressSlot, 0-atak 1-defence)	

Global( "BuildsTable", {} )

Global( "clTable", {
	DRUID = "DRUID",
	MAGE = "MAGE",
	NECROMANCER = "NECROMANCER",
	PALADIN = "PALADIN",
	PRIEST = "PRIEST",
	PSIONIC = "PSIONIC", 
	STALKER = "STALKER",
	WARRIOR = "WARRIOR",
	BARD = "BARD", 
	ENGINEER = "ENGINEER",
	WARLOCK = "WARLOCK"
})

Global( "TryFindCnt", 0 )
Global( "LoadingBuild", {} )
Global( "IsLoadingNow", false )
Global( "LastActivityTime", 0 )

local m_lastOffenceInsigniaID = nil
local m_lastDefenceInsigniaID = nil
local m_lastOffenceInsigniaIndex = nil
local m_lastDefenceInsigniaIndex = nil
local m_changedItemOnTick = {}
local m_unsupportedEquipWarned = false
local m_missingOffenceWarned = false
local m_missingDefenceWarned = false

local m_locale = getLocale()
----------------------------------------------------------------------------------------------------
-- Save/Load

function IsSaveGlobal()
	local saveGlobal = userMods.GetGlobalConfigSection("StatManger_free_use_global")
	
	return saveGlobal and saveGlobal.value
end

function SetSaveGlobal(aValue)
	if aValue then
		LogToChat(m_locale["saveGlobal"])
	else
		LogToChat(m_locale["saveLocal"])
	end
	userMods.SetGlobalConfigSection( "StatManger_free_use_global", { value = aValue } )
end

function SaveBuildsTable()
	if (IsSaveGlobal()) then
		userMods.SetGlobalConfigSection( "StatBuilds", BuildsTable )
	else
		userMods.SetAvatarConfigSection( "StatBuilds", BuildsTable )
	end
end

function LoadBuildsTable()
	if (IsSaveGlobal()) then
		BuildsTable = userMods.GetGlobalConfigSection( "StatBuilds" )
	else
		BuildsTable = userMods.GetAvatarConfigSection( "StatBuilds" )
	end

	if not BuildsTable then
		BuildsTable = {}
	end
end

----------------------------------------------------------------------------------------------------

function GetAvatarClass()
	if avatar.IsExist and not avatar.IsExist() then
		return nil
	end
	local avatarClass = avatar.GetClass()
	return clTable[avatarClass] or avatarClass
end

function SaveCurrentBuild( name )
	local build = {}
	build.name = name
	build.class = GetAvatarClass()
	SaveStatBuild( build )

	table.insert( BuildsTable, build )
	SaveBuildsTable()
end

function UpdateBuild( index )
	BuildsTable[ index ].class = GetAvatarClass()
	SaveStatBuild( BuildsTable[ index ] )

	SaveBuildsTable()
end

function LoadBuild( aBuild )
	LogToChat(m_locale["workStart"])
	IsLoadingNow = true
	ResetTryCnt()
	LoadingBuild = aBuild
	
	m_lastOffenceInsigniaID = nil
	m_lastDefenceInsigniaID = nil
	m_lastOffenceInsigniaIndex = nil
	m_lastDefenceInsigniaIndex = nil
	m_unsupportedEquipWarned = false
	m_missingOffenceWarned = false
	m_missingDefenceWarned = false

	LoadBuildInternal(aBuild)
end

function StopLoadBuild()
	IsLoadingNow = false
	ResetTryCnt()
	m_changedItemOnTick = {}
	LoadingBuild = {}
	LogToChat(m_locale["doesNotEnd"], "warning")
end

function GetTimestamp()
	return common.GetMsFromDateTime( common.GetLocalDateTime() )
end


local function IsAllChangedItemVerified()
	for _, verified in pairs(m_changedItemOnTick) do
		if not verified then
			return false
		end
	end
	return true
end

function OnItemChanged(aParam)
	if IsLoadingNow then
		if m_changedItemOnTick[aParam.itemId] ~= nil then
			m_changedItemOnTick[aParam.itemId] = true
			if IsAllChangedItemVerified() then
				LoadBuildInternal( LoadingBuild )
			end
		end
	end
end

function LoadBuildInternal( aBuild )
	LastActivityTime = GetTimestamp()
	if IsPlayerInCombat() then
		LogToChat(m_locale["inFight"], "warning")
		IsLoadingNow = false
		return false
	end
	local myDressedSlots = unit.GetEquipmentItemIds(avatar.GetId(), ITEM_CONT_EQUIPMENT)
	m_changedItemOnTick = {}
	local insigniaMissing = false
	for i = 0, DRESS_SLOT_UNDRESSABLE-1 do
		local dressedItemID = myDressedSlots[i]
		if aBuild.stats and aBuild.stats[i] and dressedItemID then
			local neededOffenceStatId = aBuild.stats[i][ENUM_SpecialStatType_Offence]
			local neededDefenceStatId = aBuild.stats[i][ENUM_SpecialStatType_Defence]
			local bonus = itemLib.GetBonus(dressedItemID)

			if bonus and bonus.specStats then
				local offenceStat = GetStatByType(bonus.specStats, ENUM_SpecialStatType_Offence)
				local defenceStat = GetStatByType(bonus.specStats, ENUM_SpecialStatType_Defence)
				
				if offenceStat and defenceStat then
					local offenceInsignia = nil;
					local defenceInsignia = nil;

					offenceInsignia, defenceInsignia = GetInsignia()
					if offenceInsignia then 
						if ChangeStat(i, offenceInsignia, dressedItemID, neededOffenceStatId, ENUM_SpecialStatType_Offence) then
							m_changedItemOnTick[dressedItemID] = false
						end
					else 
						insigniaMissing = true
						if not m_missingOffenceWarned then
							m_missingOffenceWarned = true
							LogToChat(m_locale["missingAttackInsignia"], "warning")
						end
					end
					--иногда при смене одновременно атакующей и защитной стат они меняются сервером в разное время, поэтому крутим по одной
					if m_changedItemOnTick[dressedItemID] == nil then
						if defenceInsignia then 
							if ChangeStat(i, defenceInsignia, dressedItemID, neededDefenceStatId, ENUM_SpecialStatType_Defence) then
								m_changedItemOnTick[dressedItemID] = false
							end
						else 
							insigniaMissing = true
							if not m_missingDefenceWarned then
								m_missingDefenceWarned = true
								LogToChat(m_locale["missingDefenseInsignia"], "warning")
							end
						end
					end
				end
			end
		end
	end
	
	-- защита от дурака, если что то изменится в api для избежания ухода в бесконечный цикл
	if TryFindCnt > 10 then 
		IsLoadingNow = false
		LogToChat(m_locale["limitError"], "error")
		return
	end
	
	TryFindCnt = TryFindCnt + 1
	
	if GetTableSize(m_changedItemOnTick) == 0 then
		IsLoadingNow = false
		if not insigniaMissing then
			LogToChat(m_locale["workDone"])
		end
	end
end

function DeleteBuild( anIndex )
	table.remove( BuildsTable, anIndex )
	SaveBuildsTable()
end

function ChangeStat(anInd, anInsignia, aDressedItemID, aNeededOffenceStatId, aType)
	if IsPlayerInCombat() then
		LogToChat(m_locale["inFight"], "warning")
		IsLoadingNow = false
		return false
	end
	
	local mayBeUsed = itemLib.CanUseOnItem(anInsignia, aDressedItemID)
	if mayBeUsed then
		if itemLib.IsUseOnItemAndTakeActions(anInsignia) then 
			local bonus = itemLib.GetBonus(aDressedItemID)
			local someStat = GetStatByType(bonus.specStats, aType)
			
			if not aNeededOffenceStatId:IsEqual(someStat.id) then
				avatar.UseItemOnItemAndTakeActions(anInsignia, aDressedItemID)
				return true
			end
		end
	end
	
	return false
end

function IsPlayerInCombat()
  local playerId = avatar.GetId()
  return object.IsInCombat(playerId)
end

function ResetTryCnt()
	TryFindCnt = 0
end

function GetStatByType(aSpecStat, aType)
	if GetTableSize(aSpecStat) > 3 and not m_unsupportedEquipWarned then
		m_unsupportedEquipWarned = true
		--не тир3 а что-то новое, выведем предупреждение, возможно потребуется др механизм
		LogToChat(m_locale["unsuportedEquip"], "error")
	end
	local statsByTypeArr = {}
	for i, specStat in pairs(aSpecStat) do
		if specStat and specStat.type == aType then
			table.insert(statsByTypeArr, specStat)
		end
	end
	--в тир3 шмоте ищем макс стат этого типа и сохраняем его
	local maxSpexStat = nil
	for i, specStat in pairs(statsByTypeArr) do
		if maxSpexStat == nil then
			maxSpexStat = specStat
		end
		if specStat.value > maxSpexStat.value then
			maxSpexStat = specStat
		end
	end
	
	return maxSpexStat
end

function CheckItemName(aMyItems, anRightNameArr, aLastInsigniaIndex, aLastInsigniaID)
	if aLastInsigniaIndex~=nil then
		local itemID = containerLib.GetItem(ITEM_CONT_INVENTORY, aLastInsigniaIndex)
		if aLastInsigniaID and itemID and aLastInsigniaID == itemID then
			return aLastInsigniaID, aLastInsigniaIndex
		end
	end
		
	for _, searchInsigniaName in ipairs(anRightNameArr) do
		for i, itemID in pairs(aMyItems) do
			local itemName = ItemInfoGetName(itemID)
			
			if itemName == searchInsigniaName then
				return itemID, i
			end
		end
	end
	return nil
end

function GetInsignia()
	local myItems = containerLib.GetItems(ITEM_CONT_INVENTORY)
	if not myItems then 
		myItems = {}
	end
	m_lastOffenceInsigniaID, m_lastOffenceInsigniaIndex = CheckItemName(myItems, g_offensiveItems, m_lastOffenceInsigniaIndex, m_lastOffenceInsigniaID)
	m_lastDefenceInsigniaID, m_lastDefenceInsigniaIndex = CheckItemName(myItems, g_defensiveItems, m_lastDefenceInsigniaIndex, m_lastDefenceInsigniaID)
	
	return m_lastOffenceInsigniaID, m_lastDefenceInsigniaID
end


function ItemInfoGetName(anID)
	if anID then
		local itemInfo = itemLib.GetItemInfo(anID)
		if itemInfo then
			if itemInfo.name then
				return itemInfo.name
			else
				return common.GetEmptyWString()
			end
		else
			return common.GetEmptyWString()
		end
	end
end
----------------------------------------------------------------------------------------------------

function SaveStatBuild(aBuilds)
	aBuilds.stats = {}
	m_unsupportedEquipWarned = false

	local myDressedSlots = unit.GetEquipmentItemIds(avatar.GetId(), ITEM_CONT_EQUIPMENT)
	
	for i = 0, DRESS_SLOT_UNDRESSABLE-1 do
		local dressedItemID = myDressedSlots[i]
		if dressedItemID then
			local bonus = itemLib.GetBonus(dressedItemID)
			if bonus and bonus.specStats then
				local offenceStat = GetStatByType(bonus.specStats, ENUM_SpecialStatType_Offence)
				local defenceStat = GetStatByType(bonus.specStats, ENUM_SpecialStatType_Defence)

				
				if offenceStat and defenceStat then					
					local cell = {}
					cell[ENUM_SpecialStatType_Offence] = offenceStat.id
					cell[ENUM_SpecialStatType_Defence] = defenceStat.id

					aBuilds.stats[i] = cell;
				end 
			end
		end
		
	end
end