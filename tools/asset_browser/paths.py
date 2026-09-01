"""Path helpers for asset browser files and generated backups."""

from __future__ import annotations

from datetime import datetime
from pathlib import Path

from .constants import PROMPT_TEMPLATE_FILE

def project_root_from_script() -> Path:
    return Path(__file__).resolve().parents[2]

def template_path() -> Path:
    return Path(__file__).resolve().with_name(PROMPT_TEMPLATE_FILE)

def palette_backup_root() -> Path:
    stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    return Path(__file__).resolve().with_name("palette_backups") / stamp

def relative_or_name(path: Path, project_root: Path) -> Path:
    try:
        return path.relative_to(project_root)
    except ValueError:
        return Path(path.name)
