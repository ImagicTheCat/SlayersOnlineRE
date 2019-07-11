INSERT INTO users(id, pseudo, password) VALUES(1, 'test', UNHEX(SHA2(CONCAT('<server_salt>1test', SHA2('<client_salt>test',512)),512)));
