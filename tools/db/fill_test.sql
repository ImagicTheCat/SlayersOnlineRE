INSERT INTO users(id, pseudo, password) VALUES(1, 'test', UNHEX(SHA2(CONCAT('<server_salt>test', UNHEX(SHA2('<client_salt>testtest',512))),512)));
