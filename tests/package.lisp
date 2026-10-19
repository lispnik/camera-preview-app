;;;; tests/package.lisp

(defpackage #:camera-preview-app/tests
  (:use #:common-lisp #:fiveam #:camera-preview-app)
  ;; Both export RUN; the suite never calls the application's.
  (:shadowing-import-from #:fiveam #:run)
  (:export #:run-tests))

(in-package #:camera-preview-app/tests)

(def-suite camera-preview-app)

(defun run-tests ()
  "Run the suite and return T if every test passed.  FIVEAM:RUN! returns NIL on
failure but ASDF ignores a TEST-OP's value; the caller checks this instead."
  (run! 'camera-preview-app))
