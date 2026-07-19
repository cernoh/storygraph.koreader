allow_defined_top_level_globals = true
stds.lua51 = {
  read_globals = { "self" }
}

ignore = {
  "212/self",
  "__"
}

max_line_length = 300
globals = {
  "G_defaults",
  "G_reader_settings",
  "logger",
  "UIManager",
  "InputContainer",
  "InfoMessage",
  "NetworkMgr",
  "socket"
}
read_globals = {
  "describe",
  "it",
  "assert"
}
