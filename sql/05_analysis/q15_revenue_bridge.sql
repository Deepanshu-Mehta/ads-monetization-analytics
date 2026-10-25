-- Q15 · What moved revenue week over week?
-- View:    Intermediary (Criteo).
-- Method:  Revenue = conversions x attribution rate x average CPO (the driver tree's Criteo row).
--          The log-mean (LMDI) method splits each week's revenue change into one effect per driver,
--          and the three effects add up exactly to the change (D07). Weeks are conversion weeks,
--          compared across the middle weeks only (weeks 1-3, days 7-27; D08). Revenue inside that
--          window is left-censored, so every bridge is shown raw and lag-adjusted: each day's
--          conversions, attributed conversions and revenue are divided by their lag completeness
--          before summing (D40). Average CPO moves with campaign mix as well as price, so its effect
--          is "price & mix". The biggest campaign movers for the latest week pair follow (raw).
-- Output:  long format for a waterfall: one row per week pair x basis x component.
-- Answer:  Lag-adjusted, revenue is flat (+0.6% from week 1 to 2, -1.2% from week 2 to 3), but the
--          mix beneath it is shifting: conversion volume fell 9.1% from week 2 to 3 and a rising
--          average CPO (+7.2%) made up for it. The raw bridge tells a different, wrong story: growth
--          of 8.5% then 3.4%, with the attribution rate apparently falling 8.9% in week 1 to 2, both
--          artefacts of censoring (D37, D40). The largest campaign decliner in week 2 to 3 is
--          14661605, the churn-risk account from Q13.
-- Decision it informs: the weekly "why did revenue move?" readout for leadership.

WITH daily AS (
    SELECT f.conversion_day AS day,
           count(*)                                          AS conversions,
           count(*) FILTER (WHERE f.attributed = 1)          AS attributed,
           coalesce(sum(f.cpo_idx) FILTER (WHERE f.attributed = 1), 0) AS revenue
    FROM fact_conversion f
    WHERE f.conversion_day BETWEEN 7 AND 27
    GROUP BY 1
),
weekly AS (
    SELECT 'raw' AS basis, d.day // 7 AS week,
           sum(d.conversions) AS conversions, sum(d.attributed) AS attributed, sum(d.revenue) AS revenue
    FROM daily d GROUP BY ALL
    UNION ALL
    SELECT 'lag-adjusted', d.day // 7,
           sum(d.conversions / c.conversions_complete), sum(d.attributed / c.attributed_complete),
           sum(d.revenue / c.revenue_complete)
    FROM daily d JOIN metrics_criteo_lag_completeness c USING (day) GROUP BY ALL
),
pairs AS (
    SELECT c.basis, c.week,
           p.revenue AS r0, c.revenue AS r1,
           p.conversions AS v0, c.conversions AS v1,
           p.attributed / p.conversions AS a0, c.attributed / c.conversions AS a1,
           p.revenue / p.attributed AS p0, c.revenue / c.attributed AS p1
    FROM weekly c
    JOIN weekly p ON p.basis = c.basis AND p.week = c.week - 1
    WHERE least(p.attributed, c.attributed, p.revenue, c.revenue) > 0
),
lmdi AS (
    SELECT *, coalesce((r1 - r0) / nullif(ln(r1) - ln(r0), 0), r0) AS l FROM pairs
),
drivers AS (
    SELECT 'week ' || (week - 1) || ' to ' || week AS week_pair, week, basis, component_order, component, value
    FROM lmdi,
    LATERAL (VALUES
        (0, 'start revenue', r0),
        (1, 'volume (conversions)', l * ln(v1 / v0)),
        (2, 'attribution rate', l * ln(a1 / a0)),
        (3, 'price & mix (average CPO)', l * ln(p1 / p0)),
        (4, 'end revenue', r1)
    ) AS t(component_order, component, value)
),
campaign_weeks AS (
    SELECT campaign_id,
           coalesce(sum(cpo_idx) FILTER (WHERE attributed = 1 AND conversion_day BETWEEN 14 AND 20), 0) AS r0,
           coalesce(sum(cpo_idx) FILTER (WHERE attributed = 1 AND conversion_day BETWEEN 21 AND 27), 0) AS r1
    FROM fact_conversion GROUP BY 1
),
movers AS (
    SELECT * FROM (
        SELECT 'week 2 to 3' AS week_pair, 3 AS week, 'raw' AS basis,
               10 + row_number() OVER (ORDER BY r1 - r0 DESC) AS component_order,
               'campaign ' || campaign_id || ' (top gainer)' AS component, r1 - r0 AS value
        FROM campaign_weeks QUALIFY row_number() OVER (ORDER BY r1 - r0 DESC) <= 5
    )
    UNION ALL
    SELECT * FROM (
        SELECT 'week 2 to 3', 3, 'raw', 20 + row_number() OVER (ORDER BY r1 - r0),
               'campaign ' || campaign_id || ' (top decliner)', r1 - r0
        FROM campaign_weeks QUALIFY row_number() OVER (ORDER BY r1 - r0) <= 5
    )
)
SELECT
    week_pair, basis,
    CASE WHEN component_order < 10 THEN 'driver' ELSE 'campaign mover' END    AS component_type,
    component,
    round(value, 3)                                                           AS revenue_idx,
    CASE WHEN component_order BETWEEN 1 AND 3 OR component_order >= 10
         THEN round(value / first_value(value) OVER (PARTITION BY week_pair, basis ORDER BY component_order), 4)
    END                                                                       AS share_of_start_revenue
FROM (SELECT * FROM drivers UNION ALL SELECT * FROM movers)
ORDER BY week, basis DESC, component_order;
