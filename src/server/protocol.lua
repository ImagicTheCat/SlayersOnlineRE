-- net packet protocol enum
return {
  PROTOCOL = 0,
  MAP = 1, -- change map,
  ENTITY_ADD = 2,
  ENTITY_REMOVE = 3,
  INPUT_ORIENTATION = 4,
  INPUT_MOVE_FORWARD = 5,
  ENTITY_PACKET = 6,
  MAP_MOVEMENTS = 7,
  INPUT_ATTACK = 8,
  INPUT_CHAT = 9,
  MAP_CHAT = 10,
  CHAT_MESSAGE_SERVER = 11,
  INPUT_INTERACT = 12,
  EVENT_MESSAGE = 13,
  EVENT_MESSAGE_SKIP = 14,
  EVENT_INPUT_QUERY = 15,
  EVENT_INPUT_QUERY_ANSWER = 16,
  EVENT_INPUT_STRING = 17,
  EVENT_INPUT_STRING_ANSWER = 18,
  PLAYER_CONFIG = 19,
  MOTD_LOGIN = 20,
  LOGIN = 21
}
