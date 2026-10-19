;;;; tools/build-ecl.lisp -- build/ecl/camera-preview, a native ECL executable.
;;;;
;;;; Loaded by `make app-ecl' into lispnik/ecl, with the source registry already
;;;; set up.  asdf-macos-app is SBCL-only, so the bundle around this executable
;;;; is assembled by the Makefile; this file only makes the program.
;;;;
;;;; ECL has no image to dump.  Every file of every system is compiled to C and
;;;; then to an object, and the objects are linked with libecl into one Mach-O,
;;;; whose initialisation runs each file's top-level forms in order at startup.
;;;;
;;;; Two steps rather than ASDF:MAKE-BUILD, because of UIOP.  CFFI is compiled
;;;; against it, and in ECL it is not a system ASDF will link in but part of
;;;; ECL's own `asdf' module -- so a monolithic program built the obvious way
;;;; linked everything but UIOP and died at startup: "The packages (UIOP/OS ...)
;;;; were referenced in compiled file but have not been created".  So the
;;;; systems go into one static library, and C:BUILD-PROGRAM links that with
;;;; ECL's prebuilt libasdf.a, ASDF's library first so UIOP exists before
;;;; anything that names it is initialised.

(in-package #:cl-user)

(require :cmp)

(defparameter *output* (merge-pathnames "build/ecl/camera-preview" (uiop:getcwd)))

(ensure-directories-exist *output*)

;;; The library and every dependency in one archive -- MONOLITHIC-LIB-OP on the
;;; library system, not on #:camera-preview-app/app.  On that one, its
;;; :BUILD-PATHNAME made ASDF answer with an archive of main.o alone, and the
;;; program started with no CAMERA-PREVIEW-APP package at all.  So main.lisp
;;; goes in separately, as that system's own LIB-OP archive.
(asdf:operate 'asdf:monolithic-lib-op :camera-preview-app)
(asdf:operate 'asdf:lib-op :camera-preview-app/app)

(c:build-program
 *output*
 :lisp-files (list (translate-logical-pathname "SYS:libasdf.a")
                   (asdf:output-file 'asdf:monolithic-lib-op :camera-preview-app)
                   (asdf:output-file 'asdf:lib-op :camera-preview-app/app))
 ;; AppKit linked at LAUNCH, not only dlopened later as objc does.  The App
 ;; Sandbox lets a process reach LaunchServices only if a framework that
 ;; checks in with it was loaded when the sandbox went on, at exec; one that
 ;; links nothing but libSystem, as an ECL program does, is refused
 ;; (deny mach-lookup com.apple.coreservices.launchservicesd) and
 ;; -[NSApplication init] then aborts the process.  Measured with a C program
 ;; that dlopens AppKit: it aborts the same way linked against nothing, and
 ;; runs linked against CoreServices or Foundation.
 :ld-flags '("-framework" "AppKit")
 ;; Run before any of the app's code is initialised.
 ;;
 ;; The BYTECODES compiler, because objc calls COMPILE at run time -- once per
 ;; Lisp method signature, in blocks.lisp -- and ECL's default COMPILE is the
 ;; native one: it REQUIREs the CMP module from ECL's install directory and
 ;; runs clang.  Measured: with that directory absent the program died with
 ;; "Don't know how to REQUIRE CMP".  The bytecode compiler is in libecl, and
 ;; is what objc already uses on iOS, where there is no C compiler either.
 ;; objc's optional compiled trampolines probe for a C compiler and fall back
 ;; to the dynamic FFI, so they need nothing here.
 ;;
 ;; And SYS:help.doc detached from the documentation pool, as asdf-ios-app does
 ;; on a phone: SI::*DOCUMENTATION-POOL* is a hash table and that pathname, so
 ;; objc's load-time (SETF DOCUMENTATION ...) opened a file no bundle has --
 ;; "Cannot open SYS:help.doc", measured, the moment ECLDIR was taken away.
 ;; Docstrings still go in the table.  With both, the program needs nothing
 ;; from ECL's install directory, and the bundle ships none of it.
 :prologue-code '(progn
                  (ext:install-bytecodes-compiler)
                  (setf si::*documentation-pool*
                        (remove-if (lambda (entry) (or (stringp entry) (pathnamep entry)))
                                   si::*documentation-pool*)))
 ;; MAIN never returns: it exits with _exit(2) itself.  Named by string,
 ;; because this file is READ before the package it is in exists.
 :epilogue-code '(funcall (intern "MAIN" "CAMERA-PREVIEW-APP")))

(format t "~&built ~A~%" *output*)
