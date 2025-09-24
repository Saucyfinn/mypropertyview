#!/usr/bin/env python3
"""
Enhanced PropertyView server with Replit secrets injection
"""
import os
import http.server
import socketserver
from urllib.parse import urlparse, parse_qs

class PropertyViewHandler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        # Parse the URL
        parsed_path = urlparse(self.path)
        
        # If requesting the main page, inject environment variables
        if parsed_path.path in ['/', '/index.html']:
            self.send_response(200)
            self.send_header('Content-type', 'text/html')
            self.send_header('Cache-Control', 'no-cache, no-store, must-revalidate')
            self.send_header('Pragma', 'no-cache')
            self.send_header('Expires', '0')
            self.end_headers()
            
            # Read the HTML file
            try:
                with open('index.html', 'r', encoding='utf-8') as f:
                    html_content = f.read()
                
                # Inject environment variables
                env_script = self.generate_env_script()
                
                # Insert the environment script before the existing API integration
                html_content = html_content.replace(
                    '<!-- Enhanced API Integration with Replit Secrets -->',
                    f'{env_script}\n  <!-- Enhanced API Integration with Replit Secrets -->'
                )
                
                self.wfile.write(html_content.encode('utf-8'))
                
            except FileNotFoundError:
                self.send_error(404, "index.html not found")
            except Exception as e:
                self.send_error(500, f"Server error: {str(e)}")
        else:
            # For all other files, use default handler
            super().do_GET()
    
    def generate_env_script(self):
        """Generate JavaScript to inject Replit secrets"""
        linz_key = os.environ.get('LINZ_API_KEY', '')
        locationiq_key = os.environ.get('LOCATIONIQ_KEY', '')
        google_key = os.environ.get('GOOGLE_API_KEY', '')
        
        return f"""  <!-- Replit Environment Secrets Injection -->
  <script>
    // Inject Replit secrets into global scope
    window.REPLIT_LINZ_API_KEY = '{linz_key}';
    window.REPLIT_LOCATIONIQ_KEY = '{locationiq_key}';
    window.REPLIT_GOOGLE_API_KEY = '{google_key}';
    console.log('Replit secrets injected:', {{
      LINZ: !!window.REPLIT_LINZ_API_KEY,
      LocationIQ: !!window.REPLIT_LOCATIONIQ_KEY,
      Google: !!window.REPLIT_GOOGLE_API_KEY
    }});
  </script>"""

def run_server(port=5000):
    """Run the enhanced PropertyView server"""
    try:
        with socketserver.TCPServer(("", port), PropertyViewHandler) as httpd:
            print(f"🚀 PropertyView Enhanced server starting on port {port}")
            print(f"📡 Environment secrets: {len([k for k in ['LINZ_API_KEY', 'LOCATIONIQ_KEY', 'GOOGLE_API_KEY'] if os.environ.get(k)])} of 3 loaded")
            print(f"🌐 Open: http://localhost:{port}")
            print("Press Ctrl+C to stop the server")
            httpd.serve_forever()
    except KeyboardInterrupt:
        print("\n🛑 Server stopped by user")
    except OSError as e:
        if e.errno == 98:  # Address already in use
            print(f"❌ Port {port} is already in use. Try a different port.")
        else:
            print(f"❌ Server error: {e}")
    except Exception as e:
        print(f"❌ Unexpected error: {e}")

if __name__ == "__main__":
    run_server()