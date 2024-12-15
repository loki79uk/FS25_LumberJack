-- ============================================================= --
-- LUMBERJACK MOD for FS25 - loki_79
-- ============================================================= --
LumberJack = {}
LumberJack.name = g_currentModName
LumberJack.path = g_currentModDirectory

-- DEFAULTS
LumberJack.cutAnywhere = true
LumberJack.createWoodchips = false
LumberJack.superStrengthValue = 1000
LumberJack.normalStrengthValue = 0.2
LumberJack.superDistanceValue = 12
LumberJack.normalDistanceValue = 3
LumberJack.minCutDistance = 0.1
LumberJack.maxCutDistance = 4.0
LumberJack.defaultCutDuration = 3
LumberJack.destroyFoliageSize = 2
LumberJack.showDebug = false

-- VARIABLES
LumberJack.longHoldThreshold = 1000
LumberJack.doubleTapThreshold = 500
LumberJack.maxWoodchips = 2000

-- FLAGS
LumberJack.superStrength = false
LumberJack.lockStrength = false
LumberJack.strengthHeld = false
LumberJack.useChainsawFlag = false
LumberJack.stumpGrindingPossible = false
LumberJack.bushCuttingPossible = false
LumberJack.destroyAllFoliage = false
LumberJack.initialised = false

-- FOUND USING RAY CAST
LumberJack.closestObject = nil

-- FOUND USING GIANTS RING SELECTOR
LumberJack.chainsawShape = nil
LumberJack.chainsawCanCut = nil
		
-- BUSH LAYER STRINGS
LumberJack.foliageSearchNames = {
	"bush",
	"forest"
}

LumberJack.ringColour = {
	white   = {1, 1, 1, 0},
	orange  = {1, 0.27, 0, 1},
	red     = {0.8, 0.05, 0.05, 1},
	green   = {0.395, 0.925, 0.115, 1},
	yellow  = {0.925, 0.395, 0.05, 1},
}

source(g_currentModDirectory .. 'LumberJackSettings.lua')
source(g_currentModDirectory .. 'events/DeleteShapeEvent.lua')
source(g_currentModDirectory .. 'events/CreateSawdustEvent.lua')
source(g_currentModDirectory .. 'events/SuperStrengthEvent.lua')
source(g_currentModDirectory .. 'events/ToggleServerSettingEvent.lua')

addModEventListener(LumberJack)

function debugPrint(str) 
	if LumberJack.showDebug then
		print("[LumberJack] " .. str)
	end
end

-- DETECT SUPER STRENGTH CONSOLE COMMAND
executeConsoleCommand = Utils.overwrittenFunction(executeConsoleCommand,
function(command, superFunc, ...)
	if command == 'gsPlayerSuperStrengthToggle' then
		debugPrint("called gsPlayerSuperStrengthToggle - " .. tostring(LumberJack.superStrength))
	end
	superFunc(command, ...)
end
)

HandToolHands.consoleCommandToggleSuperStrength = Utils.overwrittenFunction(HandToolHands.consoleCommandToggleSuperStrength,
function(self, superFunc, ...)
	local result = superFunc(self, ...)
	
	LumberJack.superStrength = self.spec_hands.hasSuperStrength
	debugPrint("called consoleCommandToggleSuperStrength - " .. tostring(LumberJack.superStrength))
	return result
end
)

-- ALLOW TREE SPRAYING ANYWHERE ON THE MAP
HandToolSprayCan.getIsSprayingAllowed = Utils.overwrittenFunction(HandToolSprayCan.getIsSprayingAllowed,
function(self, superFunc, ...)
	if g_currentMission:getHasPlayerPermission("cutTrees") then
		-- debugPrint("can spray tree..")
		return true
	end
	return superFunc(self, ...)
end
)

-- GET CHAINSAW TARGET SHAPE
HandToolChainsaw.updateRingSelector = Utils.overwrittenFunction(HandToolChainsaw.updateRingSelector,
function(self, superFunc, shape, canCut, ...)
	if shape and shape.node then
		-- debugPrint("shape: " .. tostring(shape))
		-- debugPrint("canCut: " .. tostring(canCut))
		LumberJack.chainsawShape = shape.node
		LumberJack.chainsawCanCut = canCut
	end
	return superFunc(self, shape, canCut, ...)
end
)

-- ALLOW CHAINSAW CUTTING ANYWHERE ON THE MAP
HandToolChainsaw.testIfCutAllowed = Utils.overwrittenFunction(HandToolChainsaw.testIfCutAllowed,
function(self, superFunc, shape, x, z, ...)
	
	if shape == 0 or shape == nil then
		return false
	end
	
	local canCutTrees = g_currentMission:getHasPlayerPermission("cutTrees")
	local canChainsaw = g_currentMission:getHasPlayerPermission("chainsawSettings")
	local canAccess = g_currentMission.accessHandler:canFarmAccessLand(self.carryingPlayer.farmId, x, z)

	local isAllowed = canCutTrees and ((canChainsaw and LumberJack.cutAnywhere) or canAccess)
	if isAllowed then
		-- debugPrint("can cut shape: " .. tostring(shape))
		return true
	else
		return superFunc(self, shape, x, z, ...)
	end
end
)

-- DETECT SPLITSHAPES FROM CHAINSAW CALLBACK
function LumberJack:targetRaycastCallback(hitObjectId, x, y, z, distance)
	if hitObjectId ~= 0 and hitObjectId ~= nil then
		LumberJack.targetLocation = {x, y, z}
		LumberJack.targetDistance = distance
		LumberJack.targetOnGround = hitObjectId==g_currentMission.terrainRootNode
		if LumberJack.targetedSplitShapeId ~= hitObjectId then
			if getHasClassId(hitObjectId, ClassIds.MESH_SPLIT_SHAPE) then
				LumberJack.targetedSplitShapeId = hitObjectId
			else
				LumberJack.targetedSplitShapeId = nil
			end
		end
	end
end

function LumberJack.updateTargetRaycast()
	
	LumberJack.targetLocation = nil
	LumberJack.targetOnGround = nil
	
	local cameraNode = g_localPlayer:getCurrentCameraNode()
	if cameraNode then
		
		local x, y, z = getWorldTranslation(cameraNode)
		local dx, dy, dz = unProject(0.52, 0.4, 1)
		dx, dy, dz = dx-x, dy-y, dz-z
		dx, dy, dz = MathUtil.vector3Normalize(dx, dy, dz)
		local collisionMask = CollisionFlag.DEFAULT + CollisionFlag.TERRAIN + CollisionFlag.TREE + CollisionFlag.VEHICLE

		raycastClosest(x, y, z, dx, dy, dz, LumberJack.superDistanceValue, "targetRaycastCallback", LumberJack, collisionMask)
		
	end
end

-- ALTERNATIVE TO "FIND SPLIT SHAPE"
function LumberJack:getSplitShape(shape)
	local objectId = shape or LumberJack.closestObject and LumberJack.closestObject.id
	
	if objectId~=nil and objectId~=0 and entityExists(objectId) then
		if getHasClassId(objectId, ClassIds.MESH_SPLIT_SHAPE) then
			if getSplitType(objectId) ~= 0 then
				local isSplit = getIsSplitShapeSplit(objectId)
				local isStatic = getRigidBodyType(objectId) == RigidBodyType.STATIC
				local isDynamic = getRigidBodyType(objectId) == RigidBodyType.DYNAMIC
				
				local isTree = isStatic and not isSplit
				local isStump = isStatic and isSplit
				local isBranch = isDynamic and isSplit
			
				return objectId, isTree, isStump, isBranch
			end
		end
	end
	return nil
end


-- ADD SHORTCUT KEY SELECTION TO OPTIONS MENU
function LumberJack:registerActionEvents(force)

	if force or not LumberJack.actionEventId then
		debugPrint("LUMBERJACK: ADDING ACTION EVENT")
		local success, actionEventId = g_inputBinding:registerActionEvent('LUMBERJACK_STRENGTH', LumberJack, LumberJack.strengthKeyCallback, true, true, false, true)
		debugPrint(" success = " .. tostring(success))
		LumberJack.actionEventId = success and actionEventId or nil
	end

	g_inputBinding:setActionEventTextPriority(actionEventId, GS_PRIO_LOW)
	g_inputBinding:setActionEventActive(actionEventId, true)
    g_inputBinding:setActionEventText(actionEventId, g_i18n:getText("menu_TOGGLE_STRENGTH"))
	g_inputBinding:setActionEventTextVisibility(actionEventId, true)
end

-- LUMBERJACK FUNCTIONS:
function LumberJack:loadMap(name)
	-- print("Load Mod: 'LumberJack'")

	LumberJack.readSettings()
	LumberJack.injectMenu()
	
	if not g_startMissionInfo.isMultiplayer then
		print("adding console command - 'lumberjackLoadSettings'")
		addConsoleCommand("lumberjackLoadSettings", "Load LumberJack settings from the local mod settings file", "readSettings", LumberJack)
	else
		print("LumberJack console command is disabled for multiplayer")
	end
	
end

function LumberJack:strengthKeyCallback(id, state)
	LumberJack.strengthKeyState = state
	LumberJack.strengthKeyAction = true
end

function LumberJack.doToggleStrength()
	--debugPrint("doToggleStrength")
	if g_currentMission:getHasPlayerPermission("superStrength") then

		LumberJack.superStrength = not LumberJack.superStrength
		--executeConsoleCommand('gsPlayerSuperStrengthToggle')
		SuperStrengthEvent.sendEvent(LumberJack.superStrength)
		
		if LumberJack.superStrength then
			debugPrint("SUPER-STRENGTH IS ON")
		else
			debugPrint("SUPER-STRENGTH IS OFF")
		end
		
	else
		if LumberJack.superStrength then
			debugPrint("SUPER STRENGTH PERMISSON MISSING")
			LumberJack.superStrength = false
			SuperStrengthEvent.sendEvent(LumberJack.superStrength)
		end
	end
end

function LumberJack.updateStrength(dt)

	if LumberJack.playerIsEntered and not g_gui:getIsGuiVisible() then

		LumberJack.tapCount = LumberJack.tapCount or 0
		LumberJack.holdTime = LumberJack.holdTime or 0
		LumberJack.doubleTapTime = LumberJack.doubleTapTime or 0
		
		if LumberJack.tapCount == 1 then
			LumberJack.doubleTapTime = LumberJack.doubleTapTime + dt
			if LumberJack.doubleTapTime > LumberJack.doubleTapThreshold then
				LumberJack.tapCount = 0
				LumberJack.doubleTapTime = 0
			end
		end
		
		if LumberJack.strengthKeyState == 1 then -- KEY DOWN
			LumberJack.holdTime = LumberJack.holdTime + dt
			--debugPrint("Running Strength Update with hold time: " .. LumberJack.holdTime)
			if LumberJack.strengthKeyAction == true then
				LumberJack.tapCount = LumberJack.tapCount + 1
				--debugPrint("TAP COUNT = " .. LumberJack.tapCount .. ", HOLD TIME = " .. LumberJack.holdTime)
			end
			if LumberJack.tapCount == 1 then
				local holdThreshold = math.max(LumberJack.longHoldThreshold, LumberJack.doubleTapThreshold)
				if LumberJack.holdTime > holdThreshold + 1 then
					if not LumberJack.superStrength and not LumberJack.strengthHeld then
						-- debugPrint("LONG PRESS HOLD")
						LumberJack.strengthHeld = true
						LumberJack.doToggleStrength()
					end
					--debugPrint("RESET TAP COUNT TO 0")
					LumberJack.tapCount = 0
				end
				LumberJack.doubleTapTime = 0
			elseif LumberJack.tapCount == 2 then
				-- debugPrint("DOUBLE TAP")
				LumberJack.tapCount = 0
				LumberJack.doToggleStrength()
			end
		else -- KEY UP
			if LumberJack.superStrength and LumberJack.strengthHeld then
				-- debugPrint("LONG PRESS RELEASE")
				LumberJack.doToggleStrength()
			end
			LumberJack.holdTime = 0
			LumberJack.strengthHeld = false
		end
		
		LumberJack.strengthKeyAction = false
	end
end

function LumberJack.setSuperStrenth(handToolHands, superStrengthActive, mass, distance)
	--debugPrint("setSuperStrenthServer.")
	local spec = handToolHands.spec_hands
	local previousStatus = spec.hasSuperStrength
	
	spec.hasSuperStrength = superStrengthActive
	
	spec.currentMaximumMass = mass
	spec.pickupDistance = distance
	
	local carryingPlayer = handToolHands:getCarryingPlayer()
	if carryingPlayer and carryingPlayer.isOwner then
		carryingPlayer.targeter:removeTargetType(HandToolHands)
		carryingPlayer.targeter:addTargetType(HandToolHands, HandToolHands.TARGET_MASK, 0.5, spec.pickupDistance)
	end
	
	if previousStatus ~= spec.hasSuperStrength then
		if spec.hasSuperStrength then
			debugPrint("Enabled super strength.")
		else
			debugPrint("Disabled super strength.")
		end
	-- else
		-- debugPrint("Updated super strength without change.")
	end
end

function LumberJack.updateVariables(dt)
	
	local function compareFloats(a, b)
		local epsilon = 0.001
		return math.abs(a - b) < epsilon
	end
	
	if g_currentMission:getHasPlayerPermission('superStrength') then
		
		-- INCREASE PICKUP MASS
		if not compareFloats(HandToolHands.MAXIMUM_PICKUP_MASS, LumberJack.normalStrengthValue) then
			HandToolHands.MAXIMUM_PICKUP_MASS = LumberJack.normalStrengthValue
			debugPrint("MAXIMUM_PICKUP_MASS = " .. string.format("%.3f", LumberJack.normalStrengthValue))
		end

		if not compareFloats(HandToolHands.SUPER_STRENGTH_PICKUP_MASS, LumberJack.superStrengthValue) then
			HandToolHands.SUPER_STRENGTH_PICKUP_MASS = LumberJack.superStrengthValue
			debugPrint("SUPER_STRENGTH_PICKUP_MASS = " .. LumberJack.superStrengthValue)
		end
		
		-- INCREASE PICKUP DISTANCE
		if LumberJack.superStrength then
			g_currentMission:addExtraPrintText(g_i18n:getText("input_LUMBERJACK_STRENGTH") .. ": " .. g_i18n:getText("ui_on"))
			if not compareFloats(HandToolHands.PICKUP_DISTANCE, LumberJack.superDistanceValue) then
				HandToolHands.PICKUP_DISTANCE = LumberJack.superDistanceValue
				debugPrint("PICKUP_DISTANCE = " .. LumberJack.superDistanceValue)
			end
		else
			--g_currentMission:addExtraPrintText(g_i18n:getText("input_LUMBERJACK_STRENGTH") .. ": " .. g_i18n:getText("ui_off"))
			if not compareFloats(HandToolHands.PICKUP_DISTANCE, LumberJack.normalDistanceValue) then
				HandToolHands.PICKUP_DISTANCE = LumberJack.normalDistanceValue
				debugPrint("PICKUP_DISTANCE = " .. LumberJack.normalDistanceValue)
			end
		end

	end
	
	if g_currentMission:getHasPlayerPermission('chainsawSettings') then
		
		-- INCREASE CUT DISTANCE
		if not compareFloats(HandToolChainsaw.MINIMUM_CUT_DISTANCE, LumberJack.minCutDistance) then
			HandToolChainsaw.MINIMUM_CUT_DISTANCE = LumberJack.minCutDistance
			debugPrint("MINIMUM_CUT_DISTANCE = " .. LumberJack.minCutDistance)
		end
		
		if not compareFloats(HandToolChainsaw.MAXIMUM_CUT_DISTANCE, LumberJack.maxCutDistance) then
			HandToolChainsaw.MAXIMUM_CUT_DISTANCE = LumberJack.maxCutDistance
			debugPrint("MAXIMUM_CUT_DISTANCE = " .. LumberJack.maxCutDistance)
		end
		
	end
end

function LumberJack.updateChainsaw(dt)
	
	local player = g_localPlayer
	
	if player and player.isHoldingChainsaw then

		LumberJack.stumpGrindingPossible = false
		
		-- g_currentMission:addExtraPrintText("chainsawShape: " .. tostring(LumberJack.chainsawShape))
		-- g_currentMission:addExtraPrintText("chainsawCanCut: " .. tostring(LumberJack.chainsawCanCut))
		
		--CHECK FOR CHAINSAW
		local handTool = player.currentHandTool
		if not handTool or not handTool.spec_chainsaw then
			debugPrint("NOT A CHAINSAW")
			return
		end

		-- RUNNING WHITH CHAINSAW
		if handTool.runMultiplier == 0 then
			debugPrint("ALLOW RUNNING WITH CHAINSAW")
			handTool.runMultiplier = 0.75
			handTool.walkMultiplier = 0.90
		end

		local chainsaw = handTool.spec_chainsaw
		
		if LumberJack.chainsawShape and chainsaw.ringNode then
			if LumberJack.chainsawCanCut then
			-- SHOW GREEN RING SELECTOR
				local c = LumberJack.ringColour['green']
				setShaderParameter(chainsaw.ringNode, "colorScale", c[1], c[2], c[3], c[4], false)
			else
			-- SHOW ORANGE/YELLOW RING SELECTOR
				local c = LumberJack.ringColour['yellow']
				setShaderParameter(chainsaw.ringNode, "colorScale", c[1], c[2], c[3], c[4], false)
			end
		end
			
		if LumberJack.originalDefaultCutDuration == nil then
			LumberJack.originalChainsawStartupTime = chainsaw.startupTime
			LumberJack.originalDefaultCutDuration = chainsaw.cutTimePerSquareMeter / 1000
			LumberJack.originalMaximumCutDiameter = chainsaw.maximumCutDiameter --2.5
			LumberJack.originalMaximumDelimbDiameter = chainsaw.maximumDelimbDiameter --1
		end

		if g_currentMission:getHasPlayerPermission('chainsawSettings') then
			-- INCREASE CUTTING SPEED
			chainsaw.startupTime = LumberJack.defaultCutDuration/4 * 1000
			chainsaw.cutTimePerSquareMeter = LumberJack.defaultCutDuration * 1000
		else
			chainsaw.startupTime = LumberJack.originalChainsawStartupTime
			chainsaw.cutTimePerSquareMeter = LumberJack.originalDefaultCutDuration
			chainsaw.maximumCutDiameter = LumberJack.originalMaximumCutDiameter
			chainsaw.maximumDelimbDiameter = LumberJack.originalMaximumDelimbDiameter
		end
		
		-- DESTROY SMALL LOGS WHEN USING THE CHAINSAW --
		if chainsaw.isCutting and chainsaw.currentCutState == 3 then
			-- debugPrint("CHAINSAW CUTTING " .. tostring(chainsaw.currentCutState))

			if not LumberJack.useChainsawFlag and not g_startMissionInfo.isMultiplayer then
				if LumberJack.chainsawShape and entityExists(LumberJack.chainsawShape) then
					local splitShape = LumberJack.chainsawShape
					local volume = getVolume(splitShape)
					if volume < 0.100 then
					-- DELETE THE SHAPE if too small to worry about (e.g. felling wedge or thin branch)
						LumberJack.deleteSplitShape(splitShape)
					end
				end
				LumberJack.useChainsawFlag = true
			end
			
			LumberJack.createSawdust(chainsaw)
		else
			-- debugPrint("CHAINSAW NOT CUTTING " .. tostring(chainsaw.currentCutState))
			local motor = handTool.spec_motorized
			local isChainsawIdle = motor.currentRPM < 1.1*motor.minRPM
			local isChainsawActive = motor.currentRPM > 0.8*motor.maxRPM

			if not LumberJack.chainsawCanCut then

				-- STUMP GRINDING
				if not LumberJack.bushCuttingActive then
					if LumberJack.closestObject and LumberJack.splitShape ~= LumberJack.closestObject then
						local splitShape = LumberJack.closestObject.splitShape
						if splitShape and entityExists(splitShape) then
							LumberJack.splitShape = LumberJack.closestObject
						else
							LumberJack.splitShape = nil
						end
					end
					
					if LumberJack.splitShape and entityExists(LumberJack.splitShape.id) then
					
						if LumberJack.showDebug then
							if LumberJack.splitShape.isStump then
								g_currentMission:addExtraPrintText("Stump")
							elseif LumberJack.splitShape.isTree then
								g_currentMission:addExtraPrintText("Tree")
							elseif LumberJack.splitShape.isBranch then
								g_currentMission:addExtraPrintText("Branch")
							end
						end

						if LumberJack.superStrength then
							local shape = LumberJack.splitShape and LumberJack.splitShape.id
							if shape and entityExists(shape) then
								local rx, _, rz = getWorldTranslation(chainsaw.ringNode)
								LumberJack.stumpGrindingPossible = handTool:testIfCutAllowed(shape, rx, rz)
								if not LumberJack.stumpGrindingPossible then
									debugPrint("Stump Grinding NOT allowed")
								end
							end
						else
							if LumberJack.splitShape.isStump then
								local shape = LumberJack.splitShape and LumberJack.splitShape.id or 0
								local x0,y0,z0 = getWorldTranslation(shape)
								local y = getTerrainHeightAtWorldPos(g_currentMission.terrainRootNode, x0, y0, z0)
								local lenBelow, lenAbove = getSplitShapePlaneExtents(shape, 0,y,0, 0,1,0)

								if lenAbove < 1.5 then
									local rx, _, rz = getWorldTranslation(chainsaw.ringNode)
									LumberJack.stumpGrindingPossible = handTool:testIfCutAllowed(shape, rx, rz)
								else
									if LumberJack.showDebug then
										g_currentMission:addExtraPrintText("Stump is too tall")
									end
								end
								-- g_currentMission:addExtraPrintText(string.format("below:%.3f   above:%.3f", lenBelow,lenAbove))
							end
						end
					-- else
						-- g_currentMission:addExtraPrintText("*** NO SPLITSHAPE AVAILABLE ***")
					end
				end
				
				-- BUSH GRINDING
				if LumberJack.destroyFoliageSize == 0 or LumberJack.stumpGrindingPossible or LumberJack.stumpGrindingActive then
					LumberJack.bushCuttingPossible = false
				else
					LumberJack.updateTargetRaycast()
					if not LumberJack.targetLocation or not LumberJack.targetOnGround then
						LumberJack.bushCuttingPossible = false
					elseif isChainsawIdle or LumberJack.superStrength then
						local shape = LumberJack.targetedSplitShapeId or 0
						local rx, rz = LumberJack.targetLocation[1], LumberJack.targetLocation[3]
						LumberJack.bushCuttingPossible = handTool:testIfCutAllowed(shape, rx, rz) and LumberJack:seekAndDestroyFoliage(rx, rz)
					end
				end

				if LumberJack.stumpGrindingPossible then
				-- SHOW RED RING SELECTOR
					local c = LumberJack.ringColour['red']
					setShaderParameter(chainsaw.ringNode, "colorScale", c[1], c[2], c[3], c[4], false)
				end
				
			else
				-- CHAINSAW HAS FOUND A PLACE TO CUT THE TREE
				
				if LumberJack.chainsawShape and entityExists(LumberJack.chainsawShape) then
					local shape = LumberJack.chainsawShape

					if getVolume(shape) < 0.100 then
						-- SHOW RED RING SELECTOR if too small to worry about (e.g. felling wedge or thin branch)
						-- local c = LumberJack.ringColour.red
						-- setShaderParameter(chainsaw.ringNode, "colorScale", c[1], c[2], c[3], c[4], false)
					else
						-- SHOW DIMENSIONS AFTER NEW CUT
						local function getCutStartEnd(chainsaw)
							local pos = {getWorldTranslation(chainsaw.ringNode)}
							local scale = {getScale(chainsaw.ringNode)}
							local dir = {localDirectionToWorld(chainsaw.ringNode, 0, 1, 0)}
							local startPos = {
								pos[1] - 0.5 * scale[1] * dir[1],
								pos[2] - 0.5 * scale[2] * dir[2],
								pos[3] - 0.5 * scale[3] * dir[3]
							}
							local endPos = {
								pos[1] + 0.5 * scale[1] * dir[1],
								pos[2] + 0.5 * scale[2] * dir[2],
								pos[3] + 0.5 * scale[3] * dir[3]
							}
							return startPos[1], startPos[2], startPos[3], endPos[1], endPos[2], endPos[3]
						end
						local cutStartX, cutStartY, cutStartZ, cutEndX, cutEndY, cutEndZ = getCutStartEnd(chainsaw)
						local x0, y0, z0 = (cutStartX+cutEndX)/2, (cutStartY+cutEndY)/2, (cutStartZ+cutEndZ)/2
						local below, above = getSplitShapePlaneExtents(shape, x0, y0, z0, localDirectionToWorld(shape, 0, 1, 0))
						g_currentMission:addExtraPrintText(g_i18n:getText("infohud_length") .. string.format(":   %.1fm  |  %.1fm", below, above))
	
						-- if LumberJack.showDebug then
							-- drawDebugLine(cutStartX,cutStartY,cutStartZ,1,1,1,cutEndX,cutEndY,cutEndZ,1,1,1)
						-- end
					end
				end
			end
			
			-- GRIND STUMPS USING THE CHAINSAW --
			if LumberJack.stumpGrindingPossible and isChainsawActive then
				LumberJack.stumpGrindingActive = true
				LumberJack.stumpGrindingTime = (LumberJack.stumpGrindingTime or 0) + dt
				if LumberJack.stumpGrindingTime < 3000 then
					-- STUMP GRINDING
					local shape = LumberJack.splitShape and LumberJack.splitShape.id
					if shape and entityExists(shape) then
						local target = {getWorldTranslation(shape)}
						if LumberJack.splitShape.isStump then 
							target[2] = target[2] + 0.5
						elseif LumberJack.splitShape.isTree then 
							target[2] = target[2] + 1.0
						elseif LumberJack.splitShape.isBranch then
							target = LumberJack.targetLocation
						end
						
						setShaderParameter(chainsaw.ringNode, "colorScale", 0, 0, 0, 0, false)
						if target then
							local cutTranslation = {worldToLocal(handTool.graphicalNodeParent, target[1], target[2], target[3])}
							setTranslation(handTool.graphicalNode, cutTranslation[1]/3, cutTranslation[2]/3, cutTranslation[3]/3)
						end
						--handTool:updateParticles()
						LumberJack.createSawdust(chainsaw, 0, target)
					end
				else
					if LumberJack.splitShape then
						debugPrint("DELETE SPLIT SHAPE " .. LumberJack.splitShape.id)
						if LumberJack.deleteSplitShape(LumberJack.splitShape.id) then
							LumberJack.splitShape = nil
						end
					end
					LumberJack.stumpGrindingTime = nil
					LumberJack.stumpGrindingActive = false
					LumberJack.stumpGrindingPossible = false
					LumberJack.createSawdust(chainsaw, -2)
				end
			elseif LumberJack.bushCuttingPossible and isChainsawActive then
				LumberJack.bushCuttingActive = true
				LumberJack.stumpGrindingTime = (LumberJack.stumpGrindingTime or 0) + dt
				if (LumberJack.superStrength and LumberJack.stumpGrindingTime < 100)
				or (not LumberJack.superStrength and LumberJack.stumpGrindingTime < 1000) then
					local target = LumberJack.targetLocation
					local cutTranslation = {worldToLocal(handTool.graphicalNodeParent, target[1], target[2], target[3])}
					setTranslation(handTool.graphicalNode, cutTranslation[1]/5, cutTranslation[2]/5, cutTranslation[3]/5)
					--handTool:updateParticles()
				else
					debugPrint("Bush Cutting - DELETE BUSH")
					local rx, rz = LumberJack.targetLocation[1], LumberJack.targetLocation[3]
					LumberJack:seekAndDestroyFoliage(rx, rz, true)
					LumberJack.stumpGrindingTime = nil
					LumberJack.bushCuttingPossible = false
				end												   
				
			else
				LumberJack.stumpGrindingTime = nil
				LumberJack.bushCuttingActive = false
				LumberJack.stumpGrindingActive = false
			end
			
			if LumberJack.useChainsawFlag then
				LumberJack.useChainsawFlag = false
				
				local abortedCut = LumberJack.chainsawShape and entityExists(LumberJack.chainsawShape)
				if abortedCut then
					debugPrint("ABORTED CUT")
					LumberJack.createSawdust(chainsaw, -2)
				else
					-- debugPrint("COMPLETED CUT")
					LumberJack.createSawdust(chainsaw, -1)
				end
			end
			
			LumberJack.chainsawShape = nil
			LumberJack.chainsawCanCut = nil
		end

	end
end

function LumberJack.moveChainsawCameraFocus(chainsaw, x0, y0, z0)
	if chainsaw ~= nil and chainsaw.chainsawCameraFocus then
		local x,y,z = worldToLocal(getParent(chainsaw.chainsawCameraFocus), x0,y0,z0)
		setTranslation(chainsaw.chainsawCameraFocus, x,y,z)
	end
end

function LumberJack.resetRingSelector(chainsaw)
	if chainsaw ~= nil and chainsaw.ringSelector then
		local x,y,z = getWorldTranslation(chainsaw.chainsawCameraFocus)
		setWorldTranslation(chainsaw.ringSelector, x, y, z)
		setScale(chainsaw.ringSelector, 1, 1, 1)
	end
end

BaseMission.loadMap = Utils.overwrittenFunction(BaseMission.loadMap,
	function(self, superFunc, filename, ...)
		LumberJack.mapI3dFilename = filename
		superFunc(self, filename, ...)
	end
)

function LumberJack.getDecoFunctionData()
	local functionData = LumberJack.decoFunctionData
	
	local function createFoliageModifier(foliage, terrainRootNode)
		if foliage.terrainDataPlaneId and foliage.startStateChannel and foliage.numStateChannels and terrainRootNode then
			local modifier = DensityMapModifier.new(foliage.terrainDataPlaneId, foliage.startStateChannel, foliage.numStateChannels, terrainRootNode)
			modifier:setNewTypeIndexMode(DensityIndexCompareMode.ZERO)
			
			local filter = DensityMapFilter.new(foliage.terrainDataPlaneId, foliage.startStateChannel, foliage.numStateChannels, terrainRootNode)
			filter:setValueCompareParams(DensityValueCompareType.GREATER, 0)
			
			return {modifier = modifier, filter = filter}
		end
	end

	if functionData == nil then
		local terrainRootNode = g_currentMission.terrainRootNode
		local decoFoliages = g_currentMission.foliageSystem.decoFoliages
		local paintableFoliages = g_currentMission.foliageSystem.paintableFoliages
		
		functionData = {
			foliageIsBush = {},
			foliageModifiers = {},
			foliageMultilayers = {},
			foliagesByName = {}
		}
		
		local modifiers = functionData.foliageModifiers
		local foliagesByName = functionData.foliagesByName
		
		debugPrint("DECO FOLIAGES")
		for index, foliage in ipairs(decoFoliages) do
			if foliage and foliage.layerName then
				debugPrint(tostring(foliage.terrainDataPlaneId) .. " [" .. tostring(index) .. "] : " .. tostring(foliage.layerName))
				modifiers[foliage] = modifiers[foliage] or createFoliageModifier(foliage, terrainRootNode)
				foliagesByName[foliage.layerName] = foliagesByName[foliage.layerName] or foliage
			end
		end
		
		debugPrint("PAINTABLE FOLIAGES")
		for index, foliage in ipairs(paintableFoliages) do
			if foliage and foliage.layerName then
				debugPrint(tostring(foliage.terrainDataPlaneId) .. " [" .. tostring(index) .. "] : " .. tostring(foliage.layerName))
				modifiers[foliage] = modifiers[foliage] or createFoliageModifier(foliage, terrainRootNode)
				foliagesByName[foliage.layerName] = foliagesByName[foliage.layerName] or foliage
			end
		end

		if LumberJack.mapI3dFilename then
			local i = 1
			debugPrint("search for bush layers in : " .. tostring(LumberJack.mapI3dFilename))
			
			local xmlFile = XMLFile.load("MapI3d", LumberJack.mapI3dFilename)
			if xmlFile then

				local rootKey = "i3D.Scene.TerrainTransformGroup.Layers.FoliageSystem"
				while true do
					local layerKey = string.format(rootKey..".FoliageMultiLayer(%d)", i-1)
					if not xmlFile:hasProperty(layerKey) then
						break
					end
					local densityMapId = xmlFile:getInt(layerKey.."#densityMapId")
					local numTypeIndexChannels = xmlFile:getInt(layerKey.."#numTypeIndexChannels")
					
					debugPrint("["..i.."] densityMapId: " .. tostring(densityMapId))

					functionData.foliageIsBush[i] = {}
					functionData.foliageMultilayers[i] = {}
					functionData.foliageMultilayers[i].densityMapId = densityMapId
					functionData.foliageMultilayers[i].numTypeIndexChannels = numTypeIndexChannels
					
					local j = 1
					while true do
						local typeKey = string.format(layerKey..".FoliageType(%d)", j-1)
						if not xmlFile:hasProperty(typeKey) then
							break
						end
						local isBush = false
						local layerName = xmlFile:getString(typeKey.."#name", "MISSING")
						
						for _, name in pairs(LumberJack.foliageSearchNames) do
							if string.find(layerName:lower(), name) then
								isBush = true
								local foliage = foliagesByName[layerName]
								if foliage then
									functionData.foliageIsBush[i][j] = foliage
									if not functionData.foliageMultilayers[i].terrainDataPlaneId then
										functionData.foliageMultilayers[i].terrainDataPlaneId = foliage.terrainDataPlaneId
									end
								end
							end
						end
						
						debugPrint(" j="..j.." : " .. tostring(layerName))
						j = j + 1
					end
					
					i = i + 1
				end
				
				xmlFile:delete()
			else
				debugPrint("COULD NOT LOAD MAP FOR FOLIAGE LAYERS")
			end

			LumberJack.decoFunctionData = functionData
		end
	end

	return functionData
end

function LumberJack:removeDeco(startWorldX, startWorldZ, areaSize, destroyAll)
	local functionData = LumberJack.getDecoFunctionData()

	if functionData ~= nil then
		local h = areaSize/2
		for layer, layerData in pairs(functionData.foliageMultilayers) do
			
			local numChannels = layerData.numTypeIndexChannels
			local decoFoliageId = layerData.terrainDataPlaneId
			
			if not decoFoliageId or not numChannels then
				break
			end

			for index, foliage in pairs(functionData.foliageIsBush[layer]) do
				local modifiers = functionData.foliageModifiers[foliage]
				if modifiers.modifier and modifiers.filter then
					modifiers.modifier:setParallelogramWorldCoords(startWorldX-h, startWorldZ-h, startWorldX+h, startWorldZ-h, startWorldX-h, startWorldZ+h, DensityCoordType.POINT_POINT_POINT)
					modifiers.modifier:executeSet(0, modifiers.filter)
				end
			end
		end
	end
end

function LumberJack:seekAndDestroyFoliage(startWorldX, startWorldZ, destroy)
	
	local functionData = LumberJack.getDecoFunctionData()
	
	if functionData ~= nil then
		
		if not functionData.foliageMultilayers then
			debugPrint("NO MULTILAYERS FOUND")
			return
		end
		
		if destroy and LumberJack.destroyAllFoliage then
			debugPrint("DESTROY ALL FOLIAGE")
			LumberJack:removeDeco(startWorldX, startWorldZ, LumberJack.destroyFoliageSize, destroy)
			return
		end

		local foundAny = false
		for layer, layerData in pairs(functionData.foliageMultilayers) do
			
			local numChannels = layerData.numTypeIndexChannels
			local decoFoliageId = layerData.terrainDataPlaneId
			
			if not decoFoliageId or not numChannels then
				break
			end

			local squareSize  = 0.05
			local areaSize = LumberJack.destroyFoliageSize
			local numSquares = math.ceil(areaSize / squareSize)
			local offset = (areaSize - (numSquares * squareSize)) / 2
			for i = 0, numSquares-1 do
				for j = 0, numSquares-1 do
				
					local found = false
					local rx = startWorldX-areaSize/2 + i*squareSize + offset
					local rz = startWorldZ-areaSize/2 + j*squareSize + offset
					
					local bits = getDensityAtWorldPos(decoFoliageId, rx+squareSize/2, 0, rz+squareSize/2)
					local index = numChannels == 0 and 1 or bitAND(bits, 2^numChannels - 1)
					local value = bitShiftRight(bits, numChannels)
					
					if value > 0 and (functionData.foliageIsBush[layer][index] or LumberJack.destroyAllFoliage) then
						found = true
						foundAny = true
					end

					if found and destroy then
						LumberJack:removeDeco(rx, rz, squareSize)
					end
					
					if LumberJack.showDebug then
						local d = 0.025*squareSize
						if found then
							DebugUtil.drawDebugAreaRectangle(rx+d,0,rz+d, rx+squareSize-d,0,rz+d, rx+d,0,rz+squareSize-d, true, 0,0,1)
						end
					end
			  
				end	
			end
			
			if LumberJack.showDebug then
				local n=LumberJack.destroyFoliageSize
				local scale = g_currentMission.terrainSize / getDensityMapSize(decoFoliageId)
				DebugUtil.drawDebugAreaRectangle(startWorldX-n/2,0,startWorldZ-n/2, startWorldX+n/2,0,startWorldZ-n/2, startWorldX-n/2,0,startWorldZ+n/2, true, 1,1,1)
				
				for x = -n, n do
					for z = -n, n do
						local rx,rz = math.floor((startWorldX+x*scale)/scale)*scale, math.floor((startWorldZ+z*scale)/scale)*scale
						local bits = getDensityAtWorldPos(decoFoliageId, startWorldX+x*scale, 0, startWorldZ+z*scale)
						local index = numChannels == 0 and 1 or bitAND(bits, 2^numChannels - 1)
						local value = bitShiftRight(bits, numChannels)
						local valueString = string.format("%d - %d", index, value)
						
						local d = 0.025
						local yg = getTerrainHeightAtWorldPos(g_currentMission.terrainRootNode, rx+scale/2,0,rz+scale/2)
						if value > 0 and (functionData.foliageIsBush[layer][index] or LumberJack.destroyAllFoliage)  then
							DebugUtil.drawDebugAreaRectangle(rx+d,0,rz+d, rx+scale-d,0,rz+d, rx+d,0,rz+scale-d, true, 0,1,0)
							-- Utils.renderTextAtWorldPosition(rx+scale/2, yg+0.1, rz+scale/2, valueString, getCorrectTextSize(0.012), 0, {1,1,1})
						else
							DebugUtil.drawDebugAreaRectangle(rx+d,0,rz+d, rx+scale-d,0,rz+d, rx+d,0,rz+scale-d, true, 0.15,0.15,0.15)
							-- Utils.renderTextAtWorldPosition(rx+scale/2, yg+0.1, rz+scale/2, valueString, getCorrectTextSize(0.012), 0, {0.3,0.3,0.3})
						end
					end
				end
			end

			if LumberJack.showDebug and foundAny then
				g_currentMission:addExtraPrintText("Bush")
			end
		end
		
		return foundAny
	end
end

function LumberJack.getClosestTarget(player)
	
	if player.currentHandTool and player.currentHandTool.spec_chainsaw then
		local chainsaw = player.currentHandTool.spec_chainsaw
		local chainsawCutting = chainsaw.isCutting and chainsaw.currentCutState == 3 
		if chainsawCutting or LumberJack.bushCuttingActive or LumberJack.stumpGrindingActive then
			-- g_currentMission:addExtraPrintText("chainsaw cutting - NO UPDATE")
			return
		end
	end
	
	LumberJack.closestObject = nil

	if not player.targeter.closestTargetsByKey then
		-- debugPrint("NO closestTargetsByKey")
		return
	end
		
	local size = 0
	local distance = math.huge
	for k, v in pairs(player.targeter.closestTargetsByKey) do
		size = size + 1
		if distance > v.distance then
			LumberJack.closestObject = LumberJack.closestObject or {}
			LumberJack.closestObject.id = v.node
			LumberJack.closestObject.distance = v.distance
			
			local splitShapeId, isTree, isStump, isBranch = LumberJack:getSplitShape(v.node)
			LumberJack.closestObject.splitShape = splitShapeId
			LumberJack.closestObject.isTree = isTree
			LumberJack.closestObject.isStump = isStump
			LumberJack.closestObject.isBranch = isBranch
		end
	end

	if LumberJack.closestObject and entityExists(LumberJack.closestObject.id) then
		if LumberJack.closestObject.id ~= LumberJack.lastClosestObjectId then
			LumberJack.lastClosestObjectId = LumberJack.closestObject.id
			
			if LumberJack.closestObject.splitShape then
				-- TODO: client may not know these?
				if LumberJack.closestObject.isTree then
					debugPrint("FOUND TREE: " .. tostring(LumberJack.closestObject.id))
				elseif LumberJack.closestObject.isStump then
					debugPrint("FOUND STUMP: " .. tostring(LumberJack.closestObject.id))
				elseif LumberJack.closestObject.isBranch then
					debugPrint("FOUND BRANCH: " .. tostring(LumberJack.closestObject.id))
				end
				if LumberJack.closestObject.splitShape ~= LumberJack.closestObject.id then
					debugPrint("split shape id = " .. LumberJack.closestObject.splitShape)
				end
			else
				-- debugPrint("FOUND OBJECT: " .. tostring(LumberJack.closestObject.id))
			end
			-- debugPrint(size .. " objects in range")
		end
		return LumberJack.closestObject
	end
end

function LumberJack:doUpdate(dt)
	
	local masterServer = g_masterServerConnection.masterServerCallbackTarget
	local isSaving = masterServer.isSaving
	local isLoadingMap = masterServer.isLoadingMap
	local isExitingGame = masterServer.isExitingGame
	local isSynchronizingWithPlayers = masterServer.isSynchronizingWithPlayers
	if isLoadingMap or isExitingGame or isSaving or isSynchronizingWithPlayers then
		return
	end
	
	LumberJack.startupTime = LumberJack.startupTime or 0
	if LumberJack.startupTime < 1000 then
		LumberJack.startupTime = LumberJack.startupTime + dt
		-- debugPrint("wait for startup.." .. LumberJack.startupTime)
		return
	end

	-- Dedicated Server has no player
	if not g_localPlayer then
		debugPrint("Warning: no player ID")
		return
	end

	local player = g_localPlayer
	local isInVehicle = player:getIsInVehicle()
	
	LumberJack.playerIsEntered = player.isControlled and not isInVehicle

	if LumberJack.playerIsEntered and not g_gui:getIsGuiVisible() then
	
		-- CHANGE GLOBAL VALUES ON FIRST RUN
		if not LumberJack.initialised then
			debugPrint("*** LumberJack - DEBUG ENABLED ***")
			
			LumberJack.getDecoFunctionData()
			
			LumberJack:registerActionEvents()
			
			LumberJack.initialised = true
		end
		
		LumberJack.getClosestTarget(player)
		-- IF OBSERVING AN OBJECT
		if LumberJack.closestObject then
			-- Display Mass of LAST OBSERVED OBJECT in 'F1' Help Menu
			local object = LumberJack.closestObject.id
			if not player.currentHandToolIndex then
				g_currentMission:addExtraPrintText(g_i18n:getText("text_MASS") .. string.format(": %.1f ", 1000*(getMass(object) or 1)) .. g_i18n:getText("text_KG"))
			end
		end
		
		LumberJack.updateStrength(dt)
		LumberJack.updateVariables(dt)
		LumberJack.updateChainsaw(dt)
		
		-- if player.isHoldingChainsaw then
			-- if LumberJack.bushCuttingActive then
				-- g_currentMission:addExtraPrintText("Bush Cutting: ACTIVE")
			-- else
				-- g_currentMission:addExtraPrintText("Bush Cutting Possible: " .. tostring(LumberJack.bushCuttingPossible))
			-- end
			
			-- if LumberJack.stumpGrindingActive then
				-- g_currentMission:addExtraPrintText("Stump Grinding: ACTIVE")
			-- else
				-- g_currentMission:addExtraPrintText("Stump Grinding Possible: " .. tostring(LumberJack.stumpGrindingPossible))
			-- end
		-- end

	end	
	
end

function LumberJack:update(dt)

	if LumberJack.stopError then
		if not LumberJack.printedError then
			LumberJack.printedError = true
			print("LumberJack - FATAL ERROR: " .. LumberJack.result)
		end
		return
	end
	
	local status, result = pcall(LumberJack.doUpdate, self, dt)

	if not status then
		LumberJack.stopError = true
		LumberJack.result = result
	end
end


function LumberJack.createSawdust(chainsaw, amount, position, noEventSend)

	if LumberJack.createWoodchips and chainsaw then
		if g_currentMission:getIsServer() then
			local fillTypeIndex = FillType.WOODCHIPS
			local minAmount = g_densityMapHeightManager:getMinValidLiterValue(fillTypeIndex)
		
			local delta
			if amount == -2 then
				-- debugPrint("empty all sawdust = 0")
				delta = 0
				chainsaw.totalSawdust = 0
			elseif amount == -1 then
				-- debugPrint("set minimum sawdust = " .. minAmount)
				delta = minAmount
			else
				local speed = chainsaw.cutTimePerSquareMeter or 4000
				delta = (60/(speed/1000) * (math.random(50, 100)/100) * (g_currentDt/1000)) + (amount or 0)
			end
			
			chainsaw.totalSawdust = chainsaw.totalSawdust or 0
			chainsaw.totalSawdust = chainsaw.totalSawdust + delta

			if chainsaw.totalSawdust >= minAmount then
				-- debugPrint("DROP SAWDUST " .. chainsaw.totalSawdust)
				local positionNode = chainsaw.cutNode or chainsaw.cutGuideNode or chainsaw.ringNode
				if not positionNode and not position then
					-- debugPrint("NO DROP POSITION NODE FOUND")
					chainsaw.totalSawdust = 0
					return
				end
				
				local pos = positionNode and {getWorldTranslation(positionNode)} or position
				if positionNode and position then
					pos[1] = position[1]
					pos[3] = position[3]
				end
				
				local sx, sy, sz = pos[1], pos[2], pos[3]
				local ex, ey, ez = sx, sy, sz
				
				if LumberJack.useChainsawFlag and not LumberJack.stumpGrindingPossible then
					local rand = math.random(50, 100)/100
					local dx, _, dz = localDirectionToWorld(positionNode, 0, 1, 0)
					sx = sx + (rand * math.min(3, dx))
					sz = sz + (rand * math.min(3, dz))
				end

				local innerRadius = 0
				local outerRadius = DensityMapHeightUtil.getDefaultMaxRadius(fillTypeIndex)
				local dropped, lineOffset = DensityMapHeightUtil.tipToGroundAroundLine(nil,
					chainsaw.totalSawdust, fillTypeIndex, sx, sy, sz, ex, ey, ez, innerRadius, outerRadius)
				
				chainsaw.totalSawdust = chainsaw.totalSawdust - dropped
				
				if dropped == 0 then
					-- debugPrint("COULDN'T DROP SAWDUST HERE")
					chainsaw.totalSawdust = 0
				end
			end

		else
			CreateSawdustEvent.sendEvent(g_localPlayer, amount, position, noEventSend)
		end
	end

end

function LumberJack.deleteSplitShape(shape, noEventSend)

	if shape and entityExists(shape) then
		if g_currentMission:getIsServer() then

			local volume = getVolume(shape)
			local splitType = g_splitShapeManager:getSplitTypeByIndex(getSplitType(shape))
			local amount = volume * splitType.volumeToLiter * splitType.woodChipsPerLiter / 5
			if amount > LumberJack.maxWoodchips then amount = LumberJack.maxWoodchips end
			-- debugPrint("amount: " .. tostring(amount))
			local chainsaw = g_localPlayer.currentHandTool.spec_chainsaw
			local cutPosition = {getWorldTranslation(shape)}
			LumberJack.createSawdust(chainsaw, amount, cutPosition)
		
			g_currentMission:removeKnownSplitShape(shape)
			local isTree = getRigidBodyType(shape) == RigidBodyType.STATIC
			-- debugPrint("split shape is TREE = " .. tostring(isTree))
			
			if isTree then
				local lodId = shape+2
				if entityExists(lodId) and getName(lodId) == 'LOD1' then
					debugPrint("DELETE LOD1 " .. lodId)
					delete(lodId)
				end
			end
			
			if entityExists(shape) then
				if isTree then
					debugPrint("DELETE LOD0 " .. shape)
				else
					debugPrint("DELETE " .. shape)
				end
				delete(shape)
				g_densityMapHeightManager:consoleCommandUpdateTipCollisions()
				return true
			end
		else
			DeleteShapeEvent.sendEvent(shape)
		end
	else
		debugPrint("split shape id " .. shape .. " NOT VALID")
	end

end

function LumberJack.cutSplitShapeCallback(unused, shape, isBelow, isAbove, minY, maxY, minZ, maxZ)
    if shape ~= nil then
		table.insert(LumberJack.cutShapes, {
			shape = shape,
			isBelow = isBelow,
			isAbove = isAbove,
			minY = minY,
			maxY = maxY,
			minZ = minZ,
			maxZ = maxZ
		})
    end
end
