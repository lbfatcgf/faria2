# 构建发布包

需要 Flutter **3.47+**（Dart 3.13+），与 `pubspec.lock` 的 SDK 约束一致。

## Linux

依赖：

```bash
sudo apt-get install -y clang cmake ninja-build pkg-config \
  libgtk-3-dev liblzma-dev libx11-dev libxi-dev
```

构建并打包：

```bash
./scripts/build_linux_release.sh
```

输出：

```text
dist/faria2-linux-x64.tar.gz
# arm64 机器上为 dist/faria2-linux-arm64.tar.gz
```

压缩包内顶层目录为 `faria2/`，包含可执行文件、Flutter 运行库以及
`README.md`、`LICENSE`。运行方式：

```bash
tar -xzf dist/faria2-linux-x64.tar.gz
./faria2/faria2
```

## Windows

依赖：Visual Studio 2022（勾选“使用 C++ 的桌面开发”工作负载）。

在 PowerShell 中构建并打包：

```powershell
.\scripts\build_windows_release.ps1
```

输出：

```text
dist/faria2-windows-x64.zip
```

压缩包内顶层目录为 `faria2`，解压后运行：

```text
faria2\faria2.exe
```

## 指定 Flutter

如果 `flutter` 不在 PATH 中：

```bash
FLUTTER=/path/to/flutter ./scripts/build_linux_release.sh
```

```powershell
$env:FLUTTER = 'C:\path\to\flutter\bin\flutter.bat'
.\scripts\build_windows_release.ps1
```

## GitHub Actions

工作流：[`.github/workflows/build-release.yml`](../.github/workflows/build-release.yml)

- 只有推送 `v*` 标签（例如 `v1.0.1`）才会自动构建：
  1. 在 Ubuntu 上分析、测试并构建 Linux x64 压缩包；
  2. 在 Windows 上构建 Windows x64 压缩包；
  3. 把两个压缩包附加到对应的 GitHub Release。
- `main` / `master` 的普通提交不会触发工作流。
- 也可以在 GitHub 的 **Actions → Build release → Run workflow** 手动触发，
  构建完成后从该次运行的 Artifacts 下载压缩包（不会创建 Release）。

示例：

```bash
git tag v1.0.1
git push origin v1.0.1
```

faria2 首次运行时会自动下载 aria2c 到用户缓存目录，因此目标机器需要能访问
下载源；也可以在设置中手动指定已安装的 aria2c。
