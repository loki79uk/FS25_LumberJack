-- ============================================================= --
-- TOGGLE SAWDUST EVENT
-- ============================================================= --
ToggleSawdustEvent = {}
ToggleSawdustEvent_mt = Class(ToggleSawdustEvent, Event)

InitEventClass(ToggleSawdustEvent, "ToggleSawdustEvent")

function ToggleSawdustEvent.emptyNew()
	--print("ToggleSawdust - EMPTY NEW")
	local self =  Event.new(ToggleSawdustEvent_mt)
	return self
end

function ToggleSawdustEvent.new(createWoodchips)
	--print("ToggleSawdust - NEW")
	local self = ToggleSawdustEvent.emptyNew()
	self.createWoodchips = createWoodchips
	return self
end

function ToggleSawdustEvent:readStream(streamId, connection)
	--print("ToggleSawdust - READ STREAM")
	self.createWoodchips = streamReadBool(streamId)
	LumberJack.createWoodchips = self.createWoodchips
	
	if connection:getIsServer() then
		local woodchipsOption = LumberJack.CONTROLS['createWoodchips']
		local isAdmin = g_currentMission:getIsServer() or g_currentMission.isMasterUser
		woodchipsOption:setState(LumberJack.getStateIndex('createWoodchips'))
		woodchipsOption:setDisabled(not isAdmin)
	else
		ToggleSawdustEvent.sendEvent(LumberJack.createWoodchips)
	end

end

function ToggleSawdustEvent:writeStream(streamId, connection)
	--print("ToggleSawdust - WRITE STREAM");
	streamWriteBool(streamId, self.createWoodchips)
end

function ToggleSawdustEvent.sendEvent(createWoodchips, noEventSend)
	if noEventSend == nil or noEventSend == false then
		if g_server ~= nil then
			--print("server: Toggle Sawdust Event")
			g_server:broadcastEvent(ToggleSawdustEvent.new(createWoodchips), false)
		else
			--print("client: Toggle Sawdust Event")
			g_client:getServerConnection():sendEvent(ToggleSawdustEvent.new(createWoodchips))
		end
	end
end
