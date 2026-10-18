import json,pathlib,shutil
ROOT=pathlib.Path(__file__).resolve().parents[1]
def settings():return json.loads((ROOT/'.local/database.json').read_text())
def tool(name):
    candidate=pathlib.Path('/opt/homebrew/opt/postgresql@17/bin')/name
    return str(candidate) if candidate.exists() else shutil.which(name) or name
