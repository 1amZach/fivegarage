Config = {}

-- Ace for /returncar and /impoundcar. The server console can always use them.
--   add_ace group.admin fivegarage.admin allow
Config.adminAce = 'fivegarage.admin'

-- Taking a car out of a different garage than the one it's parked in.
-- A number is the fee, false means it can only be taken where it was parked.
Config.transferFee = 250

-- Paid at a depot when the car has no fee of its own, like one that was
-- destroyed or lost on a restart.
Config.depotFee = 500

-- Cars still marked out when fivegarage starts go to the depot. Cars that are
-- still in the world (fivegarage restarted on a running server) are left alone.
Config.depotOnStart = true

-- Accounts fees come from, tried in order.
Config.payWith = { 'bank', 'cash' }

-- Put the player in the driver seat after taking a car out.
Config.warpIn = true

-- Fuel: 'ox_fuel' sets Entity(vehicle).state.fuel, 'native' sets it with the
-- game native on the owner's client, false leaves it alone.
Config.fuel = 'ox_fuel'

-- Engine upgrades, brakes, armour and so on are kept from the database when a
-- car is parked instead of trusting what the client sends. Turn off only if
-- your tuning script never saves to the database itself.
Config.keepPerformance = true

-- Keys are given with qbx_vehiclekeys or qb-vehiclekeys when one is started.
-- For anything else, give them here:
--   Config.giveKeys = function(src, vehicle, plate)
--       exports.mykeys:give(src, plate)
--   end
Config.giveKeys = nil

-- `radius` is how far from a garage's point the server lets players use it
-- and park, `markerRadius` where the prompt shows. Garages can set their own
-- `radius`.
Config.radius = 20.0
Config.markerRadius = 4.0

-- Seconds between garage actions per player.
Config.cooldown = 2

-- A spawn point is free when no vehicle is this close to it.
Config.clearRadius = 3.0

-- Garage types and the vehicle types they take.
Config.types = {
    car = { automobile = true, bike = true, trailer = true },
    boat = { boat = true, submarine = true },
    air = { heli = true, plane = true },
}

Config.blips = {
    car = { sprite = 357, color = 3, scale = 0.7 },
    boat = { sprite = 356, color = 3, scale = 0.7 },
    air = { sprite = 359, color = 3, scale = 0.7 },
    depot = { sprite = 68, color = 47, scale = 0.7 },
}

-- Public garages. Add `job` or `gang` (and `grade`) to make one shared: only
-- that group can use it, and any member can take out what's parked there.
Config.garages = {
    legion = {
        label = 'Legion Square',
        type = 'car',
        coords = vec3(215.9, -809.7, 30.7),
        spawns = { vec4(234.2, -787.1, 30.2, 160.0), vec4(237.6, -784.6, 30.2, 160.0) },
    },
    pinkcage = {
        label = 'Pink Cage Motel',
        type = 'car',
        coords = vec3(273.4, -344.0, 44.9),
        spawns = { vec4(270.9, -343.0, 44.5, 160.0), vec4(267.6, -341.7, 44.5, 160.0) },
    },
    spanish = {
        label = 'Spanish Avenue',
        type = 'car',
        coords = vec3(-1160.9, -741.4, 19.6),
        spawns = { vec4(-1145.2, -745.4, 19.3, 108.0), vec4(-1142.7, -749.2, 19.0, 108.0) },
    },
    airport = {
        label = 'Airport Parking',
        type = 'car',
        coords = vec3(-773.1, -2033.0, 8.9),
        spawns = { vec4(-779.8, -2040.2, 8.5, 315.0), vec4(-776.0, -2043.7, 8.5, 315.0) },
    },
    sandy = {
        label = 'Sandy Shores',
        type = 'car',
        coords = vec3(1737.8, 3710.2, 34.1),
        spawns = { vec4(1730.4, 3714.8, 34.1, 20.0), vec4(1725.6, 3712.4, 34.2, 20.0) },
    },
    paleto = {
        label = 'Paleto Bay',
        type = 'car',
        coords = vec3(140.6, 6613.0, 31.9),
        spawns = { vec4(145.4, 6600.6, 31.8, 180.0), vec4(150.5, 6596.3, 31.8, 180.0) },
    },
    lsyc = {
        label = 'Puerto Del Sol Marina',
        type = 'boat',
        coords = vec3(-794.7, -1510.8, 1.6),
        spawns = { vec4(-798.0, -1500.6, 0.1, 110.0) },
    },
    paletocove = {
        label = 'Paleto Cove',
        type = 'boat',
        coords = vec3(-1605.0, 5258.6, 2.1),
        spawns = { vec4(-1600.4, 5265.5, 0.1, 25.0) },
    },
    lsia = {
        label = 'LSIA Hangar',
        type = 'air',
        coords = vec3(-1243.5, -3391.9, 13.9),
        spawns = { vec4(-1258.4, -3394.6, 13.9, 330.0) },
        radius = 40.0,
    },
    sandyair = {
        label = 'Sandy Shores Airfield',
        type = 'air',
        coords = vec3(1757.7, 3296.1, 41.1),
        spawns = { vec4(1740.9, 3279.0, 41.1, 190.0) },
        radius = 40.0,
    },

    -- shared
    grove = {
        label = 'Grove Street',
        type = 'car',
        gang = 'families',
        coords = vec3(105.6, -1941.2, 20.8),
        spawns = { vec4(102.4, -1935.0, 20.6, 50.0) },
        blip = false,
    },
}

-- Where lost, destroyed and impounded vehicles are picked up. `type` limits a
-- depot to one garage type, leave it out for all of them.
Config.depots = {
    davis = {
        label = 'Davis Impound',
        type = 'car',
        coords = vec3(409.3, -1623.0, 29.3),
        spawns = { vec4(416.4, -1628.3, 29.3, 140.0), vec4(419.9, -1631.6, 29.3, 140.0) },
    },
    sandy = {
        label = 'Sandy Shores Impound',
        type = 'car',
        coords = vec3(1649.7, 3789.6, 34.8),
        spawns = { vec4(1643.7, 3798.4, 34.5, 216.0) },
    },
    marina = {
        label = 'Marina Impound',
        type = 'boat',
        coords = vec3(-790.4, -1514.6, 1.6),
        spawns = { vec4(-805.5, -1496.0, 0.1, 110.0) },
    },
    hangar = {
        label = 'Hangar Impound',
        type = 'air',
        coords = vec3(-1236.0, -3384.0, 13.9),
        spawns = { vec4(-1270.0, -3380.0, 13.9, 330.0) },
        radius = 40.0,
    },
}

-- Police impound with /impound or the target option.
Config.impound = {
    command = 'impound',
    jobs = { police = 0, sheriff = 0 },
    onDuty = true,
    target = true,
    defaultFee = 500,
    maxFee = 10000,
    distance = 8.0,
}

-- Job vehicles. Spawned and handed back, never owned. `grade` is the lowest
-- grade for each one. `plate` is the prefix, the rest is numbers.
Config.jobGarages = {
    mrpd = {
        label = 'Mission Row PD',
        job = 'police',
        plate = 'LSPD',
        onDuty = true,
        coords = vec3(448.2, -1017.4, 28.6),
        spawns = { vec4(446.2, -1025.5, 28.6, 4.0), vec4(442.5, -1025.9, 28.6, 4.0), vec4(438.7, -1026.3, 28.7, 4.0) },
        vehicles = {
            { model = 'police', label = 'Cruiser', grade = 0, livery = 0, extras = { [1] = true, [2] = true } },
            { model = 'police2', label = 'Buffalo', grade = 1 },
            { model = 'police3', label = 'Interceptor', grade = 2 },
            { model = 'policeb', label = 'Bike', grade = 2 },
            { model = 'fbi2', label = 'Unmarked SUV', grade = 3 },
        },
    },
    mrpdair = {
        label = 'Mission Row Helipad',
        job = 'police',
        plate = 'LSPD',
        onDuty = true,
        coords = vec3(461.5, -982.3, 43.7),
        spawns = { vec4(449.2, -981.3, 43.7, 90.0) },
        radius = 25.0,
        vehicles = {
            { model = 'polmav', label = 'Maverick', grade = 3, livery = 0 },
        },
    },
    pillbox = {
        label = 'Pillbox Hill',
        job = 'ambulance',
        plate = 'EMS',
        onDuty = true,
        coords = vec3(294.6, -574.8, 43.2),
        spawns = { vec4(290.2, -588.5, 43.2, 340.0), vec4(294.8, -590.6, 43.2, 340.0) },
        vehicles = {
            { model = 'ambulance', label = 'Ambulance', grade = 0 },
        },
    },
}

-- Job vehicles one player can have out from one job garage at a time.
Config.jobLimit = 1
