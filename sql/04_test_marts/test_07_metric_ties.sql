-- Gate 2 · Metric views tie to the marts
-- Every metric view adds back up to the mart it reads, so the dashboard and the analysis
-- cannot drift from the warehouse: iPinYou advertiser view vs fact_auction; every Criteo view
-- vs mart_campaign_day; the middle-weeks window vs the day view on the same days.
-- Passes when it returns 0 rows.
WITH ipy AS (
    SELECT f.advertiser_id
    FROM (SELECT advertiser_id,
                 count(*)                              AS bids,
                 count(*) FILTER (WHERE won)           AS impressions,
                 count(*) FILTER (WHERE clicked)       AS clicks,
                 count(*) FILTER (WHERE converted)     AS conversions,
                 coalesce(sum(pay_price), 0) / 1000.0  AS spend_fen
          FROM fact_auction GROUP BY advertiser_id) f
    FULL JOIN metrics_ipy_advertiser m USING (advertiser_id)
    WHERE m.advertiser_id IS NULL OR f.advertiser_id IS NULL
       OR f.bids <> m.bids OR f.impressions <> m.impressions OR f.clicks <> m.clicks
       OR f.conversions <> m.conversions OR abs(f.spend_fen - m.spend_fen) > 1e-6 * f.spend_fen
),
criteo(tie_group, source, is_reference, impressions, clicks, media_cost_idx, conversions, attributed_conversions, revenue_idx) AS (
    SELECT 'whole period', 'mart_campaign_day', true, sum(impressions), sum(clicks), sum(media_cost_idx),
           sum(conversions), sum(attributed_conversions), sum(revenue_idx) FROM mart_campaign_day
    UNION ALL SELECT 'whole period', 'metrics_criteo_day', false, sum(impressions), sum(clicks), sum(media_cost_idx),
           sum(conversions), sum(attributed_conversions), sum(revenue_idx) FROM metrics_criteo_day
    UNION ALL SELECT 'whole period', 'metrics_criteo_week', false, sum(impressions), sum(clicks), sum(media_cost_idx),
           sum(conversions), sum(attributed_conversions), sum(revenue_idx) FROM metrics_criteo_week
    UNION ALL SELECT 'whole period', 'metrics_criteo_campaign', false, sum(impressions), sum(clicks), sum(media_cost_idx),
           sum(conversions), sum(attributed_conversions), sum(revenue_idx) FROM metrics_criteo_campaign
    UNION ALL SELECT 'whole period', 'metrics_criteo_platform', false, impressions, clicks, media_cost_idx,
           conversions, attributed_conversions, revenue_idx FROM metrics_criteo_platform WHERE reporting_window = 'whole period'
    UNION ALL SELECT 'middle weeks', 'metrics_criteo_day', true, sum(impressions), sum(clicks), sum(media_cost_idx),
           sum(conversions), sum(attributed_conversions), sum(revenue_idx) FROM metrics_criteo_day WHERE is_middle_day
    UNION ALL SELECT 'middle weeks', 'metrics_criteo_week', false, sum(impressions), sum(clicks), sum(media_cost_idx),
           sum(conversions), sum(attributed_conversions), sum(revenue_idx) FROM metrics_criteo_week WHERE is_middle_week
    UNION ALL SELECT 'middle weeks', 'metrics_criteo_platform', false, impressions, clicks, media_cost_idx,
           conversions, attributed_conversions, revenue_idx FROM metrics_criteo_platform WHERE reporting_window = 'middle weeks'
)
SELECT 'iPinYou advertiser ' || advertiser_id AS check_name, 'metrics_ipy_advertiser vs fact_auction' AS detail FROM ipy
UNION ALL
SELECT 'Criteo ' || t.tie_group || ': ' || t.source, 'differs from ' || r.source
FROM criteo t
JOIN criteo r ON r.tie_group = t.tie_group AND r.is_reference AND NOT t.is_reference
WHERE t.impressions IS DISTINCT FROM r.impressions OR t.clicks IS DISTINCT FROM r.clicks
   OR t.conversions IS DISTINCT FROM r.conversions OR t.attributed_conversions IS DISTINCT FROM r.attributed_conversions
   OR abs(t.media_cost_idx - r.media_cost_idx) > 1e-6 * r.media_cost_idx
   OR abs(t.revenue_idx - r.revenue_idx) > 1e-6 * r.revenue_idx
UNION ALL
SELECT 'Criteo platform windows', 'expected exactly one whole-period and one middle-weeks row'
FROM metrics_criteo_platform
HAVING count(*) FILTER (WHERE reporting_window = 'whole period') <> 1
    OR count(*) FILTER (WHERE reporting_window = 'middle weeks') <> 1;
