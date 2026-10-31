-- Owned vehicles live in the framework's own table. fivegarage keeps what
-- that table has no column for (ESX garage and impound state, impound reasons)
-- in its own table, keyed by plate.

DB = {}

local join = ' LEFT JOIN fivegarage f ON f.plate = v.plate'

local upsert = [[INSERT INTO fivegarage (plate, garage, state, fee, reason, fuel, engine, body) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
ON DUPLICATE KEY UPDATE garage = COALESCE(VALUES(garage), garage), state = VALUES(state), fee = VALUES(fee), reason = VALUES(reason),
fuel = COALESCE(VALUES(fuel), fuel), engine = COALESCE(VALUES(engine), engine), body = COALESCE(VALUES(body), body)]]

DB.sql = {
    qb = {
        select = 'SELECT v.citizenid AS owner, v.plate, v.vehicle, v.hash, v.mods, v.garage, v.state, v.fuel, v.engine, v.body, v.depotprice, f.reason FROM player_vehicles v' .. join,
        store = 'UPDATE player_vehicles SET state = 1, garage = ?, mods = ?, fuel = ?, engine = ?, body = ?, depotprice = 0 WHERE plate = ?',
        state = 'UPDATE player_vehicles SET state = ?, garage = COALESCE(?, garage), depotprice = ? WHERE plate = ?',
        out = 'SELECT plate FROM player_vehicles WHERE state = 0',
        depot = 'UPDATE player_vehicles SET state = 2 WHERE state = 0 AND plate IN (%s)',
    },
    esx = {
        select = 'SELECT v.owner, v.plate, v.vehicle, v.type, v.stored, f.garage, f.state, f.fee, f.fuel, f.engine, f.body, f.reason FROM owned_vehicles v' .. join,
        store = 'UPDATE owned_vehicles SET stored = 1, vehicle = ? WHERE plate = ?',
        state = 'UPDATE owned_vehicles SET stored = ? WHERE plate = ?',
        out = 'SELECT v.plate FROM owned_vehicles v' .. join .. ' WHERE v.stored = 0 AND COALESCE(f.state, 0) = 0',
        depot = 'INSERT INTO fivegarage (plate, state) VALUES %s ON DUPLICATE KEY UPDATE state = 2',
    },
    upsert = upsert,
}

local function sql() return Framework.name() == 'esx' and DB.sql.esx or DB.sql.qb end

local function decode(s)
    if type(s) == 'table' then return s end
    if type(s) ~= 'string' or s == '' then return {} end
    local ok, t = pcall(json.decode, s)
    return ok and type(t) == 'table' and t or {}
end

function DB.trim(plate)
    return type(plate) == 'string' and plate:match('^%s*(.-)%s*$') or nil
end

local function row(r)
    if not r then return end
    if sql() == DB.sql.qb then
        local props = decode(r.mods)
        return {
            plate = DB.trim(r.plate), owner = r.owner, props = props,
            model = props.model or r.hash or r.vehicle, name = r.vehicle,
            garage = r.garage, state = tonumber(r.state) or 1,
            fuel = tonumber(r.fuel) or props.fuelLevel or 100,
            engine = tonumber(r.engine) or props.engineHealth or 1000,
            body = tonumber(r.body) or props.bodyHealth or 1000,
            fee = tonumber(r.depotprice) or 0, reason = r.reason,
        }
    end
    local props = decode(r.vehicle)
    return {
        plate = DB.trim(r.plate), owner = r.owner, props = props, model = props.model, kind = r.type,
        garage = r.garage, state = tonumber(r.state) or (tonumber(r.stored) == 1 and 1 or 0),
        fuel = tonumber(r.fuel) or props.fuelLevel or 100,
        engine = tonumber(r.engine) or props.engineHealth or 1000,
        body = tonumber(r.body) or props.bodyHealth or 1000,
        fee = tonumber(r.fee) or 0, reason = r.reason,
    }
end

local function rows(list)
    local out = {}
    for _, r in ipairs(list or {}) do out[#out + 1] = row(r) end
    return out
end

function DB.owned(id)
    local s = sql()
    return rows(MySQL.query.await(s.select .. (s == DB.sql.esx and ' WHERE v.owner = ?' or ' WHERE v.citizenid = ?'), { id }))
end

function DB.byPlate(plate)
    plate = DB.trim(plate)
    if not plate or plate == '' then return end
    return row(MySQL.single.await(sql().select .. ' WHERE v.plate = ?', { plate }))
end

-- Everything parked in one garage, whoever owns it. For shared garages.
function DB.parked(garage)
    local s = sql()
    local where = s == DB.sql.esx and ' WHERE f.garage = ? AND f.state = 1' or ' WHERE v.garage = ? AND v.state = 1'
    return rows(MySQL.query.await(s.select .. where, { garage }))
end

function DB.store(plate, garage, props, fuel, engine, body)
    local s = sql()
    if s == DB.sql.esx then
        local n = MySQL.update.await(s.store, { json.encode(props), plate })
        MySQL.update.await(upsert, { plate, garage, 1, 0, nil, fuel, engine, body })
        return (n or 0) > 0
    end
    local n = MySQL.update.await(s.store, { garage, json.encode(props), fuel, engine, body, plate })
    MySQL.update.await(upsert, { plate, garage, 1, 0, nil, nil, nil, nil })
    return (n or 0) > 0
end

function DB.setState(plate, state, garage, fee, reason)
    local s = sql()
    fee = math.floor(tonumber(fee) or 0)
    local n
    if s == DB.sql.esx then
        n = MySQL.update.await(s.state, { state == 1 and 1 or 0, plate })
    else
        n = MySQL.update.await(s.state, { state, garage, fee, plate })
    end
    MySQL.update.await(upsert, { plate, garage, state, fee, reason, nil, nil, nil })
    return (n or 0) > 0
end

function DB.outPlates()
    local out = {}
    for _, r in ipairs(MySQL.query.await(sql().out, {}) or {}) do out[#out + 1] = DB.trim(r.plate) end
    return out
end

function DB.toDepot(plates)
    local s = sql()
    for i = 1, #plates, 200 do
        local chunk = { table.unpack(plates, i, math.min(i + 199, #plates)) }
        local marks = s == DB.sql.esx and ('(?, 2), '):rep(#chunk):sub(1, -3) or ('?, '):rep(#chunk):sub(1, -3)
        MySQL.update.await(s.depot:format(marks), chunk)
    end
end

DB.schema = [[
CREATE TABLE IF NOT EXISTS `fivegarage` (
    `plate` VARCHAR(12) NOT NULL,
    `garage` VARCHAR(50) NULL,
    `state` TINYINT NOT NULL DEFAULT 1,
    `fee` INT UNSIGNED NOT NULL DEFAULT 0,
    `reason` VARCHAR(120) NULL,
    `fuel` FLOAT NULL,
    `engine` FLOAT NULL,
    `body` FLOAT NULL,
    `updated` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`plate`),
    KEY `garage_state` (`garage`, `state`)
)]]
