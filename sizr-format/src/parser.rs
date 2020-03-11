/**
 * Parser for the sizr-format language
 */

#[macro_use] extern crate regex;
use regex::Regex;

#[macro_use] extern crate lazy_static;
use std::collections::BTreeMap;

pub mod parser {

    pub enum AstNode<'a> {
        Indent,
        Outdent,
        Align(Regex),
        Add(Box<AstNode<'a>>, Box<AstNode<'a>>),
        Quote(&'a str)
    }

    #[derive(Debug)]
    struct ParseContext<'a> {
        pub src: &'a str,
        pub loc: u32,
        pub ast: AstNode<'a>, // Vec<TopLevelDef>
    }

    impl<'a> ParseContext<'a> {
        fn remainingSrc(&self) -> &'a str {
            self.src[self.loc..]
        }
    }

    pub mod atoms {
        use ParseContext;
        fn parse_integer(ctx: &mut ParseContext) {
            let end = ctx.src[ctx.loc](|c| c.whitespace);
            let atom_src = ctx.src[ctx.loc..ctx.src];
        }

        fn parse_quote(ctx: &mut ParseContext) {
            ctx.loc += 1; //skip delimiter
        }

        fn parse_regex(ctx: &mut ParseContext) {
            ctx.loc += 1; //skip delimiter
        }

        fn parse_paren_group(ctx: &mut ParseContext) {
            ctx.loc += 1; //skip opener
        }

        fn parse_lambda(ctx: &mut ParseContext) {
        }

        fn parse_wrap(ctx: &mut ParseContext) {
        }
    }

    fn parseAtom(ctx: &mut ParseContext) {
    }

    fn parseCommand(ctx: &mut ParseContext) {
        match ctx.remainingSrc()[0] {
            '"'  => { atoms::parse_quote(&ctx) },
            '\\' => { atoms::parse_wrap(&ctx) },
            '?'  => { atoms::parse_cond(&ctx) },
            _ => panic!("Unknown token, expected write command")
        }
    }

    fn skipWhitespace(ctx: &mut ParseContext) {
        ctx.loc = ctx.remainingSrc().find(|c| !c.is_space());
    }

    fn parseFile(ctx: &mut ParseContext) {
        while ctx.loc < ctx.src.length {
            skipWhitespace(&ctx);
            parseFormatDef(&ctx);
        }
    }

    fn skipToDelim(ctx: &mut ParseContext) {
        ctx.loc = ctx.remainingSrc().findIndex(|c| c == '\'');
    }

    fn parseFormatDef(ctx: &mut ParseContext) {
        skipWhitespace(&ctx);
        parseIdentifier(&ctx);
        skipToDelim(&ctx);
        //parseDelim?
        let idxAfterDelim = ctx.remainingSrc().findIndex(|c| c != '\'');
        let delim = ctx.remainingSrc()[..idxAfterDelim];
        while ctx.remainingSrc()[..idxAfterDelim.len()] == delim {
            skipWhitespace(&ctx);
            parseCommand(&ctx);
        }
    }

    pub mod ops {
        fn parse_slice(ctx: &mut ParseContext) {
        }

        pub enum Precedence {
            Logic = 0,
            Comp, Add, Mult, Exp, Dot,
        }

        lazy_static! {
          pub static ref binOpPrecedenceMap: BTreeMap<&'static str, Precedence> = {
            let mut m = BTreeMap::new();
            m.insert("&",  Precedence::Logic);
            m.insert("|",  Precedence::Logic);
            m.insert("^",  Precedence::Logic);
            m.insert(">",  Precedence::Comp);
            m.insert(">=", Precedence::Comp);
            m.insert("=",  Precedence::Comp);
            m.insert("!=", Precedence::Comp);
            m.insert("<=", Precedence::Comp);
            m.insert("<",  Precedence::Comp);
            m.insert("+",  Precedence::Add);
            m.insert("-",  Precedence::Add);
            m.insert("*",  Precedence::Mult);
            m.insert("/",  Precedence::Mult);
            m.insert("//", Precedence::Mult);
            m.insert("%",  Precedence::Mult);
            m.insert("**", Precedence::Exp);
            m.insert(".",  Precedence::Dot);
            m
          }
        }
    }

    /** TODO: use precedence climbing for bin ops */
    fn parse_bin_op(ctx: &mut ParseContext) {
    }

    fn parse_unary_op(ctx: &mut ParseContext) {
    }

    fn parse_indent_ctx_decl(ctx: &mut ParseContext) {
        match ctx.src[ctx.loc..ctx.loc+2] {
            "|>" => { ctx.ast.add(Indent()); },
            ">/" => { ctx.loc+=1; parse_regex(&ctx); },
            "<|" => { ctx.ast.add(Outdent()) },
            _ => panic!("Unknown token, expected indentation context")
        }
    }
}
