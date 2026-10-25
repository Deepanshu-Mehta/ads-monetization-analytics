-- Gate 1 · Date coverage
-- iPinYou: Season 2 training, 6-12 Jun 2013, every log within the window and all 7 days present.
-- Criteo: impression days 0-30 (day 30 ends at 22:00, D06) and no conversion before its impression.
-- Passes when it returns 0 rows.
WITH ipy AS (
    SELECT 'bids' AS log, min(ts) AS first_ts, max(ts) AS last_ts, count(DISTINCT date) AS days FROM stg_ipy_bids
    UNION ALL SELECT 'impressions', min(ts), max(ts), count(DISTINCT ts::DATE) FROM stg_ipy_imps
    UNION ALL SELECT 'clicks', min(first_click_ts), max(first_click_ts), count(DISTINCT first_click_ts::DATE) FROM stg_ipy_clicks
    UNION ALL SELECT 'conversions', min(first_conversion_ts), max(first_conversion_ts), NULL FROM stg_ipy_convs
)
SELECT 'iPinYou ' || log || ' outside 6-12 Jun 2013 or missing days' AS check_name,
       first_ts::VARCHAR || ' .. ' || last_ts::VARCHAR AS value
FROM ipy
WHERE first_ts < TIMESTAMP '2013-06-06' OR last_ts >= TIMESTAMP '2013-06-13'
   OR (log IN ('bids', 'impressions', 'clicks') AND days <> 7)
UNION ALL
SELECT 'Criteo impression days outside 0-30 or missing days', min(day)::VARCHAR || ' .. ' || max(day)::VARCHAR
FROM stg_criteo_imps
HAVING min(day) <> 0 OR max(day) <> 30 OR count(DISTINCT day) <> 31
UNION ALL
SELECT 'Criteo conversion before its impression', count(*)::VARCHAR
FROM stg_criteo_imps
WHERE conversion_ts < ts
HAVING count(*) > 0;
