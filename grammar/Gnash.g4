/*
 * ANTLR4 grammar for the Gnash provisioning DSL.
 * Captures the syntax observed in src/gnash/steps/AdminGroupNopass.gnash,
 * including function definitions, control flow, collections, and
 * interpolated string literals.
 */
grammar Gnash;

compilationUnit
    : packageDecl? importDecl* topLevelElement* EOF
    ;

packageDecl
    : 'package' qualifiedName
    ;

importDecl
    : 'import' qualifiedName
    ;

qualifiedName
    : IDENTIFIER ('.' IDENTIFIER)*
    ;

topLevelElement
    : functionDecl
    | globalStatement
    ;

globalStatement
    : expressionStatement
    ;

functionDecl
    : modifier* 'def' IDENTIFIER '(' parameterList? ')' block
    ;

modifier
    : 'public'
    | 'private'
    | 'protected'
    | 'static'
    ;

parameterList
    : parameter (',' parameter)*
    ;

parameter
    : IDENTIFIER
    ;

block
    : '{' statement* '}'
    ;

statement
    : block
    | ifStatement
    | forStatement
    | tryStatement
    | returnStatement
    | throwStatement
    | breakStatement
    | continueStatement
    | expressionStatement
    ;

ifStatement
    : 'if' '(' expression ')' block ('else' (ifStatement | block))?
    ;

forStatement
    : 'for' '(' IDENTIFIER 'in' expression ')' block
    ;

tryStatement
    : 'try' block catchClause+ finallyClause?
    ;

catchClause
    : 'catch' '(' IDENTIFIER ')' block
    ;

finallyClause
    : 'finally' block
    ;

returnStatement
    : 'return' expression?
    ;

throwStatement
    : 'throw' expression
    ;

breakStatement
    : 'break'
    ;

continueStatement
    : 'continue'
    ;

expressionStatement
    : expression
    ;

expression
    : assignment
    ;

assignment
    : destructuringPattern '=' assignment
    | logicOrExpression
    ;

destructuringPattern
    : IDENTIFIER
    | '(' IDENTIFIER (',' IDENTIFIER)* ')'
    ;

logicOrExpression
    : logicAndExpression ( '||' logicAndExpression )*
    ;

logicAndExpression
    : equalityExpression ( '&&' equalityExpression )*
    ;

equalityExpression
    : relationalExpression ( ('==' | '!=') relationalExpression )*
    ;

relationalExpression
    : additiveExpression ( ('<' | '>' | '<=' | '>=' | 'is') additiveExpression )*
    ;

additiveExpression
    : multiplicativeExpression ( ('+' | '-') multiplicativeExpression )*
    ;

multiplicativeExpression
    : unaryExpression ( ('*' | '/' | '%') unaryExpression )*
    ;

unaryExpression
    : ('!' | '-' | '+') unaryExpression
    | postfixExpression
    ;

postfixExpression
    : primaryExpression postfixOperator*
    ;

postfixOperator
    : '.' IDENTIFIER (arguments)?
    | arguments
    ;

arguments
    : '(' argumentList? ')'
    ;

argumentList
    : expression (',' expression)*
    ;

primaryExpression
    : literal
    | IDENTIFIER
    | '(' expression ')'
    ;

literal
    : NUMBER
    | STRING
    | SHELL_CMD
    | 'true'
    | 'false'
    | 'null'
    | listLiteral
    | mapLiteral
    ;

listLiteral
    : '[' (expression (',' expression)*)? ']'
    ;

mapLiteral
    : '{' mapEntry (',' mapEntry)* ','? '}'
    | '{' '}'
    ;

mapEntry
    : mapKey ':' expression
    ;

mapKey
    : IDENTIFIER
    | STRING
    ;

// -----------------------------------------------------------------------------
// Lexer rules
// -----------------------------------------------------------------------------

SHELL_CMD
    : '$"' ( '\\' . | ~["\\] )* '"'
    ;

STRING
    : '"' ( '\\' . | ~["\\] )* '"'
    ;

NUMBER
    : DIGIT+
    ;

IDENTIFIER
    : LETTER (LETTER | DIGIT)*
    ;

fragment LETTER
    : [a-zA-Z_]
    ;

fragment DIGIT
    : [0-9]
    ;

WS
    : [ \t\r\n]+ -> skip
    ;

LINE_COMMENT
    : '//' ~[\r\n]* -> skip
    ;

BLOCK_COMMENT
    : '/*' .*? '*/' -> skip
    ;

SHEBANG
    : '#!' ~[\r\n]* -> skip
    ;
