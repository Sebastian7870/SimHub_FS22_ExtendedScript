-- SimHub Telemetry mod
-- 2020 - Wotever
-- This mod can be freely modified as long as it stays used in conjonction with SimHub
-- Simhub will automatically discover any new telemetry data being added to the output
--
SHTelemetry = {}
SHTelemetry.currentModDirectory = g_currentModDirectory
SHTelemetry.currentModName = g_currentModName
SHTelemetryContext = {}
SHTelemetryContext.isLoaded = false
SHTelemetryContext.updateCount = 0
SHTelemetryContext.pipeName = "\\\\.\\pipe\\SHTelemetry"
SHTelemetryContext.tabdata = {}
SHTelemetryContext.tabLength = 1
SHTelemetryContext.lastTelemetryRefresh = 0

function SHTelemetry:initialize()
    addConsoleCommand("shtPrintTelemetryData", "Prints the current telemetry data into the console", "consoleCommandPrintTelemetryData", self)
end
SHTelemetry:initialize()


source(SHTelemetry.currentModDirectory .. "utilities/utilities.lua")
S7870_Tools:init(SHTelemetry.currentModName)


-- settings
SHTelemetryContext.refreshRate = 1 -- not milliseconds, based on game's refresh rate (500 ≙ ~9 s)
SHTelemetry.maxFillLevelDepth = 5
SHTelemetry.maxFillLevelAmount = 6
SHTelemetry.Debug = true


-- local functions
local function getFormattedOperatingTime(operatingTime)
    if operatingTime then
        local minutes = operatingTime / (1000 * 60)
        local hours = math.floor(minutes / 60)
        minutes = math.floor((minutes - hours * 60) / 6)
        local minutesString = string.format("%02d", minutes * 10)
        return tonumber(hours .. "." .. minutesString)
    else
        return tonumber("0.0")
    end
end

local function addFillLevelToTable(fillLevel, fillType, capacity, mass, fillLevelTable)
    if fillLevel > 0 then
        if (fillLevelTable[fillType] ~= nil) then
            fillLevelTable[fillType]["level"] = fillLevelTable[fillType]["level"] + fillLevel
            fillLevelTable[fillType]["capacity"] = fillLevelTable[fillType]["capacity"] + capacity
            fillLevelTable[fillType]["mass"] = fillLevelTable[fillType]["mass"] + mass
        else
            fillLevelTable[fillType] = {
                level = fillLevel,
                capacity = capacity,
                mass = mass
            }
        end
    end
end

local function getLargestNumberOfAttachedImplement(device, level)
    local level = level or 1
    local returnValue = level -- default value is one because the device given when calling this function is already present 

    if device ~= nil and device.spec_attacherJoints ~= nil and device.spec_attacherJoints.attacherJoints ~= nil then
        for _, implement in ipairs(device.spec_attacherJoints.attachedImplements) do
            local childValue = getLargestNumberOfAttachedImplement(implement.object, level + 1)
            if childValue > returnValue then
                returnValue = childValue
            end
        end
    end

    return returnValue
end

local function getFillLevelFromFillUnit(fillUnit)
    local fillType = fillUnit.fillType
    if fillUnit.capacity > 0 and fillUnit.showOnHud then
        if fillType == FillType.UNKNOWN and table.size(fillUnit.supportedFillTypes) == 1 then
            fillType = next(fillUnit.supportedFillTypes)
        end

        if fillUnit.fillTypeToDisplay ~= FillType.UNKNOWN then
            fillType = fillUnit.fillTypeToDisplay
        end

        local fillLevel = fillUnit.fillLevel
        if fillUnit.fillLevelToDisplay ~= nil then
            fillLevel = fillUnit.fillLevelToDisplay
        end

        fillLevel = math.ceil(fillLevel)

        local capacity = fillUnit.capacity or fillLevel

        if fillUnit.parentUnitOnHud ~= nil then
            if fillType == FillType.UNKNOWN then
                fillType = fillUnits[fillUnit.parentUnitOnHud].fillType;
            end
            capacity = 0
        elseif fillUnit.childUnitOnHud ~= nil and fillType == FillType.UNKNOWN then
            fillType = fillUnits[fillUnit.childUnitOnHud].fillType
        end

        local fillTypeDesc = g_fillTypeManager:getFillTypeByIndex(fillType)
        local mass = 0
        if fillTypeDesc ~= nil then
            mass = fillLevel * fillTypeDesc.massPerLiter * 1000
        else
            mass = fillLevel
        end

        if fillLevel > 0 then
            return fillLevel, fillType, capacity, mass
        end
    end
end

local function getIsFoldable(device)
    local spec = device.spec_foldable
    return spec ~= nil and spec.foldingParts ~= nil and #spec.foldingParts > 0
end

local function getMoveToolValueAndPercent(movingTool)
    if movingTool == nil then return nil end

    local transOrRot, transOrRotPercentage
    local hasRotation = (movingTool.rotationAxis and movingTool.curRot) or false
    local hasTranslation = (movingTool.translationAxis and movingTool.curTrans) or false

    if hasRotation then
        local curRot = movingTool.curRot[movingTool.rotationAxis]
        transOrRot = math.deg(curRot) * -1
        if movingTool.rotMin and movingTool.rotMax then
            transOrRotPercentage = (curRot - movingTool.rotMin) / (movingTool.rotMax - movingTool.rotMin)
        end
    end

    -- sometimes a rotationAxis is given even if the movingTool cannot rotate, thus a workaround had to be found.
    if hasTranslation and (not hasRotation or transOrRot == 0) then
        transOrRot = movingTool.curTrans[movingTool.translationAxis]
        if movingTool.transMin and movingTool.transMax then
            transOrRotPercentage = (transOrRot - movingTool.transMin) / (movingTool.transMax - movingTool.transMin)
        end
    end

    return transOrRot, transOrRotPercentage
end

local function checkImplementStatusRecursively(device, functionName, returnImplement, skipCurrentImplement)
    if device == nil then
        return false
    end

    skipCurrentImplement = skipCurrentImplement or false

    local functionMethod = functionName
    if type(functionName) == "string" then
        functionMethod = device[functionName]
    end

    local result = false
    local returnDevice = nil
    if not skipCurrentImplement then
        result = functionMethod and functionMethod(device, false)
        returnDevice = result and device or nil
    end

    if not result and device.getAttachedImplements then
        local implements = device:getAttachedImplements()
        for _, implement in pairs(implements) do
            local newDevice = implement.object
            result, returnDevice = checkImplementStatusRecursively(newDevice, functionName, returnImplement, false)
        end
    end

    if returnImplement then
        return result, returnDevice
    else
        return result
    end
end

local function findSpecializationRecursively(device, specName)
    if device ~= nil and device[specName] ~= nil then
        return device[specName], device
    elseif device ~= nil and device.getAttachedImplements ~= nil then
        local implements = device:getAttachedImplements()
        for _, implement in pairs(implements) do
            local spec, newDevice = findSpecializationRecursively(implement.object, specName)
            if spec ~= nil then
                return spec, newDevice
            end
        end
    else
        return nil, nil
    end
end

local function getIsFrontImplement(transform, rootVehicle)
    if transform ~= nil and rootVehicle ~= nil then
        local worldX, worldY, worldZ = getWorldTranslation(transform)
        local _, _, localZ = worldToLocal(rootVehicle.rootNode, worldX, worldY, worldZ)

        local positionString = ""
        if localZ > 0 then
            -- Implement is attached at the front
            return true
        else
            -- Implement is attached at the back
            return false
        end
    end
    LogMessage("Function \"isFrontImplement(transform, rootVehicle)\": transform or rootVehicle is nil. Unexpected values might be a consequence.")
end

local function hasFrontloader(rootVehicle)
    if rootVehicle ~= nil then
        
    end
end

local function logWrongValueType(name, value)
    LogMessage(string.format("Wrong type found in Telemetry data, arguments: name=%s, value=%s", tostring(name), tostring(value)))
end

-- global functions
function SHTelemetry:buildTelemetry()
    SHTelemetryContext.tabdata = {}
    SHTelemetryContext.tabLength = 1
    -- Start
    self:addRawStringToTelemetry("{")

    local mission = g_currentMission
    local farmId = g_currentMission:getFarmId()
    local farm
    if farmId ~= nil and farmId ~= FarmManager.SPECTATOR_FARM_ID and g_farmManager.getFarmById then 
        farm = g_farmManager:getFarmById(farmId) 
    end

    -- Mission / Environment
    if farm ~= nil and farm.money ~= nil then 
        self:addNumberToTelemetry("money", farm.money)
    end
    self:addNumberToTelemetry("dayTime", mission.environment.currentHour * 3600 + mission.environment.currentMinute * 60)
    self:addNumberToTelemetry("day", mission.environment.currentDay)
    self:addFloatToTelemetry("timeScale", mission.missionInfo.timeScale)
    self:addNumberToTelemetry("playTime", mission.missionInfo.playTime)
    --Sebastian7870:
    self:addNumberToTelemetry("currentDayInPeriod", mission.environment.currentDayInPeriod)
    self:addNumberToTelemetry("currentPeriod", mission.environment.currentPeriod)
    self:addStringToTelemetry("currentPeriodName", g_i18n:formatDayInPeriod(nil, nil, true))
    self:addNumberToTelemetry("currentSeason", mission.environment.currentSeason)
    self:addNumberToTelemetry("currentYear", mission.environment.currentYear)

    self:addNumberToTelemetry("currentWeather", mission.environment.weather:getCurrentWeatherType())
    local sixHours = 6 * 60 * 60 * 1000
    local dayPlus6h, timePlus6h = mission.environment:getDayAndDayTime(mission.environment.dayTime + sixHours, mission.environment.currentMonotonicDay)
    self:addNumberToTelemetry("nextWeather", mission.environment.weather:getNextWeatherType(dayPlus6h, timePlus6h))
    
    self:addNumberToTelemetry("currentTemperaturInC", g_i18n:getTemperature(mission.environment.weather:getCurrentTemperature()))

    -- Vehicle
    if (g_currentMission.controlledVehicle ~= nil) then
        local vehicle = g_currentMission.controlledVehicle

        -- Content
        tabLength = self:addBoolToTelemetry("isInVehicle", true)
        tabLength = self:addStringToTelemetry("vehicleName", mission.currentVehicleName)
        if (vehicle.spec_motorized ~= nil) then
            local engine = vehicle:getMotor()
            local fuelLevel, fuelCapacity = self:getVehicleFuelLevelAndCapacity(vehicle)
            local lastFuelUsage = vehicle.spec_motorized.lastFuelUsage
            local spec_motorized = vehicle.spec_motorized
            local spec_lights = vehicle.spec_lights
            local motorFan = vehicle.spec_motorized.motorFan
            local motorTemperature = vehicle.spec_motorized.motorTemperature
            local cruiseControl = vehicle.spec_drivable.cruiseControl
            local cruiseControlSpeed = cruiseControl.speed
            local reverserDirection = vehicle.getReverserDirection == nil and 1 or vehicle:getReverserDirection()
            local isReverseDriving = vehicle:getLastSpeed() > spec_motorized.reverseDriveThreshold and vehicle.movingDirection ~= reverserDirection
            local mass = vehicle:getTotalMass(true)
            local massTotal = vehicle:getTotalMass()

            -- Miscellaneous variables
            local selectedObject = vehicle:getSelectedVehicle()

            -- Moves and basic engine
            self:addBoolToTelemetry("isMotorStarted", spec_motorized.isMotorStarted)
            self:addBoolToTelemetry("isReverseDriving", isReverseDriving)
            self:addBoolToTelemetry("isReverseDirection", vehicle.movingDirection == reverserDirection)
            self:addNumberToTelemetry("maxRpm", engine:getMaxRpm())
            self:addNumberToTelemetry("minRpm", engine:getMinRpm())
            self:addNumberToTelemetry("Rpm", (vehicle.spec_motorized.motor:getLastModulatedMotorRpm() or 0))
            self:addFloatToTelemetry("speed", vehicle:getLastSpeed())
            self:addNumberToTelemetry("fuelLevel", fuelLevel)
            self:addNumberToTelemetry("fuelCapacity", fuelCapacity)
            self:addFloatToTelemetry("lastFuelUsage", lastFuelUsage)
            local isPTOActive, ptoRPM = checkImplementStatusRecursively(vehicle, "getIsPowerTakeOffActive"), 0
            if isPTOActive then ptoRPM = vehicle.spec_motorized.motor:getLastModulatedMotorRpm() end
            self:addNumberToTelemetry(string.format("ptoRPM", positionString), ptoRPM)
            self:addFloatToTelemetry("mass", mass)
            self:addFloatToTelemetry("massTotal", massTotal)


            -- Temps
            self:addNumberToTelemetry("motorTemperature", motorTemperature.value)
            self:addBoolToTelemetry("motorFanEnabled", motorFan.enabled)

            -- Cruise control
            self:addNumberToTelemetry("cruiseControlMaxSpeed", cruiseControlSpeed)
            self:addBoolToTelemetry("cruiseControlActive", cruiseControl.state ~= Drivable.CRUISECONTROL_STATE_OFF)

            -- Lights
            local alpha = MathUtil.clamp((math.cos(7 * getShaderTimeSec()) + 0.2), 0, 1)
            local leftIndicator = spec_lights ~= nil and (spec_lights.turnLightState == Lights.TURNLIGHT_LEFT or spec_lights.turnLightState == Lights.TURNLIGHT_HAZARD) and alpha > 0.5
            local rightIndicator = spec_lights ~= nil and (spec_lights.turnLightState == Lights.TURNLIGHT_RIGHT or spec_lights.turnLightState == Lights.TURNLIGHT_HAZARD) and alpha > 0.5
            self:addBoolToTelemetry("leftTurnIndicator", leftIndicator)
            self:addBoolToTelemetry("rightTurnIndicator", rightIndicator)
            self:addBoolToTelemetry("beaconLightsActive", spec_lights.beaconLightsActive)

            -- ###########################   Sebastian7870   ###########################
            -- Selection Information:
            self:addSelectionInformation(vehicle)

            -- General Information:
            self:addNumberToTelemetry("currentDirection", vehicle.spec_motorized.motor.currentDirection)

            local x1, y1, z1 = localToWorld(vehicle.rootNode, 0, 0, 0)
            local x2, y2, z2 = localToWorld(vehicle.rootNode, 0, 0, 1)
            local dx, dz = x2 - x1, z2 - z1

            local heading = 180 - (180 / math.pi) * math.atan2(dx, dz)
            self:addFloatToTelemetry("heading", heading)

            local farmlandID = 0
			local x, _, z = getWorldTranslation(vehicle.rootNode)
			local farmland = g_farmlandManager:getFarmlandAtWorldPosition(x, z)
			local dist = math.huge
			if farmland ~= nil then
				local fields = g_fieldManager.farmlandIdFieldMapping[farmland.id]
				if fields ~= nil then
					for _, field in pairs(fields) do
						local rx, rz = field.posX, field.posZ
						local dx, dz = rx - x, rz - z
						local rdist = math.sqrt(dx^2 + dz^2)
						dist = math.min(dist, rdist)				
						if rdist == dist then farmlandID = field.fieldId end
					end
				end
			end
			self:addNumberToTelemetry("farmlandID", farmlandID)

            -- Vehicle Information:
            local spec_powerConsumer = vehicle.spec_powerConsumer
            if vehicle.getIsPowerTakeOffActive ~= nil and vehicle:getIsPowerTakeOffActive() ~= nil and spec_powerConsumer ~= nil then
                self:addBoolToTelemetry("vehicle_isPTOActive", vehicle:getIsPowerTakeOffActive())
            end
            
            if getIsFoldable(vehicle) and vehicle:getIsUnfolded() ~= nil then
                local isFoldable = getIsFoldable(vehicle)
                local isUnfolded = false
                local unfoldingState = 0
                if isFoldable then
                    local spec_foldable = vehicle.spec_foldable
                    if spec_foldable.foldAnimTime <= 1 then
                        unfoldingState = 1 - spec_foldable.foldAnimTime
                    else
                        unfoldingState = 0
                    end
                    isUnfolded = vehicle:getIsUnfolded()
                end

                self:addBoolToTelemetry("vehicle_isUnfolded", isUnfolded)
                self:addFloatToTelemetry("vehicle_unfoldingState", unfoldingState)
            end

            local spec_powerTakeOffs = vehicle.spec_powerTakeOffs
            local hasFrontPTO = false
            local hasBackPTO = false
            if spec_powerTakeOffs ~= nil and spec_powerTakeOffs.outputPowerTakeOffs ~= nil then
                for _, powerTakeOff in ipairs(spec_powerTakeOffs.outputPowerTakeOffs) do
                    local worldX, worldY, worldZ = getWorldTranslation(powerTakeOff.outputNode)
                    local _, _, localZ = worldToLocal(vehicle.rootNode, worldX, worldY, worldZ)
                    if localZ > 0 then
                        -- has front pto
                        hasFrontPTO = true
                    else
                        -- has back pto
                        hasBackPTO = true
                    end
                end
            end
            self:addBoolToTelemetry("hasFrontPTO", hasFrontPTO)
            self:addBoolToTelemetry("hasBackPTO", hasBackPTO)

            -- FillLevel Information:

            local currentFillLevels = {}
            self:getAllFillLevels(vehicle, currentFillLevels, 0)
            local f_index = 1
            for fillTypeIndex, fillTypeInfo in pairs(currentFillLevels) do
                local fillTypeTitle = g_fillTypeManager:getFillTypeTitleByIndex(fillTypeIndex) or "UNKNOWN"
                local fillLevelPercentage = fillTypeInfo.level / fillTypeInfo.capacity

                self:addNumberToTelemetry("fillLevel_" .. tostring(f_index), fillTypeInfo.level)
                self:addNumberToTelemetry("fillLevelCapacity_" .. tostring(f_index), fillTypeInfo.capacity)
                self:addFloatToTelemetry("fillLevelPercentage_" .. tostring(f_index), fillLevelPercentage)
                self:addFloatToTelemetry("fillLevelMass_" .. tostring(f_index), fillTypeInfo.mass)
                self:addStringToTelemetry("fillLevelName_" .. tostring(f_index), fillTypeTitle)

                f_index = f_index + 1
                if f_index >= SHTelemetry.maxFillLevelAmount then
                    break
                end
            end

            -- AttacherJoint Information:

            local axis_frontloaderArm_arm_transform
            local axis_frontloaderArm_arm_transformPercentage
            local axis_frontloaderArm_arm2_transform
            local axis_frontloaderArm_arm2_transformPercentage
            local axis_frontloaderArm_tool_transform
            local axis_frontloaderArm_tool_transformPercentage
            local axis_frontloaderArm_tool2_transform
            local axis_frontloaderArm_tool2_transformPercentage
            local axis_frontloaderArm_tool3_transform
            local axis_frontloaderArm_tool3_transformPercentage
            local axis_frontloaderArm_tool4_transform
            local axis_frontloaderArm_tool4_transformPercentage
            local axis_frontloaderArm_tool5_transform
            local axis_frontloaderArm_tool5_transformPercentage
            local axis_cutter_reel_transform
            local axis_cutter_reel_transformPercentage
            local axis_cutter_reel2_transform
            local axis_cutter_reel2_transformPercentage

            local spec_attacherJoints = vehicle.spec_attacherJoints
            if spec_attacherJoints ~= nil then
                -- These variables have to be nil to be skipped by the if-statement below if no new data arrives
                local implement_index1_tippingState = nil
                local implement_index1_tippingProgress = nil
                local implement_index1_tipSideName = nil
                local implement_index2_tippingState = nil
                local implement_index2_tippingProgress = nil
                local implement_index2_tipSideName = nil

                for jointIndex, attacherJoint in ipairs(spec_attacherJoints.attacherJoints) do
                    -- LogDebugMessage(string.format("index: %s  |  jointType: %s", jointIndex, attacherJoint.jointType))

                    local implement = vehicle:getImplementFromAttacherJointIndex(tonumber(jointIndex))
                    if implement ~= nil and implement.object ~= nil then

                        local isFrontImplement = getIsFrontImplement(attacherJoint.jointTransform, vehicle)
                        local positionString = ""
                        if isFrontImplement then
                            -- Implement is attached at the front
                            positionString = "front"
                        else
                            -- Implement is attached at the back
                            positionString = "back"
                        end

                        -- get largest amount of attached implements
                        local selectableObjects = getLargestNumberOfAttachedImplement(implement.object)
                        local selectableObjectsString = positionString
                        if attacherJoint.jointType == AttacherJoints.JOINTTYPE_ATTACHABLEFRONTLOADER then
                            selectableObjectsString = "frontloader"
                        end
                        self:addNumberToTelemetry(string.format("selectableObjects_%s", selectableObjectsString), selectableObjects)

                        local isLowered = checkImplementStatusRecursively(implement.object, "getIsLowered")

                        local isFoldable, returnedImplement = checkImplementStatusRecursively(implement.object, getIsFoldable, true)
                        local isUnfolded = false
                        local unfoldingState = 0
                        if returnedImplement ~= nil and isFoldable then
                            local spec_foldable = returnedImplement.spec_foldable
                            if spec_foldable ~= nil and spec_foldable.foldAnimTime <= 1 then
                                unfoldingState = 1 - spec_foldable.foldAnimTime
                            else
                                unfoldingState = 0
                            end

                            isUnfolded = checkImplementStatusRecursively(returnedImplement, "getIsUnfolded")
                        end

                        local isPTOActive = checkImplementStatusRecursively(implement.object, "getIsPowerTakeOffActive")

                        local attacherJoint_moveAlpha
                        if attacherJoint ~= nil and attacherJoint.moveAlpha ~= nil then
                            attacherJoint_moveAlpha = 1 - attacherJoint.moveAlpha
                        else
                            attacherJoint_moveAlpha = 0
                        end

                        -- if a frontloader is mounted, tool information will be sent:
                        if attacherJoint.jointType == AttacherJoints.JOINTTYPE_ATTACHABLEFRONTLOADER then
                            local spec_cylindered = implement.object.spec_cylindered
                            if spec_cylindered ~= nil then
                                local movingTools = spec_cylindered.movingTools or {}
                                for _, movingTool in ipairs(movingTools) do
                                    local axis = movingTool.axis or ""

                                    if axis == "AXIS_FRONTLOADER_ARM" then
                                        axis_frontloaderArm_arm_transform, axis_frontloaderArm_arm_transformPercentage = getMoveToolValueAndPercent(movingTool)
                                    elseif axis == "AXIS_FRONTLOADER_ARM2" then
                                        axis_frontloaderArm_arm2_transform, axis_frontloaderArm_arm2_transformPercentage = getMoveToolValueAndPercent(movingTool)
                                    elseif axis == "AXIS_FRONTLOADER_TOOL" then
                                        axis_frontloaderArm_tool_transform, axis_frontloaderArm_tool_transformPercentage = getMoveToolValueAndPercent(movingTool)
                                    elseif axis == "AXIS_FRONTLOADER_TOOL2" then
                                        axis_frontloaderArm_tool2_transform, axis_frontloaderArm_tool2_transformPercentage = getMoveToolValueAndPercent(movingTool)
                                    elseif axis == "AXIS_FRONTLOADER_TOOL3" then
                                        axis_frontloaderArm_tool3_transform, axis_frontloaderArm_tool3_transformPercentage = getMoveToolValueAndPercent(movingTool)
                                    elseif axis == "AXIS_FRONTLOADER_TOOL4" then
                                        axis_frontloaderArm_tool4_transform, axis_frontloaderArm_tool4_transformPercentage = getMoveToolValueAndPercent(movingTool)
                                    elseif axis == "AXIS_FRONTLOADER_TOOL5" then
                                        axis_frontloaderArm_tool5_transform, axis_frontloaderArm_tool5_transformPercentage = getMoveToolValueAndPercent(movingTool)
                                    end
                                end
                            end
                        elseif attacherJoint.jointType == AttacherJoints.JOINTTYPE_CUTTER then
                            local spec_cylindered = implement.object.spec_cylindered
                            if spec_cylindered ~= nil then
                                local movingTools = spec_cylindered.movingTools or {}
                                for _, movingTool in ipairs(movingTools) do
                                    local axis = movingTool.axis or ""

                                    if axis == "AXIS_CUTTER_REEL" then
                                        axis_cutter_reel_transform, axis_cutter_reel_transformPercentage = getMoveToolValueAndPercent(movingTool)
                                    elseif axis == "AXIS_CUTTER_REEL2" then
                                        axis_cutter_reel2_transform, axis_cutter_reel2_transformPercentage = getMoveToolValueAndPercent(movingTool)
                                    end
                                end
                            end
                        end

                        -- variables seperated in front and back implements:
                        self:addStringToTelemetry(string.format("implement_%s_name", positionString), implement.object:getFullName())
                        self:addBoolToTelemetry(string.format("implement_%s_isLowered", positionString), isLowered)
                        self:addBoolToTelemetry(string.format("implement_%s_isUnfolded", positionString), isUnfolded)
                        self:addFloatToTelemetry(string.format("implement_%s_unfoldingState", positionString), unfoldingState)
                        self:addBoolToTelemetry(string.format("implement_%s_isPTOActive", positionString), isPTOActive)
                        self:addFloatToTelemetry(string.format("implement_%s_attacherJoint_moveAlpha", positionString), attacherJoint_moveAlpha)
                        self:addFloatToTelemetry(string.format("implement_%s_workingWidth", positionString), workingWidth)

                        -- tipState
                        local result, returnedTrailer = checkImplementStatusRecursively(implement.object, "getTipState", true)
                        local spec_trailer_index1
                        if returnedTrailer ~= nil then
                            spec_trailer_index1 = returnedTrailer.spec_trailer
                        end

                        if spec_trailer_index1 ~= nil and result ~= nil and type(result) == "number" and returnedTrailer ~= nil then
                            implement_index1_tippingState = result

                            if spec_trailer_index1.tipSides ~= nil then
                                local tipSide = spec_trailer_index1.tipSides[spec_trailer_index1.currentTipSideIndex]
                                implement_index1_tippingProgress = tipSide ~= nil and returnedTrailer:getAnimationTime(tipSide.animation.name) or 0
                                local tipSideIndex = spec_trailer_index1.preferedTipSideIndex or 0

                                implement_index1_tipSideName = spec_trailer_index1.tipSides[tipSideIndex] ~= nil and spec_trailer_index1.tipSides[tipSideIndex].name or " "
                            end

                            local result, returnedTrailer2 = checkImplementStatusRecursively(returnedTrailer, "getTipState", true, true)
                            result = result or 0
                            local spec_trailer_index2
                            if returnedTrailer2 ~= nil then
                                spec_trailer_index2 = returnedTrailer2.spec_trailer
                            end

                            if spec_trailer_index2 ~= nil and result ~= nil and type(result) == "number" and returnedTrailer2 ~= nil then
                                implement_index2_tippingState = result

                                if spec_trailer_index2.tipSides ~= nil then
                                    local tipSide = spec_trailer_index2.tipSides[spec_trailer_index2.currentTipSideIndex]
                                    implement_index2_tippingProgress = tipSide ~= nil and returnedTrailer2:getAnimationTime(tipSide.animation.name) or 0
                                    local tipSideIndex = spec_trailer_index2.preferedTipSideIndex or 0

                                    implement_index2_tipSideName = spec_trailer_index2.tipSides[tipSideIndex] ~= nil and spec_trailer_index2.tipSides[tipSideIndex].name or " "
                                end
                            end
                        end
                    end
                end

                -- Outside of the loop to prevent nil values (if for example an implement attached on the front has no trailer attached to it but there are trailers at the back)
                -- Data will only be added if the values are not nil.
                self:addNumberToTelemetry("implement_index1_tippingState", implement_index1_tippingState)
                self:addNumberToTelemetry("implement_index1_tippingProgress", implement_index1_tippingProgress)
                self:addStringToTelemetry("implement_index1_tipSideName", implement_index1_tipSideName)

                self:addNumberToTelemetry("implement_index2_tippingState", implement_index2_tippingState)
                self:addNumberToTelemetry("implement_index2_tippingProgress", implement_index2_tippingProgress)
                self:addStringToTelemetry("implement_index2_tipSideName", implement_index2_tipSideName)
            end

            -- MovingTools Information (Frontloader, telehandler, etc.):

            local axis_craneArm_arm_transform
            local axis_craneArm_arm_transformPercentage
            local axis_craneArm_arm2_transform
            local axis_craneArm_arm2_transformPercentage
            local axis_craneArm_arm3_transform
            local axis_craneArm_arm3_transformPercentage
            local axis_craneArm_arm4_transform
            local axis_craneArm_arm4_transformPercentage
            local axis_craneArm_tool_transform
            local axis_craneArm_tool_transformPercentage
            local axis_craneArm_tool2_transform
            local axis_craneArm_tool2_transformPercentage
            local axis_craneArm_tool3_transform
            local axis_craneArm_tool3_transformPercentage
            local axis_craneArm_support_transform
            local axis_craneArm_support_transformPercentage

            local spec_cylindered = vehicle.spec_cylindered
            if spec_cylindered ~= nil then
                local movingTools = spec_cylindered.movingTools or {}
                for _, movingTool in ipairs(movingTools) do
                    local axis = movingTool.axis or ""

                    if axis == "AXIS_FRONTLOADER_ARM" then
                        axis_frontloaderArm_arm_transform, axis_frontloaderArm_arm_transformPercentage = getMoveToolValueAndPercent(movingTool)
                    elseif axis == "AXIS_FRONTLOADER_ARM2" then
                        axis_frontloaderArm_arm2_transform, axis_frontloaderArm_arm2_transformPercentage = getMoveToolValueAndPercent(movingTool)
                    elseif axis == "AXIS_FRONTLOADER_TOOL" then
                        axis_frontloaderArm_tool_transform, axis_frontloaderArm_tool_transformPercentage = getMoveToolValueAndPercent(movingTool)
                    elseif axis == "AXIS_FRONTLOADER_TOOL2" then
                        axis_frontloaderArm_tool2_transform, axis_frontloaderArm_tool2_transformPercentage = getMoveToolValueAndPercent(movingTool)
                    elseif axis == "AXIS_FRONTLOADER_TOOL3" then
                        axis_frontloaderArm_tool3_transform, axis_frontloaderArm_tool3_transformPercentage = getMoveToolValueAndPercent(movingTool)
                    elseif axis == "AXIS_FRONTLOADER_TOOL4" then
                        axis_frontloaderArm_tool4_transform, axis_frontloaderArm_tool4_transformPercentage = getMoveToolValueAndPercent(movingTool)
                    elseif axis == "AXIS_FRONTLOADER_TOOL5" then
                        axis_frontloaderArm_tool5_transform, axis_frontloaderArm_tool5_transformPercentage = getMoveToolValueAndPercent(movingTool)
                    elseif axis == "AXIS_CRANE_ARM" then
                        axis_craneArm_arm_transform, axis_craneArm_arm_transformPercentage = getMoveToolValueAndPercent(movingTool)
                    elseif axis == "AXIS_CRANE_ARM2" then
                        axis_craneArm_arm2_transform, axis_craneArm_arm2_transformPercentage = getMoveToolValueAndPercent(movingTool)
                    elseif axis == "AXIS_CRANE_ARM3" then
                        axis_craneArm_arm3_transform, axis_craneArm_arm3_transformPercentage = getMoveToolValueAndPercent(movingTool)
                    elseif axis == "AXIS_CRANE_ARM4" then
                        axis_craneArm_arm4_transform, axis_craneArm_arm4_transformPercentage = getMoveToolValueAndPercent(movingTool)
                    elseif axis == "AXIS_CRANE_TOOL" then
                        axis_craneArm_tool_transform, axis_craneArm_tool_transformPercentage = getMoveToolValueAndPercent(movingTool)
                    elseif axis == "AXIS_CRANE_TOOL2" then
                        axis_craneArm_tool2_transform, axis_craneArm_tool3_transformPercentage = getMoveToolValueAndPercent(movingTool)
                    elseif axis == "AXIS_CRANE_TOOL3" then
                        axis_craneArm_tool2_transform, axis_craneArm_tool3_transformPercentage = getMoveToolValueAndPercent(movingTool)
                    elseif axis == "AXIS_CRANE_SUPPORT" then
                        axis_craneArm_support_transform, axis_craneArm_support_transformPercentage = getMoveToolValueAndPercent(movingTool)
                    end
                end
            end

            -- frontloader implements will be replaced if the vehicle has inbuilt frontloaderArm axes (e.g. telehandlers)
            self:addFloatToTelemetry("axis_frontloaderArm_arm_transform", axis_frontloaderArm_arm_transform)
            self:addFloatToTelemetry("axis_frontloaderArm_arm_transformPercentage", axis_frontloaderArm_arm_transformPercentage)
            self:addFloatToTelemetry("axis_frontloaderArm_arm2_transform", axis_frontloaderArm_arm2_transform)
            self:addFloatToTelemetry("axis_frontloaderArm_arm2_transformPercentage", axis_frontloaderArm_arm2_transformPercentage)
            self:addFloatToTelemetry("axis_frontloaderArm_tool_transform", axis_frontloaderArm_tool_transform)
            self:addFloatToTelemetry("axis_frontloaderArm_tool_transformPercentage", axis_frontloaderArm_tool_transformPercentage)
            self:addFloatToTelemetry("axis_frontloaderArm_tool2_transform", axis_frontloaderArm_tool2_transform)
            self:addFloatToTelemetry("axis_frontloaderArm_tool2_transformPercentage", axis_frontloaderArm_tool2_transformPercentage)
            self:addFloatToTelemetry("axis_frontloaderArm_tool3_transform", axis_frontloaderArm_tool3_transform)
            self:addFloatToTelemetry("axis_frontloaderArm_tool3_transformPercentage", axis_frontloaderArm_tool3_transformPercentage)
            self:addFloatToTelemetry("axis_frontloaderArm_tool4_transform", axis_frontloaderArm_tool4_transform)
            self:addFloatToTelemetry("axis_frontloaderArm_tool4_transformPercentage", axis_frontloaderArm_tool4_transformPercentage)
            self:addFloatToTelemetry("axis_frontloaderArm_tool5_transform", axis_frontloaderArm_tool5_transform)
            self:addFloatToTelemetry("axis_frontloaderArm_tool5_transformPercentage", axis_frontloaderArm_tool5_transformPercentage)
            -- crane axes
            self:addFloatToTelemetry("axis_craneArm_arm_transform", axis_craneArm_arm_transform)
            self:addFloatToTelemetry("axis_craneArm_arm_transformPercentage", axis_craneArm_arm_transformPercentage)
            self:addFloatToTelemetry("axis_craneArm_arm2_transform", axis_craneArm_arm2_transform)
            self:addFloatToTelemetry("axis_craneArm_arm2_transformPercentage", axis_craneArm_arm2_transformPercentage)
            self:addFloatToTelemetry("axis_craneArm_arm3_transform", axis_craneArm_arm3_transform)
            self:addFloatToTelemetry("axis_craneArm_arm3_transformPercentage", axis_craneArm_arm3_transformPercentage)
            self:addFloatToTelemetry("axis_craneArm_arm4_transform", axis_craneArm_arm4_transform)
            self:addFloatToTelemetry("axis_craneArm_arm4_transformPercentage", axis_craneArm_arm4_transformPercentage)
            self:addFloatToTelemetry("axis_craneArm_tool_transform", axis_craneArm_tool_transform)
            self:addFloatToTelemetry("axis_craneArm_tool_transformPercentage", axis_craneArm_tool_transformPercentage)
            self:addFloatToTelemetry("axis_craneArm_tool2_transform", axis_craneArm_tool2_transform)
            self:addFloatToTelemetry("axis_craneArm_tool2_transformPercentage", axis_craneArm_tool2_transformPercentage)
            self:addFloatToTelemetry("axis_craneArm_tool3_transform", axis_craneArm_tool3_transform)
            self:addFloatToTelemetry("axis_craneArm_tool3_transformPercentage", axis_craneArm_tool3_transformPercentage)
            self:addFloatToTelemetry("axis_craneArm_support_transform", axis_craneArm_support_transform)
            self:addFloatToTelemetry("axis_craneArm_support_transformPercentage", axis_craneArm_support_transformPercentage)
            -- harvester axes
            self:addFloatToTelemetry("axis_cutter_reel_transform", axis_cutter_reel_transform)
            self:addFloatToTelemetry("axis_cutter_reel_transformPercentage", axis_cutter_reel_transformPercentage)
            self:addFloatToTelemetry("axis_cutter_reel2_transform", axis_cutter_reel2_transform)
            self:addFloatToTelemetry("axis_cutter_reel2_transformPercentage", axis_cutter_reel2_transformPercentage)

            -- Miscellaneous Information:

            local spec_ridgeMarker = selectedObject.spec_ridgeMarker or findSpecializationRecursively(vehicle, "spec_ridgeMarker")
            local ridgeMarkerState = spec_ridgeMarker ~= nil and spec_ridgeMarker.ridgeMarkerState or 0

            local spec_baler = selectedObject.spec_baler or  findSpecializationRecursively(vehicle, "spec_baler")
            local selectedBaleType
            local selectedBaleSize
            if spec_baler ~= nil and spec_baler.preSelectedBaleTypeIndex ~= nil then
                selectedBaleType = spec_baler.baleTypes[spec_baler.preSelectedBaleTypeIndex]

                if selectedBaleType.isRoundBale then
                    selectedBaleSize = selectedBaleType.diameter * 100
                else
                    selectedBaleSize = selectedBaleType.length * 100
                end
            end

            -- Mod Support: BaleCounter by Ifko|nator
            local spec_baleCounter = selectedObject.spec_baleCounter or findSpecializationRecursively(vehicle, "spec_baleCounter")
            local sessionBaleCounter
            local lifetimeBaleCounter
            if spec_baleCounter ~= nil then
                sessionBaleCounter = spec_baleCounter.countToday
                lifetimeBaleCounter = spec_baleCounter.countTotal
            else
                -- support for Goeweil and Vermeer DLC bale counter
                spec_baleCounter = ((selectedObject.spec_pdlc_vermeerPack and selectedObject.spec_pdlc_vermeerPack.baleCounter) or findSpecializationRecursively(vehicle, "spec_pdlc_vermeerPack.baleCounter")) or ((selectedObject.spec_pdlc_goeweilPack and selectedObject.spec_pdlc_goeweilPack.baleCounter) or findSpecializationRecursively(vehicle, "spec_pdlc_goeweilPack.baleCounter"))
                if spec_baleCounter ~= nil then
                    sessionBaleCounter = spec_baleCounter.sessionCounter
                    lifetimeBaleCounter = spec_baleCounter.lifetimeCounter
                end
            end

            local spec_wrappedBaleCounter = selectedObject.spec_wrappedBaleCounter or findSpecializationRecursively(vehicle, "spec_wrappedBaleCounter")
            local sessionWrappedBaleCounter
            local lifetimeWrappedBaleCounter
            if spec_wrappedBaleCounter ~= nil then
                sessionWrappedBaleCounter = spec_wrappedBaleCounter.countToday
                lifetimeWrappedBaleCounter = spec_wrappedBaleCounter.countTotal
            end

            local spec_lockSteeringAxles = selectedObject.spec_lockSteeringAxles or findSpecializationRecursively(vehicle, "spec_lockSteeringAxles")
            local isSteeringAxleLocked
            if spec_lockSteeringAxles ~= nil then
                isSteeringAxleLocked = spec_lockSteeringAxles.lockSteeringAxle
            end

            local spec_workMode = selectedObject.spec_workMode or findSpecializationRecursively(vehicle, "spec_workMode")
            local currentWorkModeName
            if spec_workMode ~= nil and spec_workMode.state ~= nil and spec_workMode.workModes ~= nil and #spec_workMode.workModes > 0 then
                currentWorkModeName = spec_workMode.workModes[spec_workMode.state].name or nil
            end

            local spec_mower = selectedObject.spec_mower or findSpecializationRecursively(vehicle, "spec_mower")
            local isMoverConditioner
            if spec_mower ~= nil and spec_mower.currentConverter ~= nil then
                isMoverConditioner = spec_mower.currentConverter == "MOWERCONDITIONER"
            end

            local spec_sowingMachine = selectedObject.spec_sowingMachine or findSpecializationRecursively(vehicle, "spec_sowingMachine")
            local currentSeedSelectionName
            if spec_sowingMachine ~= nil then
                local fillType = g_fruitTypeManager:getFillTypeByFruitTypeIndex(spec_sowingMachine.seeds[spec_sowingMachine.currentSeed])
                currentSeedSelectionName = fillType.title
            end

            local spec_cover = selectedObject.spec_cover or findSpecializationRecursively(vehicle, "spec_cover")
            local isCoverOn
            if isCoverOn ~= nil then
                isCoverOn = spec_cover.state > 0 or false
            end

            self:addNumberToTelemetry(("implement_ridgeMarkerState"), ridgeMarkerState)
            self:addNumberToTelemetry(("implement_sessionBaleCounter"), sessionBaleCounter)
            self:addNumberToTelemetry(("implement_lifetimeBaleCounter"), lifetimeBaleCounter)
            self:addNumberToTelemetry(("implement_sessionWrappedBaleCounter"), sessionWrappedBaleCounter)
            self:addNumberToTelemetry(("implement_lifetimeWrappedBaleCounter"), lifetimeWrappedBaleCounter)
            self:addBoolToTelemetry(("implement_isSteeringAxleLocked"), isSteeringAxleLocked)
            self:addStringToTelemetry(("implement_currentWorkModeName"), currentWorkModeName)
            self:addBoolToTelemetry(("implement_isMoverConditioner"), isMoverConditioner)
            self:addStringToTelemetry(("implement_currentSeedSelectionName"), currentSeedSelectionName)
            self:addBoolToTelemetry(("implement_isCoverOn"), isCoverOn)

            -- Vehicle Specific Information
            self:addCombineInformation(vehicle)

            -- Vehicle Control Addon Information
            self:addVehicleControlAddonInformation(vehicle)

            -- GPS Information
            self:addGuidanceSteeringInformation(vehicle)

            -- ProSeed Information
            self:addProSeedInformation(vehicle)

            -- PrecisionFarming Information
            self:addPrecisionFarmingInformation(vehicle)


            if SHTelemetry.Debug == true then
                -- FillLevels Debugging:
                -- DebugUtil.printTableRecursively(currentFillLevels)
            end

        end
        self:addNumberToTelemetry("vehiclePrice", vehicle:getPrice())
        self:addNumberToTelemetry("vehicleSellPrice", vehicle:getSellPrice())

    else
        self:addBoolToTelemetry("isInVehicle", false)
    end

    -- End
    self:addRawStringToTelemetry('"pluginVersion": "1.0"}')

    -- Send content
    local res = table.concat(SHTelemetryContext.tabdata)
    SHTelemetryContext.shfile:write(res)
    SHTelemetryContext.shfile:flush()
end

-- This function has to be called from the root Vehicle to work properly, do only add first two arguments.
local function getIndexOfActiveImplement(rootVehicle, returnIsFronloader, isFrontloader, level)
    local level = level or 1
    returnIsFronloader = returnIsFronloader or false
    isFrontloader = isFrontloader or false
    local positionFactor = 1
    local returnValue = 0

    if rootVehicle ~= nil  and not rootVehicle:getIsActiveForInput() and rootVehicle.spec_attacherJoints ~= nil and rootVehicle.spec_attacherJoints.attacherJoints ~= nil and rootVehicle.steeringAxleNode ~= nil then
        for _, implement in ipairs(rootVehicle.spec_attacherJoints.attachedImplements) do

            -- root vehicle
            if level == 1 then
                local jointDescIndex = implement.jointDescIndex
				local jointDesc = rootVehicle.spec_attacherJoints.attacherJoints[jointDescIndex]
				local isFrontImplement = getIsFrontImplement(jointDesc.jointTransform, rootVehicle)
				if isFrontImplement then
					positionFactor = 1
				else
					positionFactor = -1
				end

                if jointDesc.jointType == AttacherJoints.JOINTTYPE_ATTACHABLEFRONTLOADER then
                    isFrontloader = true
                else
                    -- if another device is attached at the front, the boolean will be reset
                    isFrontloader = false
                end
            end

            if implement.object:getIsActiveForInput() then
				returnValue = level
			else
				returnValue = getIndexOfActiveImplement(implement.object, returnIsFronloader, isFrontloader, level + 1)
			end
			-- exit recursion if selected device has been found
			if returnValue ~= 0 then break end
        end
    end

    if returnIsFronloader then
        return returnValue * positionFactor, isFrontloader
    end
    return returnValue * positionFactor
end

function SHTelemetry:addSelectionInformation(vehicle)
    local selectedObjectIndex, isFrontloader = getIndexOfActiveImplement(vehicle, true)

    self:addNumberToTelemetry("selectedObject_index", selectedObjectIndex)
    self:addBoolToTelemetry("selectedObject_isFrontloader", isFrontloader)

    local selectedObject = vehicle:getSelectedVehicle()
    local isLowered = selectedObject.getIsLowered ~= nil and selectedObject:getIsLowered()
    local isFoldable = selectedObject.getIsFoldable ~= nil and selectedObject:getIsFoldable()
    local isUnfolded, unfoldingState = false, 0
    if isFoldable ~= nil and isFoldable then
        local spec_foldable = selectedObject.spec_foldable
        if spec_foldable ~= nil and spec_foldable.foldAnimTime <= 1 then
            unfoldingState = 1 - spec_foldable.foldAnimTime
        else
            unfoldingState = 0
        end
        isUnfolded = selectedObject:getIsUnfolded()

    end
    local isPTOActive = selectedObject:getIsPowerTakeOffActive()

    self:addStringToTelemetry("implement_selected_name", selectedObject:getFullName())
    self:addBoolToTelemetry("implement_selected_isLowered", isLowered)
    self:addBoolToTelemetry("implement_selected_isUnfolded", isUnfolded)
    self:addFloatToTelemetry("implement_selected_unfoldingState", unfoldingState)
    self:addBoolToTelemetry("implement_selected_isPTOActive", isPTOActive)

    local implement_selected_tippingState
    local implement_selected_tippingProgress
    local implement_selected_tipSideName

    local tipState = selectedObject.getTipState ~= nil and selectedObject:getTipState()
    local spec_trailer = selectedObject.spec_trailer
    if spec_trailer ~= nil and tipState ~= nil and type(tipState) == "number" then
        implement_selected_tippingState = tipState

        if spec_trailer.tipSides ~= nil then
            local tipSide = spec_trailer.tipSides[spec_trailer.currentTipSideIndex]
            implement_selected_tippingProgress = tipSide ~= nil and selectedObject:getAnimationTime(tipSide.animation.name) or 0
            local tipSideIndex = spec_trailer.preferedTipSideIndex or 0

            implement_selected_tipSideName = spec_trailer.tipSides[tipSideIndex] ~= nil and spec_trailer.tipSides[tipSideIndex].name or " "
        end
    end

    self:addNumberToTelemetry("implement_selected_tippingState", implement_selected_tippingState)
    self:addNumberToTelemetry("implement_selected_tippingProgress", implement_selected_tippingProgress)
    self:addStringToTelemetry("implement_selected_tipSideName", implement_selected_tipSideName)
end

function SHTelemetry:addCombineInformation(vehicle)
    local spec_combine = vehicle.spec_combine
    if spec_combine ~= nil then
        local isSwathActive = spec_combine.isSwathActive
        local isSwathProducing = spec_combine.chopperPSenabled
        local isFilling = spec_combine.isFilling
        local workedHectars = spec_combine.workedHectars
        local spec_cutter = findSpecializationRecursively(vehicle, "spec_cutter")
        local cutter_currentCutHeight
        if spec_cutter ~= nil then
            local cutter_currentCutHeight = spec_combine.currentCutHeight
        end

        local spec_pipe = vehicle.spec_pipe
        local pipe_currentState
        local pipe_isFolding
        local pipe_foldingState
        local pipe_overloadingState
        if spec_pipe ~= nil then
            pipe_currentState =  spec_pipe.currentState
            pipe_isFolding = spec_pipe.currentState ~= spec_pipe.targetState
            pipe_foldingState = spec_pipe:getAnimationTime(spec_pipe.animation.name)
            pipe_overloadingState = spec_pipe:getDischargeState()
        end

        local spec_xpCombine = vehicle.spec_xpCombine -- or findSpecializationRecursively(vehicle, "spec_xpCombine") -- if the harvester is a trailer (potato, carrots, ...), it should search for them
        if spec_xpCombine ~= nil then
            local mrCombineLimiter = spec_xpCombine.mrCombineLimiter

            local combineXP_tonPerHour = mrCombineLimiter.tonPerHour

            local combineXP_engineLoad = mrCombineLimiter.engineLoad * mrCombineLimiter.loadMultiplier

            local combineXP_yield = (mrCombineLimiter.yield == mrCombineLimiter.yield) and mrCombineLimiter.yield or 0

            local combineXP_hasHighMoisture = mrCombineLimiter.highMoisture


            self:addFloatToTelemetry("combineXP_tonPerHour", combineXP_tonPerHour)
            self:addFloatToTelemetry("combineXP_engineLoad", combineXP_engineLoad)
            self:addFloatToTelemetry("combineXP_yield", combineXP_yield)
            self:addBoolToTelemetry("combineXP_hasHighMoisture", combineXP_hasHighMoisture)
        end

        self:addBoolToTelemetry("isSwathActive", isSwathActive)
        self:addBoolToTelemetry("isSwathProducing", isSwathProducing)
        self:addBoolToTelemetry("isFilling", isFilling)
        self:addFloatToTelemetry("workedHectars", workedHectars)
        self:addFloatToTelemetry("cutter_currentCutHeight", cutter_currentCutHeight)
        self:addNumberToTelemetry("pipe_currentState", pipe_currentState)
        self:addBoolToTelemetry("pipe_isFolding", pipe_isFolding)
        self:addFloatToTelemetry("pipe_foldingState", pipe_foldingState)
        self:addNumberToTelemetry("pipe_overloadingState", pipe_overloadingState)
    end
end

function SHTelemetry:addVehicleControlAddonInformation(vehicle)
    local spec_vca = vehicle.spec_vca
    if spec_vca ~= nil then
        local vca_isHandbrakeActive = spec_vca.handbrake
        local vca_isDiffLockFrontActive = spec_vca.diffLockFront
        local vca_isDiffLockBackActive = spec_vca.diffLockBack
        local vca_isAWDActive = spec_vca.diffLockAWD
        local vca_isAWDFrontActive = spec_vca.diffFrontAdv
        local vca_isKeepSpeedActive = spec_vca.ksIsOn
        local vca_keepSpeed = spec_vca.keepSpeed
        local vca_keepSpeedTemp = spec_vca.keepSpeedTemp
        local vca_slip = spec_vca.wheelSlip ~= nil and (spec_vca.wheelSlip - 1) or 0
        local vca_cruiseControlSpeed2 = spec_vca.ccSpeed2
        local vca_cruiseControlSpeed3 = spec_vca.ccSpeed3

        self:addBoolToTelemetry("vca_isHandbrakeActive", vca_isHandbrakeActive)
        self:addBoolToTelemetry("vca_isDiffLockFrontActive", vca_isDiffLockFrontActive)
        self:addBoolToTelemetry("vca_isDiffLockBackActive", vca_isDiffLockBackActive)
        self:addBoolToTelemetry("vca_isAWDActive", vca_isAWDActive)
        self:addBoolToTelemetry("vca_isAWDFrontActive", vca_isAWDFrontActive)
        self:addBoolToTelemetry("vca_isKeepSpeedActive", vca_isKeepSpeedActive)
        self:addFloatToTelemetry("vca_keepSpeed", vca_keepSpeed)
        self:addFloatToTelemetry("vca_keepSpeedTemp", vca_keepSpeedTemp)
        self:addFloatToTelemetry("vca_slip", vca_slip)
        self:addNumberToTelemetry("vca_cruiseControlSpeed2", vca_cruiseControlSpeed2)
        self:addNumberToTelemetry("vca_cruiseControlSpeed3", vca_cruiseControlSpeed3)
    end
end

function SHTelemetry:addGuidanceSteeringInformation(vehicle)
    local spec_gps = vehicle.spec_globalPositioningSystem
    local gps_hasGuidanceSystem = false

    if spec_gps ~= nil then
        local gps_hasGuidanceSystem = spec_gps.hasGuidanceSystem
        local gps_isGuidanceActive = spec_gps.guidanceIsActive
        local gps_isGuidanceSteeringActive = spec_gps.guidanceSteeringIsActive

        if gps_isGuidanceActive and spec_gps.guidanceData ~= nil then
            local gps_currentLane = spec_gps.guidanceData.currentLane

            local gps_targetLaneDistanceDelta
            if spec_gps.guidanceData.alphaRad ~= nil and spec_gps.guidanceData.snapDirectionMultiplier ~= nil and spec_gps.guidanceData.width ~= nil then
                gps_targetLaneDistanceDelta = (spec_gps.guidanceData.snapDirectionMultiplier * spec_gps.guidanceData.alphaRad * spec_gps.guidanceData.width)
            end

            local x1, y1, z1 = localToWorld(vehicle.rootNode, 0, 0, 0)
            local x2, y2, z2 = localToWorld(vehicle.rootNode, 0, 0, 1)
            local dx, dz = x2 - x1, z2 - z1

            local heading = 180 - (180 / math.pi) * math.atan2(dx, dz)
            local snapAngle = 0

            -- we need to find the snap angle, specific to the Guidance Mod used
            -- Guidance Steering
            if spec_gps.lastInputValues ~= nil and spec_gps.lastInputValues.guidanceIsActive then
                if spec_gps.guidanceData.snapDirection ~= nil then
                    local lineDirX, lineDirZ = unpack(spec_gps.guidanceData.snapDirection)
                    local lineDirection = 0
                    if type(lineDirX / lineDirZ) == "number" and lineDirX ~= 0 and lineDirZ ~= 0 then
                        lineDirection = lineDirX / lineDirZ
                    end
                    snapAngle = -math.deg(math.atan(lineDirection))
                end
            end

            local offset = heading - snapAngle
            if offset > 180 then
                offset = offset - 360
            end
            if offset > 90 then
                offset = offset - 180
            end
            if offset < -90 then
                offset = offset + 180
            end
            local gps_headingDelta = offset

            local gps_laneWidth = spec_gps.guidanceData.width ~= nil and spec_gps.guidanceData.width or nil

            self:addBoolToTelemetry("gps_isGuidanceActive", gps_isGuidanceActive)
            self:addBoolToTelemetry("gps_isGuidanceSteeringActive", gps_isGuidanceSteeringActive)
            self:addNumberToTelemetry("gps_currentLane", gps_currentLane)
            self:addFloatToTelemetry("gps_targetLaneDistanceDelta", gps_targetLaneDistanceDelta)
            self:addFloatToTelemetry("gps_headingDelta", gps_headingDelta)
            self:addFloatToTelemetry("gps_laneWidth", gps_laneWidth)
        end
    self:addBoolToTelemetry("gps_hasGuidanceSystem", gps_hasGuidanceSystem)
    end
end

function SHTelemetry:addProSeedInformation(vehicle)
    local specPS = findSpecializationRecursively(vehicle, "spec_proSeedTramLines")
	local specSE = findSpecializationRecursively(vehicle, "spec_proSeedSowingExtension")
    if specPS ~= nil and specSE ~= nil then
        local tramLineMode = specPS.tramLineMode
        local rawText = FS22_proSeed.ProSeedTramLines.TRAMLINE_MODE_TO_KEY[tramLineMode]
        local proSeed_tramLineMode = g_i18n.modEnvironments["FS22_proSeed"]:getText(("info_mode_%s"):format(rawText))

        local proSeed_tramLineDistance = specPS.tramLineDistance
        local proSeed_currentLane = specPS.currentLane
        local proSeed_maxLine = specPS.tramLinePeriodicSequence
        if proSeed_maxLine == 2 and specPS.tramLineDistanceMultiplier == 1 then proSeed_maxLine = 1 end
        local proSeed_createTramLines = specPS.createTramLines
        local proSeed_allowFertilizer = specSE.allowFertilizer
        local proSeed_sessionHectares = specSE.sessionHectares
        local proSeed_totalHectares = specSE.totalHectares
        local proSeed_hectarePerHour = specSE.hectarePerHour
        local proSeed_seedUsage = specSE.seedUsage

        local proSeed_shutoffMode = specPS.shutoffMode
        local proSeed_shutoffModeText = ""
        if proSeed_shutoffMode == 0 then proSeed_shutoffModeText = "Volle Arbeitsbreite"
        elseif proSeed_shutoffMode == 1 then proSeed_shutoffModeText = "Linksseitig aktiv"
        elseif proSeed_shutoffMode == 2 then proSeed_shutoffModeText = "Rechtsseitig aktiv" end

        local proSeed_createPreMarkedTramLines = specPS.createPreMarkedTramLines
        local proSeed_allowSound = specSE.allowSound

        self:addStringToTelemetry("proSeed_tramLineMode", proSeed_tramLineMode)
        self:addNumberToTelemetry("proSeed_tramLineDistance", proSeed_tramLineDistance)
        self:addNumberToTelemetry("proSeed_currentLane", proSeed_currentLane)
        self:addNumberToTelemetry("proSeed_maxLine", proSeed_maxLine)
        self:addBoolToTelemetry("proSeed_createTramLines", proSeed_createTramLines)
        self:addBoolToTelemetry("proSeed_allowFertilizer", proSeed_allowFertilizer)
        self:addFloatToTelemetry("proSeed_sessionHectares", proSeed_sessionHectares)
        self:addFloatToTelemetry("proSeed_totalHectares", proSeed_totalHectares)
        self:addFloatToTelemetry("proSeed_hectarePerHour", proSeed_hectarePerHour)
        self:addFloatToTelemetry("proSeed_seedUsage", proSeed_seedUsage)
        self:addNumberToTelemetry("proSeed_shutoffMode", proSeed_shutoffMode)
        self:addStringToTelemetry("proSeed_shutoffModeText", proSeed_shutoffModeText)
        self:addBoolToTelemetry("proSeed_createPreMarkedTramLines", proSeed_createPreMarkedTramLines)
        self:addBoolToTelemetry("proSeed_allowSound", proSeed_allowSound)
    end
end

function SHTelemetry:addPrecisionFarmingInformation(vehicle)
    local selectedObject = vehicle:getSelectedVehicle()

	local spec_cropSensor = selectedObject.spec_ridgeMarker or findSpecializationRecursively(vehicle, "spec_cropSensor")
    local precisionFarming_cropSensor_isActive
	if spec_cropSensor ~= nil then
        precisionFarming_cropSensor_isActive = spec_cropSensor.isActive
    end
    self:addBoolToTelemetry("precisionFarming_cropSensor_isActive", precisionFarming_cropSensor_isActive or false)
	
    local spec_extendedSprayer, pfVehicle
    if selectedObject.spec_extendedSprayer ~= nil then
        spec_extendedSprayer = selectedObject.spec_extendedSprayer
        pfVehicle = selectedObject
    else
	    spec_extendedSprayer, pfVehicle = findSpecializationRecursively(vehicle, "spec_extendedSprayer")
    end
	if spec_extendedSprayer ~= nil then
		local sourceVehicle, fillUnitIndex = FS22_precisionFarming.ExtendedSprayer.getFillTypeSourceVehicle(pfVehicle)
		local hasLimeLoaded, hasFertilizerLoaded = FS22_precisionFarming.ExtendedSprayer.getCurrentSprayerMode(pfVehicle)
	
		-- soil type
        if spec_extendedSprayer.lastTouchedSoilType ~= 0 and spec_extendedSprayer.soilMap ~= nil then
            local soilType = spec_extendedSprayer.soilMap:getSoilTypeByIndex(spec_extendedSprayer.lastTouchedSoilType)
            if soilType ~= nil and soilType.name ~= nil then
                local precisionFarming_soilTypeName = soilType.name
                self:addStringToTelemetry("precisionFarming_soilTypeName", precisionFarming_soilTypeName)
            end
        end
		
		local sprayAmountAutoMode = spec_extendedSprayer.sprayAmountAutoMode
		-- sprayAmountAutoMode
	    self:addBoolToTelemetry("precisionFarming_isSprayAmountAutoModeActive", sprayAmountAutoMode)
		
		local sprayFillType = sourceVehicle:getFillUnitFillType(fillUnitIndex)
		local fillTypeDesc = g_fillTypeManager:getFillTypeByIndex(sprayFillType)
		local massPerLiter = (fillTypeDesc.massPerLiter / FillTypeManager.MASS_SCALE)
		local applicationRate = 0
		
        local returnValueFormat = "%.2f t/ha"

		-- lime values
		if hasLimeLoaded then
		
			local phMap = spec_extendedSprayer.pHMap
            local phActualInt = spec_extendedSprayer.phActualBuffer:get()
            local phTargetInt = spec_extendedSprayer.phTargetBuffer:get()

            local phActual = phMap:getPhValueFromInternalValue(phActualInt) or 0
            self:addNumberToTelemetry("precisionFarming_phActual", phActual)

            local phTarget = phMap:getPhValueFromInternalValue(phTargetInt)	or 0	
            self:addNumberToTelemetry("precisionFarming_phTarget", phTarget)

			local phChanged = 0
			if sprayAmountAutoMode then
                phChanged = phTarget - phActual
				applicationRate = spec_extendedSprayer.lastLitersPerHectar * massPerLiter
			else
				local requiredLitersPerHa = phMap:getLimeUsageByStateChange(spec_extendedSprayer.sprayAmountManual)
            	phChanged = phMap:getPhValueFromChangedStates(spec_extendedSprayer.sprayAmountManual)
				applicationRate = requiredLitersPerHa * massPerLiter
			end
            self:addNumberToTelemetry("precisionFarming_phChanged", phChanged)
            self:addNumberToTelemetry("precisionFarming_applicationRate", applicationRate)
            self:addStringToTelemetry("precisionFarming_applicationRateFormattedString", string.format(returnValueFormat, tostring(applicationRate)))
				
		-- fertilizer part
		elseif hasFertilizerLoaded then
			
			local nitrogenMap = spec_extendedSprayer.nitrogenMap
			local nActualInt = spec_extendedSprayer.nActualBuffer:get()
			local nTargetInt = spec_extendedSprayer.nTargetBuffer:get()		
			
			local nActual = nitrogenMap:getNitrogenValueFromInternalValue(nActualInt) or 0
            self:addNumberToTelemetry("precisionFarming_nActual", nActual)
			
			local nTarget = nitrogenMap:getNitrogenValueFromInternalValue(nTargetInt) or 0
            self:addNumberToTelemetry("precisionFarming_nTarget", nTarget)
			
			local nitrogenChanged = 0
			if sprayAmountAutoMode then
                nitrogenChanged = nTarget - nActual
			else
            	nitrogenChanged = nitrogenMap:getNitrogenFromChangedStates(spec_extendedSprayer.sprayAmountManual) or 0
			end
            self:addNumberToTelemetry("precisionFarming_nitrogenChanged", nitrogenChanged)
			
			local litersPerHectar
			if sprayAmountAutoMode then
				litersPerHectar = spec_extendedSprayer.lastLitersPerHectar
			else
				litersPerHectar = nitrogenMap:getFertilizerUsageByStateChange(spec_extendedSprayer.sprayAmountManual, sprayFillType)
			end
            self:addNumberToTelemetry("precisionFarming_litersPerHectar", litersPerHectar)

			
			if spec_extendedSprayer.isSolidFertilizerSprayer then
				returnValueFormat = "%d kg/ha"
				applicationRate = litersPerHectar * massPerLiter * 1000
			elseif spec_extendedSprayer.isLiquidFertilizerSprayer then
				returnValueFormat = "%d l/ha"
				applicationRate = litersPerHectar
			elseif spec_extendedSprayer.isSlurryTanker then
				returnValueFormat = "%.1f mÂ³/ha"
				applicationRate = litersPerHectar / 1000
			elseif spec_extendedSprayer.isManureSpreader then
				returnValueFormat = "%.1f t/ha"
				applicationRate = litersPerHectar * massPerLiter
			end
            self:addFloatToTelemetry("precisionFarming_applicationRate", applicationRate)
            self:addStringToTelemetry("precisionFarming_applicationRateFormattedString", string.format(returnValueFormat, tostring(applicationRate)))
        end
	end
end

function SHTelemetry:getVehicleFuelLevelAndCapacity(vehicle)
    local fuelFillType = vehicle:getConsumerFillUnitIndex(FillType.DIESEL)
    local level = vehicle:getFillUnitFillLevel(fuelFillType)
    local capacity = vehicle:getFillUnitCapacity(fuelFillType)

    return level, capacity
end

function SHTelemetry:getAllFillLevels(vehicle, fillLevelTable, depth)
    self:getFillLevelsFromObject(vehicle, fillLevelTable)

    if vehicle.getAttachedImplements ~= nil and depth < SHTelemetry.maxFillLevelDepth then
        local attachedImplements = vehicle:getAttachedImplements();
        for _, implement in pairs(attachedImplements) do
            if implement.object ~= nil then
                local newDepth = depth + 1
                self:getAllFillLevels(implement.object, fillLevelTable, newDepth)
            end
        end
    end
end

function SHTelemetry:getFillLevelsFromObject(object, fillLevelTable)
    local spec_fillUnit = object.spec_fillUnit

    if spec_fillUnit ~= nil and spec_fillUnit.fillUnits ~= nil then
        for _, fillUnit in ipairs(spec_fillUnit.fillUnits) do
            local fillLevel, fillType, capacity, mass = getFillLevelFromFillUnit(fillUnit)
            if (fillLevel ~= nil and fillType ~= nil and capacity ~= nil and mass ~= nil) then
                addFillLevelToTable(fillLevel, fillType, capacity, mass, fillLevelTable)
            end
        end
    end

    local spec_tensionBelts = object.spec_tensionBelts
    if spec_tensionBelts ~= nil then
        if spec_tensionBelts.hasTensionBelts then
            for _, objectData in pairs(spec_tensionBelts.objectsToJoint) do
                local object = objectData.object
                if object ~= nil then
                    local spec_fillUnitObject = object.spec_fillUnit

                    if spec_fillUnitObject ~= nil and spec_fillUnitObject.fillUnits ~= nil then
                        for _, fillUnit in ipairs(spec_fillUnitObject.fillUnits) do
                            local fillLevel, fillType, capacity, _ = getFillLevelFromFillUnit(fillUnit)
                            -- Returned mass from function above does not include pallet mass, therefore we use the following piece of code:
                            local mass = object.serverMass * 1000
                            if (fillLevel ~= nil and fillType ~= nil and capacity ~= nil and mass ~= nil) then
                                addFillLevelToTable(fillLevel, fillType, capacity, mass, fillLevelTable)
                            end
                        end
                    end
                end
            end
        end
    end
    return fillLevelTable
end

function SHTelemetry:initPipe(dt)
    -- Re/Init file
    if (SHTelemetryContext.updateCount == 0) then
        if (SHTelemetryContext.shfile ~= nil) then
            SHTelemetryContext.shfile:flush()
            SHTelemetryContext.shfile:close()
        end

        local newfile = io.open(SHTelemetryContext.pipeName, "w")
        SHTelemetryContext.shfile = newfile
    end

    SHTelemetryContext.updateCount = SHTelemetryContext.updateCount + 1
    if (SHTelemetryContext.updateCount == 300) then
        SHTelemetryContext.updateCount = 0
    end
end


function SHTelemetry:update(dt)
    -- Init file
    self:initPipe(dt)

    -- If pipe is ready
    if (SHTelemetryContext.shfile ~= nil) then
        if SHTelemetryContext.lastTelemetryRefresh >= SHTelemetryContext.refreshRate then
            self:buildTelemetry()
            SHTelemetryContext.lastTelemetryRefresh = 0
            --print("UpdatedTelemetry")
            --print(getDate("%T"))
        end
    end
    SHTelemetryContext.lastTelemetryRefresh = SHTelemetryContext.lastTelemetryRefresh + 1
    --print(SHTelemetryContext.lastTelemetryRefresh)
end

function SHTelemetry:addBoolToTelemetry(name, value)
    if (value ~= nil) then
        if type(value) == "boolean" then
            if (value) then
                SHTelemetryContext.tabdata[SHTelemetryContext.tabLength] = string.format('"%s": true, ', name)
            else
                SHTelemetryContext.tabdata[SHTelemetryContext.tabLength] = string.format('"%s": false, ', name)
            end
            self:incrementTablePosition()
        else
            logWrongValueType(name, value)
        end
    end
end

function SHTelemetry:addStringToTelemetry(name, value)
    if (value ~= nil) then
        if type(value) == "string" then
            SHTelemetryContext.tabdata[SHTelemetryContext.tabLength] = string.format('"%s": "%s", ', name, value:gsub('"', '\\"'))
            self:incrementTablePosition()
        else
            logWrongValueType(name, value)
        end
    end
end

function SHTelemetry:addRawStringToTelemetry(value)
    SHTelemetryContext.tabdata[SHTelemetryContext.tabLength] = value
    self:incrementTablePosition()
end

function SHTelemetry:addNumberToTelemetry(name, value)
    if (value ~= nil) then
        if type(value) == "number" then
            if (value ~= value) then return end --Check if it is not "nan" (0/0)
            SHTelemetryContext.tabdata[SHTelemetryContext.tabLength] = string.format('"%s": %d, ', name, value)
            self:incrementTablePosition()
        else
            logWrongValueType(name, value)
        end
    end
end

function SHTelemetry:addFloatToTelemetry(name, value)
    if (value ~= nil) then
        if type(value) == "number" then 
            if (value ~= value) then return end --Check if it is not "nan" (0/0)
            SHTelemetryContext.tabdata[SHTelemetryContext.tabLength] = string.format('"%s": %.3f, ', name, value)
            self:incrementTablePosition()
        else
            logWrongValueType(name, value)
        end
    end
end

function SHTelemetry:incrementTablePosition()
    SHTelemetryContext.tabLength = SHTelemetryContext.tabLength + 1
end

function SHTelemetry:consoleCommandPrintTelemetryData()
    print("############################################### SimHub Telemetry (Edit by Sebastain7870) - Telemetry Data ###############################################")
    for _, value in ipairs(SHTelemetryContext.tabdata) do
        print(value)
    end
end

addModEventListener(SHTelemetry)