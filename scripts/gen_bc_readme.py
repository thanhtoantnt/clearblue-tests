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
    "c-ares": {"base": "589b5887", "repo": "c-ares/c-ares", "upstream": "https://github.com/c-ares/c-ares",
                "artifact": "libcares.so.2.19.4 (shared lib)",
                "build": "cmake -G Ninja -DCMAKE_C_COMPILER=gclang -DCMAKE_C_FLAGS='-O0 -g -fPIC -Xclang -no-opaque-pointers' -DCMAKE_BUILD_TYPE=Debug -DCARES_SHARED=ON -DCARES_STATIC=OFF",
                "out_kind": "libcares (~40k inst)"},
    "libevent": {"base": "e1f0335d", "repo": "libevent/libevent", "upstream": "https://github.com/libevent/libevent",
                "artifact": "libevent_core-2.2.so.1.0.1 (shared lib)",
                "build": "cmake -G Ninja -DCMAKE_C_COMPILER=gclang -DCMAKE_C_FLAGS='-O0 -g -fPIC -Xclang -no-opaque-pointers' -DCMAKE_BUILD_TYPE=Debug -DEVENT__LIBRARY_TYPE=SHARED -DEVENT__DISABLE_OPENSSL=ON -DEVENT__DISABLE_MBEDTLS=ON -DEVENT__DISABLE_TESTS=ON -DEVENT__DISABLE_SAMPLES=ON",
                "out_kind": "libevent_core (~30k inst)"},
    "mbedtls": {"base": "12556bc2a2", "repo": "Mbed-TLS/mbedtls", "upstream": "https://github.com/Mbed-TLS/mbedtls",
                "artifact": "libmbedtls.so.4.2.0 (shared lib)",
                "setup": "git submodule update --init --recursive && pip install jsonschema jinja2",
                "build": "cmake -G Ninja -DCMAKE_C_COMPILER=gclang -DCMAKE_C_FLAGS='-O0 -g -fPIC -Xclang -no-opaque-pointers' -DCMAKE_BUILD_TYPE=Debug -DENABLE_PROGRAMS=OFF -DENABLE_TESTING=OFF -DUSE_SHARED_MBEDTLS_LIBRARY=ON",
                "out_kind": "libmbedtls (~25k inst)"},
    "openssh": {"base": "cadefc724", "repo": "openssh/openssh-portable", "upstream": "https://github.com/openssh/openssh-portable",
                "artifact": "sshd (server binary)",
                "build": "autoreconf -fi ; ./configure CC=gclang CFLAGS='-O0 -g -fPIC -Xclang -no-opaque-pointers' ; make sshd",
                "out_kind": "sshd (~75k inst)"},
    "zstd": {"base": "5c7b7bad", "repo": "facebook/zstd", "upstream": "https://github.com/facebook/zstd",
                "artifact": "libzstd.so.1.6.0 (multithreaded shared lib)",
                "build": "make -C lib lib-mt CC=gclang CFLAGS='-O0 -g -fPIC -Xclang -no-opaque-pointers'",
                "out_kind": "libzstd (mt, ~300k inst)"},
    "wolfssl": {"base": "5dd7717d1", "repo": "wolfSSL/wolfssl", "upstream": "https://github.com/wolfSSL/wolfssl",
                "artifact": "libwolfssl.so.45.0.0 (shared lib)",
                "build": "cmake -G Ninja -DCMAKE_C_COMPILER=gclang -DCMAKE_C_FLAGS='-O0 -g -fPIC -Xclang -no-opaque-pointers' -DCMAKE_BUILD_TYPE=Debug -DWOLFSSL_SHARED=ON -DBUILD_SHARED_LIBS=ON -DWOLFSSL_EXAMPLES=OFF -DWOLFSSL_CRYPT_TESTS=OFF",
                "out_kind": "libwolfssl (~160k inst)"},
    "memcached": {"base": "2d51e36", "repo": "memcached/memcached", "upstream": "https://github.com/memcached/memcached",
                "artifact": "memcached (server binary)",
                "setup": "# needs libevent: build it (see bc/libevent) then cmake --install <dir> --prefix /tmp/lev\n./autogen.sh && autoreconf -fi && automake --add-missing --copy",
                "build": "./configure CC=gclang CFLAGS='-O0 -g -fPIC -Xclang -no-opaque-pointers' --with-libevent=/tmp/lev LDFLAGS='-L/tmp/lev/lib -Wl,-rpath,/tmp/lev/lib' CPPFLAGS='-I/tmp/lev/include' ; make",
                "out_kind": "memcached (~15k inst)"},
    "nghttp2": {"base": "d5ab3d92", "repo": "nghttp2/nghttp2", "upstream": "https://github.com/nghttp2/nghttp2",
                "artifact": "libnghttp2.so.14.29.4 (shared lib)",
                "setup": "git submodule update --init --recursive",
                "build": "cmake -G Ninja -DCMAKE_C_COMPILER=gclang -DCMAKE_C_FLAGS='-O0 -g -fPIC -Xclang -no-opaque-pointers' -DCMAKE_BUILD_TYPE=Debug -DBUILD_STATIC_LIBS=OFF -DENABLE_APP=OFF -DENABLE_HPACK_TOOLS=OFF -DENABLE_EXAMPLES=OFF",
                "out_kind": "libnghttp2 (~small HTTP/2 lib)"},
    "libssh2": {"base": "fe667c60", "repo": "libssh2/libssh2", "upstream": "https://github.com/libssh2/libssh2",
                "artifact": "libssh2.so.1.0.1 (shared lib, OpenSSL backend)",
                "build": "cmake -G Ninja -DCMAKE_C_COMPILER=gclang -DCMAKE_C_FLAGS='-O0 -g -fPIC -Xclang -no-opaque-pointers' -DCMAKE_BUILD_TYPE=Debug -DBUILD_SHARED_LIBS=ON -DBUILD_EXAMPLES=OFF -DBUILD_TESTING=OFF -DENABLE_ZLIB_COMPRESSION=OFF",
                "out_kind": "libssh2 (SSH client lib, ~moderate size)"},
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
        # (build command shown in full in the 'Reproduce the .bc files' section below)
        lines.append("## Reproduce the .bc files from source\n")
        lines.append("The committed `.bc` files are self-contained, but you can rebuild any of them "
                     "from the upstream source. The key rule: **`old.bc` and every `pr-*.bc` must "
                     "use the identical toolchain and flags** so `cb-check` fingerprints match.\n")
        lines.append("### Prerequisites (once)\n")
        lines.append("```bash\n"
                     "# gllvm wraps clang to embed bitcode -- https://github.com/SRI-CSL/gllvm\n"
                     "go install github.com/SRI-CSL/gllvm/cmd/gclang@latest\n"
                     "go install github.com/SRI-CSL/gllvm/cmd/get-bc@latest\n"
                     "# point gllvm at LLVM 15 (typed pointers), then put it on PATH\n"
                     "export LLVM_COMPILER_PATH=$HOME/tools/llvm15-official/bin\n"
                     "export PATH=$HOME/go/bin:$LLVM_COMPILER_PATH:$PATH\n"
                     "which gclang get-bc   # sanity check\n"
                     "```\n")
        lines.append(f"### 1. Build `old.bc` (the baseline)\n")
        lines.append(f"```bash\n"
                     f"git clone {m['upstream']}.git {proj}\n"
                     f"cd {proj}\n"
                     f"git checkout {m['base']}\n\n"
                     + (f"# project-specific setup\n{m['setup']}\n\n" if m.get('setup') else "")
                     + f"# build + extract bitcode (artifact: {m['artifact']})\n"
                     f"{m['build']}\n"
                     f"get-bc -o old.bc\n"
                     f"```\n")
        lines.append("### 2. Build `pr-NNNN.bc` (one per pull request)\n")
        lines.append("Reset to the baseline, apply the PR's source, rebuild with the **same** "
                     "command, and save under a new name:\n")
        lines.append(f"```bash\n"
                     f"git reset --hard {m['base']}\n"
                     "# fetch the PR ref and copy its changed .c/.h onto the tree\n"
                     "git fetch origin pull/NNNN/head:pr-NNNN\n"
                     "mb=$(git merge-base HEAD pr-NNNN)\n"
                     "git diff --name-only $mb pr-NNNN | grep -E '\\.(c|h)$' | \\\n"
                     "  while read f; do git show pr-NNNN:$f > $f; done\n"
                     "git branch -D pr-NNNN\n\n"
                     f"# rebuild with the SAME command as step 1\n"
                     f"{m['build']}\n"
                     f"get-bc -o pr-NNNN.bc\n"
                     f"```\n")
        lines.append("> `scripts/build_pr_bc.sh` automates steps 1-2 for every PR recorded in "
                     "`results/<proj>/summary.tsv`; run it from the repo root: "
                     "`./scripts/build_pr_bc.sh " + proj + "`.\n")
        lines.append("See [`docs/producing-bitcode.md`](../../docs/producing-bitcode.md) for the "
                     "full recipe.\n")
        # cb-check analysis section
        lines.append("## Reproduce the results (cb-check analysis)\n")
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
