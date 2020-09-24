"""
AST transformation engine prototype for Sizr transform language
"""

import ast
import libcst as cst
from typing import Optional, List, Set, Iterator, Tuple, Sequence
from functools import reduce
from .code import Query, Transform, ScopeExpr, capture_any
from .cst_util import unified_leave
from .util import tryFind, notFound
import operator


# TODO: better name
node_table = {
    cst.ClassDef: {
        'func': lambda n: True,
        'class': lambda n: True,
        'name': lambda node: node.name,
    },
    cst.FunctionDef: {
        'func': True,
    },
}

property_testers = {
    'func': lambda val, node: isinstance(node, cst.FunctionDef),
    'class': lambda val, node: isinstance(node, cst.ClassDef),
}


nesting_op_children_getter = {
    '.': lambda node: node.body.body if isinstance(node, cst.ClassDef) else (),
    '(': lambda node: node.params if isinstance(node, cst.FunctionDef) else (),
    None: lambda node: node.children
}

possible_node_classes_per_prop = {
    'type': lambda val: {},  # TODO: make a special "any" set
    'func': lambda val: {cst.FunctionDef},
    'class': lambda val: {cst.ClassDef},
    'var': lambda val: {cst.Name}
}


def elemNameFromNode(node: cst.CSTNode) -> Set[str]:
    return {
        cst.FunctionDef: lambda: {node.name.value},
        cst.ClassDef: lambda: {node.name.value},
        cst.Assign: lambda: {t.target.value for t in node.targets},
    }[node.__class__]()


# future code organization
# default_prop_values = {}
# node_from_prop_builders = {cst.ClassDef: lambda props: cst.ClassDef }


class Capture:
    def __init__(self, node: cst.CSTNode, name: Optional[str] = None):
        self.node = node
        self.name = name
    # FIXME: fix CaptureExpr vs Capture[Ref?] naming
    # maybe I can leave this to be fixed by the alpha phase :)
    __repr__ = __str__ = lambda s: f'<CaptureRef|name={s.name},node={s.node}>'


class SelectionMatch:
    CaptureType = Capture

    def __init__(self, captures: List[CaptureType]):
        self.captures = captures

    # probably want capture list to be retrievable by name,
    # perhaps abstracting over int-indexable map/dict is in order
    def getCaptureByName(self, name: str) -> CaptureType:
        first, *_ = filter(lambda c: c.name == name, self.captures)
        return first

    __repr__ = __str__ = lambda s: f'<Match|{s.captures}>'


# TODO: proof of the need to clarify a datum names, as `Element` or `ProgramElement` or `Unit` or `Name`
def astNodeFromAssertion(assertion: Query, match: SelectionMatch) -> cst.CSTNode:
    if not assertion.nested_scopes:
        return
    # TODO: mass intersect possible_nodes_per_prop and and raise on multiple
    # results (some kind of "ambiguous error"). Also need to match with captured/anchored
    cur_scope, *next_scopes = assertion.nested_scopes
    cur_capture, *next_captures = match.captures
    name = cur_scope.capture.literal or cur_capture.node.name
    next_assertion = Query()
    next_assertion.nested_scopes = next_scopes
    inner = astNodeFromAssertion(next_assertion, SelectionMatch(next_captures))
    if 'class' in cur_scope.properties and cur_scope.properties['class']:
        return cst.ClassDef(
            name=cst.Name(name),
            body=cst.IndentedBlock(
                body=(
                    inner if inner is not None
                    else cst.SimpleStatementLine(body=(cst.Pass(),)),
                )
            ),
            bases=(),
            keywords=(),
            decorators=()
        )
    if 'func' in cur_scope.properties and cur_scope.properties['func']:
        # TODO: need properties to be a dictionary subclass that returns false for unknown keys
        return cst.FunctionDef(
            name=cst.Name(name),
            params=cst.Parameters(),
            body=cst.IndentedBlock(  # NOTE: wrapping in indented block may not be a good idea
                # because nesting ops like `;` may return a block in the future spec
                body=(
                    inner if inner is not None
                    else cst.SimpleStatementLine(body=(cst.Pass(),)),
                )
            ),
            decorators=(),
            asynchronous=cur_scope.properties.get(
                'async') and cst.Asynchronous(),
            # returns=None
        )
    elif cur_scope.properties.get('var') != False:
        # TODO: need properties to be a dictionary that returns false for unknown keys
        return cst.Assign(
            targets=(cst.AssignTarget(target=cst.Name(name)),),
            value=cst.Name("None")
        )
    raise Exception("Could not determine a node type from the name properties")


def dictKeysAndValues(d): return d.keys(), d.values()


def select(root: cst.CSTNode, selector: Query) -> List[SelectionMatch]:
    selected: List[SelectionMatch] = []

    # TODO: dont root search at global scope, that's not the original design
    # I'll probably need to change the parser to store the prefixing nesting op
    # NOTE: I have no idea how mypy works yet, I'm just pretending it's typescript
    # NOTE: I saw other typing usage briefly and I'm pretty sure it doesn't work this way
    def search(node: cst.CSTNode, scopes, nesting_op: Optional[str] = None, captures: Optional[List[cst.CSTNode]] = None):
        if captures is None:
            captures = []
        cur_scope, *rest_scopes = scopes
        for node in nesting_op_children_getter[nesting_op](node):
            # FIXME: autopep8 is making this really ugly... (or maybe I am)
            if ((cur_scope.capture == capture_any
                 # TODO: switch to elemNameFromNode
                 or (hasattr(node, 'name')  # TODO: prefer isinstance()
                     and cur_scope.capture.pattern.match(node.name.value) is not None))
                    # TODO: abstract to literate function "matchesScopeProps"?
                    and all(map(lambda k, v: property_testers[k](v, node),
                                *dictKeysAndValues(cur_scope.properties)))):
                next_captures = [*captures,
                                 Capture(node, cur_scope.capture.name)]
                if rest_scopes:
                    search(node, rest_scopes,
                           cur_scope.nesting_op, next_captures)
                else:
                    selected.append(SelectionMatch(next_captures))

    search(root, selector.nested_scopes)
    return selected  # maybe should have search return the result list


def destroy_selection(py_ast: cst.CSTNode, matches: Iterator[SelectionMatch] = {}) -> cst.CSTNode:
    """ remove the selected nodes from the AST, for destructive queries """

    class DestroySelection(cst.CSTTransformer):
        def __getattr__(self, attr):
            if attr.startswith('leave_'):
                return self._leave
            else:
                raise AttributeError(f"no such attribute '{attr}'")

        def _leave(self, prev: cst.CSTNode, next: cst.CSTNode) -> cst.CSTNode:
            # TODO: create a module tree from scratch for the assertion and merge the trees
            if any(lambda m: prev.deep_equals(m.captures[-1].node), matches):
                # XXX: may need to fix the lack/gain of pass in bodies...
                # return cst.RemoveFromParent()
                return cst.Pass()
            return next

    post_destroy_tree = py_ast.visit(DestroySelection())
    # bodies_fixed_tree = FixEmptyBodies().visit(post_destroy_tree)
    # fixed_tree = cst.fix_missing_locations(bodies_fixed_tree)
    fixed_tree = post_destroy_tree
    return fixed_tree


def assert_(py_ast: cst.CSTNode, assertion: Query, matches: Optional[Iterator[SelectionMatch]]) -> cst.CSTNode:
    """
    TODO: in programming `assert` has a context of being passive, not fixing if it finds that it's incorrect,
    perhaps a more active word should be chosen
    """
    if matches is None:
        matches = set()

    @ unified_leave
    class Transformer(cst.CSTTransformer):
        def _leave(self, prev: cst.CSTNode, next: cst.CSTNode) -> cst.CSTNode:
            # TODO: if unanchored assertion create a module tree from scratch
            # NOTE: in the future can cache lib cst node comparisons for speed
            target = tryFind(lambda m: prev.deep_equals(
                m.captures[-1].node), matches)
            if target is notFound:
                return next
            else:
                return astNodeFromAssertion(assertion, target)

    transformed_tree = py_ast.visit(Transformer())
    print(transformed_tree)

    return transformed_tree


# NOTE: default to print to stdout, take a cli arg for target file for now
def exec_transform(src: str, transform: Transform) -> str:
    py_ast = cst.parse_module(src)
    selection = None
    if transform.selector:
        selection = select(py_ast, transform.selector)
    if transform.destructive:
        py_ast = destroy_selection(py_ast, selection)
    if transform.assertion:
        py_ast = assert_(py_ast, transform.assertion, selection)
    result = py_ast.code
    import difflib
    diff = ''.join(
        difflib.unified_diff(
            src.splitlines(1),
            result.splitlines(1)
        )
    )
    if diff:
        print(diff)
    else:
        print('no changes!')
    return result
