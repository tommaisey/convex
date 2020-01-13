;; Command to begin a recording. User can supply a simple number for
;; the recording length or a specific arc of time. If a simple number,
;; the recording starts at the next whole multiple of that number.
(define-syntax record
  (syntax-rules ()
    ((_ arc/len filepath)
     (if rendered-point
         (let ([bufnum (open-write-buffer filepath)]
               [arc (if (number? arc/len)
                        (let ([start (round-up rendered-point arc/len)])
                          (make-arc start (+ start arc/len)))
                        arc/len)])

           (unless (arc? arc)
             (error 'record "first arg should be an arc or a number" arc/len))

           (when active-recording
             (lest [synth-id (recording-state-synth active-recording)]
                   (stop-synth synth-id))
             (close-write-buffer (recording-state-bufnum active-recording)))

           (set! active-recording (make-recording-state arc bufnum))
           (println (format "recording starts in ~~~A measures"
                            (exact (round (- (arc-start arc) rendered-point))))))
         (println (string-append "Won't record to: " filepath
                                 ". Retry after playhead has begun.\n"))))))

;;----------------------------------------------------------------
;; Note: need a separate `in` for each input channel. `disk-out` fails
;; if num input channels doesn't match the buffer's channels. `in` can
;; read multiple channels but can only output one.
(sc/send-synth sc3 "recorder2"
  (letc ([:inbus 0] [:outbuf -1])
    (let* ([sig1 (sc/in 1 sc/ar :inbus)]
           [sig2 (sc/in 1 sc/ar (+u :inbus 1))]
           [sig-chans (sc/mce2 sig1 sig2)])
      (sc/disk-out :outbuf sig-chans))))

(define-immutable-record recording-state
  [arc (make-arc 0 1)]
  [bufnum -1]
  [synth #f])

;; A global recording-state (optional).
(define active-recording #f)

;; Called regularly from the playback thread. If the user has requested
;; a recording, it starts and ends a diskout synth at the right time.
(define (update-recording beat-now render-arc t)
  (when active-recording
    (let* ([synth-id (recording-state-synth active-recording)]
           [rec-arc (recording-state-arc active-recording)]
           [start (arc-start rec-arc)]
           [end (arc-end rec-arc)])
      (cond
        ((and (not synth-id) (within-arc? render-arc start))
         (start-recording (time-at-beat start beat-now t)))

        ((and synth-id (within-arc? render-arc end))
         (cancel-recording (time-at-beat end beat-now t)))))))

(define* (start-recording [/opt (t (sc/utc))])
  (when active-recording
    (let* ([bufnum (recording-state-bufnum active-recording)]
           [event (make-event 0 (:inbus 0) (:outbuf bufnum))]
           [args (event-symbols->strings event)]
           [synth-id 55378008]) ; only one at a time for now
      (play-when "recorder2" t recording-group args synth-id)
      (set! active-recording (recording-state-with-synth active-recording synth-id))
      (println "recording started!"))))

(define* (cancel-recording [/opt (t (sc/utc))])
  (when active-recording
    (let* ([synth-id (recording-state-synth active-recording)]
           [bufnum (recording-state-bufnum active-recording)])
      (stop-synth synth-id t)
      (close-write-buffer bufnum (+ t 0.01))
      (set! active-recording #f)
      (println "recording ended!"))))