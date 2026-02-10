# Tiny Decoder-Only Transformer (SLM) + JARVIS HUD

Offline educational project demonstrating the internals of a tiny **decoder-only Transformer** (untrained) with a **JARVIS-style Qt/QML HUD**.

## Backend (Python)

### Quick start (global Python on Windows)
```powershell
.\run.ps1 -InstallDeps
```

### GPU (optional, NVIDIA)
The backend already prefers CUDA automatically, but your Python environment must have a **CUDA-enabled** PyTorch build.

Check what you have:
```powershell
python -c "import torch; print(torch.__version__); print('cuda_available', torch.cuda.is_available()); print('torch.version.cuda', torch.version.cuda)"
```

If your version ends with `+cpu` (and `cuda_available` is `False`), reinstall PyTorch with CUDA using the official selector:
```text
https://pytorch.org/get-started/locally/
```

### One-click launcher (EXE)
Build a small Windows launcher that starts the backend and then opens the GUI (if built):
```powershell
cmake -S launcher -B launcher\build
cmake --build launcher\build --config Release
.\launcher\build\Release\JarvisLauncher.exe
```

If you already have `JarvisLauncher.exe` in the project root, you can just double-click it.

### Setup
```powershell
cd backend
python -m venv .venv
.\.venv\Scripts\pip install -r requirements.txt
```

### Run
```powershell
cd backend
.\.venv\Scripts\python server.py
```

The backend starts a WebSocket server on `ws://localhost:8765`.

## GUI (Qt 6 + QML)

### Build (CMake)
You need a Qt 6 installation that includes **Qt Quick** and **Qt WebSockets**.

```powershell
cd gui
cmake -S . -B build
cmake --build build --config Release
```

### Run
```powershell
.\build\Release\JarvisHUD.exe
```

The GUI connects to `ws://localhost:8765` automatically.
