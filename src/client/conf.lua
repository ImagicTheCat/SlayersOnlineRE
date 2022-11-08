-- https://github.com/ImagicTheCat/SlayersOnlineRE
-- MIT license (see LICENSE, src/server/main.lua or src/client/main.lua)

function love.conf(t)
  t.identity = "SlayersOnlineRE"
  t.externalstorage = true

  t.window.title = "Slayers Online RE"
  t.window.resizable = true
  t.window.usedpiscale = false
end
