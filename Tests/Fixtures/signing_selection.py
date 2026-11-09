"""Exercise real bundle staging with mocked signing tools; never access a keychain."""
import json
import os
import pathlib
import subprocess
import sys
import uuid

root = pathlib.Path(".build/signing-" + str(uuid.uuid4())).resolve()
for name in ["scripts", ".build/release", "mockbin", "build/Pulse.app/Contents/MacOS"]:
    (root / name).mkdir(parents=True, exist_ok=True)
(root / "scripts/bundle.sh").write_bytes(pathlib.Path("scripts/bundle.sh").read_bytes())
(root / "scripts/make-icon.py").write_bytes(pathlib.Path("scripts/make-icon.py").read_bytes())
(root / ".build/release/Pulse").write_text("new binary")
old = root / "build/Pulse.app/Contents/MacOS/Pulse"
selector = "ab" * 20
security = root / "mockbin/security"
security.write_text("#!" + sys.executable + "\nimport os\n"
                    "h='ab'*20\nprint(' 1) '+h+' \\\"Fixture Signing\\\"'.replace('\\\\',''))\n"
                    "if os.environ.get('AMBIGUOUS'): print(' 2) '+'cd'*20+' \\\"Fixture Signing\\\"'.replace('\\\\',''))\n")
signer = root / "mockbin/codesign"
signer.write_text("#!" + sys.executable + "\nimport os,sys\n"
                  "if '-s' in sys.argv and os.environ.get('SIGN_FAIL'): sys.exit(1)\n"
                  "if '-d' in sys.argv: print('designated => identifier fixture and certificate leaf = fixture')\n")
for tool in [security, signer]:
    tool.chmod(0o700)
base = dict(os.environ, PATH=str(root / "mockbin") + ":" + os.environ["PATH"])
for key in [k for k in base if k.startswith("PULSE_")] + ["SIGN_IDENTITY"]: base.pop(key, None)
cases = [("adhoc", None, False, False, True),
         ("name", "Fixture Signing", False, False, True),
         ("hash", selector, False, False, True),
         ("missing", "Missing Fixture", False, False, False),
         ("ambiguous", "Fixture Signing", True, False, False),
         ("signing_failure", "Fixture Signing", False, True, False)]
for name, value, ambiguous, fail, success in cases:
    old.write_text("preserved binary")
    env = dict(base)
    if value is not None:
        env["SIGN_IDENTITY"] = value
    if ambiguous:
        env["AMBIGUOUS"] = "1"
    if fail:
        env["SIGN_FAIL"] = "1"
    result = subprocess.run(["/bin/zsh", str(root / "scripts/bundle.sh")], env=env,
                            capture_output=True, text=True)
    assert (result.returncode == 0) == success, (name, result.stderr)
    assert old.read_text() == ("new binary" if success else "preserved binary"), name
    print("PASS signing fixture: " + name)
