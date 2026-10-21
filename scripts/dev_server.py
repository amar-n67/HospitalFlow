#!/usr/bin/env python3
"""Local development supervisor: rebuild/restart when the Git commit changes."""
import os,pathlib,signal,subprocess,sys,time
ROOT=pathlib.Path(__file__).resolve().parents[1]

def revision(root):
    result=subprocess.run(['git','-C',str(root),'rev-parse','HEAD'],capture_output=True,text=True)
    return result.stdout.strip() if result.returncode==0 else None

class CommitWatcher:
    def __init__(self,root,build,start,stop):
        self.root=root;self.build=build;self.start=start;self.stop=stop
        self.current=revision(root);self.attempted=self.current;self.process=None
    def launch(self):
        if not self.build():return False
        self.current=revision(self.root);self.attempted=self.current;self.process=self.start();return True
    def check(self):
        target=revision(self.root)
        if target is None or target==self.attempted:return False
        self.attempted=target
        print('Git commit changed; building the updated HospitalFlow release…',flush=True)
        if not self.build():
            print('Build failed. The previous server remains running. Fix the build and restart, or make a new commit.',flush=True);return False
        if revision(self.root)!=target:
            self.attempted=None;return False
        self.stop(self.process);self.process=self.start();self.current=target
        print('HospitalFlow restarted for commit '+target[:12],flush=True);return True


def main():
    env={**os.environ,'ASPNETCORE_ENVIRONMENT':'Development','Urls':'http://localhost:5136'}
    def build():return subprocess.run(['dotnet','build','HospitalFlow.csproj','--nologo'],cwd=ROOT).returncode==0
    def start():return subprocess.Popen(['dotnet',str(ROOT/'bin/Debug/net10.0/HospitalFlow.dll'),'--contentRoot',str(ROOT)],cwd=ROOT,env=env)
    def stop(process):
        if process is None or process.poll() is not None:return
        process.terminate()
        try:process.wait(timeout=10)
        except subprocess.TimeoutExpired:process.kill();process.wait()
    watcher=CommitWatcher(ROOT,build,start,stop)
    def request_stop(*_):raise KeyboardInterrupt
    signal.signal(signal.SIGTERM,request_stop)
    try:
        if not watcher.launch():return 1
        print('Watching Git commits. New committed versions rebuild/restart automatically; Ctrl+C stops only HospitalFlow.',flush=True)
        while True:
            if watcher.process.poll() is not None:return watcher.process.returncode
            watcher.check();time.sleep(2)
    except KeyboardInterrupt:return 0
    finally:stop(watcher.process)

if __name__=='__main__':sys.exit(main())
