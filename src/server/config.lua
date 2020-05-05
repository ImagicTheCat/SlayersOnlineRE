return {
  host = "localhost:27505",
  max_clients = 100,
  tickrate = 60,
  save_interval = 60, -- seconds
  project_name = "game",
  db = {
    host = "localhost",
    port = 3306,
    user = "root",
    password = "",
    name = "slayers_online_re"
  },
  motd = "Bienvenue sur Slayers Online RE.",
  server_vars_init = { -- map of key => value
  },
  spawn_location = { -- default (re)spawn location
    map = "BZ zone combat",
    cx = 15,
    cy = 15
  }
}
