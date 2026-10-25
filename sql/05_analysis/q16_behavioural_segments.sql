-- Q16 · Which kinds of campaigns behave alike?
-- View:    Intermediary (Criteo).
-- Method:  Criteo's category fields (cat1-cat9) are undisclosed, so true category analysis is not
--          possible (D12). Instead, scored campaigns (at least 50 attributed conversions, D17) are
--          banded on three behaviours, each split at its median: CTR (engagement), CVR (post-click
--          conversion) and median conversion lag, the hours from the last impression to the
--          conversion (fast or slow buyers). That gives up to eight behavioural segments, labelled
--          as such; the long tail is shown alongside. For an illustration of real industry
--          differences, see Q1: iPinYou has one advertiser per industry.
-- Metrics: campaigns, revenue and media-cost share, margin %, return on media cost, attribution rate,
--          CTR, CVR and median lag per segment (all sum ÷ sum except the lag, a median of medians).
-- Answer:  Buyer speed separates the economics more than engagement does. The four slow-buyer
--          segments (195 campaigns, median lag about 3 days) earn 67.6% of revenue at 77-80% margins,
--          while fast-buyer campaigns with a high CTR run the thinnest margins (60-67%). Slow buyers
--          are also paid for least often (41-54% attribution, against up to 73% for the fastest), so
--          the most profitable advertisers are the most exposed to the attribution leakage in Q14.
-- Decision it informs: how category and sales teams group advertisers for playbooks and pricing.

WITH lag AS (
    SELECT campaign_id, median((conversion_ts - last_impression_ts) / 3600.0) AS median_lag_hours
    FROM fact_conversion GROUP BY campaign_id
),
banded AS (
    SELECT c.*, l.median_lag_hours,
        c.ctr >= median(c.ctr) OVER ()                           AS high_ctr,
        c.cvr >= median(c.cvr) OVER ()                           AS high_cvr,
        l.median_lag_hours <= median(l.median_lag_hours) OVER () AS fast
    FROM metrics_criteo_campaign c JOIN lag l USING (campaign_id)
    WHERE c.volume_tier = 'scored'
),
labelled AS (
    SELECT *,
        CASE WHEN high_ctr THEN 'high CTR' ELSE 'low CTR' END || ' · ' ||
        CASE WHEN high_cvr THEN 'high CVR' ELSE 'low CVR' END || ' · ' ||
        CASE WHEN fast THEN 'fast buyers' ELSE 'slow buyers' END AS segment
    FROM banded
    UNION ALL
    SELECT c.*, l.median_lag_hours, NULL, NULL, NULL, 'Long tail (not scored)'
    FROM metrics_criteo_campaign c JOIN lag l USING (campaign_id)
    WHERE c.volume_tier = 'long tail'
)
SELECT
    segment,
    count(*)                                                                    AS campaigns,
    round(sum(revenue_idx) / (SELECT sum(revenue_idx) FROM metrics_criteo_campaign), 4)       AS revenue_share,
    round(sum(media_cost_idx) / (SELECT sum(media_cost_idx) FROM metrics_criteo_campaign), 4) AS media_cost_share,
    round(margin_pct(sum(revenue_idx), sum(media_cost_idx)), 4)                 AS margin_pct,
    round(return_on_media_cost(sum(revenue_idx), sum(media_cost_idx)), 2)       AS return_on_media_cost,
    round(attribution_rate(sum(attributed_conversions), sum(conversions)), 4)   AS attribution_rate,
    round(ctr(sum(clicks), sum(impressions)), 4)                                AS ctr,
    round(cvr(sum(conversions), sum(clicks)), 4)                                AS cvr,
    round(median(median_lag_hours), 1)                                          AS median_lag_hours
FROM labelled
GROUP BY segment
ORDER BY segment = 'Long tail (not scored)', revenue_share DESC;
