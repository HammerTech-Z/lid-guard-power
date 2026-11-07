"""Actual shell wrapper -> osascript argv, then real AppleScript path quoting.
Elevation itself is replaced/removed, never prompting or altering power settings.
"""
from pathlib import Path
import os, subprocess, tempfile, shlex
root=Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="lid launcher's & ") as temp:
 base=Path(temp)
 apple=(root/'install-for-agent.sh').read_text().split("<<'APPLESCRIPT'\n",1)[1].rsplit("\nAPPLESCRIPT",1)[0]
 source=base/'launcher.applescript';source.write_text(apple)
 subprocess.run(['osacompile','-o',str(base/'launcher.scpt'),str(source)],check=True,timeout=10)
 executable=apple.replace(' with administrator privileges','')
 fixture=base/'enable.sh';marker=base/'ok'
 fixture.write_text('printf success > '+shlex.quote(str(marker))+'\n')
 test=base/'test.applescript';test.write_text(executable)
 subprocess.run(['osascript',str(test),str(fixture)],check=True,capture_output=True,timeout=10)
 assert marker.read_text()=='success'
 print('PASS AppleScript compile + real quoted dispatch')
 # Copy the package; replace only the absolute privileged-dispatch executable.
 import shutil
 package=base/'package';shutil.copytree(root,package,ignore=shutil.ignore_patterns('.git','__pycache__'))
 dispatch=base/'mock-osascript'
 dispatch.write_text('#!/bin/bash\nprintf \'%s\\n\' "$@" > "$CAPTURE"\n/bin/cat > "$CAPTURE.apple"\nexit "${DISPATCH_RC:-0}"\n')
 dispatch.chmod(0o755)
 harness=package/'install-for-agent.sh'
 harness.write_text(harness.read_text().replace('/usr/bin/osascript',shlex.quote(str(dispatch))))
 mocks=base/'mocks.sh';mocks.write_text('id() { echo 501; }\n')
 for action in ['enable','disable']:
  for rc in [0,1]:
   capture=base/f'{action}-{rc}.argv'
   env=dict(os.environ,BASH_ENV=str(mocks),CAPTURE=str(capture),DISPATCH_RC=str(rc))
   proc=subprocess.run(['/bin/bash',str(package/(action+'.command'))],env=env,capture_output=True,text=True,timeout=10)
   assert proc.returncode==rc,(proc.stdout,proc.stderr)
   assert capture.read_text().splitlines()==['-',str(package/(action+'.sh'))]
   assert capture.with_suffix('.argv.apple').read_text()==apple+'\n'
   print('PASS',action,'real wrapper dispatch / rc',rc)
 # Already-root branch must clear inherited shell/test settings.
 fixture=package/'enable.sh';env_report=base/'env.txt'
 fixture.write_text('/usr/bin/env > '+shlex.quote(str(env_report))+'\n')
 mocks.write_text('id() { echo 0; }\n')
 env=dict(os.environ,BASH_ENV=str(mocks),LIDGUARD_ROOT='/must-not-leak',DRY_RUN='1')
 proc=subprocess.run(['/bin/bash',str(package/'install-for-agent.sh'),'--install'],env=env,capture_output=True,text=True,timeout=10)
 assert proc.returncode==0,(proc.stdout,proc.stderr)
 values=env_report.read_text()
 assert 'LIDGUARD_ROOT=' not in values and 'BASH_ENV=' not in values and 'DRY_RUN=' not in values
 print('PASS already-root dispatch clears inherited environment')
