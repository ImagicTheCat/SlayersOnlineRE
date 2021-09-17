-- Prepared statements.
return function(db)
  local uint = "INTEGER UNSIGNED"
  local ubint = "BIGINT UNSIGNED"
  local utint = "TINYINT UNSIGNED"
  local pseudo_t, password_t = "VARCHAR(50)", "BINARY(64)"
  -- server
  db:prepare("server/setVar", "INSERT INTO server_vars(id, value) VALUES({1}, {2}) ON DUPLICATE KEY UPDATE value = {2}", {"VARCHAR(200)", "TEXT(65535)"})
  db:prepare("server/getVars", "SELECT id, value FROM server_vars")
  db:prepare("user/createAccount", [[
INSERT INTO users(
  pseudo,
  password,
  rank,
  ban_timestamp,
  class,
  level,
  alignment,
  reputation,
  gold,
  chest_gold,
  xp,
  strength_pts,
  dexterity_pts,
  constitution_pts,
  magic_pts,
  remaining_pts,
  weapon_slot,
  shield_slot,
  helmet_slot,
  armor_slot,
  guild,
  guild_rank,
  guild_rank_title
) VALUES(
  {pseudo}, {password},
  {rank}, 0, 1, 1, 100, 0, 0,
  0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0,
  "", 0, ""
);
]], {
  pseudo = pseudo_t,
  password = password_t,
  rank = utint
})
  db:prepare("user/setRank", "UPDATE users SET rank = {rank} WHERE pseudo = {pseudo}", {rank = utint, pseudo = pseudo_t})
  db:prepare("user/setGuild", "UPDATE users SET guild = {guild}, guild_rank = {rank}, guild_rank_title = {title} WHERE pseudo = {pseudo}", {
    guild = "VARCHAR(100)", rank = utint,
    title = "VARCHAR(100)", pseudo = pseudo_t
})
  db:prepare("user/setBan", "UPDATE users SET ban_timestamp = {timestamp} WHERE pseudo = {pseudo}", {pseudo = pseudo_t, timestamp = "INTEGER"})
  db:prepare("server/getFreeSkins", "SELECT name FROM skins WHERE free = TRUE")
  -- user
  db:prepare("user/login", "SELECT * FROM users WHERE pseudo = {1} AND password = {2}", {pseudo_t, password_t})
  db:prepare("user/getVars", "SELECT id,value FROM users_vars WHERE user_id = {1}", {uint})
  db:prepare("user/getBoolVars", "SELECT id,value FROM users_bool_vars WHERE user_id = {1}", {uint})
  db:prepare("user/setVar", "INSERT INTO users_vars(user_id, id, value) VALUES({1},{2},{3}) ON DUPLICATE KEY UPDATE value = {3}", {uint, uint, "INTEGER"})
  db:prepare("user/setBoolVar", "INSERT INTO users_bool_vars(user_id, id, value) VALUES({1},{2},{3}) ON DUPLICATE KEY UPDATE value = {3}", {uint, uint, "TINYINT"})
  db:prepare("user/setConfig", "UPDATE users SET config = {2} WHERE id = {1}", {uint, "BLOB(65535)"})
  db:prepare("user/setState", "UPDATE users SET state = {2} WHERE id = {1}", {uint, "BLOB(65535)"})
  db:prepare("user/setData", [[
    UPDATE users SET
    level = {level},
    alignment = {alignment},
    reputation = {reputation},
    gold = {gold},
    chest_gold = {chest_gold},
    xp = {xp},
    strength_pts = {strength_pts},
    dexterity_pts = {dexterity_pts},
    constitution_pts = {constitution_pts},
    magic_pts = {magic_pts},
    remaining_pts = {remaining_pts},
    weapon_slot = {weapon_slot},
    shield_slot = {shield_slot},
    helmet_slot = {helmet_slot},
    armor_slot = {armor_slot}
    WHERE id = {user_id}
  ]], {
    level = utint,
    alignment = utint,
    reputation = uint,
    gold = ubint,
    chest_gold = ubint,
    xp = ubint,
    strength_pts = uint,
    dexterity_pts = uint,
    constitution_pts = uint,
    magic_pts = uint,
    remaining_pts = uint,
    weapon_slot = uint,
    shield_slot = uint,
    helmet_slot = uint,
    armor_slot = uint,
    user_id = uint
  })
  db:prepare("user/pruneSkins", [[
    DELETE users_skins FROM users_skins
    INNER JOIN users AS sharer ON users_skins.shared_by = sharer.id
    INNER JOIN users AS self ON users_skins.user_id = self.id
    WHERE users_skins.user_id = {1} AND self.guild != sharer.guild
  ]], {uint})
  db:prepare("user/getSkins", "SELECT name FROM users_skins WHERE user_id = {1}", {uint})
  -- inventory
  db:prepare("inventory/getItems", "SELECT id, amount FROM users_items WHERE user_id = {1} AND inventory = {2}", {uint, uint})
  db:prepare("inventory/setItem", "INSERT INTO users_items(user_id, inventory, id, amount) VALUES({1},{2},{3},{4}) ON DUPLICATE KEY UPDATE amount = {4}", {uint, uint, uint, uint})
  db:prepare("inventory/removeItem", "DELETE FROM users_items WHERE user_id = {1} AND inventory = {2} AND id = {3}", {uint, uint, uint})
end
