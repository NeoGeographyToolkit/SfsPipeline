
import os
from pathlib import Path

from qgis.PyQt.QtCore import Qt
from qgis.PyQt.QtWidgets import (
    QDockWidget, QWidget, QVBoxLayout, QHBoxLayout,
    QLabel, QLineEdit, QPushButton, QComboBox,
    QListWidget, QFileDialog, QMessageBox
)
from qgis.core import (
    QgsProject, QgsRasterLayer,
    QgsExpression, QgsExpressionContext,
    QgsExpressionContextUtils
)
from qgis.utils import iface


class RasterMatchDock(QDockWidget):
    def __init__(self):
        super().__init__("Raster Matcher")
        self.setObjectName("RasterMatchDock")
        self.file_cache = {}  # name -> Path

        # --- Widgets ---
        main = QWidget()
        layout = QVBoxLayout()
        main.setLayout(layout)
        self.setWidget(main)

        # 1) Folder picker
        h1 = QHBoxLayout()
        h1.addWidget(QLabel("Raster dir:"))
        self.dir_edit = QLineEdit()
        h1.addWidget(self.dir_edit)
        btn_browse = QPushButton("Browse…")
        btn_browse.clicked.connect(self.on_browse)
        h1.addWidget(btn_browse)
        layout.addLayout(h1)

        # 2) Field selector
        h2 = QHBoxLayout()
        h2.addWidget(QLabel("Match field:"))
        self.field_cb = QComboBox()
        h2.addWidget(self.field_cb)
        btn_refresh_fields = QPushButton("Refresh Fields")
        btn_refresh_fields.clicked.connect(self.populate_fields)
        h2.addWidget(btn_refresh_fields)
        layout.addLayout(h2)

        # 3) Expression filter
        h3 = QHBoxLayout()
        h3.addWidget(QLabel("Feature filter (QGIS expr.):"))
        self.expr_edit = QLineEdit()
        h3.addWidget(self.expr_edit)
        layout.addLayout(h3)

        # 4) List + buttons
        self.list_widget = QListWidget()
        layout.addWidget(self.list_widget)

        h4 = QHBoxLayout()
        btn_refresh = QPushButton("Refresh List")
        btn_refresh.clicked.connect(self.refresh_list)
        h4.addWidget(btn_refresh)
        btn_load = QPushButton("Load Rasters")
        btn_load.clicked.connect(self.load_selected)
        h4.addWidget(btn_load)
        layout.addLayout(h4)

        # initial fill
        self.populate_fields()

    def on_browse(self):
        d = QFileDialog.getExistingDirectory(self, "Select raster folder")
        if not d:
            return
        self.dir_edit.setText(d)
        self.build_cache(Path(d))

    def build_cache(self, folder: Path):
        """Scan folder once; cache name → Path for all .tif files."""
        self.file_cache.clear()
        for p in folder.glob("*.tif"):
            self.file_cache[p.name] = p

    def populate_fields(self):
        """Load the field names from the active vector layer."""
        self.field_cb.clear()
        layer = iface.activeLayer()
        if not layer or layer.type() != layer.VectorLayer:
            return
        self.field_cb.addItems([f.name() for f in layer.fields()])

    def refresh_list(self):
        """Recompute matching filenames and show them."""
        self.list_widget.clear()
        layer = iface.activeLayer()
        if not layer or layer.type() != layer.VectorLayer:
            QMessageBox.warning(self, "Raster Matcher", "Activate a vector layer first")
            return

        # decide which features to use
        expr_txt = self.expr_edit.text().strip()
        if expr_txt:
            expr = QgsExpression(expr_txt)
            if expr.hasParserError():
                QMessageBox.critical(self, "Expression error", expr.parserErrorString())
                return
            ctx = QgsExpressionContext()
            ctx.appendScopes(QgsExpressionContextUtils.globalProjectLayerScopes(layer))
            feats = [f for f in layer.getFeatures() if expr.evaluate(f, ctx)]
        else:
            feats = layer.selectedFeatures()
        if not feats:
            QMessageBox.information(self, "Raster Matcher", "No features matched")
            return

        fld = self.field_cb.currentText()
        substrings = {str(f[fld]) for f in feats if f[fld] is not None}

        hits = set()
        for name, path in self.file_cache.items():
            low = name.lower()
            if any(s.lower() in low for s in substrings):
                hits.add(name)

        for name in sorted(hits):
            self.list_widget.addItem(name)

    def load_selected(self):
        """Load each listed TIFF into the project."""
        proj = QgsProject.instance()
        for idx in range(self.list_widget.count()):
            name = self.list_widget.item(idx).text()
            path = self.file_cache.get(name)
            if not path:
                continue
            layer = QgsRasterLayer(str(path), name)
            if not layer.isValid():
                iface.messageBar().pushWarning("Raster Matcher", f"Failed to load {name}")
                continue
            proj.addMapLayer(layer)
        iface.messageBar().pushInfo("Raster Matcher", "Done loading rasters.")


