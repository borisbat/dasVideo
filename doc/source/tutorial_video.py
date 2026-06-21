# -*- coding: utf-8 -*-
#
# Local Sphinx directive: ``.. video:: scene_name.mp4`` embeds a tutorial
# recording from ``_static/tutorials/`` in a native HTML5 player.
#
# Centralizes the player markup so the chrome (controls, preload, sizing) is
# tuned in one place instead of being duplicated across every tutorial page.
# The player starts PAUSED with native controls (play/pause, scrubber, volume,
# fullscreen); audio is on; no autoplay, no loop -- it behaves like a normal
# embedded video. Vendored from dasImgui's tutorial_video.py.
#
# Kept out of the vendored ``daslang.py`` domain (which stays byte-compatible
# with daslang upstream) -- this is presentation local to the dasVulkan docs.

import re

from docutils import nodes
from docutils.parsers.rst import Directive

# A tutorial video is a plain ``<name>.mp4`` basename under _static/tutorials/.
# Restricting the argument to that shape keeps it out of the raw HTML as anything
# but a safe filename (no quotes/brackets that could break markup, no path
# traversal that could reference unintended files).
_SAFE_VIDEO_NAME = re.compile(r'^[A-Za-z0-9._-]+\.mp4$')


# Tutorial RSTs live at ``tutorials/<name>.rst`` and render to
# ``tutorials/<name>.html``; ``../_static/tutorials/`` resolves to the built
# ``_static/tutorials/`` for all of them.
_VIDEO_HTML = (
    '<video controls preload="metadata" playsinline width="100%">\n'
    '  <source src="../_static/tutorials/{name}" type="video/mp4">\n'
    "  Your browser doesn't support HTML5 video. "
    '<a href="../_static/tutorials/{name}">Download the recording</a>.\n'
    '</video>'
)


class VideoDirective(Directive):
    """``.. video:: scene_name.mp4`` -- embed a tutorial recording.

    One argument: the mp4 filename under ``doc/source/_static/tutorials/``.
    """

    required_arguments = 1
    optional_arguments = 0
    final_argument_whitespace = False
    has_content = False

    def run(self):
        name = self.arguments[0].strip()
        if not _SAFE_VIDEO_NAME.match(name):
            raise self.error(
                "video: argument must be a plain '<name>.mp4' filename under "
                "_static/tutorials/ (got %r)" % name)
        return [nodes.raw('', _VIDEO_HTML.format(name=name), format='html')]


def setup(app):
    app.add_directive('video', VideoDirective)
    return {
        'version': '1.0',
        'parallel_read_safe': True,
        'parallel_write_safe': True,
    }
