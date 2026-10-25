-- Q12 · Do advertisers stay and keep spending?
-- View:    Intermediary (Criteo); each campaign stands in for an advertiser.
-- Method:  Each campaign joins the cohort of the week of its first impression. Only the four
--          complete weeks (days 0-27) are used (D06). The data starts mid-flight, so the week-0
--          cohort mixes long-running and new campaigns and is labelled "existing" (D05); weeks 1-3
--          are true new-advertiser cohorts. Spend is media cost (impression-dated delivery), the
--          activity measure: revenue is conversion-dated and lagged.
-- Metrics: cohort size, active campaigns and media cost by week since start; campaign retention
--          (active ÷ cohort size) and spend retention (media cost ÷ the cohort's first-week cost).
-- Answer:  The dataset is a closed panel of advertisers: 674 of 675 campaigns are live in week 0
--          and only one launches later, so acquisition cohorts cannot be measured here. Retention of
--          the existing base is near total: 670 of 674 (99.4%) are still active in week 3, and their
--          spend is 101% of week 0 after a dip to 94% in week 1. Growth in this sample comes from
--          existing advertisers spending more, not from new ones.
-- Decision it informs: whether growth depends on keeping existing advertisers or adding new ones.

WITH weekly AS (
    SELECT campaign_id, day // 7 AS week, sum(media_cost_idx) AS media_cost_idx
    FROM mart_campaign_day
    WHERE day <= 27 AND impressions > 0
    GROUP BY ALL
),
cohort AS (
    SELECT campaign_id, min(week) AS cohort_week FROM weekly GROUP BY campaign_id
),
grid AS (
    SELECT c.cohort_week, w.week - c.cohort_week AS weeks_since_start,
           count(DISTINCT w.campaign_id) AS active_campaigns, sum(w.media_cost_idx) AS media_cost_idx
    FROM weekly w JOIN cohort c USING (campaign_id)
    GROUP BY ALL
)
SELECT
    cohort_week,
    CASE WHEN cohort_week = 0 THEN 'existing (week 0)' ELSE 'new in week ' || cohort_week END AS cohort,
    weeks_since_start,
    first_value(active_campaigns) OVER c                                        AS cohort_size,
    active_campaigns,
    round(active_campaigns / first_value(active_campaigns) OVER c, 3)           AS campaign_retention,
    round(media_cost_idx, 3)                                                    AS media_cost_idx,
    round(media_cost_idx / first_value(media_cost_idx) OVER c, 3)               AS spend_retention,
    round(media_cost_idx / sum(media_cost_idx) OVER (PARTITION BY cohort_week + weeks_since_start), 3)
                                                                                AS share_of_week_spend
FROM grid
WINDOW c AS (PARTITION BY cohort_week ORDER BY weeks_since_start)
ORDER BY cohort_week, weeks_since_start;
