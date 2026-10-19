;;;; src/login-item.lisp -- starting at login.
;;;;
;;;; Ported from utc-status-app, where the reasons below were found the hard way.
;;;;
;;;; THERE IS NO Info.plist KEY FOR THIS.  A login item is not declared, it is
;;;; REGISTERED at run time by the application itself.
;;;;
;;;; LSSharedFileList RATHER THAN SMAppService.  SMAppService is the API Apple
;;;; documents for macOS 13 and later, and -[SMAppService mainAppService]
;;;; answered NotFound for an SBCL bundle in every arrangement utc-status tried
;;;; -- unsigned, Developer ID, notarised, from ~/Applications and from
;;;; /Applications.  Hammerspoon and Syncthing do login items this way and
;;;; neither links ServiceManagement.  Deprecated since 10.11, and it works.
;;;;
;;;; These are C functions, not messages, so CFFI makes the calls.  The types are
;;;; toll-free bridged -- a CFURLRef is an NSURL, a CFArrayRef an NSArray -- so
;;;; everything else is ordinary INVOKE.

(in-package #:camera-preview-app)

(cffi:defcfun ("LSSharedFileListCreate" %shared-file-list-create) :pointer
  (allocator :pointer) (list-type :pointer) (options :pointer))

(cffi:defcfun ("LSSharedFileListInsertItemURL" %shared-file-list-insert) :pointer
  (list :pointer) (after :pointer) (display-name :pointer) (icon :pointer)
  (url :pointer) (properties :pointer) (property-values :pointer))

(cffi:defcfun ("LSSharedFileListCopySnapshot" %shared-file-list-snapshot) :pointer
  (list :pointer) (seed :pointer))

(cffi:defcfun ("LSSharedFileListItemCopyResolvedURL" %shared-file-list-item-url) :pointer
  (item :pointer) (flags :uint32) (error :pointer))

(cffi:defcfun ("LSSharedFileListItemRemove" %shared-file-list-item-remove) :int
  (list :pointer) (item :pointer))

(cffi:defcfun ("CFRelease" %cf-release) :void (object :pointer))

(defun %global (name)
  "The value of an exported CFTypeRef global, or a null pointer.  The symbol's
address is dereferenced: it is the location of the constant, not the constant."
  (let ((address (cffi:foreign-symbol-pointer name)))
    (if address (cffi:mem-ref address :pointer) (cffi:null-pointer))))

(defun bundle-path ()
  "This application's .app directory, or NIL when it is not in one."
  (ensure-frameworks)
  (objc:with-autorelease-pool ()
    (let ((bundle (objc:invoke "NSBundle" "mainBundle")))
      (unless (nullp (objc:invoke bundle "bundleIdentifier"))
        (objc:invoke-into 'string bundle "bundlePath")))))

(defun sandboxed-p ()
  "Whether this process runs in the App Sandbox, as a Mac App Store build does.
The sandbox sets APP_SANDBOX_CONTAINER_ID in the environment of every process
it contains."
  (and (uiop:getenv "APP_SANDBOX_CONTAINER_ID") t))

(defun login-item-available-p ()
  "Whether registering is possible here.

NIL from the loose binary: an entry naming a bare executable would start it
with no bundle, and so no camera.  And NIL in the sandbox, which refuses
LSSharedFileList -- the App Store way is SMAppService, which did not work for
an SBCL bundle (see the header), so the store build simply has no Start at
Login rather than a menu item that always fails."
  (and (not (sandboxed-p)) (bundle-path) t))

(defmacro with-login-items ((list) &body body)
  "Bind LIST to the session's login item list for the extent of BODY."
  `(let ((,list (%shared-file-list-create
                 (cffi:null-pointer)
                 (%global "kLSSharedFileListSessionLoginItems")
                 (cffi:null-pointer))))
     (if (cffi:null-pointer-p ,list)
         nil
         (unwind-protect (progn ,@body)
           (%cf-release ,list)))))

(defun %our-item (list)
  "The login item pointing at this application, RETAINED, or NIL.

The caller must release it.  A CFArray owns its elements, so releasing the
snapshot releases every item in it, and an item returned across that release
without a retain is a dangling pointer -- a memory fault on the remove path."
  (let ((snapshot (%shared-file-list-snapshot list (cffi:null-pointer)))
        (ours (bundle-path)))
    (unless (cffi:null-pointer-p snapshot)
      (unwind-protect
           (loop for index below (objc:invoke snapshot "count")
                 for item = (objc:invoke snapshot "objectAtIndex:" index)
                 for url = (%shared-file-list-item-url
                            (objc:objc-object-pointer item) 0 (cffi:null-pointer))
                 unless (cffi:null-pointer-p url)
                   do (let ((path (objc:invoke-into 'string url "path")))
                        (%cf-release url)
                        (when (and path ours (string= path ours))
                          (return (objc:retain item)))))
        (%cf-release snapshot)))))

(defun login-item-status ()
  "Whether this application starts at login: :ENABLED, :NOT-REGISTERED, or
:NOT-FOUND when it is not running from a bundle and the question is void."
  (if (not (login-item-available-p))
      :not-found
      (objc:with-autorelease-pool ()
        (with-login-items (list)
          (let ((item (%our-item list)))
            (cond (item (objc:release item) :enabled)
                  (t :not-registered)))))))

(defun register-login-item ()
  "Add this application to the login items.  Returns the resulting status.

ENSURE-FRAMEWORKS before the pool, not inside it: WITH-AUTORELEASE-POOL needs
Foundation, and this may be the first Objective-C call the process makes."
  (ensure-frameworks)
  (objc:with-autorelease-pool ()
    (let ((path (or (bundle-path)
                    (error "Not running from a bundle, so there is nothing to register."))))
      (with-login-items (list)
        (let* ((url (objc:invoke "NSURL" "fileURLWithPath:" path))
               (item (%shared-file-list-insert
                      list (%global "kLSSharedFileListItemLast")
                      (cffi:null-pointer) (cffi:null-pointer)
                      (objc:objc-object-pointer url)
                      (cffi:null-pointer) (cffi:null-pointer))))
          (when (cffi:null-pointer-p item)
            (error "The login item list refused ~A." path))
          (%cf-release item)))))
  (login-item-status))

(defun unregister-login-item ()
  "Remove this application from the login items.  Returns the resulting status."
  (ensure-frameworks)
  (objc:with-autorelease-pool ()
    (with-login-items (list)
      (let ((item (%our-item list)))
        (when item
          (unwind-protect
               (%shared-file-list-item-remove list (objc:objc-object-pointer item))
            (objc:release item))))))
  (login-item-status))
