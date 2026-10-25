-- Q4 · Which exchanges deliver value?
-- View:    Buyer (iPinYou). Value = cost per click (eCPC), so exchanges are ranked within each
--          advertiser from cheapest to dearest click. CPM and CTR show which lever drives it.
-- Metrics: bids, impressions, win rate, CPM, CTR (Wilson 95%), eCPC, share of the advertiser's
--          spend. All 15 advertiser x exchange cells clear the 30-click rule (D03).
-- Answer:  AdX delivers the dearest clicks for all five advertisers (142-fen eCPC overall vs 89 on
--          Tencent, +60%) because its CTR is the lowest (0.054%), yet each advertiser still puts
--          26-34% of spend there. Tencent is cheapest for four of five on the lowest CPM (64 fen),
--          but its 10-17% win rate for three advertisers caps how much spend can move at current bids.
-- Decision it informs: supply allocation (which exchange to shift budget towards).

WITH cells AS (
    SELECT advertiser_id, exchange_id, exchange_name,
           sum(bids) AS bids, sum(impressions) AS impressions, sum(clicks) AS clicks, sum(spend_fen) AS spend_fen
    FROM metrics_ipy_hourly
    GROUP BY ALL
)
SELECT
    advertiser_id,
    exchange_name,
    bids::BIGINT                                                        AS bids,
    impressions::BIGINT                                                 AS impressions,
    clicks::BIGINT                                                      AS clicks,
    round(win_rate(impressions, bids), 4)                               AS win_rate,
    round(cpm(spend_fen, impressions), 2)                               AS cpm_fen,
    round(ctr(clicks, impressions), 6)                                  AS ctr,
    round(wilson_low(clicks, impressions), 6)                           AS ctr_low,
    round(wilson_high(clicks, impressions), 6)                          AS ctr_high,
    round(ecpc(spend_fen, clicks), 1)                                   AS ecpc_fen,
    round(spend_fen / sum(spend_fen) OVER (PARTITION BY advertiser_id), 3) AS share_of_advertiser_spend,
    CASE WHEN clicks >= min_rate_events()
         THEN rank() OVER (PARTITION BY advertiser_id, clicks >= min_rate_events() ORDER BY ecpc(spend_fen, clicks))
    END                                                                 AS ecpc_rank
FROM cells
ORDER BY advertiser_id, ecpc_rank;
