from __future__ import annotations

import argparse
from pathlib import Path

from .validator import AssetManifestValidator, AssetValidationError


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate the authoritative runtime asset manifest")
    parser.add_argument("command", choices=["check"])
    parser.add_argument("--root", type=Path, default=Path.cwd())
    parser.add_argument("--manifest", default="assets/asset-manifest.json")
    args = parser.parse_args()

    try:
        result = AssetManifestValidator(args.root.resolve()).validate(args.manifest)
    except AssetValidationError as error:
        print(f"Asset validation failed:\n{error}")
        return 1

    print(
        "Asset validation passed: "
        f"{result['asset_count']} assets, {result['resource_count']} scene/resource references"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
