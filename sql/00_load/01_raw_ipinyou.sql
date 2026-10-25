-- Raw layer: iPinYou Season 2 (training 6-12 Jun 2013 + leaderboard test set).
-- Views over the Parquet files written by scripts/convert_to_parquet.py.
-- Every column is text exactly as released; types are applied in sql/01_staging.
-- source_file records which daily log each row came from.

CREATE OR REPLACE VIEW raw_ipy_bid AS
SELECT *, regexp_extract(filename, '(\d{8})\.parquet$', 1) AS source_day
FROM read_parquet('data/parquet/ipinyou/bid/*.parquet', filename = true);

CREATE OR REPLACE VIEW raw_ipy_imp AS
SELECT *, regexp_extract(filename, '(\d{8})\.parquet$', 1) AS source_day
FROM read_parquet('data/parquet/ipinyou/imp/*.parquet', filename = true);

CREATE OR REPLACE VIEW raw_ipy_clk AS
SELECT *, regexp_extract(filename, '(\d{8})\.parquet$', 1) AS source_day
FROM read_parquet('data/parquet/ipinyou/clk/*.parquet', filename = true);

CREATE OR REPLACE VIEW raw_ipy_conv AS
SELECT *, regexp_extract(filename, '(\d{8})\.parquet$', 1) AS source_day
FROM read_parquet('data/parquet/ipinyou/conv/*.parquet', filename = true);

CREATE OR REPLACE VIEW raw_ipy_test AS
SELECT * FROM read_parquet('data/parquet/ipinyou/test/*.parquet');

CREATE OR REPLACE VIEW raw_ipy_region AS
SELECT * FROM read_parquet('data/parquet/ipinyou/lookup/region.parquet');

CREATE OR REPLACE VIEW raw_ipy_city AS
SELECT * FROM read_parquet('data/parquet/ipinyou/lookup/city.parquet');
