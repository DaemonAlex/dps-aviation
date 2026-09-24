fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'dps-aviation'
author 'DelPerroSands'
version '0.1.0'
description 'Flight behaviour for DPS: throttle that idles instead of cutting out, and a sane ground taxi'

shared_script '@ox_lib/init.lua'

client_scripts {
    'config.lua',
    'client.lua',
}
