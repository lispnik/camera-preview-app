;;;; camera-preview-app-bundle.asd -- Camera Preview.app, in its own file.
;;;;
;;;; Separate from camera-preview-app.asd because :DEFSYSTEM-DEPENDS-ON is
;;;; resolved when the .asd is READ: in the main file, loading the library at
;;;; all would require asdf-macos-app to be present.  Here it is only needed
;;;; when the bundle is asked for, which is what `make app' does.
;;;;
;;;; For a camera application the bundle is not optional packaging.  TCC, the
;;;; privacy system, asks the user about the camera on behalf of a bundle, using
;;;; the bundle's NSCameraUsageDescription as the question, and remembers the
;;;; answer against its identifier.  Without that key the process is killed on
;;;; first use of the camera; without the camera entitlement the hardened
;;;; runtime refuses it silently.  Both are below.

(asdf:defsystem #:camera-preview-app-bundle
  :description "Camera Preview.app, a menu-bar bundle."
  :defsystem-depends-on ("asdf-macos-app")
  :class :macos-app-system
  :build-operation "macos-app-op"
  :depends-on (#:camera-preview-app)
  :entry-point "camera-preview-app:main"
  :version "0.1.0"
  :bundle-identifier "com.lispnik.camera-preview"
  :bundle-name "Camera Preview"
  :bundle-executable "camera-preview"
  ;; LSUIElement: no Dock icon and no application menu, but UI all the same.
  :bundle-agent t
  :bundle-principal-class "NSApplication"
  :bundle-category "public.app-category.utilities"
  ;; Drawn by tools/icon.lisp -- see `make icon'.
  :bundle-icon "res/icon.png"
  :bundle-copyright "MIT"
  ;; The sentence macOS shows in the permission prompt.  Required: a process
  ;; that touches the camera without it is terminated by TCC, not refused.
  :bundle-info-plist (("NSCameraUsageDescription"
                       . "Camera Preview shows your camera so you can check how you look before a meeting. Nothing is recorded or sent anywhere."))
  ;; The SBCL defaults plus com.apple.security.device.camera.  #. because ASDF
  ;; does not evaluate defsystem initargs, and merged against this file rather
  ;; than left relative, so the build does not depend on the current directory.
  :entitlements #.(merge-pathnames "etc/entitlements.plist"
                                   (or *load-truename* *compile-file-truename*))
  ;; Ad hoc unless an identity is supplied through the environment; an empty
  ;; value counts as absent, which is what make passes for an unset variable.
  ;;
  ;;   make app SIGN_IDENTITY="Developer ID Application: You (TEAMID)"
  :code-signing-identity #.(let ((identity (uiop:getenv "CAMERA_PREVIEW_SIGN_IDENTITY")))
                             (if (and identity (plusp (length identity)))
                                 identity
                                 "-"))
  :bundle-output-directory "build/"
  :components ((:module "src"
                :components ((:file "main")))))
