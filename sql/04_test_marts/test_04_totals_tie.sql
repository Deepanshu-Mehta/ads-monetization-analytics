-- Gate 2 · Totals tie across layers
-- Aggregates must add back up to their sources, so no row is dropped or double counted:
-- hourly mart vs fact_auction, campaign-day mart vs Criteo staging and fact_conversion.
-- Revenue is compared with a small tolerance for floating-point summation order.
-- Passes when it returns 0 rows.
WITH checks(check_name, mart_value, source_value) AS (
    SELECT 'iPinYou bids',        (SELECT sum(bids)        FROM mart_ipy_hourly), (SELECT count(*) FROM fact_auction)
    UNION ALL SELECT 'iPinYou impressions', (SELECT sum(impressions) FROM mart_ipy_hourly), (SELECT count(*) FILTER (WHERE won) FROM fact_auction)
    UNION ALL SELECT 'iPinYou clicks',      (SELECT sum(clicks)      FROM mart_ipy_hourly), (SELECT count(*) FILTER (WHERE clicked) FROM fact_auction)
    UNION ALL SELECT 'iPinYou pay_price',   (SELECT sum(pay_price_sum) FROM mart_ipy_hourly), (SELECT sum(pay_price) FROM fact_auction)
    UNION ALL SELECT 'Criteo impressions',  (SELECT sum(impressions) FROM mart_campaign_day), (SELECT count(*) FROM stg_criteo_imps)
    UNION ALL SELECT 'Criteo clicks',       (SELECT sum(clicks)      FROM mart_campaign_day), (SELECT sum(click) FROM stg_criteo_imps)
    UNION ALL SELECT 'Criteo media cost',   (SELECT sum(media_cost_idx) FROM mart_campaign_day), (SELECT sum(cost) FROM stg_criteo_imps)
    UNION ALL SELECT 'Criteo conversions',  (SELECT sum(conversions) FROM mart_campaign_day), (SELECT count(*) FROM fact_conversion)
    UNION ALL SELECT 'Criteo revenue',      (SELECT sum(revenue_idx) FROM mart_campaign_day),
                                            (SELECT sum(cpo_idx) FILTER (WHERE attributed = 1) FROM fact_conversion)
)
SELECT * FROM checks
WHERE abs(mart_value - source_value) > 1e-6 * greatest(abs(source_value), 1);
