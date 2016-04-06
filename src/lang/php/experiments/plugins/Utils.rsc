module lang::php::experiments::plugins::Utils

import lang::php::ast::AbstractSyntax;

public NameOrExpr wrapExpr(scalar(string(str s))) = name(name(s));
public default NameOrExpr wrapExpr(Expr e) = expr(e);
