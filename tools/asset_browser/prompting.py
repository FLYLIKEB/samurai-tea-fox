"""Codex prompt template loading and rendering."""

from __future__ import annotations

from pathlib import Path

from .constants import BUILTIN_PROMPT_TEMPLATE
from .paths import template_path

def load_prompt_template() -> str:
    path = template_path()
    if not path.exists():
        return BUILTIN_PROMPT_TEMPLATE
    return path.read_text(encoding="utf-8")

def save_prompt_template(template: str) -> None:
    template_path().write_text(template, encoding="utf-8")

def render_prompt_template(
    template: str,
    paths: list[str],
    project_root: Path | None = None,
) -> str:
    lines = "\n".join(f"- {path}" for path in paths)
    rendered = template.replace("{asset_list}", lines)
    rendered = rendered.replace("{asset_count}", str(len(paths)))
    if project_root is not None:
        rendered = rendered.replace("{project_root}", str(project_root))
    if "{asset_list}" not in template:
        rendered = f"{rendered.rstrip()}\n\n이미지:\n{lines}\n"
    return rendered if rendered.endswith("\n") else f"{rendered}\n"

def codex_prompt_for(paths: list[str], project_root: Path | None = None) -> str:
    return render_prompt_template(load_prompt_template(), paths, project_root)
