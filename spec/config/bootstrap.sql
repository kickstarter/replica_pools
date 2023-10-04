-- Create MySQL db & user for running specs
CREATE DATABASE IF NOT EXISTS test_db;
CREATE USER 'read_only'@'%' IDENTIFIED BY 'readme';
GRANT SELECT ON test_db.* TO 'read_only'@'%';
