;;;; src/portable.lisp -- the three things SBCL and ECL spell differently.
;;;;
;;;; Everything else here is portable Common Lisp over objc, which runs on both.
;;;; These are the process's edges: its arguments, its exit, and the signal it
;;;; is asked to quit with.

(in-package #:camera-preview-app)

(defun command-arguments ()
  "The arguments after the program name."
  (rest #+sbcl sb-ext:*posix-argv*
        #+ecl (ext:command-args)
        #-(or sbcl ecl) (uiop:raw-command-line-arguments)))

(defun exit-now (code)
  "End the process with CODE immediately: no unwinding, no exit hooks.

_exit(2) through CFFI rather than each implementation's abort option, so it is
the same act on both -- and the only one that is safe from a signal handler or
with -[NSApplication run] on the stack, which a Lisp unwind cannot pass."
  (cffi:foreign-funcall "_exit" :int code :void))

(defun finish-and-exit (code)
  "Flush and exit.  Inside a bundle standard output is a log file, and what an
exit does with a half-full buffer is not something to rely on -- so the buffers
are flushed here, and then nothing else is needed from the Lisp on the way out."
  (finish-output *standard-output*)
  (finish-output *error-output*)
  (exit-now code))

(defun exit-on-sigterm ()
  "Make SIGTERM end the process at once.

SIGTERM is how `kill', launchd, and logout or shutdown ask an application to
quit.  SBCL's own handler answers it with SB-EXT:EXIT, which UNWINDS -- and the
main thread's stack runs through -[NSApplication run], foreign frames a Lisp
unwind cannot pass through.  Measured: the process ignored `kill' outright and
had to be killed with -9, which logout would have waited on.

So the handler exits without unwinding.  Nothing is lost: there is no unsaved
state, preferences are written as they change, and the camera is released by
the kernel when the process goes -- its light is off the moment it exits."
  #+sbcl
  (sb-sys:enable-interrupt sb-unix:sigterm
                           (lambda (signal info context)
                             (declare (ignore signal info context))
                             (exit-now 0)))
  #+ecl
  (ext:set-signal-handler ext:+sigterm+
                          (lambda (&rest arguments)
                            (declare (ignore arguments))
                            (exit-now 0))))

(defun redirect-output-to-log ()
  "Inside an ECL bundle, send output to ~/Library/Logs/<bundle name>.log.

asdf-macos-app's toplevel does this for the SBCL bundle; the ECL bundle is
assembled without it, and a process LaunchServices starts has /dev/null for
standard output -- so without this every line the application writes is lost.
Only when output is not a terminal, so running the executable from a shell
still prints there."
  #+ecl
  (unless (= 1 (cffi:foreign-funcall "isatty" :int 1 :int))
    (let ((name (ignore-errors
                 (objc:invoke-into 'string (objc:invoke "NSBundle" "mainBundle")
                                   "objectForInfoDictionaryKey:" "CFBundleName"))))
      (when (and name (plusp (length name)))
        (let ((stream (open (merge-pathnames (format nil "Library/Logs/~A.log" name)
                                             (user-homedir-pathname))
                            :direction :output :if-exists :append
                            :if-does-not-exist :create)))
          (setf *standard-output* stream
                *error-output* stream))))))
