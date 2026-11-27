#!/usr/bin/env python3
"""
Load ServiceNow extract CSVs into local Delta Lake tables and publish flat Parquet
snapshots for Power BI Desktop.

Modes
-----
initial : Build/replace Delta tables from CSV files already in Data/
          (incident.csv, sc_req_item.csv), then write Parquet snapshots.
daily   : Upsert rows from a staging CSV into Delta by `number` (update if
          present, insert if new), refresh the Parquet snapshot, then archive
          the staging CSV under Data/archive/.

Guest Guest rows (opened_by) are excluded in both modes.
"""

from __future__ import annotations

import argparse
import shutil
import sys
from datetime import datetime
from pathlib import Path

import pandas as pd
import pyarrow as pa
from deltalake import DeltaTable, write_deltalake

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_DATA_DIR = ROOT / "Data"

TABLES = {
    "incident": {
        "csv_name": "incident.csv",
        "delta_dir": "delta/incident",
        "parquet_name": "incident.parquet",
    },
    "sc_req_item": {
        "csv_name": "sc_req_item.csv",
        "delta_dir": "delta/sc_req_item",
        "parquet_name": "sc_req_item.parquet",
    },
}

# Columns that should round-trip as datetime / bool / int for Power BI.
DATETIME_COLS = {
    "opened_at",
    "reopened_time",
    "closed_at",
    "sys_created_on",
    "resolved_at",
    "sys_updated_on",
}
BOOL_COLS = {"active", "u_time_reported"}
INT_COLS = {
    "calendar_duration",
    "business_duration",
    "child_incidents",
    "reassignment_count",
    "u_offering_reassignment_count",
    "u_rpt_open_duration_test",
    "reopen_count",
    "sys_mod_count",
}


def _log(msg: str) -> None:
    print(msg, flush=True)


def read_csv(path: Path) -> pd.DataFrame:
    if not path.is_file():
        raise FileNotFoundError(f"CSV not found: {path}")

    # ServiceNow list exports are usually UTF-8; some rows contain Windows-1252 bytes.
    last_error: Exception | None = None
    df = None
    for encoding in ("utf-8-sig", "utf-8", "cp1252", "latin-1"):
        try:
            df = pd.read_csv(path, dtype=str, keep_default_na=False, encoding=encoding)
            _log(f"  Read {path.name} with encoding={encoding}")
            break
        except UnicodeDecodeError as exc:
            last_error = exc
    if df is None:
        raise last_error or RuntimeError(f"Unable to decode CSV: {path}")
    if "number" not in df.columns:
        raise ValueError(f"CSV is missing required 'number' column: {path}")

    if "opened_by" in df.columns:
        before = len(df)
        df = df[df["opened_by"].astype(str).str.strip() != "Guest Guest"].copy()
        dropped = before - len(df)
        if dropped:
            _log(f"  Filtered {dropped} Guest Guest row(s) from {path.name}")

    # Normalize blank cells to pandas NA for typed columns.
    for col in df.columns:
        df[col] = df[col].replace({"": pd.NA})

    for col in DATETIME_COLS:
        if col in df.columns:
            df[col] = pd.to_datetime(df[col], errors="coerce")

    for col in BOOL_COLS:
        if col in df.columns:
            df[col] = (
                df[col]
                .astype(str)
                .str.strip()
                .str.lower()
                .map({"true": True, "false": False, "1": True, "0": False})
            )

    for col in INT_COLS:
        if col in df.columns:
            numeric = pd.to_numeric(df[col], errors="coerce")
            non_null = numeric.dropna()
            if len(non_null) == 0 or (non_null % 1 == 0).all():
                df[col] = numeric.round().astype("Int64")
            else:
                # Duration-like fields sometimes arrive with fractional values.
                df[col] = numeric.astype("Float64")

    # Keep number as non-null string key.
    df["number"] = df["number"].astype(str).str.strip()
    df = df[df["number"].ne("") & df["number"].ne("nan")].copy()

    # Drop duplicate numbers within the batch (keep last).
    dupes = df.duplicated(subset=["number"], keep="last").sum()
    if dupes:
        _log(f"  Dropped {dupes} duplicate number(s) within batch (kept last)")
        df = df.drop_duplicates(subset=["number"], keep="last")

    return df.reset_index(drop=True)


def dataframe_to_arrow(df: pd.DataFrame) -> pa.Table:
    return pa.Table.from_pandas(df, preserve_index=False)


def write_parquet_snapshot(df: pd.DataFrame, parquet_path: Path) -> None:
    parquet_path.parent.mkdir(parents=True, exist_ok=True)
    tmp = parquet_path.with_suffix(".parquet.tmp")
    df.to_parquet(tmp, engine="pyarrow", index=False)
    tmp.replace(parquet_path)


def publish_snapshot_from_delta(delta_path: Path, parquet_path: Path) -> int:
    dt = DeltaTable(str(delta_path))
    df = dt.to_pandas(engine="datafusion")
    write_parquet_snapshot(df, parquet_path)
    return len(df)


def initial_load(table_key: str, data_dir: Path) -> None:
    meta = TABLES[table_key]
    csv_path = data_dir / meta["csv_name"]
    delta_path = data_dir / meta["delta_dir"]
    parquet_path = data_dir / meta["parquet_name"]

    _log(f"[{table_key}] Initial load from {csv_path}")
    df = read_csv(csv_path)
    _log(f"  Rows after filters: {len(df)}")

    if delta_path.exists():
        shutil.rmtree(delta_path)
    delta_path.mkdir(parents=True, exist_ok=True)

    table = dataframe_to_arrow(df)
    write_deltalake(str(delta_path), table, mode="overwrite")
    write_parquet_snapshot(df, parquet_path)
    _log(f"  Wrote Delta -> {delta_path}")
    _log(f"  Wrote Parquet snapshot -> {parquet_path}")


def daily_upsert(table_key: str, data_dir: Path, csv_path: Path | None = None) -> None:
    meta = TABLES[table_key]
    staging = Path(csv_path) if csv_path else data_dir / meta["csv_name"]
    delta_path = data_dir / meta["delta_dir"]
    parquet_path = data_dir / meta["parquet_name"]
    archive_dir = data_dir / "archive"

    _log(f"[{table_key}] Daily upsert from {staging}")
    incoming = read_csv(staging)
    _log(f"  Incoming rows after filters: {len(incoming)}")

    if not DeltaTable.is_deltatable(str(delta_path)):
        _log("  Delta table missing; running initial load semantics for this table")
        if delta_path.exists():
            shutil.rmtree(delta_path)
        delta_path.mkdir(parents=True, exist_ok=True)
        write_deltalake(str(delta_path), dataframe_to_arrow(incoming), mode="overwrite")
    else:
        dt = DeltaTable(str(delta_path))
        source = dataframe_to_arrow(incoming)
        (
            dt.merge(
                source=source,
                predicate="target.number = source.number",
                source_alias="source",
                target_alias="target",
            )
            .when_matched_update_all()
            .when_not_matched_insert_all()
            .execute()
        )
        _log("  Merge complete (matched update / not-matched insert)")

    total = publish_snapshot_from_delta(delta_path, parquet_path)
    _log(f"  Parquet snapshot refreshed ({total} rows) -> {parquet_path}")

    archive_dir.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    archive_path = archive_dir / f"{table_key}_{stamp}.csv"
    shutil.move(str(staging), str(archive_path))
    _log(f"  Archived staging CSV -> {archive_path}")


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--mode",
        choices=("initial", "daily"),
        required=True,
        help="initial: build from Data CSVs; daily: upsert staging CSV then archive",
    )
    parser.add_argument(
        "--table",
        choices=("incident", "sc_req_item", "all"),
        default="all",
        help="Which table(s) to process (default: all)",
    )
    parser.add_argument(
        "--data-dir",
        type=Path,
        default=DEFAULT_DATA_DIR,
        help=f"Data directory (default: {DEFAULT_DATA_DIR})",
    )
    parser.add_argument(
        "--csv",
        type=Path,
        default=None,
        help="Optional explicit staging CSV path (daily mode, single --table only)",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    data_dir = args.data_dir.resolve()
    data_dir.mkdir(parents=True, exist_ok=True)

    if args.csv and args.table == "all":
        raise SystemExit("--csv requires a single --table (incident or sc_req_item)")

    tables = list(TABLES) if args.table == "all" else [args.table]
    _log(f"Mode={args.mode} tables={tables} data_dir={data_dir}")

    for key in tables:
        if args.mode == "initial":
            initial_load(key, data_dir)
        else:
            daily_upsert(key, data_dir, csv_path=args.csv)

    _log("Done.")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:  # noqa: BLE001 - surface clean CLI errors
        print(f"ERROR: {exc}", file=sys.stderr)
        raise SystemExit(1) from exc
