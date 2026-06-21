# Sphinx config for the dasVideo reference docs. The local `daslang` extension
# (copied from the daslang docs, same as dasImgui) registers the `das` Pygments
# lexer + the `das` domain so `.. code-block:: das` highlights correctly.
import os
import sys

sys.path.insert(0, os.path.abspath("."))

project = "dasVideo"
author = "Boris Batkin"
copyright = "2026, Boris Batkin"
release = "0.1"

extensions = ["daslang"]
templates_path = ["_templates"]
exclude_patterns = []

html_theme = "alabaster"
