"""Linux/WSL supervision for the existing campaign controller and descendants.

Deadline covers validation, hashing, archival, workers and evidence processing.
RSS/output caps are sampled; RLIMIT_FSIZE also bounds individual child files.
"""
import ctypes
import errno
import multiprocessing
import os
from pathlib import Path
import resource
import signal
import time
import traceback


def process_table():
    table = {}
    for path in Path("/proc").iterdir():
        if not path.name.isdigit():
            continue
        try:
            raw = (path / "stat").read_text()
            fields = raw[raw.rfind(")") + 2:].split()
            table[int(path.name)] = {"parent": int(fields[1]), "start": int(fields[19]),
                                     "state": fields[0], "rss": int(fields[21]) * os.sysconf("SC_PAGE_SIZE")}
        except (FileNotFoundError, ProcessLookupError):
            pass
    return table


def descendants(table, roots):
    selected = set(roots)
    while True:
        more = {pid for pid, row in table.items() if row["parent"] in selected} - selected
        if not more:
            return selected & table.keys()
        selected |= more


def output_bytes(root):
    total = 0
    if not root.exists():
        return total
    pending = [root]
    while pending:
        with os.scandir(pending.pop()) as entries:
            for entry in entries:
                try:
                    if entry.is_symlink():
                        raise ValueError(f"symlink in campaign output: {entry.path}")
                    if entry.is_dir(follow_symlinks=False):
                        pending.append(Path(entry.path))
                    elif entry.is_file(follow_symlinks=False):
                        total += entry.stat(follow_symlinks=False).st_size
                except FileNotFoundError:
                    pass  # atomic replacement or temporary-file removal
    return total


def subreaper(value=None):
    libc = ctypes.CDLL(None, use_errno=True)
    current = ctypes.c_int()
    if libc.prctl(37, ctypes.byref(current), 0, 0, 0):  # PR_GET_CHILD_SUBREAPER
        raise OSError(ctypes.get_errno(), "cannot query child subreaper")
    if value is not None and libc.prctl(36, int(value), 0, 0, 0):  # PR_SET_CHILD_SUBREAPER
        raise OSError(ctypes.get_errno(), "cannot enable child subreaper")
    return current.value


def controller_child(target, args, connection, storage_bytes):
    os.setsid()
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    _, maximum = resource.getrlimit(resource.RLIMIT_FSIZE)
    ceiling = storage_bytes if maximum == resource.RLIM_INFINITY else min(storage_bytes, maximum)
    resource.setrlimit(resource.RLIMIT_FSIZE, (ceiling, ceiling))
    try:
        code = target(args, lambda message: connection.send(message))
        connection.send({"kind": "finished", "code": code})
    except BaseException as error:
        connection.send({"kind": "error", "execution": "storage_exhausted" if
                         isinstance(error, OSError) and error.errno == errno.EFBIG else "controller_error",
                         "detail": traceback.format_exc(limit=8)[-6000:]})
    finally:
        connection.close()


def supervise(target, args):
    """Run one controller, reap escaped-session helpers, and return an audit."""
    started, started_unix = time.monotonic(), time.time()
    deadline = started + args.campaign_budget
    output = args.output.resolve()
    storage_cap = int(args.storage_budget_mib * 1024 * 1024)
    rss_cap = int(args.rss_budget_mib * 1024 * 1024)
    interval, grace = 0.1, 1.0
    before = process_table()
    old_children = {(pid, row["start"]) for pid, row in before.items() if row["parent"] == os.getpid()}
    previous = subreaper(True)
    context = multiprocessing.get_context("fork")
    receive, send = context.Pipe(duplex=False)
    process = context.Process(target=controller_child, args=(target, args, send, storage_cap))
    tracked = {}
    peak_rss = peak_storage = 0
    phases, current_phase, message, execution = [], "controller_start", None, "completed"

    def owned():
        table = process_table()
        roots = {process.pid} | {pid for pid, row in table.items()
                  if row["parent"] == os.getpid() and (pid, row["start"]) not in old_children}
        selected = descendants(table, roots)
        for pid in selected:
            tracked[pid] = table[pid]["start"]
        return {pid: row for pid, row in table.items() if tracked.get(pid) == row["start"]}

    def drain():
        nonlocal message, current_phase
        while receive.poll():
            try:
                event = receive.recv()
            except EOFError:
                break
            if event["kind"] == "phase":
                phases.append(event)
                current_phase = event["name"]
            else:
                message = event

    def measure():
        nonlocal peak_rss, peak_storage
        tree = owned()
        rss = sum(row["rss"] for row in tree.values() if row["state"] != "Z")
        stored = output_bytes(output)
        peak_rss, peak_storage = max(peak_rss, rss), max(peak_storage, stored)
        return rss, stored

    try:
        process.start()
        send.close()
        while process.is_alive():
            drain()
            if time.monotonic() >= deadline:
                execution = "budget_exhausted"
                break
            rss, stored = measure()
            if stored > storage_cap or rss > rss_cap:
                execution = "storage_exhausted" if stored > storage_cap else "memory_exhausted"
                break
            process.join(timeout=min(interval, max(0, deadline - time.monotonic())))
        drain()
        rss, stored = measure()
        if execution == "completed":
            if stored > storage_cap or rss > rss_cap:
                execution = "storage_exhausted" if stored > storage_cap else "memory_exhausted"
            elif message is None or process.exitcode != 0:
                execution = "controller_error"
            elif message["kind"] == "error":
                execution = message["execution"]
            elif type(message.get("code")) is not int:
                execution = "controller_error"
            elif time.monotonic() > deadline:
                execution = "budget_exhausted"
            elif any(pid != process.pid and row["state"] != "Z" for pid, row in owned().items()):
                execution = "orphan_processes"
    except KeyboardInterrupt:
        execution = "cancelled"
    except BaseException:
        execution = "supervisor_error"
        message = {"detail": traceback.format_exc(limit=8)[-6000:]}
    finally:
        # Stop spawning first, then kill all owned descendants, including helpers
        # that created their own sessions. Re-scan after orphan reparenting.
        cleanup_deadline = time.monotonic() + grace
        while True:
            tree = owned() if process.pid is not None else {}
            alive = {pid: row for pid, row in tree.items() if row["state"] != "Z"}
            for pid in ([process.pid] if process.pid in alive else []) + [pid for pid in alive if pid != process.pid]:
                try:
                    os.kill(pid, signal.SIGSTOP)
                    os.kill(pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
            if process.pid is not None:
                process.join(timeout=0.02)
            for pid, row in tree.items():
                if pid != process.pid:
                    try:
                        os.waitpid(pid, os.WNOHANG)
                    except ChildProcessError:
                        pass
            if not alive or time.monotonic() >= cleanup_deadline:
                break
        remaining = [pid for pid, row in owned().items() if row["state"] != "Z"] if process.pid else []
        receive.close()
        subreaper(previous)
    if remaining:
        execution = "cleanup_incomplete"
    code = message.get("code", 1) if message and execution == "completed" else 1
    return {"schema_version": 1, "execution": execution, "exit": code,
            "verdict": "no_issue_detected" if execution == "completed" and code == 0 else
                       "harness_error" if execution in ("controller_error", "supervisor_error") else "incomplete",
            "started_unix": started_unix, "seconds": round(time.monotonic() - started, 3),
            "deadline_seconds": args.campaign_budget, "phase_at_stop": current_phase, "phases": phases,
            "storage_limit_bytes": storage_cap, "output_bytes_high_water": peak_storage,
            "rss_limit_bytes": rss_cap, "sum_descendant_rss_bytes_high_water": peak_rss,
            "poll_seconds": interval, "cleanup_grace_seconds": grace,
            "cleanup_remaining_pids": remaining, "controller_detail": message}
