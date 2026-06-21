# -*- coding: utf-8 -*-
#
# dasVideo documentation build configuration.
#
# Vendored from daslang/doc/source/conf.py via dasVulkan/dasImgui — HTML-only
# (Pages deploy), and trimmed of the vulkan2rst generator + tutorial-video bits
# dasVideo doesn't have yet. Reconcile against the daslang upstream when the
# daslang Sphinx domain / Forge theme evolves.

import sys
import os
import time

# Make the vendored `daslang` Sphinx domain (das lexer + das: directives) importable.
sys.path.insert(0, os.path.abspath('.'))

extensions = ['daslang', 'sphinx.ext.intersphinx']

# Resolve cross-refs to daslang core against the published daslang docs.
intersphinx_mapping = {
    'daslang': ('https://daslang.io/doc/', None),
}
intersphinx_disabled_reftypes = []

templates_path = ['_templates']
suppress_warnings = ['toctree.not_included']

source_suffix = '.rst'
master_doc = 'index'

project = u'dasVideo documentation'
copyright = '2026-%s, Boris Batkin' % time.strftime('%Y')
author = u'Boris Batkin'

version = u'0.1'
release = u'0.1'
language = 'en'

exclude_patterns = []

pygments_style = 'sphinx'
highlight_language = 'none'

# -- HTML output (Forge dark theme — matches daslang.io/doc/ and the other modules) --

html_theme = 'sphinx_rtd_theme'
html_theme_options = {
    'style_nav_header_background': '#0d0c0a',
    'collapse_navigation': False,
    'sticky_navigation': True,
    'navigation_depth': 4,
    'titles_only': False,
}
html_logo = '_static/forge-logo.svg'
html_favicon = 'daslang-favicon.svg'
html_static_path = ['_static']
# sphinx_rtd_theme reads this and adds an "Edit on GitHub" link to every page.
html_context = {
    'display_github': True,
    'github_user': 'borisbat',
    'github_repo': 'dasVideo',
    'github_version': 'master',
    'conf_py_path': '/doc/source/',
}
html_css_files = ['custom.css', 'custom-patch.css']

htmlhelp_basename = 'dasvideo_doc'
