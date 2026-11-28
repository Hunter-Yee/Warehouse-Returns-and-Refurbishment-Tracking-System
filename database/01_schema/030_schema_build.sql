-- In-database version stamp: which release built this schema, from which commit, and the
-- exact checksum of every script that ran. build/build_database.sh writes one SchemaBuild row
-- and one SchemaBuildScript row per manifest file after all scripts succeed, so the database
-- itself answers "what version am I?" without the repository or the build log.
-- Not one of the 15 business tables; append-only like the audit tables.

CREATE TABLE SchemaBuild (
 BuildID INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
 ReleaseTag VARCHAR(64) NOT NULL,
 CommitSHA CHAR(40) NOT NULL,
 ManifestSHA256 CHAR(64) NOT NULL,
 ScriptCount SMALLINT UNSIGNED NOT NULL,
 MySQLVersion VARCHAR(64) NOT NULL,
 BuiltBy VARCHAR(100) NOT NULL,
 BuiltAt DATETIME(6) NOT NULL,
 CONSTRAINT ck_schemabuild_sha CHECK (CHAR_LENGTH(CommitSHA) = 40 AND CHAR_LENGTH(ManifestSHA256) = 64)
) ENGINE=InnoDB;

CREATE TABLE SchemaBuildScript (
 BuildID INT UNSIGNED NOT NULL,
 RunOrder SMALLINT UNSIGNED NOT NULL,
 ScriptPath VARCHAR(255) NOT NULL,
 ScriptSHA256 CHAR(64) NOT NULL,
 PRIMARY KEY (BuildID, RunOrder),
 CONSTRAINT uq_schemabuildscript_path UNIQUE (BuildID, ScriptPath),
 CONSTRAINT fk_schemabuildscript_build FOREIGN KEY (BuildID) REFERENCES SchemaBuild(BuildID) ON DELETE RESTRICT
) ENGINE=InnoDB;
