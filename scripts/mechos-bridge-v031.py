#!/usr/bin/env python3
# MECHOS_BRIDGE_V031
from __future__ import annotations
import json, os, secrets, ssl, subprocess, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

CONFIG=Path.home()/".config/mechos/bridge.json"
ROOT=Path.home()/".local/share/mechos/bridge"
TOKEN=ROOT/"token"; CODE=ROOT/"pair-code"; CERT=ROOT/"bridge.crt"; KEY=ROOT/"bridge.key"
ROOT.mkdir(parents=True,exist_ok=True)
os.chmod(ROOT,0o700)

def load_config():
    d={"enabled":False,"lan_enabled":False}
    if CONFIG.exists():
        try:d.update(json.loads(CONFIG.read_text()))
        except Exception:pass
    return d

def secret_file(path,nbytes=24):
    if not path.exists():
        path.write_text(secrets.token_urlsafe(nbytes)+"\n"); os.chmod(path,0o600)
    return path.read_text().strip()

AUTH=secret_file(TOKEN)
if not CODE.exists():
    CODE.write_text(f"{secrets.randbelow(1000000):06d}\n"); os.chmod(CODE,0o600)
PAIR=CODE.read_text().strip()

def status():
    def read(p,default="unknown"):
        try:return Path(p).read_text().strip()
        except Exception:return default
    mode=read(Path.home()/".config/mechos/session-mode","gaming")
    release=read("/etc/mechos/release","unknown")
    reboot=Path("/var/lib/mechos/reboot-required").exists()
    return {"version":1,"mechos":release,"mode":mode,"reboot_required":reboot,"time":int(time.time())}

def launch(action):
    fixed={
      "open_mechscope":["/usr/local/bin/mechos-mode-launch","gaming"],
      "open_desktop":["/usr/local/bin/mechos-mode-launch","desktop"],
      "open_creator":["/usr/local/bin/mechos-mode-launch","creator"],
      "open_updates":["/usr/local/bin/mechos-update-center"],
    }
    cmd=fixed.get(action)
    if not cmd or not Path(cmd[0]).exists(): return False
    subprocess.Popen(cmd,stdin=subprocess.DEVNULL,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,start_new_session=True)
    return True

class H(BaseHTTPRequestHandler):
    server_version="MechOSBridge/0.3.1"
    def sendj(self,code,obj):
        raw=(json.dumps(obj)+"\n").encode(); self.send_response(code)
        self.send_header("Content-Type","application/json"); self.send_header("Content-Length",str(len(raw)))
        self.end_headers(); self.wfile.write(raw)
    def auth(self):
        return self.headers.get("Authorization","")==f"Bearer {AUTH}"
    def do_GET(self):
        q=urlparse(self.path)
        if q.path=="/pair":
            code=parse_qs(q.query).get("code",[""])[0]
            if secrets.compare_digest(code,PAIR): self.sendj(200,{"token":AUTH,"api":1}); return
            self.sendj(403,{"error":"invalid pairing code"}); return
        if not self.auth(): self.sendj(401,{"error":"authentication required"}); return
        if q.path=="/status": self.sendj(200,status()); return
        self.sendj(404,{"error":"not found"})
    def do_POST(self):
        if not self.auth(): self.sendj(401,{"error":"authentication required"}); return
        if self.path!="/action": self.sendj(404,{"error":"not found"}); return
        try:
            n=min(int(self.headers.get("Content-Length","0")),4096)
            body=json.loads(self.rfile.read(n) or b"{}")
        except Exception:
            self.sendj(400,{"error":"invalid json"}); return
        action=str(body.get("action",""))
        self.sendj(200 if launch(action) else 400,{"ok":bool(launch(action)),"action":action})
    def log_message(self,fmt,*args): pass

def ensure_tls():
    if CERT.exists() and KEY.exists(): return True
    if not shutil.which("openssl"): return False
    p=subprocess.run(["openssl","req","-x509","-newkey","rsa:2048","-nodes","-keyout",str(KEY),
                      "-out",str(CERT),"-days","365","-subj","/CN=mechos.local"],
                     stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    if p.returncode: return False
    os.chmod(KEY,0o600); return True

def main():
    cfg=load_config()
    if not cfg.get("enabled"): return
    lan=bool(cfg.get("lan_enabled"))
    host="0.0.0.0" if lan else "127.0.0.1"
    httpd=ThreadingHTTPServer((host,37831),H)
    if lan:
        import shutil
        if not shutil.which("openssl"): raise SystemExit("openssl required for encrypted LAN bridge")
        if not (CERT.exists() and KEY.exists()):
            p=subprocess.run(["openssl","req","-x509","-newkey","rsa:2048","-nodes","-keyout",str(KEY),
                              "-out",str(CERT),"-days","365","-subj","/CN=mechos.local"],
                             stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
            if p.returncode: raise SystemExit("failed to create bridge TLS certificate")
            os.chmod(KEY,0o600)
        ctx=ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER); ctx.load_cert_chain(CERT,KEY)
        httpd.socket=ctx.wrap_socket(httpd.socket,server_side=True)
    httpd.serve_forever()

if __name__=="__main__": main()
