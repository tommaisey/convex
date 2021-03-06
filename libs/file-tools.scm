(library (file-tools)

  (export has-extension?
          valid-scheme-path?
          file-parent-exists?
          home-dir expand-path
          path-append path+
          child-file-paths
          rmdir mkdir-rec
          definitions-in-file
          file-lines
          os-symbol)

  (import (chezscheme) (utilities))

  ;; Returns a lambda that checks for any of the given extensions
  (define (has-extension? . exts)
    (lambda (path)
      (let ([ext (string-downcase (path-extension path))]
            [exts (map string-downcase exts)])
        (for-any (lambda (e) (string=? e ext)) exts))))

  ;; Checks a path's extension for an extension associated with scheme.
  (define valid-scheme-path? (has-extension? "scm"))

  ;; A safer way to add a file name to a directory
  (define (path-append dir . files)
    (let* ([sep (string (directory-separator))]
           [dir (if (string-suffix? sep dir) dir (str+ dir sep))])
      (apply str+ dir files)))

  ;; Mirrors our string-append -> str+ alias.
  (alias path+ path-append)

  ;; Unlike directory-list, returns full path of child files
  (define (child-file-paths dir)
    (map (lambda (f) (path-append dir f))
         (directory-list dir)))

  ;; Deletes a dir recursively.
  (define (rmdir dir)
    (or (not (file-exists? dir))
        (and (file-regular? dir) (delete-file dir))
        (and (for-all identity (map rmdir (child-file-paths dir)))
             (delete-directory dir))))

  ;; Makes a dir recursively
  (define (mkdir-rec dir)
    (when (not (file-parent-exists? dir))
      (mkdir-rec (path-parent dir)))
    (or (file-exists? dir) (begin (mkdir dir) #t)))

  ;; Expands out ~/ from a path on unix.
  (define (expand-path path)
    (if (home-dir-path? path)
        (let ([len (string-length path)])
          (path+ home-dir (substring path (min 2 len) len)))
        (values path)))

  ;; True if a path starts with '~' and we're on unix.
  (define (home-dir-path? path)
    (and (not (eqv? os-symbol 'windows))
         (eqv? #\~ (string-ref path 0))))

  ;; Check if a file's parent directory exists
  (define (file-parent-exists? path)
    (file-exists? (path-parent path)))

  ;; Returns a human-readable symbol for the os from Chez's cryptic machine-type.
  (define os-symbol
    (let* ([m-type-list (string->list (symbol->string (machine-type)))]
           [chez-name (list->string (cdr (memp char-numeric? m-type-list)))])
      (cdar (memp (lambda (x) (string=? (car x) chez-name))
                  '(("fb"  . freebsd)
                    ("le"  . linux)
                    ("nb"  . netbsd)
                    ("nt"  . windows)
                    ("ob"  . openbsd)
                    ("osx" . macos)
                    ("qnx" . qnx)
                    ("s2"  . solaris))))))

  ;; The user's home directory.
  (define home-dir
    (if (eqv? os-symbol 'windows)
        (path+ (getenv "SystemDrive") (getenv "HOMEPATH"))
        (getenv "HOME")))

  ;;-----------------------------------------------------------------------
  ;; Looks for top-level forms in a file matching defining-form? and
  ;; returns the name of the definition using a name-getter fn.
  ;; Warning: currently won't work with definitions in a library or module.
  (define (definitions-in-file file-path defining-form? name-getter)
    (define (do-read)
      (do ([s (read) (read)]
           [out (list) (if (defining-form? s)
                           (cons (name-getter s) out) out)])
          ((eof-object? s) out)))
    (with-input-from-file file-path do-read))

  ;; Open a file as a textual (rather than binary) port.
  (define (open-file-as-textual-port file)
    (open-file-input-port file (file-options) 'block (native-transcoder)))

  ;; Read a port into a list of lines.
  (define (lines-from-port p)
    (do ([line (get-line p) (get-line p)]
         [lines (list) (cons line lines)])
        ((eof-object? line)
         (begin (close-port p) (reverse lines)))))

  ;; Read an entire file into a list of lines.
  ;; Don't do this with huge files!
  (define (file-lines file)
    (lines-from-port (open-file-as-textual-port file))))
