"""
sizr language code, currently slow and interpreted, hopefully eventually JITed
(won't be a python core at that point)
"""

# TODO: pep8

from itertools import product
import re
from .util import FrozenDict
from typing import List, Optional, Set, Dict
import libcst as cst


pattern_any = re.compile('')


class CaptureExpr:
    """an expression describing a capture"""

    def __init__(self, pattern=pattern_any, name: Optional[str] = None):
        self.pattern = pattern
        self.name = name  # name to get the capture by

    __repr__ = __str__ = lambda s: f'<{type(s).__name__}|$/{s.pattern.pattern}/{s.name if s.name is not None else ""}>'

    def __eq__(self, r):
        return self.pattern == r.pattern and self.name == r.name


class CapturedElement(CaptureExpr):
    """realized ast node from a capture expression"""

    def __init__(self, base: CaptureExpr, node: cst.CSTNode):
        super().__init__(base.pattern, base.name)
        self.node = node

    def __eq__(self, r):
        return self.pattern == r.pattern and self.name == r.name


class CaptureReference(CaptureExpr):
    """realized ast node from a capture expression"""

    def __init__(self, base: CaptureExpr, target: CapturedElement):
        super().__init__(base.pattern, base.name)
        self.target = target

    def get_name_for_match(self, match: "Match"):
        # TODO: implement backreferences
        return self.pattern.pattern


class ScopeExpr:
    def __init__(self, nesting_op: Optional[str] = None):
        self.capture = CaptureExpr()
        self.nesting_op = nesting_op
        self.properties = {}

    def __eq__(self, r):
        return (self.capture.name == r.capture.name
                and self.nesting_op == r.nesting_op
                and self.properties == r.properties)

    def __hash__(self):
        return hash((self.capture.name,
                     self.nesting_op,
                     # maybe use frozenset instead of sorted
                     tuple(sorted(self.properties.items()))))

    @property
    def _props_str(self) -> str:
        return ' '.join(
            f'{k}={v}' if not isinstance(v, bool)
            else f'{"" if v else "!"}{k}'
            for k, v, in self.properties.items())

    __repr__ = __str__ = lambda s: f'<{type(s).__name__}|{s._props_str} {s.capture} {s.nesting_op}>'


class Query:
    # TODO: can only be both an assertion or a selection when it's a Query Expression, need to clarify that
    """can be a selector or assertion when contextually on one side of a transform"""

    def __init__(self, nested_scopes: Optional[List[ScopeExpr]] = None):
        self.nested_scopes = nested_scopes or []

    __repr__ = __str__ = lambda s: f'<{type(s).__name__}|scopes={s.nested_scopes}>'

    def __bool__(self): return bool(self.nested_scopes)


# TODO: derived from import discovery, will need facility for direct references, like
# C++ includes and
class ProgramContext:
    def __init__(self):
        self.modules = []
        self.module_graph = {}  # TODO: pick a graph data module


class TransformExpr:
    def __init__(self, selector: Optional[Query] = None, assertion: Optional[Query] = None, destructive=False):
        self.selector = selector or Query()
        self.assertion = assertion or Query()
        self.destructive = destructive

    __repr__ = __str__ = lambda s: f'''<{type(s).__name__}{
        '!' if s.destructive else ''
    }|selector={s.selector},assertion={s.assertion}>'''


class Match():
    def __init__(self, elem_path: Optional[List[CapturedElement]]):
        self.elem_path = elem_path or []
        self._by_name: Dict[str, CapturedElement] = {
            s.name: s for s in self.elem_path}

    def by_name(self, name: str) -> Optional[CapturedElement]:
        return self._by_name.get(name)

    __repr__ = __str__ = lambda s: f'''<{type(s).__name__}|{s.elem_path}>'''


class TransformContext(TransformExpr):
    # XXX: maybe replace captured_nodes with direct captured_selection
    def __init__(self, base: TransformExpr, module: cst.Module):
        super().__init__(base.selector, base.assertion, base.destructive)
        self.matches: List[Match] = []
        self._init_reference_structure(module)

    def add_match(self, match: Match or List[CapturedElement]):
        if not isinstance(match, Match):
            match = Match(match)
        self.matches.append(match)

    @property
    def capture_reference_indices(self):
        # XXX: probably much better to use an actual mapping/dict
        # XXX: for now assumes capture unique capture names, in the future intersecting
        # capture names will need to be explicitly disambiguated with syntax (i.e. MyClass$1).
        # It may however be possible to use a 'fully qualified' (pathed) name so only
        # capture *references* require being unambiguous
        return filter(lambda pair: pair[0][1].capture.name == pair[1][1].capture.name,
                      product(enumerate(self.assertion.nested_scopes),
                              enumerate(self.selector.nested_scopes)))

    def _init_reference_structure(self, module: cst.Module):
        wrapper = cst.metadata.MetadataWrapper(module)
        scopes = set(wrapper.resolve(cst.metadata.ScopeProvider).values())
        # ranges = wrapper.resolve(cst.metadata.PositionProvider)
        self.references: Dict[cst.CSTNode, Set[cst.metadata.Access]] = {}
        # XXX: O(n^4)
        for scope in scopes:
            for assignment in scope.assignments:
                for ref in assignment.references:
                    for match in self.matches:
                        capture = match.elem_path[-1]
                        if ref.node == capture.node:
                            self.references.get(
                                assignment.node, set()).add(ref)
