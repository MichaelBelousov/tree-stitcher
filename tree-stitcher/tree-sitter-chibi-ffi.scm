
(c-include "./bindings.h")

(define-c-struct TSNode
  ;; chibi scheme seems to be unable to handle an embedded array
  ;; ((array unsigned-int 4) context context)
  (unsigned-int context1) ; intentionally inaccessible
  (unsigned-int context2)
  (unsigned-int context3)
  (unsigned-int context4)
  ((maybe-null (pointer (const void))) id id)
  ((maybe-null (pointer (const void))) tree tree))

;; raw tree-sitter binding
(define-c string ts_node_string ((struct TSNode)))

(define-c-struct TSQueryCapture
  ((struct TSNode) node node)
  (unsigned-int index index))

(define-c-struct TSQueryMatch
  (unsigned-int id id)
  (unsigned-short pattern_index pattern-index)
  (unsigned-short capture_count capture-count)
  ((array (const TSQueryCapture) null) captures captures))

;; opaque, hence stupid hidden int property
(define-c-struct ExecQueryResult
  [finalizer: free_ExecQueryResult]
  (int _test))

(define-c (free string) node_source ((struct TSNode) ExecQueryResult))

(define-c (array (const TSQueryMatch) null) matches_ExecQueryResult (ExecQueryResult))

(define-c sexp transform_ExecQueryResult (ExecQueryResult sexp (value ctx sexp)))

(define-c
  ;; FIXME: leaking!
  ;; (free (array (pointer (const query_match)) null))
  (pointer ExecQueryResult)
  exec_query
  ((const string) (array (const string) null)))

