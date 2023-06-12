# Typescript example refactors implemented in sizr lisp

## Example tsserver refactors implemented in sizr lisp

### _addOrRemoveBracesToArrowFunction_

```lisp
(function_definition)
```

### _convertExport_

#### default to named

```lisp
(function_definition)
```

#### named to default

```lisp
(function_definition)
```

### _convertImport_

#### namespace to named

#### named to namespace

```lisp
(function_definition)
```

### _extractSymbol_

#### extract selected expression to variable

#### extract method

### _extractType_

#### extract to type alias

```lisp
(function_definition)
```

#### extract to type interface

```lisp
(transform
  (variable_declaration
    name: (identifier) @name
    type: (object_type_literal) @type)
  @root ;; do not modify
  ;; augmentations
  (interface_declaration
    name: (string-append (ast->string @name) "Type")
    body: @type.body)
  (ts-workspace ".")) ;; NOTE: maybe I should make workspace the first argument, not last
```

## Other

### extract

