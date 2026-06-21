# Neurai (XNA) node — KawPoW, RVN-based, compiled from source for aarch64.
# bullseye builder (gcc-10/glibc2.31) for boost1.7x+bdb4.8; trixie-slim runtime.
FROM debian:bullseye AS builder
RUN apt-get update && apt-get install -y --no-install-recommends \
        git ca-certificates curl wget build-essential libtool autotools-dev automake \
        cmake pkg-config python3 bsdmainutils patch xz-utils unzip \
    && rm -rf /var/lib/apt/lists/*
ARG NEURAI_TAG=1.0.5
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
RUN cd depends && make -j3 NO_QT=1 NO_UPNP=1 FALLBACK_DOWNLOAD_PATH=https://bitcoincore.org/depends-sources
RUN ./autogen.sh && \
    CONFIG_SITE="$(echo /Neurai/depends/*-linux-gnu/share/config.site)" ./configure \
        --disable-tests --disable-bench --without-gui && \
    make -j3 && strip src/neuraid src/neurai-cli
FROM debian:trixie-slim
RUN apt-get update && apt-get install -y --no-install-recommends libstdc++6 ca-certificates \
    && rm -rf /var/lib/apt/lists/*
COPY --from=builder /Neurai/src/neuraid    /usr/local/bin/neuraid
COPY --from=builder /Neurai/src/neurai-cli /usr/local/bin/neurai-cli
RUN useradd -m -u 1000 neurai && mkdir -p /data && chown neurai:neurai /data
USER neurai
EXPOSE 19000 19001 28334
ENTRYPOINT ["neuraid"]
