#!/usr/bin/env python3
# MECHOS_GAME_RUN_V031
from __future__ import annotations
import argparse,json,os,shutil,subprocess,sys,time
from pathlib import Path

STATE=Path.home()/".local/state/mechos"; STATE.mkdir(parents=True,exist_ok=True)
CRASH=STATE/"game-crashes-v031.jsonl"

def profile_get():
    if not shutil.which("powerprofilesctl"): return None
    p=subprocess.run(["powerprofilesctl","get"],text=True,stdout=subprocess.PIPE,stderr=subprocess.DEVNULL)
    return p.stdout.strip() if p.returncode==0 else None

def profile_set(value):
    if value and shutil.which("powerprofilesctl"):
        subprocess.run(["powerprofilesctl","set",value],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)

def map_profile(p):
    return {"efficiency":"power-saver","balanced":"balanced","performance":"performance"}.get(p,"balanced")

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument("--id",required=True)
    ap.add_argument("--profile",choices=["efficiency","balanced","performance"],default="balanced")
    ap.add_argument("command",nargs=argparse.REMAINDER)
    ns=ap.parse_args()
    cmd=ns.command[1:] if ns.command[:1]==["--"] else ns.command
    if not cmd: raise SystemExit("command required")
    old=profile_get(); requested=map_profile(ns.profile); profile_set(requested)
    actual=cmd
    if shutil.which("gamemoderun"): actual=["gamemoderun",*cmd]
    started=time.time(); rc=127
    try:
        p=subprocess.run(actual,check=False); rc=p.returncode
    finally:
        profile_set(old)
    elapsed=round(time.time()-started,2)
    if rc!=0:
        rec={"time":int(time.time()),"game_id":ns.id,"exit_code":rc,"elapsed_seconds":elapsed,
             "profile":ns.profile,"command":Path(cmd[0]).name}
        with CRASH.open("a",encoding="utf-8") as f:f.write(json.dumps(rec)+"\n")
    raise SystemExit(rc)

if __name__=="__main__": main()
