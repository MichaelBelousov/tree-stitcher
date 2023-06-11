;; tree-sitter like lisp expressions for tree-stitcher augmentations

(define-syntax define-simple-node
  (syntax-rules ()
    ((define-simple-node name)
      (define (name . children)
        (cons 'name children)))))

(define-syntax define-debug-node
  (syntax-rules ()
    ((define-simple-node name)
      (define (name . children)
        (display name)
        (display ":\n")
        (display children)
        (newline)
        (cons name children)))))

(define (field? x)
  (and (symbol? x)
       (string-suffix? ":" (symbol->string x))))

;; can I make defaultable nodes support only fields?
(define-syntax define-defaultable-node
  (syntax-rules ()
    ((define-defaultable-node name default-children ...)
      (define (name . children)
        (if (null? children)
            '(name default-children ...)
            (cons 'name children))))))

(define (asterisk-ize-symbol sym)
  (string->symbol (string-append (symbol->string sym) "*")))

;; defines both name and name* functions, the latter being a short-hand
(define-syntax define-surrounded-node
  (syntax-rules ()
    ((define-surrounded-node name (left ...) (right ...))
      (begin
        ;; (if (not (list-prefix? left children)) (error "invalid"))
        ;; (if (not (list-suffix? right children)) (error "invalid children for this node"))
        (define (name . children)
          (cons 'name children))
        ;; how is it that I can't find anyone describing how to do this?
        ;; eval works for now to prevent manually needing to write it out...
        (eval `(define (,(asterisk-ize-symbol 'name) . children)
                 `(name left ... ,@children right ...)))))))

;; like define-surrounded-node, but no children for the non-special
;; function defaults to the left and right tokens
(define-syntax define-defaultable-surrounded-node
  (syntax-rules ()
    ((define-defaultable-surrounded-node name (left ...) (right ...))
      (begin
        ;; (if (not (list-prefix? left children)) (error "invalid"))
        ;; (if (not (list-suffix? right children)) (error "invalid children for this node"))
        (define (name . children)
          (if (null? children)
              '(name left ... right ...)
              (cons 'name children)))
        ;; how is it that I can't find anyone describing how to do this?
        ;; eval works for now to prevent manually needing to write it out...
        (eval `(define (,(asterisk-ize-symbol 'name) . children)
                 `(name left ... ,@children right ...)))))))

;; FIXME: a hashtable doesn't actually work, because it's possible to have multiple nodes
;; marked with the same field on one parent (e.g. multi-declarators in C)
(define (process-children children)
  ;; returns field-hash or 'has-extra
  (define (impl field-hash args)
    (cond ((null? args) field-hash)
          ((and (field? (car args))
                (null? (cdr args)))
           (error "field argument not followed by node" (car args)))
          ;; TODO: add nice error when field isn't followed by anything
          ((field? (car args))
           (hash-table-set! field-hash (car args) (cadr args))
           (impl field-hash (cddr args)))
          (else 'has-extra)))
  (impl (make-hash-table symbol=?) children))

(define-syntax define-field
  (syntax-rules ()
    ((define-field fields field-name)
     ;; UNHYGIENIC
     `(field-name ,(hash-table-ref         fields field-name)))
    ((define-field fields field-name default)
     `(field-name ,(hash-table-ref/default fields field-name default)))))

;; NEXT: The idea here, is that an invocation containing only field arguments
;; should still be able to use a "default", even if some field arguments are required
;; NOTE: these are not exactly like tree-sitter ASTs, you can't have multiple field arguments
(define-syntax define-complex-node
  (syntax-rules ()
    ((_ name ((field-args ...) ...))
     ;; FIXME: make syntax error if name is not symbol?
     (define (name . children)
       (let* ((fields (process-children children)))
         (if (equal? fields 'has-extra)
             (cons 'name children)
             `(name ,@(define-field fields field-args ...) ...)))))))

;;; technically there is no well-defined way to specify merge points of trees
;;; in tree-sitter ASTs, even `field: (blah)` doesn't work because a grammar
;;; may contain arbitrarily placed fields on the same node
;;; so this is restricted to bailing out if it encounters the same field not in
;;; sequence, and replaces all of that field in sequence when a field is encountered
(define (ast-replace ast . replacements)
  '())

