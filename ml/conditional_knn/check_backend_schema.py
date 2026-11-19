#!/usr/bin/env python3
"""Read-only schema smoke check using the app's ignored public Supabase config.

Requests zero rows and never signs in, changes data, or prints credentials.
The neutral/great view columns indicate the 0006 schema is exposed, but a
zero-row API check does not validate authenticated writes or SQL constraints.
"""

import json
from pathlib import Path
import plistlib
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import Request, urlopen


def main() -> None:
    repo = Path(__file__).resolve().parents[2]
    config = plistlib.loads((repo / "CineMatch/App/Secrets.plist").read_bytes())
    base = config["SUPABASE_URL"].rstrip("/")
    checks = {
        "taste_signals": "movie_id,signal,rating,source,updated_at,pipeline",
        "recommendation_batches": "id,pipeline,model_version,input_count",
        "recommendation_feedback": "batch_id,movie_id,score",
        "recommendation_metrics_by_score": "neutral,great",
    }
    failed = False
    for table, columns in checks.items():
        query = urlencode({"select": columns, "limit": 0})
        request = Request(f"{base}/rest/v1/{table}?{query}", headers={
            "apikey": config["SUPABASE_ANON_KEY"], "Accept": "application/json",
        })
        try:
            with urlopen(request, timeout=10) as response:
                rows = json.load(response)
                print(json.dumps({"table": table, "status": response.status, "returnedRows": len(rows)}))
        except HTTPError as error:
            print(json.dumps({"table": table, "status": error.code, "check": "not_confirmed"}))
            failed = True
        except URLError:
            print(json.dumps({"table": table, "check": "network_unavailable"}))
            raise SystemExit(2) from None
    raise SystemExit(1 if failed else 0)


if __name__ == "__main__":
    main()
