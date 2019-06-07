;; -*- geiser-scheme-implementation: chez-*-
;;----------------------------------------------------------
;; Rhythm helper functions
;; ---------------------------------------------------------
(library (rhythm)
  (export
   snap-next
   snap-next2
   snap-prev
   snap-prev2
   snap-nearest
     
   make-euclid
   euclid-num-steps
   euclid-num-hits
   euclid-offset)

  (import (chezscheme) (utilities) (event))

  ;; Snap a value to the next number divisible by divisor,
  ;; if `beat` isn't already cleanly divisible by divisor.
  (define (snap-next beat divisor)
    (let ([overlap (mod beat divisor)])
      (if (zero? overlap) beat (+ (- divisor overlap) beat))))

  ;; Snap a value to the next number divisible by divisor,
  ;; even if 'beat' is cleanly divisible by divisor.
  (define (snap-next2 beat divisor)
    (let ([overlap (mod beat divisor)])
      (+ (- divisor overlap) beat)))

  ;; Snap a value to the previous number divisible by divisor,
  ;; if 'beat' isn't already cleanly divisible by divisor
  (define (snap-prev beat divisor)
    (let ([overlap (mod beat divisor)])
      (- beat overlap)))

  ;; Snap a value to the previous number divisible by divisor,
  ;; even if 'beat' is cleanly divisible by divisor
  (define (snap-prev2 beat divisor)
    (let ([prev (snap-prev beat divisor)])
      (if (= prev beat) (- beat divisor) prev)))

  ;; Snap to the next or previous divisor, whichever's closer.
  (define (snap-nearest beat divisor)
    (let* ([overlap (mod beat divisor)]
	   [prev (- beat overlap)])
      (if (>= overlap (* 0.5 divisor))
	  (+ prev divisor) prev)))

  ;;-----------------------------------------------------------------
  ;; Euclidean patterns
  ;;-----------------------------------------------------------------
  ;; Parameters for a euclidean rhythm
  (define-record euclid (num-steps num-hits offset))

  ;; This version would always result in a hit on the last step,
  ;; but the usual expectation is that it's on the first step
  ;; TODO: is this necessary? Wouldn't just (add1 offset) work?
  (define (euclid-normalise-offset e)
    (let ([new-offset (mod (add1 (euclid-offset e)) (euclid-num-steps e))])
      (make-euclid (euclid-num-steps e) (euclid-num-hits e) new-offset)))

  ;; non-iterative derivation of this algorithm:
  ;; http://computermusicdesign.com/simplest-euclidean-rhythm-algorithm-explained/
  (define (euclidean-hit? step e)
    (check-type euclid? e "Parameter 'e' must be a euclidean record")
    
    (let* ([e      (euclid-normalise-offset e)]
	   [hits   (euclid-num-hits e)]
	   [steps  (euclid-num-steps e)]
	   [offset (euclid-offset e)]
	   ;; put bucket in state as if it had done N = offset iterations 
	   [bucket (mod (* hits (- steps offset)) steps)]
	   ;; compute state of bucket just before the requested step
	   [bucket (+ bucket (* hits (mod step steps)))])
      
      (not (eqv? (quotient bucket steps)
		 (quotient (+ bucket hits) steps)))))
  ); end module 'rhythm'