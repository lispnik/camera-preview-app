;;;; src/main.lisp -- the entry point, for both the binary and the bundle.

(in-package #:camera-preview-app)

(defparameter +usage+
  "camera-preview -- a menu-bar camera preview.

  camera-preview                 run until Quit is chosen from the menu
  camera-preview --show          open the preview straight away
  camera-preview --timeout 30    quit after 30 seconds, whatever happens
  camera-preview --cameras       list the cameras and exit
  camera-preview --status        print the camera permission and exit
  camera-preview --login-status  say whether it starts at login, and exit
  camera-preview --login-add     start it at login, and exit
  camera-preview --login-remove  stop starting it at login, and exit
  camera-preview --help          this

Click the camera icon in the menu bar to see yourself; click again, press
Escape or click elsewhere to put it away.  Right-click for the camera list,
mirroring, Start at Login and Quit.")

(defun %argument (name arguments)
  (second (member name arguments :test #'string=)))

(defun %flag (name arguments)
  (member name arguments :test #'string=))

(defun main ()
  "The entry point.  Errors become a message and a non-zero exit, never the
debugger: a menu-bar application has no terminal to show one in."
  (ensure-frameworks)
  (redirect-output-to-log)
  (let ((arguments (command-arguments)))
    (handler-case
        (cond
          ((or (%flag "--help" arguments) (%flag "-h" arguments))
           (write-line +usage+)
           (finish-and-exit 0))
          ((%flag "--status" arguments)
           (format t "~&camera permission: ~(~A~)~%" (authorization-status))
           (finish-and-exit 0))
          ((%flag "--login-status" arguments)
           (format t "~&login item: ~(~A~)~%" (login-item-status))
           (finish-and-exit 0))
          ((%flag "--login-add" arguments)
           (format t "~&login item: ~(~A~)~%" (register-login-item))
           (finish-and-exit 0))
          ((%flag "--login-remove" arguments)
           (format t "~&login item: ~(~A~)~%" (unregister-login-item))
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
      (stream-error () (exit-now 0))
      (error (condition)
        (format *error-output* "~&camera-preview: ~A~%" condition)
        (finish-and-exit 1)))))
