fx_version 'cerulean'
game 'gta5'
author "dnj"
lua54 "on"
shared_scripts {
    'shared/*.lua',
    '@ox_lib/init.lua'
}
server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/*.lua'
}
client_scripts {
    'client/*.lua'
}

