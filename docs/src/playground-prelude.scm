
;; ; this causes a hang in the garbage collector?
(import (sizr transform))
(import (sizr langs cpp))

;; FIXME: figure out why arguments to this macro were being expanded
;; when defined in the library, so this can go back in the library
(define-syntax transform
  (syntax-rules ()
    ((transform from to paths)
       (let* ((query-str (expr->string (quote from)))
              (query-str-rooted (string-append "(" query-str " @__root)"))
              (r (exec_query query-str-rooted paths)))
       (transform_ExecQueryResult r (quote to))))))

(define in-playground #t)
(define playground-workspace '("/target.txt"))

