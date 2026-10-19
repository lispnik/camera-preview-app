;;;; src/package.lisp

(defpackage #:camera-preview-app
  (:use #:common-lisp)
  (:export
   ;; The pure half: rectangles in, a rectangle out.  No Objective-C here.
   #:rect #:rect-x #:rect-y #:rect-width #:rect-height
   #:panel-frame #:+default-aspect+ #:+screen-fraction+
   #:unpack-dimensions
   ;; The camera.
   #:authorization-status #:video-devices #:device-name #:device-id
   ;; The application.
   #:run #:main))
