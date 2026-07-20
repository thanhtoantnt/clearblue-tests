#!/usr/bin/env python3
"""Generate bc/<project>/README.md from committed bitcode + /tmp/prinfo_*.json.
Run from the repo root after fetching PR info (see fetch_prinfo in the docs)."""
import json, subprocess, sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
BC = REPO / "bc"

# baseline commit + build artifact per project
META = {
    "curl":    {"base": "bc440a89d4", "repo": "curl/curl", "upstream": "https://github.com/curl/curl",
                "artifact": "libcurl-d.so.4.8.0 (libcurl, shared, no OpenSSL/LDAP/libpsl)",
                "build": "cmake -G Ninja -DCMAKE_C_COMPILER=gclang -DCMAKE_C_FLAGS='-O0 -g -fPIC -Xclang -no-opaque-pointers' -DCMAKE_BUILD_TYPE=Debug -DBUILD_SHARED_LIBS=ON -DCURL_USE_OPENSSL=OFF -DCURL_DISABLE_LDAP=ON -DCURL_USE_LIBPSL=OFF",
                "out_kind": "libcurl (debug shared lib)"},
    "git":     {"base": "55526a1826", "repo": "git/git", "upstream": "https://github.com/git/git",
                "artifact": "git (the single monolithic binary)",
                "build": "make CC=gclang CFLAGS='-O0 -g -fPIC -Xclang -no-opaque-pointers' NO_OPENSSL=1 NO_CURL=1 NO_EXPAT=1 NO_GETTEXT=1 git",
                "out_kind": "git binary (~977k inst)"},
    "libuv":   {"base": "2cadaa40", "repo": "libuv/libuv", "upstream": "https://github.com/libuv/libuv",
                "artifact": "libuv.so.1.0.0 (shared lib)",
                "build": "cmake -G Ninja -DCMAKE_C_COMPILER=gclang -DCMAKE_C_FLAGS='-O0 -g -fPIC -Xclang -no-opaque-pointers' -DCMAKE_BUILD_TYPE=Debug -DBUILD_TESTING=OFF",
                "out_kind": "libuv (~50k inst)"},
    "darknet": {"base": "f6afaabc", "repo": "pjreddie/darknet", "upstream": "https://github.com/pjreddie/darknet",
                "artifact": "darknet binary",
                "build": "make CC=gclang CPP=gclang++ DEBUG=1 GPU=0 CFLAGS='-Wall -Wno-unused-result -Wno-unknown-pragmas -Wfatal-errors -fPIC -O0 -g -Xclang -no-opaque-pointers'",
                "out_kind": "darknet (~122k inst)"},
    "redis":   {"base": "1aa21f97d", "repo": "redis/redis", "upstream": "https://github.com/redis/redis",
                "artifact": "src/redis-server",
                "build": "make CC=gclang OPTIMIZATION=-O0 CFLAGS='-O0 -g -fPIC -Xclang -no-opaque-pointers -fno-lto -Wno-error -std=gnu11' LDFLAGS=-fno-lto MALLOC=libc BUILD_TLS=no",
                "out_kind": "redis-server (~540k inst)"},
    "openssl": {"base": "380d6afcb3", "repo": "openssl/openssl", "upstream": "https://github.com/openssl/openssl",
                "artifact": "libcrypto.so.3 (libcrypto only)",
                "build": "./config CC=gclang CFLAGS='-O0 -g -fPIC -Xclang -no-opaque-pointers' no-asm shared -d ; make build_libs",
                "out_kind": "libcrypto (~900k inst)"},
}

def du(f):
    try: return subprocess.check_output(["du","-h",str(f)]).split()[0].decode()
    except Exception: return "?"

def main():
    for proj in META:
        d = BC / proj
        if not d.is_dir(): continue
        info = json.loads((Path(f"/tmp/prinfo_{proj}.json")).read_text()) if (Path(f"/tmp/prinfo_{proj}.json")).exists() else {}
        prs = sorted([p.stem.replace("pr-","") for p in d.glob("pr-*.bc")],
                     key=lambda x: (0,int(x)) if x.lstrip("-").isdigit() else (1,x))
        m = META[proj]
        lines = []
        lines.append(f"# `bc/{proj}/` — {proj} bitcode for cb-check incremental-persist\n")
        lines.append(f"This folder holds typed-pointer LLVM 15 bitcode for **{proj}**, used as the "
                     "input for the `cb-check` incremental-persist benchmark "
                     "(`scripts/run_bench.sh`).\n")
        lines.append("## Layout\n")
        lines.append("- **`old.bc`** — the stored baseline. Produced from the upstream source at "
                     f"commit [`{m['base']}`]({m['upstream']}/commit/{m['base']}). "
                     "`run_bench.sh` stores SEGs from this once; everything else is benchmarked "
                     "against it.\n")
        lines.append("- **`pr-<NNNN>.bc`** — one bitcode per pull request. Each was produced by "
                     "applying that PR's source onto the baseline commit and recompiling with the "
                     "**identical** flags used for `old.bc`. "
                     "(Names with `pr-syn<N>.bc` are synthetic no-op edits, not real PRs.)\n")
        lines.append("## Build configuration\n")
        lines.append(f"| | |\n|---|---|\n"
                     f"| Upstream | `{m['repo']}` (<{m['upstream']}>)\n"
                     f"| Baseline commit | `{m['base']}`\n"
                     f"| Artifact extracted | `{m['artifact']}`\n"
                     f"| Toolchain | gllvm `gclang` + `get-bc`, LLVM 15, `-Xclang -no-opaque-pointers`\n"
                     f"| Result size | `{m['out_kind']}`\n")
        lines.append("```bash\n# how each .bc was built (same for old.bc and every pr-*.bc)\n"
                     f"{m['build']}\nget-bc -o <file>.bc <artifact>\n```\n")
        lines.append("See [`docs/producing-bitcode.md`](../../docs/producing-bitcode.md) for the "
                     "full recipe.\n")
        # Reproduce section — explicit cb-check commands
        lines.append("## Reproduce the results\n")
        lines.append("Three explicit `cb-check` invocations reproduce one data point: "
                     "**store** the baseline once, then run a sample **incremental** "
                     "(reuses stored SEGs) and **scratch** (no store) to compare.\n")
        lines.append("```bash\nCBC=$HOME/github/FermatAnalyzer/build/tools/cb-check/cb-check\n\n"
                     "# 1) store the baseline once (writes ./persist/{proj}/seg/ ...)\n"
                     "$CBC --hide-progress-bar -nworkers=16 -enable-build-seg-only \\\n"
                     "     -persist-dir=./persist/{proj} bc/{proj}/old.bc\n\n"
                     "# 2) incremental on a PR's bitcode (loads clean SEGs, rebuilds dirty)\n"
                     "$CBC --hide-progress-bar -nworkers=16 -enable-build-seg-only \\\n"
                     "     -enable-incremental-persist -persist-dir=./persist/{proj} bc/{proj}/pr-NNNN.bc\n\n"
                     "# 3) scratch on the same bitcode (no store; full rebuild)\n"
                     "$CBC --hide-progress-bar -nworkers=16 -enable-build-seg-only bc/{proj}/pr-NNNN.bc\n"
                     "```\n".format(proj=proj))
        lines.append("Run steps 2–3 for each `pr-*.bc` in this folder. Compare the "
                     "`SEG-Building spends time ***...***` line and the "
                     "`[Incremental persist] body-dirty: N, +callers: M` line. "
                     "Incremental wins when `inc` wall-time < `scratch` wall-time.\n")
        lines.append("Result columns and log fields are explained in "
                     "[`../../docs/cb-check-incremental-persist.md`](../../docs/cb-check-incremental-persist.md) "
                     "and [`../../README.md`](../../README.md#result-columns).\n")
        lines.append(f"## Files in this folder ({len(prs) + (1 if (d/'old.bc').exists() else 0)} total)\n")
        lines.append("| File | PR / source | Title | Changed C/C++ files |\n|------|-------------|-------|---------------------|\n")
        lines.append(f"| `old.bc` ({du(d/'old.bc')}) | baseline `{m['base']}` | — | — |\n")
        for pr in prs:
            f = d / f"pr-{pr}.bc"
            if pr.startswith("syn"):
                lines.append(f"| `pr-{pr}.bc` ({du(f)}) | synthetic touch #{pr[3:]} | *(no-op source edit)* | *(one .c file)* |\n")
            else:
                t = info.get(pr, {})
                title = (t.get("title") or "?").replace("|","\\|")[:70]
                files = (t.get("files") or "?").replace("|","\\|")[:60]
                link = f"[#{pr}]({m['upstream']}/pull/{pr})"
                lines.append(f"| `pr-{pr}.bc` ({du(f)}) | {link} | {title} | {files} |\n")
        (d / "README.md").write_text("".join(lines))
        print(f"wrote {d/'README.md'}: old.bc + {len(prs)} pr-*.bc")

if __name__ == "__main__":
    main()
