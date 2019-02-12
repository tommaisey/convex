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
;; a raw event list - see pipeline-node) and returning a new one
;; with a filtered event list. While it would be simpler if it returned
;; a lambda taking an individual event, we want filters to be able to
;; recognise sequential patterns of events.
;;
;; Transformers also take a context/event-list, and do something to
;; each of the events, returning a new list.
;; ------------------------------------------------------------

(library (event-dsl)
  (export to is any-of all-of none-of phrase
	  change morph-all shadow-all morph-if shadow-if)

  (import (chezscheme) (utilities) (event) (context)
	  (c-vals) (srfi s26 cut))
  ;;---------------------------------------------------------
  ;; Takes either a key (shorthand for (this key #f)) or a c-val.
  ;; BEWARE: what if we want to check for values of #f?
  (define-syntax is
    (syntax-rules ()
      ((_ key/getter pred args ...)
       (lambda (context)
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

  ;; Subtract the events matched by each filter from the input.
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
      (let* ([columns  (map (cut sort event-before? <>) ll)]
	     [patterns (columns-to-rows columns)])
	(concatenate (filter (cut sorted? event-before? <>) patterns))))
    (lambda [events]
      (concatenate (map (cut <> events) filters))))

  ;;-----------------------------------------------
  ;; Returns the alist cell to update an event. 
  (define-syntax to
    (syntax-rules ()
      ((_ key value)
       (lambda (context)
	 (check-type symbol? key "First argument of 'to' must be a key.")
	 (cons key (get-c-val value context))))))

  ;; Returns the context's current event with the changes
  ;; of all the to-fns applied (see 'to' above). 
  (define (change . to-fns)
    (lambda (context)
      (let ([fn (lambda (n to-fn) (cons (to-fn context) n))])
	(fold-left fn (context-event context) to-fns))))

  ;;------------------------------------------------------
  ;; Top level transformation statements. Typically pred would
  ;; be 'is', 'all-of', 'phrase' etc. change-fn would be 'change'.
  (define (morph-all change-fn)
    (lambda (context)
      (context-map change-fn context)))
  
  (define (morph-if pred change-fn)
    (lambda (context)
      (define (update c)
	(if (pred c) (change-fn c) (context-event c)))
      (context-map update context)))
  
  (define (shadow-all change-fn)
    (lambda (context)
      (contexts-merge context ((morph-all change-fn) context))))
  
  (define (shadow-if pred change-fn)
    (lambda (context)
      (let* ([copied (context-filter pred context)]
	     [changed (context-map change-fn copied)]
	     [trimmed (context-trim changed)])
	(contexts-merge context trimmed))))

  ) ; end module 'event dsl'
