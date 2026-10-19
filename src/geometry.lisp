;;;; src/geometry.lisp -- where the panel goes and how big it is.
;;;;
;;;; Pure: rectangles are #(x y width height) vectors of doubles in Cocoa screen
;;;; coordinates -- origin at the bottom left of the main screen, y up -- which
;;;; is exactly what -[NSWindow frame] and -[NSScreen visibleFrame] return
;;;; through objc, and exactly what -setFrame:display: takes.  So nothing here
;;;; converts anything, and the suite can check it without a window server.

(in-package #:camera-preview-app)

(defparameter +screen-fraction+ 1/3
  "How much of the screen's width the preview takes.  The brief said about a
third: big enough to see your hair, small enough not to feel like a mirror on
the wall.")

(defparameter +default-aspect+ 16/9
  "Width over height when the camera has not said.  Every built-in Mac camera
since 2020 is 16:9, so it is the least wrong guess for the instant before the
real format is known.")

(defparameter +gap+ 6d0
  "Points between the bottom of the menu bar item and the top of the panel.")

(defparameter +margin+ 8d0
  "Points the panel keeps clear of the edges of the visible screen.")

(defun rect (x y width height)
  (vector (float x 1d0) (float y 1d0) (float width 1d0) (float height 1d0)))

(defun rect-x (r) (aref r 0))
(defun rect-y (r) (aref r 1))
(defun rect-width (r) (aref r 2))
(defun rect-height (r) (aref r 3))

(defun panel-frame (anchor screen visible &key (aspect +default-aspect+)
                                              (fraction +screen-fraction+)
                                              (gap +gap+) (margin +margin+))
  "The preview panel's frame, hanging below ANCHOR.

ANCHOR is the status item's window frame, SCREEN the full frame of the screen
it is on and VISIBLE that screen's visible frame (less the menu bar and Dock).
ASPECT is the camera's width over its height.

The panel is FRACTION of the screen's width and exactly ASPECT in shape, so the
picture is never letterboxed or cropped.  It is centred under the item and slid
sideways as far as it must be to stay on screen -- the item is usually near the
right-hand edge, and a panel centred on it would hang off.  If the screen is too
short for that height (a very tall camera, a very wide screen) it shrinks, still
in proportion, rather than running into the Dock."
  (let* ((aspect (if (and aspect (plusp aspect)) aspect +default-aspect+))
         (top (- (rect-y anchor) gap))
         (bottom-limit (+ (rect-y visible) margin))
         (left-limit (+ (rect-x visible) margin))
         (right-limit (- (+ (rect-x visible) (rect-width visible)) margin))
         (width (* (rect-width screen) fraction))
         (height (/ width aspect)))
    (when (> height (- top bottom-limit))
      (setf height (max 1 (- top bottom-limit))
            width (* height aspect)))
    (when (> width (- right-limit left-limit))
      (setf width (max 1 (- right-limit left-limit))
            height (/ width aspect)))
    (let* ((centre (+ (rect-x anchor) (/ (rect-width anchor) 2)))
           (x (- centre (/ width 2)))
           (x (min x (- right-limit width)))
           (x (max x left-limit)))
      ;; Whole points: a fractional origin puts the panel's edges, and the
      ;; video inside them, on half pixels, which is a soft picture for nothing.
      ;; The height is rounded BEFORE the origin is taken from it; rounding the
      ;; two separately moves the top edge off the gap by a point.
      (let ((height (round height)))
        (rect (round x) (- (round top) height) (round width) height)))))

(defun unpack-dimensions (packed)
  "(VALUES WIDTH HEIGHT) from a CMVideoDimensions returned as one 64-bit integer.

CMVideoFormatDescriptionGetDimensions returns a struct of two int32s by value,
which CFFI cannot declare without libffi.  But an eight-byte struct of two ints
comes back in a single integer register on both architectures -- x0 on arm64,
RAX on x86-64 -- so declaring the result :UINT64 is the ABI, not a trick, and on
a little-endian machine the first field, the width, is the low half."
  (values (ldb (byte 32 0) packed)
          (ldb (byte 32 32) packed)))

(defun rect-contains-point-p (r x y)
  (and (<= (rect-x r) x (+ (rect-x r) (rect-width r)))
       (<= (rect-y r) y (+ (rect-y r) (rect-height r)))))

(defun moved-frame (left top width height visible &key (margin +margin+))
  "The panel's frame when the user has dragged it: its top-left corner at LEFT,
TOP, WIDTH by HEIGHT, slid back inside VISIBLE as far as it must be.

The top-left corner is what is remembered, not the origin, because the origin
is the BOTTOM left in Cocoa and the height changes with the camera: anchoring
the bottom would make a panel moved under the menu bar grow up into it when a
taller camera was chosen.  Clamped because the screen it was left on may since
have shrunk, moved or been unplugged.  If it is wider or taller than the
screen, the top-left edge wins, which keeps the picture's top -- your face --
in view."
  (let* ((left-limit (+ (rect-x visible) margin))
         (right-limit (- (+ (rect-x visible) (rect-width visible)) margin))
         (bottom-limit (+ (rect-y visible) margin))
         (top-limit (- (+ (rect-y visible) (rect-height visible)) margin))
         (x (max left-limit (min left (- right-limit width))))
         (top (min top-limit (max top (+ bottom-limit height))))
         (height (round height)))
    (rect (round x) (- (round top) height) (round width) height)))
