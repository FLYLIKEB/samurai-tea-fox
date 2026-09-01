"""Image discovery for the asset browser."""

from __future__ import annotations

from pathlib import Path

from .constants import IMAGE_EXTENSIONS
from .models import AssetImage

def find_images(root: Path, project_root: Path) -> list[AssetImage]:
    if not root.exists():
        return []

    images: list[AssetImage] = []
    for path in root.rglob("*"):
        if not path.is_file():
            continue
        if path.suffix.lower() not in IMAGE_EXTENSIONS:
            continue
        try:
            relative_path = path.relative_to(project_root)
        except ValueError:
            relative_path = path
        images.append(AssetImage(path=path, relative_path=relative_path))

    return sorted(images, key=lambda item: item.relative_path.as_posix().lower())
