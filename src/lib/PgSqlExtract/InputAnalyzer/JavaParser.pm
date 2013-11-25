####################################################################
#
#    This file was generated using Parse::Yapp version 1.05.
#
#        Don't edit this file, use source file instead.
#
#             ANY CHANGE MADE HERE WILL BE LOST !
#
####################################################################
package PgSqlExtract::InputAnalyzer::JavaParser;
use vars qw ( @ISA );
use strict;

@ISA= qw ( Parse::Yapp::Driver );
use Parse::Yapp::Driver;


use warnings;
no warnings "recursion";
use strict;
use Carp;
use utf8;
use PgSqlExtract::Common::Lexer;
use PgSqlExtract::Common;
use Scalar::Util;

#!
#! 識別子(Identifiers)の定義
#!
my $Identifiers = qr{ ( [\w_\$][\w\d_\$]* ) }xms;


#!
#! キーワード（予約語）の定義
#!
my %keywords = (
    map { $_ => uc($_) . '_TOKEN' } qw(
        abstract    continue    for           new          switch
        assert      default     if            package      synchronized
        boolean     do          goto          private      this
        break       double      implements    protected    throw
        byte        else        import        public       throws
        case        enum        instanceof    return       transient
        catch       extends     int           short        try
        char        final       interface     static       void 
        class       finally     long          strictfp     volatile
        const       float       native        super        while
    ),
);

#!
#! リテラルパターンの定義(Integer Literals)
#!
my $Digit                    = qr{\d}xms;
my $HexDigit                 = qr{[\da-fA-F]}xms;
my $OctDigit                 = qr{[0-7]}xms;
my $IntegerTypeSuffix        = qr{[lL]}xms;
my $DecimalNumeral           = qr{ 0 | [1-9] $Digit* }xms;

my $HexNumeral               = qr{ 0 [xX] $HexDigit+ }xms;

my $OctalNumeral             = qr{ 0 $OctDigit+ }xms;

my $DecimalIntegerLiteral    = qr{ $DecimalNumeral $IntegerTypeSuffix? }xms;
my $HexIntegerLiteral        = qr{ $HexNumeral     $IntegerTypeSuffix? }xms;
my $OctalIntegerLiteral      = qr{ $OctalNumeral   $IntegerTypeSuffix? }xms;


#!
#! リテラルパターンの定義(Floating-Point Literals)
#!
my $ExponentPart     = qr{ [eE] [+-]?\d+ }xms;
my $FloatTypeSuffix  = qr{ [fFdD] }xms;
my $HexSignificand   = qr{ 0 [xX] (?: $HexDigit+ \.? | $HexDigit* \. $HexDigit+) }xms;
my $BinaryExponentIndicator = qr{ [pP] [+-]?\d+ }xms; 


my $DecimalFPLiteral1 = qr{ $Digit+ \. $Digit* $ExponentPart? $FloatTypeSuffix?}xms;
my $DecimalFPLiteral2 = qr{         \. $Digit+ $ExponentPart? $FloatTypeSuffix?}xms;
my $DecimalFPLiteral3 = qr{            $Digit+ $ExponentPart  $FloatTypeSuffix?}xms;
my $DecimalFPLiteral4 = qr{            $Digit+ $ExponentPart? $FloatTypeSuffix}xms;
my $HexadecimalFPLiteral = qr{ $HexSignificand $BinaryExponentIndicator $FloatTypeSuffix? }xms;

#!
#! リテラルパターンの定義(Boolean)
#! Booleanリテラルは、キーワードとして扱う
#!
$keywords{'true'}  = 'TRUE_TOKEN';
$keywords{'false'} = 'FALSE_TOKEN';

#!
#! リテラルパターンの定義(Character)
#! ''内に任意の文字列を記述可能とする定義としており、これは本来の定義とは
#! 異なるが、これは'\u000'といった記述に対応するためである。
#! コンパイルが正常終了したソースコードが解析対象となるため、下記の定義で
#! 字句解析を行っても問題ない。
#!
my $CharacterLiteral = qr{ ['] (?: [^'\\] | \\[btnfru"'\\0-9] )* ['] }xms;

#!
#! リテラルパターンの定義(String)
#!
my $StringLiteral    = qr{ ["] (?: [^"\\] | \\[btnfru"'\\0-9] )* ["] }xms;


#!
#! リテラルパターンの定義(Null)
#! Nullリテラルは、キーワードとして扱う
#!
$keywords{'null'}  = 'NULL_TOKEN';


#!
#! セパレータパターンの定義
#! セパレータパターンは、キーワードとして扱う
#! ただし、DOT_TOKENはfloat値との誤認識を避けるため、特殊キーワードとして定義する
#!
my %separator = (
    '(' => 'LP_TOKEN' ,
    ')' => 'RP_TOKEN' ,
    '{' => 'LCB_TOKEN',
    '}' => 'RCB_TOKEN',
    '[' => 'LSB_TOKEN',
    ']' => 'RSB_TOKEN',
    ';' => 'SMC_TOKEN',
    ',' => 'CM_TOKEN' ,
#!    '.' => 'DOT_TOKEN',
);

while(my ($key, $value) = each %separator) {
    $keywords{$key} = $value;
}

#!
#! コロン、クエスションはキーワードとして扱う
#!
$keywords{':'} = 'CLN_TOKEN';
$keywords{'?'} = 'QUES_TOKEN';


#!
#! オペレータパターンの定義
#!
#! オペレータについては、'=', '+', '+='について個別に識別する。これは、式解析
#! での判断対象となるためである。
#! また、'*'、'<>'、'&'、についても個別に識別する。これは、構文を構成する文字
#! であるためである。
#! 他のオペレータについては字句解析の高速化のため個別には識別しない。
#!
#! パターンマッチによるオペレータの誤認識('&&'を'&''&'と認識するなど)を避ける
#! ように定義の順番を考慮すること
#!
#! shift演算子については、'>>'は、TypeArgumentsの入れ子(<String, Map<String, String>>など)の
#! 終端と誤認識する場合があるため、GT_OPRの連続で定義する。そのため、トークンとしては
#! 定義しない。
#!
my $oprAssignEqual = qr{ = }xms;
my $oprAssignPls   = qr{ \+= }xms;
my $oprPlus        = qr{ \+ }xms;

my $oprAssign      = qr{ >{2,3}= | <{2}= | [*/&|^%-]= }xms;
my $oprCOr         = qr{\|\|}xms;
my $oprCAnd        = qr{&&}xms;
my $oprOr          = qr{\|}xms;
my $oprNor         = qr{\^}xms;
my $oprAmp         = qr{&}xms;
my $oprEquality    = qr{[=!]=}xms;
my $oprRelational  = qr{[<>]=}xms;
#!my $oprShift       = qr{>{2,3} | <{2}}xms;
my $oprShift       = qr{<{2}}xms;
my $oprMulti       = qr{[/%]}xms;
my $oprAsteri      = qr{ \* }xms;
my $oprMinus       = qr{ - }xms;
my $oprGt          = qr{ > }xms;
my $oprLt          = qr{ < }xms;
my $oprPostfix     = qr{ \+\+ | -- }xms;
my $oprPrefix      = qr{[!~]}xms;


#!
#! 特殊キーワード
#! BNFによる構文定義のみでは表現が難しいものについては、字句解析で識別を行う
#! 方針とする
#! そのような特殊なキーワードを定義する
#! - Annotationを示す@は、@InterfaceとInterfaceで定義を共用するため、特殊定義
#!   とする
#! - line指定として、#lineをキーワードとして定義する
#!
my $annoInterface = qr{[@] \s* interface }xms;
my $atmark        = qr{@}xms;
my $dot           = qr{[.]};
my $line_detective = qr{[#]line}xms;
#!$keywords{'\#line'} = 'LINE_DECL_TOKEN';


#!
#! レクサに定義するパターンの定義
#!
my @pattern = (

    #
    # リテラルパターン(Floating-Point Literals)
    #
    $DecimalFPLiteral1,     'FLOAT_LITERAL', 
    $DecimalFPLiteral2,     'FLOAT_LITERAL', 
    $DecimalFPLiteral3,     'FLOAT_LITERAL', 
    $DecimalFPLiteral4,     'FLOAT_LITERAL', 
    $HexadecimalFPLiteral,  'FLOAT_LITERAL', 
    
    
    #
    # リテラルパターン(Integer Literals)
    #
    $HexIntegerLiteral,     'INTEGER_LITERAL',
    $OctalIntegerLiteral,   'INTEGER_LITERAL',
    $DecimalIntegerLiteral, 'INTEGER_LITERAL',
    
    #
    # リテラルパターン(Character)
    #
    $CharacterLiteral,      'CHAR_LITERAL',

    #
    # リテラルパターン(String)
    #
    $StringLiteral,        'STRING_LITERAL',

    #
    # 識別子
    #
    $Identifiers,           'IDENTIFIER',

    #
    # 特殊キーワード
    #
	$annoInterface,         'ATMARK_INTERFACE_TOKEN',
	$line_detective,        'LINE_DECL_TOKEN',

	#
	# オペレータパターン
	# 定義する順番に注意する
	# マッチング対象の文字列長が長いものから定義する必要がある
	#
    $oprAssign,            'ASSIGN_OPR',
    $oprShift,             'SHIFT_OPR',
    $oprEquality,          'EQUALITY_OPR',
    $oprRelational,        'RELATIONAL_OPR',
    $oprAssignPls,         'ASSIGN_P_OPR',
    $oprCOr,               'COR_OPR',
    $oprCAnd,              'CAND_OPR',
    $oprPostfix,           'POSTFIX_OPR',
	$oprAssignEqual,       'EQUAL_OPR',
	$oprPlus,              'PLUS_OPR',
	$oprOr,                'OR_OPR',
	$oprNor,               'NOR_OPR',
	$oprAmp,               'AMP_OPR',
	$oprMulti,             'MULTI_OPR',
	$oprAsteri,            'ASTARI_OPR',
	$oprMinus,             'MINUS_OPR',
	$oprGt,                'GT_OPR',
	$oprLt,                'LT_OPR',
    $oprPrefix,            'PREFIX_OPR',
	$atmark,               'ATMARK_TOKEN',
	$dot,                  'DOT_TOKEN',
);


#!
#! 解析対象外パターン(コメント、空白文字)の定義
#! '\s'は、空白、HT(水平タブ)、FF(フォームフィード)、改行(CR, LF, CR+LF)に
#! マッチングする
#!
my $commentPattern = q(
    ( (?:  \s+
           | //[^\n]*
           | /\*.*?\*/
      )+
    )
);


#!
#! トークンIDの識別表を作成する
#! クラスメンバ変数の終端を示す特殊なトークンID「VARDECL_DELIMITER」を追加する
#!
my @tokenIdlist = values %keywords;
my $index = 0;
push(@tokenIdlist, grep { $index++ % 2 == 1 } @pattern);
map {$tokenId{$_} = $index++ } @tokenIdlist;
$tokenId{'VARDECL_DELIMITER'} = $index++;

#!
#! キーワードに対するトークン情報オブジェクトプールを作成する
#! lookupは、トークン情報がプール対象であるかを判別するハッシュである
#! キーワード以外はプール対象としない（'VARDECL_DELIMITER'は特別なキーワード
#! としてプールする)
#!
my %G_tokenchace = ();
my %lookup = reverse %keywords;
$lookup{'VARDECL_DELIMITER'} = '##;##';

#!
#! トークン一覧を作成する（デバッグ用）
#!
#!open(OUT, ">TOKEN_LIST.txt") or die "File create error TOKEN_LIST.txt\n$!\n";
#!for my $key (sort keys %keywords) {
#!    print OUT "$key\t$keywords{$key}\n";
#!}
#!for(my $i = 0; $i < scalar @pattern; $i+=2) {
#!    print OUT "$pattern[$i]\t$pattern[$i+1]\n";
#!}
#!lose(OUT);



my $counter = 0;

#!
#! レクサの生成およびパターンの登録
#!
my $lex = PgSqlExtract::Common::Lexer->new();
$lex->setPattern({
        EXT_KEYWORD => \%keywords,
        EXT_PATTERN => \@pattern,
        SKIP_PATTERN => $commentPattern
    });
$lex->setDebugMode(0);



#!
#! ノード種別の定義
#! ノード種別の比較にはequal_nodetype関数を使用する
#!
my $nodetypeid = 1;
my %nodetypehash = (
    map { $_ => $nodetypeid++ } qw(
 N_AdditiveExpression N_AndExpression N_Arguments N_ArrayDim N_assert
 N_AssignmentOperator N_BlockStatements N_CastExpression N_catch N_catches
 N_ConditionalAndExpression N_ConditionalExpressionRest N_ConditionalOrExpression
 N_ConstantDeclarator N_ConstantDeclaratorRest N_ConstantDeclaratorsRest
 N_Delimiter N_else N_EqualityExpression N_ExclusiveOrExpression N_Expression
 N_ExpressionList N_ExprInDim N_finally N_for N_ForControl N_forInit N_ForUpdate
 N_ForVarControl N_if N_InclusiveOrExpression N_InstanceOfExpression
 N_LocalVariableDeclarationStatement N_MetaNode N_MethodBody N_MethodInvocation
 N_Modifier N_MoreStatementExpressions N_MultiplicativeExpression N_NormalFor
 N_ParExpression N_Primary N_QualifiedIdentifier N_QualifiedIdentifierList
 N_RelationalExpression N_return N_ScopeInfo N_ShiftExpression N_switch
 N_SwitchBlockStatementGroup N_SwitchBlockStatementGroups N_SwitchLabel
 N_synchronized N_throw N_Type N_VariableDeclarator N_VariableDeclaratorRest
 N_VariableDeclarators N_VariableDeclaratorsRest N_VariableInitializerList
 N_while N_try N_ExpandFor

    ),
);

#!
#! ノード種別のキャッシュ
#! scantree内で頻繁に使用される下記のノード種別については、値を別に保持する
#!
my $G_ScopeInfo_id = $nodetypehash{'N_ScopeInfo'};
my $G_Delimiter_id = $nodetypehash{'N_Delimiter'};
my $G_MetaNode_id  = $nodetypehash{'N_MetaNode'};
my $G_element_id   = 0;

#!
#! static擬似メソッドの付与ID
#! staticイニシャライザについては、擬似的なメソッドと解釈して解析を行う
#! その擬似的なメソッドのメソッド識別子に付与するIDである
#!
my $G_static_number = 0;

#!
#! ファイル情報へのリファレンス
#! クラス情報は、それを抽出した時点でファイル情報へ格納される
#!
my $G_fileinfo_ref;

#!
#! 抽出したクラス名をスタックで管理する
#!
my @G_classname_ident = ();




sub new {
        my($class)=shift;
        ref($class)
    and $class=ref($class);

    my($self)=$class->SUPER::new( yyversion => '1.05',
                                  yystates =>
[
	{#State 0
		ACTIONS => {
			'ATMARK_TOKEN' => 2
		},
		DEFAULT => -188,
		GOTOS => {
			'CompilationUnit' => 1,
			'Annotation' => 3,
			'AnnotationsOrEmpty' => 4,
			'Annotations' => 5
		}
	},
	{#State 1
		ACTIONS => {
			'' => 6
		}
	},
	{#State 2
		ACTIONS => {
			'IDENTIFIER' => 7
		},
		GOTOS => {
			'QualifiedIdentifier' => 8
		}
	},
	{#State 3
		DEFAULT => -170
	},
	{#State 4
		ACTIONS => {
			'PACKAGE_TOKEN' => 9
		},
		DEFAULT => -232,
		GOTOS => {
			'PackageDeclarationOrEmpty' => 10
		}
	},
	{#State 5
		ACTIONS => {
			'ATMARK_TOKEN' => 2
		},
		DEFAULT => -189,
		GOTOS => {
			'Annotation' => 11
		}
	},
	{#State 6
		DEFAULT => 0
	},
	{#State 7
		DEFAULT => -285
	},
	{#State 8
		ACTIONS => {
			'DOT_TOKEN' => 12,
			'LP_TOKEN' => 14
		},
		DEFAULT => -173,
		GOTOS => {
			'AnnotationBodyOrEmpty' => 13
		}
	},
	{#State 9
		ACTIONS => {
			'IDENTIFIER' => 7
		},
		GOTOS => {
			'QualifiedIdentifier' => 15
		}
	},
	{#State 10
		ACTIONS => {
			'IMPORT_TOKEN' => 18
		},
		DEFAULT => -234,
		GOTOS => {
			'ImportDeclarations' => 17,
			'ImportDeclaration' => 16,
			'ImportDeclarationsOrEmpty' => 19
		}
	},
	{#State 11
		DEFAULT => -171
	},
	{#State 12
		ACTIONS => {
			'IDENTIFIER' => 20
		}
	},
	{#State 13
		DEFAULT => -172
	},
	{#State 14
		ACTIONS => {
			'SHORT_TOKEN' => 22,
			'INTEGER_LITERAL' => 53,
			'RP_TOKEN' => 52,
			'LONG_TOKEN' => 26,
			'VOID_TOKEN' => 54,
			'BYTE_TOKEN' => 27,
			'LCB_TOKEN' => 55,
			'MINUS_OPR' => 30,
			'TRUE_TOKEN' => 58,
			'DOUBLE_TOKEN' => 57,
			'INT_TOKEN' => 59,
			'FALSE_TOKEN' => 32,
			'NULL_TOKEN' => 62,
			'LP_TOKEN' => 65,
			'POSTFIX_OPR' => 64,
			'FLOAT_LITERAL' => 36,
			'CHAR_TOKEN' => 38,
			'IDENTIFIER' => 39,
			'PLUS_OPR' => 41,
			'THIS_TOKEN' => 67,
			'BOOLEAN_TOKEN' => 69,
			'CHAR_LITERAL' => 43,
			'ATMARK_TOKEN' => 2,
			'PREFIX_OPR' => 45,
			'FLOAT_TOKEN' => 47,
			'STRING_LITERAL' => 74,
			'NEW_TOKEN' => 73,
			'SUPER_TOKEN' => 76
		},
		GOTOS => {
			'AdditiveOpr' => 50,
			'CastExpression' => 21,
			'UnaryExpressionNotPlusMinus' => 23,
			'RelationalExpression' => 24,
			'InstanceOfExpression' => 25,
			'ElementValueArrayInitializer' => 51,
			'AnnotationValueList' => 29,
			'MultiplicativeExpression' => 28,
			'EqualityExpression' => 56,
			'LcbToken' => 31,
			'ParExpression' => 61,
			'AnnotationValue' => 60,
			'Primary' => 33,
			'ExclusiveOrExpression' => 34,
			'InclusiveOrExpression' => 35,
			'ConditionalOrExpression' => 63,
			'AllocationExpression' => 37,
			'BasicType' => 40,
			'Literal' => 66,
			'UnaryOpr' => 42,
			'ElementValue' => 68,
			'ConditionalAndExpression' => 70,
			'PrimaryExpression' => 44,
			'ShiftExpression' => 71,
			'Annotation' => 72,
			'ConditionalExpression' => 46,
			'UnaryExpression' => 48,
			'AdditiveExpression' => 75,
			'AndExpression' => 49,
			'PrimaryPrefix' => 77
		}
	},
	{#State 15
		ACTIONS => {
			'DOT_TOKEN' => 12,
			'SMC_TOKEN' => 78
		},
		GOTOS => {
			'SmcToken' => 79
		}
	},
	{#State 16
		DEFAULT => -243
	},
	{#State 17
		ACTIONS => {
			'IMPORT_TOKEN' => 18
		},
		DEFAULT => -235,
		GOTOS => {
			'ImportDeclaration' => 80
		}
	},
	{#State 18
		ACTIONS => {
			'STATIC_TOKEN' => 82
		},
		DEFAULT => -239,
		GOTOS => {
			'StaticOrEmpty' => 81
		}
	},
	{#State 19
		DEFAULT => -230,
		GOTOS => {
			'@1-3' => 83
		}
	},
	{#State 20
		DEFAULT => -286
	},
	{#State 21
		DEFAULT => -56
	},
	{#State 22
		DEFAULT => -97
	},
	{#State 23
		DEFAULT => -52
	},
	{#State 24
		ACTIONS => {
			'INSTANCEOF_TOKEN' => 84
		},
		DEFAULT => -31
	},
	{#State 25
		DEFAULT => -29
	},
	{#State 26
		DEFAULT => -100
	},
	{#State 27
		DEFAULT => -96
	},
	{#State 28
		ACTIONS => {
			'MULTI_OPR' => 86,
			'ASTARI_OPR' => 87
		},
		DEFAULT => -43,
		GOTOS => {
			'MultiplicativeOpr' => 85
		}
	},
	{#State 29
		ACTIONS => {
			'CM_TOKEN' => 88,
			'RP_TOKEN' => 89
		}
	},
	{#State 30
		DEFAULT => -46
	},
	{#State 31
		ACTIONS => {
			'SHORT_TOKEN' => 22,
			'INTEGER_LITERAL' => 53,
			'LONG_TOKEN' => 26,
			'VOID_TOKEN' => 54,
			'BYTE_TOKEN' => 27,
			'LCB_TOKEN' => 55,
			'MINUS_OPR' => 30,
			'TRUE_TOKEN' => 58,
			'DOUBLE_TOKEN' => 57,
			'INT_TOKEN' => 59,
			'FALSE_TOKEN' => 32,
			'NULL_TOKEN' => 62,
			'POSTFIX_OPR' => 64,
			'LP_TOKEN' => 65,
			'FLOAT_LITERAL' => 36,
			'CHAR_TOKEN' => 38,
			'IDENTIFIER' => 90,
			'PLUS_OPR' => 41,
			'THIS_TOKEN' => 67,
			'BOOLEAN_TOKEN' => 69,
			'CHAR_LITERAL' => 43,
			'ATMARK_TOKEN' => 2,
			'PREFIX_OPR' => 45,
			'FLOAT_TOKEN' => 47,
			'STRING_LITERAL' => 74,
			'NEW_TOKEN' => 73,
			'SUPER_TOKEN' => 76
		},
		DEFAULT => -184,
		GOTOS => {
			'AdditiveOpr' => 50,
			'CastExpression' => 21,
			'UnaryExpressionNotPlusMinus' => 23,
			'RelationalExpression' => 24,
			'ElementValuesOrEmpty' => 91,
			'InstanceOfExpression' => 25,
			'ElementValueArrayInitializer' => 51,
			'MultiplicativeExpression' => 28,
			'EqualityExpression' => 56,
			'ElementValues' => 92,
			'LcbToken' => 31,
			'ParExpression' => 61,
			'Primary' => 33,
			'ExclusiveOrExpression' => 34,
			'InclusiveOrExpression' => 35,
			'ConditionalOrExpression' => 63,
			'AllocationExpression' => 37,
			'BasicType' => 40,
			'Literal' => 66,
			'UnaryOpr' => 42,
			'ElementValue' => 93,
			'ConditionalAndExpression' => 70,
			'PrimaryExpression' => 44,
			'ShiftExpression' => 71,
			'Annotation' => 72,
			'ConditionalExpression' => 46,
			'UnaryExpression' => 48,
			'AdditiveExpression' => 75,
			'AndExpression' => 49,
			'PrimaryPrefix' => 77
		}
	},
	{#State 32
		DEFAULT => -6
	},
	{#State 33
		ACTIONS => {
			'LSB_TOKEN' => 94,
			'DOT_TOKEN' => 96,
			'LP_TOKEN' => 100
		},
		DEFAULT => -61,
		GOTOS => {
			'ExprInDim' => 98,
			'ArrayDim' => 99,
			'Arguments' => 97,
			'PrimarySuffix' => 95
		}
	},
	{#State 34
		ACTIONS => {
			'NOR_OPR' => 101
		},
		DEFAULT => -23
	},
	{#State 35
		ACTIONS => {
			'OR_OPR' => 102
		},
		DEFAULT => -21
	},
	{#State 36
		DEFAULT => -2
	},
	{#State 37
		DEFAULT => -71
	},
	{#State 38
		DEFAULT => -98
	},
	{#State 39
		ACTIONS => {
			'EQUAL_OPR' => 103
		},
		DEFAULT => -70
	},
	{#State 40
		DEFAULT => -65
	},
	{#State 41
		DEFAULT => -45
	},
	{#State 42
		ACTIONS => {
			'SHORT_TOKEN' => 22,
			'INTEGER_LITERAL' => 53,
			'LONG_TOKEN' => 26,
			'VOID_TOKEN' => 54,
			'BYTE_TOKEN' => 27,
			'MINUS_OPR' => 30,
			'TRUE_TOKEN' => 58,
			'DOUBLE_TOKEN' => 57,
			'INT_TOKEN' => 59,
			'FALSE_TOKEN' => 32,
			'NULL_TOKEN' => 62,
			'POSTFIX_OPR' => 64,
			'LP_TOKEN' => 65,
			'FLOAT_LITERAL' => 36,
			'CHAR_TOKEN' => 38,
			'IDENTIFIER' => 90,
			'PLUS_OPR' => 41,
			'THIS_TOKEN' => 67,
			'BOOLEAN_TOKEN' => 69,
			'CHAR_LITERAL' => 43,
			'PREFIX_OPR' => 45,
			'FLOAT_TOKEN' => 47,
			'STRING_LITERAL' => 74,
			'NEW_TOKEN' => 73,
			'SUPER_TOKEN' => 76
		},
		GOTOS => {
			'AdditiveOpr' => 50,
			'AllocationExpression' => 37,
			'CastExpression' => 21,
			'BasicType' => 40,
			'UnaryExpressionNotPlusMinus' => 23,
			'Literal' => 66,
			'UnaryOpr' => 42,
			'PrimaryExpression' => 44,
			'ParExpression' => 61,
			'UnaryExpression' => 104,
			'Primary' => 33,
			'PrimaryPrefix' => 77
		}
	},
	{#State 43
		DEFAULT => -3
	},
	{#State 44
		ACTIONS => {
			'POSTFIX_OPR' => 105
		},
		DEFAULT => -57
	},
	{#State 45
		ACTIONS => {
			'SHORT_TOKEN' => 22,
			'INTEGER_LITERAL' => 53,
			'LONG_TOKEN' => 26,
			'VOID_TOKEN' => 54,
			'BYTE_TOKEN' => 27,
			'MINUS_OPR' => 30,
			'TRUE_TOKEN' => 58,
			'DOUBLE_TOKEN' => 57,
			'INT_TOKEN' => 59,
			'FALSE_TOKEN' => 32,
			'NULL_TOKEN' => 62,
			'POSTFIX_OPR' => 64,
			'LP_TOKEN' => 65,
			'FLOAT_LITERAL' => 36,
			'CHAR_TOKEN' => 38,
			'IDENTIFIER' => 90,
			'PLUS_OPR' => 41,
			'THIS_TOKEN' => 67,
			'BOOLEAN_TOKEN' => 69,
			'CHAR_LITERAL' => 43,
			'PREFIX_OPR' => 45,
			'FLOAT_TOKEN' => 47,
			'STRING_LITERAL' => 74,
			'NEW_TOKEN' => 73,
			'SUPER_TOKEN' => 76
		},
		GOTOS => {
			'AdditiveOpr' => 50,
			'AllocationExpression' => 37,
			'CastExpression' => 21,
			'BasicType' => 40,
			'UnaryExpressionNotPlusMinus' => 23,
			'Literal' => 66,
			'UnaryOpr' => 42,
			'PrimaryExpression' => 44,
			'ParExpression' => 61,
			'UnaryExpression' => 106,
			'Primary' => 33,
			'PrimaryPrefix' => 77
		}
	},
	{#State 46
		DEFAULT => -180
	},
	{#State 47
		DEFAULT => -101
	},
	{#State 48
		DEFAULT => -47
	},
	{#State 49
		ACTIONS => {
			'AMP_OPR' => 107
		},
		DEFAULT => -25
	},
	{#State 50
		DEFAULT => -53
	},
	{#State 51
		DEFAULT => -182
	},
	{#State 52
		DEFAULT => -174
	},
	{#State 53
		DEFAULT => -1
	},
	{#State 54
		DEFAULT => -67
	},
	{#State 55
		DEFAULT => -363
	},
	{#State 56
		ACTIONS => {
			'EQUALITY_OPR' => 108
		},
		DEFAULT => -27
	},
	{#State 57
		DEFAULT => -102
	},
	{#State 58
		DEFAULT => -5
	},
	{#State 59
		DEFAULT => -99
	},
	{#State 60
		DEFAULT => -176
	},
	{#State 61
		DEFAULT => -66
	},
	{#State 62
		DEFAULT => -7
	},
	{#State 63
		ACTIONS => {
			'COR_OPR' => 110,
			'QUES_TOKEN' => 111
		},
		DEFAULT => -16,
		GOTOS => {
			'ConditionalExpressionRest' => 109
		}
	},
	{#State 64
		DEFAULT => -54
	},
	{#State 65
		ACTIONS => {
			'SHORT_TOKEN' => 22,
			'INTEGER_LITERAL' => 53,
			'LONG_TOKEN' => 26,
			'VOID_TOKEN' => 54,
			'BYTE_TOKEN' => 27,
			'MINUS_OPR' => 30,
			'TRUE_TOKEN' => 58,
			'DOUBLE_TOKEN' => 57,
			'INT_TOKEN' => 59,
			'FALSE_TOKEN' => 32,
			'NULL_TOKEN' => 62,
			'POSTFIX_OPR' => 64,
			'LP_TOKEN' => 65,
			'FLOAT_LITERAL' => 36,
			'CHAR_TOKEN' => 38,
			'IDENTIFIER' => 90,
			'PLUS_OPR' => 41,
			'THIS_TOKEN' => 67,
			'BOOLEAN_TOKEN' => 69,
			'CHAR_LITERAL' => 43,
			'PREFIX_OPR' => 45,
			'FLOAT_TOKEN' => 47,
			'STRING_LITERAL' => 74,
			'NEW_TOKEN' => 73,
			'SUPER_TOKEN' => 76
		},
		GOTOS => {
			'AdditiveOpr' => 50,
			'CastExpression' => 21,
			'UnaryExpressionNotPlusMinus' => 23,
			'RelationalExpression' => 24,
			'InstanceOfExpression' => 25,
			'MultiplicativeExpression' => 28,
			'EqualityExpression' => 56,
			'ParExpression' => 61,
			'Primary' => 33,
			'ExclusiveOrExpression' => 34,
			'InclusiveOrExpression' => 35,
			'ConditionalOrExpression' => 63,
			'AllocationExpression' => 37,
			'Expression' => 114,
			'BasicType' => 112,
			'Literal' => 66,
			'UnaryOpr' => 42,
			'ConditionalAndExpression' => 70,
			'PrimaryExpression' => 44,
			'ShiftExpression' => 71,
			'UnaryExpression' => 48,
			'ConditionalExpression' => 113,
			'AdditiveExpression' => 75,
			'AndExpression' => 49,
			'PrimaryPrefix' => 77
		}
	},
	{#State 66
		DEFAULT => -64
	},
	{#State 67
		DEFAULT => -68
	},
	{#State 68
		DEFAULT => -178
	},
	{#State 69
		DEFAULT => -103
	},
	{#State 70
		ACTIONS => {
			'CAND_OPR' => 115
		},
		DEFAULT => -19
	},
	{#State 71
		ACTIONS => {
			'GT_OPR' => 118,
			'SHIFT_OPR' => 119,
			'RELATIONAL_OPR' => 120,
			'LT_OPR' => 121
		},
		DEFAULT => -33,
		GOTOS => {
			'RelationalOpr' => 117,
			'ShiftOpr' => 116
		}
	},
	{#State 72
		DEFAULT => -181
	},
	{#State 73
		ACTIONS => {
			'IDENTIFIER' => 123,
			'CHAR_TOKEN' => 38,
			'SHORT_TOKEN' => 22,
			'LONG_TOKEN' => 26,
			'BYTE_TOKEN' => 27,
			'BOOLEAN_TOKEN' => 69,
			'DOUBLE_TOKEN' => 57,
			'INT_TOKEN' => 59,
			'FLOAT_TOKEN' => 47
		},
		GOTOS => {
			'BasicType' => 122
		}
	},
	{#State 74
		DEFAULT => -4
	},
	{#State 75
		ACTIONS => {
			'MINUS_OPR' => 30,
			'PLUS_OPR' => 41
		},
		DEFAULT => -38,
		GOTOS => {
			'AdditiveOpr' => 124
		}
	},
	{#State 76
		DEFAULT => -69
	},
	{#State 77
		DEFAULT => -62
	},
	{#State 78
		DEFAULT => -362
	},
	{#State 79
		DEFAULT => -233
	},
	{#State 80
		DEFAULT => -244
	},
	{#State 81
		ACTIONS => {
			'IDENTIFIER' => 7
		},
		GOTOS => {
			'QualifiedIdentifier' => 125
		}
	},
	{#State 82
		DEFAULT => -240
	},
	{#State 83
		ACTIONS => {
			'' => -236,
			'VOLATILE_TOKEN' => 136,
			'FINAL_TOKEN' => 126,
			'PROTECTED_TOKEN' => 137,
			'SMC_TOKEN' => 78,
			'NATIVE_TOKEN' => 129,
			'STRICTFP_TOKEN' => 130,
			'ABSTRACT_TOKEN' => 132,
			'PUBLIC_TOKEN' => 133,
			'PRIVATE_TOKEN' => 140,
			'STATIC_TOKEN' => 142,
			'TRANSIENT_TOKEN' => 143,
			'ATMARK_TOKEN' => 2,
			'SYNCHRONIZED_TOKEN' => 135
		},
		DEFAULT => -205,
		GOTOS => {
			'ClassOrInterfaceDeclaration' => 127,
			'SmcToken' => 139,
			'TypeDeclarations' => 128,
			'TypeDeclarationsOrEmpty' => 138,
			'Modifier' => 141,
			'Annotation' => 145,
			'ModifiersOrEmpty' => 134,
			'TypeDeclaration' => 144,
			'Modifiers' => 131
		}
	},
	{#State 84
		ACTIONS => {
			'CHAR_TOKEN' => 38,
			'IDENTIFIER' => 7,
			'SHORT_TOKEN' => 22,
			'LONG_TOKEN' => 26,
			'BYTE_TOKEN' => 27,
			'BOOLEAN_TOKEN' => 69,
			'DOUBLE_TOKEN' => 57,
			'INT_TOKEN' => 59,
			'FLOAT_TOKEN' => 47
		},
		GOTOS => {
			'BasicType' => 148,
			'Type' => 147,
			'QualifiedIdentifier' => 146
		}
	},
	{#State 85
		ACTIONS => {
			'SHORT_TOKEN' => 22,
			'INTEGER_LITERAL' => 53,
			'LONG_TOKEN' => 26,
			'VOID_TOKEN' => 54,
			'BYTE_TOKEN' => 27,
			'MINUS_OPR' => 30,
			'TRUE_TOKEN' => 58,
			'DOUBLE_TOKEN' => 57,
			'INT_TOKEN' => 59,
			'FALSE_TOKEN' => 32,
			'NULL_TOKEN' => 62,
			'POSTFIX_OPR' => 64,
			'LP_TOKEN' => 65,
			'FLOAT_LITERAL' => 36,
			'CHAR_TOKEN' => 38,
			'IDENTIFIER' => 90,
			'PLUS_OPR' => 41,
			'THIS_TOKEN' => 67,
			'BOOLEAN_TOKEN' => 69,
			'CHAR_LITERAL' => 43,
			'PREFIX_OPR' => 45,
			'FLOAT_TOKEN' => 47,
			'STRING_LITERAL' => 74,
			'NEW_TOKEN' => 73,
			'SUPER_TOKEN' => 76
		},
		GOTOS => {
			'AdditiveOpr' => 50,
			'AllocationExpression' => 37,
			'CastExpression' => 21,
			'BasicType' => 40,
			'UnaryExpressionNotPlusMinus' => 23,
			'Literal' => 66,
			'UnaryOpr' => 42,
			'PrimaryExpression' => 44,
			'ParExpression' => 61,
			'UnaryExpression' => 149,
			'Primary' => 33,
			'PrimaryPrefix' => 77
		}
	},
	{#State 86
		DEFAULT => -50
	},
	{#State 87
		DEFAULT => -49
	},
	{#State 88
		ACTIONS => {
			'SHORT_TOKEN' => 22,
			'INTEGER_LITERAL' => 53,
			'LONG_TOKEN' => 26,
			'VOID_TOKEN' => 54,
			'BYTE_TOKEN' => 27,
			'LCB_TOKEN' => 55,
			'MINUS_OPR' => 30,
			'TRUE_TOKEN' => 58,
			'DOUBLE_TOKEN' => 57,
			'INT_TOKEN' => 59,
			'FALSE_TOKEN' => 32,
			'NULL_TOKEN' => 62,
			'POSTFIX_OPR' => 64,
			'LP_TOKEN' => 65,
			'FLOAT_LITERAL' => 36,
			'CHAR_TOKEN' => 38,
			'IDENTIFIER' => 39,
			'PLUS_OPR' => 41,
			'THIS_TOKEN' => 67,
			'BOOLEAN_TOKEN' => 69,
			'CHAR_LITERAL' => 43,
			'ATMARK_TOKEN' => 2,
			'PREFIX_OPR' => 45,
			'FLOAT_TOKEN' => 47,
			'STRING_LITERAL' => 74,
			'NEW_TOKEN' => 73,
			'SUPER_TOKEN' => 76
		},
		GOTOS => {
			'AdditiveOpr' => 50,
			'CastExpression' => 21,
			'UnaryExpressionNotPlusMinus' => 23,
			'RelationalExpression' => 24,
			'InstanceOfExpression' => 25,
			'ElementValueArrayInitializer' => 51,
			'MultiplicativeExpression' => 28,
			'EqualityExpression' => 56,
			'LcbToken' => 31,
			'AnnotationValue' => 150,
			'ParExpression' => 61,
			'Primary' => 33,
			'ExclusiveOrExpression' => 34,
			'InclusiveOrExpression' => 35,
			'ConditionalOrExpression' => 63,
			'AllocationExpression' => 37,
			'BasicType' => 40,
			'Literal' => 66,
			'UnaryOpr' => 42,
			'ElementValue' => 68,
			'ConditionalAndExpression' => 70,
			'PrimaryExpression' => 44,
			'ShiftExpression' => 71,
			'Annotation' => 72,
			'ConditionalExpression' => 46,
			'UnaryExpression' => 48,
			'AdditiveExpression' => 75,
			'AndExpression' => 49,
			'PrimaryPrefix' => 77
		}
	},
	{#State 89
		DEFAULT => -175
	},
	{#State 90
		DEFAULT => -70
	},
	{#State 91
		ACTIONS => {
			'RCB_TOKEN' => 151
		},
		GOTOS => {
			'RcbToken' => 152
		}
	},
	{#State 92
		ACTIONS => {
			'CM_TOKEN' => 153
		},
		DEFAULT => -226,
		GOTOS => {
			'CommaOrEmpty' => 154
		}
	},
	{#State 93
		DEFAULT => -186
	},
	{#State 94
		ACTIONS => {
			'SHORT_TOKEN' => 22,
			'INTEGER_LITERAL' => 53,
			'LONG_TOKEN' => 26,
			'VOID_TOKEN' => 54,
			'BYTE_TOKEN' => 27,
			'MINUS_OPR' => 30,
			'TRUE_TOKEN' => 58,
			'DOUBLE_TOKEN' => 57,
			'INT_TOKEN' => 59,
			'FALSE_TOKEN' => 32,
			'NULL_TOKEN' => 62,
			'RSB_TOKEN' => 155,
			'POSTFIX_OPR' => 64,
			'LP_TOKEN' => 65,
			'FLOAT_LITERAL' => 36,
			'CHAR_TOKEN' => 38,
			'IDENTIFIER' => 90,
			'PLUS_OPR' => 41,
			'THIS_TOKEN' => 67,
			'BOOLEAN_TOKEN' => 69,
			'CHAR_LITERAL' => 43,
			'PREFIX_OPR' => 45,
			'FLOAT_TOKEN' => 47,
			'STRING_LITERAL' => 74,
			'NEW_TOKEN' => 73,
			'SUPER_TOKEN' => 76
		},
		GOTOS => {
			'AdditiveOpr' => 50,
			'CastExpression' => 21,
			'UnaryExpressionNotPlusMinus' => 23,
			'RelationalExpression' => 24,
			'InstanceOfExpression' => 25,
			'MultiplicativeExpression' => 28,
			'EqualityExpression' => 56,
			'ParExpression' => 61,
			'Primary' => 33,
			'ExclusiveOrExpression' => 34,
			'InclusiveOrExpression' => 35,
			'ConditionalOrExpression' => 63,
			'AllocationExpression' => 37,
			'Expression' => 156,
			'BasicType' => 40,
			'Literal' => 66,
			'UnaryOpr' => 42,
			'ConditionalAndExpression' => 70,
			'PrimaryExpression' => 44,
			'ShiftExpression' => 71,
			'UnaryExpression' => 48,
			'ConditionalExpression' => 113,
			'AdditiveExpression' => 75,
			'AndExpression' => 49,
			'PrimaryPrefix' => 77
		}
	},
	{#State 95
		DEFAULT => -63
	},
	{#State 96
		ACTIONS => {
			'IDENTIFIER' => 159,
			'THIS_TOKEN' => 160,
			'CLASS_TOKEN' => 157,
			'NEW_TOKEN' => 73,
			'SUPER_TOKEN' => 161
		},
		GOTOS => {
			'AllocationExpression' => 158
		}
	},
	{#State 97
		ACTIONS => {
			'LCB_TOKEN' => 55
		},
		DEFAULT => -301,
		GOTOS => {
			'LcbToken' => 163,
			'ClassBody' => 162,
			'ClassBodyOrEmpty' => 164
		}
	},
	{#State 98
		DEFAULT => -77
	},
	{#State 99
		ACTIONS => {
			'LSB_TOKEN' => 165,
			'LCB_TOKEN' => 55
		},
		DEFAULT => -82,
		GOTOS => {
			'ArrayInitializer' => 167,
			'LcbToken' => 166,
			'ArrayInitializerOrEmpty' => 168
		}
	},
	{#State 100
		ACTIONS => {
			'SHORT_TOKEN' => 22,
			'INTEGER_LITERAL' => 53,
			'LONG_TOKEN' => 26,
			'VOID_TOKEN' => 54,
			'BYTE_TOKEN' => 27,
			'MINUS_OPR' => 30,
			'TRUE_TOKEN' => 58,
			'DOUBLE_TOKEN' => 57,
			'INT_TOKEN' => 59,
			'FALSE_TOKEN' => 32,
			'NULL_TOKEN' => 62,
			'POSTFIX_OPR' => 64,
			'LP_TOKEN' => 65,
			'FLOAT_LITERAL' => 36,
			'CHAR_TOKEN' => 38,
			'IDENTIFIER' => 90,
			'PLUS_OPR' => 41,
			'THIS_TOKEN' => 67,
			'BOOLEAN_TOKEN' => 69,
			'CHAR_LITERAL' => 43,
			'PREFIX_OPR' => 45,
			'FLOAT_TOKEN' => 47,
			'STRING_LITERAL' => 74,
			'NEW_TOKEN' => 73,
			'SUPER_TOKEN' => 76
		},
		DEFAULT => -12,
		GOTOS => {
			'AdditiveOpr' => 50,
			'CastExpression' => 21,
			'UnaryExpressionNotPlusMinus' => 23,
			'RelationalExpression' => 24,
			'InstanceOfExpression' => 25,
			'MultiplicativeExpression' => 28,
			'ExpressionList' => 169,
			'EqualityExpression' => 56,
			'ParExpression' => 61,
			'Primary' => 33,
			'ExclusiveOrExpression' => 34,
			'InclusiveOrExpression' => 35,
			'ConditionalOrExpression' => 63,
			'AllocationExpression' => 37,
			'Expression' => 171,
			'BasicType' => 40,
			'Literal' => 66,
			'UnaryOpr' => 42,
			'ConditionalAndExpression' => 70,
			'PrimaryExpression' => 44,
			'ShiftExpression' => 71,
			'UnaryExpression' => 48,
			'ConditionalExpression' => 113,
			'AdditiveExpression' => 75,
			'AndExpression' => 49,
			'PrimaryPrefix' => 77,
			'ExpressionListOrEmpty' => 170
		}
	},
	{#State 101
		ACTIONS => {
			'SHORT_TOKEN' => 22,
			'INTEGER_LITERAL' => 53,
			'LONG_TOKEN' => 26,
			'VOID_TOKEN' => 54,
			'BYTE_TOKEN' => 27,
			'MINUS_OPR' => 30,
			'TRUE_TOKEN' => 58,
			'DOUBLE_TOKEN' => 57,
			'INT_TOKEN' => 59,
			'FALSE_TOKEN' => 32,
			'NULL_TOKEN' => 62,
			'POSTFIX_OPR' => 64,
			'LP_TOKEN' => 65,
			'FLOAT_LITERAL' => 36,
			'CHAR_TOKEN' => 38,
			'IDENTIFIER' => 90,
			'PLUS_OPR' => 41,
			'THIS_TOKEN' => 67,
			'BOOLEAN_TOKEN' => 69,
			'CHAR_LITERAL' => 43,
			'PREFIX_OPR' => 45,
			'FLOAT_TOKEN' => 47,
			'STRING_LITERAL' => 74,
			'NEW_TOKEN' => 73,
			'SUPER_TOKEN' => 76
		},
		GOTOS => {
			'AdditiveOpr' => 50,
			'CastExpression' => 21,
			'UnaryExpressionNotPlusMinus' => 23,
			'RelationalExpression' => 24,
			'InstanceOfExpression' => 25,
			'MultiplicativeExpression' => 28,
			'EqualityExpression' => 56,
			'ParExpression' => 61,
			'Primary' => 33,
			'AllocationExpression' => 37,
			'BasicType' => 40,
			'Literal' => 66,
			'UnaryOpr' => 42,
			'PrimaryExpression' => 44,
			'ShiftExpression' => 71,
			'UnaryExpression' => 48,
			'AdditiveExpression' => 75,
			'AndExpression' => 172,
			'PrimaryPrefix' => 77
		}
	},
	{#State 102
		ACTIONS => {
			'SHORT_TOKEN' => 22,
			'INTEGER_LITERAL' => 53,
			'LONG_TOKEN' => 26,
			'VOID_TOKEN' => 54,
			'BYTE_TOKEN' => 27,
			'MINUS_OPR' => 30,
			'TRUE_TOKEN' => 58,
			'DOUBLE_TOKEN' => 57,
			'INT_TOKEN' => 59,
			'FALSE_TOKEN' => 32,
			'NULL_TOKEN' => 62,
			'POSTFIX_OPR' => 64,
			'LP_TOKEN' => 65,
			'FLOAT_LITERAL' => 36,
			'CHAR_TOKEN' => 38,
			'IDENTIFIER' => 90,
			'PLUS_OPR' => 41,
			'THIS_TOKEN' => 67,
			'BOOLEAN_TOKEN' => 69,
			'CHAR_LITERAL' => 43,
			'PREFIX_OPR' => 45,
			'FLOAT_TOKEN' => 47,
			'STRING_LITERAL' => 74,
			'NEW_TOKEN' => 73,
			'SUPER_TOKEN' => 76
		},
		GOTOS => {
			'AdditiveOpr' => 50,
			'CastExpression' => 21,
			'UnaryExpressionNotPlusMinus' => 23,
			'RelationalExpression' => 24,
			'InstanceOfExpression' => 25,
			'MultiplicativeExpression' => 28,
			'EqualityExpression' => 56,
			'ParExpression' => 61,
			'Primary' => 33,
			'ExclusiveOrExpression' => 173,
			'AllocationExpression' => 37,
			'BasicType' => 40,
			'Literal' => 66,
			'UnaryOpr' => 42,
			'PrimaryExpression' => 44,
			'ShiftExpression' => 71,
			'UnaryExpression' => 48,
			'AdditiveExpression' => 75,
			'AndExpression' => 49,
			'PrimaryPrefix' => 77
		}
	},
	{#State 103
		ACTIONS => {
			'SHORT_TOKEN' => 22,
			'INTEGER_LITERAL' => 53,
			'LONG_TOKEN' => 26,
			'VOID_TOKEN' => 54,
			'BYTE_TOKEN' => 27,
			'LCB_TOKEN' => 55,
			'MINUS_OPR' => 30,
			'TRUE_TOKEN' => 58,
			'DOUBLE_TOKEN' => 57,
			'INT_TOKEN' => 59,
			'FALSE_TOKEN' => 32,
			'NULL_TOKEN' => 62,
			'POSTFIX_OPR' => 64,
			'LP_TOKEN' => 65,
			'FLOAT_LITERAL' => 36,
			'CHAR_TOKEN' => 38,
			'IDENTIFIER' => 90,
			'PLUS_OPR' => 41,
			'THIS_TOKEN' => 67,
			'BOOLEAN_TOKEN' => 69,
			'CHAR_LITERAL' => 43,
			'ATMARK_TOKEN' => 2,
			'PREFIX_OPR' => 45,
			'FLOAT_TOKEN' => 47,
			'STRING_LITERAL' => 74,
			'NEW_TOKEN' => 73,
			'SUPER_TOKEN' => 76
		},
		GOTOS => {
			'AdditiveOpr' => 50,
			'CastExpression' => 21,
			'UnaryExpressionNotPlusMinus' => 23,
			'RelationalExpression' => 24,
			'InstanceOfExpression' => 25,
			'ElementValueArrayInitializer' => 51,
			'MultiplicativeExpression' => 28,
			'EqualityExpression' => 56,
			'LcbToken' => 31,
			'ParExpression' => 61,
			'Primary' => 33,
			'ExclusiveOrExpression' => 34,
			'InclusiveOrExpression' => 35,
			'ConditionalOrExpression' => 63,
			'AllocationExpression' => 37,
			'BasicType' => 40,
			'Literal' => 66,
			'UnaryOpr' => 42,
			'ElementValue' => 174,
			'ConditionalAndExpression' => 70,
			'PrimaryExpression' => 44,
			'ShiftExpression' => 71,
			'Annotation' => 72,
			'ConditionalExpression' => 46,
			'UnaryExpression' => 48,
			'AdditiveExpression' => 75,
			'AndExpression' => 49,
			'PrimaryPrefix' => 77
		}
	},
	{#State 104
		DEFAULT => -51
	},
	{#State 105
		DEFAULT => -58
	},
	{#State 106
		DEFAULT => -55
	},
	{#State 107
		ACTIONS => {
			'SHORT_TOKEN' => 22,
			'INTEGER_LITERAL' => 53,
			'LONG_TOKEN' => 26,
			'VOID_TOKEN' => 54,
			'BYTE_TOKEN' => 27,
			'MINUS_OPR' => 30,
			'TRUE_TOKEN' => 58,
			'DOUBLE_TOKEN' => 57,
			'INT_TOKEN' => 59,
			'FALSE_TOKEN' => 32,
			'NULL_TOKEN' => 62,
			'POSTFIX_OPR' => 64,
			'LP_TOKEN' => 65,
			'FLOAT_LITERAL' => 36,
			'CHAR_TOKEN' => 38,
			'IDENTIFIER' => 90,
			'PLUS_OPR' => 41,
			'THIS_TOKEN' => 67,
			'BOOLEAN_TOKEN' => 69,
			'CHAR_LITERAL' => 43,
			'PREFIX_OPR' => 45,
			'FLOAT_TOKEN' => 47,
			'STRING_LITERAL' => 74,
			'NEW_TOKEN' => 73,
			'SUPER_TOKEN' => 76
		},
		GOTOS => {
			'AdditiveOpr' => 50,
			'CastExpression' => 21,
			'UnaryExpressionNotPlusMinus' => 23,
			'RelationalExpression' => 24,
			'InstanceOfExpression' => 25,
			'MultiplicativeExpression' => 28,
			'EqualityExpression' => 175,
			'ParExpression' => 61,
			'Primary' => 33,
			'AllocationExpression' => 37,
			'BasicType' => 40,
			'Literal' => 66,
			'UnaryOpr' => 42,
			'PrimaryExpression' => 44,
			'ShiftExpression' => 71,
			'UnaryExpression' => 48,
			'AdditiveExpression' => 75,
			'PrimaryPrefix' => 77
		}
	},
	{#State 108
		ACTIONS => {
			'SHORT_TOKEN' => 22,
			'INTEGER_LITERAL' => 53,
			'LONG_TOKEN' => 26,
			'VOID_TOKEN' => 54,
			'BYTE_TOKEN' => 27,
			'MINUS_OPR' => 30,
			'TRUE_TOKEN' => 58,
			'DOUBLE_TOKEN' => 57,
			'INT_TOKEN' => 59,
			'FALSE_TOKEN' => 32,
			'NULL_TOKEN' => 62,
			'POSTFIX_OPR' => 64,
			'LP_TOKEN' => 65,
			'FLOAT_LITERAL' => 36,
			'CHAR_TOKEN' => 38,
			'IDENTIFIER' => 90,
			'PLUS_OPR' => 41,
			'THIS_TOKEN' => 67,
			'BOOLEAN_TOKEN' => 69,
			'CHAR_LITERAL' => 43,
			'PREFIX_OPR' => 45,
			'FLOAT_TOKEN' => 47,
			'STRING_LITERAL' => 74,
			'NEW_TOKEN' => 73,
			'SUPER_TOKEN' => 76
		},
		GOTOS => {
			'AdditiveOpr' => 50,
			'CastExpression' => 21,
			'UnaryExpressionNotPlusMinus' => 23,
			'RelationalExpression' => 24,
			'InstanceOfExpression' => 176,
			'MultiplicativeExpression' => 28,
			'ParExpression' => 61,
			'Primary' => 33,
			'AllocationExpression' => 37,
			'BasicType' => 40,
			'Literal' => 66,
			'UnaryOpr' => 42,
			'PrimaryExpression' => 44,
			'ShiftExpression' => 71,
			'UnaryExpression' => 48,
			'AdditiveExpression' => 75,
			'PrimaryPrefix' => 77
		}
	},
	{#State 109
		DEFAULT => -17
	},
	{#State 110
		ACTIONS => {
			'SHORT_TOKEN' => 22,
			'INTEGER_LITERAL' => 53,
			'LONG_TOKEN' => 26,
			'VOID_TOKEN' => 54,
			'BYTE_TOKEN' => 27,
			'MINUS_OPR' => 30,
			'TRUE_TOKEN' => 58,
			'DOUBLE_TOKEN' => 57,
			'INT_TOKEN' => 59,
			'FALSE_TOKEN' => 32,
			'NULL_TOKEN' => 62,
			'POSTFIX_OPR' => 64,
			'LP_TOKEN' => 65,
			'FLOAT_LITERAL' => 36,
			'CHAR_TOKEN' => 38,
			'IDENTIFIER' => 90,
			'PLUS_OPR' => 41,
			'THIS_TOKEN' => 67,
			'BOOLEAN_TOKEN' => 69,
			'CHAR_LITERAL' => 43,
			'PREFIX_OPR' => 45,
			'FLOAT_TOKEN' => 47,
			'STRING_LITERAL' => 74,
			'NEW_TOKEN' => 73,
			'SUPER_TOKEN' => 76
		},
		GOTOS => {
			'AdditiveOpr' => 50,
			'CastExpression' => 21,
			'UnaryExpressionNotPlusMinus' => 23,
			'RelationalExpression' => 24,
			'InstanceOfExpression' => 25,
			'MultiplicativeExpression' => 28,
			'EqualityExpression' => 56,
			'ParExpression' => 61,
			'Primary' => 33,
			'ExclusiveOrExpression' => 34,
			'InclusiveOrExpression' => 35,
			'AllocationExpression' => 37,
			'BasicType' => 40,
			'Literal' => 66,
			'UnaryOpr' => 42,
			'ConditionalAndExpression' => 177,
			'PrimaryExpression' => 44,
			'ShiftExpression' => 71,
			'UnaryExpression' => 48,
			'AdditiveExpression' => 75,
			'AndExpression' => 49,
			'PrimaryPrefix' => 77
		}
	},
	{#State 111
		ACTIONS => {
			'SHORT_TOKEN' => 22,
			'INTEGER_LITERAL' => 53,
			'LONG_TOKEN' => 26,
			'VOID_TOKEN' => 54,
			'BYTE_TOKEN' => 27,
			'MINUS_OPR' => 30,
			'TRUE_TOKEN' => 58,
			'DOUBLE_TOKEN' => 57,
			'INT_TOKEN' => 59,
			'FALSE_TOKEN' => 32,
			'NULL_TOKEN' => 62,
			'POSTFIX_OPR' => 64,
			'LP_TOKEN' => 65,
			'FLOAT_LITERAL' => 36,
			'CHAR_TOKEN' => 38,
			'IDENTIFIER' => 90,
			'PLUS_OPR' => 41,
			'THIS_TOKEN' => 67,
			'BOOLEAN_TOKEN' => 69,
			'CHAR_LITERAL' => 43,
			'PREFIX_OPR' => 45,
			'FLOAT_TOKEN' => 47,
			'STRING_LITERAL' => 74,
			'NEW_TOKEN' => 73,
			'SUPER_TOKEN' => 76
		},
		GOTOS => {
			'AdditiveOpr' => 50,
			'CastExpression' => 21,
			'UnaryExpressionNotPlusMinus' => 23,
			'RelationalExpression' => 24,
			'InstanceOfExpression' => 25,
			'MultiplicativeExpression' => 28,
			'EqualityExpression' => 56,
			'ParExpression' => 61,
			'Primary' => 33,
			'ExclusiveOrExpression' => 34,
			'InclusiveOrExpression' => 35,
			'ConditionalOrExpression' => 63,
			'AllocationExpression' => 37,
			'Expression' => 178,
			'BasicType' => 40,
			'Literal' => 66,
			'UnaryOpr' => 42,
			'ConditionalAndExpression' => 70,
			'PrimaryExpression' => 44,
			'ShiftExpression' => 71,
			'UnaryExpression' => 48,
			'ConditionalExpression' => 113,
			'AdditiveExpression' => 75,
			'AndExpression' => 49,
			'PrimaryPrefix' => 77
		}
	},
	{#State 112
		ACTIONS => {
			'RP_TOKEN' => 179
		},
		DEFAULT => -65
	},
	{#State 113
		DEFAULT => -8
	},
	{#State 114
		ACTIONS => {
			'EQUAL_OPR' => 182,
			'ASSIGN_P_OPR' => 180,
			'ASSIGN_OPR' => 184,
			'RP_TOKEN' => 183
		},
		GOTOS => {
			'AssignmentOperator' => 181
		}
	},
	{#State 115
		ACTIONS => {
			'SHORT_TOKEN' => 22,
			'INTEGER_LITERAL' => 53,
			'LONG_TOKEN' => 26,
			'VOID_TOKEN' => 54,
			'BYTE_TOKEN' => 27,
			'MINUS_OPR' => 30,
			'TRUE_TOKEN' => 58,
			'DOUBLE_TOKEN' => 57,
			'INT_TOKEN' => 59,
			'FALSE_TOKEN' => 32,
			'NULL_TOKEN' => 62,
			'POSTFIX_OPR' => 64,
			'LP_TOKEN' => 65,
			'FLOAT_LITERAL' => 36,
			'CHAR_TOKEN' => 38,
			'IDENTIFIER' => 90,
			'PLUS_OPR' => 41,
			'THIS_TOKEN' => 67,
			'BOOLEAN_TOKEN' => 69,
			'CHAR_LITERAL' => 43,
			'PREFIX_OPR' => 45,
			'FLOAT_TOKEN' => 47,
			'STRING_LITERAL' => 74,
			'NEW_TOKEN' => 73,
			'SUPER_TOKEN' => 76
		},
		GOTOS => {
			'AdditiveOpr' => 50,
			'CastExpression' => 21,
			'UnaryExpressionNotPlusMinus' => 23,
			'RelationalExpression' => 24,
			'InstanceOfExpression' => 25,
			'MultiplicativeExpression' => 28,
			'EqualityExpression' => 56,
			'ParExpression' => 61,
			'Primary' => 33,
			'ExclusiveOrExpression' => 34,
			'InclusiveOrExpression' => 185,
			'AllocationExpression' => 37,
			'BasicType' => 40,
			'Literal' => 66,
			'UnaryOpr' => 42,
			'PrimaryExpression' => 44,
			'ShiftExpression' => 71,
			'UnaryExpression' => 48,
			'AdditiveExpression' => 75,
			'AndExpression' => 49,
			'PrimaryPrefix' => 77
		}
	},
	{#State 116
		ACTIONS => {
			'SHORT_TOKEN' => 22,
			'INTEGER_LITERAL' => 53,
			'LONG_TOKEN' => 26,
			'VOID_TOKEN' => 54,
			'BYTE_TOKEN' => 27,
			'MINUS_OPR' => 30,
			'TRUE_TOKEN' => 58,
			'DOUBLE_TOKEN' => 57,
			'INT_TOKEN' => 59,
			'FALSE_TOKEN' => 32,
			'NULL_TOKEN' => 62,
			'POSTFIX_OPR' => 64,
			'LP_TOKEN' => 65,
			'FLOAT_LITERAL' => 36,
			'CHAR_TOKEN' => 38,
			'IDENTIFIER' => 90,
			'PLUS_OPR' => 41,
			'THIS_TOKEN' => 67,
			'BOOLEAN_TOKEN' => 69,
			'CHAR_LITERAL' => 43,
			'PREFIX_OPR' => 45,
			'FLOAT_TOKEN' => 47,
			'STRING_LITERAL' => 74,
			'NEW_TOKEN' => 73,
			'SUPER_TOKEN' => 76
		},
		GOTOS => {
			'AdditiveOpr' => 50,
			'AllocationExpression' => 37,
			'CastExpression' => 21,
			'BasicType' => 40,
			'UnaryExpressionNotPlusMinus' => 23,
			'Literal' => 66,
			'UnaryOpr' => 42,
			'MultiplicativeExpression' => 28,
			'PrimaryExpression' => 44,
			'ParExpression' => 61,
			'UnaryExpression' => 48,
			'AdditiveExpression' => 186,
			'Primary' => 33,
			'PrimaryPrefix' => 77
		}
	},
	{#State 117
		ACTIONS => {
			'SHORT_TOKEN' => 22,
			'INTEGER_LITERAL' => 53,
			'LONG_TOKEN' => 26,
			'VOID_TOKEN' => 54,
			'BYTE_TOKEN' => 27,
			'MINUS_OPR' => 30,
			'TRUE_TOKEN' => 58,
			'DOUBLE_TOKEN' => 57,
			'INT_TOKEN' => 59,
			'FALSE_TOKEN' => 32,
			'NULL_TOKEN' => 62,
			'POSTFIX_OPR' => 64,
			'LP_TOKEN' => 65,
			'FLOAT_LITERAL' => 36,
			'CHAR_TOKEN' => 38,
			'IDENTIFIER' => 90,
			'PLUS_OPR' => 41,
			'THIS_TOKEN' => 67,
			'BOOLEAN_TOKEN' => 69,
			'CHAR_LITERAL' => 43,
			'PREFIX_OPR' => 45,
			'FLOAT_TOKEN' => 47,
			'STRING_LITERAL' => 74,
			'NEW_TOKEN' => 73,
			'SUPER_TOKEN' => 76
		},
		GOTOS => {
			'AdditiveOpr' => 50,
			'AllocationExpression' => 37,
			'CastExpression' => 21,
			'BasicType' => 40,
			'UnaryExpressionNotPlusMinus' => 23,
			'Literal' => 66,
			'UnaryOpr' => 42,
			'MultiplicativeExpression' => 28,
			'PrimaryExpression' => 44,
			'ShiftExpression' => 187,
			'ParExpression' => 61,
			'UnaryExpression' => 48,
			'AdditiveExpression' => 75,
			'Primary' => 33,
			'PrimaryPrefix' => 77
		}
	},
	{#State 118
		ACTIONS => {
			'GT_OPR' => 188
		},
		DEFAULT => -36
	},
	{#State 119
		DEFAULT => -40
	},
	{#State 120
		DEFAULT => -35
	},
	{#State 121
		DEFAULT => -37
	},
	{#State 122
		DEFAULT => -81
	},
	{#State 123
		DEFAULT => -80
	},
	{#State 124
		ACTIONS => {
			'SHORT_TOKEN' => 22,
			'INTEGER_LITERAL' => 53,
			'LONG_TOKEN' => 26,
			'VOID_TOKEN' => 54,
			'BYTE_TOKEN' => 27,
			'MINUS_OPR' => 30,
			'TRUE_TOKEN' => 58,
			'DOUBLE_TOKEN' => 57,
			'INT_TOKEN' => 59,
			'FALSE_TOKEN' => 32,
			'NULL_TOKEN' => 62,
			'POSTFIX_OPR' => 64,
			'LP_TOKEN' => 65,
			'FLOAT_LITERAL' => 36,
			'CHAR_TOKEN' => 38,
			'IDENTIFIER' => 90,
			'PLUS_OPR' => 41,
			'THIS_TOKEN' => 67,
			'BOOLEAN_TOKEN' => 69,
			'CHAR_LITERAL' => 43,
			'PREFIX_OPR' => 45,
			'FLOAT_TOKEN' => 47,
			'STRING_LITERAL' => 74,
			'NEW_TOKEN' => 73,
			'SUPER_TOKEN' => 76
		},
		GOTOS => {
			'AdditiveOpr' => 50,
			'AllocationExpression' => 37,
			'CastExpression' => 21,
			'BasicType' => 40,
			'UnaryExpressionNotPlusMinus' => 23,
			'Literal' => 66,
			'UnaryOpr' => 42,
			'MultiplicativeExpression' => 189,
			'PrimaryExpression' => 44,
			'ParExpression' => 61,
			'UnaryExpression' => 48,
			'Primary' => 33,
			'PrimaryPrefix' => 77
		}
	},
	{#State 125
		ACTIONS => {
			'DOT_TOKEN' => 190
		},
		DEFAULT => -241,
		GOTOS => {
			'DotAllOrEmpty' => 191
		}
	},
	{#State 126
		DEFAULT => -197
	},
	{#State 127
		DEFAULT => -245
	},
	{#State 128
		ACTIONS => {
			'' => -237,
			'VOLATILE_TOKEN' => 136,
			'FINAL_TOKEN' => 126,
			'PROTECTED_TOKEN' => 137,
			'SMC_TOKEN' => 78,
			'NATIVE_TOKEN' => 129,
			'STRICTFP_TOKEN' => 130,
			'ABSTRACT_TOKEN' => 132,
			'PUBLIC_TOKEN' => 133,
			'PRIVATE_TOKEN' => 140,
			'STATIC_TOKEN' => 142,
			'TRANSIENT_TOKEN' => 143,
			'ATMARK_TOKEN' => 2,
			'SYNCHRONIZED_TOKEN' => 135
		},
		DEFAULT => -205,
		GOTOS => {
			'Modifier' => 141,
			'ClassOrInterfaceDeclaration' => 127,
			'TypeDeclaration' => 192,
			'Annotation' => 145,
			'ModifiersOrEmpty' => 134,
			'SmcToken' => 139,
			'Modifiers' => 131
		}
	},
	{#State 129
		DEFAULT => -198
	},
	{#State 130
		DEFAULT => -202
	},
	{#State 131
		ACTIONS => {
			'VOLATILE_TOKEN' => 136,
			'FINAL_TOKEN' => 126,
			'PROTECTED_TOKEN' => 137,
			'NATIVE_TOKEN' => 129,
			'STRICTFP_TOKEN' => 130,
			'ABSTRACT_TOKEN' => 132,
			'PUBLIC_TOKEN' => 133,
			'PRIVATE_TOKEN' => 140,
			'STATIC_TOKEN' => 142,
			'TRANSIENT_TOKEN' => 143,
			'ATMARK_TOKEN' => 2,
			'SYNCHRONIZED_TOKEN' => 135
		},
		DEFAULT => -206,
		GOTOS => {
			'Modifier' => 193,
			'Annotation' => 145
		}
	},
	{#State 132
		DEFAULT => -196
	},
	{#State 133
		DEFAULT => -192
	},
	{#State 134
		ACTIONS => {
			'INTERFACE_TOKEN' => 203,
			'ENUM_TOKEN' => 194,
			'ATMARK_INTERFACE_TOKEN' => 204,
			'CLASS_TOKEN' => 195
		},
		GOTOS => {
			'NormalInterfaceDeclaration' => 197,
			'EnumDeclaration' => 199,
			'ClassOrInterfaceDeclarationDecl' => 200,
			'NormalClassDeclaration' => 202,
			'InterfaceOrAtInterface' => 196,
			'ClassDeclaration' => 198,
			'InterfaceDeclaration' => 201
		}
	},
	{#State 135
		DEFAULT => -199
	},
	{#State 136
		DEFAULT => -201
	},
	{#State 137
		DEFAULT => -193
	},
	{#State 138
		DEFAULT => -231
	},
	{#State 139
		DEFAULT => -246
	},
	{#State 140
		DEFAULT => -194
	},
	{#State 141
		DEFAULT => -203
	},
	{#State 142
		DEFAULT => -195
	},
	{#State 143
		DEFAULT => -200
	},
	{#State 144
		DEFAULT => -247
	},
	{#State 145
		DEFAULT => -191
	},
	{#State 146
		ACTIONS => {
			'LSB_TOKEN' => 205,
			'DOT_TOKEN' => 12
		},
		DEFAULT => -90,
		GOTOS => {
			'ArrayDim' => 207,
			'ArrayDimOrEmpty' => 206
		}
	},
	{#State 147
		DEFAULT => -32
	},
	{#State 148
		ACTIONS => {
			'LSB_TOKEN' => 205
		},
		DEFAULT => -90,
		GOTOS => {
			'ArrayDim' => 207,
			'ArrayDimOrEmpty' => 208
		}
	},
	{#State 149
		DEFAULT => -48
	},
	{#State 150
		DEFAULT => -177
	},
	{#State 151
		DEFAULT => -364
	},
	{#State 152
		DEFAULT => -183
	},
	{#State 153
		ACTIONS => {
			'SHORT_TOKEN' => 22,
			'INTEGER_LITERAL' => 53,
			'LONG_TOKEN' => 26,
			'VOID_TOKEN' => 54,
			'BYTE_TOKEN' => 27,
			'LCB_TOKEN' => 55,
			'MINUS_OPR' => 30,
			'TRUE_TOKEN' => 58,
			'DOUBLE_TOKEN' => 57,
			'INT_TOKEN' => 59,
			'FALSE_TOKEN' => 32,
			'NULL_TOKEN' => 62,
			'POSTFIX_OPR' => 64,
			'LP_TOKEN' => 65,
			'FLOAT_LITERAL' => 36,
			'CHAR_TOKEN' => 38,
			'IDENTIFIER' => 90,
			'PLUS_OPR' => 41,
			'THIS_TOKEN' => 67,
			'BOOLEAN_TOKEN' => 69,
			'CHAR_LITERAL' => 43,
			'ATMARK_TOKEN' => 2,
			'PREFIX_OPR' => 45,
			'FLOAT_TOKEN' => 47,
			'STRING_LITERAL' => 74,
			'NEW_TOKEN' => 73,
			'SUPER_TOKEN' => 76
		},
		DEFAULT => -227,
		GOTOS => {
			'AdditiveOpr' => 50,
			'CastExpression' => 21,
			'UnaryExpressionNotPlusMinus' => 23,
			'RelationalExpression' => 24,
			'InstanceOfExpression' => 25,
			'ElementValueArrayInitializer' => 51,
			'MultiplicativeExpression' => 28,
			'EqualityExpression' => 56,
			'LcbToken' => 31,
			'ParExpression' => 61,
			'Primary' => 33,
			'ExclusiveOrExpression' => 34,
			'InclusiveOrExpression' => 35,
			'ConditionalOrExpression' => 63,
			'AllocationExpression' => 37,
			'BasicType' => 40,
			'Literal' => 66,
			'UnaryOpr' => 42,
			'ElementValue' => 209,
			'ConditionalAndExpression' => 70,
			'PrimaryExpression' => 44,
			'ShiftExpression' => 71,
			'Annotation' => 72,
			'ConditionalExpression' => 46,
			'UnaryExpression' => 48,
			'AdditiveExpression' => 75,
			'AndExpression' => 49,
			'PrimaryPrefix' => 77
		}
	},
	{#State 154
		DEFAULT => -185
	},
	{#State 155
		DEFAULT => -92
	},
	{#State 156
		ACTIONS => {
			'EQUAL_OPR' => 182,
			'ASSIGN_P_OPR' => 180,
			'ASSIGN_OPR' => 184,
			'RSB_TOKEN' => 210
		},
		GOTOS => {
			'AssignmentOperator' => 181
		}
	},
	{#State 157
		DEFAULT => -74
	},
	{#State 158
		DEFAULT => -75
	},
	{#State 159
		DEFAULT => -76
	},
	{#State 160
		DEFAULT => -72
	},
	{#State 161
		DEFAULT => -73
	},
	{#State 162
		DEFAULT => -302
	},
	{#State 163
		ACTIONS => {
			'VOLATILE_TOKEN' => 136,
			'FINAL_TOKEN' => 126,
			'PROTECTED_TOKEN' => 137,
			'LCB_TOKEN' => -239,
			'SMC_TOKEN' => 78,
			'LINE_DECL_TOKEN' => 216,
			'NATIVE_TOKEN' => 129,
			'STRICTFP_TOKEN' => 130,
			'RCB_TOKEN' => 151,
			'ABSTRACT_TOKEN' => 132,
			'PUBLIC_TOKEN' => 133,
			'PRIVATE_TOKEN' => 140,
			'STATIC_TOKEN' => 219,
			'TRANSIENT_TOKEN' => 143,
			'ATMARK_TOKEN' => 2,
			'SYNCHRONIZED_TOKEN' => 135
		},
		DEFAULT => -205,
		GOTOS => {
			'LineDecl' => 217,
			'StaticOrEmpty' => 212,
			'SmcToken' => 218,
			'ClassBodyDeclarations' => 213,
			'RcbToken' => 214,
			'Modifier' => 141,
			'Annotation' => 145,
			'ModifiersOrEmpty' => 215,
			'ClassBodyDeclaration' => 211,
			'Modifiers' => 131
		}
	},
	{#State 164
		DEFAULT => -79
	},
	{#State 165
		ACTIONS => {
			'RSB_TOKEN' => 220
		}
	},
	{#State 166
		ACTIONS => {
			'SHORT_TOKEN' => 22,
			'INTEGER_LITERAL' => 53,
			'LONG_TOKEN' => 26,
			'VOID_TOKEN' => 54,
			'BYTE_TOKEN' => 27,
			'LCB_TOKEN' => 55,
			'MINUS_OPR' => 30,
			'TRUE_TOKEN' => 58,
			'DOUBLE_TOKEN' => 57,
			'INT_TOKEN' => 59,
			'FALSE_TOKEN' => 32,
			'NULL_TOKEN' => 62,
			'POSTFIX_OPR' => 64,
			'LP_TOKEN' => 65,
			'FLOAT_LITERAL' => 36,
			'CHAR_TOKEN' => 38,
			'IDENTIFIER' => 90,
			'PLUS_OPR' => 41,
			'THIS_TOKEN' => 67,
			'BOOLEAN_TOKEN' => 69,
			'CHAR_LITERAL' => 43,
			'PREFIX_OPR' => 45,
			'FLOAT_TOKEN' => 47,
			'STRING_LITERAL' => 74,
			'NEW_TOKEN' => 73,
			'SUPER_TOKEN' => 76
		},
		DEFAULT => -222,
		GOTOS => {
			'AdditiveOpr' => 50,
			'CastExpression' => 21,
			'UnaryExpressionNotPlusMinus' => 23,
			'RelationalExpression' => 24,
			'InstanceOfExpression' => 25,
			'MultiplicativeExpression' => 28,
			'EqualityExpression' => 56,
			'ArrayInitializer' => 221,
			'LcbToken' => 166,
			'ParExpression' => 61,
			'VariableInitializerList' => 222,
			'Primary' => 33,
			'ExclusiveOrExpression' => 34,
			'InclusiveOrExpression' => 35,
			'ConditionalOrExpression' => 63,
			'AllocationExpression' => 37,
			'Expression' => 224,
			'BasicType' => 40,
			'Literal' => 66,
			'UnaryOpr' => 42,
			'VariableInitializer' => 225,
			'ConditionalAndExpression' => 70,
			'PrimaryExpression' => 44,
			'ShiftExpression' => 71,
			'UnaryExpression' => 48,
			'ConditionalExpression' => 113,
			'AdditiveExpression' => 75,
			'AndExpression' => 49,
			'PrimaryPrefix' => 77,
			'VariableInitializerListOrEmpty' => 223
		}
	},
	{#State 167
		DEFAULT => -83
	},
	{#State 168
		DEFAULT => -78
	},
	{#State 169
		ACTIONS => {
			'CM_TOKEN' => 226
		},
		DEFAULT => -13
	},
	{#State 170
		ACTIONS => {
			'RP_TOKEN' => 227
		}
	},
	{#State 171
		ACTIONS => {
			'EQUAL_OPR' => 182,
			'ASSIGN_P_OPR' => 180,
			'ASSIGN_OPR' => 184
		},
		DEFAULT => -10,
		GOTOS => {
			'AssignmentOperator' => 181
		}
	},
	{#State 172
		ACTIONS => {
			'AMP_OPR' => 107
		},
		DEFAULT => -26
	},
	{#State 173
		ACTIONS => {
			'NOR_OPR' => 101
		},
		DEFAULT => -24
	},
	{#State 174
		DEFAULT => -179
	},
	{#State 175
		ACTIONS => {
			'EQUALITY_OPR' => 108
		},
		DEFAULT => -28
	},
	{#State 176
		DEFAULT => -30
	},
	{#State 177
		ACTIONS => {
			'CAND_OPR' => 115
		},
		DEFAULT => -20
	},
	{#State 178
		ACTIONS => {
			'EQUAL_OPR' => 182,
			'ASSIGN_P_OPR' => 180,
			'CLN_TOKEN' => 228,
			'ASSIGN_OPR' => 184
		},
		GOTOS => {
			'AssignmentOperator' => 181
		}
	},
	{#State 179
		ACTIONS => {
			'SHORT_TOKEN' => 22,
			'INTEGER_LITERAL' => 53,
			'LONG_TOKEN' => 26,
			'VOID_TOKEN' => 54,
			'BYTE_TOKEN' => 27,
			'MINUS_OPR' => 30,
			'TRUE_TOKEN' => 58,
			'DOUBLE_TOKEN' => 57,
			'INT_TOKEN' => 59,
			'FALSE_TOKEN' => 32,
			'NULL_TOKEN' => 62,
			'POSTFIX_OPR' => 64,
			'LP_TOKEN' => 65,
			'FLOAT_LITERAL' => 36,
			'CHAR_TOKEN' => 38,
			'IDENTIFIER' => 90,
			'PLUS_OPR' => 41,
			'THIS_TOKEN' => 67,
			'BOOLEAN_TOKEN' => 69,
			'CHAR_LITERAL' => 43,
			'PREFIX_OPR' => 45,
			'FLOAT_TOKEN' => 47,
			'STRING_LITERAL' => 74,
			'NEW_TOKEN' => 73,
			'SUPER_TOKEN' => 76
		},
		GOTOS => {
			'AdditiveOpr' => 50,
			'AllocationExpression' => 37,
			'CastExpression' => 21,
			'BasicType' => 40,
			'UnaryExpressionNotPlusMinus' => 23,
			'Literal' => 66,
			'UnaryOpr' => 42,
			'PrimaryExpression' => 44,
			'ParExpression' => 61,
			'UnaryExpression' => 229,
			'Primary' => 33,
			'PrimaryPrefix' => 77
		}
	},
	{#State 180
		DEFAULT => -86
	},
	{#State 181
		ACTIONS => {
			'SHORT_TOKEN' => 22,
			'INTEGER_LITERAL' => 53,
			'LONG_TOKEN' => 26,
			'VOID_TOKEN' => 54,
			'BYTE_TOKEN' => 27,
			'MINUS_OPR' => 30,
			'TRUE_TOKEN' => 58,
			'DOUBLE_TOKEN' => 57,
			'INT_TOKEN' => 59,
			'FALSE_TOKEN' => 32,
			'NULL_TOKEN' => 62,
			'POSTFIX_OPR' => 64,
			'LP_TOKEN' => 65,
			'FLOAT_LITERAL' => 36,
			'CHAR_TOKEN' => 38,
			'IDENTIFIER' => 90,
			'PLUS_OPR' => 41,
			'THIS_TOKEN' => 67,
			'BOOLEAN_TOKEN' => 69,
			'CHAR_LITERAL' => 43,
			'PREFIX_OPR' => 45,
			'FLOAT_TOKEN' => 47,
			'STRING_LITERAL' => 74,
			'NEW_TOKEN' => 73,
			'SUPER_TOKEN' => 76
		},
		GOTOS => {
			'AdditiveOpr' => 50,
			'CastExpression' => 21,
			'UnaryExpressionNotPlusMinus' => 23,
			'RelationalExpression' => 24,
			'InstanceOfExpression' => 25,
			'MultiplicativeExpression' => 28,
			'EqualityExpression' => 56,
			'ParExpression' => 61,
			'Primary' => 33,
			'ExclusiveOrExpression' => 34,
			'InclusiveOrExpression' => 35,
			'ConditionalOrExpression' => 63,
			'AllocationExpression' => 37,
			'BasicType' => 40,
			'Literal' => 66,
			'UnaryOpr' => 42,
			'ConditionalAndExpression' => 70,
			'PrimaryExpression' => 44,
			'ShiftExpression' => 71,
			'UnaryExpression' => 48,
			'ConditionalExpression' => 230,
			'AdditiveExpression' => 75,
			'AndExpression' => 49,
			'PrimaryPrefix' => 77
		}
	},
	{#State 182
		DEFAULT => -85
	},
	{#State 183
		ACTIONS => {
			'SHORT_TOKEN' => 22,
			'LONG_TOKEN' => 26,
			'BYTE_TOKEN' => 27,
			'FALSE_TOKEN' => 32,
			'PREFIX_OPR' => 45,
			'FLOAT_TOKEN' => 47,
			'INTEGER_LITERAL' => 53,
			'VOID_TOKEN' => 54,
			'DOUBLE_TOKEN' => 57,
			'NULL_TOKEN' => 62,
			'LP_TOKEN' => 65,
			'THIS_TOKEN' => 67,
			'STRING_LITERAL' => 74,
			'SUPER_TOKEN' => 76,
			'FLOAT_LITERAL' => 36,
			'IDENTIFIER' => 90,
			'CHAR_TOKEN' => 38,
			'CHAR_LITERAL' => 43,
			'TRUE_TOKEN' => 58,
			'INT_TOKEN' => 59,
			'BOOLEAN_TOKEN' => 69,
			'NEW_TOKEN' => 73
		},
		DEFAULT => -107,
		GOTOS => {
			'AllocationExpression' => 37,
			'CastExpression' => 21,
			'BasicType' => 40,
			'UnaryExpressionNotPlusMinus' => 231,
			'Literal' => 66,
			'PrimaryExpression' => 44,
			'ParExpression' => 61,
			'Primary' => 33,
			'PrimaryPrefix' => 77
		}
	},
	{#State 184
		DEFAULT => -87
	},
	{#State 185
		ACTIONS => {
			'OR_OPR' => 102
		},
		DEFAULT => -22
	},
	{#State 186
		ACTIONS => {
			'MINUS_OPR' => 30,
			'PLUS_OPR' => 41
		},
		DEFAULT => -39,
		GOTOS => {
			'AdditiveOpr' => 124
		}
	},
	{#State 187
		ACTIONS => {
			'GT_OPR' => 232,
			'SHIFT_OPR' => 119
		},
		DEFAULT => -34,
		GOTOS => {
			'ShiftOpr' => 116
		}
	},
	{#State 188
		ACTIONS => {
			'GT_OPR' => 233
		},
		DEFAULT => -41
	},
	{#State 189
		ACTIONS => {
			'MULTI_OPR' => 86,
			'ASTARI_OPR' => 87
		},
		DEFAULT => -44,
		GOTOS => {
			'MultiplicativeOpr' => 85
		}
	},
	{#State 190
		ACTIONS => {
			'IDENTIFIER' => 20,
			'ASTARI_OPR' => 234
		}
	},
	{#State 191
		ACTIONS => {
			'SMC_TOKEN' => 78
		},
		GOTOS => {
			'SmcToken' => 235
		}
	},
	{#State 192
		DEFAULT => -248
	},
	{#State 193
		DEFAULT => -204
	},
	{#State 194
		ACTIONS => {
			'IDENTIFIER' => 236
		}
	},
	{#State 195
		ACTIONS => {
			'IDENTIFIER' => 237
		}
	},
	{#State 196
		ACTIONS => {
			'IDENTIFIER' => 238
		}
	},
	{#State 197
		DEFAULT => -287
	},
	{#State 198
		DEFAULT => -250
	},
	{#State 199
		DEFAULT => -253
	},
	{#State 200
		DEFAULT => -249
	},
	{#State 201
		DEFAULT => -251
	},
	{#State 202
		DEFAULT => -252
	},
	{#State 203
		DEFAULT => -291
	},
	{#State 204
		DEFAULT => -292
	},
	{#State 205
		ACTIONS => {
			'RSB_TOKEN' => 155
		}
	},
	{#State 206
		DEFAULT => -88
	},
	{#State 207
		ACTIONS => {
			'LSB_TOKEN' => 165
		},
		DEFAULT => -91
	},
	{#State 208
		DEFAULT => -89
	},
	{#State 209
		DEFAULT => -187
	},
	{#State 210
		DEFAULT => -84
	},
	{#State 211
		DEFAULT => -308
	},
	{#State 212
		ACTIONS => {
			'LCB_TOKEN' => 55
		},
		GOTOS => {
			'Block' => 240,
			'LcbToken' => 239
		}
	},
	{#State 213
		ACTIONS => {
			'VOLATILE_TOKEN' => 136,
			'FINAL_TOKEN' => 126,
			'PROTECTED_TOKEN' => 137,
			'LCB_TOKEN' => -239,
			'SMC_TOKEN' => 78,
			'LINE_DECL_TOKEN' => 216,
			'NATIVE_TOKEN' => 129,
			'STRICTFP_TOKEN' => 130,
			'RCB_TOKEN' => 151,
			'ABSTRACT_TOKEN' => 132,
			'PUBLIC_TOKEN' => 133,
			'PRIVATE_TOKEN' => 140,
			'STATIC_TOKEN' => 219,
			'TRANSIENT_TOKEN' => 143,
			'ATMARK_TOKEN' => 2,
			'SYNCHRONIZED_TOKEN' => 135
		},
		DEFAULT => -205,
		GOTOS => {
			'LineDecl' => 217,
			'StaticOrEmpty' => 212,
			'SmcToken' => 218,
			'RcbToken' => 242,
			'Modifier' => 141,
			'ModifiersOrEmpty' => 215,
			'Annotation' => 145,
			'ClassBodyDeclaration' => 241,
			'Modifiers' => 131
		}
	},
	{#State 214
		DEFAULT => -299
	},
	{#State 215
		ACTIONS => {
			'CHAR_TOKEN' => 38,
			'IDENTIFIER' => 246,
			'SHORT_TOKEN' => 22,
			'ENUM_TOKEN' => 194,
			'CLASS_TOKEN' => 195,
			'LONG_TOKEN' => 26,
			'VOID_TOKEN' => 251,
			'BYTE_TOKEN' => 27,
			'BOOLEAN_TOKEN' => 69,
			'DOUBLE_TOKEN' => 57,
			'INTERFACE_TOKEN' => 203,
			'INT_TOKEN' => 59,
			'ATMARK_INTERFACE_TOKEN' => 204,
			'FLOAT_TOKEN' => 47,
			'LT_OPR' => 253
		},
		GOTOS => {
			'MethodDecl' => 250,
			'BasicType' => 148,
			'FieldDecl' => 245,
			'EnumDeclaration' => 199,
			'QualifiedIdentifier' => 146,
			'NormalClassDeclaration' => 202,
			'MemberDecl' => 248,
			'TypeParameters' => 247,
			'InterfaceOrAtInterface' => 196,
			'InterfaceDeclaration' => 249,
			'GenericMethodOrConstructorDecl' => 252,
			'NormalInterfaceDeclaration' => 197,
			'Type' => 243,
			'ClassDeclaration' => 244
		}
	},
	{#State 216
		ACTIONS => {
			'INTEGER_LITERAL' => 254
		}
	},
	{#State 217
		DEFAULT => -311
	},
	{#State 218
		DEFAULT => -310
	},
	{#State 219
		ACTIONS => {
			'LCB_TOKEN' => -240
		},
		DEFAULT => -195
	},
	{#State 220
		DEFAULT => -93
	},
	{#State 221
		DEFAULT => -220
	},
	{#State 222
		ACTIONS => {
			'CM_TOKEN' => 255
		},
		DEFAULT => -226,
		GOTOS => {
			'CommaOrEmpty' => 256
		}
	},
	{#State 223
		ACTIONS => {
			'RCB_TOKEN' => 151
		},
		GOTOS => {
			'RcbToken' => 257
		}
	},
	{#State 224
		ACTIONS => {
			'EQUAL_OPR' => 182,
			'ASSIGN_P_OPR' => 180,
			'ASSIGN_OPR' => 184
		},
		DEFAULT => -221,
		GOTOS => {
			'AssignmentOperator' => 181
		}
	},
	{#State 225
		DEFAULT => -224
	},
	{#State 226
		ACTIONS => {
			'SHORT_TOKEN' => 22,
			'INTEGER_LITERAL' => 53,
			'LONG_TOKEN' => 26,
			'VOID_TOKEN' => 54,
			'BYTE_TOKEN' => 27,
			'MINUS_OPR' => 30,
			'TRUE_TOKEN' => 58,
			'DOUBLE_TOKEN' => 57,
			'INT_TOKEN' => 59,
			'FALSE_TOKEN' => 32,
			'NULL_TOKEN' => 62,
			'POSTFIX_OPR' => 64,
			'LP_TOKEN' => 65,
			'FLOAT_LITERAL' => 36,
			'CHAR_TOKEN' => 38,
			'IDENTIFIER' => 90,
			'PLUS_OPR' => 41,
			'THIS_TOKEN' => 67,
			'BOOLEAN_TOKEN' => 69,
			'CHAR_LITERAL' => 43,
			'PREFIX_OPR' => 45,
			'FLOAT_TOKEN' => 47,
			'STRING_LITERAL' => 74,
			'NEW_TOKEN' => 73,
			'SUPER_TOKEN' => 76
		},
		GOTOS => {
			'AdditiveOpr' => 50,
			'CastExpression' => 21,
			'UnaryExpressionNotPlusMinus' => 23,
			'RelationalExpression' => 24,
			'InstanceOfExpression' => 25,
			'MultiplicativeExpression' => 28,
			'EqualityExpression' => 56,
			'ParExpression' => 61,
			'Primary' => 33,
			'ExclusiveOrExpression' => 34,
			'InclusiveOrExpression' => 35,
			'ConditionalOrExpression' => 63,
			'AllocationExpression' => 37,
			'Expression' => 258,
			'BasicType' => 40,
			'Literal' => 66,
			'UnaryOpr' => 42,
			'ConditionalAndExpression' => 70,
			'PrimaryExpression' => 44,
			'ShiftExpression' => 71,
			'UnaryExpression' => 48,
			'ConditionalExpression' => 113,
			'AdditiveExpression' => 75,
			'AndExpression' => 49,
			'PrimaryPrefix' => 77
		}
	},
	{#State 227
		DEFAULT => -104
	},
	{#State 228
		ACTIONS => {
			'SHORT_TOKEN' => 22,
			'INTEGER_LITERAL' => 53,
			'LONG_TOKEN' => 26,
			'VOID_TOKEN' => 54,
			'BYTE_TOKEN' => 27,
			'MINUS_OPR' => 30,
			'TRUE_TOKEN' => 58,
			'DOUBLE_TOKEN' => 57,
			'INT_TOKEN' => 59,
			'FALSE_TOKEN' => 32,
			'NULL_TOKEN' => 62,
			'POSTFIX_OPR' => 64,
			'LP_TOKEN' => 65,
			'FLOAT_LITERAL' => 36,
			'CHAR_TOKEN' => 38,
			'IDENTIFIER' => 90,
			'PLUS_OPR' => 41,
			'THIS_TOKEN' => 67,
			'BOOLEAN_TOKEN' => 69,
			'CHAR_LITERAL' => 43,
			'PREFIX_OPR' => 45,
			'FLOAT_TOKEN' => 47,
			'STRING_LITERAL' => 74,
			'NEW_TOKEN' => 73,
			'SUPER_TOKEN' => 76
		},
		GOTOS => {
			'AdditiveOpr' => 50,
			'CastExpression' => 21,
			'UnaryExpressionNotPlusMinus' => 23,
			'RelationalExpression' => 24,
			'InstanceOfExpression' => 25,
			'MultiplicativeExpression' => 28,
			'EqualityExpression' => 56,
			'ParExpression' => 61,
			'Primary' => 33,
			'ExclusiveOrExpression' => 34,
			'InclusiveOrExpression' => 35,
			'ConditionalOrExpression' => 63,
			'AllocationExpression' => 37,
			'Expression' => 259,
			'BasicType' => 40,
			'Literal' => 66,
			'UnaryOpr' => 42,
			'ConditionalAndExpression' => 70,
			'PrimaryExpression' => 44,
			'ShiftExpression' => 71,
			'UnaryExpression' => 48,
			'ConditionalExpression' => 113,
			'AdditiveExpression' => 75,
			'AndExpression' => 49,
			'PrimaryPrefix' => 77
		}
	},
	{#State 229
		DEFAULT => -59
	},
	{#State 230
		DEFAULT => -9
	},
	{#State 231
		DEFAULT => -60
	},
	{#State 232
		ACTIONS => {
			'GT_OPR' => 188
		}
	},
	{#State 233
		DEFAULT => -42
	},
	{#State 234
		DEFAULT => -242
	},
	{#State 235
		DEFAULT => -238
	},
	{#State 236
		DEFAULT => -271,
		GOTOS => {
			'@4-2' => 260
		}
	},
	{#State 237
		DEFAULT => -254,
		GOTOS => {
			'@2-2' => 261
		}
	},
	{#State 238
		DEFAULT => -288,
		GOTOS => {
			'@8-2' => 262
		}
	},
	{#State 239
		ACTIONS => {
			'ASSERT_TOKEN' => 272,
			'FINAL_TOKEN' => 126,
			'SHORT_TOKEN' => 22,
			'LONG_TOKEN' => 26,
			'BYTE_TOKEN' => 27,
			'MINUS_OPR' => 30,
			'SMC_TOKEN' => 78,
			'NATIVE_TOKEN' => 129,
			'DO_TOKEN' => 264,
			'FALSE_TOKEN' => 32,
			'WHILE_TOKEN' => 274,
			'STRICTFP_TOKEN' => 130,
			'FLOAT_LITERAL' => 36,
			'CHAR_TOKEN' => 38,
			'IDENTIFIER' => 277,
			'PLUS_OPR' => 41,
			'RCB_TOKEN' => 151,
			'ABSTRACT_TOKEN' => 132,
			'FOR_TOKEN' => 266,
			'CHAR_LITERAL' => 43,
			'PUBLIC_TOKEN' => 133,
			'SWITCH_TOKEN' => 268,
			'PREFIX_OPR' => 45,
			'FLOAT_TOKEN' => 47,
			'SYNCHRONIZED_TOKEN' => 269,
			'VOLATILE_TOKEN' => 136,
			'PROTECTED_TOKEN' => 137,
			'RETURN_TOKEN' => 270,
			'INTEGER_LITERAL' => 53,
			'THROW_TOKEN' => 279,
			'VOID_TOKEN' => 54,
			'LCB_TOKEN' => 55,
			'TRUE_TOKEN' => 58,
			'LINE_DECL_TOKEN' => 216,
			'DOUBLE_TOKEN' => 57,
			'INT_TOKEN' => 59,
			'CONTINUE_TOKEN' => 280,
			'NULL_TOKEN' => 62,
			'LP_TOKEN' => 65,
			'POSTFIX_OPR' => 64,
			'IF_TOKEN' => 285,
			'BREAK_TOKEN' => 283,
			'TRY_TOKEN' => 286,
			'THIS_TOKEN' => 67,
			'BOOLEAN_TOKEN' => 69,
			'PRIVATE_TOKEN' => 140,
			'STATIC_TOKEN' => 142,
			'TRANSIENT_TOKEN' => 143,
			'ATMARK_TOKEN' => 2,
			'NEW_TOKEN' => 73,
			'STRING_LITERAL' => 74,
			'SUPER_TOKEN' => 76
		},
		DEFAULT => -205,
		GOTOS => {
			'CastExpression' => 21,
			'UnaryExpressionNotPlusMinus' => 23,
			'StatementExpression' => 273,
			'RelationalExpression' => 24,
			'ClassOrInterfaceDeclaration' => 263,
			'InstanceOfExpression' => 25,
			'MultiplicativeExpression' => 28,
			'LcbToken' => 239,
			'Primary' => 275,
			'ExclusiveOrExpression' => 34,
			'InclusiveOrExpression' => 35,
			'Modifiers' => 265,
			'BlockStatement' => 276,
			'AllocationExpression' => 37,
			'BasicType' => 40,
			'UnaryOpr' => 42,
			'RcbToken' => 267,
			'PrimaryExpression' => 44,
			'ModifiersOrEmpty' => 134,
			'UnaryExpression' => 48,
			'ConditionalExpression' => 113,
			'AndExpression' => 49,
			'AdditiveOpr' => 50,
			'Block' => 278,
			'EqualityExpression' => 56,
			'ParExpression' => 61,
			'BlockStatements' => 281,
			'Statement' => 282,
			'ConditionalOrExpression' => 63,
			'Expression' => 284,
			'Literal' => 66,
			'LineDecl' => 271,
			'SmcToken' => 287,
			'ConditionalAndExpression' => 70,
			'LocalVariableDeclarationStatement' => 288,
			'Modifier' => 141,
			'ShiftExpression' => 71,
			'Annotation' => 145,
			'AdditiveExpression' => 75,
			'PrimaryPrefix' => 77
		}
	},
	{#State 240
		DEFAULT => -312
	},
	{#State 241
		DEFAULT => -309
	},
	{#State 242
		DEFAULT => -300
	},
	{#State 243
		ACTIONS => {
			'IDENTIFIER' => 290
		},
		GOTOS => {
			'VariableDeclarators' => 289,
			'VariableDeclarator' => 291
		}
	},
	{#State 244
		DEFAULT => -322
	},
	{#State 245
		DEFAULT => -318
	},
	{#State 246
		ACTIONS => {
			'LP_TOKEN' => 293
		},
		DEFAULT => -285,
		GOTOS => {
			'ConstructorDeclaratorRest' => 292,
			'FormalParameters' => 294
		}
	},
	{#State 247
		ACTIONS => {
			'CHAR_TOKEN' => 38,
			'IDENTIFIER' => 297,
			'SHORT_TOKEN' => 22,
			'LONG_TOKEN' => 26,
			'VOID_TOKEN' => 295,
			'BYTE_TOKEN' => 27,
			'BOOLEAN_TOKEN' => 69,
			'DOUBLE_TOKEN' => 57,
			'INT_TOKEN' => 59,
			'FLOAT_TOKEN' => 47
		},
		GOTOS => {
			'BasicType' => 148,
			'Type' => 296,
			'QualifiedIdentifier' => 146,
			'GenericMethodOrConstructorRest' => 298
		}
	},
	{#State 248
		DEFAULT => -313
	},
	{#State 249
		DEFAULT => -321
	},
	{#State 250
		DEFAULT => -317
	},
	{#State 251
		ACTIONS => {
			'IDENTIFIER' => 299
		}
	},
	{#State 252
		DEFAULT => -316
	},
	{#State 253
		ACTIONS => {
			'IDENTIFIER' => 302
		},
		GOTOS => {
			'TypeParameter' => 301,
			'TypeParametersList' => 300
		}
	},
	{#State 254
		ACTIONS => {
			'SMC_TOKEN' => 303
		}
	},
	{#State 255
		ACTIONS => {
			'SHORT_TOKEN' => 22,
			'INTEGER_LITERAL' => 53,
			'LONG_TOKEN' => 26,
			'VOID_TOKEN' => 54,
			'BYTE_TOKEN' => 27,
			'MINUS_OPR' => 30,
			'LCB_TOKEN' => 55,
			'TRUE_TOKEN' => 58,
			'DOUBLE_TOKEN' => 57,
			'INT_TOKEN' => 59,
			'FALSE_TOKEN' => 32,
			'NULL_TOKEN' => 62,
			'FLOAT_LITERAL' => 36,
			'POSTFIX_OPR' => 64,
			'LP_TOKEN' => 65,
			'IDENTIFIER' => 90,
			'CHAR_TOKEN' => 38,
			'PLUS_OPR' => 41,
			'THIS_TOKEN' => 67,
			'BOOLEAN_TOKEN' => 69,
			'CHAR_LITERAL' => 43,
			'PREFIX_OPR' => 45,
			'FLOAT_TOKEN' => 47,
			'NEW_TOKEN' => 73,
			'STRING_LITERAL' => 74,
			'SUPER_TOKEN' => 76
		},
		DEFAULT => -227,
		GOTOS => {
			'AdditiveOpr' => 50,
			'CastExpression' => 21,
			'UnaryExpressionNotPlusMinus' => 23,
			'RelationalExpression' => 24,
			'InstanceOfExpression' => 25,
			'MultiplicativeExpression' => 28,
			'EqualityExpression' => 56,
			'LcbToken' => 166,
			'ArrayInitializer' => 221,
			'ParExpression' => 61,
			'Primary' => 33,
			'ExclusiveOrExpression' => 34,
			'InclusiveOrExpression' => 35,
			'ConditionalOrExpression' => 63,
			'AllocationExpression' => 37,
			'Expression' => 224,
			'BasicType' => 40,
			'Literal' => 66,
			'UnaryOpr' => 42,
			'VariableInitializer' => 304,
			'ConditionalAndExpression' => 70,
			'PrimaryExpression' => 44,
			'ShiftExpression' => 71,
			'UnaryExpression' => 48,
			'ConditionalExpression' => 113,
			'AdditiveExpression' => 75,
			'AndExpression' => 49,
			'PrimaryPrefix' => 77
		}
	},
	{#State 256
		DEFAULT => -223
	},
	{#State 257
		DEFAULT => -219
	},
	{#State 258
		ACTIONS => {
			'EQUAL_OPR' => 182,
			'ASSIGN_P_OPR' => 180,
			'ASSIGN_OPR' => 184
		},
		DEFAULT => -11,
		GOTOS => {
			'AssignmentOperator' => 181
		}
	},
	{#State 259
		ACTIONS => {
			'ASSIGN_P_OPR' => 180,
			'EQUAL_OPR' => 182,
			'ASSIGN_OPR' => 184
		},
		DEFAULT => -18,
		GOTOS => {
			'AssignmentOperator' => 181
		}
	},
	{#State 260
		ACTIONS => {
			'IMPLEMENTS_TOKEN' => 305
		},
		DEFAULT => -259,
		GOTOS => {
			'ImplementsListOrEmpty' => 306
		}
	},
	{#State 261
		ACTIONS => {
			'LT_OPR' => 253
		},
		DEFAULT => -265,
		GOTOS => {
			'TypeParametersOrEmpty' => 307,
			'TypeParameters' => 308
		}
	},
	{#State 262
		ACTIONS => {
			'LT_OPR' => 253
		},
		DEFAULT => -265,
		GOTOS => {
			'TypeParametersOrEmpty' => 309,
			'TypeParameters' => 308
		}
	},
	{#State 263
		DEFAULT => -113
	},
	{#State 264
		ACTIONS => {
			'ASSERT_TOKEN' => 272,
			'SHORT_TOKEN' => 22,
			'LONG_TOKEN' => 26,
			'BYTE_TOKEN' => 27,
			'MINUS_OPR' => 30,
			'SMC_TOKEN' => 78,
			'DO_TOKEN' => 264,
			'FALSE_TOKEN' => 32,
			'WHILE_TOKEN' => 274,
			'FLOAT_LITERAL' => 36,
			'IDENTIFIER' => 277,
			'CHAR_TOKEN' => 38,
			'PLUS_OPR' => 41,
			'FOR_TOKEN' => 266,
			'CHAR_LITERAL' => 43,
			'SWITCH_TOKEN' => 268,
			'PREFIX_OPR' => 45,
			'FLOAT_TOKEN' => 47,
			'SYNCHRONIZED_TOKEN' => 310,
			'RETURN_TOKEN' => 270,
			'INTEGER_LITERAL' => 53,
			'VOID_TOKEN' => 54,
			'THROW_TOKEN' => 279,
			'LCB_TOKEN' => 55,
			'DOUBLE_TOKEN' => 57,
			'TRUE_TOKEN' => 58,
			'INT_TOKEN' => 59,
			'CONTINUE_TOKEN' => 280,
			'NULL_TOKEN' => 62,
			'LP_TOKEN' => 65,
			'POSTFIX_OPR' => 64,
			'IF_TOKEN' => 285,
			'BREAK_TOKEN' => 283,
			'TRY_TOKEN' => 286,
			'THIS_TOKEN' => 67,
			'BOOLEAN_TOKEN' => 69,
			'NEW_TOKEN' => 73,
			'STRING_LITERAL' => 74,
			'SUPER_TOKEN' => 76
		},
		GOTOS => {
			'AdditiveOpr' => 50,
			'CastExpression' => 21,
			'Block' => 278,
			'UnaryExpressionNotPlusMinus' => 23,
			'StatementExpression' => 273,
			'RelationalExpression' => 24,
			'InstanceOfExpression' => 25,
			'MultiplicativeExpression' => 28,
			'EqualityExpression' => 56,
			'LcbToken' => 239,
			'ParExpression' => 61,
			'Primary' => 33,
			'ExclusiveOrExpression' => 34,
			'Statement' => 311,
			'InclusiveOrExpression' => 35,
			'ConditionalOrExpression' => 63,
			'AllocationExpression' => 37,
			'Expression' => 284,
			'BasicType' => 40,
			'Literal' => 66,
			'UnaryOpr' => 42,
			'SmcToken' => 287,
			'ConditionalAndExpression' => 70,
			'PrimaryExpression' => 44,
			'ShiftExpression' => 71,
			'UnaryExpression' => 48,
			'ConditionalExpression' => 113,
			'AdditiveExpression' => 75,
			'AndExpression' => 49,
			'PrimaryPrefix' => 77
		}
	},
	{#State 265
		ACTIONS => {
			'VOLATILE_TOKEN' => 136,
			'FINAL_TOKEN' => 126,
			'SHORT_TOKEN' => 22,
			'PROTECTED_TOKEN' => 137,
			'LONG_TOKEN' => 26,
			'BYTE_TOKEN' => 27,
			'DOUBLE_TOKEN' => 57,
			'INT_TOKEN' => 59,
			'NATIVE_TOKEN' => 129,
			'STRICTFP_TOKEN' => 130,
			'IDENTIFIER' => 7,
			'CHAR_TOKEN' => 38,
			'ABSTRACT_TOKEN' => 132,
			'BOOLEAN_TOKEN' => 69,
			'PUBLIC_TOKEN' => 133,
			'PRIVATE_TOKEN' => 140,
			'STATIC_TOKEN' => 142,
			'TRANSIENT_TOKEN' => 143,
			'ATMARK_TOKEN' => 2,
			'FLOAT_TOKEN' => 47,
			'SYNCHRONIZED_TOKEN' => 135
		},
		DEFAULT => -206,
		GOTOS => {
			'Modifier' => 193,
			'BasicType' => 148,
			'Type' => 312,
			'Annotation' => 145,
			'QualifiedIdentifier' => 146
		}
	},
	{#State 266
		ACTIONS => {
			'LP_TOKEN' => 313
		}
	},
	{#State 267
		DEFAULT => -108
	},
	{#State 268
		ACTIONS => {
			'LP_TOKEN' => 315
		},
		GOTOS => {
			'ParExpression' => 314
		}
	},
	{#State 269
		ACTIONS => {
			'LP_TOKEN' => 315
		},
		DEFAULT => -199,
		GOTOS => {
			'ParExpression' => 316
		}
	},
	{#State 270
		ACTIONS => {
			'SHORT_TOKEN' => 22,
			'INTEGER_LITERAL' => 53,
			'LONG_TOKEN' => 26,
			'VOID_TOKEN' => 54,
			'BYTE_TOKEN' => 27,
			'MINUS_OPR' => 30,
			'SMC_TOKEN' => 78,
			'TRUE_TOKEN' => 58,
			'DOUBLE_TOKEN' => 57,
			'INT_TOKEN' => 59,
			'FALSE_TOKEN' => 32,
			'NULL_TOKEN' => 62,
			'FLOAT_LITERAL' => 36,
			'POSTFIX_OPR' => 64,
			'LP_TOKEN' => 65,
			'IDENTIFIER' => 90,
			'CHAR_TOKEN' => 38,
			'PLUS_OPR' => 41,
			'THIS_TOKEN' => 67,
			'BOOLEAN_TOKEN' => 69,
			'CHAR_LITERAL' => 43,
			'PREFIX_OPR' => 45,
			'FLOAT_TOKEN' => 47,
			'NEW_TOKEN' => 73,
			'STRING_LITERAL' => 74,
			'SUPER_TOKEN' => 76
		},
		GOTOS => {
			'AdditiveOpr' => 50,
			'CastExpression' => 21,
			'UnaryExpressionNotPlusMinus' => 23,
			'RelationalExpression' => 24,
			'InstanceOfExpression' => 25,
			'MultiplicativeExpression' => 28,
			'EqualityExpression' => 56,
			'ParExpression' => 61,
			'Primary' => 33,
			'ExclusiveOrExpression' => 34,
			'InclusiveOrExpression' => 35,
			'ConditionalOrExpression' => 63,
			'AllocationExpression' => 37,
			'Expression' => 317,
			'BasicType' => 40,
			'Literal' => 66,
			'UnaryOpr' => 42,
			'SmcToken' => 318,
			'ConditionalAndExpression' => 70,
			'PrimaryExpression' => 44,
			'ShiftExpression' => 71,
			'UnaryExpression' => 48,
			'ConditionalExpression' => 113,
			'AdditiveExpression' => 75,
			'AndExpression' => 49,
			'PrimaryPrefix' => 77
		}
	},
	{#State 271
		DEFAULT => -115
	},
	{#State 272
		ACTIONS => {
			'SHORT_TOKEN' => 22,
			'INTEGER_LITERAL' => 53,
			'LONG_TOKEN' => 26,
			'VOID_TOKEN' => 54,
			'BYTE_TOKEN' => 27,
			'MINUS_OPR' => 30,
			'TRUE_TOKEN' => 58,
			'DOUBLE_TOKEN' => 57,
			'INT_TOKEN' => 59,
			'FALSE_TOKEN' => 32,
			'NULL_TOKEN' => 62,
			'FLOAT_LITERAL' => 36,
			'POSTFIX_OPR' => 64,
			'LP_TOKEN' => 65,
			'IDENTIFIER' => 90,
			'CHAR_TOKEN' => 38,
			'PLUS_OPR' => 41,
			'THIS_TOKEN' => 67,
			'BOOLEAN_TOKEN' => 69,
			'CHAR_LITERAL' => 43,
			'PREFIX_OPR' => 45,
			'FLOAT_TOKEN' => 47,
			'NEW_TOKEN' => 73,
			'STRING_LITERAL' => 74,
			'SUPER_TOKEN' => 76
		},
		GOTOS => {
			'AdditiveOpr' => 50,
			'CastExpression' => 21,
			'UnaryExpressionNotPlusMinus' => 23,
			'RelationalExpression' => 24,
			'InstanceOfExpression' => 25,
			'MultiplicativeExpression' => 28,
			'EqualityExpression' => 56,
			'ParExpression' => 61,
			'Primary' => 33,
			'ExclusiveOrExpression' => 34,
			'InclusiveOrExpression' => 35,
			'ConditionalOrExpression' => 63,
			'AllocationExpression' => 37,
			'Expression' => 319,
			'BasicType' => 40,
			'Literal' => 66,
			'UnaryOpr' => 42,
			'ConditionalAndExpression' => 70,
			'PrimaryExpression' => 44,
			'ShiftExpression' => 71,
			'UnaryExpression' => 48,
			'ConditionalExpression' => 113,
			'AdditiveExpression' => 75,
			'AndExpression' => 49,
			'PrimaryPrefix' => 77
		}
	},
	{#State 273
		ACTIONS => {
			'SMC_TOKEN' => 78
		},
		GOTOS => {
			'SmcToken' => 320
		}
	},
	{#State 274
		ACTIONS => {
			'LP_TOKEN' => 315
		},
		GOTOS => {
			'ParExpression' => 321
		}
	},
	{#State 275
		ACTIONS => {
			'LSB_TOKEN' => 94,
			'LP_TOKEN' => 100,
			'DOT_TOKEN' => 96,
			'IDENTIFIER' => 323
		},
		DEFAULT => -61,
		GOTOS => {
			'VariableDeclarators' => 322,
			'ExprInDim' => 98,
			'ArrayDim' => 99,
			'VariableDeclarator' => 291,
			'Arguments' => 97,
			'PrimarySuffix' => 95
		}
	},
	{#State 276
		DEFAULT => -110
	},
	{#State 277
		ACTIONS => {
			'CLN_TOKEN' => 324
		},
		DEFAULT => -70
	},
	{#State 278
		DEFAULT => -119
	},
	{#State 279
		ACTIONS => {
			'SHORT_TOKEN' => 22,
			'INTEGER_LITERAL' => 53,
			'LONG_TOKEN' => 26,
			'VOID_TOKEN' => 54,
			'BYTE_TOKEN' => 27,
			'MINUS_OPR' => 30,
			'TRUE_TOKEN' => 58,
			'DOUBLE_TOKEN' => 57,
			'INT_TOKEN' => 59,
			'FALSE_TOKEN' => 32,
			'NULL_TOKEN' => 62,
			'FLOAT_LITERAL' => 36,
			'POSTFIX_OPR' => 64,
			'LP_TOKEN' => 65,
			'IDENTIFIER' => 90,
			'CHAR_TOKEN' => 38,
			'PLUS_OPR' => 41,
			'THIS_TOKEN' => 67,
			'BOOLEAN_TOKEN' => 69,
			'CHAR_LITERAL' => 43,
			'PREFIX_OPR' => 45,
			'FLOAT_TOKEN' => 47,
			'NEW_TOKEN' => 73,
			'STRING_LITERAL' => 74,
			'SUPER_TOKEN' => 76
		},
		GOTOS => {
			'AdditiveOpr' => 50,
			'CastExpression' => 21,
			'UnaryExpressionNotPlusMinus' => 23,
			'RelationalExpression' => 24,
			'InstanceOfExpression' => 25,
			'MultiplicativeExpression' => 28,
			'EqualityExpression' => 56,
			'ParExpression' => 61,
			'Primary' => 33,
			'ExclusiveOrExpression' => 34,
			'InclusiveOrExpression' => 35,
			'ConditionalOrExpression' => 63,
			'AllocationExpression' => 37,
			'Expression' => 325,
			'BasicType' => 40,
			'Literal' => 66,
			'UnaryOpr' => 42,
			'ConditionalAndExpression' => 70,
			'PrimaryExpression' => 44,
			'ShiftExpression' => 71,
			'UnaryExpression' => 48,
			'ConditionalExpression' => 113,
			'AdditiveExpression' => 75,
			'AndExpression' => 49,
			'PrimaryPrefix' => 77
		}
	},
	{#State 280
		ACTIONS => {
			'IDENTIFIER' => 326,
			'SMC_TOKEN' => 78
		},
		GOTOS => {
			'SmcToken' => 327
		}
	},
	{#State 281
		ACTIONS => {
			'ASSERT_TOKEN' => 272,
			'FINAL_TOKEN' => 126,
			'SHORT_TOKEN' => 22,
			'LONG_TOKEN' => 26,
			'BYTE_TOKEN' => 27,
			'MINUS_OPR' => 30,
			'SMC_TOKEN' => 78,
			'NATIVE_TOKEN' => 129,
			'DO_TOKEN' => 264,
			'FALSE_TOKEN' => 32,
			'WHILE_TOKEN' => 274,
			'STRICTFP_TOKEN' => 130,
			'FLOAT_LITERAL' => 36,
			'IDENTIFIER' => 277,
			'CHAR_TOKEN' => 38,
			'PLUS_OPR' => 41,
			'RCB_TOKEN' => 151,
			'ABSTRACT_TOKEN' => 132,
			'FOR_TOKEN' => 266,
			'CHAR_LITERAL' => 43,
			'PUBLIC_TOKEN' => 133,
			'SWITCH_TOKEN' => 268,
			'PREFIX_OPR' => 45,
			'FLOAT_TOKEN' => 47,
			'SYNCHRONIZED_TOKEN' => 269,
			'VOLATILE_TOKEN' => 136,
			'PROTECTED_TOKEN' => 137,
			'RETURN_TOKEN' => 270,
			'INTEGER_LITERAL' => 53,
			'THROW_TOKEN' => 279,
			'VOID_TOKEN' => 54,
			'LCB_TOKEN' => 55,
			'TRUE_TOKEN' => 58,
			'LINE_DECL_TOKEN' => 216,
			'DOUBLE_TOKEN' => 57,
			'INT_TOKEN' => 59,
			'CONTINUE_TOKEN' => 280,
			'NULL_TOKEN' => 62,
			'LP_TOKEN' => 65,
			'POSTFIX_OPR' => 64,
			'IF_TOKEN' => 285,
			'BREAK_TOKEN' => 283,
			'TRY_TOKEN' => 286,
			'THIS_TOKEN' => 67,
			'BOOLEAN_TOKEN' => 69,
			'PRIVATE_TOKEN' => 140,
			'STATIC_TOKEN' => 142,
			'TRANSIENT_TOKEN' => 143,
			'ATMARK_TOKEN' => 2,
			'NEW_TOKEN' => 73,
			'STRING_LITERAL' => 74,
			'SUPER_TOKEN' => 76
		},
		DEFAULT => -205,
		GOTOS => {
			'CastExpression' => 21,
			'UnaryExpressionNotPlusMinus' => 23,
			'StatementExpression' => 273,
			'RelationalExpression' => 24,
			'ClassOrInterfaceDeclaration' => 263,
			'InstanceOfExpression' => 25,
			'MultiplicativeExpression' => 28,
			'LcbToken' => 239,
			'Primary' => 275,
			'ExclusiveOrExpression' => 34,
			'InclusiveOrExpression' => 35,
			'Modifiers' => 265,
			'BlockStatement' => 329,
			'AllocationExpression' => 37,
			'BasicType' => 40,
			'UnaryOpr' => 42,
			'RcbToken' => 328,
			'PrimaryExpression' => 44,
			'ModifiersOrEmpty' => 134,
			'UnaryExpression' => 48,
			'ConditionalExpression' => 113,
			'AndExpression' => 49,
			'AdditiveOpr' => 50,
			'Block' => 278,
			'EqualityExpression' => 56,
			'ParExpression' => 61,
			'Statement' => 282,
			'ConditionalOrExpression' => 63,
			'Expression' => 284,
			'Literal' => 66,
			'LineDecl' => 271,
			'SmcToken' => 287,
			'ConditionalAndExpression' => 70,
			'LocalVariableDeclarationStatement' => 288,
			'Modifier' => 141,
			'ShiftExpression' => 71,
			'Annotation' => 145,
			'AdditiveExpression' => 75,
			'PrimaryPrefix' => 77
		}
	},
	{#State 282
		DEFAULT => -114
	},
	{#State 283
		ACTIONS => {
			'IDENTIFIER' => 330,
			'SMC_TOKEN' => 78
		},
		GOTOS => {
			'SmcToken' => 331
		}
	},
	{#State 284
		ACTIONS => {
			'EQUAL_OPR' => 182,
			'ASSIGN_P_OPR' => 180,
			'ASSIGN_OPR' => 184
		},
		DEFAULT => -94,
		GOTOS => {
			'AssignmentOperator' => 181
		}
	},
	{#State 285
		ACTIONS => {
			'LP_TOKEN' => 315
		},
		GOTOS => {
			'ParExpression' => 332
		}
	},
	{#State 286
		ACTIONS => {
			'LCB_TOKEN' => 55
		},
		GOTOS => {
			'Block' => 333,
			'LcbToken' => 239
		}
	},
	{#State 287
		DEFAULT => -135
	},
	{#State 288
		DEFAULT => -112
	},
	{#State 289
		ACTIONS => {
			'CM_TOKEN' => 334,
			'SMC_TOKEN' => 78
		},
		GOTOS => {
			'SmcToken' => 335
		}
	},
	{#State 290
		ACTIONS => {
			'EQUAL_OPR' => 338,
			'LSB_TOKEN' => 205,
			'LP_TOKEN' => 293
		},
		DEFAULT => -211,
		GOTOS => {
			'ArrayDim' => 339,
			'FormalParameters' => 340,
			'MethodDeclaratorRest' => 337,
			'VariableDeclaratorRest' => 336
		}
	},
	{#State 291
		DEFAULT => -207
	},
	{#State 292
		DEFAULT => -320
	},
	{#State 293
		ACTIONS => {
			'VOLATILE_TOKEN' => 136,
			'FINAL_TOKEN' => 126,
			'PROTECTED_TOKEN' => 137,
			'RP_TOKEN' => 344,
			'NATIVE_TOKEN' => 129,
			'STRICTFP_TOKEN' => 130,
			'ABSTRACT_TOKEN' => 132,
			'PUBLIC_TOKEN' => 133,
			'PRIVATE_TOKEN' => 140,
			'STATIC_TOKEN' => 142,
			'ATMARK_TOKEN' => 2,
			'TRANSIENT_TOKEN' => 143,
			'SYNCHRONIZED_TOKEN' => 135
		},
		DEFAULT => -205,
		GOTOS => {
			'Modifier' => 141,
			'FormalParameterDeclsList' => 342,
			'Annotation' => 145,
			'ModifiersOrEmpty' => 343,
			'Modifiers' => 131,
			'FormalParameterDecls' => 341
		}
	},
	{#State 294
		ACTIONS => {
			'THROWS_TOKEN' => 346
		},
		DEFAULT => -349,
		GOTOS => {
			'ThrowsQIdentOrEmpty' => 345
		}
	},
	{#State 295
		ACTIONS => {
			'IDENTIFIER' => 347
		}
	},
	{#State 296
		ACTIONS => {
			'IDENTIFIER' => 348
		}
	},
	{#State 297
		ACTIONS => {
			'LP_TOKEN' => 293
		},
		DEFAULT => -285,
		GOTOS => {
			'ConstructorDeclaratorRest' => 349,
			'FormalParameters' => 294
		}
	},
	{#State 298
		DEFAULT => -325
	},
	{#State 299
		ACTIONS => {
			'LP_TOKEN' => 293
		},
		GOTOS => {
			'FormalParameters' => 351,
			'VoidMethodDeclaratorRest' => 350
		}
	},
	{#State 300
		ACTIONS => {
			'CM_TOKEN' => 352,
			'GT_OPR' => 353
		}
	},
	{#State 301
		DEFAULT => -263
	},
	{#State 302
		ACTIONS => {
			'EXTENDS_TOKEN' => 354
		},
		DEFAULT => -267
	},
	{#State 303
		DEFAULT => -116
	},
	{#State 304
		DEFAULT => -225
	},
	{#State 305
		ACTIONS => {
			'CHAR_TOKEN' => 38,
			'IDENTIFIER' => 7,
			'SHORT_TOKEN' => 22,
			'LONG_TOKEN' => 26,
			'BYTE_TOKEN' => 27,
			'BOOLEAN_TOKEN' => 69,
			'DOUBLE_TOKEN' => 57,
			'INT_TOKEN' => 59,
			'FLOAT_TOKEN' => 47
		},
		GOTOS => {
			'TypeList' => 355,
			'BasicType' => 148,
			'Type' => 356,
			'QualifiedIdentifier' => 146
		}
	},
	{#State 306
		ACTIONS => {
			'LCB_TOKEN' => 55
		},
		GOTOS => {
			'LcbToken' => 358,
			'EnumBody' => 357
		}
	},
	{#State 307
		ACTIONS => {
			'EXTENDS_TOKEN' => 359
		},
		DEFAULT => -257,
		GOTOS => {
			'ExtendsTypeOrEmpty' => 360
		}
	},
	{#State 308
		DEFAULT => -266
	},
	{#State 309
		ACTIONS => {
			'EXTENDS_TOKEN' => 361
		},
		DEFAULT => -293,
		GOTOS => {
			'ExtendsTypeListOrEmpty' => 362
		}
	},
	{#State 310
		ACTIONS => {
			'LP_TOKEN' => 315
		},
		GOTOS => {
			'ParExpression' => 316
		}
	},
	{#State 311
		ACTIONS => {
			'WHILE_TOKEN' => 363
		}
	},
	{#State 312
		ACTIONS => {
			'IDENTIFIER' => 323
		},
		GOTOS => {
			'VariableDeclarators' => 364,
			'VariableDeclarator' => 291
		}
	},
	{#State 313
		ACTIONS => {
			'FINAL_TOKEN' => 126,
			'SHORT_TOKEN' => 22,
			'LONG_TOKEN' => 26,
			'BYTE_TOKEN' => 27,
			'MINUS_OPR' => 30,
			'NATIVE_TOKEN' => 129,
			'FALSE_TOKEN' => 32,
			'STRICTFP_TOKEN' => 130,
			'FLOAT_LITERAL' => 36,
			'IDENTIFIER' => 90,
			'CHAR_TOKEN' => 38,
			'PLUS_OPR' => 41,
			'ABSTRACT_TOKEN' => 132,
			'CHAR_LITERAL' => 43,
			'PUBLIC_TOKEN' => 133,
			'PREFIX_OPR' => 45,
			'FLOAT_TOKEN' => 47,
			'SYNCHRONIZED_TOKEN' => 135,
			'VOLATILE_TOKEN' => 136,
			'INTEGER_LITERAL' => 53,
			'PROTECTED_TOKEN' => 137,
			'VOID_TOKEN' => 54,
			'TRUE_TOKEN' => 58,
			'DOUBLE_TOKEN' => 57,
			'INT_TOKEN' => 59,
			'NULL_TOKEN' => 62,
			'LP_TOKEN' => 65,
			'POSTFIX_OPR' => 64,
			'THIS_TOKEN' => 67,
			'BOOLEAN_TOKEN' => 69,
			'PRIVATE_TOKEN' => 140,
			'STATIC_TOKEN' => 142,
			'TRANSIENT_TOKEN' => 143,
			'ATMARK_TOKEN' => 2,
			'NEW_TOKEN' => 73,
			'STRING_LITERAL' => 74,
			'SUPER_TOKEN' => 76
		},
		DEFAULT => -162,
		GOTOS => {
			'CastExpression' => 21,
			'UnaryExpressionNotPlusMinus' => 23,
			'StatementExpression' => 367,
			'RelationalExpression' => 24,
			'InstanceOfExpression' => 25,
			'MultiplicativeExpression' => 28,
			'ForInitOrEmpty' => 368,
			'Primary' => 369,
			'ExclusiveOrExpression' => 34,
			'InclusiveOrExpression' => 35,
			'Modifiers' => 365,
			'AllocationExpression' => 37,
			'BasicType' => 40,
			'UnaryOpr' => 42,
			'ForInit' => 370,
			'PrimaryExpression' => 44,
			'UnaryExpression' => 48,
			'ConditionalExpression' => 113,
			'AndExpression' => 49,
			'AdditiveOpr' => 50,
			'ForVarControl' => 366,
			'EqualityExpression' => 56,
			'ParExpression' => 61,
			'ForControl' => 371,
			'ConditionalOrExpression' => 63,
			'Expression' => 284,
			'Literal' => 66,
			'ConditionalAndExpression' => 70,
			'Modifier' => 141,
			'ShiftExpression' => 71,
			'Annotation' => 145,
			'AdditiveExpression' => 75,
			'PrimaryPrefix' => 77
		}
	},
	{#State 314
		ACTIONS => {
			'LCB_TOKEN' => 55
		},
		GOTOS => {
			'LcbToken' => 372
		}
	},
	{#State 315
		ACTIONS => {
			'SHORT_TOKEN' => 22,
			'INTEGER_LITERAL' => 53,
			'LONG_TOKEN' => 26,
			'VOID_TOKEN' => 54,
			'BYTE_TOKEN' => 27,
			'MINUS_OPR' => 30,
			'TRUE_TOKEN' => 58,
			'DOUBLE_TOKEN' => 57,
			'INT_TOKEN' => 59,
			'FALSE_TOKEN' => 32,
			'NULL_TOKEN' => 62,
			'FLOAT_LITERAL' => 36,
			'POSTFIX_OPR' => 64,
			'LP_TOKEN' => 65,
			'IDENTIFIER' => 90,
			'CHAR_TOKEN' => 38,
			'PLUS_OPR' => 41,
			'THIS_TOKEN' => 67,
			'BOOLEAN_TOKEN' => 69,
			'CHAR_LITERAL' => 43,
			'PREFIX_OPR' => 45,
			'FLOAT_TOKEN' => 47,
			'NEW_TOKEN' => 73,
			'STRING_LITERAL' => 74,
			'SUPER_TOKEN' => 76
		},
		GOTOS => {
			'AdditiveOpr' => 50,
			'CastExpression' => 21,
			'UnaryExpressionNotPlusMinus' => 23,
			'RelationalExpression' => 24,
			'InstanceOfExpression' => 25,
			'MultiplicativeExpression' => 28,
			'EqualityExpression' => 56,
			'ParExpression' => 61,
			'Primary' => 33,
			'ExclusiveOrExpression' => 34,
			'InclusiveOrExpression' => 35,
			'ConditionalOrExpression' => 63,
			'AllocationExpression' => 37,
			'Expression' => 373,
			'BasicType' => 40,
			'Literal' => 66,
			'UnaryOpr' => 42,
			'ConditionalAndExpression' => 70,
			'PrimaryExpression' => 44,
			'ShiftExpression' => 71,
			'UnaryExpression' => 48,
			'ConditionalExpression' => 113,
			'AdditiveExpression' => 75,
			'AndExpression' => 49,
			'PrimaryPrefix' => 77
		}
	},
	{#State 316
		ACTIONS => {
			'LCB_TOKEN' => 55
		},
		GOTOS => {
			'Block' => 374,
			'LcbToken' => 239
		}
	},
	{#State 317
		ACTIONS => {
			'EQUAL_OPR' => 182,
			'ASSIGN_P_OPR' => 180,
			'ASSIGN_OPR' => 184,
			'SMC_TOKEN' => 78
		},
		GOTOS => {
			'SmcToken' => 375,
			'AssignmentOperator' => 181
		}
	},
	{#State 318
		DEFAULT => -128
	},
	{#State 319
		ACTIONS => {
			'EQUAL_OPR' => 182,
			'ASSIGN_P_OPR' => 180,
			'CLN_TOKEN' => 376,
			'ASSIGN_OPR' => 184
		},
		DEFAULT => -138,
		GOTOS => {
			'AssertExpOrEmpty' => 377,
			'AssignmentOperator' => 181
		}
	},
	{#State 320
		DEFAULT => -136
	},
	{#State 321
		ACTIONS => {
			'ASSERT_TOKEN' => 272,
			'SHORT_TOKEN' => 22,
			'LONG_TOKEN' => 26,
			'BYTE_TOKEN' => 27,
			'MINUS_OPR' => 30,
			'SMC_TOKEN' => 78,
			'DO_TOKEN' => 264,
			'FALSE_TOKEN' => 32,
			'WHILE_TOKEN' => 274,
			'FLOAT_LITERAL' => 36,
			'IDENTIFIER' => 277,
			'CHAR_TOKEN' => 38,
			'PLUS_OPR' => 41,
			'FOR_TOKEN' => 266,
			'CHAR_LITERAL' => 43,
			'SWITCH_TOKEN' => 268,
			'PREFIX_OPR' => 45,
			'FLOAT_TOKEN' => 47,
			'SYNCHRONIZED_TOKEN' => 310,
			'RETURN_TOKEN' => 270,
			'INTEGER_LITERAL' => 53,
			'VOID_TOKEN' => 54,
			'THROW_TOKEN' => 279,
			'LCB_TOKEN' => 55,
			'DOUBLE_TOKEN' => 57,
			'TRUE_TOKEN' => 58,
			'INT_TOKEN' => 59,
			'CONTINUE_TOKEN' => 280,
			'NULL_TOKEN' => 62,
			'LP_TOKEN' => 65,
			'POSTFIX_OPR' => 64,
			'IF_TOKEN' => 285,
			'BREAK_TOKEN' => 283,
			'TRY_TOKEN' => 286,
			'THIS_TOKEN' => 67,
			'BOOLEAN_TOKEN' => 69,
			'NEW_TOKEN' => 73,
			'STRING_LITERAL' => 74,
			'SUPER_TOKEN' => 76
		},
		GOTOS => {
			'AdditiveOpr' => 50,
			'CastExpression' => 21,
			'Block' => 278,
			'UnaryExpressionNotPlusMinus' => 23,
			'StatementExpression' => 273,
			'RelationalExpression' => 24,
			'InstanceOfExpression' => 25,
			'MultiplicativeExpression' => 28,
			'EqualityExpression' => 56,
			'LcbToken' => 239,
			'ParExpression' => 61,
			'Primary' => 33,
			'ExclusiveOrExpression' => 34,
			'Statement' => 378,
			'InclusiveOrExpression' => 35,
			'ConditionalOrExpression' => 63,
			'AllocationExpression' => 37,
			'Expression' => 284,
			'BasicType' => 40,
			'Literal' => 66,
			'UnaryOpr' => 42,
			'SmcToken' => 287,
			'ConditionalAndExpression' => 70,
			'PrimaryExpression' => 44,
			'ShiftExpression' => 71,
			'UnaryExpression' => 48,
			'ConditionalExpression' => 113,
			'AdditiveExpression' => 75,
			'AndExpression' => 49,
			'PrimaryPrefix' => 77
		}
	},
	{#State 322
		ACTIONS => {
			'CM_TOKEN' => 334,
			'SMC_TOKEN' => 78
		},
		GOTOS => {
			'SmcToken' => 379
		}
	},
	{#State 323
		ACTIONS => {
			'EQUAL_OPR' => 338,
			'LSB_TOKEN' => 205
		},
		DEFAULT => -211,
		GOTOS => {
			'ArrayDim' => 339,
			'VariableDeclaratorRest' => 336
		}
	},
	{#State 324
		ACTIONS => {
			'ASSERT_TOKEN' => 272,
			'SHORT_TOKEN' => 22,
			'LONG_TOKEN' => 26,
			'BYTE_TOKEN' => 27,
			'MINUS_OPR' => 30,
			'SMC_TOKEN' => 78,
			'DO_TOKEN' => 264,
			'FALSE_TOKEN' => 32,
			'WHILE_TOKEN' => 274,
			'FLOAT_LITERAL' => 36,
			'IDENTIFIER' => 277,
			'CHAR_TOKEN' => 38,
			'PLUS_OPR' => 41,
			'FOR_TOKEN' => 266,
			'CHAR_LITERAL' => 43,
			'SWITCH_TOKEN' => 268,
			'PREFIX_OPR' => 45,
			'FLOAT_TOKEN' => 47,
			'SYNCHRONIZED_TOKEN' => 310,
			'RETURN_TOKEN' => 270,
			'INTEGER_LITERAL' => 53,
			'VOID_TOKEN' => 54,
			'THROW_TOKEN' => 279,
			'LCB_TOKEN' => 55,
			'DOUBLE_TOKEN' => 57,
			'TRUE_TOKEN' => 58,
			'INT_TOKEN' => 59,
			'CONTINUE_TOKEN' => 280,
			'NULL_TOKEN' => 62,
			'LP_TOKEN' => 65,
			'POSTFIX_OPR' => 64,
			'IF_TOKEN' => 285,
			'BREAK_TOKEN' => 283,
			'TRY_TOKEN' => 286,
			'THIS_TOKEN' => 67,
			'BOOLEAN_TOKEN' => 69,
			'NEW_TOKEN' => 73,
			'STRING_LITERAL' => 74,
			'SUPER_TOKEN' => 76
		},
		GOTOS => {
			'AdditiveOpr' => 50,
			'CastExpression' => 21,
			'Block' => 278,
			'UnaryExpressionNotPlusMinus' => 23,
			'StatementExpression' => 273,
			'RelationalExpression' => 24,
			'InstanceOfExpression' => 25,
			'MultiplicativeExpression' => 28,
			'EqualityExpression' => 56,
			'LcbToken' => 239,
			'ParExpression' => 61,
			'Primary' => 33,
			'ExclusiveOrExpression' => 34,
			'Statement' => 380,
			'InclusiveOrExpression' => 35,
			'ConditionalOrExpression' => 63,
			'AllocationExpression' => 37,
			'Expression' => 284,
			'BasicType' => 40,
			'Literal' => 66,
			'UnaryOpr' => 42,
			'SmcToken' => 287,
			'ConditionalAndExpression' => 70,
			'PrimaryExpression' => 44,
			'ShiftExpression' => 71,
			'UnaryExpression' => 48,
			'ConditionalExpression' => 113,
			'AdditiveExpression' => 75,
			'AndExpression' => 49,
			'PrimaryPrefix' => 77
		}
	},
	{#State 325
		ACTIONS => {
			'EQUAL_OPR' => 182,
			'ASSIGN_P_OPR' => 180,
			'ASSIGN_OPR' => 184,
			'SMC_TOKEN' => 78
		},
		GOTOS => {
			'SmcToken' => 381,
			'AssignmentOperator' => 181
		}
	},
	{#State 326
		ACTIONS => {
			'SMC_TOKEN' => 78
		},
		GOTOS => {
			'SmcToken' => 382
		}
	},
	{#State 327
		DEFAULT => -133
	},
	{#State 328
		DEFAULT => -109
	},
	{#State 329
		DEFAULT => -111
	},
	{#State 330
		ACTIONS => {
			'SMC_TOKEN' => 78
		},
		GOTOS => {
			'SmcToken' => 383
		}
	},
	{#State 331
		DEFAULT => -131
	},
	{#State 332
		ACTIONS => {
			'ASSERT_TOKEN' => 272,
			'SHORT_TOKEN' => 22,
			'LONG_TOKEN' => 26,
			'BYTE_TOKEN' => 27,
			'MINUS_OPR' => 30,
			'SMC_TOKEN' => 78,
			'DO_TOKEN' => 264,
			'FALSE_TOKEN' => 32,
			'WHILE_TOKEN' => 274,
			'FLOAT_LITERAL' => 36,
			'IDENTIFIER' => 277,
			'CHAR_TOKEN' => 38,
			'PLUS_OPR' => 41,
			'FOR_TOKEN' => 266,
			'CHAR_LITERAL' => 43,
			'SWITCH_TOKEN' => 268,
			'PREFIX_OPR' => 45,
			'FLOAT_TOKEN' => 47,
			'SYNCHRONIZED_TOKEN' => 310,
			'RETURN_TOKEN' => 270,
			'INTEGER_LITERAL' => 53,
			'VOID_TOKEN' => 54,
			'THROW_TOKEN' => 279,
			'LCB_TOKEN' => 55,
			'DOUBLE_TOKEN' => 57,
			'TRUE_TOKEN' => 58,
			'INT_TOKEN' => 59,
			'CONTINUE_TOKEN' => 280,
			'NULL_TOKEN' => 62,
			'LP_TOKEN' => 65,
			'POSTFIX_OPR' => 64,
			'IF_TOKEN' => 285,
			'BREAK_TOKEN' => 283,
			'TRY_TOKEN' => 286,
			'THIS_TOKEN' => 67,
			'BOOLEAN_TOKEN' => 69,
			'NEW_TOKEN' => 73,
			'STRING_LITERAL' => 74,
			'SUPER_TOKEN' => 76
		},
		GOTOS => {
			'AdditiveOpr' => 50,
			'CastExpression' => 21,
			'Block' => 278,
			'UnaryExpressionNotPlusMinus' => 23,
			'StatementExpression' => 273,
			'RelationalExpression' => 24,
			'InstanceOfExpression' => 25,
			'MultiplicativeExpression' => 28,
			'EqualityExpression' => 56,
			'LcbToken' => 239,
			'ParExpression' => 61,
			'Primary' => 33,
			'ExclusiveOrExpression' => 34,
			'Statement' => 384,
			'InclusiveOrExpression' => 35,
			'ConditionalOrExpression' => 63,
			'AllocationExpression' => 37,
			'Expression' => 284,
			'BasicType' => 40,
			'Literal' => 66,
			'UnaryOpr' => 42,
			'SmcToken' => 287,
			'ConditionalAndExpression' => 70,
			'PrimaryExpression' => 44,
			'ShiftExpression' => 71,
			'UnaryExpression' => 48,
			'ConditionalExpression' => 113,
			'AdditiveExpression' => 75,
			'AndExpression' => 49,
			'PrimaryPrefix' => 77
		}
	},
	{#State 333
		ACTIONS => {
			'CATCH_TOKEN' => 387
		},
		DEFAULT => -142,
		GOTOS => {
			'CatchesOrEmpty' => 385,
			'CatchesOrFinally' => 389,
			'Catches' => 388,
			'CatchClause' => 386
		}
	},
	{#State 334
		ACTIONS => {
			'IDENTIFIER' => 323
		},
		GOTOS => {
			'VariableDeclarator' => 390
		}
	},
	{#State 335
		DEFAULT => -324
	},
	{#State 336
		DEFAULT => -212
	},
	{#State 337
		DEFAULT => -323
	},
	{#State 338
		ACTIONS => {
			'SHORT_TOKEN' => 22,
			'INTEGER_LITERAL' => 53,
			'LONG_TOKEN' => 26,
			'VOID_TOKEN' => 54,
			'BYTE_TOKEN' => 27,
			'MINUS_OPR' => 30,
			'LCB_TOKEN' => 55,
			'TRUE_TOKEN' => 58,
			'DOUBLE_TOKEN' => 57,
			'INT_TOKEN' => 59,
			'FALSE_TOKEN' => 32,
			'NULL_TOKEN' => 62,
			'FLOAT_LITERAL' => 36,
			'POSTFIX_OPR' => 64,
			'LP_TOKEN' => 65,
			'IDENTIFIER' => 90,
			'CHAR_TOKEN' => 38,
			'PLUS_OPR' => 41,
			'THIS_TOKEN' => 67,
			'BOOLEAN_TOKEN' => 69,
			'CHAR_LITERAL' => 43,
			'PREFIX_OPR' => 45,
			'FLOAT_TOKEN' => 47,
			'NEW_TOKEN' => 73,
			'STRING_LITERAL' => 74,
			'SUPER_TOKEN' => 76
		},
		GOTOS => {
			'AdditiveOpr' => 50,
			'CastExpression' => 21,
			'UnaryExpressionNotPlusMinus' => 23,
			'RelationalExpression' => 24,
			'InstanceOfExpression' => 25,
			'MultiplicativeExpression' => 28,
			'EqualityExpression' => 56,
			'LcbToken' => 166,
			'ArrayInitializer' => 221,
			'ParExpression' => 61,
			'Primary' => 33,
			'ExclusiveOrExpression' => 34,
			'InclusiveOrExpression' => 35,
			'ConditionalOrExpression' => 63,
			'AllocationExpression' => 37,
			'Expression' => 224,
			'BasicType' => 40,
			'Literal' => 66,
			'UnaryOpr' => 42,
			'VariableInitializer' => 391,
			'ConditionalAndExpression' => 70,
			'PrimaryExpression' => 44,
			'ShiftExpression' => 71,
			'UnaryExpression' => 48,
			'ConditionalExpression' => 113,
			'AdditiveExpression' => 75,
			'AndExpression' => 49,
			'PrimaryPrefix' => 77
		}
	},
	{#State 339
		ACTIONS => {
			'EQUAL_OPR' => 392,
			'LSB_TOKEN' => 165
		},
		DEFAULT => -214
	},
	{#State 340
		ACTIONS => {
			'LSB_TOKEN' => 205
		},
		DEFAULT => -90,
		GOTOS => {
			'ArrayDim' => 207,
			'ArrayDimOrEmpty' => 393
		}
	},
	{#State 341
		DEFAULT => -356
	},
	{#State 342
		ACTIONS => {
			'CM_TOKEN' => 394,
			'RP_TOKEN' => 395
		}
	},
	{#State 343
		ACTIONS => {
			'CHAR_TOKEN' => 38,
			'IDENTIFIER' => 7,
			'SHORT_TOKEN' => 22,
			'LONG_TOKEN' => 26,
			'BYTE_TOKEN' => 27,
			'BOOLEAN_TOKEN' => 69,
			'DOUBLE_TOKEN' => 57,
			'INT_TOKEN' => 59,
			'FLOAT_TOKEN' => 47
		},
		GOTOS => {
			'BasicType' => 148,
			'Type' => 396,
			'QualifiedIdentifier' => 146
		}
	},
	{#State 344
		DEFAULT => -353
	},
	{#State 345
		ACTIONS => {
			'LCB_TOKEN' => 55
		},
		GOTOS => {
			'Block' => 398,
			'LcbToken' => 239,
			'MethodBody' => 397
		}
	},
	{#State 346
		ACTIONS => {
			'IDENTIFIER' => 7
		},
		GOTOS => {
			'QualifiedIdentifierList' => 399,
			'QualifiedIdentifier' => 400
		}
	},
	{#State 347
		ACTIONS => {
			'LP_TOKEN' => 293
		},
		GOTOS => {
			'FormalParameters' => 340,
			'MethodDeclaratorRest' => 401
		}
	},
	{#State 348
		ACTIONS => {
			'LP_TOKEN' => 293
		},
		GOTOS => {
			'FormalParameters' => 340,
			'MethodDeclaratorRest' => 402
		}
	},
	{#State 349
		DEFAULT => -328
	},
	{#State 350
		DEFAULT => -319
	},
	{#State 351
		ACTIONS => {
			'THROWS_TOKEN' => 346
		},
		DEFAULT => -349,
		GOTOS => {
			'ThrowsQIdentOrEmpty' => 403
		}
	},
	{#State 352
		ACTIONS => {
			'IDENTIFIER' => 302
		},
		GOTOS => {
			'TypeParameter' => 404
		}
	},
	{#State 353
		DEFAULT => -262
	},
	{#State 354
		ACTIONS => {
			'CHAR_TOKEN' => 38,
			'IDENTIFIER' => 7,
			'SHORT_TOKEN' => 22,
			'LONG_TOKEN' => 26,
			'BYTE_TOKEN' => 27,
			'BOOLEAN_TOKEN' => 69,
			'DOUBLE_TOKEN' => 57,
			'INT_TOKEN' => 59,
			'FLOAT_TOKEN' => 47
		},
		GOTOS => {
			'Bound' => 405,
			'BasicType' => 148,
			'Type' => 406,
			'QualifiedIdentifier' => 146
		}
	},
	{#State 355
		ACTIONS => {
			'CM_TOKEN' => 407
		},
		DEFAULT => -260
	},
	{#State 356
		DEFAULT => -295
	},
	{#State 357
		DEFAULT => -272,
		GOTOS => {
			'@5-5' => 408
		}
	},
	{#State 358
		ACTIONS => {
			'IDENTIFIER' => -188,
			'ATMARK_TOKEN' => 2
		},
		DEFAULT => -275,
		GOTOS => {
			'Annotation' => 3,
			'EnumConstants' => 409,
			'EnumConstant' => 412,
			'EnumConstantsOrEmpty' => 411,
			'AnnotationsOrEmpty' => 410,
			'Annotations' => 5
		}
	},
	{#State 359
		ACTIONS => {
			'CHAR_TOKEN' => 38,
			'IDENTIFIER' => 7,
			'SHORT_TOKEN' => 22,
			'LONG_TOKEN' => 26,
			'BYTE_TOKEN' => 27,
			'BOOLEAN_TOKEN' => 69,
			'DOUBLE_TOKEN' => 57,
			'INT_TOKEN' => 59,
			'FLOAT_TOKEN' => 47
		},
		GOTOS => {
			'BasicType' => 148,
			'Type' => 413,
			'QualifiedIdentifier' => 146
		}
	},
	{#State 360
		ACTIONS => {
			'IMPLEMENTS_TOKEN' => 305
		},
		DEFAULT => -259,
		GOTOS => {
			'ImplementsListOrEmpty' => 414
		}
	},
	{#State 361
		ACTIONS => {
			'CHAR_TOKEN' => 38,
			'IDENTIFIER' => 7,
			'SHORT_TOKEN' => 22,
			'LONG_TOKEN' => 26,
			'BYTE_TOKEN' => 27,
			'BOOLEAN_TOKEN' => 69,
			'DOUBLE_TOKEN' => 57,
			'INT_TOKEN' => 59,
			'FLOAT_TOKEN' => 47
		},
		GOTOS => {
			'TypeList' => 415,
			'BasicType' => 148,
			'Type' => 356,
			'QualifiedIdentifier' => 146
		}
	},
	{#State 362
		ACTIONS => {
			'LCB_TOKEN' => 55
		},
		GOTOS => {
			'LcbToken' => 417,
			'InterfaceBody' => 416
		}
	},
	{#State 363
		ACTIONS => {
			'LP_TOKEN' => 315
		},
		GOTOS => {
			'ParExpression' => 418
		}
	},
	{#State 364
		ACTIONS => {
			'CM_TOKEN' => 334,
			'SMC_TOKEN' => 78
		},
		GOTOS => {
			'SmcToken' => 419
		}
	},
	{#State 365
		ACTIONS => {
			'VOLATILE_TOKEN' => 136,
			'FINAL_TOKEN' => 126,
			'SHORT_TOKEN' => 22,
			'PROTECTED_TOKEN' => 137,
			'LONG_TOKEN' => 26,
			'BYTE_TOKEN' => 27,
			'DOUBLE_TOKEN' => 57,
			'INT_TOKEN' => 59,
			'NATIVE_TOKEN' => 129,
			'STRICTFP_TOKEN' => 130,
			'IDENTIFIER' => 7,
			'CHAR_TOKEN' => 38,
			'ABSTRACT_TOKEN' => 132,
			'BOOLEAN_TOKEN' => 69,
			'PUBLIC_TOKEN' => 133,
			'PRIVATE_TOKEN' => 140,
			'STATIC_TOKEN' => 142,
			'TRANSIENT_TOKEN' => 143,
			'ATMARK_TOKEN' => 2,
			'FLOAT_TOKEN' => 47,
			'SYNCHRONIZED_TOKEN' => 135
		},
		GOTOS => {
			'Modifier' => 193,
			'BasicType' => 148,
			'Type' => 420,
			'Annotation' => 145,
			'QualifiedIdentifier' => 146
		}
	},
	{#State 366
		DEFAULT => -160
	},
	{#State 367
		ACTIONS => {
			'CM_TOKEN' => 421
		},
		DEFAULT => -158,
		GOTOS => {
			'MoreStatementExpressions' => 422,
			'MoreStatementExpressionsOrEmpty' => 423
		}
	},
	{#State 368
		ACTIONS => {
			'SMC_TOKEN' => 78
		},
		GOTOS => {
			'SmcToken' => 424
		}
	},
	{#State 369
		ACTIONS => {
			'LSB_TOKEN' => 94,
			'LP_TOKEN' => 100,
			'DOT_TOKEN' => 96,
			'IDENTIFIER' => 426
		},
		DEFAULT => -61,
		GOTOS => {
			'ForVarControlRest' => 427,
			'VariableDeclarators' => 425,
			'ExprInDim' => 98,
			'ArrayDim' => 99,
			'VariableDeclarator' => 291,
			'Arguments' => 97,
			'PrimarySuffix' => 95
		}
	},
	{#State 370
		DEFAULT => -163
	},
	{#State 371
		ACTIONS => {
			'RP_TOKEN' => 428
		}
	},
	{#State 372
		ACTIONS => {
			'DEFAULT_TOKEN' => 430,
			'CASE_TOKEN' => 431
		},
		DEFAULT => -149,
		GOTOS => {
			'SwitchBlockStatementGroup' => 429,
			'SwitchLabel' => 432,
			'SwitchBlockStatementGroups' => 433
		}
	},
	{#State 373
		ACTIONS => {
			'EQUAL_OPR' => 182,
			'ASSIGN_P_OPR' => 180,
			'ASSIGN_OPR' => 184,
			'RP_TOKEN' => 434
		},
		GOTOS => {
			'AssignmentOperator' => 181
		}
	},
	{#State 374
		DEFAULT => -127
	},
	{#State 375
		DEFAULT => -129
	},
	{#State 376
		ACTIONS => {
			'SHORT_TOKEN' => 22,
			'INTEGER_LITERAL' => 53,
			'LONG_TOKEN' => 26,
			'VOID_TOKEN' => 54,
			'BYTE_TOKEN' => 27,
			'MINUS_OPR' => 30,
			'TRUE_TOKEN' => 58,
			'DOUBLE_TOKEN' => 57,
			'INT_TOKEN' => 59,
			'FALSE_TOKEN' => 32,
			'NULL_TOKEN' => 62,
			'FLOAT_LITERAL' => 36,
			'POSTFIX_OPR' => 64,
			'LP_TOKEN' => 65,
			'IDENTIFIER' => 90,
			'CHAR_TOKEN' => 38,
			'PLUS_OPR' => 41,
			'THIS_TOKEN' => 67,
			'BOOLEAN_TOKEN' => 69,
			'CHAR_LITERAL' => 43,
			'PREFIX_OPR' => 45,
			'FLOAT_TOKEN' => 47,
			'NEW_TOKEN' => 73,
			'STRING_LITERAL' => 74,
			'SUPER_TOKEN' => 76
		},
		GOTOS => {
			'AdditiveOpr' => 50,
			'CastExpression' => 21,
			'UnaryExpressionNotPlusMinus' => 23,
			'RelationalExpression' => 24,
			'InstanceOfExpression' => 25,
			'MultiplicativeExpression' => 28,
			'EqualityExpression' => 56,
			'ParExpression' => 61,
			'Primary' => 33,
			'ExclusiveOrExpression' => 34,
			'InclusiveOrExpression' => 35,
			'ConditionalOrExpression' => 63,
			'AllocationExpression' => 37,
			'Expression' => 435,
			'BasicType' => 40,
			'Literal' => 66,
			'UnaryOpr' => 42,
			'ConditionalAndExpression' => 70,
			'PrimaryExpression' => 44,
			'ShiftExpression' => 71,
			'UnaryExpression' => 48,
			'ConditionalExpression' => 113,
			'AdditiveExpression' => 75,
			'AndExpression' => 49,
			'PrimaryPrefix' => 77
		}
	},
	{#State 377
		ACTIONS => {
			'SMC_TOKEN' => 78
		},
		GOTOS => {
			'SmcToken' => 436
		}
	},
	{#State 378
		DEFAULT => -123
	},
	{#State 379
		DEFAULT => -117
	},
	{#State 380
		DEFAULT => -137
	},
	{#State 381
		DEFAULT => -130
	},
	{#State 382
		DEFAULT => -134
	},
	{#State 383
		DEFAULT => -132
	},
	{#State 384
		ACTIONS => {
			'ELSE_TOKEN' => 438
		},
		DEFAULT => -144,
		GOTOS => {
			'ElseStatementOrEmpty' => 437
		}
	},
	{#State 385
		ACTIONS => {
			'FINALLY_TOKEN' => 439
		}
	},
	{#State 386
		DEFAULT => -146
	},
	{#State 387
		ACTIONS => {
			'LP_TOKEN' => 440
		}
	},
	{#State 388
		ACTIONS => {
			'CATCH_TOKEN' => 387,
			'FINALLY_TOKEN' => -143
		},
		DEFAULT => -140,
		GOTOS => {
			'CatchClause' => 441
		}
	},
	{#State 389
		DEFAULT => -125
	},
	{#State 390
		DEFAULT => -208
	},
	{#State 391
		DEFAULT => -216
	},
	{#State 392
		ACTIONS => {
			'SHORT_TOKEN' => 22,
			'INTEGER_LITERAL' => 53,
			'LONG_TOKEN' => 26,
			'VOID_TOKEN' => 54,
			'BYTE_TOKEN' => 27,
			'MINUS_OPR' => 30,
			'LCB_TOKEN' => 55,
			'TRUE_TOKEN' => 58,
			'DOUBLE_TOKEN' => 57,
			'INT_TOKEN' => 59,
			'FALSE_TOKEN' => 32,
			'NULL_TOKEN' => 62,
			'FLOAT_LITERAL' => 36,
			'POSTFIX_OPR' => 64,
			'LP_TOKEN' => 65,
			'IDENTIFIER' => 90,
			'CHAR_TOKEN' => 38,
			'PLUS_OPR' => 41,
			'THIS_TOKEN' => 67,
			'BOOLEAN_TOKEN' => 69,
			'CHAR_LITERAL' => 43,
			'PREFIX_OPR' => 45,
			'FLOAT_TOKEN' => 47,
			'NEW_TOKEN' => 73,
			'STRING_LITERAL' => 74,
			'SUPER_TOKEN' => 76
		},
		GOTOS => {
			'AdditiveOpr' => 50,
			'CastExpression' => 21,
			'UnaryExpressionNotPlusMinus' => 23,
			'RelationalExpression' => 24,
			'InstanceOfExpression' => 25,
			'MultiplicativeExpression' => 28,
			'EqualityExpression' => 56,
			'LcbToken' => 166,
			'ArrayInitializer' => 221,
			'ParExpression' => 61,
			'Primary' => 33,
			'ExclusiveOrExpression' => 34,
			'InclusiveOrExpression' => 35,
			'ConditionalOrExpression' => 63,
			'AllocationExpression' => 37,
			'Expression' => 224,
			'BasicType' => 40,
			'Literal' => 66,
			'UnaryOpr' => 42,
			'VariableInitializer' => 442,
			'ConditionalAndExpression' => 70,
			'PrimaryExpression' => 44,
			'ShiftExpression' => 71,
			'UnaryExpression' => 48,
			'ConditionalExpression' => 113,
			'AdditiveExpression' => 75,
			'AndExpression' => 49,
			'PrimaryPrefix' => 77
		}
	},
	{#State 393
		ACTIONS => {
			'THROWS_TOKEN' => 346
		},
		DEFAULT => -349,
		GOTOS => {
			'ThrowsQIdentOrEmpty' => 443
		}
	},
	{#State 394
		ACTIONS => {
			'VOLATILE_TOKEN' => 136,
			'FINAL_TOKEN' => 126,
			'PROTECTED_TOKEN' => 137,
			'NATIVE_TOKEN' => 129,
			'STRICTFP_TOKEN' => 130,
			'ABSTRACT_TOKEN' => 132,
			'PUBLIC_TOKEN' => 133,
			'PRIVATE_TOKEN' => 140,
			'STATIC_TOKEN' => 142,
			'ATMARK_TOKEN' => 2,
			'TRANSIENT_TOKEN' => 143,
			'SYNCHRONIZED_TOKEN' => 135
		},
		DEFAULT => -205,
		GOTOS => {
			'Modifier' => 141,
			'Annotation' => 145,
			'ModifiersOrEmpty' => 343,
			'Modifiers' => 131,
			'FormalParameterDecls' => 444
		}
	},
	{#State 395
		DEFAULT => -354
	},
	{#State 396
		ACTIONS => {
			'DOT_TOKEN' => 446,
			'IDENTIFIER' => 447
		},
		GOTOS => {
			'FormalParameterDeclsRest' => 445,
			'VariableDeclaratorId' => 448
		}
	},
	{#State 397
		DEFAULT => -348
	},
	{#State 398
		DEFAULT => -360
	},
	{#State 399
		ACTIONS => {
			'CM_TOKEN' => 449
		},
		DEFAULT => -350
	},
	{#State 400
		ACTIONS => {
			'DOT_TOKEN' => 12
		},
		DEFAULT => -351
	},
	{#State 401
		DEFAULT => -327
	},
	{#State 402
		DEFAULT => -326
	},
	{#State 403
		ACTIONS => {
			'LCB_TOKEN' => 55,
			'SMC_TOKEN' => 78
		},
		GOTOS => {
			'Block' => 398,
			'LcbToken' => 239,
			'MethodBodyOrSemiColon' => 450,
			'SmcToken' => 452,
			'MethodBody' => 451
		}
	},
	{#State 404
		DEFAULT => -264
	},
	{#State 405
		ACTIONS => {
			'AMP_OPR' => 453
		},
		DEFAULT => -268
	},
	{#State 406
		DEFAULT => -269
	},
	{#State 407
		ACTIONS => {
			'CHAR_TOKEN' => 38,
			'IDENTIFIER' => 7,
			'SHORT_TOKEN' => 22,
			'LONG_TOKEN' => 26,
			'BYTE_TOKEN' => 27,
			'BOOLEAN_TOKEN' => 69,
			'DOUBLE_TOKEN' => 57,
			'INT_TOKEN' => 59,
			'FLOAT_TOKEN' => 47
		},
		GOTOS => {
			'BasicType' => 148,
			'Type' => 454,
			'QualifiedIdentifier' => 146
		}
	},
	{#State 408
		DEFAULT => -261,
		GOTOS => {
			'NameFinalzer' => 455
		}
	},
	{#State 409
		ACTIONS => {
			'CM_TOKEN' => 456
		},
		DEFAULT => -276
	},
	{#State 410
		ACTIONS => {
			'IDENTIFIER' => 457
		}
	},
	{#State 411
		ACTIONS => {
			'CM_TOKEN' => 458
		},
		DEFAULT => -226,
		GOTOS => {
			'CommaOrEmpty' => 459
		}
	},
	{#State 412
		DEFAULT => -279
	},
	{#State 413
		DEFAULT => -258
	},
	{#State 414
		ACTIONS => {
			'LCB_TOKEN' => 55
		},
		GOTOS => {
			'LcbToken' => 163,
			'ClassBody' => 460
		}
	},
	{#State 415
		ACTIONS => {
			'CM_TOKEN' => 407
		},
		DEFAULT => -294
	},
	{#State 416
		DEFAULT => -289,
		GOTOS => {
			'@9-6' => 461
		}
	},
	{#State 417
		ACTIONS => {
			'VOLATILE_TOKEN' => 136,
			'FINAL_TOKEN' => 126,
			'PROTECTED_TOKEN' => 137,
			'SMC_TOKEN' => 78,
			'LINE_DECL_TOKEN' => 216,
			'NATIVE_TOKEN' => 129,
			'STRICTFP_TOKEN' => 130,
			'RCB_TOKEN' => 151,
			'ABSTRACT_TOKEN' => 132,
			'PUBLIC_TOKEN' => 133,
			'PRIVATE_TOKEN' => 140,
			'STATIC_TOKEN' => 142,
			'ATMARK_TOKEN' => 2,
			'TRANSIENT_TOKEN' => 143,
			'SYNCHRONIZED_TOKEN' => 135
		},
		DEFAULT => -205,
		GOTOS => {
			'LineDecl' => 465,
			'SmcToken' => 467,
			'RcbToken' => 462,
			'InterfaceBodyDeclaration' => 466,
			'Modifier' => 141,
			'ModifiersOrEmpty' => 463,
			'Annotation' => 145,
			'InterfaceBodyDeclarations' => 464,
			'Modifiers' => 131
		}
	},
	{#State 418
		ACTIONS => {
			'SMC_TOKEN' => 78
		},
		GOTOS => {
			'SmcToken' => 468
		}
	},
	{#State 419
		DEFAULT => -118
	},
	{#State 420
		ACTIONS => {
			'IDENTIFIER' => 426
		},
		GOTOS => {
			'ForVarControlRest' => 469,
			'VariableDeclarators' => 425,
			'VariableDeclarator' => 291
		}
	},
	{#State 421
		ACTIONS => {
			'SHORT_TOKEN' => 22,
			'INTEGER_LITERAL' => 53,
			'LONG_TOKEN' => 26,
			'VOID_TOKEN' => 54,
			'BYTE_TOKEN' => 27,
			'MINUS_OPR' => 30,
			'TRUE_TOKEN' => 58,
			'DOUBLE_TOKEN' => 57,
			'INT_TOKEN' => 59,
			'FALSE_TOKEN' => 32,
			'NULL_TOKEN' => 62,
			'FLOAT_LITERAL' => 36,
			'POSTFIX_OPR' => 64,
			'LP_TOKEN' => 65,
			'IDENTIFIER' => 90,
			'CHAR_TOKEN' => 38,
			'PLUS_OPR' => 41,
			'THIS_TOKEN' => 67,
			'BOOLEAN_TOKEN' => 69,
			'CHAR_LITERAL' => 43,
			'PREFIX_OPR' => 45,
			'FLOAT_TOKEN' => 47,
			'NEW_TOKEN' => 73,
			'STRING_LITERAL' => 74,
			'SUPER_TOKEN' => 76
		},
		GOTOS => {
			'AdditiveOpr' => 50,
			'CastExpression' => 21,
			'UnaryExpressionNotPlusMinus' => 23,
			'StatementExpression' => 470,
			'RelationalExpression' => 24,
			'InstanceOfExpression' => 25,
			'MultiplicativeExpression' => 28,
			'EqualityExpression' => 56,
			'ParExpression' => 61,
			'Primary' => 33,
			'ExclusiveOrExpression' => 34,
			'InclusiveOrExpression' => 35,
			'ConditionalOrExpression' => 63,
			'AllocationExpression' => 37,
			'Expression' => 284,
			'BasicType' => 40,
			'Literal' => 66,
			'UnaryOpr' => 42,
			'ConditionalAndExpression' => 70,
			'PrimaryExpression' => 44,
			'ShiftExpression' => 71,
			'UnaryExpression' => 48,
			'ConditionalExpression' => 113,
			'AdditiveExpression' => 75,
			'AndExpression' => 49,
			'PrimaryPrefix' => 77
		}
	},
	{#State 422
		ACTIONS => {
			'CM_TOKEN' => 471
		},
		DEFAULT => -159
	},
	{#State 423
		DEFAULT => -190
	},
	{#State 424
		ACTIONS => {
			'SHORT_TOKEN' => 22,
			'INTEGER_LITERAL' => 53,
			'LONG_TOKEN' => 26,
			'VOID_TOKEN' => 54,
			'BYTE_TOKEN' => 27,
			'MINUS_OPR' => 30,
			'TRUE_TOKEN' => 58,
			'DOUBLE_TOKEN' => 57,
			'INT_TOKEN' => 59,
			'FALSE_TOKEN' => 32,
			'NULL_TOKEN' => 62,
			'FLOAT_LITERAL' => 36,
			'POSTFIX_OPR' => 64,
			'LP_TOKEN' => 65,
			'IDENTIFIER' => 90,
			'CHAR_TOKEN' => 38,
			'PLUS_OPR' => 41,
			'THIS_TOKEN' => 67,
			'BOOLEAN_TOKEN' => 69,
			'CHAR_LITERAL' => 43,
			'PREFIX_OPR' => 45,
			'FLOAT_TOKEN' => 47,
			'NEW_TOKEN' => 73,
			'STRING_LITERAL' => 74,
			'SUPER_TOKEN' => 76
		},
		DEFAULT => -14,
		GOTOS => {
			'AdditiveOpr' => 50,
			'CastExpression' => 21,
			'UnaryExpressionNotPlusMinus' => 23,
			'RelationalExpression' => 24,
			'InstanceOfExpression' => 25,
			'MultiplicativeExpression' => 28,
			'EqualityExpression' => 56,
			'ParExpression' => 61,
			'Primary' => 33,
			'ExclusiveOrExpression' => 34,
			'ExpressionOrEmpty' => 472,
			'InclusiveOrExpression' => 35,
			'ConditionalOrExpression' => 63,
			'AllocationExpression' => 37,
			'Expression' => 473,
			'BasicType' => 40,
			'Literal' => 66,
			'UnaryOpr' => 42,
			'ConditionalAndExpression' => 70,
			'PrimaryExpression' => 44,
			'ShiftExpression' => 71,
			'UnaryExpression' => 48,
			'ConditionalExpression' => 113,
			'AdditiveExpression' => 75,
			'AndExpression' => 49,
			'PrimaryPrefix' => 77
		}
	},
	{#State 425
		ACTIONS => {
			'CM_TOKEN' => 334,
			'SMC_TOKEN' => 78
		},
		GOTOS => {
			'SmcToken' => 474
		}
	},
	{#State 426
		ACTIONS => {
			'EQUAL_OPR' => 338,
			'LSB_TOKEN' => 205,
			'CLN_TOKEN' => 475
		},
		DEFAULT => -211,
		GOTOS => {
			'ArrayDim' => 339,
			'VariableDeclaratorRest' => 336
		}
	},
	{#State 427
		DEFAULT => -166
	},
	{#State 428
		ACTIONS => {
			'ASSERT_TOKEN' => 272,
			'SHORT_TOKEN' => 22,
			'LONG_TOKEN' => 26,
			'BYTE_TOKEN' => 27,
			'MINUS_OPR' => 30,
			'SMC_TOKEN' => 78,
			'DO_TOKEN' => 264,
			'FALSE_TOKEN' => 32,
			'WHILE_TOKEN' => 274,
			'FLOAT_LITERAL' => 36,
			'IDENTIFIER' => 277,
			'CHAR_TOKEN' => 38,
			'PLUS_OPR' => 41,
			'FOR_TOKEN' => 266,
			'CHAR_LITERAL' => 43,
			'SWITCH_TOKEN' => 268,
			'PREFIX_OPR' => 45,
			'FLOAT_TOKEN' => 47,
			'SYNCHRONIZED_TOKEN' => 310,
			'RETURN_TOKEN' => 270,
			'INTEGER_LITERAL' => 53,
			'VOID_TOKEN' => 54,
			'THROW_TOKEN' => 279,
			'LCB_TOKEN' => 55,
			'DOUBLE_TOKEN' => 57,
			'TRUE_TOKEN' => 58,
			'INT_TOKEN' => 59,
			'CONTINUE_TOKEN' => 280,
			'NULL_TOKEN' => 62,
			'LP_TOKEN' => 65,
			'POSTFIX_OPR' => 64,
			'IF_TOKEN' => 285,
			'BREAK_TOKEN' => 283,
			'TRY_TOKEN' => 286,
			'THIS_TOKEN' => 67,
			'BOOLEAN_TOKEN' => 69,
			'NEW_TOKEN' => 73,
			'STRING_LITERAL' => 74,
			'SUPER_TOKEN' => 76
		},
		GOTOS => {
			'AdditiveOpr' => 50,
			'CastExpression' => 21,
			'Block' => 278,
			'UnaryExpressionNotPlusMinus' => 23,
			'StatementExpression' => 273,
			'RelationalExpression' => 24,
			'InstanceOfExpression' => 25,
			'MultiplicativeExpression' => 28,
			'EqualityExpression' => 56,
			'LcbToken' => 239,
			'ParExpression' => 61,
			'Primary' => 33,
			'ExclusiveOrExpression' => 34,
			'Statement' => 476,
			'InclusiveOrExpression' => 35,
			'ConditionalOrExpression' => 63,
			'AllocationExpression' => 37,
			'Expression' => 284,
			'BasicType' => 40,
			'Literal' => 66,
			'UnaryOpr' => 42,
			'SmcToken' => 287,
			'ConditionalAndExpression' => 70,
			'PrimaryExpression' => 44,
			'ShiftExpression' => 71,
			'UnaryExpression' => 48,
			'ConditionalExpression' => 113,
			'AdditiveExpression' => 75,
			'AndExpression' => 49,
			'PrimaryPrefix' => 77
		}
	},
	{#State 429
		DEFAULT => -150
	},
	{#State 430
		ACTIONS => {
			'CLN_TOKEN' => 477
		}
	},
	{#State 431
		ACTIONS => {
			'SHORT_TOKEN' => 22,
			'INTEGER_LITERAL' => 53,
			'LONG_TOKEN' => 26,
			'VOID_TOKEN' => 54,
			'BYTE_TOKEN' => 27,
			'MINUS_OPR' => 30,
			'TRUE_TOKEN' => 58,
			'DOUBLE_TOKEN' => 57,
			'INT_TOKEN' => 59,
			'FALSE_TOKEN' => 32,
			'NULL_TOKEN' => 62,
			'FLOAT_LITERAL' => 36,
			'POSTFIX_OPR' => 64,
			'LP_TOKEN' => 65,
			'IDENTIFIER' => 90,
			'CHAR_TOKEN' => 38,
			'PLUS_OPR' => 41,
			'THIS_TOKEN' => 67,
			'BOOLEAN_TOKEN' => 69,
			'CHAR_LITERAL' => 43,
			'PREFIX_OPR' => 45,
			'FLOAT_TOKEN' => 47,
			'NEW_TOKEN' => 73,
			'STRING_LITERAL' => 74,
			'SUPER_TOKEN' => 76
		},
		GOTOS => {
			'AdditiveOpr' => 50,
			'CastExpression' => 21,
			'UnaryExpressionNotPlusMinus' => 23,
			'RelationalExpression' => 24,
			'ConstantExpression' => 478,
			'InstanceOfExpression' => 25,
			'MultiplicativeExpression' => 28,
			'EqualityExpression' => 56,
			'ParExpression' => 61,
			'Primary' => 33,
			'ExclusiveOrExpression' => 34,
			'InclusiveOrExpression' => 35,
			'ConditionalOrExpression' => 63,
			'AllocationExpression' => 37,
			'Expression' => 479,
			'BasicType' => 40,
			'Literal' => 66,
			'UnaryOpr' => 42,
			'ConditionalAndExpression' => 70,
			'PrimaryExpression' => 44,
			'ShiftExpression' => 71,
			'UnaryExpression' => 48,
			'ConditionalExpression' => 113,
			'AdditiveExpression' => 75,
			'AndExpression' => 49,
			'PrimaryPrefix' => 77
		}
	},
	{#State 432
		ACTIONS => {
			'ASSERT_TOKEN' => 272,
			'FINAL_TOKEN' => 126,
			'DEFAULT_TOKEN' => -152,
			'SHORT_TOKEN' => 22,
			'LONG_TOKEN' => 26,
			'BYTE_TOKEN' => 27,
			'MINUS_OPR' => 30,
			'SMC_TOKEN' => 78,
			'NATIVE_TOKEN' => 129,
			'DO_TOKEN' => 264,
			'FALSE_TOKEN' => 32,
			'WHILE_TOKEN' => 274,
			'CASE_TOKEN' => -152,
			'STRICTFP_TOKEN' => 130,
			'FLOAT_LITERAL' => 36,
			'IDENTIFIER' => 277,
			'CHAR_TOKEN' => 38,
			'PLUS_OPR' => 41,
			'RCB_TOKEN' => -152,
			'ABSTRACT_TOKEN' => 132,
			'FOR_TOKEN' => 266,
			'CHAR_LITERAL' => 43,
			'PUBLIC_TOKEN' => 133,
			'SWITCH_TOKEN' => 268,
			'PREFIX_OPR' => 45,
			'FLOAT_TOKEN' => 47,
			'SYNCHRONIZED_TOKEN' => 269,
			'VOLATILE_TOKEN' => 136,
			'PROTECTED_TOKEN' => 137,
			'RETURN_TOKEN' => 270,
			'INTEGER_LITERAL' => 53,
			'THROW_TOKEN' => 279,
			'VOID_TOKEN' => 54,
			'LCB_TOKEN' => 55,
			'TRUE_TOKEN' => 58,
			'LINE_DECL_TOKEN' => 216,
			'DOUBLE_TOKEN' => 57,
			'INT_TOKEN' => 59,
			'CONTINUE_TOKEN' => 280,
			'NULL_TOKEN' => 62,
			'LP_TOKEN' => 65,
			'POSTFIX_OPR' => 64,
			'IF_TOKEN' => 285,
			'BREAK_TOKEN' => 283,
			'TRY_TOKEN' => 286,
			'THIS_TOKEN' => 67,
			'BOOLEAN_TOKEN' => 69,
			'PRIVATE_TOKEN' => 140,
			'STATIC_TOKEN' => 142,
			'TRANSIENT_TOKEN' => 143,
			'ATMARK_TOKEN' => 2,
			'NEW_TOKEN' => 73,
			'STRING_LITERAL' => 74,
			'SUPER_TOKEN' => 76
		},
		DEFAULT => -205,
		GOTOS => {
			'CastExpression' => 21,
			'UnaryExpressionNotPlusMinus' => 23,
			'StatementExpression' => 273,
			'RelationalExpression' => 24,
			'ClassOrInterfaceDeclaration' => 263,
			'InstanceOfExpression' => 25,
			'MultiplicativeExpression' => 28,
			'LcbToken' => 239,
			'Primary' => 275,
			'ExclusiveOrExpression' => 34,
			'InclusiveOrExpression' => 35,
			'Modifiers' => 265,
			'BlockStatement' => 276,
			'AllocationExpression' => 37,
			'BasicType' => 40,
			'UnaryOpr' => 42,
			'PrimaryExpression' => 44,
			'ModifiersOrEmpty' => 134,
			'UnaryExpression' => 48,
			'ConditionalExpression' => 113,
			'AndExpression' => 49,
			'AdditiveOpr' => 50,
			'Block' => 278,
			'EqualityExpression' => 56,
			'ParExpression' => 61,
			'BlockStatements' => 480,
			'Statement' => 282,
			'ConditionalOrExpression' => 63,
			'Expression' => 284,
			'Literal' => 66,
			'LineDecl' => 271,
			'SmcToken' => 287,
			'ConditionalAndExpression' => 70,
			'LocalVariableDeclarationStatement' => 288,
			'Modifier' => 141,
			'ShiftExpression' => 71,
			'Annotation' => 145,
			'AdditiveExpression' => 75,
			'PrimaryPrefix' => 77
		}
	},
	{#State 433
		ACTIONS => {
			'DEFAULT_TOKEN' => 430,
			'RCB_TOKEN' => 151,
			'CASE_TOKEN' => 431
		},
		GOTOS => {
			'SwitchBlockStatementGroup' => 482,
			'SwitchLabel' => 432,
			'RcbToken' => 481
		}
	},
	{#State 434
		DEFAULT => -107
	},
	{#State 435
		ACTIONS => {
			'EQUAL_OPR' => 182,
			'ASSIGN_P_OPR' => 180,
			'ASSIGN_OPR' => 184
		},
		DEFAULT => -139,
		GOTOS => {
			'AssignmentOperator' => 181
		}
	},
	{#State 436
		DEFAULT => -120
	},
	{#State 437
		DEFAULT => -121
	},
	{#State 438
		ACTIONS => {
			'ASSERT_TOKEN' => 272,
			'SHORT_TOKEN' => 22,
			'LONG_TOKEN' => 26,
			'BYTE_TOKEN' => 27,
			'MINUS_OPR' => 30,
			'SMC_TOKEN' => 78,
			'DO_TOKEN' => 264,
			'FALSE_TOKEN' => 32,
			'WHILE_TOKEN' => 274,
			'FLOAT_LITERAL' => 36,
			'IDENTIFIER' => 277,
			'CHAR_TOKEN' => 38,
			'PLUS_OPR' => 41,
			'FOR_TOKEN' => 266,
			'CHAR_LITERAL' => 43,
			'SWITCH_TOKEN' => 268,
			'PREFIX_OPR' => 45,
			'FLOAT_TOKEN' => 47,
			'SYNCHRONIZED_TOKEN' => 310,
			'RETURN_TOKEN' => 270,
			'INTEGER_LITERAL' => 53,
			'VOID_TOKEN' => 54,
			'THROW_TOKEN' => 279,
			'LCB_TOKEN' => 55,
			'DOUBLE_TOKEN' => 57,
			'TRUE_TOKEN' => 58,
			'INT_TOKEN' => 59,
			'CONTINUE_TOKEN' => 280,
			'NULL_TOKEN' => 62,
			'LP_TOKEN' => 65,
			'POSTFIX_OPR' => 64,
			'IF_TOKEN' => 285,
			'BREAK_TOKEN' => 283,
			'TRY_TOKEN' => 286,
			'THIS_TOKEN' => 67,
			'BOOLEAN_TOKEN' => 69,
			'NEW_TOKEN' => 73,
			'STRING_LITERAL' => 74,
			'SUPER_TOKEN' => 76
		},
		GOTOS => {
			'AdditiveOpr' => 50,
			'CastExpression' => 21,
			'Block' => 278,
			'UnaryExpressionNotPlusMinus' => 23,
			'StatementExpression' => 273,
			'RelationalExpression' => 24,
			'InstanceOfExpression' => 25,
			'MultiplicativeExpression' => 28,
			'EqualityExpression' => 56,
			'LcbToken' => 239,
			'ParExpression' => 61,
			'Primary' => 33,
			'ExclusiveOrExpression' => 34,
			'Statement' => 483,
			'InclusiveOrExpression' => 35,
			'ConditionalOrExpression' => 63,
			'AllocationExpression' => 37,
			'Expression' => 284,
			'BasicType' => 40,
			'Literal' => 66,
			'UnaryOpr' => 42,
			'SmcToken' => 287,
			'ConditionalAndExpression' => 70,
			'PrimaryExpression' => 44,
			'ShiftExpression' => 71,
			'UnaryExpression' => 48,
			'ConditionalExpression' => 113,
			'AdditiveExpression' => 75,
			'AndExpression' => 49,
			'PrimaryPrefix' => 77
		}
	},
	{#State 439
		ACTIONS => {
			'LCB_TOKEN' => 55
		},
		GOTOS => {
			'Block' => 484,
			'LcbToken' => 239
		}
	},
	{#State 440
		ACTIONS => {
			'VOLATILE_TOKEN' => 136,
			'FINAL_TOKEN' => 126,
			'PROTECTED_TOKEN' => 137,
			'NATIVE_TOKEN' => 129,
			'STRICTFP_TOKEN' => 130,
			'ABSTRACT_TOKEN' => 132,
			'PUBLIC_TOKEN' => 133,
			'PRIVATE_TOKEN' => 140,
			'STATIC_TOKEN' => 142,
			'ATMARK_TOKEN' => 2,
			'TRANSIENT_TOKEN' => 143,
			'SYNCHRONIZED_TOKEN' => 135
		},
		DEFAULT => -205,
		GOTOS => {
			'Modifier' => 141,
			'Annotation' => 145,
			'ModifiersOrEmpty' => 343,
			'Modifiers' => 131,
			'FormalParameterDecls' => 485
		}
	},
	{#State 441
		DEFAULT => -147
	},
	{#State 442
		DEFAULT => -215
	},
	{#State 443
		ACTIONS => {
			'LCB_TOKEN' => 55,
			'SMC_TOKEN' => 78
		},
		GOTOS => {
			'Block' => 398,
			'LcbToken' => 239,
			'MethodBodyOrSemiColon' => 486,
			'SmcToken' => 452,
			'MethodBody' => 451
		}
	},
	{#State 444
		DEFAULT => -357
	},
	{#State 445
		DEFAULT => -355
	},
	{#State 446
		ACTIONS => {
			'DOT_TOKEN' => 487
		}
	},
	{#State 447
		ACTIONS => {
			'LSB_TOKEN' => 205
		},
		DEFAULT => -228,
		GOTOS => {
			'ArrayDim' => 488
		}
	},
	{#State 448
		DEFAULT => -358
	},
	{#State 449
		ACTIONS => {
			'IDENTIFIER' => 7
		},
		GOTOS => {
			'QualifiedIdentifier' => 489
		}
	},
	{#State 450
		DEFAULT => -343
	},
	{#State 451
		DEFAULT => -341
	},
	{#State 452
		DEFAULT => -342
	},
	{#State 453
		ACTIONS => {
			'CHAR_TOKEN' => 38,
			'IDENTIFIER' => 7,
			'SHORT_TOKEN' => 22,
			'LONG_TOKEN' => 26,
			'BYTE_TOKEN' => 27,
			'BOOLEAN_TOKEN' => 69,
			'DOUBLE_TOKEN' => 57,
			'INT_TOKEN' => 59,
			'FLOAT_TOKEN' => 47
		},
		GOTOS => {
			'BasicType' => 148,
			'Type' => 490,
			'QualifiedIdentifier' => 146
		}
	},
	{#State 454
		DEFAULT => -296
	},
	{#State 455
		DEFAULT => -273
	},
	{#State 456
		ACTIONS => {
			'ATMARK_TOKEN' => 2
		},
		DEFAULT => -188,
		GOTOS => {
			'Annotation' => 3,
			'EnumConstant' => 491,
			'AnnotationsOrEmpty' => 410,
			'Annotations' => 5
		}
	},
	{#State 457
		DEFAULT => -281,
		GOTOS => {
			'@6-2' => 492
		}
	},
	{#State 458
		DEFAULT => -227
	},
	{#State 459
		ACTIONS => {
			'SMC_TOKEN' => 78
		},
		DEFAULT => -277,
		GOTOS => {
			'EnumBodyDeclarationsOrEmpty' => 494,
			'EnumBodyDeclarations' => 493,
			'SmcToken' => 495
		}
	},
	{#State 460
		DEFAULT => -255,
		GOTOS => {
			'@3-7' => 496
		}
	},
	{#State 461
		DEFAULT => -261,
		GOTOS => {
			'NameFinalzer' => 497
		}
	},
	{#State 462
		DEFAULT => -303
	},
	{#State 463
		ACTIONS => {
			'CHAR_TOKEN' => 38,
			'IDENTIFIER' => 7,
			'SHORT_TOKEN' => 22,
			'ENUM_TOKEN' => 194,
			'CLASS_TOKEN' => 195,
			'LONG_TOKEN' => 26,
			'VOID_TOKEN' => 502,
			'BYTE_TOKEN' => 27,
			'BOOLEAN_TOKEN' => 69,
			'INTERFACE_TOKEN' => 203,
			'DOUBLE_TOKEN' => 57,
			'INT_TOKEN' => 59,
			'ATMARK_INTERFACE_TOKEN' => 204,
			'FLOAT_TOKEN' => 47,
			'LT_OPR' => 253
		},
		GOTOS => {
			'BasicType' => 148,
			'InterfaceGenericMethodDecl' => 504,
			'InterfaceMemberDecl' => 498,
			'EnumDeclaration' => 199,
			'QualifiedIdentifier' => 146,
			'TypeParameters' => 505,
			'InterfaceOrAtInterface' => 196,
			'NormalClassDeclaration' => 202,
			'InterfaceDeclaration' => 500,
			'NormalInterfaceDeclaration' => 197,
			'Type' => 503,
			'ClassDeclaration' => 499,
			'InterfaceMethodOrFieldDecl' => 501
		}
	},
	{#State 464
		ACTIONS => {
			'VOLATILE_TOKEN' => 136,
			'FINAL_TOKEN' => 126,
			'PROTECTED_TOKEN' => 137,
			'SMC_TOKEN' => 78,
			'NATIVE_TOKEN' => 129,
			'STRICTFP_TOKEN' => 130,
			'RCB_TOKEN' => 151,
			'ABSTRACT_TOKEN' => 132,
			'PUBLIC_TOKEN' => 133,
			'PRIVATE_TOKEN' => 140,
			'STATIC_TOKEN' => 142,
			'ATMARK_TOKEN' => 2,
			'TRANSIENT_TOKEN' => 143,
			'SYNCHRONIZED_TOKEN' => 135
		},
		DEFAULT => -205,
		GOTOS => {
			'Modifier' => 141,
			'InterfaceBodyDeclaration' => 507,
			'Annotation' => 145,
			'ModifiersOrEmpty' => 463,
			'SmcToken' => 467,
			'RcbToken' => 506,
			'Modifiers' => 131
		}
	},
	{#State 465
		DEFAULT => -307
	},
	{#State 466
		DEFAULT => -305
	},
	{#State 467
		DEFAULT => -329
	},
	{#State 468
		DEFAULT => -124
	},
	{#State 469
		DEFAULT => -167
	},
	{#State 470
		DEFAULT => -156
	},
	{#State 471
		ACTIONS => {
			'SHORT_TOKEN' => 22,
			'INTEGER_LITERAL' => 53,
			'LONG_TOKEN' => 26,
			'VOID_TOKEN' => 54,
			'BYTE_TOKEN' => 27,
			'MINUS_OPR' => 30,
			'TRUE_TOKEN' => 58,
			'DOUBLE_TOKEN' => 57,
			'INT_TOKEN' => 59,
			'FALSE_TOKEN' => 32,
			'NULL_TOKEN' => 62,
			'FLOAT_LITERAL' => 36,
			'POSTFIX_OPR' => 64,
			'LP_TOKEN' => 65,
			'IDENTIFIER' => 90,
			'CHAR_TOKEN' => 38,
			'PLUS_OPR' => 41,
			'THIS_TOKEN' => 67,
			'BOOLEAN_TOKEN' => 69,
			'CHAR_LITERAL' => 43,
			'PREFIX_OPR' => 45,
			'FLOAT_TOKEN' => 47,
			'NEW_TOKEN' => 73,
			'STRING_LITERAL' => 74,
			'SUPER_TOKEN' => 76
		},
		GOTOS => {
			'AdditiveOpr' => 50,
			'CastExpression' => 21,
			'UnaryExpressionNotPlusMinus' => 23,
			'StatementExpression' => 508,
			'RelationalExpression' => 24,
			'InstanceOfExpression' => 25,
			'MultiplicativeExpression' => 28,
			'EqualityExpression' => 56,
			'ParExpression' => 61,
			'Primary' => 33,
			'ExclusiveOrExpression' => 34,
			'InclusiveOrExpression' => 35,
			'ConditionalOrExpression' => 63,
			'AllocationExpression' => 37,
			'Expression' => 284,
			'BasicType' => 40,
			'Literal' => 66,
			'UnaryOpr' => 42,
			'ConditionalAndExpression' => 70,
			'PrimaryExpression' => 44,
			'ShiftExpression' => 71,
			'UnaryExpression' => 48,
			'ConditionalExpression' => 113,
			'AdditiveExpression' => 75,
			'AndExpression' => 49,
			'PrimaryPrefix' => 77
		}
	},
	{#State 472
		ACTIONS => {
			'SMC_TOKEN' => 78
		},
		GOTOS => {
			'SmcToken' => 509
		}
	},
	{#State 473
		ACTIONS => {
			'EQUAL_OPR' => 182,
			'ASSIGN_P_OPR' => 180,
			'ASSIGN_OPR' => 184
		},
		DEFAULT => -15,
		GOTOS => {
			'AssignmentOperator' => 181
		}
	},
	{#State 474
		ACTIONS => {
			'SHORT_TOKEN' => 22,
			'INTEGER_LITERAL' => 53,
			'LONG_TOKEN' => 26,
			'VOID_TOKEN' => 54,
			'BYTE_TOKEN' => 27,
			'MINUS_OPR' => 30,
			'TRUE_TOKEN' => 58,
			'DOUBLE_TOKEN' => 57,
			'INT_TOKEN' => 59,
			'FALSE_TOKEN' => 32,
			'NULL_TOKEN' => 62,
			'FLOAT_LITERAL' => 36,
			'POSTFIX_OPR' => 64,
			'LP_TOKEN' => 65,
			'IDENTIFIER' => 90,
			'CHAR_TOKEN' => 38,
			'PLUS_OPR' => 41,
			'THIS_TOKEN' => 67,
			'BOOLEAN_TOKEN' => 69,
			'CHAR_LITERAL' => 43,
			'PREFIX_OPR' => 45,
			'FLOAT_TOKEN' => 47,
			'NEW_TOKEN' => 73,
			'STRING_LITERAL' => 74,
			'SUPER_TOKEN' => 76
		},
		DEFAULT => -14,
		GOTOS => {
			'AdditiveOpr' => 50,
			'CastExpression' => 21,
			'UnaryExpressionNotPlusMinus' => 23,
			'RelationalExpression' => 24,
			'InstanceOfExpression' => 25,
			'MultiplicativeExpression' => 28,
			'EqualityExpression' => 56,
			'ParExpression' => 61,
			'Primary' => 33,
			'ExclusiveOrExpression' => 34,
			'ExpressionOrEmpty' => 510,
			'InclusiveOrExpression' => 35,
			'ConditionalOrExpression' => 63,
			'AllocationExpression' => 37,
			'Expression' => 473,
			'BasicType' => 40,
			'Literal' => 66,
			'UnaryOpr' => 42,
			'ConditionalAndExpression' => 70,
			'PrimaryExpression' => 44,
			'ShiftExpression' => 71,
			'UnaryExpression' => 48,
			'ConditionalExpression' => 113,
			'AdditiveExpression' => 75,
			'AndExpression' => 49,
			'PrimaryPrefix' => 77
		}
	},
	{#State 475
		ACTIONS => {
			'SHORT_TOKEN' => 22,
			'INTEGER_LITERAL' => 53,
			'LONG_TOKEN' => 26,
			'VOID_TOKEN' => 54,
			'BYTE_TOKEN' => 27,
			'MINUS_OPR' => 30,
			'TRUE_TOKEN' => 58,
			'DOUBLE_TOKEN' => 57,
			'INT_TOKEN' => 59,
			'FALSE_TOKEN' => 32,
			'NULL_TOKEN' => 62,
			'FLOAT_LITERAL' => 36,
			'POSTFIX_OPR' => 64,
			'LP_TOKEN' => 65,
			'IDENTIFIER' => 90,
			'CHAR_TOKEN' => 38,
			'PLUS_OPR' => 41,
			'THIS_TOKEN' => 67,
			'BOOLEAN_TOKEN' => 69,
			'CHAR_LITERAL' => 43,
			'PREFIX_OPR' => 45,
			'FLOAT_TOKEN' => 47,
			'NEW_TOKEN' => 73,
			'STRING_LITERAL' => 74,
			'SUPER_TOKEN' => 76
		},
		GOTOS => {
			'AdditiveOpr' => 50,
			'CastExpression' => 21,
			'UnaryExpressionNotPlusMinus' => 23,
			'RelationalExpression' => 24,
			'InstanceOfExpression' => 25,
			'MultiplicativeExpression' => 28,
			'EqualityExpression' => 56,
			'ParExpression' => 61,
			'Primary' => 33,
			'ExclusiveOrExpression' => 34,
			'InclusiveOrExpression' => 35,
			'ConditionalOrExpression' => 63,
			'AllocationExpression' => 37,
			'Expression' => 511,
			'BasicType' => 40,
			'Literal' => 66,
			'UnaryOpr' => 42,
			'ConditionalAndExpression' => 70,
			'PrimaryExpression' => 44,
			'ShiftExpression' => 71,
			'UnaryExpression' => 48,
			'ConditionalExpression' => 113,
			'AdditiveExpression' => 75,
			'AndExpression' => 49,
			'PrimaryPrefix' => 77
		}
	},
	{#State 476
		DEFAULT => -122
	},
	{#State 477
		DEFAULT => -155
	},
	{#State 478
		ACTIONS => {
			'CLN_TOKEN' => 512
		}
	},
	{#State 479
		ACTIONS => {
			'EQUAL_OPR' => 182,
			'ASSIGN_P_OPR' => 180,
			'ASSIGN_OPR' => 184
		},
		DEFAULT => -95,
		GOTOS => {
			'AssignmentOperator' => 181
		}
	},
	{#State 480
		ACTIONS => {
			'ASSERT_TOKEN' => 272,
			'FINAL_TOKEN' => 126,
			'DEFAULT_TOKEN' => -153,
			'SHORT_TOKEN' => 22,
			'LONG_TOKEN' => 26,
			'BYTE_TOKEN' => 27,
			'MINUS_OPR' => 30,
			'SMC_TOKEN' => 78,
			'NATIVE_TOKEN' => 129,
			'DO_TOKEN' => 264,
			'FALSE_TOKEN' => 32,
			'WHILE_TOKEN' => 274,
			'CASE_TOKEN' => -153,
			'STRICTFP_TOKEN' => 130,
			'FLOAT_LITERAL' => 36,
			'IDENTIFIER' => 277,
			'CHAR_TOKEN' => 38,
			'PLUS_OPR' => 41,
			'RCB_TOKEN' => -153,
			'ABSTRACT_TOKEN' => 132,
			'FOR_TOKEN' => 266,
			'CHAR_LITERAL' => 43,
			'PUBLIC_TOKEN' => 133,
			'SWITCH_TOKEN' => 268,
			'PREFIX_OPR' => 45,
			'FLOAT_TOKEN' => 47,
			'SYNCHRONIZED_TOKEN' => 269,
			'VOLATILE_TOKEN' => 136,
			'PROTECTED_TOKEN' => 137,
			'RETURN_TOKEN' => 270,
			'INTEGER_LITERAL' => 53,
			'THROW_TOKEN' => 279,
			'VOID_TOKEN' => 54,
			'LCB_TOKEN' => 55,
			'TRUE_TOKEN' => 58,
			'LINE_DECL_TOKEN' => 216,
			'DOUBLE_TOKEN' => 57,
			'INT_TOKEN' => 59,
			'CONTINUE_TOKEN' => 280,
			'NULL_TOKEN' => 62,
			'LP_TOKEN' => 65,
			'POSTFIX_OPR' => 64,
			'IF_TOKEN' => 285,
			'BREAK_TOKEN' => 283,
			'TRY_TOKEN' => 286,
			'THIS_TOKEN' => 67,
			'BOOLEAN_TOKEN' => 69,
			'PRIVATE_TOKEN' => 140,
			'STATIC_TOKEN' => 142,
			'TRANSIENT_TOKEN' => 143,
			'ATMARK_TOKEN' => 2,
			'NEW_TOKEN' => 73,
			'STRING_LITERAL' => 74,
			'SUPER_TOKEN' => 76
		},
		DEFAULT => -205,
		GOTOS => {
			'CastExpression' => 21,
			'UnaryExpressionNotPlusMinus' => 23,
			'StatementExpression' => 273,
			'RelationalExpression' => 24,
			'ClassOrInterfaceDeclaration' => 263,
			'InstanceOfExpression' => 25,
			'MultiplicativeExpression' => 28,
			'LcbToken' => 239,
			'Primary' => 275,
			'ExclusiveOrExpression' => 34,
			'InclusiveOrExpression' => 35,
			'Modifiers' => 265,
			'BlockStatement' => 329,
			'AllocationExpression' => 37,
			'BasicType' => 40,
			'UnaryOpr' => 42,
			'PrimaryExpression' => 44,
			'ModifiersOrEmpty' => 134,
			'UnaryExpression' => 48,
			'ConditionalExpression' => 113,
			'AndExpression' => 49,
			'AdditiveOpr' => 50,
			'Block' => 278,
			'EqualityExpression' => 56,
			'ParExpression' => 61,
			'Statement' => 282,
			'ConditionalOrExpression' => 63,
			'Expression' => 284,
			'Literal' => 66,
			'LineDecl' => 271,
			'SmcToken' => 287,
			'ConditionalAndExpression' => 70,
			'LocalVariableDeclarationStatement' => 288,
			'Modifier' => 141,
			'ShiftExpression' => 71,
			'Annotation' => 145,
			'AdditiveExpression' => 75,
			'PrimaryPrefix' => 77
		}
	},
	{#State 481
		DEFAULT => -126
	},
	{#State 482
		DEFAULT => -151
	},
	{#State 483
		DEFAULT => -145
	},
	{#State 484
		DEFAULT => -141
	},
	{#State 485
		ACTIONS => {
			'RP_TOKEN' => 513
		}
	},
	{#State 486
		DEFAULT => -340
	},
	{#State 487
		ACTIONS => {
			'DOT_TOKEN' => 514
		}
	},
	{#State 488
		ACTIONS => {
			'LSB_TOKEN' => 165
		},
		DEFAULT => -229
	},
	{#State 489
		ACTIONS => {
			'DOT_TOKEN' => 12
		},
		DEFAULT => -352
	},
	{#State 490
		DEFAULT => -270
	},
	{#State 491
		DEFAULT => -280
	},
	{#State 492
		ACTIONS => {
			'LP_TOKEN' => 100
		},
		DEFAULT => -105,
		GOTOS => {
			'Arguments' => 516,
			'ArgumentsOrEmpty' => 515
		}
	},
	{#State 493
		DEFAULT => -278
	},
	{#State 494
		ACTIONS => {
			'RCB_TOKEN' => 151
		},
		GOTOS => {
			'RcbToken' => 517
		}
	},
	{#State 495
		ACTIONS => {
			'FINAL_TOKEN' => 126,
			'SMC_TOKEN' => 78,
			'NATIVE_TOKEN' => 129,
			'STRICTFP_TOKEN' => 130,
			'RCB_TOKEN' => -314,
			'ABSTRACT_TOKEN' => 132,
			'PUBLIC_TOKEN' => 133,
			'SYNCHRONIZED_TOKEN' => 135,
			'VOLATILE_TOKEN' => 136,
			'PROTECTED_TOKEN' => 137,
			'LCB_TOKEN' => -239,
			'LINE_DECL_TOKEN' => 216,
			'PRIVATE_TOKEN' => 140,
			'STATIC_TOKEN' => 219,
			'TRANSIENT_TOKEN' => 143,
			'ATMARK_TOKEN' => 2
		},
		DEFAULT => -205,
		GOTOS => {
			'StaticOrEmpty' => 212,
			'LineDecl' => 217,
			'ClassBodyDeclarationsOrEmpty' => 518,
			'SmcToken' => 218,
			'ClassBodyDeclarations' => 519,
			'Modifier' => 141,
			'ModifiersOrEmpty' => 215,
			'Annotation' => 145,
			'ClassBodyDeclaration' => 211,
			'Modifiers' => 131
		}
	},
	{#State 496
		DEFAULT => -261,
		GOTOS => {
			'NameFinalzer' => 520
		}
	},
	{#State 497
		DEFAULT => -290
	},
	{#State 498
		DEFAULT => -330
	},
	{#State 499
		DEFAULT => -335
	},
	{#State 500
		DEFAULT => -334
	},
	{#State 501
		DEFAULT => -331
	},
	{#State 502
		ACTIONS => {
			'IDENTIFIER' => 521
		}
	},
	{#State 503
		ACTIONS => {
			'IDENTIFIER' => 522
		}
	},
	{#State 504
		DEFAULT => -332
	},
	{#State 505
		ACTIONS => {
			'CHAR_TOKEN' => 38,
			'IDENTIFIER' => 7,
			'SHORT_TOKEN' => 22,
			'LONG_TOKEN' => 26,
			'VOID_TOKEN' => 523,
			'BYTE_TOKEN' => 27,
			'BOOLEAN_TOKEN' => 69,
			'DOUBLE_TOKEN' => 57,
			'INT_TOKEN' => 59,
			'FLOAT_TOKEN' => 47
		},
		GOTOS => {
			'BasicType' => 148,
			'Type' => 524,
			'QualifiedIdentifier' => 146
		}
	},
	{#State 506
		DEFAULT => -304
	},
	{#State 507
		DEFAULT => -306
	},
	{#State 508
		DEFAULT => -157
	},
	{#State 509
		ACTIONS => {
			'SHORT_TOKEN' => 22,
			'INTEGER_LITERAL' => 53,
			'LONG_TOKEN' => 26,
			'VOID_TOKEN' => 54,
			'BYTE_TOKEN' => 27,
			'MINUS_OPR' => 30,
			'TRUE_TOKEN' => 58,
			'DOUBLE_TOKEN' => 57,
			'INT_TOKEN' => 59,
			'FALSE_TOKEN' => 32,
			'NULL_TOKEN' => 62,
			'FLOAT_LITERAL' => 36,
			'POSTFIX_OPR' => 64,
			'LP_TOKEN' => 65,
			'IDENTIFIER' => 90,
			'CHAR_TOKEN' => 38,
			'PLUS_OPR' => 41,
			'THIS_TOKEN' => 67,
			'BOOLEAN_TOKEN' => 69,
			'CHAR_LITERAL' => 43,
			'PREFIX_OPR' => 45,
			'FLOAT_TOKEN' => 47,
			'NEW_TOKEN' => 73,
			'STRING_LITERAL' => 74,
			'SUPER_TOKEN' => 76
		},
		DEFAULT => -164,
		GOTOS => {
			'AdditiveOpr' => 50,
			'CastExpression' => 21,
			'UnaryExpressionNotPlusMinus' => 23,
			'StatementExpression' => 526,
			'RelationalExpression' => 24,
			'InstanceOfExpression' => 25,
			'ForUpdate' => 527,
			'MultiplicativeExpression' => 28,
			'EqualityExpression' => 56,
			'ParExpression' => 61,
			'ForUpdateOrEmpty' => 525,
			'Primary' => 33,
			'ExclusiveOrExpression' => 34,
			'InclusiveOrExpression' => 35,
			'ConditionalOrExpression' => 63,
			'AllocationExpression' => 37,
			'Expression' => 284,
			'BasicType' => 40,
			'Literal' => 66,
			'UnaryOpr' => 42,
			'ConditionalAndExpression' => 70,
			'PrimaryExpression' => 44,
			'ShiftExpression' => 71,
			'UnaryExpression' => 48,
			'ConditionalExpression' => 113,
			'AdditiveExpression' => 75,
			'AndExpression' => 49,
			'PrimaryPrefix' => 77
		}
	},
	{#State 510
		ACTIONS => {
			'SMC_TOKEN' => 78
		},
		GOTOS => {
			'SmcToken' => 528
		}
	},
	{#State 511
		ACTIONS => {
			'EQUAL_OPR' => 182,
			'ASSIGN_P_OPR' => 180,
			'ASSIGN_OPR' => 184
		},
		DEFAULT => -169,
		GOTOS => {
			'AssignmentOperator' => 181
		}
	},
	{#State 512
		DEFAULT => -154
	},
	{#State 513
		ACTIONS => {
			'LCB_TOKEN' => 55
		},
		GOTOS => {
			'Block' => 529,
			'LcbToken' => 239
		}
	},
	{#State 514
		ACTIONS => {
			'IDENTIFIER' => 447
		},
		GOTOS => {
			'VariableDeclaratorId' => 530
		}
	},
	{#State 515
		ACTIONS => {
			'LCB_TOKEN' => 55
		},
		DEFAULT => -301,
		GOTOS => {
			'LcbToken' => 163,
			'ClassBody' => 162,
			'ClassBodyOrEmpty' => 531
		}
	},
	{#State 516
		DEFAULT => -106
	},
	{#State 517
		DEFAULT => -274
	},
	{#State 518
		DEFAULT => -284
	},
	{#State 519
		ACTIONS => {
			'FINAL_TOKEN' => 126,
			'SMC_TOKEN' => 78,
			'NATIVE_TOKEN' => 129,
			'STRICTFP_TOKEN' => 130,
			'RCB_TOKEN' => -315,
			'ABSTRACT_TOKEN' => 132,
			'PUBLIC_TOKEN' => 133,
			'SYNCHRONIZED_TOKEN' => 135,
			'VOLATILE_TOKEN' => 136,
			'PROTECTED_TOKEN' => 137,
			'LCB_TOKEN' => -239,
			'LINE_DECL_TOKEN' => 216,
			'PRIVATE_TOKEN' => 140,
			'STATIC_TOKEN' => 219,
			'TRANSIENT_TOKEN' => 143,
			'ATMARK_TOKEN' => 2
		},
		DEFAULT => -205,
		GOTOS => {
			'Modifier' => 141,
			'StaticOrEmpty' => 212,
			'LineDecl' => 217,
			'Annotation' => 145,
			'ModifiersOrEmpty' => 215,
			'ClassBodyDeclaration' => 241,
			'SmcToken' => 218,
			'Modifiers' => 131
		}
	},
	{#State 520
		DEFAULT => -256
	},
	{#State 521
		ACTIONS => {
			'LP_TOKEN' => 293
		},
		GOTOS => {
			'FormalParameters' => 533,
			'VoidInterfaceMethodDeclaratorRest' => 532
		}
	},
	{#State 522
		ACTIONS => {
			'EQUAL_OPR' => 539,
			'LSB_TOKEN' => 205,
			'LP_TOKEN' => 535
		},
		GOTOS => {
			'AnnotationMethodRest' => 542,
			'InterfaceMethodDeclaratorRest' => 538,
			'ConstantDeclaratorRest' => 536,
			'ArrayDim' => 540,
			'InterfaceMethodOrFieldRest' => 534,
			'ConstantDeclaratorsRest' => 537,
			'FormalParameters' => 541
		}
	},
	{#State 523
		ACTIONS => {
			'IDENTIFIER' => 543
		}
	},
	{#State 524
		ACTIONS => {
			'IDENTIFIER' => 544
		}
	},
	{#State 525
		DEFAULT => -161
	},
	{#State 526
		ACTIONS => {
			'CM_TOKEN' => 421
		},
		DEFAULT => -158,
		GOTOS => {
			'MoreStatementExpressions' => 422,
			'MoreStatementExpressionsOrEmpty' => 545
		}
	},
	{#State 527
		DEFAULT => -165
	},
	{#State 528
		ACTIONS => {
			'SHORT_TOKEN' => 22,
			'INTEGER_LITERAL' => 53,
			'LONG_TOKEN' => 26,
			'VOID_TOKEN' => 54,
			'BYTE_TOKEN' => 27,
			'MINUS_OPR' => 30,
			'TRUE_TOKEN' => 58,
			'DOUBLE_TOKEN' => 57,
			'INT_TOKEN' => 59,
			'FALSE_TOKEN' => 32,
			'NULL_TOKEN' => 62,
			'FLOAT_LITERAL' => 36,
			'POSTFIX_OPR' => 64,
			'LP_TOKEN' => 65,
			'IDENTIFIER' => 90,
			'CHAR_TOKEN' => 38,
			'PLUS_OPR' => 41,
			'THIS_TOKEN' => 67,
			'BOOLEAN_TOKEN' => 69,
			'CHAR_LITERAL' => 43,
			'PREFIX_OPR' => 45,
			'FLOAT_TOKEN' => 47,
			'NEW_TOKEN' => 73,
			'STRING_LITERAL' => 74,
			'SUPER_TOKEN' => 76
		},
		DEFAULT => -164,
		GOTOS => {
			'AdditiveOpr' => 50,
			'CastExpression' => 21,
			'UnaryExpressionNotPlusMinus' => 23,
			'StatementExpression' => 526,
			'RelationalExpression' => 24,
			'InstanceOfExpression' => 25,
			'ForUpdate' => 527,
			'MultiplicativeExpression' => 28,
			'EqualityExpression' => 56,
			'ParExpression' => 61,
			'ForUpdateOrEmpty' => 546,
			'Primary' => 33,
			'ExclusiveOrExpression' => 34,
			'InclusiveOrExpression' => 35,
			'ConditionalOrExpression' => 63,
			'AllocationExpression' => 37,
			'Expression' => 284,
			'BasicType' => 40,
			'Literal' => 66,
			'UnaryOpr' => 42,
			'ConditionalAndExpression' => 70,
			'PrimaryExpression' => 44,
			'ShiftExpression' => 71,
			'UnaryExpression' => 48,
			'ConditionalExpression' => 113,
			'AdditiveExpression' => 75,
			'AndExpression' => 49,
			'PrimaryPrefix' => 77
		}
	},
	{#State 529
		DEFAULT => -148
	},
	{#State 530
		DEFAULT => -359
	},
	{#State 531
		DEFAULT => -282,
		GOTOS => {
			'@7-5' => 547
		}
	},
	{#State 532
		DEFAULT => -333
	},
	{#State 533
		ACTIONS => {
			'THROWS_TOKEN' => 346
		},
		DEFAULT => -349,
		GOTOS => {
			'ThrowsQIdentOrEmpty' => 548
		}
	},
	{#State 534
		DEFAULT => -336
	},
	{#State 535
		ACTIONS => {
			'VOLATILE_TOKEN' => 136,
			'FINAL_TOKEN' => 126,
			'PROTECTED_TOKEN' => 137,
			'RP_TOKEN' => 549,
			'NATIVE_TOKEN' => 129,
			'STRICTFP_TOKEN' => 130,
			'ABSTRACT_TOKEN' => 132,
			'PUBLIC_TOKEN' => 133,
			'PRIVATE_TOKEN' => 140,
			'STATIC_TOKEN' => 142,
			'ATMARK_TOKEN' => 2,
			'TRANSIENT_TOKEN' => 143,
			'SYNCHRONIZED_TOKEN' => 135
		},
		DEFAULT => -205,
		GOTOS => {
			'Modifier' => 141,
			'FormalParameterDeclsList' => 342,
			'Annotation' => 145,
			'ModifiersOrEmpty' => 343,
			'Modifiers' => 131,
			'FormalParameterDecls' => 341
		}
	},
	{#State 536
		DEFAULT => -209
	},
	{#State 537
		ACTIONS => {
			'CM_TOKEN' => 550,
			'SMC_TOKEN' => 78
		},
		GOTOS => {
			'SmcToken' => 551
		}
	},
	{#State 538
		DEFAULT => -338
	},
	{#State 539
		ACTIONS => {
			'SHORT_TOKEN' => 22,
			'INTEGER_LITERAL' => 53,
			'LONG_TOKEN' => 26,
			'VOID_TOKEN' => 54,
			'BYTE_TOKEN' => 27,
			'MINUS_OPR' => 30,
			'LCB_TOKEN' => 55,
			'TRUE_TOKEN' => 58,
			'DOUBLE_TOKEN' => 57,
			'INT_TOKEN' => 59,
			'FALSE_TOKEN' => 32,
			'NULL_TOKEN' => 62,
			'FLOAT_LITERAL' => 36,
			'POSTFIX_OPR' => 64,
			'LP_TOKEN' => 65,
			'IDENTIFIER' => 90,
			'CHAR_TOKEN' => 38,
			'PLUS_OPR' => 41,
			'THIS_TOKEN' => 67,
			'BOOLEAN_TOKEN' => 69,
			'CHAR_LITERAL' => 43,
			'PREFIX_OPR' => 45,
			'FLOAT_TOKEN' => 47,
			'NEW_TOKEN' => 73,
			'STRING_LITERAL' => 74,
			'SUPER_TOKEN' => 76
		},
		GOTOS => {
			'AdditiveOpr' => 50,
			'CastExpression' => 21,
			'UnaryExpressionNotPlusMinus' => 23,
			'RelationalExpression' => 24,
			'InstanceOfExpression' => 25,
			'MultiplicativeExpression' => 28,
			'EqualityExpression' => 56,
			'LcbToken' => 166,
			'ArrayInitializer' => 221,
			'ParExpression' => 61,
			'Primary' => 33,
			'ExclusiveOrExpression' => 34,
			'InclusiveOrExpression' => 35,
			'ConditionalOrExpression' => 63,
			'AllocationExpression' => 37,
			'Expression' => 224,
			'BasicType' => 40,
			'Literal' => 66,
			'UnaryOpr' => 42,
			'VariableInitializer' => 552,
			'ConditionalAndExpression' => 70,
			'PrimaryExpression' => 44,
			'ShiftExpression' => 71,
			'UnaryExpression' => 48,
			'ConditionalExpression' => 113,
			'AdditiveExpression' => 75,
			'AndExpression' => 49,
			'PrimaryPrefix' => 77
		}
	},
	{#State 540
		ACTIONS => {
			'EQUAL_OPR' => 553,
			'LSB_TOKEN' => 165
		}
	},
	{#State 541
		ACTIONS => {
			'LSB_TOKEN' => 205
		},
		DEFAULT => -90,
		GOTOS => {
			'ArrayDim' => 207,
			'ArrayDimOrEmpty' => 554
		}
	},
	{#State 542
		DEFAULT => -339
	},
	{#State 543
		ACTIONS => {
			'LP_TOKEN' => 293
		},
		GOTOS => {
			'InterfaceMethodDeclaratorRest' => 555,
			'FormalParameters' => 541
		}
	},
	{#State 544
		ACTIONS => {
			'LP_TOKEN' => 293
		},
		GOTOS => {
			'InterfaceMethodDeclaratorRest' => 556,
			'FormalParameters' => 541
		}
	},
	{#State 545
		DEFAULT => -361
	},
	{#State 546
		DEFAULT => -168
	},
	{#State 547
		DEFAULT => -261,
		GOTOS => {
			'NameFinalzer' => 557
		}
	},
	{#State 548
		ACTIONS => {
			'SMC_TOKEN' => 78
		},
		GOTOS => {
			'SmcToken' => 558
		}
	},
	{#State 549
		ACTIONS => {
			'DEFAULT_TOKEN' => 560
		},
		DEFAULT => -353,
		GOTOS => {
			'DefaultValue' => 559
		}
	},
	{#State 550
		ACTIONS => {
			'IDENTIFIER' => 562
		},
		GOTOS => {
			'ConstantDeclarator' => 561
		}
	},
	{#State 551
		DEFAULT => -337
	},
	{#State 552
		DEFAULT => -217
	},
	{#State 553
		ACTIONS => {
			'SHORT_TOKEN' => 22,
			'INTEGER_LITERAL' => 53,
			'LONG_TOKEN' => 26,
			'VOID_TOKEN' => 54,
			'BYTE_TOKEN' => 27,
			'MINUS_OPR' => 30,
			'LCB_TOKEN' => 55,
			'TRUE_TOKEN' => 58,
			'DOUBLE_TOKEN' => 57,
			'INT_TOKEN' => 59,
			'FALSE_TOKEN' => 32,
			'NULL_TOKEN' => 62,
			'FLOAT_LITERAL' => 36,
			'POSTFIX_OPR' => 64,
			'LP_TOKEN' => 65,
			'IDENTIFIER' => 90,
			'CHAR_TOKEN' => 38,
			'PLUS_OPR' => 41,
			'THIS_TOKEN' => 67,
			'BOOLEAN_TOKEN' => 69,
			'CHAR_LITERAL' => 43,
			'PREFIX_OPR' => 45,
			'FLOAT_TOKEN' => 47,
			'NEW_TOKEN' => 73,
			'STRING_LITERAL' => 74,
			'SUPER_TOKEN' => 76
		},
		GOTOS => {
			'AdditiveOpr' => 50,
			'CastExpression' => 21,
			'UnaryExpressionNotPlusMinus' => 23,
			'RelationalExpression' => 24,
			'InstanceOfExpression' => 25,
			'MultiplicativeExpression' => 28,
			'EqualityExpression' => 56,
			'LcbToken' => 166,
			'ArrayInitializer' => 221,
			'ParExpression' => 61,
			'Primary' => 33,
			'ExclusiveOrExpression' => 34,
			'InclusiveOrExpression' => 35,
			'ConditionalOrExpression' => 63,
			'AllocationExpression' => 37,
			'Expression' => 224,
			'BasicType' => 40,
			'Literal' => 66,
			'UnaryOpr' => 42,
			'VariableInitializer' => 563,
			'ConditionalAndExpression' => 70,
			'PrimaryExpression' => 44,
			'ShiftExpression' => 71,
			'UnaryExpression' => 48,
			'ConditionalExpression' => 113,
			'AdditiveExpression' => 75,
			'AndExpression' => 49,
			'PrimaryPrefix' => 77
		}
	},
	{#State 554
		ACTIONS => {
			'THROWS_TOKEN' => 346
		},
		DEFAULT => -349,
		GOTOS => {
			'ThrowsQIdentOrEmpty' => 564
		}
	},
	{#State 555
		DEFAULT => -346
	},
	{#State 556
		DEFAULT => -345
	},
	{#State 557
		DEFAULT => -283
	},
	{#State 558
		DEFAULT => -347
	},
	{#State 559
		DEFAULT => -297
	},
	{#State 560
		ACTIONS => {
			'SHORT_TOKEN' => 22,
			'INTEGER_LITERAL' => 53,
			'LONG_TOKEN' => 26,
			'VOID_TOKEN' => 54,
			'BYTE_TOKEN' => 27,
			'MINUS_OPR' => 30,
			'LCB_TOKEN' => 55,
			'TRUE_TOKEN' => 58,
			'DOUBLE_TOKEN' => 57,
			'INT_TOKEN' => 59,
			'FALSE_TOKEN' => 32,
			'NULL_TOKEN' => 62,
			'FLOAT_LITERAL' => 36,
			'POSTFIX_OPR' => 64,
			'LP_TOKEN' => 65,
			'IDENTIFIER' => 90,
			'CHAR_TOKEN' => 38,
			'PLUS_OPR' => 41,
			'THIS_TOKEN' => 67,
			'BOOLEAN_TOKEN' => 69,
			'CHAR_LITERAL' => 43,
			'PREFIX_OPR' => 45,
			'ATMARK_TOKEN' => 2,
			'FLOAT_TOKEN' => 47,
			'NEW_TOKEN' => 73,
			'STRING_LITERAL' => 74,
			'SUPER_TOKEN' => 76
		},
		GOTOS => {
			'AdditiveOpr' => 50,
			'CastExpression' => 21,
			'UnaryExpressionNotPlusMinus' => 23,
			'RelationalExpression' => 24,
			'InstanceOfExpression' => 25,
			'ElementValueArrayInitializer' => 51,
			'MultiplicativeExpression' => 28,
			'EqualityExpression' => 56,
			'LcbToken' => 31,
			'ParExpression' => 61,
			'Primary' => 33,
			'ExclusiveOrExpression' => 34,
			'InclusiveOrExpression' => 35,
			'ConditionalOrExpression' => 63,
			'AllocationExpression' => 37,
			'BasicType' => 40,
			'Literal' => 66,
			'UnaryOpr' => 42,
			'ElementValue' => 565,
			'ConditionalAndExpression' => 70,
			'PrimaryExpression' => 44,
			'ShiftExpression' => 71,
			'ConditionalExpression' => 46,
			'UnaryExpression' => 48,
			'Annotation' => 72,
			'AdditiveExpression' => 75,
			'AndExpression' => 49,
			'PrimaryPrefix' => 77
		}
	},
	{#State 561
		DEFAULT => -210
	},
	{#State 562
		ACTIONS => {
			'EQUAL_OPR' => 539,
			'LSB_TOKEN' => 205
		},
		GOTOS => {
			'ConstantDeclaratorRest' => 566,
			'ArrayDim' => 540
		}
	},
	{#State 563
		DEFAULT => -218
	},
	{#State 564
		ACTIONS => {
			'SMC_TOKEN' => 78
		},
		GOTOS => {
			'SmcToken' => 567
		}
	},
	{#State 565
		DEFAULT => -298
	},
	{#State 566
		DEFAULT => -213
	},
	{#State 567
		DEFAULT => -344
	}
],
                                  yyrules  =>
[
	[#Rule 0
		 '$start', 2, undef
	],
	[#Rule 1
		 'Literal', 1, undef
	],
	[#Rule 2
		 'Literal', 1, undef
	],
	[#Rule 3
		 'Literal', 1, undef
	],
	[#Rule 4
		 'Literal', 1,
sub {
        $_[1]->{TOKEN} =~ s{\A"}{}xms;
        $_[1]->{TOKEN} =~ s{"\z}{}xms;
        $_[1]
    }
	],
	[#Rule 5
		 'Literal', 1, undef
	],
	[#Rule 6
		 'Literal', 1, undef
	],
	[#Rule 7
		 'Literal', 1, undef
	],
	[#Rule 8
		 'Expression', 1,
sub {
        ['N_Expression', $_[1]];
    }
	],
	[#Rule 9
		 'Expression', 3,
sub {
        my $leftside = pop(@{$_[1]});
        push(@{$_[1]}, [ 'N_AssignmentOperator', $leftside, $_[2], $_[3] ]);
        $_[1]
    }
	],
	[#Rule 10
		 'ExpressionList', 1,
sub {
        ['N_ExpressionList', $_[1]]
    }
	],
	[#Rule 11
		 'ExpressionList', 3,
sub {
        push(@{$_[1]}, $_[2]);
        push(@{$_[1]}, $_[3]);
        $_[1];
    }
	],
	[#Rule 12
		 'ExpressionListOrEmpty', 0, undef
	],
	[#Rule 13
		 'ExpressionListOrEmpty', 1, undef
	],
	[#Rule 14
		 'ExpressionOrEmpty', 0, undef
	],
	[#Rule 15
		 'ExpressionOrEmpty', 1, undef
	],
	[#Rule 16
		 'ConditionalExpression', 1, undef
	],
	[#Rule 17
		 'ConditionalExpression', 2,
sub {
        ['N_ConditionalOrExpression', $_[1], @{$_[2]} ]
    }
	],
	[#Rule 18
		 'ConditionalExpressionRest', 4,
sub {
        [$_[1], $_[2], $_[3], $_[4]]
    }
	],
	[#Rule 19
		 'ConditionalOrExpression', 1, undef
	],
	[#Rule 20
		 'ConditionalOrExpression', 3,
sub {
        ['N_ConditionalOrExpression', $_[1], $_[2], $_[3]]
    }
	],
	[#Rule 21
		 'ConditionalAndExpression', 1, undef
	],
	[#Rule 22
		 'ConditionalAndExpression', 3,
sub { 
        ['N_ConditionalAndExpression', $_[1], $_[2], $_[3]]
    }
	],
	[#Rule 23
		 'InclusiveOrExpression', 1, undef
	],
	[#Rule 24
		 'InclusiveOrExpression', 3,
sub {
        ['N_InclusiveOrExpression', $_[1], $_[2], $_[3]]
    }
	],
	[#Rule 25
		 'ExclusiveOrExpression', 1, undef
	],
	[#Rule 26
		 'ExclusiveOrExpression', 3,
sub {
        ['N_ExclusiveOrExpression', $_[1], $_[2], $_[3]]
    }
	],
	[#Rule 27
		 'AndExpression', 1, undef
	],
	[#Rule 28
		 'AndExpression', 3,
sub {
        ['N_AndExpression', $_[1], $_[2], $_[3]]
    }
	],
	[#Rule 29
		 'EqualityExpression', 1, undef
	],
	[#Rule 30
		 'EqualityExpression', 3,
sub {
        ['N_EqualityExpression', $_[1], $_[2], $_[3]]
    }
	],
	[#Rule 31
		 'InstanceOfExpression', 1, undef
	],
	[#Rule 32
		 'InstanceOfExpression', 3,
sub {
        ['N_InstanceOfExpression', $_[1], $_[2], $_[3]]
    }
	],
	[#Rule 33
		 'RelationalExpression', 1, undef
	],
	[#Rule 34
		 'RelationalExpression', 3,
sub {
        ['N_RelationalExpression', $_[1], $_[2], $_[3]]
    }
	],
	[#Rule 35
		 'RelationalOpr', 1, undef
	],
	[#Rule 36
		 'RelationalOpr', 1, undef
	],
	[#Rule 37
		 'RelationalOpr', 1, undef
	],
	[#Rule 38
		 'ShiftExpression', 1, undef
	],
	[#Rule 39
		 'ShiftExpression', 3,
sub {
        ['N_ShiftExpression', $_[1], $_[2], $_[3]]
    }
	],
	[#Rule 40
		 'ShiftOpr', 1, undef
	],
	[#Rule 41
		 'ShiftOpr', 2,
sub { $_[1]->{KEYWORD} = 'SHIFT_OPR'; $_[1]->{TOKEN} = '>>'; $_[1]}
	],
	[#Rule 42
		 'ShiftOpr', 3,
sub { $_[1]->{KEYWORD} = 'SHIFT_OPR'; $_[1]->{TOKEN} = '>>>'; $_[1]}
	],
	[#Rule 43
		 'AdditiveExpression', 1, undef
	],
	[#Rule 44
		 'AdditiveExpression', 3,
sub {
        ['N_AdditiveExpression', $_[1], $_[2], $_[3]]
    }
	],
	[#Rule 45
		 'AdditiveOpr', 1, undef
	],
	[#Rule 46
		 'AdditiveOpr', 1, undef
	],
	[#Rule 47
		 'MultiplicativeExpression', 1, undef
	],
	[#Rule 48
		 'MultiplicativeExpression', 3,
sub {
        ['N_MultiplicativeExpression', $_[1], $_[2], $_[3]]
    }
	],
	[#Rule 49
		 'MultiplicativeOpr', 1, undef
	],
	[#Rule 50
		 'MultiplicativeOpr', 1, undef
	],
	[#Rule 51
		 'UnaryExpression', 2,
sub {$_[2]}
	],
	[#Rule 52
		 'UnaryExpression', 1, undef
	],
	[#Rule 53
		 'UnaryOpr', 1, undef
	],
	[#Rule 54
		 'UnaryOpr', 1, undef
	],
	[#Rule 55
		 'UnaryExpressionNotPlusMinus', 2,
sub {$_[2]}
	],
	[#Rule 56
		 'UnaryExpressionNotPlusMinus', 1, undef
	],
	[#Rule 57
		 'UnaryExpressionNotPlusMinus', 1, undef
	],
	[#Rule 58
		 'UnaryExpressionNotPlusMinus', 2,
sub {$_[1]}
	],
	[#Rule 59
		 'CastExpression', 4,
sub {['N_CastExpression', $_[4]]}
	],
	[#Rule 60
		 'CastExpression', 4,
sub {['N_CastExpression', $_[4]]}
	],
	[#Rule 61
		 'PrimaryExpression', 1, undef
	],
	[#Rule 62
		 'Primary', 1,
sub {
        ['N_Primary', $_[1]];
    }
	],
	[#Rule 63
		 'Primary', 2,
sub {
        my $suffixnode = $_[2];
        if($suffixnode) {
            if(ref($suffixnode) eq 'ARRAY' 
                and equal_nodetype($suffixnode, 'N_Arguments')) {
            
                my $primary = pop(@{$_[1]});
                push(@{$_[1]}, ['N_MethodInvocation', $primary, $suffixnode]);

            } else {
                push(@{$_[1]}, @{$suffixnode} );
            }
        }
        
        $_[1]
    }
	],
	[#Rule 64
		 'PrimaryPrefix', 1, undef
	],
	[#Rule 65
		 'PrimaryPrefix', 1, undef
	],
	[#Rule 66
		 'PrimaryPrefix', 1, undef
	],
	[#Rule 67
		 'PrimaryPrefix', 1, undef
	],
	[#Rule 68
		 'PrimaryPrefix', 1, undef
	],
	[#Rule 69
		 'PrimaryPrefix', 1, undef
	],
	[#Rule 70
		 'PrimaryPrefix', 1, undef
	],
	[#Rule 71
		 'PrimaryPrefix', 1, undef
	],
	[#Rule 72
		 'PrimarySuffix', 2,
sub {shift && \@_ }
	],
	[#Rule 73
		 'PrimarySuffix', 2,
sub {shift && \@_ }
	],
	[#Rule 74
		 'PrimarySuffix', 2,
sub {shift && \@_ }
	],
	[#Rule 75
		 'PrimarySuffix', 2,
sub {shift && \@_ }
	],
	[#Rule 76
		 'PrimarySuffix', 2,
sub {shift && \@_ }
	],
	[#Rule 77
		 'PrimarySuffix', 1,
sub {shift && \@_ }
	],
	[#Rule 78
		 'PrimarySuffix', 2,
sub {shift && \@_ }
	],
	[#Rule 79
		 'PrimarySuffix', 2,
sub {
        if(defined $_[2]) {
            my $classinfo = create_classinfo(['inner', $G_static_number++ ], 
                                    $_[2]->{METHOD}, $_[2]->{VARIABLE});
            push(@{$G_fileinfo_ref->classlist()}, $classinfo);
        }
        $_[1];
    }
	],
	[#Rule 80
		 'AllocationExpression', 2,
sub { [$_[1], $_[2]] }
	],
	[#Rule 81
		 'AllocationExpression', 2,
sub { [$_[1], $_[2]] }
	],
	[#Rule 82
		 'ArrayInitializerOrEmpty', 0, undef
	],
	[#Rule 83
		 'ArrayInitializerOrEmpty', 1,
sub {shift && \@_ }
	],
	[#Rule 84
		 'ExprInDim', 3,
sub {
        shift && \@_
    }
	],
	[#Rule 85
		 'AssignmentOperator', 1, undef
	],
	[#Rule 86
		 'AssignmentOperator', 1, undef
	],
	[#Rule 87
		 'AssignmentOperator', 1, undef
	],
	[#Rule 88
		 'Type', 2,
sub { ['N_Type', $_[1], $_[2]]; }
	],
	[#Rule 89
		 'Type', 2,
sub { ['N_Type', $_[1], $_[2]] }
	],
	[#Rule 90
		 'ArrayDimOrEmpty', 0, undef
	],
	[#Rule 91
		 'ArrayDimOrEmpty', 1, undef
	],
	[#Rule 92
		 'ArrayDim', 2,
sub { ['N_ArrayDim', $_[1], $_[2]] }
	],
	[#Rule 93
		 'ArrayDim', 3,
sub { push(@{$_[1]}, $_[2]); push(@{$_[1]}, $_[3]); $_[1] }
	],
	[#Rule 94
		 'StatementExpression', 1, undef
	],
	[#Rule 95
		 'ConstantExpression', 1, undef
	],
	[#Rule 96
		 'BasicType', 1, undef
	],
	[#Rule 97
		 'BasicType', 1, undef
	],
	[#Rule 98
		 'BasicType', 1, undef
	],
	[#Rule 99
		 'BasicType', 1, undef
	],
	[#Rule 100
		 'BasicType', 1, undef
	],
	[#Rule 101
		 'BasicType', 1, undef
	],
	[#Rule 102
		 'BasicType', 1, undef
	],
	[#Rule 103
		 'BasicType', 1, undef
	],
	[#Rule 104
		 'Arguments', 3,
sub {
        shift && ['N_Arguments', @_]
    }
	],
	[#Rule 105
		 'ArgumentsOrEmpty', 0, undef
	],
	[#Rule 106
		 'ArgumentsOrEmpty', 1, undef
	],
	[#Rule 107
		 'ParExpression', 3,
sub { ['N_ParExpression', $_[2]] }
	],
	[#Rule 108
		 'Block', 2,
sub {
        [ 'N_ScopeInfo', create_scopeinfo(['N_BlockStatements']) ]
    }
	],
	[#Rule 109
		 'Block', 3,
sub {
        [ 'N_ScopeInfo', create_scopeinfo($_[2]) ]
    }
	],
	[#Rule 110
		 'BlockStatements', 1,
sub {
        my $blockstmts = ['N_BlockStatements'];
        defined $_[1] and push(@{$blockstmts}, $_[1]);
        $blockstmts;
    }
	],
	[#Rule 111
		 'BlockStatements', 2,
sub {
        defined $_[2] and push(@{$_[1]}, $_[2]);
        $_[1];
    }
	],
	[#Rule 112
		 'BlockStatement', 1, undef
	],
	[#Rule 113
		 'BlockStatement', 1, undef
	],
	[#Rule 114
		 'BlockStatement', 1, undef
	],
	[#Rule 115
		 'BlockStatement', 1, undef
	],
	[#Rule 116
		 'LineDecl', 3,
sub {
        $_[0]->getLexer()->setLine($_[2]->{TOKEN});
        undef;
    }
	],
	[#Rule 117
		 'LocalVariableDeclarationStatement', 3,
sub {
        shift && ['N_LocalVariableDeclarationStatement', @_]
    }
	],
	[#Rule 118
		 'LocalVariableDeclarationStatement', 4,
sub {
        shift && ['N_LocalVariableDeclarationStatement', @_]
    }
	],
	[#Rule 119
		 'Statement', 1, undef
	],
	[#Rule 120
		 'Statement', 4,
sub {
        ['N_assert', create_linenode($_[1]), $_[2], ['N_Delimiter'], $_[3]]
    }
	],
	[#Rule 121
		 'Statement', 4,
sub {
        ['N_if', create_linenode($_[1]),  $_[2], ['N_Delimiter'], $_[3], ['N_Delimiter'], $_[4]]
    }
	],
	[#Rule 122
		 'Statement', 5,
sub {
        ['N_for', create_linenode($_[1]),  $_[3], ['N_Delimiter'], $_[5]]
    }
	],
	[#Rule 123
		 'Statement', 3,
sub {
        ['N_while', create_linenode($_[1]), $_[2], ['N_Delimiter'], $_[3]]
    }
	],
	[#Rule 124
		 'Statement', 5,
sub {
        ['N_while', create_linenode($_[1]), $_[2], ['N_Delimiter'], create_addcode(), create_linenode($_[3]), $_[4]]
    }
	],
	[#Rule 125
		 'Statement', 3,
sub {
        ['N_try',  create_linenode($_[1]), $_[2], $_[3]]
    }
	],
	[#Rule 126
		 'Statement', 5,
sub {
        ['N_switch',  create_linenode($_[1]), $_[2], ['N_ScopeInfo', create_scopeinfo($_[4])]]
    }
	],
	[#Rule 127
		 'Statement', 3,
sub {
        ['N_synchronized',  create_linenode($_[1]), $_[2], $_[3]]
    }
	],
	[#Rule 128
		 'Statement', 2,
sub { undef }
	],
	[#Rule 129
		 'Statement', 3,
sub {
        ['N_return',  create_linenode($_[1]), $_[2]]
    }
	],
	[#Rule 130
		 'Statement', 3,
sub { ['N_throw',  create_linenode($_[1]), $_[2]] }
	],
	[#Rule 131
		 'Statement', 2,
sub { undef }
	],
	[#Rule 132
		 'Statement', 3,
sub { undef }
	],
	[#Rule 133
		 'Statement', 2,
sub { undef }
	],
	[#Rule 134
		 'Statement', 3,
sub { undef }
	],
	[#Rule 135
		 'Statement', 1,
sub { undef }
	],
	[#Rule 136
		 'Statement', 2,
sub { $_[1] }
	],
	[#Rule 137
		 'Statement', 3,
sub { $_[3] }
	],
	[#Rule 138
		 'AssertExpOrEmpty', 0, undef
	],
	[#Rule 139
		 'AssertExpOrEmpty', 2,
sub { $_[2] }
	],
	[#Rule 140
		 'CatchesOrFinally', 1, undef
	],
	[#Rule 141
		 'CatchesOrFinally', 3,
sub {
        my $result = ['N_finally', $_[3]];
        if(defined($_[1])) {
            push(@{$_[1]}, $result);
            $result = $_[1];
        }
        $result
    }
	],
	[#Rule 142
		 'CatchesOrEmpty', 0, undef
	],
	[#Rule 143
		 'CatchesOrEmpty', 1, undef
	],
	[#Rule 144
		 'ElseStatementOrEmpty', 0, undef
	],
	[#Rule 145
		 'ElseStatementOrEmpty', 2,
sub { ['N_else', create_addcode(), create_linenode($_[1]), $_[2]] }
	],
	[#Rule 146
		 'Catches', 1,
sub { ['N_catches', $_[1]] }
	],
	[#Rule 147
		 'Catches', 2,
sub { push(@{$_[1]}, $_[2]) ; $_[1] }
	],
	[#Rule 148
		 'CatchClause', 5,
sub {
         ['N_catch', $_[5] ]
     }
	],
	[#Rule 149
		 'SwitchBlockStatementGroups', 0,
sub { ['N_SwitchBlockStatementGroups'] }
	],
	[#Rule 150
		 'SwitchBlockStatementGroups', 1,
sub {
        shift @{$_[1]};
        ['N_SwitchBlockStatementGroups', @{$_[1]}];
    }
	],
	[#Rule 151
		 'SwitchBlockStatementGroups', 2,
sub {
        my $result = $_[1];
        my $last_node = $result->[-1];
        my $linenode = undef;
        if(equal_nodetype($last_node, 'N_MetaNode')) {
            $linenode = $last_node;
        }
        
        if(defined $linenode) {
            if($_[2]->[0] eq 'stmt') {
                shift @{$_[2]};
                my $switch_label = $_[2]->[0];
                $switch_label->[1] = pop(@{$result});
                push(@{$result}, @{$_[2]});
            }
        } else {
            shift @{$_[2]};
            push(@{$result}, @{$_[2]});
        }
        
        $result;
    }
	],
	[#Rule 152
		 'SwitchBlockStatementGroup', 1,
sub { ['line', $_[1]] }
	],
	[#Rule 153
		 'SwitchBlockStatementGroup', 2,
sub {
        shift @{$_[2]};
        my $first_block_stmt = shift @{$_[2]};
        [ 'stmt', [ 'N_SwitchLabel', $_[1],  $first_block_stmt ], @{$_[2]} ]
    }
	],
	[#Rule 154
		 'SwitchLabel', 3,
sub { create_linenode($_[1]) }
	],
	[#Rule 155
		 'SwitchLabel', 2,
sub { create_linenode($_[1]) }
	],
	[#Rule 156
		 'MoreStatementExpressions', 2,
sub { ['N_MoreStatementExpressions', $_[1], $_[2]] }
	],
	[#Rule 157
		 'MoreStatementExpressions', 3,
sub {
        push(@{$_[1]}, $_[2]); push(@{$_[1]}, $_[3]);
        $_[1]
    }
	],
	[#Rule 158
		 'MoreStatementExpressionsOrEmpty', 0, undef
	],
	[#Rule 159
		 'MoreStatementExpressionsOrEmpty', 1, undef
	],
	[#Rule 160
		 'ForControl', 1, undef
	],
	[#Rule 161
		 'ForControl', 5,
sub {
        my @result = ('N_ForControl');
        defined $_[1] and do { push(@result, $_[1]);  };
        defined $_[3] and do { push(@result, create_addcode()); push(@result, $_[3]); };
        defined $_[5] and do { push(@result, create_addcode()); push(@result, $_[5]); };
        \@result;
    }
	],
	[#Rule 162
		 'ForInitOrEmpty', 0, undef
	],
	[#Rule 163
		 'ForInitOrEmpty', 1, undef
	],
	[#Rule 164
		 'ForUpdateOrEmpty', 0, undef
	],
	[#Rule 165
		 'ForUpdateOrEmpty', 1, undef
	],
	[#Rule 166
		 'ForVarControl', 2,
sub { create_forvar_control($_[1], $_[2]) }
	],
	[#Rule 167
		 'ForVarControl', 3,
sub { create_forvar_control($_[2], $_[3]) }
	],
	[#Rule 168
		 'ForVarControlRest', 5,
sub {
              ['N_NormalFor', $_[1], $_[3], $_[5]]
          }
	],
	[#Rule 169
		 'ForVarControlRest', 3,
sub { ['N_ExpandFor', $_[1], $_[3]] }
	],
	[#Rule 170
		 'Annotations', 1,
sub { undef }
	],
	[#Rule 171
		 'Annotations', 2,
sub { undef }
	],
	[#Rule 172
		 'Annotation', 3, undef
	],
	[#Rule 173
		 'AnnotationBodyOrEmpty', 0, undef
	],
	[#Rule 174
		 'AnnotationBodyOrEmpty', 2, undef
	],
	[#Rule 175
		 'AnnotationBodyOrEmpty', 3, undef
	],
	[#Rule 176
		 'AnnotationValueList', 1, undef
	],
	[#Rule 177
		 'AnnotationValueList', 3, undef
	],
	[#Rule 178
		 'AnnotationValue', 1, undef
	],
	[#Rule 179
		 'AnnotationValue', 3, undef
	],
	[#Rule 180
		 'ElementValue', 1, undef
	],
	[#Rule 181
		 'ElementValue', 1, undef
	],
	[#Rule 182
		 'ElementValue', 1, undef
	],
	[#Rule 183
		 'ElementValueArrayInitializer', 3, undef
	],
	[#Rule 184
		 'ElementValuesOrEmpty', 0, undef
	],
	[#Rule 185
		 'ElementValuesOrEmpty', 2, undef
	],
	[#Rule 186
		 'ElementValues', 1, undef
	],
	[#Rule 187
		 'ElementValues', 3, undef
	],
	[#Rule 188
		 'AnnotationsOrEmpty', 0, undef
	],
	[#Rule 189
		 'AnnotationsOrEmpty', 1, undef
	],
	[#Rule 190
		 'ForInit', 2,
sub {
       ['N_forInit', $_[1], $_[2]]
   }
	],
	[#Rule 191
		 'Modifier', 1, undef
	],
	[#Rule 192
		 'Modifier', 1, undef
	],
	[#Rule 193
		 'Modifier', 1, undef
	],
	[#Rule 194
		 'Modifier', 1, undef
	],
	[#Rule 195
		 'Modifier', 1, undef
	],
	[#Rule 196
		 'Modifier', 1, undef
	],
	[#Rule 197
		 'Modifier', 1, undef
	],
	[#Rule 198
		 'Modifier', 1, undef
	],
	[#Rule 199
		 'Modifier', 1, undef
	],
	[#Rule 200
		 'Modifier', 1, undef
	],
	[#Rule 201
		 'Modifier', 1, undef
	],
	[#Rule 202
		 'Modifier', 1, undef
	],
	[#Rule 203
		 'Modifiers', 1,
sub {
        ['N_Modifier', $_[1]]
    }
	],
	[#Rule 204
		 'Modifiers', 2,
sub {
        push(@{$_[1]}, $_[2]); $_[1]
    }
	],
	[#Rule 205
		 'ModifiersOrEmpty', 0, undef
	],
	[#Rule 206
		 'ModifiersOrEmpty', 1, undef
	],
	[#Rule 207
		 'VariableDeclarators', 1,
sub {
        ['N_VariableDeclarators', $_[1]]
    }
	],
	[#Rule 208
		 'VariableDeclarators', 3,
sub {
        push(@{$_[1]}, $_[2]); push(@{$_[1]}, $_[3]); $_[1]
    }
	],
	[#Rule 209
		 'ConstantDeclaratorsRest', 1,
sub {
        ['N_ConstantDeclaratorsRest', $_[1]]
    }
	],
	[#Rule 210
		 'ConstantDeclaratorsRest', 3,
sub {
        push(@{$_[1]}, $_[2]); push(@{$_[1]}, $_[3]); $_[1]
    }
	],
	[#Rule 211
		 'VariableDeclarator', 1,
sub {
       ['N_VariableDeclarator',
         ['N_MetaNode', {name => $_[1]}],
         $_[1]
       ]
    }
	],
	[#Rule 212
		 'VariableDeclarator', 2,
sub {
        my $nodename = shift @{$_[2]};
        my $metanode = shift @{$_[2]};
        my $decl = $metanode->[1];
        $decl->{name} = $_[1];
        
        ['N_VariableDeclarator', $metanode, $_[1], @{$_[2]} ]
    }
	],
	[#Rule 213
		 'ConstantDeclarator', 2,
sub {
        my $nodename = shift @{$_[2]};
        my $metanode = shift @{$_[2]};
        my $decl = $metanode->[1];
        $decl->{name} = $_[1];

        ['N_ConstantDeclarator',$metanode, $_[1], @{$_[2]} ]
    }
	],
	[#Rule 214
		 'VariableDeclaratorRest', 1,
sub {
        ['N_VariableDeclaratorRest',
         ['N_MetaNode', {type => 'ARRAY'}],
         $_[1]
        ]
    }
	],
	[#Rule 215
		 'VariableDeclaratorRest', 3,
sub {
        ['N_VariableDeclaratorRest',
         ['N_MetaNode', {type => 'ARRAY', value => $_[3]}],
         $_[1], $_[2], $_[3]
        ]
    }
	],
	[#Rule 216
		 'VariableDeclaratorRest', 2,
sub {
        ['N_VariableDeclaratorRest',
         ['N_MetaNode', {type => 'NORMAL', value => $_[2]}],
         $_[1], $_[2]
        ]
    }
	],
	[#Rule 217
		 'ConstantDeclaratorRest', 2,
sub { 
        ['N_ConstantDeclaratorRest',
         ['N_MetaNode', {type => 'NORMAL', value => $_[2]}],
         $_[1], $_[2]
        ]
    }
	],
	[#Rule 218
		 'ConstantDeclaratorRest', 3,
sub {
        ['N_ConstantDeclaratorRest',
         ['N_MetaNode', {type => 'ARRAY', value => $_[3]}],
         $_[1], $_[2], $_[3]
        ]
    }
	],
	[#Rule 219
		 'ArrayInitializer', 3,
sub {
        defined $_[2] ? ['N_ScopeInfo', create_scopeinfo($_[2])] : undef
    }
	],
	[#Rule 220
		 'VariableInitializer', 1, undef
	],
	[#Rule 221
		 'VariableInitializer', 1, undef
	],
	[#Rule 222
		 'VariableInitializerListOrEmpty', 0, undef
	],
	[#Rule 223
		 'VariableInitializerListOrEmpty', 2,
sub { $_[1]; }
	],
	[#Rule 224
		 'VariableInitializerList', 1,
sub { ['N_VariableInitializerList', $_[1]]; }
	],
	[#Rule 225
		 'VariableInitializerList', 3,
sub {
        push(@{$_[1]}, $_[2], $_[3]);
        $_[1];
    }
	],
	[#Rule 226
		 'CommaOrEmpty', 0, undef
	],
	[#Rule 227
		 'CommaOrEmpty', 1, undef
	],
	[#Rule 228
		 'VariableDeclaratorId', 1,
sub { ['VariableDeclaratorId', $_[1]]}
	],
	[#Rule 229
		 'VariableDeclaratorId', 2,
sub { ['VariableDeclaratorId', $_[1], $_[2]]}
	],
	[#Rule 230
		 '@1-3', 0,
sub {
        $G_fileinfo_ref = FileInfo->new();
        if($_[2]) {
            $G_fileinfo_ref->packagename($_[2]);
        }
    }
	],
	[#Rule 231
		 'CompilationUnit', 5,
sub {
        $G_fileinfo_ref
    }
	],
	[#Rule 232
		 'PackageDeclarationOrEmpty', 0, undef
	],
	[#Rule 233
		 'PackageDeclarationOrEmpty', 3,
sub {
        normalize_token($_[2])
    }
	],
	[#Rule 234
		 'ImportDeclarationsOrEmpty', 0, undef
	],
	[#Rule 235
		 'ImportDeclarationsOrEmpty', 1, undef
	],
	[#Rule 236
		 'TypeDeclarationsOrEmpty', 0, undef
	],
	[#Rule 237
		 'TypeDeclarationsOrEmpty', 1, undef
	],
	[#Rule 238
		 'ImportDeclaration', 5, undef
	],
	[#Rule 239
		 'StaticOrEmpty', 0, undef
	],
	[#Rule 240
		 'StaticOrEmpty', 1, undef
	],
	[#Rule 241
		 'DotAllOrEmpty', 0, undef
	],
	[#Rule 242
		 'DotAllOrEmpty', 2, undef
	],
	[#Rule 243
		 'ImportDeclarations', 1, undef
	],
	[#Rule 244
		 'ImportDeclarations', 2, undef
	],
	[#Rule 245
		 'TypeDeclaration', 1, undef
	],
	[#Rule 246
		 'TypeDeclaration', 1, undef
	],
	[#Rule 247
		 'TypeDeclarations', 1, undef
	],
	[#Rule 248
		 'TypeDeclarations', 2, undef
	],
	[#Rule 249
		 'ClassOrInterfaceDeclaration', 2,
sub { undef }
	],
	[#Rule 250
		 'ClassOrInterfaceDeclarationDecl', 1, undef
	],
	[#Rule 251
		 'ClassOrInterfaceDeclarationDecl', 1, undef
	],
	[#Rule 252
		 'ClassDeclaration', 1, undef
	],
	[#Rule 253
		 'ClassDeclaration', 1, undef
	],
	[#Rule 254
		 '@2-2', 0,
sub {
        push(@G_classname_ident, $_[2]->{TOKEN});    
    }
	],
	[#Rule 255
		 '@3-7', 0,
sub {
        my $classinfo = create_classinfo(\@G_classname_ident, 
                                $_[7]->{METHOD}, $_[7]->{VARIABLE});
        push(@{$G_fileinfo_ref->classlist()}, $classinfo);
    }
	],
	[#Rule 256
		 'NormalClassDeclaration', 9,
sub { undef }
	],
	[#Rule 257
		 'ExtendsTypeOrEmpty', 0, undef
	],
	[#Rule 258
		 'ExtendsTypeOrEmpty', 2, undef
	],
	[#Rule 259
		 'ImplementsListOrEmpty', 0, undef
	],
	[#Rule 260
		 'ImplementsListOrEmpty', 2, undef
	],
	[#Rule 261
		 'NameFinalzer', 0,
sub { pop(@G_classname_ident); }
	],
	[#Rule 262
		 'TypeParameters', 3, undef
	],
	[#Rule 263
		 'TypeParametersList', 1, undef
	],
	[#Rule 264
		 'TypeParametersList', 3, undef
	],
	[#Rule 265
		 'TypeParametersOrEmpty', 0, undef
	],
	[#Rule 266
		 'TypeParametersOrEmpty', 1, undef
	],
	[#Rule 267
		 'TypeParameter', 1, undef
	],
	[#Rule 268
		 'TypeParameter', 3, undef
	],
	[#Rule 269
		 'Bound', 1, undef
	],
	[#Rule 270
		 'Bound', 3, undef
	],
	[#Rule 271
		 '@4-2', 0,
sub {
        push (@G_classname_ident, $_[2]->{TOKEN});
    }
	],
	[#Rule 272
		 '@5-5', 0,
sub {
        if(defined $_[5]) {
            my $classinfo = create_classinfo(\@G_classname_ident, 
                                $_[5]->{METHOD}, $_[5]->{VARIABLE});
            push(@{$G_fileinfo_ref->classlist()}, $classinfo);
        }
    }
	],
	[#Rule 273
		 'EnumDeclaration', 7,
sub { undef }
	],
	[#Rule 274
		 'EnumBody', 5,
sub { $_[4] }
	],
	[#Rule 275
		 'EnumConstantsOrEmpty', 0, undef
	],
	[#Rule 276
		 'EnumConstantsOrEmpty', 1, undef
	],
	[#Rule 277
		 'EnumBodyDeclarationsOrEmpty', 0,
sub { undef }
	],
	[#Rule 278
		 'EnumBodyDeclarationsOrEmpty', 1, undef
	],
	[#Rule 279
		 'EnumConstants', 1, undef
	],
	[#Rule 280
		 'EnumConstants', 3, undef
	],
	[#Rule 281
		 '@6-2', 0,
sub {
        push (@G_classname_ident, $_[2]->{TOKEN});
    }
	],
	[#Rule 282
		 '@7-5', 0,
sub {
        if(defined $_[5]) {
            my $classinfo = create_classinfo(\@G_classname_ident, 
                                    $_[5]->{METHOD}, $_[5]->{VARIABLE});
            push(@{$G_fileinfo_ref->classlist()}, $classinfo);
            
        }
    }
	],
	[#Rule 283
		 'EnumConstant', 7,
sub { undef }
	],
	[#Rule 284
		 'EnumBodyDeclarations', 2,
sub { $_[2] }
	],
	[#Rule 285
		 'QualifiedIdentifier', 1,
sub { ['N_QualifiedIdentifier', $_[1] ] }
	],
	[#Rule 286
		 'QualifiedIdentifier', 3,
sub {
        push(@{$_[1]}, $_[2]); push(@{$_[1]}, $_[3]); $_[1]
    }
	],
	[#Rule 287
		 'InterfaceDeclaration', 1, undef
	],
	[#Rule 288
		 '@8-2', 0,
sub {
        push(@G_classname_ident, $_[2]->{TOKEN}); 
    }
	],
	[#Rule 289
		 '@9-6', 0,
sub {
        if($tokenId{$_[1]->{KEYWORD}} != $tokenId{'ATMARK_INTERFACE_TOKEN'}) {
            my $classinfo = create_classinfo(\@G_classname_ident, 
                                    $_[6]->{METHOD}, $_[6]->{VARIABLE});
            push(@{$G_fileinfo_ref->classlist()}, $classinfo);
        }
    }
	],
	[#Rule 290
		 'NormalInterfaceDeclaration', 8,
sub { undef }
	],
	[#Rule 291
		 'InterfaceOrAtInterface', 1, undef
	],
	[#Rule 292
		 'InterfaceOrAtInterface', 1, undef
	],
	[#Rule 293
		 'ExtendsTypeListOrEmpty', 0, undef
	],
	[#Rule 294
		 'ExtendsTypeListOrEmpty', 2, undef
	],
	[#Rule 295
		 'TypeList', 1, undef
	],
	[#Rule 296
		 'TypeList', 3, undef
	],
	[#Rule 297
		 'AnnotationMethodRest', 3, undef
	],
	[#Rule 298
		 'DefaultValue', 2, undef
	],
	[#Rule 299
		 'ClassBody', 2,
sub { {} }
	],
	[#Rule 300
		 'ClassBody', 3,
sub { $_[2] }
	],
	[#Rule 301
		 'ClassBodyOrEmpty', 0, undef
	],
	[#Rule 302
		 'ClassBodyOrEmpty', 1, undef
	],
	[#Rule 303
		 'InterfaceBody', 2,
sub { {} }
	],
	[#Rule 304
		 'InterfaceBody', 3,
sub {
         $_[2]
     }
	],
	[#Rule 305
		 'InterfaceBodyDeclarations', 1,
sub {
        my %variable_ref = (VARIABLE => []);
        if(defined $_[1]) {
            push(@{$variable_ref{VARIABLE}}, @{$_[1]});
        }
        \%variable_ref
    }
	],
	[#Rule 306
		 'InterfaceBodyDeclarations', 2,
sub {
        if(defined $_[2]) {
            push(@{$_[1]->{VARIABLE}}, @{$_[2]});
        }
        $_[1]
    }
	],
	[#Rule 307
		 'InterfaceBodyDeclarations', 1, undef
	],
	[#Rule 308
		 'ClassBodyDeclarations', 1,
sub {
        my $classbody = { METHOD => [], VARIABLE => [] };
        
        if(defined $_[1]) {
            if(exists($_[1]->{METHOD}) and defined $_[1]->{METHOD}) {
                push(@{$classbody->{METHOD}}, $_[1]->{METHOD});
            }
            if(exists($_[1]->{VARIABLE})) {
                push(@{$classbody->{VARIABLE}}, @{$_[1]->{VARIABLE}});
            }
        }
        $classbody
    }
	],
	[#Rule 309
		 'ClassBodyDeclarations', 2,
sub {
        if(defined $_[2]) {
            if(exists($_[2]->{METHOD}) and defined $_[1]->{METHOD}) {
                push(@{$_[1]->{METHOD}}, $_[2]->{METHOD});
            }
            if(exists($_[2]->{VARIABLE})) {
                push(@{$_[1]->{VARIABLE}}, @{$_[2]->{VARIABLE}});
            }
        }
        $_[1]
    }
	],
	[#Rule 310
		 'ClassBodyDeclaration', 1, undef
	],
	[#Rule 311
		 'ClassBodyDeclaration', 1, undef
	],
	[#Rule 312
		 'ClassBodyDeclaration', 2,
sub {
        { METHOD => create_methodinfo('block', ['STATIC', $G_static_number++], $_[2]) }
    }
	],
	[#Rule 313
		 'ClassBodyDeclaration', 2,
sub {
        my $memberdecl = $_[2];
        
        if(exists($memberdecl->{VARIABLE})) {
            my $type         = $memberdecl->{VARIABLE}->[0];
            my $variabledecl = $memberdecl->{VARIABLE}->[1];
            
            my $fieldtype = ['N_type', $_[1], $type];
            
            shift @{$variabledecl};
            
            my @varlist = ();
            for my $current_vardecl (@{$variabledecl}) {
                my $decl = refer_metanode($current_vardecl);
                if(defined $decl) {
                    my $varinfo = create_VariableInfo(
                        $decl->{name}, $fieldtype, $decl->{type}, $decl->{value});
                    push(@varlist, $varinfo);
                }
            }
            undef $memberdecl->{VARIABLE};
            $memberdecl->{VARIABLE} = \@varlist;
        }
        
        $memberdecl;
    }
	],
	[#Rule 314
		 'ClassBodyDeclarationsOrEmpty', 0,
sub { {} }
	],
	[#Rule 315
		 'ClassBodyDeclarationsOrEmpty', 1, undef
	],
	[#Rule 316
		 'MemberDecl', 1,
sub {
        {METHOD => $_[1]}
    }
	],
	[#Rule 317
		 'MemberDecl', 1,
sub {
        {METHOD => $_[1]}
    }
	],
	[#Rule 318
		 'MemberDecl', 1,
sub {
        {VARIABLE => $_[1]}
    }
	],
	[#Rule 319
		 'MemberDecl', 3,
sub {
        {METHOD => create_methodinfo($_[2]->{TOKEN}, $_[3]->{TYPELIST}, $_[3]->{SCOPE})}
    }
	],
	[#Rule 320
		 'MemberDecl', 2,
sub {
        {METHOD => create_methodinfo($_[1]->{TOKEN}, $_[2]->{TYPELIST}, $_[2]->{SCOPE})}
    }
	],
	[#Rule 321
		 'MemberDecl', 1, undef
	],
	[#Rule 322
		 'MemberDecl', 1, undef
	],
	[#Rule 323
		 'MethodDecl', 3,
sub {
        create_methodinfo($_[2]->{TOKEN}, $_[3]->{TYPELIST}, $_[3]->{SCOPE})
    }
	],
	[#Rule 324
		 'FieldDecl', 3,
sub { [ $_[1], $_[2] ] }
	],
	[#Rule 325
		 'GenericMethodOrConstructorDecl', 2,
sub { $_[2] }
	],
	[#Rule 326
		 'GenericMethodOrConstructorRest', 3,
sub {
        create_methodinfo($_[2]->{TOKEN}, $_[3]->{TYPELIST}, $_[3]->{SCOPE})
    }
	],
	[#Rule 327
		 'GenericMethodOrConstructorRest', 3,
sub {
        create_methodinfo($_[2]->{TOKEN}, $_[3]->{TYPELIST}, $_[3]->{SCOPE})
    }
	],
	[#Rule 328
		 'GenericMethodOrConstructorRest', 2,
sub {
        create_methodinfo($_[1]->{TOKEN}, $_[2]->{TYPELIST}, $_[2]->{SCOPE})
    }
	],
	[#Rule 329
		 'InterfaceBodyDeclaration', 1,
sub {undef}
	],
	[#Rule 330
		 'InterfaceBodyDeclaration', 2,
sub {
        my $varinfo = undef;
        
        if(defined $_[2]) {
            my ($vartype, $ident, $memberdecl) = @{$_[2]};

            if(equal_nodetype($memberdecl, 'N_ConstantDeclaratorsRest')) {
                $varinfo = [];
                my $type = ['N_type', $_[1], $vartype ];
                my $is_first = 1;
                shift @{$memberdecl};
                
                for my $vardecl (@{$memberdecl}) {
                    my $decl = refer_metanode($vardecl);

                    if(defined $decl) {
                        if($is_first) {
                            $decl->{name} = $ident;
                            $is_first = 0;
                        }
                        my $one_varinfo = create_VariableInfo(
                            $decl->{name}, $type, $decl->{type}, $decl->{value});
                        push(@$varinfo, $one_varinfo);                        
                    }
                }
            }
        }
        $varinfo
    }
	],
	[#Rule 331
		 'InterfaceMemberDecl', 1, undef
	],
	[#Rule 332
		 'InterfaceMemberDecl', 1,
sub {undef}
	],
	[#Rule 333
		 'InterfaceMemberDecl', 3,
sub {undef}
	],
	[#Rule 334
		 'InterfaceMemberDecl', 1,
sub {undef}
	],
	[#Rule 335
		 'InterfaceMemberDecl', 1,
sub {undef}
	],
	[#Rule 336
		 'InterfaceMethodOrFieldDecl', 3,
sub {
        my $fieldrest = undef;
        
        if(defined $_[3]) {
            $fieldrest = [ $_[1], $_[2], $_[3] ];
        }
        
        $fieldrest;
    }
	],
	[#Rule 337
		 'InterfaceMethodOrFieldRest', 2,
sub { $_[1] }
	],
	[#Rule 338
		 'InterfaceMethodOrFieldRest', 1,
sub { undef }
	],
	[#Rule 339
		 'InterfaceMethodOrFieldRest', 1,
sub { undef }
	],
	[#Rule 340
		 'MethodDeclaratorRest', 4,
sub {
        my $method_decl = {TYPELIST => $_[1]};
        if(equal_nodetype($_[4], 'N_MethodBody')) {
            $method_decl->{SCOPE} = $_[4]->[1];
        }
        $method_decl
    }
	],
	[#Rule 341
		 'MethodBodyOrSemiColon', 1, undef
	],
	[#Rule 342
		 'MethodBodyOrSemiColon', 1, undef
	],
	[#Rule 343
		 'VoidMethodDeclaratorRest', 3,
sub {
        my $method_decl = {TYPELIST => $_[1]};
        if(equal_nodetype($_[3], 'N_MethodBody')) {
            $method_decl->{SCOPE} = $_[3]->[1];
        }
        $method_decl
    }
	],
	[#Rule 344
		 'InterfaceMethodDeclaratorRest', 4, undef
	],
	[#Rule 345
		 'InterfaceGenericMethodDecl', 4, undef
	],
	[#Rule 346
		 'InterfaceGenericMethodDecl', 4, undef
	],
	[#Rule 347
		 'VoidInterfaceMethodDeclaratorRest', 3, undef
	],
	[#Rule 348
		 'ConstructorDeclaratorRest', 3,
sub {
        {TYPELIST => $_[1], SCOPE => $_[3]->[1]}
    }
	],
	[#Rule 349
		 'ThrowsQIdentOrEmpty', 0, undef
	],
	[#Rule 350
		 'ThrowsQIdentOrEmpty', 2, undef
	],
	[#Rule 351
		 'QualifiedIdentifierList', 1,
sub {['N_QualifiedIdentifierList'], $_[1]}
	],
	[#Rule 352
		 'QualifiedIdentifierList', 3,
sub {
        push(@{$_[1]}, $_[2]); push(@{$_[1]}, $_[3]); $_[1]
    }
	],
	[#Rule 353
		 'FormalParameters', 2,
sub { [] }
	],
	[#Rule 354
		 'FormalParameters', 3,
sub { $_[2] }
	],
	[#Rule 355
		 'FormalParameterDecls', 3,
sub {
        [ normalize_token($_[2]) ]
    }
	],
	[#Rule 356
		 'FormalParameterDeclsList', 1, undef
	],
	[#Rule 357
		 'FormalParameterDeclsList', 3,
sub {
        push(@{$_[1]}, $_[3]->[0]); $_[1];
    }
	],
	[#Rule 358
		 'FormalParameterDeclsRest', 1, undef
	],
	[#Rule 359
		 'FormalParameterDeclsRest', 4, undef
	],
	[#Rule 360
		 'MethodBody', 1,
sub {['N_MethodBody', $_[1]]}
	],
	[#Rule 361
		 'ForUpdate', 2,
sub {
        ['N_ForUpdate', $_[1], $_[2]]
    }
	],
	[#Rule 362
		 'SmcToken', 1, undef
	],
	[#Rule 363
		 'LcbToken', 1, undef
	],
	[#Rule 364
		 'RcbToken', 1, undef
	]
],
                                  @_);
    bless($self,$class);
}




#####################################################################
# Function: _Error
#
# 概要:
# 構文エラーの起因となったトークンと行番号を埋め込んだ文字列を生成
# する。
# 構文エラーを検出した際に実行される。
#
# パラメータ:
# _[0] - パーサオブジェクト 
#
# 戻り値:
# なし
#
# 例外:
# なし
#
# 特記事項:
# - 文字列のフォーマットを下記とする。
# Parse error %s:行番号 (エラーの原因となった字句)\n
#
#####################################################################
sub _Error {
    my $curval = $_[0]->YYCurval;
    $_[0]->{YYData}->{ERRMES} = sprintf "Parse error %%s:%d (near token '%s')\n", $curval->{LINE}, $curval->{TOKEN};
}


#####################################################################
# Function: _Lexer
#
# 概要:
# 字句解析を実行し、1トークンの情報を返却する。パーサオブジェクトにより
# 実行される。
#
# パラメータ:
# parser - パーサオブジェクト 
#
# 戻り値:
# - トークンIDとトークン情報のリスト
#
# 例外:
# なし
#
# 特記事項:
# - トークン情報のリストは以下の構造を持つ
# | TOKEN    - 切り出した字句
# | KEYWORD  - 字句に対するトークンID
# | LINE     - トークンが記述されている行番号
#
#####################################################################
sub _Lexer {
    my ($parser) = shift;

    my $result = $lex->nextToken;
    
    if($result) {
        $parser->{YYData}->{LINE} = $result->{LINE};
        return ($result->{KEYWORD}, $result);
    }
    else {
        return ('', undef);
    }
}

#####################################################################
# Function: Run
#
# 概要:
# 構文解析を実行し、ファイル情報を生成する。
#
# パラメータ:
# parser - パーサオブジェクト 
#
# 戻り値:
# fileinfo - ファイル情報
#
# 例外:
# なし
#
# 特記事項:
# なし
#
#####################################################################
sub Run {
    my $self = shift;
    my $parser_debug_flg = 0;

    $G_static_number = 0;
    $G_fileinfo_ref = undef;
    @G_classname_ident = ();

    $lex->setTarget($self->{YYData}->{INPUT});
    defined($self->{YYData}->{loglevel}) and  $self->{YYData}->{loglevel} > 10
                                    and $parser_debug_flg = 0x1F;
    $lex->setDebugMode($parser_debug_flg);

    $self->YYParse( yylex => \&_Lexer, yyerror => \&_Error, yydebug => $parser_debug_flg);
}


#####################################################################
# Function: getLexer
#
# 概要:
# 字句解析処理(レクサオブジェクト)を返却する
# 実行される。
#
# パラメータ:
# なし
#
# 戻り値:
# - レクサオブジェクト
#
# 例外:
# なし
#
# 特記事項:
# なし
#
#####################################################################
sub getLexer {
    return $lex;
}


#####################################################################
# Function: scantree
#
# 概要:
# 指定されたノードを走査し、式情報のリスト、およびスコープ情報の
# リストを抽出する。各トークンの内容は、トークン情報で管理する。
#
# パラメータ:
# targettree - 走査対象となるトークンリスト
# result_ref - 出力結果のリスト(出力)
#
# 戻り値:
# なし
#
# 例外:
# なし
#
# 特記事項:
# - 出力結果のリストは、ノードに含まれるコード情報ごとに、下記の情報を
#   ハッシュで管理する。このハッシュ領域は、呼び出し元で準備する必要が
#   ある。
# | exprset   => @  抽出した式情報のリスト
# | scopeset  => @  抽出したスコープ情報のリスト
# | line      => $  当該式情報の行番号
#
# - 1つのトークンリストより複数のコード情報が生成されるケース(for文)が
#   存在するため、出力結果のリストはコード情報ごとに上記のハッシュが
#   格納される
#
# - exprlistは、当該ノードに存在する、式解析対象となる式情報のリスト
#   である。
#
#####################################################################
sub scantree {
    my ($targettree, $result_ref) = @_;

    my $current_hash = $result_ref->[-1]; # 現在のコード情報を格納する領域
    
    my $type = ref($targettree);
    
    if(!(defined $targettree and defined $type)) {
        $_[0]->{YYData}->{ERRMES} = sprintf "Parse error %%s:-- (%s)\n", "unkown node in scantree" . defined $targettree ? $targettree : "undef value";
        $_[0]->YYAbort;
    }
    #
    # 単一要素の場合は、リスト化して式集合へ登録する
    #
    if($type eq 'HASH') {
        my $current_exprset = $current_hash->{exprset}->[-1];
        
        my $token = get_token($targettree->{KEYWORD}, $targettree->{TOKEN});
        push(@{$current_exprset}, $token);
        
        if(!exists $current_hash->{line}) {
            $current_hash->{line} = $targettree->{LINE};
        }
    }
    
    #
    # 配列の場合は、スコープ情報か、トークンリストか識別する
    #
    elsif($type eq 'ARRAY') {
        my $current_id = undef;
        if(scalar @$targettree != 0 and defined $targettree->[0]) {
            $current_id = $nodetypehash{$targettree->[0]};
        }
        # トークンリストがノードでない場合(要素ハッシュの集合など)は、
        # トークンリストの要素を処理する
        # 
        !defined $current_id and $current_id = $G_element_id;
                #
        # スコープ情報の場合、スコープ情報リストへ格納する
        #
        if($current_id == $G_ScopeInfo_id) {
            my $current_scopeset = $current_hash->{scopeset};
            push(@{$current_scopeset}, $targettree->[1]);
        }
        
        #
        # デリミタトークンの場合は、式情報のリストに新たなリストを追加する
        # 現時点までで抽出したトークン群で、1つの式情報と確定する
        #
        elsif($current_id == $G_Delimiter_id) {
            push(@{$current_hash->{exprset}}, []);
        }
        #
        # メタデータを格納するノードの場合：
        # 行番号を保持している場合は、当該トークンリストの行番号を、保持している
        # 行番号とする(ただしまだ行番号が未登録の場合)
        # 新規コード情報追加の場合、出力結果のリストに新規ハッシュを追加する
        #
        elsif($current_id == $G_MetaNode_id) {
            my $metadata = $targettree->[1];
            
            if(exists $metadata->{line} and !exists $current_hash->{line}) {
                $current_hash->{line} = $metadata->{line};
            }
            
            if(exists $metadata->{addcode}) {
                push(@{$result_ref}, { exprset => [[]], scopeset => []});
            }
        }
        #
        # 条件演算以外のトークンリストの場合、トークン情報のリストを
        # 生成して、式情報リストへ格納する
        #
        else {
            #
            # トークンリストよりトークン情報を生成する
            # トークンリストは、そのままコード情報のトークンリストとして格納
            # されるため、shift操作などにより、要素を削除しないこと
            #
            my $i = 0;

            # targettreeがノードの場合は、ノード名の分、ポインタをずらす
            $current_id != $G_element_id and $i++;

            while($i < scalar @{$targettree}) {
                $current_hash = $result_ref->[-1]; # 現在のコード情報の更新を行う
                defined($targettree->[$i]) and scantree($targettree->[$i], $result_ref);
                $i++;
            }
        }
    }
    return;
}

#####################################################################
# Function: scanscope
#
# 概要:
# スコープ情報を走査し、格納されているトークンの集合を抽出する。
# スコープ情報が格納するコード情報が正規化されたコードの場合、その
# 式情報リストが保持する内容を連結した文字列を抽出したトークンリスト
# に格納する。スコープ情報が格納するコード情報が、下位スコープ情報
# の場合、下位スコープ情報についてさらにスコープ情報の走査を行う。
#
# パラメータ:
# scopeinfo  - 走査対象となるスコープ情報
# exprlist   - 抽出したトークンのリスト(出力)
#
# 戻り値:
# なし
#
# 例外:
# なし
#
# 特記事項:
# - 変数情報の値がArrayInitializerの場合、平坦化する際に利用する
#
#####################################################################
sub scanscope {
    my ($scopeinfo, $exprlist) = @_;
    
    for my $code_set (@{$scopeinfo->codelist()}) {
        if($code_set->codeType() == CODETYPE_CODE) {
            for my $expr (@{$code_set->exprlist}) {
                push(@{$exprlist}, @{$expr});
            }
        } else {
            scanscope($code_set->tokenlist(0), $exprlist);
#            push(@{$exprlist}, get_token('CM_TOKEN'));
        }
    }
}



#####################################################################
# Function: create_scopeinfo
#
#
# 概要:
# スコープ情報を新規に生成する。指定されたトークンリストよりコード
# 情報を生成し、スコープ情報に格納する。
#
# パラメータ:
# tokenlist - トークンリスト
#
# 戻り値:
# コード情報
#
# 例外:
# なし
#
# 特記事項:
# なし
#
#####################################################################
sub create_scopeinfo {
    my ($tokenlist) = @_;
    
    #
    # ノード名を削除する
    # tokenlistには、N_BlockStatementの集合が格納されている
    #
    shift @{$tokenlist};
    my $scope_info = Scope->new();

    #
    # 指定されたトークンリストすべてについて、コード情報の生成を
    # 行う
    #
    for my $node (@{$tokenlist}) {
        next if !defined($node);
        
        #
        # 当該トークン(ノード)がスコープ情報の場合は、その下位スコープ情報
        # に対するコード情報を生成して、現スコープ情報に格納する
        #
        if(equal_nodetype($node, 'N_ScopeInfo')) {
                    
            my $child_scope1 = $node->[1];
            $child_scope1->parent($scope_info);
                    
            push(@{$scope_info->codelist()},
                         create_codeset_for_scope($child_scope1));
                    
        }
        #
        # 当該トークン(ノード)がスコープ情報以外の場合は、そのトークン
        # に対するコード情報を生成して、現スコープ情報に格納する
        #
        else {
            my $codeset = create_codeset_for_code($node);
            push(@{$scope_info->codelist()}, @{$codeset->{CODE}});
            
            #
            # 当該ノード内に下位スコープが存在した場合は、スコープ間の
            # 親子関係を構築する        
            #
            for my $child_scope2 (@{$codeset->{SCOPE}}) {
                $child_scope2->parent($scope_info);
            }
        }
    }
    
    return $scope_info;
}

#####################################################################
# Function: create_codeset_for_scope
#
#
# 概要:
# スコープ情報を格納するコード情報を新規に生成する。
#
# パラメータ:
# scope - スコープ情報
#
# 戻り値:
# コード情報
#
# 例外:
# なし
#
# 特記事項:
# なし
#
#####################################################################
sub create_codeset_for_scope {
    
    my ($scope) = @_;

    my $codeset = CodeSet->new();
    $codeset->codeType(CODETYPE_SCOPE);
    $codeset->tokenlist(0, $scope);
    return $codeset;
}


#####################################################################
# Function: create_codeset_for_code
#
#
# 概要:
# トークンリストを格納するコード情報を新規に生成する。トークンリスト
# を解析して、式集合を抽出し格納する。また、式に含まれるスコープ情報を
# 抽出した場合は、スコープ情報ごとにコード情報を生成する。
#
# パラメータ:
# tokenlist - トークンリスト
#
# 戻り値:
# - コード情報のリストのリファレンス、および子スコープ情報のリストのリファレンス
#
# 特記事項:
# - 返却はハッシュに格納して返却する
# | CODE  => コード情報のリストのリファレンス
# | SCOPE => 子スコープ情報のリストのリファレンス
#####################################################################
sub create_codeset_for_code {
    my ($tokenlist) = @_;
    
    my @codelist = ();
    my @scopelist = ();

    #
    # トークンリストの解析結果
    #
    my $result_ref = [
        {
            exprset  => [[]],
            scopeset => [],
        }
    ];

    scantree($tokenlist, $result_ref);
    
    for my $current_codeinfo (@{$result_ref}) {
        #
        # トークンリストを格納するコード情報を生成する
        #
        my $codeset = CodeSet->new(linenumber => $current_codeinfo->{line});
        $codeset->codeType(CODETYPE_CODE);
        $codeset->tokenlist(0, $tokenlist);
        push(@{$codeset->exprlist()}, @{$current_codeinfo->{exprset}});

        push(@codelist, $codeset);

        #
        # トークンリストよりスコープ情報を抽出した場合は、スコープ情報を含む
        # コード情報を生成する
        #                
        if(scalar @{$current_codeinfo->{scopeset}} > 0) {
            for my $scope (@{$current_codeinfo->{scopeset}}) {
                push(@codelist, create_codeset_for_scope($scope));
                push(@scopelist, $scope);
            }
        }
    }




    
    return {CODE => \@codelist, SCOPE => \@scopelist};
}

#####################################################################
# Function: refer_metanode
#
#
# 概要:
# 指定されたノードがMetaNodeである場合、その内容を返却する
#
# パラメータ:
# node    - ノード情報
#
# 戻り値:
# MetaNodeを保持している場合、その内容。保持していない場合は未定義値
#
# 例外:
# なし
#
# 特記事項:
# なし
#
#####################################################################
sub refer_metanode {
    my ($node) = @_;
    if(defined $node and ref($node) eq 'ARRAY'
        and equal_nodetype($node->[1], 'N_MetaNode')) {
        return $node->[1]->[1];
    }
    undef;
}

#####################################################################
# Function: create_linenode
#
# 概要:
# 指定されたトークンの行番号を保持するMetaNodeを生成する
#
# パラメータ:
# token    - ノード情報
#
# 戻り値:
# MetaNode - 行番号を保持するMetaNode
#
# 例外:
# なし
#
# 特記事項:
# なし
#
#####################################################################
sub create_linenode {
    my ($token) = @_;
    return ['N_MetaNode', {line => $token->{LINE}}];
}

#####################################################################
# Function: create_addcode
#
# 概要:
# トークンリスト解析時に新規コード情報として情報を格納する指示を
# 追加するMetaNodeを生成する
#
# パラメータ:
# なし
#
# 戻り値:
# MetaNode - 新規コード情報追加を指示するMetaNode
#
# 例外:
# なし
#
# 特記事項:
# なし
#
#####################################################################
sub create_addcode {
    return ['N_MetaNode', {addcode => 1}];
}


#####################################################################
# Function: equal_nodetype
#
#
# 概要:
# 指定されたノードがkeywordが示すノード種別の場合、真を返却する。
# 指定されたノードが定義されていない、またはノードではない場合は
# 偽を返却する
#
# パラメータ:
# node    - ノード情報
# keyword - ノード種別を示す文字列 
#
# 戻り値:
# 真偽値
#
# 例外:
# - ノード情報の構造が不正な場合
# - ノード種別を示す文字列が不正な場合
#
# 特記事項:
# なし
#
#####################################################################
sub equal_nodetype {
    my ($node, $keyword) = @_;
    my $b = 0;
    if(defined $node and ref($node) eq 'ARRAY'
             and $node->[0] =~ m{N_}xms) {
        $b = $nodetypehash{$node->[0]} == $nodetypehash{$keyword};
    }
    return $b;
}

#####################################################################
# Function: create_VariableInfo
#
#
# 概要:
# 変数情報を新規に生成する。
#
# パラメータ:
# name      - 変数名のトークン
# typeinfo  - 型のトークンリスト(N_typeノード)
# typetype  - 型の識別情報(NORMAL or ARRAYという文字列)
# valueinfo - 値のトークンリスト(N_VariableInitializerノード)
#
# 戻り値:
# 変数情報
#
# 例外:
# なし
#
# 特記事項:
# - N_VariableInitialzerノードは、単一の値と配列初期化子の２パターン
#   の場合が考えられる。配列初期化子の場合は、normalize_tokenにより
#   要素をコンマ区切りで連結したトークンリストに平坦化される。これは、
#   式解析においてスコープを意識することなく解析させるための措置である。
# - 型名として格納される内容は下記の通り
# - String(Stringオブジェクト)
# - StringBuffer(StringBufferオブジェクト)
# - String[](Stringオブジェクトの配列)
# - StringBuffer[](StringBufferの配列)
# - 上記以外の型
# - 値として格納される内容はトークンリストとなる
#
#####################################################################
sub create_VariableInfo {
    my ($name, $typeinfo, $typetype, $valueinfo) = @_;

    #
    # 型名を取得する
    # String, StringBufferの型名に修飾子が付与されている場合は取り除く
    #
    my $result_ref = [
        {
            exprset  => [[]],
            scopeset => [],
        }
    ];
    scantree($typeinfo, $result_ref);
    
    my $line = $result_ref->[0]->{line};
    
    #
    # 型名は、収集した式リストの「最初の式リストの最後の要素」を取得する
    # - 先頭から要素を参照し、'['の直前の型名か、要素の最後の型名を取得する
    # - '['を検出した場合は、型種別を'ARRAY'に変更する
    my ($index, $result_of_exprset);
    for($index = 0, $result_of_exprset = $result_ref->[0]->{exprset}->[0];
        $index < scalar @{$result_of_exprset};
        $index++) {
        
        if($result_of_exprset->[$index]->token() eq '[') {
            $typetype = 'ARRAY';
            last;
        }
    }
    my $typename = $result_of_exprset->[$index - 1]->token();

    #
    # 型種別が配列の場合、配列を示す文字列を付与する
    #
    if(defined($typetype) and $typetype eq 'ARRAY') {
        $typename = $typename . '[]';
    }

    my $var_info = VariableInfo->new(name => $name->{TOKEN}, type => $typename, linenumber => $line);

    #
    # トークンリストから値を取得する
    # scantreeの結果として取得した式リスト、およびスコープ情報リスト内に
    # 格納されているトークンをひとつずつ抽出し、tokenlistに格納する 
    #
    if(defined $valueinfo) {
        $result_ref->[0]->{exprset} = [[]];
        $result_ref->[0]->{scopeset} = [];
        scantree($valueinfo, $result_ref);
        
        my $tokenlist = $var_info->value();
        my $exprset = [];
        map { push(@{$tokenlist}, $_)} @{$result_ref->[0]->{exprset}->[0]};
        map {scanscope($_, $exprset); push(@{$tokenlist}, @{$exprset})}
            @{$result_ref->[0]->{scopeset}};
    
        #
        # 変数情報の終端を示すVARDECL_DELIMITERトークンを追加する
        #
        my $delimiter = get_token('VARDECL_DELIMITER');
        push(@{$tokenlist}, $delimiter);
    }
    return $var_info;
}

#####################################################################
# Function: create_methodinfo
#
#
# 概要:
# メソッド情報を新規に生成する。メソッド定義実体が存在しない場合
# (abstract定義中のメソッドなど)の場合は、undefを返却する。
#
# パラメータ:
# name      - メソッド名
# typelist  - 型名のリスト
# scope     - ルートスコープ情報
#
# 戻り値:
# メソッド情報
#
# 例外:
# なし
#
# 特記事項:
# なし
#
#####################################################################
sub create_methodinfo {
    my ($name, $typelist, $scope) = @_;
    
    #
    # メソッド定義実体が存在しない場合(abstract定義など)は、undefを返却
    #
    if(!defined $scope) {
        return undef;
    }
    
    my $method = MethodInfo->new();
    $method->ident($name . '-' . join('-', @{$typelist}));
    $method->name($name);
    $method->rootscope_ref($scope->[1]);
    
    return $method;
}

#####################################################################
# Function: create_classinfo
#
#
# 概要:
# クラス情報を新規に生成する
#
# パラメータ:
# namelist    - クラス名のリスト
# methodlist  - メソッド情報のリスト
# varlist     - 変数情報のリスト
#
# 戻り値:
# クラス情報
#
# 例外:
# なし
#
# 特記事項:
# - クラス名のリストより"$"区切りで連結した文字列を生成し、クラス名として
#   登録する
#
#####################################################################
sub create_classinfo {
    my ($namelist, $methodlist, $varlist) = @_;
    my $classinfo = ClassInfo->new();
    $classinfo->classname(join('$', @{$namelist}));
    push(@{$classinfo->varlist()}, @{$varlist}) if(defined $varlist);
    
    my @enable_method_list = ();
    if(defined $methodlist) {
        @enable_method_list = grep { defined } @{$methodlist};    
    }
    if(scalar @enable_method_list > 0) {
        push(@{$classinfo->methodlist()}, @enable_method_list);

    } elsif(defined $varlist and scalar @{$varlist} > 0){
        #
        # interfaceなど、メソッドがひとつもないクラスについては変数情報
        # に対する式解析を行わせるためダミーのメソッドを登録する
        #
        my $methodinfo = create_methodinfo(
            'block', ['STATIC', $G_static_number++],
            [ 'N_ScopeInfo', create_scopeinfo(['N_BlockStatements']) ]
        );
        push(@{$classinfo->methodlist()}, $methodinfo);
    }
    
    return $classinfo;
}



#####################################################################
# Function: normalize_token
#
#
# 概要:
# トークンリスト(ノード)の内容を走査して、トークンリスト内の文字列を
# 抽出し、連結した文字列を返却する。
#
# パラメータ:
# node      - トークンリスト(ノード)
# 
#
# 戻り値:
# トークンリスト内の文字列を連結した文字列
#
# 例外:
# なし
#
# 特記事項:
# なし
#
#####################################################################
sub normalize_token {
    my ($node) = @_;
    my $value = '';
    my $result_ref = [
        {
            exprset  => [[]],
            scopeset => [],
        }
    ];
    scantree($node, $result_ref);
    
    for my $expr (@{$result_ref->[0]->{exprset}}) {
        map {$value .= $_->token() } @{$expr};
    }
    return $value;
}

#####################################################################
# Function: get_token
#
#
# 概要:
# トークンIDに対するトークン情報を返却する。トークン情報オブジェクト
# プールにオブジェクトが存在する場合は、そのトークン情報を返却する。
# 抽出し、連結した文字列を返却する。
#
# パラメータ:
# keyword - トークンID
# token   - 切り出した文字列
# 
#
# 戻り値:
# トークンIDに対するトークン情報
#
# 例外:
# なし
#
# 特記事項:
# なし
#
#####################################################################
sub get_token {
    my ($keyword, $token) = @_;
    
    my $tokeninfo;
    
    #
    # トークンIDがキャッシュ対象であるか判別する
    #
    if(exists $lookup{$keyword}) {
        
        #
        # キャッシュ対象の場合、トークン情報をキャッシュより取得する
        # 取得できなかった場合は、新規に作成してキャッシュへ登録する
        #
        $tokeninfo = $G_tokenchace{$keyword};
        if(!defined $tokeninfo) {
            $tokeninfo = Token->new(token => $lookup{$keyword}, id => $tokenId{$keyword});
            $G_tokenchace{$keyword} = $tokeninfo;
        }
    } else {
        #
        # キャッシュ対象でない場合は、新規にトークン情報を生成する
        #
        $tokeninfo = Token->new(token => $token, id => $tokenId{$keyword});
    }
    return $tokeninfo;
}


#####################################################################
# Function: create_forvar_control
#
#
# 概要:
# ForVarControlの定義内容より、N_ForControlノード、もしくはN_ForVarControl
# ノードを生成し、返却する。
#
# パラメータ:
# type - PrimaryTypeの内容
# rest - ForVarControlRestの内容
# 
#
# 戻り値:
# N_ForControlノード、もしくは、N_ForVarControlノード
#
# 例外:
# なし
#
# 特記事項:
# なし
#
#####################################################################
sub create_forvar_control {
    my ($type, $rest) = @_;
    my $for_ctrl;
    if(equal_nodetype($rest, 'N_NormalFor')) {
        my $for_init = ['N_forInit', $type, $rest->[1]];
        $for_ctrl = ['N_ForControl', $for_init, create_addcode(), $rest->[2], create_addcode(), $rest->[3]];
    }
    else {
        $for_ctrl = ['N_ForVarControl', $type, $rest->[1], ['N_Delimiter'], $rest->[2]];
    }
    $for_ctrl
}


#sub print_node {
#    my ($node, $indent) = @_;
#
#    if(!defined $node) {
#        printf "%sempty-node\n";
#        return;
#    }
#
#    my $type = Scalar::Util::reftype($node);
#    
#    if($type eq 'HASH') {
#        printf "%s%s: %s \"%s\"\n", $indent, $node, $node->{KEYWORD}, $node->{TOKEN};
#    }
#    elsif($type eq 'ARRAY') {
#        
#        if(ref $node->[0] or $node->[0] !~ m{N_}xms) {
#            print "invalid node structure: $node\n";
#        }
#        printf "%s%s: %s\n", $indent, $node, $node->[0];
#        if($node->[0] =~ m{ARRAY}) {
#            
#            print "invalid: ", join(",", @{$node}), "\n";
#        }
#        if($node->[0] eq 'N_MetaNode') {
#            return;
#        }
#        $indent = $indent . '  ';
#        my @restnode = @{$node}[1 .. $#{$node}];
#        
#        for my $current (@restnode) {
#            print_node($current, $indent);
#        }
#    }
#    else {
#        printf "%sunkown node -> [%s]\n", $indent, $node;
#    }
#    
#}






1;
