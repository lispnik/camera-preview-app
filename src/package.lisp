;;;; src/package.lisp

(defpackage #:camera-preview-app
  (:use #:common-lisp)
  (:export
   ;; The pure half: rectangles in, a rectangle out.  No Objective-C here.
   #:rect #:rect-x #:rect-y #:rect-width #:rect-height
   #:panel-frame #:moved-frame #:rect-contains-point-p
   #:+default-aspect+ #:+screen-fraction+
   #:unpack-dimensions
   ;; The camera.
   #:authorization-status #:video-devices #:device-name #:device-id
   ;; Starting at login.
   #:login-item-status #:login-item-available-p
   #:register-login-item #:unregister-login-item #:bundle-path
   ;; The application.
   #:run #:main))
