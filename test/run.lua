-- lua5.4 test/run.lua
-- Runs the server side of fivegarage against a fake FiveM server and database.

local passed, failed = 0, 0
local function check(name, cond)
    if cond then passed = passed + 1 else failed = failed + 1; io.write('FAIL ' .. name .. '\n') end
end

-- Events, timers ----------------------------------------------------------------

local handlers, triggered, toClient = {}, {}, {}
function AddEventHandler(name, fn) handlers[name] = handlers[name] or {}; table.insert(handlers[name], fn) end
function RegisterNetEvent(name, fn) if fn then AddEventHandler(name, fn) end end
local function fire(name, src, ...)
    source = src
    for _, fn in ipairs(handlers[name] or {}) do fn(...) end
end
function TriggerEvent(name, ...)
    triggered[#triggered + 1] = { name = name, args = { ... } }
    fire(name, nil, ...)
end
function TriggerClientEvent(name, target, ...) toClient[#toClient + 1] = { name = name, target = target, args = { ... } } end
local function events(name)
    local out = {}
    for _, t in ipairs(triggered) do if t.name == name then out[#out + 1] = t.args end end
    return out
end

local clock = 0
function GetGameTimer() return clock end
local function tick() clock = clock + 5000 end
function CreateThread(fn) fn() end
function Wait() end
function SetTimeout(_, fn) fn() end

local printed = {}
function print(...) printed[#printed + 1] = table.concat({ ... }, ' ') end

local stored, n = {}, 0
json = {
    encode = function(t) n = n + 1; local k = 'json#' .. n; stored[k] = t; return k end,
    decode = function(s) return assert(stored[s], 'bad json') end,
}

local vmeta = { __sub = function(a, b) return { x = a.x - b.x, y = a.y - b.y, z = a.z - b.z } end }
function vec3(x, y, z) return setmetatable({ x = x, y = y, z = z }, vmeta) end
function vec4(x, y, z, w) return setmetatable({ x = x, y = y, z = z, w = w }, vmeta) end

function GetHashKey(s)
    local h = 0
    for c in s:lower():gmatch('.') do
        h = (h + c:byte()) & 0xFFFFFFFF
        h = (h + (h << 10)) & 0xFFFFFFFF
        h = h ~ (h >> 6)
    end
    h = (h + (h << 3)) & 0xFFFFFFFF
    h = h ~ (h >> 11)
    h = (h + (h << 15)) & 0xFFFFFFFF
    return h >= 0x80000000 and h - 0x100000000 or h
end

-- Players, entities ---------------------------------------------------------------

local players, entities, bags, nextEntity = {}, {}, {}, 100
local started = { fivegarage = 'started', oxmysql = 'started', ox_lib = 'started', qbx_core = 'started' }
local aces = {}

local function addPlayer(src, name, pos)
    players[src] = { name = name, pos = pos }
end
local function moveTo(src, pos) players[src].pos = pos end

local function bag(key)
    bags[key] = bags[key] or setmetatable({}, { __index = { set = function(self, k, v) rawset(self, k, v) end } })
    return bags[key]
end
function Entity(e) return { state = bag('e' .. e) } end
function Player(src) return { state = bag('p' .. src) } end

function GetPlayerName(src) local p = players[tonumber(src)]; return p and p.name end
function GetPlayers() local out = {}; for src in pairs(players) do out[#out + 1] = tostring(src) end; return out end
function GetPlayerPed(src) return players[tonumber(src)] and tonumber(src) + 1000 or 0 end
function GetEntityCoords(e) local p = players[e - 1000]; if p then return p.pos end; return entities[e].pos end
function GetEntityHeading() return 90.0 end
function IsPlayerAceAllowed(src, ace) return aces[src .. ace] == true end
function GetPlayerRoutingBucket() return 0 end
function SetEntityRoutingBucket(e, b) entities[e].bucket = b end
local warped = {}
function SetPedIntoVehicle(ped, veh, seat) warped[#warped + 1] = { ped = ped, veh = veh, seat = seat } end

local function addVehicle(plate, model, pos, extra)
    nextEntity = nextEntity + 1
    local e = { plate = ('%-8s'):format(plate), model = GetHashKey(model), pos = pos, vtype = 'automobile', engine = 900.0, body = 800.0 }
    for k, v in pairs(extra or {}) do e[k] = v end
    entities[nextEntity] = e
    return nextEntity
end

local spawned = {}
function CreateVehicleServerSetter(hash, vtype, x, y, z, h)
    nextEntity = nextEntity + 1
    entities[nextEntity] = { plate = '', model = hash, pos = vec3(x, y, z), vtype = vtype, engine = 1000.0, body = 1000.0 }
    spawned[#spawned + 1] = { entity = nextEntity, hash = hash, vtype = vtype, h = h }
    return nextEntity
end
function DoesEntityExist(e) return entities[e] ~= nil end
function DeleteEntity(e) entities[e] = nil; fire('entityRemoved', nil, e) end
function GetAllVehicles() local out = {}; for e in pairs(entities) do out[#out + 1] = e end; table.sort(out); return out end
function GetEntityType(e) return entities[e] and 2 or 0 end
function GetVehicleType(e) return entities[e].vtype end
function GetEntityModel(e) return entities[e].model end
function GetVehicleNumberPlateText(e) return entities[e].plate end
function SetVehicleNumberPlateText(e, p) entities[e].plate = ('%-8s'):format(p) end
function GetVehicleEngineHealth(e) return entities[e].engine end
function GetVehicleBodyHealth(e) return entities[e].body end
function NetworkGetNetworkIdFromEntity(e) return e + 5000 end
function NetworkGetEntityFromNetworkId(id) return entities[id - 5000] and id - 5000 or 0 end
function GetResourceState(name) return started[name] or 'missing' end
function GetCurrentResourceName() return 'fivegarage' end

local commands = {}
function RegisterCommand(name, fn) commands[name] = fn end

-- ox_lib --------------------------------------------------------------------------

local callbacks, modelTypes = {}, {}
lib = { callback = {
    register = function(name, fn) callbacks[name] = fn end,
    await = function(name, _, hash) assert(name == 'fivegarage:modelType'); return modelTypes[hash] or 'automobile' end,
} }
local function call(name, src, ...) return callbacks[name](src, ...) end

-- Frameworks ----------------------------------------------------------------------

local qbPlayers, esxPlayers = {}, {}

local function qbPlayer(src, citizenid, job, grade, gang, bank)
    local d = {
        source = src, citizenid = citizenid, license = 'license:' .. citizenid,
        charinfo = { firstname = players[src].name, lastname = 'Test' },
        job = { name = job or 'unemployed', grade = { level = grade or 0 }, onduty = true },
        gang = { name = gang or 'none', grade = { level = 0 } },
        money = { bank = bank or 10000, cash = 0 },
    }
    qbPlayers[src] = {
        PlayerData = d,
        Functions = {
            RemoveMoney = function(acc, amount) d.money[acc] = d.money[acc] - amount; return true end,
            AddMoney = function(acc, amount) d.money[acc] = d.money[acc] + amount; return true end,
        },
    }
    return d
end

local function esxPlayer(src, identifier, job, grade, money)
    local accounts = { bank = { money = money or 10000 }, money = { money = 0 } }
    esxPlayers[src] = {
        identifier = identifier, accounts = accounts,
        getJob = function() return { name = job or 'unemployed', grade = grade or 0 } end,
        getName = function() return players[src].name .. ' Test' end,
        getAccount = function(name) return accounts[name] end,
        removeAccountMoney = function(name, amount) accounts[name].money = accounts[name].money - amount end,
        addAccountMoney = function(name, amount) accounts[name].money = accounts[name].money + amount end,
    }
    return esxPlayers[src]
end

local registered, calls, qbxTypes = {}, {}, {}
local function record(res) return function(_, ...) calls[#calls + 1] = { res = res, args = { ... } } end end
local function callsTo(res)
    local out = {}
    for _, c in ipairs(calls) do if c.res == res then out[#out + 1] = c.args end end
    return out
end

exports = setmetatable({}, {
    __call = function(_, name, fn) registered[name] = fn end,
    __index = function(_, res)
        if res == 'qbx_core' then
            return {
                GetPlayer = function(_, src) return qbPlayers[src] end,
                GetVehiclesByHash = function(_, hash) return qbxTypes[hash] and { type = qbxTypes[hash] } or { adder = {} } end,
            }
        end
        if res == 'es_extended' then return { getSharedObject = function() return { GetPlayerFromId = function(src) return esxPlayers[src] end } end } end
        if res == 'fivelog' then return { add = record('fivelog') } end
        if res == 'warden' then return { allow = record('warden') } end
        if res == 'qbx_vehiclekeys' then return { GiveKeys = record('keys') } end
    end,
})

-- Database ------------------------------------------------------------------------

local pv, ov, fg = {}, {}, {}
local queries = {}

local function copy(t) local c = {}; for k, v in pairs(t) do c[k] = v end; return c end
local function sorted(list) table.sort(list, function(a, b) return a.plate < b.plate end); return list end

local function joined(r, owner)
    local c, f = copy(r), fg[r.plate] or {}
    c.owner, c.citizenid = c[owner], nil
    c.reason = f.reason
    return c, f
end

local function selectQb(where, p)
    local out = {}
    for _, r in pairs(pv) do
        local hit = where == ' WHERE v.citizenid = ?' and r.citizenid == p[1]
            or where == ' WHERE v.plate = ?' and r.plate == p[1]
            or where == ' WHERE v.garage = ? AND v.state = 1' and r.garage == p[1] and r.state == 1
        if hit then out[#out + 1] = joined(r, 'citizenid') end
    end
    return sorted(out)
end

local function selectEsx(where, p)
    local out = {}
    for _, r in pairs(ov) do
        local f = fg[r.plate] or {}
        local hit = where == ' WHERE v.owner = ?' and r.owner == p[1]
            or where == ' WHERE v.plate = ?' and r.plate == p[1]
            or where == ' WHERE f.garage = ? AND f.state = 1' and f.garage == p[1] and f.state == 1
        if hit then
            local c = joined(r, 'owner')
            c.garage, c.state, c.fee, c.fuel, c.engine, c.body = f.garage, f.state, f.fee, f.fuel, f.engine, f.body
            out[#out + 1] = c
        end
    end
    return sorted(out)
end

local function run(sql, p)
    p = p or {}
    queries[#queries + 1] = { sql = sql, params = p }
    local S = DB.sql
    if sql == DB.schema then return {} end
    if sql:sub(1, #S.qb.select) == S.qb.select then return selectQb(sql:sub(#S.qb.select + 1), p) end
    if sql:sub(1, #S.esx.select) == S.esx.select then return selectEsx(sql:sub(#S.esx.select + 1), p) end

    if sql == S.qb.store then
        local r = pv[p[6]]
        if not r then return 0 end
        r.state, r.garage, r.mods, r.fuel, r.engine, r.body, r.depotprice = 1, p[1], p[2], p[3], p[4], p[5], 0
        return 1
    end
    if sql == S.qb.state then
        local r = pv[p[4]]
        if not r then return 0 end
        r.state, r.depotprice = p[1], p[3]
        if p[2] ~= nil then r.garage = p[2] end
        return 1
    end
    if sql == S.qb.out then
        local out = {}
        for _, r in pairs(pv) do if r.state == 0 then out[#out + 1] = { plate = r.plate } end end
        return sorted(out)
    end
    if sql:find('^UPDATE player_vehicles SET state = 2 WHERE state = 0 AND plate IN') then
        local count = 0
        for _, plate in ipairs(p) do if pv[plate] and pv[plate].state == 0 then pv[plate].state = 2; count = count + 1 end end
        return count
    end

    if sql == S.esx.store then
        local r = ov[p[2]]
        if not r then return 0 end
        r.stored, r.vehicle = 1, p[1]
        return 1
    end
    if sql == S.esx.state then
        local r = ov[p[2]]
        if not r then return 0 end
        r.stored = p[1]
        return 1
    end
    if sql == S.esx.out then
        local out = {}
        for _, r in pairs(ov) do
            if r.stored == 0 and ((fg[r.plate] or {}).state or 0) == 0 then out[#out + 1] = { plate = r.plate } end
        end
        return sorted(out)
    end
    if sql:find('^INSERT INTO fivegarage %(plate, state%) VALUES') then
        for _, plate in ipairs(p) do fg[plate] = fg[plate] or {}; fg[plate].state = 2 end
        return #p
    end

    if sql == S.upsert then
        local f = fg[p[1]] or {}
        if p[2] ~= nil then f.garage = p[2] end
        f.state, f.fee, f.reason = p[3], p[4], p[5]
        f.fuel, f.engine, f.body = p[6] or f.fuel, p[7] or f.engine, p[8] or f.body
        fg[p[1]] = f
        return 1
    end
    error('unhandled sql: ' .. sql)
end

MySQL = {
    query = { await = function(sql, p) return run(sql, p) end },
    single = { await = function(sql, p) return run(sql, p)[1] end },
    update = { await = function(sql, p) return run(sql, p) end },
}

local function queried(pattern)
    for _, q in ipairs(queries) do if q.sql:find(pattern) then return true end end
    return false
end

-- Setup ---------------------------------------------------------------------------

local legion = vec3(215.9, -809.7, 30.7)
local pinkcage = vec3(273.4, -344.0, 44.9)
local davis = vec3(409.3, -1623.0, 29.3)
local mrpd = vec3(448.2, -1017.4, 28.6)
local far = vec3(2000, 2000, 30)

local function qbCar(plate, owner, state, garage, extra)
    local props = { model = GetHashKey('sultan'), plate = plate, modEngine = -1, color1 = 1 }
    pv[plate] = {
        citizenid = owner, license = 'license:' .. owner, plate = plate, vehicle = 'sultan', hash = tostring(GetHashKey('sultan')),
        mods = json.encode(props), garage = garage, state = state, fuel = 80, engine = 950.0, body = 900.0, depotprice = 0,
    }
    for k, v in pairs(extra or {}) do pv[plate][k] = v end
    return pv[plate]
end

addPlayer(1, 'Bob', legion)
addPlayer(2, 'Al', legion)
addPlayer(3, 'Cop', mrpd)
qbPlayer(1, 'C1')
qbPlayer(2, 'C2')
qbPlayer(3, 'C3', 'police', 0)

qbCar('LOST1', 'C1', 0, 'legion')
qbCar('STILL1', 'C1', 0, 'legion')
qbCar('HOME1', 'C1', 1, 'legion')
qbCar('PINK1', 'C1', 1, 'pinkcage')
qbCar('OTHER1', 'C2', 1, 'legion')
local still = addVehicle('STILL1', 'sultan', vec3(0, 0, 0))

started.fivelog, started.warden, started.fivepanel, started.qbx_vehiclekeys = 'started', 'started', 'started', 'started'

for _, f in ipairs({ 'config.lua', 'server/framework.lua', 'server/db.lua', 'server/vehicles.lua', 'server/garages.lua', 'server/jobs.lua', 'server/main.lua' }) do
    dofile(f)
end

local G = Garage

-- Tests ---------------------------------------------------------------------------

do -- start up
    check('framework detected', Framework.name() == 'qbx')
    check('schema created', queries[1].sql == DB.schema)
    check('lost car sent to the depot', pv.LOST1.state == 2)
    check('car still in the world left out', pv.STILL1.state == 0 and G.out.STILL1 and G.out.STILL1.entity == still)
    check('parked cars untouched', pv.HOME1.state == 1)
    check('player state synced', bag('p1').fivegarage and bag('p1').fivegarage.job == 'unemployed')
    check('depot count printed', printed[#printed]:find('1 vehicle moved to the depot') ~= nil)
end

do -- the garage list
    local list = call('fivegarage:list', 1, 'legion')
    local by = {}
    for _, v in ipairs(list) do by[v.plate] = v end
    check('own cars listed', by.HOME1 and by.PINK1 and by.LOST1 and not by.OTHER1)
    check('stats as percent', by.HOME1.fuel == 80 and by.HOME1.engine == 95 and by.HOME1.body == 90)
    check('here and elsewhere', by.HOME1.here == true and by.PINK1.here == false and by.PINK1.fee == 250 and by.PINK1.garage == 'Pink Cage Motel')
    check('out car marked out', by.STILL1.out == true)
    moveTo(1, far)
    check('no list from far away', call('fivegarage:list', 1, 'legion') == nil)
    moveTo(1, legion)
end

do -- taking a car out
    local before = #spawned
    local ok = call('fivegarage:take', 1, 'legion', 'HOME1')
    local s = spawned[#spawned]
    check('take works', ok == true and #spawned == before + 1)
    check('spawned server side with type', s.vtype == 'automobile' and s.hash == GetHashKey('sultan') & 0xFFFFFFFF)
    check('plate set server side', entities[s.entity].plate == 'HOME1   ')
    check('state out', pv.HOME1.state == 0)
    check('tracked', G.out.HOME1.entity == s.entity and exports and registered.isOut('HOME1') == true)
    local b = bag('e' .. s.entity)
    check('props for the owner client', b.fivegarage.owner == 1 and b.fivegarage.props.color1 == 1 and b.fivegarage.props.plate == 'HOME1')
    check('ox_fuel state set', b.fuel == 80)
    check('warped in', warped[#warped].veh == s.entity and warped[#warped].ped == 1001)
    check('keys given', callsTo('keys')[1] and callsTo('keys')[1][1] == 1 and callsTo('keys')[1][2] == s.entity)
    local w = callsTo('warden')
    check('warden told, never for everything', #w == 3 and w[1][2] ~= 'all' and w[1][3] == 5)
    local logs = callsTo('fivelog')
    check('fivelog take', logs[#logs][1] == 'vehicles' and logs[#logs][3] == 'Bob Test took HOME1 out of Legion Square')
    check('spawned event', #events('fivegarage:spawned') == 1 and events('fivegarage:spawned')[1][2] == 'HOME1')
end

do -- no duplicates
    tick()
    pv.HOME1.state = 1 -- say the database got out of step
    local before = #spawned
    local ok, msg = call('fivegarage:take', 1, 'legion', 'HOME1')
    check('duplicate refused while it exists', ok == false and msg == 'That vehicle is already out.' and #spawned == before)
    pv.HOME1.state = 0

    tick()
    ok, msg = call('fivegarage:take', 1, 'legion', 'STILL1')
    check('car out from before the restart refused', ok == false and msg == 'That vehicle is already out.')
end

do -- rate limit
    tick()
    call('fivegarage:take', 1, 'legion', 'NOPE')
    local ok, msg = call('fivegarage:take', 1, 'legion', 'HOME1')
    check('rate limited', ok == false and msg == 'Slow down.')
end

do -- parking
    tick()
    local veh = G.out.HOME1.entity
    entities[veh].pos = vec3(220, -800, 30)
    entities[veh].engine = 700.0
    bag('e' .. veh).fuel = 42
    local ok = call('fivegarage:store', 1, 'legion', veh + 5000, { model = 1, plate = 'FAKE', modEngine = 3, color1 = 5 })
    check('store works', ok == true)
    check('state in', pv.HOME1.state == 1 and pv.HOME1.garage == 'legion')
    local props = json.decode(pv.HOME1.mods)
    check('props saved, plate and model from the server', props.color1 == 5 and props.plate == 'HOME1' and props.model == GetHashKey('sultan'))
    check('performance mods kept from the database', props.modEngine == -1)
    check('fuel and health from the server', pv.HOME1.fuel == 42 and pv.HOME1.engine == 700.0)
    check('vehicle deleted and untracked', entities[veh] == nil and G.out.HOME1 == nil and registered.isOut('HOME1') == false)
    check('stored event', events('fivegarage:stored')[1][2] == 'HOME1' and events('fivegarage:stored')[1][3] == 'legion')
end

do -- someone else's car
    tick()
    local before = #spawned
    local ok, msg = call('fivegarage:take', 2, 'legion', 'PINK1')
    check('ownership refused on take', ok == false and msg == 'Not allowed.' and #spawned == before)
    local logs = callsTo('fivelog')
    check('refusal logged', logs[#logs][3]:find('^Refused: tried to take PINK1') ~= nil)

    tick()
    local veh = addVehicle('HOME1', 'sultan', vec3(216, -805, 30))
    ok = call('fivegarage:store', 2, 'legion', veh + 5000, {})
    check('ownership refused on store', ok == false and pv.HOME1.state == 1 and entities[veh] ~= nil)
    DeleteEntity(veh)

    tick()
    veh = addVehicle('HOME1', 'adder', vec3(216, -805, 30))
    pv.HOME1.state = 0
    ok = call('fivegarage:store', 1, 'legion', veh + 5000, {})
    check('different model under my plate refused', ok == false and entities[veh] ~= nil and pv.HOME1.state == 0)
    DeleteEntity(veh)
    pv.HOME1.state = 1
end

do -- distance
    tick()
    moveTo(1, far)
    local before = #spawned
    local ok = call('fivegarage:take', 1, 'legion', 'HOME1')
    check('take refused far from the garage', ok == false and #spawned == before and pv.HOME1.state == 1)
    moveTo(1, legion)
end

do -- transfers
    tick()
    local ok = call('fivegarage:take', 1, 'legion', 'PINK1')
    check('transfer charged', ok == true and qbPlayers[1].PlayerData.money.bank == 10000 - 250)
    DeleteEntity(G.out.PINK1.entity)
    check('entityRemoved untracks', G.out.PINK1 == nil)
    pv.PINK1.state = 1

    tick()
    Config.transferFee = false
    local msg
    ok, msg = call('fivegarage:take', 1, 'legion', 'PINK1')
    check('transfer off', ok == false and msg == 'That vehicle is parked at Pink Cage Motel.')
    Config.transferFee = 250

    tick()
    qbPlayers[1].PlayerData.money.bank = 100
    ok, msg = call('fivegarage:take', 1, 'legion', 'PINK1')
    check("can't afford", ok == false and msg:find('afford') and pv.PINK1.state == 1 and qbPlayers[1].PlayerData.money.bank == 100)
    qbPlayers[1].PlayerData.money.bank = 10000
end

do -- type checks
    tick()
    modelTypes[GetHashKey('sultan') & 0xFFFFFFFF] = 'boat'
    local ok, msg = call('fivegarage:take', 1, 'legion', 'HOME1')
    check('boat not out of a car garage', ok == false and msg:find("can't come out") and pv.HOME1.state == 1)
    modelTypes = {}

    tick()
    qbxTypes[GetHashKey('sultan') & 0xFFFFFFFF] = 'automobile'
    ok = call('fivegarage:take', 1, 'legion', 'HOME1')
    check('type from qbx_core', ok == true)
    registered.setState('HOME1', 1, 'legion')
    check('setState export deletes the car', pv.HOME1.state == 1 and next(G.out) == 'STILL1' and next(G.out, 'STILL1') == nil)
end

do -- depot
    tick()
    moveTo(1, davis)
    local list = call('fivegarage:depot', 1, 'davis')
    local by = {}
    for _, v in ipairs(list) do by[v.plate] = v end
    check('lost car at the depot with config fee', by.LOST1 and by.LOST1.fee == 500)
    check('car still out not at the depot', by.STILL1 == nil and by.HOME1 == nil)

    local bank = qbPlayers[1].PlayerData.money.bank
    local ok = call('fivegarage:recover', 1, 'davis', 'LOST1')
    check('depot recovery', ok == true and pv.LOST1.state == 0 and qbPlayers[1].PlayerData.money.bank == bank - 500)
    local logs = callsTo('fivelog')
    check('depot logged', logs[#logs][3] == 'Bob Test got LOST1 back from Davis Impound for $500')

    tick()
    local msg
    ok, msg = call('fivegarage:recover', 1, 'davis', 'LOST1')
    check('no recovery while still out', ok == false and msg == 'That vehicle is still out.')

    DeleteEntity(G.out.LOST1.entity)
    tick()
    ok = call('fivegarage:recover', 1, 'davis', 'LOST1')
    check('destroyed car recoverable again', ok == true)

    tick()
    pv.PINK1.state, pv.PINK1.depotprice = 2, 1200
    bank = qbPlayers[1].PlayerData.money.bank
    ok = call('fivegarage:recover', 1, 'davis', 'PINK1')
    check('impound fee charged', ok == true and qbPlayers[1].PlayerData.money.bank == bank - 1200)

    tick()
    moveTo(2, davis)
    pv.OTHER1.state = 2
    ok = call('fivegarage:recover', 2, 'davis', 'HOME1')
    check("can't recover someone else's", ok == false)
    tick()
    moveTo(1, far)
    ok = call('fivegarage:recover', 1, 'davis', 'OTHER1')
    check('depot distance', ok == false)
    moveTo(1, legion)
    moveTo(2, legion)
end

do -- job garages
    tick()
    local ok = call('fivegarage:jobTake', 3, 'mrpd', 1)
    local s = spawned[#spawned]
    local plate = DB.trim(entities[s.entity].plate)
    check('job vehicle', ok == true and s.hash == GetHashKey('police') & 0xFFFFFFFF)
    check('job plate prefix', plate:find('^LSPD%d%d%d%d$') ~= nil and G.jobs[plate].src == 3)
    check('livery and extras sent', bag('e' .. s.entity).fivegarage.livery == 0 and bag('e' .. s.entity).fivegarage.extras[1] == true)

    tick()
    local msg
    ok, msg = call('fivegarage:jobTake', 3, 'mrpd', 1)
    check('job limit', ok == false and msg == 'Return your current vehicle first.')

    tick()
    ok = call('fivegarage:jobTake', 3, 'mrpd', 3)
    check('grade too low', ok == false and callsTo('fivelog')[#callsTo('fivelog')][3]:find('below grade 2') ~= nil)

    tick()
    moveTo(2, mrpd)
    ok = call('fivegarage:jobTake', 2, 'mrpd', 1)
    check('wrong job refused', ok == false)

    tick()
    qbPlayers[3].PlayerData.job.onduty = false
    ok, msg = call('fivegarage:jobTake', 3, 'mrpd', 2)
    check('off duty', ok == false and msg == 'Go on duty first.')
    qbPlayers[3].PlayerData.job.onduty = true

    tick()
    moveTo(3, legion)
    entities[s.entity].pos = vec3(216, -805, 30)
    ok, msg = call('fivegarage:store', 3, 'legion', s.entity + 5000, {})
    check('job car not parked in a public garage', ok == false and msg:find('job garage'))

    tick()
    moveTo(3, mrpd)
    entities[s.entity].pos = vec3(446, -1025, 28)
    ok = call('fivegarage:jobReturn', 3, 'mrpd', s.entity + 5000)
    check('job vehicle returned', ok == true and entities[s.entity] == nil and G.jobs[plate] == nil)

    tick()
    qbPlayers[3].PlayerData.job.grade.level = 2
    ok = call('fivegarage:jobTake', 3, 'mrpd', 3)
    check('higher grade can take it', ok == true)
    moveTo(2, legion)
end

do -- police impound
    tick()
    local veh = addVehicle('OTHER1', 'sultan', vec3(450, -1015, 28))
    pv.OTHER1.state = 0
    local ok, msg = call('fivegarage:impound', 3, veh + 5000, 999999, 'Parked\non the sidewalk')
    check('impounded', ok == true and msg == 'Impounded OTHER1.' and entities[veh] == nil)
    check('impound state, fee capped, reason cleaned', pv.OTHER1.state == 2 and pv.OTHER1.depotprice == 10000 and fg.OTHER1.reason == 'Parked on the sidewalk')
    local act = events('fivepanel:activity')
    check('fivepanel told', act[#act][1] == 'Cop (in game)' and act[#act][2]:find('impounded OTHER1 for %$10000') ~= nil)

    tick()
    local npc = addVehicle('NPC123', 'adder', vec3(450, -1015, 28))
    ok, msg = call('fivegarage:impound', 3, npc + 5000)
    check('unowned car just removed', ok == true and msg == 'Vehicle removed.' and entities[npc] == nil)

    tick()
    veh = addVehicle('HOME1', 'sultan', vec3(216, -805, 30))
    ok = call('fivegarage:impound', 1, veh + 5000, 0, 'x')
    check('not police refused', ok == false and entities[veh] ~= nil)
    DeleteEntity(veh)

    tick()
    veh = addVehicle('HOME1', 'sultan', vec3(500, -1015, 28))
    ok, msg = call('fivegarage:impound', 3, veh + 5000, 0)
    check('impound distance', ok == false and msg == 'Get closer to the vehicle.')
    DeleteEntity(veh)
end

do -- staff commands
    local veh = addVehicle('OTHER1', 'sultan', vec3(0, 0, 10))
    pv.OTHER1.state = 0
    commands.returncar(0, { 'OTHER1' })
    check('returncar from the console', pv.OTHER1.state == 1 and pv.OTHER1.depotprice == 0 and entities[veh] == nil)
    check('console reply', printed[#printed] == 'OTHER1 is back in its garage.')
    local act = events('fivepanel:activity')
    check('fivepanel staff action', act[#act][1] == 'Console' and act[#act][2] == 'Console returned OTHER1 to its garage')

    commands.impoundcar(2, { 'OTHER1', '300' })
    check('impoundcar needs the ace', pv.OTHER1.state == 1 and toClient[#toClient].args[1].description == 'Not allowed.')
    aces['2fivegarage.admin'] = true
    commands.impoundcar(2, { 'OTHER1', '300' })
    check('impoundcar with the ace', pv.OTHER1.state == 2 and pv.OTHER1.depotprice == 300 and fg.OTHER1.reason == 'Staff')
    check('fivepanel names the player', events('fivepanel:activity')[#events('fivepanel:activity')][1] == 'Al (in game)')
    commands.returncar(0, { 'NOPE' })
    check('unknown plate', printed[#printed]:find('No owned vehicle') ~= nil)
end

do -- exports
    local list = registered.getVehicles('C1')
    check('getVehicles', #list == 4 and list[1].plate == 'HOME1')
    check('setState rejects junk', registered.setState('HOME1', 7) == false)
    tick()
    moveTo(1, legion)
    local netId = registered.spawn(1, 'HOME1')
    check('spawn export', netId and entities[netId - 5000] and pv.HOME1.state == 0)
    local again, err = registered.spawn(1, 'HOME1')
    check('spawn export refuses a duplicate', again == nil and err == 'That vehicle is already out.')
end

do -- without the other resources
    started.fivelog, started.warden, started.fivepanel, started.qbx_vehiclekeys = nil, nil, nil, nil
    local logs, w, act, keys = #callsTo('fivelog'), #callsTo('warden'), #events('fivepanel:activity'), #callsTo('keys')
    registered.setState('HOME1', 1)
    tick()
    local ok = call('fivegarage:take', 1, 'legion', 'HOME1')
    check('works alone', ok == true)
    check('nothing sent to missing resources', #callsTo('fivelog') == logs and #callsTo('warden') == w and #callsTo('keys') == keys)
    commands.returncar(0, { 'HOME1' })
    check('no fivepanel event', #events('fivepanel:activity') == act)

    started['qb-vehiclekeys'] = 'started'
    tick()
    call('fivegarage:take', 1, 'legion', 'HOME1')
    check('qb-vehiclekeys event', toClient[#toClient].name == 'vehiclekeys:client:SetOwner' and toClient[#toClient].args[1] == 'HOME1')
    started['qb-vehiclekeys'] = nil
    commands.returncar(0, { 'HOME1' })

    local hooked
    Config.giveKeys = function(src, _, plate) hooked = src .. plate end
    tick()
    call('fivegarage:take', 1, 'legion', 'HOME1')
    check('giveKeys hook', hooked == '1HOME1')
    Config.giveKeys = nil
    commands.returncar(0, { 'HOME1' })
end

do -- shared garage
    tick()
    local grove = Config.garages.grove
    moveTo(1, grove.coords)
    moveTo(2, grove.coords)
    qbCar('GANG1', 'C2', 1, 'grove')
    local ok = call('fivegarage:list', 1, 'grove')
    check('shared garage needs the gang', ok == false)
    qbPlayers[1].PlayerData.gang.name = 'families'
    qbPlayers[2].PlayerData.gang.name = 'families'
    local list = call('fivegarage:list', 1, 'grove')
    local shared
    for _, v in ipairs(list) do if v.plate == 'GANG1' then shared = v end end
    check('members see what is parked there', shared and shared.shared == true and shared.here == true)
    ok = call('fivegarage:take', 1, 'grove', 'GANG1')
    check('member takes a shared car', ok == true and pv.GANG1.state == 0)
    tick()
    ok = call('fivegarage:take', 1, 'legion', 'OTHER1')
    check('shared rule only inside the shared garage', ok == false)
end

do -- ESX
    Framework.reset()
    started.qbx_core, started.es_extended = nil, 'started'
    for k in pairs(G.out) do G.out[k] = nil end
    for e in pairs(entities) do entities[e] = nil end
    queries = {}
    esxPlayer(1, 'char1:abc')
    esxPlayer(3, 'char1:cop', 'police', 0)
    local function esxCar(plate, owner, stored)
        ov[plate] = { owner = owner, plate = plate, vehicle = json.encode({ model = GetHashKey('sultan'), plate = plate, fuelLevel = 60.0 }), type = 'car', stored = stored }
    end
    esxCar('ESX1', 'char1:abc', 1)
    esxCar('ESXLOST', 'char1:abc', 0)
    esxCar('ESXOUT', 'char1:abc', 0)
    local veh = addVehicle('ESXOUT', 'sultan', vec3(5, 5, 5))

    dofile('server/main.lua')
    check('esx detected', Framework.name() == 'esx')
    check('esx start up', fg.ESXLOST and fg.ESXLOST.state == 2 and not fg.ESXOUT and G.out.ESXOUT.entity == veh)
    check('esx queries owned_vehicles', queried('FROM owned_vehicles') and not queried('player_vehicles'))

    moveTo(1, legion)
    local list = call('fivegarage:list', 1, 'legion')
    local by = {}
    for _, v in ipairs(list) do by[v.plate] = v end
    check('esx list', by.ESX1 and by.ESX1.state == 1 and by.ESX1.here and by.ESX1.fuel == 60 and by.ESXLOST.state == 2)

    tick()
    local ok = call('fivegarage:take', 1, 'legion', 'ESX1')
    check('esx take', ok == true and ov.ESX1.stored == 0 and fg.ESX1.state == 0)

    tick()
    local car = G.out.ESX1.entity
    entities[car].pos = vec3(218, -805, 30)
    ok = call('fivegarage:store', 1, 'legion', car + 5000, { color1 = 9 })
    check('esx store', ok == true and ov.ESX1.stored == 1 and fg.ESX1.garage == 'legion' and fg.ESX1.state == 1)
    check('esx props in owned_vehicles', json.decode(ov.ESX1.vehicle).color1 == 9 and fg.ESX1.engine == 1000.0)

    tick()
    moveTo(1, davis)
    ok = call('fivegarage:recover', 1, 'davis', 'ESXLOST')
    check('esx depot paid from bank', ok == true and esxPlayers[1].accounts.bank.money == 10000 - 500 and fg.ESXLOST.state == 0)

    tick()
    moveTo(3, legion)
    esxPlayers[3].getJob = function() return { name = 'police', grade = 0 } end
    local imp = addVehicle('ESX1', 'sultan', vec3(216, -805, 30))
    ok = call('fivegarage:impound', 3, imp + 5000, 250, 'Abandoned')
    check('esx impound', ok == true and fg.ESX1.state == 2 and fg.ESX1.fee == 250 and ov.ESX1.stored == 0)

    tick()
    moveTo(1, davis)
    esxPlayers[1].accounts.bank.money = 0
    esxPlayers[1].accounts.money.money = 300
    ok = call('fivegarage:recover', 1, 'davis', 'ESX1')
    check('esx fee from cash when the bank is empty', ok == true and esxPlayers[1].accounts.money.money == 50)
end

io.write(('%d passed, %d failed\n'):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
