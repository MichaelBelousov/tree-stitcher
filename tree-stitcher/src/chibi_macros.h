#include <chibi/eval.h>

sexp_sint_t _sexp_unbox_fixnum(sexp s);
sexp _sexp_car(sexp s);
sexp _sexp_cdr(sexp s);
long _sexp_length_unboxed(sexp s);
char* _sexp_string_data(sexp s);
unsigned _sexp_string_size(sexp s);
sexp _sexp_symbol_to_string(sexp ctx, sexp s);
void _sexp_debug(sexp ctx, const char* message, sexp s);
sexp _sexp_eval(sexp ctx, sexp s, sexp env);
sexp _sexp_context_env(sexp ctx);
sexp _sexp_make_env(sexp ctx);
int _sexp_pairp(sexp p);
int _sexp_symbolp(sexp s);
int _sexp_nullp(sexp s);
int _sexp_exceptionp(sexp s);
int _sexp_stringp(sexp s);
sexp _sexp_cons(sexp ctx, sexp a, sexp b);
sexp _sexp_nreverse(sexp ctx, sexp ls);
sexp _sexp_reverse(sexp ctx, sexp ls);
sexp _sexp_append2(sexp ctx, sexp a, sexp b);
sexp _sexp_list2(sexp ctx, sexp a, sexp b);
void _sexp_print_exception(sexp ctx, sexp exn, sexp out_port);
void _sexp_write(sexp ctx, sexp obj, sexp port);
void _sexp_write_char(sexp ctx, char c, sexp port);
void _sexp_flush(sexp ctx, sexp port);
sexp _sexp_current_error_port(sexp ctx);
sexp _sexp_current_output_port(sexp ctx);
sexp _sexp_equalp(sexp ctx, sexp a, sexp b);
sexp _sexp_define_foreign(sexp ctx, sexp env, const char* name, int num_args, sexp_proc1 func);

// non-macro translation helpers
void _set_sexp_car(sexp ls, sexp in_car);

