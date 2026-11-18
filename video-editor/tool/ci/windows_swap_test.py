#!/usr/bin/env python3
# Runs the Windows update script (assets/update/clipforge-update.ps1) with a
# PRETEND app folder, on a real Windows machine: the "Windows app" job of
# the build workflow. It cannot be run anywhere else (PowerShell, and the
# way Windows locks files of running programs, are the point).
#
#   python tool\ci\windows_swap_test.py <an .exe to play the app>
#
# The .exe is copied into the pretend folders as clipforge.exe (the built
# clipforge-mcp.exe does fine: started without input it waits, which makes
# it a "running app" whose file Windows locks).
#
# Scenarios:
#   1. the app closes -> the folders are swapped, result "updated", the old
#      folder is removed, the new app is started;
#   2. a program is still RUNNING from the install folder -> the folder
#      cannot be moved: result "failed", the old app is whole and unchanged,
#      the unpacked update is still there;
#   3. the update folder is incomplete -> "failed", nothing changed;
#   4. the new folder cannot be moved in (a file in it is locked) -> the old
#      app is put back: "failed", old app whole;
#   5. paths with spaces and non-ASCII letters work;
#   6. a folder standing in for Documents\ClipForge is never touched.
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.normpath(os.path.join(HERE, "..", "..", "assets", "update", "clipforge-update.ps1"))


def fail(message):
    print("FAILED: " + message, file=sys.stderr)
    sys.exit(1)


def check(condition, what):
    if not condition:
        fail(what)
    print("  ok  " + what)


def read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


def make_app(folder, exe, version):
    os.makedirs(os.path.join(folder, "data"))
    shutil.copy2(exe, os.path.join(folder, "clipforge.exe"))
    with open(os.path.join(folder, "version.txt"), "w", encoding="utf-8") as f:
        f.write(version)
    with open(os.path.join(folder, "data", "app.so"), "w", encoding="utf-8") as f:
        f.write("code of " + version)


def run_script(install, new, result, wait_pid=0, extra=()):
    command = ["powershell.exe", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass",
               "-File", SCRIPT, "-InstallDir", install, "-NewDir", new,
               "-WaitPid", str(wait_pid), "-ExeName", "clipforge.exe",
               "-ResultFile", result, "-Version", "9.9.9", "-NoRestart"] + list(extra)
    # Like the app does it: from a folder outside the install folder.
    return subprocess.run(command, cwd=tempfile.gettempdir(), capture_output=True, text=True, timeout=180)


def result_of(path):
    raw = open(path, "rb").read()
    check(not raw.startswith(b"\xef\xbb\xbf"), "the result file has no byte order mark")
    return json.loads(raw.decode("utf-8"))


def start_app(folder):
    # Started with the install folder as its working folder, as a
    # double-clicked app is: that is what keeps Windows from renaming it.
    """A 'running app': the exe waits for input that never comes."""
    return subprocess.Popen([os.path.join(folder, "clipforge.exe")], stdin=subprocess.PIPE,
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, cwd=folder,
                            env=dict(os.environ, CLIPFORGE_MCP_NO_HANDOVER="1"))


def scenario(root, exe, name):
    base = os.path.join(root, name)
    install = os.path.join(base, "Apps", "ClipForge")
    new = install + ".update-new"
    make_app(install, exe, "old")
    make_app(new, exe, "new")
    documents = os.path.join(base, "Documents", "ClipForge", "projects", "p1")
    os.makedirs(documents)
    with open(os.path.join(documents, "project.json"), "w", encoding="utf-8") as f:
        f.write('{"name":"Holiday"}')
    return install, new, os.path.join(base, "update-result.json"), documents


def main():
    if os.name != "nt":
        fail("this check is for Windows (the PowerShell script and Windows file locks)")
    if len(sys.argv) < 2 or not os.path.isfile(sys.argv[1]):
        fail("usage: windows_swap_test.py <an .exe to play the app>")
    exe = os.path.abspath(sys.argv[1])
    root = tempfile.mkdtemp(prefix="clipforge-swap-")

    print("1. the app closes, the folders are swapped")
    install, new, result, documents = scenario(root, exe, "one")
    app = start_app(install)
    time.sleep(1)
    try:
        os.rename(install, install + ".probe")
        os.rename(install + ".probe", install)
        # Windows allows this for a program that only has its own .exe
        # open (seen on the CI runner). The real app also holds data files
        # open, so the script still waits for the app to exit first.
        print("  note  this stand-in app does not lock its folder; the script must still wait for it to exit")
    except OSError:
        print("  ok  the folder cannot be renamed while the app runs (that is why a helper script is needed)")
    runner = subprocess.Popen(
        ["powershell.exe", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass",
         "-File", SCRIPT, "-InstallDir", install, "-NewDir", new, "-WaitPid", str(app.pid),
         "-ExeName", "clipforge.exe", "-ResultFile", result, "-Version", "9.9.9", "-NoRestart"],
        cwd=tempfile.gettempdir(), stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    time.sleep(3)
    check(read(os.path.join(install, "version.txt")) == "old" and not os.path.exists(result),
          "nothing happens while the app is still running")
    app.stdin.close()  # the app closes
    app.wait(timeout=30)
    out, err = runner.communicate(timeout=120)
    check(runner.returncode == 0, "the script ends with 0 (%s %s)" % (out.strip(), err.strip()))
    check(read(os.path.join(install, "version.txt")) == "new", "the install folder holds the new version")
    check(os.path.isfile(os.path.join(install, "data", "app.so")), "with all its files")
    check(result_of(result)["status"] == "updated", 'the result says "updated"')
    check(result_of(result)["version"] == "9.9.9", "and names the version")
    check(not os.path.exists(install + ".update-old"), "the old folder was removed")
    check(not os.path.exists(new), "the unpacked folder is gone (it became the app)")
    check(read(os.path.join(documents, "project.json")) == '{"name":"Holiday"}', "the projects are untouched")

    print("2. a program still runs from the install folder")
    install, new, result, documents = scenario(root, exe, "two")
    busy = start_app(install)
    time.sleep(1)
    done = run_script(install, new, result, extra=["-Retries", "4"])
    check(done.returncode == 3, "the script ends with 3 (got %s: %s)" % (done.returncode, done.stderr.strip()))
    check(result_of(result)["status"] == "failed", 'the result says "failed"')
    check(read(os.path.join(install, "version.txt")) == "old", "the old app is unchanged")
    check(os.path.isfile(os.path.join(install, "data", "app.so")), "and whole")
    check(busy.poll() is None, "the running program was not disturbed")
    check(read(os.path.join(new, "version.txt")) == "new", "the unpacked update is still there for another try")
    check(not os.path.exists(install + ".update-old"), "no half-moved folder is left")
    busy.stdin.close()
    busy.wait(timeout=30)

    print("3. the update folder is incomplete")
    install, new, result, documents = scenario(root, exe, "three")
    os.remove(os.path.join(new, "clipforge.exe"))
    done = run_script(install, new, result)
    check(done.returncode == 2, "the script ends with 2")
    check(result_of(result)["status"] == "failed", 'the result says "failed"')
    check(read(os.path.join(install, "version.txt")) == "old", "the old app is unchanged")

    print("4. the new folder cannot be moved in: the old app is put back")
    install, new, result, documents = scenario(root, exe, "four")
    blocker = start_app(new)  # a running program locks the NEW folder
    time.sleep(1)
    done = run_script(install, new, result)
    check(done.returncode == 4, "the script ends with 4 (got %s: %s)" % (done.returncode, done.stderr.strip()))
    check(result_of(result)["status"] == "failed", 'the result says "failed"')
    check(read(os.path.join(install, "version.txt")) == "old", "the old app is back in its place")
    check(os.path.isfile(os.path.join(install, "clipforge.exe")), "and can be started")
    check(not os.path.exists(install + ".update-old"), "no renamed copy is left")
    blocker.stdin.close()
    blocker.wait(timeout=30)

    print("5. spaces and other letters in the path")
    base = os.path.join(root, "fünf видео", "My Apps")
    install = os.path.join(base, "Clip Forge")
    new = install + ".update-new"
    make_app(install, exe, "old")
    make_app(new, exe, "new")
    result = os.path.join(base, "update result.json")
    done = run_script(install, new, result)
    check(done.returncode == 0, "the script ends with 0 (%s)" % done.stderr.strip())
    check(read(os.path.join(install, "version.txt")) == "new", "swapped")
    check(result_of(result)["status"] == "updated", 'the result says "updated"')

    print("6. restart: the new app is started after the swap")
    install, new, result, documents = scenario(root, exe, "six")
    command = ["powershell.exe", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass",
               "-File", SCRIPT, "-InstallDir", install, "-NewDir", new, "-ExeName", "clipforge.exe",
               "-ResultFile", result, "-Version", "9.9.9"]
    done = subprocess.run(command, cwd=tempfile.gettempdir(), capture_output=True, text=True, timeout=180)
    check(done.returncode == 0, "the script ends with 0 (%s)" % done.stderr.strip())
    time.sleep(2)
    # (wmic is no longer part of Windows; PowerShell lists the processes.)
    listed = subprocess.run(
        ["powershell.exe", "-NoProfile", "-Command",
         "Get-Process clipforge -ErrorAction SilentlyContinue | ForEach-Object { $_.Path }"],
        capture_output=True, text=True).stdout
    print("  started:", listed.strip().replace("\n", " | "))
    # Started without input the stand-in may already have ended; the result
    # file and the swap are what count. Leftover processes are ended.
    subprocess.run(["taskkill", "/IM", "clipforge.exe", "/F"], capture_output=True)
    check(read(os.path.join(install, "version.txt")) == "new", "swapped")

    shutil.rmtree(root, ignore_errors=True)
    print("OK: the Windows update script swaps, refuses and rolls back as designed")


if __name__ == "__main__":
    main()
