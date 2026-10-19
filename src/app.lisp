;;;; src/app.lisp -- the menu-bar item, and showing and hiding the preview.
;;;;
;;;; Left click toggles the preview; right click (or control-click) opens a menu.
;;;; A status item with a menu set never sends its action, so the menu is NOT
;;;; set on the item: the button acts on both mouse buttons, and the action
;;;; decides which one it was and, for the right one, sets the menu just long
;;;; enough to open it.
;;;;
;;;; The rules from utc-status-app hold here too and are not repeated at length:
;;;; the application must be an Accessory or the item's clicks go nowhere; it
;;;; must run under -[NSApplication run], not a pump loop, or menu tracking
;;;; starves; timers go in the common modes or they freeze while a menu is
;;;; open; and -stop: needs an event posted behind it before -run notices.

(in-package #:camera-preview-app)

(defconstant +activation-policy-accessory+ 1)
(defparameter +square-status-item-length+ -2d0 "NSSquareStatusItemLength.")
(defparameter +run-loop-common-modes+ "kCFRunLoopCommonModes")

(defconstant +event-mask-left-mouse-up+ (ash 1 2))
(defconstant +event-mask-right-mouse-down+ (ash 1 3))
(defconstant +event-type-right-mouse-down+ 3)
(defconstant +modifier-control+ (ash 1 18))

(defparameter +poll-seconds+ 0.5d0
  "How often the camera permission is re-read while the user is being asked.")

(defparameter +reshow-guard-seconds+ 0.3
  "How soon after the panel hid itself a click on the item is taken to be the
click that hid it.  See STATUS-ITEM-CLICKED.")

(defparameter +privacy-settings-url+
  "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")

(defvar *controller* nil "The CONTROLLER instance; AppKit's target and delegate.")
(defvar *status-item* nil "The NSStatusItem, while running.")
(defvar *poll-timer* nil "The NSTimer watching for a permission answer, or NIL.")
(defvar *hidden-at* 0 "INTERNAL-REAL-TIME the panel last hid itself on losing key.")
(defvar *menu-devices* '() "The cameras listed in the open menu, by tag.")

;;; Menu item tags.  Cameras take 0 upwards.
(defconstant +tag-mirror+ -1)

(objc:define-objc-class controller ()
  ()
  (:objc-class-name "LispCameraPreviewController"))

(defun target () (objc:objc-object-pointer *controller*))
(defun app () (objc:invoke "NSApplication" "sharedApplication"))
(defun button () (objc:invoke *status-item* "button"))

;;; The log --------------------------------------------------------------------------

(defun note (control &rest arguments)
  "One timestamped line to standard output, which in the bundle is
~/Library/Logs/Camera Preview.log.  Flushed at once: the line that matters is
the last one before something went wrong."
  (multiple-value-bind (s m h) (decode-universal-time (get-universal-time))
    (format t "~&~2,'0D:~2,'0D:~2,'0D ~?~%" h m s control arguments))
  (finish-output))

;;; Showing and hiding ------------------------------------------------------------

(defun message-for (status)
  "What to say in the panel instead of a picture, or NIL for nothing."
  (case status
    (:not-determined
     "Allow Camera Preview to use the camera, in the dialog macOS is showing.")
    ((:denied :restricted)
     (format nil "Camera access is turned off.~%~
                  Turn on Camera Preview in System Settings › Privacy & Security › Camera ~
                  -- right-click the menu bar icon for a shortcut."))
    (t nil)))

(defun place-panel ()
  "Size the panel to the camera and hang it under the status item."
  (let* ((item-window (objc:invoke (button) "window"))
         (screen (let ((screen (objc:invoke item-window "screen")))
                   (if (nullp screen)
                       (objc:invoke "NSScreen" "mainScreen")
                       screen))))
    (objc:invoke *panel* "setFrame:display:"
                 (panel-frame (objc:invoke item-window "frame")
                              (objc:invoke screen "frame")
                              (objc:invoke screen "visibleFrame")
                              :aspect (or (camera-aspect) +default-aspect+))
                 t)
    (layout-message)))

(defun activate-application ()
  "Make this the active application, so the panel can be key.

-activateIgnoringOtherApps: is deprecated from macOS 14 in favour of the
cooperative -activate, which is sent where it exists.  A click on our own status
item is exactly the user action cooperative activation honours."
  (let ((app (app)))
    (if (objc:can-invoke-p app "activate")
        (objc:invoke app "activate")
        (objc:invoke app "activateIgnoringOtherApps:" t))))

(defun show-preview ()
  "Put the panel on screen with the camera running in it."
  (ensure-panel (target))
  (let ((status (authorization-status)))
    (note "show: permission ~(~A~), camera ~:[not attached~;attached~]"
          status *input*)
    (cond ((member status '(:denied :restricted))
           (show-message (message-for status)))
          ((ensure-device-attached)
           (show-message (message-for status)))
          ((null (video-devices))
           (show-message "No camera is connected."))
          (t
           (show-message (message-for status))))
    (place-panel)
    (activate-application)
    (objc:invoke *panel* "makeKeyAndOrderFront:" (cffi:null-pointer))
    (objc:invoke (button) "highlight:" t)
    (note "shown at ~S, visible ~A, key ~A, aspect ~A"
          (objc:invoke *panel* "frame") (objc:invoke *panel* "isVisible")
          (objc:invoke *panel* "isKeyWindow") (camera-aspect))
    (start-camera)
    (when (eq status :not-determined)
      (start-polling))))

(defun hide-preview (&key restore-focus)
  "Take the panel off screen and turn the camera off.

RESTORE-FOCUS hands the keyboard back to whichever application had it, for a
panel dismissed by Escape or by the item: activating to show the panel took it,
and nothing else would give it back.  Not wanted when the panel is hiding
because the user clicked into another application, which already has it."
  (when (panel-visible-p)
    (note "hide~:[~; (restoring focus)~]" restore-focus)
    (objc:invoke *panel* "orderOut:" (cffi:null-pointer))
    (stop-camera)
    (when *status-item*
      (objc:invoke (button) "highlight:" nil))
    (when restore-focus
      (objc:invoke (app) "hide:" (cffi:null-pointer)))))

;;; Waiting for permission ---------------------------------------------------------

(defun start-polling ()
  (unless *poll-timer*
    (setf *poll-timer*
          (objc:invoke "NSTimer"
                       "timerWithTimeInterval:target:selector:userInfo:repeats:"
                       +poll-seconds+ (target)
                       (objc:coerce-to-selector "pollAuthorization:")
                       (cffi:null-pointer) t))
    (objc:invoke (objc:invoke "NSRunLoop" "currentRunLoop") "addTimer:forMode:"
                 *poll-timer* +run-loop-common-modes+)))

(defun stop-polling ()
  (when *poll-timer*
    (objc:invoke *poll-timer* "invalidate")
    (setf *poll-timer* nil)))

(objc:define-objc-method ("pollAuthorization:" :void)
    ((self controller) (timer objc:objc-object-pointer))
  (declare (ignore timer))
  ;; The answer arrives in another process; this is where it is noticed.  On a
  ;; yes the input is made again -- the one made while the question was open
  ;; may be attached to nothing -- and the session restarted, so the picture
  ;; appears without the user having to click again.
  (let ((status (authorization-status)))
    (unless (eq status :not-determined)
      (note "permission answered: ~(~A~)" status)
      (stop-polling)
      (when (eq status :authorized)
        (attach-device (chosen-device)))
      (when (panel-visible-p)
        (show-message (message-for status))
        (place-panel)
        (stop-camera)
        (start-camera)
        (activate-application)
        (objc:invoke *panel* "makeKeyAndOrderFront:" (cffi:null-pointer))))))

;;; The status item and its delegate methods ---------------------------------------

(defun right-click-p ()
  (let ((event (objc:invoke (app) "currentEvent")))
    (and (not (nullp event))
         (or (= (objc:invoke event "type") +event-type-right-mouse-down+)
             (logtest (objc:invoke event "modifierFlags") +modifier-control+)))))

(objc:define-objc-method ("statusItemClicked:" :void)
    ((self controller) (sender objc:objc-object-pointer))
  (declare (ignore sender))
  (note "click: ~:[left~;right~], panel ~:[hidden~;visible~]"
        (right-click-p) (panel-visible-p))
  (cond ((right-click-p)
         (open-menu))
        ((panel-visible-p)
         (hide-preview :restore-focus t))
        ;; Pressing the item while the panel is up may cost the panel key status
        ;; BEFORE the action arrives, depending on the system: the panel has
        ;; already hidden itself, and showing it again would make the click
        ;; that should close it reopen it instead.
        ((< (/ (- (get-internal-real-time) *hidden-at*)
               internal-time-units-per-second)
            +reshow-guard-seconds+))
        (t
         (show-preview))))

(objc:define-objc-method ("showPreview:" :void)
    ((self controller) (sender objc:objc-object-pointer))
  (declare (ignore sender))
  (show-preview))

(objc:define-objc-method ("windowDidResignKey:" :void)
    ((self controller) (notification objc:objc-object-pointer))
  (declare (ignore notification))
  (note "panel lost key")
  ;; Except while macOS is asking about the camera: its dialog is another
  ;; process's window, taking key from ours, and the user is about to want the
  ;; picture that answering it produces.
  (unless (eq (authorization-status) :not-determined)
    (when (panel-visible-p)
      (setf *hidden-at* (get-internal-real-time))
      (hide-preview))))

;;; The menu ------------------------------------------------------------------------

(defun %menu-item (title action &key (tag 0) (key "") (state 0))
  (let ((item (objc:invoke (objc:invoke "NSMenuItem" "alloc")
                           "initWithTitle:action:keyEquivalent:"
                           title
                           (if action (objc:coerce-to-selector action) (cffi:null-pointer))
                           key)))
    (when action (objc:invoke item "setTarget:" (target)))
    (objc:invoke item "setTag:" tag)
    (objc:invoke item "setState:" state)
    (objc:autorelease item)))

(defun build-menu ()
  "The right-click menu, made fresh each time so the camera list is current."
  (let ((menu (objc:autorelease (objc:alloc-init-object "NSMenu")))
        (current (let ((device (current-device)))
                   (and device (not (nullp device)) (device-id device))))
        (devices (video-devices)))
    (setf *menu-devices* devices)
    (if devices
        (loop for device in devices
              for index from 0
              do (objc:invoke menu "addItem:"
                              (%menu-item (device-name device) "selectCamera:"
                                          :tag index
                                          :state (if (equal (device-id device) current)
                                                     1 0))))
        (let ((item (%menu-item "No Camera" nil)))
          (objc:invoke item "setEnabled:" nil)
          (objc:invoke menu "addItem:" item)))
    (objc:invoke menu "addItem:" (objc:invoke "NSMenuItem" "separatorItem"))
    (objc:invoke menu "addItem:" (%menu-item "Mirror Image" "toggleMirror:"
                                             :tag +tag-mirror+
                                             :state (if *mirrored* 1 0)))
    (objc:invoke menu "addItem:" (%menu-item "Camera Privacy Settings…"
                                             "openPrivacySettings:"))
    (objc:invoke menu "addItem:" (objc:invoke "NSMenuItem" "separatorItem"))
    (objc:invoke menu "addItem:" (%menu-item "Quit Camera Preview" "quit:" :key "q"))
    menu))

(defun open-menu ()
  "Open the menu under the item, the way a status item's own menu opens.

-performClick: on an item that HAS a menu opens it, positioned and styled by
AppKit, and returns once it is dismissed -- so the menu is attached for exactly
that long and the next left click is an action again."
  (objc:invoke *status-item* "setMenu:" (build-menu))
  (objc:invoke (button) "performClick:" (cffi:null-pointer))
  (objc:invoke *status-item* "setMenu:" (cffi:null-pointer)))

(objc:define-objc-method ("selectCamera:" :void)
    ((self controller) (sender objc:objc-object-pointer))
  (let ((device (nth (objc:invoke sender "tag") *menu-devices*)))
    (when device
      (save-camera-id (device-id device))
      (when (attach-device device)
        (when (panel-visible-p)
          ;; A different camera may be a different shape.
          (place-panel)
          (start-camera))))))

(objc:define-objc-method ("toggleMirror:" :void)
    ((self controller) (sender objc:objc-object-pointer))
  (declare (ignore sender))
  (set-mirrored (not *mirrored*)))

(objc:define-objc-method ("openPrivacySettings:" :void)
    ((self controller) (sender objc:objc-object-pointer))
  (declare (ignore sender))
  (objc:invoke (objc:invoke "NSWorkspace" "sharedWorkspace") "openURL:"
               (objc:invoke "NSURL" "URLWithString:" +privacy-settings-url+)))

(objc:define-objc-method ("quit:" :void)
    ((self controller) (sender objc:objc-object-pointer))
  (declare (ignore sender))
  (stop-the-application))

;;; Running ---------------------------------------------------------------------------

(defun stop-the-application ()
  "End -[NSApplication run], camera off first."
  (hide-preview)
  (stop-polling)
  (stop-camera)
  (wait-for-camera)
  (let ((app (app)))
    (objc:invoke app "stop:" (cffi:null-pointer))
    (objc:invoke app "postEvent:atStart:"
                 (objc:invoke "NSEvent"
                              "otherEventWithType:location:modifierFlags:timestamp:windowNumber:context:subtype:data1:data2:"
                              15         ; NSEventTypeApplicationDefined
                              #(0d0 0d0)
                              0 0d0 0 (cffi:null-pointer) 0 0 0)
                 t))
  (values))

(defun make-status-item ()
  (let ((item (objc:invoke (objc:invoke "NSStatusBar" "systemStatusBar")
                           "statusItemWithLength:" +square-status-item-length+)))
    (let ((button (objc:invoke item "button"))
          (image (objc:invoke "NSImage" "imageWithSystemSymbolName:accessibilityDescription:"
                              "camera.fill" "Camera Preview")))
      ;; A template image, so it is drawn in the menu bar's own colour, light or
      ;; dark, and inverted when highlighted -- as every system item is.
      (objc:invoke image "setTemplate:" t)
      (objc:invoke button "setImage:" image)
      (objc:invoke button "setToolTip:" "Camera Preview")
      (objc:invoke button "setTarget:" (target))
      (objc:invoke button "setAction:" (objc:coerce-to-selector "statusItemClicked:"))
      ;; Left on mouse UP, as a status item's own action is.  Shown on mouse
      ;; down, the panel became key and then lost it again as the button
      ;; finished tracking the click, and hid itself before it was seen.
      ;; Right on mouse down, as a menu opens.
      (objc:invoke button "sendActionOn:" (logior +event-mask-left-mouse-up+
                                                  +event-mask-right-mouse-down+)))
    item))

(defun run (&key timeout show)
  "Put the camera icon in the menu bar and run until Quit.  Returns T.

Must be called on thread 1.  TIMEOUT, in seconds, quits anyway, so a test or a
demo cannot wedge.  SHOW opens the preview as soon as the item is up."
  (ensure-frameworks)
  (objc.runloop:shared-application)
  (objc.runloop:set-activation-policy +activation-policy-accessory+)
  (setf *controller* (make-instance 'controller)
        *status-item* (make-status-item))
  (ensure-session)
  (note "started; permission ~(~A~), camera ~A" (authorization-status)
        (let ((device (chosen-device))) (if device (device-name device) "none")))
  (when show
    ;; After a moment, not now: until the run loop has turned once the status
    ;; item's window has no frame, and the panel would be placed at the origin.
    (objc:invoke (target) "performSelector:withObject:afterDelay:"
                 (objc:coerce-to-selector "showPreview:") (cffi:null-pointer) 0.3d0))
  (when timeout
    (objc:invoke "NSTimer" "scheduledTimerWithTimeInterval:target:selector:userInfo:repeats:"
                 (float timeout 1d0) (target) (objc:coerce-to-selector "quit:")
                 (cffi:null-pointer) nil))
  (unwind-protect
       (objc:invoke (app) "run")
    (stop-camera)
    (wait-for-camera)
    (when *status-item*
      (objc:invoke (objc:invoke "NSStatusBar" "systemStatusBar")
                   "removeStatusItem:" *status-item*)
      (setf *status-item* nil)))
  t)
