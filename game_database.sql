CREATE DATABASE gamedatabase;
USE gamedatabase;

CREATE TABLE Users (
    user_Id INT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(50) UNIQUE NOT NULL,
    rating INT DEFAULT 1500,
    wins INT DEFAULT 0,
    losses INT DEFAULT 0
);

CREATE TABLE Avatars (
    char_Id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(50) UNIQUE NOT NULL,
    base_hp INT NOT NULL,
    element_type VARCHAR(50) NOT NULL,
    power_rating INT NOT NULL
);

CREATE TABLE Abilities (
    ability_Id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(50) UNIQUE NOT NULL,
    power INT NOT NULL,
    element_type VARCHAR(50) NOT NULL
);

CREATE TABLE Active_Matches (
    match_Id INT AUTO_INCREMENT PRIMARY KEY,
    player1_Id INT,
    player2_Id INT,
    status VARCHAR(50) DEFAULT 'ACTIVE',
    winner_Id INT,
    started_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (player1_Id) REFERENCES Users(user_Id),
    FOREIGN KEY (player2_Id) REFERENCES Users(user_Id),
    FOREIGN KEY (winner_Id) REFERENCES Users(user_Id)
);

CREATE TABLE Combat_Units (
    unit_Id INT AUTO_INCREMENT PRIMARY KEY,
    match_Id INT,
    player_Id INT,
    avatar_Id INT,
    current_hp INT NOT NULL,
    FOREIGN KEY (match_Id) REFERENCES Active_Matches(match_Id),
    FOREIGN KEY (player_Id) REFERENCES Users(user_Id),
    FOREIGN KEY (avatar_Id) REFERENCES Avatars(char_Id)
);

CREATE TABLE combat_log (
    log_Id INT AUTO_INCREMENT PRIMARY KEY,
    match_Id INT,
    attacker_Id INT,
    defender_Id INT,
    ability_Id INT,
    damage INT,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (match_Id) REFERENCES Active_Matches(match_Id),
    FOREIGN KEY (attacker_Id) REFERENCES Combat_Units(unit_Id),
    FOREIGN KEY (defender_Id) REFERENCES Combat_Units(unit_Id),
    FOREIGN KEY (ability_Id) REFERENCES Abilities(ability_Id)
);

CREATE TABLE Match_History (
    history_id INT AUTO_INCREMENT PRIMARY KEY,
    match_id INT NOT NULL,
    player1_id INT NOT NULL,
    player2_id INT NOT NULL,
    player1_avatar_id INT NOT NULL,
    player2_avatar_id INT NOT NULL,
    winner_id INT NOT NULL,
    player1_rating_change INT,
    player2_rating_change INT,
    completed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (match_id) REFERENCES Active_Matches(match_id),
    FOREIGN KEY (player1_id) REFERENCES Users(user_id),
    FOREIGN KEY (player2_id) REFERENCES Users(user_id),
    FOREIGN KEY (winner_id) REFERENCES Users(user_id),
    FOREIGN KEY (player1_avatar_id) REFERENCES Avatars(char_id),
    FOREIGN KEY (player2_avatar_id) REFERENCES Avatars(char_id)
);

DELIMITER //

CREATE PROCEDURE initialize_game_data()
BEGIN
    INSERT INTO Avatars (name, base_hp, element_type, power_rating) VALUES
    ('Warrior', 100, 'Physical', 80),
    ('Mage', 80, 'Magic', 90),
    ('Archer', 85, 'Physical', 85),
    ('Healer', 70, 'Magic', 75);

    INSERT INTO Abilities (name, power, element_type) VALUES
    ('Strike', 50, 'Physical'),
    ('Fireball', 60, 'Magic'),
    ('Arrow Shot', 45, 'Physical'),
    ('Heal', 40, 'Magic');
END //

CREATE TRIGGER after_match_complete
AFTER UPDATE ON Active_Matches
FOR EACH ROW
BEGIN
    DECLARE rating_change INT DEFAULT 45;
    
    -- Only proceed if the match status changed to COMPLETED
    IF NEW.status = 'COMPLETED' AND OLD.status = 'ACTIVE' THEN
        -- Update ratings based on winner
        IF NEW.winner_id = NEW.player1_id THEN
            -- Player 1 wins
            UPDATE Users 
            SET rating = rating + rating_change 
            WHERE user_id = NEW.player1_id;
            
            UPDATE Users 
            SET rating = rating - rating_change 
            WHERE user_id = NEW.player2_id;
        ELSE
            -- Player 2 wins
            UPDATE Users 
            SET rating = rating - rating_change 
            WHERE user_id = NEW.player1_id;
            
            UPDATE Users 
            SET rating = rating + rating_change 
            WHERE user_id = NEW.player2_id;
        END IF;
        
        -- Record match in history
        INSERT INTO Match_History (
            match_id,
            player1_id,
            player2_id,
            player1_avatar_id,
            player2_avatar_id,
            winner_id,
            player1_rating_change,
            player2_rating_change
        )
        SELECT 
            NEW.match_id,
            NEW.player1_id,
            NEW.player2_id,
            cu1.avatar_id,
            cu2.avatar_id,
            NEW.winner_id,
            CASE WHEN NEW.winner_id = NEW.player1_id THEN rating_change ELSE -rating_change END,
            CASE WHEN NEW.winner_id = NEW.player2_id THEN rating_change ELSE -rating_change END
        FROM Combat_Units cu1
        JOIN Combat_Units cu2 ON cu1.match_id = cu2.match_id
        WHERE cu1.match_id = NEW.match_id
        AND cu1.player_id = NEW.player1_id
        AND cu2.player_id = NEW.player2_id;
    END IF;
END //

CREATE PROCEDURE start_match(
    IN player1_Id INT, 
    IN player2_Id INT,
    IN player1_avatar_id INT,
    IN player2_avatar_id INT,
    OUT new_match_id INT
)
BEGIN
    -- Create the match
    INSERT INTO Active_Matches(player1_Id, player2_Id)
    VALUES(player1_Id, player2_Id);
    
    SET new_match_id = LAST_INSERT_ID();
    -- Create combat units for both players
    INSERT INTO Combat_Units(match_Id, player_Id, avatar_Id, current_hp)
    SELECT 
        new_match_id,
        player1_Id,
        player1_avatar_id,
        (SELECT base_hp FROM Avatars WHERE char_Id = player1_avatar_id);
        
    INSERT INTO Combat_Units(match_Id, player_Id, avatar_Id, current_hp)
    SELECT 
        new_match_id,
        player2_Id,
        player2_avatar_id,
        (SELECT base_hp FROM Avatars WHERE char_Id = player2_avatar_id);
END //

CREATE PROCEDURE perform_attack(
    IN p_match_Id INT,
    IN p_attacker_avatar_id INT,
    IN p_ability_Id INT
)
BEGIN
    DECLARE damage INT;
    DECLARE defender_avatar_id INT;
    DECLARE attacker_player_id INT;

    -- Get damage value
    SELECT power INTO damage
    FROM Abilities 
    WHERE ability_Id = p_ability_Id;
    
    -- Get defender avatar_Id
    SELECT avatar_Id INTO defender_avatar_id
    FROM Combat_Units
    WHERE match_Id = p_match_Id
    AND avatar_Id != p_attacker_avatar_id
    LIMIT 1;
    
    -- Update defender HP
    UPDATE Combat_Units 
    SET current_hp = GREATEST(0, current_hp - damage)
    WHERE match_Id = p_match_Id
    AND avatar_Id = defender_avatar_id;
    
    -- Check win condition
    IF (SELECT current_hp FROM Combat_Units 
        WHERE match_Id = p_match_Id 
        AND avatar_Id = defender_avatar_id) = 0 
    THEN
        -- Get attacker's player ID
        SELECT player_Id INTO attacker_player_id 
        FROM Combat_Units 
        WHERE match_Id = p_match_Id
        AND avatar_Id = p_attacker_avatar_id;
        
        -- Update match status
        UPDATE Active_Matches 
        SET status = 'COMPLETED', 
            winner_Id = attacker_player_id
        WHERE match_Id = p_match_Id;
        
        -- Update player stats
        UPDATE Users 
        SET wins = wins + 1 
        WHERE user_Id = attacker_player_id;
        
        UPDATE Users 
        SET losses = losses + 1 
        WHERE user_Id = (
            SELECT player_Id 
            FROM Combat_Units 
            WHERE match_Id = p_match_Id
            AND avatar_Id = defender_avatar_id
        );
    END IF;
    
    -- Log the attack
    INSERT INTO combat_log (match_Id, attacker_Id, defender_Id, ability_Id, damage)
    VALUES (p_match_id, p_attacker_avatar_id, defender_avatar_id, p_ability_Id, damage);
END //

DELIMITER ;

-- views 
CREATE VIEW vw_player_stats AS
SELECT 
    u.user_id,
    u.username,
    u.rating,
    u.wins,
    u.losses,
    (u.wins + u.losses) as total_games,
    (
        SELECT name 
        FROM Avatars a
        JOIN Combat_Units cu ON a.char_id = cu.avatar_id
        WHERE cu.player_id = u.user_id
        GROUP BY name
        ORDER BY COUNT(*) DESC
        LIMIT 1
    ) as most_played_avatar
FROM Users u;

CREATE VIEW vw_active_matches AS
SELECT 
    m.match_id,
    u1.username as player1,
    u2.username as player2,
    a1.name as player1_avatar,
    a2.name as player2_avatar,
    cu1.current_hp as player1_hp,
    cu2.current_hp as player2_hp,
    m.status
FROM Active_Matches m
JOIN Users u1 ON m.player1_id = u1.user_id
JOIN Users u2 ON m.player2_id = u2.user_id
JOIN Combat_Units cu1 ON cu1.match_id = m.match_id AND cu1.player_id = u1.user_id
JOIN Combat_Units cu2 ON cu2.match_id = m.match_id AND cu2.player_id = u2.user_id
JOIN Avatars a1 ON cu1.avatar_id = a1.char_id
JOIN Avatars a2 ON cu2.avatar_id = a2.char_id;

CREATE VIEW vw_match_history AS
SELECT 
    mh.match_id,
    u1.username as player1,
    u2.username as player2,
    CASE WHEN mh.winner_id = mh.player1_id THEN u1.username ELSE u2.username END as winner,
    mh.player1_rating_change,
    mh.player2_rating_change,
    mh.completed_at
FROM Match_History mh
JOIN Users u1 ON mh.player1_id = u1.user_id
JOIN Users u2 ON mh.player2_id = u2.user_id;

-- View match status
SELECT 
    m.match_Id,
    u1.username as player1,
    a1.name as player1_avatar,
    cu1.current_hp as player1_hp,
    u2.username as player2,
    a2.name as player2_avatar,
    cu2.current_hp as player2_hp,
    m.status,
    CASE 
        WHEN m.winner_Id = u1.user_Id THEN u1.username
        WHEN m.winner_Id = u2.user_Id THEN u2.username
        ELSE NULL
    END as winner
FROM Active_Matches m
JOIN Users u1 ON m.player1_Id = u1.user_Id
JOIN Users u2 ON m.player2_Id = u2.user_Id
JOIN Combat_Units cu1 ON cu1.match_Id = m.match_Id AND cu1.player_Id = u1.user_Id
JOIN Combat_Units cu2 ON cu2.match_Id = m.match_Id AND cu2.player_Id = u2.user_Id
JOIN Avatars a1 ON cu1.avatar_Id = a1.char_Id
JOIN Avatars a2 ON cu2.avatar_Id = a2.char_Id
WHERE m.match_Id = @match_id;

-- Test the system
CALL initialize_game_data();

INSERT INTO Users (username) VALUES 
('DragonSlayer'),
('MageSupreme'),
('ArcherQueen'),
('WarriorKing'),
('HealerPro'),
('BattleMaster');

-- Store player IDs in variables for easier reference
SET @player1 = (SELECT user_Id FROM Users WHERE username = 'DragonSlayer');
SET @player2 = (SELECT user_Id FROM Users WHERE username = 'MageSupreme');
SET @player3 = (SELECT user_Id FROM Users WHERE username = 'ArcherQueen');
SET @player4 = (SELECT user_Id FROM Users WHERE username = 'WarriorKing');
SET @player5 = (SELECT user_Id FROM Users WHERE username = 'HealerPro');
SET @player6 = (SELECT user_Id FROM Users WHERE username = 'BattleMaster');

-- Simulate several matches
-- Match 1: DragonSlayer vs MageSupreme
CALL start_match(@player1, @player2, 1, 2, @match_id);
CALL perform_attack(@match_id, 1, 1); -- Warrior Strike
CALL perform_attack(@match_id, 2, 2); -- Mage Fireball
CALL perform_attack(@match_id, 1, 1); -- Warrior Strike

-- Match 2: ArcherQueen vs WarriorKing
CALL start_match(@player3, @player4, 3, 1, @match_id);
CALL perform_attack(@match_id, 3, 3); -- Archer Shot
CALL perform_attack(@match_id, 1, 1); -- Warrior Strike
CALL perform_attack(@match_id, 3, 3); -- Archer Shot
CALL perform_attack(@match_id, 3, 3); -- Archer Shot

-- Match 3: HealerPro vs BattleMaster
CALL start_match(@player5, @player6, 4, 1, @match_id);
CALL perform_attack(@match_id, 1, 1); -- Warrior Strike
CALL perform_attack(@match_id, 4, 4); -- Healer Heal
CALL perform_attack(@match_id, 1, 1); -- Warrior Strike
CALL perform_attack(@match_id, 1, 1); -- Warrior Strike

-- Match 4: DragonSlayer vs ArcherQueen
CALL start_match(@player1, @player3, 1, 3, @match_id);
CALL perform_attack(@match_id, 3, 3); -- Archer Shot
CALL perform_attack(@match_id, 1, 1); -- Warrior Strike
CALL perform_attack(@match_id, 3, 3); -- Archer Shot

-- Match 5: MageSupreme vs HealerPro
CALL start_match(@player2, @player5, 2, 4, @match_id);
CALL perform_attack(@match_id, 2, 2); -- Mage Fireball
CALL perform_attack(@match_id, 4, 4); -- Healer Heal
CALL perform_attack(@match_id, 2, 2); -- Mage Fireball
CALL perform_attack(@match_id, 2, 2); -- Mage Fireball

-- Perform an attack with Fireball
SELECT @new_match_id as match_id, @attacker_unit_id as attacker_unit_id;
CALL perform_attack(@new_match_id, @attacker_unit_id, 2);
CALL perform_attack(@new_match_id, @attacker_unit_id, 2);



Select * from vw_player_stats;
Select * from vw_active_matches ;
Select * from vw_match_history;
Select * from Users;
-- drop database gamedatabase;