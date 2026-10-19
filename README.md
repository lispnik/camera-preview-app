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
| `src/main.lisp` | the entry point |
| `tools/icon.lisp` | draws `res/icon.png` (`make icon`) |

No frame passes through Lisp: the video goes straight from AVFoundation into a
Core Animation layer. The session is started and stopped from an
`NSOperationQueue` that never runs Lisp code, because `-startRunning` blocks for
most of a second. Permission is watched with a main-thread timer rather than a
completion block, because a block would call into Lisp from a libdispatch
worker.
