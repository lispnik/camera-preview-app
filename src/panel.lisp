;;;; src/panel.lisp -- the borderless panel the picture hangs in.
;;;;
;;;; Not an NSPopover.  A popover brings an arrow, a material background and a
;;;; margin round its content, and the brief was a plain camera view: here the
;;;; panel IS the picture, corner to corner, with rounded corners and a shadow
;;;; so it reads as a thing that dropped out of the menu bar.
;;;;
;;;; A Lisp subclass of NSPanel, because a borderless window answers NO to
;;;; -canBecomeKeyWindow.  Key status is what makes the panel go away by
;;;; itself: the moment the user clicks anywhere else it resigns key, and the
;;;; delegate hides it.  It is also what delivers Escape, as -cancelOperation:.

(in-package #:camera-preview-app)

(defconstant +style-borderless+ 0)
(defconstant +backing-buffered+ 2)

(defconstant +status-window-level+ 25
  "NSStatusWindowLevel: level with the menu bar, so the panel is not drawn
under some other application's floating window.")

(defconstant +collection-behavior+
  (logior 1      ; CanJoinAllSpaces: wherever you are when you click
          8      ; Transient: not a window Mission Control should arrange
          64     ; IgnoresCycle: not one Cmd-` should reach
          256)   ; FullScreenAuxiliary: over a full-screen meeting app too
  "NSWindowCollectionBehavior for a panel that belongs to the menu bar.")

(defconstant +view-autoresize+ (logior 2 16)
  "NSViewWidthSizable | NSViewHeightSizable.")

(defparameter +corner-radius+ 12d0)

(defvar *panel* nil "The NSPanel, once made.  Reused for every showing.")
(defvar *message* nil "The NSTextField shown instead of a picture, when there is none.")

(objc:define-objc-class preview-panel ()
  ()
  (:objc-class-name "LispCameraPreviewPanel")
  (:objc-superclass-name "NSPanel"))

(objc:define-objc-method ("canBecomeKeyWindow" objc:objc-bool)
    ((self preview-panel))
  t)

(objc:define-objc-method ("cancelOperation:" :void)
    ((self preview-panel) (sender objc:objc-object-pointer))
  (declare (ignore sender))
  (hide-preview :restore-focus t))

(defun text-alignment-center ()
  "NSTextAlignmentCenter, which is not one number.

AppKit's enumeration follows UIKit's values wherever TARGET_ABI_USES_IOS_VALUES
holds, which is everywhere except x86-64: centre is 1 on Apple silicon and 2 on
Intel.  Hard-coding either right-aligns the text on the other machine."
  (if (search "X86" (machine-type)) 2 1))

(defun make-message-label ()
  (let ((label (objc:invoke "NSTextField" "wrappingLabelWithString:" "")))
    (objc:invoke label "setTextColor:" (objc:invoke "NSColor" "whiteColor"))
    (objc:invoke label "setFont:" (objc:invoke "NSFont" "systemFontOfSize:" 15d0))
    (objc:invoke label "setAlignment:" (text-alignment-center))
    (objc:invoke label "setHidden:" t)
    (objc:retain label)))

(defun make-panel (delegate)
  "The panel, empty, with the preview layer inside it.  Not yet on screen."
  (let* ((panel (objc:invoke (objc:invoke "LispCameraPreviewPanel" "alloc")
                             "initWithContentRect:styleMask:backing:defer:"
                             (rect 0 0 480 270) +style-borderless+
                             +backing-buffered+ nil))
         (content (objc:invoke panel "contentView")))
    ;; Lisp owns it; see "-releasedWhenClosed defaults to YES" in objc's notes.
    (objc:invoke panel "setReleasedWhenClosed:" nil)
    (objc:invoke panel "setOpaque:" nil)
    (objc:invoke panel "setBackgroundColor:" (objc:invoke "NSColor" "clearColor"))
    (objc:invoke panel "setHasShadow:" t)
    (objc:invoke panel "setLevel:" +status-window-level+)
    (objc:invoke panel "setCollectionBehavior:" +collection-behavior+)
    ;; Hiding is ours to decide (on resign key), not AppKit's on deactivation:
    ;; while the permission prompt is up the app is inactive and the panel has
    ;; to stay put.
    (objc:invoke panel "setHidesOnDeactivate:" nil)
    ;; Dragged by the picture itself: a borderless window has no title bar to
    ;; grab.  The content view and the layer-hosting view under it both answer
    ;; YES to -mouseDownCanMoveWindow, being non-opaque NSViews, so a press
    ;; anywhere on the panel moves it.
    (objc:invoke panel "setMovableByWindowBackground:" t)
    (objc:invoke panel "setDelegate:" delegate)
    (objc:invoke content "setWantsLayer:" t)
    (let ((layer (objc:invoke content "layer")))
      (objc:invoke layer "setCornerRadius:" +corner-radius+)
      (objc:invoke layer "setMasksToBounds:" t)
      (objc:invoke layer "setBackgroundColor:"
                   (objc:invoke (objc:invoke "NSColor" "blackColor") "CGColor")))
    ;; The preview layer goes in a layer-HOSTING view of its own rather than
    ;; straight into the content view's layer: a layer-backed view owns its
    ;; sublayer order, and a hand-added sublayer can end up drawn over the
    ;; message label.  -setLayer: before -setWantsLayer: is what makes a view
    ;; hosting rather than backed.
    (let ((host (objc:invoke (objc:invoke "NSView" "alloc") "initWithFrame:"
                             (objc:invoke content "bounds"))))
      (objc:invoke host "setLayer:" (ensure-session))
      (objc:invoke host "setWantsLayer:" t)
      (objc:invoke host "setAutoresizingMask:" +view-autoresize+)
      (objc:invoke content "addSubview:" host)
      (objc:release host))
    (setf *message* (make-message-label))
    (objc:invoke content "addSubview:" *message*)
    panel))

(defun ensure-panel (delegate)
  (or *panel* (setf *panel* (make-panel delegate))))

(defun layout-message ()
  "Centre the message label in the panel, wrapping to the panel's width."
  (when (and *panel* *message*)
    (let* ((bounds (objc:invoke (objc:invoke *panel* "contentView") "bounds"))
           (width (- (rect-width bounds) 40))
           (fitted (objc:invoke *message* "sizeThatFits:" (vector width 10000d0)))
           (height (aref fitted 1)))
      (objc:invoke *message* "setPreferredMaxLayoutWidth:" width)
      (objc:invoke *message* "setFrame:"
                   (rect 20 (/ (- (rect-height bounds) height) 2) width height)))))

(defun show-message (text)
  "Show TEXT in the panel in place of the picture, or clear it with NIL."
  (when *message*
    (cond (text
           (objc:invoke *message* "setStringValue:" text)
           (objc:invoke *message* "setHidden:" nil)
           (layout-message))
          (t
           (objc:invoke *message* "setHidden:" t)))))

(defun panel-visible-p ()
  (and *panel* (= 1 (objc:invoke *panel* "isVisible"))))
