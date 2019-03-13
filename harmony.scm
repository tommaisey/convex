#!chezscheme ;; Needed for symbols like 5th

(library (harmony)
  (export
   ;; 5th triad sus2 sus4 6th 7th 9th 11th 13th
   ;; minor major harmMinor pentNeutral pentMajor pentMinor
   ;; blues dorian phrygian lydian mixolydian locrian wholeTone
   ;; chromatic arabicA arabicB japanese ryukyu spanish
   ;; I II III IV V VI VII VIII IX X XI XII
   ;; Ab A A+ Bb B C C+ Db D D+ Eb E F F+ Gb G G+

   :tuning :octave
   :root :midinote
   :scale :scale-degree
   :chord-shape :chord-degree
   :scd :chd :chs

   event-with-freq
   chord-semitone
   chord-shape)

  (import (scheme) (event) (for (utilities) expand))

  (define (midicps midi freqA)
    (* freqA (expt 2 (/ (- midi 69) 12))))

  ;; TODO: get defaults for :octave, :scale, :chord-shape etc from context defaults.
  (define (event-with-freq e)
    (alist-let
     e ([freq ':freq #f]
	[midi :midinote #f])
     (cond
      (freq freq)
      (midi (midicps midi 440))
      (else
       (alist-let
	e ([oct :octave 0]
	   [root :root 0]
	   [scale :scale minor]
	   [sc-deg :scale-degree 0]
	   [ch-deg :chord-degree 0]
	   [ch-shape :chord-shape triad])
	(let* ([s (chord-semitone oct sc-deg ch-deg ch-shape scale)]
	       [f (midicps (+ 60 root s) 440)])
	  (event-remove-multi (event-set e ':freq f)
			      (list :scale :chord-shape :octave :root))))))))

  ;; Gets the semitone of a chord with a particular root (scale-degree),
  ;; chord shape, scale shape and octave. Semitone is normalised to 0 = middle C.
  (define (chord-semitone octave root-scale-deg chord-deg shape scale)
    (let* ([sc-len (shape-len scale)]
	   [sh-len (shape-len shape)]
	   [scale  (shape-degrees scale)]
	   [shape  (shape-degrees shape)]
	   [sh-idx (mod chord-deg sh-len)]
	   [sh-deg (list-nth shape sh-idx)]
	   [sc-deg (+ root-scale-deg sh-deg)]
	   [sc-idx (mod sc-deg sc-len)]
	   [oct-overflow (+ (exact (truncate (/ chord-deg sh-len)))
			    (exact (truncate (/ sc-deg sc-len))))]
	   [semitone (list-nth scale sc-idx)])
      ;; (println (format "sh-idx: ~A, sh-deg: ~A, shape: ~A" sh-idx sh-deg shape))
      ;; (println (format "sc-idx: ~A, sc-deg: ~A, scale: ~A, semitone: ~A" sc-idx sc-deg scale semitone))
      ;; (println (format "oct-overflow: ~A" oct-overflow))
      (+ semitone
	 (* oct-overflow 12)
	 (* octave 12))))

  (define (chord-shape root-scale-deg shape scale)
    (map (lambda (deg) (chord-semitone 0 root-scale-deg deg shape scale))
	 (iota (length (cadr shape)))))
  
  ;; Event key definitions
  (define :octave ':octave)
  (define :midinote ':midinote)
  (define :root ':root)
  (define :scale ':scale)
  (define :tuning ':tuning)
  (define :chord-shape ':chord-shape)
  (define :scale-degree ':scale-degree)
  (define :chord-degree ':chord-degree)
  (define :scd :scale-degree)
  (define :chd :chord-degree)
  (define :chs :chord-shape)

  ;;------------------------------------------------------
  ;; Used for chords and scales
  (define-record-type shape
    (fields (immutable name) ;; symbol
	    (immutable degrees) ;; list
	    (immutable len)))  ;; number

  ;; Defaults used in this file, but replaced in top-level below.
  (define triad (make-shape 'triad '(0 2 4) 3))
  (define minor (make-shape 'minor '(0 2 4 5 7 8 10) 7))

  (define-syntax def-shape
    (syntax-rules ()
      ((_ name lst)
       (defpattern name (make-shape 'name 'lst (length 'lst))))))

  ;;------------------------------------------------------
  ;; These are added to the top-level environment so they can
  ;; be distinguished from functions in a pdef. They must come
  ;; last in this file.
  ;; Chord shape definitions (in degrees of current scale)
  (def-shape 5th   (0 4))
  (def-shape triad (0 2 4))
  (def-shape sus2  (0 3 4)) ;; TODO: what should this be? placeholder
  (def-shape sus4  (0 3 4))
  (def-shape 6th   (0 2 4 5))
  (def-shape 7th   (0 2 4 6))
  (def-shape 9th   (0 2 4 8))
  (def-shape 11th  (0 2 4 10))
  (def-shape 13th  (0 2 4 12))

  ;; Scale shape definitions
  (def-shape major       (0 2 4 5 7 9 11))
  (def-shape minor       (0 2 4 5 7 8 10))
  (def-shape harmMinor   (0 2 4 5 7 8 11))
  (def-shape pentNeutral (0 2 5 7 10))
  (def-shape pentMajor   (0 2 4 7 9))
  (def-shape pentMinor   (0 3 5 7 10))
  (def-shape blues       (0 3 5 6 7 10))
  (def-shape dorian      (0 2 3 5 7 9 10))
  (def-shape phrygian    (0 1 3 5 7 8 10))
  (def-shape lydian      (0 2 4 6 7 9 11))
  (def-shape mixolydian  (0 2 4 5 7 9 10))
  (def-shape locrian     (0 1 3 5 6 8 10))
  (def-shape wholeTone   (0 2 4 6 8 10))
  (def-shape arabicA     (0 2 3 5 6 8 9 11))
  (def-shape arabicB     (0 2 4 5 6 8 10))
  (def-shape japanese    (0 4 6 7 11))
  (def-shape ryukyu      (0 4 5 7 11))
  (def-shape spanish     (0 1 3 4 5 6 8 10))
  (def-shape chromatic   (0 1 2 3 4 5 6 7 8 9 10 11))
  
  (defpattern Gb -6)
  (defpattern G  -5)
  (defpattern G+ -4)
  (defpattern Ab -4)
  (defpattern A  -3)
  (defpattern A+ -2)
  (defpattern Bb -2)
  (defpattern B  -1)
  (defpattern C  0)
  (defpattern C+ 1)
  (defpattern Db 1)
  (defpattern D  2)
  (defpattern D+ 3)
  (defpattern Eb 3)
  (defpattern E  4)
  (defpattern F  5)
  (defpattern F+ 6)

  (defpattern I    0)
  (defpattern II   1)
  (defpattern III  2)
  (defpattern IV   3)
  (defpattern V    4)
  (defpattern VI   5)
  (defpattern VII  6)
  (defpattern VIII 7)
  (defpattern IX  8)
  (defpattern X    9)
  (defpattern XI   10)
  (defpattern XII  11)
  )