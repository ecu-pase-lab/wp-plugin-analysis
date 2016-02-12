module lang::php::experiments::plugins::CommentSyntax

lexical Whitespace = [\ \t];
	
layout Layout = Whitespace* >>! [\ \t];

lexical Star = "*";

lexical At = "@";

lexical EOL = [\n\r];
	
lexical Text = ![@\n\r] ![\n\r]*;
	
lexical Type = [a-zA-Z0-9_]+ >>! [a-zA-Z0-9_];

lexical Tag = "@param" | "@link" | "@deprecated" | 
              "@package" | "@subpackage" | "@since" | "@type" | "@see" | 
              "@todo" | "@global" | "@filter" | "@access";

lexical JustTag = "@private" | "@internal" | "@ignore";

syntax Line
	= textLine: Star Text text
	| firstLine: "/" Star Star
	| blankLine: Star+
	| taggedLine: Star Tag Text text
	| justTaggedLine: Star JustTag
	| lastLine: Star "/"
	| onlyLine: "/" Star Star Text text Star "/"
	| onlyTaggedLine: "/" Star Star Tag Text text Star "/"
	;

syntax Lines
	= singleLine: Line line
	| left multipleLines: Line line EOL Lines lines
	;
	
syntax Comment = Lines lines;