;;-----------------------------------------------------------------
;; Plays a event at the right time in the future.
;; To allow for sample accurate playback you must supply
;; a consistent `current-time` for all events dispatched at
;; the same time.
(define* (play-event event beat-now [/opt (time-now (sc/utc))])
  (let ([event (preprocess-event event)])
    (alist-let event ([beat    :beat 0]
                      [inst    :inst "sine-grain"]
                      [group   :group standard-group]
                      [control :control #f]
                      [sustain :sustain #f])
      (let ([time (time-at-beat beat beat-now time-now)]
            [args (event-symbols->strings event)])
        (create-group group sc/add-to-head default-group)
        (if control
            (if (or (not (number? group)) (<= group 1))
                (println "Error: control event didn't specify a valid group.")
                (control-when time group args))
            (play-when inst time group args))))))

(define (time-at-beat beat beat-now time-now)
  (let ([delay (secs-until beat beat-now bpm)])
    (+ time-now delay playback-latency)))

;; Computes frequency for events using the harmony system.
;; Gives sampler instrument to events with samples.
(define (preprocess-event event)
  (event-clean (process-times (process-inst event))))

;; If it looks like a sampler event, sets the right inst if it's
;; missing. If it looks like a freq event, computes freq.
(define (process-inst event)
  (lest [sample (event-get event :sample #f)]
        (process-sample event sample)
        (process-event-freq event)))

;; Interprets the :sample and :sample-idx keys to select a sample bufnum
(define (process-sample event sample)
  (define bufnum
    (cond ((vector? sample)
           (open-read-buffer (get-sample-safe sample (event-get event :sample-idx 0))))
          ((valid-sample? sample)
           (open-read-buffer sample))
          (else (error 'process-sample "Couldn't get sample" sample))))
  (define inst (event-get event :inst "sampler"))
  (event-set-multi event (:sample bufnum) (:inst inst)))

;; Converts any key found in the 'tempo-dependent-keys' alist
;; from measures to seconds, for prior to sending to SC.
(define (process-times event)
  (define (convert event entry)
    (if (cdr entry)
        (event-set event (car entry) (measures->secs (cdr entry) bpm))
        event))
  (let ([vals (event-get-multi event tempo-dependent-keys)])
    (fold-left convert event vals)))