--!strict
-- This module is a class that represents a stage.
-- 
-- Programmer: Christian Toney (Christian_Toney)
-- © 2024 – 2025 Beastslash LLC

local DataStoreService = game:GetService("DataStoreService");
local DataStore = {
  StageMetadata = DataStoreService:GetDataStore("StageMetadata");
  StageBuildData = DataStoreService:GetDataStore("StageBuildData");
  PublishedStages = DataStoreService:GetOrderedDataStore("PublishedStages");
  PrivateServerStages = DataStoreService:GetDataStore("PrivateServerStages");
  Inventory = DataStoreService:GetDataStore("Inventory");
};
local HttpService = game:GetService("HttpService");

export type PermissionOverride = {
  ["stage.delete"]: boolean?;
  ["stage.save"]: boolean?;
};

export type StageMemberObject = {
  id: number;
  role: "Admin";
};

export type StageConstructorProperties = {

  -- The stage's unique ID.
  id: string;
  
  -- A list of stage overrides.
  permissionOverrides: {PermissionOverride};
  
  -- The stage's name.
  name: string;
  
  -- Time in seconds when the stage was created.
  timeCreated: number;
  
  --Time in seconds when the stage was last updated.
  timeUpdated: number;
  
  -- The stage's description.
  description: string?;

  -- The stage's description.
  isPublished: boolean;

  -- The stage's members.
  members: {StageMemberObject};

};

export type StageProperties = StageConstructorProperties & {

  model: Model?;
  
}

export type UpdatableStageProperties = {
  id: string?;
  permissionOverrides: {PermissionOverride}?;
  name: string?;
  timeCreated: number?;
  timeUpdated: number?;
  description: string?;
  isPublished: boolean?;
  members: {StageMemberObject}?;
}

export type StageMethods = {
  updateBuildData: (self: Stage, newData: {string}) -> ();
  updateMetadata: (self: Stage, newData: UpdatableStageProperties) -> ();
  delete: (self: Stage) -> ();
  download: (self: Stage) -> Model;
  publish: (self: Stage) -> ();
  unpublish: (self: Stage) -> ();
  getBuildData: (self: Stage) -> StageBuildData;
  toString: (self: Stage) -> string;
}

export type StageEvents = {

  -- Fires when the stage metadata is updated.
  onMetadataUpdate: BindableEvent;
  
  -- Fires when the build data is completely updated.
  onBuildDataUpdate: BindableEvent;
  
  -- Fires when the build data is partially updated. 
  onBuildDataUpdateProgressChanged: BindableEvent;

  onStageBuildDataDownloadProgressChanged: BindableEvent;
  
  -- Fires when the stage is deleted.
  onDelete: BindableEvent;
  
}

local Stage = {
  __index = {} :: StageMethods;
};

export type Stage = typeof(setmetatable({}, {__index = Stage.__index})) & StageProperties & StageMethods & StageEvents;

export type StageBuildDataItem = {
  type: string; 
  properties: {[string]: any};
  attributes: {[string]: any};
};

export type StageBuildData = {{StageBuildDataItem}};

-- Returns a new Stage object.
function Stage.new(properties: StageProperties): Stage
  
  local stage = properties;

  for _, eventName in ipairs({"onMetadataUpdate", "onBuildDataUpdate", "onBuildDataUpdateProgressChanged", "onDelete", "onStageBuildDataDownloadProgressChanged"}) do

    stage[eventName] = Instance.new("BindableEvent");

  end

  setmetatable(stage, {__index = Stage.__index});
  
  return stage :: any;
  
end

-- Returns a random Stage object from the published stages list.
function Stage.random(): Stage

  -- Get a random published ID.
  local dataStorePages = DataStore.PublishedStages:GetSortedAsync(true, 100);
  local publishedStageIDs = {};
  repeat 

    local currentPage = dataStorePages:GetCurrentPage();
    for _, entry in ipairs(currentPage) do

      table.insert(publishedStageIDs, entry.key)

    end;

    if not dataStorePages.IsFinished then

      dataStorePages:AdvanceToNextPageAsync();

    end;

  until dataStorePages.IsFinished;

  if #publishedStageIDs == 0 then

    error("There are no published stages available.");

  end;

  local stage: Stage;
  repeat

    local selectedStageIDIndex = math.random(1, #publishedStageIDs);
    local selectedStageID = publishedStageIDs[selectedStageIDIndex];

    local stageFound, errorMessage = pcall(function()
      
      local possibleStage = Stage.fromID(selectedStageID);
      stage = possibleStage;

    end);

    if not stageFound and errorMessage:find("doesn't exist") then

      task.spawn(function()

        DataStore.PublishedStages:RemoveAsync(selectedStageID);
        table.remove(publishedStageIDs, selectedStageIDIndex);
        print(`Removed {selectedStageID} from the published stages list because it doesn't exist.`);

      end);

    end;

  until stage;

  return stage;

end;

-- Returns a new Stage object based on an ID.
function Stage.fromID(id: string): Stage
  
  local encodedStageData = DataStoreService:GetDataStore("StageMetadata"):GetAsync(id);
  assert(encodedStageData, `Stage {id} doesn't exist.`);
  
  local stageData = HttpService:JSONDecode(encodedStageData);
  stageData.id = id;
  
  return Stage.new(stageData);
  
end

-- Returns a list of the player's stages. Removes stage IDs that cannot be found.
function Stage.listFromOwnerID(ownerID: number): {Stage}

  local stages = {};
  local keyList = DataStore.Inventory:ListKeysAsync(`{ownerID}/stages`);
  repeat

    local keys = keyList:GetCurrentPage();
    local stageIDsToRemove = {};
    for _, key in ipairs(keys) do

      local stageListEncoded = DataStore.Inventory:GetAsync(key.KeyName);
      local stageList = HttpService:JSONDecode(stageListEncoded);
      for _, stageID in ipairs(stageList) do
  
        local success, message = pcall(function()

          table.insert(stages, Stage.fromID(stageID));

        end);
        
        if not success then

          if message:find("doesn't exist yet.") then

            stageIDsToRemove[key.KeyName] = stageIDsToRemove[key.KeyName] or {};
            table.insert(stageIDsToRemove[key.KeyName], stageID);

          else

            warn(message);

          end;
  
        end;
  
      end;
  
    end;

    for keyName, stageIDs in pairs(stageIDsToRemove) do

      DataStore.Inventory:UpdateAsync(keyName, function(encodedStageIDs)
      
        local decodedStageIDs = HttpService:JSONDecode(encodedStageIDs);
        for _, stageID in ipairs(stageIDs) do

          local indexToRemove = table.find(decodedStageIDs, stageID);
          if indexToRemove then
          
            table.remove(decodedStageIDs, indexToRemove);

          end;

        end;
        
        return HttpService:JSONEncode(decodedStageIDs);

      end);

      print(`Removed the following stage IDs because they don't exist: {HttpService:JSONEncode(stageIDs)}`);

    end;

    if not keyList.IsFinished then

      keyList:AdvanceToNextPageAsync();

    end;

  until keyList.IsFinished;

  return stages;

end;

-- Returns a random, unused stage ID.
function Stage:generateID(): string
  
  local possibleID;

  while task.wait() and not possibleID do

    -- Generate a stage ID.
    possibleID = HttpService:GenerateGUID();
    local canGetStage = pcall(function() Stage.fromID(possibleID) end);
    if canGetStage then 

      possibleID = nil;

    end;
    
  end;

  return possibleID;
  
end

-- Edits the stage's build data.
function Stage.__index:updateBuildData(newBuildData: {string}): ()

  for index, chunk in ipairs(newBuildData) do

    DataStore.StageBuildData:SetAsync(`{self.id}/{index}`, chunk);
    self.onBuildDataUpdateProgressChanged:Fire(index, #newBuildData);

  end
  self.onBuildDataUpdate:Fire();

end

-- Edits the stage's metadata.
function Stage.__index:updateMetadata(newData: UpdatableStageProperties): ()

  DataStore.StageMetadata:UpdateAsync(self.id, function(encodedOldMetadata)
  
    local newMetadata = HttpService:JSONDecode(encodedOldMetadata or "{}");
    for key, value in pairs(newData) do

      newMetadata[key] = value;

    end;

    return HttpService:JSONEncode(newMetadata);

  end);

  for key, value in pairs(newData) do

    (self :: {})[key] = value;

  end;
  
  self.onMetadataUpdate:Fire(newData);
  
end

-- Irrecoverably deletes the stage, including its build data.
-- This also unpublishes the stage if it is published.
-- This method does not remove the stage from members' inventories because it may take a longer time.
-- Instead, the stage will be automatically deleted from the members' inventories as the Stage Maker cannot find them. (See Player.__index:getStages())
function Stage.__index:delete(): ()
  
  -- Remove the stage from the published stages list if possible.
  if self.isPublished then

    self:unpublish();

  end;

  -- Delete build data.
  local keyList = DataStore.StageBuildData:ListKeysAsync(self.id);
  repeat

    local keys = keyList:GetCurrentPage();
    for _, key in ipairs(keys) do

      DataStore.StageBuildData:RemoveAsync(key.KeyName);
  
    end;

    if not keyList.IsFinished then

      keyList:AdvanceToNextPageAsync();

    end;

  until keyList.IsFinished;
  
  -- Delete metadata.
  DataStore.StageMetadata:RemoveAsync(self.id);

  -- Tell the player.
  print(`Stage {self.id} has been successfully deleted.`);
  self.onDelete:Fire();
  
end

function Stage.__index:download(): Model

  local stageModel = Instance.new("Model");
  local buildData = self:getBuildData();

  -- Calculate the total parts.
  local totalParts = 0;
  for _, page in ipairs(buildData) do

    for _, instance in ipairs(page) do

      totalParts += 1;

    end;

  end;

  -- Add the parts to the stage model.
  local partsAudited = 0;
  for _, page in ipairs(buildData) do

    for _, instanceData in ipairs(page) do

      local instance = Instance.new(instanceData.type) :: any;
      instance.Anchored = true;
      local function setEnum(enum, property, value)

        for _, enumItem in ipairs(enum:GetEnumItems()) do

          if enumItem.Value == value then
            
            instance[property] = enumItem;

          end;

        end;  

      end;

      for property, value in pairs(instanceData.properties) do

        local enumProperties = {
          Material = Enum.Material;
          Shape = Enum.PartType;
          BackSurface = Enum.SurfaceType;
          BottomSurface = Enum.SurfaceType;
          FrontSurface = Enum.SurfaceType;
          LeftSurface = Enum.SurfaceType;
          RightSurface = Enum.SurfaceType;
          TopSurface = Enum.SurfaceType;
        }

        if property == "Color" then

          instance[property] = Color3.fromHex(value);

        elseif ({Size = 1; Position = 1; Orientation = 1})[property] then

          instance[property] = Vector3.new(value.X, value.Y, value.Z);

        elseif enumProperties[property] then

          setEnum(enumProperties[property], property, value);

        elseif ({Transparency = 1; Reflectance = 1; Name = 1; CastShadow = 1; Anchored = 1; CanCollide = 1;})[property] then

          instance[property] = value;

        else

          warn(`Unknown property: {property}`);

        end;

      end;

      for attribute, value in pairs(instanceData.attributes) do

        instance:SetAttribute(attribute, value);

      end;

      local baseDurability = instance:GetAttribute("BaseDurability");
      if baseDurability then

        instance:SetAttribute("CurrentDurability", baseDurability);

      end

      instance.Parent = stageModel;

      partsAudited += 1;
      self.onStageBuildDataDownloadProgressChanged:Fire(partsAudited, totalParts);

    end;

  end;

  self.model = stageModel;

  return stageModel;

end;

-- Adds this stage's build data to the published stage index.
function Stage.__index:publish(): ()

  -- Verify that this stage isn't already published.
  assert(not self.isPublished, "This stage is already published.");

  -- Add this stage to the published stages list.
  DataStore.PublishedStages:SetAsync(self.id :: string, DateTime.now().UnixTimestampMillis);

  -- Mark this stage has published.
  self:updateMetadata({isPublished = true});

  print(`Successfully published Stage {self.id}.`);

end;

-- Removes this stage from the published stage index.
function Stage.__index:unpublish(): ()

  -- Verify that this stage is published.
  assert(self.isPublished, "This stage is already unpublished.");

  -- Remove this stage from the published stages list.
  DataStore.PublishedStages:RemoveAsync(self.id);

  -- Mark this stage has unpublished.
  self:updateMetadata({isPublished = false});

  print(`Successfully unpublished Stage {self.id}.`);

end;

-- Returns this stage's build data.
function Stage.__index:getBuildData(): StageBuildData

  local keyList = DataStore.StageBuildData:ListKeysAsync(self.id);
  local buildDataEncoded = {};
  repeat

    local keys = keyList:GetCurrentPage();
    for _, key in ipairs(keys) do

      local partialEncodedBuildData = DataStore.StageBuildData:GetAsync(key.KeyName);
      table.insert(buildDataEncoded, HttpService:JSONDecode(partialEncodedBuildData));
  
    end;

    if not keyList.IsFinished then

      keyList:AdvanceToNextPageAsync();

    end;

  until keyList.IsFinished;

  return buildDataEncoded;

end;

function Stage.__index:toString(): string

  local properties = {"ID", "permissionOverrides", "name", "timeCreated", "timeUpdated", "description", "isPublished", "members"}
  local encodedData = {};
  for _, property in ipairs(properties) do

    encodedData[property] = (self :: {})[property];

  end;

  return HttpService:JSONEncode(encodedData);

end;

return Stage;