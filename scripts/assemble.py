#!/usr/bin/env python3
"""把 SPM 产物组装成可双击运行的 .app 包。"""
import os
import shutil
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCRATCH = os.path.join(ROOT, "build", ".spm")
APP = os.path.join(ROOT, "build", "AirLingo.app")
CONTENTS = os.path.join(APP, "Contents")
MACOS = os.path.join(CONTENTS, "MacOS")
RESOURCES = os.path.join(CONTENTS, "Resources")
BIN_CANDIDATES = [
    os.path.join(ROOT, "build", "out", "AirLingo"),
    os.path.join(SCRATCH, "apple", "Products", "release", "AirLingo"),
]

# 固定的签名身份：只要签名不变，TCC（辅助功能/屏幕录制）的授权就不会因为重新构建而失效。
# 用 ad-hoc（"-"）签名时系统按 cdhash 记录授权，每次编译都会换哈希，授权就会失效。
SIGN_IDENTITY = os.environ.get("AIRLINGO_SIGN_ID", "AirLingo Dev")
BUNDLE_ID = "com.airlingo.mac"


def _identity_available() -> bool:
    try:
        out = subprocess.run(["security", "find-identity", "-v", "-p", "codesigning"],
                             capture_output=True, text=True).stdout
    except OSError:
        return False
    return SIGN_IDENTITY in out


def sign() -> None:
    identity = SIGN_IDENTITY if _identity_available() else "-"
    subprocess.run(["codesign", "--force", "--timestamp=none",
                    "--identifier", BUNDLE_ID,
                    "--sign", identity, APP],
                   capture_output=True, text=True)
    verify = subprocess.run(["codesign", "--verify", "--deep", "--strict", APP],
                            capture_output=True, text=True)
    if verify.returncode == 0:
        req = subprocess.run(["codesign", "-d", "-r-", APP],
                             capture_output=True, text=True).stderr.strip()
        print(f"签名身份: {identity}")
        if "designated" in req:
            print(f"授权绑定: {req.splitlines()[-1].strip()}")
    else:
        print(f"签名校验失败: {verify.stderr.strip()}", file=sys.stderr)


def main() -> int:
    BIN = next((p for p in BIN_CANDIDATES if os.path.exists(p)), None)
    if not BIN:
        print("找不到编译产物，先运行 scripts/build.sh", file=sys.stderr)
        return 1

    if os.path.exists(APP):
        try:
            shutil.rmtree(APP)
        except OSError:
            pass
    os.makedirs(MACOS, exist_ok=True)
    os.makedirs(RESOURCES, exist_ok=True)

    shutil.copy2(BIN, os.path.join(MACOS, "AirLingo"))
    os.chmod(os.path.join(MACOS, "AirLingo"), 0o755)
    shutil.copy2(os.path.join(ROOT, "scripts", "Info.plist"), os.path.join(CONTENTS, "Info.plist"))

    icon_source = os.path.join(ROOT, "Resources", "AppIcon.icns")
    if os.path.exists(icon_source):
        shutil.copy2(icon_source, os.path.join(RESOURCES, "AppIcon.icns"))

    sign()
    print(f"已生成 {APP}")

    # 安装到 /Applications：路径固定，避免同一应用出现多份授权记录。
    installed = os.environ.get("AIRLINGO_INSTALL") == "1"
    if installed:
        target = "/Applications/AirLingo.app"
        subprocess.run(["pkill", "-f", f"{target}/Contents/MacOS/AirLingo"], capture_output=True)
        if os.path.exists(target):
            shutil.rmtree(target, ignore_errors=True)
        subprocess.run(["ditto", APP, target], capture_output=True)
        print(f"已安装 {target}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
