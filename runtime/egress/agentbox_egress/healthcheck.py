"""HEALTHCHECK da imagem: a admin API responde."""
import sys
import urllib.request

from .config import load_config

try:
    cfg = load_config()
    with urllib.request.urlopen(f"http://127.0.0.1:{cfg.admin_port}/v1/health", timeout=2) as r:
        sys.exit(0 if r.status == 200 else 1)
except Exception:
    sys.exit(1)
