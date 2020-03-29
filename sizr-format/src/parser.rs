/**
 * Parser for the sizr-format language
 */

extern crate regex;
extern crate lazy_static;

use std::vec::Vec;
use std::boxed::Box;
use std::cell::Cell;


#[derive(Debug)]
pub enum Ast<'a> {
    Indent,
    Outdent,
    Align(Option<regex::Regex>),
    Add(Box<Ast<'a>>, Box<Ast<'a>>),
    Quote(&'a str),
    Regex(regex::Regex),
    Number(f64),
    Variable{ name: &'a str },
    Lambda{ property: &'a str, equals: Option<Box<Ast<'a>>> },
    Underscore,
    Group(Box<Ast<'a>>),
    Cond{
        cond: Box<Ast<'a>>, // Group
        then: Option<Box<Ast<'a>>>,
        else_: Option<Box<Ast<'a>>>
    },
    WrapPoint,
    NodeFormat(Vec<Box<Ast<'a>>>),
    File(Vec<Ast<'a>>),
}

// TODO: make private to this module
#[derive(Debug)]
pub struct ParseContext<'a> {
    pub src: &'a str,
    pub loc: Cell<usize>,
}

impl<'a> ParseContext<'a> {
    pub fn remaining_src(&self) -> &'a str {
        &self.src[self.loc.get()..]
    }

    pub fn inc_loc(&self, inc: usize) -> usize {
        /* FIXME: find idiomatic rust solution for this stuff */
        &self.loc.set(self.loc.get() + inc);
        self.loc.get()
    }

    pub fn new(in_src: &'a str) -> Self {
        ParseContext{
            src: in_src,
            loc: Cell::new(0),
        }
    }
}

pub mod matcher {
    use super::*;

    pub fn identifier(ctx: &ParseContext) -> bool {
        if let Some(c) = ctx.remaining_src().chars().nth(0) {
            c.is_ascii_alphabetic()
        } else { false }
    }

    pub fn number(ctx: &ParseContext) -> bool {
        if let Some(c) = ctx.remaining_src().chars().nth(0) {
            c.is_ascii_digit()
        } else { false }
    }

    pub fn quote(ctx: &ParseContext) -> bool {
        ctx.remaining_src().chars().nth(0) == Some('"')
    }

    pub fn regex(ctx: &ParseContext) -> bool {
        ctx.remaining_src().chars().nth(0) == Some('/')
    }

    pub fn eol(ctx: &ParseContext) -> bool {
        ctx.remaining_src().chars().nth(0) == Some('\n')
    }

    pub fn eof(ctx: &ParseContext) -> bool {
        ctx.remaining_src().chars().nth(0) == None
    }

    pub fn lambda(ctx: &ParseContext) -> bool {
        ctx.remaining_src().chars().nth(0) == Some('.')
    }

    pub fn cond(ctx: &ParseContext) -> bool {
        ctx.remaining_src().chars().nth(0) == Some('?')
    }

    pub fn variable(ctx: &ParseContext) -> bool {
        ctx.remaining_src().chars().nth(0) == Some('$')
    }

    pub fn binary_op(ctx: &ParseContext) -> bool {
        if let Some(end) = ctx.remaining_src().find(
            |c: char| c.is_whitespace() || c.is_ascii_alphanumeric()
        ) {
            ops::BINARY_OPS.iter()
                .any(|op| op.symbol == &ctx.remaining_src()[..end])
        } else { false }
    }

    pub fn unary_op(ctx: &ParseContext) -> bool {
        match ctx.remaining_src().chars().nth(0) {
            Some('-') | Some('~') | Some('!') => true,
            _ => false
        }
    }

    pub fn wrap_point(ctx: &ParseContext) -> bool {
        ctx.remaining_src().chars().nth(0) == Some('\\')
    }

    pub fn indent_ctx_decl(ctx: &ParseContext) -> bool {
        match &ctx.src[ctx.loc.get()..ctx.loc.get()+2] {
            "|>" | ">/" | "<|"  => true,
            _ => false
        }
    }
}

fn skip_to_char(ctx: &ParseContext, to: char) {
    match &ctx.remaining_src().find(|c| c == to) {
        Some(jump) => ctx.inc_loc(*jump),
        None => panic!("EOI")
    };
}

fn skip_char(ctx: &ParseContext, to: char) {
    skip_to_char(ctx, to);
    ctx.inc_loc(1);
}

fn skip_whitespace(ctx: &ParseContext) {
    match &ctx.remaining_src().find(|c: char| !c.is_whitespace()) {
        Some(jump) => ctx.inc_loc(*jump),
        None => panic!("reached EOI")
    };
}

pub mod atoms {
    use super::*;

    // NOTE: maybe take immutable context ref?
    pub fn read_identifier<'a>(ctx: &'a ParseContext) -> &'a str {
        // TODO: verify first char is not numeric in debug mode
        if let Some(after) = ctx.remaining_src().find(
            |c: char| !c.is_ascii_alphanumeric() && c != '_'
        ) {
            // TODO: convert escape sequences i.e. \n, \\, etc
            let content = &ctx.remaining_src()[..after];
            ctx.inc_loc(after);
            content
        } else {
            panic!("debug");
        }
    }


    fn read_quoted<'a>(ctx: &'a ParseContext, delim: char) -> &'a str {
        // TODO: in debug mode check explicitly for delimiter match
        ctx.inc_loc(1); //skip delimiter
        let start = ctx.loc.get();
        loop {
            match ctx.remaining_src().find(|c: char| c == '\\' || c == delim) {
                Some(jump) => {
                    match &ctx.remaining_src().chars().nth(jump) {
                        Some('\\')  => { ctx.inc_loc(jump + 2); },
                        Some(delim) => { ctx.inc_loc(jump + 1); break; },
                        _ => panic!("unreachable")
                    }
                },
                None => break
            }
        }
        &ctx.src[start..ctx.loc.get()-1]
    }

    pub fn parse_number<'a>(ctx: &'a ParseContext) -> Ast<'a> {
        // TODO: support scientific notation
        if let Some(end) =
            ctx.remaining_src().find(|c: char| !c.is_ascii_digit() && c != '.'
        ) {
            let src = &ctx.remaining_src()[..end];
            let parsed = src.parse::<f64>().unwrap();
            Ast::Number(parsed)
        } else {
            panic!("failed to parse number");
        }
    }

    pub fn parse_quote<'a>(ctx: &'a ParseContext) -> Ast<'a> {
        Ast::Quote(read_quoted(ctx, '"'))
    }

    pub fn parse_regex<'a>(ctx: &'a ParseContext) -> Ast<'a> {
        Ast::Regex(regex::Regex::new(read_quoted(ctx, '/')).unwrap())
    }

    pub fn parse_paren_group<'a>(ctx: &'a ParseContext) -> Ast<'a> {
        ctx.inc_loc(1); //skip opener
        // TODO: in debug mode check explicitly for delimiter match
        let expr = exprs::parse_expression(ctx);
        ctx.inc_loc(1); //skip closer
        // TODO: in debug mode check explicitly for delimiter match
        Ast::Group(Box::new(expr))
    }

    pub fn parse_lambda<'a>(ctx: &'a ParseContext) -> Ast<'a> {
        // TODO: in debug mode explicitly check for "." start
        ctx.inc_loc(1);
        let name = read_identifier(ctx);
        Ast::Lambda{
            property: name,
            equals: match ctx.remaining_src().chars().nth(0) {
                Some('=') => {
                    let expr = exprs::parse_expression(ctx);
                    Some(Box::new(expr))
                },
                Some(_) => None,
                _ => panic!("unexpected during lambda parsing")
            }
        }
    }

    // TODO: allow wrap points to form implicit conditions
    pub fn parse_wrap_point<'a>(ctx: &'a ParseContext) -> Ast<'a> {
        ctx.inc_loc(1);
        Ast::WrapPoint
    }

    pub fn parse_variable<'a>(ctx: &'a ParseContext) -> Ast<'a> {
        ctx.inc_loc(1);
        Ast::Variable{ name: read_identifier(ctx) }
    }

    pub fn parse_indent_ctx_decl<'a>(ctx: &'a ParseContext) -> Ast<'a> {
        match &ctx.src[ctx.loc.get()..ctx.loc.get()+2] {
            "|>" => { ctx.inc_loc(2); Ast::Indent },
            ">/" => { ctx.inc_loc(1); atoms::parse_regex(ctx) },
            "<|" => { ctx.inc_loc(2); Ast::Outdent },
            _ => panic!("Unknown token, expected indentation context")
        }
    }
}

//pub mod writes
pub mod exprs {
    use super::*;

    pub fn parse_cond<'a>(ctx: &'a ParseContext) -> Ast<'a> {
        ctx.inc_loc(1); //skip "?"
        skip_whitespace(ctx);
        let cond = Box::new(atoms::parse_paren_group(ctx));
        skip_whitespace(ctx);
        if ctx.remaining_src().chars().nth(0) == Some(':') {
            Ast::Cond {
                cond,
                then: None,
                else_: Some(Box::new(parse_expression(ctx)))
            }
        } else {
            let then = Some(Box::new(parse_expression(ctx)));
            skip_char(ctx, ':');
            skip_whitespace(ctx);
            let else_ = Some(Box::new(parse_expression(ctx)));
            Ast::Cond { cond, then, else_ }
        }
    }

    // parse_expression?
    pub fn parse_expression<'a>(ctx: &'a ParseContext) -> Ast<'a> {
        if matcher::quote(ctx) {
            atoms::parse_quote(ctx)
        } else if matcher::wrap_point(ctx) {
            atoms::parse_wrap_point(ctx)
        } else if matcher::cond(ctx) {
            parse_cond(ctx)
        } else if matcher::variable(ctx) {
            atoms::parse_variable(ctx)
        } else if matcher::indent_ctx_decl(ctx) {
            atoms::parse_indent_ctx_decl(ctx)
        } else if matcher::unary_op(ctx) {
            expr::parse_unary_op(ctx)
        } else {
            panic!("Unknown token, expected write command")
        }
    }
}

// TODO: rename to like a "NodeSet", parse_file sounds too high-level
fn parse_file(ctx: &ParseContext) {
    while ctx.loc.get() < ctx.src.len() {
        //skip_whitespace(ctx);
        parse_format_def(ctx);
    }
}

fn parse_format_def(ctx: &ParseContext) {
    skip_whitespace(ctx);
    let name = atoms::read_identifier(ctx);
    skip_to_char(ctx, '\'');
    if let Some(end) = ctx.remaining_src().find(|c: char| c != '\'') {
        let delim = &(ctx.remaining_src()[..end]);
        ctx.inc_loc(end);
        while &ctx.remaining_src()[..end] != delim {
            skip_whitespace(ctx);
            exprs::parse_expression(ctx);
        }
    } else {
        panic!("bad format definition syntax");
    }
}

pub mod ops {
    use super::*;

    /*
    fn parse_slice(ctx: &ParseContext) {
    }
    */

    pub enum Precedence {
        Logic = 0, Comp, Add, Mult, Exp, Dot,
    }

    pub struct BinOpDef {
        pub symbol: &'static str,
        pub prec: Precedence,
    }

    pub static AND: BinOpDef =
        BinOpDef{symbol: "&",  prec: Precedence::Logic};
    pub static OR: BinOpDef =
        BinOpDef{symbol: "|",  prec: Precedence::Logic};
    pub static XOR: BinOpDef =
        BinOpDef{symbol: "^",  prec: Precedence::Logic};
    pub static GT: BinOpDef =
        BinOpDef{symbol: ">",  prec: Precedence::Comp};
    pub static GTE: BinOpDef =
        BinOpDef{symbol: ">=", prec: Precedence::Comp};
    pub static EQ: BinOpDef =
        BinOpDef{symbol: "=",  prec: Precedence::Comp};
    pub static NEQ: BinOpDef =
        BinOpDef{symbol: "!=", prec: Precedence::Comp};
    pub static LTE: BinOpDef =
        BinOpDef{symbol: "<=", prec: Precedence::Comp};
    pub static LT: BinOpDef =
        BinOpDef{symbol: "<",  prec: Precedence::Comp};
    pub static ADD: BinOpDef =
        BinOpDef{symbol: "+",  prec: Precedence::Add};
    pub static SUB: BinOpDef =
        BinOpDef{symbol: "-",  prec: Precedence::Add};
    pub static MUL: BinOpDef =
        BinOpDef{symbol: "*",  prec: Precedence::Mult};
    pub static DIV: BinOpDef =
        BinOpDef{symbol: "/",  prec: Precedence::Mult};
    pub static IDIV: BinOpDef =
        BinOpDef{symbol: "//", prec: Precedence::Mult};
    pub static MOD: BinOpDef =
        BinOpDef{symbol: "%",  prec: Precedence::Mult};
    pub static POW: BinOpDef =
        BinOpDef{symbol: "**", prec: Precedence::Exp};
    pub static DOT: BinOpDef =
        BinOpDef{symbol: ".",  prec: Precedence::Dot};

    pub static BINARY_OPS: Vec<BinOpDef> = vec![
        AND, OR, XOR,
        GT, GTE, EQ, NEQ, LTE, LT,
        ADD, SUB,
        MUL, DIV, IDIV, MOD,
        POW,
        DOT,
    ];

    // TODO: rename to prefix_unary_op?
    pub fn parse_unary_op(ctx: &ParseContext) {
    }

    // TODO: use precedence climbing for bin ops
    pub fn parse_bin_op(ctx: &ParseContext) {
      //parseAtom(ctx);
      //parse_bin_op(ctx);
      //parseAtom(ctx);
      //while match ctx.remaining_src() {
      //}
      // match () {
      // }
    }

}

pub fn parse_text(text: &str) {
    //create parse context
    //parse
    let ctx = ParseContext::new(text);
    let ast = parse_file(&ctx);
    println!("{:?}", ast);
}
