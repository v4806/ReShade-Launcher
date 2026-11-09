# XXMI Injector Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace `injector.exe` with an adapted XXMI `3dmloader.dll` adapter while preserving every existing injection-dependent launch mode.

**Architecture:** A Python module builds a deterministic DLL plan, launches the configured program, binds injection to the new target PID, and calls `3dmloader.dll` through `ctypes`. The native injector keeps upstream exports and adds a PID-bound CBT hook that does not require the host-side `d3dx.ini` loader name to match ReShade Launcher.

**Tech Stack:** Python 3.14, pytest, ctypes, psutil, PyQt6, C++17, MSVC v143, `3dmloader.dll`.

**Spec:** `docs/superpowers/specs/2026-11-09-xxmi-injector-migration-design.md`

## Global Constraints

- `direct` is the default when `injection_method` is absent.
- DLL order remains `ReShade64.dll`, `d3d11_path`, then `dll_files`.
- `validate_launch()` and `launch_game()` remain importable from `注入启动模块.py`.
- All paths passed to native injection functions are absolute Unicode paths.
- A failed injection must not be automatically retried against the same process.
- Hook cleanup must run in `finally`.
- New builds must not execute `injector.exe`.
- HOOK is supported only when `launch_program` and `target_program` resolve to the same executable; launcher-to-child launches use DIRECT.
- The project is not a Git repository; record file hashes and test results in `.superpowers/sdd/xxmi-injector-migration/progress.md` instead of commits.

## Review Focus

- Same-name stale game process: only the process created by this launch may receive DLLs.
- Launcher-spawned child process: injection and exit monitoring must follow the selected child PID.
- Missing DLL in an old config: launch must fail before starting the game.
- HOOK after a prior failed startup: the mutex and hook must be reusable on the next launch.
- ReShade plus 3DMigoto in HOOK mode: the hook DLL must be confirmed loaded before remaining DLLs are injected.
- Paths containing spaces or non-ASCII characters: launch and native injection must preserve the exact path.
- Packaged one-dir execution: `3dmloader.dll`, translations, and the main executable must be found from app root or `_MEIPASS`.

---

### Task 1: Injection Planning and Validation

**Files:**
- Create: `xxmi_injection.py`
- Create: `tests/test_xxmi_injection_plan.py`
- Modify: `.superpowers/sdd/xxmi-injector-migration/progress.md`

**Interfaces:**
- Produces: `InjectionPlan(method: str, hook_dll: Path | None, direct_dlls: tuple[Path, ...])`
- Produces: `build_injection_plan(config: dict, script_dir: str) -> InjectionPlan`
- Produces: `validate_injection_plan(config: dict, script_dir: str) -> tuple[bool, str]`
- Produces: `hook_candidate(config: dict) -> Path | None`

- [ ] **Step 1: Write failing tests**

```python
def test_direct_plan_preserves_reshade_d3d11_and_custom_order(tmp_path):
    ...
    assert [p.name for p in plan.direct_dlls] == [
        "ReShade64.dll", "d3d11.dll", "custom.dll"
    ]

def test_missing_dll_is_an_error_not_filtered(tmp_path):
    ...
    assert ok is False
    assert "missing.dll" in error

def test_hook_plan_excludes_hook_dll_from_direct_list(tmp_path):
    ...
    assert plan.method == "hook"
    assert plan.hook_dll.name == "d3d11.dll"
    assert [p.name for p in plan.direct_dlls] == ["ReShade64.dll", "custom.dll"]

def test_launcher_child_target_rejects_hook(tmp_path):
    config = {"launch_program": "launcher.exe", "target_program": "game.exe", ...}
    assert validate_injection_plan(config, str(tmp_path))[0] is False
```

- [ ] **Step 2: Run tests and verify RED**

Run: `python -m pytest tests/test_xxmi_injection_plan.py -q`
Expected: FAIL because `xxmi_injection` and `build_injection_plan` do not exist.

- [ ] **Step 3: Implement minimal planning API**

Implement `xxmi_injection.py` with a `Path`-based plan, runtime-path lookup for app root and `_MEIPASS`, method normalization, explicit missing-file errors, and HOOK candidate validation.

- [ ] **Step 4: Run tests and verify GREEN**

Run: `python -m pytest tests/test_xxmi_injection_plan.py -q`
Expected: PASS.

### Task 2: Adapted Native Hook DLL

**Files:**
- Create: `native/3dmloader/Injector.cpp`
- Create: `native/3dmloader/Injector.h`
- Create: `native/3dmloader/InjectorLib.vcxproj`
- Create: `native/3dmloader/BUILD.md`
- Create: `native/3dmloader/LICENSE.GPL.txt`
- Create: `tests/native/target.cpp`
- Create: `tests/native/probe.cpp`
- Create: `tests/test_xxmi_injection_native.py`
- Modify: `.superpowers/sdd/xxmi-injector-migration/progress.md`

**Interfaces:**
- Produces native export: `Inject(DWORD pid, LPCWSTR module_path, int timeout) -> int`
- Produces native export: `HookLibraryByPid(LPCWSTR module_path, DWORD target_pid, HHOOK *hook, HANDLE *mutex) -> int`
- Produces native export: `UnhookLibraryByPid(HHOOK *hook, HANDLE *mutex) -> int`
- Consumes: upstream XXMI `InjectorLib` source from commit carried in `BUILD.md`.

- [ ] **Step 1: Write failing native integration tests**

```python
def test_direct_injection_loads_probe_dll(tmp_path):
    ...
    assert adapter.inject(pid, str(probe_dll)) == 0
    assert marker_path.read_text() == str(pid)

def test_hook_injection_loads_d3d11_candidate_in_new_pid(tmp_path):
    ...
    result = launch_and_inject(config_with_hook, app_root, adapter_factory=real_adapter)
    assert result.target_pid > 0
    assert marker_path.read_text() == str(result.target_pid)

def test_preexisting_same_name_process_is_not_injected(tmp_path):
    ...
    assert preexisting_marker.exists() is False
    assert selected_marker.read_text() == str(result.target_pid)
```

- [ ] **Step 2: Run tests and verify RED**

Run: `python -m pytest tests/test_xxmi_injection_native.py -q`
Expected: FAIL because `native/3dmloader/3dmloader.dll` and the adapted export do not exist.

- [ ] **Step 3: Import and adapt upstream InjectorLib**

Copy the XXMI `InjectorLib` source, preserve upstream exports, add a named shared-memory configuration, add a CBT callback in `3dmloader.dll`, and provide `HookLibraryByPid`. Do not modify XXMI's `d3d11.dll`.

Fix the upstream remote-thread timeout cleanup: do not free the remote path allocation unless `WaitForSingleObject` confirms the remote thread ended. Add a separate PID-bound unhook function so the new callback state never depends on the upstream `HookLibrary` globals.

- [ ] **Step 4: Build x64 DLL**

Run: `& 'C:\Program Files\Microsoft Visual Studio\18\Community\MSBuild\Current\Bin\MSBuild.exe' native\3dmloader\InjectorLib.vcxproj /p:Configuration=Release /p:Platform=x64 /m`
Expected: exit 0 and `native/3dmloader/x64/Release/3dmloader.dll` exists.

- [ ] **Step 5: Build the controlled native test target and probe**

Run: `powershell -ExecutionPolicy Bypass -File tests\native\build_test_binaries.ps1`
Expected: `tests/native/bin/x64/target.exe` and `probe.dll` exist.

- [ ] **Step 6: Copy the built DLL to the application root**

Copy `native/3dmloader/x64/Release/3dmloader.dll` to `3dmloader.dll`.

- [ ] **Step 7: Run native tests and verify GREEN**

Run: `python -m pytest tests/test_xxmi_injection_native.py -q`
Expected: PASS for DIRECT and HOOK injection, unique PID selection, and cleanup into generated x64 test processes.

### Task 3: ctypes Adapter and Launch Orchestration

**Files:**
- Modify: `xxmi_injection.py`
- Create: `tests/test_xxmi_injection_launch.py`
- Modify: `.superpowers/sdd/xxmi-injector-migration/progress.md`

**Interfaces:**
- Produces: `XxmiInjector(injector_path: str | Path)`
- Produces methods: `inject(pid: int, dll_path: str | Path, timeout: int = 15) -> None`
- Produces methods: `hook_by_pid(dll_path: str | Path, target_pid: int) -> None`
- Produces methods: `unhook() -> None`
- Produces: `launch_game(config: dict, script_dir: str) -> LaunchResult | None`
- Produces: `LaunchResult(root_pid: int, target_pid: int, root_process: SuspendedProcess | None)`
- Consumes: Task 1 plan API and Task 2 native exports.

- [ ] **Step 1: Write failing orchestration tests**

```python
def test_direct_launch_binds_new_pid_and_injects_in_order(fake_runtime):
    ...
    assert fake_injector.calls == [
        (target_pid, "ReShade64.dll"),
        (target_pid, "d3d11.dll"),
        (target_pid, "custom.dll"),
    ]

def test_hook_launch_cleans_up_after_injection_error(fake_runtime):
    ...
    assert fake_injector.unhook_count == 1

def test_launch_does_not_choose_preexisting_same_name_process(fake_runtime):
    ...
    assert selected_pid == new_pid

def test_direct_same_exe_injects_before_resume(fake_runtime):
    ...
    assert fake_runtime.events == ["create_suspended", "inject", "resume"]

def test_launcher_child_uses_direct_even_when_config_requests_hook(fake_runtime):
    ...
    assert plan.method == "direct"
```

- [ ] **Step 2: Run tests and verify RED**

Run: `python -m pytest tests/test_xxmi_injection_launch.py -q`
Expected: FAIL because the adapter and orchestration functions are incomplete.

- [ ] **Step 3: Implement ctypes adapter and process binding**

Load only required native exports, use absolute paths, select a new matching PID from the pre-launch snapshot, preserve launch arguments, verify loaded module paths, and always release hook state in `finally`.

Use `CreateProcessW(CREATE_SUSPENDED)` for direct executable launches. Inject HOOK candidates and same-process DIRECT DLLs before resuming the primary thread. For launcher-to-child launches, resume the launcher, select a descendant/new PID with matching executable path, then inject.

- [ ] **Step 4: Run tests and verify GREEN**

Run: `python -m pytest tests/test_xxmi_injection_launch.py -q`
Expected: PASS.

### Task 4: Replace Launcher Injection Facade and Configuration Flow

**Files:**
- Modify: `注入启动模块.py`
- Modify: `ReShade启动器.py`
- Modify: `进程管理.py`
- Modify: `配置管理器.py`
- Modify: `对话框模块.py`
- Create: `tests/test_launcher_compatibility.py`
- Modify: `.superpowers/sdd/xxmi-injector-migration/progress.md`

**Interfaces:**
- Preserves: `validate_launch(config, script_dir) -> tuple[bool, str]`
- Preserves: `launch_game(config, script_dir) -> tuple[int | None, int | None]`
- Adds config field: `"injection_method": "direct" | "hook"`
- Preserves: all existing `reshade_dll`, `d3d11_path`, `dll_files`, shortcut, and process-management fields.

- [ ] **Step 1: Write failing compatibility tests**

```python
def test_legacy_config_without_injection_method_defaults_to_direct():
    ...
    assert plan.method == "direct"

def test_saved_configs_include_explicit_direct_method():
    ...
    assert config["injection_method"] == "direct"

def test_process_cleanup_has_no_global_injector_taskkill():
    ...
    assert "taskkill /F /IM injector.exe" not in source_text

def test_edit_config_round_trip_preserves_hook_method():
    ...
    assert data["injection_method"] == "hook"
```

- [ ] **Step 2: Run tests and verify RED**

Run: `python -m pytest tests/test_launcher_compatibility.py -q`
Expected: FAIL on missing field and old injector cleanup.

- [ ] **Step 3: Replace facade and add selector**

Make `注入启动模块.py` delegate validation and launch to `xxmi_injection.py`; retain VC++ helpers. Add the injection-method selector to the edit dialog, save explicit `direct` for newly created configs, and remove `injector.exe` cleanup. Use `target_pid` for exit monitoring and registered-process termination. If injection fails after the game starts, keep that PID registered and return an explicit failure so the shortcut does not report a normal exit.

- [ ] **Step 4: Run tests and verify GREEN**

Run: `python -m pytest tests/test_launcher_compatibility.py -q`
Expected: PASS.

### Task 5: Packaging and Update Metadata

**Files:**
- Modify: `ReShade Launcher Build.spec`
- Modify: `ReShade Debug.spec`
- Modify: `更新管理器.py`
- Modify: `生成更新清单.py`
- Modify: `update_manifest.json`
- Modify: `translations.json`
- Create: `tests/test_packaging_metadata.py`
- Modify: `.superpowers/sdd/xxmi-injector-migration/progress.md`

**Interfaces:**
- Produces packaged data entry: `3dmloader.dll`
- Removes update item: `injector.exe`
- Produces application update ZIP containing both EXEs and `_internal/3dmloader.dll`

- [ ] **Step 1: Write failing packaging tests**

```python
def test_update_manifest_uses_3dmloader_instead_of_injector():
    ...
    assert "injector.exe" not in paths
    assert manifest["app"]["url"].endswith(".zip")

def test_pyinstaller_specs_include_3dmloader():
    ...
    assert "3dmloader.dll" in spec_text
```

- [ ] **Step 2: Run tests and verify RED**

Run: `python -m pytest tests/test_packaging_metadata.py -q`
Expected: FAIL because packaging and manifest still name `injector.exe`.

- [ ] **Step 3: Update specs, manifest, translations, and help text**

Add the built DLL to both specs, remove `injector.exe` from update references, update Chinese and English user-facing text, and replace language packs that mention `injector.exe` with generic `3dmloader.dll` wording.

- [ ] **Step 4: Build a packaged application**

Run: `pyinstaller --noconfirm "ReShade Launcher Build.spec"`
Expected: the packaged app starts and resolves `3dmloader.dll` from `_internal`.

- [ ] **Step 5: Regenerate manifest with the app ZIP**

Run: `python 生成更新清单.py --app-src "dist\ReShade Launcher Build"`
Expected: exit 0, `update_manifest.json` has an `app` entry, and no independent `3dmloader.dll` item or `injector.exe` item exists.

- [ ] **Step 6: Run tests and verify GREEN**

Run: `python -m pytest tests/test_packaging_metadata.py -q`
Expected: PASS.

### Task 6: Full Verification

**Files:**
- Modify: `.superpowers/sdd/xxmi-injector-migration/progress.md`

**Interfaces:**
- Consumes every prior task.

- [ ] **Step 1: Run the complete automated suite**

Run: `python -m pytest -q`
Expected: all tests pass.

- [ ] **Step 2: Compile-check production Python files**

Run: `python -m py_compile xxmi_injection.py 注入启动模块.py ReShade启动器.py 配置管理器.py 对话框模块.py 进程管理.py 更新管理器.py 生成更新清单.py`
Expected: exit 0.

- [ ] **Step 3: Verify native exports**

Run: `python -c "import ctypes; d=ctypes.WinDLL(r'3dmloader.dll'); print(d.Inject, d.HookLibraryByPid, d.UnhookLibraryByPid)"`
Expected: all three exports resolve.

- [ ] **Step 4: Verify plans for all four modes**

Run: `python -m pytest tests/test_xxmi_injection_plan.py tests/test_launcher_compatibility.py -q`
Expected: PASS for ReShade-only, built-in, custom, and XXMI plans.

- [ ] **Step 5: Run controlled DIRECT and HOOK integration tests**

Run: `python -m pytest tests/test_xxmi_injection_native.py -q`
Expected: PASS and both probe marker files are created by the selected target PIDs.

- [ ] **Step 6: Verify old-install upgrade path**

Extract `_test_app.zip` to a temporary directory, run the update manager against the newly generated manifest/app ZIP in a test harness, and verify the EXE plus `_internal/3dmloader.dll` are replaced as one unit.

Run: `python -m pytest tests/test_packaging_metadata.py -q`
Expected: PASS.

- [ ] **Step 7: Record evidence**

Write commands, exit codes, pass counts, DLL hashes, and any manual limitation to `.superpowers/sdd/xxmi-injector-migration/progress.md`.
