fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'fivegarage'
description 'Garages, impound and job vehicles for Qbox, QBCore and ESX'
version '1.0.0'
author 'IamZach'
discord 'https://discord.gg/agn'
repository 'https://github.com/1amZach/fivegarage'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/framework.lua',
    'server/db.lua',
    'server/vehicles.lua',
    'server/garages.lua',
    'server/jobs.lua',
    'server/main.lua',
}

client_scripts {
    'client/vehicle.lua',
    'client/main.lua',
}

dependencies {
    'ox_lib',
    'oxmysql',
}
