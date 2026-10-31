-- Properties for cars the server spawned for us, and what the server can't
-- know about a model on its own.

local submarines = {}
for _, name in ipairs({ 'submersible', 'submersible2', 'avisa', 'kosatka' }) do submarines[joaat(name)] = true end

function ModelType(hash)
    hash = type(hash) == 'string' and (tonumber(hash) or joaat(hash)) or tonumber(hash)
    if not hash or not IsModelInCdimage(hash) or not IsModelAVehicle(hash) then return end
    if IsThisModelAHeli(hash) then return 'heli' end
    if IsThisModelAPlane(hash) then return 'plane' end
    if submarines[hash] then return 'submarine' end
    if IsThisModelABoat(hash) or IsThisModelAJetski(hash) then return 'boat' end
    if IsThisModelABike(hash) or IsThisModelABicycle(hash) then return 'bike' end
    if IsThisModelATrain(hash) then return 'train' end
    if GetVehicleClassFromName(hash) == 11 and GetDisplayNameFromVehicleModel(hash):lower():find('trailer') then return 'trailer' end
    return 'automobile'
end

lib.callback.register('fivegarage:modelType', ModelType)

local function waitFor(fn, ms)
    local stop = GetGameTimer() + ms
    repeat
        local v = fn()
        if v then return v end
        Wait(50)
    until GetGameTimer() > stop
end

AddStateBagChangeHandler('fivegarage', nil, function(bag, _, value)
    if type(value) ~= 'table' or value.owner ~= cache.serverId then return end

    local veh = waitFor(function()
        local e = GetEntityFromStateBagName(bag)
        return e ~= 0 and e or nil
    end, 5000)
    if not veh then return end

    local mine = waitFor(function()
        if NetworkGetEntityOwner(veh) == cache.playerId then return true end
        NetworkRequestControlOfEntity(veh)
    end, 5000)
    if not mine then return end

    if value.props then lib.setVehicleProperties(veh, value.props) end
    if value.fuel then SetVehicleFuelLevel(veh, value.fuel + 0.0) end
    if value.livery then
        SetVehicleLivery(veh, value.livery)
        if GetNumVehicleMods(veh, 48) > 0 then
            SetVehicleModKit(veh, 0)
            SetVehicleMod(veh, 48, value.livery, false)
        end
    end
    for id, on in pairs(value.extras or {}) do
        id = tonumber(id)
        if id and DoesExtraExist(veh, id) then SetVehicleExtra(veh, id, not on) end
    end
    SetVehicleDirtLevel(veh, 0.0)
    SetVehicleOnGroundProperly(veh)
    Entity(veh).state:set('fivegarage', nil, true)
end)

-- --------------------------------------------------------------------- labels

function VehicleLabel(model, fallback)
    local hash = type(model) == 'string' and (tonumber(model) or joaat(model)) or tonumber(model)
    if not hash then return fallback or 'Vehicle' end
    local name = GetDisplayNameFromVehicleModel(hash)
    local label = name and GetLabelText(name)
    if label and label ~= 'NULL' then return label end
    if fallback then return fallback end
    return name and name ~= 'CARNOTFOUND' and name:sub(1, 1) .. name:sub(2):lower() or 'Vehicle'
end

-- ------------------------------------------------------------------- impound

local function canImpound()
    local me = LocalPlayer.state.fivegarage
    local grade = me and Config.impound.jobs[me.job]
    return grade ~= nil and (me.grade or 0) >= grade and (not Config.impound.onDuty or me.duty)
end

local function impound(veh)
    if not veh or veh == 0 then return lib.notify({ description = 'No vehicle nearby.', type = 'error' }) end
    local input = lib.inputDialog('Impound ' .. GetVehicleNumberPlateText(veh), {
        { type = 'number', label = 'Fee', default = Config.impound.defaultFee, min = 0, max = Config.impound.maxFee },
        { type = 'input', label = 'Reason', max = 120 },
    })
    if not input or not DoesEntityExist(veh) then return end
    local ok, msg = lib.callback.await('fivegarage:impound', false, NetworkGetNetworkIdFromEntity(veh), input[1], input[2])
    lib.notify({ description = msg or (ok and 'Done.' or 'Not allowed.'), type = ok and 'success' or 'error' })
end

RegisterCommand(Config.impound.command, function()
    if not canImpound() then return lib.notify({ description = 'Not allowed.', type = 'error' }) end
    local veh = cache.vehicle or lib.getClosestVehicle(GetEntityCoords(cache.ped), 5.0, false)
    impound(veh)
end, false)

if Config.impound.target and GetResourceState('ox_target') == 'started' then
    exports.ox_target:addGlobalVehicle({
        {
            name = 'fivegarage:impound',
            icon = 'fa-solid fa-truck-pickup',
            label = 'Impound',
            distance = 3.0,
            canInteract = function() return canImpound() end,
            onSelect = function(data) impound(data.entity) end,
        },
    })
end
