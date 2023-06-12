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
}
