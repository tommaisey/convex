;; -*- geiser-scheme-implementation: chez-*-
;; ------------------------------------------------------------
;; Macros/functions that implement a DSL for specifying/transforming
;; musical patterns. We don't want beginners to ever have to type
;; 'lambda' or scary words like that. We'd prefer that they don't
;; know they're programming at all.
;;
;; DSL basically consists of two parts: filters and transformers.
;;
;; Filters return lambdas taking a context (or, for repl convenience,
;; a raw note list - see pipeline-node) and returning a new one
;; with a filtered note list. While it would be simpler if it returned
;; a lambda taking an individual note, we want filters to be able to
;; recognise sequential patterns of notes.
;;
;; Transformers also take a context/note-list, and do something to
;; each of the notes, returning a new list.
;; ------------------------------------------------------------

(library (note-dsl)
  (export to is any-of all-of none-of phrase
	  change-all copy-all
	  change-if copy-if)

  (import (chezscheme) (note) (utilities) (srfi s26 cut))

  ;;--------------------------------------------------------
  ;; Abstracts away the concept of a 'context' from the user.
  ;; Inside a macro using this (currently just 'is' and 'to') it's
  ;; easy to access properties of the current note with 'this' and
  ;; neighbouring notes with 'next'.
  (define-syntax context-node
    (lambda (x)
      (syntax-case x ()
	((_ [context notes-id window-id] body rest ...)
	 (with-syntax ([this    (datum->syntax (syntax context) 'this)]
		       [next    (datum->syntax (syntax context) 'next)]
		       [nearest (datum->syntax (syntax context) 'nearest)])
	   (syntax
	    (lambda (context)
	      (define (get c k d)
		(note-get (context-note c) k d))
	      (define (next idx k d)
		(get (context-move context idx) k d))
	      (define (nearest time k d)
		(get (context-to-closest-note context time) k d))
	      (define (this k d) (get context k d))
	      (begin body rest ...)))))

	((_ [context] body rest ...)
	 (syntax (context-node [context notes window] body rest ...)))
	((_ [context notes-id] body rest ...)
	 (syntax (context-node [context notes-id window] body rest ...))))))

  ;;---------------------------------------------------------
  ;; Takes either a key (shorthand for (this key #f) or a lambda
  ;; that returns a value given a context, e.g. (next +1 :freq)
  ;; BEWARE: what if we want to check for values of #f?
  (define-syntax is
    (syntax-rules ()
      ((_ key/getter pred args ...)
       (context-node [context]
	 (let ([v (if (procedure? key/getter)
		      (key/getter context)
		      ((this key/getter #f) context))])
	   (and v (pred v args ...)))))))
  
  ;; Find the intersection of the inner filters
  (define (all-of . preds)
    (lambda (context)
      ((combine-preds preds for-all) context)))

  ;; Find the union of the inner filters.
  (define (any-of . preds)
    (lambda (context)
      ((combine-preds preds for-any) context)))

  ;; Subtract the notes matched by each filter from the input.
  (define (none-of . preds)
    (lambda (context)
      ((combine-preds preds for-none) context)))

  ;; Takes: a list of N filters (e.g. has, any)
  ;; Returns: a filter finding sequences matching the inputs.
  ;; This doesn't work very well currently. Will need thorough
  ;; unit tests.
  ;; TODO: not updated since switched to new context model...
  (define (phrase . filters)
    (define (merge-results ll)
      (let* ([columns  (map (cut sort note-before? <>) ll)]
	     [patterns (columns-to-rows columns)])
	(merge-inner (filter (cut sorted? note-before? <>) patterns))))
    (lambda [notes]
      (merge-inner (map (cut <> notes) filters))))

  ;;-----------------------------------------------
  ;; Returns the alist cell to update a note. Able to
  (define-syntax to
    (syntax-rules ()
      ((_ key value)
       ; (check-type symbol? key "First argument of 'to' must be a key.")
       (context-node [context]
	 (cons key value)))))

  ;; Returns the context's current note with the changes
  ;; of all the to-fns applied (see 'to' above). 
  (define (change . to-fns)
    (lambda (context)
      (fold-left (lambda (n to-fn) (cons (to-fn context) n))
		 (context-note context) to-fns)))

  ;;------------------------------------------------------
  ;; Top level transformation statements. Typically pred would
  ;; be 'is', 'all-of', 'phrase' etc. change-fn would be 'change'.
  (define (change-if pred change-fn)
    (lambda (context)
      (let recur ([c context] [result '()])
	(if (context-complete? c)
	    (make-context (reverse result) '()
			  (context-window c))
	    (let ([f (if (pred c) change-fn context-note)])
	      (recur (context-move c 1) (cons (f c) result)))))))

  (define (change-all change-fn)
    (change-if (lambda (_) #t) change-fn))

  (define (copy-if pred change-fn)
    (lambda (context)
      (let ([original (context-notes-next context)])
	(let recur ([c context] [result '()])
	  (if (context-complete? c)
	      (make-context (merge-sorted result original note-before?) '()
			    (context-window c))
	      (recur (context-move c 1)
		     (if (pred c)
			 (cons (change-fn c) result)
			 result)))))))

  (define (copy-all change-fn)
    (copy-if (lambda (_) #t) change-fn))

  ;; Adding statements
  (define (add to-add)
    0) ; TODO: stub

  (define (add-looped loop-window to-add)
    0) ; TODO: stub

  ) ; end module 'note dsl'
