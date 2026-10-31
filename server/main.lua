local G = Garage

local function reply(src, text, kind)
    if src == 0 then return print(text) end
    TriggerClientEvent('ox_lib:notify', src, { description = text, type = kind or 'inform' })
end

local function staff(src) return src == 0 or IsPlayerAceAllowed(src, Config.adminAce) end

-- /returncar AB12CD34   /impoundcar AB12CD34 500
RegisterCommand('returncar', function(src, args)
    if not staff(src) then return reply(src, 'Not allowed.', 'error') end
    local plate = DB.trim(table.concat(args, ' '))
    if not plate or plate == '' then return reply(src, 'Usage: /returncar <plate>') end

    CreateThread(function()
        local r = DB.byPlate(plate)
        if not r then return reply(src, ('No owned vehicle with plate %s.'):format(plate), 'error') end
        local veh = G.isOut(r.plate)
        if veh then DeleteEntity(veh) end
        G.untrack(r.plate)
        DB.setState(r.plate, 1, nil, 0, nil)

        local text = ('%s returned %s to its garage'):format(G.who(src), r.plate)
        G.log(src, text, { plate = r.plate, staff = true })
        G.panel(src, text)
        reply(src, ('%s is back in its garage.'):format(r.plate), 'success')
    end)
end, false)

RegisterCommand('impoundcar', function(src, args)
    if not staff(src) then return reply(src, 'Not allowed.', 'error') end
    local fee = #args > 1 and tonumber(args[#args])
    if fee then table.remove(args) end
    local plate = DB.trim(table.concat(args, ' '))
    if not plate or plate == '' then return reply(src, 'Usage: /impoundcar <plate> [fee]') end
    fee = math.max(0, math.floor(fee or 0))

    CreateThread(function()
        if not DB.byPlate(plate) then return reply(src, ('No owned vehicle with plate %s.'):format(plate), 'error') end
        G.impound(plate, G.isOut(plate), fee, 'Staff')

        local text = ('%s impounded %s for $%d'):format(G.who(src), plate, fee)
        G.log(src, text, { plate = plate, fee = fee, staff = true })
        G.panel(src, text)
        reply(src, ('%s is at the depot.'):format(plate), 'success')
    end)
end, false)

-- ------------------------------------------------------------------- exports

exports('getVehicles', function(identifier)
    return identifier and DB.owned(identifier) or {}
end)

-- state: 0 out, 1 in a garage, 2 impounded. A car that's out is deleted when
-- it's put anywhere else.
exports('setState', function(plate, state, garage)
    plate, state = DB.trim(plate), tonumber(state)
    if not plate or (state ~= 0 and state ~= 1 and state ~= 2) then return false end
    if state ~= 0 then
        local veh = G.isOut(plate)
        if veh then DeleteEntity(veh) end
        G.untrack(plate)
    end
    return DB.setState(plate, state, garage, 0, nil)
end)

exports('isOut', function(plate)
    plate = DB.trim(plate)
    return plate ~= nil and G.isOut(plate) ~= nil
end)

-- Spawns an owned car for a player, at `coords` (vec4) or where they stand.
-- Returns the net id, or nil and why.
exports('spawn', function(src, plate, coords)
    src = tonumber(src)
    local r = src and DB.byPlate(plate)
    if not r then return nil, 'Unknown plate.' end
    if G.isOut(r.plate) then return nil, 'That vehicle is already out.' end
    if not coords then
        local pos, ped = G.pos(src)
        if not pos then return nil, 'Player not found.' end
        coords = vec4(pos.x, pos.y, pos.z, GetEntityHeading(ped))
    end
    local veh, netId = G.takeOut(src, r, coords, nil)
    if not veh then return nil, netId end
    return netId
end)

-- ------------------------------------------------------------------ start up

CreateThread(function()
    MySQL.query.await(DB.schema)
    for _, id in ipairs(GetPlayers()) do Framework.sync(tonumber(id)) end
    if not Config.depotOnStart then return end

    local world, lost = G.world(), {}
    for _, plate in ipairs(DB.outPlates()) do
        if world[plate] then G.track(plate, world[plate]) else lost[#lost + 1] = plate end
    end
    if #lost > 0 then
        DB.toDepot(lost)
        print(('[fivegarage] %d vehicle%s moved to the depot'):format(#lost, #lost == 1 and '' or 's'))
    end
end)
