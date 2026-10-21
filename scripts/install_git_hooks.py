#!/usr/bin/env python3
"""Enable the tracked HospitalFlow version hook for this checkout only."""
import pathlib,subprocess
root=pathlib.Path(__file__).resolve().parents[1]
current=subprocess.run(['git','-C',str(root),'config','--local','--get','core.hooksPath'],capture_output=True,text=True).stdout.strip()
if current and current!='.githooks':raise SystemExit('Another hooksPath is already configured; integrate its hooks before changing this setting: '+current)
default=root/'.git/hooks/pre-commit'
if not current and default.exists():raise SystemExit('An existing pre-commit hook needs integration; it was preserved.')
subprocess.run(['git','-C',str(root),'config','--local','core.hooksPath','.githooks'],check=True)
print('Enabled .githooks/pre-commit for this repository. No commit was created.')
