;; -*- geiser-scheme-implementation: chez-*-
;; This is the place where patterns are registered with a playback
;; thread. The thread periodically pulls events from the patterns and
;; pushes them on to our sound engine back-ends (e.g. OSC , MIDI).
(library (playback)
  (export
   bpm->mps bpm->spm
   measures->secs secs->measures
   secs-until sleep-secs
   make-pattern-dict
   iterate-patterns list-patterns
   add-pattern remove-pattern
   get-pattern clear-patterns
   pattern-success-symbols
   pattern-error-symbols
   list-patterns-in-file
   list-files-with-playing-patterns
   list-pattern-names
   semaphore semaphore? make-semaphore
   start-waiting stop-waiting waiting?
   start-suspendable-thread)

  (import (scheme)
          (context)
          (context-render)
          (seq-eval)
          (utilities)
          (file-tools))

  ;;------------------------------------------------
  ;; Some useful functions for dealing with time.

  ;; Convert bpm to measures per second (mps)
  (define (bpm->mps bpm) (/ bpm 60 4))
  ;; Convert bpm to seconds per measure
  (define (bpm->spm bpm) (/ 1 (bpm->mps bpm)))
  ;; Convert a value in measures to seconds
  (define (measures->secs m bpm) (* m (bpm->spm bpm)))
  ;; Convert a value in seconds to measures
  (define (secs->measures s bpm) (* s (bpm->mps bpm)))

  (define (secs-until beat current-beat bpm)
    (/ (- beat current-beat) (bpm->mps bpm)))

  (define (sleep-secs secs)
    (let* ([secs-whole (trunc-int secs)]
           [ns (trunc-int (* (- secs secs-whole) 10e8))])
      (sleep (make-time 'time-duration ns secs-whole))))

  ;;------------------------------------------------
  ;; Manage a threadsafe dictionary of playing patterns.

  (define (make-pattern-dict)
    (make-safe-val (make-hashtable symbol-hash eq? 32)))

  (define pattern-success-symbols
    (make-parameter '(success done ok you-betcha)))
  (define pattern-error-symbols
    (make-parameter '(error !!! nope try-again)))

  ;; Before adding the pattern, we run it in a few contexts
  ;; on this thread. That way, we get early error reporting,
  ;; and less chance of a broken pattern on the playback thread.
  (define (add-pattern dict id fn)
    (define (choose symbols)
      (let ([len (length symbols)])
        (if (eq? len 1)
            (list-ref symbols 0)
            (list-ref symbols (random (dec len))))))
    (define (handle-error condition)
      (display-condition condition)
      (println "^^^ Pattern appears broken.")
      (choose (pattern-error-symbols)))
    (guard (x [else (handle-error x)])
      (let ([pos (random 10000)]
            [neg (* -1 (random 1000))])
        (render-arc fn 0 8)
        (render-arc fn pos (+ pos 8))
        (render-arc fn neg (+ neg 10))
        (safe-val-apply hashtable-set! dict id fn)
        (choose (pattern-success-symbols)))))

  (define (remove-pattern dict id)
    (safe-val-apply hashtable-delete! dict id))

  (define (get-pattern dict id)
    (safe-val-apply hashtable-ref dict id #f))

  (define (clear-patterns dict)
    (safe-val-apply hashtable-clear! dict))

  (define (iterate-patterns dict fn)
    (let-values ([(keys values) (safe-val-apply hashtable-entries dict)])
      (vector-for-each fn values)))

  (define (list-patterns dict)
    (let-values ([(keys values) (safe-val-apply hashtable-entries dict)])
      (vector->list values)))

  (define (list-pattern-names dict)
    (let-values ([(keys values) (safe-val-apply hashtable-entries dict)])
      (vector->list keys)))

  (define (list-patterns-in-file file-path pattern-form?)
    (definitions-in-file file-path pattern-form? (lambda (f) (cadr f))))

  (define (list-files-with-playing-patterns root-path pattern-dict pattern-form?)

    (define (contains-playing? file)
      (and (string=? (path-extension file) "scm")
           (for-any (lambda (p) (get-pattern pattern-dict p))
                    (list-patterns-in-file file pattern-form?))))

    (define (build result file)
      (let ([recur (lambda (f) (list-files-with-playing-patterns
                           f pattern-dict pattern-form?))])
        (cond
         ((file-directory? file) (append (recur file) result))
         ((contains-playing? file) (cons file result))
         (else result))))

    (fold-left build '() (child-file-paths root-path)))

  ;;------------------------------------------------
  ;; Infrastructure for a special playback thread.
  ;; It calls a process-fn roughly each chunk-secs.
  ;; It's pausable and restartable via a 'semaphore'.

  (define-record-type semaphore
    (fields (mutable val semaphore-val set-semaphore-val!)
            (immutable mutex)
            (immutable cond))
    (protocol
     (lambda (new)
       (lambda () (new #t (make-mutex) (make-condition))))))

  (define (set-semaphore sem val)
    (with-mutex (semaphore-mutex sem)
      (set-semaphore-val! sem val)))

  (define (set-and-signal-semaphore sem val)
    (with-mutex (semaphore-mutex sem)
      (set-semaphore-val! sem val)
      (condition-signal (semaphore-cond sem))))

  (define (start-waiting sem) (set-semaphore sem #t))
  (define (stop-waiting sem) (set-and-signal-semaphore sem #f))
  (define (waiting? sem)
    (with-mutex (semaphore-mutex sem)
      (semaphore-val sem)))

  ;; Allows introduction of rebindable values for process-fn and
  ;; chunk-secs, so you can use global values and change the
  ;; loop's callback interactively.
  (define-syntax start-suspendable-thread
    (syntax-rules ()
      ((_ process-fn chunk-secs sem)
       (fork-thread
        (lambda ()
          (let loop ()
            (with-mutex (semaphore-mutex sem)
              (when (semaphore-val sem)
                (condition-wait
                 (semaphore-cond sem)
                 (semaphore-mutex sem))))
            (process-fn)
            (sleep-secs chunk-secs)
            (loop)))))))
  )
