-- Drops the legacy_rate column. Irreversible: back up the rates table first.
ALTER TABLE rates DROP COLUMN legacy_rate;
