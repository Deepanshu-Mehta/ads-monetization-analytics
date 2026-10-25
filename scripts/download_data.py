"""Download the two source datasets into data/raw/ and verify their checksums.

Safe to rerun: a file that is already present and passes its checksum is skipped,
and an interrupted download resumes from where it stopped.

Sources (checked 2026-10-25):
- iPinYou Season 2: Figshare mirror of ipinyou.contest.dataset (season 2 only).
  The original UCL link now returns 403. The archive's own files.md5 is checked
  again after extraction, in scripts/convert_to_parquet.py.
- Criteo Attribution: Criteo's official Hugging Face dataset repo, pinned to a commit.
"""

import hashlib
import ssl
import sys
import urllib.request
from pathlib import Path

RAW_DIR = Path(__file__).resolve().parents[1] / "data" / "raw"
CHUNK = 8 * 1024 * 1024

try:  # python.org builds on macOS ship without root certificates
    import certifi

    SSL_CONTEXT = ssl.create_default_context(cafile=certifi.where())
except ImportError:
    SSL_CONTEXT = ssl.create_default_context()

DATASETS = [
    {
        "name": "iPinYou Season 2",
        "url": "https://ndownloader.figshare.com/files/10082688",
        "file": "ipinyou.contest.dataset-season2.zip",
        "size": 3_610_000_000,  # approximate, for progress only
        "algo": "md5",
        "digest": "9ee18bf8c4dd19d1c41e6e77088367f9",
    },
    {
        "name": "Criteo Attribution",
        "url": (
            "https://huggingface.co/datasets/criteo/criteo-attribution-dataset/resolve/"
            "904188a63cbad78bee43cd26ff5ee4ac77903986/criteo_attribution_dataset.tsv.gz"
        ),
        "file": "criteo_attribution_dataset.tsv.gz",
        "size": 653_015_824,
        "algo": "sha256",
        "digest": "94ac7a465564349bc7ba008602211d5990a3c53cc133abc0aadef61ea2391a98",
    },
]


def file_digest(path: Path, algo: str) -> str:
    h = hashlib.new(algo)
    with path.open("rb") as f:
        while chunk := f.read(CHUNK):
            h.update(chunk)
    return h.hexdigest()


def download(ds: dict) -> None:
    target = RAW_DIR / ds["file"]
    partial = target.with_suffix(target.suffix + ".part")

    if target.exists():
        if file_digest(target, ds["algo"]) == ds["digest"]:
            print(f"[skip] {ds['name']}: {target.name} present, checksum OK")
            return
        print(f"[warn] {ds['name']}: checksum mismatch, downloading again")
        target.unlink()

    start = partial.stat().st_size if partial.exists() else 0
    req = urllib.request.Request(ds["url"], headers={"User-Agent": "ads-analysis-downloader"})
    if start:
        req.add_header("Range", f"bytes={start}-")
    with urllib.request.urlopen(req, timeout=60, context=SSL_CONTEXT) as resp:
        if start and resp.status != 206:
            start = 0  # server ignored the range request; restart cleanly
        mode = "ab" if start else "wb"
        done, next_report = start, start
        with partial.open(mode) as out:
            while chunk := resp.read(CHUNK):
                out.write(chunk)
                done += len(chunk)
                if done >= next_report:
                    print(f"  {ds['name']}: {done / 1e9:.2f} / ~{ds['size'] / 1e9:.2f} GB", flush=True)
                    next_report = done + 250_000_000

    actual = file_digest(partial, ds["algo"])
    if actual != ds["digest"]:
        sys.exit(f"[fail] {ds['name']}: {ds['algo']} {actual} != expected {ds['digest']}")
    partial.rename(target)
    print(f"[ok]   {ds['name']}: {target.name} downloaded, checksum OK")


def main() -> None:
    RAW_DIR.mkdir(parents=True, exist_ok=True)
    for ds in DATASETS:
        download(ds)


if __name__ == "__main__":
    main()
