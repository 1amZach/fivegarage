# fivegarage

Garages, a depot and job vehicles for Qbox, QBCore and ESX. Players park their own cars and take them out again, pick up lost or impounded ones at the depot, and jobs get their vehicles from a list.

The server spawns every car and checks every action, so the client can't take out someone else's car, a second copy of one that's already out, or one from across the map.

## Features

- Public garages for cars, boats and aircraft, with blips. The menu shows each car's fuel, engine and body.
- Take a car out of the garage it's parked in, or from any garage for a fee (`Config.transferFee`)
- Park the car you're in or standing next to. Its mods, damage and fuel are saved.
- A car can only be out once. Taking it again while it still exists is refused.
- The depot: cars that were destroyed, deleted or lost on a restart are picked up there for a fee. On start, anything still marked out goes there.
- Police impound with `/impound` or the target option, with a fee and a reason
- Job garages: a vehicle list per job with a lowest grade for each, livery and extras, and a plate prefix like `LSPD1234`. Handed back, never owned.
- Shared garages for a gang or job, where any member can take out what's parked there
- Keys for qbx_vehiclekeys and qb-vehiclekeys, or your own key script through `Config.giveKeys`
- Fuel through ox_fuel or the game native
- ox_target when it's running, otherwise a prompt and **E**

Uses the framework's own vehicle table: `player_vehicles` on Qbox and QBCore, `owned_vehicles` on ESX. Anything that table has no column for, like the garage and impound state on ESX or an impound reason, is kept in a small `fivegarage` table by plate.

## With the others

- **[fivelog](https://github.com/1amZach/fivelog):** every take out, park, depot pickup, impound and staff return is logged under `vehicles`, and so is anything fivegarage refused.
- **[fivepanel](https://github.com/1amZach/fivepanel):** police impounds and staff commands show in the activity feed.
- **[warden](https://github.com/1amZach/warden):** a garage spawn never gets a player flagged for a blocked model, entity spam or the warp into the seat.

## Install

Needs [ox_lib](https://github.com/overextended/ox_lib) and [oxmysql](https://github.com/overextended/oxmysql).

1. Remove or stop your old garage script: `qbx_garages`, `qb-garages` or `esx_garage`. Running two garage scripts on the same table ends badly.

2. Drop `fivegarage` into your resources and add to `server.cfg` after ox_lib, oxmysql and your framework:

   ```
   ensure fivegarage
   ```

3. The `fivegarage` table is made on first start. If your database user can't create tables, run `sql/fivegarage.sql` yourself.

4. For the staff commands:

   ```
   add_ace group.admin fivegarage.admin allow
   ```

Cars parked in garages from your old script that aren't in `Config.garages` can be taken out at any garage of the right type, without a fee.

## Config

`config.lua`:

| | |
|---|---|
| `Config.garages` | Public garages: `label`, `type` (`car`, `boat`, `air`), `coords`, `spawns`, optional `radius` and `blip`. Add `job` or `gang` and `grade` for a shared one |
| `Config.depots` | Where lost and impounded cars are picked up. `type` limits one to a garage type |
| `Config.jobGarages` | `job`, `plate` prefix, `onDuty`, and `vehicles` with `model`, `label`, `grade`, `livery`, `extras` |
| `Config.transferFee` | Fee to take a car from a different garage, or `false` to only allow where it's parked |
| `Config.depotFee` | Depot fee for cars that don't have one of their own |
| `Config.depotOnStart` | Send cars still marked out to the depot on start |
| `Config.impound` | Command, jobs with their lowest grade, fee limits, and the target option |
| `Config.payWith` | Accounts fees are taken from, in order |
| `Config.fuel` | `'ox_fuel'`, `'native'` or `false` |
| `Config.giveKeys` | Function for key scripts other than qbx_vehiclekeys and qb-vehiclekeys |
| `Config.keepPerformance` | Keep engine, brake, transmission, suspension, armour and turbo upgrades from the database when parking |
| `Config.jobLimit` | Job vehicles one player can have out from one job garage |
| `Config.radius` | How far from a garage the server lets players use it |

## Commands

| | |
|---|---|
| `/impound` | Police: impound the car you're in or next to, with a fee and a reason |
| `/returncar <plate>` | Staff: put a car back in its garage, free |
| `/impoundcar <plate> [fee]` | Staff: send a car to the depot |

Both staff commands work from the server console.

## For other resources

Server side:

```lua
-- everything a player owns: plate, model, garage, state, fuel, engine, body, fee
local cars = exports.fivegarage:getVehicles(citizenid)

-- 0 out, 1 in a garage, 2 impounded. A car that's out is deleted first.
exports.fivegarage:setState('AB12CD34', 1, 'legion')

if exports.fivegarage:isOut('AB12CD34') then return end

-- spawn an owned car for a player where they stand, or at a vec4
local netId, err = exports.fivegarage:spawn(source, 'AB12CD34')

AddEventHandler('fivegarage:spawned', function(src, plate, netId, garage) end)
AddEventHandler('fivegarage:stored', function(src, plate, garage) end)
```

On ESX the identifier is the player's `identifier`. Call these from a thread, they wait on the database.

## Testing

```
lua5.4 test/run.lua
```

Runs the server side against a fake FiveM server and database, on Qbox and ESX.

## Support

Made by **IamZach**. Questions, bugs or ideas: [discord.gg/agn](https://discord.gg/agn)

## License

MIT
