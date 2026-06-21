# neurai-arm64-docker

Run a **Neurai (XNA) full node on ARM64** (Raspberry Pi 5, etc.) in Docker — KawPoW,
Bitcoin-Core-style daemon, **compiled from source for aarch64**.

## The blocker it solves
On a native aarch64 build, Bitcoin-Core's `depends` system sets
`HOST=aarch64-unknown-linux-gnu` and **boost's `user-config.jam` invokes the triplet-prefixed
compiler `aarch64-unknown-linux-gnu-g++`** — which doesn't exist on a native host (the compiler
is just `g++`). The build dies with `provided command 'aarch64-unknown-linux-gnu-g++' not found`.

Fix: **symlink the whole triplet-prefixed toolchain to the native tools** before `depends`
builds boost. (See the `RUN T=aarch64-unknown-linux-gnu ...` line in the Dockerfile.)

Built on **bullseye (gcc-10)** for the boost 1.7x / bdb 4.8 era; runs on a `trixie-slim` runtime.

## Usage
```bash
cp neurai.conf.example neurai.conf      # set a strong rpcuser/rpcpassword
docker compose up -d --build            # ~1-2h depends build on a Pi 5
docker compose logs -f
docker exec neurai-node neurai-cli -conf=/etc/neurai/neurai.conf -datadir=/data getblockcount
```
RPC `127.0.0.1:19001` · P2P `19000` · ZMQ `28334`.

### Fast sync tip
To skip a long sync: cleanly stop a synced Neurai wallet elsewhere and copy its `blocks/` +
`chainstate/` into this node's volume, `chown -R 1000:1000`, then start. Match `txindex` to
whatever the source used (default 0) or you'll be told to `-reindex`.

## License
Neurai is the property of its respective authors. This repo is only the aarch64 Docker recipe.
