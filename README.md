# Camera Preview

A macOS menu-bar app for checking how you look before a meeting, written in
Common Lisp.

Click the camera icon in the menu bar and a plain, borderless view of your
camera drops down below it: mirrored, in the camera's own aspect ratio, about a
third of the screen wide. Click the icon again, press Escape, or click anywhere
else, and it goes away and the camera turns off.

Drag the picture to move it; it reopens where you left it, kept on screen if
your displays change.

Right-click (or control-click) the icon for:

- the list of cameras, to choose which one to show (remembered)
- **Mirror Image** — on by default; turn it off to see what the meeting sees
- **Reset Position** — back under the icon; shown once you have moved it
- **Camera Privacy Settings…** — if you said no to the permission prompt
- **Start at Login** — only shown when running from the bundle; the checkmark
  reflects System Settings › General › Login Items, so removing it there is
  noticed
- **Quit**

Built on [objc](https://github.com/lispnik/objc) and packaged with
[asdf-macos-app](https://github.com/lispnik/asdf-macos-app), on SBCL.

## Building

The two libraries are sibling checkouts; objc's `ocicl/` supplies everything
else.

```
cd ~/Projects/common-lisp
git clone https://github.com/lispnik/objc.git
git clone https://github.com/lispnik/asdf-macos-app.git
(cd objc && ocicl install)
cd camera-preview-app
make            # build/Camera Preview.app
make run        # build it and open it
make install    # copy it to ~/Applications
make test       # the FiveAM suite (geometry; no camera or window server needed)
```

`OBJC_DIR` and `MACOS_APP_DIR` override where the Makefile looks for the two
libraries.

The first time the preview opens, macOS asks for permission to use the camera.
The picture appears as soon as you allow it, without another click.

### Signing, so it asks only once

Without a signing identity the bundle is signed ad hoc, and macOS asks for the
camera again after **every** rebuild: an ad hoc signature is a hash of that
exact build, so each build is a new app to it. Signed with a certificate, the
permission is remembered against your team and the bundle identifier instead,
and survives rebuilds.

```
cp local.mk.example local.mk     # git ignores local.mk
security find-identity -v -p codesigning
# then set SIGN_IDENTITY in local.mk to one of those
```

A "Developer ID Application" certificate can also be notarised for
distribution; "Apple Development" is enough for your own machine. Signing with
a certificate timestamps the signature, so `make app` then needs the network.
`make app SIGN_IDENTITY="…"` works for a one-off.

## Building with ECL

The same source also builds on [lispnik/ecl](https://github.com/lispnik/ecl)
(stock ECL cannot resolve foreign symbols the way CFFI needs on Darwin):

```
make test-ecl    # the suite on ECL
make app-ecl     # build/ecl/Camera Preview ECL.app
make run-ecl
```

`ECL_PREFIX` says where that ECL is installed (default
`~/Projects/ecl/ecl-native`). asdf-macos-app is SBCL-only, so the ECL bundle is
assembled by the Makefile around a program `tools/build-ecl.lisp` links, with
the SBCL bundle's Info.plist and icon under its own identifier
(`com.lispnik.camera-preview-ecl`) so both can be installed at once. It
carries `libecl` and nothing else from ECL: the program switches `compile` to
ECL's bytecode compiler (objc compiles per method signature at run time, and
the native compiler would need clang and ECL's install directory) and detaches
`SYS:help.doc` from the documentation pool.

### The Mac App Store and TestFlight

The ECL app is also the one that goes to the Mac App Store, as
`com.burnsidemk.camera-preview-ecl`:

```
make mas-ecl          # build/mas/Camera-Preview-ECL.pkg
make testflight-ecl   # validate it, then upload it
```

It needs, in `local.mk` (see `local.mk.example`), an Apple Distribution and a
Mac Installer Distribution identity, a Mac App Store provisioning profile for
that identifier, and an App Store Connect API key. The store build is the
local one re-signed: the ECL bundle is sandboxed in every build, so
`make run-ecl` runs what TestFlight runs. Start at Login is absent from it,
since the sandbox refuses the API it uses.

Two things the sandbox required, both measured:

- **AppKit is linked at launch.** A sandboxed process may reach LaunchServices
  only if a framework that checks in with it was loaded at exec. An ECL
  program links only `libSystem` and objc `dlopen`s AppKit later, so
  `-[NSApplication init]` was refused and aborted the process — as did a C
  program that `dlopen`ed AppKit and linked nothing else.
- **`LSMinimumSystemVersion` is read from the executable**, not inherited from
  the SBCL bundle's 11.0: ECL here is built for the macOS it was built on, and
  App Store Connect refuses an arm64-only app declaring less than 12.0.

Measured on an Apple silicon Mac, the two bundles one after the other, idle in the
menu bar:

| | SBCL 2.6.8 | lispnik/ecl 26.5.5 |
|---|---|---|
| bundle on disk | 57 MB (a 50 MB core) | 8.6 MB |
| start to exit, warm | 0.04 s | 0.25 s |
| CPU to start up | 0.16 s | 0.45 s |
| memory footprint, idle | 74 MB | 31 MB |
| CPU, 30 s idle | ~0.01 s | ~0.01 s |
| threads, idle | 7 | 11 |

SBCL maps a saved image and is running almost at once; ECL has no image, and
re-runs every file's top-level forms at each start. ECL is a seventh the size
and less than half the memory. Neither does anything while idle, and with the
preview open the video goes from AVFoundation to Core Animation without passing
through Lisp in either.

## Why a bundle

macOS grants the camera to an *application*, which means a bundle with
`NSCameraUsageDescription` in its Info.plist (the sentence in the prompt) and,
under the hardened runtime, the `com.apple.security.device.camera` entitlement.
Both are in `camera-preview-app-bundle.asd` and `etc/entitlements.plist`.

`make bin` still builds a loose `bin/camera-preview`, which is handy from a
REPL, but run from a terminal it asks for the camera as the terminal.

## Command line

```
Camera Preview.app/Contents/MacOS/camera-preview --show         open the preview at launch
Camera Preview.app/Contents/MacOS/camera-preview --timeout 30   quit after 30 seconds
Camera Preview.app/Contents/MacOS/camera-preview --cameras      list cameras and exit
Camera Preview.app/Contents/MacOS/camera-preview --status       print the camera permission
Camera Preview.app/Contents/MacOS/camera-preview --login-status say whether it starts at login
Camera Preview.app/Contents/MacOS/camera-preview --login-add    start it at login
Camera Preview.app/Contents/MacOS/camera-preview --login-remove stop starting it at login
```

A login item records the bundle's path, so `make install` first and enable it
from the installed copy, not from `build/`, which `make clean` deletes.

Inside the bundle, output goes to `~/Library/Logs/Camera Preview.log`.

## Layout

| file | what |
|---|---|
| `src/geometry.lisp` | where the panel goes and how big it is; pure, and tested |
| `src/camera.lisp` | `AVCaptureSession`, the preview layer, devices, permission |
| `src/panel.lisp` | the borderless `NSPanel` subclass that holds the picture |
| `src/login-item.lisp` | Start at Login, via `LSSharedFileList` (see its header for why not `SMAppService`) |
| `src/app.lisp` | the status item, its menu, showing and hiding |
| `src/portable.lisp` | arguments, exit, SIGTERM and logging, for SBCL and ECL |
| `src/main.lisp` | the entry point |
| `tools/icon.lisp` | draws `res/icon.png` (`make icon`) |
| `tools/build-ecl.lisp` | links the ECL executable (`make app-ecl`) |

No frame passes through Lisp: the video goes straight from AVFoundation into a
Core Animation layer. The session is started and stopped from an
`NSOperationQueue` that never runs Lisp code, because `-startRunning` blocks for
most of a second. Permission is watched with a main-thread timer rather than a
completion block, because a block would call into Lisp from a libdispatch
worker.
