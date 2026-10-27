#!/bin/bash
set -euo pipefail

src=$(pwd)
GHOSTTY_DIR="$src/ghostty-${MINIMAL_ARG_GHOSTTY_COMMIT}"
test -f "$GHOSTTY_DIR/build.zig"

export CC=gcc
export LD=gcc
# Setting RUSTFLAGS also replaces upstream's .cargo/config.toml target
# rustflags, which ask for mold (not a dependency here).
export RUSTFLAGS="-C linker=gcc --remap-path-prefix=$src=/builddir --remap-path-prefix=$HOME/.cargo=/cargo"
export CARGO_INCREMENTAL=0

# Security floor (CVE-2026-111943): phux embeds webpki-roots (see build.ncl).
# Fail closed if a pre-fix rustls-webpki 0.103.x or webpki-roots /
# webpki-root-certs 1.0.x is locked.
grep -A1 '^name = "rustls-webpki"$' Cargo.lock | grep -q '^version = "0.103.16"$' || {
  echo "ERROR: rustls-webpki 0.103.16 is not in Cargo.lock (CVE-2026-111943)" >&2
  exit 1
}
if grep -A1 -E '^name = "(rustls-webpki|webpki-roots|webpki-root-certs)"$' Cargo.lock |
  grep -qE '^version = "(0[.]103[.]([0-9]|1[0-5])|1[.]0[.][0-9])"$'; then
  echo "ERROR: a pre-CVE-2026-111943 rustls-webpki / webpki-roots is still in Cargo.lock" >&2
  exit 1
fi

# Crates and the libghostty-rs git rev, checked against Cargo.lock.
cargo fetch --locked

# The Ghostty source we hand libghostty-vt-sys must be the commit it pins.
sys_build_rs=$(find "${CARGO_HOME:-$HOME/.cargo}/git/checkouts" -path '*/crates/libghostty-vt-sys/build.rs' | head -n1)
grep -q "^const GHOSTTY_COMMIT: &str = \"${MINIMAL_ARG_GHOSTTY_COMMIT}\";" "$sys_build_rs" || {
  echo "ERROR: libghostty-vt-sys pins a different Ghostty commit than build.ncl:" >&2
  grep '^const GHOSTTY_COMMIT' "$sys_build_rs" >&2 || true
  exit 1
}

# Build libghostty-vt from the pinned tarball with the packaged zig. This skips
# the crate's prebuilt-archive download and its git clone. Zig's caches stay in
# the build tree; CPU baseline matches upstream's release build.
export GHOSTTY_SOURCE_DIR="$GHOSTTY_DIR"
export LIBGHOSTTY_VT_SYS_CPU=baseline
export LIBGHOSTTY_VT_SYS_OPTIMIZE=ReleaseFast
export ZIG_GLOBAL_CACHE_DIR="$src/.zig-global-cache"
export ZIG_LOCAL_CACHE_DIR="$src/.zig-local-cache"

# Stamp a distributed release build, as upstream's release script does.
export PHUX_RELEASE_ARTIFACT=1

cargo build --frozen --release --bin phux --bin phux-mcp

mkdir -p "$OUTPUT_DIR/usr/bin"
install -m 755 target/release/phux "$OUTPUT_DIR/usr/bin/phux"
install -m 755 target/release/phux-mcp "$OUTPUT_DIR/usr/bin/phux-mcp"
