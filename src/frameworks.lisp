;;;; src/frameworks.lisp -- the frameworks this application needs loaded.
;;;;
;;;; ENSURE-OBJC-INITIALIZED loads Foundation and nothing else.  The status item
;;;; and the panel are AppKit, the capture session is AVFoundation, the preview
;;;; is a Core Animation layer, and the camera's dimensions come from a Core
;;;; Media C function.  Forgetting one shows up as `Cannot find class', which
;;;; reads like a fault in the bindings and is a missing framework.

(in-package #:camera-preview-app)

(defparameter +frameworks+
  '("/System/Library/Frameworks/AppKit.framework/Versions/C/AppKit"
    "/System/Library/Frameworks/AVFoundation.framework/Versions/A/AVFoundation"
    "/System/Library/Frameworks/CoreMedia.framework/Versions/A/CoreMedia"
    "/System/Library/Frameworks/QuartzCore.framework/Versions/A/QuartzCore")
  "Everything beyond Foundation.  See the header.")

(defun ensure-frameworks ()
  "Initialise Objective-C with every framework here loaded.  Idempotent.

Every entry point calls this rather than trusting that something else already
has, so any function here can be called on its own from a REPL."
  (objc:ensure-objc-initialized :modules +frameworks+))

(defun framework-constant (name)
  "The NSString an exported framework constant such as AVMediaTypeVideo holds.

Read from the framework rather than written out as a literal: these are
documented as opaque, and a literal that happens to match today is a guess."
  (ensure-frameworks)
  (let ((symbol (cffi:foreign-symbol-pointer name)))
    (unless symbol
      (error "No such framework constant: ~A" name))
    (cffi:mem-ref symbol :pointer)))

(defun nullp (object)
  "True if OBJECT, a pointer or an Objective-C object, is nil."
  (or (null object)
      (cffi:null-pointer-p (if (cffi:pointerp object)
                               object
                               (objc:objc-object-pointer object)))))
