module lang::php::experiments::plugins::Guard

import lang::php::ast::AbstractSyntax;

@doc{Is the definition definitely guarded, definitely not guarded, or maybe guarded}
data Guard = Guarded() | PotentiallyGuarded(list[Expr] exprs) | NotGuarded();
