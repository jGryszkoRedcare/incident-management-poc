import json, time, pathlib, contextlib

_FLAG_FILE = pathlib.Path("/etc/flagd/demo.flagd.json")
_FLAGD_RELOAD_GRACE_SEC = 2        # file‑watcher settles within ~1 s

@contextlib.contextmanager
def temporary_flag(flag: str, variant: str = "on"):
    """
    Context manager:
        with temporary_flag("adFailure", "on"):
            ... run code that expects the flag active ...
    Auto‑restores the previous defaultVariant afterwards.
    """
    data = json.loads(_FLAG_FILE.read_text())
    if flag not in data["flags"]:
        raise KeyError(f"unknown flag {flag}")

    old_variant = data["flags"][flag]["defaultVariant"]
    try:
        data["flags"][flag]["defaultVariant"] = variant
        _FLAG_FILE.write_text(json.dumps(data, indent=2))
        time.sleep(_FLAGD_RELOAD_GRACE_SEC)
        yield
    finally:
        data["flags"][flag]["defaultVariant"] = old_variant
        _FLAG_FILE.write_text(json.dumps(data, indent=2))
        time.sleep(_FLAGD_RELOAD_GRACE_SEC)
