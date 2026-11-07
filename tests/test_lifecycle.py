"""Isolated production installer paths; mock only system signals/service dispatch.
Real files, cp/install/mv, plist parsing, and shell exit/traps are exercised.
No root access, real launchctl or real pmset is used.
"""
from pathlib import Path
import os, subprocess, tempfile, shutil, plistlib
ROOT=Path(__file__).resolve().parents[1]
MOCKS=r"""
chown() { :; }
uname() { echo Darwin; }
id() { echo 0; }
ioreg() { echo '"AppleClamshellState" = No'; }
sysadminctl() { echo "screenLock delay is ${POLICY:-immediate}"; }
sleep() { :; }
pmset() {
 if [ "$*" = -g ]; then echo "SleepDisabled $(cat "$CASE/disabled")"; return; fi
 if [ "$1 $2" = '-a disablesleep' ]; then
  if [ "${FAIL:-}" = pmset ] && [ ! -f "$CASE/failed" ]; then touch "$CASE/failed"; return 1; fi
  echo "$3" > "$CASE/disabled"; return
 fi
 echo "Unexpected pmset $*" >&2; return 99
}
launchctl() {
 case "$1" in
 print)
   if [ -f "$CASE/unloading" ]; then
    n=$(cat "$CASE/unloading")
    if [ "$n" -gt 0 ]; then echo $((n-1)) > "$CASE/unloading"
    else rm -f "$CASE/unloading" "$CASE/loaded"; fi
   fi
   [ -f "$CASE/loaded" ] || return 1
   echo 'state = running'; echo 'pid = 4242' ;;
 bootout)
   if [ "${FAIL:-}" = bootout ] && [ ! -f "$CASE/failed" ]; then touch "$CASE/failed"; return 1; fi
   if [ "${FAIL:-}" = async_stop ]; then echo 2 > "$CASE/unloading"
   else rm -f "$CASE/loaded"; fi ;;
 bootstrap)
   [ ! -f "$CASE/loaded" ] || return 5
   if [ "${FAIL:-}" = bootstrap ] && [ ! -f "$CASE/failed" ]; then touch "$CASE/failed"; return 1; fi
   touch "$CASE/loaded"
   if [ "${FAIL:-}" != readiness ]; then
    echo 'version=1.1.0 mode=on power=ac lid=open disabled=1 locked=0 pid=4242 now' > "$CASE/root/usr/local/etc/lid-guard.state"
   fi ;;
 *) echo "Unexpected launchctl $*" >&2; return 99 ;;
 esac
}
"""
with tempfile.TemporaryDirectory(prefix="lid installer's & " ) as tmp:
 base=Path(tmp);pkg=base/'package';shutil.copytree(ROOT,pkg,ignore=shutil.ignore_patterns('.git','__pycache__'))
 for name in ['enable.sh','disable.sh','install-for-agent.sh']:
  subprocess.run(['/bin/bash','-n',str(pkg/name)],check=True)
 mocks=base/'mocks.sh';mocks.write_text(MOCKS)
 def run(case,action,real=False,**extra):
  env=dict(os.environ,LIDGUARD_ROOT=str(case/'root'),CASE=str(case),BASH_ENV=str(mocks),**extra)
  target=pkg
  if real:
   target=case/'package'
   if not target.exists():
    shutil.copytree(pkg,target)
    f=target/'lifecycle.sh';s=f.read_text()
    # Keep REAL=1; redirect ONLY filesystem root, preserving real service branches.
    s=s.replace('[ -z "$ROOT" ] || REAL=0',': # REAL=1 with isolated filesystem root')
    f.write_text(s)
  return subprocess.run(['/bin/bash',str(target/action)],env=env,capture_output=True,text=True,timeout=15)
 def new(name):
  case=base/name;case.mkdir();(case/'disabled').write_text('0\n');return case
 def content(case):
  files=['usr/local/bin/lid-guard.sh','Library/LaunchDaemons/co.user.lid-guard.plist','usr/local/etc/lid-guard.mode']
  return {f:(case/'root'/f).read_bytes() if (case/'root'/f).exists() else None for f in files}
 count=0
 def check(name,fn):
  global count
  fn();count+=1;print('PASS',name,flush=True)
 def sandbox():
  c=new('sandbox');a=run(c,'enable.sh');assert a.returncode==0,(a.stdout,a.stderr)
  plist=plistlib.loads((c/'root/Library/LaunchDaemons/co.user.lid-guard.plist').read_bytes())
  assert plist['ProgramArguments']==[str(c/'root/usr/local/bin/lid-guard.sh')]
  assert (c/'root/usr/local/bin/lid-guard.sh').read_bytes()==(ROOT/'lid-guard.sh').read_bytes()
  assert run(c,'enable.sh').returncode==0
  assert list((c/'root/usr/local/bin').glob('*.bak-*'))
  assert run(c,'disable.sh').returncode==0
  assert list((c/'root/usr/local/bin').glob('*.disabled-*'))
  assert all(x is None for x in content(c).values())
  assert run(c,'disable.sh').returncode==0
 check('sandbox install / upgrade / uninstall / repeat, XML special paths',sandbox)
 def dry():
  c=new('dry');a=run(c,'enable.sh',DRY_RUN='1');assert a.returncode==0
  assert not (c/'root').exists()
 check('dry run makes no writes',dry)
 def policy():
  c=new('policy');a=run(c,'enable.sh',True,POLICY='60 seconds');assert a.returncode!=0
  assert not (c/'root').exists()
 check('non-immediate lock policy refuses before mutation',policy)
 def lifecycle():
  c=new('real-success');a=run(c,'enable.sh',True);assert a.returncode==0,(a.stdout,a.stderr)
  assert (c/'loaded').exists()
  a=run(c,'disable.sh',True);assert a.returncode==0,(a.stdout,a.stderr)
  assert not (c/'loaded').exists();assert (c/'disabled').read_text().strip()=='0'
 check('real service branch / readiness / uninstall verification',lifecycle)
 for failure in ['bootstrap','readiness','bootout','pmset']:
  def scenario(failure=failure):
   c=new(failure);a=run(c,'enable.sh',True);assert a.returncode==0,(a.stdout,a.stderr)
   before=content(c);(c/'disabled').write_text('1\n')
   action='disable.sh' if failure=='pmset' else 'enable.sh'
   a=run(c,action,True,FAIL=failure);assert a.returncode!=0,(a.stdout,a.stderr)
   assert '完成' not in a.stdout,(a.stdout,a.stderr)
   assert content(c)==before;assert (c/'loaded').exists()
   assert (c/'disabled').read_text().strip()=='1'
   assert not (c/'root/var/run/lid-guard-install.lock').exists()
  check(failure+' failure returns nonzero and restores files/service/power',scenario)
 def fresh_failure():
  c=new('fresh-failure');a=run(c,'enable.sh',True,FAIL='bootstrap');assert a.returncode!=0
  assert all(x is None for x in content(c).values());assert not (c/'loaded').exists()
 check('fresh install failure removes partial installation',fresh_failure)
 def lock():
  c=new('lock');path=c/'root/var/run/lid-guard-install.lock';path.mkdir(parents=True)
  a=run(c,'enable.sh');assert a.returncode!=0;assert path.exists()
 check('concurrent operations refuse shared lock',lock)
 def async_stop():
  c=new('async');a=run(c,'enable.sh',True);assert a.returncode==0
  a=run(c,'enable.sh',True,FAIL='async_stop');assert a.returncode==0,(a.stdout,a.stderr)
  a=run(c,'disable.sh',True,FAIL='async_stop');assert a.returncode==0,(a.stdout,a.stderr)
  assert not (c/'loaded').exists()
 check('async bootout waits before bootstrap and uninstall',async_stop)
print('RESULT',count,'/ 11')
