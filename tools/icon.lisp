;;;; tools/icon.lisp -- the application icon, drawn with the objc bindings.
;;;;
;;;; A build tool, loaded by `make icon' and never part of the dumped image.
;;;; The artwork is code: a rounded plate with a gradient, and the SF Symbol the
;;;; menu bar item uses, drawn large in white -- so the icon in Finder and the
;;;; icon in the menu bar are visibly the same thing.
;;;;
;;;; Drawing offscreen means supplying the graphics context by hand; NSColor,
;;;; NSBezierPath and NSImage all draw into whatever context is current, and
;;;; without -setCurrentContext: they silently draw nowhere.

(defpackage #:camera-preview-icon
  (:use #:common-lisp)
  (:export #:render-icon))

(in-package #:camera-preview-icon)

(defun ensure-appkit ()
  (objc:ensure-objc-initialized
   :modules '("/System/Library/Frameworks/AppKit.framework/Versions/C/AppKit")))

(defun color (red green blue &optional (alpha 1))
  (objc:invoke "NSColor" "colorWithSRGBRed:green:blue:alpha:"
               (float red 1d0) (float green 1d0) (float blue 1d0) (float alpha 1d0)))

(defun rect (x y width height)
  (vector (float x 1d0) (float y 1d0) (float width 1d0) (float height 1d0)))

(defun draw-plate (size)
  "The rounded square.  macOS does not mask an application icon, so the corners
have to be drawn, inset by the grid's margin like every other icon in the Dock."
  (let* ((inset (* size 0.1))
         (path (objc:invoke "NSBezierPath" "bezierPathWithRoundedRect:xRadius:yRadius:"
                            (rect inset inset (- size (* 2 inset)) (- size (* 2 inset)))
                            (float (* size 0.18) 1d0) (float (* size 0.18) 1d0)))
         (gradient (objc:invoke (objc:invoke "NSGradient" "alloc")
                                "initWithStartingColor:endingColor:"
                                (color 0.20 0.55 0.95) (color 0.10 0.22 0.55))))
    ;; 270 degrees: light at the top, as if lit from above.
    (objc:invoke gradient "drawInBezierPath:angle:" path 270d0)
    (objc:release gradient)))

(defun draw-symbol (size name)
  "SF Symbol NAME in white, centred, about half the plate across."
  (let* ((configuration
           (objc:invoke
            (objc:invoke "NSImageSymbolConfiguration" "configurationWithPointSize:weight:"
                         (float (* size 0.36) 1d0) 0.3d0) ; NSFontWeightSemibold
            "configurationByApplyingConfiguration:"
            (objc:invoke "NSImageSymbolConfiguration" "configurationWithHierarchicalColor:"
                         (color 1 1 1))))
         (image (objc:invoke
                 (objc:invoke "NSImage" "imageWithSystemSymbolName:accessibilityDescription:"
                              name nil)
                 "imageWithSymbolConfiguration:" configuration))
         (extent (objc:invoke image "size"))
         (width (aref extent 0))
         (height (aref extent 1)))
    (objc:invoke image "drawInRect:"
                 (rect (/ (- size width) 2) (/ (- size height) 2) width height))))

(defun render-icon (path &key (size 1024))
  "Draw the icon at SIZE x SIZE and write it to PATH as a PNG.  Returns PATH."
  (ensure-appkit)
  (objc:with-autorelease-pool ()
    (let ((rep (objc:invoke (objc:invoke "NSBitmapImageRep" "alloc")
                            "initWithBitmapDataPlanes:pixelsWide:pixelsHigh:bitsPerSample:samplesPerPixel:hasAlpha:isPlanar:colorSpaceName:bytesPerRow:bitsPerPixel:"
                            (cffi:null-pointer) size size 8 4 t nil
                            "NSCalibratedRGBColorSpace" 0 0)))
      (objc:invoke "NSGraphicsContext" "saveGraphicsState")
      (unwind-protect
           (progn
             (objc:invoke "NSGraphicsContext" "setCurrentContext:"
                          (objc:invoke "NSGraphicsContext"
                                       "graphicsContextWithBitmapImageRep:" rep))
             (draw-plate size)
             (draw-symbol size "camera.fill"))
        (objc:invoke "NSGraphicsContext" "restoreGraphicsState"))
      (let ((data (objc:invoke rep "representationUsingType:properties:"
                               4 (objc:invoke "NSDictionary" "dictionary")))) ; PNG
        (ensure-directories-exist path)
        (unless (= 1 (objc:invoke data "writeToFile:atomically:"
                                  (namestring (merge-pathnames path)) t))
          (error "Could not write ~A" path)))
      (objc:release rep)))
  path)
