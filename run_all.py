"""Build the warehouse and run the project end to end.

Stages, in order:
  --load      download (if needed) -> Parquet -> sql/00_load -> sql/01_staging
              -> gate 1 (sql/02_test_staging) -> sql/03_marts -> gate 2 (sql/04_test_marts)
  --test      rerun both test gates against the existing warehouse, without rebuilding
  --profile   write docs/data_profile.md from the built warehouse
  --analysis  run sql/05_analysis and export each result to output/
  --report    write docs/weekly_review.md (stretch goal)

With no flags, runs --load then --analysis. Every step is idempotent
(CREATE OR REPLACE, never append), so any stage can be rerun safely.
A test file passes when it returns 0 rows; the run stops at the first failure.
"""

import argparse
import os
import subprocess
import sys
import time
from pathlib import Path

import duckdb

ROOT = Path(__file__).resolve().parent
SQL = ROOT / "sql"
DB_PATH = ROOT / "data" / "warehouse.duckdb"
OUTPUT = ROOT / "output"


def connect() -> duckdb.DuckDBPyConnection:
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    con = duckdb.connect(str(DB_PATH))
    con.execute(f"SET memory_limit = '5GB'; SET temp_directory = '{ROOT / 'data' / 'tmp'}';")
    return con


def sql_files(folder: str) -> list[Path]:
    return sorted((SQL / folder).glob("*.sql"))


def run_build(con, folder: str) -> None:
    for path in sql_files(folder):
        start = time.perf_counter()
        con.execute(path.read_text())
        print(f"  [built] {folder}/{path.name} ({time.perf_counter() - start:.1f}s)")


def run_gate(con, folder: str) -> None:
    files = sql_files(folder)
    if not files:
        print(f"  [gate]  {folder}: no tests yet")
        return
    for path in files:
        rows = con.execute(path.read_text()).fetchdf()
        if len(rows):
            print(f"  [FAIL]  {folder}/{path.name}: {len(rows)} row(s)\n{rows.head(10).to_string()}")
            sys.exit(1)
        print(f"  [pass]  {folder}/{path.name}")


def run_python(script: str) -> None:
    result = subprocess.run([sys.executable, "-u", str(ROOT / "scripts" / script)], cwd=ROOT)
    if result.returncode:
        sys.exit(result.returncode)


def stage_load(con) -> None:
    print("== Download and convert")
    run_python("download_data.py")
    run_python("convert_to_parquet.py")
    print("== Raw and staging")
    run_build(con, "00_load")
    run_build(con, "01_staging")
    print("== Gate 1: staging tests")
    run_gate(con, "02_test_staging")
    print("== Marts")
    run_build(con, "03_marts")
    print("== Gate 2: mart tests")
    run_gate(con, "04_test_marts")


def stage_test(con) -> None:
    print("== Gate 1: staging tests")
    run_gate(con, "02_test_staging")
    print("== Gate 2: mart tests")
    run_gate(con, "04_test_marts")


def stage_analysis(con) -> None:
    print("== Analysis")
    files = sql_files("05_analysis")
    if not files:
        print("  no analysis files yet")
        return
    OUTPUT.mkdir(exist_ok=True)
    for path in files:
        out = OUTPUT / f"{path.stem}.csv"
        con.execute(path.read_text()).fetchdf().to_csv(out, index=False)
        print(f"  [ran]   {path.name} -> {out.relative_to(ROOT)}")


def stage_report(con) -> None:
    print("== Weekly review: not built yet (stretch goal)")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    for flag in ("load", "test", "profile", "analysis", "report"):
        parser.add_argument(f"--{flag}", action="store_true")
    args = parser.parse_args()
    if not any(vars(args).values()):
        args.load = args.analysis = True

    os.chdir(ROOT)  # SQL files use paths relative to the repo root
    if args.load and DB_PATH.exists():
        DB_PATH.unlink()  # full rebuild; DuckDB files do not shrink after CREATE OR REPLACE
    con = connect()
    try:
        if args.load:
            stage_load(con)
        elif args.test:
            stage_test(con)
        if args.profile:
            con.close()  # the profiler opens its own read-only connection
            run_python("profile_data.py")
            con = connect()
        if args.analysis:
            stage_analysis(con)
        if args.report:
            stage_report(con)
    finally:
        con.close()


if __name__ == "__main__":
    main()
