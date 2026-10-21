"""Verify commit detection/restart and failure preservation in a temporary Git repository."""
import importlib.util,pathlib,subprocess,tempfile
ROOT=pathlib.Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('dev_supervisor',ROOT/'scripts/dev_server.py');module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
with tempfile.TemporaryDirectory(prefix='hospitalflow-watch-test-') as folder:
 root=pathlib.Path(folder)
 def git(*args):return subprocess.run(['git','-C',str(root),*args],check=True,capture_output=True,text=True).stdout.strip()
 git('init','-q');git('config','user.name','Synthetic Test');git('config','user.email','watch@example.test');git('config','commit.gpgsign','false')
 file=root/'example';file.write_text('initial');git('add','.');git('commit','-qm','initial')
 started=[];stopped=[];can_build=[True]
 def start():value=object();started.append(value);return value
 watcher=module.CommitWatcher(root,lambda:can_build[0],start,lambda p:stopped.append(p))
 assert watcher.launch();first=watcher.process;assert not watcher.check()
 file.write_text('uncommitted');assert not watcher.check(),'Uncommitted edits must not invent a release'
 git('add','.');git('commit','-qm','second');assert watcher.check();assert stopped==[first] and len(started)==2
 second=watcher.process;can_build[0]=False;file.write_text('failed build');git('add','.');git('commit','-qm','third');assert not watcher.check();assert watcher.process is second and stopped==[first]
 can_build[0]=True;file.write_text('fixed');git('add','.');git('commit','-qm','fourth');assert watcher.check();assert stopped==[first,second] and len(started)==3
print('PASS: new commits restart the local build, unchanged revisions do not, and failed builds preserve the running process.')
