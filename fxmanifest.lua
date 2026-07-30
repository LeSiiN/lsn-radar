fx_version "cerulean"

game "gta5"

author "LeSiiN"
description "Police radar and plate reader, styled to match ps-mdt and ps-dispatch"
version "1.0.3"

lua54 "yes"

ui_page "html/index.html"
-- ui_page "http://localhost:5173/" -- for dev

shared_script "shared/config.lua"

client_script {
  "client/utils.lua",
  "client/main.lua",
  "client/scan.lua",
  "client/radar.lua",
  "client/plates.lua",
  "client/target.lua",
  "client/preview.lua",
}

server_script {
  "server/main.lua",
}

files {
  "html/**",
}

dependencies {
  "qb-core",
}
