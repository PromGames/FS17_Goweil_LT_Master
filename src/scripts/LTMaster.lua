--
--Goweil LT Master
--
--TyKonKet (Team FSI Modding)
--
--18/04/2017
LTMaster = {};
LTMaster.debug = true

LTMaster.STATUS_OC_OPEN = 1;
LTMaster.STATUS_OC_OPENING = 2;
LTMaster.STATUS_OC_CLOSED = 3;
LTMaster.STATUS_OC_CLOSING = 4;

LTMaster.STATUS_RL_LOWERED = 1;
LTMaster.STATUS_RL_LOWERING = 2;
LTMaster.STATUS_RL_RAISED = 3;
LTMaster.STATUS_RL_RAISING = 4;

LTMaster.STATUS_FU_UNFOLDED = 1;
LTMaster.STATUS_FU_UNFOLDING = 2;
LTMaster.STATUS_FU_FOLDED = 3;
LTMaster.STATUS_FU_FOLDING = 4;

source(g_currentModDirectory .. "scripts/LTMaster.animations.lua");
source(g_currentModDirectory .. "scripts/LTMaster.baler.lua");
source(g_currentModDirectory .. "scripts/events/hoodStatusEvent.lua");
source(g_currentModDirectory .. "scripts/events/supportsStatusEvent.lua");
source(g_currentModDirectory .. "scripts/events/foldingStatusEvent.lua");
source(g_currentModDirectory .. "scripts/events/ladderStatusEvent.lua");
source(g_currentModDirectory .. "scripts/events/baleSlideStatusEvent.lua");
source(g_currentModDirectory .. "scripts/events/sideUnloadEvent.lua");
source(g_currentModDirectory .. "scripts/events/conveyorStatusEvent.lua");
source(g_currentModDirectory .. "scripts/events/balerCreateBaleEvent.lua");
source(g_currentModDirectory .. "scripts/events/balerChangeVolumeEvent.lua");

function LTMaster.print(text, ...)
    if LTMaster.debug then
        local start = string.format("[%s(%s)] -> ", "LTMaster", getDate("%H:%M:%S"));
        local ptext = string.format(text, ...);
        print(string.format("%s%s", start, ptext));
    end
end

function LTMaster.prerequisitesPresent(specializations)
    return true;
end

function LTMaster:preLoad(savegame)
    self.updateHoodStatus = LTMaster.updateHoodStatus;
    self.updateSupportsStatus = LTMaster.updateSupportsStatus;
    self.updateFoldingStatus = LTMaster.updateFoldingStatus;
    self.updateLadderStatus = LTMaster.updateLadderStatus;
    self.updateBaleSlideStatus = LTMaster.updateBaleSlideStatus;
    self.unloadSide = LTMaster.unloadSide;
    self.setConveyorStatus = LTMaster.setConveyorStatus;
    self.getIsConveyorOverloading = LTMaster.getIsConveyorOverloading;
end

function LTMaster:load(savegame)
    self.applyInitialAnimation = Utils.overwrittenFunction(self.applyInitialAnimation, LTMaster.applyInitialAnimation);
    self.getIsTurnedOnAllowed = Utils.overwrittenFunction(self.getIsTurnedOnAllowed, LTMaster.getIsTurnedOnAllowed);
    self.getTurnedOnNotAllowedWarning = Utils.overwrittenFunction(self.getTurnedOnNotAllowedWarning, LTMaster.getTurnedOnNotAllowedWarning);
    self.getConsumedPtoTorque = Utils.overwrittenFunction(self.getConsumedPtoTorque, LTMaster.getConsumedPtoTorque);
    self.getPtoRpm = Utils.overwrittenFunction(self.getPtoRpm, LTMaster.getPtoRpm);
    self.getIsFoldAllowed = Utils.overwrittenFunction(self.getIsFoldAllowed, LTMaster.getIsFoldAllowed);
    
    self.LTMaster = {};
    
    self.LTMaster.fillUnits = {};
    self.LTMaster.fillUnits["main"] = {};
    self.LTMaster.fillUnits["main"].index = Utils.getNoNil(getXMLInt(self.xmlFile, "vehicle.LTMaster.triggers.tipTrigger#fillUnitIndex"), 1);
    self.LTMaster.fillUnits["right"] = {};
    self.LTMaster.fillUnits["right"].index = Utils.getNoNil(getXMLInt(self.xmlFile, "vehicle.LTMaster.triggers.tipTrigger#rightFillUnitIndex"), 2);
    self.LTMaster.fillUnits["right"].unloadSpeed = 0;
    self.LTMaster.fillUnits["left"] = {};
    self.LTMaster.fillUnits["left"].index = Utils.getNoNil(getXMLInt(self.xmlFile, "vehicle.LTMaster.triggers.tipTrigger#leftFillUnitIndex"), 3);
    self.LTMaster.fillUnits["left"].unloadSpeed = 0;
    self.LTMaster.fillUnits["baler"] = {};
    self.LTMaster.fillUnits["baler"].index = Utils.getNoNil(getXMLInt(self.xmlFile, "vehicle.LTMaster.baler#fillUnitIndex"), 4);
    self.LTMaster.fillUnits["silageAdditive"] = {};
    self.LTMaster.fillUnits["silageAdditive"].index = Utils.getNoNil(getXMLInt(self.xmlFile, "vehicle.LTMaster.silageAdditive#fillUnitIndex"), 4);
    
    self.LTMaster.conveyor = {};
    if self.isClient then
        self.LTMaster.conveyor.effects = EffectManager:loadEffect(self.xmlFile, "vehicle.LTMaster.conveyor.effects", self.components, self);
        self.LTMaster.conveyor.uvScrollParts = Utils.loadScrollers(self.components, self.xmlFile, "vehicle.LTMaster.conveyor.uvScrollParts.uvScrollPart", {}, false);
        self.LTMaster.conveyor.rotatingParts = Utils.loadRotationNodes(self.xmlFile, {}, "vehicle.LTMaster.conveyor.rotatingParts.rotatingPart", "LTMaster.conveyor", self.components)
        self.LTMaster.conveyor.unloadParticleSystems = {};
        local i = 0;
        while true do
            local key = string.format("vehicle.LTMaster.conveyor.unloadParticleSystems.emitterShape(%d)", i);
            if not hasXMLProperty(self.xmlFile, key) then
                break;
            end
            local emitterShape = Utils.indexToObject(self.components, getXMLString(self.xmlFile, key .. "#node"));
            local particleType = getXMLString(self.xmlFile, key .. "#particleType");
            if emitterShape ~= nil then
                for fillType, _ in pairs(self:getUnitFillTypes(self.LTMaster.fillUnits["main"].index)) do
                    local particleSystem = MaterialUtil.getParticleSystem(fillType, particleType);
                    if particleSystem ~= nil then
                        if self.LTMaster.conveyor.unloadParticleSystems[fillType] == nil then
                            self.LTMaster.conveyor.unloadParticleSystems[fillType] = {};
                        end
                        local currentPS = ParticleUtil.copyParticleSystem(self.xmlFile, key, particleSystem, emitterShape);
                        table.insert(self.LTMaster.conveyor.unloadParticleSystems[fillType], currentPS);
                    end
                end
            end
            i = i + 1;
        end
        self.LTMaster.conveyor.augerParticleSystems = {};
        local i = 0;
        while true do
            local key = string.format("vehicle.LTMaster.conveyor.augerParticleSystems.emitterShape(%d)", i);
            if not hasXMLProperty(self.xmlFile, key) then
                break;
            end
            local emitterShape = Utils.indexToObject(self.components, getXMLString(self.xmlFile, key .. "#node"));
            local particleType = getXMLString(self.xmlFile, key .. "#particleType");
            if emitterShape ~= nil then
                for fillType, _ in pairs(self:getUnitFillTypes(self.LTMaster.fillUnits["main"].index)) do
                    local particleSystem = MaterialUtil.getParticleSystem(fillType, particleType);
                    if particleSystem ~= nil then
                        if self.LTMaster.conveyor.augerParticleSystems[fillType] == nil then
                            self.LTMaster.conveyor.augerParticleSystems[fillType] = {};
                        end
                        local currentPS = ParticleUtil.copyParticleSystem(self.xmlFile, key, particleSystem, emitterShape);
                        table.insert(self.LTMaster.conveyor.augerParticleSystems[fillType], currentPS);
                    end
                end
            end
            i = i + 1;
        end
    end
    self.LTMaster.conveyor.overloadingCapacity = Utils.getNoNil(getXMLFloat(self.xmlFile, "vehicle.LTMaster.conveyor#overloadingCapacity"), 100);
    --self.LTMaster.conveyor.overloadingDelay = Utils.getNoNil(getXMLFloat(self.xmlFile, "vehicle.LTMaster.conveyor#overloadingDelay"), 3);
    self.LTMaster.conveyor.isOverloading = false;
    
    self.LTMaster.sideUnload = {};
    self.LTMaster.sideUnload.animation = getXMLString(self.xmlFile, "vehicle.LTMaster.sideUnload#animationName");
    self.LTMaster.sideUnload.maxAmount = Utils.getNoNil(getXMLFloat(self.xmlFile, "vehicle.LTMaster.sideUnload#maxAmount"), 0);
    self.LTMaster.sideUnload.isUnloading = false;
    
    local trigger = Utils.indexToObject(self.components, getXMLString(self.xmlFile, "vehicle.LTMaster.triggers.triggerLeft#index"));
    self.LTMaster.triggerLeft = PlayerTrigger:new(trigger, Utils.getNoNil(getXMLFloat(self.xmlFile, "vehicle.LTMaster.triggers.triggerLeft#radius"), 2.5));
    trigger = Utils.indexToObject(self.components, getXMLString(self.xmlFile, "vehicle.LTMaster.triggers.triggerRight#index"));
    self.LTMaster.triggerRight = PlayerTrigger:new(trigger, Utils.getNoNil(getXMLFloat(self.xmlFile, "vehicle.LTMaster.triggers.triggerRight#radius"), 2.5));
    trigger = Utils.indexToObject(self.components, getXMLString(self.xmlFile, "vehicle.LTMaster.triggers.triggerLadder#index"));
    self.LTMaster.triggerLadder = PlayerTrigger:new(trigger, Utils.getNoNil(getXMLFloat(self.xmlFile, "vehicle.LTMaster.triggers.triggerLadder#radius"), 2.5));
    trigger = Utils.indexToObject(self.components, getXMLString(self.xmlFile, "vehicle.LTMaster.triggers.triggerBaleSlide#index"));
    self.LTMaster.triggerBaleSlide = PlayerTrigger:new(trigger, Utils.getNoNil(getXMLFloat(self.xmlFile, "vehicle.LTMaster.triggers.triggerBaleSlide#radius"), 2.5));
    trigger = Utils.indexToObject(self.components, getXMLString(self.xmlFile, "vehicle.LTMaster.triggers.tipTrigger#index"));
    self.LTMaster.tipTrigger = LTMasterTipTrigger:new(self.isServer, self.isClient);
    self.LTMaster.tipTrigger:load(trigger, self, self.LTMaster.fillUnits["main"].index, self.LTMaster.fillUnits["right"].index, self.LTMaster.fillUnits["left"].index);
    self.LTMaster.tipTrigger:register(true);
    
    self.LTMaster.hoods = {};
    self.LTMaster.hoods.openingSound = SoundUtil.loadSample(self.xmlFile, {}, "vehicle.LTMaster.hoods.openingSound", nil, self.baseDirectory);
    self.LTMaster.hoods.closingSound = SoundUtil.loadSample(self.xmlFile, {}, "vehicle.LTMaster.hoods.closingSound", nil, self.baseDirectory);
    self.LTMaster.hoods.delayedUpdateHoodStatus = DelayedCallBack:new(LTMaster.updateHoodStatus, self);
    self.LTMaster.hoods["left"] = {};
    self.LTMaster.hoods["left"].name = "left";
    self.LTMaster.hoods["left"].animation = getXMLString(self.xmlFile, "vehicle.LTMaster.hoods.leftDoor#animationName");
    self.LTMaster.hoods["left"].status = LTMaster.STATUS_OC_CLOSED;
    
    self.LTMaster.hoods["right"] = {};
    self.LTMaster.hoods["right"].name = "right";
    self.LTMaster.hoods["right"].animation = getXMLString(self.xmlFile, "vehicle.LTMaster.hoods.rightDoor#animationName");
    self.LTMaster.hoods["right"].status = LTMaster.STATUS_OC_CLOSED;
    
    self.LTMaster.supports = {};
    self.LTMaster.supports.animation = getXMLString(self.xmlFile, "vehicle.LTMaster.supports#animationName");
    self.LTMaster.supports.status = LTMaster.STATUS_RL_RAISED;
    self.LTMaster.supports.delayedUpdateSupportsStatus = DelayedCallBack:new(LTMaster.updateSupportsStatus, self);
    self.LTMaster.supports.sound = SoundUtil.loadSample(self.xmlFile, {}, "vehicle.LTMaster.supports.sound", nil, self.baseDirectory);
    
    self.LTMaster.folding = {};
    self.LTMaster.folding.animation = getXMLString(self.xmlFile, "vehicle.LTMaster.folding#animationName");
    self.LTMaster.folding.status = LTMaster.STATUS_FU_FOLDED;
    self.LTMaster.folding.delayedUpdateFoldingStatus = DelayedCallBack:new(LTMaster.updateFoldingStatus, self);
    self.LTMaster.folding.sound = SoundUtil.loadSample(self.xmlFile, {}, "vehicle.LTMaster.folding.sound", nil, self.baseDirectory);
    
    self.LTMaster.ladder = {};
    self.LTMaster.ladder.animation = getXMLString(self.xmlFile, "vehicle.LTMaster.ladder#animationName");
    self.LTMaster.ladder.status = LTMaster.STATUS_RL_RAISED;
    self.LTMaster.ladder.delayedUpdateLadderStatus = DelayedCallBack:new(LTMaster.updateLadderStatus, self);
    self.LTMaster.ladder.sound = SoundUtil.loadSample(self.xmlFile, {}, "vehicle.LTMaster.ladder.sound", nil, self.baseDirectory);
    
    self.LTMaster.baleSlide = {};
    self.LTMaster.baleSlide.animation = getXMLString(self.xmlFile, "vehicle.LTMaster.baleSlide#animationName");
    self.LTMaster.baleSlide.status = LTMaster.STATUS_RL_RAISED;
    self.LTMaster.baleSlide.delayedUpdateBaleSlideStatus = DelayedCallBack:new(LTMaster.updateBaleSlideStatus, self);
    self.LTMaster.baleSlide.sound = SoundUtil.loadSample(self.xmlFile, {}, "vehicle.LTMaster.baleSlide.sound", nil, self.baseDirectory);
    
    self.LTMaster.silageAdditive = {};
    self.LTMaster.silageAdditive.enabled = true;
    self.LTMaster.silageAdditive.isUsing = false;
    self.LTMaster.silageAdditive.gain = Utils.getNoNil(getXMLFloat(self.xmlFile, "vehicle.LTMaster.silageAdditive#gain"), 1.1);
    self.LTMaster.silageAdditive.usage = Utils.getNoNil(getXMLFloat(self.xmlFile, "vehicle.LTMaster.silageAdditive#usage"), 0.001);
    local fillTypeNames = getXMLString(self.xmlFile, "vehicle.LTMaster.silageAdditive#fillTypes");
    self.LTMaster.silageAdditive.fillTypes = FillUtil.getFillTypesByNames(fillTypeNames);
    self.LTMaster.silageAdditive.acceptedFillTypes = {};
    if self.LTMaster.silageAdditive.fillTypes ~= nil then
        for _, fillType in pairs(self.LTMaster.silageAdditive.fillTypes) do
            self.LTMaster.silageAdditive.acceptedFillTypes[fillType] = true;
        end
    end
    self.LTMaster.silageAdditive.fillType = FillUtil.FILLTYPE_LIQUIDFERTILIZER;
    if self.isClient then
        self.LTMaster.silageAdditive.effects = EffectManager:loadEffect(self.xmlFile, "vehicle.LTMaster.silageAdditive.effects", self.components, self);
    end
    
    LTMaster.loadBaler(self);
end

function LTMaster:postLoad(savegame)
    LTMaster.postLoadBaler(self, savegame);
    if self.isServer then
        if savegame ~= nil and not savegame.resetVehicles then
            self.LTMaster.hoods["left"].status = Utils.getNoNil(getXMLInt(savegame.xmlFile, savegame.key .. "#leftHoodStatus"), self.LTMaster.hoods["left"].status);
            self.LTMaster.hoods["right"].status = Utils.getNoNil(getXMLInt(savegame.xmlFile, savegame.key .. "#rightHoodStatus"), self.LTMaster.hoods["right"].status);
            self.LTMaster.supports.status = Utils.getNoNil(getXMLInt(savegame.xmlFile, savegame.key .. "#supportsStatus"), self.LTMaster.supports.status);
            self.LTMaster.folding.status = Utils.getNoNil(getXMLInt(savegame.xmlFile, savegame.key .. "#foldingStatus"), self.LTMaster.folding.status);
            self.LTMaster.ladder.status = Utils.getNoNil(getXMLInt(savegame.xmlFile, savegame.key .. "#ladderStatus"), self.LTMaster.ladder.status);
            self.LTMaster.baleSlide.status = Utils.getNoNil(getXMLInt(savegame.xmlFile, savegame.key .. "#baleSlideStatus"), self.LTMaster.baleSlide.status);
        elseif savegame == nil then
            self:setUnitFillLevel(self.LTMaster.fillUnits["silageAdditive"].index, math.huge, FillUtil.FILLTYPE_SILAGEADDITIVE, true);
        end
        LTMaster.finalizeLoad(self);
    end
end

function LTMaster:getSaveAttributesAndNodes(nodeIdent)
    local attributes = string.format("leftHoodStatus=\"%s\" rightHoodStatus=\"%s\" ", self.LTMaster.hoods["left"].status, self.LTMaster.hoods["right"].status);
    attributes = attributes .. string.format("supportsStatus=\"%s\" ", self.LTMaster.supports.status);
    attributes = attributes .. string.format("foldingStatus=\"%s\" ", self.LTMaster.folding.status);
    attributes = attributes .. string.format("ladderStatus=\"%s\" ", self.LTMaster.ladder.status);
    attributes = attributes .. string.format("baleSlideStatus=\"%s\" ", self.LTMaster.baleSlide.status);
    local bAttributes, bNodes = LTMaster.getSaveAttributesAndNodesBaler(self, nodeIdent);
    return attributes .. " " .. bAttributes, bNodes;
end

function LTMaster:finalizeLoad()
    self:updateHoodStatus(self.LTMaster.hoods["left"], nil, true);
    self:updateHoodStatus(self.LTMaster.hoods["right"], nil, true);
    self:updateSupportsStatus(self.LTMaster.supports.status, true);
    self:updateFoldingStatus(self.LTMaster.folding.status, true);
    self:updateLadderStatus(self.LTMaster.ladder.status, true);
    self:updateBaleSlideStatus(self.LTMaster.baleSlide.status, true);
    self:setBaleVolume(self.LTMaster.baler.baleVolumesIndex);
end

function LTMaster:delete()
    self.LTMaster.triggerLeft:delete();
    self.LTMaster.triggerRight:delete();
    self.LTMaster.triggerLadder:delete();
    self.LTMaster.triggerBaleSlide:delete();
    self.LTMaster.tipTrigger:delete();
    SoundUtil.deleteSample(self.LTMaster.hoods.openingSound);
    SoundUtil.deleteSample(self.LTMaster.hoods.closingSound);
    SoundUtil.deleteSample(self.LTMaster.supports.sound);
    SoundUtil.deleteSample(self.LTMaster.folding.sound);
    SoundUtil.deleteSample(self.LTMaster.ladder.sound);
    SoundUtil.deleteSample(self.LTMaster.baleSlide.sound);
    if self.isClient then
        EffectManager:deleteEffects(self.LTMaster.conveyor.effects);
        EffectManager:deleteEffects(self.LTMaster.silageAdditive.effects);
        for _, particleSystems in pairs(self.LTMaster.conveyor.unloadParticleSystems) do
            ParticleUtil.deleteParticleSystems(particleSystems);
        end
        for _, particleSystems in pairs(self.LTMaster.conveyor.augerParticleSystems) do
            ParticleUtil.deleteParticleSystems(particleSystems);
        end
    end
    LTMaster.deleteBaler(self);
end

function LTMaster:mouseEvent(posX, posY, isDown, isUp, button)
end

function LTMaster:keyEvent(unicode, sym, modifier, isDown)
end

function LTMaster:writeStream(streamId, connection)
    LTMaster.writeStreamBaler(self, streamId, connection);
    if not connection:getIsServer() then
        streamWriteUInt8(streamId, self.LTMaster.hoods["left"].status);
        streamWriteUInt8(streamId, self.LTMaster.hoods["right"].status);
        streamWriteUInt8(streamId, self.LTMaster.supports.status);
        streamWriteUInt8(streamId, self.LTMaster.folding.status);
        streamWriteUInt8(streamId, self.LTMaster.ladder.status);
        streamWriteUInt8(streamId, self.LTMaster.baleSlide.status);
        streamWriteInt32(streamId, self.LTMaster.tipTrigger.id);
        streamWriteBool(streamId, self.LTMaster.sideUnload.isUnloading);
        streamWriteBool(streamId, self.LTMaster.conveyor.isOverloading);
        streamWriteBool(streamId, self.LTMaster.silageAdditive.isUsing);
        streamWriteUInt8(streamId, self.LTMaster.baler.baleVolumesIndex);
        self.LTMaster.tipTrigger:writeStream(streamId, connection);
        g_server:registerObjectInStream(connection, self.LTMaster.tipTrigger);
    end
end

function LTMaster:readStream(streamId, connection)
    LTMaster.readStreamBaler(self, streamId, connection);
    if connection:getIsServer() then
        self.LTMaster.hoods["left"].status = streamReadUInt8(streamId);
        self.LTMaster.hoods["right"].status = streamReadUInt8(streamId);
        self.LTMaster.supports.status = streamReadUInt8(streamId);
        self.LTMaster.folding.status = streamReadUInt8(streamId);
        self.LTMaster.ladder.status = streamReadUInt8(streamId);
        self.LTMaster.baleSlide.status = streamReadUInt8(streamId);
        local tipTriggerId = streamReadInt32(streamId);
        self.LTMaster.sideUnload.isUnloading = streamReadBool(streamId);
        self.LTMaster.conveyor.isOverloading = streamReadBool(streamId);
        self.LTMaster.silageAdditive.isUsing = streamReadBool(streamId);
        self.LTMaster.baler.baleVolumesIndex = streamReadUInt8(streamId);
        self.LTMaster.tipTrigger:readStream(streamId, connection);
        g_client:finishRegisterObject(self.LTMaster.tipTrigger, tipTriggerId);
        LTMaster.finalizeLoad(self);
    end
end

function LTMaster:writeUpdateStream(streamId, connection, dirtyMask)
    if not connection:getIsServer() then
        streamWriteUInt8(streamId, self.LTMaster.hoods["left"].status);
        streamWriteUInt8(streamId, self.LTMaster.hoods["right"].status);
        streamWriteUInt8(streamId, self.LTMaster.supports.status);
        streamWriteUInt8(streamId, self.LTMaster.folding.status);
        streamWriteUInt8(streamId, self.LTMaster.ladder.status);
        streamWriteUInt8(streamId, self.LTMaster.baleSlide.status);
        streamWriteUInt8(streamId, self.LTMaster.baler.baleVolumesIndex);
        streamWriteBool(streamId, self.LTMaster.sideUnload.isUnloading);
        streamWriteBool(streamId, self.LTMaster.conveyor.isOverloading);
        streamWriteBool(streamId, self.LTMaster.silageAdditive.isUsing);
    end
end

function LTMaster:readUpdateStream(streamId, timestamp, connection)
    if connection:getIsServer() then
        self.LTMaster.hoods["left"].status = streamReadUInt8(streamId);
        self.LTMaster.hoods["right"].status = streamReadUInt8(streamId);
        self.LTMaster.supports.status = streamReadUInt8(streamId);
        self.LTMaster.folding.status = streamReadUInt8(streamId);
        self.LTMaster.ladder.status = streamReadUInt8(streamId);
        self.LTMaster.ladder.baleSlide = streamReadUInt8(streamId);
        self.LTMaster.baler.baleVolumesIndex = streamReadUInt8(streamId);
        self.LTMaster.sideUnload.isUnloading = streamReadBool(streamId);
        self.LTMaster.conveyor.isOverloading = streamReadBool(streamId);
        self.LTMaster.silageAdditive.isUsing = streamReadBool(streamId);
    end
end

function LTMaster:update(dt)
    LTMaster.updateBaler(self, dt);
    self.LTMaster.hoods.delayedUpdateHoodStatus:update(dt);
    self.LTMaster.supports.delayedUpdateSupportsStatus:update(dt);
    self.LTMaster.folding.delayedUpdateFoldingStatus:update(dt);
    self.LTMaster.ladder.delayedUpdateLadderStatus:update(dt);
    self.LTMaster.baleSlide.delayedUpdateBaleSlideStatus:update(dt);
    if self.isClient then
        LTMaster.animationsInput(self, dt);
        if self.LTMaster.triggerLeft.active and not self.LTMaster.sideUnload.isUnloading then
            if self:getUnitFillLevel(self.LTMaster.fillUnits["main"].index) <= self.LTMaster.sideUnload.maxAmount then
                g_currentMission:addHelpButtonText(g_i18n:getText("GLTM_UNLOAD_SIDE"), InputBinding.IMPLEMENT_EXTRA4, nil, GS_PRIO_HIGH);
                if InputBinding.hasEvent(InputBinding.IMPLEMENT_EXTRA4) then
                    g_client:getServerConnection():sendEvent(SideUnloadEvent:new(self));
                    self.LTMaster.sideUnload.isUnloading = true;
                end
            end
        end
    end
    if self.isServer then
        if self.baleWrapperState ~= nil and self.baleWrapperState == BaleWrapper.STATE_WRAPPER_FINSIHED then
            self:doStateChange(BaleWrapper.CHANGE_BUTTON_EMPTY);
        end
    end
end

function LTMaster:updateTick(dt)
    local normalizedDt = dt / 1000;
    LTMaster.updateTickBaler(self, dt, normalizedDt);
    PlayerTriggers:update();
    if self.isServer then
        if self.LTMaster.sideUnload.isUnloading then
            for _, fillUnit in pairs({self.LTMaster.fillUnits["left"], self.LTMaster.fillUnits["right"]}) do
                local fillType = self:getUnitLastValidFillType(fillUnit.index);
                local fillLevel = self:getUnitFillLevel(fillUnit.index);
                local delta = math.min(fillLevel, fillUnit.unloadSpeed * dt);
                if delta > 0 then
                    local mainCapacity = self:getUnitCapacity(self.LTMaster.fillUnits["main"].index);
                    local mainFillLevel = self:getUnitFillLevel(self.LTMaster.fillUnits["main"].index);
                    local mainDelta = math.min(delta, mainCapacity - mainFillLevel);
                    if mainDelta > 0 then
                        self:setUnitFillLevel(fillUnit.index, fillLevel - mainDelta, fillType);
                        self:setUnitFillLevel(self.LTMaster.fillUnits["main"].index, mainFillLevel + mainDelta, fillType);
                    end
                end
            end
            if self:getAnimationTime(self.LTMaster.sideUnload.animation) >= 1 then
                self.LTMaster.sideUnload.isUnloading = false;
            end
        end
    end
    if self.isClient then
        if self.LTMaster.silageAdditive.effects ~= nil then
            if self.LTMaster.silageAdditive.isUsing and self:getIsConveyorOverloading() then
                EffectManager:setFillType(self.LTMaster.silageAdditive.effects, self.LTMaster.silageAdditive.fillType);
                EffectManager:startEffects(self.LTMaster.silageAdditive.effects);
            else
                EffectManager:stopEffects(self.LTMaster.silageAdditive.effects);
            end
        end
        if self.LTMaster.conveyor.effects ~= nil then
            if self:getUnitFillLevel(self.LTMaster.fillUnits["main"].index) > 10 then
                if self.LTMaster.conveyor.isOverloading then
                    local lastValidFillType = self:getUnitLastValidFillType(self.LTMaster.fillUnits["main"].index);
                    EffectManager:setFillType(self.LTMaster.conveyor.effects, lastValidFillType);
                    EffectManager:startEffects(self.LTMaster.conveyor.effects);
                    for _, effect in pairs(self.LTMaster.conveyor.effects) do
                        if effect.setScrollUpdate ~= nil then
                            effect:setScrollUpdate(true);
                        end
                    end
                    Utils.updateScrollers(self.LTMaster.conveyor.uvScrollParts, dt, true);
                    Utils.updateRotationNodes(self, self.LTMaster.conveyor.rotatingParts, dt, true);
                else
                    for _, effect in pairs(self.LTMaster.conveyor.effects) do
                        if effect.setScrollUpdate ~= nil then
                            effect:setScrollUpdate(false);
                        end
                    end
                    Utils.updateScrollers(self.LTMaster.conveyor.uvScrollParts, dt, false, false);
                    Utils.updateRotationNodes(self, self.LTMaster.conveyor.rotatingParts, dt, false);
                end
            else
                EffectManager:stopEffects(self.LTMaster.conveyor.effects);
                Utils.updateScrollers(self.LTMaster.conveyor.uvScrollParts, dt, false);
                Utils.updateRotationNodes(self, self.LTMaster.conveyor.rotatingParts, dt, false);
            end
        end
        if self:getIsConveyorOverloading() then
            local currentUnloadParticleSystems = self.LTMaster.conveyor.unloadParticleSystems[self:getUnitLastValidFillType(self.LTMaster.fillUnits["main"].index)];
            if currentUnloadParticleSystems ~= self.LTMaster.conveyor.currentUnloadParticleSystems then
                if self.LTMaster.conveyor.currentUnloadParticleSystems ~= nil then
                    for _, ps in pairs(self.LTMaster.conveyor.currentUnloadParticleSystems) do
                        ParticleUtil.setEmittingState(ps, false);
                    end
                end
                self.LTMaster.conveyor.currentUnloadParticleSystems = currentUnloadParticleSystems;
                if self.LTMaster.conveyor.currentUnloadParticleSystems ~= nil then
                    for _, ps in pairs(self.LTMaster.conveyor.currentUnloadParticleSystems) do
                        ParticleUtil.setEmittingState(ps, true);
                    end
                end
            end
        else
            if self.LTMaster.conveyor.currentUnloadParticleSystems ~= nil then
                for _, ps in pairs(self.LTMaster.conveyor.currentUnloadParticleSystems) do
                    ParticleUtil.setEmittingState(ps, false)
                end
                self.LTMaster.conveyor.currentUnloadParticleSystems = nil;
            end
        end
        if self.LTMaster.conveyor.isOverloading then
            local currentAugerParticleSystems = self.LTMaster.conveyor.augerParticleSystems[self:getUnitLastValidFillType(self.LTMaster.fillUnits["main"].index)];
            if currentAugerParticleSystems ~= self.LTMaster.conveyor.currentAugerParticleSystems then
                if self.LTMaster.conveyor.currentAugerParticleSystems ~= nil then
                    for _, ps in pairs(self.LTMaster.conveyor.currentAugerParticleSystems) do
                        ParticleUtil.setEmittingState(ps, false);
                    end
                end
                self.LTMaster.conveyor.currentAugerParticleSystems = currentAugerParticleSystems;
                if self.LTMaster.conveyor.currentAugerParticleSystems ~= nil then
                    for _, ps in pairs(self.LTMaster.conveyor.currentAugerParticleSystems) do
                        ParticleUtil.setEmittingState(ps, true);
                    end
                end
            end
        else
            if self.LTMaster.conveyor.currentAugerParticleSystems ~= nil then
                for _, ps in pairs(self.LTMaster.conveyor.currentAugerParticleSystems) do
                    ParticleUtil.setEmittingState(ps, false)
                end
                self.LTMaster.conveyor.currentAugerParticleSystems = nil;
            end
        end
    end
end

function LTMaster:draw()
    LTMaster.drawBaler(self);
end

function LTMaster:unloadSide()
    self:playAnimation(self.LTMaster.sideUnload.animation, 1);
    local animationDuration = self:getAnimationDuration(self.LTMaster.sideUnload.animation) / 2;
    self.LTMaster.fillUnits["left"].unloadSpeed = self:getUnitFillLevel(self.LTMaster.fillUnits["left"].index) / animationDuration;
    self.LTMaster.fillUnits["right"].unloadSpeed = self:getUnitFillLevel(self.LTMaster.fillUnits["right"].index) / animationDuration;
    self.LTMaster.sideUnload.isUnloading = true;
end

function LTMaster:getIsFoldAllowed(superFunc, onAiTurnOn)
    if self:getIsTurnedOn() then
        return false;
    end
    if superFunc ~= nil then
        return superFunc(self, onAiTurnOn)
    end
    return true;
end

function LTMaster:getIsTurnedOnAllowed(superFunc, isTurnedOn)
    if isTurnedOn then
        if self.LTMaster.folding.status ~= LTMaster.STATUS_FU_UNFOLDED then
            return false;
        end
    end
    if superFunc ~= nil then
        return superFunc(self, isTurnedOn);
    end
    return true;
end

function LTMaster:getTurnedOnNotAllowedWarning(superFunc)
    if self.LTMaster.folding.status ~= LTMaster.STATUS_FU_UNFOLDED then
        return "qui si deve mettere il messaggio di errore";
    end
    if superFunc ~= nil then
        return superFunc(self);
    end
    return nil;
end

function LTMaster:getConsumedPtoTorque(superFunc)
    local torque = 0;
    if superFunc ~= nil then
        torque = superFunc(self);
    end
    if self.LTMaster.supports.status == LTMaster.STATUS_RL_LOWERING or self.LTMaster.supports.status == LTMaster.STATUS_RL_RAISING then
        torque = torque + (50 / (540 * math.pi / 30));
    end
    if self.LTMaster.folding.status == LTMaster.STATUS_FU_FOLDING or self.LTMaster.folding.status == LTMaster.STATUS_FU_UNFOLDING then
        torque = torque + (120 / (760 * math.pi / 30));
    end
    return torque;
end

function LTMaster:getPtoRpm(superFunc)
    local ptoRpm = 0;
    if superFunc ~= nil then
        ptoRpm = superFunc(self);
    end
    if self.LTMaster.supports.status == LTMaster.STATUS_RL_LOWERING or self.LTMaster.supports.status == LTMaster.STATUS_RL_RAISING then
        ptoRpm = math.max(ptoRpm, 540);
    end
    if self.LTMaster.folding.status == LTMaster.STATUS_FU_FOLDING or self.LTMaster.folding.status == LTMaster.STATUS_FU_UNFOLDING then
        ptoRpm = math.max(ptoRpm, 760);
    end
    return ptoRpm;
end

function LTMaster:getIsConveyorOverloading()
    return self.LTMaster.conveyor.isOverloading and self.LTMaster.conveyor.effects[1].state == ShaderPlaneEffect.STATE_ON;
end
