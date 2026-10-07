#!/usr/bin/env python3
"""Export or verify ABI arrays using built artifacts; no network or third-party packages."""
import argparse
import json
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("--check", action="store_true")
args = parser.parse_args()
root = Path(__file__).resolve().parent.parent
for name in ("LaunchToken", "QuantumEngine"):
    artifact = root / "out" / f"{name}.sol" / f"{name}.json"
    abi = json.loads(artifact.read_text())["abi"]
    destination = root / "docs" / "abi" / f"{name}.json"
    if args.check:
        if json.loads(destination.read_text()) != abi:
            raise SystemExit(f"ABI mismatch: {destination}")
        print(f"Verified {name} ABI")
    else:
        destination.write_text(json.dumps(abi, indent=2) + "\n")
        print(f"Exported {name} ABI")
