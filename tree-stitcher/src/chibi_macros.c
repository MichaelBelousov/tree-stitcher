#include "chibi_macros.h"

// a lot of the macros and even the sexp struct act up in zig's cImports, so here are manual bindings
sexp_sint_t _sexp_unbox_fixnum(sexp s) { return sexp_unbox_fixnum(s); }
sexp _sexp_car(sexp s) { return sexp_car(s); }
sexp _sexp_cdr(sexp s) { return sexp_cdr(s); }
long _sexp_length_unboxed(sexp s) { return sexp_length_unboxed(s); }
char* _sexp_string_data(sexp s) { return sexp_string_data(s); }
unsigned _sexp_string_size(sexp s) { return sexp_string_size(s); }
sexp _sexp_symbol_to_string(sexp ctx, sexp s) { return sexp_symbol_to_string(ctx, s); }
void _sexp_debug(sexp ctx, const char* message, sexp s) { sexp_debug(ctx, message, s); }
sexp _sexp_eval(sexp ctx, sexp s, sexp env) { return sexp_eval(ctx, s, env); }
sexp _sexp_context_env(sexp ctx) { return sexp_context_env(ctx); }
int _sexp_pairp(sexp s) { return sexp_pairp(s); }
int _sexp_symbolp(sexp s) { return sexp_symbolp(s); }
int _sexp_nullp(sexp s) { return sexp_nullp(s); }
int _sexp_exceptionp(sexp s) { return sexp_exceptionp(s); }
int _sexp_stringp(sexp s) { return sexp_stringp(s); }
sexp _sexp_cons(sexp ctx, sexp a, sexp b) { return sexp_cons(ctx, a, b); }
sexp _sexp_nreverse(sexp ctx, sexp ls) { return sexp_nreverse(ctx, ls); }
sexp _sexp_reverse(sexp ctx, sexp ls) { return sexp_reverse(ctx, ls); }
sexp _sexp_append2(sexp ctx, sexp a, sexp b) { return sexp_append2(ctx, a, b); }
sexp _sexp_list2(sexp ctx, sexp a, sexp b) { return sexp_list2(ctx, a, b); }
void _sexp_print_exception(sexp ctx, sexp exn, sexp out_port) { sexp_print_exception(ctx, exn, out_port); }
void _sexp_write(sexp ctx, sexp obj, sexp port) { sexp_write(ctx, obj, port); }
void _sexp_write_char(sexp ctx, char c, sexp port) { sexp_write_char(ctx, c, port); }
void _sexp_flush(sexp ctx, sexp port) { sexp_flush(ctx, port); }
sexp _sexp_current_error_port(sexp ctx) { return sexp_current_error_port(ctx); }
sexp _sexp_current_output_port(sexp ctx) { return sexp_current_output_port(ctx); }
sexp _sexp_equalp(sexp ctx, sexp a, sexp b) { return sexp_equalp(ctx, a, b); }

// non-macro translation helpers
void _set_sexp_car(sexp ls, sexp in_car) { sexp_car(ls) = in_car; }

