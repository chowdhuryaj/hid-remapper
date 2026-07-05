#!/usr/bin/env python3
"""Dev server for the configurator: plain http.server plus Cache-Control:
no-cache, so edited ES modules are always revalidated (the default heuristic
caching serves stale modules for hours after an edit)."""

import functools
import http.server
import os
import sys


class NoCacheHandler(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header('Cache-Control', 'no-cache')
        super().end_headers()


if __name__ == '__main__':
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8731
    directory = sys.argv[2] if len(sys.argv) > 2 else os.path.dirname(os.path.abspath(__file__))
    handler = functools.partial(NoCacheHandler, directory=directory)
    http.server.ThreadingHTTPServer(('127.0.0.1', port), handler).serve_forever()
