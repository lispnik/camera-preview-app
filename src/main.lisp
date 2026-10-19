;;;; src/main.lisp -- the entry point, for both the binary and the bundle.

(in-package #:camera-preview-app)

(defparameter +usage+
  "camera-preview -- a menu-bar camera preview.

  camera-preview               run until Quit is chosen from the menu
  camera-preview --show        open the preview straight away
  camera-preview --timeout 30  quit after 30 seconds, whatever happens
  camera-preview --cameras     list the cameras and exit
  camera-preview --status      print the camera permission and exit
  camera-preview --help        this

Click the camera icon in the menu bar to see yourself; click again, press
Escape or click elsewhere to put it away.  Right-click for the camera list,
mirroring and Quit.")

(defun %argument (name arguments)
  (second (member name arguments :test #'string=)))

(defun %flag (name arguments)
  (member name arguments :test #'string=))

(defun finish-and-exit (code)
  "Flush and exit.  Inside a bundle standard output is a log file, and what
SB-EXT:EXIT does with a half-full buffer is not something to rely on."
  (finish-output *standard-output*)
  (finish-output *error-output*)
  (sb-ext:exit :code code))

(defun main ()
  "The entry point.  Errors become a message and a non-zero exit, never the
debugger: a menu-bar application has no terminal to show one in."
  (let ((arguments (rest sb-ext:*posix-argv*)))
    (handler-case
        (cond
          ((or (%flag "--help" arguments) (%flag "-h" arguments))
           (write-line +usage+)
           (finish-and-exit 0))
          ((%flag "--status" arguments)
           (format t "~&camera permission: ~(~A~)~%" (authorization-status))
           (finish-and-exit 0))
          ((%flag "--cameras" arguments)
           (dolist (device (video-devices))
             (format t "~A  ~A~%" (device-id device) (device-name device)))
           (finish-and-exit 0))
          (t
           (run :show (%flag "--show" arguments)
                :timeout (let ((seconds (%argument "--timeout" arguments)))
                           (when seconds (parse-integer seconds))))
           (finish-and-exit 0)))
      (stream-error () (sb-ext:exit :code 0 :abort t))
      (error (condition)
        (format *error-output* "~&camera-preview: ~A~%" condition)
        (finish-and-exit 1)))))
