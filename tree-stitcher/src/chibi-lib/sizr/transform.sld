(define-library (sizr transform)
  (import
    (scheme base)
    ; (scheme file)
    (scheme read)
    (scheme write))
  (export transform ast->string expr->string string->expr)

  ;; bindings seem unreachable without this?
  ;; FIXME: see how eval.sld works, maybe importing (meta) will suffice?
  (begin
    (define exec_query exec_query)
    (define transform_ExecQueryResult transform_ExecQueryResult))

  (include "transform.scm"))
