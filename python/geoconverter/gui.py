"""Графический интерфейс конвертера (tkinter, только stdlib, русский язык).

Конвертация выполняется в фоновом потоке: кнопки не блокируются,
сообщения лога передаются в GUI через очередь и опрос widget.after.
"""

from __future__ import annotations

import os
import queue
import threading
import traceback
import tkinter as tk
from tkinter import filedialog, messagebox, scrolledtext, ttk

from . import __version__
from . import core, crs

APP_TITLE = f"Геопространственный конвертер {__version__}"

# Разрешённые входные расширения (мультивыбор в диалоге).
FILETYPES = [
    ("Геоданные", "*.dwg *.dxf *.shp *.geojson *.gpkg"),
    ("AutoCAD DWG", "*.dwg"),
    ("AutoCAD DXF", "*.dxf"),
    ("Shapefile", "*.shp"),
    ("GeoJSON", "*.geojson *.json"),
    ("GeoPackage", "*.gpkg"),
    ("Все файлы", "*.*"),
]


class ConverterApp:
    """Главное окно приложения."""

    def __init__(self, root: tk.Tk) -> None:
        self.root = root
        root.title(APP_TITLE)
        root.geometry("980x720")

        self.log_queue: queue.Queue = queue.Queue()
        self.worker: threading.Thread | None = None
        self._build_ui()
        self._poll_log()
        self._init_tool_paths()

    # ------------------------------------------------------------------ UI
    def _build_ui(self) -> None:
        pad = {"padx": 6, "pady": 3}

        # --- Файлы ---
        files = ttk.LabelFrame(self.root, text="Входные файлы")
        files.pack(fill="both", expand=False, padx=8, pady=4)
        self.file_list = tk.Listbox(files, selectmode="extended", height=6)
        self.file_list.pack(side="left", fill="both", expand=True,
                            padx=(6, 2), pady=6)
        btns = ttk.Frame(files)
        btns.pack(side="right", fill="y", padx=(2, 6), pady=6)
        ttk.Button(btns, text="Добавить файлы…",
                   command=self.add_files).pack(fill="x", pady=2)
        ttk.Button(btns, text="Удалить выбранные",
                   command=self.remove_selected).pack(fill="x", pady=2)
        ttk.Button(btns, text="Очистить список",
                   command=lambda: self.file_list.delete(0, "end")).pack(
                       fill="x", pady=2)

        # --- Системы координат ---
        crs_frame = ttk.LabelFrame(
            self.root, text="Системы координат (СК)")
        crs_frame.pack(fill="x", padx=8, pady=4)
        self.crs_keys = crs.CRS_KEYS  # wgs84, mggt, dgi, dgi_shift, custom
        labels = [crs.crs_label(k) for k in self.crs_keys]

        ttk.Label(crs_frame, text="Исходная СК:").grid(
            row=0, column=0, sticky="w", **pad)
        self.src_crs = ttk.Combobox(crs_frame, values=labels,
                                    state="readonly", width=42)
        self.src_crs.current(0)
        self.src_crs.grid(row=0, column=1, sticky="w", **pad)

        ttk.Label(crs_frame, text="Целевая СК:").grid(
            row=1, column=0, sticky="w", **pad)
        self.dst_crs = ttk.Combobox(crs_frame, values=labels,
                                    state="readonly", width=42)
        self.dst_crs.current(0)
        self.dst_crs.grid(row=1, column=1, sticky="w", **pad)

        ttk.Label(crs_frame, text="PROJ-строка\n(пользовательская СК):").grid(
            row=2, column=0, sticky="nw", **pad)
        self.custom_proj = ttk.Entry(crs_frame, width=56)
        self.custom_proj.grid(row=2, column=1, sticky="w", **pad)

        # --- Выход ---
        out_frame = ttk.LabelFrame(self.root, text="Выходные данные")
        out_frame.pack(fill="x", padx=8, pady=4)
        ttk.Label(out_frame, text="Формат:").grid(row=0, column=0, sticky="w", **pad)
        self.out_format = ttk.Combobox(
            out_frame, values=list(core.OUTPUT_DRIVERS), state="readonly",
            width=10)
        self.out_format.current(0)
        self.out_format.grid(row=0, column=1, sticky="w", **pad)
        self.out_format.bind("<<ComboboxSelected>>", self._on_format_change)

        ttk.Label(out_frame, text="Папка:").grid(row=1, column=0, sticky="w", **pad)
        self.out_dir = ttk.Entry(out_frame, width=70)
        self.out_dir.grid(row=1, column=1, columnspan=2, sticky="we", **pad)
        ttk.Button(out_frame, text="Обзор…",
                   command=self.choose_out_dir).grid(row=1, column=3, **pad)

        # --- Опции вектор -> DWG ---
        self.dwg_frame = ttk.LabelFrame(
            self.root, text="Оформление «вектор → DWG/DXF» (точки)")
        self.dwg_frame.pack(fill="x", padx=8, pady=4)
        r = 0
        ttk.Label(self.dwg_frame, text="Разбивка по полю:").grid(
            row=r, column=0, sticky="w", **pad)
        self.split_field = ttk.Entry(self.dwg_frame, width=20)
        self.split_field.grid(row=r, column=1, sticky="w", **pad)

        ttk.Label(self.dwg_frame, text="Цвет маркеров по полю:").grid(
            row=r, column=2, sticky="w", **pad)
        self.color_field = ttk.Entry(self.dwg_frame, width=20)
        self.color_field.grid(row=r, column=3, sticky="w", **pad)

        r += 1
        self.var_markers = tk.BooleanVar(value=True)
        ttk.Checkbutton(self.dwg_frame, text="Маркеры точек, диаметр (м):",
                        variable=self.var_markers).grid(
                            row=r, column=0, sticky="w", **pad)
        self.marker_diameter = ttk.Entry(self.dwg_frame, width=8)
        self.marker_diameter.insert(0, "2.0")
        self.marker_diameter.grid(row=r, column=1, sticky="w", **pad)

        self.var_labels = tk.BooleanVar(value=True)
        ttk.Checkbutton(self.dwg_frame, text="Подписи точек (поле):",
                        variable=self.var_labels).grid(
                            row=r, column=2, sticky="w", **pad)
        self.label_field = ttk.Entry(self.dwg_frame, width=20)
        self.label_field.grid(row=r, column=3, sticky="w", **pad)
        ttk.Label(self.dwg_frame, text="высота текста:").grid(
            row=r, column=4, sticky="w", **pad)
        self.label_height = ttk.Entry(self.dwg_frame, width=6)
        self.label_height.insert(0, "2.5")
        self.label_height.grid(row=r, column=5, sticky="w", **pad)

        r += 1
        self.var_legend = tk.BooleanVar(value=True)
        ttk.Checkbutton(
            self.dwg_frame,
            text="Легенда с цифровыми кодами (справа-снизу, отступ ≥ 20 м)",
            variable=self.var_legend).grid(row=r, column=0, columnspan=2,
                                           sticky="w", **pad)
        self.var_xlsx = tk.BooleanVar(value=True)
        ttk.Checkbutton(self.dwg_frame, text="Выгрузка точек в XLSX",
                        variable=self.var_xlsx).grid(
                            row=r, column=2, columnspan=2, sticky="w", **pad)

        # --- Инструменты ---
        tools = ttk.LabelFrame(self.root, text="Инструменты")
        tools.pack(fill="x", padx=8, pady=4)
        ttk.Label(tools, text="ogr2ogr:").grid(row=0, column=0, sticky="w", **pad)
        self.ogr2ogr_path = ttk.Entry(tools, width=70)
        self.ogr2ogr_path.grid(row=0, column=1, columnspan=2, sticky="we", **pad)
        ttk.Button(tools, text="Обзор…",
                   command=lambda: self._browse_exe(self.ogr2ogr_path)
                   ).grid(row=0, column=3, **pad)

        ttk.Label(tools, text="ODA File Converter:").grid(
            row=1, column=0, sticky="w", **pad)
        self.oda_path = ttk.Entry(tools, width=70)
        self.oda_path.grid(row=1, column=1, columnspan=2, sticky="we", **pad)
        ttk.Button(tools, text="Обзор…",
                   command=lambda: self._browse_exe(self.oda_path)
                   ).grid(row=1, column=3, **pad)

        # --- Лог и запуск ---
        self.run_btn = ttk.Button(self.root, text="Конвертировать",
                                  command=self.start_conversion)
        self.run_btn.pack(fill="x", padx=8, pady=4)

        self.log = scrolledtext.ScrolledText(self.root, wrap="word",
                                             height=14, state="disabled")
        self.log.pack(fill="both", expand=True, padx=8, pady=4)

        self.status = ttk.Label(self.root, text="Готов к работе",
                                relief="sunken", anchor="w")
        self.status.pack(fill="x", side="bottom", padx=8, pady=2)

    # ------------------------------------------------------------- действия
    def _init_tool_paths(self) -> None:
        """Автоопределение ogr2ogr и подстановка пути ODA по умолчанию."""
        found = core.find_ogr2ogr()
        if found:
            self.ogr2ogr_path.insert(0, found)
            self.log_msg(f"ogr2ogr найден: {found}")
        else:
            self.ogr2ogr_path.insert(0, "")
            self.log_msg(
                "ogr2ogr не найден автоматически. Укажите путь вручную "
                "(например, C:/Program Files/QGIS/bin/ogr2ogr.exe).")
        self.oda_path.insert(0, core.ODA_DEFAULT_PATH)

    def _browse_exe(self, entry: ttk.Entry) -> None:
        path = filedialog.askopenfilename(
            filetypes=[("Исполняемые файлы", "*.exe"), ("Все файлы", "*.*")])
        if path:
            entry.delete(0, "end")
            entry.insert(0, path)

    def add_files(self) -> None:
        """Диалог Проводника с мультивыбором + автоопределение СК по .prj."""
        paths = filedialog.askopenfilenames(
            title="Выберите файлы для конвертации", filetypes=FILETYPES)
        for p in paths:
            ext = os.path.splitext(p)[1].lower()
            if ext not in (".dwg", ".dxf", ".shp", ".geojson", ".gpkg"):
                self.log_msg(f"Пропущен неподдерживаемый файл: {p}")
                continue
            if p not in self.file_list.get(0, "end"):
                self.file_list.insert("end", p)
            # Автоопределение исходной СК по .prj (только Shapefile).
            if ext == ".shp":
                prj = os.path.splitext(p)[0] + ".prj"
                if os.path.isfile(prj):
                    key = crs.detect_crs_from_prj_file(prj)
                    if key:
                        self.src_crs.current(self.crs_keys.index(key))
                        self.log_msg(
                            f"По {os.path.basename(prj)} определена СК: "
                            f"{crs.crs_label(key)} — выбрана как исходная.")

    def remove_selected(self) -> None:
        for idx in reversed(self.file_list.curselection()):
            self.file_list.delete(idx)

    def choose_out_dir(self) -> None:
        d = filedialog.askdirectory(title="Выберите выходную папку")
        if d:
            self.out_dir.delete(0, "end")
            self.out_dir.insert(0, d)

    def _on_format_change(self, _event=None) -> None:
        """Опции оформления актуальны для DWG/DXF; для прочих — приглушены."""
        state = "normal" if self.out_format.get() in ("DWG", "DXF") else "disabled"
        for child in self.dwg_frame.winfo_children():
            if isinstance(child, (ttk.Entry, ttk.Checkbutton)):
                child.configure(state=state)

    # ---------------------------------------------------------- конвертация
    def _feature_options(self) -> dict:
        label_field = self.label_field.get().strip() if self.var_labels.get() else ""
        return {
            "markers": self.var_markers.get(),
            "marker_diameter": self._float(self.marker_diameter, 2.0),
            "color_field": self.color_field.get().strip(),
            "label_field": label_field,
            "label_height": self._float(self.label_height, 2.5),
            "legend": self.var_legend.get(),
            "xlsx": self.var_xlsx.get(),
            "split_field": self.split_field.get().strip(),
        }

    @staticmethod
    def _float(entry: ttk.Entry, default: float) -> float:
        try:
            return float(entry.get().replace(",", "."))
        except (ValueError, AttributeError):
            return default

    def _resolve_srs(self, combo: ttk.Combobox) -> str:
        key = self.crs_keys[combo.current()]
        return crs.resolve_crs(key, self.custom_proj.get())

    def start_conversion(self) -> None:
        """Запуск конвертации в фоновом потоке (кнопки не блокируются)."""
        if self.worker and self.worker.is_alive():
            messagebox.showwarning(APP_TITLE, "Конвертация уже выполняется.")
            return
        files = list(self.file_list.get(0, "end"))
        if not files:
            messagebox.showwarning(APP_TITLE, "Добавьте входные файлы.")
            return
        out_dir = self.out_dir.get().strip() or os.getcwd()
        out_format = self.out_format.get()
        try:
            s_srs = self._resolve_srs(self.src_crs)
            t_srs = self._resolve_srs(self.dst_crs)
        except ValueError as exc:
            messagebox.showerror(APP_TITLE, str(exc))
            return
        ogr2ogr = core.resolve_ogr2ogr(self.ogr2ogr_path.get().strip())
        if not ogr2ogr:
            messagebox.showerror(
                APP_TITLE,
                "ogr2ogr не найден. Установите QGIS/OSGeo4W или укажите путь.")
            return
        oda = core.find_oda(self.oda_path.get().strip())
        opts = self._feature_options() if out_format in ("DWG", "DXF") else {}

        self.run_btn.configure(state="disabled")
        self.status.configure(text="Конвертация…")
        self.worker = threading.Thread(
            target=self._worker, daemon=True,
            args=(files, out_format, out_dir, s_srs, t_srs, ogr2ogr, oda, opts),
        )
        self.worker.start()

    def _worker(self, files, out_format, out_dir, s_srs, t_srs,
                ogr2ogr, oda, opts) -> None:
        """Фоновый поток: последовательная конвертация всех файлов."""
        self.log_msg(f"=== Конвертация {len(files)} файл(ов) -> {out_format} ===")
        self.log_msg(f"Исходная СК: {s_srs}")
        self.log_msg(f"Целевая СК:   {t_srs}")
        try:
            ok = 0
            for i, path in enumerate(files, 1):
                self.log_msg(f"\n--- Файл {i}/{len(files)}: {path} ---")
                results = core.convert_one_file(
                    src=path, out_format=out_format, out_dir=out_dir,
                    s_srs=s_srs, t_srs=t_srs,
                    ogr2ogr_exe=ogr2ogr, oda_exe=oda,
                    log=self.log_msg, feature_options=opts,
                )
                if results:
                    ok += 1
            self.log_msg(
                f"\n=== Завершено: успешно {ok} из {len(files)} файл(ов), "
                f"папка: {out_dir} ===")
        except Exception:
            self.log_msg("ОШИБКА (внутренняя):\n" + traceback.format_exc())
        finally:
            self.log_queue.put(("__done__", None))

    # ------------------------------------------------------------- лог/статус
    def log_msg(self, message: str) -> None:
        """Положить сообщение в очередь лога (потокобезопасно)."""
        self.log_queue.put(("log", str(message)))

    def _poll_log(self) -> None:
        """Забрать сообщения из очереди в текстовое поле лога."""
        try:
            while True:
                kind, payload = self.log_queue.get_nowait()
                if kind == "log":
                    self.log.configure(state="normal")
                    self.log.insert("end", payload + "\n")
                    self.log.see("end")
                    self.log.configure(state="disabled")
                elif kind == "__done__":
                    self.run_btn.configure(state="normal")
                    self.status.configure(text="Готов к работе")
        except queue.Empty:
            pass
        self.root.after(100, self._poll_log)


def run() -> None:
    """Запустить приложение (точка входа GUI)."""
    root = tk.Tk()
    try:
        ttk.Style().theme_use("clam")
    except tk.TclError:
        pass
    ConverterApp(root)
    root.mainloop()
