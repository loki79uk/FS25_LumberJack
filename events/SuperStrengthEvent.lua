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
	--print("SuperStrength - READ STREAM")
	if not connection:getIsServer() then
		local superStrengthEnabled = streamReadBool(streamId)
		local maxPickableMass = streamReadFloat32(streamId)
		local maxObjectDistance = streamReadFloat32(streamId)
		
		local player = g_currentMission:getPlayerByConnection(connection)
		if player ~= nil then
			player.superStrengthEnabled = superStrengthEnabled
			player.maxPickableMass = maxPickableMass
			player.maxPickableObjectDistance = maxObjectDistance
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
	--print("SuperStrength - RUN")
	if g_currentMission.player then
	
		local maxPickableMass = LumberJack.normalStrengthValue
		local maxObjectDistance = LumberJack.normalDistanceValue
		if superStrengthEnabled then
			maxPickableMass = LumberJack.superStrengthValue
			maxObjectDistance = LumberJack.superDistanceValue
		end

		g_currentMission.player.superStrengthEnabled = superStrengthEnabled
		g_currentMission.player.maxPickableMass = maxPickableMass
		g_currentMission.player.maxPickableObjectDistance = maxObjectDistance
		
		if g_server == nil then
			--print("SuperStrength CLIENT SEND")
			g_client:getServerConnection():sendEvent(SuperStrengthEvent.new(superStrengthEnabled, maxPickableMass, maxObjectDistance))
		end
	end
	
end
