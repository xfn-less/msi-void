"""Prepare a matching Homebrew Linux bottle for the normal XBPS transaction."""

import json
import pathlib
import re
import subprocess
import sys
import urllib.error
import urllib.request

OFFICIAL = "https://repo-fastly.voidlinux.org/current"
LOCAL = "/var/cache/xbps/qutebrowser"


def query(prop, package, remote=False):
    command = ["xbps-query"]
    if remote:
        command += ["-R", "-i", "--repository=" + OFFICIAL]
    return subprocess.check_output(command + ["-p", prop, package], text=True).strip()


def needs_update(installed, available):
    result = subprocess.run(
        ["xbps-uhelper", "cmpver", available, installed], check=False
    )
    if result.returncode not in (0, 1, 255):
        raise ValueError("XBPS 版本比较失败")
    return result.returncode == 1


class BottleUnavailable(ValueError):
    """The requested version has no available Linux bottle."""


def registry_index(name, version):
    if name not in ("qtwebengine", "libxml2") or not re.fullmatch(
        r"\d+\.\d+\.\d+(?:_\d+)?", version
    ):
        raise ValueError("无效的二进制名称或版本")
    with urllib.request.urlopen(
        f"https://ghcr.io/token?service=ghcr.io&scope=repository:homebrew/core/{name}:pull",
        timeout=60,
    ) as response:
        token = json.load(response)["token"]
    request = urllib.request.Request(
        f"https://ghcr.io/v2/homebrew/core/{name}/manifests/{version}",
        headers={
            "Authorization": "Bearer " + token,
            "Accept": "application/vnd.oci.image.index.v1+json",
        },
    )
    with urllib.request.urlopen(request, timeout=60) as response:
        return json.load(response)


def bottle(name, version):
    try:
        manifest = registry_index(name, version)
    except urllib.error.HTTPError as error:
        if error.code != 404:
            raise
        error.close()
        raise BottleUnavailable(f"仓库没有 {name} {version}") from error
    if (
        manifest.get("annotations", {}).get("org.opencontainers.image.version")
        != version
    ):
        raise ValueError(f"{name} 返回的清单版本与目标 {version} 不符")
    for entry in manifest.get("manifests", []):
        platform = entry.get("platform", {})
        if platform.get("os") != "linux" or platform.get("architecture") != "amd64":
            continue
        annotations = entry["annotations"]
        if (
            annotations.get("org.opencontainers.image.ref.name")
            != version + ".x86_64_linux"
        ):
            raise ValueError("Linux 二进制的版本标记不符")
        digest = annotations.get("sh.brew.bottle.digest", "")
        if not re.fullmatch("[a-f0-9]{64}", digest):
            raise ValueError("二进制校验值无效")
        return {
            "sha256": digest,
            "dependencies": json.loads(annotations["sh.brew.tab"])[
                "runtime_dependencies"
            ],
        }
    raise BottleUnavailable(f"{name} {version} 没有 x86_64 Linux 二进制")


def resolve(version):
    qt = bottle("qtwebengine", version)
    xml_dependency = next(
        (dep for dep in qt["dependencies"] if dep["full_name"] == "libxml2"), None
    )
    if xml_dependency is None:
        raise ValueError("Qt 二进制清单没有记录 libxml2，需检查新的打包方式")
    xml_version = xml_dependency["pkg_version"]
    if not re.fullmatch(r"\d+\.\d+\.\d+(?:_\d+)?", xml_version):
        raise ValueError("不支持的 libxml2 版本格式")
    xml = bottle("libxml2", xml_version)
    return {
        "qt": version,
        "xml": xml_version,
        "qt_sha": qt["sha256"],
        "xml_sha": xml["sha256"],
    }


def plan(destination):
    installed = subprocess.run(
        ["xbps-query", "-p", "pkgver", "qt6-webengine"], capture_output=True, text=True
    )
    if installed.returncode:
        print("未安装 QtWebEngine，跳过替代内核检查。")
        return
    if query("repository", "qt6-webengine") != LOCAL:
        print("QtWebEngine 不由本地脚本管理，继续使用原软件源。")
        return
    installed = installed.stdout.strip().removeprefix("qt6-webengine-")
    available = query("pkgver", "qt6-webengine", True).removeprefix("qt6-webengine-")
    if not re.fullmatch(r"6\.\d+\.\d+_\d+", available):
        raise ValueError(f"不支持的目标版本格式：{available}")
    if not needs_update(installed, available):
        print(f"QtWebEngine 本地 {installed}，官方 {available}：无需替换。")
        return
    version = available.rsplit("_", 1)[0]
    print(f"准备 QtWebEngine {installed} → {available}。")
    try:
        selected = resolve(version)
    except BottleUnavailable as error:
        print(f"{error}：保留当前内核，继续检查系统升级。")
        return
    selected["pkgver"] = available
    pathlib.Path(destination).write_text(json.dumps(selected))


def dependencies(manifest, needed_file):
    data = json.loads(pathlib.Path(manifest).read_text())
    version = data["qt"]
    major, minor, _ = map(int, version.split("."))
    upper = f"{major}.{minor + 1}"
    needed = set(pathlib.Path(needed_file).read_text().split())
    deps = []
    # Keep only upstream dependency providers used by these binaries, plus TLS.
    for dep in query("run_depends", "qt6-webengine", True).split():
        name = re.split("[<>=]", dep)[0]
        if name == "qt6-pdf":
            continue
        provided = set(query("shlib-provides", name, True).split())
        if not (provided & needed) and name != "qt6-plugin-tls-openssl":
            continue
        if name.startswith("qt6-"):
            dep = dep.split("<", 1)[0] + f"<{upper}"
        deps.append(dep)
    print(" ".join(deps))


def verify(directory, version):
    root = pathlib.Path(directory)
    headers = "\n".join(
        path.read_text() for path in root.glob("qtwebengine/*/include/**/*config*.h")
    )
    for feature in ("webengine_vaapi", "webengine_proprietary_codecs"):
        if not re.search(rf"#define QT_FEATURE_{feature}\s+1\b", headers):
            raise ValueError(f"新二进制缺少 {feature}，停止更新")
    private = root / "pkg/usr/lib/qtwebengine-hw"
    core = root / f"pkg/usr/lib/libQt6WebEngineCore.so.{version}"
    needed = subprocess.check_output(
        ["patchelf", "--print-needed", core], text=True
    ).split()
    for library in needed:
        if library.startswith("libxml2.") and not (private / library).exists():
            raise ValueError(f"附带的 libxml2 不提供 {library}")
    # Check versioned libc/C++ symbols too: SONAME compatibility alone is insufficient.
    for pattern, provider in [
        (rb"GLIBC_\d+\.\d+(?:\.\d+)?", "/usr/lib/libc.so.6"),
        (rb"(?:GLIBCXX|CXXABI)_\d+\.\d+(?:\.\d+)?", "/usr/lib/libstdc++.so.6"),
    ]:
        available = set(re.findall(pattern, pathlib.Path(provider).read_bytes()))
        required = set()
        for path in (root / "pkg/usr/lib").rglob("*"):
            if path.is_file() and not path.is_symlink():
                content = path.read_bytes()
                if content.startswith(b"\x7fELF"):
                    required.update(re.findall(pattern, content))
        missing = required - available
        if missing:
            raise ValueError(
                "当前系统缺少二进制要求的符号版本："
                + ", ".join(sorted(x.decode() for x in missing))
            )


if __name__ == "__main__":
    try:
        if sys.argv[1] == "plan":
            plan(sys.argv[2])
        elif sys.argv[1] == "resolve":
            print(json.dumps(resolve(sys.argv[2]), indent=2))
        elif sys.argv[1] == "dependencies":
            dependencies(sys.argv[2], sys.argv[3])
        elif sys.argv[1] == "verify":
            verify(sys.argv[2], sys.argv[3])
        else:
            raise ValueError("未知操作")
    except (ValueError, KeyError, OSError, subprocess.CalledProcessError) as error:
        sys.exit(f"QtWebEngine 准备失败，尚未升级系统：{error}")
