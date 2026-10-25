-- Q14 · Where is revenue leaking?
-- View:    Intermediary (Criteo is paid only for conversions the advertiser attributes to it).
-- Method:  An unattributed conversion is one the platform helped drive but was not paid for; its
--          cpo is still recorded (D24), so its value can be estimated. Attribution falls steeply
--          with the lag between the last impression and the conversion (77% within a day, 24% at
--          14-30 days, D37), so a campaign with slow converters looks leaky without being so. Each
--          conversion's expected attribution is therefore the platform rate for its lag (whole days
--          0-30), and a campaign's excess leakage is expected minus actual attributed conversions,
--          tested with a z-score (|z| >= 3 is significant). Campaigns need at least 30 conversions.
-- Metrics: conversions, attribution rate (actual and lag-expected), excess unattributed
--          conversions and their value at the campaign's cpo, unpaid value share.
-- Answer:  Criteo is paid for 54% of the conversions it drives. Against the platform's own
--          lag-expected rates, 163 of 621 campaigns attribute significantly less (164 significantly
--          more: the benchmark is the platform average, not an absolute standard); closing those
--          163 gaps is worth about 16% of current revenue. The largest single gap is 5061834 (20% vs
--          44% expected, 2.2% of total revenue). Both loss-making Fix accounts from Q11 are
--          attribution problems, not pricing ones: 28351001 and 10474106 attribute 25% and 13% of
--          mostly same-day conversions against 60% and 65% expected, and at those rates would earn
--          margins of about 53% and 83% instead of losses.
-- Decision it informs: which advertisers to approach about attribution terms.

WITH conv AS (
    SELECT campaign_id, attributed, cpo_idx, conversion_day - last_impression_day AS day_lag
    FROM fact_conversion
),
lag_rate AS (
    SELECT day_lag, avg(attributed) AS expected_rate FROM conv GROUP BY day_lag
),
per_campaign AS (
    SELECT
        c.campaign_id,
        count(*)                                            AS conversions,
        sum(c.attributed)                                   AS attributed,
        sum(l.expected_rate)                                AS expected_attributed,
        sum(l.expected_rate * (1 - l.expected_rate))        AS variance,
        avg(c.cpo_idx)                                      AS avg_cpo_idx,
        sum(c.cpo_idx) FILTER (WHERE c.attributed = 0)      AS unpaid_value_idx,
        sum(c.cpo_idx)                                      AS total_value_idx,
        median(c.day_lag)                                   AS median_lag_days
    FROM conv c JOIN lag_rate l USING (day_lag)
    GROUP BY c.campaign_id
)
SELECT
    p.campaign_id,
    p.conversions::BIGINT                                                     AS conversions,
    p.attributed::BIGINT                                                      AS attributed_conversions,
    round(attribution_rate(p.attributed, p.conversions), 4)                   AS attribution_rate,
    round(p.expected_attributed / p.conversions, 4)                           AS expected_rate_for_lag_mix,
    p.median_lag_days,
    round(p.expected_attributed - p.attributed, 1)                            AS excess_unattributed,
    round((p.expected_attributed - p.attributed) / sqrt(p.variance), 1)       AS leakage_z,
    abs((p.expected_attributed - p.attributed) / sqrt(p.variance)) >= 3       AS significant,
    round(greatest(p.expected_attributed - p.attributed, 0) * p.avg_cpo_idx, 3) AS excess_unpaid_value_idx,
    round(p.unpaid_value_idx / p.total_value_idx, 4)                          AS unpaid_value_share,
    round(c.revenue_share, 5)                                                 AS revenue_share,
    round(c.margin_pct, 4)                                                    AS margin_pct
FROM per_campaign p
JOIN metrics_criteo_campaign c USING (campaign_id)
WHERE p.conversions >= min_rate_events()
ORDER BY excess_unpaid_value_idx DESC, leakage_z DESC;
