# Ads Monetization & Auction Health Analytics

Business analysis of an ad platform's revenue, auction health and advertiser performance, built on two public advertising datasets with SQL (DuckDB), Excel and a BI dashboard.

> **Status:** in progress. Phase 1 (warehouse layer) is complete; findings, recommendations and the dashboard are added as later phases land.

## Business questions

The project answers 16 questions an ads-monetization analyst faces every week, from *"why did revenue move?"* to *"what is a reserve-price change worth before we ship it?"*. Each question has its own SQL file in `sql/05_analysis/`, which opens with the question and its one-sentence answer. The answers table is filled in here as each phase completes.

## Data

| Dataset | What it covers | Used for | Licence |
| :- | :- | :- | :- |
| [iPinYou RTB, Season 2](https://arxiv.org/abs/1407.7073) | 53M bids, 12M impressions, 5 advertisers, 6–12 Jun 2013 | Auction health, inventory, pricing simulation | Research release |
| [Criteo Attribution Modeling for Bidding](https://huggingface.co/datasets/criteo/criteo-attribution-dataset) | 16.5M impressions, 700 campaigns, 30 days | Platform P&L, advertiser segments, cohorts | CC BY-NC-SA 4.0 |

**Credits.** iPinYou data: Liao et al., *iPinYou Global RTB Bidding Algorithm Competition Dataset* (2014), and Zhang et al., *Real-Time Bidding Benchmarking with iPinYou Dataset* (2014). Criteo data: Diemert, Meynet et al., *Attribution Modeling Increases Efficiency of Bidding in Display Advertising* (AdKDD 2017).

Known limitations, and the proxies used for them, are listed in [`docs/requirements.md`](docs/requirements.md). Every judgment call is recorded in [`docs/decisions.md`](docs/decisions.md).

## Architecture

```
data/raw  ──►  data/parquet  ──►  raw_* views  ──►  stg_* tables  ──►  gate 1  ──►  fact_* / dim_* / mart_*  ──►  gate 2  ──►  analysis, dashboard, Excel
(downloads)    (all text,         (sql/00_load)     (typed, parsed,    (tests)      (sql/03_marts)                 (tests)
               md5-verified)                         deduplicated)
```

| Layer | Folder | Tables |
| :- | :- | :- |
| Raw | `sql/00_load` | `raw_ipy_bid`, `raw_ipy_imp`, `raw_ipy_clk`, `raw_ipy_conv`, `raw_ipy_test`, `raw_ipy_region`, `raw_ipy_city`, `raw_criteo` |
| Staging | `sql/01_staging` | `stg_ipy_bids`, `stg_ipy_imps`, `stg_ipy_clicks`, `stg_ipy_convs`, `stg_criteo_imps` |
| Marts | `sql/03_marts` | `fact_auction`, `dim_advertiser`, `dim_exchange`, `dim_slot`, `dim_geo`, `mart_ipy_hourly`, `fact_conversion`, `dim_campaign`, `mart_campaign_day` |

Each table's SQL header states its grain, primary key and source.

## How to reproduce

Requires Python 3.11+ and about 18 GB of free disk space (4 GB of downloads, 3.6 GB of Parquet, a 6 GB warehouse, plus room for one decompressed log). Runs on a laptop with 8 GB of RAM; a full build takes about 25 minutes.

```bash
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
python run_all.py --load        # download (~4.3 GB), verify checksums, convert to Parquet, build the warehouse
python run_all.py --test        # rerun the quality gates
python run_all.py --analysis    # run the business questions, export results to output/
```

Every step is idempotent and can be rerun safely.

## Repository layout

```
├── run_all.py              # orchestrator: --load --test --analysis --report
├── scripts/                # download_data.py, convert_to_parquet.py
├── sql/
│   ├── 00_load/            # raw_* views over Parquet
│   ├── 01_staging/         # stg_*: typed, parsed, deduplicated
│   ├── 02_test_staging/    # gate 1: each test returns 0 rows
│   ├── 03_marts/           # fact_*, dim_*, mart_*
│   ├── 04_test_marts/      # gate 2: benchmark reconciliation and business rules
│   └── 05_analysis/        # q01 … q16, one business question each
├── excel/                  # floor-price sizing model
├── dashboard/              # dashboard file and page exports
└── docs/                   # requirements, decision log, metric dictionary
```
