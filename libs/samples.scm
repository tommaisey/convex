(library (samples)

  (export
    samples
    samples-dir
    valid-sample?
    get-sample-safe
    path-append
    name-contains?
    number-strings)

  (import (scheme) (node-eval) (utilities) (context))

  (define-syntax samples
    (syntax-rules ()
      ((_ name files ...)
       (samples-impl name (list files ...)))))

  (define-syntax samples-dir
    (syntax-rules ()
      ((_ name dir-path pred)
       (samples-impl name
         (let* ([p (if (procedure? pred) pred (lambda (s) (string=? pred s)))]
                [p (lambda (s) (and (p s) (valid-sample? s)))])
           (map (lambda (x) (path-append dir-path x))
                (filter p (list-sort string<? (directory-list dir-path)))))))

      ((_ name dir-path)
       (samples-dir name dir-path (lambda (x) #t)))))

  ;; Declares 4 new identifiers based off the `name`.
  ;; - `name` is a value containing the first sample returned by list-impl.
  ;; - `name/` is a fn that take indeces and returns samples
  ;; - `name-list` is the raw list of samples
  ;; - `name-num` is the number of samples
  (define-syntax samples-impl
    (lambda (x)
      (syntax-case x ()
        ((_ name list-impl)
         (with-syntax ([id (gen-id #'name #'name)]
                       [id/  (gen-id #'name #'name "/")]
                       [id-num  (gen-id #'name #'name "-num")])
           #'(begin
               (define id (list->vector list-impl))
               (define id-num (vector-length id))

               (define (id/ val)
                 (lambda (context)
                   (get-sample-safe id (get-leaf val context))))

               (vector-for-each (lambda (x) (println (path-last x))) id)

               (println (string-append (symbol->string 'id) ": "
                                       (number->string id-num)
                                       " samples defined."))))))))

  (define (valid-sample? f)
    (and (string? f)
         (for-any (lambda (ext) (string-ci=? ext (path-extension f)))
                  (list "wav" "aif" "aiff" "ogg"))))

  (define (get-sample-safe sample-vec idx)
    (let ([len (vector-length sample-vec)])
      (cond
        ((not (number? idx))
         (error 'get-sample-safe "Can't index sample" idx))
        ((zero? len)
         (error 'get-sample-safe "No samples in vector"))
        (else (vector-ref sample-vec (mod (trunc-int idx) len))))))

  ;; A safer way to add a file name to a directory
  (define (path-append dir file)
    (string-append (path-root dir) (string (directory-separator)) file))

  ;; Returns a predicate for matching strings. May take a string or a
  ;; list of strings. Supply a bool for the first arg to invert the results.
  (define name-contains?
    (case-lambda
      ((string-or-list)
       (name-contains? #t string-or-list))

      ((accept? string-or-list)
       (if (string? string-or-list)
           (name-contains? accept? (list string-or-list))
           (lambda (s) ((if accept? for-any for-none)
                        (lambda (s2) (string-contains s s2)) string-or-list))))))

  ;; Returns a list of the numbers between `start` and `end` as strings.
  ;; They are padded with zeros to `num-chars` characters.
  (define (number-strings start end num-chars)
    (let ([raw-nums (map (lambda (x) (+ start x)) (iota (+ 1 (- end start))))]
          [f-str (string-append "~" (number->string num-chars) ",'0d")])
      (map (lambda (x) (format f-str x)) raw-nums))))