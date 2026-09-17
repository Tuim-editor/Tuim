# Performance Profiling

Tuim prioritizes low latency and minimal CPU/memory overhead. To prevent performance regressions and substantiate efficiency claims, Tuim uses an automated performance profiling harness.

---

## 1. Running the Profiling Harness

Run the profiler against an optimized release build:

```bash
# 1. Build an optimized release executable
zig build -Doptimize=ReleaseFast

# 2. Run the profiling script
python3 scripts/profile_tuim.py
```

The script outputs measured latency, redraw stats, and writes detailed results to `docs/performance-profile.json`. You can pass `--optimization ReleaseFast` to record the build profile metadata.

---

## 2. What the Harness Measures

The profiling suite evaluates **9 automated scenarios** under real terminal constraints:
1. `startup`: Offline cold startup time to first byte and settled output.
2. `normal_typing_navigation`: Cursor motions, buffer scrolling, and input dispatch latency.
3. `git_view_idle_refresh`: Git status polling and background worker load while idle.
4. `large_directory`: Starting in a generated directory containing 5,000 files.
5. `large_file`: Opening and composition of a multi-megabyte complex Unicode file.
6. `resize_storms`: 12 rapid consecutive `SIGWINCH` resize cycles measuring row-run byte efficiency.
7. `terminal_output_bursts`: Rapid high-throughput shell stream handling.
8. `idle_wakeups`: CPU usage and reactor wakeups when the editor is completely idle.
9. `plugin_initialization`: Headless measurement of lazy.nvim specification loading.

---

## 3. Key Benchmark Highlights

* **Offline Cold Startup**:
  * Measures time from process launch to first emitted terminal byte.
  * Measures time until terminal output settles into an idle state.
* **Resize Storm Redraws**:
  * Sends 12 rapid `SIGWINCH` signals across varying terminal geometries `((24, 80), (55, 170), (30, 100), (45, 140)) * 3`.
  * Verifies that differential row-run rendering discards unnecessary full repaints.
* **Large Unicode File Loading**:
  * Generates a multi-megabyte file packed with multi-byte Unicode codepoints, CJK characters, emoji, and combining marks.
* **5,000-File Directory Traversal**:
  * Evaluates Explorer indexing responsiveness and memory bounds.

---

## 4. Interpreting the Results

* **Machine-Specific Data**: Benchmark timings are hardware- and environment-dependent. When comparing changes, always benchmark against the same physical hardware, terminal dimensions, and filesystem conditions.
* **Temporary Cleanup**: The generated multi-megabyte files and 5,000-file directories are placed under temporary locations (`/tmp` or `$RUNNER_TEMP`) and automatically deleted after the test finishes.

---

## Next Steps

Learn how release binaries and AppImages are packaged in **[Packaging & Releases](Packaging-and-Releases.md)**.
