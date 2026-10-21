"""Verify base-ten version carry and the actual hook using a disposable Git repository."""
import importlib.util,json,pathlib,shutil,subprocess,tempfile
ROOT=pathlib.Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('versioning',ROOT/'scripts/version_release.py');module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
for before,after in [('1.0.0','1.0.1'),('1.0.9','1.1.0'),('1.9.9','2.0.0'),('9.9.9','10.0.0')]:assert module.next_version(before)==after
with tempfile.TemporaryDirectory(prefix='hospitalflow-version-test-') as folder:
 root=pathlib.Path(folder)
 def git(*args):
  result=subprocess.run(['git','-C',str(root),*args],capture_output=True,text=True)
  assert result.returncode==0,result.stderr+result.stdout
  return result.stdout.strip()
 git('init','--quiet');git('config','user.name','Synthetic Version Test');git('config','user.email','version@example.test');git('config','commit.gpgsign','false')
 (root/'.githooks').mkdir();(root/'scripts').mkdir()
 shutil.copy(ROOT/'scripts/version_release.py',root/'scripts/version_release.py');shutil.copy(ROOT/'.githooks/pre-commit',root/'.githooks/pre-commit');(root/'.githooks/pre-commit').chmod(0o755)
 git('config','core.hooksPath','.githooks')
 (root/'VERSION').write_text('1.0.0\n');(root/'release.json').write_text('{"version":"1.0.0","releases":[]}');git('add','.');git('commit','-m','Synthetic initial commit')
 assert (root/'VERSION').read_text().strip()=='1.0.1'
 (root/'example.txt').write_text('changed');git('add','example.txt');git('commit','-m','Synthetic feature update')
 manifest=json.loads(git('show','HEAD:release.json'));assert manifest['version']=='1.0.2',manifest;assert 'example.txt' in manifest['releases'][-1]['notes'];assert manifest['releases'][-1]['sourceParent']==git('rev-parse','HEAD^')
 assert not git('status','--porcelain'),'Hook must leave a clean tree'
 # A rejected commit retry stamps the same next version from HEAD.
 (root/'example.txt').write_text('retry');git('add','example.txt');message=root/'message.txt';message.write_text('Retry update');module.stamp(root,str(message));first=(root/'VERSION').read_text();module.stamp(root,str(message));assert (root/'VERSION').read_text()==first
print('PASS: actual commit hook stages release history with correct rollover, parent revision and retry behavior; no real project commit created.')
