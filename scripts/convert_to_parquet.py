"""Convert the raw downloads in data/raw/ into Parquet under data/parquet/.

iPinYou ships bz2-compressed, header-less, tab-separated logs, which DuckDB cannot
read directly. Each log is streamed out of the zip once: the compressed bytes are
checked against the archive's files.md5 while being decompressed to a temporary
file, which DuckDB converts to Parquet before it is deleted. Only one decompressed
log exists on disk at a time (decision D22 in docs/decisions.md).

Every column is written as text; types are applied in sql/01_staging (D21).
Safe to rerun: outputs that already exist are skipped. A manifest of source
checksums and row counts is written to data/parquet/_manifest.json.
"""

import bz2
import hashlib
import json
import re
import sys
import zipfile
from pathlib import Path

import duckdb
import pyarrow as pa
import pyarrow.parquet as pq

ROOT = Path(__file__).resolve().parents[1]
RAW = ROOT / "data" / "raw"
OUT = ROOT / "data" / "parquet"
TMP = ROOT / "data" / "tmp"
IPINYOU_ZIP = RAW / "ipinyou.contest.dataset-season2.zip"
CRITEO_GZ = RAW / "criteo_attribution_dataset.tsv.gz"

# Column layouts from the dataset specification (Liao et al., 2014, Tables 2 and 3).
BID_COLUMNS = [
    "bid_id", "ts_raw", "ipinyou_id", "user_agent", "ip", "region_id", "city_id",
    "ad_exchange", "domain", "url", "anonymous_url", "slot_id", "slot_width",
    "slot_height", "slot_visibility", "slot_format", "floor_price", "creative_id",
    "bid_price", "advertiser_id", "user_profile_ids",
]
EVENT_COLUMNS = [  # impression, click and conversion logs
    "bid_id", "ts_raw", "log_type", "ipinyou_id", "user_agent", "ip", "region_id",
    "city_id", "ad_exchange", "domain", "url", "anonymous_url", "slot_id",
    "slot_width", "slot_height", "slot_visibility", "slot_format", "floor_price",
    "creative_id", "bid_price", "pay_price", "landing_page_url", "advertiser_id",
    "user_profile_ids",
]
TEST_COLUMNS = EVENT_COLUMNS + ["test_clicks", "test_has_conversion"]  # spec section 2.4

LOG_PATTERN = re.compile(r"training2nd/(bid|imp|clk|conv)\.(\d{8})\.txt\.bz2$")
TEST_PATTERN = re.compile(r"testing2nd/.*\.txt\.bz2$")
LOG_COLUMNS = {"bid": BID_COLUMNS, "imp": EVENT_COLUMNS, "clk": EVENT_COLUMNS, "conv": EVENT_COLUMNS}


def connect() -> duckdb.DuckDBPyConnection:
    TMP.mkdir(parents=True, exist_ok=True)
    con = duckdb.connect()
    con.execute(f"SET memory_limit = '4GB'; SET temp_directory = '{TMP}';")
    return con


def tsv_to_parquet(con, src: Path, dst: Path, columns: list[str]) -> tuple[int, int]:
    """Convert one header-less, tab-separated log to Parquet, all columns as text.

    The dialect is fixed, not sniffed: tab delimiter, no quoting, no escapes, no comments,
    '\\n' line endings. User agents containing quotes, commas, '#' or control bytes pass
    through untouched. Stray carriage returns would break the parser; convert_ipinyou
    rejects them while decompressing.

    Some rows omit the trailing field (no final tab). null_padding sets the last column to
    NULL for those; strict_mode rejects rows with too many fields. A row missing more than
    its last field would leave the second-to-last column NULL, which fails the conversion.
    Returns (rows, rows_missing_last_field).
    """
    col_spec = "{" + ", ".join(f"'{c}': 'VARCHAR'" for c in columns) + "}"
    tmp_dst = dst.with_suffix(".parquet.tmp")
    con.execute(f"""
        COPY (
            SELECT * FROM read_csv('{src}', columns = {col_spec}, delim = '\t', quote = '',
                                   escape = '', comment = '', header = false, new_line = '\\n',
                                   auto_detect = false, strict_mode = true, null_padding = true)
        ) TO '{tmp_dst}' (FORMAT parquet, COMPRESSION zstd)
    """)
    rows, padded, broken = con.execute(f"""
        SELECT count(*),
               count(*) FILTER (WHERE "{columns[-1]}" IS NULL),
               count(*) FILTER (WHERE "{columns[-2]}" IS NULL)
        FROM read_parquet('{tmp_dst}')
    """).fetchone()
    if broken:
        tmp_dst.unlink()
        sys.exit(f"[fail] {src.name}: {broken} row(s) missing more than the last field")
    tmp_dst.rename(dst)
    return rows, padded


def first_line_fields(path: Path) -> int:
    with path.open("r", encoding="utf-8", errors="replace") as f:
        return len(f.readline().rstrip("\n").split("\t"))


def load_md5_table(zf: zipfile.ZipFile) -> dict[str, str]:
    """Map each archive path (relative to the dataset folder) to its expected md5."""
    member = next((m for m in zf.namelist() if m.endswith("files.md5")), None)
    if member is None:
        sys.exit("[fail] files.md5 not found in the iPinYou archive")
    table = {}
    for line in zf.read(member).decode("utf-8", errors="replace").splitlines():
        # BSD format, as shipped: "MD5 (training2nd/bid.20130606.txt.bz2) = 2f88cace..."
        if match := re.match(r"MD5 \((.+)\) = ([0-9a-f]{32})$", line.strip()):
            table[match.group(1)] = match.group(2)
    if not table:
        sys.exit("[fail] files.md5 could not be parsed")
    return table


def expected_md5(md5_table: dict[str, str], member: str) -> str | None:
    """files.md5 paths are relative to the dataset folder, e.g. training2nd/bid.20130606.txt.bz2."""
    return md5_table.get(member.split("/", 1)[-1])


def convert_ipinyou(con, manifest: dict) -> None:
    if not IPINYOU_ZIP.exists():
        sys.exit(f"[fail] {IPINYOU_ZIP.name} missing: run scripts/download_data.py first")
    with zipfile.ZipFile(IPINYOU_ZIP) as zf:
        md5_table = load_md5_table(zf)
        members = zf.namelist()

        jobs = []
        for m in members:
            if match := LOG_PATTERN.search(m):
                kind, day = match.groups()
                jobs.append((m, OUT / "ipinyou" / kind / f"{day}.parquet", LOG_COLUMNS[kind]))
            elif TEST_PATTERN.search(m):
                jobs.append((m, OUT / "ipinyou" / "test" / (Path(m).name.split(".txt")[0] + ".parquet"), TEST_COLUMNS))
        if not jobs:
            sys.exit("[fail] no Season 2 logs found in the archive")

        for member, dst, columns in sorted(jobs):
            if dst.exists():
                print(f"[skip] {dst.relative_to(ROOT)}")
                continue
            dst.parent.mkdir(parents=True, exist_ok=True)
            want = expected_md5(md5_table, member)
            if want is None:
                sys.exit(f"[fail] {member} has no entry in files.md5")

            # One pass: md5 of the compressed bytes, decompression to a temp file, and a count
            # of line feeds (to reconcile rows) and carriage returns (which the parser rejects).
            tmp_txt = TMP / (Path(member).name.removesuffix(".bz2"))
            md5, decomp = hashlib.md5(), bz2.BZ2Decompressor()
            line_feeds = carriage_returns = 0
            last_byte = b"\n"

            def emit(data: bytes) -> None:
                nonlocal line_feeds, carriage_returns, last_byte
                line_feeds += data.count(b"\n")
                carriage_returns += data.count(b"\r")
                if data:
                    last_byte = data[-1:]
                out.write(data)

            with zf.open(member) as src, tmp_txt.open("wb") as out:
                while chunk := src.read(16 * 1024 * 1024):
                    md5.update(chunk)
                    emit(decomp.decompress(chunk))
                    if decomp.eof and decomp.unused_data:  # multi-stream bz2
                        rest = decomp.unused_data
                        decomp = bz2.BZ2Decompressor()
                        emit(decomp.decompress(rest))
            if md5.hexdigest() != want:
                tmp_txt.unlink()
                sys.exit(f"[fail] md5 mismatch for {member}: {md5.hexdigest()} != {want}")
            if carriage_returns:
                tmp_txt.unlink()
                sys.exit(f"[fail] {member}: {carriage_returns} carriage return(s) inside the data")

            fields = first_line_fields(tmp_txt)
            if fields != len(columns):
                tmp_txt.unlink()
                sys.exit(f"[fail] {member}: {fields} fields, expected {len(columns)}")

            rows, padded = tsv_to_parquet(con, tmp_txt, dst, columns)
            tmp_txt.unlink()
            lines = line_feeds + (last_byte != b"\n")  # final line may lack a line feed
            if rows != lines:
                dst.unlink()
                sys.exit(f"[fail] {member}: parsed {rows:,} rows from {lines:,} lines")
            manifest[str(dst.relative_to(OUT))] = {"source": member, "md5": want, "rows": rows,
                                                   "rows_missing_last_field": padded}
            note = f", {padded:,} missing the last field" if padded else ""
            print(f"[ok]   {dst.relative_to(ROOT)}: {rows:,} rows (md5 verified{note})")

        for name in ("region.en.txt", "city.en.txt"):
            dst = OUT / "ipinyou" / "lookup" / name.replace(".en.txt", ".parquet")
            if dst.exists():
                print(f"[skip] {dst.relative_to(ROOT)}")
                continue
            member = next((m for m in members if m.endswith(name)), None)
            if member is None:
                print(f"[warn] {name} not in archive; dim_geo will have ids only")
                continue
            content = zf.read(member)
            if hashlib.md5(content).hexdigest() != expected_md5(md5_table, member):
                sys.exit(f"[fail] md5 mismatch for {member}")
            dst.parent.mkdir(parents=True, exist_ok=True)
            # Lookups are "id<TAB>name", except city.en.txt's first line ("0 unknown"),
            # which uses a space. Parse leniently here; the files are a few hundred lines.
            pairs = []
            for line in content.decode("utf-8").splitlines():
                if line.strip():
                    sep = "\t" if "\t" in line else " "
                    pairs.append([part.strip() for part in line.split(sep, 1)])
            pq.write_table(pa.table({"id": [p[0] for p in pairs], "name": [p[1] for p in pairs]}), dst)
            rows = len(pairs)
            manifest[str(dst.relative_to(OUT))] = {"source": member, "md5": expected_md5(md5_table, member), "rows": rows}
            print(f"[ok]   {dst.relative_to(ROOT)}: {rows:,} rows")


def convert_criteo(con, manifest: dict) -> None:
    dst = OUT / "criteo" / "criteo_attribution.parquet"
    if dst.exists():
        print(f"[skip] {dst.relative_to(ROOT)}")
        return
    if not CRITEO_GZ.exists():
        sys.exit(f"[fail] {CRITEO_GZ.name} missing: run scripts/download_data.py first")
    dst.parent.mkdir(parents=True, exist_ok=True)
    tmp_dst = dst.with_suffix(".parquet.tmp")
    con.execute(f"""
        COPY (
            SELECT * FROM read_csv('{CRITEO_GZ}', delim = '\t', header = true,
                                   all_varchar = true, quote = '', escape = '')
        ) TO '{tmp_dst}' (FORMAT parquet, COMPRESSION zstd)
    """)
    rows = con.execute(f"SELECT count(*) FROM read_parquet('{tmp_dst}')").fetchone()[0]
    tmp_dst.rename(dst)
    manifest[str(dst.relative_to(OUT))] = {"source": CRITEO_GZ.name, "rows": rows}
    print(f"[ok]   {dst.relative_to(ROOT)}: {rows:,} rows")


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    manifest_path = OUT / "_manifest.json"
    manifest = json.loads(manifest_path.read_text()) if manifest_path.exists() else {}
    con = connect()
    try:
        convert_ipinyou(con, manifest)
        convert_criteo(con, manifest)
    finally:
        manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
