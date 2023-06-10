#include <chibi/eval.h>
#include <tree_sitter/api.h>

// TODO: use -femit-h instead, but it's not available yet

// opaque
struct ExecQueryResult {};

const struct ExecQueryResult** exec_query(const char* query, const char** paths);

void free_ExecQueryResult(struct ExecQueryResult*);
const TSQueryMatch** matches_ExecQueryResult(struct ExecQueryResult*);
sexp transform_ExecQueryResult(struct ExecQueryResult*, sexp substitution, sexp ctx);

const char* node_source(TSNode, const struct ExecQueryResult*);

sexp node_to_ast(sexp ctx, TSNode node, const struct ExecQueryResult*);

