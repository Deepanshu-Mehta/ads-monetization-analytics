-- Q9 · What does the daily P&L look like?
-- View:    Intermediary (Criteo buys display media and is paid per attributed conversion).
-- Metrics: daily impressions, CTR, media cost (impression-dated) and revenue (conversion-dated),
--          with 7-day rolling sums (sum ÷ sum, D04). Revenue on day d of the window is only partly
--          observed, because conversions from impressions before day 0 are missing; dividing by the
--          lag completeness gives a lag-adjusted revenue line (D40). Money is in transformed units,
--          so read trends and ratios, not levels. Margin is not shown per day: it would set
--          conversion-dated revenue against impression-dated cost (D14); the answer quotes it for
--          the whole period and the middle weeks from metrics_criteo_platform, and compares middle
--          weeks 1 and 3 on lag-adjusted weekly sums (the 7-day columns on days 13 and 27).
-- Answer:  Over the whole period Criteo keeps 75.7% of revenue as gross margin (revenue is 4.1x
--          media cost; 71.0% in the middle weeks). Raw 7-day revenue climbs 12% from week 1 to
--          week 3, but that is the data window filling in: lag-adjusted revenue is flat (-0.6%)
--          while media cost rose 7.6%, so lag-adjusted margin slipped from 74.9% in week 1 to 72.8%
--          in week 3.
-- Decision it informs: the leadership P&L view (dashboard page 1).

SELECT
    d.day,
    d.period,
    d.is_middle_day,
    d.impressions::BIGINT                                                       AS impressions,
    round(d.ctr, 4)                                                             AS ctr,
    round(d.media_cost_idx, 3)                                                  AS media_cost_idx,
    round(d.revenue_idx, 3)                                                     AS revenue_idx,
    round(c.revenue_complete, 3)                                                AS revenue_complete,
    round(d.revenue_idx / c.revenue_complete, 3)                                AS revenue_idx_lag_adjusted,
    CASE WHEN d.day BETWEEN 6 AND 30 THEN round(sum(d.media_cost_idx) OVER w, 3) END       AS media_cost_idx_7d,
    CASE WHEN d.day >= 6 THEN round(sum(d.revenue_idx) OVER w, 3) END                     AS revenue_idx_7d,
    CASE WHEN d.day BETWEEN 6 AND 30
         THEN round(sum(d.revenue_idx / c.revenue_complete) OVER w, 3) END                AS revenue_idx_7d_lag_adjusted,
    CASE WHEN d.day BETWEEN 6 AND 30
         THEN round(ctr(sum(d.clicks) OVER w, sum(d.impressions) OVER w), 4) END          AS ctr_7d
FROM metrics_criteo_day d
LEFT JOIN metrics_criteo_lag_completeness c USING (day)
WINDOW w AS (ORDER BY d.day ROWS BETWEEN 6 PRECEDING AND CURRENT ROW)
ORDER BY d.day;
