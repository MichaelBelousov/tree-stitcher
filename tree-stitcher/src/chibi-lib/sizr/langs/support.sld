(define-library (sizr langs support)
  (import
    (scheme base)
    (scheme eval)
    (chibi string)
    (srfi 125)) ;; hash tables
  (export 
    define-simple-node
    define-debug-node
    field?
    define-defaultable-node
    asterisk-ize-symbol
    define-surrounded-node
    define-defaultable-surrounded-node
    process-children
    define-field
    define-complex-node)
  (include "support.scm"))
