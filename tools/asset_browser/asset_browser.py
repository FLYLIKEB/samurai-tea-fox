#!/usr/bin/env python3
"""Minimal local asset image browser for Samurai Tea Fox."""

from __future__ import annotations

import argparse
from datetime import datetime
import json
import math
import shutil
import subprocess
from dataclasses import dataclass
from pathlib import Path
import tkinter as tk
from tkinter import colorchooser, filedialog, messagebox, ttk

try:
    from PIL import Image, ImageTk
except ImportError:  # Pillow is optional; Tk can still load PNG/GIF/PPM/PGM.
    Image = None
    ImageTk = None


IMAGE_EXTENSIONS = {
    ".png",
    ".gif",
    ".jpg",
    ".jpeg",
    ".bmp",
    ".webp",
    ".tga",
    ".tif",
    ".tiff",
    ".ppm",
    ".pgm",
}

BG = "#f4f1e8"
PANEL = "#e7e1d2"
TEXT = "#1f1f1f"
MUTED = "#6c675e"
SELECTED = "#2f6f73"
SELECTED_TEXT = "#ffffff"
BORDER = "#bdb5a3"
ERROR = "#8c3f38"
PROMPT_TEMPLATE_FILE = "default_prompt_template.txt"
ART_STYLE_TOKENS_PATH = Path("assets/style/art-style-tokens.json")
BUILTIN_PROMPT_TEMPLATE = """아래 로컬 게임 에셋 이미지들을 한 번에 확인하고 수정해줘.

먼저 assets/style/art-style-tokens.json을 읽고, 그 파일의 팔레트/공통 시각 컨셉/ImageGen positive·negative 토큰을 기준으로 작업해.
색상 팔레트와 시각 제약은 다른 곳에 새로 복제하지 말고 해당 JSON을 단일 정본으로 유지해.

이미지:
{asset_list}
"""


@dataclass(frozen=True)
class AssetImage:
    path: Path
    relative_path: Path


def project_root_from_script() -> Path:
    return Path(__file__).resolve().parents[2]


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


def template_path() -> Path:
    return Path(__file__).resolve().with_name(PROMPT_TEMPLATE_FILE)


def load_prompt_template() -> str:
    path = template_path()
    if not path.exists():
        return BUILTIN_PROMPT_TEMPLATE
    return path.read_text(encoding="utf-8")


def save_prompt_template(template: str) -> None:
    template_path().write_text(template, encoding="utf-8")


def render_prompt_template(template: str, paths: list[str], project_root: Path | None = None) -> str:
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


def load_art_style_tokens(project_root: Path) -> tuple[dict | None, str]:
    path = project_root / ART_STYLE_TOKENS_PATH
    if not path.exists():
        return None, f"스타일 토큰 파일이 없습니다: {ART_STYLE_TOKENS_PATH.as_posix()}"
    try:
        return json.loads(path.read_text(encoding="utf-8")), ""
    except json.JSONDecodeError as exc:
        return None, f"JSON 읽기 오류: {exc}"


def save_art_style_tokens(project_root: Path, data: dict) -> None:
    path = project_root / ART_STYLE_TOKENS_PATH
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def normalize_hex_color(color: str) -> str:
    color = color.strip()
    if not color:
        return color
    if not color.startswith("#"):
        color = f"#{color}"
    if len(color) != 7:
        return color.upper()
    return color.upper()


def hex_to_rgb(color: str) -> tuple[int, int, int] | None:
    color = normalize_hex_color(color)
    if len(color) != 7 or not color.startswith("#"):
        return None
    try:
        return int(color[1:3], 16), int(color[3:5], 16), int(color[5:7], 16)
    except ValueError:
        return None


def extract_palette_colors(data: dict | None) -> list[tuple[int, int, int]]:
    if data is None:
        return []

    colors: list[tuple[int, int, int]] = []
    seen: set[tuple[int, int, int]] = set()
    palette = data.get("palette", {})

    for entry in palette.get("global", []):
        rgb = hex_to_rgb(entry.get("hex", ""))
        if rgb is not None and rgb not in seen:
            colors.append(rgb)
            seen.add(rgb)

    for accent in palette.get("biome_accents", []):
        for hex_color in accent.get("colors", []):
            rgb = hex_to_rgb(hex_color)
            if rgb is not None and rgb not in seen:
                colors.append(rgb)
                seen.add(rgb)

    return colors


def nearest_palette_color(
    rgb: tuple[int, int, int],
    palette: list[tuple[int, int, int]],
) -> tuple[int, int, int]:
    red, green, blue = rgb
    return min(
        palette,
        key=lambda color: (
            (red - color[0]) * (red - color[0])
            + (green - color[1]) * (green - color[1])
            + (blue - color[2]) * (blue - color[2])
        ),
    )


def recolor_image_to_palette(image, palette: list[tuple[int, int, int]]):
    if not palette:
        return image

    image = image.convert("RGBA")
    remapped = []
    for red, green, blue, alpha in image.getdata():
        if alpha == 0:
            remapped.append((red, green, blue, alpha))
            continue
        mapped = nearest_palette_color((red, green, blue), palette)
        remapped.append((mapped[0], mapped[1], mapped[2], alpha))

    recolored = Image.new("RGBA", image.size)
    recolored.putdata(remapped)
    return recolored


def palette_backup_root() -> Path:
    stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    return Path(__file__).resolve().with_name("palette_backups") / stamp


def relative_or_name(path: Path, project_root: Path) -> Path:
    try:
        return path.relative_to(project_root)
    except ValueError:
        return Path(path.name)


def save_recolored_image(path: Path, palette: list[tuple[int, int, int]]) -> None:
    if Image is None:
        raise RuntimeError("Pillow가 설치되어 있지 않습니다.")

    with Image.open(path) as opened:
        recolored = recolor_image_to_palette(opened, palette)
        suffix = path.suffix.lower()
        if suffix in {".jpg", ".jpeg"}:
            recolored = recolored.convert("RGB")
        recolored.save(path)


def apply_palette_to_images(
    image_paths: list[Path],
    palette: list[tuple[int, int, int]],
    project_root: Path,
    backup_root: Path,
) -> tuple[int, list[str]]:
    converted = 0
    failures: list[str] = []

    for path in image_paths:
        try:
            backup_path = backup_root / relative_or_name(path, project_root)
            backup_path.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(path, backup_path)
            save_recolored_image(path, palette)
            converted += 1
        except Exception as exc:
            failures.append(f"{path}: {exc}")

    return converted, failures


def format_art_style_tokens(data: dict | None, error: str) -> str:
    if data is None:
        return error

    lines: list[str] = []
    lines.append(f"제목: {data.get('title', '(제목 없음)')}")
    lines.append(f"ID: {data.get('id', '(id 없음)')}")
    lines.append("")

    management_rule = data.get("management_rule", {})
    if management_rule:
        lines.append("[관리 규칙]")
        for value in management_rule.values():
            lines.append(f"- {value}")
        lines.append("")

    project_concept = data.get("project_concept", {})
    if project_concept:
        lines.append("[공통 컨셉]")
        if project_concept.get("short"):
            lines.append(f"- {project_concept['short']}")
        if project_concept.get("mood"):
            lines.append(f"- 분위기: {', '.join(project_concept['mood'])}")
        if project_concept.get("motifs"):
            lines.append(f"- 모티브: {', '.join(project_concept['motifs'])}")
        if project_concept.get("avoid_mood"):
            lines.append(f"- 피할 분위기: {', '.join(project_concept['avoid_mood'])}")
        lines.append("")

    pixel_rules = data.get("pixel_rules", {})
    if pixel_rules:
        lines.append("[픽셀 규칙]")
        for key, value in pixel_rules.items():
            lines.append(f"- {key}: {value}")
        lines.append("")

    style_pillars = data.get("style_pillars", [])
    if style_pillars:
        lines.append("[스타일 축]")
        for pillar in style_pillars:
            lines.append(f"- {pillar.get('name', pillar.get('id', '(이름 없음)'))}: {pillar.get('rule', '')}")
        lines.append("")

    palette = data.get("palette", {})
    global_palette = palette.get("global", [])
    if global_palette:
        lines.append("[전역 팔레트]")
        for color in global_palette:
            lines.append(
                f"- {color.get('name', color.get('id', '(색상)'))} "
                f"{color.get('hex', '')}: {color.get('usage', '')}"
            )
        lines.append("")

    biome_accents = palette.get("biome_accents", [])
    if biome_accents:
        lines.append("[바이옴 포인트 색]")
        for accent in biome_accents:
            colors = ", ".join(accent.get("colors", []))
            lines.append(f"- {accent.get('name', accent.get('id', '(바이옴)'))}: {colors} / {accent.get('usage', '')}")
        lines.append("")

    palette_rules = palette.get("rules", {})
    if palette_rules:
        lines.append("[팔레트 금지/규칙]")
        for key, value in palette_rules.items():
            if isinstance(value, list):
                lines.append(f"- {key}: {', '.join(value)}")
            else:
                lines.append(f"- {key}: {value}")
        lines.append("")

    asset_profiles = data.get("asset_profiles", {})
    if asset_profiles:
        lines.append("[에셋 프로필 토큰]")
        for profile_id, profile in asset_profiles.items():
            lines.append(f"- {profile_id}")
            positive = profile.get("positive_tokens", [])
            negative = profile.get("negative_tokens", [])
            if positive:
                lines.append(f"  positive: {', '.join(positive)}")
            if negative:
                lines.append(f"  negative: {', '.join(negative)}")
        lines.append("")

    prompt_assembly = data.get("prompt_assembly", {})
    if prompt_assembly:
        lines.append("[프롬프트 조립]")
        for key, value in prompt_assembly.items():
            if isinstance(value, list):
                lines.append(f"- {key}: {', '.join(value)}")
            else:
                lines.append(f"- {key}: {value}")

    return "\n".join(lines).rstrip() + "\n"


class AssetBrowser(tk.Tk):
    def __init__(self, project_root: Path, asset_root: Path, scale: int) -> None:
        super().__init__()
        self.project_root = project_root
        self.asset_root = asset_root
        self.scale_var = tk.IntVar(value=scale)
        self.palette_preview_var = tk.BooleanVar(value=False)
        self.filter_var = tk.StringVar()
        self.status_var = tk.StringVar()
        self.path_var = tk.StringVar(value=str(asset_root))
        self.images: list[AssetImage] = []
        self.filtered_images: list[AssetImage] = []
        self.selected: set[Path] = set()
        self.thumbnail_refs: list[tk.PhotoImage] = []
        self.prompt_template = load_prompt_template()
        self.art_style_data: dict | None = None
        self.art_style_raw = ""
        self.prompt_dirty = False
        self.template_dirty = False
        self.updating_prompt = False
        self.updating_template = False

        self.title("무사여우 에셋 브라우저")
        self.geometry("1360x940")
        self.minsize(1040, 720)
        self.configure(bg=BG)

        self._build_ui()
        self.rescan()

    def _build_ui(self) -> None:
        style = ttk.Style(self)
        style.configure("TNotebook", background=PANEL, borderwidth=0)
        style.configure("TNotebook.Tab", padding=(12, 5))

        toolbar = tk.Frame(self, bg=PANEL, padx=10, pady=8)
        toolbar.pack(side=tk.TOP, fill=tk.X)

        tk.Label(toolbar, text="폴더", bg=PANEL, fg=TEXT).grid(row=0, column=0, sticky="w")
        path_entry = tk.Entry(toolbar, textvariable=self.path_var, bg=BG, fg=TEXT, relief=tk.FLAT)
        path_entry.grid(row=0, column=1, sticky="ew", padx=(6, 6))

        self._button(toolbar, "찾기", self.choose_root).grid(row=0, column=2, padx=2)
        self._button(toolbar, "새로고침", self.rescan).grid(row=0, column=3, padx=2)
        self._button(toolbar, "Finder에서 폴더 보기", self.reveal_asset_root).grid(
            row=0, column=4, padx=2
        )

        tk.Label(toolbar, text="필터", bg=PANEL, fg=TEXT).grid(
            row=1, column=0, sticky="w", pady=(8, 0)
        )
        filter_entry = tk.Entry(
            toolbar,
            textvariable=self.filter_var,
            bg=BG,
            fg=TEXT,
            relief=tk.FLAT,
            insertbackground=TEXT,
        )
        filter_entry.grid(row=1, column=1, sticky="ew", padx=(6, 6), pady=(8, 0))
        filter_entry.bind("<KeyRelease>", lambda _event: self.apply_filter())

        scale_box = tk.OptionMenu(toolbar, self.scale_var, 2, 3, 4, 5, 6, 8, command=self._scale_changed)
        scale_box.configure(bg=BG, fg=TEXT, activebackground=PANEL, relief=tk.FLAT, width=6)
        scale_box["menu"].configure(bg=BG, fg=TEXT)
        scale_box.grid(row=1, column=2, padx=2, pady=(8, 0))
        tk.Label(toolbar, text="배율", bg=PANEL, fg=MUTED).grid(
            row=1, column=3, sticky="w", pady=(8, 0)
        )

        toolbar.columnconfigure(1, weight=1)

        actions = tk.Frame(self, bg=BG, padx=10, pady=8)
        actions.pack(side=tk.TOP, fill=tk.X)

        self._button(actions, "전체 선택", self.select_all).pack(side=tk.LEFT, padx=(0, 6))
        self._button(actions, "선택 해제", self.clear_selection).pack(side=tk.LEFT, padx=(0, 14))
        self._button(actions, "상대경로 복사", self.copy_relative_paths).pack(side=tk.LEFT, padx=(0, 6))
        self._button(actions, "절대경로 복사", self.copy_absolute_paths).pack(side=tk.LEFT, padx=(0, 6))
        self._button(actions, "Codex 프롬프트 복사", self.copy_codex_prompt).pack(
            side=tk.LEFT, padx=(0, 6)
        )
        self._button(actions, "TXT 저장", self.save_txt).pack(side=tk.LEFT)
        self._button(actions, "표시 이미지 실제 변환", self.apply_palette_to_shown_images).pack(
            side=tk.LEFT, padx=(14, 0)
        )
        preview_toggle = tk.Checkbutton(
            actions,
            text="팔레트 테스트 보기",
            variable=self.palette_preview_var,
            command=self.toggle_palette_preview,
            bg=BG,
            fg=TEXT,
            activebackground=BG,
            activeforeground=TEXT,
            selectcolor=PANEL,
            relief=tk.FLAT,
            padx=10,
        )
        preview_toggle.pack(side=tk.RIGHT)

        bottom_panel = tk.Frame(self, bg=PANEL, padx=10, pady=8)
        bottom_panel.pack(side=tk.BOTTOM, fill=tk.X)

        notebook = ttk.Notebook(bottom_panel)
        notebook.pack(side=tk.TOP, fill=tk.X)

        prompt_panel = tk.Frame(notebook, bg=PANEL, padx=8, pady=8)
        template_panel = tk.Frame(notebook, bg=PANEL, padx=8, pady=8)
        style_panel = tk.Frame(notebook, bg=PANEL, padx=8, pady=8)
        notebook.add(prompt_panel, text="복사 프롬프트")
        notebook.add(template_panel, text="기본 템플릿")
        notebook.add(style_panel, text="스타일 토큰")

        prompt_header = tk.Frame(prompt_panel, bg=PANEL)
        prompt_header.pack(side=tk.TOP, fill=tk.X, pady=(0, 6))

        tk.Label(
            prompt_header,
            text="복사될 Codex 프롬프트",
            bg=PANEL,
            fg=TEXT,
            anchor="w",
        ).pack(side=tk.LEFT)
        self._button(prompt_header, "프롬프트 초기화", self.reset_prompt).pack(side=tk.RIGHT)

        self.prompt_text = tk.Text(
            prompt_panel,
            height=8,
            bg=BG,
            fg=TEXT,
            insertbackground=TEXT,
            relief=tk.FLAT,
            wrap=tk.WORD,
            padx=8,
            pady=8,
            undo=True,
        )
        self.prompt_text.pack(side=tk.TOP, fill=tk.X)
        self.prompt_text.bind("<<Modified>>", self._prompt_modified)

        template_header = tk.Frame(template_panel, bg=PANEL)
        template_header.pack(side=tk.TOP, fill=tk.X, pady=(0, 6))

        tk.Label(
            template_header,
            text="기본 프롬프트 템플릿",
            bg=PANEL,
            fg=TEXT,
            anchor="w",
        ).pack(side=tk.LEFT)
        self._button(template_header, "기본값 복원", self.restore_builtin_template).pack(
            side=tk.RIGHT, padx=(6, 0)
        )
        self._button(template_header, "다시 읽기", self.reload_template).pack(
            side=tk.RIGHT, padx=(6, 0)
        )
        self._button(template_header, "템플릿 저장", self.save_template).pack(side=tk.RIGHT)

        template_path_row = tk.Frame(template_panel, bg=PANEL)
        template_path_row.pack(side=tk.TOP, fill=tk.X, pady=(0, 6))
        tk.Label(
            template_path_row,
            text=f"파일: {template_path()}",
            bg=PANEL,
            fg=MUTED,
            anchor="w",
            justify=tk.LEFT,
            wraplength=310,
        ).pack(side=tk.LEFT, fill=tk.X, expand=True)
        self._button(template_path_row, "경로 복사", self.copy_template_path).pack(
            side=tk.RIGHT, padx=(6, 0)
        )
        self._button(template_path_row, "Finder에서 보기", self.reveal_template_file).pack(
            side=tk.RIGHT
        )

        self.template_text = tk.Text(
            template_panel,
            height=7,
            bg=BG,
            fg=TEXT,
            insertbackground=TEXT,
            relief=tk.FLAT,
            wrap=tk.WORD,
            padx=8,
            pady=8,
            undo=True,
        )
        self.template_text.pack(side=tk.TOP, fill=tk.X)
        self.template_text.bind("<<Modified>>", self._template_modified)
        self.set_template_text(self.prompt_template, dirty=False)

        style_header = tk.Frame(style_panel, bg=PANEL)
        style_header.pack(side=tk.TOP, fill=tk.X, pady=(0, 6))

        tk.Label(
            style_header,
            text="아트 스타일 토큰",
            bg=PANEL,
            fg=TEXT,
            anchor="w",
        ).pack(side=tk.LEFT)
        self._button(style_header, "원본 복사", self.copy_art_style_tokens).pack(
            side=tk.RIGHT, padx=(6, 0)
        )
        self._button(style_header, "다시 읽기", self.reload_art_style_tokens).pack(side=tk.RIGHT)

        style_path_row = tk.Frame(style_panel, bg=PANEL)
        style_path_row.pack(side=tk.TOP, fill=tk.X, pady=(0, 6))
        self.style_file_path = self.project_root / ART_STYLE_TOKENS_PATH
        tk.Label(
            style_path_row,
            text=f"파일: {self.style_file_path}",
            bg=PANEL,
            fg=MUTED,
            anchor="w",
            justify=tk.LEFT,
            wraplength=310,
        ).pack(side=tk.LEFT, fill=tk.X, expand=True)
        self._button(style_path_row, "경로 복사", self.copy_art_style_path).pack(
            side=tk.RIGHT, padx=(6, 0)
        )
        self._button(style_path_row, "Finder에서 보기", self.reveal_art_style_file).pack(
            side=tk.RIGHT
        )

        self.palette_frame = tk.Frame(style_panel, bg=BG, padx=8, pady=6)
        self.palette_frame.pack(side=tk.TOP, fill=tk.X, pady=(0, 6))

        style_text_frame = tk.Frame(style_panel, bg=PANEL)
        style_text_frame.pack(side=tk.TOP, fill=tk.X)
        self.style_text = tk.Text(
            style_text_frame,
            height=7,
            bg=BG,
            fg=TEXT,
            insertbackground=TEXT,
            relief=tk.FLAT,
            wrap=tk.WORD,
            padx=8,
            pady=8,
        )
        style_scrollbar = tk.Scrollbar(style_text_frame, orient=tk.VERTICAL, command=self.style_text.yview)
        self.style_text.configure(yscrollcommand=style_scrollbar.set)
        self.style_text.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        style_scrollbar.pack(side=tk.RIGHT, fill=tk.Y)
        self.reload_art_style_tokens()

        status = tk.Label(
            bottom_panel,
            textvariable=self.status_var,
            anchor="w",
            bg=PANEL,
            fg=MUTED,
            padx=0,
            pady=6,
        )
        status.pack(side=tk.BOTTOM, fill=tk.X)

        image_area = tk.Frame(self, bg=BG)
        image_area.pack(side=tk.TOP, fill=tk.BOTH, expand=True)

        self.canvas = tk.Canvas(image_area, bg=BG, highlightthickness=0)
        scrollbar = tk.Scrollbar(image_area, orient=tk.VERTICAL, command=self.canvas.yview)
        self.grid_frame = tk.Frame(self.canvas, bg=BG, padx=10, pady=10)

        self.grid_window = self.canvas.create_window((0, 0), window=self.grid_frame, anchor="nw")
        self.canvas.configure(yscrollcommand=scrollbar.set)
        self.canvas.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        scrollbar.pack(side=tk.RIGHT, fill=tk.Y)

        self.grid_frame.bind("<Configure>", self._update_scroll_region)
        self.canvas.bind("<Configure>", self._resize_grid_window)
        self.canvas.bind_all("<MouseWheel>", self._on_mousewheel)

    def _button(self, parent: tk.Widget, text: str, command) -> tk.Button:
        return tk.Button(
            parent,
            text=text,
            command=command,
            bg=BG,
            fg=TEXT,
            activebackground=PANEL,
            activeforeground=TEXT,
            relief=tk.FLAT,
            padx=10,
            pady=5,
            highlightthickness=1,
            highlightbackground=BORDER,
        )

    def choose_root(self) -> None:
        chosen = filedialog.askdirectory(initialdir=self.path_var.get() or str(self.project_root))
        if not chosen:
            return
        self.path_var.set(chosen)
        self.rescan()

    def rescan(self) -> None:
        root = Path(self.path_var.get()).expanduser()
        if not root.is_absolute():
            root = (self.project_root / root).resolve()
        self.asset_root = root
        self.path_var.set(str(root))
        self.images = find_images(root, self.project_root)
        self.selected = {path for path in self.selected if path in {item.path for item in self.images}}
        self.apply_filter()
        self.update_prompt_preview(force=True)

    def apply_filter(self) -> None:
        query = self.filter_var.get().strip().lower()
        if query:
            self.filtered_images = [
                item for item in self.images if query in item.relative_path.as_posix().lower()
            ]
        else:
            self.filtered_images = list(self.images)
        self.render_grid()

    def render_grid(self) -> None:
        for child in self.grid_frame.winfo_children():
            child.destroy()
        self.thumbnail_refs.clear()

        if not self.filtered_images:
            tk.Label(
                self.grid_frame,
                text="이미지가 없습니다",
                bg=BG,
                fg=MUTED,
                font=("TkDefaultFont", 15),
                pady=40,
            ).grid(row=0, column=0, sticky="n")
            self._set_status()
            return

        width = max(self.canvas.winfo_width(), 720)
        cell_width = 168
        columns = max(1, width // cell_width)

        for index, item in enumerate(self.filtered_images):
            row = index // columns
            column = index % columns
            self._add_cell(item, row, column)

        self._set_status()

    def _add_cell(self, item: AssetImage, row: int, column: int) -> None:
        is_selected = item.path in self.selected
        bg = SELECTED if is_selected else BG
        fg = SELECTED_TEXT if is_selected else TEXT
        meta_fg = SELECTED_TEXT if is_selected else MUTED

        cell = tk.Frame(
            self.grid_frame,
            bg=bg,
            padx=8,
            pady=8,
            highlightthickness=1,
            highlightbackground=SELECTED if is_selected else BORDER,
            width=150,
            height=190,
        )
        cell.grid(row=row, column=column, padx=6, pady=6, sticky="n")
        cell.grid_propagate(False)

        thumb, meta = self._load_thumbnail(item.path)
        if thumb is not None:
            self.thumbnail_refs.append(thumb)
            image_label = tk.Label(cell, image=thumb, bg=bg)
        else:
            image_label = tk.Label(
                cell,
                text="미리보기\n불가",
                bg=bg,
                fg=ERROR if not is_selected else SELECTED_TEXT,
                width=15,
                height=6,
                justify=tk.CENTER,
            )
        image_label.pack(side=tk.TOP, pady=(0, 6))

        name_label = tk.Label(
            cell,
            text=item.relative_path.name,
            bg=bg,
            fg=fg,
            wraplength=130,
            justify=tk.CENTER,
        )
        name_label.pack(side=tk.TOP)

        rel_parent = item.relative_path.parent.as_posix()
        detail = f"{meta} | {rel_parent}"
        detail_label = tk.Label(
            cell,
            text=detail,
            bg=bg,
            fg=meta_fg,
            wraplength=130,
            justify=tk.CENTER,
            font=("TkDefaultFont", 9),
        )
        detail_label.pack(side=tk.BOTTOM, pady=(4, 0))

        for widget in (cell, image_label, name_label, detail_label):
            widget.bind("<Button-1>", lambda _event, asset=item: self.toggle_selection(asset))
            widget.bind("<Double-Button-1>", lambda _event, asset=item: self.copy_single_prompt(asset))

    def _load_thumbnail(self, path: Path) -> tuple[tk.PhotoImage | None, str]:
        scale = max(1, self.scale_var.get())

        if Image is not None and ImageTk is not None:
            try:
                with Image.open(path) as opened:
                    image = opened.convert("RGBA")
                    width, height = image.size
                    meta_suffix = ""
                    if self.palette_preview_var.get():
                        palette = extract_palette_colors(self.art_style_data)
                        if palette:
                            image = recolor_image_to_palette(image, palette)
                            meta_suffix = " | 팔레트 테스트"
                        else:
                            meta_suffix = " | 팔레트 없음"
                    target_width, target_height = self._scaled_size(width, height, scale)
                    resampling = getattr(Image, "Resampling", Image)
                    image = image.resize((target_width, target_height), resampling.NEAREST)
                    return ImageTk.PhotoImage(image), f"{width}x{height}{meta_suffix}"
            except Exception as exc:  # Tk fallback may still work for PNG/GIF.
                pil_error = exc
        else:
            pil_error = None

        if self.palette_preview_var.get():
            return None, "팔레트 테스트는 Pillow 필요"

        try:
            image = tk.PhotoImage(file=str(path))
            width, height = image.width(), image.height()
            target_width, target_height = self._scaled_size(width, height, scale)
            zoom = max(1, min(target_width // max(width, 1), target_height // max(height, 1)))
            if zoom > 1:
                image = image.zoom(zoom, zoom)
            elif max(width, height) > 192:
                subsample = math.ceil(max(width, height) / 192)
                image = image.subsample(subsample, subsample)
            return image, f"{width}x{height}"
        except Exception as exc:
            if pil_error is not None:
                return None, f"{path.suffix.lower()} 지원 안 됨"
            return None, f"읽기 오류: {exc.__class__.__name__}"

    def _scaled_size(self, width: int, height: int, scale: int) -> tuple[int, int]:
        max_dimension = max(width, height)
        if max_dimension <= 64:
            return max(1, width * scale), max(1, height * scale)

        fit_scale = min(1.0, 192 / max_dimension)
        return max(1, int(width * fit_scale)), max(1, int(height * fit_scale))

    def toggle_selection(self, asset: AssetImage) -> None:
        if asset.path in self.selected:
            self.selected.remove(asset.path)
        else:
            self.selected.add(asset.path)
        self.render_grid()
        self.update_prompt_preview()

    def select_all(self) -> None:
        self.selected.update(item.path for item in self.filtered_images)
        self.render_grid()
        self.update_prompt_preview()

    def clear_selection(self) -> None:
        self.selected.clear()
        self.render_grid()
        self.update_prompt_preview()

    def selected_assets(self) -> list[AssetImage]:
        selected = set(self.selected)
        return [item for item in self.images if item.path in selected]

    def selected_relative_paths(self) -> list[str]:
        return [item.relative_path.as_posix() for item in self.selected_assets()]

    def selected_absolute_paths(self) -> list[str]:
        return [str(item.path) for item in self.selected_assets()]

    def copy_relative_paths(self) -> None:
        self._copy_lines(self.selected_relative_paths(), "상대경로")

    def copy_absolute_paths(self) -> None:
        self._copy_lines(self.selected_absolute_paths(), "절대경로")

    def copy_codex_prompt(self) -> None:
        paths = self.selected_relative_paths()
        if not paths:
            self._warn_no_selection()
            return
        prompt = self.prompt_text.get("1.0", "end-1c").strip()
        if not prompt:
            self._warn_empty_prompt()
            return
        self._copy_text(prompt + "\n", "Codex 프롬프트")

    def copy_single_prompt(self, asset: AssetImage) -> None:
        prompt = render_prompt_template(
            self.prompt_template,
            [asset.relative_path.as_posix()],
            self.project_root,
        )
        self.set_prompt_text(prompt, dirty=False)
        self._copy_text(prompt, "단일 이미지 프롬프트")

    def reset_prompt(self) -> None:
        self.update_prompt_preview(force=True)

    def update_prompt_preview(self, force: bool = False) -> None:
        if self.prompt_dirty and not force:
            return
        paths = self.selected_relative_paths()
        if paths:
            prompt = render_prompt_template(self.prompt_template, paths, self.project_root)
        else:
            prompt = "이미지를 선택하면 여기에 복사될 Codex 프롬프트가 표시됩니다.\n"
        self.set_prompt_text(prompt, dirty=False)

    def set_prompt_text(self, text: str, dirty: bool) -> None:
        self.updating_prompt = True
        self.prompt_text.delete("1.0", tk.END)
        self.prompt_text.insert("1.0", text)
        self.prompt_text.edit_modified(False)
        self.prompt_dirty = dirty
        self.updating_prompt = False

    def _prompt_modified(self, _event: tk.Event) -> None:
        if self.updating_prompt:
            self.prompt_text.edit_modified(False)
            return
        if self.prompt_text.edit_modified():
            self.prompt_dirty = True
            self.prompt_text.edit_modified(False)
            self._set_status()

    def save_template(self) -> None:
        content = self.template_text.get("1.0", "end-1c")
        if not content.strip():
            self._warn_empty_template()
            return
        if "{asset_list}" not in content:
            ok = messagebox.askokcancel(
                "이미지 목록 치환값 없음",
                "{asset_list}가 없으면 이미지 목록이 프롬프트 끝에 자동으로 붙습니다. 계속 저장할까요?",
            )
            if not ok:
                return
        save_prompt_template(content if content.endswith("\n") else f"{content}\n")
        self.prompt_template = load_prompt_template()
        self.set_template_text(self.prompt_template, dirty=False)
        self.update_prompt_preview(force=True)
        self.status_var.set(f"템플릿 저장 완료: {template_path()}")

    def reload_template(self) -> None:
        self.prompt_template = load_prompt_template()
        self.set_template_text(self.prompt_template, dirty=False)
        self.update_prompt_preview(force=True)
        self.status_var.set(f"템플릿 다시 읽음: {template_path()}")

    def restore_builtin_template(self) -> None:
        self.prompt_template = BUILTIN_PROMPT_TEMPLATE
        self.set_template_text(self.prompt_template, dirty=True)
        self.update_prompt_preview(force=True)
        self.status_var.set("기본 템플릿을 편집창에 복원했습니다. 저장하면 파일에 반영됩니다.")

    def reload_art_style_tokens(self) -> None:
        path = self.project_root / ART_STYLE_TOKENS_PATH
        data, error = load_art_style_tokens(self.project_root)
        self.art_style_data = data
        if path.exists():
            self.art_style_raw = path.read_text(encoding="utf-8")
        else:
            self.art_style_raw = ""
        self.render_palette_swatches(data)
        self.style_text.configure(state=tk.NORMAL)
        self.style_text.delete("1.0", tk.END)
        self.style_text.insert("1.0", format_art_style_tokens(data, error))
        self.style_text.configure(state=tk.DISABLED)
        if error:
            self.status_var.set(error)
        else:
            self.status_var.set(f"아트 스타일 토큰 다시 읽음: {ART_STYLE_TOKENS_PATH.as_posix()}")
        if self.palette_preview_var.get():
            self.render_grid()

    def copy_art_style_tokens(self) -> None:
        if not self.art_style_raw:
            self._warn_no_art_style_tokens()
            return
        self._copy_text(self.art_style_raw, "아트 스타일 토큰 원본")
        self.status_var.set("아트 스타일 토큰 원본 복사 완료")

    def render_palette_swatches(self, data: dict | None) -> None:
        for child in self.palette_frame.winfo_children():
            child.destroy()

        if data is None:
            tk.Label(
                self.palette_frame,
                text="팔레트 없음",
                bg=BG,
                fg=MUTED,
                anchor="w",
            ).grid(row=0, column=0, sticky="w")
            return

        palette = data.get("palette", {})
        global_palette = palette.get("global", [])
        biome_accents = palette.get("biome_accents", [])

        tk.Label(self.palette_frame, text="전역 팔레트", bg=BG, fg=TEXT, anchor="w").grid(
            row=0, column=0, columnspan=2, sticky="w", pady=(0, 4)
        )
        tk.Label(
            self.palette_frame,
            text="색상칩 클릭으로 수정",
            bg=BG,
            fg=MUTED,
            anchor="e",
        ).grid(row=0, column=1, sticky="e", pady=(0, 4))
        for index, color in enumerate(global_palette[:14]):
            row = 1 + index // 2
            column = index % 2
            self._add_color_swatch(
                self.palette_frame,
                row,
                column,
                color.get("hex", ""),
                color.get("name", color.get("id", "색상")),
                lambda selected, color_index=index: self.update_global_palette_color(
                    color_index,
                    selected,
                ),
            )

        accent_start_row = 1 + math.ceil(min(len(global_palette), 14) / 2)
        if biome_accents:
            tk.Label(
                self.palette_frame,
                text="바이옴 포인트",
                bg=BG,
                fg=TEXT,
                anchor="w",
            ).grid(row=accent_start_row, column=0, columnspan=2, sticky="w", pady=(8, 4))
            for index, accent in enumerate(biome_accents[:4]):
                row = accent_start_row + 1 + index // 2
                column = index % 2
                self._add_accent_swatch(
                self.palette_frame,
                row,
                column,
                accent.get("colors", []),
                accent.get("name", accent.get("id", "바이옴")),
                index,
            )

    def _add_color_swatch(
        self,
        parent: tk.Widget,
        row: int,
        column: int,
        hex_color: str,
        name: str,
        on_pick,
    ) -> None:
        item = tk.Frame(parent, bg=BG)
        item.grid(row=row, column=column, sticky="w", padx=(0, 12), pady=2)
        canvas = tk.Canvas(item, width=22, height=18, bg=BG, highlightthickness=1, highlightbackground=BORDER)
        canvas.pack(side=tk.LEFT)
        self._safe_rectangle(canvas, 2, 2, 20, 16, hex_color)
        canvas.configure(cursor="hand2")
        tk.Label(
            item,
            text=f"{name} {hex_color}",
            bg=BG,
            fg=TEXT,
            anchor="w",
            font=("TkDefaultFont", 9),
        ).pack(side=tk.LEFT, padx=(5, 0))
        canvas.bind(
            "<Button-1>",
            lambda _event, current=hex_color, label=name, callback=on_pick: self.pick_palette_color(
                current,
                label,
                callback,
            ),
        )

    def _add_accent_swatch(
        self,
        parent: tk.Widget,
        row: int,
        column: int,
        colors: list[str],
        name: str,
        accent_index: int,
    ) -> None:
        item = tk.Frame(parent, bg=BG)
        item.grid(row=row, column=column, sticky="w", padx=(0, 12), pady=2)
        for index, hex_color in enumerate(colors[:3]):
            canvas = tk.Canvas(
                item,
                width=14,
                height=18,
                bg=BG,
                highlightthickness=1,
                highlightbackground=BORDER,
            )
            canvas.pack(side=tk.LEFT)
            self._safe_rectangle(canvas, 2, 2, 12, 16, hex_color)
            canvas.configure(cursor="hand2")
            canvas.bind(
                "<Button-1>",
                lambda _event,
                current=hex_color,
                label=f"{name} {index + 1}",
                accent=accent_index,
                color_index=index: self.pick_palette_color(
                    current,
                    label,
                    lambda selected: self.update_biome_accent_color(accent, color_index, selected),
                ),
            )
        tk.Label(
            item,
            text=name,
            bg=BG,
            fg=TEXT,
            anchor="w",
            font=("TkDefaultFont", 9),
        ).pack(side=tk.LEFT, padx=(5, 0))

    def _safe_rectangle(
        self,
        canvas: tk.Canvas,
        x0: int,
        y0: int,
        x1: int,
        y1: int,
        hex_color: str,
    ) -> None:
        try:
            canvas.create_rectangle(x0, y0, x1, y1, fill=hex_color, outline="")
        except tk.TclError:
            canvas.create_rectangle(x0, y0, x1, y1, fill=ERROR, outline="")

    def pick_palette_color(self, current_hex: str, name: str, on_pick) -> None:
        selected = colorchooser.askcolor(
            color=normalize_hex_color(current_hex),
            title=f"{name} 색상 선택",
            parent=self,
        )
        if not selected or not selected[1]:
            return
        on_pick(normalize_hex_color(selected[1]))

    def update_global_palette_color(self, color_index: int, hex_color: str) -> None:
        if self.art_style_data is None:
            self._warn_no_art_style_tokens()
            return
        palette = self.art_style_data.get("palette", {})
        global_palette = palette.get("global", [])
        if color_index >= len(global_palette):
            return
        global_palette[color_index]["hex"] = hex_color
        self.persist_art_style_tokens(f"전역 팔레트 색상 저장: {hex_color}")

    def update_biome_accent_color(self, accent_index: int, color_index: int, hex_color: str) -> None:
        if self.art_style_data is None:
            self._warn_no_art_style_tokens()
            return
        palette = self.art_style_data.get("palette", {})
        biome_accents = palette.get("biome_accents", [])
        if accent_index >= len(biome_accents):
            return
        colors = biome_accents[accent_index].get("colors", [])
        if color_index >= len(colors):
            return
        colors[color_index] = hex_color
        self.persist_art_style_tokens(f"바이옴 포인트 색상 저장: {hex_color}")

    def persist_art_style_tokens(self, status: str) -> None:
        if self.art_style_data is None:
            return
        save_art_style_tokens(self.project_root, self.art_style_data)
        self.reload_art_style_tokens()
        if self.palette_preview_var.get():
            self.render_grid()
        self.status_var.set(status)

    def copy_template_path(self) -> None:
        self._copy_text(str(template_path()), "템플릿 파일 경로")
        self.status_var.set("템플릿 파일 경로 복사 완료")

    def copy_art_style_path(self) -> None:
        self._copy_text(str(self.project_root / ART_STYLE_TOKENS_PATH), "아트 스타일 토큰 파일 경로")
        self.status_var.set("아트 스타일 토큰 파일 경로 복사 완료")

    def reveal_template_file(self) -> None:
        self.reveal_in_finder(template_path())

    def reveal_art_style_file(self) -> None:
        self.reveal_in_finder(self.project_root / ART_STYLE_TOKENS_PATH)

    def reveal_asset_root(self) -> None:
        self.reveal_in_finder(self.asset_root)

    def reveal_in_finder(self, path: Path) -> None:
        target = path if path.exists() else path.parent
        try:
            subprocess.run(["open", "-R", str(target)], check=True)
            self.status_var.set(f"Finder에서 표시: {target}")
        except (OSError, subprocess.CalledProcessError) as exc:
            messagebox.showerror("Finder 열기 실패", f"{target}\n\n{exc}")

    def set_template_text(self, text: str, dirty: bool) -> None:
        self.updating_template = True
        self.template_text.delete("1.0", tk.END)
        self.template_text.insert("1.0", text)
        self.template_text.edit_modified(False)
        self.template_dirty = dirty
        self.updating_template = False

    def _template_modified(self, _event: tk.Event) -> None:
        if self.updating_template:
            self.template_text.edit_modified(False)
            return
        if self.template_text.edit_modified():
            self.template_dirty = True
            self.template_text.edit_modified(False)
            self._set_status()

    def save_txt(self) -> None:
        paths = self.selected_relative_paths()
        if not paths:
            self._warn_no_selection()
            return
        target = filedialog.asksaveasfilename(
            initialdir=str(self.project_root / "tools" / "asset_browser"),
            initialfile="selected_assets.txt",
            defaultextension=".txt",
            filetypes=[("텍스트 파일", "*.txt"), ("모든 파일", "*.*")],
        )
        if not target:
            return
        Path(target).write_text("\n".join(paths) + "\n", encoding="utf-8")
        self.status_var.set(f"{len(paths)}개 경로를 저장했습니다: {target}")

    def _copy_lines(self, lines: list[str], label: str) -> None:
        if not lines:
            self._warn_no_selection()
            return
        self._copy_text("\n".join(lines) + "\n", label)

    def _copy_text(self, text: str, label: str) -> None:
        self.clipboard_clear()
        self.clipboard_append(text)
        self.update()
        self.status_var.set(f"{label} 복사 완료: {len(self.selected)}개 선택됨")

    def _warn_no_selection(self) -> None:
        messagebox.showinfo("선택 없음", "먼저 이미지를 하나 이상 선택하세요.")

    def _warn_empty_prompt(self) -> None:
        messagebox.showinfo("프롬프트 없음", "복사할 프롬프트 내용을 입력하세요.")

    def _warn_empty_template(self) -> None:
        messagebox.showinfo("템플릿 없음", "저장할 기본 프롬프트 템플릿을 입력하세요.")

    def _warn_no_art_style_tokens(self) -> None:
        messagebox.showinfo("토큰 없음", "복사할 아트 스타일 토큰 파일을 찾지 못했습니다.")

    def _set_status(self) -> None:
        suffixes = []
        if self.prompt_dirty:
            suffixes.append("프롬프트 수정됨")
        if self.template_dirty:
            suffixes.append("템플릿 수정됨")
        suffix = f" | {' | '.join(suffixes)}" if suffixes else ""
        self.status_var.set(
            f"전체 {len(self.images)}개 | 표시 {len(self.filtered_images)}개 | 선택 {len(self.selected)}개{suffix}"
        )

    def _scale_changed(self, _value: str) -> None:
        self.render_grid()

    def toggle_palette_preview(self) -> None:
        self.render_grid()
        if self.palette_preview_var.get():
            self.status_var.set("팔레트 테스트 보기: 원본 파일은 변경하지 않습니다.")
        else:
            self._set_status()

    def apply_palette_to_shown_images(self) -> None:
        if Image is None:
            messagebox.showerror("Pillow 필요", "실제 이미지 변환에는 Pillow가 필요합니다.")
            return

        if not self.filtered_images:
            messagebox.showinfo("이미지 없음", "변환할 표시 이미지가 없습니다.")
            return

        palette = extract_palette_colors(self.art_style_data)
        if not palette:
            messagebox.showinfo("팔레트 없음", "적용할 팔레트 색상을 찾지 못했습니다.")
            return

        backup_root = palette_backup_root()
        count = len(self.filtered_images)
        ok = messagebox.askokcancel(
            "실제 이미지 변환 확인",
            "현재 화면에 표시된 이미지 전체를 팔레트 색으로 실제 변환합니다.\n\n"
            f"대상: {count}개\n"
            f"백업 위치: {backup_root}\n\n"
            "원본 파일이 덮어써집니다. 계속할까요?",
        )
        if not ok:
            return

        paths = [item.path for item in self.filtered_images]
        converted, failures = apply_palette_to_images(paths, palette, self.project_root, backup_root)
        self.rescan()
        if failures:
            self._copy_text("\n".join(failures) + "\n", "변환 실패 목록")
            messagebox.showwarning(
                "일부 변환 실패",
                f"{converted}개 변환 완료, {len(failures)}개 실패.\n"
                "실패 목록은 클립보드에 복사했습니다.",
            )
        else:
            messagebox.showinfo(
                "변환 완료",
                f"{converted}개 이미지를 변환했습니다.\n백업 위치: {backup_root}",
            )
        self.status_var.set(f"팔레트 실제 변환 완료: {converted}개 | 백업: {backup_root}")

    def _update_scroll_region(self, _event: tk.Event) -> None:
        self.canvas.configure(scrollregion=self.canvas.bbox("all"))

    def _resize_grid_window(self, event: tk.Event) -> None:
        self.canvas.itemconfigure(self.grid_window, width=event.width)
        self.render_grid()

    def _on_mousewheel(self, event: tk.Event) -> None:
        self.canvas.yview_scroll(int(-1 * (event.delta / 120)), "units")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="프로젝트 에셋 이미지를 확인하고 선택합니다.")
    parser.add_argument(
        "--root",
        default="assets",
        help="스캔할 이미지 폴더입니다. 기본값은 프로젝트 assets 폴더입니다.",
    )
    parser.add_argument(
        "--scale",
        type=int,
        default=4,
        choices=[2, 3, 4, 5, 6, 8],
        help="작은 픽셀아트 이미지를 보여줄 정수 미리보기 배율입니다.",
    )
    parser.add_argument(
        "--list-images",
        action="store_true",
        help="UI를 열지 않고 발견한 이미지 경로만 출력합니다.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    project_root = project_root_from_script()
    asset_root = Path(args.root).expanduser()
    if not asset_root.is_absolute():
        asset_root = (project_root / asset_root).resolve()

    if args.list_images:
        for image in find_images(asset_root, project_root):
            print(image.relative_path.as_posix())
        return 0

    app = AssetBrowser(project_root=project_root, asset_root=asset_root, scale=args.scale)
    app.mainloop()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
