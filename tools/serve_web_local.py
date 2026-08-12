#!/usr/bin/env python3
"""本地验证用静态服务器：禁用缓存 + 正确 .wasm MIME，避免浏览器缓存旧构建。"""
import http.server, socketserver, sys

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8848

class Handler(http.server.SimpleHTTPRequestHandler):
    extensions_map = {
        **http.server.SimpleHTTPRequestHandler.extensions_map,
        ".wasm": "application/wasm",
        ".js": "text/javascript",
        ".pck": "application/octet-stream",
    }
    def end_headers(self):
        self.send_header("Cache-Control", "no-store, no-cache, must-revalidate, max-age=0")
        self.send_header("Pragma", "no-cache")
        self.send_header("Expires", "0")
        super().end_headers()

with socketserver.TCPServer(("127.0.0.1", PORT), Handler) as httpd:
    print(f"serving dist/web on http://127.0.0.1:{PORT} (no-cache)")
    httpd.serve_forever()
