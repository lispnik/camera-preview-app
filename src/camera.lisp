;;;; src/camera.lisp -- the capture session and its preview layer.
;;;;
;;;; The picture is an AVCaptureVideoPreviewLayer: AVFoundation draws the
;;;; camera's frames straight into a Core Animation layer on its own threads, so
;;;; not one frame passes through Lisp.  What Lisp does is choose the device,
;;;; start and stop the session, and read the format's shape.
;;;;
;;;; TWO THINGS HERE ARE NOT OBVIOUS.
;;;;
;;;; -startRunning BLOCKS, for most of a second while the camera powers up, and
;;;; AVFoundation says not to call it on the main thread.  So both it and
;;;; -stopRunning are sent from an NSOperationQueue -- but as NSInvocationOperations
;;;; aimed at the session itself, so the background thread runs only
;;;; AVFoundation's code and never enters Lisp.  A Lisp block on that queue
;;;; would work too, until the collector ran on the main thread while it was
;;;; parked; see "Only one libdispatch worker thread" in objc's CLAUDE.md.  One
;;;; operation at a time, so a quick show-hide-show is start, stop, start in that
;;;; order rather than whichever thread wins.
;;;;
;;;; Permission is asked for without a completion handler.  On macOS, creating
;;;; the device input for an app that has never been asked brings up the
;;;; system's prompt by itself; the handler-taking API would mean a Lisp block
;;;; called on an arbitrary queue, for news a timer on the main thread can read
;;;; just as well.  See POLL-AUTHORIZATION in app.lisp.

(in-package #:camera-preview-app)

(defvar *session* nil "The AVCaptureSession, once made.  Kept for the life of the process.")
(defvar *input* nil "The AVCaptureDeviceInput currently attached, or NIL.")
(defvar *preview-layer* nil "The AVCaptureVideoPreviewLayer showing *SESSION*.")
(defvar *session-queue* nil "The serial NSOperationQueue that starts and stops it.")
(defvar *mirrored* t "Whether the picture is shown as a mirror.  See SET-MIRRORED.")

(defparameter +camera-key+ "CameraUniqueID"
  "The user-defaults key holding the chosen camera's unique ID.")

(defparameter +mirror-key+ "MirrorImage"
  "The user-defaults key holding whether to mirror.")

;;; Devices and permission --------------------------------------------------------

(defun media-type-video ()
  (framework-constant "AVMediaTypeVideo"))

(defun authorization-status ()
  "This process's camera permission: :NOT-DETERMINED, :RESTRICTED, :DENIED or
:AUTHORIZED.

Not a property of the app alone: a loose binary run from Terminal is judged as
Terminal, which is one reason the bundle is the real build."
  (ensure-frameworks)
  (case (objc:invoke "AVCaptureDevice" "authorizationStatusForMediaType:"
                     (media-type-video))
    (0 :not-determined)
    (1 :restricted)
    (2 :denied)
    (3 :authorized)
    (t :unknown)))

(defun video-devices ()
  "Every camera, as a list of AVCaptureDevice pointers.

+devicesWithMediaType: is deprecated in favour of a discovery session, which
needs the device TYPES named up front -- and the names have changed twice
(External, ExternalUnknown, ContinuityCamera) across the systems this runs on.
The deprecated call simply returns everything, which is what a list of cameras
to choose from wants."
  (ensure-frameworks)
  (let ((array (objc:invoke "AVCaptureDevice" "devicesWithMediaType:"
                            (media-type-video))))
    (loop for i below (objc:invoke array "count")
          collect (objc:invoke array "objectAtIndex:" i))))

(defun device-name (device)
  (objc:ns-string-to-string (objc:invoke device "localizedName")))

(defun device-id (device)
  (objc:ns-string-to-string (objc:invoke device "uniqueID")))

;;; Preferences --------------------------------------------------------------------

(defun defaults ()
  (objc:invoke "NSUserDefaults" "standardUserDefaults"))

(defun saved-camera-id ()
  (let ((value (objc:invoke (defaults) "stringForKey:" +camera-key+)))
    (unless (nullp value)
      (objc:ns-string-to-string value))))

(defun save-camera-id (id)
  (objc:invoke (defaults) "setObject:forKey:" id +camera-key+))

(defun load-mirror-preference ()
  "Read the mirror preference into *MIRRORED*; unset means mirrored.

A mirror is what a person checking their face expects -- raise your right hand
and the hand on the right of the picture goes up.  The unmirrored picture is
what the meeting will see, and is one menu item away."
  (setf *mirrored*
        (if (nullp (objc:invoke (defaults) "objectForKey:" +mirror-key+))
            t
            (= 1 (objc:invoke (defaults) "boolForKey:" +mirror-key+)))))

(defun chosen-device ()
  "The camera to show: the one last chosen if it is still plugged in, else the
system's default, else the first there is.  NIL if there are none."
  (ensure-frameworks)
  (let ((id (saved-camera-id)))
    (or (and id
             (let ((device (objc:invoke "AVCaptureDevice" "deviceWithUniqueID:" id)))
               (unless (nullp device) device)))
        (let ((device (objc:invoke "AVCaptureDevice" "defaultDeviceWithMediaType:"
                                   (media-type-video))))
          (unless (nullp device) device))
        (first (video-devices)))))

;;; The session ----------------------------------------------------------------------

(defun ensure-session ()
  "Make the session, its preview layer and its queue, once.  Returns the layer."
  (ensure-frameworks)
  (unless *session*
    (setf *session* (objc:alloc-init-object "AVCaptureSession"))
    ;; alloc/init rather than +layerWithSession:, so the layer is ours (+1) and
    ;; not an autoreleased object that happens to survive while a superlayer
    ;; holds it.
    (setf *preview-layer* (objc:invoke (objc:invoke "AVCaptureVideoPreviewLayer" "alloc")
                                       "initWithSession:" *session*))
    ;; Fill, not fit.  The panel is made in the camera's own shape, so the two
    ;; agree to the point; Fill means a rounding difference between them crops a
    ;; pixel rather than drawing a hairline of black down one side.
    (objc:invoke *preview-layer* "setVideoGravity:"
                 (framework-constant "AVLayerVideoGravityResizeAspectFill"))
    (setf *session-queue* (objc:alloc-init-object "NSOperationQueue"))
    (objc:invoke *session-queue* "setMaxConcurrentOperationCount:" 1)
    (load-mirror-preference))
  *preview-layer*)

(defun current-device ()
  "The device attached to the session, or NIL."
  (when *input*
    (objc:invoke *input* "device")))

(defun attach-device (device)
  "Make DEVICE the session's only input.  Returns T if it was attached.

Fails -- NIL, and no input -- when the camera is not ours to use yet, which is
the normal state of affairs the first time: this call is what brings up the
permission prompt, and it answers before the user has."
  (ensure-session)
  (objc:invoke *session* "beginConfiguration")
  (unwind-protect
       (progn
         (when *input*
           (objc:invoke *session* "removeInput:" *input*)
           (objc:release *input*)
           (setf *input* nil))
         (when device
           (let ((input (objc:invoke (objc:invoke "AVCaptureDeviceInput" "alloc")
                                     "initWithDevice:error:"
                                     device (cffi:null-pointer))))
             (cond ((nullp input) nil)
                   ((= 1 (objc:invoke *session* "canAddInput:" input))
                    (objc:invoke *session* "addInput:" input)
                    (setf *input* input))
                   (t (objc:release input))))))
    (objc:invoke *session* "commitConfiguration"))
  (when *input*
    (apply-mirroring)
    t))

(defun ensure-device-attached ()
  "Attach the chosen camera unless one already is.  Returns T if one is."
  (or (and *input* t)
      (attach-device (chosen-device))))

(defun apply-mirroring ()
  "Push *MIRRORED* to the preview layer's connection.

The connection exists only once an input is attached, which is why this is
called from ATTACH-DEVICE and not once at start-up.  Automatic adjustment has to
be switched off first or setting the flag raises an NSException."
  (when *preview-layer*
    (let ((connection (objc:invoke *preview-layer* "connection")))
      (unless (or (nullp connection)
                  (zerop (objc:invoke connection "isVideoMirroringSupported")))
        (objc:invoke connection "setAutomaticallyAdjustsVideoMirroring:" nil)
        (objc:invoke connection "setVideoMirrored:" *mirrored*)))))

(defun set-mirrored (mirrored)
  (setf *mirrored* (and mirrored t))
  (objc:invoke (defaults) "setBool:forKey:" *mirrored* +mirror-key+)
  (apply-mirroring))

(defun camera-aspect ()
  "The attached camera's width over its height, or NIL if none is attached.

Read from the device's active format, which the session sets from its preset
when the input is added -- so it is the shape of the frames actually being
drawn, not of the largest format the camera could do."
  (let ((device (current-device)))
    (when (and device (not (nullp device)))
      (let ((description (objc:invoke (objc:invoke device "activeFormat")
                                      "formatDescription")))
        (unless (nullp description)
          (multiple-value-bind (width height)
              (unpack-dimensions
               ;; A plain C call, so the trap masking objc does around every
               ;; send is ours to do here.
               (float-features:with-float-traps-masked (:invalid :divide-by-zero)
                 (cffi:foreign-funcall "CMVideoFormatDescriptionGetDimensions"
                                       :pointer description :uint64)))
            (when (and (plusp width) (plusp height))
              (/ width height))))))))

(defun %session-operation (selector)
  "Send SELECTOR to the session from the session queue.  See the header."
  (let ((operation (objc:invoke (objc:invoke "NSInvocationOperation" "alloc")
                                "initWithTarget:selector:object:"
                                *session* (objc:coerce-to-selector selector)
                                (cffi:null-pointer))))
    (objc:invoke *session-queue* "addOperation:" operation)
    (objc:release operation)))

(defun start-camera ()
  "Start the session, off the main thread.  The camera's light comes on."
  (when (and *session* *input*)
    (%session-operation "startRunning")))

(defun stop-camera ()
  "Stop the session, off the main thread.  The camera's light goes off.

Stopped every time the panel is put away, not merely hidden: a camera light
that stays on after you have looked is the one thing this application must not
do."
  (when *session*
    (%session-operation "stopRunning")))

(defun wait-for-camera ()
  "Block until queued starts and stops have run.  For quitting: the process
must not exit with the camera still on its way down."
  (when *session-queue*
    (objc:invoke *session-queue* "waitUntilAllOperationsAreFinished")))
