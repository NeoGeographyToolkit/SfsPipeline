"""
This is a startup.py file for QGIS to add some basic non-standard utilities
to QGIS. For the moment these are macOS centric, but could be easily 
adapted/updated to be more cross platform friendly

To install, please copy or symbolic link the file to the path
for your operating system as described in QGIS docs:
https://docs.qgis.org/testing/en/docs/pyqgis_developer_cookbook/intro.html#the-startup-py-file

"""

from qgis.PyQt.QtWidgets import QAction, QApplication, QLabel
from qgis.utils import iface
from qgis.core import *

###############################
# selected layers count toolbar

label = QLabel("Selected Layers Count:")
count = QLabel()

tree_view = iface.layerTreeView()
c = len(tree_view.selectedLayers())
count.setText(str(c))

tb = iface.addToolBar("Selected layers")
tb.addWidget(label)
tb.addWidget(count)

def show_selected_layers_count():
    c = len(tree_view.selectedLayers())
    count.setText(str(c))

tree_view.selectionModel().selectionChanged.connect(show_selected_layers_count)

###############################################
# copy selected file source paths to clipboard  

def copy_selected_layer_sources():
    """Copy full source paths of all selected layers to the clipboard."""
    layers = iface.layerTreeView().selectedLayers()
    paths = [lyr.source() for lyr in layers]
    QApplication.clipboard().setText("\n".join(paths))
    iface.messageBar().pushMessage(
        f"Copied {len(paths)} layer(s) to clipboard",
        level=Qgis.Info,
        duration=3
    )

# --- create the QAction ---
action = QAction("Copy selected layer sources", iface.mainWindow())
action.setShortcut("Alt+Cmd+C")
action.triggered.connect(copy_selected_layer_sources)

# --- register the shortcut and add to menu/toolbar ---
iface.registerMainWindowAction(action, "Alt+Cmd+C")
iface.addPluginToMenu("&Custom", action)
iface.addToolBarIcon(action)