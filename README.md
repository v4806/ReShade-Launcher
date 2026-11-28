# ReShade Launcher

Windows 游戏 Mod 与 ReShade 启动器，使用 C++20、Win32、Direct2D 和 DirectWrite 构建。

## 功能

- 支持 XXMI、内置 Mod 加载器、ReShade 游戏和自定义 DLL 配置。
- 默认包不包含内置 Mod 加载器；选择受支持的游戏时会从本仓库按需下载并校验安装，仓库没有对应加载器时才打开目录由用户手动放置。
- 默认只安装精简着色器包，完整着色器和纹理包按需从 GitHub 下载。
- 从 GitHub Releases 检查更新，校验 SHA-256 后静默安装并自动重启。
- 保留已有的 `launch_config`、`custom_data`、Presets、Mods 和 `d3dx_user.ini`。

## 构建

需要 Windows 10/11 x64、Visual Studio C++ 工作负载、CMake、Ninja、Inno Setup 6 和 Python 3。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\build_release.ps1
```

构建默认执行干净编译，避免 C++ 头文件依赖缓存导致旧对象混入发布包。日常调试可显式使用增量编译：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\build_release.ps1 -Incremental
```

## 产物

- `dist\release\ReShade-Launcher-installer-v3.0.0.exe`
- `dist\release\ReShade-Launcher-portable-v3.0.0.zip`
- `dist\release\ReShade-Launcher-shaders-full-v1.zip`

内置 Mod 加载器的按需下载包位于 `mod-loaders\`，构建时会根据 `MOD_loader\` 内容生成并写入 `version.json`。Inno Setup 脚本位于 `packaging\ReShade-Launcher.iss`。完整着色器包作为 GitHub Release 资产单独发布，不进入安装器或便携包；内置 Mod 加载器也不会进入安装器或便携包。

## 测试

```powershell
python -m pytest tests\test_shader_pack_builder.py -q
ctest --preset windows-x64-release --output-on-failure
```

使用教程视频：
https://www.bilibili.com/video/BV1fcTz68EYs/
