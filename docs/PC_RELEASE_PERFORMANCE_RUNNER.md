The PC performance runner exercises the exported **32-bit shipping client**, using its opt-in diagnostic entry point. It runs all five original published maps against a private authoritative server at `127.0.0.1:17861`. It does not modify the modes or use a player account.

After exporting build 55, run from the repository:

```powershell
python -X utf8 tools/run_pc_performance.py --version-file dist/release/Bobux-Windows-0.1.50-build55-stage/version.json --tag release55
```

The executable's PE architecture, size and SHA-256 must match the packaged `version.json`. The runner starts the source dedicated server with separate `.codex-tmp` userdata and strips inherited service keys, bearer tokens, heartbeat configuration and test identities. It refuses userdata containing an account session and an occupied server port. Cleanup terminates only processes created by this run.

By default, original map/media caches are copied from `.codex-tmp/performance-server` into `.codex-tmp/release55-pc`. No session/profile files are copied. The City RP cache is initialized from the checksum-verified original map audit when absent. Missing optional media may still be read from the public asset server. These measurements represent **warm map caches**, rather than first-ever download times. Use `--cold-client --client-appdata .codex-tmp/release55-pc-cold --tag release55-cold` for a fresh client cache; the private server cache remains warm.

The main report is `.codex-tmp/performance/pc-release55.json`, accompanied by retained client, client-console and server logs. Each map reports join time, frame percentiles, gameplay FPS, Luau diagnostics and departure time. Park and Valley must respond to their actual published start buttons. A missing map result, duplicate sample, script failure, resource error or nonzero client exit fails the run.

The start diagnostic rejects Buttons on hidden DataModel canvas layers, touches
the drawable mirror, and waits up to two seconds for the original intro callback
to hide its button. Sending a touch by itself is not counted as success.

After publication, exercise the same actual exported client against the live
server with isolated guest data:

```powershell
python -X utf8 tools/run_pc_performance.py --version-file dist/release/Bobux-Windows-0.1.50-build55-stage/version.json --tag release55-public --server ws://109.71.245.162/ws
```

This mode starts no local server. It records public-server identity in the report
and does not claim locally captured server diagnostics. Credential-bearing URLs
are rejected; the client still uses separate account-free diagnostic userdata.

To prepare isolated caches without starting any GPU benchmark:

```powershell
python -X utf8 tools/run_pc_performance.py --prepare-only
```

Run GPU measurements while exports and other graphics tests are stopped. The runner does not disable scripts, physics or rendering features. It does not establish a controlled before/after performance baseline by itself.

The isolated Android package can be measured after the PC run, using a separate private server on port 17860:

```powershell
python -X utf8 tools/run_android_release_performance.py --apk .codex-tmp/performance/Bobux-Android55-performance.apk --output .codex-tmp/performance/android55.log --serial R5CXA2HYLFZ
```

Prepare that APK with the release engine template, `--maps=park,valley,nds,lift,city_rp --seconds=15 --runs=1 --tag=android55 --server=ws://127.0.0.1:17860`, using `tools/build_performance_apk.py`. The wrapper selects the authorized device, records APK checksum, model, Android version and battery temperature, and validates all five collected samples. It retains caches of the isolated `com.bobux.performance` package; the ordinary game package is untouched. It removes only forwarding created by this invocation and stops only its dedicated server, collector and isolated diagnostic app. An existing identical reverse mapping is retained.

`--capture-valley` retains a settling screenshot. `--valley-motion` additionally
requires observed `--camera x1,y1,x2,y2` and `--joystick x1,y1,x2,y2` coordinates;
it records a camera turn, walk, screenshots and video. These measurements are
labelled as a diagnostic replay, not a baseline. For an older diagnostic APK
whose start-control check was insufficient, `--valley-start-tap x,y` uses the
observed original button position and saves an additional screenshot after the
physical ADB tap. Coordinates must fit the captured device dimensions.

Runner contracts: `python -m unittest discover -s tools -p test_performance_runners.py`.
