# Neurai (XNA) node — KawPoW, RVN-based, compiled from source for aarch64.
# bullseye builder (gcc-10/glibc2.31) for boost1.7x+bdb4.8; trixie-slim runtime.
#
# KEEP bullseye. It is not laziness and it is not drift: gcc-10 is what boost 1.71 and
# bdb 4.8 compile under. On gcc-12 (bookworm) the depends build dies in
# boost/thread/pthread/thread_data.hpp — "missing binary operator before token (" —
# because newer glibc stopped making PTHREAD_STACK_MIN a compile-time constant, which
# breaks boost's `#if PTHREAD_STACK_MIN > 0`. Moving the base forward means bumping boost,
# which is a different and much larger change than a node version bump.
FROM debian:bullseye AS builder
# Debian 11 reached EOL on 2026-08-14. deb.debian.org no longer carries a consistent
# bullseye-security, so apt resolves package versions the mirror has already removed and
# `apt-get install` 404s on individual files — while `apt-get update` itself succeeds, which
# is what makes it look like a cache problem rather than an EOL problem. Two rebuilds were
# burned on --no-cache and --pull before that was understood. The archive still has
# everything. Check-Valid-Until is off because an archived Release file is deliberately
# expired; that is expected for an archived suite, not a signature problem.
RUN printf '%s\n' \
      'deb http://archive.debian.org/debian bullseye main' \
      'deb http://archive.debian.org/debian-security bullseye-security main' \
      > /etc/apt/sources.list \
    && printf '%s\n' 'Acquire::Check-Valid-Until "false";' \
      > /etc/apt/apt.conf.d/99no-check-valid-until \
    && apt-get update && apt-get install -y --no-install-recommends \
        git ca-certificates curl wget build-essential libtool autotools-dev automake \
        cmake pkg-config python3 bsdmainutils patch xz-utils unzip \
    && rm -rf /var/lib/apt/lists/*
# 1.0.6 is upstream's own words a "mandatory soft fork", published 2026-08-13, and it is the
# version this node must be on — not eventually, already. Two consensus rules, BOTH activating
# at mainnet height H = 1,739,500. We were at 1,812,752 on 2026-10-06, so the chain is 73,000
# blocks PAST activation: 1.0.5 was not "a bit behind", it was running without rules the
# network had adopted.
#
#  1. The KAWPOW header-height check, which is what `bad-blk-height` below is the name of.
#     CheckBlockHeader's checkpoint shortcut validates a KAWPOW block using only the
#     miner-supplied mix_hash, and decides whether to take that cheap path from
#     `block.nHeight` — a field THE MINER CONTROLS. A block mined above the last checkpoint
#     declares a height below it, triggers the shortcut, and skips real memory-hard KAWPOW
#     verification. ContextualCheckBlockHeader never compared the declared height against
#     pindexPrev->nHeight + 1. The same bug was ACTIVELY EXPLOITED on Ravencoin mainnet on
#     2026-08-07; Neurai audited its own chain first and found no sign of prior exploitation
#     here, which is why this is a correctness upgrade rather than an incident.
#  2. The asset-transfer amount overflow: CheckTxAssets accumulated per-asset amounts in a
#     signed int64 and only enforced inputs == outputs, so crafted amounts overflow the
#     accumulator while the equality still holds — asset inflation.
#
# 1.0.6 also ships recovery for a node that already ingested a contaminated index
# (LoadBlockIndexGuts skipping bad entries instead of aborting, PruneBrokenBlockIndex, and a
# chainstate auto-rebuild). Ours needed none of it — it came up with blocks == headers and no
# reindex — but that recovery path is exactly what the RVN node's 2026-08 death needed.
# 1.0.7 (upstream 2026-10-10): stability, sync, block import and refreshed checkpoints; same consensus
# rules as 1.0.6 (the bad-blk-height check below still has to be IN the binary). Built -j2 on the Pi
# so the live pools keep two cores.
ARG NEURAI_TAG=1.0.7
RUN git clone --depth 1 --branch ${NEURAI_TAG} https://github.com/NeuraiProject/Neurai.git /Neurai
WORKDIR /Neurai
# Native aarch64 build: depends sets HOST=aarch64-unknown-linux-gnu and boost's
# user-config.jam invokes the triplet-prefixed compiler (aarch64-unknown-linux-gnu-g++),
# which does not exist on a native host (compilers are unprefixed). Symlink the whole
# triplet-prefixed toolchain to the native tools so boost (and any other prefixed-tool
# caller) resolves correctly.
RUN T=aarch64-unknown-linux-gnu && \
    for tool in gcc g++ cpp ar ranlib strip nm ld as objcopy objdump; do \
        src="$(command -v $tool || true)"; \
        [ -n "$src" ] && ln -sf "$src" /usr/local/bin/${T}-${tool}; \
    done
RUN cd depends && make -j2 NO_QT=1 NO_UPNP=1 FALLBACK_DOWNLOAD_PATH=https://bitcoincore.org/depends-sources
RUN ./autogen.sh && \
    CONFIG_SITE="$(echo /Neurai/depends/*-linux-gnu/share/config.site)" ./configure \
        --disable-tests --disable-bench --without-gui && \
    make -j2 && strip src/neuraid src/neurai-cli \
    # The tag is not the proof. A release page has been known to claim new code while
    # attaching old code, and a git tag can be moved. The fix introduces a `bad-blk-height`
    # rejection, so that string has to be IN the binary we are about to ship. It is a
    # literal in .rodata, so it survives `strip` — this checks what actually ships, not an
    # intermediate. Without this the build succeeds against any tag at all.
    && grep -q 'bad-blk-height' src/neuraid \
    && echo "verified: neuraid contains the bad-blk-height consensus check"
FROM debian:trixie-slim
RUN apt-get update && apt-get install -y --no-install-recommends libstdc++6 ca-certificates \
    && rm -rf /var/lib/apt/lists/*
COPY --from=builder /Neurai/src/neuraid    /usr/local/bin/neuraid
COPY --from=builder /Neurai/src/neurai-cli /usr/local/bin/neurai-cli
RUN useradd -m -u 1000 neurai && mkdir -p /data && chown neurai:neurai /data
USER neurai
EXPOSE 19000 19001 28334
ENTRYPOINT ["neuraid"]
