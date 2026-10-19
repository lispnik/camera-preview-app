;;;; camera-preview-app.asd -- a macOS menu-bar camera preview, in Common Lisp.
;;;;
;;;; Three systems.  #:camera-preview-app is the library; its geometry is kept
;;;; free of Objective-C so the suite can test it without a window server or a
;;;; camera.  #:camera-preview-app/app builds bin/camera-preview, the loose
;;;; binary.  #:camera-preview-app/tests is the FiveAM suite.
;;;;
;;;; The bundle is in camera-preview-app-bundle.asd, and for this application
;;;; it is the one that matters: macOS grants the camera to a BUNDLE with an
;;;; NSCameraUsageDescription.  The loose binary, run from a terminal, borrows
;;;; the terminal's camera permission instead -- useful from a REPL, and nothing
;;;; else.

(asdf:defsystem #:camera-preview-app
  :description "A macOS menu-bar camera preview, for checking your appearance before a meeting."
  :long-description
  "An NSStatusItem with a camera icon.  Clicking it drops a plain, borderless
panel below it showing the camera, mirrored, in the camera's own aspect ratio
and about a third of the screen wide.  Clicking again, pressing Escape, or
clicking anywhere else puts it away and turns the camera off.

Right-clicking offers the choice of camera, mirroring, and Quit.

Built on the objc bindings: the status item, the panel, the capture session
and its preview layer are Objective-C objects driven from Lisp, and the panel's
key handling and the controller's actions are Lisp methods."
  :author "Matthew Kennedy <burnsidemk@gmail.com>"
  :license "MIT"
  :version "0.1.0"
  :serial t
  :depends-on (#:objc #:cffi #:float-features)
  :components ((:module "src"
                :serial t
                :components
                ((:file "package")
                 (:file "frameworks")
                 (:file "geometry")
                 (:file "camera")
                 (:file "panel")
                 (:file "login-item")
                 (:file "app")))))

(asdf:defsystem #:camera-preview-app/app
  :description "bin/camera-preview, the menu-bar application as a loose binary."
  :depends-on (#:camera-preview-app)
  :build-operation "program-op"
  ;; ASDF resolves :BUILD-PATHNAME against the SYSTEM's pathname, so the
  ;; components live in a :MODULE rather than under a system-level :PATHNAME,
  ;; which would put the binary in src/bin/.
  :build-pathname "bin/camera-preview"
  :entry-point "camera-preview-app:main"
  :components ((:module "src"
                :components ((:file "main")))))

(asdf:defsystem #:camera-preview-app/tests
  :description "The FiveAM suite."
  :depends-on (#:camera-preview-app #:fiveam)
  :serial t
  :components ((:module "tests"
                :serial t
                :components
                ((:file "package")
                 (:file "geometry-tests"))))
  ;; FIVEAM:RUN! returns NIL on failure and ASDF discards a TEST-OP's value, so
  ;; the status has to be turned into an error here or a red suite goes green.
  :perform (asdf:test-op (o c)
             (unless (uiop:symbol-call :camera-preview-app/tests :run-tests)
               (error "The test suite failed."))))
