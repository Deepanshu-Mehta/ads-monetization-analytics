-- Q3 · Which inventory is overpriced?
-- View:    Buyer (iPinYou). A segment's value index = its share of clicks ÷ its share of spend.
--          Below 1, the segment costs more than it delivers; above 1, it is underpriced.
-- Metrics: spend, impressions, clicks, CPM, CTR (Wilson 95%), eCPC, spend share, click share.
--          Segments are slot size × visibility, the cut that keeps 95% of won impressions above
--          the 30-click rule (data profile; D03). Shares are taken over all won inventory before
--          the rule, so they add to 100%; smaller segments pool into "Other (low volume)".
-- Answer:  300x250 below the fold is the most overpriced inventory: 9.0% of spend for 3.2% of
--          clicks (value index 0.36; eCPC 307 fen, 2.8x the 109-fen average). The same size above
--          the fold returns 14.2% of clicks on 8.7% of spend (index 1.63, eCPC 67 fen): the market
--          charges 38% more CPM for above-the-fold placement, but it delivers 6.3x the CTR.
-- Decision it informs: inventory pricing, and where a buyer should shift spend.

WITH seg AS (
    SELECT size_label, visibility_label,
           count(*)                             AS impressions,
           count(*) FILTER (WHERE clicked)      AS clicks,
           sum(pay_price) / 1000.0              AS spend_fen
    FROM fact_auction
    WHERE won
    GROUP BY ALL
),
shares AS (
    SELECT *,
           spend_fen / sum(spend_fen) OVER ()        AS spend_share,
           clicks / sum(clicks) OVER ()              AS click_share,
           clicks >= min_rate_events()               AS reportable
    FROM seg
),
pooled AS (
    SELECT
        CASE WHEN reportable THEN size_label || ' · ' || visibility_label ELSE 'Other (low volume)' END AS segment,
        sum(impressions)::BIGINT    AS impressions,
        sum(clicks)::BIGINT         AS clicks,
        sum(spend_fen)              AS spend_fen,
        sum(spend_share)            AS spend_share,
        sum(click_share)            AS click_share,
        count(*)                    AS segments_pooled
    FROM shares
    GROUP BY 1
)
SELECT
    segment,
    impressions, clicks,
    round(spend_fen / 100, 0)                             AS spend_rmb,
    round(cpm(spend_fen, impressions), 2)                 AS cpm_fen,
    round(ctr(clicks, impressions), 6)                    AS ctr,
    round(wilson_low(clicks, impressions), 6)             AS ctr_low,
    round(wilson_high(clicks, impressions), 6)            AS ctr_high,
    round(ecpc(spend_fen, clicks), 1)                     AS ecpc_fen,
    round(spend_share, 4)                                 AS spend_share,
    round(click_share, 4)                                 AS click_share,
    round(click_share / spend_share, 2)                   AS value_index,
    segments_pooled
FROM pooled
ORDER BY segment = 'Other (low volume)', spend_fen DESC;
