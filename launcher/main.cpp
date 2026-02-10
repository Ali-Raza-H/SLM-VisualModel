#include <windows.h>

#include <filesystem>
#include <optional>
#include <string>
#include <vector>

namespace fs = std::filesystem;

static std::wstring quoteArg(const std::wstring &s) {
  // Minimal Windows command-line quoting:
  // - wrap in quotes if it contains whitespace
  // - escape embedded quotes
  if (s.find_first_of(L" \t\n\v\"") == std::wstring::npos) {
    return s;
  }
  std::wstring out;
  out.push_back(L'"');
  for (wchar_t ch : s) {
    if (ch == L'"') {
      out.append(L"\\\"");
    } else {
      out.push_back(ch);
    }
  }
  out.push_back(L'"');
  return out;
}

static std::wstring moduleDir() {
  std::wstring buf;
  buf.resize(32768);
  const DWORD n = GetModuleFileNameW(nullptr, buf.data(), static_cast<DWORD>(buf.size()));
  if (n == 0 || n >= buf.size()) {
    return L".";
  }
  buf.resize(n);
  const fs::path p(buf);
  return p.parent_path().wstring();
}

static std::optional<std::wstring> findOnPath(const wchar_t *exeName) {
  std::wstring buf;
  buf.resize(32768);
  const DWORD n =
      SearchPathW(nullptr, exeName, nullptr, static_cast<DWORD>(buf.size()), buf.data(), nullptr);
  if (n == 0 || n >= buf.size()) {
    return std::nullopt;
  }
  buf.resize(n);
  return buf;
}

struct Proc {
  HANDLE process = nullptr;
  HANDLE thread = nullptr;
};

static void closeProc(Proc &p) {
  if (p.thread) {
    CloseHandle(p.thread);
    p.thread = nullptr;
  }
  if (p.process) {
    CloseHandle(p.process);
    p.process = nullptr;
  }
}

static std::optional<Proc> startProcess(const std::wstring &app, const std::wstring &cmdLine,
                                        const std::wstring &workDir, DWORD creationFlags) {
  STARTUPINFOW si{};
  si.cb = sizeof(si);
  PROCESS_INFORMATION pi{};

  // CreateProcess requires a mutable buffer for the command line.
  std::vector<wchar_t> mutableCmd(cmdLine.begin(), cmdLine.end());
  mutableCmd.push_back(L'\0');

  const BOOL ok = CreateProcessW(app.c_str(), mutableCmd.data(), nullptr, nullptr, FALSE,
                                creationFlags, nullptr, workDir.c_str(), &si, &pi);
  if (!ok) {
    return std::nullopt;
  }

  Proc p;
  p.process = pi.hProcess;
  p.thread = pi.hThread;
  return p;
}

static DWORD getExitCode(HANDLE h) {
  DWORD code = 0;
  if (!GetExitCodeProcess(h, &code)) {
    return 0;
  }
  return code;
}

static int msgBox(const std::wstring &text, const std::wstring &caption, UINT flags) {
  return MessageBoxW(nullptr, text.c_str(), caption.c_str(), flags | MB_TOPMOST);
}

static std::optional<fs::path> findGuiExe(const fs::path &root) {
  const fs::path gui = root / "gui";
  const std::vector<fs::path> candidates = {
      gui / "build" / "Release" / "JarvisHUD.exe",
      gui / "build" / "Debug" / "JarvisHUD.exe",
      gui / "build" / "JarvisHUD.exe",
      gui / "build-msvc" / "Release" / "JarvisHUD.exe",
      gui / "build-msvc" / "Debug" / "JarvisHUD.exe",
      gui / "build-mingw" / "JarvisHUD.exe",
  };

  for (const auto &p : candidates) {
    if (fs::exists(p)) {
      return p;
    }
  }

  // Fallback: find it anywhere under gui/ (useful when build dirs are renamed).
  try {
    for (auto it = fs::recursive_directory_iterator(gui); it != fs::recursive_directory_iterator();
         ++it) {
      const auto &p = it->path();
      if (!it->is_regular_file()) {
        continue;
      }
      if (p.filename() == "JarvisHUD.exe") {
        return p;
      }
    }
  } catch (...) {
    // Ignore filesystem traversal issues.
  }

  return std::nullopt;
}

int WINAPI wWinMain(HINSTANCE, HINSTANCE, PWSTR, int) {
  const fs::path root(moduleDir());
  const fs::path backendDir = root / "backend";
  const fs::path serverPy = backendDir / "server.py";

  if (!fs::exists(serverPy)) {
    msgBox(L"Missing backend/server.py next to the launcher.\n\n"
           L"Expected:\n  " +
               serverPy.wstring(),
           L"JarvisLauncher", MB_ICONERROR);
    return 1;
  }

  // Prefer python.exe, fallback to py.exe -3
  auto python = findOnPath(L"python.exe");
  bool usingPyLauncher = false;
  if (!python) {
    python = findOnPath(L"py.exe");
    usingPyLauncher = python.has_value();
  }
  if (!python) {
    msgBox(L"Python not found.\n\nInstall Python 3.10+ and ensure 'python' or 'py' is on PATH.",
           L"JarvisLauncher", MB_ICONERROR);
    return 1;
  }

  std::wstring backendCmd;
  if (usingPyLauncher) {
    backendCmd = quoteArg(*python) + L" -3 " + quoteArg(serverPy.wstring());
  } else {
    backendCmd = quoteArg(*python) + L" " + quoteArg(serverPy.wstring());
  }

  // Start backend in a separate console so logs are visible.
  auto backendProc =
      startProcess(*python, backendCmd, backendDir.wstring(), CREATE_NEW_CONSOLE);
  if (!backendProc) {
    const DWORD err = GetLastError();
    msgBox(L"Failed to start backend process.\n\nCreateProcess error: " + std::to_wstring(err),
           L"JarvisLauncher", MB_ICONERROR);
    return 1;
  }

  // If backend exits immediately, show a helpful message.
  Sleep(500);
  const DWORD backendCode = getExitCode(backendProc->process);
  if (backendCode != STILL_ACTIVE) {
    closeProc(*backendProc);
    msgBox(
        L"The backend exited immediately.\n\nCommon causes:\n"
        L"- Missing Python packages (torch/numpy/websockets)\n"
        L"- Port 8765 already in use\n\n"
        L"Fix packages with:\n  python -m pip install -r backend\\requirements.txt",
        L"JarvisLauncher", MB_ICONERROR);
    return 1;
  }

  // Try to start the GUI if it's already built.
  auto guiExe = findGuiExe(root);
  if (!guiExe) {
    msgBox(L"Backend started (ws://localhost:8765), but GUI executable was not found.\n\n"
           L"Build the GUI with Qt 6:\n"
           L"  cd gui\n"
           L"  cmake -S . -B build\n"
           L"  cmake --build build --config Release\n",
           L"JarvisLauncher", MB_ICONWARNING);
    // Leave backend running in its console.
    closeProc(*backendProc);
    return 0;
  }

  const std::wstring guiApp = guiExe->wstring();
  const std::wstring guiCmd = quoteArg(guiApp);
  auto guiProc = startProcess(guiApp, guiCmd, guiExe->parent_path().wstring(), 0);
  if (!guiProc) {
    msgBox(L"Backend started, but failed to start the GUI:\n\n" + guiApp, L"JarvisLauncher",
           MB_ICONERROR);
    closeProc(*backendProc);
    return 1;
  }

  // Keep launcher alive: when GUI exits, terminate backend.
  WaitForSingleObject(guiProc->process, INFINITE);
  TerminateProcess(backendProc->process, 0);

  closeProc(*guiProc);
  closeProc(*backendProc);
  return 0;
}
