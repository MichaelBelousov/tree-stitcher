;; FIXME: generate (some of) these with macros from tree-sitter's node_types.json

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
(define-complex-node declaration
  ((type: (primitive_type "int"))
   (declarator:)))

(define-simple-node comment) ;; hmmmm


