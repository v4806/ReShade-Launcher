# Adapted XXMI 3dmloader

Source basis: `SpectrumQT/XXMI-Libs-Package`, `InjectorLib/Injector.cpp` at local source commit `065dc746`.

The upstream `Inject`, `HookLibrary`, `WaitForInjection`, `UnhookLibrary`, and `StartProcess` exports remain available. This build adds:

- `HookLibraryByPid`: installs a PID-bound CBT hook without loading the target `d3d11.dll` into the launcher process.
- `UnhookLibraryByPid`: releases only resources owned by `HookLibraryByPid`.

The `Inject` timeout path no longer frees the remote argument buffer until the remote thread is confirmed finished. If it times out, the allocation is left to the target process lifetime rather than risking a use-after-free.

Build x64 Release:

```powershell
& 'C:\Program Files\Microsoft Visual Studio\18\Community\MSBuild\Current\Bin\MSBuild.exe' .\InjectorLib.vcxproj /p:Configuration=Release /p:Platform=x64 /m
```

Output: `x64\Release\3dmloader.dll`.

This repository contains GPLv3 text in `LICENSE.GPL.txt` and the upstream notice in `COPYING.txt`.
