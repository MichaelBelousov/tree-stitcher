(load "zig-out/lib/libbindings.so")
(define q (exec_query "((function_definition) @func)" '("/home/mike/test2.cpp")))
; (display (captures (match (car q))))
(display (capture-count (car q)))
(display "\n")
(display (captures (car q)))
(display "\n")
(display (id (car q)))
(display "\n")
(display (captures (car q)))
(display "\n")
; (display (list-ref (captures (car q)) 0))
; (display "\n")
(display (node (captures (car q))))
(display "\n")
(display (tree (node (captures (car q)))))
(display "\n")
(display (ts_node_string (node (captures (car q)))))
(display "\n")
