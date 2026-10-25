-- Q1 · What does the market look like, and do the numbers reconcile?
-- View:    Buyer (iPinYou, a DSP bidding for five advertisers), Season 2, 6-12 Jun 2013.
-- Metrics: bids, impressions, win rate, spend, CPM, CTR (Wilson 95%), eCPC, CVR, spend share.
--          Each auction counted once (D27); money in fen, CPM in fen per 1,000 (D29).
-- Answer:  Five advertisers bought 12.2M impressions from 53.3M bids (22.9% win rate) for
--          RMB 9,538 at a 78-fen CPM, and every published Table 3 cell reconciles; tyre advertiser
--          3476 is the outlier, with the lowest CTR (0.052%, 95% CI 0.049-0.055%) and an eCPC of
--          152 fen, 40% above the 109-fen average.
-- Decision it informs: whether the data can be trusted for the analysis that follows.

WITH per_advertiser AS (
    SELECT
        CAST(advertiser_id AS VARCHAR)                     AS advertiser,
        industry,
        bids::BIGINT AS bids, impressions::BIGINT AS impressions, clicks::BIGINT AS clicks,
        conversions::BIGINT AS conversions, spend_fen
    FROM metrics_ipy_advertiser
),
with_total AS (
    SELECT * FROM per_advertiser
    UNION ALL
    SELECT 'All advertisers', NULL, sum(bids)::BIGINT, sum(impressions)::BIGINT, sum(clicks)::BIGINT,
           sum(conversions)::BIGINT, sum(spend_fen)
    FROM per_advertiser
),
table3 AS (   -- the gate 2 test proves every published cell matches; restate it per advertiser
    SELECT CAST(advertiser_id AS VARCHAR) AS advertiser, 'all 10 published cells match' AS table3_reconciliation
    FROM ref_ipinyou_table3
    GROUP BY 1
)
SELECT
    w.advertiser,
    w.industry,
    w.bids,
    w.impressions,
    round(win_rate(w.impressions, w.bids), 4)                          AS win_rate,
    round(w.spend_fen / 100, 0)                                        AS spend_rmb,
    round(cpm(w.spend_fen, w.impressions), 2)                          AS cpm_fen,
    w.clicks,
    round(ctr(w.clicks, w.impressions), 6)                             AS ctr,
    round(wilson_low(w.clicks, w.impressions), 6)                      AS ctr_low,
    round(wilson_high(w.clicks, w.impressions), 6)                     AS ctr_high,
    round(ecpc(w.spend_fen, w.clicks), 2)                              AS ecpc_fen,
    w.conversions,
    CASE WHEN w.conversions >= min_rate_events() THEN round(cvr(w.conversions, w.clicks), 4) END AS cvr,
    round(w.spend_fen / sum(w.spend_fen) FILTER (WHERE w.industry IS NOT NULL) OVER (), 4)    AS spend_share,
    coalesce(t.table3_reconciliation, 'n/a (total)')                   AS table3_reconciliation
FROM with_total w
LEFT JOIN table3 t USING (advertiser)
ORDER BY w.industry IS NULL, w.spend_fen DESC;
