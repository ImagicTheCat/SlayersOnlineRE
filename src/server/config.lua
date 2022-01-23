return {
  host = "localhost:27505",
  max_clients = 100,
  tickrate = 60,
  -- Used to decrease event computations (prefer 1/x fractions, where x is an integer).
  event_frequency_factor = 1,
  save_period = 120, -- seconds
  project_name = "game",
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
  },
  player_config = { -- default player config
    scancode_controls = {
      w = "up",
      d = "right",
      s = "down",
      a = "left",
      space = "attack",
      lalt = "defend",
      e = "interact",
      ["return"] = "return",
      escape = "menu",
      acback = "menu", -- android escape key
      ["1"] = "quick1",
      ["2"] = "quick2",
      ["3"] = "quick3",
      pagedown = "chat_up",
      pageup = "chat_down",
      up = "chat_prev",
      down = "chat_next",
      f11 = "fullscreen"
    },
    gamepad_controls = {
      dpup = "up",
      dpright = "right",
      dpdown = "down",
      dpleft = "left",
      x = "attack",
      b = "defend",
      a = "interact",
      back = "return",
      start = "menu",
      y = "quick1",
      rightshoulder = "quick2",
      leftshoulder = "quick3"
    },
    gui = {
      font_size = 25,
      dialog_height = 0.25,
      chat_height = 0.25
    },
    quick_actions = {},
    volume = {
      master = 1,
      music = 0.75
    }
  }
}
