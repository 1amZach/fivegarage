local target = GetResourceState('ox_target') == 'started'
local busy = false

local function me() return LocalPlayer.state.fivegarage or {} end

local function access(place)
    local p = me()
    if place.job then return p.job == place.job and (p.grade or 0) >= (place.grade or 0) end
    if place.gang then return p.gang == place.gang and (p.gangGrade or 0) >= (place.grade or 0) end
    return true
end

local function notify(ok, msg)
    lib.notify({ description = msg or (ok and 'Done.' or 'Not allowed.'), type = ok and 'success' or 'error' })
end

-- One request at a time, whatever the player mashes.
local function once(fn)
    return function(...)
        if busy then return end
        busy = true
        local args = table.pack(...)
        CreateThread(function()
            local ok, err = pcall(fn, table.unpack(args, 1, args.n))
            busy = false
            if not ok then print(err) end
        end)
    end
end

local function nearbyVehicle()
    return cache.vehicle or lib.getClosestVehicle(GetEntityCoords(cache.ped), 6.0, false)
end

local function leave(veh)
    if GetVehiclePedIsIn(cache.ped, false) ~= veh then return end
    TaskLeaveVehicle(cache.ped, veh, 0)
    local stop = GetGameTimer() + 3000
    while IsPedInAnyVehicle(cache.ped, false) and GetGameTimer() < stop do Wait(100) end
end

local function fits(kind, model)
    return Config.types[kind][ModelType(model) or 'automobile'] == true
end

local function stats(v)
    return {
        { label = 'Fuel', value = v.fuel .. '%' },
        { label = 'Engine', value = v.engine .. '%' },
        { label = 'Body', value = v.body .. '%' },
    }
end

-- ------------------------------------------------------------------- garages

local park = once(function(id)
    local veh = nearbyVehicle()
    if not veh or not NetworkGetEntityIsNetworked(veh) then return notify(false, 'No vehicle to park.') end
    local props = lib.getVehicleProperties(veh)
    leave(veh)
    local ok, msg = lib.callback.await('fivegarage:store', false, id, NetworkGetNetworkIdFromEntity(veh), props)
    notify(ok, ok and 'Vehicle parked.' or msg)
end)

local take = once(function(id, plate)
    local ok, msg = lib.callback.await('fivegarage:take', false, id, plate)
    if not ok then notify(false, msg) end
end)

local function status(v)
    if v.state == 1 and v.here then return v.shared and 'Parked here (shared)' or 'Parked here', true end
    if v.state == 1 and v.fee then return ('At %s, $%d to bring here'):format(v.garage or 'another garage', v.fee), true end
    if v.state == 1 then return ('At %s'):format(v.garage or 'another garage') end
    if v.state == 0 then return v.out and 'Out' or 'At the depot' end
    return 'Impounded' .. (v.reason and (': ' .. v.reason) or '')
end

local openGarage = once(function(id, g)
    local list = lib.callback.await('fivegarage:list', false, id)
    if type(list) ~= 'table' then return notify(false) end

    local options = {
        { title = 'Park vehicle', icon = 'square-parking', disabled = not nearbyVehicle(), onSelect = function() park(id) end },
    }
    table.sort(list, function(a, b)
        if (a.here or false) ~= (b.here or false) then return a.here == true end
        return a.plate < b.plate
    end)
    for _, v in ipairs(list) do
        if fits(g.type, v.model) then
            local text, can = status(v)
            options[#options + 1] = {
                title = ('%s  %s'):format(VehicleLabel(v.model, v.name), v.plate),
                description = text,
                icon = g.type == 'boat' and 'ship' or g.type == 'air' and 'helicopter' or 'car',
                disabled = not can,
                metadata = stats(v),
                onSelect = function() take(id, v.plate) end,
            }
        end
    end
    if #options == 1 then options[2] = { title = 'Nothing parked here', disabled = true } end

    lib.registerContext({ id = 'fivegarage', title = g.label, options = options })
    lib.showContext('fivegarage')
end)

-- -------------------------------------------------------------------- depots

local recover = once(function(id, plate)
    local ok, msg = lib.callback.await('fivegarage:recover', false, id, plate)
    if not ok then notify(false, msg) end
end)

local openDepot = once(function(id, d)
    local list = lib.callback.await('fivegarage:depot', false, id)
    if type(list) ~= 'table' then return notify(false) end

    local options = {}
    for _, v in ipairs(list) do
        if not d.type or fits(d.type, v.model) then
            options[#options + 1] = {
                title = ('%s  %s'):format(VehicleLabel(v.model, v.name), v.plate),
                description = ('$%d%s'):format(v.fee, v.state == 2 and v.reason and (', impounded: ' .. v.reason) or ''),
                icon = 'car-burst',
                metadata = stats(v),
                onSelect = function() recover(id, v.plate) end,
            }
        end
    end
    if #options == 0 then options[1] = { title = 'Nothing to pick up', disabled = true } end

    lib.registerContext({ id = 'fivegarage', title = d.label, options = options })
    lib.showContext('fivegarage')
end)

-- ---------------------------------------------------------------------- jobs

local jobReturn = once(function(id)
    local veh = nearbyVehicle()
    if not veh or not NetworkGetEntityIsNetworked(veh) then return notify(false, 'No vehicle to return.') end
    leave(veh)
    local ok, msg = lib.callback.await('fivegarage:jobReturn', false, id, NetworkGetNetworkIdFromEntity(veh))
    notify(ok, ok and 'Vehicle returned.' or msg)
end)

local jobTake = once(function(id, i)
    local ok, msg = lib.callback.await('fivegarage:jobTake', false, id, i)
    if not ok then notify(false, msg) end
end)

local function openJob(id, g)
    local grade = me().grade or 0
    local options = {
        { title = 'Return vehicle', icon = 'rotate-left', disabled = not nearbyVehicle(), onSelect = function() jobReturn(id) end },
    }
    for i, v in ipairs(g.vehicles) do
        if grade >= (v.grade or 0) then
            options[#options + 1] = { title = v.label, icon = 'car', onSelect = function() jobTake(id, i) end }
        end
    end
    lib.registerContext({ id = 'fivegarage', title = g.label, options = options })
    lib.showContext('fivegarage')
end

-- ------------------------------------------------------------- places, blips

local shown

local function prompt(text)
    if text == shown then return end
    shown = text
    if text then lib.showTextUI(text) else lib.hideTextUI() end
end

-- opens: on foot. quick: in a vehicle, if the place has one.
local function place(p, label, usable, open, quick)
    lib.points.new({
        coords = p.coords,
        distance = 30,
        onExit = function() prompt(nil) end,
        nearby = function(self)
            if not usable() then return prompt(nil) end
            DrawMarker(36, p.coords.x, p.coords.y, p.coords.z, 0, 0, 0, 0, 0, 0, 1.0, 1.0, 1.0, 255, 255, 255, 140, false, true, 2, false, nil, nil, false)
            if self.currentDistance > Config.markerRadius then return prompt(nil) end

            local fn, text
            if cache.vehicle and quick then
                fn, text = quick[2], '[E] ' .. quick[1]
            elseif not cache.vehicle and not target then
                fn, text = open, '[E] ' .. label
            end
            prompt(text)
            if fn and IsControlJustReleased(0, 38) then
                prompt(nil)
                fn()
            end
        end,
    })

    if target then
        exports.ox_target:addSphereZone({
            coords = p.coords,
            radius = 1.5,
            options = { { label = label, icon = 'fa-solid fa-warehouse', distance = 2.5, canInteract = usable, onSelect = open } },
        })
    end
end

local function blip(p, style)
    local b = AddBlipForCoord(p.coords.x, p.coords.y, p.coords.z)
    SetBlipSprite(b, style.sprite)
    SetBlipColour(b, style.color)
    SetBlipScale(b, style.scale)
    SetBlipAsShortRange(b, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(p.label)
    EndTextCommandSetBlipName(b)
end

for id, g in pairs(Config.garages) do
    place(g, 'Open garage', function() return access(g) end,
        function() openGarage(id, g) end,
        { 'Park vehicle', function() park(id) end })
    if g.blip ~= false and (g.blip or not (g.job or g.gang)) then blip(g, Config.blips[g.type]) end
end

for id, d in pairs(Config.depots) do
    place(d, 'Open depot', function() return true end, function() openDepot(id, d) end)
    if d.blip ~= false then blip(d, Config.blips.depot) end
end

for id, g in pairs(Config.jobGarages) do
    local function usable()
        local p = me()
        return p.job == g.job and (not g.onDuty or p.duty)
    end
    place(g, 'Job garage', usable, function() openJob(id, g) end, { 'Return vehicle', function() jobReturn(id) end })
    if g.blip then blip(g, Config.blips.car) end
end
