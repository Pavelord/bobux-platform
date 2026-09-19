"""Isolated parser only: never execute scripts or fetch URLs from an uploaded place."""
import sys
from pathlib import Path
if sys.platform != "win32":
    import resource
    resource.setrlimit(resource.RLIMIT_AS, (768 * 1024 * 1024,) * 2)
    resource.setrlimit(resource.RLIMIT_CPU, (40, 40))
    resource.setrlimit(resource.RLIMIT_FSIZE, (96 * 1024 * 1024,) * 2)
sys.path.insert(0, str(Path(sys.argv[1]).resolve().parent))
import rbxl_converter
raise SystemExit(rbxl_converter.main([sys.argv[1], sys.argv[2], sys.argv[3]]))
