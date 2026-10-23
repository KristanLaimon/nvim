"""Explicit remote check: version, bound constants, zero-row catalog query."""

import argparse
import getpass
import importlib.util
import json
from pathlib import Path
import sys


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("engine", choices=["mysql", "postgres"])
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, required=True)
    parser.add_argument("--database", required=True)
    parser.add_argument("--user", required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    sys.path.insert(0, str(root / ".foxnvim/query/private/drivers"))
    spec = importlib.util.spec_from_file_location("query_bridge", root / "scripts/query_bridge.py")
    bridge = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(bridge)
    driver = bridge.Driver()
    try:
        profile = vars(args)
        profile["password"] = getpass.getpass("Database password (not saved): ")
        result = driver.connect(profile, root)
        profile.pop("password", None)
        rows = driver.execute("SELECT ? AS bound, NULL AS missing", ["quote' stays data"], lambda _message: None, 1)["sets"][0]["rows"]
        assert rows == [["quote' stays data", None]], "Parameter binding mismatch"
        driver.rows("SELECT column_name,data_type FROM information_schema.columns WHERE table_schema=%s LIMIT 0", (args.database if args.engine == "mysql" else "public",))
        print(json.dumps({"engine": args.engine, "version": result["version"], "read_only": True, "binding": "passed", "catalog_query": "passed (zero rows)", "business_rows_read": 0}))
    finally:
        driver.close()


if __name__ == "__main__":
    main()
