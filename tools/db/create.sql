-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.
--
-- Copyright (c) 2019 ImagicTheCat

CREATE TABLE users(
  id INTEGER PRIMARY KEY,
  pseudo TEXT UNIQUE COLLATE NOCASE,
  salt BLOB,
  password BLOB,
  rank INTEGER, -- user rank (permissions); 0: server, 10: normal player
  creation_timestamp INTEGER,
  ban_timestamp INTEGER, -- ban timestamp (end)
  config BLOB, -- player config (msgpack)
  state BLOB, -- player state (msgpack)
  class INTEGER, -- class index (1-based)
  level INTEGER DEFAULT 1,
  alignment INTEGER DEFAULT 100,
  reputation INTEGER DEFAULT 0,
  gold INTEGER DEFAULT 0,
  chest_gold INTEGER DEFAULT 0,
  xp INTEGER DEFAULT 0,
  strength_pts INTEGER DEFAULT 0,
  dexterity_pts INTEGER DEFAULT 0,
  constitution_pts INTEGER DEFAULT 0,
  magic_pts INTEGER DEFAULT 0,
  remaining_pts INTEGER DEFAULT 0,
  weapon_slot INTEGER DEFAULT 0, -- object index (1-based, 0 is empty)
  shield_slot INTEGER DEFAULT 0,
  helmet_slot INTEGER DEFAULT 0,
  armor_slot INTEGER DEFAULT 0,
  guild TEXT DEFAULT '',
  guild_rank INTEGER DEFAULT 0,
  guild_rank_title INTEGER DEFAULT '',
  -- play stats
  stat_played INTEGER DEFAULT 0, -- seconds
  stat_traveled REAL DEFAULT 0, -- meters (cells)
  stat_mob_kills INTEGER DEFAULT 0,
  stat_deaths INTEGER DEFAULT 0
);

CREATE TABLE users_vars(
  id INTEGER,
  user_id INTEGER,
  value INTEGER,
  PRIMARY KEY(id, user_id),
  FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE TABLE users_bool_vars(
  id INTEGER,
  user_id INTEGER,
  value INTEGER,
  PRIMARY KEY(id, user_id),
  FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE TABLE server_vars(
  id TEXT PRIMARY KEY,
  value TEXT
);

CREATE TABLE users_items(
  id INTEGER,
  user_id INTEGER,
  inventory INTEGER,
  amount INTEGER UNSIGNED,
  PRIMARY KEY(id, user_id, inventory),
  FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE TABLE skins(
  name TEXT PRIMARY KEY,
  free INTEGER
);

CREATE TABLE users_skins(
  user_id INTEGER,
  name TEXT,
  type TEXT, -- #: access, M: module, @: guild sharing
  quantity INTEGER,
  start_quantity INTEGER,
  shared_by INTEGER,
  FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE,
  FOREIGN KEY(shared_by) REFERENCES users(id) ON DELETE CASCADE
);

CREATE INDEX users_skins_index ON users_skins(user_id);
