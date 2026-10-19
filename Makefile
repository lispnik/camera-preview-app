# Makefile for camera-preview-app.
#
#   make            build "build/Camera Preview.app"
#   make run        build the app and open it
#   make bin        build bin/camera-preview, the loose binary
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

.PHONY: all app run bin test icon repl install clean

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
