#!/usr/bin/env python3
# MECHOS_MECHSCOPE_REFERENCE_COMPAT_V25
"""Runtime compatibility helpers for generated MechScope owners.

Some older generated owners retain the exact-reference MechScope layout while
losing the helper block that originally defined MechReferenceGauge and
mechos_gpu_load_percent.  Keep those small helpers source-owned here so the
stable runtime can restore only missing names in memory without rewriting the
installed owner.
"""
from __future__ import annotations

import subprocess

from PyQt6.QtWidgets import QWidget


class MechReferenceGauge(QWidget):
    """Compact percentage gauge used by the MechScope exact-reference layout."""

    def __init__(
        self,
        title,
        value=None,
        detail="Load",
        accent="#41ddff",
        parent=None,
    ):
        super().__init__(parent)
        self.title = str(title)
        self.value = value
        self.detail = str(detail)
        self.accent = str(accent)
        self.setMinimumSize(92, 92)
        self.setMaximumHeight(126)

    def setValue(self, value):
        try:
            self.value = max(0, min(100, int(float(value))))
        except Exception:
            self.value = None
        self.update()

    def paintEvent(self, event):
        from PyQt6.QtCore import QRectF, Qt
        from PyQt6.QtGui import QColor, QFont, QPainter, QPen

        painter = QPainter(self)
        painter.setRenderHint(QPainter.RenderHint.Antialiasing, True)
        side = max(70, min(self.width(), self.height()) - 16)
        rect = QRectF((self.width() - side) / 2, 5, side, side)

        base = QPen(QColor("#172039"), 9)
        base.setCapStyle(Qt.PenCapStyle.RoundCap)
        painter.setPen(base)
        painter.drawArc(rect, 90 * 16, -360 * 16)

        if self.value is not None:
            active = QPen(QColor(self.accent), 9)
            active.setCapStyle(Qt.PenCapStyle.RoundCap)
            painter.setPen(active)
            painter.drawArc(rect, 90 * 16, -int(360 * 16 * (self.value / 100.0)))

        painter.setPen(QColor("#dce7ff"))
        font = QFont()
        font.setPointSize(8)
        font.setBold(True)
        painter.setFont(font)
        painter.drawText(
            rect.adjusted(0, 12, 0, 0),
            Qt.AlignmentFlag.AlignHCenter | Qt.AlignmentFlag.AlignTop,
            self.title,
        )

        font = QFont()
        font.setPointSize(16)
        font.setBold(True)
        painter.setFont(font)
        painter.drawText(
            rect,
            Qt.AlignmentFlag.AlignCenter,
            "--" if self.value is None else f"{self.value}%",
        )

        painter.setPen(QColor("#8fa1ba"))
        font = QFont()
        font.setPointSize(7)
        painter.setFont(font)
        painter.drawText(
            rect.adjusted(0, 0, 0, -11),
            Qt.AlignmentFlag.AlignHCenter | Qt.AlignmentFlag.AlignBottom,
            self.detail,
        )


def mechos_gpu_load_percent():
    """Return GPU utilization when a supported local driver exposes it."""

    command = r'''if command -v nvidia-smi >/dev/null 2>&1; then
  nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits 2>/dev/null | head -n1
  exit 0
fi
for f in /sys/class/drm/card*/device/gpu_busy_percent; do
  [ -r "$f" ] || continue
  cat "$f"
  exit 0
done'''
    try:
        output = subprocess.check_output(
            ["bash", "-lc", command],
            text=True,
            stderr=subprocess.DEVNULL,
            timeout=3,
        ).strip()
        first = output.splitlines()[0]
        return max(0, min(100, int(float(first))))
    except Exception:
        return None
