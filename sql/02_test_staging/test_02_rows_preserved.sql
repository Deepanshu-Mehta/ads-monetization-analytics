-- Gate 1 · No rows lost between raw and staging
-- Deduplication may collapse rows but must not lose them: event counts in staging add back up
-- to the raw row counts, and typed tables keep every raw row.
-- Passes when it returns 0 rows.
WITH checks(check_name, raw_rows, staged_rows) AS (
    SELECT 'bids',        (SELECT count(*) FROM raw_ipy_bid),  (SELECT count(*) FROM stg_ipy_bids)
    UNION ALL
    SELECT 'impressions', (SELECT count(*) FROM raw_ipy_imp),  (SELECT sum(impression_events) FROM stg_ipy_imps)
    UNION ALL
    SELECT 'clicks',      (SELECT count(*) FROM raw_ipy_clk),  (SELECT sum(click_events) FROM stg_ipy_clicks)
    UNION ALL
    SELECT 'conversions', (SELECT count(*) FROM raw_ipy_conv), (SELECT sum(conversion_events) FROM stg_ipy_convs)
    UNION ALL
    SELECT 'criteo',      (SELECT count(*) FROM raw_criteo),   (SELECT count(*) FROM stg_criteo_imps)
)
SELECT * FROM checks WHERE raw_rows <> staged_rows;
