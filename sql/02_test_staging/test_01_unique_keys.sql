-- Gate 1 · Unique keys
-- Every staging table holds one row per stated key. Duplicate impression, click and conversion
-- events are collapsed in staging (D27), so any duplicate here is a staging bug.
-- Passes when it returns 0 rows.
SELECT 'stg_ipy_bids' AS table_name, bid_id AS key, count(*) AS row_count FROM stg_ipy_bids GROUP BY bid_id HAVING count(*) > 1
UNION ALL
SELECT 'stg_ipy_imps', bid_id, count(*) FROM stg_ipy_imps GROUP BY bid_id HAVING count(*) > 1
UNION ALL
SELECT 'stg_ipy_clicks', bid_id, count(*) FROM stg_ipy_clicks GROUP BY bid_id HAVING count(*) > 1
UNION ALL
SELECT 'stg_ipy_convs', bid_id, count(*) FROM stg_ipy_convs GROUP BY bid_id HAVING count(*) > 1
UNION ALL
SELECT 'stg_criteo_imps', CAST(imp_id AS VARCHAR), count(*) FROM stg_criteo_imps GROUP BY imp_id HAVING count(*) > 1;
