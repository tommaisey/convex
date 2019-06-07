;;---------------------------------------------------------
(define pattern-dict (make-pattern-dict))

(define-syntax pattern
  (syntax-rules ()

    ((_ name play-now? p)
     (begin (define name p)
            (when play-now?
              (add-pattern pattern-dict 'name p))))

    ((_ name p)
     (pattern name #t p))))

(define-syntax start
  (syntax-rules ()

    ((_) (start-playhead))

    ((_ name) (add-pattern pattern-dict 'name name))))

(define-syntax stop
  (syntax-rules ()

    ((_) (stop-playhead))

    ((_ name) (remove-pattern pattern-dict 'name))))

(define (pause) (pause-playhead)) ;; for symmetry
(define (clear-all) (clear-patterns pattern-dict))

(define (print-patterns start end)
  (define ctxt
    (fold-left (lambda (c p) (contexts-merge c (render p start end)))
               (make-empty-context start end)
               (list-patterns pattern-dict)))
  (context-map (lambda (c) (event-clean (process-inst (context-event c)))) ctxt))

;;-----------------------------------------------------------------
(define bpm 100)
(define playback-thread #f)
(define playback-chunk 1/8) ; 1/8th beat for now
(define playback-thread-semaphore (make-semaphore))
(define playback-latency 0.2)

;; State used to mitigate timing jitter in callbacks:
(define last-process-time #f) ;; time of last callback, utc
(define last-process-beat 0)  ;; time of last callback, beats
(define jitter-overlap 1/32)  ;; extra time to render each block
(define rendered-point #f)    ;; musical time that has been sent to SC

;; Called regularly by the playback thread. It renders events in
;; chunks whose length are determined by playback-chunk, plus a
;; little extra ('jitter-overlap') to allow for the callback to
;; happen late.
(define (process-chunk)
  (let ([t (utc)])

    ;; Dispatches all the events that were rendered.
    (define (play-chunk now-beat context)
      (for-each (lambda (e) (play-event e now-beat t))
                (context-events-next context)))

    (define (pattern-player now-beat start end)
      (lambda (p) (play-chunk now-beat (render p start end))))

    (guard (x [else (handle-error x)])
      (let* ([now (+ last-process-beat (beats-since-last-process t))]
             [start (or rendered-point now)]
             [end (+ now playback-chunk jitter-overlap)]
             [player (pattern-player now start end)])
        (iterate-patterns pattern-dict player)
        (set! last-process-time t)
        (set! last-process-beat now)
        (set! rendered-point end)))))

;; Only creates new thread if one isn't already in playback-thread.
(define (start-thread semaphore)
  (when (not playback-thread)
    (set! playback-thread
          (start-suspendable-thread
           process-chunk (* playback-chunk (bpm->spm bpm)) semaphore))))

(define (start-playhead)
  (start-thread playback-thread-semaphore)
  (stop-waiting playback-thread-semaphore)
  (playhead-sync-info))

(define (pause-playhead)
  (start-waiting playback-thread-semaphore)
  (set! rendered-point #f)
  (set! last-process-time #f)
  (playhead-sync-info))

(define (stop-playhead)
  (pause-playhead)
  (set! last-process-beat 0)
  (playhead-sync-info))

(define (playing?)
  (not (waiting? playback-thread-semaphore)))

(define (beats-since-last-process utc-time)
  (if (not last-process-time) 0
      (secs->measures (- utc-time last-process-time) bpm)))

(define (playhead-sync-info)
  (let ([now (+ last-process-beat (beats-since-last-process (utc)))])
    (println
     (format "(playhead-sync ~A (position ~A) (mps ~A))"
             (if (playing?) 'playing 'stopped) now (bpm->mps bpm)))))

(define (set-bpm! n)
  (set! bpm n)
  (let ([e (make-event 0 (:tempo (bpm->mps n))
                       (:control "tempo")
                       (:group bus-effect-group))])
    (playhead-sync-info)
    (play-event e 0)))

(set-bpm! bpm)

(define (handle-error condition)
  (let ([p (console-output-port)])
    (display-condition condition p)
    (newline p)
    (flush-output-port p)
    (clear-patterns pattern-dict)))