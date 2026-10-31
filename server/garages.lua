-- Public and shared garages, depots and police impound.

local G = Garage

function G.access(p, place)
    if place.job then return p.job == place.job and p.grade >= (place.grade or 0) and (not place.onDuty or p.duty) end
    if place.gang then return p.gang == place.gang and p.gangGrade >= (place.grade or 0) end
    return true
end

local function shared(g) return g.job or g.gang end

local function depotFee(r)
    return r.state == 2 and r.fee > 0 and r.fee or Config.depotFee
end

local function entry(r, extra)
    local e = {
        plate = r.plate, model = r.model, name = r.name,
        fuel = math.floor(r.fuel + 0.5), engine = math.floor(r.engine / 10 + 0.5), body = math.floor(r.body / 10 + 0.5),
        state = r.state, reason = r.reason,
    }
    for k, v in pairs(extra or {}) do e[k] = v end
    return e
end

-- Where the car is parked, if that's one of ours. Cars from an old garage
-- script with names we don't know can be taken anywhere.
local function parkedAt(r)
    return r.garage and Config.garages[r.garage] and r.garage or nil
end

local performance = { 'modEngine', 'modBrakes', 'modTransmission', 'modSuspension', 'modArmor', 'modTurbo' }

local function cleanProps(props, r, veh)
    if type(props) ~= 'table' then props = {} end
    local ok, s = pcall(json.encode, props)
    if not ok or #s > 32768 then props = {} end
    if not next(props) then props = r.props or {} end
    if Config.keepPerformance then
        for _, k in ipairs(performance) do props[k] = (r.props or {})[k] end
    end
    props.plate = r.plate
    props.model = GetEntityModel(veh)
    props.engineHealth = GetVehicleEngineHealth(veh)
    props.bodyHealth = GetVehicleBodyHealth(veh)
    return props
end

local function fuelOf(veh, props)
    local f = Config.fuel == 'ox_fuel' and Entity(veh).state.fuel or props.fuelLevel
    return math.max(0, math.min(100, tonumber(f) or 100))
end

local function vehicleAt(netId)
    local veh = NetworkGetEntityFromNetworkId(tonumber(netId) or 0)
    if not veh or veh == 0 or not DoesEntityExist(veh) or GetEntityType(veh) ~= 2 then return end
    return veh, DB.trim(GetVehicleNumberPlateText(veh))
end
G.vehicleAt = vehicleAt

local function pay(src, fee, reason)
    if fee <= 0 then return 'none' end
    return Framework.pay(src, fee, reason)
end

-- ------------------------------------------------------------------ garages

lib.callback.register('fivegarage:list', function(src, id)
    local g, p = Config.garages[id], Framework.player(src)
    if not g or not p then return end
    if not G.access(p, g) then return G.odd(src, ('opened %s without access'):format(g.label)) end
    if not G.near(src, g) then return end

    local list, seen = {}, {}
    for _, r in ipairs(DB.owned(p.id)) do
        seen[r.plate] = true
        local at = parkedAt(r)
        local e = entry(r, { garage = at and Config.garages[at].label })
        if r.state == 1 then
            e.here = not at or at == id
            if not e.here then e.fee = Config.transferFee or nil end
        elseif r.state == 0 then
            e.out = G.isOut(r.plate) ~= nil
        end
        list[#list + 1] = e
    end
    if shared(g) then
        for _, r in ipairs(DB.parked(id)) do
            if not seen[r.plate] then list[#list + 1] = entry(r, { here = true, shared = true }) end
        end
    end
    return list
end)

lib.callback.register('fivegarage:take', function(src, id, plate)
    local g, p = Config.garages[id], Framework.player(src)
    if not g or not p or type(plate) ~= 'string' then return false end
    if not G.ready(src, 'garage') then return false, 'Slow down.' end
    if not G.access(p, g) then return G.odd(src, ('used %s without access'):format(g.label)) end
    local near, pos = G.near(src, g)
    if not near then
        return G.odd(src, ('tried to take %s out at %s from %.0fm away'):format(plate, g.label, pos and G.dist(pos, g.coords) or -1))
    end

    local r = DB.byPlate(plate)
    if not r then return G.odd(src, ('tried to take unknown plate %s'):format(plate:sub(1, 12))) end
    local here = parkedAt(r)
    if r.owner ~= p.id and not (shared(g) and here == id) then
        return G.odd(src, ('tried to take %s, which belongs to someone else'):format(r.plate), { plate = r.plate })
    end
    if G.isOut(r.plate) then return false, 'That vehicle is already out.' end
    if r.state == 2 then return false, 'That vehicle is impounded.' end
    if r.state ~= 1 then return false, 'That vehicle is at the depot.' end

    local fee = 0
    if here and here ~= id then
        if not Config.transferFee then return false, ('That vehicle is parked at %s.'):format(Config.garages[here].label) end
        fee = Config.transferFee
    end

    local vtype = G.modelType(src, r.model)
    if not vtype or not G.fits(g.type, vtype) then return false, "That vehicle can't come out here." end
    local spot = G.freeSpawn(g)
    if not spot then return false, 'Every spot is taken. Move a vehicle first.' end

    local account = pay(src, fee, 'garage-transfer')
    if not account then return false, ("You can't afford the $%d fee."):format(fee) end

    local veh, err = G.takeOut(src, r, spot, id, g.type)
    if not veh then
        Framework.refund(src, account, fee, 'garage-transfer')
        return false, err
    end
    G.log(src, ('%s took %s out of %s%s'):format(G.who(src), r.plate, g.label, fee > 0 and (' for $%d'):format(fee) or ''),
        { plate = r.plate, garage = id, fee = fee })
    return true
end)

lib.callback.register('fivegarage:store', function(src, id, netId, props)
    local g, p = Config.garages[id], Framework.player(src)
    if not g or not p then return false end
    if not G.ready(src, 'garage') then return false, 'Slow down.' end
    if not G.access(p, g) then return G.odd(src, ('used %s without access'):format(g.label)) end
    if not G.near(src, g) then return G.odd(src, ('tried to park at %s from too far away'):format(g.label)) end

    local veh, plate = vehicleAt(netId)
    if not veh then return false, 'No vehicle to park.' end
    if G.dist(GetEntityCoords(veh), g.coords) > (g.radius or Config.radius) then return false, 'The vehicle is too far away.' end
    if G.jobs[plate] then return false, 'Job vehicles go back to their job garage.' end

    local r = DB.byPlate(plate)
    if not r then return false, "You don't own this vehicle." end
    if r.owner ~= p.id then
        return G.odd(src, ('tried to park %s, which belongs to someone else'):format(plate), { plate = plate })
    end
    -- a plate changed on someone else's car
    local model = G.hash(r.model)
    if model and model ~= G.hash(GetEntityModel(veh)) then
        return G.odd(src, ('tried to park a different model as %s'):format(plate), { plate = plate, model = GetEntityModel(veh) })
    end
    if not G.fits(g.type, GetVehicleType(veh)) then return false, "That vehicle can't be parked here." end

    props = cleanProps(props, r, veh)
    local fuel = fuelOf(veh, props)
    local engine, body = props.engineHealth, props.bodyHealth
    props.fuelLevel = fuel

    DeleteEntity(veh)
    G.untrack(plate)
    DB.store(plate, id, props, fuel, engine, body)
    TriggerEvent('fivegarage:stored', src, plate, id)
    G.log(src, ('%s parked %s at %s'):format(G.who(src), plate, g.label), { plate = plate, garage = id, fuel = fuel, engine = engine, body = body })
    return true
end)

-- -------------------------------------------------------------------- depots

lib.callback.register('fivegarage:depot', function(src, id)
    local d, p = Config.depots[id], Framework.player(src)
    if not d or not p or not G.near(src, d) then return end
    local list = {}
    for _, r in ipairs(DB.owned(p.id)) do
        if r.state == 2 or (r.state == 0 and not G.isOut(r.plate)) then
            list[#list + 1] = entry(r, { fee = depotFee(r) })
        end
    end
    return list
end)

lib.callback.register('fivegarage:recover', function(src, id, plate)
    local d, p = Config.depots[id], Framework.player(src)
    if not d or not p or type(plate) ~= 'string' then return false end
    if not G.ready(src, 'garage') then return false, 'Slow down.' end
    if not G.near(src, d) then return G.odd(src, ('tried to use %s from too far away'):format(d.label)) end

    local r = DB.byPlate(plate)
    if not r then return G.odd(src, ('tried to recover unknown plate %s'):format(plate:sub(1, 12))) end
    if r.owner ~= p.id then return G.odd(src, ('tried to recover %s, which belongs to someone else'):format(r.plate)) end
    if r.state == 1 then return false, 'That vehicle is in a garage.' end
    if G.isOut(r.plate) then return false, 'That vehicle is still out.' end

    local vtype = G.modelType(src, r.model)
    if not vtype or not G.fits(d.type, vtype) then return false, "That vehicle isn't kept here." end
    local spot = G.freeSpawn(d)
    if not spot then return false, 'Every spot is taken. Move a vehicle first.' end

    local fee = depotFee(r)
    local account = pay(src, fee, 'vehicle-depot')
    if not account then return false, ("You can't afford the $%d fee."):format(fee) end

    local veh, err = G.takeOut(src, r, spot, id, d.type)
    if not veh then
        Framework.refund(src, account, fee, 'vehicle-depot')
        return false, err
    end
    G.log(src, ('%s got %s back from %s for $%d'):format(G.who(src), r.plate, d.label, fee), { plate = r.plate, depot = id, fee = fee })
    return true
end)

-- ------------------------------------------------------------------- impound

-- Deletes the car and, if someone owns it, sends it to the depot.
-- Returns 'owned', 'job' or 'other'.
function G.impound(plate, veh, fee, reason)
    if veh and DoesEntityExist(veh) then DeleteEntity(veh) end
    local job = G.jobs[plate] ~= nil
    G.untrack(plate)
    if job then return 'job' end
    if not DB.byPlate(plate) then return 'other' end
    DB.setState(plate, 2, nil, fee, reason)
    return 'owned'
end

function G.canImpound(p)
    local grade = p and Config.impound.jobs[p.job]
    return grade ~= nil and p.grade >= grade and (not Config.impound.onDuty or p.duty)
end

lib.callback.register('fivegarage:impound', function(src, netId, fee, reason)
    local p = Framework.player(src)
    if not G.canImpound(p) then return G.odd(src, 'tried to impound without the job') end
    if not G.ready(src, 'impound') then return false, 'Slow down.' end

    local veh, plate = vehicleAt(netId)
    if not veh then return false, 'No vehicle found.' end
    local pos = G.pos(src)
    if not pos or G.dist(pos, GetEntityCoords(veh)) > Config.impound.distance then return false, 'Get closer to the vehicle.' end

    fee = math.max(0, math.min(Config.impound.maxFee, math.floor(tonumber(fee) or Config.impound.defaultFee)))
    reason = tostring(reason or ''):gsub('%c', ' '):sub(1, 120)
    if reason == '' then reason = nil end

    local what = G.impound(plate, veh, fee, reason)
    local text = ('%s impounded %s'):format(G.who(src), plate)
    if what == 'owned' then
        text = text .. (' for $%d'):format(fee) .. (reason and (': ' .. reason) or '')
        G.log(src, text, { plate = plate, fee = fee, reason = reason })
        G.panel(src, text)
        return true, ('Impounded %s.'):format(plate)
    end
    G.log(src, text, { plate = plate, kind = what })
    return true, 'Vehicle removed.'
end)
