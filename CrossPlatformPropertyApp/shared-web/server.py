#!/usr/bin/env python3
import os
import http.server
import socketserver
from urllib.parse import urlparse, parse_qs

class PropertyMapHandler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/' or self.path == '/index.html':
            # Serve index.html with API key injection
            self.send_response(200)
            self.send_header('Content-type', 'text/html')
            self.send_header('Cache-Control', 'no-cache, no-store, must-revalidate')
            self.send_header('Pragma', 'no-cache')
            self.send_header('Expires', '0')
            self.end_headers()
            
            # Read the HTML file
            with open('index.html', 'r') as f:
                html = f.read()
            
            # Get API keys from environment
            linz_key = os.getenv('LINZ_API_KEY', '')
            locationiq_key = os.getenv('LOCATIONIQ_KEY', 'pk.022a4792ac3437f3ae8d42bf5128cc88')
            google_key = os.getenv('GOOGLE_API_KEY', 'AIzaSyAw4vQ2HO7S_hZ4U0-C0uPx7SBX88XJLVA')
            
            # Escape quotes for JavaScript
            escaped_linz = linz_key.replace("'", "\\'")
            escaped_locationiq = locationiq_key.replace("'", "\\'")
            escaped_google = google_key.replace("'", "\\'")
            
            # Inject API keys
            injection_script = f"""
    <script>
    console.log('🔑 Server injecting API keys...');
    window.LINZ_API_KEY = '{escaped_linz}';
    window.LOCATIONIQ_API_KEY = '{escaped_locationiq}';
    window.GOOGLE_API_KEY = '{escaped_google}';
    console.log('🔑 API Keys injected:', {{
        LINZ: !!window.LINZ_API_KEY,
        LocationIQ: !!window.LOCATIONIQ_API_KEY,
        Google: !!window.GOOGLE_API_KEY
    }});
    console.log('🔑 LINZ API Key length:', window.LINZ_API_KEY.length);
    </script>
    """
            
            # Insert injection script before closing head tag
            html = html.replace('</head>', injection_script + '</head>')
            
            self.wfile.write(html.encode())
        else:
            # Serve other files normally
            super().do_GET()

if __name__ == "__main__":
    PORT = 5000
    
    try:
        with socketserver.TCPServer(("", PORT), PropertyMapHandler) as httpd:
            print(f"🚀 PropertyMapApp server starting on port {PORT}")
            
            # Show environment status
            linz_key = os.getenv('LINZ_API_KEY', '')
            locationiq_key = os.getenv('LOCATIONIQ_KEY', '')
            google_key = os.getenv('GOOGLE_API_KEY', '')
            
            print(f"✅ LINZ_API_KEY: {len(linz_key)} chars" if linz_key else "❌ LINZ_API_KEY: missing")
            print(f"✅ LOCATIONIQ_KEY: {len(locationiq_key)} chars" if locationiq_key else "⚠️ LOCATIONIQ_KEY: using fallback")
            print(f"✅ GOOGLE_API_KEY: {len(google_key)} chars" if google_key else "⚠️ GOOGLE_API_KEY: using fallback")
            print(f"📡 Environment secrets: {sum([bool(linz_key), bool(locationiq_key), bool(google_key)])} of 3 loaded")
            print(f"🌐 Open: http://localhost:{PORT}")
            print("Press Ctrl+C to stop the server")
            
            httpd.serve_forever()
    except OSError as e:
        print(f"❌ Failed to start server on port {PORT}: {e}")