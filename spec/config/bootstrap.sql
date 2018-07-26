-- Create MySQL db & user for running specs
create database IF NOT EXISTS test_db;
grant select on test_db.* to 'read_only' identified by 'readme';
