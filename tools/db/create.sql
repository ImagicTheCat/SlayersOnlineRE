CREATE TABLE users(
  id INTEGER UNSIGNED AUTO_INCREMENT,
  pseudo VARCHAR(50) UNIQUE,
  password BINARY(64),
  config BLOB,
  state BLOB,
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
