;; FIXME: loads from cwd, make load-rel or something
;; use real imports
(load "./src/langs/cpp.scm")
(load "./src/query.scm")
(load "./tests/support.scm")

(define workspace '("./tests/cpp/simple1.cpp"))

(test-group "cpp-simple"

  (test-query
    (dedent "
    int f() { return 5; }
    int main() {
        int a = f();
        return a;
    }")
    (transform
      ((function_definition declarator: (_ (identifier) @name)) @func)
      (@func)
      workspace))

  (test-query
    (dedent "
    f
    main
    ")
    (transform
      ((function_definition declarator: (_ (identifier) @name)) @func)
      (@name)
      workspace))

  (test-query
    (dedent "
    int foo() { return 5; }
    int foo() {
        int a = f();
        return a;
    }")
    (transform
      ((function_definition declarator: (_ (identifier) @name)) @func)
      (@func declarator:
             (function_declarator
               declarator: (identifier "foo")
               parameters: (parameter_list)))
      workspace))

  (test-query
    (dedent "
    int foo() { return 5; }
    int foo() {
        int a = f();
        return a;
    }")
    (transform
      ((function_definition declarator: (_ (identifier) @name)) @func)
      (@func declarator:
             (function_declarator
               declarator: (identifier "foo")))
      workspace))

  (test-query
    "int in_a, in_b"
    (transform
      ((function_definition declarator: (_ (identifier) @name)) @func)
      (@func declarator:
             (function_declarator
               declarator: (identifier "foo")))
      (string-workspace "int a, b;")))

  ;; FIXME: stupid test
  ;; (test-query
  ;;   (dedent "
  ;;   int f() {
  ;;     f
  ;;   }

  ;;   const int x = 5;

  ;;   int main() {
  ;;     main
  ;;   }")
  ;;   (transform
  ;;     ((function_definition declarator: (_ (identifier) @name)) @func)
  ;;     (ast->string (@func body: `("{" (unquote (@name)) "}")))
  ;;     workspace))

  ;; (test-query
  ;;   (dedent "
  ;;   // deleted: f

  ;;   const int x = 5;

  ;;   // deleted: main
  ;;   ")
  ;;   (transform
  ;;     ((function_definition declarator: (_ (identifier) @name)) @func)
  ;;     (ast->string (comment "// deleted: " (@name)))
  ;;     workspace))

  ) ; end test-group "cpp-simple"

