-- luacheck config

max_line_length = false

ignore = {
  "21.",
  "4",
  "54"
}

globals = {
  "asyncR",
  "async",
  "class",
  "xtype",
  "warn",
  "wpcall"
}

files["src/server"] = {
  globals = {
    "loop",
    "timer",
    "itimer",
    "wait",
    "server"
  }
}

files["src/client"] = {
  globals = {
    "love",
    "client",
    "scheduler"
  }
}
