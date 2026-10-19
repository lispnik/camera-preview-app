;;;; tests/geometry-tests.lisp -- where the panel goes.  No window server needed.

(in-package #:camera-preview-app/tests)

(in-suite camera-preview-app)

;;; A 1512x982 MacBook Pro screen with a 37-point menu bar and no Dock at the
;;; bottom, and a status item near the right-hand end of the bar.
(defparameter *screen* (rect 0 0 1512 982))
(defparameter *visible* (rect 0 0 1512 945))
(defparameter *item* (rect 1300 945 30 37))

(defun right-edge (r) (+ (rect-x r) (rect-width r)))
(defun top-edge (r) (+ (rect-y r) (rect-height r)))

(test a-third-of-the-screen-wide
  (is (= 504 (rect-width (panel-frame *item* *screen* *visible*)))))

(test the-cameras-own-shape
  (let ((wide (panel-frame *item* *screen* *visible* :aspect 16/9))
        (square (panel-frame *item* *screen* *visible* :aspect 4/3)))
    (is (= 284 (rect-height wide)))     ; 504 / (16/9) = 283.5, rounded
    (is (= 378 (rect-height square)))))

(test hangs-just-below-the-item
  (let ((frame (panel-frame *item* *screen* *visible*)))
    (is (= (- 945 6) (top-edge frame)))))

(test centred-under-the-item-when-there-is-room
  (let* ((item (rect 700 945 30 37))
         (frame (panel-frame item *screen* *visible*)))
    (is (= 715 (+ (rect-x frame) (/ (rect-width frame) 2))))))

(test slid-left-to-stay-on-screen
  ;; Centred on x=1315 a 504-wide panel would end at 1567, past the edge.
  (let ((frame (panel-frame *item* *screen* *visible*)))
    (is (= (- 1512 8) (right-edge frame)))))

(test slid-right-near-the-left-edge
  (let ((frame (panel-frame (rect 10 945 30 37) *screen* *visible*)))
    (is (= 8 (rect-x frame)))))

(test shrinks-in-proportion-on-a-short-screen
  ;; A 3440x1440 ultrawide: a third is 1147 wide and 645 high at 16:9, which
  ;; fits; a 9:16 portrait camera at that width would be 2039 high, which does
  ;; not, so it shrinks to the space below the bar and keeps its shape.
  (let* ((screen (rect 0 0 3440 1440))
         (visible (rect 0 70 3440 1345))
         (item (rect 3000 1415 30 25))
         (frame (panel-frame item screen visible :aspect 9/16)))
    (is (= 78 (rect-y frame)))
    (is (< (abs (- (/ (rect-width frame) (rect-height frame)) 9/16)) 0.01))))

(test a-missing-aspect-is-the-default
  (is (equalp (panel-frame *item* *screen* *visible* :aspect nil)
              (panel-frame *item* *screen* *visible* :aspect +default-aspect+))))

(test a-secondary-screen-to-the-left
  ;; Negative coordinates: a screen arranged to the left of the main one.
  (let* ((screen (rect -1920 0 1920 1080))
         (visible (rect -1920 0 1920 1055))
         (item (rect -100 1055 30 25))
         (frame (panel-frame item screen visible)))
    (is (= 640 (rect-width frame)))
    (is (= -8 (right-edge frame)))))

(test dimensions-unpack-width-low
  ;; 1280x720 as CMVideoDimensions comes back as one 64-bit register.
  (multiple-value-bind (width height) (unpack-dimensions (logior 1280 (ash 720 32)))
    (is (= 1280 width))
    (is (= 720 height))))
