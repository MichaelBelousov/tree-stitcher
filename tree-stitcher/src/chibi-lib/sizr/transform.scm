
(define (expr->string e)
  (call-with-port
    (open-output-string)
    (lambda (out)
      (write e out)
      (get-output-string out))))

(define (string->expr s)
  (read (open-input-string s)))

(define-syntax exec_query2
  (syntax-rules ()
    ; is this hygienic?
    ((exec_query2 exp path)
       (map (lambda (c) (string->expr (ts_node_string (node (captures c)))))
            (matches_ExecQueryResult (exec_query (expr->string (quote exp)) '(path)))))))

; TODO: add # to use outer symbols in a tree-sitter query
; (((function_definition declarator: (_ (identifier) @name)) @func)
;   (#starts-with-in_? @name))
(define-syntax transform
  (syntax-rules ()
    ; is this hygienic?
    ((transform from to paths)
       (let* ((query-str (expr->string (quote from)))
              (query-str-rooted (string-append "(" query-str " @__root)"))
              (r (exec_query query-str-rooted paths)))
       ;; need get all text between the captured nodes
       (transform_ExecQueryResult r (quote to))))))

(define s-indent "  ")

;; FIXME: do this in the bindings
(define (ast->string ast)
  (call-with-port
    (open-output-string)
    (lambda (out)
      (define indent "")
      (define (func node)

        (if (string? node)
          (begin
            (write-string node out)
            (write-char #\space out)
            (cond
              ((string=? node "{")
               (begin (set! indent (string-append indent s-indent))
                      (write-char #\newline out)
                      (write-string indent out)))
              ((string=? node ";")
               (begin (write-char #\newline out)
                      (write-string indent out)))
              ((string=? node "}")
               (begin ;(set! indent (substring indent (string-length s-indent)))
                      (write-char #\newline out)
                      (write-string indent out))))))


        (if (and (pair? node) (not (null? node)))
          (begin (func (car node))
                 (func (cdr node))))
        (get-output-string out))
      (func ast))))
