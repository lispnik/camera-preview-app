# Makefile for camera-preview-app.
#
#   make            build "build/Camera Preview.app"
#   make run        build the app and open it
#   make bin        build bin/camera-preview, the loose binary
#   make app-ecl    build "build/ecl/Camera Preview ECL.app" with lispnik/ecl
#   make run-ecl    build that and open it
#   make mas-ecl    the ECL app as a signed Mac App Store .pkg
#   make testflight-ecl   validate that .pkg and upload it to TestFlight
#   make test       run the FiveAM suite
#   make icon       redraw res/icon.png
#   make repl       an SBCL with the library loaded
#   make install    copy the app to $(APPS)
#   make clean      remove the builds, fasls, and this tree's ASDF cache
#
# objc and asdf-macos-app are sibling checkouts, not ocicl packages, so every
# target builds a source registry from this tree plus those two -- with
# :IGNORE-INHERITED-CONFIGURATION, so a missing dependency fails here rather than
# resolving to whatever ~/.sbclrc happens to find.  objc's own ocicl/ directory
# supplies cffi, fiveam and the rest (`cd $(OBJC_DIR) && ocicl install').

LISP ?= sbcl
OBJC_DIR ?= $(HOME)/Projects/common-lisp/objc
MACOS_APP_DIR ?= $(HOME)/Projects/common-lisp/asdf-macos-app
APPS ?= $(HOME)/Applications
# lispnik/ecl, not Homebrew's: stock ECL cannot resolve foreign symbols through
# :default on Darwin, which CFFI needs.  See objc's README, "ECL".
ECL_PREFIX ?= $(HOME)/Projects/ecl/ecl-native
ECL ?= $(ECL_PREFIX)/bin/ecl

# Machine-specific settings, kept out of git: in practice, this machine's
# signing identity.  See local.mk.example.
-include local.mk

# Empty means ad hoc: builds anywhere, runs locally, cannot be notarised -- and
# macOS asks for the camera again after every build, because an ad hoc
# signature is a hash of the code and so a new identity each time.  A real
# certificate's identity survives rebuilds.
SIGN_IDENTITY ?=
export CAMERA_PREVIEW_SIGN_IDENTITY = $(SIGN_IDENTITY)

REGISTRY = (asdf:initialize-source-registry \
              (list :source-registry \
                    (list :tree (truename "./")) \
                    (list :tree (truename "$(OBJC_DIR)")) \
                    (list :tree (truename "$(MACOS_APP_DIR)")) \
                    :ignore-inherited-configuration))

SBCL = $(LISP) --non-interactive --no-userinit --no-sysinit \
         --eval '(require :asdf)' --eval '$(REGISTRY)'

# The bundle's name has a space in it, which Make cannot have in a target, so
# its freshness is tracked by a stamp.
APP = build/Camera Preview.app
APP_STAMP = build/.app-stamp

.PHONY: all app run bin test test-ecl app-ecl run-ecl mas-ecl testflight-ecl \
        icon repl install clean

all: app

app: $(APP_STAMP)

$(APP_STAMP): camera-preview-app.asd camera-preview-app-bundle.asd \
              $(wildcard src/*.lisp) etc/entitlements.plist res/icon.png \
              $(wildcard local.mk)
	$(SBCL) --eval '(asdf:make :camera-preview-app-bundle)'
	@touch $(APP_STAMP)
	@echo "built $(APP)"

# `open', not the executable directly: launched from a shell, the process is
# the shell's responsibility as far as TCC is concerned, and the camera prompt
# would be about Terminal rather than about this app.
run: app
	open "$(APP)"

bin: bin/camera-preview

bin/camera-preview: camera-preview-app.asd $(wildcard src/*.lisp)
	@mkdir -p bin
	$(SBCL) --eval '(asdf:make :camera-preview-app/app)'
	@echo "built $@"

test:
	$(SBCL) --eval '(asdf:load-system :camera-preview-app/tests)' \
	  --eval '(uiop:quit (if (camera-preview-app/tests:run-tests) 0 1))'

# ECL -----------------------------------------------------------------------
#
# asdf-macos-app dumps an SBCL image and is SBCL-only, so the ECL bundle is put
# together here: tools/build-ecl.lisp links a native executable, and this rule
# wraps it in the same Info.plist, icon and entitlements as the SBCL bundle --
# under its own identifier, so the two can be installed and compared side by
# side -- with libecl beside it in Frameworks/.  ECL's install directory is not
# shipped: the program is built not to need it (see tools/build-ecl.lisp).

ECL_SBCL = $(ECL) --norc --eval '(require :asdf)' --eval '$(REGISTRY)'
# The identifier registered in App Store Connect for the ECL build.
ECL_BUNDLE_ID = com.burnsidemk.camera-preview-ecl
# CFBundleVersion, which App Store Connect requires to rise with every upload
# of the same short version.  The time, so two uploads from one commit -- a
# rejected build fixed and sent again -- still differ.
ECL_BUILD := $(shell date +%Y%m%d.%H%M)
ECL_APP = build/ecl/Camera Preview ECL.app
ECL_APP_STAMP = build/ecl/.app-stamp
ECL_LIBECL = $(notdir $(firstword $(shell otool -L $(ECL) | sed -n 's|.*@rpath/\(libecl[^ ]*\).*|\1|p')))

app-ecl: $(ECL_APP_STAMP)

build/ecl/camera-preview: camera-preview-app.asd $(wildcard src/*.lisp) tools/build-ecl.lisp
	$(ECL_SBCL) --load tools/build-ecl.lisp --eval '(ext:quit 0)'

# The SBCL bundle is a prerequisite for its Info.plist and .icns, which are
# copied and renamed rather than generated twice.
$(ECL_APP_STAMP): build/ecl/camera-preview $(APP_STAMP) etc/entitlements-ecl.plist Makefile
	rm -rf "$(ECL_APP)"
	mkdir -p "$(ECL_APP)/Contents/MacOS" "$(ECL_APP)/Contents/Resources" \
	         "$(ECL_APP)/Contents/Frameworks"
	cp build/ecl/camera-preview "$(ECL_APP)/Contents/MacOS/camera-preview"
	cp "$(APP)/Contents/PkgInfo" "$(ECL_APP)/Contents/"
	cp "$(APP)/Contents/Resources/camera-preview.icns" "$(ECL_APP)/Contents/Resources/"
	cp "$(APP)/Contents/Info.plist" "$(ECL_APP)/Contents/Info.plist"
	plutil -replace CFBundleIdentifier -string $(ECL_BUNDLE_ID) "$(ECL_APP)/Contents/Info.plist"
	plutil -replace CFBundleVersion -string $(ECL_BUILD) "$(ECL_APP)/Contents/Info.plist"
	@# The oldest macOS the executable will actually load on, read from it
	@# rather than inherited from the SBCL bundle's 11.0: ECL and the program
	@# are built for the machine they were built on.  Also what App Store
	@# Connect checks -- an arm64-only app must say 12.0 or later.
	plutil -replace LSMinimumSystemVersion -string \
	  "$$(otool -l build/ecl/camera-preview | sed -n '/LC_BUILD_VERSION/,/minos/s/.*minos //p' | head -1)" \
	  "$(ECL_APP)/Contents/Info.plist"
	@# Answers App Store Connect's export compliance question in advance:
	@# nothing here encrypts anything.
	plutil -replace ITSAppUsesNonExemptEncryption -bool NO "$(ECL_APP)/Contents/Info.plist"
	plutil -replace CFBundleName -string "Camera Preview ECL" "$(ECL_APP)/Contents/Info.plist"
	plutil -replace CFBundleDisplayName -string "Camera Preview ECL" "$(ECL_APP)/Contents/Info.plist"
	@# libecl from the bundle, not from the ECL tree: the link left an
	@# absolute LC_RPATH to $(ECL_PREFIX)/lib, which would work here and
	@# nowhere else.
	cp -L "$(ECL_PREFIX)/lib/$(ECL_LIBECL)" "$(ECL_APP)/Contents/Frameworks/"
	install_name_tool -delete_rpath "$(ECL_PREFIX)/lib/" "$(ECL_APP)/Contents/MacOS/camera-preview"
	install_name_tool -add_rpath "@executable_path/../Frameworks" "$(ECL_APP)/Contents/MacOS/camera-preview"
	@# Innermost first, as asdf-macos-app does: the dylib, then the bundle
	@# with the hardened runtime and the camera entitlement.
	codesign --force --sign "$(or $(SIGN_IDENTITY),-)" $(if $(SIGN_IDENTITY),--timestamp) \
	  "$(ECL_APP)/Contents/Frameworks/$(ECL_LIBECL)"
	codesign --force --sign "$(or $(SIGN_IDENTITY),-)" $(if $(SIGN_IDENTITY),--timestamp) \
	  --options runtime --entitlements etc/entitlements-ecl.plist "$(ECL_APP)"
	codesign --verify --deep --strict "$(ECL_APP)"
	@touch $(ECL_APP_STAMP)
	@echo "built $(ECL_APP)"

run-ecl: app-ecl
	open "$(ECL_APP)"

# The Mac App Store build --------------------------------------------------
#
# The same bundle re-signed for the store: by an Apple Distribution identity,
# with the Mac App Store provisioning profile embedded and the two entitlements
# that profile grants added to the sandbox and camera ones, then wrapped in a
# .pkg signed by the Mac Installer Distribution identity, which is the only form
# App Store Connect takes a Mac app in.  A store-signed app will not launch
# locally; `make run-ecl' runs the same code, sandboxed the same way.
#
# local.mk supplies MAS_IDENTITY, MAS_INSTALLER_IDENTITY, MAS_PROFILE,
# ASC_KEY_ID and ASC_ISSUER_ID; see local.mk.example.

MAS_DIR = build/mas
MAS_APP = $(MAS_DIR)/Camera Preview ECL.app
MAS_PKG = $(MAS_DIR)/Camera-Preview-ECL.pkg
MAS_ENTITLEMENTS = $(MAS_DIR)/entitlements.plist
# The team, from the identity's "(TEAMID)" suffix.
TEAM_ID = $(shell echo '$(MAS_IDENTITY)' | sed -n 's/.*(\([A-Z0-9]*\)).*/\1/p')

mas-ecl: $(ECL_APP_STAMP)
	@test -n "$(MAS_IDENTITY)" -a -n "$(MAS_INSTALLER_IDENTITY)" -a -f "$(MAS_PROFILE)" || { \
	  echo "error: set MAS_IDENTITY, MAS_INSTALLER_IDENTITY and MAS_PROFILE in local.mk" >&2; exit 1; }
	rm -rf "$(MAS_DIR)"
	mkdir -p "$(MAS_DIR)"
	cp -R "$(ECL_APP)" "$(MAS_APP)"
	cp "$(MAS_PROFILE)" "$(MAS_APP)/Contents/embedded.provisionprofile"
	cp etc/entitlements-ecl.plist "$(MAS_ENTITLEMENTS)"
	plutil -insert 'com\.apple\.application-identifier' -string "$(TEAM_ID).$(ECL_BUNDLE_ID)" "$(MAS_ENTITLEMENTS)"
	plutil -insert 'com\.apple\.developer\.team-identifier' -string "$(TEAM_ID)" "$(MAS_ENTITLEMENTS)"
	codesign --force --sign "$(MAS_IDENTITY)" "$(MAS_APP)/Contents/Frameworks/$(ECL_LIBECL)"
	codesign --force --sign "$(MAS_IDENTITY)" --entitlements "$(MAS_ENTITLEMENTS)" "$(MAS_APP)"
	codesign --verify --deep --strict "$(MAS_APP)"
	productbuild --component "$(MAS_APP)" /Applications \
	  --sign "$(MAS_INSTALLER_IDENTITY)" "$(MAS_PKG)"
	@echo "built $(MAS_PKG)"

testflight-ecl: mas-ecl
	@test -n "$(ASC_KEY_ID)" -a -n "$(ASC_ISSUER_ID)" || { \
	  echo "error: set ASC_KEY_ID and ASC_ISSUER_ID in local.mk" >&2; exit 1; }
	xcrun altool --validate-app -f "$(MAS_PKG)" -t macos \
	  --apiKey "$(ASC_KEY_ID)" --apiIssuer "$(ASC_ISSUER_ID)"
	xcrun altool --upload-app -f "$(MAS_PKG)" -t macos \
	  --apiKey "$(ASC_KEY_ID)" --apiIssuer "$(ASC_ISSUER_ID)"

test-ecl:
	$(ECL_SBCL) --eval '(asdf:load-system :camera-preview-app/tests)' \
	  --eval '(ext:quit (if (camera-preview-app/tests:run-tests) 0 1))'

res/icon.png: tools/icon.lisp
	$(SBCL) --eval '(asdf:load-system :objc)' \
	  --load tools/icon.lisp \
	  --eval '(camera-preview-icon:render-icon "res/icon.png")'
	@echo "drew res/icon.png"

icon: res/icon.png

repl:
	$(LISP) --no-userinit --no-sysinit \
	  --eval '(require :asdf)' --eval '$(REGISTRY)' \
	  --eval '(asdf:load-system :camera-preview-app)'

install: app
	@mkdir -p "$(APPS)"
	rm -rf "$(APPS)/Camera Preview.app"
	cp -R "$(APP)" "$(APPS)/"
	@echo "installed $(APPS)/Camera Preview.app"

clean:
	rm -rf bin build
	rm -rf $(HOME)/.cache/common-lisp/*/$(CURDIR)
