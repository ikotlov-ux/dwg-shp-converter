#!/usr/bin/env python3
"""Точка входа геопространственного конвертера (GUI на tkinter).

Запуск:
    python app.py
"""

from __future__ import annotations

import importlib
import sys

# Перезагрузка модулей при повторном запуске из одной сессии (например, в JupyterLab)
for _mod_name in (
    "geoconverter",
    "geoconverter.crs",
    "geoconverter.features",
    "geoconverter.core",
    "geoconverter.gui",
):
    if _mod_name in sys.modules:
        importlib.reload(sys.modules[_mod_name])

from geoconverter.gui import run


if __name__ == "__main__":
    sys.exit(run())
