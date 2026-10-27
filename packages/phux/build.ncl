# phux — terminal multiplexer and agent server built on libghostty-vt.
#
# BUILT FROM SOURCE, like herdr (the closest neighbour: also Rust over a
# Zig-built libghostty-vt). Upstream also publishes signed glibc release
# archives; AGENTS.md rules those out while rust and zig are packaged.
#
# libghostty-vt comes in through the `libghostty-vt-sys` git dependency
# (phall1/libghostty-rs, pinned by rev in Cargo.lock). Left alone, its build
# script first tries to download a PREBUILT libghostty-vt archive, then falls
# back to `git clone` of Ghostty. build.sh sets GHOSTTY_SOURCE_DIR to the pinned
# Ghostty tarball below, which skips both and builds it with our zig 0.16.0
# (the exact version Ghostty's build.zig.zon requires).
#
# `needs` internet: cargo fetches the crates and the libghostty-rs git rev
# pinned in Cargo.lock (`cargo fetch --locked`), and `zig build` fetches the
# Ghostty Zig packages pinned by content hash in its build.zig.zon (uucode,
# translate_c, aro, highway, ...), as zls does.
#
# Embedded trust store: phux's push-notice client (phux-server) and quictun
# forwards verify against webpki-roots' compiled-in Mozilla roots; upstream has
# no switch to the system store yet. build.sh fails closed unless Cargo.lock
# carries the CVE-2026-111943 floor (rustls-webpki 0.103.16, webpki-roots
# 1.0.10), as zellij and codex do.
let { standaloneTest, subsetOf, Attrs, BuildSpec, Local, Needs, OutputBin, Source, .. } = import "minimal.ncl" in
let base = import "../base/build.ncl" in
let git = import "../git/build.ncl" in
let rust = import "../rust/build.ncl" in
let toolchain = import "../toolchain/build.ncl" in
let zig = import "../zig/build.ncl" in

let gcc = import "../gcc/build.ncl" in
let glibc = import "../glibc/build.ncl" in

let version = "0.113.1" in
# Must equal GHOSTTY_COMMIT in libghostty-vt-sys at the rev Cargo.lock pins;
# build.sh fails the build if they drift apart on a version bump.
let ghostty_commit = "3ba2c3d68300d2914c85087e0f71466a43d46d05" in
{
  name = "phux",
  build_deps = [
    { file = "build.sh" } | Local,
    {
      url = "https://github.com/no-phux/phux/archive/refs/tags/v%{version}.tar.gz",
      sha256 = "03a6e2c44e01e8d054ba2cc20627b6495e21a6fc03229e28799e9bf2b4565907",
      extract = true,
      strip_prefix = "phux-%{version}",
    } | Source,
    # Ghostty (phall1 fork) at the commit libghostty-vt-sys pins. Extracted
    # without strip_prefix, so it lands in ./ghostty-<commit>/.
    {
      url = "https://github.com/phall1/ghostty/archive/%{ghostty_commit}.tar.gz",
      sha256 = "ee2dc89020060b2d2973a37b9971bbc92a7f161e0738dc842eaa6bd68c0baae4",
      extract = true,
    } | Source,
    base,
    # .cargo/config.toml sets net.git-fetch-with-cli, so cargo fetches the
    # libghostty-rs git dependency with the git CLI.
    git,
    rust,
    toolchain,
    zig,
  ],

  runtime_deps = [glibc, subsetOf gcc ["libgcc"]],

  needs =
    {
      dns = {},
      internet = {},
    } | Needs,

  cmd = "./build.sh",
  build_args = {
    include version,
    include ghostty_commit,
  },

  outputs = {
    phux = { glob = "usr/bin/phux" } | OutputBin,
    phux-mcp = { glob = "usr/bin/phux-mcp" } | OutputBin,
  },

  attrs =
    {
      upstream_version = version,
      license_spdx = "Apache-2.0",
      source_provenance = {
        category = 'GithubRepo,
        owner = "no-phux",
        repo = "phux",
      },
      # Fat LTO with one codegen unit (upstream's release profile) plus a
      # full Zig build of libghostty-vt.
      build_cost_multiple = 4,
    } | Attrs,

  tests = {
    smoketest = standaloneTest "/usr/bin/phux --version",
    mcp_smoketest = standaloneTest "/usr/bin/phux-mcp --version",
  },
} | BuildSpec
