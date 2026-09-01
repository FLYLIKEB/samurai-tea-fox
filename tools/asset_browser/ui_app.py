"""Tkinter UI for the local asset browser."""

from __future__ import annotations

import math
from pathlib import Path
import tkinter as tk

from .constants import BG, BORDER, ERROR, MUTED, SELECTED, SELECTED_TEXT, TEXT
from .constants import GRID_CELL_HEIGHT, GRID_CELL_PITCH, GRID_CELL_WIDTH, THUMBNAIL_BOX_SIZE
from .image_ops import Image, ImageTk, recolor_image_to_palette
from .models import AssetImage
from .prompting import load_prompt_template
from .style_tokens import extract_palette_colors
from .ui_actions import ActionsMixin
from .ui_layout import LayoutMixin
from .ui_palette import PalettePanelMixin

class AssetBrowser(LayoutMixin, PalettePanelMixin, ActionsMixin, tk.Tk):
    def __init__(self, project_root: Path, asset_root: Path, scale: int) -> None:
        super().__init__()
        self.project_root = project_root
        self.asset_root = asset_root
        self.scale_var = tk.IntVar(value=scale)
        self.palette_preview_var = tk.BooleanVar(value=False)
        self.bottom_panel_visible = tk.BooleanVar(value=False)
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
        columns = max(1, width // GRID_CELL_PITCH)

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
            padx=6,
            pady=6,
            highlightthickness=1,
            highlightbackground=SELECTED if is_selected else BORDER,
            width=GRID_CELL_WIDTH,
            height=GRID_CELL_HEIGHT,
        )
        cell.grid(row=row, column=column, padx=4, pady=4, sticky="n")
        cell.grid_propagate(False)

        image_box = tk.Frame(
            cell,
            bg=bg,
            width=THUMBNAIL_BOX_SIZE,
            height=THUMBNAIL_BOX_SIZE,
        )
        image_box.pack(side=tk.TOP)
        image_box.pack_propagate(False)

        thumb, meta = self._load_thumbnail(item.path)
        if thumb is not None:
            self.thumbnail_refs.append(thumb)
            image_label = tk.Label(image_box, image=thumb, bg=bg)
        else:
            image_label = tk.Label(
                image_box,
                text="미리보기\n불가",
                bg=bg,
                fg=ERROR if not is_selected else SELECTED_TEXT,
                width=15,
                height=6,
                justify=tk.CENTER,
            )
        image_label.pack(expand=True)

        name_label = tk.Label(
            cell,
            text=item.relative_path.name,
            bg=bg,
            fg=fg,
            wraplength=124,
            justify=tk.CENTER,
            height=2,
        )
        name_label.pack(side=tk.TOP)

        rel_parent = item.relative_path.parent.as_posix()
        detail = f"{meta} | {rel_parent}"
        detail_label = tk.Label(
            cell,
            text=detail,
            bg=bg,
            fg=meta_fg,
            wraplength=124,
            justify=tk.CENTER,
            font=("TkDefaultFont", 9),
            height=2,
        )
        detail_label.pack(side=tk.BOTTOM)

        for widget in (cell, image_box, image_label, name_label, detail_label):
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

        fit_scale = min(1.0, THUMBNAIL_BOX_SIZE / max_dimension)
        return max(1, int(width * fit_scale)), max(1, int(height * fit_scale))
