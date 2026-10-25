-- Q13 · Who is about to churn?
-- View:    Intermediary (Criteo); each campaign stands in for an advertiser.
-- Method:  Media cost (impression-dated delivery) in the last 7 complete days (days 23-29; day 30
--          stops at 22:00) against the 7 days before (16-22). A campaign is at risk when delivery
--          fell more than 50%, and churned when it fell to zero. Only campaigns with material prior
--          delivery (at least 1,000 impressions in days 16-22) are assessed, so tiny campaigns do
--          not swing in and out of the list.
-- Metrics: prior and recent media cost and impressions, change %, whole-period revenue share
--          (the revenue at stake), margin % and volume tier.
-- Output:  the at-risk list, largest revenue at stake first.
-- Answer:  36 of 510 material campaigns cut delivery by more than half in the last 7 days, 4 of
--          them to zero, together holding 4.0% of revenue. One account dominates the list: the #9
--          campaign by revenue (14661605, 1.75% of revenue on its own) cut media cost by 77%, so it
--          is the first outreach call; no other at-risk campaign holds more than 0.22%.
-- Decision it informs: the account-management outreach list.

WITH windows AS (
    SELECT campaign_id,
           sum(media_cost_idx) FILTER (WHERE day BETWEEN 16 AND 22) AS prior_cost,
           sum(media_cost_idx) FILTER (WHERE day BETWEEN 23 AND 29) AS recent_cost,
           sum(impressions)    FILTER (WHERE day BETWEEN 16 AND 22) AS prior_impressions,
           sum(impressions)    FILTER (WHERE day BETWEEN 23 AND 29) AS recent_impressions
    FROM mart_campaign_day
    GROUP BY campaign_id
),
assessed AS (
    SELECT w.*, coalesce(w.recent_cost, 0) / w.prior_cost - 1 AS cost_change
    FROM windows w
    WHERE w.prior_impressions >= 1000 AND w.prior_cost > 0
)
SELECT
    a.campaign_id,
    CASE WHEN coalesce(a.recent_impressions, 0) = 0 THEN 'churned' ELSE 'at risk' END AS status,
    round(a.prior_cost, 3)                                                      AS prior_7d_media_cost_idx,
    round(coalesce(a.recent_cost, 0), 3)                                        AS recent_7d_media_cost_idx,
    a.prior_impressions::BIGINT                                                 AS prior_7d_impressions,
    coalesce(a.recent_impressions, 0)::BIGINT                                   AS recent_7d_impressions,
    round(a.cost_change, 3)                                                     AS media_cost_change,
    c.revenue_rank,
    round(c.revenue_share, 5)                                                   AS revenue_share,
    round(c.margin_pct, 4)                                                      AS margin_pct,
    c.volume_tier,
    (SELECT count(*) FROM assessed)                                             AS campaigns_assessed
FROM assessed a
JOIN metrics_criteo_campaign c USING (campaign_id)
WHERE a.cost_change < -0.5
ORDER BY c.revenue_share DESC;
