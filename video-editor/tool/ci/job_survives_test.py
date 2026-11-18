#!/usr/bin/env python3
# Checks that an export started through clipforge-mcp keeps running when the
# program that started the helper ends the helper's whole PROCESS TREE - what
# Claude Code does on Windows when it quits or disconnects.
#
#   python tool/ci/job_survives_test.py <path of clipforge-mcp(.exe)>
#
# Steps: make a 1080p test video with FFmpeg, create a project through the
# real helper, start export_video, then kill the helper's tree (Windows:
# `taskkill /PID <pid> /T /F`; elsewhere: the helper's process group), and
# wait for the export to finish on its own: the job file must say
# "finished" and the video must be there, complete (ffprobe).
#
# Needs ffmpeg and ffprobe on the PATH. Standard library only. Run by the
# "Windows app" job of the build workflow (and by the Linux check job).
import json
import os
import shutil
import signal
import subprocess
import sys
import tempfile
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from mcp_client import Server, fail  # noqa: E402

SECONDS = 150  # long enough that the export is still running when the tree is killed


def alive(pid):
    if os.name == "nt":
        out = subprocess.run(["tasklist", "/FI", "PID eq %d" % pid, "/NH"],
                             capture_output=True, text=True).stdout
        return str(pid) in out
    try:
        os.kill(pid, 0)
        return True
    except OSError:
        return False


def main():
    if len(sys.argv) < 2:
        fail("usage: job_survives_test.py <clipforge-mcp>")
    command = [os.path.abspath(sys.argv[1])]
    if not shutil.which("ffmpeg") or not shutil.which("ffprobe"):
        fail("ffmpeg / ffprobe are not on the PATH")
    tmp = tempfile.mkdtemp(prefix="clipforge-job-test-")
    projects = os.path.join(tmp, "ClipForge", "projects")
    video = os.path.join(tmp, "long.mp4")
    out = os.path.join(tmp, "exported.mp4")
    subprocess.run([
        "ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
        "-f", "lavfi", "-i", "testsrc2=size=1920x1080:rate=30:duration=%d" % SECONDS,
        "-f", "lavfi", "-i", "sine=frequency=440:duration=%d" % SECONDS,
        "-c:v", "libx264", "-preset", "ultrafast", "-pix_fmt", "yuv420p",
        "-c:a", "aac", "-shortest", video], check=True)

    server = Server(command, projects, new_group=True)
    server.initialize()
    _, status = server.call("get_status")
    print("helper:", status.get("build", {}).get("display"))
    _, created = server.call("create_project", {"name": "Survive"})
    project = created["project"]["id"]
    server.call("add_media", {"project_id": project, "paths": [video]})
    server.call("add_title", {"project_id": project, "text": "Still running", "start_ms": 0,
                              "duration_ms": 5000})
    text, job = server.call("export_video", {
        "project_id": project, "output_path": out, "quality": "full",
        "hardware": False, "wait_seconds": 3})
    job_id = job.get("jobId")
    if not job_id:
        fail("export_video gave no job id:\n" + text)
    job_file = os.path.join(tmp, "ClipForge", "claude-jobs", job_id + ".json")

    def record():
        with open(job_file, encoding="utf-8") as f:
            return json.load(f)

    deadline = time.time() + 30
    while record().get("status") == "starting" and time.time() < deadline:
        time.sleep(0.3)
    before = record()
    worker = before.get("workerPid")
    print("job %s: status %s, worker pid %s, runner %s" % (
        job_id, before.get("status"), worker, before.get("runner")))
    if before.get("status") != "running":
        fail("the export is not running before the kill (status %r): the test video is "
             "too short for this machine, or the export failed: %s" % (
                 before.get("status"), before.get("error")))
    if not worker or not alive(worker):
        fail("the worker process %r is not running" % worker)
    if worker == server.process.pid:
        fail("the export runs inside the helper, not in its own process")

    # What Claude Code does on Windows: end the helper's whole tree.
    pid = server.process.pid
    if os.name == "nt":
        killed = subprocess.run(["taskkill", "/PID", str(pid), "/T", "/F"],
                                capture_output=True, text=True)
        print(killed.stdout.strip(), killed.stderr.strip())
        if str(worker) in killed.stdout:
            fail("taskkill /T reached the worker (pid %s): it is still part of the helper's tree" % worker)
    else:
        os.killpg(os.getpgid(pid), signal.SIGKILL)
    server.process.wait(timeout=30)
    time.sleep(2)
    if alive(pid):
        fail("the helper is still running after the kill")
    if not alive(worker) and record().get("status") != "finished":
        fail("the worker (pid %s) died with the helper's process tree; job status: %s" % (
            worker, record().get("status")))
    print("the helper is gone, the worker (pid %s) is still exporting: %d%%" % (
        worker, int(100 * (record().get("progress") or 0))))

    deadline = time.time() + 15 * 60
    while time.time() < deadline:
        r = record()
        if r.get("status") in ("finished", "failed", "cancelled"):
            break
        time.sleep(1)
    r = record()
    if r.get("status") != "finished":
        fail("the export ended as %r: %s" % (r.get("status"), r.get("error")))
    if not os.path.isfile(out):
        fail("the job says finished but %s is not there" % out)
    probed = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration",
                             "-of", "default=nw=1:nk=1", out], capture_output=True, text=True)
    seconds = float(probed.stdout.strip() or 0)
    if abs(seconds - SECONDS) > 1.5:
        fail("the exported video is %.1f s long, expected %d" % (seconds, SECONDS))

    # A new helper (Claude started again) reports the finished export.
    again = Server(command, projects)
    again.initialize()
    text, status = again.call("get_export_status", {"job_id": job_id})
    again.close()
    if status.get("status") != "finished":
        fail("a new helper does not see the export as finished:\n" + text)
    print("OK: the export finished after the helper's process tree was killed "
          "(%.1f s video, %.1f MB)" % (seconds, os.path.getsize(out) / 1e6))
    shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    main()
