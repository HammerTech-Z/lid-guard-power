"""Read-only harness --check through real status script, with isolated signals."""
from pathlib import Path
import tempfile,subprocess,shutil,os,time
root=Path(__file__).resolve().parents[1]
mocks=r"""
launchctl() {
 case "$SCENE" in
 absent|conflict) return 1 ;;
 stopped) echo 'state = waiting' ;;
 *) echo 'state = running'; echo 'pid = 4242' ;;
 esac
}
pmset() {
 if [ "$*" = '-g ps' ]; then echo "Now drawing from 'AC Power'"
 elif [ "$*" = -g ]; then [ "$SCENE" != conflict ] && echo 'SleepDisabled 0' || echo 'SleepDisabled 1'
 else return 99; fi
}
ioreg() { echo '"AppleClamshellState" = No'; echo '"IOConsoleLocked" = No'; }
sysadminctl() { echo 'screenLock delay is immediate'; }
"""
with tempfile.TemporaryDirectory(prefix='lid-check-') as tmp:
 base=Path(tmp);pkg=base/'package';pkg.mkdir();etc=base/'etc';etc.mkdir()
 for name in ['install-for-agent.sh','status.sh']:
  s=(root/name).read_text()
  if name=='status.sh': s=s.replace('ETC=/usr/local/etc','ETC='+str(etc)).replace('/var/log/lid-guard.log',str(base/'none.log'))
  (pkg/name).write_text(s)
 mock=base/'mocks.sh';mock.write_text(mocks)
 for scene,rc in [('absent',0),('healthy',0),('stopped',1),('conflict',1),('stale',1),('wrong_pid',1),('old_version',1)]:
  version='old' if scene=='old_version' else '1.1.0';pid='999' if scene=='wrong_pid' else '4242'
  state=etc/'lid-guard.state';state.write_text(f'version={version} mode=on power=ac lid=open disabled=1 locked=0 pid={pid} now\n')
  if scene=='stale': os.utime(state,(time.time()-60,time.time()-60))
  before=state.read_bytes()
  proc=subprocess.run(['/bin/bash',str(pkg/'install-for-agent.sh'),'--check'],env=dict(os.environ,BASH_ENV=str(mock),SCENE=scene),capture_output=True,text=True,timeout=10)
  assert proc.returncode==rc,(scene,proc.stdout,proc.stderr)
  assert state.read_bytes()==before
  if scene=='stopped': assert '运行中' not in proc.stdout
  print('PASS',scene,'check exit',rc)
print('RESULT 7 / 7')
