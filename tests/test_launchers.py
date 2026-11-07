from pathlib import Path
import subprocess, tempfile, shlex
root=Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="lid launcher's ") as temp:
 base=Path(temp)
 for action in ["enable","disable"]:
  wrapper=(root/(action+".command")).read_text()
  subprocess.run(["bash","-n",str(root/(action+".command"))],check=True)
  apple=wrapper.split("<<'APPLESCRIPT'\n",1)[1].rsplit("\nAPPLESCRIPT",1)[0]
  source=base/(action+".applescript");source.write_text(apple)
  subprocess.run(["osacompile","-o",str(base/(action+".scpt")),str(source)],check=True)
  # Same AppleScript quoting, ordinary shell execution; no elevation or system changes.
  executable=apple.replace(' with administrator privileges','')
  fixture=base/(action+".sh");marker=base/(action+".ok")
  fixture.write_text('printf success > '+shlex.quote(str(marker))+'\n')
  test=base/(action+"-test.applescript");test.write_text(executable)
  subprocess.run(["osascript",str(test),str(fixture)],check=True,capture_output=True)
  assert marker.read_text()=="success"
  print("PASS",action,"AppleScript compile + path with spaces/apostrophe dispatch")
