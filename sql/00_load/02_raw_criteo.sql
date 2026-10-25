-- Raw layer: Criteo Attribution Modeling for Bidding dataset (30 days, one row per impression).
-- View over the Parquet file written by scripts/convert_to_parquet.py; all columns are text.
-- The file has no impression key, so file_row_number (0-based, in the released order,
-- which is sorted by timestamp) becomes the impression id in staging.

CREATE OR REPLACE VIEW raw_criteo AS
SELECT *
FROM read_parquet('data/parquet/criteo/criteo_attribution.parquet', file_row_number = true);
