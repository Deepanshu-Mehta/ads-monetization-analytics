-- Q11 · Which campaigns should we scale, fix, grow or review?
-- View:    Intermediary (Criteo); each campaign stands in for an advertiser.
-- Method:  Campaigns with at least 50 attributed conversions are scored (D17); the rest form the
--          long tail. Scored campaigns are split at the median of volume (media cost) and of
--          margin % over the whole period (D36):
--              Scale  = high volume, high margin    Fix    = high volume, low margin
--              Grow   = low volume, high margin     Review = low volume, low margin
--          NTILE(4) quartiles of both axes refine the scorecard within each quadrant.
-- Metrics: media cost, revenue, margin %, return on media cost, CTR, CVR, attribution rate.
-- Output:  one row per campaign (the scorecard); quadrant totals are in the answer.
-- Answer:  Scale (70 campaigns) earns 39.9% of revenue on 26.8% of media cost at an 83.7% margin;
--          Fix (125) earns as much (39.6%) but absorbs 53.3% of media cost at 67.3%. Fix holds 3
--          loss-making accounts, including the #35 revenue campaign (28351001: -3.4% margin, 25%
--          attribution rate), each a re-pricing or attribution conversation. Grow (125) earns 9.2%
--          at the best margin, 86.2%. Across all 675 campaigns, 15 lose money (11 in the long tail).
-- Decision it informs: account prioritisation for category and sales teams.

WITH scored AS (
    SELECT *,
        median(media_cost_idx) OVER () AS median_cost,
        median(margin_pct)     OVER () AS median_margin,
        ntile(4) OVER (ORDER BY media_cost_idx) AS volume_quartile,
        ntile(4) OVER (ORDER BY margin_pct)     AS margin_quartile
    FROM metrics_criteo_campaign
    WHERE volume_tier = 'scored'
)
SELECT
    c.campaign_id,
    CASE
        WHEN s.campaign_id IS NULL                                               THEN 'Long tail'
        WHEN s.media_cost_idx >= s.median_cost AND s.margin_pct >= s.median_margin THEN 'Scale'
        WHEN s.media_cost_idx >= s.median_cost                                    THEN 'Fix'
        WHEN s.margin_pct >= s.median_margin                                      THEN 'Grow'
        ELSE 'Review'
    END                                                                         AS quadrant,
    s.volume_quartile,
    s.margin_quartile,
    c.revenue_rank,
    round(c.media_cost_idx, 3)                                                  AS media_cost_idx,
    round(c.revenue_idx, 3)                                                     AS revenue_idx,
    round(c.revenue_share, 5)                                                   AS revenue_share,
    round(c.margin_pct, 4)                                                      AS margin_pct,
    round(c.return_on_media_cost, 2)                                            AS return_on_media_cost,
    c.margin_idx < 0                                                            AS loss_making,
    round(c.ctr, 4)                                                             AS ctr,
    CASE WHEN c.cvr_reportable THEN round(c.cvr, 4) END                         AS cvr,
    round(c.attribution_rate, 4)                                                AS attribution_rate,
    c.attributed_conversions::BIGINT                                            AS attributed_conversions
FROM metrics_criteo_campaign c
LEFT JOIN scored s USING (campaign_id)
ORDER BY ['Scale', 'Fix', 'Grow', 'Review', 'Long tail'].list_position(quadrant), c.revenue_rank;
