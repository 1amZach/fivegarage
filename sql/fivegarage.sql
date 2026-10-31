-- fivegarage makes this table itself on start. Run it by hand only if your
-- database user can't create tables.

CREATE TABLE IF NOT EXISTS `fivegarage` (
    `plate` VARCHAR(12) NOT NULL,
    `garage` VARCHAR(50) NULL,
    `state` TINYINT NOT NULL DEFAULT 1,
    `fee` INT UNSIGNED NOT NULL DEFAULT 0,
    `reason` VARCHAR(120) NULL,
    `fuel` FLOAT NULL,
    `engine` FLOAT NULL,
    `body` FLOAT NULL,
    `updated` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`plate`),
    KEY `garage_state` (`garage`, `state`)
);
