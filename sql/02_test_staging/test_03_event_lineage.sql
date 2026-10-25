-- Gate 1 · Event lineage (orphans)
-- Every impression must come from a bid. Clicks and conversions without an impression row are
-- a known logging gap (D31): 87 clicks and 13 conversions, half of the clicks in the 22:00 hour
-- of 10 June when bid volume jumped fivefold. They are allowed only if they still have a bid
-- and stay within 1.5% of clicked auctions (clicks) or 5% of converted auctions (conversions; 13 of 404).
-- Passes when it returns 0 rows.
WITH counts AS (
    SELECT
        (SELECT count(*) FROM stg_ipy_imps i ANTI JOIN stg_ipy_bids b USING (bid_id))     AS imps_without_bid,
        (SELECT count(*) FROM stg_ipy_clicks c ANTI JOIN stg_ipy_bids b USING (bid_id))   AS clicks_without_bid,
        (SELECT count(*) FROM stg_ipy_convs v ANTI JOIN stg_ipy_bids b USING (bid_id))    AS convs_without_bid,
        (SELECT count(*) FROM stg_ipy_clicks c ANTI JOIN stg_ipy_imps i USING (bid_id))   AS clicks_without_imp,
        (SELECT count(*) FROM stg_ipy_convs v ANTI JOIN stg_ipy_imps i USING (bid_id))    AS convs_without_imp,
        (SELECT count(*) FROM stg_ipy_clicks)                                             AS clicks,
        (SELECT count(*) FROM stg_ipy_convs)                                              AS convs
)
SELECT 'impressions without a bid' AS check_name, imps_without_bid AS value FROM counts WHERE imps_without_bid > 0
UNION ALL SELECT 'clicks without a bid', clicks_without_bid FROM counts WHERE clicks_without_bid > 0
UNION ALL SELECT 'conversions without a bid', convs_without_bid FROM counts WHERE convs_without_bid > 0
UNION ALL SELECT 'clicks without an impression above 1.5%', clicks_without_imp FROM counts WHERE clicks_without_imp > 0.015 * clicks
UNION ALL SELECT 'conversions without an impression above 5%', convs_without_imp FROM counts WHERE convs_without_imp > 0.05 * convs;
