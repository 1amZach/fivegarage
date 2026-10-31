-- Job vehicles: spawned from the config list, handed back, never owned.

local G = Garage

local function jobPlate(prefix)
    prefix = (prefix or ''):sub(1, 6)
    local digits = 8 - #prefix
    for _ = 1, 50 do
        local plate = prefix .. ('%0' .. digits .. 'd'):format(math.random(0, 10 ^ digits - 1))
        if not G.jobs[plate] and not G.out[plate] then return plate end
    end
end

local function allowed(src, g)
    local p = Framework.player(src)
    if not p or p.job ~= g.job then return nil, 'job' end
    if g.onDuty and not p.duty then return nil, 'duty' end
    return p
end

lib.callback.register('fivegarage:jobTake', function(src, id, index)
    local g = Config.jobGarages[id]
    local v = g and g.vehicles[tonumber(index)]
    if not v then return false end
    if not G.ready(src, 'garage') then return false, 'Slow down.' end

    local p, why = allowed(src, g)
    if why == 'duty' then return false, 'Go on duty first.' end
    if not p then return G.odd(src, ('tried to take a %s from %s without the job'):format(v.label, g.label)) end
    if p.grade < (v.grade or 0) then return G.odd(src, ('tried to take a %s from %s below grade %d'):format(v.label, g.label, v.grade)) end
    if not G.near(src, g) then return G.odd(src, ('tried to use %s from too far away'):format(g.label)) end

    local mine = 0
    for _, j in pairs(G.jobs) do
        if j.src == src and j.garage == id and DoesEntityExist(j.entity) then mine = mine + 1 end
    end
    if mine >= Config.jobLimit then return false, 'Return your current vehicle first.' end

    local spot = G.freeSpawn(g)
    if not spot then return false, 'Every spot is taken. Move a vehicle first.' end
    local plate = jobPlate(g.plate)
    if not plate then return false, 'No free plate.' end

    local ok, veh, netId = pcall(G.spawn, src, {
        model = v.model, plate = plate, coords = spot, props = { plate = plate }, fuel = 100,
        job = { livery = v.livery, extras = v.extras },
    })
    if not ok or not veh then return false, ok and netId or 'The vehicle failed to spawn.' end

    G.jobs[plate] = { entity = veh, src = src, garage = id, job = g.job }
    G.entities[veh] = plate
    TriggerEvent('fivegarage:spawned', src, plate, netId, id)
    G.log(src, ('%s took a %s (%s) from %s'):format(G.who(src), v.label, plate, g.label), { plate = plate, garage = id, model = v.model })
    return true
end)

lib.callback.register('fivegarage:jobReturn', function(src, id, netId)
    local g = Config.jobGarages[id]
    if not g then return false end
    if not G.ready(src, 'garage') then return false, 'Slow down.' end
    if not allowed(src, g) then return G.odd(src, ('tried to return a vehicle to %s without the job'):format(g.label)) end
    if not G.near(src, g) then return G.odd(src, ('tried to use %s from too far away'):format(g.label)) end

    local veh, plate = G.vehicleAt(netId)
    if not veh then return false, 'No vehicle to return.' end
    if G.dist(GetEntityCoords(veh), g.coords) > (g.radius or Config.radius) then return false, 'The vehicle is too far away.' end
    local j = G.jobs[plate]
    if not j or Config.jobGarages[j.garage].job ~= g.job then return false, "That isn't one of your job's vehicles." end

    DeleteEntity(veh)
    G.untrack(plate)
    TriggerEvent('fivegarage:stored', src, plate, id)
    G.log(src, ('%s returned %s to %s'):format(G.who(src), plate, g.label), { plate = plate, garage = id })
    return true
end)
