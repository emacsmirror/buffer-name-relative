;;; buffer-name-relative.el --- Relative buffer names -*- lexical-binding: t -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Copyright (C) 2023  Campbell Barton

;; Author: Campbell Barton <ideasman42@gmail.com>

;; URL: https://codeberg.org/ideasman42/emacs-buffer-name-relative
;; Keywords: convenience
;; Version: 0.1
;; Package-Requires: ((emacs "28.1"))

;;; Commentary:

;; Provide a global mode to make file buffer names root/VC relative.
;;

;;; Usage

;;
;; Write the following code to your .emacs file:
;;
;;   (require 'buffer-name-relative)
;;   (buffer-name-relative-mode)
;;
;; Or with `use-package':
;;
;;   (use-package buffer-name-relative)
;;   (buffer-name-relative-mode)
;;

;;; Code:

(require 'vc)


;; ---------------------------------------------------------------------------
;; Compatibility

(eval-when-compile
  (when (version< emacs-version "31.1")
    (defmacro incf (place &optional delta)
      "Increment PLACE by DELTA or 1."
      (declare (debug (gv-place &optional form)))
      (gv-letplace (getter setter) place
        (funcall setter `(+ ,getter ,(or delta 1)))))
    (defmacro decf (place &optional delta)
      "Decrement PLACE by DELTA or 1."
      (declare (debug (gv-place &optional form)))
      (gv-letplace (getter setter) place
        (funcall setter `(- ,getter ,(or delta 1)))))))


;; ---------------------------------------------------------------------------
;; Custom Variables

(defgroup buffer-name-relative nil
  "Root relative buffer names."
  :group 'convenience)

(defcustom buffer-name-relative-prefix "./"
  "Text to include before relative paths.
Or optionally a pair of strings which surround the project
directory name."
  :type '(choice string (cons string string)))

(defcustom buffer-name-relative-prefix-map nil
  "Optional abbreviations of project paths.
You may wish to use short abbreviation for project names,
otherwise the parent directory will be used."
  :type '(alist :key-type string :value-type string))

(defcustom buffer-name-relative-root-functions (list 'buffer-name-relative-root-path-from-vc)
  "List of functions symbols which take a file-path and return a root path or nil.
The non-nil result of any function is used as the root path.
Any errors are demoted into messages."
  :type '(repeat symbol))

(defcustom buffer-name-relative-fallback 'default
  "Behavior when the root directory can't be found."
  :type
  '(choice (const :tag "Default Directory" default)
           (const :tag "Absolute Path" absolute)
           (const :tag "None" nil)))

(defcustom buffer-name-relative-abbrev-limit 0
  "Abbreviate leading directories longer than this, zero for no abbreviation."
  :type 'integer)


;; ---------------------------------------------------------------------------
;; Private Functions

(defun buffer-name-relative--abbrev-directory-impl (path overflow)
  "Abbreviate PATH by OVERFLOW characters."
  (declare (important-return-value t))
  ;; Skip leading slashes.
  (let ((beg (string-match-p "[^/]" path)))
    (cond
     (beg
      (let ((end (string-search "/" path beg)))
        (cond
         (end
          (incf beg)
          (let ((len 1)
                (trunc (- end beg)))
            (decf overflow trunc)
            (when (< overflow 0)
              (decf beg overflow)
              (incf trunc overflow)
              (decf len overflow)
              (setq overflow 0))
            ;; The resulting abbreviated name.
            (cons
             ;; The `head'.
             (cond
              ((< 1 len)
               (concat (substring path 0 (1- beg)) "~"))
              (t
               (substring path 0 beg)))
             ;; The `tail'.
             (cond
              ((zerop overflow)
               (cons (substring path end) nil))
              (t
               (buffer-name-relative--abbrev-directory-impl (substring path end) overflow))))))
         (t ;; `end' not found.
          (cons path nil)))))
     (t ;; `beg' not found.
      (cons path nil)))))

(defun buffer-name-relative--abbrev-directory (path path-len-goal)
  "Abbreviate PATH to PATH-LEN-GOAL (if possible)."
  (declare (important-return-value t))
  (let ((overflow (- (length path) path-len-goal)))
    (cond
     ((<= overflow 0)
      path)
     (t
      (mapconcat #'identity (buffer-name-relative--abbrev-directory-impl path overflow)
                 ;; emacs-29+ can remove this separator.
                 "")))))

(defun buffer-name-relative--root-path-lookup (filepath)
  "Lookup `buffer-name-relative-root-functions' using FILEPATH for a relative directory."
  (declare (important-return-value t))
  (let ((name-base nil)
        (functions buffer-name-relative-root-functions))
    (while functions
      (let ((fn (pop functions)))
        (let ((name-base-test
               (condition-case err
                   (funcall fn filepath)
                 (error
                  (message "Error calling \"%s\": %s" (symbol-name fn) err)
                  ;; Resolve to nil.
                  nil))))
          (when name-base-test
            (setq name-base name-base-test)
            ;; Break.
            (setq functions nil)))))

    (unless name-base
      (setq name-base
            (cond
             ((eq buffer-name-relative-fallback 'default)
              default-directory)
             ((eq buffer-name-relative-fallback 'absolute)
              (file-name-directory filepath))
             ((null buffer-name-relative-fallback)
              ""))))

    name-base))

(defun buffer-name-relative--create-file-buffer-advice (orig-fn filepath)
  "VCS root-relative buffer name (where possible).
Advice around `create-file-buffer'.
Wrap ORIG-FN, which creates a buffer from FILEPATH."
  (declare (important-return-value t))
  (let ((buf (funcall orig-fn filepath)))
    ;; Error's are very unlikely, this is to ensure even the most remote
    ;; chance of an error doesn't make the file fail to load.
    (condition-case-unless-debug err
        (when buf
          (let ((name-base (or (buffer-name-relative--root-path-calc-relative filepath) filepath)))
            ;; Create a unique name and rename the buffer.
            (let ((name-unique name-base)
                  (name-id 0))
              (while (get-buffer name-unique)
                (setq name-unique (concat name-base (format " <%d>" name-id)))
                (incf name-id))
              (with-current-buffer buf
                (rename-buffer name-unique)))))
      (error
       (message "Error creating vc-backend root name: %s" err)))
    buf))

(defun buffer-name-relative--root-path-calc-prefix (base-path)
  "Given a BASE-PATH, return a prefix to show before the relative path."
  (declare (important-return-value t))
  (cond
   ((stringp buffer-name-relative-prefix)
    ;; String literal result.
    buffer-name-relative-prefix)
   ;; Coerce non-strings as an error here will cause the buffer not to load properly.
   ((consp buffer-name-relative-prefix)
    (let* ((base-path-noslash (directory-file-name base-path))
           (str-beg (car buffer-name-relative-prefix))
           (str-end (cdr buffer-name-relative-prefix))
           (str-body nil))
      (when buffer-name-relative-prefix-map
        (setq str-body
              (alist-get base-path-noslash buffer-name-relative-prefix-map nil nil #'equal)))
      (unless (stringp str-body)
        (setq str-body
              (cond
               ((null str-body)
                (file-name-nondirectory base-path-noslash))
               (t
                (format "%S" str-body)))))
      (unless (stringp str-beg)
        (setq str-beg (format "%S" str-beg)))
      (unless (stringp str-end)
        (setq str-end (format "%S" str-end)))
      ;; Project prefix result.
      (concat str-beg str-body str-end)))
   (t
    (message "warning: `buffer-name-relative-prefix' must be a string or a cons pair of strings")
    ;; Fallback prefix result
    "?/")))

(defun buffer-name-relative--root-path-calc-relative (filepath)
  "Return the version control relative path to FILEPATH."
  (declare (important-return-value t))
  (let ((base-path (buffer-name-relative--root-path-lookup filepath)))
    (cond
     (base-path
      (let ((filepath-rel-prefix nil)
            (filepath-rel (file-relative-name filepath base-path)))

        ;; Ensure the relative version of the path is not "worse" (by some definition).
        (cond
         ((string-prefix-p "../" filepath-rel)
          ;; Having to go "up" a directory means it's likely the chosen
          ;; `base-path' doesn't relate to the `filepath', so check for some alternatives.
          (cond
           ((string-prefix-p "~/" filepath)
            ;; Prefer the home directory, over a relative path.
            (setq filepath-rel-prefix (substring filepath 0 2))
            (setq filepath-rel (substring filepath 2)))
           ((string-suffix-p filepath filepath-rel)
            ;; Prefer an absolute directory, if the relative directory
            ;; ends up going back up to the root.
            (let ((beg (string-match-p "[^/]" filepath)))
              (setq filepath-rel-prefix (substring filepath 0 beg))
              (setq filepath-rel (substring filepath beg))))))
         ((string-equal base-path "~/")
          ;; It's possible the root happens to be use users home directory.
          (setq filepath-rel-prefix base-path)))

        (unless filepath-rel-prefix
          ;; Common case, the relative path is a child of the `base-path'.
          ;; In most cases no changes are needed here,
          ;; although in the event we would like to do literal replacements
          ;; for a known `base-path', this is the place to do it.
          (setq filepath-rel-prefix (buffer-name-relative--root-path-calc-prefix base-path)))

        ;; Abbreviate?
        (unless (zerop buffer-name-relative-abbrev-limit)
          (let* ((name (file-name-nondirectory filepath-rel))
                 (name-len (length name))
                 (filepath-rel-len (length filepath-rel))
                 (dir-len (- filepath-rel-len name-len)))
            (when (< buffer-name-relative-abbrev-limit dir-len)
              (setq filepath-rel
                    (concat
                     (buffer-name-relative--abbrev-directory
                      (substring filepath-rel 0 dir-len) buffer-name-relative-abbrev-limit)
                     name)))))
        (concat filepath-rel-prefix filepath-rel)))
     (t
      nil))))


;; ---------------------------------------------------------------------------
;; Public Functions

;; NOTE: no need to auto-load this function, it's only public because it's
;; referenced from `buffer-name-relative-root-functions'.

(defun buffer-name-relative-root-path-from-vc (filepath)
  "Return the version control directory from FILEPATH or nil."
  (declare (important-return-value t))
  ;; Any unlikely errors will be caught by the caller,
  ;; ignore errors from `vc-responsible-backend' because this causes noise
  ;; in the case it can't be detected.
  (let ((vc-base-path nil))
    (let ((vc-backend
           (ignore-errors
             (vc-responsible-backend filepath))))
      (when vc-backend
        (setq vc-base-path (vc-call-backend vc-backend 'root filepath))))
    vc-base-path))

(defun buffer-name-relative-root-path-from-ffip (filepath)
  "Return the FFIP directory from FILEPATH or nil."
  (declare (important-return-value t))
  (let ((result nil))
    (when (fboundp 'ffip-project-root)
      (let ((dir (file-name-directory filepath)))
        (when dir
          (let ((default-directory dir))
            (condition-case-unless-debug err
                (setq result (funcall #'ffip-project-root))
              (error
               (message "Error finding FFIP root name: %s" err)))))))
    result))

(defun buffer-name-relative-root-path-from-projectile (filepath)
  "Return the PROJECTILE directory from FILEPATH or nil."
  (declare (important-return-value t))
  (let ((result nil))
    (when (fboundp 'projectile-project-root)
      (let ((dir (file-name-directory filepath)))
        (when dir
          (condition-case-unless-debug err
              (setq result (funcall #'projectile-project-root dir))
            (error
             (message "Error finding PROJECTILE root name: %s" err))))))
    result))

;; ---------------------------------------------------------------------------
;; Global Mode

(defun buffer-name-relative--mode-enable ()
  "Turn on `buffer-name-relative-mode' globally."
  (declare (important-return-value nil))
  (advice-add 'create-file-buffer :around #'buffer-name-relative--create-file-buffer-advice))

(defun buffer-name-relative--mode-disable ()
  "Turn on `buffer-name-relative-mode' globally."
  (declare (important-return-value nil))
  (advice-remove 'create-file-buffer #'buffer-name-relative--create-file-buffer-advice))

;;;###autoload
(define-minor-mode buffer-name-relative-mode
  "Toggle saving the undo data in the current buffer (Undo-Fu Session Mode)."
  :global t

  (cond
   (buffer-name-relative-mode
    (buffer-name-relative--mode-enable))
   (t
    (buffer-name-relative--mode-disable))))

(provide 'buffer-name-relative)
;; Local Variables:
;; fill-column: 99
;; indent-tabs-mode: nil
;; elisp-autofmt-format-quoted: nil
;; End:
;;; buffer-name-relative.el ends here
