# -*- coding: utf-8 -*-
#
# dasVideo documentation build configuration.
#
# Vendored from daslang/doc/source/conf.py via dasVulkan/dasImgui — HTML-only
# (Pages deploy), trimmed of the vulkan2rst generator. Reconcile against the daslang
# upstream when the daslang Sphinx domain / Forge theme evolves.

import sys
import os
import time

# Make the vendored `daslang` Sphinx domain + `tutorial_video` directive importable.
sys.path.insert(0, os.path.abspath('.'))

# Tutorial recordings (.mp4) live next to each tutorial under <repo>/tutorials/<name>/.
# Copy them into _static/tutorials/ at build time so the `.. video::` directive can
# serve them by basename; the copies are gitignored. Runs at conf load, before the build.
import shutil as _shutil
import glob as _glob
_conf_dir = os.path.abspath(os.path.dirname(__file__))
_repo_root = os.path.abspath(os.path.join(_conf_dir, '..', '..'))
_video_dst = os.path.join(_conf_dir, '_static', 'tutorials')
os.makedirs(_video_dst, exist_ok=True)
_seen_videos = {}
for _mp4 in _glob.glob(os.path.join(_repo_root, 'tutorials', '**', '*.mp4'), recursive=True):
    _base = os.path.basename(_mp4)
    # `.. video::` serves by basename, so a name collision would embed the wrong clip.
    # Fail loudly instead; each tutorial's recording must be uniquely named.
    if _base in _seen_videos:
        raise RuntimeError(
            "tutorial video basename collision: %r and %r both map to "
            "_static/tutorials/%s -- give each recording a unique name"
            % (_seen_videos[_base], _mp4, _base))
    _seen_videos[_base] = _mp4
    _shutil.copy2(_mp4, os.path.join(_video_dst, _base))

extensions = ['daslang', 'tutorial_video', 'sphinx.ext.intersphinx']

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
