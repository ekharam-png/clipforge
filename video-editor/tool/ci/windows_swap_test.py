#!/usr/bin/env python3
# Runs the Windows update scripts (assets/update/clipforge-update.ps1 and
# clipforge-update.cmd) with PRETEND app folders, on a real Windows
# machine: the "Windows app" job of the build workflow. It cannot be run
# anywhere else (PowerShell, cmd, robocopy and the way Windows locks files
# and folders are the point).
#
#   python tool\ci\windows_swap_test.py <an .exe to play the app>
#
# The .exe is copied into the pretend folders as clipforge.exe (the built
# clipforge-mcp.exe does fine: started without input it waits, which makes
# it a "running app" whose file Windows locks).
#
# Since 1.14.1 the scripts replace the CONTENTS of the app folder
# (robocopy /MIR, with a safety copy) instead of renaming the folder: on
# real PCs the rename never happened. What is checked:
#
# PowerShell script
#   1. the app closes -> the files are replaced IN the same folder, result
#      "updated", nothing is left next to it, every step is in the log;
#   2. a program still RUNS from the install folder -> "failed", the file
#      is named, nothing changed;
#   3. the update folder is incomplete -> "failed", nothing changed;
#   4. THE CASE FROM REAL PCs: something holds the FOLDER (a handle like
#      Explorer's, and a process whose current folder it is, running all
#      the time) -> the folder cannot be renamed, and the update WORKS;
#   5. one file inside is held open by another program -> "failed", the
#      file is named, nothing changed; and when the lock only shows up
#      during the copy: the old version is put back completely;
#   6. paths with spaces and non-ASCII letters work;
#   7. the new app is started after the update;
#   8. markers: an .update-old folder the updater did not make is never
#      removed; an unpacked update without marker is left alone;
#   9. an update left unpacked by "Later" is finished at the next start;
#  10. an app that does not close is left alone;
#  11. "tidy up" (-Mode move): the app moves from a download folder into
#      "ClipForge"; only proven ClipForge folders of the list are removed;
#  12. a second script for the same update stops at once;
#  13. started the way the app starts it (a short-lived PowerShell runs
#      Start-Process), the script survives the app's whole process tree
#      being ended.
# cmd script (the fallback when PowerShell does not start)
#  14. update, a locked program file, roll-back, tidy-up, and started the
#      way the app starts it.
import ctypes
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ASSETS = os.path.normpath(os.path.join(HERE, "..", "..", "assets", "update"))
INSTALL_DART = os.path.normpath(os.path.join(HERE, "..", "..", "lib", "core", "update", "update_install.dart"))
MARKER = ".clipforge-update-marker"
VERSION_FILE = os.path.join("data", "clipforge-version.json")
SCRIPT = None  # the .ps1, written with CRLF line ends as the app does
CMD_DIR = None  # the folder with clipforge-update.cmd (CRLF), as the app's work folder


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


def write(path, text):
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)


def show_log(log):
    if log and os.path.isfile(log):
        print("  --- update-log.txt ---")
        with open(log, "rb") as f:
            for line in f.read().decode("utf-8", "replace").splitlines():
                print("  | " + line)


def make_app(folder, exe, version, marker=False):
    os.makedirs(os.path.join(folder, "data"))
    shutil.copy2(exe, os.path.join(folder, "clipforge.exe"))
    write(os.path.join(folder, "version.txt"), version)
    write(os.path.join(folder, "data", "app.so"), "code of " + version)
    write(os.path.join(folder, VERSION_FILE), '{"version":"%s"}\n' % version)
    # A file only this version has: it must be gone after an update and
    # back after a roll-back.
    write(os.path.join(folder, "only-in-" + version + ".txt"), version)
    if marker:
        write(os.path.join(folder, MARKER), '{"by":"ClipForge updater"}')


def is_version(folder, version):
    return (read(os.path.join(folder, "version.txt")) == version
            and read(os.path.join(folder, VERSION_FILE)) == '{"version":"%s"}\n' % version
            and read(os.path.join(folder, "data", "app.so")) == "code of " + version
            and os.path.isfile(os.path.join(folder, "clipforge.exe"))
            and os.path.isfile(os.path.join(folder, "only-in-" + version + ".txt"))
            and len([n for n in os.listdir(folder) if n.startswith("only-in-")]) == 1)


def ps_command(install, new, result, wait_pid=0, extra=(), log=None, restart=False):
    command = ["powershell.exe", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass",
               "-File", SCRIPT, "-InstallDir", install, "-NewDir", new,
               "-WaitPid", str(wait_pid), "-ExeName", "clipforge.exe",
               "-ResultFile", result, "-Version", "9.9.9"]
    if log:
        command += ["-LogFile", log]
    if not restart:
        command.append("-NoRestart")
    return command + list(extra)


def clean_env():
    env = dict(os.environ, CLIPFORGE_MCP_NO_HANDOVER="1")
    for name in list(env):
        if name.upper().startswith("CF_UPD_"):
            del env[name]
    return env


def run_script(install, new, result, wait_pid=0, extra=(), log=None):
    # Like the app does it: from a folder outside the install folder.
    return subprocess.run(ps_command(install, new, result, wait_pid, extra, log), cwd=tempfile.gettempdir(),
                          env=clean_env(), capture_output=True, text=True, timeout=300)


def cmd_env(install, new, result, log, wait_pid=0, **more):
    env = clean_env()
    env.update({
        "CF_UPD_INSTALL": install, "CF_UPD_NEW": new, "CF_UPD_PID": str(wait_pid),
        "CF_UPD_EXE": "clipforge.exe", "CF_UPD_RESULT": result, "CF_UPD_LOG": log,
        "CF_UPD_VERSION": "9.9.9", "CF_UPD_TOKEN": "", "CF_UPD_MODE": "update",
        "CF_UPD_REMOVE_LIST": "", "CF_UPD_NORESTART": "1", "CF_UPD_RETRIES": "4",
    })
    env.update(more)
    return env


def run_cmd(env):
    # Named relative to the work folder, as the app starts it.
    return subprocess.run(["cmd.exe", "/d", "/c", "clipforge-update.cmd"], cwd=CMD_DIR, env=env,
                          capture_output=True, text=True, timeout=300)


def result_of(path):
    raw = open(path, "rb").read()
    check(not raw.startswith(b"\xef\xbb\xbf"), "the result file has no byte order mark")
    return json.loads(raw.decode("utf-8"))


def start_app(folder):
    """A 'running app': the exe waits for input that never comes. Started
    with the install folder as its working folder, as a double-clicked app
    is."""
    return subprocess.Popen([os.path.join(folder, "clipforge.exe")], stdin=subprocess.PIPE,
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, cwd=folder,
                            env=clean_env())


def stop_app(app):
    try:
        app.stdin.close()
        app.wait(timeout=30)
    except Exception:
        app.kill()


def sleeper(cwd=None, seconds=600):
    """A process that only waits (python itself, so no file of the pretend
    app is in use by it)."""
    return subprocess.Popen([sys.executable, "-c", "import time; time.sleep(%d)" % seconds], cwd=cwd,
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


kernel32 = ctypes.WinDLL("kernel32", use_last_error=True) if os.name == "nt" else None
INVALID_HANDLE = ctypes.c_void_p(-1).value


def hold(path, share, directory=False):
    """Opens [path] for reading and keeps it open with the given sharing
    (1 = others may read, 2 = write, 4 = delete/rename), the way another
    program would. Returns the handle; release() closes it."""
    kernel32.CreateFileW.restype = ctypes.c_void_p
    kernel32.CreateFileW.argtypes = [ctypes.c_wchar_p, ctypes.c_uint32, ctypes.c_uint32, ctypes.c_void_p,
                                     ctypes.c_uint32, ctypes.c_uint32, ctypes.c_void_p]
    GENERIC_READ, OPEN_EXISTING, BACKUP_SEMANTICS = 0x80000000, 3, 0x02000000
    handle = kernel32.CreateFileW(path, GENERIC_READ, share, None, OPEN_EXISTING,
                                  BACKUP_SEMANTICS if directory else 0, None)
    if handle is None or handle == INVALID_HANDLE:
        fail("could not hold %s open (error %d)" % (path, ctypes.get_last_error()))
    return handle


def release(handle):
    kernel32.CloseHandle.argtypes = [ctypes.c_void_p]
    kernel32.CloseHandle(handle)


def scenario(root, exe, name, marker=True):
    base = os.path.join(root, name)
    install = os.path.join(base, "Apps", "ClipForge")
    new = install + ".update-new"
    make_app(install, exe, "old")
    make_app(new, exe, "new", marker=marker)
    documents = os.path.join(base, "Documents", "ClipForge", "projects", "p1")
    os.makedirs(documents)
    write(os.path.join(documents, "project.json"), '{"name":"Holiday"}')
    return install, new, os.path.join(base, "update-result.json"), documents, os.path.join(base, "update-log.txt")


def wait_for(condition, seconds):
    until = time.time() + seconds
    while time.time() < until:
        if condition():
            return True
        time.sleep(0.25)
    return condition()


def launcher_script():
    """The PowerShell one-liner the app uses to start the script outside
    its process tree: kWindowsSwapStartScript in update_install.dart."""
    text = read(INSTALL_DART)
    start = text.index("const String kWindowsSwapStartScript =")
    block = text[start:text.index(";\n", text.index("[Console]::Out.Write", start))]
    parts = re.findall(r'r"([^"]*)"', block)
    if not parts:
        fail("kWindowsSwapStartScript was not found in update_install.dart")
    return "".join(parts)


def crlf(text):
    return text.replace("\r\n", "\n").replace("\n", "\r\n")


def main():
    global SCRIPT, CMD_DIR
    if os.name != "nt":
        fail("this check is for Windows (PowerShell, cmd, robocopy and Windows file locks)")
    if len(sys.argv) < 2 or not os.path.isfile(sys.argv[1]):
        fail("usage: windows_swap_test.py <an .exe to play the app>")
    exe = os.path.abspath(sys.argv[1])
    root = tempfile.mkdtemp(prefix="clipforge-swap-")
    # The scripts as the app writes them: into a work folder, CRLF.
    CMD_DIR = os.path.join(root, "work folder")
    os.makedirs(CMD_DIR)
    SCRIPT = os.path.join(CMD_DIR, "clipforge-update.ps1")
    for name in ("clipforge-update.ps1", "clipforge-update.cmd"):
        with open(os.path.join(ASSETS, name), encoding="ascii") as f:
            text = f.read()
        with open(os.path.join(CMD_DIR, name), "w", encoding="ascii", newline="") as f:
            f.write(crlf(text))

    print("1. the app closes, the files are replaced inside the same folder")
    install, new, result, documents, log = scenario(root, exe, "one")
    folder_id = os.stat(install).st_ino
    # An installed ClipForge also holds the installer's uninstaller, which
    # no update contains: it must survive.
    write(os.path.join(install, "unins000.exe"), "uninstaller")
    write(os.path.join(install, "unins000.dat"), "its data")
    app = start_app(install)
    time.sleep(1)
    runner = subprocess.Popen(ps_command(install, new, result, app.pid, log=log, extra=["-Token", "tok1"]),
                              cwd=tempfile.gettempdir(), env=clean_env(),
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    check(wait_for(lambda: os.path.isfile(log) and "started token=tok1 " in read(log), 30),
          'the script writes "started token=…" into the log at once (the app waits for this line)')
    time.sleep(2)
    check(is_version(install, "old") and not os.path.exists(result),
          "nothing happens while the app is still running")
    stop_app(app)  # the app closes
    out, err = runner.communicate(timeout=180)
    show_log(log)
    check(runner.returncode == 0, "the script ends with 0 (%s %s)" % (out.strip(), err.strip()))
    check(is_version(install, "new"), "the install folder holds the new version, whole, and no file of the old one")
    check(os.stat(install).st_ino == folder_id, "it is the SAME folder as before (it was not renamed or replaced)")
    check(read(os.path.join(install, "unins000.exe")) == "uninstaller" and read(os.path.join(install, "unins000.dat")) == "its data",
          "the installer's uninstaller in the folder was kept")
    check(result_of(result)["status"] == "updated", 'the result says "updated"')
    check(result_of(result)["version"] == "9.9.9", "and names the version")
    check(not os.path.exists(install + ".update-old"), "the safety copy was removed")
    check(not os.path.exists(new), "the unpacked folder (it has the marker) was removed")
    check(not os.path.exists(os.path.join(install, MARKER)), "the marker was not copied into the app folder")
    check(read(os.path.join(documents, "project.json")) == '{"name":"Holiday"}', "the projects are untouched")
    text = read(log)
    for piece in ("args: install=[" + install + "]", "the app (pid %d) has closed" % app.pid,
                  "no file of the app is in use", "robocopy (safety copy) exit code",
                  "robocopy (new version) exit code", "check: the program and the version file are the new ones",
                  "result: updated", "done"):
        check(piece in text, "the log has: " + piece)

    print("2. a program still runs from the install folder")
    install, new, result, documents, log = scenario(root, exe, "two")
    busy = start_app(install)
    time.sleep(1)
    done = run_script(install, new, result, extra=["-Retries", "4"], log=log)
    show_log(log)
    check(done.returncode == 3, "the script ends with 3 (got %s: %s)" % (done.returncode, done.stderr.strip()))
    check(result_of(result)["status"] == "failed", 'the result says "failed"')
    check("clipforge.exe" in result_of(result)["message"], "and names the file that is in use: " + result_of(result)["message"])
    check(is_version(install, "old"), "the old app is unchanged and whole")
    check(busy.poll() is None, "the running program was not disturbed")
    check(is_version(new, "new"), "the unpacked update is still there for another try")
    check(not os.path.exists(install + ".update-old"), "no safety copy is left")
    stop_app(busy)

    print("3. the update folder is incomplete")
    install, new, result, documents, log = scenario(root, exe, "three")
    os.remove(os.path.join(new, "clipforge.exe"))
    done = run_script(install, new, result, log=log)
    check(done.returncode == 2, "the script ends with 2")
    check(result_of(result)["status"] == "failed", 'the result says "failed"')
    check(is_version(install, "old"), "the old app is unchanged")

    print("4. THE CASE FROM REAL PCs: the folder itself is held (a window, a terminal) - the update works")
    install, new, result, documents, log = scenario(root, exe, "four")
    # Like an Explorer window or a scanner: a handle on the folder that
    # does not allow renaming it.
    folder_handle = hold(install, share=1 | 2, directory=True)
    # Like a terminal: a process whose current folder is the install
    # folder, running during the whole update.
    terminal = sleeper(cwd=install)
    time.sleep(1)
    try:
        os.rename(install, install + ".probe")
        os.rename(install + ".probe", install)
        print("  note  Windows let the held folder be renamed here; the update must work either way")
    except OSError as e:
        print("  ok  the folder cannot be renamed while it is held (%s): this is what stopped 1.12 - 1.14" % e.__class__.__name__)
    done = run_script(install, new, result, log=log)
    show_log(log)
    check(done.returncode == 0, "the script ends with 0 (got %s: %s)" % (done.returncode, done.stderr.strip()))
    check(terminal.poll() is None, "the process with its current folder there ran the whole time")
    check(is_version(install, "new"), "the install folder holds the new version")
    check(result_of(result)["status"] == "updated", 'the result says "updated"')
    check(not os.path.exists(new) and not os.path.exists(install + ".update-old"), "nothing is left next to the app")
    release(folder_handle)
    terminal.kill()

    print("5. one file inside is held open by another program")
    install, new, result, documents, log = scenario(root, exe, "five")
    held = os.path.join(install, "data", "app.so")
    # Another program has it open for reading and lets others only read.
    file_handle = hold(held, share=1)
    done = run_script(install, new, result, extra=["-Retries", "3"], log=log)
    show_log(log)
    check(done.returncode == 3, "the script ends with 3 (got %s: %s)" % (done.returncode, done.stderr.strip()))
    answer = result_of(result)
    check(answer["status"] == "failed", 'the result says "failed"')
    check("data\\app.so" in answer["message"], "and names the file: " + answer["message"])
    check("Nothing was changed" in answer["message"], "and says that nothing was changed")
    check(is_version(install, "old") and is_version(new, "new"), "old app and unpacked update are as they were")
    check(not os.path.exists(install + ".update-old"), "no safety copy is left")
    # The same lock, but only noticed during the copy: roll back.
    os.remove(result)
    done = run_script(install, new, result, extra=["-SkipLockCheck"], log=log)
    show_log(log)
    check(done.returncode == 4, "without the check first: the script ends with 4 (got %s: %s)" % (done.returncode, done.stderr.strip()))
    answer = result_of(result)
    check(answer["status"] == "failed", 'the result says "failed"')
    check("app.so" in answer["message"], "and names the file: " + answer["message"])
    check("ClipForge is unchanged" in answer["message"], "and says ClipForge is unchanged")
    check(is_version(install, "old"), "the old version was put back completely (also the file only it has)")
    check(is_version(new, "new"), "the unpacked update is still there for another try")
    check(not os.path.exists(install + ".update-old"), "the safety copy was removed after putting it back")
    check("robocopy (putting the old version back) exit code" in read(log), "the log shows the roll-back")
    release(file_handle)
    # The other program lets go: now it works.
    os.remove(result)
    done = run_script(install, new, result, log=log)
    check(done.returncode == 0 and is_version(install, "new"), "once the file is free the update works")

    print("6. spaces and other letters in the path")
    base = os.path.join(root, "fünf видео", "My Apps (x86) & more")
    install = os.path.join(base, "Clip Forge")
    new = install + ".update-new"
    make_app(install, exe, "old")
    make_app(new, exe, "new", marker=True)
    result = os.path.join(base, "update result.json")
    log = os.path.join(base, "update log.txt")
    done = run_script(install, new, result, log=log)
    show_log(log)
    check(done.returncode == 0, "the script ends with 0 (%s)" % done.stderr.strip())
    check(is_version(install, "new"), "updated")
    check(result_of(result)["status"] == "updated", 'the result says "updated"')
    check(not os.path.exists(new) and not os.path.exists(install + ".update-old"), "nothing is left next to the app")

    print("7. restart: the new app is started after the update")
    install, new, result, documents, log = scenario(root, exe, "seven")
    done = subprocess.run(ps_command(install, new, result, log=log, restart=True), cwd=tempfile.gettempdir(),
                          env=clean_env(), capture_output=True, text=True, timeout=300)
    check(done.returncode == 0, "the script ends with 0 (%s)" % done.stderr.strip())
    check("started the app: " + os.path.join(install, "clipforge.exe") in read(log), "the log says the app was started")
    time.sleep(2)
    # (wmic is no longer part of Windows; PowerShell lists the processes.)
    listed = subprocess.run(
        ["powershell.exe", "-NoProfile", "-Command",
         "Get-Process clipforge -ErrorAction SilentlyContinue | ForEach-Object { $_.Path }"],
        capture_output=True, text=True).stdout
    print("  started:", listed.strip().replace("\n", " | "))
    # Started without input the stand-in may already have ended; the result
    # file and the files are what count. Leftover processes are ended.
    subprocess.run(["taskkill", "/IM", "clipforge.exe", "/F"], capture_output=True)
    check(is_version(install, "new"), "updated")

    print("8. markers: only folders the updater made are ever removed")
    install, new, result, documents, log = scenario(root, exe, "eight")
    # Somebody's own folder that happens to have the name: no marker.
    theirs = install + ".update-old"
    os.makedirs(theirs)
    write(os.path.join(theirs, "my notes.txt"), "mine")
    r = run_script(install, new, result, log=log)
    check(r.returncode == 2, "the script refuses (exit 2), got %s" % r.returncode)
    check(result_of(result)["status"] == "failed", 'the result says "failed"')
    check("did not make" in result_of(result)["message"], "and says a folder ClipForge did not make is in the way")
    check(read(os.path.join(theirs, "my notes.txt")) == "mine", "their folder is untouched")
    check(is_version(install, "old"), "the app is unchanged")
    check(is_version(new, "new"), "the unpacked update is kept for another try")
    # The same with a leftover of the updater (it has the marker): cleared.
    os.remove(result)
    write(os.path.join(theirs, MARKER), "{}")
    r = run_script(install, new, result, log=log)
    check(r.returncode == 0, "with the marker the leftover is cleared and the update runs (%s)" % r.stderr.strip())
    check(is_version(install, "new"), "the new version is in place")
    check(not os.path.exists(theirs), "no .update-old folder is left")
    # An unpacked folder WITHOUT the marker is used but never removed.
    install, new, result, documents, log = scenario(root, exe, "eight-b", marker=False)
    r = run_script(install, new, result, log=log)
    check(r.returncode == 0 and is_version(install, "new"), "an unpacked update without marker is installed")
    check(is_version(new, "new"), "but its folder is left alone")
    check("left alone (no marker)" in read(log), "and the log says so")

    print("9. apply at the next start: an unpacked update left by 'Later', no app running")
    install, new, result, documents, log = scenario(root, exe, "nine")
    # The app starts, sees the waiting update and runs the script with its
    # own process id, then exits at once: here a process that is gone.
    gone = subprocess.Popen(["cmd.exe", "/c", "exit"])
    gone.wait()
    r = run_script(install, new, result, wait_pid=gone.pid, log=log)
    check(r.returncode == 0, "exit 0 (%s)" % r.stderr.strip())
    check(is_version(install, "new"), "the new version is in place")
    check(result_of(result)["status"] == "updated", 'the result the app reads at its next start says "updated"')
    check(not os.path.exists(new) and not os.path.exists(install + ".update-old"), "nothing is left next to the app")

    print("10. an app that does not close is left alone")
    install, new, result, documents, log = scenario(root, exe, "ten")
    alive = sleeper()
    r = run_script(install, new, result, wait_pid=alive.pid, extra=["-WaitSeconds", "3"], log=log)
    check(r.returncode == 6, "the script ends with 6 (got %s)" % r.returncode)
    check("did not close" in result_of(result)["message"], "and says ClipForge did not close")
    check(is_version(install, "old") and is_version(new, "new"), "nothing was changed")
    alive.kill()

    print("11. tidy up: the app moves from a download folder into 'ClipForge'")
    base = os.path.join(root, "eleven", "Apps")
    first = os.path.join(base, "ClipForge-1.12.0")
    second = first + ".update-new"
    running = second + ".update-new"
    target = os.path.join(base, "ClipForge")
    make_app(first, exe, "1.12.0")
    make_app(second, exe, "1.13.0")
    make_app(running, exe, "1.14.1")  # no marker: 1.12 / 1.13 wrote none
    # Things on the list that must NOT be removed: no ClipForge in it, and
    # a ClipForge that is not next to the app.
    notes = os.path.join(base, "ClipForge notes")
    os.makedirs(notes)
    write(os.path.join(notes, "notes.txt"), "mine")
    elsewhere = os.path.join(root, "eleven", "Other place", "ClipForge-old")
    make_app(elsewhere, exe, "1.0.0")
    result = os.path.join(root, "eleven", "update-result.json")
    log = os.path.join(root, "eleven", "update-log.txt")
    remove_list = os.path.join(root, "eleven", "tidy-remove.txt")
    with open(remove_list, "w", encoding="utf-8", newline="") as f:
        f.write("\r\n".join([first, second, notes, elsewhere, target, running]))
    r = run_script(target, running, result, log=log, extra=["-Mode", "move", "-RemoveListFile", remove_list])
    show_log(log)
    check(r.returncode == 0, "the script ends with 0 (got %s: %s)" % (r.returncode, r.stderr.strip()))
    check(is_version(target, "1.14.1"), "'ClipForge' was made and holds this version")
    check(result_of(result)["status"] == "updated" and result_of(result)["mode"] == "move",
          'the result says "updated", mode "move"')
    check(not os.path.exists(running), "the download folder the app ran from is gone")
    check(not os.path.exists(first) and not os.path.exists(second), "the two older ClipForge folders are gone")
    check(read(os.path.join(notes, "notes.txt")) == "mine", "a folder without ClipForge in it was not touched")
    check(is_version(elsewhere, "1.0.0"), "a ClipForge folder somewhere else was not touched")
    check(not os.path.exists(target + ".update-old"), "nothing else is left")
    # Into a folder that holds an older ClipForge: brought up to date.
    base = os.path.join(root, "eleven-b", "Apps")
    target = os.path.join(base, "ClipForge")
    running = target + ".update-new"
    make_app(target, exe, "1.13.0")
    make_app(running, exe, "1.14.1")
    result = os.path.join(root, "eleven-b", "update-result.json")
    log = os.path.join(root, "eleven-b", "update-log.txt")
    r = run_script(target, running, result, log=log, extra=["-Mode", "move"])
    check(r.returncode == 0 and is_version(target, "1.14.1"), "an older ClipForge in 'ClipForge' is replaced by this version")
    check(not os.path.exists(running) and not os.path.exists(target + ".update-old"), "and nothing is left next to it")
    # Into a folder that is not ClipForge: refused.
    base = os.path.join(root, "eleven-c", "Apps")
    target = os.path.join(base, "ClipForge")
    running = target + ".update-new"
    os.makedirs(target)
    write(os.path.join(target, "holiday.txt"), "mine")
    make_app(running, exe, "1.14.1")
    result = os.path.join(root, "eleven-c", "update-result.json")
    r = run_script(target, running, result, extra=["-Mode", "move"])
    check(r.returncode == 2, "a folder 'ClipForge' that is not ClipForge: refused (exit 2), got %s" % r.returncode)
    check(os.listdir(target) == ["holiday.txt"] and is_version(running, "1.14.1"), "nothing was changed")

    print("12. a second script for the same update stops at once")
    install, new, result, documents, log = scenario(root, exe, "twelve")
    os.makedirs(result + ".tok12.lock")
    r = run_script(install, new, result, log=log, extra=["-Token", "tok12"])
    check(r.returncode == 7, "the script ends with 7 (got %s)" % r.returncode)
    check(is_version(install, "old") and not os.path.exists(result), "and changes nothing")

    print("13. started the way the app does it, the script survives the app's process tree being ended")
    install, new, result, documents, log = scenario(root, exe, "thirteen")
    # The "app": a process that starts the script exactly as the app does
    # (the launcher line from update_install.dart, values in the
    # environment) and then keeps running.
    env = clean_env()
    env.update({
        "CF_UPD_INSTALL": install, "CF_UPD_NEW": new, "CF_UPD_EXE": "clipforge.exe",
        "CF_UPD_RESULT": result, "CF_UPD_LOG": log, "CF_UPD_VERSION": "9.9.9", "CF_UPD_TOKEN": "tok13",
        "CF_UPD_MODE": "update", "CF_UPD_REMOVE_LIST": "", "CF_UPD_SCRIPT": SCRIPT, "CF_UPD_WORKDIR": CMD_DIR,
        "CF_TEST_LAUNCHER": launcher_script(),
    })
    app_code = (
        "import os, subprocess, sys, time\n"
        "env = dict(os.environ, CF_UPD_PID=str(os.getpid()))\n"
        "r = subprocess.run(['powershell.exe', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',\n"
        "                    '-WindowStyle', 'Hidden', '-Command', os.environ['CF_TEST_LAUNCHER']],\n"
        "                   env=env, cwd=os.environ['CF_UPD_WORKDIR'], capture_output=True, text=True)\n"
        "print(r.returncode, r.stdout.strip(), r.stderr.strip(), flush=True)\n"
        "time.sleep(600)\n")
    app = subprocess.Popen([sys.executable, "-c", app_code], env=env, stdout=subprocess.PIPE, text=True)
    line = app.stdout.readline().strip()
    print("  the launcher said:", line)
    check(line.startswith("0 ") and line.split()[1].isdigit(), "the launcher ends with 0 and prints the script's process id")
    check(wait_for(lambda: os.path.isfile(log) and "started token=tok13 " in read(log), 30),
          "the script reports in through the log while the app still runs")
    check(is_version(install, "old"), "and waits for the app")
    # What Windows does to a tree: everything started by the app goes.
    subprocess.run(["taskkill", "/PID", str(app.pid), "/T", "/F"], capture_output=True)
    app.wait(timeout=30)
    ok = wait_for(lambda: os.path.isfile(result), 120)
    show_log(log)
    check(ok, "the script was not ended with the app's process tree: it wrote its result")
    check(result_of(result)["status"] == "updated", 'the result says "updated"')
    check(wait_for(lambda: not os.path.exists(new) and not os.path.exists(install + ".update-old"), 60),
          "and it tidied up")
    check(is_version(install, "new"), "the new version is in place")
    subprocess.run(["taskkill", "/IM", "clipforge.exe", "/F"], capture_output=True)

    print("14. the cmd script (used when PowerShell does not start)")
    print(" a. update")
    install, new, result, documents, log = scenario(root, exe, "cmd-a")
    folder_id = os.stat(install).st_ino
    terminal = sleeper(cwd=install)  # a terminal in the folder, as in 4
    write(os.path.join(install, "unins000.exe"), "uninstaller")
    gone = subprocess.Popen(["cmd.exe", "/c", "exit"])
    gone.wait()
    r = run_cmd(cmd_env(install, new, result, log, wait_pid=gone.pid, CF_UPD_TOKEN="tokc"))
    show_log(log)
    check(r.returncode == 0, "the script ends with 0 (got %s: %s %s)" % (r.returncode, r.stdout.strip(), r.stderr.strip()))
    check(is_version(install, "new"), "the install folder holds the new version, whole, and no file of the old one")
    check(os.stat(install).st_ino == folder_id, "it is the same folder as before")
    check(read(os.path.join(install, "unins000.exe")) == "uninstaller", "the installer's uninstaller in the folder was kept")
    check(result_of(result) == {"status": "updated", "message": "", "version": "9.9.9", "mode": "update"},
          "the result file is the JSON the app reads")
    check(not os.path.exists(new) and not os.path.exists(install + ".update-old"), "nothing is left next to the app")
    check(not os.path.exists(os.path.join(install, MARKER)), "the marker was not copied into the app folder")
    raw = open(log, "rb").read().decode("utf-8", "replace")
    for piece in ("script(cmd): started token=tokc mode=update", "robocopy (safety copy) exit code",
                  "robocopy (new version) exit code", "check: the version file is the new one",
                  "result: updated", "script(cmd): done"):
        check(piece in raw, "the log has: " + piece)
    terminal.kill()

    print(" b. the program file is in use")
    install, new, result, documents, log = scenario(root, exe, "cmd-b")
    busy = start_app(install)
    time.sleep(1)
    r = run_cmd(cmd_env(install, new, result, log))
    show_log(log)
    check(r.returncode == 3, "the script ends with 3 (got %s)" % r.returncode)
    check(result_of(result)["status"] == "failed" and "in use" in result_of(result)["message"],
          'the result says "failed", in use')
    check(is_version(install, "old") and is_version(new, "new"), "nothing was changed")
    check(not os.path.exists(install + ".update-old"), "no safety copy is left")
    stop_app(busy)

    print(" c. a file is held during the copy: the old version is put back")
    install, new, result, documents, log = scenario(root, exe, "cmd-c")
    file_handle = hold(os.path.join(install, "data", "app.so"), share=1)
    r = run_cmd(cmd_env(install, new, result, log))
    show_log(log)
    check(r.returncode == 4, "the script ends with 4 (got %s)" % r.returncode)
    check(result_of(result)["status"] == "failed" and "ClipForge is unchanged" in result_of(result)["message"],
          'the result says "failed", ClipForge is unchanged')
    check(is_version(install, "old"), "the old version was put back completely")
    check(is_version(new, "new"), "the unpacked update is still there")
    check(not os.path.exists(install + ".update-old"), "the safety copy was removed after putting it back")
    release(file_handle)

    print(" d. markers and an incomplete update")
    install, new, result, documents, log = scenario(root, exe, "cmd-d")
    theirs = install + ".update-old"
    os.makedirs(theirs)
    write(os.path.join(theirs, "my notes.txt"), "mine")
    r = run_cmd(cmd_env(install, new, result, log))
    check(r.returncode == 2 and "did not make" in result_of(result)["message"], "an .update-old folder without marker: refused")
    check(read(os.path.join(theirs, "my notes.txt")) == "mine" and is_version(install, "old"), "nothing was touched")
    shutil.rmtree(theirs)
    os.remove(os.path.join(new, "clipforge.exe"))
    r = run_cmd(cmd_env(install, new, result, log))
    check(r.returncode == 2 and "not complete" in result_of(result)["message"], "an incomplete update: refused")
    check(is_version(install, "old"), "the app is unchanged")

    print(" e. tidy up")
    base = os.path.join(root, "cmd-e", "Apps")
    first = os.path.join(base, "ClipForge-1.12.0")
    running = first + ".update-new"
    target = os.path.join(base, "ClipForge")
    make_app(first, exe, "1.12.0")
    make_app(running, exe, "1.14.1")
    notes = os.path.join(base, "ClipForge notes")
    os.makedirs(notes)
    write(os.path.join(notes, "notes.txt"), "mine")
    elsewhere = os.path.join(root, "cmd-e", "Other place", "ClipForge-old")
    make_app(elsewhere, exe, "1.0.0")
    result = os.path.join(root, "cmd-e", "update-result.json")
    log = os.path.join(root, "cmd-e", "update-log.txt")
    remove_list = os.path.join(root, "cmd-e", "tidy-remove.txt")
    with open(remove_list, "w", encoding="utf-8", newline="") as f:
        f.write("\r\n".join([first, notes, elsewhere, target, running]))
    r = run_cmd(cmd_env(target, running, result, log, CF_UPD_MODE="move", CF_UPD_REMOVE_LIST=remove_list))
    show_log(log)
    check(r.returncode == 0, "the script ends with 0 (got %s: %s %s)" % (r.returncode, r.stdout.strip(), r.stderr.strip()))
    check(is_version(target, "1.14.1"), "'ClipForge' was made and holds this version")
    check(result_of(result)["mode"] == "move" and result_of(result)["status"] == "updated", 'the result says "updated", mode "move"')
    check(not os.path.exists(running) and not os.path.exists(first), "the download folder and the older ClipForge folder are gone")
    check(read(os.path.join(notes, "notes.txt")) == "mine" and is_version(elsewhere, "1.0.0"),
          "folders that are not older ClipForge folders next to the app were not touched")

    print(" f. started the way the app does it (cmd /c start /min cmd /c clipforge-update.cmd)")
    install, new, result, documents, log = scenario(root, exe, "cmd-f")
    app_code = (
        "import os, subprocess, sys, time\n"
        "env = dict(os.environ, CF_UPD_PID=str(os.getpid()))\n"
        "r = subprocess.run(['cmd.exe', '/d', '/c', 'start', '/min', 'cmd.exe', '/d', '/c', 'clipforge-update.cmd'],\n"
        "                   env=env, cwd=os.environ['CF_UPD_WORKDIR'])\n"
        "print(r.returncode, flush=True)\n"
        "time.sleep(600)\n")
    env = cmd_env(install, new, result, log, CF_UPD_TOKEN="tokf", CF_UPD_WORKDIR=CMD_DIR)
    app = subprocess.Popen([sys.executable, "-c", app_code], env=env, stdout=subprocess.PIPE, text=True)
    line = app.stdout.readline().strip()
    check(line == "0", "the start command ends with 0 at once (got %r)" % line)
    check(wait_for(lambda: os.path.isfile(log) and b"started token=tokf " in open(log, "rb").read(), 30),
          "the script reports in through the log while the app still runs")
    check(is_version(install, "old"), "and waits for the app")
    subprocess.run(["taskkill", "/PID", str(app.pid), "/T", "/F"], capture_output=True)
    app.wait(timeout=30)
    ok = wait_for(lambda: os.path.isfile(result), 120)
    show_log(log)
    check(ok, "the script was not ended with the app's process tree: it wrote its result")
    check(result_of(result)["status"] == "updated", 'the result says "updated"')
    check(wait_for(lambda: not os.path.exists(new) and not os.path.exists(install + ".update-old"), 60),
          "and it tidied up")
    check(is_version(install, "new"), "the new version is in place")

    shutil.rmtree(root, ignore_errors=True)
    print("OK: the Windows update scripts replace, refuse and roll back as designed")


if __name__ == "__main__":
    main()
