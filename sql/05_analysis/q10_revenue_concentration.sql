-- Q10 · How concentrated is revenue?
-- View:    Intermediary (Criteo); each campaign stands in for an advertiser.
-- Metrics: whole-period revenue per campaign (all conversions of the period's impressions, D36),
--          revenue share, cumulative revenue share by revenue rank (the Pareto curve), and the
--          cumulative media-cost share of the same campaigns. Headline concentration measures
--          (top-10% share, Herfindahl index) come from metrics_criteo_platform.
-- Answer:  Revenue is top-heavy but not dependent on any one advertiser: 44 of 675 campaigns
--          (6.5%) earn half of it and 187 (28%) earn 80%; the top 10% earn 58.9% while taking 56.4%
--          of media cost. The largest campaign is only 4.0% of revenue, so the Herfindahl index is
--          98, far below the 1,500 that marks a moderately concentrated market. The top 44 accounts
--          warrant dedicated account management.
-- Decision it informs: dependence risk, and how account management effort should be split.

SELECT
    revenue_rank,
    campaign_id,
    round(revenue_rank / count(*) OVER (), 4)                                   AS campaign_percentile,
    round(revenue_share, 5)                                                     AS revenue_share,
    round(sum(revenue_share) OVER (ORDER BY revenue_rank), 4)                   AS cumulative_revenue_share,
    round(sum(media_cost_idx) OVER (ORDER BY revenue_rank) / sum(media_cost_idx) OVER (), 4)
                                                                                AS cumulative_media_cost_share,
    round(margin_pct, 4)                                                        AS margin_pct,
    volume_tier
FROM metrics_criteo_campaign
ORDER BY revenue_rank;
