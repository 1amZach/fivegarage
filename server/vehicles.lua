-- Spawning, tracking which plates are out, and the other resources we talk to.

Garage = { out = {}, jobs = {}, entities = {}, busy = {}, last = {} }
local G = Garage

local function started(name) return GetResourceState(name) == 'started' end
G.started = started

function G.dist(a, b)
    local dx, dy, dz = a.x - b.x, a.y - b.y, (a.z or 0) - (b.z or 0)
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

function G.pos(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return end
    return GetEntityCoords(ped), ped
end

-- Distance from the server's idea of where the player is, never the client's.
function G.near(src, place)
    local pos = G.pos(src)
    return pos and G.dist(pos, place.coords) <= (place.radius or Config.radius), pos
end

function G.ready(src, key)
    local k, now = src .. ':' .. key, GetGameTimer()
    if G.last[k] and now - G.last[k] < Config.cooldown * 1000 then return false end
    G.last[k] = now
    return true
end

function G.who(src)
    local p = Framework.player(src)
    return p and p.name or GetPlayerName(src) or 'Console'
end

-- --------------------------------------------------------------- integrations

function G.log(src, text, data)
    if not started('fivelog') then return end
    pcall(function() exports.fivelog:add('vehicles', src, text, data) end)
end

function G.panel(src, text)
    if not started('fivepanel') then return end
    local name = src and src > 0 and GetPlayerName(src)
    TriggerEvent('fivepanel:activity', name and ('%s (in game)'):format(name) or 'Console', text)
end

-- Something a normal client never sends. Logged, and the client gets a plain no.
function G.odd(src, text, data)
    print(('[fivegarage] refused %s (%s): %s'):format(GetPlayerName(src) or '?', src, text))
    G.log(src, 'Refused: ' .. text, data)
    return false, 'Not allowed.'
end

-- warden only needs to look away from the checks a garage spawn can trip:
-- a job model on its blocked list, a few cars in a row, the warp into the seat.
local wardenKinds = { 'blockedModel', 'entitySpam', 'teleport' }

local function quiet(src)
    if not started('warden') then return end
    for _, kind in ipairs(wardenKinds) do
        pcall(function() exports.warden:allow(src, kind, 5) end)
    end
end

function G.keys(src, veh, plate)
    if started('qbx_vehiclekeys') then
        if pcall(function() exports.qbx_vehiclekeys:GiveKeys(src, veh) end) then return end
        TriggerClientEvent('vehiclekeys:client:SetOwner', src, plate)
    elseif started('qb-vehiclekeys') then
        TriggerClientEvent('vehiclekeys:client:SetOwner', src, plate)
    elseif Config.giveKeys then
        pcall(Config.giveKeys, src, veh, plate)
    end
end

-- ------------------------------------------------------------------ tracking

function G.track(plate, veh, src, garage)
    G.out[plate] = { entity = veh, src = src, garage = garage }
    G.entities[veh] = plate
end

function G.untrack(plate)
    local o = G.out[plate] or G.jobs[plate]
    if o then G.entities[o.entity] = nil end
    G.out[plate], G.jobs[plate] = nil, nil
end

function G.world()
    local list = {}
    for _, veh in ipairs(GetAllVehicles()) do
        local plate = DB.trim(GetVehicleNumberPlateText(veh))
        if plate then list[plate] = veh end
    end
    return list
end

-- The entity for a plate that's out and still exists. A car spawned by some
-- other script with the same plate counts too.
function G.isOut(plate)
    local o = G.out[plate]
    if o and DoesEntityExist(o.entity) then return o.entity end
    if o then G.untrack(plate) end
    local veh = G.world()[plate]
    if veh then G.track(plate, veh) end
    return veh
end

AddEventHandler('entityRemoved', function(entity)
    local plate = G.entities[entity]
    if plate then G.untrack(plate) end
end)

function G.freeSpawn(place)
    local taken = {}
    for _, veh in ipairs(GetAllVehicles()) do taken[#taken + 1] = GetEntityCoords(veh) end
    for _, spot in ipairs(place.spawns) do
        local clear = true
        for _, c in ipairs(taken) do
            if G.dist(c, spot) < Config.clearRadius then clear = false break end
        end
        if clear then return spot end
    end
end

-- ------------------------------------------------------------------- spawning

local vehicleTypes = { automobile = true, bike = true, boat = true, heli = true, plane = true, submarine = true, trailer = true, train = true }
local known = {}

function G.hash(model)
    local h = type(model) == 'string' and (tonumber(model) or GetHashKey(model)) or tonumber(model)
    return h and math.tointeger(h) and (math.tointeger(h) & 0xFFFFFFFF) or nil
end

-- CreateVehicleServerSetter needs the vehicle type up front. Qbox knows it for
-- the vehicles in its shared list, anything else is asked from the player's
-- client and only trusted for that player.
function G.modelType(src, model)
    local hash = G.hash(model)
    if not hash then return end
    if known[hash] then return known[hash], hash end

    if Framework.name() == 'qbx' then
        local ok, v = pcall(function() return exports.qbx_core:GetVehiclesByHash(hash) end)
        local t = ok and type(v) == 'table' and v.type
        if vehicleTypes[t] then
            known[hash] = t
            return t, hash
        end
    end

    if not src or src <= 0 then return nil, hash end
    local t = lib.callback.await('fivegarage:modelType', src, hash)
    return vehicleTypes[t] and t or nil, hash
end

function G.fits(garageType, vtype)
    return not garageType or (Config.types[garageType] or {})[vtype] == true
end

-- opts: model, plate, coords (vec4), props, fuel, job ({ livery, extras })
function G.spawn(src, opts)
    local vtype, hash = G.modelType(src, opts.model)
    if not vtype then return nil, 'Unknown vehicle model.' end
    if not G.fits(opts.garageType, vtype) then return nil, "That vehicle can't come out here." end

    quiet(src)
    local c = opts.coords
    local veh = CreateVehicleServerSetter(hash, vtype, c.x, c.y, c.z, c.w or 0.0)
    for _ = 1, 100 do
        if veh and veh ~= 0 and DoesEntityExist(veh) then break end
        Wait(20)
    end
    if not veh or veh == 0 or not DoesEntityExist(veh) then return nil, 'The vehicle failed to spawn.' end

    SetVehicleNumberPlateText(veh, opts.plate)
    SetEntityRoutingBucket(veh, GetPlayerRoutingBucket(src))
    if Config.warpIn then SetPedIntoVehicle(GetPlayerPed(src), veh, -1) end

    local fuel = math.max(0, math.min(100, tonumber(opts.fuel) or 100))
    local state = Entity(veh).state
    if Config.fuel == 'ox_fuel' then state:set('fuel', fuel, true) end
    -- applied by the requesting player's client once it owns the entity
    state:set('fivegarage', {
        owner = src,
        props = opts.props,
        fuel = Config.fuel == 'native' and fuel or nil,
        livery = opts.job and opts.job.livery,
        extras = opts.job and opts.job.extras,
    }, true)

    G.keys(src, veh, opts.plate)
    return veh, NetworkGetNetworkIdFromEntity(veh)
end

-- An owned car out of a garage or depot. `r` is a DB row.
function G.takeOut(src, r, coords, from, garageType)
    if G.busy[r.plate] then return nil, 'That vehicle is already on its way.' end
    G.busy[r.plate] = true

    local props = r.props or {}
    props.plate, props.fuelLevel = r.plate, r.fuel
    props.engineHealth, props.bodyHealth = r.engine, r.body
    local ok, veh, netId = pcall(G.spawn, src, {
        model = r.model, plate = r.plate, coords = coords, props = props, fuel = r.fuel, garageType = garageType,
    })
    G.busy[r.plate] = nil
    if not ok then
        print(('[fivegarage] spawning %s failed: %s'):format(r.plate, veh))
        return nil, 'The vehicle failed to spawn.'
    end
    if not veh then return nil, netId end

    G.track(r.plate, veh, src, from)
    DB.setState(r.plate, 0, nil, 0, nil)
    TriggerEvent('fivegarage:spawned', src, r.plate, netId, from)
    return veh, netId
end

AddEventHandler('playerDropped', function()
    local prefix = source .. ':'
    for k in pairs(G.last) do
        if k:sub(1, #prefix) == prefix then G.last[k] = nil end
    end
end)
