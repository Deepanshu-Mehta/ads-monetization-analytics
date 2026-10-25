-- Gate 1 · Criteo attribution consistency
-- Within one conversion and campaign, every impression row should carry the same attribution
-- flag. 26 of 438,679 pairs (0.006%) do not; fact_conversion treats a pair as attributed if any
-- row says so (D32). The test fails if the share grows beyond 0.01%.
-- Passes when it returns 0 rows.
WITH pairs AS (
    SELECT conversion_id, campaign_id, count(DISTINCT attribution) AS attribution_values
    FROM stg_criteo_imps
    WHERE conversion = 1
    GROUP BY ALL
)
SELECT 'conversion x campaign pairs with mixed attribution above 0.01%' AS check_name,
       count(*) FILTER (WHERE attribution_values > 1) AS value
FROM pairs
HAVING count(*) FILTER (WHERE attribution_values > 1) > 0.0001 * count(*);
