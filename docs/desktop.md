# Desktop clients

Tauri 2 wraps the same remote Phoenix LiveView interface used by browsers. The
client automatically opens the last selected server on startup, defaulting to
https://tijara-tides.onrender.com/ on first launch. Root addresses open directly
at /play; explicitly entered paths are preserved. Each server currently hosts one
world. The game session is held by the webview's persistent cookies, so returning
to a server resumes the same account and company unless signed out or expired.
Connection Settings remembers the ten most recent distinct addresses in a
dropdown and always includes production. Select one or enter a new URL, then
click **Connect to server**. Addresses are stored locally when connecting; the
list may include an unreachable server. A browser and a native app normally have
separate cookie stores and therefore join as separate guests.

The window size, position, and maximized state are saved locally on exit and restored on
the next launch using Tauri's window-state plugin. The first launch defaults to
1200 × 800, with a minimum window size of 640 × 480.

There is no embedded Elixir runtime, local simulation, or offline game. Launching
or closing a desktop client only changes its connection to the shared world.

## Develop and build

Install Rust, Node.js 22+, and your platform's
[Tauri prerequisites](https://v2.tauri.app/start/prerequisites/). On macOS this
includes Xcode Command Line Tools. On Ubuntu 24.04:

```sh
sudo apt-get install build-essential pkg-config libwebkit2gtk-4.1-dev libgtk-3-dev \
  libdbus-1-dev libayatana-appindicator3-dev librsvg2-dev patchelf
```

From the repository root:

```sh
npm ci
npm run desktop:dev
```

Run `mix phx.server` separately if you want a local server, then enter
`http://localhost:4000` in the client. A server is not required to build packages.
The development server from the initial skeleton work uses port 4011 if still
running; normal fresh startup defaults to 4000.

```sh
# macOS, on the architecture you want to distribute
npm run desktop:build -- --ci --bundles app,dmg -- --locked

# Linux (Ubuntu 24.04), on the architecture you want to distribute
npm run desktop:build -- --ci --bundles deb -- --locked
```

Output lives under `src-tauri/target/release/bundle/`. macOS builds produce an
`.app` and a `.dmg`; Linux produces a `.deb`. The CI matrix builds Apple Silicon
Mac and Linux x86_64 on native runners. The .deb declares a glibc 2.39
floor and WebKitGTK 4.1; use the Flatpak on distributions with older host libraries.
Linux ARM packaging is not part of the current CI matrix.

## Desktop icons

The cargo ship artwork in `src-tauri/icons/cargo-ship-v2/source.png` is the
master icon. Regenerate the packaged PNG sizes and macOS `.icns` with
`npm run desktop:icons`. The `.deb` installs PNG icons at 32, 128, 256, 512,
and 1024 pixels. Flatpak installs only the 32, 128, 256, and 512 pixel sizes to
meet its 512×512 export limit. These sizes preserve the artwork and its
transparent corners.
The packaging uses these raster sizes directly; no SVG conversion is needed.

## Connection handling

**Tijara Tides → Connection Settings** (`Cmd/Ctrl+Shift+C`) returns to the local
connection screen even if the remote server fails to load. **Reload**
(`Cmd/Ctrl+R`) retries the current page. The native Edit menu supports copy/paste.
These menu actions are implemented in Rust and do not depend on the server UI.
Opening Connection Settings suppresses automatic reconnection so you can change
servers even when the previous server is unavailable.

The launcher accepts HTTPS, plus HTTP on loopback (`localhost`, `127.0.0.1`,
`[::1]`) for development. It rejects credentials embedded in URLs, query strings,
and fragments. Rust also blocks navigation to insecure remote HTTP, file URLs,
and non-web schemes. Remote pages have no Tauri capabilities or custom commands;
there is no shell, filesystem, notification, or updater plugin installed.

## Flatpak

This is a downloadable/sideloadable `.flatpak` bundle, not a Flathub submission.
The manifest repackages the native .deb against GNOME 50, matching the approach
in Armchair Metropolist. It grants network access for multiplayer, Wayland/X11
window display, IPC for X11, and GPU rendering. It grants no home-directory or
system-bus access. The earlier game's forced dummy proxy resolver is omitted:
this client needs normal network/proxy behavior.

The shared AppStream metadata names the Debian launcher, `Tijara Tides.desktop`.
Flatpak renames that launcher to the application ID and updates the metadata's
`desktop-id` to match during packaging. Both verification scripts assert the
installed pair through `scripts/check-appstream-launcher.py`, so the rename
cannot silently leave the metadata pointing at a launcher that is not there.

On Linux, install the toolchain and runtime once:

```sh
sudo apt-get install flatpak flatpak-builder elfutils librsvg2-common \
  appstream desktop-file-utils xvfb xauth xdotool dbus-x11
flatpak remote-add --user --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
flatpak install --user flathub org.gnome.Platform//50 org.gnome.Sdk//50
```

Then build and check the packages (use the actual .deb filename):

```sh
scripts/verify-deb.sh 'src-tauri/target/release/bundle/deb/Tijara Tides_0.1.0_amd64.deb'
scripts/build-flatpak.sh 'src-tauri/target/release/bundle/deb/Tijara Tides_0.1.0_amd64.deb'
scripts/verify-flatpak.sh dist/tijara-tides-x86_64.flatpak
```

The verification script installs the bundle in your user Flatpak installation,
checks permissions and dynamic library resolution, and opens its native window
under a temporary X11 display. It requires a Linux desktop stack with usable
Flatpak sandbox support. Install and launch normally with:

```sh
flatpak install --user dist/tijara-tides-x86_64.flatpak
flatpak run io.github.adsouza.tijara-tides
```

The Flatpak toolchain explicitly includes `elfutils` and `librsvg2-common` and
checks the SVG loader before building. This carries forward the packaging fixes
from Armchair Metropolist instead of relying on apt's recommended dependencies.

## Verification and distribution

```sh
npm run desktop:test
python3 scripts/check-desktop-versions.py
cargo fmt --manifest-path src-tauri/Cargo.toml --check
cargo clippy --manifest-path src-tauri/Cargo.toml --locked --all-targets -- -D warnings
cargo test --manifest-path src-tauri/Cargo.toml --locked
mix precommit
mix assets.build
```

`.github/workflows/desktop.yml` builds and uploads downloadable package artifacts
on branch pushes, pull requests, manual runs, and `v*` tag pushes. A pushed release
tag such as `v0.1.1` must match the versions in the tagged commit. Once both native
builds and their package checks pass, the workflow attaches the `.deb`, `.flatpak`,
`.dmg`, and `.app.zip` to a draft GitHub Release with generated release notes, then
publishes it after all uploads succeed. It verifies that the remote tag still
points to the built commit. The release job alone gets repository write access.
Ordinary branch pushes, pull requests, and manual runs only produce CI artifacts.
The workflow does not deploy the server or submit to an app store. macOS `.app`
artifacts are zipped with `ditto` to preserve executable permissions and metadata.

If publishing fails, rerun the failed job to reuse the draft release and retry its
uploads. Already-published releases are never replaced automatically; publish a
new version instead.

Current macOS artifacts are development builds without Developer ID signing or
Apple notarization. Before public distribution, configure the certificate and
notarization credentials using [Tauri's macOS signing workflow](https://v2.tauri.app/distribute/sign/macos/).
No signing credentials or public distribution accounts are assumed here.

Before a new versioned release, update all version declarations together:

```sh
npm run version:bump -- patch    # 0.1.0 -> 0.1.1
npm run version:bump -- minor    # increment minor and reset patch
npm run version:bump -- major    # increment major and reset minor/patch
npm run version:bump -- 1.2.3    # set an explicit greater X.Y.Z version
```

The helper updates `mix.exs`, both npm manifests, Cargo manifests/lockfile, Tauri
configuration, and AppStream metadata. It adds a new AppStream release dated today
while preserving prior releases, then verifies that all versions agree. Use
`--date YYYY-MM-DD` to set the release date explicitly. Invalid versions or existing
version mismatches fail before any files change. The helper preserves dependency
versions and does not commit, tag, push, or publish; review and commit the diff,
then push to trigger the desktop build. The consistency check also runs in CI.

After committing the helper/workflow changes and the version bump, push the
commit and its matching tag to publish a release. For example, after bumping to
`0.1.1` and committing that diff:

```sh
git tag -a v0.1.1 -m "Tijara Tides 0.1.1"
git push origin main
git push origin v0.1.1
```

The tag must point to the commit containing the workflow and bumped versions.
You can also release the current `0.1.0` as `v0.1.0` without bumping it first.
