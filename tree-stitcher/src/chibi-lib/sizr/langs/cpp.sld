(define-library (sizr langs cpp)
  (import
    (sizr langs support)
    (scheme base)
    (scheme read)
    (scheme write))
  ;; kind of want to export everything from cpp.sld...

  (export 
    ;fields
    type:
    declarator:
    parameters:
    body:
    value:
    arguments:
    function:

    ; nodes
    primitive_type
    number_literal
    identifier
    parameter_list
    compound_statement
    compound_statement
    return_statement
    argument_list
    call_expression
    init_declarator
    function_declarator
    function_definition
    declaration
    comment
  )

  (include "cpp.scm"))

