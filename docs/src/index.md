# Sizr Lisp

Sizr Lisp is a Scheme distribution focusing on the `Sizr` package, an
AST transformation toolkit built upon <a href="">Tree-sitter</a>. Sizr Lisp is
based on <a href="">Chibi Scheme</a>.

By taking Tree-sitter's existing support for selecting program source sections with
lisp-ish queries, and then evaluating real Scheme programs in the context of that
selection, we can write highly dynamic transformations to augment or replace source code.

## Selecting code

The first thing we need to do to figure out how to do things with our code, is to
tell Sizr which parts of the code we want to talk about. This the process of
<em>selecting</em> code. Once we have selected some code, we can then 


```lisp
(function_definition)
```

```lisp
((function_definition) @func)
```

Note that grouping in the selection language does not follow Lisp semantics.
In Lisp, `(function)` has a very different meaning than. More on that in
[understanding scheme code](#understanding-scheme-code), below.
`((function))`.


```
((function_definition) @func)
```

See [tree-sitter's query language documentation](/FIXME) for a full description of
the query syntax. The only limitation of Sizr's query syntax support is that a true lisp
can not contain a `.` in arbitrary locations, so in Sizr Lisp you must use the a
quoted symbol instead, `'.`.

## Understanding scheme code

If you do not have familarity with Lisp code, then congratulations for making
it this far. There are many great explanations which I cannot imitate,
but I recommend the classic
[Structure and Interpretation of Computer Programs](https://mitp-content-server.mit.edu/books/content/sectbyfn/books_pres_0/6515/sicp.zip/full-text/book/book.html").
I will give a dangerously succinct primer here, which you may skip if you're
already familiar. Or find another if it was too dangerously succinct.

Assuming some prior programming experience with C-like languages,
all we need to know for the purposes of this article is that a function call
in such a language, that looks like `f(a, b, c)`, in Lisp would look
like `(f a b c)`. By extension,
nested function calls work similarly. `f(g(a, h()))` would be
`(f (g a (h)))`. And finally, your typical arithmetic operators like `+`, `*`, `-`, etc.,
have no special syntax, and must be used like the rest of the functions, yielding code
like `(+ (/ 1 2))`.

So then let's look at a tree-sitter query and think about how we might "evaluate it"
as Lisp code. We will quickly learn there is some magic involved in all but the most
basic examples.

```
(binary_expression (number_literal) "+" (number_literal))
```

While this is a valid tree-sitter query, it's not strictly "evaluable", we do not know
_what number_ our `number_literal`s are. For this reason, in the replace or augment clauses,
of a Sizr transform, you have to specify the token as a string (or number) argument to many
AST leaf nodes:

```
(binary_expression (number_literal 4) "+" (number_literal 5))
```

For simplicity sake, I elided the field names, which optionally prefix important nodes. Fields
are specific to the language grammar, defined in that particular language's Sizr library, for
the `binary_expression` node we have the following fields:

```
(binary_expression
  left: (number_literal)
  operator: "+"
  right: (number_literal))
```

So now that we can build some simple syntaxes, let's take a look at how we can replace pieces
of captured syntaxes. Take the following transform.

```
(transform 
  ;; the selection
  (binary_expression
    left: (number_literal) @num
    right: (string_literal))

  ;; the replacement
  (binary_expression
    left: (call_expression (identifier "String") (@num)))

  ;; the workspace
  my-workspace)
```

While the above expression demonstrates a weakness in Sizr, that will be ignored for now
and elaborated upon [below](#the-problem-with-sizr).

Note that in Tree-sitter's query language, a `@capture` applies to the form directly preceding it.
Also note that I _did not specify_ the `operator:` field, meaning this will match any binary expression,
on such literals, regardless of operator, be it `4 + "hello"` or `4 == "hello"`. Finally, notice
that the replacement clause contains a reference to `@num`, which will be _expanded_ as part of the
evaluation of the replacement. In fact, you can think of `@num` as a function evaluating
in the context of each selection, returning the value that had been captured. If we were running this over
the code `1 + "hello"" || 2 == "world"` (great example, I know), then our replacement clause
would evaluate over _both_ number/string binary expressions separately:

<pre>
<span style="color:red">1 + "hello"</span> || <span style="color:blue">2 + "world"</span>
</pre>

So in the first, red, source section, replacement `(@num)` would evaluate to
<span style="color:red"><code>(number_literal 1)</code></span>,
and in the second, it would evaluate to
<span style="color:blue"><code>(number_literal 2)</code></span>. So if for the first source section,
we expand the capture, and then fill in the specified fields replacements, we would get a
replacement of:

```lisp
;; the replacement
(binary_expression
  left: (call_expression (identifier "String") (number_literal "1"))
  operator: "+"
  right: (string_literal "hello")))
```

Which, perhaps you can guess, is fed to the Sizr transform's inner logic, and serialized
to code code looking like:

<pre>
<span style="color:red">String(1) + "hello"</span> || <span style="color:blue">String(2) + "world"</span>
</pre>

And finally, the last piece of the puzzle, armed with the knowledge that `@capture`'s are treated
as functions in the replacement code, that will return the capture value in each replacement context,
you may be happy to know that this function can take arguments to replace its own fields

## Replacing code


## Workspaces

A workspace is a group of interrelated files on a computer system
that make up a codebase. They can include program source files, program tooling
configuration, settings, etc. To Sizr Lisp, these are exposed as a set of files,
and an environment mapping. Workspaces are important so that sizr can find all
your code, and, eventually, update references during replacing transformations.


## Augmenting code

Not only can we select code and replace it, but we can select code and use it to
generate new code in our [workspace](workspaces).


## The problem with sizr

Well, it turns out that while having a uniform query language for multiple languages is
nice, those languages, especially their grammars, are very different. This means that code
written for one language in Sizr is often not portable to other languages.

Blah, blah, blah.
