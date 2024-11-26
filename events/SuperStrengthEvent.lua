-- ============================================================= --
-- SUPER STRENGTH EVENT
-- ============================================================= --
SuperStrengthEvent = {}
SuperStrengthEvent_mt = Class(SuperStrengthEvent, Event)

InitEventClass(SuperStrengthEvent, "SuperStrengthEvent")

function SuperStrengthEvent.emptyNew()
	--print("SuperStrength - EMPTY NEW")
	local self =  Event.new(SuperStrengthEvent_mt)
	return self
end

function SuperStrengthEvent.new(superStrengthEnabled, maxPickableMass, maxObjectDistance)
	--print("SuperStrength - NEW")
	local self = SuperStrengthEvent.emptyNew()
	self.superStrengthEnabled = superStrengthEnabled
	self.maxPickableMass = maxPickableMass
	self.maxObjectDistance = maxObjectDistance
	return self
end

function SuperStrengthEvent:readStream(streamId, connection)
	--debugPrint("SuperStrength - READ STREAM")
	if not connection:getIsServer() then
		local superStrengthEnabled = streamReadBool(streamId)
		local maxPickableMass = streamReadFloat32(streamId)
		local maxObjectDistance = streamReadFloat32(streamId)
		
		local player = g_currentMission:getPlayerByConnection(connection)
		if player ~= nil and player.hands ~= nil then
			LumberJack.setSuperStrenth(player.hands, superStrengthEnabled, maxPickableMass, maxObjectDistance)
		end
	end
end

function SuperStrengthEvent:writeStream(streamId, connection)
	--print("SuperStrength - WRITE STREAM");
	if connection:getIsServer() then
		streamWriteBool(streamId, self.superStrengthEnabled or LumberJack.superStrength)
		streamWriteFloat32(streamId, self.maxPickableMass or LumberJack.normalStrengthValue)
		streamWriteFloat32(streamId, self.maxObjectDistance or LumberJack.normalDistanceValue)
	end
end

function SuperStrengthEvent.sendEvent(superStrengthEnabled)
	--debugPrint("SuperStrength - RUN")
	local hands = g_localPlayer.hands
	if hands then
	
		local maxPickableMass = LumberJack.normalStrengthValue
		local maxObjectDistance = LumberJack.normalDistanceValue
		if superStrengthEnabled then
			maxPickableMass = LumberJack.superStrengthValue
			maxObjectDistance = LumberJack.superDistanceValue
		end

		LumberJack.setSuperStrenth(hands, superStrengthEnabled, maxPickableMass, maxObjectDistance)
		
		if g_server == nil then
			--debugPrint("SuperStrength CLIENT SEND")
			g_client:getServerConnection():sendEvent(SuperStrengthEvent.new(superStrengthEnabled, maxPickableMass, maxObjectDistance))
		end
	else
		debugPrint("SuperStrength - hands is nil")
	end
	
end
