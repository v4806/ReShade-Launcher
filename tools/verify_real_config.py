import json
import subprocess
import sys
import time
import traceback

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from reshade_launcher.game.injector import launch_game


def main() -> int:
    config_path = Path(sys.argv[1])
    log_path = Path(sys.argv[2])
    config = json.loads(config_path.read_text(encoding="utf-8"))

    try:
        result = launch_game(config, str(ROOT))
        time.sleep(2)
        payload = {
            "ok": True,
            "root_pid": result.root_pid,
            "target_pid": result.target_pid,
        }
        subprocess.run(
            ["taskkill", "/F", "/PID", str(result.target_pid)],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    except Exception as exc:
        payload = {
            "ok": False,
            "error": str(exc),
            "traceback": traceback.format_exc(),
        }

    log_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    return 0 if payload["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
