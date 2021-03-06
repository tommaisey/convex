(library (ops-time)
  (export mv- mv+ mv/ mv* tt+ tt- tt* tt/
          flip-time swing taps legato)

  (import (chezscheme)
          (utilities) (context) (arc) (event)
          (context-render)
          (seq-eval)
          (seq-subdivide)
          (ops-chains)
          (rhythm)
          (only (samples) :sidx))

  ;; A general 'mv', taking a math op and a def. The math op is
  ;; called with each segment's current time and the value returned by
  ;; def. The input context is resolved with a different arc, in effect
  ;; shifting it in time.
  (define (mv math-op inv-math-op . sdefs)
    (let ([impl (mv-math-impl math-op inv-math-op)])
      (apply with (map (lambda (p) (wrap-subdivide-fn impl p)) sdefs))))

  (define (mv+ . sdefs) (apply mv + - sdefs))
  (define (mv- . sdefs) (apply mv - + sdefs))
  (define (mv* . sdefs) (apply mv * / sdefs))
  (define (mv/ . sdefs) (apply mv / * sdefs))

  (alias tt+ mv+)
  (alias tt- mv-)
  (alias tt* mv*)
  (alias tt/ mv/)

  ;; Resolves input context with an arc shifted by the seq value,
  ;; effectively moving a different slice of time into this one.
  (define (mv-math-impl math-fn inv-math-fn)
    (let ([mul? (or (eq? math-fn *) (eq? math-fn /))])
      (define (move-events delta)
        (lambda (context)
          (let ([e (event-move (context-event context) delta math-fn)]
                [sus-spread (lambda (s) (math-fn (abs delta) s))])
            (if mul? (event-update e :sustain sus-spread 1/8) e))))
      (lambda (context seq)
        (let* ([old-arc (context-arc context)]
               [val (eval-seq-empty seq (arc-start old-arc) context)])
          (cond
            ((is-rest? val) (context-resolve context))
            ((not (number? val)) (error 'mv "number" val))
            (else
              (let* ([new-arc (arc-math old-arc inv-math-fn val)]
                     ;; When we flip time, start/end exclusivity is messed up!
                     [inverse (and mul? (< val 0))]
                     [new-arc (if inverse (arc-widen new-arc 1/128) new-arc)]
                     [shifted (rearc context new-arc)]
                     [shifted (context-resolve shifted)]
                     [shifted (context-map (move-events val) shifted)]
                     [shifted (context-sort shifted)])
                (context-trim (rearc shifted old-arc)))))))))

  ;;-------------------------------------------------------------------
  ;; Swing - implemented as a sine wave, so that notes off the main beat
  ;; are moved progressively more as they get closer to it.
  (define (swing period amount)

    (define (mover context)
      (let* ([period (eval-seq period context)]
             [amount (eval-seq amount context)]
             [now (context-now context)]
             [ev (context-event context)]
             [b (event-beat ev)]
             [offset (+ b (* 3 (/ period 2)))]
             [t (+ b (range-sine (* 2 period) 0 (* amount period) offset))]
             [sus (event-get ev ':sustain #f)])
        (if sus
            (event-set-multi ev (:beat t) (':sustain (- sus (- t b))))
            (event-set-multi ev (:beat t)))))

    (unless (between? amount 0.0 1.001)
      (error 'swing "amount should be in the range 0 <-> 1" amount))

    (lambda (context)
      (let* ([s (context-start context)]
             [e (context-end context)]
             [c (context-resolve (rearc context (make-arc (- s period) e)))])
        (context-trim (rearc (context-map mover c) (make-arc s e))))))

  ;;-------------------------------------------------------------------
  ;; Taps is like a MIDI delay effect, but it can operate in reverse.
  ;; The optional node arguments are applied to the taps differently.
  ;; `iterative-node` is applied once to the 1st tap, twice to the 2nd, etc.
  ;; `once-node` is applied once to all taps but not the original.
  (define* (taps period num [/opt (once-node (with)) (iterative-node #f)])

    ;; Compute furthest lookahead/lookback that might be required.
    (define possible-range
      (let ([min-p (seq-meta-field period seq-meta-rng-min)]
            [max-p (seq-meta-field period seq-meta-rng-max)]
            [min-n (seq-meta-field num seq-meta-rng-min)]
            [max-n (seq-meta-field num seq-meta-rng-max)])
        (if (for-all identity (list min-p max-p min-n max-n))
            (let ([values (list (* min-p min-n)
                                (* min-p max-n)
                                (* max-p min-n)
                                (* max-p max-n))])
              (list (apply min values) (apply max values)))
            (error 'taps "period and num must specify definite ranges"
                   (list period num)))))

    ;; Builds a list of pairs of times and their indeces.
    ;; Omits the original 'src' time.
    (define (list-taps src period num start end)
      (if (zero? num) (list)
          (let* ([sign (if (> num 0) 1 -1)]
                 [time-flt (lambda (ti) (between? (car ti) start end))]
                 [time-idx (lambda (i) (cons (+ src (* (inc i) sign period))
                                             (inc i)))])
            (filter time-flt (map time-idx (iota (abs num)))))))

    ;; Sets the new time and repeatedly applies iterative-node to an event.
    ;; Has to wrap then unwrap the event in a context so iterative-node
    ;; can work on it individually.
    (define (tap-maker ev period)
      (lambda (time-and-idx)
        (let* ([t (car time-and-idx)]
               [i (cdr time-and-idx)]
               [e (event-set ev :beat t)])
          (if (eq? iterative-node #f) e
              (context-event ((apply with (repeat i iterative-node))
                              (make-context (make-arc t (+ t period)) 
                                            (list e))))))))

    ;; Builds a list of events (the taps) based on the context's current event.
    (define (build-taps start end)
      (lambda (context)
        (let* ([t (context-now context)]
               [period (eval-seq period context)]
               [num (eval-seq num context)]
               [times-and-indeces (list-taps t period num start end)])
          (map (tap-maker (context-event context) period) times-and-indeces))))

    ;; Just catches a common error (reversing period and num).
    (if (and (number? num) (not (integer? num)))
        (error 'taps "number of taps should be an integer" num))

    (lambda (context)
      (let* ([orig-arc (context-arc context)]
             [s (arc-start orig-arc)]
             [e (arc-end orig-arc)]
             [a (make-arc (- s (apply max 0 possible-range))
                          (- e (apply min 0 possible-range)))]
             [c (context-resolve (rearc context a))]
             [c-taps (context-map (build-taps s e) c append)])

        (contexts-merge
         (rearc c orig-arc)
         (once-node (rearc c-taps orig-arc))))))

  ;;-------------------------------------------------------------------
  ;; Flips time of events within each chunk.
  ;; e.g. with chunk = 2:
  ;; 0.1 -> 1.9 and vice versa.
  ;; 2.1 -> 3.9 and vice versa
  ;; 1 -> 1
  ;; TODO: I think this requests more from its source than needed, but
  ;; it's hard to get it right at chunk boundaries. Investigate.
  (define (flip-time chunk)

    (define (flip-chunked x)
      (let* ([x-trunc (round-down x chunk)]
             [x-mod (- x x-trunc)])
        (+ x-trunc (abs (- x-mod chunk)))))

    (define (move-event start end)
      (lambda (context)
        (let* ([e (context-event context)]
               [t (flip-chunked (event-beat e))])
          (if (between? t start end)
              (event-set e time-key t)
              (list))))) ;; empty events are ignored by context-map

    (lambda (context)
      (let* ([s (- (context-start context) chunk)]
             [e (round-up (context-end context) chunk)]
             [c (context-resolve (rearc context (make-arc s e)))]
             [c (context-sort (context-map (move-event s e) c))])
        (context-trim (rearc c (context-arc context))))))

  ;;-------------------------------------------------------------------
  ;; Lengthens notes to stretch until the next note, up until a maximum
  ;; length. Ignores next notes that are closer than threshold.
  (define* (legato [/opt (max-length 2) (threshold 1/16) (end-nudge 0)])

    (define (lengthen c)
      (let* ([e (context-event c)]
             [start (event-beat e)]
             [threshold (+ threshold start)]
             [next (context-to-event-after c threshold)])
        (if (context-it-end? next)
            (event-set e :sustain max-length)
            (let* ([next-start (event-beat (context-event next))]
                   [delta (min (+ (- next-start start) end-nudge) max-length)])
              (event-set e :sustain delta)))))

    (unless (and (number? max-length) (positive? max-length))
      (error 'legato "max-length expected to be a positive number" max-length))

    (lambda (context)
      (lif [requested (context-resolve context)]
           (context-empty? requested) requested
           (let* ([arc (make-arc (context-start context)
                                 (+ max-length (context-end context)))]
                  [lookahead (context-resolve (rearc context arc))]
                  [lengthened (context-map lengthen lookahead)])
             (context-trim (rearc lengthened (context-arc context)))))))

  )
