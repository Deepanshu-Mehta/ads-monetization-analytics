-- Gate 2 · Metric rules
-- Ratios stay in their valid range, Wilson intervals bracket their rate, the reporting rules
-- in the metric dictionary hold (margin only for middle weeks, D14; week 0 has no "new"
-- campaigns, D05), and concentration measures are well formed.
-- Passes when it returns 0 rows.
WITH c AS (
    SELECT
        (SELECT count(*) FROM metrics_ipy_hourly
         WHERE win_rate NOT BETWEEN 0 AND 1 OR ctr NOT BETWEEN 0 AND 1 OR bid_headroom NOT BETWEEN 0 AND 1)
                                                                            AS ipy_hourly_ratio_out_of_range,
        (SELECT count(*) FROM metrics_ipy_advertiser
         WHERE win_rate NOT BETWEEN 0 AND 1 OR bid_headroom NOT BETWEEN 0 AND 1
            OR NOT (ctr_low <= ctr AND ctr <= ctr_high) OR ctr_low < 0 OR ctr_high > 1)
                                                                            AS ipy_advertiser_ratio_out_of_range,
        (SELECT count(*) FROM metrics_criteo_campaign
         WHERE ctr NOT BETWEEN 0 AND 1 OR attribution_rate NOT BETWEEN 0 AND 1 OR revenue_share NOT BETWEEN 0 AND 1
            OR NOT (ctr_low <= ctr AND ctr <= ctr_high))                    AS criteo_campaign_ratio_out_of_range,
        (SELECT count(*) FROM metrics_criteo_day
         WHERE ctr NOT BETWEEN 0 AND 1 OR attribution_rate NOT BETWEEN 0 AND 1)
                                                                            AS criteo_day_ratio_out_of_range,
        (SELECT count(*) FROM metrics_criteo_week
         WHERE (margin_pct IS NOT NULL OR return_on_media_cost IS NOT NULL) AND NOT is_middle_week)
                                                                            AS criteo_margin_outside_middle_weeks,
        (SELECT count(*) FROM metrics_criteo_week WHERE week = 0 AND new_campaigns IS NOT NULL)
                                                                            AS criteo_new_campaigns_in_week_0,
        (SELECT count(*) FROM metrics_criteo_week WHERE is_middle_week AND NOT is_complete_week)
                                                                            AS criteo_incomplete_middle_week,
        (SELECT count(*) FROM metrics_criteo_platform
         WHERE reporting_window = 'whole period'
           AND (top_decile_revenue_share NOT BETWEEN 0.1 AND 1 OR revenue_hhi NOT BETWEEN 1.0 / active_campaigns AND 1))
                                                                            AS criteo_concentration_out_of_range,
        (SELECT abs(sum(revenue_share) - 1) > 1e-9 FROM metrics_criteo_campaign)::INT
                                                                            AS criteo_revenue_shares_not_summing_to_1
)
SELECT check_name, value
FROM c
UNPIVOT (value FOR check_name IN (ipy_hourly_ratio_out_of_range, ipy_advertiser_ratio_out_of_range,
                                  criteo_campaign_ratio_out_of_range, criteo_day_ratio_out_of_range,
                                  criteo_margin_outside_middle_weeks, criteo_new_campaigns_in_week_0,
                                  criteo_incomplete_middle_week, criteo_concentration_out_of_range,
                                  criteo_revenue_shares_not_summing_to_1))
WHERE value > 0;
