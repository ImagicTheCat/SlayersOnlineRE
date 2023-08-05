-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.
--
-- Copyright (c) 2019 ImagicTheCat

-- Prepared statements.
-- (async)
return function(db)
  -- server
  db:prepare("begin", "BEGIN")
  db:prepare("commit", "COMMIT")
  db:prepare("rollback", "ROLLBACK")
  db:prepare("server/setVar", [[
    INSERT INTO server_vars(id, value)
    VALUES({1}, {2})
    ON CONFLICT(id) DO UPDATE SET value = {2}
  ]])
  db:prepare("server/getVars", "SELECT id, value FROM server_vars")
  db:prepare("user/createAccount", [[
    INSERT INTO users(pseudo, salt, password, rank, creation_timestamp, ban_timestamp, class)
    VALUES({pseudo}, {salt}, {password}, {rank}, {timestamp}, 0, 1)
  ]])
  db:prepare("user/deleteAccount", "DELETE FROM users WHERE pseudo = {1}")
  db:prepare("user/setRank", "UPDATE users SET rank = {rank} WHERE pseudo = {pseudo}")
  db:prepare("user/setGuild", [[
    UPDATE users SET guild = {guild}, guild_rank = {rank}, guild_rank_title = {title}
    WHERE pseudo = {pseudo}
  ]])
  db:prepare("user/setBan", "UPDATE users SET ban_timestamp = {timestamp} WHERE pseudo = {pseudo}")
  db:prepare("server/getFreeSkins", "SELECT name FROM skins WHERE free = TRUE")
  -- user
  db:prepare("user/getId", "SELECT id FROM users WHERE pseudo = {1}")
  db:prepare("user/getSalt", "SELECT salt FROM users WHERE pseudo = {1}")
  db:prepare("user/login", "SELECT * FROM users WHERE pseudo = {1} AND password = {2}")
  db:prepare("user/getVars", "SELECT id,value FROM users_vars WHERE user_id = {1}")
  db:prepare("user/getBoolVars", "SELECT id,value FROM users_bool_vars WHERE user_id = {1}")
  db:prepare("user/setVar", [[
    INSERT INTO users_vars(user_id, id, value)
    VALUES({1},{2},{3})
    ON CONFLICT(user_id, id) DO UPDATE SET value = {3}
  ]])
  db:prepare("user/setBoolVar", [[
    INSERT INTO users_bool_vars(user_id, id, value)
    VALUES({1},{2},{3})
    ON CONFLICT(id, user_id) DO UPDATE SET value = {3}
  ]])
  db:prepare("user/setConfig", "UPDATE users SET config = {2} WHERE id = {1}")
  db:prepare("user/setState", "UPDATE users SET state = {2} WHERE id = {1}")
  db:prepare("user/getState", "SELECT state FROM users WHERE id = {1}")
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
    armor_slot = {armor_slot},
    stat_played = {stat_played},
    stat_traveled = {stat_traveled},
    stat_mob_kills = {stat_mob_kills},
    stat_deaths = {stat_deaths}
    WHERE id = {user_id}
  ]])
  db:prepare("user/pruneSkins", [[
    DELETE FROM users_skins WHERE rowid IN(
      SELECT users_skins.rowid FROM users_skins
      INNER JOIN users AS sharer ON users_skins.shared_by = sharer.id
      INNER JOIN users AS self ON users_skins.user_id = self.id
      WHERE users_skins.user_id = {1} AND self.guild != sharer.guild
    )
  ]])
  db:prepare("user/getSkins", "SELECT name FROM users_skins WHERE user_id = {1}")
  db:prepare("user/deleteVars", "DELETE FROM users_vars WHERE user_id = {1}")
  db:prepare("user/deleteBoolVars", "DELETE FROM users_bool_vars WHERE user_id = {1}")
  db:prepare("user/deleteItems", "DELETE FROM users_items WHERE user_id = {1}")
  -- inventory
  db:prepare("inventory/getItems", "SELECT id, amount FROM users_items WHERE user_id = {1} AND inventory = {2}")
  db:prepare("inventory/setItem", [[
    INSERT INTO users_items(user_id, inventory, id, amount)
    VALUES({1},{2},{3},{4}) ON CONFLICT(id, user_id, inventory)
    DO UPDATE SET amount = {4}
  ]])
  db:prepare("inventory/removeItem", "DELETE FROM users_items WHERE user_id = {1} AND inventory = {2} AND id = {3}")
end
