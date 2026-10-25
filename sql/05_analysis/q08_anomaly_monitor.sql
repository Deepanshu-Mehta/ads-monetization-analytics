-- Q8 · Is anything broken?
-- View:    Intermediary (Criteo), the main monitor, plus a short iPinYou demo.
-- Method:  Criteo: each campaign's daily impressions and media cost against its own trailing 7
--          days (z-score; days 7-29, since day 30 stops at 22:00). Impression-dated measures only:
--          conversion-dated revenue would flag the censored edge weeks as anomalies (D36). Days
--          after a campaign's launch with no impressions count as zero, so a sudden stop is caught.
--          iPinYou demo: each advertiser-hour's bids against the same hour on the other six dates.
--          Seven days are too few for a stable baseline (D18), so this is illustration only.
-- Rules:   flag when |z| >= 3 and the baseline is material: a trailing mean of at least 1,000
--          impressions (Criteo) or 10,000 bids (iPinYou) (D43).
-- Output:  flagged rows only, one per entity x period x metric, largest |z| first.
-- Answer:  At platform level only day 18 stands out (media cost 18% above its trailing week,
--          z = 4.8). Per campaign, 296 of 6,212 material campaign-days cross |z| >= 3 (4.8%, against
--          about 0.3% by chance), across 117 of 675 campaigns, including 7 that fell to zero: real
--          movement, but about 13 alerts a day, so a production alert should page at |z| >= 5
--          (70 alerts, about 3 a day). The iPinYou demo catches advertiser 3427 firing 3.25M bids on
--          AdX at 01:00 on 9 Jun, taking hourly bids to 28x their usual level for that hour.
-- Decision it informs: monitoring and alerting.

WITH campaign_days AS (            -- dense grid from launch to day 29, zero-filled
    SELECT c.campaign_id, d.day,
           coalesce(m.impressions, 0)      AS impressions,
           coalesce(m.media_cost_idx, 0)   AS media_cost_idx
    FROM dim_campaign c
    CROSS JOIN range(0, 30) d(day)
    LEFT JOIN mart_campaign_day m ON m.campaign_id = c.campaign_id AND m.day = d.day
    WHERE d.day >= c.first_day
),
platform_days AS (
    SELECT NULL::BIGINT AS campaign_id, day, sum(impressions) AS impressions, sum(media_cost_idx) AS media_cost_idx
    FROM campaign_days GROUP BY day
),
criteo_long AS (
    SELECT campaign_id, day, 'impressions' AS metric, impressions::DOUBLE AS value FROM campaign_days
    UNION ALL SELECT campaign_id, day, 'media cost (idx)', media_cost_idx FROM campaign_days
    UNION ALL SELECT campaign_id, day, 'impressions', impressions::DOUBLE FROM platform_days
    UNION ALL SELECT campaign_id, day, 'media cost (idx)', media_cost_idx FROM platform_days
),
criteo_scored AS (
    SELECT *,
        avg(value)         OVER w AS baseline_mean,
        stddev_samp(value) OVER w AS baseline_sd,
        count(*)           OVER w AS baseline_days,
        avg(impressions_for_floor) OVER w AS baseline_impressions
    FROM (
        SELECT l.*, coalesce(cd.impressions, pd.impressions) AS impressions_for_floor
        FROM criteo_long l
        LEFT JOIN campaign_days cd ON cd.campaign_id = l.campaign_id AND cd.day = l.day
        LEFT JOIN platform_days pd ON l.campaign_id IS NULL AND pd.day = l.day
    )
    WINDOW w AS (PARTITION BY campaign_id, metric ORDER BY day ROWS BETWEEN 7 PRECEDING AND 1 PRECEDING)
),
criteo_flags AS (
    SELECT 'Criteo' AS dataset,
           coalesce('campaign ' || campaign_id, 'all campaigns') AS entity,
           'day ' || day AS period, metric, value, baseline_mean, baseline_sd,
           (value - baseline_mean) / baseline_sd AS z
    FROM criteo_scored
    WHERE day >= 7 AND baseline_days = 7 AND baseline_sd > 0 AND baseline_impressions >= 1000
),
ipy_hours AS (
    SELECT CAST(advertiser_id AS VARCHAR) AS entity, hour_ts, hour(hour_ts) AS hour, sum(bids) AS bids
    FROM metrics_ipy_hourly GROUP BY ALL
    UNION ALL
    SELECT 'all advertisers', hour_ts, hour(hour_ts), sum(bids) FROM metrics_ipy_hourly GROUP BY ALL
),
ipy_scored AS (                    -- baseline = the same hour on the other dates (leave one out)
    SELECT *,
        count(*) OVER p - 1                                         AS other_days,
        (sum(bids) OVER p - bids) / (count(*) OVER p - 1)           AS baseline_mean,
        sqrt(greatest((sum(bids * bids) OVER p - bids * bids
                       - (count(*) OVER p - 1) * pow((sum(bids) OVER p - bids) / (count(*) OVER p - 1), 2))
                      / (count(*) OVER p - 2), 0))                  AS baseline_sd
    FROM ipy_hours
    WINDOW p AS (PARTITION BY entity, hour)
),
ipy_flags AS (
    SELECT 'iPinYou (demo)' AS dataset,
           CASE WHEN entity = 'all advertisers' THEN entity ELSE 'advertiser ' || entity END AS entity,
           strftime(hour_ts, '%Y-%m-%d %H:00') AS period, 'bids' AS metric,
           bids::DOUBLE AS value, baseline_mean, baseline_sd,
           (bids - baseline_mean) / baseline_sd AS z
    FROM ipy_scored
    WHERE other_days >= 5 AND baseline_sd > 0 AND baseline_mean >= 10000
)
SELECT dataset, entity, period, metric,
       round(value, 4) AS value, round(baseline_mean, 4) AS baseline_mean, round(baseline_sd, 4) AS baseline_sd,
       round(z, 1) AS z,
       CASE WHEN z > 0 THEN 'spike' ELSE 'drop' END AS direction
FROM (SELECT * FROM criteo_flags UNION ALL SELECT * FROM ipy_flags)
WHERE abs(z) >= 3
ORDER BY dataset, abs(z) DESC;
