;; tree-sitter like lisp expressions for tree-stitcher augmentations

(import (scheme load))
;; FIXME: import
(load "./src/langs/support.scm")

;fields
(define type: 'type:)
(define declarator: 'declarator:)
(define parameters: 'parameters:)
(define body: 'body:)
(define value: 'value:)
(define arguments: 'arguments:)
(define function: 'function:)

;; ; nodes
(define-defaultable-node primitive_type "void")
;(define-simple-node primitive_type)
(define-simple-node number_literal)
(define (identifier name) `(identifier ,name))
;(define-simple-node identifier)
(define-defaultable-surrounded-node parameter_list ("(") (")"))
(define-simple-node compound_statement)
(define-defaultable-surrounded-node compound_statement ("{") ("}"))
(define-surrounded-node return_statement ("return") (";"))
(define-defaultable-surrounded-node argument_list ("(") (")"))
(define-complex-node call_expression
  ((function:)
   (arguments: (argument_list))
   (body: (compound_statement))))
(define-simple-node init_declarator)
(define-simple-node declaration)
(define-complex-node function_declarator
  ((declarator:)
   (parameters: (parameter_list))))
(define-complex-node function_definition
  ((type: (primitive_type))
   (declarator:)
   (body: (compound_statement))))

(define-simple-node function_definition)
(define-simple-node comment) ;; hmmmm


;; FIXME: generate these with macros
;; FIXME: children should be applied the same way as in the transform expander
;; (define (primitive_type name) `(primitive_type ,name))
;; (define (number_literal number) `(number_literal ,number))
;; (define (identifier name) `(identifier ,name))
;; (define (parameter_list . children) `(parameter_list "(" ,@children ")")) ; switch to requiring the name
;; (define (compound_statement . children) `(compound_statement "{" ,@children "}")) ; switch to requiring the name
;; (define (return_statement . children) `(return_statement ,@children))
;; (define (argument_list . children) `(argument_list ,@children))
;; (define (call_expression . children)
;;   `(function: ,(identifier "CALLER")
;;     arguments: ,(argument_list)))
;; (define (init_declarator . children)
;;     `(init_declarator
;;         declarator: ,(identifier "FOO") ;; TODO: implement required children
;;         value: ,@(cdr children))) ;; TODO: required!
;; (define (declaration . children)
;;     `(declaration
;;         type: ,(identifier "DECL_NAME") ;; TODO: implement required children
;;         declarator: ,(parameter_list)))


(display
  (eval (function_declarator
    declarator: (identifier "foo"))))
(newline)
