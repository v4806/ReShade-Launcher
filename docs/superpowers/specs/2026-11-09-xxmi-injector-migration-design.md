# XXMI Injector Migration Design

## Intent

Replace the external `injector.exe` dependency with an in-process adapter for XXMI's `3dmloader.dll`, while preserving every current launch path that depends on DLL injection: ReShade, built-in `d3d11.dll`, custom DLL lists, and XXMI importer configurations.

## Goals

- Keep the public functions `validate_launch()` and `launch_game()` so shortcuts, tray behavior, signal handling, and process management do not need a new entry point.
- Use `3dmloader.dll` as the only injector runtime in new builds.
- Preserve the effective DLL order: `ReShade64.dll`, `d3d11_path`, then `dll_files` in their saved order.
- Bind injection success to the PID created by this launch, not just a process image name.
- Support DIRECT by default for all existing configurations.
- Support HOOK for configurations that explicitly select it and provide a 3DMigoto `d3d11.dll`.
- Clean up hooks, mutexes, and native references on success, failure, timeout, and exceptions.
- Package the injector DLL and update manifest as one versioned unit.

## Non-Goals

- Do not import the whole XXMI Launcher package, platform, or event system.
- Do not modify game files, importer `d3dx.ini` files, or existing launch JSON files in bulk.
- Do not remove the old `injector.exe` from already released installations; new builds simply stop requiring or invoking it.
- Do not promise that ReShade and 3DMigoto share a fixed load order in HOOK mode. DIRECT remains the compatibility path when order matters.

## Injection Model

### DIRECT

1. Start `launch_program` with the saved arguments and working directory.
2. Resolve the target process created by this launch.
3. Call `3dmloader.dll!Inject(pid, absolute_dll_path, timeout)` once per DLL in plan order.
4. Verify the loaded module path belongs to the selected PID.

DIRECT is the default because it preserves current behavior and works for ReShade-only and custom-DLL configurations without a 3DMigoto candidate.

### HOOK

The stock XXMI `HookLibrary` assumes a loader relationship described by `d3dx.ini`. It loads the requested `d3d11.dll` into the launcher process before installing a desktop-wide CBT hook, so an unrelated launcher name can fail the DLL's host validation.

HOOK is limited to direct executable launches where `launch_program` and `target_program` resolve to the same executable. Launcher-to-child launch chains remain DIRECT because the target PID is not known before the launcher starts the child.

The adapted injector keeps the upstream exports and adds a dedicated PID-bound hook entry point:

1. Create the game process with `CREATE_SUSPENDED` and retain its PID, process handle, and primary thread handle.
2. Create a shared-memory configuration object containing that PID and the absolute `d3d11.dll` path.
3. Install a CBT hook whose callback lives in the adapted `3dmloader.dll`.
4. Resume the game's primary thread.
5. In the target process's hook callback, load the configured `d3d11.dll` directly.
6. Wait until that DLL is present in the selected PID.
7. Inject the remaining DLLs through DIRECT mode in their original order.
8. Verify every selected DLL path exists in that PID and release the hook resources in `finally`.

The hook DLL is excluded from the DIRECT DLL list, because it is loaded by the CBT callback.

For DIRECT launches, the suspended process is resumed and injection starts immediately. Native probing showed that a remote `LoadLibraryW` thread is not observable as a loaded module while the process remains suspended. For launcher-to-child launches, the launcher is resumed, the new child PID is selected from the launch chain, and DLLs are injected after discovery.

## Python Architecture

`xxmi_injection.py` owns planning, process selection, native-library calls, verification, and cleanup. `注入启动模块.py` remains the compatibility facade used by the GUI and retains the VC++ runtime helpers.

Add `injection_method` to launch JSON:

- Missing or empty: `direct`.
- `direct`: use DIRECT for every selected DLL.
- `hook`: require exactly one `d3d11.dll` candidate and use the adapted hook entry point.

Existing JSON files remain valid. New files explicitly save `direct`.

## Process Identity

Take a process snapshot before launching, then select only a matching target process that:

- has a PID not present in the pre-launch snapshot;
- belongs to the launch chain rooted at the process created by this launcher;
- matches the saved `target_program` path when available;
- otherwise matches `game_exe_name`.

The returned tuple remains `(root_pid, target_pid)`. `root_pid` is the process started by the launcher; `target_pid` is the process used for injection and later window/exit monitoring.

The same identity is used by window detection, exit waiting, shortcut auto-close, and explicit game termination. Name-only process termination is removed from these paths. If a unique target PID cannot be established, launch fails instead of guessing.

## Failure Handling

- Missing DLLs are errors during validation; do not silently filter them out.
- Injection return codes are errors and include the DLL path and native code.
- A native injection timeout must not free remote argument memory while its remote thread may still read it. The adapted source releases that memory only after the thread is confirmed finished; otherwise it intentionally leaves the remote allocation to die with the target process.
- A timeout leaves the game process tracked but reports launch failure; no automatic retry is performed.
- Hook cleanup runs in `finally`.
- Process-tree cleanup only handles processes registered by this launch. Remove the global `taskkill /IM injector.exe` operation.

## Packaging and Licensing

- Ship the adapted x64 `3dmloader.dll` in the PyInstaller `_internal` data set for packaged builds and in the source root for development.
- Include the source, build project, upstream commit, and GPLv3 notice in `native/3dmloader/`.
- Remove `injector.exe` from update selection and `update_manifest.json`.
- Publish `3dmloader.dll` only through the application ZIP generated with `--app-src`, so EXE code and native DLL cannot be updated independently to incompatible versions.
- Update user-facing help text that currently names `injector.exe`.

## Acceptance

- Unit tests cover plan order, missing-file handling, DIRECT/HOOK selection, target PID selection, and hook cleanup.
- Native integration tests prove a probe DLL is injected by DIRECT and by HOOK into a controlled x64 target.
- Native tests prove the selected target PID is the only process that receives the probe DLL, including a pre-existing same-name process.
- Existing launch JSON without `injection_method` still validates and launches.
- ReShade, built-in `d3d11.dll`, custom DLLs, and XXMI configurations each produce the expected injection plan.
- The previous `injector.exe` process is never started.
- The replacement is verified from an actual application update ZIP, not only by importing individual modules.
