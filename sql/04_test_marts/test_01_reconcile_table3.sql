-- Gate 2 · Reconciliation to the published benchmark
-- Rebuilds the iPinYou paper's Table 3 (Season 2 training) from fact_auction, using the paper's
-- conventions (D29): impressions, clicks and conversions count impression log rows, duplicates
-- included. Counts must match exactly; money and rates within 0.1%, or within half a unit of
-- the precision the paper publishes, whichever is larger.
-- Passes when it returns 0 rows.
WITH ours AS (
    SELECT
        advertiser_id,
        count(*)                                                   AS bids,
        sum(impression_events)                                     AS imps,
        sum(impression_events) FILTER (WHERE clicked)              AS clicks,
        coalesce(sum(impression_events) FILTER (WHERE converted), 0) AS convs,
        sum(pay_price_events_sum) / 1000.0                         AS cost
    FROM fact_auction
    GROUP BY advertiser_id
),
metrics AS (
    SELECT advertiser_id, metric, value
    FROM (
        SELECT advertiser_id,
               CAST(bids AS DOUBLE) AS bids, CAST(imps AS DOUBLE) AS imps,
               CAST(clicks AS DOUBLE) AS clicks, CAST(convs AS DOUBLE) AS convs, cost,
               100.0 * imps / bids                AS win_ratio,
               100.0 * clicks / imps              AS ctr,
               100.0 * convs / clicks             AS cvr,
               1000.0 * cost / imps               AS cpm,
               cost / clicks                      AS ecpc
        FROM ours
    )
    UNPIVOT (value FOR metric IN (bids, imps, clicks, convs, cost, win_ratio, ctr, cvr, cpm, ecpc))
)
SELECT r.advertiser_id, r.metric, r.paper_value, round(m.value, 4) AS our_value
FROM ref_ipinyou_table3 r
LEFT JOIN metrics m USING (advertiser_id, metric)
WHERE m.value IS NULL
   OR (r.metric IN ('bids', 'imps', 'clicks', 'convs') AND m.value <> r.paper_value)
   OR abs(m.value - r.paper_value) > greatest(0.001 * abs(r.paper_value), 0.5 * pow(10, -r.decimals));
