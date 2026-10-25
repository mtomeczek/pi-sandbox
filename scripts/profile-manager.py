#!/usr/bin/env python3
"""Shared, standard-library-only profile preflight, version audit and diagnostics."""
import argparse
import datetime
import json
import os
from pathlib import Path
import re
import shutil
import socket
import subprocess
import sys
import tempfile
import urllib.parse
import urllib.request

TOOLS = {"go", "rust", "jvm", "uv", "fnm", "python", "caddy", "playwright"}
KEYS = {"PROFILE", "BASE_IMAGE", "PI_VERSION", "TOOL", "EXTENSION", "PROJECT_NODE", "NPM", "ENV", "ENV_SECRET", "PATH", "APT", "SHELL_COMMAND"}
VERSION = re.compile(r"^v?\d+(?:\.\d+){0,3}(?:\+\d+)?$")
NAME = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")
PACKAGE = re.compile(r"^(@[A-Za-z0-9][A-Za-z0-9._-]*/)?[A-Za-z0-9][A-Za-z0-9._-]*(?:@(?:[A-Za-z0-9._+~^*-]+|[<>=~^0-9.* |+-]+))?$")
GITHUB = {"caddy": "caddyserver/caddy", "fnm": "Schniz/fnm", "uv": "astral-sh/uv"}


def read_profile(path):
    if path == "-":
        text = sys.stdin.read()
    else:
        try:
            with open(path, encoding="utf-8-sig", newline="") as source:
                text = source.read()
        except (OSError, UnicodeError):
            raise ValueError("cannot read profile file") from None
    entries = []
    for number, raw in enumerate(text.splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if any(ord(c) < 32 and c != "\t" for c in line) or "=" not in line:
            raise ValueError(f"line {number}: invalid control character or missing '='")
        key, value = line.split("=", 1)
        key = key.strip()
        if key not in KEYS:
            raise ValueError(f"line {number}: unsupported directive")
        entries.append((number, key, value.strip()))
    return text, entries


def npm_parts(spec):
    index = spec.rfind("@")
    return (spec[:index], spec[index + 1:]) if index > 0 else (spec, "latest")


def request(url: str, head: bool = False) -> str:
    if urllib.parse.urlsplit(url).scheme != "https":
        raise ValueError("upstream requests require HTTPS")
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "pi-sandbox", "Accept": "application/json"}, method="HEAD" if head else "GET")  # noqa: S310 - HTTPS checked above, URLs come from fixed upstream providers
        with urllib.request.urlopen(req, timeout=30) as response:  # noqa: S310 - HTTPS checked above
            if urllib.parse.urlsplit(response.geturl()).scheme != "https":
                raise ValueError("upstream redirected away from HTTPS")
            return "" if head else str(response.read().decode("utf-8"))
    except Exception:
        raise ValueError("upstream request failed") from None


def fetch(url):
    try:
        return json.loads(request(url))
    except (ValueError, UnicodeError):
        raise ValueError("invalid or unavailable upstream metadata") from None


def numeric(version: str) -> tuple:
    if not VERSION.fullmatch(version):
        return ()
    return tuple(int(x) for x in re.split(r"[.+]", version.lstrip("v")))


def available(kind, value):
    version = value.lstrip("v")
    if kind in GITHUB:
        tag = "v" + version if kind != "uv" else version
        fetch(f"https://api.github.com/repos/{GITHUB[kind]}/releases/tags/{tag}")
    elif kind == "go":
        releases = fetch("https://go.dev/dl/?mode=json&include=all")
        if not any(release["version"] == "go" + version for release in releases):
            raise ValueError("Go release not found")
    elif kind == "rust":
        request(f"https://static.rust-lang.org/dist/channel-rust-{version}.toml", True)
    elif kind == "python":
        request(f"https://www.python.org/ftp/python/{version}/", True)
    elif kind == "jvm":
        query = urllib.parse.urlencode({"version": version, "release_type": "ga"})
        if not fetch("https://api.adoptium.net/v3/info/release_names?" + query).get("releases"):
            raise ValueError("JDK release not found")
    elif kind == "node":
        request(f"https://nodejs.org/dist/v{version}/SHASUMS256.txt", True)
    else:
        package = urllib.parse.quote(kind, safe="")
        release = urllib.parse.quote(value, safe="")
        fetch(f"https://registry.npmjs.org/{package}/{release}")


def validate(entries, online=False):
    tools = {}
    singleton = set()
    versions = []
    for number, key, value in entries:
        if not value and key != "ENV":
            raise ValueError(f"line {number}: empty {key}")
        if key in {"PROFILE", "PI_VERSION", "BASE_IMAGE"}:
            if key in singleton:
                raise ValueError(f"duplicate {key}")
            singleton.add(key)
        if key == "PROFILE" and not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]*", value):
            raise ValueError("invalid PROFILE")
        if key == "TOOL":
            tool, separator, version = value.partition("@")
            if tool not in TOOLS or not separator or not VERSION.fullmatch(version):
                raise ValueError(f"line {number}: expected supported TOOL@numeric-version")
            if version.startswith("v") and tool not in {"fnm", "caddy"}:
                raise ValueError("only fnm/Caddy tool versions accept a leading v")
            if tool in tools:
                raise ValueError(f"duplicate tool {tool}")
            tools[tool] = version
            versions.append(("playwright" if tool == "playwright" else tool, version))
        elif key == "PI_VERSION":
            if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._+-]*", value):
                raise ValueError("invalid PI_VERSION")
            versions.append(("@earendil-works/pi-coding-agent", value))
        elif key == "BASE_IMAGE" and not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._/:@+-]*", value):
            raise ValueError("invalid BASE_IMAGE")
        elif key == "NPM":
            if not PACKAGE.fullmatch(value):
                raise ValueError(f"line {number}: invalid npm specification")
            versions.append(npm_parts(value))
        elif key in {"ENV", "ENV_SECRET"}:
            name, separator, content = value.partition("=")
            if not separator or not NAME.fullmatch(name):
                raise ValueError(f"line {number}: invalid {key} name/value")
            if key == "ENV_SECRET" and not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]*", content):
                raise ValueError("invalid Podman secret reference")
            if key == "ENV" and any(c in content for c in ('"', "\\", "`", "$")):
                raise ValueError("ENV build values must not contain shell/Containerfile expansion characters")
        elif key == "APT" and not re.fullmatch(r"[a-z0-9][a-z0-9+.:=-]*", value):
            raise ValueError("invalid APT package")
        elif key == "PATH" and not re.fullmatch(r"[A-Za-z0-9_/.:${}-]+", value):
            raise ValueError("invalid PATH entry")
        elif key == "SHELL_COMMAND" and (not value.strip() or value.rstrip().endswith("\\")):
            raise ValueError("SHELL_COMMAND must be one complete non-empty line")
    if "python" in tools and "uv" not in tools:
        raise ValueError("python requires a uv tool in the same profile")
    for number, key, value in entries:
        if key == "EXTENSION":
            kind, separator, spec = value.partition(":")
            if not separator or kind not in {"uv", "cargo", "rustup", "fnm"} or not spec:
                raise ValueError(f"line {number}: invalid extension")
            if not re.fullmatch(r"[A-Za-z0-9@._+:/-]+", spec):
                raise ValueError(f"line {number}: unsafe extension specification")
            if kind in {"uv", "fnm"} and kind not in tools:
                raise ValueError(f"{kind} extension requires its tool")
            if kind in {"cargo", "rustup"} and "rust" not in tools:
                raise ValueError(f"{kind} extension requires rust")
            if kind == "fnm":
                if not spec.startswith("node@") or not VERSION.fullmatch(spec[5:]):
                    raise ValueError("fnm extension must be node@VERSION")
                if len(spec[5:].split(".")) == 3:
                    versions.append(("node", spec[5:]))
        elif key == "PROJECT_NODE":
            if "fnm" not in tools or not VERSION.fullmatch(value):
                raise ValueError("PROJECT_NODE requires fnm and a numeric Node version")
    if online:
        for kind, version in versions:
            if numeric(version) or version in {"latest", "stable"}:
                try:
                    available(kind, version)
                except Exception:
                    raise ValueError(f"upstream verification failed for {kind}@{version}") from None
    return tools


def candidates(kind, current):
    if kind in GITHUB:
        releases = fetch(f"https://api.github.com/repos/{GITHUB[kind]}/releases?per_page=100")
        return [r["tag_name"].lstrip("v") for r in releases if not r["draft"] and not r["prerelease"]]
    if kind == "go":
        return [r["version"][2:] for r in fetch("https://go.dev/dl/?mode=json&include=all") if r["stable"]]
    if kind == "node":
        return [r["version"].lstrip("v") for r in fetch("https://nodejs.org/dist/index.json")]
    if kind == "rust":
        text = request("https://static.rust-lang.org/dist/channel-rust-stable.toml")
        match = re.search(r'\[pkg.rust\]\s*version = "([^ "\n]+)', text)
        if not match:
            raise ValueError("Rust stable version unavailable")
        return [match.group(1)]
    if kind == "python":
        today = datetime.date.today().isoformat()
        return [r["latest"] for r in fetch("https://endoflife.date/api/python.json") if r["releaseDate"] <= today]
    if kind == "jvm":
        major = numeric(current)[0]
        query = urllib.parse.urlencode({"version": f"[{major},{major + 1})", "release_type": "ga", "page_size": 100})
        return [name.removeprefix("jdk-") for name in fetch("https://api.adoptium.net/v3/info/release_names?" + query)["releases"]]
    metadata = fetch("https://registry.npmjs.org/" + urllib.parse.quote(kind, safe=""))
    return list(metadata["versions"])


def audit(entries, patch_only=False):
    changes = []
    for number, key, value in entries:
        if key == "PI_VERSION":
            kind, old = "@earendil-works/pi-coding-agent", value
        elif key == "TOOL":
            kind, old = value.split("@", 1)
        elif key == "NPM":
            kind, old = npm_parts(value)
        elif key == "PROJECT_NODE":
            kind, old = "node", value
        elif key == "EXTENSION" and value.startswith("fnm:node@"):
            kind, old = "node", value[9:]
        else:
            continue
        parts = numeric(old)
        if not parts or len(parts) < 3:
            print(f"{kind}: floating/range version retained")
            continue
        try:
            matching = [v for v in candidates(kind, old) if numeric(v) and numeric(v)[:2 if patch_only else 1] == parts[:2 if patch_only else 1]]
        except Exception:
            raise ValueError(f"could not check upstream versions for {kind}; no changes written") from None
        newest = max(matching, key=numeric) if matching else old
        if numeric(newest) > parts:
            changes.append((number, kind, old, newest, key, value))
            print(f"{kind}: {old} -> {newest}")
        else:
            print(f"{kind}: {old} (current in selected compatibility range)")
    return changes


def upgrade(path, text, changes, yes=False, dry_run=False):
    if not changes:
        return
    if dry_run:
        print("Dry run: profile would be backed up and updated; no files changed.")
        return
    if not yes and (not sys.stdin.isatty() or input("Back up and update this profile? [y/N] ").lower() not in {"y", "yes"}):
        raise ValueError("upgrade cancelled; rerun with --yes to approve")
    profile = Path(path)
    if profile.is_symlink():
        raise ValueError("refusing to replace a symlinked profile")
    # Refuse concurrent edits rather than overwriting them.
    with profile.open(encoding="utf-8-sig", newline="") as source:
        if source.read() != text:
            raise ValueError("profile changed while checking versions; retry")
    lines = text.splitlines(keepends=True)
    for number, _kind, old, new, key, value in changes:
        replacement = new if key in {"PI_VERSION", "PROJECT_NODE"} else value[:-len(old)] + new
        ending = "\r\n" if lines[number - 1].endswith("\r\n") else "\n" if lines[number - 1].endswith("\n") else ""
        lines[number - 1] = key + "=" + replacement + ending
    updated = "".join(lines)
    _, entries = parse_text(updated)
    validate(entries)
    backup = str(profile) + ".bak-" + datetime.datetime.now().strftime("%Y%m%d-%H%M%S-%f")
    shutil.copy2(profile, backup)
    fd, temporary = tempfile.mkstemp(prefix=".upgrade-", dir=profile.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="") as out:
            out.write(updated)
        os.chmod(temporary, profile.stat().st_mode & 0o777)
        os.replace(temporary, profile)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)
    print("Profile updated; backup created. Regenerate the Containerfile and rebuild explicitly.")


def parse_text(text):
    # Reuse the same parser without touching a caller's stdin.
    import io
    previous = sys.stdin
    try:
        sys.stdin = io.StringIO(text)
        return read_profile("-")
    finally:
        sys.stdin = previous


def doctor(args):
    failed = False
    podman = shutil.which("podman")
    def check(label, command):
        nonlocal failed
        command = [podman or "podman", *command[1:]]
        try:
            result = subprocess.run(command, capture_output=True, text=True, timeout=30)
        except (OSError, subprocess.TimeoutExpired):
            print("FAIL: " + label + " (unavailable or timed out)")
            failed = True
            return None
        ok = result.returncode == 0
        print(("OK: " if ok else "FAIL: ") + label)
        failed |= not ok
        return result if ok else None
    if not podman:
        raise ValueError("Podman is not installed")
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_./:@+-]*", args.image):
        raise ValueError("invalid doctor image reference")
    info = check("Podman connection", ["podman", "info", "--format", "json"])
    if not info:
        return 1
    try:
        details = json.loads(info.stdout)
        rootless = details.get("host", {}).get("security", {}).get("rootless")
        if rootless is False:
            print("FAIL: Podman is not rootless")
            failed = True
        elif rootless is True:
            print("OK: rootless Podman")
        else:
            print("WARN: rootless status unavailable")
    except (ValueError, AttributeError):
        print("WARN: Podman info metadata unavailable")
    image = check("image exists (missing: ask creator to --regenerate-containerfile --update)", ["podman", "image", "exists", args.image])
    if image:
        metadata = check("image metadata", ["podman", "image", "inspect", args.image])
        try:
            labels = json.loads(metadata.stdout)[0].get("Config", {}).get("Labels", {}) if metadata else {}
            if labels.get("io.pi-sandbox.template-version") != "2":
                print("WARN: old/unlabelled image; regenerate Containerfile and rebuild for verified CLI capabilities")
            elif "glab-device" not in labels.get("io.pi-sandbox.capabilities", ""):
                print("WARN: device-login capability not recorded; regenerate Containerfile and rebuild")
            else:
                print("OK: image records build-verified glab device login")
        except (ValueError, TypeError, IndexError, AttributeError):
            print("WARN: image capability metadata unavailable")
    for name in args.secret:
        if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]*", name):
            raise ValueError("invalid doctor secret reference")
        check(f"referenced Podman secret exists: {name}", ["podman", "secret", "inspect", name])
    for spec in args.port:
        if not re.fullmatch(r"[0-9]{1,5}:[0-9]{1,5}(?:/(?:tcp|udp))?", spec):
            raise ValueError("invalid doctor port specification")
        protocol = socket.SOCK_DGRAM if spec.endswith("/udp") else socket.SOCK_STREAM
        port = int(spec.split(":", 1)[0])
        if not 1 <= port <= 65535:
            raise ValueError("doctor port is outside 1..65535")
        try:
            with socket.socket(socket.AF_INET, protocol) as sock:
                sock.bind(("127.0.0.1", port))
            print(f"OK: local port {port} available")
        except OSError:
            failed = True
            print(f"FAIL: local port {port} is occupied or unavailable")
    print("NOTE: remote Podman hosts may have different port availability. No containers or volumes were created.")
    return 1 if failed else 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["validate", "audit", "upgrade", "doctor"])
    parser.add_argument("--file", default="-")
    parser.add_argument("--online", action="store_true")
    parser.add_argument("--patch-only", action="store_true")
    parser.add_argument("--yes", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--image", default="pi-sandbox:latest")
    parser.add_argument("--secret", action="append", default=[])
    parser.add_argument("--port", action="append", default=[])
    args = parser.parse_args()
    if args.action == "doctor":
        return doctor(args)
    text, entries = read_profile(args.file)
    validate(entries, args.online)
    if args.action == "validate":
        print("Profile validation passed" + (" (including upstream checks)" if args.online else " (offline)"))
    else:
        changes = audit(entries, args.patch_only)
        if args.action == "upgrade":
            if args.file == "-":
                raise ValueError("upgrade requires a profile file")
            upgrade(args.file, text, changes, args.yes, args.dry_run)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exc:
        # Never include raw profiles, environment values, or HTTP response bodies.
        if isinstance(exc, ValueError):
            print("Error: " + str(exc), file=sys.stderr)
        else:
            print(f"Error: profile operation failed ({type(exc).__name__}); no credentials displayed", file=sys.stderr)
        sys.exit(2)
