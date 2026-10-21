#!/usr/bin/env python3
"""Create one versioned manifest per Git commit (no commit is created by this tool)."""
import argparse,datetime,json,pathlib,re,subprocess

def next_version(value):
    if not re.fullmatch(r'\d+\.[0-9]\.[0-9]',value):raise ValueError('Expected major.minor.patch with minor/patch 0–9')
    major,minor,patch=map(int,value.split('.'));number=major*100+minor*10+patch+1
    return f'{number//100}.{number//10%10}.{number%10}'

def stamp(root,message=None):
    def git(*args,check=True):return subprocess.run(['git','-C',str(root),*args],check=check,capture_output=True,text=True)
    if git('diff','--cached','--quiet',check=False).returncode==0:return
    baseline=git('show','HEAD:VERSION',check=False)
    version=next_version(baseline.stdout.strip() if baseline.returncode==0 else '1.0.0')
    # Read committed history: retrying a rejected commit must not increment twice.
    committed=git('show','HEAD:release.json',check=False)
    history=json.loads(committed.stdout)['releases'] if committed.returncode==0 else []
    parent=git('rev-parse','--verify','HEAD',check=False).stdout.strip()
    notes=pathlib.Path(message).read_text().splitlines() if message else ['Updated: '+', '.join(git('diff','--cached','--name-only').stdout.splitlines()[:20])]
    subject=next((line.strip() for line in notes if line.strip() and not line.startswith('#')),'Application update')
    release={'version':version,'releasedAt':datetime.datetime.now(datetime.timezone.utc).isoformat(),'sourceParent':parent,'notes':subject}
    (root/'VERSION').write_text(version+'\n')
    (root/'release.json').write_text(json.dumps({'version':version,'releases':history+[release]},indent=2)+'\n')
    git('add','--','VERSION','release.json')
    print('HospitalFlow version:',version)

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('message_file',nargs='?');parser.add_argument('--root',type=pathlib.Path,default=pathlib.Path(__file__).resolve().parents[1]);args=parser.parse_args();stamp(args.root,args.message_file)
