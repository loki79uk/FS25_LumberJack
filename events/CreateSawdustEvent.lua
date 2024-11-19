-- ============================================================= --
-- CREATE SAWDUST EVENT
-- ============================================================= --
CreateSawdustEvent = {}
CreateSawdustEvent_mt = Class(CreateSawdustEvent, Event)

InitEventClass(CreateSawdustEvent, "CreateSawdustEvent")

function CreateSawdustEvent.emptyNew()
	--print("CreateSawdust - EMPTY NEW")
	local self =  Event.new(CreateSawdustEvent_mt)
	return self
end

function CreateSawdustEvent.new(player, amount, position)
	--print("CreateSawdust - NEW")
	local self = CreateSawdustEvent.emptyNew()
	self.player = player
	self.amount = amount or 0
	self.position = position
	return self
end

function CreateSawdustEvent:readStream(streamId, connection)
	--print("CreateSawdust - READ STREAM")
	if not connection:getIsServer() then
		self.player = NetworkUtil.readNodeObject(streamId)
		self.amount = streamReadInt32(streamId)
		self.position = nil
		if streamReadBool(streamId) then
			local x = streamReadInt32(streamId)
			local y = streamReadInt32(streamId)
			local z = streamReadInt32(streamId)
			self.position = {x, y, z}
		end
		
		local chainsaw = self.player.currentHandTool.spec_chainsaw
		LumberJack.createSawdust(chainsaw, self.amount, self.position, true)
		
	end
end

function CreateSawdustEvent:writeStream(streamId, connection)
	--print("CreateSawdust - WRITE STREAM");
	if connection:getIsServer() then
		NetworkUtil.writeNodeObject(streamId, self.player)
		streamWriteInt32(streamId, self.amount)
		if self.position then
			streamWriteBool(streamId, true)
			streamWriteInt32(streamId, self.position[1])
			streamWriteInt32(streamId, self.position[2])
			streamWriteInt32(streamId, self.position[3])
		else
			streamWriteBool(streamId, false)
		end
	end
end

function CreateSawdustEvent.sendEvent(player, amount, position, noEventSend)
	if noEventSend == nil or noEventSend == false then
		if g_server == nil then
			g_client:getServerConnection():sendEvent(CreateSawdustEvent.new(player, amount, position))
		end
	end
end