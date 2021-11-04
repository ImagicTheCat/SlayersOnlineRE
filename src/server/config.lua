return {
  host = "localhost:27505",
  max_clients = 100,
  tickrate = 60,
  db_tickrate = 100,
  -- Used to decrease event computations (prefer 1/x fractions, where x is an integer).
  event_frequency_factor = 1,
  save_period = 120, -- seconds
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
  inventory_size = 100,
  spell_inventory_size = 100,
  chest_size = 1000,
  respawn_delay = 10, -- seconds
  server_vars_init = { -- map of key => value
  },
  spawn_location = { -- default (re)spawn location
    map = "BZ zone combat",
    cx = 15,
    cy = 15
  }
}
