; FIXME: figure out how to hack sizr import resolution together
(import (sizr transform))
(import (sizr langs cpp))
(load "./tests/support.scm")

(define workspace '("./tests/cpp/template.cpp"))

(test-group "cpp-templates"

  (test-query
    (dedent "
    #include <iostream>

    template<int(*F)(void)>
    int g() {
      return F();
    }

    extern int(*external_f)(void);

    // extern can't have initializers!
    extern auto blah = [](){return 2;};

    int main() {
      external_f = [](){return 5;};
      std::cout << g<blah>() << std::endl;
      return 0;
    }")
    (transform
      ((function_definition declarator: (_ (identifier) @name)) @func)
      (@func)
      workspace))

  ) ; end test-group "cpp-simple"

