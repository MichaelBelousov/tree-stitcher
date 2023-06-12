# Typescript example refactors implemented in sizr lisp

## Example tsserver refactors implemented in sizr lisp

Based on a [TypeScript issue](https://github.com/microsoft/TypeScript/issues/37895) listing
several of them.

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

### _generateGetAccessorAndSetAccessor_

### _convertParamsToDestructuredObject

### _convertStringOrTemplateLiteral_

### _moveToNewFile_

## Other

### replace `instanceof` checks with checks of new field.

```lisp
(transform
  (class_declaration
    name: (identifier) @name
    body: (_) @body)
  (class_declaration
    body: (append (declaration (identifier "type")
                               "="
                               (string_literal (ast->string @name)))
                  @body))
  (ts-workspace "."))

(transform
  (binary_expression
    left: (identifier) @name
    operator: "instanceof"
    right: (subclass-of "my-class")) ;; not possible without typeinfo
  (binary_expression
    left: (field_expression argument: @name
                            field: (field_identifier ""))
    operator: "==="
    right: @class_name) ;; not possible without typeinfo
  (ts-workspace "."))
```

Not possible without type info, ey?
Time for a typescript-api->clojure-script->chibi-scheme kludge, ey?

