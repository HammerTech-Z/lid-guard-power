from pathlib import Path
import os,subprocess,tempfile,sys,hashlib,json
source=Path(sys.argv[1]) if len(sys.argv)>1 else Path(__file__).with_name('lid-guard.sh')
root=Path(tempfile.mkdtemp(prefix='lid-policy-test-'))
src=source.read_text()
assert '/usr/libexec/smcDiagnose' not in src and 'powermetrics' not in src
mocks=r"""
clock() { read -r t < "$CASE/time"; }
signals() {
 clock; p=ac; l=closed
 case "$SCENE" in
  ac_open) l=open ;;
  ac_close) [ "$t" -lt 1003 ] && l=open ;;
  battery_closed|sleep_failure|opens_before_sleep|ac_before_sleep) p=battery ;;
  ac_unplug) [ "$t" -ge 1003 ] && p=battery ;;
  battery_plug) p=battery; [ "$t" -ge 1003 ] && p=ac ;;
  battery_open) p=battery; [ "$t" -ge 1003 ] && l=open ;;
  opens_before_display) [ "$t" -ge 1001 ] && l=open ;;
  opens_before_sleep) [ "$t" -ge 1001 ] && l=open ;;
  lid_unknown) l=unknown ;;
  power_unknown) p=unknown ;;
 esac
 [ "$SCENE" != opens_before_sleep ] || { [ "$t" -lt 1001 ] || l=open; }
 [ "$SCENE" != ac_before_sleep ] || { [ "$t" -lt 1001 ] || p=ac; }
 return 0
}
date() { clock; if [ "$1" = +%s ]; then echo "$t"; else echo "T$t"; fi; }
sleep() { clock; echo $((t+$1)) > "$CASE/time"; if [ "$SCENE" = switch_off ] && [ "$t" -ge 1002 ]; then echo off > "$CASE/lid-guard.mode"; fi; }
pmset() {
 signals
 case "$*" in
 '-g ps')
   read -r n < "$CASE/ps_reads"; echo $((n+1)) > "$CASE/ps_reads"
   if { [ "$SCENE" = opens_before_sleep ] || [ "$SCENE" = ac_before_sleep ]; } && [ "$n" -ge 1 ] && [ "$t" -lt 1001 ]; then echo 1001 > "$CASE/time"; signals; fi
   case "$p" in ac) echo "Now drawing from 'AC Power'" ;; battery) echo "Now drawing from 'Battery Power'" ;; *) echo unreadable ;; esac ;;
 '-g') read -r d < "$CASE/disabled"; echo "SleepDisabled $d" ;;
 '-a disablesleep 1'|'-a disablesleep 0')
   echo "$t set $3" >> "$CASE/trace"
   [ "$SCENE" != set_failure ] || return 1
   echo "$3" > "$CASE/disabled"
   [ "$SCENE" != opens_before_display ] || echo 1001 > "$CASE/time" ;;
 displaysleepnow)
   echo "$t display $p $l" >> "$CASE/trace"
   [ "$SCENE" != display_failure ] || return 1
   case "$SCENE" in lock_unconfirmed|lock_unknown) : ;; lock_delayed) echo "$t" > "$CASE/lock_requested" ;; *) echo 1 > "$CASE/locked" ;; esac ;;
 sleepnow)
   echo "$t sleep $p $l" >> "$CASE/trace"
   [ "$SCENE" != sleep_failure ] || return 1 ;;
 *) echo "UNEXPECTED pmset $*" >&2; return 90 ;;
 esac
 return 0
}
ioreg() {
 signals
 case "$*" in
 '-n Root -d 1')
  [ "$SCENE" != lock_unknown ] || { echo unreadable; return; }
  read -r k < "$CASE/locked"
  if [ "$SCENE" = lock_delayed ] && [ -f "$CASE/lock_requested" ]; then read -r requested < "$CASE/lock_requested"; [ "$t" -lt $((requested+2)) ] || k=1; fi
  if [ "$k" = 1 ]; then echo '\"IOConsoleLocked\" = Yes' | tr -d '\\'; else echo '\"IOConsoleLocked\" = No' | tr -d '\\'; fi ;;
 *) case "$l" in closed) echo '\"AppleClamshellState\" = Yes' | tr -d '\\' ;; open) echo '\"AppleClamshellState\" = No' | tr -d '\\' ;; *) echo unreadable ;; esac ;;
 esac
}
mv() { if [ "$#" = 3 ] && [ "$1" = -f ]; then cat "$2" >> "$CASE/history"; fi; /bin/mv "$@"; }
"""
(root/'mocks.sh').write_text(mocks)
scenes=['ac_closed','ac_open','ac_close','battery_closed','ac_unplug','battery_plug','battery_open','opens_before_display','opens_before_sleep','ac_before_sleep','display_failure','lock_unconfirmed','lock_unknown','lock_delayed','lid_unknown','power_unknown','mode_off','mode_safe','switch_off','set_failure','sleep_failure']
results=[]
for scene in scenes:
 case=root/scene;case.mkdir()
 for name,value in [('time','1000'),('disabled','1' if scene in ['ac_unplug','mode_off','mode_safe','switch_off','lid_unknown','power_unknown'] else '0'),('locked','0'),('ps_reads','0'),('trace',''),('history',''),('lid-guard.mode','off' if scene=='mode_off' else 'safe' if scene=='mode_safe' else 'on')]: (case/name).write_text(value+'\n')
 instrumented=src.replace('while :; do','while [ "$(cat "$CASE/time")" -lt 1036 ]; do').replace('/usr/local/etc/',str(case)+'/').replace('/var/log/',str(case)+'/')
 script=case/'script.sh';script.write_text(instrumented)
 env=dict(os.environ,CASE=str(case),SCENE=scene,BASH_ENV=str(root/'mocks.sh'))
 proc=subprocess.run(['/bin/bash',str(script)],env=env,text=True,capture_output=True,timeout=20)
 trace=(case/'trace').read_text().splitlines(); history=(case/'history').read_text(); state=(case/'lid-guard.state').read_text();log=(case/'lid-guard.log').read_text()
 try:
  assert proc.returncode==0 and not proc.stderr,(proc.returncode,proc.stderr)
  sleeps=[x for x in trace if ' sleep ' in x];displays=[x for x in trace if ' display ' in x]
  assert all(x.endswith('sleep battery closed') for x in sleeps),sleeps
  assert all(x.endswith('display ac closed') for x in displays),displays
  if scene in ['ac_closed','ac_close','lock_delayed']: assert 'disabled=1' in state and 'locked=1' in state and displays
  if scene=='ac_open': assert 'disabled=1' in state and not displays and not sleeps
  if scene in ['battery_closed','ac_unplug']: assert 'disabled=0' in state and sleeps
  if scene=='battery_plug': assert sleeps and displays and 'disabled=1' in state and 'locked=1' in state
  if scene=='battery_open': assert 'lid=open' in state and len(sleeps)==1
  if scene in ['opens_before_display','opens_before_sleep']: assert not sleeps and not displays
  if scene=='ac_before_sleep': assert not sleeps and 'disabled=1' in state
  if scene in ['display_failure','lock_unconfirmed','lock_unknown']:
   assert 'locked=1' not in history and 'VERIFIED' not in log
   assert len(displays)>=2
   times=[int(x.split()[0]) for x in displays];assert all(b-a>=5 for a,b in zip(times,times[1:]))
  if scene in ['lid_unknown','power_unknown','mode_off','mode_safe','switch_off']: assert 'disabled=0' in state
  if scene in ['mode_off','mode_safe','lid_unknown','power_unknown']: assert not sleeps and not displays
  if scene=='switch_off': assert 'mode=off' in state
  if scene=='set_failure': assert 'disabled=1' not in history
  if scene=='sleep_failure': assert 'sleep requested' not in log and 'request failed' in log
  if scene=='battery_closed':
   times=[int(x.split()[0]) for x in sleeps];assert len(times)>=2 and all(b-a>=30 for a,b in zip(times,times[1:]))
  results.append({'scene':scene,'passed':True}); print('PASS',scene,flush=True)
 except AssertionError as e:
  results.append({'scene':scene,'passed':False,'detail':str(e)});print('FAIL',scene,e,'trace',trace,'state',state,flush=True)
report={'source':str(source),'sha256':hashlib.sha256(src.encode()).hexdigest(),'results':results,'evidence':str(root),'os_effects':'mocked'}
Path(__file__).with_name('latest-test.json').write_text(json.dumps(report,indent=2)+'\n')
print('RESULT',sum(x['passed'] for x in results),'/',len(results),'EVIDENCE',root,flush=True)
sys.exit(not all(x['passed'] for x in results))
