local utils = require("app.utils")

-- Net packet protocol.
return utils.rmap{
  "MAP",
  "ENTITY_ADD",
  "ENTITY_REMOVE",
  "INPUT_ORIENTATION",
  "INPUT_MOVE_FORWARD",
  "ENTITY_PACKET",
  "MAP_MOVEMENTS",
  "INPUT_ATTACK",
  "INPUT_CHAT",
  "MAP_CHAT",
  "CHAT_MESSAGE_SERVER",
  "INPUT_INTERACT",
  "EVENT_MESSAGE",
  "EVENT_MESSAGE_SKIP",
  "EVENT_INPUT_QUERY",
  "EVENT_INPUT_QUERY_ANSWER",
  "EVENT_INPUT_STRING",
  "EVENT_INPUT_STRING_ANSWER",
  "PLAYER_CONFIG",
  "MOTD_LOGIN",
  "LOGIN",
  "VERSION_CHECK",
  "INVENTORY_UPDATE_ITEMS",
  "CHEST_OPEN",
  "CHEST_UPDATE_ITEMS",
  "CHEST_CLOSE",
  "SHOP_OPEN",
  "SHOP_CLOSE",
  "STATS_UPDATE",
  "PLAY_MUSIC",
  "STOP_MUSIC",
  "PLAY_SOUND",
  "GOLD_STORE",
  "GOLD_WITHDRAW",
  "ITEM_STORE",
  "ITEM_WITHDRAW",
  "ITEM_BUY",
  "ITEM_SELL",
  "ITEM_TRASH",
  "SPEND_CHARACTERISTIC_POINT",
  "ITEM_EQUIP",
  "SLOT_UNEQUIP",
  "SCROLL_TO",
  "SCROLL_END",
  "SCROLL_RESET",
  "INPUT_DEFEND",
  "VIEW_SHIFT_UPDATE",
  "QUICK_ACTION_BIND",
  "ITEM_USE",
  "GLOBAL_CHAT",
  "GROUP_CHAT",
  "GUILD_CHAT",
  "PRIVATE_CHAT",
  "TARGET_PICK",
  "SPELL_INVENTORY_UPDATE_ITEMS",
  "SPELL_CAST",
  "TRADE_SEEK",
  "TRADE_OPEN",
  "TRADE_LEFT_UPDATE_ITEMS",
  "TRADE_RIGHT_UPDATE_ITEMS",
  "TRADE_SET_GOLD",
  "TRADE_PUT_ITEM",
  "TRADE_TAKE_ITEM",
  "TRADE_LOCK",
  "TRADE_PEER_LOCK",
  "TRADE_CLOSE",
  "DIALOG_QUERY",
  "DIALOG_RESULT",
  "MAP_EFFECT",
  "MAP_PLAY_ANIMATION",
  "MAP_PLAY_SOUND"
}
