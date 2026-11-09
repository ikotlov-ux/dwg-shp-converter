#!/usr/bin/env python3
"""Точка входа геопространственного конвертера (GUI на tkinter).

Запуск:
    python app.py
"""

from __future__ import annotations

import sys

from geoconverter.gui import run


if __name__ == "__main__":
    sys.exit(run())
