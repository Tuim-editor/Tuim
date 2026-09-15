#!/usr/bin/env python3
"""Deterministic Tuim profiler for immutable local build artifacts."""
import argparse, fcntl, hashlib, json, math, os, pathlib, platform, pty, random, re
import select, signal, statistics, struct, subprocess, tempfile, termios, time

ROOT = pathlib.Path(__file__).resolve().parents[1]
SCENARIOS = ("startup", "normal_typing_navigation", "git_view_idle_refresh",
             "large_directory", "large_file", "resize_storms",
             "terminal_output_bursts", "idle_wakeups", "plugin_initialization")
REGRESSION_THRESHOLD_PERCENT = 10.0

def command_output(argv, default="unknown"):
    try: return subprocess.check_output(argv, cwd=ROOT, text=True, stderr=subprocess.DEVNULL).strip() or default
    except (OSError, subprocess.SubprocessError): return default

def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""): digest.update(chunk)
    return digest.hexdigest()

def artifact_metadata(path, optimization):
    path = path.resolve(strict=True)
    zig_environment = command_output(["zig", "env"], "")
    try:
        target = json.loads(zig_environment).get("target", "unknown")
        if isinstance(target, dict): target = "-".join(str(target.get(k, "unknown")) for k in ("arch", "os", "abi"))
    except json.JSONDecodeError:
        match = re.search(r'\.target\s*=\s*"([^"]+)"', zig_environment)
        target = match.group(1) if match else "unknown"
    return {"path": str(path), "git_commit": command_output(["git", "rev-parse", "HEAD"]),
            "zig_version": command_output(["zig", "version"]), "target": target,
            "optimization_mode": optimization, "file_size": path.stat().st_size, "sha256": sha256(path)}

def percentile(values, percent):
    if not values: return None
    rank = (len(values) - 1) * percent / 100.0; low, high = math.floor(rank), math.ceil(rank)
    return values[low] if low == high else values[low] + (values[high] - values[low]) * (rank - low)

def summarize(samples):
    values = sorted(float(value) for value in samples)
    if not values: return {key: None for key in ("min", "max", "mean", "median", "p50", "p95", "p99", "stddev")}
    return {"min": min(values), "max": max(values), "mean": statistics.fmean(values),
            "median": statistics.median(values), "p50": percentile(values, 50),
            "p95": percentile(values, 95), "p99": percentile(values, 99), "stddev": statistics.pstdev(values)}

def read_until_idle(fd, timeout=5.0, idle=0.12):
    output = bytearray(); start = last = time.perf_counter(); first = None
    while time.perf_counter() - start < timeout:
        ready, _, _ = select.select([fd], [], [], 0.03)
        if ready:
            try: chunk = os.read(fd, 65536)
            except OSError: break
            if not chunk: break
            now = time.perf_counter(); first = first or now; last = now; output.extend(chunk)
        elif output and time.perf_counter() - last >= idle: break
    return bytes(output), first, time.perf_counter() - start

def quit_cleanly(pid, fd):
    status = None
    for attempt in range(120):
        if attempt % 4 == 0:
            try: os.write(fd, b"\x11")
            except OSError: pass
        waited, current = os.waitpid(pid, os.WNOHANG)
        if waited: status = current; break
        time.sleep(0.025)
    if status is None: os.kill(pid, signal.SIGTERM); _, status = os.waitpid(pid, 0)
    os.close(fd)
    return os.WEXITSTATUS(status) if os.WIFEXITED(status) else -os.WTERMSIG(status)

def proc_cpu_ms(pid):
    try:
        fields = pathlib.Path(f"/proc/{pid}/stat").read_text().split()
        return (int(fields[13]) + int(fields[14])) * 1000.0 / os.sysconf("SC_CLK_TCK")
    except (OSError, ValueError, IndexError): return 0.0

def diagnostics_metrics(path):
    try: report = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError): return {}
    flattened = {}
    for name, values in report.get("durations_ns", {}).items():
        for statistic in ("count", "min", "mean", "max", "p50", "p95", "p99"):
            if isinstance(values.get(statistic), (int, float)): flattened[f"duration.{name}.{statistic}"] = values[statistic]
    for name, value in report.get("counters", {}).items():
        if isinstance(value, (int, float)): flattened[f"counter.{name}"] = value
    return flattened

def environment(home):
    env = os.environ.copy(); env.update({"HOME": str(home), "XDG_CONFIG_HOME": str(home / "config"),
        "XDG_DATA_HOME": str(home / "data"), "XDG_STATE_HOME": str(home / "state"),
        "XDG_CACHE_HOME": str(home / "cache"), "TUIM_SKIP_ONBOARDING": "1",
        "TUIM_DISABLE_PLUGINS": "1", "TUIM_DIAGNOSTICS": "1", "TERM": "xterm-256color"})
    return env

def run_session(binary, scenario, cwd, home, fixture=None):
    data = home / "data/tuim"; data.mkdir(parents=True, exist_ok=True)
    (data / "settings.json").write_text('{"mode":"normal","nerd_fonts":false}', encoding="utf-8")
    argv = [str(binary), "--diagnostics"] + ([str(fixture)] if fixture else [])
    pid, fd = pty.fork(); started = time.perf_counter()
    if pid == 0: os.chdir(cwd); os.execve(str(binary), argv, environment(home))
    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 40, 120, 0, 0)); os.kill(pid, signal.SIGWINCH)
    initial, first, settled = read_until_idle(fd)
    terminal = {"first_output_ms": ((first or time.perf_counter()) - started) * 1000,
                "settled_ms": settled * 1000, "initial_output_bytes": len(initial)}
    action_started = time.perf_counter(); before_cpu = proc_cpu_ms(pid)
    if scenario == "normal_typing_navigation": os.write(fd, b"iDeterministic Tuim benchmark 42\x1bjkjkhhll")
    elif scenario == "git_view_idle_refresh": os.write(fd, b"\x07"); time.sleep(0.25); os.write(fd, b"jkjk")
    elif scenario in ("large_directory", "large_file"): os.write(fd, b"jjjjkkkkllllhhhh")
    elif scenario == "resize_storms":
        for rows, cols in ((24, 80), (55, 170), (30, 100), (45, 140)) * 3:
            fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0)); os.kill(pid, signal.SIGWINCH); os.write(fd, b"jk")
    elif scenario == "terminal_output_bursts":
        os.write(fd, b":terminal sh -c 'i=0; while [ $i -lt 400 ]; do echo tuim-burst-$i; i=$((i+1)); done'\r")
    elif scenario == "idle_wakeups": time.sleep(0.6)
    if scenario == "startup": interaction, interaction_first, interaction_elapsed = b"", None, 0.0
    else: interaction, interaction_first, interaction_elapsed = read_until_idle(fd, timeout=3.0)
    terminal.update({"interaction_latency_ms": ((interaction_first or time.perf_counter()) - action_started) * 1000 if scenario != "startup" else 0.0,
                     "interaction_settled_ms": interaction_elapsed * 1000, "redraw_bytes": len(interaction),
                     "idle_cpu_ms": max(0.0, proc_cpu_ms(pid) - before_cpu)})
    exit_status = quit_cleanly(pid, fd)
    return {"available": True, "exit_status": exit_status, "terminal_visible": terminal,
            "local": diagnostics_metrics(data / "diagnostics.json")}

def plugin_initialization(home):
    installed = pathlib.Path.home() / ".local/share/tuim/lazy"
    if not installed.is_dir(): return {"available": False, "reason": "no installed plugin tree", "exit_status": 0, "terminal_visible": {}, "local": {}}
    data = home / "data/tuim"; data.mkdir(parents=True, exist_ok=True); (data / "lazy").symlink_to(installed, target_is_directory=True)
    env = environment(home); env["NVIM_APPNAME"] = "tuim"; started = time.perf_counter()
    result = subprocess.run(["nvim", "--headless", "--clean", "-u", "NONE", "-c", f"luafile {ROOT / 'src/nvim/tuim_init.lua'}", "-c", "qa!"],
                            cwd=ROOT, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=30)
    return {"available": True, "exit_status": result.returncode,
            "terminal_visible": {"elapsed_ms": (time.perf_counter() - started) * 1000, "output_bytes": len(result.stdout)}, "local": {}}

def prepare_fixtures(base):
    base.mkdir(parents=True); large_file = base / "large-file.txt"
    line = "0123456789 abcdefghijklmnopqrstuvwxyz CJK=界 rocket=🚀\n"
    large_file.write_text(line * 120_000, encoding="utf-8")
    large_dir = base / "large-directory"; large_dir.mkdir()
    for index in range(5_000): (large_dir / f"entry-{index:05d}.txt").touch()
    return large_file, large_dir

def aggregate(samples):
    result = {}
    for scenario in SCENARIOS:
        runs = samples[scenario]; available = [run for run in runs if run["available"]]
        entry = {"available": bool(available), "iterations": len(runs),
                 "clean_exits": all(run["exit_status"] == 0 for run in available),
                 "exit_status_samples": [run["exit_status"] for run in available], "terminal_visible": {}, "local": {}}
        if not available: entry["reason"] = runs[0].get("reason", "unavailable")
        for section in ("terminal_visible", "local"):
            for name in sorted({name for run in available for name in run[section]}):
                raw = [run[section][name] for run in available if name in run[section]]
                entry[section][name] = {"samples": raw, "summary": summarize(raw)}
        result[scenario] = entry
    return result

def profile_artifact(binary, iterations, warmup, seed, root):
    random.seed(seed); large_file, large_dir = prepare_fixtures(root); samples = {name: [] for name in SCENARIOS}
    for iteration in range(warmup + iterations):
        for scenario in SCENARIOS:
            home = root / f"home-{iteration}-{scenario}"
            if scenario == "plugin_initialization": run = plugin_initialization(home)
            else:
                cwd = large_dir if scenario == "large_directory" else ROOT
                fixture = large_file if scenario == "large_file" else None
                run = run_session(binary, scenario, cwd, home, fixture)
            if iteration >= warmup: samples[scenario].append(run)
    result = aggregate(samples); result["large_file"].update(fixture_bytes=large_file.stat().st_size, fixture_lines=120_000)
    result["large_directory"]["fixture_entries"] = 5_000
    return result

def comparisons(baseline, candidate):
    result = {}
    for scenario in SCENARIOS:
        metrics = {}
        for section in ("terminal_visible", "local"):
            for name in sorted(baseline[scenario][section].keys() & candidate[scenario][section].keys()):
                old = baseline[scenario][section][name]["summary"]["mean"]; new = candidate[scenario][section][name]["summary"]["mean"]
                if old is None or new is None: continue
                delta = new - old; percent = delta / old * 100.0 if old else (0.0 if new == 0 else 100.0)
                metrics[f"{section}.{name}"] = {"baseline_mean": old, "candidate_mean": new, "delta": delta,
                    "percent_change": percent, "regression": percent > REGRESSION_THRESHOLD_PERCENT}
        result[scenario] = metrics
    return result

def main():
    parser = argparse.ArgumentParser(description="Profile or compare immutable Tuim binaries")
    parser.add_argument("--binary", "--candidate", dest="candidate", default=str(ROOT / "zig-out/bin/tuim")); parser.add_argument("--baseline")
    parser.add_argument("--iterations", type=int, default=5); parser.add_argument("--warmup", type=int, default=1); parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--output", default=str(ROOT / "docs/performance-profile.json")); parser.add_argument("--optimization", default="Debug")
    args = parser.parse_args()
    if args.iterations < 1 or args.warmup < 0: parser.error("--iterations must be positive and --warmup non-negative")
    binaries = {"candidate": pathlib.Path(args.candidate)}
    if args.baseline: binaries["baseline"] = pathlib.Path(args.baseline)
    artifacts = {name: artifact_metadata(path, args.optimization) for name, path in binaries.items()}
    report = {"schema_version": 2, "recorded_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "configuration": {"iterations": args.iterations, "warmup": args.warmup, "seed": args.seed, "regression_threshold_percent": REGRESSION_THRESHOLD_PERCENT},
        "system": {"platform": platform.platform(), "machine": platform.machine(), "python": platform.python_version()},
        "artifacts": artifacts, "profiles": {}}
    with tempfile.TemporaryDirectory(prefix="tuim-profile-") as temporary:
        for name, path in binaries.items():
            report["profiles"][name] = {"scenarios": profile_artifact(path.resolve(), args.iterations, args.warmup, args.seed, pathlib.Path(temporary) / name)}
            if sha256(path.resolve()) != artifacts[name]["sha256"]: raise SystemExit(f"{name} binary changed during profiling")
    if "baseline" in report["profiles"]: report["comparison"] = comparisons(report["profiles"]["baseline"]["scenarios"], report["profiles"]["candidate"]["scenarios"])
    output = pathlib.Path(args.output); output.parent.mkdir(parents=True, exist_ok=True); output.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    failures = [f"{artifact}/{scenario}" for artifact, profile in report["profiles"].items() for scenario, data in profile["scenarios"].items() if data["available"] and not data["clean_exits"]]
    if failures: raise SystemExit("profiling scenarios did not shut down cleanly: " + ", ".join(failures))
    print(f"Wrote {output} ({len(SCENARIOS)} scenarios, {args.iterations} measured iterations)")

if __name__ == "__main__": main()
