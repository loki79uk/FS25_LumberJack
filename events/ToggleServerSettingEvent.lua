-- ============================================================= --
-- TOGGLE SERVER SETTING EVENT
-- ============================================================= --
ToggleServerSettingEvent = {}
ToggleServerSettingEvent_mt = Class(ToggleServerSettingEvent, Event)

InitEventClass(ToggleServerSettingEvent, "ToggleServerSettingEvent")

function ToggleServerSettingEvent.emptyNew()
	--print("ToggleServerSetting - EMPTY NEW")
	local self =  Event.new(ToggleServerSettingEvent_mt)
	return self
end

function ToggleServerSettingEvent.new(id)
	--print("ToggleServerSetting - NEW")
	local self = ToggleServerSettingEvent.emptyNew()
	self.id = tostring(id)
	return self
end

function ToggleServerSettingEvent:readStream(streamId, connection)
	--print("ToggleServerSetting - READ STREAM")
	self.id = tostring(streamReadString(streamId))
	LumberJack[self.id] = streamReadBool(streamId)

	if connection:getIsServer() then
		local menuOption = LumberJack.CONTROLS[self.id]
		if menuOption then
			local isAdmin = g_currentMission:getIsServer() or g_currentMission.isMasterUser
			menuOption:setState(LumberJack.getStateIndex(self.id))
			menuOption:setDisabled(not isAdmin)
		end
	else
		ToggleServerSettingEvent.sendEvent(self.id)
	end

end

function ToggleServerSettingEvent:writeStream(streamId, connection)
	--print("ToggleServerSetting - WRITE STREAM");

	local value = LumberJack[self.id] or false
	
	streamWriteString(streamId, self.id)
	streamWriteBool(streamId, value)

end

function ToggleServerSettingEvent.sendEvent(id, noEventSend)
	if noEventSend == nil or noEventSend == false then
		if g_server ~= nil then
			--print("server: Toggle Sawdust Event")
			g_server:broadcastEvent(ToggleServerSettingEvent.new(id), false)
		else
			--print("client: Toggle Sawdust Event")
			g_client:getServerConnection():sendEvent(ToggleServerSettingEvent.new(id))
		end
	end
end
