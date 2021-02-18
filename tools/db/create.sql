CREATE TABLE users(
  id INTEGER UNSIGNED AUTO_INCREMENT,
  pseudo VARCHAR(50) UNIQUE,
  password BINARY(64),
  rank TINYINT UNSIGNED, -- user rank (permissions); 0: server, 10: normal player
  ban_timestamp INTEGER, -- ban timestamp (end)
  config BLOB, -- player config (msgpack)
  state BLOB, -- player state (msgpack)
  class TINYINT UNSIGNED, -- class index (1-based)
  level TINYINT UNSIGNED,
  alignment TINYINT UNSIGNED,
  reputation INTEGER UNSIGNED,
  gold BIGINT UNSIGNED,
  chest_gold BIGINT UNSIGNED,
  xp BIGINT UNSIGNED,
  strength_pts INTEGER UNSIGNED,
  dexterity_pts INTEGER UNSIGNED,
  constitution_pts INTEGER UNSIGNED,
  magic_pts INTEGER UNSIGNED,
  remaining_pts INTEGER UNSIGNED,
  weapon_slot INTEGER UNSIGNED, -- object index (1-based, 0 is empty)
  shield_slot INTEGER UNSIGNED,
  helmet_slot INTEGER UNSIGNED,
  armor_slot INTEGER UNSIGNED,
  guild VARCHAR(100),
  guild_rank TINYINT UNSIGNED,
  guild_rank_title VARCHAR(100),
  CONSTRAINT pk_users PRIMARY KEY(id)
);

CREATE TABLE users_vars(
  id INTEGER UNSIGNED,
  user_id INTEGER UNSIGNED,
  value INTEGER,
  CONSTRAINT pk_users_int_vars PRIMARY KEY(id, user_id),
  CONSTRAINT fk_users_int_vars_users FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE TABLE users_bool_vars(
  id INTEGER UNSIGNED,
  user_id INTEGER UNSIGNED,
  value TINYINT,
  CONSTRAINT pk_users_bool_vars PRIMARY KEY(id, user_id),
  CONSTRAINT fk_users_bool_vars_users FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE TABLE server_vars(
  id VARCHAR(200),
  value TEXT,
  CONSTRAINT pk_server_vars PRIMARY KEY(id)
);

CREATE TABLE users_items(
  id INTEGER UNSIGNED,
  user_id INTEGER UNSIGNED,
  inventory INTEGER UNSIGNED,
  amount INTEGER UNSIGNED,
  CONSTRAINT pk_users_items PRIMARY KEY(id, user_id, inventory),
  CONSTRAINT fk_users_items_users FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
);
