return {
  host = "localhost:27505",
  max_clients = 100,
  tickrate = 60,
  save_interval = 60, -- seconds
  -- password salts
  client_salt = "<client_salt>",
  server_salt = "<server_salt>",
  project_name = "game",
  db = {
    host = "localhost",
    port = 3306,
    user = "root",
    password = "",
    name = "slayers_online_re"
  },
  motd = "Bienvenue sur Slayers Online RE.",
  quotas = { -- {amount, period in seconds}
    packets = {250, 5}, -- input packets
    data = {5e3, 10}, -- input bytes
    chat_all = {3, 24} -- global chat messages
  },
  server_vars_init = { -- map of key => value
  },
  spawn_location = { -- default (re)spawn location
    map = "BZ zone combat",
    cx = 15,
    cy = 15
  }
}
