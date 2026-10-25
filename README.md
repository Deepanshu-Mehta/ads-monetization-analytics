# Ads Monetization & Auction Health Analytics

Business analysis of an ad platform's revenue, auction health and advertiser performance, built on two public advertising datasets with SQL (DuckDB), Excel and a BI dashboard.

> **Status:** in progress. The warehouse, quality gates, metric layer and all 16 business questions are complete; the dashboard, sizing model and recommendations follow.

## Business questions

Each question has its own SQL file in [`sql/05_analysis/`](sql/05_analysis/), which opens with the question, the perspective it takes and its answer; results are exported to [`output/`](output/). iPinYou money is in Chinese fen (100 fen = 1 RMB); prices are CPM.

**Auction health and pricing (iPinYou, 6–12 Jun 2013)**

| # | Question | Answer |
| :- | :- | :- |
| [Q1](sql/05_analysis/q01_market_overview.sql) | What does the market look like? | 12.2M impressions from 53.3M bids (22.9% win rate) at a 78-fen CPM, reconciling exactly to the published benchmark. Tyre advertiser 3476 has the lowest CTR (0.052%) and an eCPC 40% above average. |
| [Q2](sql/05_analysis/q02_competition_by_hour.sql) | When is competition highest? | At midnight: the 00:00 market price (94.8 fen) is 46% above the 02:00 trough, and 00:00 is dearer than 02:00 on every date in the window. |
| [Q3](sql/05_analysis/q03_inventory_value.sql) | Which inventory is overpriced? | 300x250 below the fold: 9.0% of spend for 3.2% of clicks (eCPC 307 fen). The same size above the fold costs 38% more CPM but delivers 6.3x the CTR. |
| [Q4](sql/05_analysis/q04_exchange_value.sql) | Which exchanges deliver value? | AdX has the dearest clicks for all five advertisers (eCPC +60% vs Tencent), yet takes 26–34% of each one's spend. |
| [Q5](sql/05_analysis/q05_competition_depth.sql) | Where is competition thin? | AdX below the fold: median clearing price 47 fen, 30.5% of auctions under 30 fen, on 15% of spend. |
| [Q6](sql/05_analysis/q06_floor_price_effects.sql) | Do floor prices shape outcomes? | Yes, within each exchange: Tencent's clearing price rises from 29 to 79 fen across floor buckets. Six Tencent slots floored at 100 take 23% of all bids and are never won. |
| [Q7](sql/05_analysis/q07_floor_price_simulation.sql) | What would raising the floor do? | +3.4% revenue with 92% of impressions kept if 70% of affected auctions still clear; break-even at 44–56% retention, so buyer response decides the outcome. |
| [Q8](sql/05_analysis/q08_anomaly_monitor.sql) | Is anything broken? | One platform-level alert in 23 days (day 18 media cost +18%); per-campaign alerts need an abs(z) ≥ 5 bar to stay actionable. Catches a 28x bid burst from one advertiser on 9 Jun. |

Q5–Q7 take the seller's view, estimated from one buyer's won auctions. iPinYou bid fixed test prices, so the floor analysis rests on clearing prices, not bids (decision D41).

**Advertiser performance (Criteo, 30 days, 675 campaigns)**

| # | Question | Answer |
| :- | :- | :- |
| [Q9](sql/05_analysis/q09_daily_pnl.sql) | What does the P&L look like? | 75.7% gross margin over the whole period. Raw revenue "grows" 12% across the middle weeks, but lag-adjusted it is flat while media cost rose 7.6%, so margin slipped from 74.9% to 72.8%. |
| [Q10](sql/05_analysis/q10_revenue_concentration.sql) | How concentrated is revenue? | 44 campaigns (6.5%) earn half of revenue; the largest earns 4.0%, so concentration is low (HHI 98). |
| [Q11](sql/05_analysis/q11_campaign_segments.sql) | Which campaigns to scale, fix, grow or review? | Scale earns 39.9% of revenue on 26.8% of cost; Fix earns as much but absorbs 53.3% of cost and holds 3 loss-making accounts. |
| [Q12](sql/05_analysis/q12_cohort_retention.sql) | Do advertisers stay? | Yes: 99.4% of advertisers are still active after three weeks. The sample is a closed panel, so new-advertiser cohorts cannot be measured. |
| [Q13](sql/05_analysis/q13_churn_risk.sql) | Who is about to churn? | 36 campaigns (4.0% of revenue) cut delivery by more than half; the #9 revenue account cut 77% and is the first call. |
| [Q14](sql/05_analysis/q14_attribution_leakage.sql) | Where is revenue leaking? | Criteo is paid for 54% of the conversions it drives. 163 campaigns attribute well below their lag-expected rate, worth about 16% of revenue, and both loss-making Fix accounts are attribution problems, not pricing ones. |
| [Q15](sql/05_analysis/q15_revenue_bridge.sql) | What moved revenue week over week? | Lag-adjusted revenue is flat, but conversion volume fell 9% in the last week, masked by a 7% rise in average CPO. The raw bridge misreads censoring as growth. |
| [Q16](sql/05_analysis/q16_behavioural_segments.sql) | Which campaigns behave alike? | Slow-buyer campaigns earn 68% of revenue at the best margins, and are the least often attributed: the most profitable advertisers carry the most leakage risk. |

Criteo money is in transformed units, so results are ratios and shares. Revenue is booked when the conversion happens, so recent weeks are incomplete; weekly comparisons are lag-adjusted (decision D40).

## Data

| Dataset | What it covers | Used for | Licence |
| :- | :- | :- | :- |
| [iPinYou RTB, Season 2](https://arxiv.org/abs/1407.7073) | 53M bids, 12M impressions, 5 advertisers, 6–12 Jun 2013 | Auction health, inventory, pricing simulation | Research release |
| [Criteo Attribution Modeling for Bidding](https://huggingface.co/datasets/criteo/criteo-attribution-dataset) | 16.5M impressions, 700 campaigns, 30 days | Platform P&L, advertiser segments, cohorts | CC BY-NC-SA 4.0 |

**Credits.** iPinYou data: Liao et al., *iPinYou Global RTB Bidding Algorithm Competition Dataset* (2014), and Zhang et al., *Real-Time Bidding Benchmarking with iPinYou Dataset* (2014). Criteo data: Diemert, Meynet et al., *Attribution Modeling Increases Efficiency of Bidding in Display Advertising* (AdKDD 2017).

Known limitations, and the proxies used for them, are listed in [`docs/requirements.md`](docs/requirements.md). Every judgment call is recorded in [`docs/decisions.md`](docs/decisions.md), and every KPI is defined once in [`docs/metric_dictionary.md`](docs/metric_dictionary.md).

## Data quality

The build **reproduces the iPinYou benchmark paper's Table 3 exactly** for all five Season 2 advertisers: all 50 published cells (bids, impressions, clicks, conversions, cost and five rates). Fourteen SQL tests run in two gates on every build, and the run stops at the first failure:

| Gate | Runs | Tests |
| :- | :- | :- |
| 1 · staging | before the marts are built | unique keys, no rows lost from raw, event lineage, date coverage, Criteo flag logic, attribution consistency |
| 2 · marts | before anything is exported | Table 3 reconciliation, second-price rule, grain of every table, totals tie across layers, referential integrity, fact contract, metric views tie to the marts, metric rules |

Known data issues are documented and bounded by tests rather than hidden: duplicate impression logs, clicks without an impression row, paying prices above the recorded bid, and Criteo cpo varying within a conversion. See [`docs/data_profile.md`](docs/data_profile.md) for the full profile.

## Architecture

```
data/raw  ──►  data/parquet  ──►  raw_* views  ──►  stg_* tables  ──►  gate 1  ──►  fact_* / dim_* / mart_* / metrics_*  ──►  gate 2  ──►  analysis, dashboard, Excel
(downloads)    (all text,         (sql/00_load)     (typed, parsed,    (tests)      (sql/03_marts)                 (tests)
               md5-verified)                         deduplicated)
```

| Layer | Folder | Tables |
| :- | :- | :- |
| Raw | `sql/00_load` | `raw_ipy_bid`, `raw_ipy_imp`, `raw_ipy_clk`, `raw_ipy_conv`, `raw_ipy_test`, `raw_ipy_region`, `raw_ipy_city`, `raw_criteo` |
| Staging | `sql/01_staging` | `stg_ipy_bids`, `stg_ipy_imps`, `stg_ipy_clicks`, `stg_ipy_convs`, `stg_criteo_imps` |
| Marts | `sql/03_marts` | `ref_ipinyou_table3`, `fact_auction`, `dim_advertiser`, `dim_exchange`, `dim_slot`, `dim_geo`, `mart_ipy_hourly`, `fact_conversion`, `dim_campaign`, `mart_campaign_day` |
| Metrics | `sql/03_marts/03_metrics.sql` | KPI macros (`ctr()`, `win_rate()`, `margin_pct()`, …) and views `metrics_ipy_hourly`, `metrics_ipy_advertiser`, `metrics_criteo_lag_completeness`, `metrics_criteo_day`, `metrics_criteo_week`, `metrics_criteo_campaign`, `metrics_criteo_platform` |

Each table's SQL header states its grain, primary key and source.

## How to reproduce

Requires Python 3.11+ and about 18 GB of free disk space (4 GB of downloads, 3.6 GB of Parquet, a 6 GB warehouse, plus room for one decompressed log). Runs on a laptop with 8 GB of RAM; a full build takes about 25 minutes.

```bash
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
python run_all.py --load        # download (~4.3 GB), verify checksums, convert to Parquet, build the warehouse
python run_all.py --test        # rerun the quality gates
python run_all.py --profile     # regenerate docs/data_profile.md from the warehouse
python run_all.py --analysis    # run the business questions, export results to output/ (about 5 seconds)
```

Every step is idempotent and can be rerun safely.

## Repository layout

```
├── run_all.py              # orchestrator: --load --test --profile --analysis --report
├── scripts/                # download, Parquet conversion, data profile
├── sql/
│   ├── 00_load/            # raw_* views over Parquet
│   ├── 01_staging/         # stg_*: typed, parsed, deduplicated
│   ├── 02_test_staging/    # gate 1: each test returns 0 rows
│   ├── 03_marts/           # fact_*, dim_*, mart_*, metric macros and views
│   ├── 04_test_marts/      # gate 2: benchmark reconciliation and business rules
│   └── 05_analysis/        # q01 … q16, one business question each
├── output/                 # results of each business question, as CSV
├── excel/                  # floor-price sizing model
├── dashboard/              # dashboard file and page exports
└── docs/                   # requirements, decision log, data profile, metric dictionary
```
