####################################################################
#
#    This file was generated using Parse::Yapp version 1.05.
#
#        Don't edit this file, use source file instead.
#
#             ANY CHANGE MADE HERE WILL BE LOST !
#
####################################################################
package PgSqlExtract::Analyzer::CParser;
use vars qw ( @ISA );
use strict;

@ISA= qw ( Parse::Yapp::Driver );
use Parse::Yapp::Driver;


#use diagnostics;
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
		_Bool	_Complex	_Imaginary	auto		break		case		char
		const	continue	default		do			double		else		enum
		extern	float		for			goto		if			inline		int
		long	new			private		protected	public		register	restrict
		return	short		signed		sizeof		static		struct		switch
		typedef	union		unsigned	void		volatile	while
    ),
);

# SQLで使用するため、大文字でも解釈できるようにtoken登録する
my $Exec	= qr{\b[e][x][e][c]\b}ixms;
my $Sql	= qr{\b[s][q][l]\b}ixms;
my $Oracle	= qr{\b[o][r][a][c][l][e]\b}ixms;
my $Tools	= qr{\b[t][o][o][l][s]\b}ixms;
my $Begin	= qr{\b[b][e][g][i][n]\b}ixms;
my $End	= qr{\b[e][n][d]\b}ixms;
my $Declare	= qr{\b[d][e][c][l][a][r][e]\b}ixms;
my $Section	= qr{\b[s][e][c][t][i][o][n]\b}ixms;

#!
#! リテラルパターンの定義(Integer Literals)
#!
my $Digit					= qr{\d}xms;
my $HexDigit				= qr{[\da-fA-F]}xms;
my $OctDigit				= qr{[0-7]}xms;
my $IntegerTypeSuffix		= qr{[uU] (?: [l][l] | [L][L] ) | [uU] [lL]? | (?: [l][l] | [L][L] ) [uU]?  | [lL] [uU]?}xms;
my $DecimalNumeral			= qr{ 0 | [1-9] $Digit* }xms;

my $HexNumeral				= qr{ 0 [xX] $HexDigit+ }xms;

my $OctalNumeral			= qr{ 0 $OctDigit+ }xms;

my $DecimalIntegerLiteral	= qr{ $DecimalNumeral $IntegerTypeSuffix? }xms;
my $HexIntegerLiteral		= qr{ $HexNumeral     $IntegerTypeSuffix? }xms;
my $OctalIntegerLiteral		= qr{ $OctalNumeral   $IntegerTypeSuffix? }xms;
my $IntegerLiteral = qr{ $OctalIntegerLiteral | $HexIntegerLiteral | $DecimalIntegerLiteral }xms;

#!
#! リテラルパターンの定義(Floating-Point Literals)
#!
my $ExponentPart	= qr{ [eE] [+-]?\d+ }xms;
my $FloatTypeSuffix	= qr{ [fFlL] }xms;
my $HexSignificand	= qr{ 0 [xX] (?: $HexDigit+ \.? | $HexDigit* \. $HexDigit+) }xms;
my $BinaryExponentIndicator	= qr{ [pP] [+-]?\d+ }xms;


my $DecimalFPLiteral1 = qr{ $Digit+ \. $Digit* $ExponentPart? $FloatTypeSuffix?}xms;
my $DecimalFPLiteral2 = qr{         \. $Digit+ $ExponentPart? $FloatTypeSuffix?}xms;
my $DecimalFPLiteral3 = qr{            $Digit+ $ExponentPart  $FloatTypeSuffix?}xms;
my $HexadecimalFPLiteral = qr{ $HexSignificand $BinaryExponentIndicator $FloatTypeSuffix? }xms;
my $FloatLiteral = qr{ $DecimalFPLiteral1 | $DecimalFPLiteral2 | $DecimalFPLiteral3 | $HexadecimalFPLiteral }xms;
#!
#! リテラルパターンの定義(Character)
#! ''内に任意の文字列を記述可能とする定義としており、これは本来の定義とは
#! 異なるが、これは'\u000'といった記述に対応するためである。
#! コンパイルが正常終了したソースコードが解析対象となるため、下記の定義で
#! 字句解析を行っても問題ない。
#! ※ ワイド文字(L'')の対応が必要
#!
my $CharacterLiteral	= qr{ [L]? ['] (?: [^'\\] | \\[?avxbtnfr"'\\0-9] | \\[\n] )* ['] }xms;

#!
#! リテラルパターンの定義(String)
#! ※ ワイド文字列(L"": Lは大文字のみらしい)の対応が必要
#!
my $StringLiteral		= qr{ [L]? ["] (?: [^"\\] | \\[?avxbtnfr"'\\0-9] | \\[\n] )* ["] }xms;


#!
#! セパレータパターンの定義
#! セパレータパターンは、キーワードとして扱う
#! ただし、DOT_TOKENはfloat値との誤認識を避けるため、
#! 特殊キーワードとして定義する
#!
my %separator = (
	'(' => 'LP_TOKEN' ,
	')' => 'RP_TOKEN' ,
	';' => 'SMC_TOKEN',
	',' => 'CM_TOKEN' ,
);

while(my ($key, $value) = each %separator) {
	$keywords{$key} = $value;
}

#!
#! クエスションはキーワードとして扱う
#!
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
#! shift演算子については、'>>'は、TypeArgumentsの入れ子(<String, Map<String,
#! String>>など)の終端と誤認識する場合があるため、GT_OPRの連続で定義する。
#! そのため、トークンとしては定義しない。
#!
my $oprAssignEqual	= qr{ = }xms;
my $oprAssignPls	= qr{ \+= }xms;
my $oprPlus			= qr{ \+ }xms;

my $oprAssign		= qr{ >{2,3}= | <{2}= | [*/&|^%-]= }xms;
my $oprCOr			= qr{\|\|}xms;
my $oprCAnd			= qr{&&}xms;
my $oprOr			= qr{\|}xms;
my $oprNor			= qr{\^}xms;
my $oprAmp			= qr{&}xms;
my $oprEquality		= qr{[=!]=}xms;
my $oprRelational	= qr{[<>]=}xms;
my $oprShift		= qr{>{2} | <{2}}xms; #! Cでは>>>がないため修正
my $oprMulti		= qr{[/%]}xms;
my $oprAsteri		= qr{ \* }xms;
my $oprMinus		= qr{ - }xms;
my $oprInEquality	= qr{ <> }xms;
my $oprGt			= qr{ > }xms;
my $oprLt			= qr{ < }xms;
my $oprPostfix		= qr{ \+\+ | -- }xms;
my $oprPrefix		= qr{[!~]}xms;
my $oprPointer		= qr{ -> }xms;

#!
#! 特殊キーワード
#! BNFによる構文定義のみでは表現が難しいものについては、字句解析で識別を行う
#! 方針とする
#! そのような特殊なキーワードを定義する
#! - Annotationを示す@は、@InterfaceとInterfaceで定義を共用するため、特殊定義
#!   とする
#!
my $atmark			= qr{@}xms;
my $ellipsis		= qr{[.][.][.]};
my $dot				= qr{[.]};

my $sepLcb				= qr{[\{]|[<][%]};
my $sepRcb				= qr{[\}]|[%][>]};
my $sepLsb				= qr{[\[]|[<][:]};
my $sepRsb				= qr{[\]]|[:][>]};
my $kwCln				= qr{[:]};

#!
#! レクサに定義するパターンの定義
#!
my @pattern = (

	#
	# 埋め込みSQLキーワード
	#
	$Exec,					'EXEC_TOKEN',
	$Sql,					'SQL_TOKEN',
	$Oracle,				'ORACLE_TOKEN',
	$Tools,					'TOOLS_TOKEN',
	$Begin,					'BEGIN_TOKEN',
	$End,					'END_TOKEN',
	$Declare,				'DECLARE_TOKEN',
	$Section,				'SECTION_TOKEN',

	#
	# リテラルパターン(Floating-Point Literals)
	#
	$FloatLiteral,		'FLOAT_LITERAL',

	#
	# リテラルパターン(Integer Literals)
	#
	$IntegerLiteral,		'INTEGER_LITERAL',

	#
	# リテラルパターン(Character)
	#
	$CharacterLiteral,		'CHAR_LITERAL',

	#
	# リテラルパターン(String)
	#
	$StringLiteral,			'STRING_LITERAL',

	#
	# 識別子
	#
	$Identifiers,			'IDENTIFIER_ORG',

	#
	# セパレータ
	# 大なり小なりより先に定義する必要がある
	#
	$sepLcb,				'LCB_TOKEN',
	$sepRcb,				'RCB_TOKEN',
	$sepLsb,				'LSB_TOKEN',
	$sepRsb,				'RSB_TOKEN',

	#
	# オペレータパターン
	# 定義する順番に注意する
	# マッチング対象の文字列長が長いものから定義する必要がある
	#
	$oprAssign,				'ASSIGN_OPR',
	$oprShift,				'SHIFT_OPR',
	$oprEquality,			'EQUALITY_OPR',
	$oprRelational,			'RELATIONAL_OPR',
	$oprAssignPls,			'ASSIGN_P_OPR',
	$oprCOr,				'COR_OPR',
	$oprCAnd,				'CAND_OPR',
	$oprPostfix,			'POSTFIX_OPR',
	$oprAssignEqual,		'EQUAL_OPR',
	$oprPlus,				'PLUS_OPR',
	$oprOr,					'OR_OPR',
	$oprNor,				'NOR_OPR',
	$oprAmp,				'AMP_OPR',
	$oprMulti,				'MULTI_OPR',
	$oprAsteri,				'ASTARI_OPR',
	$oprPointer,			'PTR_OPR',
	$oprMinus,				'MINUS_OPR',
	$oprInEquality,			'INEQUALITY_OPR',
	$oprGt,					'GT_OPR',
	$oprLt,					'LT_OPR',
	$oprPrefix,				'PREFIX_OPR',
	$atmark,				'ATMARK_TOKEN',
	$ellipsis,				'ELLIPSIS_TOKEN',
	$dot,					'DOT_TOKEN',
	$kwCln,					'CLN_TOKEN',
);

#!
#! 解析対象外パターン(コメント、空白文字)の定義
#! '\s'は、空白、HT(水平タブ)、FF(フォームフィード)、改行(CR, LF, CR+LF)に
#! マッチングする
#!
my $commentPattern = q(
	(
		(?:  \s+
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
$tokenId{'TNAME_TOKEN'} = $index++;

#!
#! キーワードに対するトークン情報オブジェクトプールを作成する
#! lookupは、トークン情報がプール対象であるかを判別するハッシュである
#! キーワード以外はプール対象としない（'VARDECL_DELIMITER'は特別なキーワード
#! としてプールする)
#!
my %G_tokenchace = ();
my %lookup = reverse %keywords;
$lookup{'VARDECL_DELIMITER'} = '##;##';


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
 N_BlockStatements
 N_if N_else N_switch N_SwitchLabel N_while N_return N_ParExpression
 N_for N_ForControl N_forInit N_ForUpdate N_ForVarControl N_NormalFor
 N_ScopeInfo N_MetaNode N_Delimiter
 N_declaration N_declaration_specifiers N_type_specifier 
 N_init_declarator_list N_init_declarator
 N_expression N_assignment_operator N_logical_OR_expression N_logical_AND_expression
 N_inclusive_OR_expression N_exclusive_OR_expression N_AND_expression
 N_equality_expression N_relational_expression N_shift_expression
 N_additive_expression N_multiplicative_expression N_cast_expression
 N_unary_expression N_postfix_expression N_primary_expression
	),
);

#!
#! ノード種別のキャッシュ
#! scantree内で頻繁に使用される下記のノード種別については、値を別に保持する
#!
my $G_ScopeInfo_id	= $nodetypehash{'N_ScopeInfo'};
my $G_Delimiter_id	= $nodetypehash{'N_Delimiter'};
my $G_MetaNode_id	= $nodetypehash{'N_MetaNode'};
my $G_element_id	= 0;

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
#! ホスト変数宣言フラグ
#! ホスト変数宣言内は真となるフラグ
#!
my $G_declaresection_flg = 0;

#!
#! 抽出したクラス名をスタックで管理する
#!
my @G_classname_ident = ();

#!
#! typedef宣言フラグ
#! typedef宣言内は真となるフラグ
#!
my $G_typedef_flg = 0;

#!
#! ANSI形式コメント行
#! ANSI形式コメント行が検出された場合に行数を格納する変数
#!
my $G_ansi_comment_line = 0;

#! 処理ロジック定義の終了


sub new {
        my($class)=shift;
        ref($class)
    and $class=ref($class);

    my($self)=$class->SUPER::new( yyversion => '1.05',
                                  yystates =>
[
	{#State 0
		ACTIONS => {
			'VOLATILE_TOKEN' => 21,
			'EXTERN_TOKEN' => 3,
			'SHORT_TOKEN' => 2,
			'ENUM_TOKEN' => 1,
			'LONG_TOKEN' => 5,
			'VOID_TOKEN' => 22,
			'DOUBLE_TOKEN' => 24,
			'INT_TOKEN' => 26,
			'_BOOL_TOKEN' => 27,
			'INLINE_TOKEN' => 8,
			'TYPEDEF_TOKEN' => 29,
			'EXEC_TOKEN' => 31,
			'_COMPLEX_TOKEN' => 32,
			'SIGNED_TOKEN' => 12,
			'CHAR_TOKEN' => 13,
			'REGISTER_TOKEN' => 34,
			'CONST_TOKEN' => 14,
			'RESTRICT_TOKEN' => 35,
			'UNION_TOKEN' => 36,
			'STRUCT_TOKEN' => 15,
			'STATIC_TOKEN' => 37,
			'TNAME_TOKEN' => 16,
			'UNSIGNED_TOKEN' => 17,
			'FLOAT_TOKEN' => 18,
			'AUTO_TOKEN' => 19
		},
		DEFAULT => -229,
		GOTOS => {
			'struct_or_union' => 33,
			'function_specifier' => 4,
			'external_declaration' => 23,
			'embedded_sql' => 6,
			'declaration_specifiers' => 7,
			'declaration' => 25,
			'struct_or_union_specifier' => 28,
			'type_specifier' => 38,
			'type_qualifier' => 9,
			'storage_class_specifier' => 10,
			'function_definition' => 11,
			'enum_specifier' => 30,
			'translation_unit' => 20
		}
	},
	{#State 1
		ACTIONS => {
			'IDENTIFIER_ORG' => 39,
			'LCB_TOKEN' => 44,
			'END_TOKEN' => 48,
			'SQL_TOKEN' => 45,
			'SECTION_TOKEN' => 40,
			'BEGIN_TOKEN' => 43,
			'DECLARE_TOKEN' => 46,
			'TOOLS_TOKEN' => 49,
			'ORACLE_TOKEN' => 41,
			'EXEC_TOKEN' => 47
		},
		GOTOS => {
			'IDENTIFIER' => 42
		}
	},
	{#State 2
		DEFAULT => -87
	},
	{#State 3
		DEFAULT => -81
	},
	{#State 4
		ACTIONS => {
			'EXTERN_TOKEN' => 3,
			'SHORT_TOKEN' => 2,
			'ENUM_TOKEN' => 1,
			'LONG_TOKEN' => 5,
			'INLINE_TOKEN' => 8,
			'SIGNED_TOKEN' => 12,
			'CHAR_TOKEN' => 13,
			'CONST_TOKEN' => 14,
			'STRUCT_TOKEN' => 15,
			'TNAME_TOKEN' => 16,
			'UNSIGNED_TOKEN' => 17,
			'FLOAT_TOKEN' => 18,
			'AUTO_TOKEN' => 19,
			'VOLATILE_TOKEN' => 21,
			'VOID_TOKEN' => 22,
			'DOUBLE_TOKEN' => 24,
			'INT_TOKEN' => 26,
			'_BOOL_TOKEN' => 27,
			'TYPEDEF_TOKEN' => 29,
			'_COMPLEX_TOKEN' => 32,
			'REGISTER_TOKEN' => 34,
			'RESTRICT_TOKEN' => 35,
			'UNION_TOKEN' => 36,
			'STATIC_TOKEN' => 37
		},
		DEFAULT => -74,
		GOTOS => {
			'struct_or_union' => 33,
			'function_specifier' => 4,
			'declaration_specifiers' => 50,
			'struct_or_union_specifier' => 28,
			'type_qualifier' => 9,
			'type_specifier' => 38,
			'storage_class_specifier' => 10,
			'enum_specifier' => 30
		}
	},
	{#State 5
		DEFAULT => -89
	},
	{#State 6
		DEFAULT => -234
	},
	{#State 7
		ACTIONS => {
			'IDENTIFIER_ORG' => 39,
			'ASTARI_OPR' => 59,
			'SMC_TOKEN' => 52,
			'END_TOKEN' => 48,
			'SQL_TOKEN' => 45,
			'SECTION_TOKEN' => 40,
			'BEGIN_TOKEN' => 43,
			'DECLARE_TOKEN' => 46,
			'TOOLS_TOKEN' => 49,
			'LP_TOKEN' => 57,
			'ORACLE_TOKEN' => 41,
			'EXEC_TOKEN' => 47
		},
		GOTOS => {
			'direct_declarator' => 58,
			'init_declarator' => 51,
			'IDENTIFIER' => 53,
			'pointer' => 55,
			'declarator' => 56,
			'init_declarator_list' => 54
		}
	},
	{#State 8
		DEFAULT => -129
	},
	{#State 9
		ACTIONS => {
			'EXTERN_TOKEN' => 3,
			'SHORT_TOKEN' => 2,
			'ENUM_TOKEN' => 1,
			'LONG_TOKEN' => 5,
			'INLINE_TOKEN' => 8,
			'SIGNED_TOKEN' => 12,
			'CHAR_TOKEN' => 13,
			'CONST_TOKEN' => 14,
			'STRUCT_TOKEN' => 15,
			'TNAME_TOKEN' => 16,
			'UNSIGNED_TOKEN' => 17,
			'FLOAT_TOKEN' => 18,
			'AUTO_TOKEN' => 19,
			'VOLATILE_TOKEN' => 21,
			'VOID_TOKEN' => 22,
			'DOUBLE_TOKEN' => 24,
			'INT_TOKEN' => 26,
			'_BOOL_TOKEN' => 27,
			'TYPEDEF_TOKEN' => 29,
			'_COMPLEX_TOKEN' => 32,
			'REGISTER_TOKEN' => 34,
			'RESTRICT_TOKEN' => 35,
			'UNION_TOKEN' => 36,
			'STATIC_TOKEN' => 37
		},
		DEFAULT => -72,
		GOTOS => {
			'struct_or_union' => 33,
			'function_specifier' => 4,
			'declaration_specifiers' => 60,
			'struct_or_union_specifier' => 28,
			'type_qualifier' => 9,
			'type_specifier' => 38,
			'storage_class_specifier' => 10,
			'enum_specifier' => 30
		}
	},
	{#State 10
		ACTIONS => {
			'EXTERN_TOKEN' => 3,
			'SHORT_TOKEN' => 2,
			'ENUM_TOKEN' => 1,
			'LONG_TOKEN' => 5,
			'INLINE_TOKEN' => 8,
			'SIGNED_TOKEN' => 12,
			'CHAR_TOKEN' => 13,
			'CONST_TOKEN' => 14,
			'STRUCT_TOKEN' => 15,
			'TNAME_TOKEN' => 16,
			'UNSIGNED_TOKEN' => 17,
			'FLOAT_TOKEN' => 18,
			'AUTO_TOKEN' => 19,
			'VOLATILE_TOKEN' => 21,
			'VOID_TOKEN' => 22,
			'DOUBLE_TOKEN' => 24,
			'INT_TOKEN' => 26,
			'_BOOL_TOKEN' => 27,
			'TYPEDEF_TOKEN' => 29,
			'_COMPLEX_TOKEN' => 32,
			'REGISTER_TOKEN' => 34,
			'RESTRICT_TOKEN' => 35,
			'UNION_TOKEN' => 36,
			'STATIC_TOKEN' => 37
		},
		DEFAULT => -68,
		GOTOS => {
			'struct_or_union' => 33,
			'function_specifier' => 4,
			'declaration_specifiers' => 61,
			'struct_or_union_specifier' => 28,
			'type_qualifier' => 9,
			'type_specifier' => 38,
			'storage_class_specifier' => 10,
			'enum_specifier' => 30
		}
	},
	{#State 11
		DEFAULT => -232
	},
	{#State 12
		DEFAULT => -92
	},
	{#State 13
		DEFAULT => -86
	},
	{#State 14
		DEFAULT => -126
	},
	{#State 15
		DEFAULT => -102
	},
	{#State 16
		DEFAULT => -98
	},
	{#State 17
		DEFAULT => -93
	},
	{#State 18
		DEFAULT => -90
	},
	{#State 19
		DEFAULT => -83
	},
	{#State 20
		ACTIONS => {
			'VOLATILE_TOKEN' => 21,
			'' => 62,
			'EXTERN_TOKEN' => 3,
			'SHORT_TOKEN' => 2,
			'ENUM_TOKEN' => 1,
			'LONG_TOKEN' => 5,
			'VOID_TOKEN' => 22,
			'DOUBLE_TOKEN' => 24,
			'INT_TOKEN' => 26,
			'_BOOL_TOKEN' => 27,
			'INLINE_TOKEN' => 8,
			'TYPEDEF_TOKEN' => 29,
			'EXEC_TOKEN' => 31,
			'_COMPLEX_TOKEN' => 32,
			'SIGNED_TOKEN' => 12,
			'CHAR_TOKEN' => 13,
			'REGISTER_TOKEN' => 34,
			'CONST_TOKEN' => 14,
			'RESTRICT_TOKEN' => 35,
			'UNION_TOKEN' => 36,
			'STRUCT_TOKEN' => 15,
			'STATIC_TOKEN' => 37,
			'TNAME_TOKEN' => 16,
			'UNSIGNED_TOKEN' => 17,
			'FLOAT_TOKEN' => 18,
			'AUTO_TOKEN' => 19
		},
		GOTOS => {
			'struct_or_union' => 33,
			'function_specifier' => 4,
			'external_declaration' => 63,
			'embedded_sql' => 6,
			'declaration_specifiers' => 7,
			'declaration' => 25,
			'struct_or_union_specifier' => 28,
			'type_specifier' => 38,
			'type_qualifier' => 9,
			'storage_class_specifier' => 10,
			'function_definition' => 11,
			'enum_specifier' => 30
		}
	},
	{#State 21
		DEFAULT => -128
	},
	{#State 22
		DEFAULT => -85
	},
	{#State 23
		DEFAULT => -230
	},
	{#State 24
		DEFAULT => -91
	},
	{#State 25
		DEFAULT => -233
	},
	{#State 26
		DEFAULT => -88
	},
	{#State 27
		DEFAULT => -94
	},
	{#State 28
		DEFAULT => -96
	},
	{#State 29
		DEFAULT => -80
	},
	{#State 30
		DEFAULT => -97
	},
	{#State 31
		ACTIONS => {
			'SQL_TOKEN' => 65,
			'TOOLS_TOKEN' => 66,
			'ORACLE_TOKEN' => 64
		}
	},
	{#State 32
		DEFAULT => -95
	},
	{#State 33
		ACTIONS => {
			'IDENTIFIER_ORG' => 39,
			'LCB_TOKEN' => 68,
			'END_TOKEN' => 48,
			'SQL_TOKEN' => 45,
			'SECTION_TOKEN' => 40,
			'BEGIN_TOKEN' => 43,
			'DECLARE_TOKEN' => 46,
			'TOOLS_TOKEN' => 49,
			'ORACLE_TOKEN' => 41,
			'EXEC_TOKEN' => 47
		},
		GOTOS => {
			'IDENTIFIER' => 67
		}
	},
	{#State 34
		DEFAULT => -84
	},
	{#State 35
		DEFAULT => -127
	},
	{#State 36
		DEFAULT => -103
	},
	{#State 37
		DEFAULT => -82
	},
	{#State 38
		ACTIONS => {
			'EXTERN_TOKEN' => 3,
			'SHORT_TOKEN' => 2,
			'ENUM_TOKEN' => 1,
			'LONG_TOKEN' => 5,
			'INLINE_TOKEN' => 8,
			'SIGNED_TOKEN' => 12,
			'CHAR_TOKEN' => 13,
			'CONST_TOKEN' => 14,
			'STRUCT_TOKEN' => 15,
			'TNAME_TOKEN' => 16,
			'UNSIGNED_TOKEN' => 17,
			'FLOAT_TOKEN' => 18,
			'AUTO_TOKEN' => 19,
			'VOLATILE_TOKEN' => 21,
			'VOID_TOKEN' => 22,
			'DOUBLE_TOKEN' => 24,
			'INT_TOKEN' => 26,
			'_BOOL_TOKEN' => 27,
			'TYPEDEF_TOKEN' => 29,
			'_COMPLEX_TOKEN' => 32,
			'REGISTER_TOKEN' => 34,
			'RESTRICT_TOKEN' => 35,
			'UNION_TOKEN' => 36,
			'STATIC_TOKEN' => 37
		},
		DEFAULT => -70,
		GOTOS => {
			'struct_or_union' => 33,
			'function_specifier' => 4,
			'declaration_specifiers' => 69,
			'struct_or_union_specifier' => 28,
			'type_qualifier' => 9,
			'type_specifier' => 38,
			'storage_class_specifier' => 10,
			'enum_specifier' => 30
		}
	},
	{#State 39
		DEFAULT => -320
	},
	{#State 40
		DEFAULT => -328
	},
	{#State 41
		DEFAULT => -323
	},
	{#State 42
		ACTIONS => {
			'LCB_TOKEN' => 70
		},
		DEFAULT => -120
	},
	{#State 43
		DEFAULT => -325
	},
	{#State 44
		ACTIONS => {
			'IDENTIFIER_ORG' => 39,
			'SQL_TOKEN' => 45,
			'END_TOKEN' => 48,
			'SECTION_TOKEN' => 40,
			'BEGIN_TOKEN' => 43,
			'DECLARE_TOKEN' => 46,
			'TOOLS_TOKEN' => 49,
			'ORACLE_TOKEN' => 41,
			'EXEC_TOKEN' => 47
		},
		GOTOS => {
			'enumeration_constant' => 74,
			'enumerator' => 73,
			'IDENTIFIER' => 72,
			'enumerator_list' => 71
		}
	},
	{#State 45
		DEFAULT => -322
	},
	{#State 46
		DEFAULT => -327
	},
	{#State 47
		DEFAULT => -321
	},
	{#State 48
		DEFAULT => -326
	},
	{#State 49
		DEFAULT => -324
	},
	{#State 50
		DEFAULT => -75
	},
	{#State 51
		DEFAULT => -76
	},
	{#State 52
		DEFAULT => -67
	},
	{#State 53
		DEFAULT => -132
	},
	{#State 54
		ACTIONS => {
			'CM_TOKEN' => 76,
			'SMC_TOKEN' => 75
		}
	},
	{#State 55
		ACTIONS => {
			'IDENTIFIER_ORG' => 39,
			'END_TOKEN' => 48,
			'SQL_TOKEN' => 45,
			'SECTION_TOKEN' => 40,
			'BEGIN_TOKEN' => 43,
			'DECLARE_TOKEN' => 46,
			'TOOLS_TOKEN' => 49,
			'ORACLE_TOKEN' => 41,
			'EXEC_TOKEN' => 47,
			'LP_TOKEN' => 57
		},
		GOTOS => {
			'direct_declarator' => 77,
			'IDENTIFIER' => 53
		}
	},
	{#State 56
		ACTIONS => {
			'VOLATILE_TOKEN' => 21,
			'EXTERN_TOKEN' => 3,
			'SHORT_TOKEN' => 2,
			'ENUM_TOKEN' => 1,
			'LONG_TOKEN' => 5,
			'VOID_TOKEN' => 22,
			'LCB_TOKEN' => 80,
			'DOUBLE_TOKEN' => 24,
			'INT_TOKEN' => 26,
			'_BOOL_TOKEN' => 27,
			'INLINE_TOKEN' => 8,
			'TYPEDEF_TOKEN' => 29,
			'_COMPLEX_TOKEN' => 32,
			'SIGNED_TOKEN' => 12,
			'CHAR_TOKEN' => 13,
			'REGISTER_TOKEN' => 34,
			'CONST_TOKEN' => 14,
			'RESTRICT_TOKEN' => 35,
			'UNION_TOKEN' => 36,
			'STRUCT_TOKEN' => 15,
			'EQUAL_OPR' => 79,
			'STATIC_TOKEN' => 37,
			'TNAME_TOKEN' => 16,
			'UNSIGNED_TOKEN' => 17,
			'FLOAT_TOKEN' => 18,
			'AUTO_TOKEN' => 19
		},
		DEFAULT => -78,
		GOTOS => {
			'struct_or_union' => 33,
			'function_specifier' => 4,
			'compound_statement' => 82,
			'declaration_specifiers' => 78,
			'declaration' => 81,
			'struct_or_union_specifier' => 28,
			'type_specifier' => 38,
			'type_qualifier' => 9,
			'declaration_list' => 83,
			'storage_class_specifier' => 10,
			'enum_specifier' => 30
		}
	},
	{#State 57
		ACTIONS => {
			'IDENTIFIER_ORG' => 39,
			'ASTARI_OPR' => 59,
			'END_TOKEN' => 48,
			'SQL_TOKEN' => 45,
			'SECTION_TOKEN' => 40,
			'BEGIN_TOKEN' => 43,
			'DECLARE_TOKEN' => 46,
			'TOOLS_TOKEN' => 49,
			'ORACLE_TOKEN' => 41,
			'EXEC_TOKEN' => 47,
			'LP_TOKEN' => 57
		},
		GOTOS => {
			'direct_declarator' => 58,
			'IDENTIFIER' => 53,
			'pointer' => 55,
			'declarator' => 84
		}
	},
	{#State 58
		ACTIONS => {
			'LSB_TOKEN' => 85,
			'LP_TOKEN' => 86
		},
		DEFAULT => -131
	},
	{#State 59
		ACTIONS => {
			'VOLATILE_TOKEN' => 21,
			'CONST_TOKEN' => 14,
			'RESTRICT_TOKEN' => 35,
			'ASTARI_OPR' => 59
		},
		DEFAULT => -147,
		GOTOS => {
			'pointer' => 88,
			'type_qualifier' => 87,
			'type_qualifier_list' => 89
		}
	},
	{#State 60
		DEFAULT => -73
	},
	{#State 61
		DEFAULT => -69
	},
	{#State 62
		DEFAULT => 0
	},
	{#State 63
		DEFAULT => -231
	},
	{#State 64
		ACTIONS => {
			'ENUM_TOKEN' => 92,
			'EXTERN_TOKEN' => 91,
			'SHORT_TOKEN' => 90,
			'LONG_TOKEN' => 93,
			'CM_TOKEN' => 94,
			'INLINE_TOKEN' => 95,
			'DO_TOKEN' => 96,
			'SIGNED_TOKEN' => 98,
			'CONST_TOKEN' => 99,
			'PLUS_OPR' => 100,
			'FOR_TOKEN' => 101,
			'PUBLIC_TOKEN' => 102,
			'SWITCH_TOKEN' => 103,
			'UNSIGNED_TOKEN' => 104,
			'CLN_TOKEN' => 105,
			'PREFIX_OPR' => 106,
			'FLOAT_TOKEN' => 107,
			'AUTO_TOKEN' => 108,
			'AMP_OPR' => 110,
			'RETURN_TOKEN' => 111,
			'RP_TOKEN' => 112,
			'INTEGER_LITERAL' => 113,
			'VOID_TOKEN' => 114,
			'COR_OPR' => 116,
			'DOUBLE_TOKEN' => 117,
			'GT_OPR' => 118,
			'MULTI_OPR' => 119,
			'TYPEDEF_TOKEN' => 120,
			'EXEC_TOKEN' => 121,
			'POSTFIX_OPR' => 122,
			'LP_TOKEN' => 123,
			'_COMPLEX_TOKEN' => 124,
			'REGISTER_TOKEN' => 125,
			'RESTRICT_TOKEN' => 126,
			'ASTARI_OPR' => 127,
			'PRIVATE_TOKEN' => 128,
			'ATMARK_TOKEN' => 129,
			'STRING_LITERAL' => 130,
			'DEFAULT_TOKEN' => 131,
			'IDENTIFIER_ORG' => 132,
			'INEQUALITY_OPR' => 133,
			'MINUS_OPR' => 134,
			'SMC_TOKEN' => 135,
			'LSB_TOKEN' => 136,
			'WHILE_TOKEN' => 137,
			'ELSE_TOKEN' => 138,
			'PTR_OPR' => 139,
			'CASE_TOKEN' => 140,
			'FLOAT_LITERAL' => 141,
			'DOT_TOKEN' => 142,
			'CHAR_TOKEN' => 143,
			'CHAR_LITERAL' => 144,
			'STRUCT_TOKEN' => 145,
			'EQUAL_OPR' => 146,
			'TNAME_TOKEN' => 147,
			'BEGIN_TOKEN' => 148,
			'SIZEOF_TOKEN' => 149,
			'VOLATILE_TOKEN' => 150,
			'_IMAGINARY_TOKEN' => 151,
			'PROTECTED_TOKEN' => 152,
			'INT_TOKEN' => 153,
			'DECLARE_TOKEN' => 154,
			'CONTINUE_TOKEN' => 155,
			'_BOOL_TOKEN' => 156,
			'GOTO_TOKEN' => 157,
			'RSB_TOKEN' => 158,
			'IF_TOKEN' => 160,
			'BREAK_TOKEN' => 159,
			'ASSIGN_OPR' => 161,
			'UNION_TOKEN' => 162,
			'EQUALITY_OPR' => 163,
			'END_TOKEN' => 164,
			'STATIC_TOKEN' => 166,
			'RELATIONAL_OPR' => 165,
			'NEW_TOKEN' => 168,
			'LT_OPR' => 167,
			'QUES_TOKEN' => 169
		},
		GOTOS => {
			'unary_operator' => 97,
			'emb_string_list' => 115,
			'emb_constant_string' => 109
		}
	},
	{#State 65
		ACTIONS => {
			'ENUM_TOKEN' => 92,
			'EXTERN_TOKEN' => 91,
			'SHORT_TOKEN' => 90,
			'LONG_TOKEN' => 93,
			'CM_TOKEN' => 94,
			'INLINE_TOKEN' => 95,
			'DO_TOKEN' => 96,
			'SIGNED_TOKEN' => 98,
			'CONST_TOKEN' => 99,
			'PLUS_OPR' => 100,
			'FOR_TOKEN' => 101,
			'PUBLIC_TOKEN' => 102,
			'SWITCH_TOKEN' => 103,
			'UNSIGNED_TOKEN' => 104,
			'CLN_TOKEN' => 105,
			'PREFIX_OPR' => 106,
			'FLOAT_TOKEN' => 107,
			'AUTO_TOKEN' => 108,
			'AMP_OPR' => 110,
			'RETURN_TOKEN' => 111,
			'RP_TOKEN' => 112,
			'INTEGER_LITERAL' => 113,
			'VOID_TOKEN' => 114,
			'COR_OPR' => 116,
			'DOUBLE_TOKEN' => 117,
			'GT_OPR' => 118,
			'MULTI_OPR' => 119,
			'TYPEDEF_TOKEN' => 120,
			'EXEC_TOKEN' => 121,
			'POSTFIX_OPR' => 122,
			'LP_TOKEN' => 123,
			'_COMPLEX_TOKEN' => 124,
			'REGISTER_TOKEN' => 125,
			'RESTRICT_TOKEN' => 126,
			'ASTARI_OPR' => 127,
			'PRIVATE_TOKEN' => 128,
			'ATMARK_TOKEN' => 129,
			'STRING_LITERAL' => 130,
			'DEFAULT_TOKEN' => 131,
			'IDENTIFIER_ORG' => 132,
			'INEQUALITY_OPR' => 133,
			'MINUS_OPR' => 134,
			'SMC_TOKEN' => 135,
			'LSB_TOKEN' => 136,
			'WHILE_TOKEN' => 137,
			'ELSE_TOKEN' => 138,
			'PTR_OPR' => 139,
			'CASE_TOKEN' => 140,
			'FLOAT_LITERAL' => 141,
			'DOT_TOKEN' => 142,
			'CHAR_TOKEN' => 143,
			'CHAR_LITERAL' => 144,
			'STRUCT_TOKEN' => 145,
			'EQUAL_OPR' => 146,
			'TNAME_TOKEN' => 147,
			'BEGIN_TOKEN' => 172,
			'VOLATILE_TOKEN' => 150,
			'SIZEOF_TOKEN' => 149,
			'_IMAGINARY_TOKEN' => 151,
			'PROTECTED_TOKEN' => 152,
			'INT_TOKEN' => 153,
			'_BOOL_TOKEN' => 156,
			'CONTINUE_TOKEN' => 155,
			'DECLARE_TOKEN' => 154,
			'GOTO_TOKEN' => 157,
			'RSB_TOKEN' => 158,
			'BREAK_TOKEN' => 159,
			'IF_TOKEN' => 160,
			'ASSIGN_OPR' => 161,
			'UNION_TOKEN' => 162,
			'EQUALITY_OPR' => 163,
			'END_TOKEN' => 173,
			'RELATIONAL_OPR' => 165,
			'STATIC_TOKEN' => 166,
			'LT_OPR' => 167,
			'NEW_TOKEN' => 168,
			'QUES_TOKEN' => 169
		},
		GOTOS => {
			'emb_declare' => 171,
			'unary_operator' => 97,
			'emb_string_list' => 170,
			'emb_constant_string' => 109
		}
	},
	{#State 66
		ACTIONS => {
			'ENUM_TOKEN' => 92,
			'EXTERN_TOKEN' => 91,
			'SHORT_TOKEN' => 90,
			'LONG_TOKEN' => 93,
			'CM_TOKEN' => 94,
			'INLINE_TOKEN' => 95,
			'DO_TOKEN' => 96,
			'SIGNED_TOKEN' => 98,
			'CONST_TOKEN' => 99,
			'PLUS_OPR' => 100,
			'FOR_TOKEN' => 101,
			'PUBLIC_TOKEN' => 102,
			'SWITCH_TOKEN' => 103,
			'UNSIGNED_TOKEN' => 104,
			'CLN_TOKEN' => 105,
			'PREFIX_OPR' => 106,
			'FLOAT_TOKEN' => 107,
			'AUTO_TOKEN' => 108,
			'AMP_OPR' => 110,
			'RETURN_TOKEN' => 111,
			'RP_TOKEN' => 112,
			'INTEGER_LITERAL' => 113,
			'VOID_TOKEN' => 114,
			'COR_OPR' => 116,
			'DOUBLE_TOKEN' => 117,
			'GT_OPR' => 118,
			'MULTI_OPR' => 119,
			'TYPEDEF_TOKEN' => 120,
			'EXEC_TOKEN' => 121,
			'POSTFIX_OPR' => 122,
			'LP_TOKEN' => 123,
			'_COMPLEX_TOKEN' => 124,
			'REGISTER_TOKEN' => 125,
			'RESTRICT_TOKEN' => 126,
			'ASTARI_OPR' => 127,
			'PRIVATE_TOKEN' => 128,
			'ATMARK_TOKEN' => 129,
			'STRING_LITERAL' => 130,
			'DEFAULT_TOKEN' => 131,
			'IDENTIFIER_ORG' => 132,
			'INEQUALITY_OPR' => 133,
			'MINUS_OPR' => 134,
			'SMC_TOKEN' => 135,
			'LSB_TOKEN' => 136,
			'WHILE_TOKEN' => 137,
			'ELSE_TOKEN' => 138,
			'PTR_OPR' => 139,
			'CASE_TOKEN' => 140,
			'FLOAT_LITERAL' => 141,
			'DOT_TOKEN' => 142,
			'CHAR_TOKEN' => 143,
			'CHAR_LITERAL' => 144,
			'STRUCT_TOKEN' => 145,
			'EQUAL_OPR' => 146,
			'TNAME_TOKEN' => 147,
			'BEGIN_TOKEN' => 148,
			'VOLATILE_TOKEN' => 150,
			'SIZEOF_TOKEN' => 149,
			'_IMAGINARY_TOKEN' => 151,
			'PROTECTED_TOKEN' => 152,
			'INT_TOKEN' => 153,
			'_BOOL_TOKEN' => 156,
			'CONTINUE_TOKEN' => 155,
			'DECLARE_TOKEN' => 154,
			'GOTO_TOKEN' => 157,
			'RSB_TOKEN' => 158,
			'BREAK_TOKEN' => 159,
			'IF_TOKEN' => 160,
			'ASSIGN_OPR' => 161,
			'UNION_TOKEN' => 162,
			'EQUALITY_OPR' => 163,
			'END_TOKEN' => 164,
			'RELATIONAL_OPR' => 165,
			'STATIC_TOKEN' => 166,
			'LT_OPR' => 167,
			'NEW_TOKEN' => 168,
			'QUES_TOKEN' => 169
		},
		GOTOS => {
			'unary_operator' => 97,
			'emb_string_list' => 174,
			'emb_constant_string' => 109
		}
	},
	{#State 67
		ACTIONS => {
			'LCB_TOKEN' => 175
		},
		DEFAULT => -101
	},
	{#State 68
		ACTIONS => {
			'VOLATILE_TOKEN' => 21,
			'SHORT_TOKEN' => 2,
			'ENUM_TOKEN' => 1,
			'LONG_TOKEN' => 5,
			'VOID_TOKEN' => 22,
			'DOUBLE_TOKEN' => 24,
			'INT_TOKEN' => 26,
			'_BOOL_TOKEN' => 27,
			'_COMPLEX_TOKEN' => 32,
			'SIGNED_TOKEN' => 12,
			'CHAR_TOKEN' => 13,
			'CONST_TOKEN' => 14,
			'RESTRICT_TOKEN' => 35,
			'UNION_TOKEN' => 36,
			'STRUCT_TOKEN' => 15,
			'UNSIGNED_TOKEN' => 17,
			'TNAME_TOKEN' => 16,
			'FLOAT_TOKEN' => 18
		},
		GOTOS => {
			'struct_or_union' => 33,
			'struct_or_union_specifier' => 28,
			'type_qualifier' => 178,
			'type_specifier' => 177,
			'struct_declaration_list' => 180,
			'enum_specifier' => 30,
			'specifier_qualifier_list' => 179,
			'struct_declaration' => 176
		}
	},
	{#State 69
		DEFAULT => -71
	},
	{#State 70
		ACTIONS => {
			'IDENTIFIER_ORG' => 39,
			'END_TOKEN' => 48,
			'SQL_TOKEN' => 45,
			'SECTION_TOKEN' => 40,
			'BEGIN_TOKEN' => 43,
			'DECLARE_TOKEN' => 46,
			'EXEC_TOKEN' => 47,
			'TOOLS_TOKEN' => 49,
			'ORACLE_TOKEN' => 41
		},
		GOTOS => {
			'enumeration_constant' => 74,
			'IDENTIFIER' => 72,
			'enumerator' => 73,
			'enumerator_list' => 181
		}
	},
	{#State 71
		ACTIONS => {
			'CM_TOKEN' => 182,
			'RCB_TOKEN' => 183
		}
	},
	{#State 72
		DEFAULT => -125
	},
	{#State 73
		DEFAULT => -121
	},
	{#State 74
		ACTIONS => {
			'EQUAL_OPR' => 184
		},
		DEFAULT => -123
	},
	{#State 75
		DEFAULT => -66
	},
	{#State 76
		ACTIONS => {
			'IDENTIFIER_ORG' => 39,
			'ASTARI_OPR' => 59,
			'END_TOKEN' => 48,
			'SQL_TOKEN' => 45,
			'SECTION_TOKEN' => 40,
			'BEGIN_TOKEN' => 43,
			'DECLARE_TOKEN' => 46,
			'EXEC_TOKEN' => 47,
			'LP_TOKEN' => 57,
			'TOOLS_TOKEN' => 49,
			'ORACLE_TOKEN' => 41
		},
		GOTOS => {
			'direct_declarator' => 58,
			'init_declarator' => 185,
			'IDENTIFIER' => 53,
			'pointer' => 55,
			'declarator' => 186
		}
	},
	{#State 77
		ACTIONS => {
			'LSB_TOKEN' => 85,
			'LP_TOKEN' => 86
		},
		DEFAULT => -130
	},
	{#State 78
		ACTIONS => {
			'IDENTIFIER_ORG' => 39,
			'SMC_TOKEN' => 52,
			'ASTARI_OPR' => 59,
			'END_TOKEN' => 48,
			'SQL_TOKEN' => 45,
			'SECTION_TOKEN' => 40,
			'DECLARE_TOKEN' => 46,
			'BEGIN_TOKEN' => 43,
			'EXEC_TOKEN' => 47,
			'LP_TOKEN' => 57,
			'TOOLS_TOKEN' => 49,
			'ORACLE_TOKEN' => 41
		},
		GOTOS => {
			'direct_declarator' => 58,
			'init_declarator' => 51,
			'IDENTIFIER' => 53,
			'pointer' => 55,
			'init_declarator_list' => 54,
			'declarator' => 186
		}
	},
	{#State 79
		ACTIONS => {
			'SIZEOF_TOKEN' => 207,
			'AMP_OPR' => 110,
			'IDENTIFIER_ORG' => 39,
			'INTEGER_LITERAL' => 191,
			'MINUS_OPR' => 134,
			'LCB_TOKEN' => 192,
			'SQL_TOKEN' => 45,
			'SECTION_TOKEN' => 40,
			'DECLARE_TOKEN' => 46,
			'FLOAT_LITERAL' => 200,
			'ORACLE_TOKEN' => 41,
			'EXEC_TOKEN' => 47,
			'POSTFIX_OPR' => 194,
			'LP_TOKEN' => 195,
			'PLUS_OPR' => 100,
			'CHAR_LITERAL' => 204,
			'ASTARI_OPR' => 127,
			'END_TOKEN' => 48,
			'BEGIN_TOKEN' => 43,
			'PREFIX_OPR' => 106,
			'STRING_LITERAL' => 198,
			'TOOLS_TOKEN' => 49
		},
		GOTOS => {
			'logical_OR_expression' => 208,
			'conditional_expression' => 199,
			'primary_expression' => 209,
			'unary_operator' => 187,
			'unary_expression' => 193,
			'equality_expression' => 201,
			'IDENTIFIER' => 202,
			'shift_expression' => 203,
			'additive_expression' => 196,
			'postfix_expression' => 210,
			'exclusive_OR_expression' => 211,
			'inclusive_OR_expression' => 205,
			'relational_expression' => 197,
			'string_literal_list' => 212,
			'AND_expression' => 188,
			'multiplicative_expression' => 206,
			'logical_AND_expression' => 213,
			'assignment_expression' => 189,
			'cast_expression' => 214,
			'initializer' => 190
		}
	},
	{#State 80
		ACTIONS => {
			'DEFAULT_TOKEN' => 227,
			'EXTERN_TOKEN' => 3,
			'SHORT_TOKEN' => 2,
			'ENUM_TOKEN' => 1,
			'IDENTIFIER_ORG' => 39,
			'LONG_TOKEN' => 5,
			'MINUS_OPR' => 134,
			'SMC_TOKEN' => 229,
			'SECTION_TOKEN' => 40,
			'DO_TOKEN' => 216,
			'INLINE_TOKEN' => 8,
			'WHILE_TOKEN' => 231,
			'CASE_TOKEN' => 233,
			'FLOAT_LITERAL' => 200,
			'ORACLE_TOKEN' => 41,
			'CHAR_TOKEN' => 13,
			'SIGNED_TOKEN' => 12,
			'CONST_TOKEN' => 14,
			'PLUS_OPR' => 100,
			'FOR_TOKEN' => 218,
			'RCB_TOKEN' => 219,
			'CHAR_LITERAL' => 204,
			'STRUCT_TOKEN' => 15,
			'SWITCH_TOKEN' => 220,
			'TNAME_TOKEN' => 16,
			'UNSIGNED_TOKEN' => 17,
			'BEGIN_TOKEN' => 43,
			'PREFIX_OPR' => 106,
			'FLOAT_TOKEN' => 18,
			'AUTO_TOKEN' => 19,
			'SIZEOF_TOKEN' => 207,
			'VOLATILE_TOKEN' => 21,
			'AMP_OPR' => 110,
			'RETURN_TOKEN' => 223,
			'INTEGER_LITERAL' => 191,
			'VOID_TOKEN' => 22,
			'LCB_TOKEN' => 80,
			'SQL_TOKEN' => 45,
			'DOUBLE_TOKEN' => 24,
			'INT_TOKEN' => 26,
			'_BOOL_TOKEN' => 27,
			'CONTINUE_TOKEN' => 238,
			'DECLARE_TOKEN' => 46,
			'GOTO_TOKEN' => 239,
			'TYPEDEF_TOKEN' => 29,
			'EXEC_TOKEN' => 225,
			'POSTFIX_OPR' => 194,
			'LP_TOKEN' => 195,
			'_COMPLEX_TOKEN' => 32,
			'IF_TOKEN' => 241,
			'BREAK_TOKEN' => 240,
			'REGISTER_TOKEN' => 34,
			'RESTRICT_TOKEN' => 35,
			'UNION_TOKEN' => 36,
			'ASTARI_OPR' => 127,
			'END_TOKEN' => 48,
			'STATIC_TOKEN' => 37,
			'STRING_LITERAL' => 198,
			'TOOLS_TOKEN' => 49
		},
		GOTOS => {
			'function_specifier' => 4,
			'iteration_statement' => 215,
			'expression_statement' => 228,
			'conditional_expression' => 199,
			'embedded_sql' => 230,
			'declaration_specifiers' => 78,
			'statement' => 217,
			'expression' => 232,
			'type_qualifier' => 9,
			'storage_class_specifier' => 10,
			'unary_operator' => 187,
			'block_item_list' => 234,
			'block_item' => 235,
			'IDENTIFIER' => 236,
			'equality_expression' => 201,
			'shift_expression' => 203,
			'inclusive_OR_expression' => 205,
			'multiplicative_expression' => 206,
			'AND_expression' => 188,
			'assignment_expression' => 221,
			'selection_statement' => 222,
			'jump_statement' => 237,
			'logical_OR_expression' => 208,
			'primary_expression' => 209,
			'declaration' => 224,
			'struct_or_union_specifier' => 28,
			'unary_expression' => 193,
			'enum_specifier' => 30,
			'struct_or_union' => 33,
			'compound_statement' => 226,
			'labeled_statement' => 242,
			'postfix_expression' => 210,
			'additive_expression' => 196,
			'exclusive_OR_expression' => 211,
			'relational_expression' => 197,
			'string_literal_list' => 212,
			'type_specifier' => 38,
			'logical_AND_expression' => 213,
			'cast_expression' => 214
		}
	},
	{#State 81
		DEFAULT => -237
	},
	{#State 82
		DEFAULT => -235
	},
	{#State 83
		ACTIONS => {
			'VOLATILE_TOKEN' => 21,
			'EXTERN_TOKEN' => 3,
			'SHORT_TOKEN' => 2,
			'ENUM_TOKEN' => 1,
			'LONG_TOKEN' => 5,
			'VOID_TOKEN' => 22,
			'LCB_TOKEN' => 80,
			'DOUBLE_TOKEN' => 24,
			'INT_TOKEN' => 26,
			'_BOOL_TOKEN' => 27,
			'INLINE_TOKEN' => 8,
			'TYPEDEF_TOKEN' => 29,
			'_COMPLEX_TOKEN' => 32,
			'CHAR_TOKEN' => 13,
			'SIGNED_TOKEN' => 12,
			'CONST_TOKEN' => 14,
			'REGISTER_TOKEN' => 34,
			'RESTRICT_TOKEN' => 35,
			'UNION_TOKEN' => 36,
			'STRUCT_TOKEN' => 15,
			'STATIC_TOKEN' => 37,
			'TNAME_TOKEN' => 16,
			'UNSIGNED_TOKEN' => 17,
			'FLOAT_TOKEN' => 18,
			'AUTO_TOKEN' => 19
		},
		GOTOS => {
			'struct_or_union' => 33,
			'function_specifier' => 4,
			'compound_statement' => 244,
			'declaration_specifiers' => 78,
			'declaration' => 243,
			'struct_or_union_specifier' => 28,
			'type_specifier' => 38,
			'type_qualifier' => 9,
			'storage_class_specifier' => 10,
			'enum_specifier' => 30
		}
	},
	{#State 84
		ACTIONS => {
			'RP_TOKEN' => 245
		}
	},
	{#State 85
		ACTIONS => {
			'SIZEOF_TOKEN' => 207,
			'VOLATILE_TOKEN' => 21,
			'AMP_OPR' => 110,
			'IDENTIFIER_ORG' => 39,
			'INTEGER_LITERAL' => 191,
			'MINUS_OPR' => 134,
			'SQL_TOKEN' => 45,
			'SECTION_TOKEN' => 40,
			'DECLARE_TOKEN' => 46,
			'RSB_TOKEN' => 249,
			'FLOAT_LITERAL' => 200,
			'ORACLE_TOKEN' => 41,
			'EXEC_TOKEN' => 47,
			'POSTFIX_OPR' => 194,
			'LP_TOKEN' => 195,
			'CONST_TOKEN' => 14,
			'PLUS_OPR' => 100,
			'RESTRICT_TOKEN' => 35,
			'CHAR_LITERAL' => 204,
			'ASTARI_OPR' => 248,
			'END_TOKEN' => 48,
			'STATIC_TOKEN' => 250,
			'BEGIN_TOKEN' => 43,
			'PREFIX_OPR' => 106,
			'STRING_LITERAL' => 198,
			'TOOLS_TOKEN' => 49
		},
		GOTOS => {
			'logical_OR_expression' => 208,
			'conditional_expression' => 199,
			'primary_expression' => 209,
			'type_qualifier_list' => 247,
			'type_qualifier' => 87,
			'unary_operator' => 187,
			'unary_expression' => 193,
			'equality_expression' => 201,
			'IDENTIFIER' => 202,
			'shift_expression' => 203,
			'postfix_expression' => 210,
			'additive_expression' => 196,
			'exclusive_OR_expression' => 211,
			'inclusive_OR_expression' => 205,
			'relational_expression' => 197,
			'string_literal_list' => 212,
			'AND_expression' => 188,
			'multiplicative_expression' => 206,
			'logical_AND_expression' => 213,
			'assignment_expression' => 246,
			'cast_expression' => 214
		}
	},
	{#State 86
		ACTIONS => {
			'EXTERN_TOKEN' => 3,
			'SHORT_TOKEN' => 2,
			'ENUM_TOKEN' => 1,
			'IDENTIFIER_ORG' => 39,
			'LONG_TOKEN' => 5,
			'SECTION_TOKEN' => 40,
			'INLINE_TOKEN' => 8,
			'ORACLE_TOKEN' => 41,
			'CHAR_TOKEN' => 13,
			'SIGNED_TOKEN' => 12,
			'CONST_TOKEN' => 14,
			'STRUCT_TOKEN' => 15,
			'TNAME_TOKEN' => 16,
			'UNSIGNED_TOKEN' => 17,
			'BEGIN_TOKEN' => 43,
			'FLOAT_TOKEN' => 18,
			'AUTO_TOKEN' => 19,
			'VOLATILE_TOKEN' => 21,
			'RP_TOKEN' => 254,
			'VOID_TOKEN' => 22,
			'DOUBLE_TOKEN' => 24,
			'SQL_TOKEN' => 45,
			'INT_TOKEN' => 26,
			'DECLARE_TOKEN' => 46,
			'_BOOL_TOKEN' => 27,
			'TYPEDEF_TOKEN' => 29,
			'EXEC_TOKEN' => 47,
			'_COMPLEX_TOKEN' => 32,
			'REGISTER_TOKEN' => 34,
			'RESTRICT_TOKEN' => 35,
			'UNION_TOKEN' => 36,
			'END_TOKEN' => 48,
			'STATIC_TOKEN' => 37,
			'TOOLS_TOKEN' => 49
		},
		GOTOS => {
			'parameter_type_list' => 257,
			'struct_or_union' => 33,
			'IDENTIFIER' => 255,
			'function_specifier' => 4,
			'parameter_declaration' => 251,
			'declaration_specifiers' => 252,
			'identifier_list' => 253,
			'struct_or_union_specifier' => 28,
			'type_specifier' => 38,
			'type_qualifier' => 9,
			'storage_class_specifier' => 10,
			'enum_specifier' => 30,
			'parameter_list' => 256
		}
	},
	{#State 87
		DEFAULT => -150
	},
	{#State 88
		DEFAULT => -149
	},
	{#State 89
		ACTIONS => {
			'VOLATILE_TOKEN' => 21,
			'CONST_TOKEN' => 14,
			'RESTRICT_TOKEN' => 35,
			'ASTARI_OPR' => 59
		},
		DEFAULT => -146,
		GOTOS => {
			'pointer' => 259,
			'type_qualifier' => 258
		}
	},
	{#State 90
		DEFAULT => -294
	},
	{#State 91
		DEFAULT => -280
	},
	{#State 92
		DEFAULT => -279
	},
	{#State 93
		DEFAULT => -286
	},
	{#State 94
		DEFAULT => -263
	},
	{#State 95
		DEFAULT => -284
	},
	{#State 96
		DEFAULT => -254
	},
	{#State 97
		DEFAULT => -258
	},
	{#State 98
		DEFAULT => -295
	},
	{#State 99
		DEFAULT => -275
	},
	{#State 100
		DEFAULT => -27
	},
	{#State 101
		DEFAULT => -282
	},
	{#State 102
		DEFAULT => -290
	},
	{#State 103
		DEFAULT => -299
	},
	{#State 104
		DEFAULT => -302
	},
	{#State 105
		ACTIONS => {
			'IDENTIFIER_ORG' => 260
		}
	},
	{#State 106
		DEFAULT => -29
	},
	{#State 107
		DEFAULT => -281
	},
	{#State 108
		DEFAULT => -272
	},
	{#State 109
		DEFAULT => -245
	},
	{#State 110
		DEFAULT => -25
	},
	{#State 111
		DEFAULT => -293
	},
	{#State 112
		DEFAULT => -261
	},
	{#State 113
		DEFAULT => -249
	},
	{#State 114
		DEFAULT => -304
	},
	{#State 115
		ACTIONS => {
			'ENUM_TOKEN' => 92,
			'EXTERN_TOKEN' => 91,
			'SHORT_TOKEN' => 90,
			'LONG_TOKEN' => 93,
			'CM_TOKEN' => 94,
			'INLINE_TOKEN' => 95,
			'DO_TOKEN' => 96,
			'SIGNED_TOKEN' => 98,
			'CONST_TOKEN' => 99,
			'PLUS_OPR' => 100,
			'FOR_TOKEN' => 101,
			'PUBLIC_TOKEN' => 102,
			'SWITCH_TOKEN' => 103,
			'UNSIGNED_TOKEN' => 104,
			'CLN_TOKEN' => 105,
			'PREFIX_OPR' => 106,
			'FLOAT_TOKEN' => 107,
			'AUTO_TOKEN' => 108,
			'AMP_OPR' => 110,
			'RETURN_TOKEN' => 111,
			'RP_TOKEN' => 112,
			'INTEGER_LITERAL' => 113,
			'VOID_TOKEN' => 114,
			'COR_OPR' => 116,
			'DOUBLE_TOKEN' => 117,
			'GT_OPR' => 118,
			'MULTI_OPR' => 119,
			'TYPEDEF_TOKEN' => 120,
			'EXEC_TOKEN' => 121,
			'POSTFIX_OPR' => 122,
			'LP_TOKEN' => 123,
			'_COMPLEX_TOKEN' => 124,
			'REGISTER_TOKEN' => 125,
			'RESTRICT_TOKEN' => 126,
			'ASTARI_OPR' => 127,
			'PRIVATE_TOKEN' => 128,
			'ATMARK_TOKEN' => 129,
			'STRING_LITERAL' => 130,
			'DEFAULT_TOKEN' => 131,
			'IDENTIFIER_ORG' => 132,
			'INEQUALITY_OPR' => 133,
			'MINUS_OPR' => 134,
			'SMC_TOKEN' => 262,
			'LSB_TOKEN' => 136,
			'WHILE_TOKEN' => 137,
			'ELSE_TOKEN' => 138,
			'PTR_OPR' => 139,
			'CASE_TOKEN' => 140,
			'FLOAT_LITERAL' => 141,
			'DOT_TOKEN' => 142,
			'CHAR_TOKEN' => 143,
			'CHAR_LITERAL' => 144,
			'STRUCT_TOKEN' => 145,
			'EQUAL_OPR' => 146,
			'TNAME_TOKEN' => 147,
			'BEGIN_TOKEN' => 148,
			'VOLATILE_TOKEN' => 150,
			'SIZEOF_TOKEN' => 149,
			'_IMAGINARY_TOKEN' => 151,
			'PROTECTED_TOKEN' => 152,
			'INT_TOKEN' => 153,
			'_BOOL_TOKEN' => 156,
			'CONTINUE_TOKEN' => 155,
			'DECLARE_TOKEN' => 154,
			'GOTO_TOKEN' => 157,
			'RSB_TOKEN' => 158,
			'BREAK_TOKEN' => 159,
			'IF_TOKEN' => 160,
			'ASSIGN_OPR' => 161,
			'UNION_TOKEN' => 162,
			'EQUALITY_OPR' => 163,
			'END_TOKEN' => 164,
			'RELATIONAL_OPR' => 165,
			'STATIC_TOKEN' => 166,
			'LT_OPR' => 167,
			'NEW_TOKEN' => 168,
			'QUES_TOKEN' => 169
		},
		GOTOS => {
			'unary_operator' => 97,
			'emb_constant_string' => 261
		}
	},
	{#State 116
		DEFAULT => -313
	},
	{#State 117
		DEFAULT => -277
	},
	{#State 118
		DEFAULT => -266
	},
	{#State 119
		DEFAULT => -317
	},
	{#State 120
		DEFAULT => -300
	},
	{#State 121
		DEFAULT => -318
	},
	{#State 122
		DEFAULT => -310
	},
	{#State 123
		DEFAULT => -260
	},
	{#State 124
		DEFAULT => -270
	},
	{#State 125
		DEFAULT => -291
	},
	{#State 126
		DEFAULT => -292
	},
	{#State 127
		DEFAULT => -26
	},
	{#State 128
		DEFAULT => -288
	},
	{#State 129
		DEFAULT => -308
	},
	{#State 130
		DEFAULT => -251
	},
	{#State 131
		DEFAULT => -276
	},
	{#State 132
		DEFAULT => -247
	},
	{#State 133
		DEFAULT => -314
	},
	{#State 134
		DEFAULT => -28
	},
	{#State 135
		DEFAULT => -262
	},
	{#State 136
		DEFAULT => -315
	},
	{#State 137
		DEFAULT => -305
	},
	{#State 138
		DEFAULT => -278
	},
	{#State 139
		DEFAULT => -319
	},
	{#State 140
		DEFAULT => -273
	},
	{#State 141
		DEFAULT => -248
	},
	{#State 142
		DEFAULT => -264
	},
	{#State 143
		DEFAULT => -274
	},
	{#State 144
		DEFAULT => -250
	},
	{#State 145
		DEFAULT => -298
	},
	{#State 146
		DEFAULT => -259
	},
	{#State 147
		DEFAULT => -309
	},
	{#State 148
		DEFAULT => -306
	},
	{#State 149
		DEFAULT => -296
	},
	{#State 150
		DEFAULT => -303
	},
	{#State 151
		DEFAULT => -271
	},
	{#State 152
		DEFAULT => -289
	},
	{#State 153
		DEFAULT => -285
	},
	{#State 154
		DEFAULT => -253
	},
	{#State 155
		DEFAULT => -256
	},
	{#State 156
		DEFAULT => -269
	},
	{#State 157
		DEFAULT => -257
	},
	{#State 158
		DEFAULT => -316
	},
	{#State 159
		DEFAULT => -255
	},
	{#State 160
		DEFAULT => -283
	},
	{#State 161
		DEFAULT => -312
	},
	{#State 162
		DEFAULT => -301
	},
	{#State 163
		DEFAULT => -311
	},
	{#State 164
		DEFAULT => -307
	},
	{#State 165
		DEFAULT => -268
	},
	{#State 166
		DEFAULT => -297
	},
	{#State 167
		DEFAULT => -267
	},
	{#State 168
		DEFAULT => -287
	},
	{#State 169
		DEFAULT => -265
	},
	{#State 170
		ACTIONS => {
			'ENUM_TOKEN' => 92,
			'EXTERN_TOKEN' => 91,
			'SHORT_TOKEN' => 90,
			'LONG_TOKEN' => 93,
			'CM_TOKEN' => 94,
			'INLINE_TOKEN' => 95,
			'DO_TOKEN' => 96,
			'SIGNED_TOKEN' => 98,
			'CONST_TOKEN' => 99,
			'PLUS_OPR' => 100,
			'FOR_TOKEN' => 101,
			'PUBLIC_TOKEN' => 102,
			'SWITCH_TOKEN' => 103,
			'UNSIGNED_TOKEN' => 104,
			'CLN_TOKEN' => 105,
			'PREFIX_OPR' => 106,
			'FLOAT_TOKEN' => 107,
			'AUTO_TOKEN' => 108,
			'AMP_OPR' => 110,
			'RETURN_TOKEN' => 111,
			'RP_TOKEN' => 112,
			'INTEGER_LITERAL' => 113,
			'VOID_TOKEN' => 114,
			'COR_OPR' => 116,
			'DOUBLE_TOKEN' => 117,
			'GT_OPR' => 118,
			'MULTI_OPR' => 119,
			'TYPEDEF_TOKEN' => 120,
			'EXEC_TOKEN' => 121,
			'POSTFIX_OPR' => 122,
			'LP_TOKEN' => 123,
			'_COMPLEX_TOKEN' => 124,
			'REGISTER_TOKEN' => 125,
			'RESTRICT_TOKEN' => 126,
			'ASTARI_OPR' => 127,
			'PRIVATE_TOKEN' => 128,
			'ATMARK_TOKEN' => 129,
			'STRING_LITERAL' => 130,
			'DEFAULT_TOKEN' => 131,
			'IDENTIFIER_ORG' => 132,
			'INEQUALITY_OPR' => 133,
			'MINUS_OPR' => 134,
			'SMC_TOKEN' => 263,
			'LSB_TOKEN' => 136,
			'WHILE_TOKEN' => 137,
			'ELSE_TOKEN' => 138,
			'PTR_OPR' => 139,
			'CASE_TOKEN' => 140,
			'FLOAT_LITERAL' => 141,
			'DOT_TOKEN' => 142,
			'CHAR_TOKEN' => 143,
			'CHAR_LITERAL' => 144,
			'STRUCT_TOKEN' => 145,
			'EQUAL_OPR' => 146,
			'TNAME_TOKEN' => 147,
			'BEGIN_TOKEN' => 148,
			'VOLATILE_TOKEN' => 150,
			'SIZEOF_TOKEN' => 149,
			'_IMAGINARY_TOKEN' => 151,
			'PROTECTED_TOKEN' => 152,
			'INT_TOKEN' => 153,
			'_BOOL_TOKEN' => 156,
			'CONTINUE_TOKEN' => 155,
			'DECLARE_TOKEN' => 154,
			'GOTO_TOKEN' => 157,
			'RSB_TOKEN' => 158,
			'BREAK_TOKEN' => 159,
			'IF_TOKEN' => 160,
			'ASSIGN_OPR' => 161,
			'UNION_TOKEN' => 162,
			'EQUALITY_OPR' => 163,
			'END_TOKEN' => 164,
			'RELATIONAL_OPR' => 165,
			'STATIC_TOKEN' => 166,
			'LT_OPR' => 167,
			'NEW_TOKEN' => 168,
			'QUES_TOKEN' => 169
		},
		GOTOS => {
			'unary_operator' => 97,
			'emb_constant_string' => 261
		}
	},
	{#State 171
		ACTIONS => {
			'SMC_TOKEN' => 264
		}
	},
	{#State 172
		ACTIONS => {
			'DECLARE_TOKEN' => 265
		},
		DEFAULT => -306
	},
	{#State 173
		ACTIONS => {
			'DECLARE_TOKEN' => 266
		},
		DEFAULT => -307
	},
	{#State 174
		ACTIONS => {
			'ENUM_TOKEN' => 92,
			'EXTERN_TOKEN' => 91,
			'SHORT_TOKEN' => 90,
			'LONG_TOKEN' => 93,
			'CM_TOKEN' => 94,
			'INLINE_TOKEN' => 95,
			'DO_TOKEN' => 96,
			'SIGNED_TOKEN' => 98,
			'CONST_TOKEN' => 99,
			'PLUS_OPR' => 100,
			'FOR_TOKEN' => 101,
			'PUBLIC_TOKEN' => 102,
			'SWITCH_TOKEN' => 103,
			'UNSIGNED_TOKEN' => 104,
			'CLN_TOKEN' => 105,
			'PREFIX_OPR' => 106,
			'FLOAT_TOKEN' => 107,
			'AUTO_TOKEN' => 108,
			'AMP_OPR' => 110,
			'RETURN_TOKEN' => 111,
			'RP_TOKEN' => 112,
			'INTEGER_LITERAL' => 113,
			'VOID_TOKEN' => 114,
			'COR_OPR' => 116,
			'DOUBLE_TOKEN' => 117,
			'GT_OPR' => 118,
			'MULTI_OPR' => 119,
			'TYPEDEF_TOKEN' => 120,
			'EXEC_TOKEN' => 121,
			'POSTFIX_OPR' => 122,
			'LP_TOKEN' => 123,
			'_COMPLEX_TOKEN' => 124,
			'REGISTER_TOKEN' => 125,
			'RESTRICT_TOKEN' => 126,
			'ASTARI_OPR' => 127,
			'PRIVATE_TOKEN' => 128,
			'ATMARK_TOKEN' => 129,
			'STRING_LITERAL' => 130,
			'DEFAULT_TOKEN' => 131,
			'IDENTIFIER_ORG' => 132,
			'INEQUALITY_OPR' => 133,
			'MINUS_OPR' => 134,
			'SMC_TOKEN' => 267,
			'LSB_TOKEN' => 136,
			'WHILE_TOKEN' => 137,
			'ELSE_TOKEN' => 138,
			'PTR_OPR' => 139,
			'CASE_TOKEN' => 140,
			'FLOAT_LITERAL' => 141,
			'DOT_TOKEN' => 142,
			'CHAR_TOKEN' => 143,
			'CHAR_LITERAL' => 144,
			'STRUCT_TOKEN' => 145,
			'EQUAL_OPR' => 146,
			'TNAME_TOKEN' => 147,
			'BEGIN_TOKEN' => 148,
			'VOLATILE_TOKEN' => 150,
			'SIZEOF_TOKEN' => 149,
			'_IMAGINARY_TOKEN' => 151,
			'PROTECTED_TOKEN' => 152,
			'INT_TOKEN' => 153,
			'_BOOL_TOKEN' => 156,
			'CONTINUE_TOKEN' => 155,
			'DECLARE_TOKEN' => 154,
			'GOTO_TOKEN' => 157,
			'RSB_TOKEN' => 158,
			'BREAK_TOKEN' => 159,
			'IF_TOKEN' => 160,
			'ASSIGN_OPR' => 161,
			'UNION_TOKEN' => 162,
			'EQUALITY_OPR' => 163,
			'END_TOKEN' => 164,
			'RELATIONAL_OPR' => 165,
			'STATIC_TOKEN' => 166,
			'LT_OPR' => 167,
			'NEW_TOKEN' => 168,
			'QUES_TOKEN' => 169
		},
		GOTOS => {
			'unary_operator' => 97,
			'emb_constant_string' => 261
		}
	},
	{#State 175
		ACTIONS => {
			'VOLATILE_TOKEN' => 21,
			'SHORT_TOKEN' => 2,
			'ENUM_TOKEN' => 1,
			'LONG_TOKEN' => 5,
			'VOID_TOKEN' => 22,
			'DOUBLE_TOKEN' => 24,
			'INT_TOKEN' => 26,
			'_BOOL_TOKEN' => 27,
			'_COMPLEX_TOKEN' => 32,
			'SIGNED_TOKEN' => 12,
			'CHAR_TOKEN' => 13,
			'CONST_TOKEN' => 14,
			'RESTRICT_TOKEN' => 35,
			'UNION_TOKEN' => 36,
			'STRUCT_TOKEN' => 15,
			'UNSIGNED_TOKEN' => 17,
			'TNAME_TOKEN' => 16,
			'FLOAT_TOKEN' => 18
		},
		GOTOS => {
			'struct_or_union' => 33,
			'struct_or_union_specifier' => 28,
			'type_qualifier' => 178,
			'type_specifier' => 177,
			'struct_declaration_list' => 268,
			'enum_specifier' => 30,
			'specifier_qualifier_list' => 179,
			'struct_declaration' => 176
		}
	},
	{#State 176
		DEFAULT => -104
	},
	{#State 177
		ACTIONS => {
			'SHORT_TOKEN' => 2,
			'ENUM_TOKEN' => 1,
			'LONG_TOKEN' => 5,
			'SIGNED_TOKEN' => 12,
			'CHAR_TOKEN' => 13,
			'CONST_TOKEN' => 14,
			'STRUCT_TOKEN' => 15,
			'UNSIGNED_TOKEN' => 17,
			'TNAME_TOKEN' => 16,
			'FLOAT_TOKEN' => 18,
			'VOLATILE_TOKEN' => 21,
			'VOID_TOKEN' => 22,
			'DOUBLE_TOKEN' => 24,
			'INT_TOKEN' => 26,
			'_BOOL_TOKEN' => 27,
			'_COMPLEX_TOKEN' => 32,
			'RESTRICT_TOKEN' => 35,
			'UNION_TOKEN' => 36
		},
		DEFAULT => -108,
		GOTOS => {
			'struct_or_union' => 33,
			'struct_or_union_specifier' => 28,
			'type_qualifier' => 178,
			'type_specifier' => 177,
			'enum_specifier' => 30,
			'specifier_qualifier_list' => 269
		}
	},
	{#State 178
		ACTIONS => {
			'SHORT_TOKEN' => 2,
			'ENUM_TOKEN' => 1,
			'LONG_TOKEN' => 5,
			'SIGNED_TOKEN' => 12,
			'CHAR_TOKEN' => 13,
			'CONST_TOKEN' => 14,
			'STRUCT_TOKEN' => 15,
			'UNSIGNED_TOKEN' => 17,
			'TNAME_TOKEN' => 16,
			'FLOAT_TOKEN' => 18,
			'VOLATILE_TOKEN' => 21,
			'VOID_TOKEN' => 22,
			'DOUBLE_TOKEN' => 24,
			'INT_TOKEN' => 26,
			'_BOOL_TOKEN' => 27,
			'_COMPLEX_TOKEN' => 32,
			'RESTRICT_TOKEN' => 35,
			'UNION_TOKEN' => 36
		},
		DEFAULT => -110,
		GOTOS => {
			'struct_or_union' => 33,
			'struct_or_union_specifier' => 28,
			'type_qualifier' => 178,
			'type_specifier' => 177,
			'enum_specifier' => 30,
			'specifier_qualifier_list' => 270
		}
	},
	{#State 179
		ACTIONS => {
			'IDENTIFIER_ORG' => 39,
			'ASTARI_OPR' => 59,
			'END_TOKEN' => 48,
			'SQL_TOKEN' => 45,
			'SECTION_TOKEN' => 40,
			'DECLARE_TOKEN' => 46,
			'BEGIN_TOKEN' => 43,
			'CLN_TOKEN' => 271,
			'EXEC_TOKEN' => 47,
			'LP_TOKEN' => 57,
			'TOOLS_TOKEN' => 49,
			'ORACLE_TOKEN' => 41
		},
		GOTOS => {
			'direct_declarator' => 58,
			'IDENTIFIER' => 53,
			'pointer' => 55,
			'struct_declarator_list' => 273,
			'declarator' => 272,
			'struct_declarator' => 274
		}
	},
	{#State 180
		ACTIONS => {
			'VOLATILE_TOKEN' => 21,
			'SHORT_TOKEN' => 2,
			'ENUM_TOKEN' => 1,
			'LONG_TOKEN' => 5,
			'VOID_TOKEN' => 22,
			'DOUBLE_TOKEN' => 24,
			'INT_TOKEN' => 26,
			'_BOOL_TOKEN' => 27,
			'_COMPLEX_TOKEN' => 32,
			'SIGNED_TOKEN' => 12,
			'CHAR_TOKEN' => 13,
			'CONST_TOKEN' => 14,
			'RCB_TOKEN' => 275,
			'RESTRICT_TOKEN' => 35,
			'UNION_TOKEN' => 36,
			'STRUCT_TOKEN' => 15,
			'UNSIGNED_TOKEN' => 17,
			'TNAME_TOKEN' => 16,
			'FLOAT_TOKEN' => 18
		},
		GOTOS => {
			'struct_or_union' => 33,
			'struct_or_union_specifier' => 28,
			'type_qualifier' => 178,
			'type_specifier' => 177,
			'enum_specifier' => 30,
			'specifier_qualifier_list' => 179,
			'struct_declaration' => 276
		}
	},
	{#State 181
		ACTIONS => {
			'CM_TOKEN' => 277,
			'RCB_TOKEN' => 278
		}
	},
	{#State 182
		ACTIONS => {
			'RCB_TOKEN' => 280,
			'IDENTIFIER_ORG' => 39,
			'END_TOKEN' => 48,
			'SQL_TOKEN' => 45,
			'SECTION_TOKEN' => 40,
			'BEGIN_TOKEN' => 43,
			'DECLARE_TOKEN' => 46,
			'EXEC_TOKEN' => 47,
			'TOOLS_TOKEN' => 49,
			'ORACLE_TOKEN' => 41
		},
		GOTOS => {
			'enumeration_constant' => 74,
			'IDENTIFIER' => 72,
			'enumerator' => 279
		}
	},
	{#State 183
		DEFAULT => -117
	},
	{#State 184
		ACTIONS => {
			'SIZEOF_TOKEN' => 207,
			'AMP_OPR' => 110,
			'IDENTIFIER_ORG' => 39,
			'INTEGER_LITERAL' => 191,
			'MINUS_OPR' => 134,
			'SQL_TOKEN' => 45,
			'SECTION_TOKEN' => 40,
			'DECLARE_TOKEN' => 46,
			'FLOAT_LITERAL' => 200,
			'ORACLE_TOKEN' => 41,
			'EXEC_TOKEN' => 47,
			'POSTFIX_OPR' => 194,
			'LP_TOKEN' => 195,
			'PLUS_OPR' => 100,
			'CHAR_LITERAL' => 204,
			'ASTARI_OPR' => 127,
			'END_TOKEN' => 48,
			'BEGIN_TOKEN' => 43,
			'PREFIX_OPR' => 106,
			'STRING_LITERAL' => 198,
			'TOOLS_TOKEN' => 49
		},
		GOTOS => {
			'logical_OR_expression' => 208,
			'conditional_expression' => 282,
			'primary_expression' => 209,
			'unary_operator' => 187,
			'unary_expression' => 281,
			'equality_expression' => 201,
			'IDENTIFIER' => 202,
			'constant_expression' => 283,
			'shift_expression' => 203,
			'additive_expression' => 196,
			'postfix_expression' => 210,
			'exclusive_OR_expression' => 211,
			'inclusive_OR_expression' => 205,
			'relational_expression' => 197,
			'AND_expression' => 188,
			'multiplicative_expression' => 206,
			'string_literal_list' => 212,
			'logical_AND_expression' => 213,
			'cast_expression' => 214
		}
	},
	{#State 185
		DEFAULT => -77
	},
	{#State 186
		ACTIONS => {
			'EQUAL_OPR' => 79
		},
		DEFAULT => -78
	},
	{#State 187
		ACTIONS => {
			'SIZEOF_TOKEN' => 207,
			'AMP_OPR' => 110,
			'IDENTIFIER_ORG' => 39,
			'INTEGER_LITERAL' => 191,
			'MINUS_OPR' => 134,
			'SQL_TOKEN' => 45,
			'SECTION_TOKEN' => 40,
			'DECLARE_TOKEN' => 46,
			'FLOAT_LITERAL' => 200,
			'ORACLE_TOKEN' => 41,
			'EXEC_TOKEN' => 47,
			'POSTFIX_OPR' => 194,
			'LP_TOKEN' => 195,
			'PLUS_OPR' => 100,
			'CHAR_LITERAL' => 204,
			'ASTARI_OPR' => 127,
			'END_TOKEN' => 48,
			'BEGIN_TOKEN' => 43,
			'PREFIX_OPR' => 106,
			'STRING_LITERAL' => 198,
			'TOOLS_TOKEN' => 49
		},
		GOTOS => {
			'IDENTIFIER' => 202,
			'string_literal_list' => 212,
			'unary_operator' => 187,
			'cast_expression' => 284,
			'primary_expression' => 209,
			'unary_expression' => 281,
			'postfix_expression' => 210
		}
	},
	{#State 188
		ACTIONS => {
			'AMP_OPR' => 285
		},
		DEFAULT => -48
	},
	{#State 189
		DEFAULT => -177
	},
	{#State 190
		DEFAULT => -79
	},
	{#State 191
		DEFAULT => -2
	},
	{#State 192
		ACTIONS => {
			'SIZEOF_TOKEN' => 207,
			'AMP_OPR' => 110,
			'IDENTIFIER_ORG' => 39,
			'INTEGER_LITERAL' => 191,
			'MINUS_OPR' => 134,
			'LCB_TOKEN' => 192,
			'SQL_TOKEN' => 45,
			'LSB_TOKEN' => 287,
			'SECTION_TOKEN' => 40,
			'DECLARE_TOKEN' => 46,
			'FLOAT_LITERAL' => 200,
			'ORACLE_TOKEN' => 41,
			'EXEC_TOKEN' => 47,
			'POSTFIX_OPR' => 194,
			'LP_TOKEN' => 195,
			'DOT_TOKEN' => 289,
			'PLUS_OPR' => 100,
			'CHAR_LITERAL' => 204,
			'ASTARI_OPR' => 127,
			'END_TOKEN' => 48,
			'BEGIN_TOKEN' => 43,
			'PREFIX_OPR' => 106,
			'STRING_LITERAL' => 198,
			'TOOLS_TOKEN' => 49
		},
		GOTOS => {
			'initializer_list' => 292,
			'logical_OR_expression' => 208,
			'conditional_expression' => 199,
			'primary_expression' => 209,
			'designation' => 288,
			'unary_operator' => 187,
			'unary_expression' => 193,
			'equality_expression' => 201,
			'IDENTIFIER' => 202,
			'designator_list' => 290,
			'shift_expression' => 203,
			'postfix_expression' => 210,
			'additive_expression' => 196,
			'exclusive_OR_expression' => 211,
			'designator' => 291,
			'inclusive_OR_expression' => 205,
			'relational_expression' => 197,
			'string_literal_list' => 212,
			'AND_expression' => 188,
			'multiplicative_expression' => 206,
			'logical_AND_expression' => 213,
			'assignment_expression' => 189,
			'cast_expression' => 214,
			'initializer' => 286
		}
	},
	{#State 193
		ACTIONS => {
			'ASSIGN_P_OPR' => 293,
			'ASSIGN_OPR' => 296,
			'EQUAL_OPR' => 295
		},
		DEFAULT => -30,
		GOTOS => {
			'assignment_operator' => 294
		}
	},
	{#State 194
		ACTIONS => {
			'SIZEOF_TOKEN' => 207,
			'AMP_OPR' => 110,
			'IDENTIFIER_ORG' => 39,
			'INTEGER_LITERAL' => 191,
			'MINUS_OPR' => 134,
			'SQL_TOKEN' => 45,
			'SECTION_TOKEN' => 40,
			'DECLARE_TOKEN' => 46,
			'FLOAT_LITERAL' => 200,
			'ORACLE_TOKEN' => 41,
			'EXEC_TOKEN' => 47,
			'POSTFIX_OPR' => 194,
			'LP_TOKEN' => 298,
			'PLUS_OPR' => 100,
			'CHAR_LITERAL' => 204,
			'ASTARI_OPR' => 127,
			'END_TOKEN' => 48,
			'BEGIN_TOKEN' => 43,
			'PREFIX_OPR' => 106,
			'STRING_LITERAL' => 198,
			'TOOLS_TOKEN' => 49
		},
		GOTOS => {
			'IDENTIFIER' => 202,
			'string_literal_list' => 212,
			'unary_operator' => 187,
			'primary_expression' => 209,
			'unary_expression' => 297,
			'postfix_expression' => 210
		}
	},
	{#State 195
		ACTIONS => {
			'SHORT_TOKEN' => 2,
			'ENUM_TOKEN' => 1,
			'IDENTIFIER_ORG' => 39,
			'LONG_TOKEN' => 5,
			'MINUS_OPR' => 134,
			'SECTION_TOKEN' => 40,
			'FLOAT_LITERAL' => 200,
			'ORACLE_TOKEN' => 41,
			'CHAR_TOKEN' => 13,
			'SIGNED_TOKEN' => 12,
			'CONST_TOKEN' => 14,
			'PLUS_OPR' => 100,
			'CHAR_LITERAL' => 204,
			'STRUCT_TOKEN' => 15,
			'TNAME_TOKEN' => 16,
			'UNSIGNED_TOKEN' => 17,
			'BEGIN_TOKEN' => 43,
			'PREFIX_OPR' => 106,
			'FLOAT_TOKEN' => 18,
			'VOLATILE_TOKEN' => 21,
			'SIZEOF_TOKEN' => 207,
			'AMP_OPR' => 110,
			'INTEGER_LITERAL' => 191,
			'VOID_TOKEN' => 22,
			'SQL_TOKEN' => 45,
			'DOUBLE_TOKEN' => 24,
			'INT_TOKEN' => 26,
			'_BOOL_TOKEN' => 27,
			'DECLARE_TOKEN' => 46,
			'EXEC_TOKEN' => 47,
			'POSTFIX_OPR' => 194,
			'LP_TOKEN' => 195,
			'_COMPLEX_TOKEN' => 32,
			'RESTRICT_TOKEN' => 35,
			'UNION_TOKEN' => 36,
			'ASTARI_OPR' => 127,
			'END_TOKEN' => 48,
			'STRING_LITERAL' => 198,
			'TOOLS_TOKEN' => 49
		},
		GOTOS => {
			'logical_OR_expression' => 208,
			'conditional_expression' => 199,
			'primary_expression' => 209,
			'struct_or_union_specifier' => 28,
			'expression' => 300,
			'type_qualifier' => 178,
			'unary_operator' => 187,
			'unary_expression' => 193,
			'enum_specifier' => 30,
			'specifier_qualifier_list' => 301,
			'type_name' => 299,
			'struct_or_union' => 33,
			'equality_expression' => 201,
			'IDENTIFIER' => 202,
			'shift_expression' => 203,
			'postfix_expression' => 210,
			'additive_expression' => 196,
			'exclusive_OR_expression' => 211,
			'inclusive_OR_expression' => 205,
			'relational_expression' => 197,
			'string_literal_list' => 212,
			'type_specifier' => 177,
			'AND_expression' => 188,
			'multiplicative_expression' => 206,
			'logical_AND_expression' => 213,
			'assignment_expression' => 221,
			'cast_expression' => 214
		}
	},
	{#State 196
		ACTIONS => {
			'MINUS_OPR' => 303,
			'PLUS_OPR' => 302
		},
		DEFAULT => -38
	},
	{#State 197
		ACTIONS => {
			'GT_OPR' => 304,
			'RELATIONAL_OPR' => 305,
			'LT_OPR' => 306
		},
		DEFAULT => -44
	},
	{#State 198
		DEFAULT => -7
	},
	{#State 199
		DEFAULT => -58
	},
	{#State 200
		DEFAULT => -3
	},
	{#State 201
		ACTIONS => {
			'EQUALITY_OPR' => 307
		},
		DEFAULT => -46
	},
	{#State 202
		DEFAULT => -1
	},
	{#State 203
		ACTIONS => {
			'SHIFT_OPR' => 308
		},
		DEFAULT => -40
	},
	{#State 204
		DEFAULT => -4
	},
	{#State 205
		ACTIONS => {
			'OR_OPR' => 309
		},
		DEFAULT => -52
	},
	{#State 206
		ACTIONS => {
			'MULTI_OPR' => 310,
			'ASTARI_OPR' => 311
		},
		DEFAULT => -35
	},
	{#State 207
		ACTIONS => {
			'SIZEOF_TOKEN' => 207,
			'AMP_OPR' => 110,
			'IDENTIFIER_ORG' => 39,
			'INTEGER_LITERAL' => 191,
			'MINUS_OPR' => 134,
			'SQL_TOKEN' => 45,
			'SECTION_TOKEN' => 40,
			'DECLARE_TOKEN' => 46,
			'FLOAT_LITERAL' => 200,
			'ORACLE_TOKEN' => 41,
			'EXEC_TOKEN' => 47,
			'POSTFIX_OPR' => 194,
			'LP_TOKEN' => 313,
			'PLUS_OPR' => 100,
			'CHAR_LITERAL' => 204,
			'ASTARI_OPR' => 127,
			'END_TOKEN' => 48,
			'BEGIN_TOKEN' => 43,
			'PREFIX_OPR' => 106,
			'STRING_LITERAL' => 198,
			'TOOLS_TOKEN' => 49
		},
		GOTOS => {
			'IDENTIFIER' => 202,
			'string_literal_list' => 212,
			'unary_operator' => 187,
			'primary_expression' => 209,
			'unary_expression' => 312,
			'postfix_expression' => 210
		}
	},
	{#State 208
		ACTIONS => {
			'COR_OPR' => 314,
			'QUES_TOKEN' => 315
		},
		DEFAULT => -56
	},
	{#State 209
		DEFAULT => -9
	},
	{#State 210
		ACTIONS => {
			'LSB_TOKEN' => 318,
			'PTR_OPR' => 319,
			'POSTFIX_OPR' => 316,
			'LP_TOKEN' => 317,
			'DOT_TOKEN' => 320
		},
		DEFAULT => -20
	},
	{#State 211
		ACTIONS => {
			'NOR_OPR' => 321
		},
		DEFAULT => -50
	},
	{#State 212
		ACTIONS => {
			'STRING_LITERAL' => 322
		},
		DEFAULT => -5
	},
	{#State 213
		ACTIONS => {
			'CAND_OPR' => 323
		},
		DEFAULT => -54
	},
	{#State 214
		DEFAULT => -32
	},
	{#State 215
		DEFAULT => -193
	},
	{#State 216
		ACTIONS => {
			'DEFAULT_TOKEN' => 227,
			'IDENTIFIER_ORG' => 39,
			'MINUS_OPR' => 134,
			'SMC_TOKEN' => 229,
			'SECTION_TOKEN' => 40,
			'DO_TOKEN' => 216,
			'WHILE_TOKEN' => 231,
			'CASE_TOKEN' => 233,
			'FLOAT_LITERAL' => 200,
			'ORACLE_TOKEN' => 41,
			'PLUS_OPR' => 100,
			'FOR_TOKEN' => 218,
			'CHAR_LITERAL' => 204,
			'SWITCH_TOKEN' => 220,
			'BEGIN_TOKEN' => 43,
			'PREFIX_OPR' => 106,
			'SIZEOF_TOKEN' => 207,
			'AMP_OPR' => 110,
			'RETURN_TOKEN' => 223,
			'INTEGER_LITERAL' => 191,
			'LCB_TOKEN' => 80,
			'SQL_TOKEN' => 45,
			'DECLARE_TOKEN' => 46,
			'CONTINUE_TOKEN' => 238,
			'GOTO_TOKEN' => 239,
			'EXEC_TOKEN' => 225,
			'POSTFIX_OPR' => 194,
			'LP_TOKEN' => 195,
			'BREAK_TOKEN' => 240,
			'IF_TOKEN' => 241,
			'ASTARI_OPR' => 127,
			'END_TOKEN' => 48,
			'STRING_LITERAL' => 198,
			'TOOLS_TOKEN' => 49
		},
		GOTOS => {
			'jump_statement' => 237,
			'iteration_statement' => 215,
			'logical_OR_expression' => 208,
			'expression_statement' => 228,
			'conditional_expression' => 199,
			'primary_expression' => 209,
			'embedded_sql' => 230,
			'statement' => 324,
			'expression' => 232,
			'unary_operator' => 187,
			'unary_expression' => 193,
			'equality_expression' => 201,
			'IDENTIFIER' => 236,
			'compound_statement' => 226,
			'labeled_statement' => 242,
			'shift_expression' => 203,
			'postfix_expression' => 210,
			'additive_expression' => 196,
			'exclusive_OR_expression' => 211,
			'inclusive_OR_expression' => 205,
			'relational_expression' => 197,
			'string_literal_list' => 212,
			'multiplicative_expression' => 206,
			'AND_expression' => 188,
			'logical_AND_expression' => 213,
			'assignment_expression' => 221,
			'cast_expression' => 214,
			'selection_statement' => 222
		}
	},
	{#State 217
		DEFAULT => -204
	},
	{#State 218
		ACTIONS => {
			'LP_TOKEN' => 325
		}
	},
	{#State 219
		DEFAULT => -199
	},
	{#State 220
		ACTIONS => {
			'LP_TOKEN' => 326
		}
	},
	{#State 221
		DEFAULT => -63
	},
	{#State 222
		DEFAULT => -192
	},
	{#State 223
		ACTIONS => {
			'SIZEOF_TOKEN' => 207,
			'AMP_OPR' => 110,
			'IDENTIFIER_ORG' => 39,
			'INTEGER_LITERAL' => 191,
			'MINUS_OPR' => 134,
			'SMC_TOKEN' => 327,
			'SQL_TOKEN' => 45,
			'SECTION_TOKEN' => 40,
			'DECLARE_TOKEN' => 46,
			'FLOAT_LITERAL' => 200,
			'ORACLE_TOKEN' => 41,
			'EXEC_TOKEN' => 47,
			'POSTFIX_OPR' => 194,
			'LP_TOKEN' => 195,
			'PLUS_OPR' => 100,
			'CHAR_LITERAL' => 204,
			'ASTARI_OPR' => 127,
			'END_TOKEN' => 48,
			'BEGIN_TOKEN' => 43,
			'PREFIX_OPR' => 106,
			'STRING_LITERAL' => 198,
			'TOOLS_TOKEN' => 49
		},
		GOTOS => {
			'logical_OR_expression' => 208,
			'conditional_expression' => 199,
			'primary_expression' => 209,
			'expression' => 328,
			'unary_operator' => 187,
			'unary_expression' => 193,
			'equality_expression' => 201,
			'IDENTIFIER' => 202,
			'shift_expression' => 203,
			'additive_expression' => 196,
			'postfix_expression' => 210,
			'exclusive_OR_expression' => 211,
			'inclusive_OR_expression' => 205,
			'relational_expression' => 197,
			'string_literal_list' => 212,
			'AND_expression' => 188,
			'multiplicative_expression' => 206,
			'logical_AND_expression' => 213,
			'assignment_expression' => 221,
			'cast_expression' => 214
		}
	},
	{#State 224
		DEFAULT => -203
	},
	{#State 225
		ACTIONS => {
			'SQL_TOKEN' => 65,
			'ORACLE_TOKEN' => 64,
			'TOOLS_TOKEN' => 66
		},
		DEFAULT => -321
	},
	{#State 226
		DEFAULT => -190
	},
	{#State 227
		ACTIONS => {
			'CLN_TOKEN' => 329
		}
	},
	{#State 228
		DEFAULT => -191
	},
	{#State 229
		DEFAULT => -206
	},
	{#State 230
		DEFAULT => -195
	},
	{#State 231
		ACTIONS => {
			'LP_TOKEN' => 330
		}
	},
	{#State 232
		ACTIONS => {
			'CM_TOKEN' => 331,
			'SMC_TOKEN' => 332
		}
	},
	{#State 233
		ACTIONS => {
			'SIZEOF_TOKEN' => 207,
			'AMP_OPR' => 110,
			'IDENTIFIER_ORG' => 39,
			'INTEGER_LITERAL' => 191,
			'MINUS_OPR' => 134,
			'SQL_TOKEN' => 45,
			'SECTION_TOKEN' => 40,
			'DECLARE_TOKEN' => 46,
			'FLOAT_LITERAL' => 200,
			'ORACLE_TOKEN' => 41,
			'EXEC_TOKEN' => 47,
			'POSTFIX_OPR' => 194,
			'LP_TOKEN' => 195,
			'PLUS_OPR' => 100,
			'CHAR_LITERAL' => 204,
			'ASTARI_OPR' => 127,
			'END_TOKEN' => 48,
			'BEGIN_TOKEN' => 43,
			'PREFIX_OPR' => 106,
			'STRING_LITERAL' => 198,
			'TOOLS_TOKEN' => 49
		},
		GOTOS => {
			'logical_OR_expression' => 208,
			'conditional_expression' => 282,
			'primary_expression' => 209,
			'unary_operator' => 187,
			'unary_expression' => 281,
			'equality_expression' => 201,
			'IDENTIFIER' => 202,
			'constant_expression' => 333,
			'shift_expression' => 203,
			'additive_expression' => 196,
			'postfix_expression' => 210,
			'exclusive_OR_expression' => 211,
			'inclusive_OR_expression' => 205,
			'relational_expression' => 197,
			'AND_expression' => 188,
			'multiplicative_expression' => 206,
			'string_literal_list' => 212,
			'logical_AND_expression' => 213,
			'cast_expression' => 214
		}
	},
	{#State 234
		ACTIONS => {
			'DEFAULT_TOKEN' => 227,
			'EXTERN_TOKEN' => 3,
			'SHORT_TOKEN' => 2,
			'ENUM_TOKEN' => 1,
			'IDENTIFIER_ORG' => 39,
			'LONG_TOKEN' => 5,
			'MINUS_OPR' => 134,
			'SMC_TOKEN' => 229,
			'SECTION_TOKEN' => 40,
			'DO_TOKEN' => 216,
			'INLINE_TOKEN' => 8,
			'WHILE_TOKEN' => 231,
			'CASE_TOKEN' => 233,
			'FLOAT_LITERAL' => 200,
			'ORACLE_TOKEN' => 41,
			'CHAR_TOKEN' => 13,
			'SIGNED_TOKEN' => 12,
			'CONST_TOKEN' => 14,
			'PLUS_OPR' => 100,
			'FOR_TOKEN' => 218,
			'RCB_TOKEN' => 334,
			'CHAR_LITERAL' => 204,
			'STRUCT_TOKEN' => 15,
			'SWITCH_TOKEN' => 220,
			'TNAME_TOKEN' => 16,
			'UNSIGNED_TOKEN' => 17,
			'BEGIN_TOKEN' => 43,
			'PREFIX_OPR' => 106,
			'FLOAT_TOKEN' => 18,
			'AUTO_TOKEN' => 19,
			'SIZEOF_TOKEN' => 207,
			'VOLATILE_TOKEN' => 21,
			'AMP_OPR' => 110,
			'RETURN_TOKEN' => 223,
			'INTEGER_LITERAL' => 191,
			'VOID_TOKEN' => 22,
			'LCB_TOKEN' => 80,
			'SQL_TOKEN' => 45,
			'DOUBLE_TOKEN' => 24,
			'INT_TOKEN' => 26,
			'_BOOL_TOKEN' => 27,
			'CONTINUE_TOKEN' => 238,
			'DECLARE_TOKEN' => 46,
			'GOTO_TOKEN' => 239,
			'TYPEDEF_TOKEN' => 29,
			'EXEC_TOKEN' => 225,
			'POSTFIX_OPR' => 194,
			'LP_TOKEN' => 195,
			'_COMPLEX_TOKEN' => 32,
			'IF_TOKEN' => 241,
			'BREAK_TOKEN' => 240,
			'REGISTER_TOKEN' => 34,
			'RESTRICT_TOKEN' => 35,
			'UNION_TOKEN' => 36,
			'ASTARI_OPR' => 127,
			'END_TOKEN' => 48,
			'STATIC_TOKEN' => 37,
			'STRING_LITERAL' => 198,
			'TOOLS_TOKEN' => 49
		},
		GOTOS => {
			'function_specifier' => 4,
			'iteration_statement' => 215,
			'expression_statement' => 228,
			'conditional_expression' => 199,
			'embedded_sql' => 230,
			'declaration_specifiers' => 78,
			'statement' => 217,
			'expression' => 232,
			'type_qualifier' => 9,
			'storage_class_specifier' => 10,
			'unary_operator' => 187,
			'block_item' => 335,
			'IDENTIFIER' => 236,
			'equality_expression' => 201,
			'shift_expression' => 203,
			'inclusive_OR_expression' => 205,
			'multiplicative_expression' => 206,
			'AND_expression' => 188,
			'assignment_expression' => 221,
			'selection_statement' => 222,
			'jump_statement' => 237,
			'logical_OR_expression' => 208,
			'primary_expression' => 209,
			'declaration' => 224,
			'struct_or_union_specifier' => 28,
			'unary_expression' => 193,
			'enum_specifier' => 30,
			'struct_or_union' => 33,
			'compound_statement' => 226,
			'labeled_statement' => 242,
			'postfix_expression' => 210,
			'additive_expression' => 196,
			'exclusive_OR_expression' => 211,
			'relational_expression' => 197,
			'string_literal_list' => 212,
			'type_specifier' => 38,
			'logical_AND_expression' => 213,
			'cast_expression' => 214
		}
	},
	{#State 235
		DEFAULT => -201
	},
	{#State 236
		ACTIONS => {
			'CLN_TOKEN' => 336
		},
		DEFAULT => -1
	},
	{#State 237
		DEFAULT => -194
	},
	{#State 238
		ACTIONS => {
			'SMC_TOKEN' => 337
		}
	},
	{#State 239
		ACTIONS => {
			'IDENTIFIER_ORG' => 39,
			'END_TOKEN' => 48,
			'SQL_TOKEN' => 45,
			'SECTION_TOKEN' => 40,
			'BEGIN_TOKEN' => 43,
			'DECLARE_TOKEN' => 46,
			'EXEC_TOKEN' => 47,
			'TOOLS_TOKEN' => 49,
			'ORACLE_TOKEN' => 41
		},
		GOTOS => {
			'IDENTIFIER' => 338
		}
	},
	{#State 240
		ACTIONS => {
			'SMC_TOKEN' => 339
		}
	},
	{#State 241
		ACTIONS => {
			'LP_TOKEN' => 340
		}
	},
	{#State 242
		DEFAULT => -189
	},
	{#State 243
		DEFAULT => -238
	},
	{#State 244
		DEFAULT => -236
	},
	{#State 245
		DEFAULT => -133
	},
	{#State 246
		ACTIONS => {
			'RSB_TOKEN' => 341
		}
	},
	{#State 247
		ACTIONS => {
			'SIZEOF_TOKEN' => 207,
			'VOLATILE_TOKEN' => 21,
			'AMP_OPR' => 110,
			'IDENTIFIER_ORG' => 39,
			'INTEGER_LITERAL' => 191,
			'MINUS_OPR' => 134,
			'SQL_TOKEN' => 45,
			'SECTION_TOKEN' => 40,
			'DECLARE_TOKEN' => 46,
			'RSB_TOKEN' => 344,
			'FLOAT_LITERAL' => 200,
			'ORACLE_TOKEN' => 41,
			'EXEC_TOKEN' => 47,
			'POSTFIX_OPR' => 194,
			'LP_TOKEN' => 195,
			'CONST_TOKEN' => 14,
			'PLUS_OPR' => 100,
			'RESTRICT_TOKEN' => 35,
			'CHAR_LITERAL' => 204,
			'ASTARI_OPR' => 343,
			'END_TOKEN' => 48,
			'STATIC_TOKEN' => 345,
			'BEGIN_TOKEN' => 43,
			'PREFIX_OPR' => 106,
			'STRING_LITERAL' => 198,
			'TOOLS_TOKEN' => 49
		},
		GOTOS => {
			'logical_OR_expression' => 208,
			'conditional_expression' => 199,
			'primary_expression' => 209,
			'type_qualifier' => 258,
			'unary_operator' => 187,
			'unary_expression' => 193,
			'equality_expression' => 201,
			'IDENTIFIER' => 202,
			'shift_expression' => 203,
			'additive_expression' => 196,
			'postfix_expression' => 210,
			'exclusive_OR_expression' => 211,
			'inclusive_OR_expression' => 205,
			'relational_expression' => 197,
			'string_literal_list' => 212,
			'AND_expression' => 188,
			'multiplicative_expression' => 206,
			'logical_AND_expression' => 213,
			'assignment_expression' => 342,
			'cast_expression' => 214
		}
	},
	{#State 248
		ACTIONS => {
			'RSB_TOKEN' => 346
		},
		DEFAULT => -26
	},
	{#State 249
		DEFAULT => -137
	},
	{#State 250
		ACTIONS => {
			'SIZEOF_TOKEN' => 207,
			'VOLATILE_TOKEN' => 21,
			'AMP_OPR' => 110,
			'IDENTIFIER_ORG' => 39,
			'INTEGER_LITERAL' => 191,
			'MINUS_OPR' => 134,
			'SQL_TOKEN' => 45,
			'SECTION_TOKEN' => 40,
			'DECLARE_TOKEN' => 46,
			'FLOAT_LITERAL' => 200,
			'ORACLE_TOKEN' => 41,
			'EXEC_TOKEN' => 47,
			'POSTFIX_OPR' => 194,
			'LP_TOKEN' => 195,
			'CONST_TOKEN' => 14,
			'PLUS_OPR' => 100,
			'RESTRICT_TOKEN' => 35,
			'CHAR_LITERAL' => 204,
			'ASTARI_OPR' => 127,
			'END_TOKEN' => 48,
			'BEGIN_TOKEN' => 43,
			'PREFIX_OPR' => 106,
			'STRING_LITERAL' => 198,
			'TOOLS_TOKEN' => 49
		},
		GOTOS => {
			'logical_OR_expression' => 208,
			'conditional_expression' => 199,
			'primary_expression' => 209,
			'type_qualifier_list' => 348,
			'type_qualifier' => 87,
			'unary_operator' => 187,
			'unary_expression' => 193,
			'equality_expression' => 201,
			'IDENTIFIER' => 202,
			'shift_expression' => 203,
			'postfix_expression' => 210,
			'additive_expression' => 196,
			'exclusive_OR_expression' => 211,
			'inclusive_OR_expression' => 205,
			'relational_expression' => 197,
			'string_literal_list' => 212,
			'AND_expression' => 188,
			'multiplicative_expression' => 206,
			'logical_AND_expression' => 213,
			'assignment_expression' => 347,
			'cast_expression' => 214
		}
	},
	{#State 251
		DEFAULT => -154
	},
	{#State 252
		ACTIONS => {
			'IDENTIFIER_ORG' => 39,
			'ASTARI_OPR' => 59,
			'END_TOKEN' => 48,
			'SQL_TOKEN' => 45,
			'LSB_TOKEN' => 352,
			'SECTION_TOKEN' => 40,
			'DECLARE_TOKEN' => 46,
			'BEGIN_TOKEN' => 43,
			'EXEC_TOKEN' => 47,
			'LP_TOKEN' => 350,
			'TOOLS_TOKEN' => 49,
			'ORACLE_TOKEN' => 41
		},
		DEFAULT => -158,
		GOTOS => {
			'direct_declarator' => 58,
			'direct_abstract_declarator' => 353,
			'IDENTIFIER' => 53,
			'pointer' => 354,
			'declarator' => 349,
			'abstract_declarator' => 351
		}
	},
	{#State 253
		ACTIONS => {
			'CM_TOKEN' => 355,
			'RP_TOKEN' => 356
		}
	},
	{#State 254
		DEFAULT => -145
	},
	{#State 255
		DEFAULT => -159
	},
	{#State 256
		ACTIONS => {
			'CM_TOKEN' => 357
		},
		DEFAULT => -152
	},
	{#State 257
		ACTIONS => {
			'RP_TOKEN' => 358
		}
	},
	{#State 258
		DEFAULT => -151
	},
	{#State 259
		DEFAULT => -148
	},
	{#State 260
		DEFAULT => -252
	},
	{#State 261
		DEFAULT => -246
	},
	{#State 262
		ACTIONS => {
			'CM_TOKEN' => -262,
			'PUBLIC_TOKEN' => -262,
			'CLN_TOKEN' => -262,
			'RP_TOKEN' => -262,
			'COR_OPR' => -262,
			'GT_OPR' => -262,
			'MULTI_OPR' => -262,
			'PRIVATE_TOKEN' => -262,
			'ATMARK_TOKEN' => -262,
			'INEQUALITY_OPR' => -262,
			'LSB_TOKEN' => -262,
			'PTR_OPR' => -262,
			'DOT_TOKEN' => -262,
			'EQUAL_OPR' => -262,
			'_IMAGINARY_TOKEN' => -262,
			'PROTECTED_TOKEN' => -262,
			'RSB_TOKEN' => -262,
			'ASSIGN_OPR' => -262,
			'EQUALITY_OPR' => -262,
			'RELATIONAL_OPR' => -262,
			'NEW_TOKEN' => -262,
			'LT_OPR' => -262,
			'QUES_TOKEN' => -262
		},
		DEFAULT => -241
	},
	{#State 263
		ACTIONS => {
			'CM_TOKEN' => -262,
			'PUBLIC_TOKEN' => -262,
			'CLN_TOKEN' => -262,
			'RP_TOKEN' => -262,
			'COR_OPR' => -262,
			'GT_OPR' => -262,
			'MULTI_OPR' => -262,
			'PRIVATE_TOKEN' => -262,
			'ATMARK_TOKEN' => -262,
			'INEQUALITY_OPR' => -262,
			'LSB_TOKEN' => -262,
			'PTR_OPR' => -262,
			'DOT_TOKEN' => -262,
			'EQUAL_OPR' => -262,
			'_IMAGINARY_TOKEN' => -262,
			'PROTECTED_TOKEN' => -262,
			'RSB_TOKEN' => -262,
			'ASSIGN_OPR' => -262,
			'EQUALITY_OPR' => -262,
			'RELATIONAL_OPR' => -262,
			'NEW_TOKEN' => -262,
			'LT_OPR' => -262,
			'QUES_TOKEN' => -262
		},
		DEFAULT => -240
	},
	{#State 264
		DEFAULT => -239
	},
	{#State 265
		ACTIONS => {
			'SECTION_TOKEN' => 359
		}
	},
	{#State 266
		ACTIONS => {
			'SECTION_TOKEN' => 360
		}
	},
	{#State 267
		ACTIONS => {
			'CM_TOKEN' => -262,
			'PUBLIC_TOKEN' => -262,
			'CLN_TOKEN' => -262,
			'RP_TOKEN' => -262,
			'COR_OPR' => -262,
			'GT_OPR' => -262,
			'MULTI_OPR' => -262,
			'PRIVATE_TOKEN' => -262,
			'ATMARK_TOKEN' => -262,
			'INEQUALITY_OPR' => -262,
			'LSB_TOKEN' => -262,
			'PTR_OPR' => -262,
			'DOT_TOKEN' => -262,
			'EQUAL_OPR' => -262,
			'_IMAGINARY_TOKEN' => -262,
			'PROTECTED_TOKEN' => -262,
			'RSB_TOKEN' => -262,
			'ASSIGN_OPR' => -262,
			'EQUALITY_OPR' => -262,
			'RELATIONAL_OPR' => -262,
			'NEW_TOKEN' => -262,
			'LT_OPR' => -262,
			'QUES_TOKEN' => -262
		},
		DEFAULT => -242
	},
	{#State 268
		ACTIONS => {
			'VOLATILE_TOKEN' => 21,
			'SHORT_TOKEN' => 2,
			'ENUM_TOKEN' => 1,
			'LONG_TOKEN' => 5,
			'VOID_TOKEN' => 22,
			'DOUBLE_TOKEN' => 24,
			'INT_TOKEN' => 26,
			'_BOOL_TOKEN' => 27,
			'_COMPLEX_TOKEN' => 32,
			'SIGNED_TOKEN' => 12,
			'CHAR_TOKEN' => 13,
			'CONST_TOKEN' => 14,
			'RCB_TOKEN' => 361,
			'RESTRICT_TOKEN' => 35,
			'UNION_TOKEN' => 36,
			'STRUCT_TOKEN' => 15,
			'UNSIGNED_TOKEN' => 17,
			'TNAME_TOKEN' => 16,
			'FLOAT_TOKEN' => 18
		},
		GOTOS => {
			'struct_or_union' => 33,
			'struct_or_union_specifier' => 28,
			'type_qualifier' => 178,
			'type_specifier' => 177,
			'enum_specifier' => 30,
			'specifier_qualifier_list' => 179,
			'struct_declaration' => 276
		}
	},
	{#State 269
		DEFAULT => -107
	},
	{#State 270
		DEFAULT => -109
	},
	{#State 271
		ACTIONS => {
			'SIZEOF_TOKEN' => 207,
			'AMP_OPR' => 110,
			'IDENTIFIER_ORG' => 39,
			'INTEGER_LITERAL' => 191,
			'MINUS_OPR' => 134,
			'SQL_TOKEN' => 45,
			'SECTION_TOKEN' => 40,
			'DECLARE_TOKEN' => 46,
			'FLOAT_LITERAL' => 200,
			'ORACLE_TOKEN' => 41,
			'EXEC_TOKEN' => 47,
			'POSTFIX_OPR' => 194,
			'LP_TOKEN' => 195,
			'PLUS_OPR' => 100,
			'CHAR_LITERAL' => 204,
			'ASTARI_OPR' => 127,
			'END_TOKEN' => 48,
			'BEGIN_TOKEN' => 43,
			'PREFIX_OPR' => 106,
			'STRING_LITERAL' => 198,
			'TOOLS_TOKEN' => 49
		},
		GOTOS => {
			'logical_OR_expression' => 208,
			'conditional_expression' => 282,
			'primary_expression' => 209,
			'unary_operator' => 187,
			'unary_expression' => 281,
			'equality_expression' => 201,
			'IDENTIFIER' => 202,
			'constant_expression' => 362,
			'shift_expression' => 203,
			'additive_expression' => 196,
			'postfix_expression' => 210,
			'exclusive_OR_expression' => 211,
			'inclusive_OR_expression' => 205,
			'relational_expression' => 197,
			'AND_expression' => 188,
			'multiplicative_expression' => 206,
			'string_literal_list' => 212,
			'logical_AND_expression' => 213,
			'cast_expression' => 214
		}
	},
	{#State 272
		ACTIONS => {
			'CLN_TOKEN' => 363
		},
		DEFAULT => -113
	},
	{#State 273
		ACTIONS => {
			'CM_TOKEN' => 364,
			'SMC_TOKEN' => 365
		}
	},
	{#State 274
		DEFAULT => -111
	},
	{#State 275
		DEFAULT => -100
	},
	{#State 276
		DEFAULT => -105
	},
	{#State 277
		ACTIONS => {
			'RCB_TOKEN' => 366,
			'IDENTIFIER_ORG' => 39,
			'END_TOKEN' => 48,
			'SQL_TOKEN' => 45,
			'SECTION_TOKEN' => 40,
			'BEGIN_TOKEN' => 43,
			'DECLARE_TOKEN' => 46,
			'EXEC_TOKEN' => 47,
			'TOOLS_TOKEN' => 49,
			'ORACLE_TOKEN' => 41
		},
		GOTOS => {
			'enumeration_constant' => 74,
			'IDENTIFIER' => 72,
			'enumerator' => 279
		}
	},
	{#State 278
		DEFAULT => -116
	},
	{#State 279
		DEFAULT => -122
	},
	{#State 280
		DEFAULT => -119
	},
	{#State 281
		DEFAULT => -30
	},
	{#State 282
		DEFAULT => -65
	},
	{#State 283
		DEFAULT => -124
	},
	{#State 284
		DEFAULT => -22
	},
	{#State 285
		ACTIONS => {
			'SIZEOF_TOKEN' => 207,
			'AMP_OPR' => 110,
			'IDENTIFIER_ORG' => 39,
			'INTEGER_LITERAL' => 191,
			'MINUS_OPR' => 134,
			'SQL_TOKEN' => 45,
			'SECTION_TOKEN' => 40,
			'DECLARE_TOKEN' => 46,
			'FLOAT_LITERAL' => 200,
			'ORACLE_TOKEN' => 41,
			'EXEC_TOKEN' => 47,
			'POSTFIX_OPR' => 194,
			'LP_TOKEN' => 195,
			'PLUS_OPR' => 100,
			'CHAR_LITERAL' => 204,
			'ASTARI_OPR' => 127,
			'END_TOKEN' => 48,
			'BEGIN_TOKEN' => 43,
			'PREFIX_OPR' => 106,
			'STRING_LITERAL' => 198,
			'TOOLS_TOKEN' => 49
		},
		GOTOS => {
			'equality_expression' => 367,
			'IDENTIFIER' => 202,
			'primary_expression' => 209,
			'shift_expression' => 203,
			'postfix_expression' => 210,
			'additive_expression' => 196,
			'relational_expression' => 197,
			'string_literal_list' => 212,
			'multiplicative_expression' => 206,
			'unary_operator' => 187,
			'cast_expression' => 214,
			'unary_expression' => 281
		}
	},
	{#State 286
		DEFAULT => -181
	},
	{#State 287
		ACTIONS => {
			'SIZEOF_TOKEN' => 207,
			'AMP_OPR' => 110,
			'IDENTIFIER_ORG' => 39,
			'INTEGER_LITERAL' => 191,
			'MINUS_OPR' => 134,
			'SQL_TOKEN' => 45,
			'SECTION_TOKEN' => 40,
			'DECLARE_TOKEN' => 46,
			'FLOAT_LITERAL' => 200,
			'ORACLE_TOKEN' => 41,
			'EXEC_TOKEN' => 47,
			'POSTFIX_OPR' => 194,
			'LP_TOKEN' => 195,
			'PLUS_OPR' => 100,
			'CHAR_LITERAL' => 204,
			'ASTARI_OPR' => 127,
			'END_TOKEN' => 48,
			'BEGIN_TOKEN' => 43,
			'PREFIX_OPR' => 106,
			'STRING_LITERAL' => 198,
			'TOOLS_TOKEN' => 49
		},
		GOTOS => {
			'logical_OR_expression' => 208,
			'conditional_expression' => 282,
			'primary_expression' => 209,
			'unary_operator' => 187,
			'unary_expression' => 281,
			'equality_expression' => 201,
			'IDENTIFIER' => 202,
			'constant_expression' => 368,
			'shift_expression' => 203,
			'additive_expression' => 196,
			'postfix_expression' => 210,
			'exclusive_OR_expression' => 211,
			'inclusive_OR_expression' => 205,
			'relational_expression' => 197,
			'AND_expression' => 188,
			'multiplicative_expression' => 206,
			'string_literal_list' => 212,
			'logical_AND_expression' => 213,
			'cast_expression' => 214
		}
	},
	{#State 288
		ACTIONS => {
			'SIZEOF_TOKEN' => 207,
			'AMP_OPR' => 110,
			'IDENTIFIER_ORG' => 39,
			'INTEGER_LITERAL' => 191,
			'MINUS_OPR' => 134,
			'LCB_TOKEN' => 192,
			'SQL_TOKEN' => 45,
			'SECTION_TOKEN' => 40,
			'DECLARE_TOKEN' => 46,
			'FLOAT_LITERAL' => 200,
			'ORACLE_TOKEN' => 41,
			'EXEC_TOKEN' => 47,
			'POSTFIX_OPR' => 194,
			'LP_TOKEN' => 195,
			'PLUS_OPR' => 100,
			'CHAR_LITERAL' => 204,
			'ASTARI_OPR' => 127,
			'END_TOKEN' => 48,
			'BEGIN_TOKEN' => 43,
			'PREFIX_OPR' => 106,
			'STRING_LITERAL' => 198,
			'TOOLS_TOKEN' => 49
		},
		GOTOS => {
			'logical_OR_expression' => 208,
			'conditional_expression' => 199,
			'primary_expression' => 209,
			'unary_operator' => 187,
			'unary_expression' => 193,
			'equality_expression' => 201,
			'IDENTIFIER' => 202,
			'shift_expression' => 203,
			'additive_expression' => 196,
			'postfix_expression' => 210,
			'exclusive_OR_expression' => 211,
			'inclusive_OR_expression' => 205,
			'relational_expression' => 197,
			'string_literal_list' => 212,
			'AND_expression' => 188,
			'multiplicative_expression' => 206,
			'logical_AND_expression' => 213,
			'assignment_expression' => 189,
			'cast_expression' => 214,
			'initializer' => 369
		}
	},
	{#State 289
		ACTIONS => {
			'IDENTIFIER_ORG' => 39,
			'END_TOKEN' => 48,
			'SQL_TOKEN' => 45,
			'SECTION_TOKEN' => 40,
			'BEGIN_TOKEN' => 43,
			'DECLARE_TOKEN' => 46,
			'EXEC_TOKEN' => 47,
			'TOOLS_TOKEN' => 49,
			'ORACLE_TOKEN' => 41
		},
		GOTOS => {
			'IDENTIFIER' => 370
		}
	},
	{#State 290
		ACTIONS => {
			'EQUAL_OPR' => 372,
			'DOT_TOKEN' => 289,
			'LSB_TOKEN' => 287
		},
		GOTOS => {
			'designator' => 371
		}
	},
	{#State 291
		DEFAULT => -185
	},
	{#State 292
		ACTIONS => {
			'CM_TOKEN' => 373,
			'RCB_TOKEN' => 374
		}
	},
	{#State 293
		DEFAULT => -62
	},
	{#State 294
		ACTIONS => {
			'SIZEOF_TOKEN' => 207,
			'AMP_OPR' => 110,
			'IDENTIFIER_ORG' => 39,
			'INTEGER_LITERAL' => 191,
			'MINUS_OPR' => 134,
			'SQL_TOKEN' => 45,
			'SECTION_TOKEN' => 40,
			'DECLARE_TOKEN' => 46,
			'FLOAT_LITERAL' => 200,
			'ORACLE_TOKEN' => 41,
			'EXEC_TOKEN' => 47,
			'POSTFIX_OPR' => 194,
			'LP_TOKEN' => 195,
			'PLUS_OPR' => 100,
			'CHAR_LITERAL' => 204,
			'ASTARI_OPR' => 127,
			'END_TOKEN' => 48,
			'BEGIN_TOKEN' => 43,
			'PREFIX_OPR' => 106,
			'STRING_LITERAL' => 198,
			'TOOLS_TOKEN' => 49
		},
		GOTOS => {
			'logical_OR_expression' => 208,
			'conditional_expression' => 199,
			'primary_expression' => 209,
			'unary_operator' => 187,
			'unary_expression' => 193,
			'equality_expression' => 201,
			'IDENTIFIER' => 202,
			'shift_expression' => 203,
			'additive_expression' => 196,
			'postfix_expression' => 210,
			'exclusive_OR_expression' => 211,
			'inclusive_OR_expression' => 205,
			'relational_expression' => 197,
			'AND_expression' => 188,
			'multiplicative_expression' => 206,
			'string_literal_list' => 212,
			'logical_AND_expression' => 213,
			'assignment_expression' => 375,
			'cast_expression' => 214
		}
	},
	{#State 295
		DEFAULT => -60
	},
	{#State 296
		DEFAULT => -61
	},
	{#State 297
		DEFAULT => -21
	},
	{#State 298
		ACTIONS => {
			'SHORT_TOKEN' => 2,
			'ENUM_TOKEN' => 1,
			'IDENTIFIER_ORG' => 39,
			'LONG_TOKEN' => 5,
			'MINUS_OPR' => 134,
			'SECTION_TOKEN' => 40,
			'FLOAT_LITERAL' => 200,
			'ORACLE_TOKEN' => 41,
			'CHAR_TOKEN' => 13,
			'SIGNED_TOKEN' => 12,
			'CONST_TOKEN' => 14,
			'PLUS_OPR' => 100,
			'CHAR_LITERAL' => 204,
			'STRUCT_TOKEN' => 15,
			'TNAME_TOKEN' => 16,
			'UNSIGNED_TOKEN' => 17,
			'BEGIN_TOKEN' => 43,
			'PREFIX_OPR' => 106,
			'FLOAT_TOKEN' => 18,
			'VOLATILE_TOKEN' => 21,
			'SIZEOF_TOKEN' => 207,
			'AMP_OPR' => 110,
			'INTEGER_LITERAL' => 191,
			'VOID_TOKEN' => 22,
			'SQL_TOKEN' => 45,
			'DOUBLE_TOKEN' => 24,
			'INT_TOKEN' => 26,
			'_BOOL_TOKEN' => 27,
			'DECLARE_TOKEN' => 46,
			'EXEC_TOKEN' => 47,
			'POSTFIX_OPR' => 194,
			'LP_TOKEN' => 195,
			'_COMPLEX_TOKEN' => 32,
			'RESTRICT_TOKEN' => 35,
			'UNION_TOKEN' => 36,
			'ASTARI_OPR' => 127,
			'END_TOKEN' => 48,
			'STRING_LITERAL' => 198,
			'TOOLS_TOKEN' => 49
		},
		GOTOS => {
			'logical_OR_expression' => 208,
			'conditional_expression' => 199,
			'primary_expression' => 209,
			'struct_or_union_specifier' => 28,
			'expression' => 300,
			'type_qualifier' => 178,
			'unary_operator' => 187,
			'unary_expression' => 193,
			'enum_specifier' => 30,
			'specifier_qualifier_list' => 301,
			'type_name' => 376,
			'struct_or_union' => 33,
			'equality_expression' => 201,
			'IDENTIFIER' => 202,
			'shift_expression' => 203,
			'postfix_expression' => 210,
			'additive_expression' => 196,
			'exclusive_OR_expression' => 211,
			'inclusive_OR_expression' => 205,
			'relational_expression' => 197,
			'string_literal_list' => 212,
			'type_specifier' => 177,
			'AND_expression' => 188,
			'multiplicative_expression' => 206,
			'logical_AND_expression' => 213,
			'assignment_expression' => 221,
			'cast_expression' => 214
		}
	},
	{#State 299
		ACTIONS => {
			'RP_TOKEN' => 377
		}
	},
	{#State 300
		ACTIONS => {
			'CM_TOKEN' => 331,
			'RP_TOKEN' => 378
		}
	},
	{#State 301
		ACTIONS => {
			'LSB_TOKEN' => 352,
			'ASTARI_OPR' => 59,
			'LP_TOKEN' => 379
		},
		DEFAULT => -162,
		GOTOS => {
			'direct_abstract_declarator' => 353,
			'pointer' => 381,
			'abstract_declarator' => 380
		}
	},
	{#State 302
		ACTIONS => {
			'SIZEOF_TOKEN' => 207,
			'AMP_OPR' => 110,
			'IDENTIFIER_ORG' => 39,
			'INTEGER_LITERAL' => 191,
			'MINUS_OPR' => 134,
			'SQL_TOKEN' => 45,
			'SECTION_TOKEN' => 40,
			'DECLARE_TOKEN' => 46,
			'FLOAT_LITERAL' => 200,
			'ORACLE_TOKEN' => 41,
			'EXEC_TOKEN' => 47,
			'POSTFIX_OPR' => 194,
			'LP_TOKEN' => 195,
			'PLUS_OPR' => 100,
			'CHAR_LITERAL' => 204,
			'ASTARI_OPR' => 127,
			'END_TOKEN' => 48,
			'BEGIN_TOKEN' => 43,
			'PREFIX_OPR' => 106,
			'STRING_LITERAL' => 198,
			'TOOLS_TOKEN' => 49
		},
		GOTOS => {
			'IDENTIFIER' => 202,
			'primary_expression' => 209,
			'postfix_expression' => 210,
			'multiplicative_expression' => 382,
			'string_literal_list' => 212,
			'unary_operator' => 187,
			'unary_expression' => 281,
			'cast_expression' => 214
		}
	},
	{#State 303
		ACTIONS => {
			'SIZEOF_TOKEN' => 207,
			'AMP_OPR' => 110,
			'IDENTIFIER_ORG' => 39,
			'INTEGER_LITERAL' => 191,
			'MINUS_OPR' => 134,
			'SQL_TOKEN' => 45,
			'SECTION_TOKEN' => 40,
			'DECLARE_TOKEN' => 46,
			'FLOAT_LITERAL' => 200,
			'ORACLE_TOKEN' => 41,
			'EXEC_TOKEN' => 47,
			'POSTFIX_OPR' => 194,
			'LP_TOKEN' => 195,
			'PLUS_OPR' => 100,
			'CHAR_LITERAL' => 204,
			'ASTARI_OPR' => 127,
			'END_TOKEN' => 48,
			'BEGIN_TOKEN' => 43,
			'PREFIX_OPR' => 106,
			'STRING_LITERAL' => 198,
			'TOOLS_TOKEN' => 49
		},
		GOTOS => {
			'IDENTIFIER' => 202,
			'primary_expression' => 209,
			'postfix_expression' => 210,
			'multiplicative_expression' => 383,
			'string_literal_list' => 212,
			'unary_operator' => 187,
			'unary_expression' => 281,
			'cast_expression' => 214
		}
	},
	{#State 304
		ACTIONS => {
			'SIZEOF_TOKEN' => 207,
			'AMP_OPR' => 110,
			'IDENTIFIER_ORG' => 39,
			'INTEGER_LITERAL' => 191,
			'MINUS_OPR' => 134,
			'SQL_TOKEN' => 45,
			'SECTION_TOKEN' => 40,
			'DECLARE_TOKEN' => 46,
			'FLOAT_LITERAL' => 200,
			'ORACLE_TOKEN' => 41,
			'EXEC_TOKEN' => 47,
			'POSTFIX_OPR' => 194,
			'LP_TOKEN' => 195,
			'PLUS_OPR' => 100,
			'CHAR_LITERAL' => 204,
			'ASTARI_OPR' => 127,
			'END_TOKEN' => 48,
			'BEGIN_TOKEN' => 43,
			'PREFIX_OPR' => 106,
			'STRING_LITERAL' => 198,
			'TOOLS_TOKEN' => 49
		},
		GOTOS => {
			'IDENTIFIER' => 202,
			'primary_expression' => 209,
			'shift_expression' => 384,
			'postfix_expression' => 210,
			'additive_expression' => 196,
			'string_literal_list' => 212,
			'multiplicative_expression' => 206,
			'unary_operator' => 187,
			'cast_expression' => 214,
			'unary_expression' => 281
		}
	},
	{#State 305
		ACTIONS => {
			'SIZEOF_TOKEN' => 207,
			'AMP_OPR' => 110,
			'IDENTIFIER_ORG' => 39,
			'INTEGER_LITERAL' => 191,
			'MINUS_OPR' => 134,
			'SQL_TOKEN' => 45,
			'SECTION_TOKEN' => 40,
			'DECLARE_TOKEN' => 46,
			'FLOAT_LITERAL' => 200,
			'ORACLE_TOKEN' => 41,
			'EXEC_TOKEN' => 47,
			'POSTFIX_OPR' => 194,
			'LP_TOKEN' => 195,
			'PLUS_OPR' => 100,
			'CHAR_LITERAL' => 204,
			'ASTARI_OPR' => 127,
			'END_TOKEN' => 48,
			'BEGIN_TOKEN' => 43,
			'PREFIX_OPR' => 106,
			'STRING_LITERAL' => 198,
			'TOOLS_TOKEN' => 49
		},
		GOTOS => {
			'IDENTIFIER' => 202,
			'primary_expression' => 209,
			'shift_expression' => 385,
			'postfix_expression' => 210,
			'additive_expression' => 196,
			'string_literal_list' => 212,
			'multiplicative_expression' => 206,
			'unary_operator' => 187,
			'cast_expression' => 214,
			'unary_expression' => 281
		}
	},
	{#State 306
		ACTIONS => {
			'SIZEOF_TOKEN' => 207,
			'AMP_OPR' => 110,
			'IDENTIFIER_ORG' => 39,
			'INTEGER_LITERAL' => 191,
			'MINUS_OPR' => 134,
			'SQL_TOKEN' => 45,
			'SECTION_TOKEN' => 40,
			'DECLARE_TOKEN' => 46,
			'FLOAT_LITERAL' => 200,
			'ORACLE_TOKEN' => 41,
			'EXEC_TOKEN' => 47,
			'POSTFIX_OPR' => 194,
			'LP_TOKEN' => 195,
			'PLUS_OPR' => 100,
			'CHAR_LITERAL' => 204,
			'ASTARI_OPR' => 127,
			'END_TOKEN' => 48,
			'BEGIN_TOKEN' => 43,
			'PREFIX_OPR' => 106,
			'STRING_LITERAL' => 198,
			'TOOLS_TOKEN' => 49
		},
		GOTOS => {
			'IDENTIFIER' => 202,
			'primary_expression' => 209,
			'shift_expression' => 386,
			'postfix_expression' => 210,
			'additive_expression' => 196,
			'string_literal_list' => 212,
			'multiplicative_expression' => 206,
			'unary_operator' => 187,
			'cast_expression' => 214,
			'unary_expression' => 281
		}
	},
	{#State 307
		ACTIONS => {
			'SIZEOF_TOKEN' => 207,
			'AMP_OPR' => 110,
			'IDENTIFIER_ORG' => 39,
			'INTEGER_LITERAL' => 191,
			'MINUS_OPR' => 134,
			'SQL_TOKEN' => 45,
			'SECTION_TOKEN' => 40,
			'DECLARE_TOKEN' => 46,
			'FLOAT_LITERAL' => 200,
			'ORACLE_TOKEN' => 41,
			'EXEC_TOKEN' => 47,
			'POSTFIX_OPR' => 194,
			'LP_TOKEN' => 195,
			'PLUS_OPR' => 100,
			'CHAR_LITERAL' => 204,
			'ASTARI_OPR' => 127,
			'END_TOKEN' => 48,
			'BEGIN_TOKEN' => 43,
			'PREFIX_OPR' => 106,
			'STRING_LITERAL' => 198,
			'TOOLS_TOKEN' => 49
		},
		GOTOS => {
			'IDENTIFIER' => 202,
			'primary_expression' => 209,
			'shift_expression' => 203,
			'postfix_expression' => 210,
			'additive_expression' => 196,
			'relational_expression' => 387,
			'string_literal_list' => 212,
			'multiplicative_expression' => 206,
			'unary_operator' => 187,
			'cast_expression' => 214,
			'unary_expression' => 281
		}
	},
	{#State 308
		ACTIONS => {
			'SIZEOF_TOKEN' => 207,
			'AMP_OPR' => 110,
			'IDENTIFIER_ORG' => 39,
			'INTEGER_LITERAL' => 191,
			'MINUS_OPR' => 134,
			'SQL_TOKEN' => 45,
			'SECTION_TOKEN' => 40,
			'DECLARE_TOKEN' => 46,
			'FLOAT_LITERAL' => 200,
			'ORACLE_TOKEN' => 41,
			'EXEC_TOKEN' => 47,
			'POSTFIX_OPR' => 194,
			'LP_TOKEN' => 195,
			'PLUS_OPR' => 100,
			'CHAR_LITERAL' => 204,
			'ASTARI_OPR' => 127,
			'END_TOKEN' => 48,
			'BEGIN_TOKEN' => 43,
			'PREFIX_OPR' => 106,
			'STRING_LITERAL' => 198,
			'TOOLS_TOKEN' => 49
		},
		GOTOS => {
			'IDENTIFIER' => 202,
			'primary_expression' => 209,
			'postfix_expression' => 210,
			'additive_expression' => 388,
			'multiplicative_expression' => 206,
			'string_literal_list' => 212,
			'unary_operator' => 187,
			'cast_expression' => 214,
			'unary_expression' => 281
		}
	},
	{#State 309
		ACTIONS => {
			'SIZEOF_TOKEN' => 207,
			'AMP_OPR' => 110,
			'IDENTIFIER_ORG' => 39,
			'INTEGER_LITERAL' => 191,
			'MINUS_OPR' => 134,
			'SQL_TOKEN' => 45,
			'SECTION_TOKEN' => 40,
			'DECLARE_TOKEN' => 46,
			'FLOAT_LITERAL' => 200,
			'ORACLE_TOKEN' => 41,
			'EXEC_TOKEN' => 47,
			'POSTFIX_OPR' => 194,
			'LP_TOKEN' => 195,
			'PLUS_OPR' => 100,
			'CHAR_LITERAL' => 204,
			'ASTARI_OPR' => 127,
			'END_TOKEN' => 48,
			'BEGIN_TOKEN' => 43,
			'PREFIX_OPR' => 106,
			'STRING_LITERAL' => 198,
			'TOOLS_TOKEN' => 49
		},
		GOTOS => {
			'IDENTIFIER' => 202,
			'equality_expression' => 201,
			'primary_expression' => 209,
			'shift_expression' => 203,
			'postfix_expression' => 210,
			'additive_expression' => 196,
			'exclusive_OR_expression' => 389,
			'relational_expression' => 197,
			'string_literal_list' => 212,
			'multiplicative_expression' => 206,
			'AND_expression' => 188,
			'unary_operator' => 187,
			'cast_expression' => 214,
			'unary_expression' => 281
		}
	},
	{#State 310
		ACTIONS => {
			'SIZEOF_TOKEN' => 207,
			'AMP_OPR' => 110,
			'IDENTIFIER_ORG' => 39,
			'INTEGER_LITERAL' => 191,
			'MINUS_OPR' => 134,
			'SQL_TOKEN' => 45,
			'SECTION_TOKEN' => 40,
			'DECLARE_TOKEN' => 46,
			'FLOAT_LITERAL' => 200,
			'ORACLE_TOKEN' => 41,
			'EXEC_TOKEN' => 47,
			'POSTFIX_OPR' => 194,
			'LP_TOKEN' => 195,
			'PLUS_OPR' => 100,
			'CHAR_LITERAL' => 204,
			'ASTARI_OPR' => 127,
			'END_TOKEN' => 48,
			'BEGIN_TOKEN' => 43,
			'PREFIX_OPR' => 106,
			'STRING_LITERAL' => 198,
			'TOOLS_TOKEN' => 49
		},
		GOTOS => {
			'IDENTIFIER' => 202,
			'string_literal_list' => 212,
			'unary_operator' => 187,
			'cast_expression' => 390,
			'primary_expression' => 209,
			'unary_expression' => 281,
			'postfix_expression' => 210
		}
	},
	{#State 311
		ACTIONS => {
			'SIZEOF_TOKEN' => 207,
			'AMP_OPR' => 110,
			'IDENTIFIER_ORG' => 39,
			'INTEGER_LITERAL' => 191,
			'MINUS_OPR' => 134,
			'SQL_TOKEN' => 45,
			'SECTION_TOKEN' => 40,
			'DECLARE_TOKEN' => 46,
			'FLOAT_LITERAL' => 200,
			'ORACLE_TOKEN' => 41,
			'EXEC_TOKEN' => 47,
			'POSTFIX_OPR' => 194,
			'LP_TOKEN' => 195,
			'PLUS_OPR' => 100,
			'CHAR_LITERAL' => 204,
			'ASTARI_OPR' => 127,
			'END_TOKEN' => 48,
			'BEGIN_TOKEN' => 43,
			'PREFIX_OPR' => 106,
			'STRING_LITERAL' => 198,
			'TOOLS_TOKEN' => 49
		},
		GOTOS => {
			'IDENTIFIER' => 202,
			'string_literal_list' => 212,
			'unary_operator' => 187,
			'cast_expression' => 391,
			'primary_expression' => 209,
			'unary_expression' => 281,
			'postfix_expression' => 210
		}
	},
	{#State 312
		DEFAULT => -23
	},
	{#State 313
		ACTIONS => {
			'SHORT_TOKEN' => 2,
			'ENUM_TOKEN' => 1,
			'IDENTIFIER_ORG' => 39,
			'LONG_TOKEN' => 5,
			'MINUS_OPR' => 134,
			'SECTION_TOKEN' => 40,
			'FLOAT_LITERAL' => 200,
			'ORACLE_TOKEN' => 41,
			'CHAR_TOKEN' => 13,
			'SIGNED_TOKEN' => 12,
			'CONST_TOKEN' => 14,
			'PLUS_OPR' => 100,
			'CHAR_LITERAL' => 204,
			'STRUCT_TOKEN' => 15,
			'TNAME_TOKEN' => 16,
			'UNSIGNED_TOKEN' => 17,
			'BEGIN_TOKEN' => 43,
			'PREFIX_OPR' => 106,
			'FLOAT_TOKEN' => 18,
			'VOLATILE_TOKEN' => 21,
			'SIZEOF_TOKEN' => 207,
			'AMP_OPR' => 110,
			'INTEGER_LITERAL' => 191,
			'VOID_TOKEN' => 22,
			'SQL_TOKEN' => 45,
			'DOUBLE_TOKEN' => 24,
			'INT_TOKEN' => 26,
			'_BOOL_TOKEN' => 27,
			'DECLARE_TOKEN' => 46,
			'EXEC_TOKEN' => 47,
			'POSTFIX_OPR' => 194,
			'LP_TOKEN' => 195,
			'_COMPLEX_TOKEN' => 32,
			'RESTRICT_TOKEN' => 35,
			'UNION_TOKEN' => 36,
			'ASTARI_OPR' => 127,
			'END_TOKEN' => 48,
			'STRING_LITERAL' => 198,
			'TOOLS_TOKEN' => 49
		},
		GOTOS => {
			'logical_OR_expression' => 208,
			'conditional_expression' => 199,
			'primary_expression' => 209,
			'struct_or_union_specifier' => 28,
			'expression' => 300,
			'type_qualifier' => 178,
			'unary_operator' => 187,
			'unary_expression' => 193,
			'enum_specifier' => 30,
			'specifier_qualifier_list' => 301,
			'type_name' => 392,
			'struct_or_union' => 33,
			'equality_expression' => 201,
			'IDENTIFIER' => 202,
			'shift_expression' => 203,
			'postfix_expression' => 210,
			'additive_expression' => 196,
			'exclusive_OR_expression' => 211,
			'inclusive_OR_expression' => 205,
			'relational_expression' => 197,
			'string_literal_list' => 212,
			'type_specifier' => 177,
			'AND_expression' => 188,
			'multiplicative_expression' => 206,
			'logical_AND_expression' => 213,
			'assignment_expression' => 221,
			'cast_expression' => 214
		}
	},
	{#State 314
		ACTIONS => {
			'SIZEOF_TOKEN' => 207,
			'AMP_OPR' => 110,
			'IDENTIFIER_ORG' => 39,
			'INTEGER_LITERAL' => 191,
			'MINUS_OPR' => 134,
			'SQL_TOKEN' => 45,
			'SECTION_TOKEN' => 40,
			'DECLARE_TOKEN' => 46,
			'FLOAT_LITERAL' => 200,
			'ORACLE_TOKEN' => 41,
			'EXEC_TOKEN' => 47,
			'POSTFIX_OPR' => 194,
			'LP_TOKEN' => 195,
			'PLUS_OPR' => 100,
			'CHAR_LITERAL' => 204,
			'ASTARI_OPR' => 127,
			'END_TOKEN' => 48,
			'BEGIN_TOKEN' => 43,
			'PREFIX_OPR' => 106,
			'STRING_LITERAL' => 198,
			'TOOLS_TOKEN' => 49
		},
		GOTOS => {
			'primary_expression' => 209,
			'unary_operator' => 187,
			'unary_expression' => 281,
			'equality_expression' => 201,
			'IDENTIFIER' => 202,
			'shift_expression' => 203,
			'additive_expression' => 196,
			'postfix_expression' => 210,
			'exclusive_OR_expression' => 211,
			'inclusive_OR_expression' => 205,
			'relational_expression' => 197,
			'AND_expression' => 188,
			'multiplicative_expression' => 206,
			'string_literal_list' => 212,
			'logical_AND_expression' => 393,
			'cast_expression' => 214
		}
	},
	{#State 315
		ACTIONS => {
			'SIZEOF_TOKEN' => 207,
			'AMP_OPR' => 110,
			'IDENTIFIER_ORG' => 39,
			'INTEGER_LITERAL' => 191,
			'MINUS_OPR' => 134,
			'SQL_TOKEN' => 45,
			'SECTION_TOKEN' => 40,
			'DECLARE_TOKEN' => 46,
			'FLOAT_LITERAL' => 200,
			'ORACLE_TOKEN' => 41,
			'EXEC_TOKEN' => 47,
			'POSTFIX_OPR' => 194,
			'LP_TOKEN' => 195,
			'PLUS_OPR' => 100,
			'CHAR_LITERAL' => 204,
			'ASTARI_OPR' => 127,
			'END_TOKEN' => 48,
			'BEGIN_TOKEN' => 43,
			'PREFIX_OPR' => 106,
			'STRING_LITERAL' => 198,
			'TOOLS_TOKEN' => 49
		},
		GOTOS => {
			'logical_OR_expression' => 208,
			'conditional_expression' => 199,
			'primary_expression' => 209,
			'expression' => 394,
			'unary_operator' => 187,
			'unary_expression' => 193,
			'equality_expression' => 201,
			'IDENTIFIER' => 202,
			'shift_expression' => 203,
			'additive_expression' => 196,
			'postfix_expression' => 210,
			'exclusive_OR_expression' => 211,
			'inclusive_OR_expression' => 205,
			'relational_expression' => 197,
			'string_literal_list' => 212,
			'AND_expression' => 188,
			'multiplicative_expression' => 206,
			'logical_AND_expression' => 213,
			'assignment_expression' => 221,
			'cast_expression' => 214
		}
	},
	{#State 316
		DEFAULT => -15
	},
	{#State 317
		ACTIONS => {
			'SIZEOF_TOKEN' => 207,
			'AMP_OPR' => 110,
			'IDENTIFIER_ORG' => 39,
			'RP_TOKEN' => 396,
			'INTEGER_LITERAL' => 191,
			'MINUS_OPR' => 134,
			'SQL_TOKEN' => 45,
			'SECTION_TOKEN' => 40,
			'DECLARE_TOKEN' => 46,
			'FLOAT_LITERAL' => 200,
			'ORACLE_TOKEN' => 41,
			'EXEC_TOKEN' => 47,
			'POSTFIX_OPR' => 194,
			'LP_TOKEN' => 195,
			'PLUS_OPR' => 100,
			'CHAR_LITERAL' => 204,
			'ASTARI_OPR' => 127,
			'END_TOKEN' => 48,
			'BEGIN_TOKEN' => 43,
			'PREFIX_OPR' => 106,
			'STRING_LITERAL' => 198,
			'TOOLS_TOKEN' => 49
		},
		GOTOS => {
			'logical_OR_expression' => 208,
			'conditional_expression' => 199,
			'primary_expression' => 209,
			'argument_expression_list' => 397,
			'unary_operator' => 187,
			'unary_expression' => 193,
			'equality_expression' => 201,
			'IDENTIFIER' => 202,
			'shift_expression' => 203,
			'additive_expression' => 196,
			'postfix_expression' => 210,
			'exclusive_OR_expression' => 211,
			'inclusive_OR_expression' => 205,
			'relational_expression' => 197,
			'string_literal_list' => 212,
			'AND_expression' => 188,
			'multiplicative_expression' => 206,
			'logical_AND_expression' => 213,
			'assignment_expression' => 395,
			'cast_expression' => 214
		}
	},
	{#State 318
		ACTIONS => {
			'SIZEOF_TOKEN' => 207,
			'AMP_OPR' => 110,
			'IDENTIFIER_ORG' => 39,
			'INTEGER_LITERAL' => 191,
			'MINUS_OPR' => 134,
			'SQL_TOKEN' => 45,
			'SECTION_TOKEN' => 40,
			'DECLARE_TOKEN' => 46,
			'FLOAT_LITERAL' => 200,
			'ORACLE_TOKEN' => 41,
			'EXEC_TOKEN' => 47,
			'POSTFIX_OPR' => 194,
			'LP_TOKEN' => 195,
			'PLUS_OPR' => 100,
			'CHAR_LITERAL' => 204,
			'ASTARI_OPR' => 127,
			'END_TOKEN' => 48,
			'BEGIN_TOKEN' => 43,
			'PREFIX_OPR' => 106,
			'STRING_LITERAL' => 198,
			'TOOLS_TOKEN' => 49
		},
		GOTOS => {
			'logical_OR_expression' => 208,
			'conditional_expression' => 199,
			'primary_expression' => 209,
			'expression' => 398,
			'unary_operator' => 187,
			'unary_expression' => 193,
			'equality_expression' => 201,
			'IDENTIFIER' => 202,
			'shift_expression' => 203,
			'additive_expression' => 196,
			'postfix_expression' => 210,
			'exclusive_OR_expression' => 211,
			'inclusive_OR_expression' => 205,
			'relational_expression' => 197,
			'string_literal_list' => 212,
			'AND_expression' => 188,
			'multiplicative_expression' => 206,
			'logical_AND_expression' => 213,
			'assignment_expression' => 221,
			'cast_expression' => 214
		}
	},
	{#State 319
		ACTIONS => {
			'IDENTIFIER_ORG' => 39,
			'END_TOKEN' => 48,
			'SQL_TOKEN' => 45,
			'SECTION_TOKEN' => 40,
			'BEGIN_TOKEN' => 43,
			'DECLARE_TOKEN' => 46,
			'EXEC_TOKEN' => 47,
			'TOOLS_TOKEN' => 49,
			'ORACLE_TOKEN' => 41
		},
		GOTOS => {
			'IDENTIFIER' => 399
		}
	},
	{#State 320
		ACTIONS => {
			'IDENTIFIER_ORG' => 39,
			'END_TOKEN' => 48,
			'SQL_TOKEN' => 45,
			'SECTION_TOKEN' => 40,
			'BEGIN_TOKEN' => 43,
			'DECLARE_TOKEN' => 46,
			'EXEC_TOKEN' => 47,
			'TOOLS_TOKEN' => 49,
			'ORACLE_TOKEN' => 41
		},
		GOTOS => {
			'IDENTIFIER' => 400
		}
	},
	{#State 321
		ACTIONS => {
			'SIZEOF_TOKEN' => 207,
			'AMP_OPR' => 110,
			'IDENTIFIER_ORG' => 39,
			'INTEGER_LITERAL' => 191,
			'MINUS_OPR' => 134,
			'SQL_TOKEN' => 45,
			'SECTION_TOKEN' => 40,
			'DECLARE_TOKEN' => 46,
			'FLOAT_LITERAL' => 200,
			'ORACLE_TOKEN' => 41,
			'EXEC_TOKEN' => 47,
			'POSTFIX_OPR' => 194,
			'LP_TOKEN' => 195,
			'PLUS_OPR' => 100,
			'CHAR_LITERAL' => 204,
			'ASTARI_OPR' => 127,
			'END_TOKEN' => 48,
			'BEGIN_TOKEN' => 43,
			'PREFIX_OPR' => 106,
			'STRING_LITERAL' => 198,
			'TOOLS_TOKEN' => 49
		},
		GOTOS => {
			'IDENTIFIER' => 202,
			'equality_expression' => 201,
			'primary_expression' => 209,
			'shift_expression' => 203,
			'postfix_expression' => 210,
			'additive_expression' => 196,
			'relational_expression' => 197,
			'string_literal_list' => 212,
			'multiplicative_expression' => 206,
			'AND_expression' => 401,
			'unary_operator' => 187,
			'cast_expression' => 214,
			'unary_expression' => 281
		}
	},
	{#State 322
		DEFAULT => -8
	},
	{#State 323
		ACTIONS => {
			'SIZEOF_TOKEN' => 207,
			'AMP_OPR' => 110,
			'IDENTIFIER_ORG' => 39,
			'INTEGER_LITERAL' => 191,
			'MINUS_OPR' => 134,
			'SQL_TOKEN' => 45,
			'SECTION_TOKEN' => 40,
			'DECLARE_TOKEN' => 46,
			'FLOAT_LITERAL' => 200,
			'ORACLE_TOKEN' => 41,
			'EXEC_TOKEN' => 47,
			'POSTFIX_OPR' => 194,
			'LP_TOKEN' => 195,
			'PLUS_OPR' => 100,
			'CHAR_LITERAL' => 204,
			'ASTARI_OPR' => 127,
			'END_TOKEN' => 48,
			'BEGIN_TOKEN' => 43,
			'PREFIX_OPR' => 106,
			'STRING_LITERAL' => 198,
			'TOOLS_TOKEN' => 49
		},
		GOTOS => {
			'IDENTIFIER' => 202,
			'equality_expression' => 201,
			'primary_expression' => 209,
			'shift_expression' => 203,
			'postfix_expression' => 210,
			'additive_expression' => 196,
			'exclusive_OR_expression' => 211,
			'inclusive_OR_expression' => 402,
			'relational_expression' => 197,
			'string_literal_list' => 212,
			'multiplicative_expression' => 206,
			'AND_expression' => 188,
			'unary_operator' => 187,
			'cast_expression' => 214,
			'unary_expression' => 281
		}
	},
	{#State 324
		ACTIONS => {
			'WHILE_TOKEN' => 403
		}
	},
	{#State 325
		ACTIONS => {
			'EXTERN_TOKEN' => 3,
			'SHORT_TOKEN' => 2,
			'ENUM_TOKEN' => 1,
			'IDENTIFIER_ORG' => 39,
			'LONG_TOKEN' => 5,
			'MINUS_OPR' => 134,
			'SMC_TOKEN' => 405,
			'SECTION_TOKEN' => 40,
			'INLINE_TOKEN' => 8,
			'FLOAT_LITERAL' => 200,
			'ORACLE_TOKEN' => 41,
			'CHAR_TOKEN' => 13,
			'SIGNED_TOKEN' => 12,
			'CONST_TOKEN' => 14,
			'PLUS_OPR' => 100,
			'CHAR_LITERAL' => 204,
			'STRUCT_TOKEN' => 15,
			'TNAME_TOKEN' => 16,
			'UNSIGNED_TOKEN' => 17,
			'BEGIN_TOKEN' => 43,
			'PREFIX_OPR' => 106,
			'FLOAT_TOKEN' => 18,
			'AUTO_TOKEN' => 19,
			'SIZEOF_TOKEN' => 207,
			'VOLATILE_TOKEN' => 21,
			'AMP_OPR' => 110,
			'INTEGER_LITERAL' => 191,
			'VOID_TOKEN' => 22,
			'SQL_TOKEN' => 45,
			'DOUBLE_TOKEN' => 24,
			'INT_TOKEN' => 26,
			'_BOOL_TOKEN' => 27,
			'DECLARE_TOKEN' => 46,
			'TYPEDEF_TOKEN' => 29,
			'EXEC_TOKEN' => 47,
			'POSTFIX_OPR' => 194,
			'LP_TOKEN' => 195,
			'_COMPLEX_TOKEN' => 32,
			'REGISTER_TOKEN' => 34,
			'RESTRICT_TOKEN' => 35,
			'UNION_TOKEN' => 36,
			'ASTARI_OPR' => 127,
			'END_TOKEN' => 48,
			'STATIC_TOKEN' => 37,
			'STRING_LITERAL' => 198,
			'TOOLS_TOKEN' => 49
		},
		GOTOS => {
			'function_specifier' => 4,
			'logical_OR_expression' => 208,
			'conditional_expression' => 199,
			'primary_expression' => 209,
			'declaration_specifiers' => 78,
			'declaration' => 404,
			'struct_or_union_specifier' => 28,
			'expression' => 406,
			'type_qualifier' => 9,
			'storage_class_specifier' => 10,
			'unary_operator' => 187,
			'unary_expression' => 193,
			'enum_specifier' => 30,
			'struct_or_union' => 33,
			'IDENTIFIER' => 202,
			'equality_expression' => 201,
			'shift_expression' => 203,
			'postfix_expression' => 210,
			'additive_expression' => 196,
			'exclusive_OR_expression' => 211,
			'inclusive_OR_expression' => 205,
			'relational_expression' => 197,
			'string_literal_list' => 212,
			'multiplicative_expression' => 206,
			'AND_expression' => 188,
			'type_specifier' => 38,
			'logical_AND_expression' => 213,
			'assignment_expression' => 221,
			'cast_expression' => 214
		}
	},
	{#State 326
		ACTIONS => {
			'SIZEOF_TOKEN' => 207,
			'AMP_OPR' => 110,
			'IDENTIFIER_ORG' => 39,
			'INTEGER_LITERAL' => 191,
			'MINUS_OPR' => 134,
			'SQL_TOKEN' => 45,
			'SECTION_TOKEN' => 40,
			'DECLARE_TOKEN' => 46,
			'FLOAT_LITERAL' => 200,
			'ORACLE_TOKEN' => 41,
			'EXEC_TOKEN' => 47,
			'POSTFIX_OPR' => 194,
			'LP_TOKEN' => 195,
			'PLUS_OPR' => 100,
			'CHAR_LITERAL' => 204,
			'ASTARI_OPR' => 127,
			'END_TOKEN' => 48,
			'BEGIN_TOKEN' => 43,
			'PREFIX_OPR' => 106,
			'STRING_LITERAL' => 198,
			'TOOLS_TOKEN' => 49
		},
		GOTOS => {
			'logical_OR_expression' => 208,
			'conditional_expression' => 199,
			'primary_expression' => 209,
			'expression' => 407,
			'unary_operator' => 187,
			'unary_expression' => 193,
			'equality_expression' => 201,
			'IDENTIFIER' => 202,
			'shift_expression' => 203,
			'additive_expression' => 196,
			'postfix_expression' => 210,
			'exclusive_OR_expression' => 211,
			'inclusive_OR_expression' => 205,
			'relational_expression' => 197,
			'string_literal_list' => 212,
			'AND_expression' => 188,
			'multiplicative_expression' => 206,
			'logical_AND_expression' => 213,
			'assignment_expression' => 221,
			'cast_expression' => 214
		}
	},
	{#State 327
		DEFAULT => -228
	},
	{#State 328
		ACTIONS => {
			'CM_TOKEN' => 331,
			'SMC_TOKEN' => 408
		}
	},
	{#State 329
		ACTIONS => {
			'DEFAULT_TOKEN' => 227,
			'IDENTIFIER_ORG' => 39,
			'MINUS_OPR' => 134,
			'SMC_TOKEN' => 229,
			'SECTION_TOKEN' => 40,
			'DO_TOKEN' => 216,
			'WHILE_TOKEN' => 231,
			'CASE_TOKEN' => 233,
			'FLOAT_LITERAL' => 200,
			'ORACLE_TOKEN' => 41,
			'PLUS_OPR' => 100,
			'FOR_TOKEN' => 218,
			'CHAR_LITERAL' => 204,
			'SWITCH_TOKEN' => 220,
			'BEGIN_TOKEN' => 43,
			'PREFIX_OPR' => 106,
			'SIZEOF_TOKEN' => 207,
			'AMP_OPR' => 110,
			'RETURN_TOKEN' => 223,
			'INTEGER_LITERAL' => 191,
			'LCB_TOKEN' => 80,
			'SQL_TOKEN' => 45,
			'DECLARE_TOKEN' => 46,
			'CONTINUE_TOKEN' => 238,
			'GOTO_TOKEN' => 239,
			'EXEC_TOKEN' => 225,
			'POSTFIX_OPR' => 194,
			'LP_TOKEN' => 195,
			'BREAK_TOKEN' => 240,
			'IF_TOKEN' => 241,
			'ASTARI_OPR' => 127,
			'END_TOKEN' => 48,
			'STRING_LITERAL' => 198,
			'TOOLS_TOKEN' => 49
		},
		GOTOS => {
			'jump_statement' => 237,
			'iteration_statement' => 215,
			'logical_OR_expression' => 208,
			'expression_statement' => 228,
			'conditional_expression' => 199,
			'primary_expression' => 209,
			'embedded_sql' => 230,
			'statement' => 409,
			'expression' => 232,
			'unary_operator' => 187,
			'unary_expression' => 193,
			'equality_expression' => 201,
			'IDENTIFIER' => 236,
			'compound_statement' => 226,
			'labeled_statement' => 242,
			'shift_expression' => 203,
			'postfix_expression' => 210,
			'additive_expression' => 196,
			'exclusive_OR_expression' => 211,
			'inclusive_OR_expression' => 205,
			'relational_expression' => 197,
			'string_literal_list' => 212,
			'multiplicative_expression' => 206,
			'AND_expression' => 188,
			'logical_AND_expression' => 213,
			'assignment_expression' => 221,
			'cast_expression' => 214,
			'selection_statement' => 222
		}
	},
	{#State 330
		ACTIONS => {
			'SIZEOF_TOKEN' => 207,
			'AMP_OPR' => 110,
			'IDENTIFIER_ORG' => 39,
			'INTEGER_LITERAL' => 191,
			'MINUS_OPR' => 134,
			'SQL_TOKEN' => 45,
			'SECTION_TOKEN' => 40,
			'DECLARE_TOKEN' => 46,
			'FLOAT_LITERAL' => 200,
			'ORACLE_TOKEN' => 41,
			'EXEC_TOKEN' => 47,
			'POSTFIX_OPR' => 194,
			'LP_TOKEN' => 195,
			'PLUS_OPR' => 100,
			'CHAR_LITERAL' => 204,
			'ASTARI_OPR' => 127,
			'END_TOKEN' => 48,
			'BEGIN_TOKEN' => 43,
			'PREFIX_OPR' => 106,
			'STRING_LITERAL' => 198,
			'TOOLS_TOKEN' => 49
		},
		GOTOS => {
			'logical_OR_expression' => 208,
			'conditional_expression' => 199,
			'primary_expression' => 209,
			'expression' => 410,
			'unary_operator' => 187,
			'unary_expression' => 193,
			'equality_expression' => 201,
			'IDENTIFIER' => 202,
			'shift_expression' => 203,
			'additive_expression' => 196,
			'postfix_expression' => 210,
			'exclusive_OR_expression' => 211,
			'inclusive_OR_expression' => 205,
			'relational_expression' => 197,
			'string_literal_list' => 212,
			'AND_expression' => 188,
			'multiplicative_expression' => 206,
			'logical_AND_expression' => 213,
			'assignment_expression' => 221,
			'cast_expression' => 214
		}
	},
	{#State 331
		ACTIONS => {
			'SIZEOF_TOKEN' => 207,
			'AMP_OPR' => 110,
			'IDENTIFIER_ORG' => 39,
			'INTEGER_LITERAL' => 191,
			'MINUS_OPR' => 134,
			'SQL_TOKEN' => 45,
			'SECTION_TOKEN' => 40,
			'DECLARE_TOKEN' => 46,
			'FLOAT_LITERAL' => 200,
			'ORACLE_TOKEN' => 41,
			'EXEC_TOKEN' => 47,
			'POSTFIX_OPR' => 194,
			'LP_TOKEN' => 195,
			'PLUS_OPR' => 100,
			'CHAR_LITERAL' => 204,
			'ASTARI_OPR' => 127,
			'END_TOKEN' => 48,
			'BEGIN_TOKEN' => 43,
			'PREFIX_OPR' => 106,
			'STRING_LITERAL' => 198,
			'TOOLS_TOKEN' => 49
		},
		GOTOS => {
			'logical_OR_expression' => 208,
			'conditional_expression' => 199,
			'primary_expression' => 209,
			'unary_operator' => 187,
			'unary_expression' => 193,
			'equality_expression' => 201,
			'IDENTIFIER' => 202,
			'shift_expression' => 203,
			'additive_expression' => 196,
			'postfix_expression' => 210,
			'exclusive_OR_expression' => 211,
			'inclusive_OR_expression' => 205,
			'relational_expression' => 197,
			'AND_expression' => 188,
			'multiplicative_expression' => 206,
			'string_literal_list' => 212,
			'logical_AND_expression' => 213,
			'assignment_expression' => 411,
			'cast_expression' => 214
		}
	},
	{#State 332
		DEFAULT => -205
	},
	{#State 333
		ACTIONS => {
			'CLN_TOKEN' => 412
		}
	},
	{#State 334
		DEFAULT => -200
	},
	{#State 335
		DEFAULT => -202
	},
	{#State 336
		ACTIONS => {
			'DEFAULT_TOKEN' => 227,
			'IDENTIFIER_ORG' => 39,
			'MINUS_OPR' => 134,
			'SMC_TOKEN' => 229,
			'SECTION_TOKEN' => 40,
			'DO_TOKEN' => 216,
			'WHILE_TOKEN' => 231,
			'CASE_TOKEN' => 233,
			'FLOAT_LITERAL' => 200,
			'ORACLE_TOKEN' => 41,
			'PLUS_OPR' => 100,
			'FOR_TOKEN' => 218,
			'CHAR_LITERAL' => 204,
			'SWITCH_TOKEN' => 220,
			'BEGIN_TOKEN' => 43,
			'PREFIX_OPR' => 106,
			'SIZEOF_TOKEN' => 207,
			'AMP_OPR' => 110,
			'RETURN_TOKEN' => 223,
			'INTEGER_LITERAL' => 191,
			'LCB_TOKEN' => 80,
			'SQL_TOKEN' => 45,
			'DECLARE_TOKEN' => 46,
			'CONTINUE_TOKEN' => 238,
			'GOTO_TOKEN' => 239,
			'EXEC_TOKEN' => 225,
			'POSTFIX_OPR' => 194,
			'LP_TOKEN' => 195,
			'BREAK_TOKEN' => 240,
			'IF_TOKEN' => 241,
			'ASTARI_OPR' => 127,
			'END_TOKEN' => 48,
			'STRING_LITERAL' => 198,
			'TOOLS_TOKEN' => 49
		},
		GOTOS => {
			'jump_statement' => 237,
			'iteration_statement' => 215,
			'logical_OR_expression' => 208,
			'expression_statement' => 228,
			'conditional_expression' => 199,
			'primary_expression' => 209,
			'embedded_sql' => 230,
			'statement' => 413,
			'expression' => 232,
			'unary_operator' => 187,
			'unary_expression' => 193,
			'equality_expression' => 201,
			'IDENTIFIER' => 236,
			'compound_statement' => 226,
			'labeled_statement' => 242,
			'shift_expression' => 203,
			'postfix_expression' => 210,
			'additive_expression' => 196,
			'exclusive_OR_expression' => 211,
			'inclusive_OR_expression' => 205,
			'relational_expression' => 197,
			'string_literal_list' => 212,
			'multiplicative_expression' => 206,
			'AND_expression' => 188,
			'logical_AND_expression' => 213,
			'assignment_expression' => 221,
			'cast_expression' => 214,
			'selection_statement' => 222
		}
	},
	{#State 337
		DEFAULT => -225
	},
	{#State 338
		ACTIONS => {
			'SMC_TOKEN' => 414
		}
	},
	{#State 339
		DEFAULT => -226
	},
	{#State 340
		ACTIONS => {
			'SIZEOF_TOKEN' => 207,
			'AMP_OPR' => 110,
			'IDENTIFIER_ORG' => 39,
			'INTEGER_LITERAL' => 191,
			'MINUS_OPR' => 134,
			'SQL_TOKEN' => 45,
			'SECTION_TOKEN' => 40,
			'DECLARE_TOKEN' => 46,
			'FLOAT_LITERAL' => 200,
			'ORACLE_TOKEN' => 41,
			'EXEC_TOKEN' => 47,
			'POSTFIX_OPR' => 194,
			'LP_TOKEN' => 195,
			'PLUS_OPR' => 100,
			'CHAR_LITERAL' => 204,
			'ASTARI_OPR' => 127,
			'END_TOKEN' => 48,
			'BEGIN_TOKEN' => 43,
			'PREFIX_OPR' => 106,
			'STRING_LITERAL' => 198,
			'TOOLS_TOKEN' => 49
		},
		GOTOS => {
			'logical_OR_expression' => 208,
			'conditional_expression' => 199,
			'primary_expression' => 209,
			'expression' => 415,
			'unary_operator' => 187,
			'unary_expression' => 193,
			'equality_expression' => 201,
			'IDENTIFIER' => 202,
			'shift_expression' => 203,
			'additive_expression' => 196,
			'postfix_expression' => 210,
			'exclusive_OR_expression' => 211,
			'inclusive_OR_expression' => 205,
			'relational_expression' => 197,
			'string_literal_list' => 212,
			'AND_expression' => 188,
			'multiplicative_expression' => 206,
			'logical_AND_expression' => 213,
			'assignment_expression' => 221,
			'cast_expression' => 214
		}
	},
	{#State 341
		DEFAULT => -135
	},
	{#State 342
		ACTIONS => {
			'RSB_TOKEN' => 416
		}
	},
	{#State 343
		ACTIONS => {
			'RSB_TOKEN' => 417
		},
		DEFAULT => -26
	},
	{#State 344
		DEFAULT => -136
	},
	{#State 345
		ACTIONS => {
			'SIZEOF_TOKEN' => 207,
			'AMP_OPR' => 110,
			'IDENTIFIER_ORG' => 39,
			'INTEGER_LITERAL' => 191,
			'MINUS_OPR' => 134,
			'SQL_TOKEN' => 45,
			'SECTION_TOKEN' => 40,
			'DECLARE_TOKEN' => 46,
			'FLOAT_LITERAL' => 200,
			'ORACLE_TOKEN' => 41,
			'EXEC_TOKEN' => 47,
			'POSTFIX_OPR' => 194,
			'LP_TOKEN' => 195,
			'PLUS_OPR' => 100,
			'CHAR_LITERAL' => 204,
			'ASTARI_OPR' => 127,
			'END_TOKEN' => 48,
			'BEGIN_TOKEN' => 43,
			'PREFIX_OPR' => 106,
			'STRING_LITERAL' => 198,
			'TOOLS_TOKEN' => 49
		},
		GOTOS => {
			'logical_OR_expression' => 208,
			'conditional_expression' => 199,
			'primary_expression' => 209,
			'unary_operator' => 187,
			'unary_expression' => 193,
			'equality_expression' => 201,
			'IDENTIFIER' => 202,
			'shift_expression' => 203,
			'additive_expression' => 196,
			'postfix_expression' => 210,
			'exclusive_OR_expression' => 211,
			'inclusive_OR_expression' => 205,
			'relational_expression' => 197,
			'AND_expression' => 188,
			'multiplicative_expression' => 206,
			'string_literal_list' => 212,
			'logical_AND_expression' => 213,
			'assignment_expression' => 418,
			'cast_expression' => 214
		}
	},
	{#State 346
		DEFAULT => -142
	},
	{#State 347
		ACTIONS => {
			'RSB_TOKEN' => 419
		}
	},
	{#State 348
		ACTIONS => {
			'SIZEOF_TOKEN' => 207,
			'VOLATILE_TOKEN' => 21,
			'AMP_OPR' => 110,
			'IDENTIFIER_ORG' => 39,
			'INTEGER_LITERAL' => 191,
			'MINUS_OPR' => 134,
			'SQL_TOKEN' => 45,
			'SECTION_TOKEN' => 40,
			'DECLARE_TOKEN' => 46,
			'FLOAT_LITERAL' => 200,
			'ORACLE_TOKEN' => 41,
			'EXEC_TOKEN' => 47,
			'POSTFIX_OPR' => 194,
			'LP_TOKEN' => 195,
			'CONST_TOKEN' => 14,
			'PLUS_OPR' => 100,
			'RESTRICT_TOKEN' => 35,
			'CHAR_LITERAL' => 204,
			'ASTARI_OPR' => 127,
			'END_TOKEN' => 48,
			'BEGIN_TOKEN' => 43,
			'PREFIX_OPR' => 106,
			'STRING_LITERAL' => 198,
			'TOOLS_TOKEN' => 49
		},
		GOTOS => {
			'logical_OR_expression' => 208,
			'conditional_expression' => 199,
			'primary_expression' => 209,
			'type_qualifier' => 258,
			'unary_operator' => 187,
			'unary_expression' => 193,
			'equality_expression' => 201,
			'IDENTIFIER' => 202,
			'shift_expression' => 203,
			'additive_expression' => 196,
			'postfix_expression' => 210,
			'exclusive_OR_expression' => 211,
			'inclusive_OR_expression' => 205,
			'relational_expression' => 197,
			'string_literal_list' => 212,
			'AND_expression' => 188,
			'multiplicative_expression' => 206,
			'logical_AND_expression' => 213,
			'assignment_expression' => 420,
			'cast_expression' => 214
		}
	},
	{#State 349
		DEFAULT => -156
	},
	{#State 350
		ACTIONS => {
			'EXTERN_TOKEN' => 3,
			'SHORT_TOKEN' => 2,
			'ENUM_TOKEN' => 1,
			'IDENTIFIER_ORG' => 39,
			'LONG_TOKEN' => 5,
			'LSB_TOKEN' => 352,
			'SECTION_TOKEN' => 40,
			'INLINE_TOKEN' => 8,
			'ORACLE_TOKEN' => 41,
			'CHAR_TOKEN' => 13,
			'SIGNED_TOKEN' => 12,
			'CONST_TOKEN' => 14,
			'STRUCT_TOKEN' => 15,
			'TNAME_TOKEN' => 16,
			'UNSIGNED_TOKEN' => 17,
			'BEGIN_TOKEN' => 43,
			'FLOAT_TOKEN' => 18,
			'AUTO_TOKEN' => 19,
			'VOLATILE_TOKEN' => 21,
			'RP_TOKEN' => 421,
			'VOID_TOKEN' => 22,
			'DOUBLE_TOKEN' => 24,
			'SQL_TOKEN' => 45,
			'INT_TOKEN' => 26,
			'_BOOL_TOKEN' => 27,
			'DECLARE_TOKEN' => 46,
			'TYPEDEF_TOKEN' => 29,
			'EXEC_TOKEN' => 47,
			'LP_TOKEN' => 350,
			'_COMPLEX_TOKEN' => 32,
			'REGISTER_TOKEN' => 34,
			'RESTRICT_TOKEN' => 35,
			'UNION_TOKEN' => 36,
			'ASTARI_OPR' => 59,
			'END_TOKEN' => 48,
			'STATIC_TOKEN' => 37,
			'TOOLS_TOKEN' => 49
		},
		GOTOS => {
			'function_specifier' => 4,
			'declarator' => 84,
			'parameter_declaration' => 251,
			'declaration_specifiers' => 252,
			'struct_or_union_specifier' => 28,
			'type_qualifier' => 9,
			'storage_class_specifier' => 10,
			'enum_specifier' => 30,
			'parameter_list' => 256,
			'abstract_declarator' => 422,
			'direct_declarator' => 58,
			'parameter_type_list' => 423,
			'struct_or_union' => 33,
			'IDENTIFIER' => 53,
			'direct_abstract_declarator' => 353,
			'pointer' => 354,
			'type_specifier' => 38
		}
	},
	{#State 351
		DEFAULT => -157
	},
	{#State 352
		ACTIONS => {
			'SIZEOF_TOKEN' => 207,
			'AMP_OPR' => 110,
			'IDENTIFIER_ORG' => 39,
			'INTEGER_LITERAL' => 191,
			'MINUS_OPR' => 134,
			'SQL_TOKEN' => 45,
			'SECTION_TOKEN' => 40,
			'DECLARE_TOKEN' => 46,
			'RSB_TOKEN' => 426,
			'FLOAT_LITERAL' => 200,
			'ORACLE_TOKEN' => 41,
			'EXEC_TOKEN' => 47,
			'POSTFIX_OPR' => 194,
			'LP_TOKEN' => 195,
			'PLUS_OPR' => 100,
			'CHAR_LITERAL' => 204,
			'ASTARI_OPR' => 425,
			'END_TOKEN' => 48,
			'BEGIN_TOKEN' => 43,
			'PREFIX_OPR' => 106,
			'STRING_LITERAL' => 198,
			'TOOLS_TOKEN' => 49
		},
		GOTOS => {
			'logical_OR_expression' => 208,
			'conditional_expression' => 199,
			'primary_expression' => 209,
			'unary_operator' => 187,
			'unary_expression' => 193,
			'equality_expression' => 201,
			'IDENTIFIER' => 202,
			'shift_expression' => 203,
			'additive_expression' => 196,
			'postfix_expression' => 210,
			'exclusive_OR_expression' => 211,
			'inclusive_OR_expression' => 205,
			'relational_expression' => 197,
			'AND_expression' => 188,
			'multiplicative_expression' => 206,
			'string_literal_list' => 212,
			'logical_AND_expression' => 213,
			'assignment_expression' => 424,
			'cast_expression' => 214
		}
	},
	{#State 353
		ACTIONS => {
			'LSB_TOKEN' => 428,
			'LP_TOKEN' => 427
		},
		DEFAULT => -165
	},
	{#State 354
		ACTIONS => {
			'IDENTIFIER_ORG' => 39,
			'END_TOKEN' => 48,
			'SQL_TOKEN' => 45,
			'LSB_TOKEN' => 352,
			'SECTION_TOKEN' => 40,
			'DECLARE_TOKEN' => 46,
			'BEGIN_TOKEN' => 43,
			'EXEC_TOKEN' => 47,
			'LP_TOKEN' => 350,
			'TOOLS_TOKEN' => 49,
			'ORACLE_TOKEN' => 41
		},
		DEFAULT => -163,
		GOTOS => {
			'direct_declarator' => 77,
			'direct_abstract_declarator' => 429,
			'IDENTIFIER' => 53
		}
	},
	{#State 355
		ACTIONS => {
			'IDENTIFIER_ORG' => 39,
			'END_TOKEN' => 48,
			'SQL_TOKEN' => 45,
			'SECTION_TOKEN' => 40,
			'BEGIN_TOKEN' => 43,
			'DECLARE_TOKEN' => 46,
			'EXEC_TOKEN' => 47,
			'TOOLS_TOKEN' => 49,
			'ORACLE_TOKEN' => 41
		},
		GOTOS => {
			'IDENTIFIER' => 430
		}
	},
	{#State 356
		DEFAULT => -144
	},
	{#State 357
		ACTIONS => {
			'VOLATILE_TOKEN' => 21,
			'EXTERN_TOKEN' => 3,
			'SHORT_TOKEN' => 2,
			'ENUM_TOKEN' => 1,
			'LONG_TOKEN' => 5,
			'VOID_TOKEN' => 22,
			'DOUBLE_TOKEN' => 24,
			'INT_TOKEN' => 26,
			'_BOOL_TOKEN' => 27,
			'INLINE_TOKEN' => 8,
			'ELLIPSIS_TOKEN' => 432,
			'TYPEDEF_TOKEN' => 29,
			'_COMPLEX_TOKEN' => 32,
			'CHAR_TOKEN' => 13,
			'SIGNED_TOKEN' => 12,
			'CONST_TOKEN' => 14,
			'REGISTER_TOKEN' => 34,
			'RESTRICT_TOKEN' => 35,
			'UNION_TOKEN' => 36,
			'STRUCT_TOKEN' => 15,
			'STATIC_TOKEN' => 37,
			'TNAME_TOKEN' => 16,
			'UNSIGNED_TOKEN' => 17,
			'FLOAT_TOKEN' => 18,
			'AUTO_TOKEN' => 19
		},
		GOTOS => {
			'struct_or_union' => 33,
			'function_specifier' => 4,
			'parameter_declaration' => 431,
			'declaration_specifiers' => 252,
			'struct_or_union_specifier' => 28,
			'type_specifier' => 38,
			'type_qualifier' => 9,
			'storage_class_specifier' => 10,
			'enum_specifier' => 30
		}
	},
	{#State 358
		DEFAULT => -143
	},
	{#State 359
		DEFAULT => -243
	},
	{#State 360
		DEFAULT => -244
	},
	{#State 361
		DEFAULT => -99
	},
	{#State 362
		DEFAULT => -115
	},
	{#State 363
		ACTIONS => {
			'SIZEOF_TOKEN' => 207,
			'AMP_OPR' => 110,
			'IDENTIFIER_ORG' => 39,
			'INTEGER_LITERAL' => 191,
			'MINUS_OPR' => 134,
			'SQL_TOKEN' => 45,
			'SECTION_TOKEN' => 40,
			'DECLARE_TOKEN' => 46,
			'FLOAT_LITERAL' => 200,
			'ORACLE_TOKEN' => 41,
			'EXEC_TOKEN' => 47,
			'POSTFIX_OPR' => 194,
			'LP_TOKEN' => 195,
			'PLUS_OPR' => 100,
			'CHAR_LITERAL' => 204,
			'ASTARI_OPR' => 127,
			'END_TOKEN' => 48,
			'BEGIN_TOKEN' => 43,
			'PREFIX_OPR' => 106,
			'STRING_LITERAL' => 198,
			'TOOLS_TOKEN' => 49
		},
		GOTOS => {
			'logical_OR_expression' => 208,
			'conditional_expression' => 282,
			'primary_expression' => 209,
			'unary_operator' => 187,
			'unary_expression' => 281,
			'equality_expression' => 201,
			'IDENTIFIER' => 202,
			'constant_expression' => 433,
			'shift_expression' => 203,
			'additive_expression' => 196,
			'postfix_expression' => 210,
			'exclusive_OR_expression' => 211,
			'inclusive_OR_expression' => 205,
			'relational_expression' => 197,
			'AND_expression' => 188,
			'multiplicative_expression' => 206,
			'string_literal_list' => 212,
			'logical_AND_expression' => 213,
			'cast_expression' => 214
		}
	},
	{#State 364
		ACTIONS => {
			'IDENTIFIER_ORG' => 39,
			'ASTARI_OPR' => 59,
			'END_TOKEN' => 48,
			'SQL_TOKEN' => 45,
			'SECTION_TOKEN' => 40,
			'DECLARE_TOKEN' => 46,
			'BEGIN_TOKEN' => 43,
			'CLN_TOKEN' => 271,
			'EXEC_TOKEN' => 47,
			'LP_TOKEN' => 57,
			'TOOLS_TOKEN' => 49,
			'ORACLE_TOKEN' => 41
		},
		GOTOS => {
			'direct_declarator' => 58,
			'IDENTIFIER' => 53,
			'pointer' => 55,
			'declarator' => 272,
			'struct_declarator' => 434
		}
	},
	{#State 365
		DEFAULT => -106
	},
	{#State 366
		DEFAULT => -118
	},
	{#State 367
		ACTIONS => {
			'EQUALITY_OPR' => 307
		},
		DEFAULT => -47
	},
	{#State 368
		ACTIONS => {
			'RSB_TOKEN' => 435
		}
	},
	{#State 369
		DEFAULT => -180
	},
	{#State 370
		DEFAULT => -188
	},
	{#State 371
		DEFAULT => -186
	},
	{#State 372
		DEFAULT => -184
	},
	{#State 373
		ACTIONS => {
			'SIZEOF_TOKEN' => 207,
			'AMP_OPR' => 110,
			'IDENTIFIER_ORG' => 39,
			'INTEGER_LITERAL' => 191,
			'MINUS_OPR' => 134,
			'LCB_TOKEN' => 192,
			'SQL_TOKEN' => 45,
			'LSB_TOKEN' => 287,
			'SECTION_TOKEN' => 40,
			'DECLARE_TOKEN' => 46,
			'FLOAT_LITERAL' => 200,
			'ORACLE_TOKEN' => 41,
			'LP_TOKEN' => 195,
			'EXEC_TOKEN' => 47,
			'POSTFIX_OPR' => 194,
			'DOT_TOKEN' => 289,
			'PLUS_OPR' => 100,
			'RCB_TOKEN' => 436,
			'CHAR_LITERAL' => 204,
			'ASTARI_OPR' => 127,
			'END_TOKEN' => 48,
			'BEGIN_TOKEN' => 43,
			'PREFIX_OPR' => 106,
			'STRING_LITERAL' => 198,
			'TOOLS_TOKEN' => 49
		},
		GOTOS => {
			'logical_OR_expression' => 208,
			'conditional_expression' => 199,
			'primary_expression' => 209,
			'designation' => 438,
			'unary_operator' => 187,
			'unary_expression' => 193,
			'equality_expression' => 201,
			'IDENTIFIER' => 202,
			'designator_list' => 290,
			'shift_expression' => 203,
			'postfix_expression' => 210,
			'additive_expression' => 196,
			'exclusive_OR_expression' => 211,
			'designator' => 291,
			'inclusive_OR_expression' => 205,
			'relational_expression' => 197,
			'string_literal_list' => 212,
			'AND_expression' => 188,
			'multiplicative_expression' => 206,
			'logical_AND_expression' => 213,
			'assignment_expression' => 189,
			'cast_expression' => 214,
			'initializer' => 437
		}
	},
	{#State 374
		DEFAULT => -178
	},
	{#State 375
		DEFAULT => -59
	},
	{#State 376
		ACTIONS => {
			'RP_TOKEN' => 439
		}
	},
	{#State 377
		ACTIONS => {
			'SIZEOF_TOKEN' => 207,
			'AMP_OPR' => 110,
			'IDENTIFIER_ORG' => 39,
			'INTEGER_LITERAL' => 191,
			'MINUS_OPR' => 134,
			'LCB_TOKEN' => 440,
			'SQL_TOKEN' => 45,
			'SECTION_TOKEN' => 40,
			'DECLARE_TOKEN' => 46,
			'FLOAT_LITERAL' => 200,
			'ORACLE_TOKEN' => 41,
			'EXEC_TOKEN' => 47,
			'POSTFIX_OPR' => 194,
			'LP_TOKEN' => 195,
			'PLUS_OPR' => 100,
			'CHAR_LITERAL' => 204,
			'ASTARI_OPR' => 127,
			'END_TOKEN' => 48,
			'BEGIN_TOKEN' => 43,
			'PREFIX_OPR' => 106,
			'STRING_LITERAL' => 198,
			'TOOLS_TOKEN' => 49
		},
		GOTOS => {
			'IDENTIFIER' => 202,
			'string_literal_list' => 212,
			'unary_operator' => 187,
			'cast_expression' => 441,
			'primary_expression' => 209,
			'unary_expression' => 281,
			'postfix_expression' => 210
		}
	},
	{#State 378
		DEFAULT => -6
	},
	{#State 379
		ACTIONS => {
			'VOLATILE_TOKEN' => 21,
			'EXTERN_TOKEN' => 3,
			'SHORT_TOKEN' => 2,
			'ENUM_TOKEN' => 1,
			'RP_TOKEN' => 421,
			'LONG_TOKEN' => 5,
			'VOID_TOKEN' => 22,
			'LSB_TOKEN' => 352,
			'DOUBLE_TOKEN' => 24,
			'INT_TOKEN' => 26,
			'_BOOL_TOKEN' => 27,
			'INLINE_TOKEN' => 8,
			'TYPEDEF_TOKEN' => 29,
			'LP_TOKEN' => 379,
			'_COMPLEX_TOKEN' => 32,
			'CHAR_TOKEN' => 13,
			'SIGNED_TOKEN' => 12,
			'CONST_TOKEN' => 14,
			'REGISTER_TOKEN' => 34,
			'RESTRICT_TOKEN' => 35,
			'UNION_TOKEN' => 36,
			'STRUCT_TOKEN' => 15,
			'ASTARI_OPR' => 59,
			'STATIC_TOKEN' => 37,
			'TNAME_TOKEN' => 16,
			'UNSIGNED_TOKEN' => 17,
			'FLOAT_TOKEN' => 18,
			'AUTO_TOKEN' => 19
		},
		GOTOS => {
			'parameter_type_list' => 423,
			'struct_or_union' => 33,
			'function_specifier' => 4,
			'parameter_declaration' => 251,
			'direct_abstract_declarator' => 353,
			'declaration_specifiers' => 252,
			'struct_or_union_specifier' => 28,
			'pointer' => 381,
			'type_specifier' => 38,
			'type_qualifier' => 9,
			'storage_class_specifier' => 10,
			'enum_specifier' => 30,
			'parameter_list' => 256,
			'abstract_declarator' => 422
		}
	},
	{#State 380
		DEFAULT => -161
	},
	{#State 381
		ACTIONS => {
			'LSB_TOKEN' => 352,
			'LP_TOKEN' => 379
		},
		DEFAULT => -163,
		GOTOS => {
			'direct_abstract_declarator' => 429
		}
	},
	{#State 382
		ACTIONS => {
			'MULTI_OPR' => 310,
			'ASTARI_OPR' => 311
		},
		DEFAULT => -36
	},
	{#State 383
		ACTIONS => {
			'MULTI_OPR' => 310,
			'ASTARI_OPR' => 311
		},
		DEFAULT => -37
	},
	{#State 384
		ACTIONS => {
			'SHIFT_OPR' => 308
		},
		DEFAULT => -42
	},
	{#State 385
		ACTIONS => {
			'SHIFT_OPR' => 308
		},
		DEFAULT => -43
	},
	{#State 386
		ACTIONS => {
			'SHIFT_OPR' => 308
		},
		DEFAULT => -41
	},
	{#State 387
		ACTIONS => {
			'GT_OPR' => 304,
			'RELATIONAL_OPR' => 305,
			'LT_OPR' => 306
		},
		DEFAULT => -45
	},
	{#State 388
		ACTIONS => {
			'MINUS_OPR' => 303,
			'PLUS_OPR' => 302
		},
		DEFAULT => -39
	},
	{#State 389
		ACTIONS => {
			'NOR_OPR' => 321
		},
		DEFAULT => -51
	},
	{#State 390
		DEFAULT => -34
	},
	{#State 391
		DEFAULT => -33
	},
	{#State 392
		ACTIONS => {
			'RP_TOKEN' => 442
		}
	},
	{#State 393
		ACTIONS => {
			'CAND_OPR' => 323
		},
		DEFAULT => -55
	},
	{#State 394
		ACTIONS => {
			'CM_TOKEN' => 331,
			'CLN_TOKEN' => 443
		}
	},
	{#State 395
		DEFAULT => -18
	},
	{#State 396
		DEFAULT => -12
	},
	{#State 397
		ACTIONS => {
			'CM_TOKEN' => 444,
			'RP_TOKEN' => 445
		}
	},
	{#State 398
		ACTIONS => {
			'CM_TOKEN' => 331,
			'RSB_TOKEN' => 446
		}
	},
	{#State 399
		DEFAULT => -14
	},
	{#State 400
		DEFAULT => -13
	},
	{#State 401
		ACTIONS => {
			'AMP_OPR' => 285
		},
		DEFAULT => -49
	},
	{#State 402
		ACTIONS => {
			'OR_OPR' => 309
		},
		DEFAULT => -53
	},
	{#State 403
		ACTIONS => {
			'LP_TOKEN' => 447
		}
	},
	{#State 404
		ACTIONS => {
			'SIZEOF_TOKEN' => 207,
			'AMP_OPR' => 110,
			'IDENTIFIER_ORG' => 39,
			'INTEGER_LITERAL' => 191,
			'MINUS_OPR' => 134,
			'SMC_TOKEN' => 448,
			'SQL_TOKEN' => 45,
			'SECTION_TOKEN' => 40,
			'DECLARE_TOKEN' => 46,
			'FLOAT_LITERAL' => 200,
			'ORACLE_TOKEN' => 41,
			'EXEC_TOKEN' => 47,
			'POSTFIX_OPR' => 194,
			'LP_TOKEN' => 195,
			'PLUS_OPR' => 100,
			'CHAR_LITERAL' => 204,
			'ASTARI_OPR' => 127,
			'END_TOKEN' => 48,
			'BEGIN_TOKEN' => 43,
			'PREFIX_OPR' => 106,
			'STRING_LITERAL' => 198,
			'TOOLS_TOKEN' => 49
		},
		GOTOS => {
			'logical_OR_expression' => 208,
			'conditional_expression' => 199,
			'primary_expression' => 209,
			'expression' => 449,
			'unary_operator' => 187,
			'unary_expression' => 193,
			'equality_expression' => 201,
			'IDENTIFIER' => 202,
			'shift_expression' => 203,
			'additive_expression' => 196,
			'postfix_expression' => 210,
			'exclusive_OR_expression' => 211,
			'inclusive_OR_expression' => 205,
			'relational_expression' => 197,
			'string_literal_list' => 212,
			'AND_expression' => 188,
			'multiplicative_expression' => 206,
			'logical_AND_expression' => 213,
			'assignment_expression' => 221,
			'cast_expression' => 214
		}
	},
	{#State 405
		ACTIONS => {
			'SIZEOF_TOKEN' => 207,
			'AMP_OPR' => 110,
			'IDENTIFIER_ORG' => 39,
			'INTEGER_LITERAL' => 191,
			'MINUS_OPR' => 134,
			'SMC_TOKEN' => 450,
			'SQL_TOKEN' => 45,
			'SECTION_TOKEN' => 40,
			'DECLARE_TOKEN' => 46,
			'FLOAT_LITERAL' => 200,
			'ORACLE_TOKEN' => 41,
			'EXEC_TOKEN' => 47,
			'POSTFIX_OPR' => 194,
			'LP_TOKEN' => 195,
			'PLUS_OPR' => 100,
			'CHAR_LITERAL' => 204,
			'ASTARI_OPR' => 127,
			'END_TOKEN' => 48,
			'BEGIN_TOKEN' => 43,
			'PREFIX_OPR' => 106,
			'STRING_LITERAL' => 198,
			'TOOLS_TOKEN' => 49
		},
		GOTOS => {
			'logical_OR_expression' => 208,
			'conditional_expression' => 199,
			'primary_expression' => 209,
			'expression' => 451,
			'unary_operator' => 187,
			'unary_expression' => 193,
			'equality_expression' => 201,
			'IDENTIFIER' => 202,
			'shift_expression' => 203,
			'additive_expression' => 196,
			'postfix_expression' => 210,
			'exclusive_OR_expression' => 211,
			'inclusive_OR_expression' => 205,
			'relational_expression' => 197,
			'string_literal_list' => 212,
			'AND_expression' => 188,
			'multiplicative_expression' => 206,
			'logical_AND_expression' => 213,
			'assignment_expression' => 221,
			'cast_expression' => 214
		}
	},
	{#State 406
		ACTIONS => {
			'CM_TOKEN' => 331,
			'SMC_TOKEN' => 452
		}
	},
	{#State 407
		ACTIONS => {
			'CM_TOKEN' => 331,
			'RP_TOKEN' => 453
		}
	},
	{#State 408
		DEFAULT => -227
	},
	{#State 409
		DEFAULT => -198
	},
	{#State 410
		ACTIONS => {
			'CM_TOKEN' => 331,
			'RP_TOKEN' => 454
		}
	},
	{#State 411
		DEFAULT => -64
	},
	{#State 412
		ACTIONS => {
			'DEFAULT_TOKEN' => 227,
			'IDENTIFIER_ORG' => 39,
			'MINUS_OPR' => 134,
			'SMC_TOKEN' => 229,
			'SECTION_TOKEN' => 40,
			'DO_TOKEN' => 216,
			'WHILE_TOKEN' => 231,
			'CASE_TOKEN' => 233,
			'FLOAT_LITERAL' => 200,
			'ORACLE_TOKEN' => 41,
			'PLUS_OPR' => 100,
			'FOR_TOKEN' => 218,
			'CHAR_LITERAL' => 204,
			'SWITCH_TOKEN' => 220,
			'BEGIN_TOKEN' => 43,
			'PREFIX_OPR' => 106,
			'SIZEOF_TOKEN' => 207,
			'AMP_OPR' => 110,
			'RETURN_TOKEN' => 223,
			'INTEGER_LITERAL' => 191,
			'LCB_TOKEN' => 80,
			'SQL_TOKEN' => 45,
			'DECLARE_TOKEN' => 46,
			'CONTINUE_TOKEN' => 238,
			'GOTO_TOKEN' => 239,
			'EXEC_TOKEN' => 225,
			'POSTFIX_OPR' => 194,
			'LP_TOKEN' => 195,
			'BREAK_TOKEN' => 240,
			'IF_TOKEN' => 241,
			'ASTARI_OPR' => 127,
			'END_TOKEN' => 48,
			'STRING_LITERAL' => 198,
			'TOOLS_TOKEN' => 49
		},
		GOTOS => {
			'jump_statement' => 237,
			'iteration_statement' => 215,
			'logical_OR_expression' => 208,
			'expression_statement' => 228,
			'conditional_expression' => 199,
			'primary_expression' => 209,
			'embedded_sql' => 230,
			'statement' => 455,
			'expression' => 232,
			'unary_operator' => 187,
			'unary_expression' => 193,
			'equality_expression' => 201,
			'IDENTIFIER' => 236,
			'compound_statement' => 226,
			'labeled_statement' => 242,
			'shift_expression' => 203,
			'postfix_expression' => 210,
			'additive_expression' => 196,
			'exclusive_OR_expression' => 211,
			'inclusive_OR_expression' => 205,
			'relational_expression' => 197,
			'string_literal_list' => 212,
			'multiplicative_expression' => 206,
			'AND_expression' => 188,
			'logical_AND_expression' => 213,
			'assignment_expression' => 221,
			'cast_expression' => 214,
			'selection_statement' => 222
		}
	},
	{#State 413
		DEFAULT => -196
	},
	{#State 414
		DEFAULT => -224
	},
	{#State 415
		ACTIONS => {
			'CM_TOKEN' => 331,
			'RP_TOKEN' => 456
		}
	},
	{#State 416
		DEFAULT => -134
	},
	{#State 417
		DEFAULT => -141
	},
	{#State 418
		ACTIONS => {
			'RSB_TOKEN' => 457
		}
	},
	{#State 419
		DEFAULT => -139
	},
	{#State 420
		ACTIONS => {
			'RSB_TOKEN' => 458
		}
	},
	{#State 421
		DEFAULT => -173
	},
	{#State 422
		ACTIONS => {
			'RP_TOKEN' => 459
		}
	},
	{#State 423
		ACTIONS => {
			'RP_TOKEN' => 460
		}
	},
	{#State 424
		ACTIONS => {
			'RSB_TOKEN' => 461
		}
	},
	{#State 425
		ACTIONS => {
			'RSB_TOKEN' => 462
		},
		DEFAULT => -26
	},
	{#State 426
		DEFAULT => -167
	},
	{#State 427
		ACTIONS => {
			'VOLATILE_TOKEN' => 21,
			'EXTERN_TOKEN' => 3,
			'SHORT_TOKEN' => 2,
			'ENUM_TOKEN' => 1,
			'RP_TOKEN' => 463,
			'LONG_TOKEN' => 5,
			'VOID_TOKEN' => 22,
			'DOUBLE_TOKEN' => 24,
			'INT_TOKEN' => 26,
			'_BOOL_TOKEN' => 27,
			'INLINE_TOKEN' => 8,
			'TYPEDEF_TOKEN' => 29,
			'_COMPLEX_TOKEN' => 32,
			'CHAR_TOKEN' => 13,
			'SIGNED_TOKEN' => 12,
			'CONST_TOKEN' => 14,
			'REGISTER_TOKEN' => 34,
			'RESTRICT_TOKEN' => 35,
			'UNION_TOKEN' => 36,
			'STRUCT_TOKEN' => 15,
			'STATIC_TOKEN' => 37,
			'TNAME_TOKEN' => 16,
			'UNSIGNED_TOKEN' => 17,
			'FLOAT_TOKEN' => 18,
			'AUTO_TOKEN' => 19
		},
		GOTOS => {
			'parameter_type_list' => 464,
			'struct_or_union' => 33,
			'function_specifier' => 4,
			'parameter_declaration' => 251,
			'declaration_specifiers' => 252,
			'struct_or_union_specifier' => 28,
			'type_specifier' => 38,
			'type_qualifier' => 9,
			'storage_class_specifier' => 10,
			'enum_specifier' => 30,
			'parameter_list' => 256
		}
	},
	{#State 428
		ACTIONS => {
			'SIZEOF_TOKEN' => 207,
			'AMP_OPR' => 110,
			'IDENTIFIER_ORG' => 39,
			'INTEGER_LITERAL' => 191,
			'MINUS_OPR' => 134,
			'SQL_TOKEN' => 45,
			'SECTION_TOKEN' => 40,
			'DECLARE_TOKEN' => 46,
			'RSB_TOKEN' => 467,
			'FLOAT_LITERAL' => 200,
			'ORACLE_TOKEN' => 41,
			'EXEC_TOKEN' => 47,
			'POSTFIX_OPR' => 194,
			'LP_TOKEN' => 195,
			'PLUS_OPR' => 100,
			'CHAR_LITERAL' => 204,
			'ASTARI_OPR' => 466,
			'END_TOKEN' => 48,
			'BEGIN_TOKEN' => 43,
			'PREFIX_OPR' => 106,
			'STRING_LITERAL' => 198,
			'TOOLS_TOKEN' => 49
		},
		GOTOS => {
			'logical_OR_expression' => 208,
			'conditional_expression' => 199,
			'primary_expression' => 209,
			'unary_operator' => 187,
			'unary_expression' => 193,
			'equality_expression' => 201,
			'IDENTIFIER' => 202,
			'shift_expression' => 203,
			'additive_expression' => 196,
			'postfix_expression' => 210,
			'exclusive_OR_expression' => 211,
			'inclusive_OR_expression' => 205,
			'relational_expression' => 197,
			'AND_expression' => 188,
			'multiplicative_expression' => 206,
			'string_literal_list' => 212,
			'logical_AND_expression' => 213,
			'assignment_expression' => 465,
			'cast_expression' => 214
		}
	},
	{#State 429
		ACTIONS => {
			'LSB_TOKEN' => 428,
			'LP_TOKEN' => 427
		},
		DEFAULT => -164
	},
	{#State 430
		DEFAULT => -160
	},
	{#State 431
		DEFAULT => -155
	},
	{#State 432
		DEFAULT => -153
	},
	{#State 433
		DEFAULT => -114
	},
	{#State 434
		DEFAULT => -112
	},
	{#State 435
		DEFAULT => -187
	},
	{#State 436
		DEFAULT => -179
	},
	{#State 437
		DEFAULT => -183
	},
	{#State 438
		ACTIONS => {
			'SIZEOF_TOKEN' => 207,
			'AMP_OPR' => 110,
			'IDENTIFIER_ORG' => 39,
			'INTEGER_LITERAL' => 191,
			'MINUS_OPR' => 134,
			'LCB_TOKEN' => 192,
			'SQL_TOKEN' => 45,
			'SECTION_TOKEN' => 40,
			'DECLARE_TOKEN' => 46,
			'FLOAT_LITERAL' => 200,
			'ORACLE_TOKEN' => 41,
			'EXEC_TOKEN' => 47,
			'POSTFIX_OPR' => 194,
			'LP_TOKEN' => 195,
			'PLUS_OPR' => 100,
			'CHAR_LITERAL' => 204,
			'ASTARI_OPR' => 127,
			'END_TOKEN' => 48,
			'BEGIN_TOKEN' => 43,
			'PREFIX_OPR' => 106,
			'STRING_LITERAL' => 198,
			'TOOLS_TOKEN' => 49
		},
		GOTOS => {
			'logical_OR_expression' => 208,
			'conditional_expression' => 199,
			'primary_expression' => 209,
			'unary_operator' => 187,
			'unary_expression' => 193,
			'equality_expression' => 201,
			'IDENTIFIER' => 202,
			'shift_expression' => 203,
			'additive_expression' => 196,
			'postfix_expression' => 210,
			'exclusive_OR_expression' => 211,
			'inclusive_OR_expression' => 205,
			'relational_expression' => 197,
			'string_literal_list' => 212,
			'AND_expression' => 188,
			'multiplicative_expression' => 206,
			'logical_AND_expression' => 213,
			'assignment_expression' => 189,
			'cast_expression' => 214,
			'initializer' => 468
		}
	},
	{#State 439
		ACTIONS => {
			'LCB_TOKEN' => 440
		}
	},
	{#State 440
		ACTIONS => {
			'SIZEOF_TOKEN' => 207,
			'AMP_OPR' => 110,
			'IDENTIFIER_ORG' => 39,
			'INTEGER_LITERAL' => 191,
			'MINUS_OPR' => 134,
			'LCB_TOKEN' => 192,
			'SQL_TOKEN' => 45,
			'LSB_TOKEN' => 287,
			'SECTION_TOKEN' => 40,
			'DECLARE_TOKEN' => 46,
			'FLOAT_LITERAL' => 200,
			'ORACLE_TOKEN' => 41,
			'EXEC_TOKEN' => 47,
			'POSTFIX_OPR' => 194,
			'LP_TOKEN' => 195,
			'DOT_TOKEN' => 289,
			'PLUS_OPR' => 100,
			'CHAR_LITERAL' => 204,
			'ASTARI_OPR' => 127,
			'END_TOKEN' => 48,
			'BEGIN_TOKEN' => 43,
			'PREFIX_OPR' => 106,
			'STRING_LITERAL' => 198,
			'TOOLS_TOKEN' => 49
		},
		GOTOS => {
			'initializer_list' => 469,
			'logical_OR_expression' => 208,
			'conditional_expression' => 199,
			'primary_expression' => 209,
			'designation' => 288,
			'unary_operator' => 187,
			'unary_expression' => 193,
			'equality_expression' => 201,
			'IDENTIFIER' => 202,
			'designator_list' => 290,
			'shift_expression' => 203,
			'postfix_expression' => 210,
			'additive_expression' => 196,
			'exclusive_OR_expression' => 211,
			'designator' => 291,
			'inclusive_OR_expression' => 205,
			'relational_expression' => 197,
			'string_literal_list' => 212,
			'AND_expression' => 188,
			'multiplicative_expression' => 206,
			'logical_AND_expression' => 213,
			'assignment_expression' => 189,
			'cast_expression' => 214,
			'initializer' => 286
		}
	},
	{#State 441
		DEFAULT => -31
	},
	{#State 442
		ACTIONS => {
			'LCB_TOKEN' => 440
		},
		DEFAULT => -24
	},
	{#State 443
		ACTIONS => {
			'SIZEOF_TOKEN' => 207,
			'AMP_OPR' => 110,
			'IDENTIFIER_ORG' => 39,
			'INTEGER_LITERAL' => 191,
			'MINUS_OPR' => 134,
			'SQL_TOKEN' => 45,
			'SECTION_TOKEN' => 40,
			'DECLARE_TOKEN' => 46,
			'FLOAT_LITERAL' => 200,
			'ORACLE_TOKEN' => 41,
			'EXEC_TOKEN' => 47,
			'POSTFIX_OPR' => 194,
			'LP_TOKEN' => 195,
			'PLUS_OPR' => 100,
			'CHAR_LITERAL' => 204,
			'ASTARI_OPR' => 127,
			'END_TOKEN' => 48,
			'BEGIN_TOKEN' => 43,
			'PREFIX_OPR' => 106,
			'STRING_LITERAL' => 198,
			'TOOLS_TOKEN' => 49
		},
		GOTOS => {
			'logical_OR_expression' => 208,
			'conditional_expression' => 470,
			'primary_expression' => 209,
			'unary_operator' => 187,
			'unary_expression' => 281,
			'equality_expression' => 201,
			'IDENTIFIER' => 202,
			'shift_expression' => 203,
			'additive_expression' => 196,
			'postfix_expression' => 210,
			'exclusive_OR_expression' => 211,
			'inclusive_OR_expression' => 205,
			'relational_expression' => 197,
			'AND_expression' => 188,
			'multiplicative_expression' => 206,
			'string_literal_list' => 212,
			'logical_AND_expression' => 213,
			'cast_expression' => 214
		}
	},
	{#State 444
		ACTIONS => {
			'SIZEOF_TOKEN' => 207,
			'AMP_OPR' => 110,
			'IDENTIFIER_ORG' => 39,
			'INTEGER_LITERAL' => 191,
			'MINUS_OPR' => 134,
			'SQL_TOKEN' => 45,
			'SECTION_TOKEN' => 40,
			'DECLARE_TOKEN' => 46,
			'FLOAT_LITERAL' => 200,
			'ORACLE_TOKEN' => 41,
			'EXEC_TOKEN' => 47,
			'POSTFIX_OPR' => 194,
			'LP_TOKEN' => 195,
			'PLUS_OPR' => 100,
			'CHAR_LITERAL' => 204,
			'ASTARI_OPR' => 127,
			'END_TOKEN' => 48,
			'BEGIN_TOKEN' => 43,
			'PREFIX_OPR' => 106,
			'STRING_LITERAL' => 198,
			'TOOLS_TOKEN' => 49
		},
		GOTOS => {
			'logical_OR_expression' => 208,
			'conditional_expression' => 199,
			'primary_expression' => 209,
			'unary_operator' => 187,
			'unary_expression' => 193,
			'equality_expression' => 201,
			'IDENTIFIER' => 202,
			'shift_expression' => 203,
			'additive_expression' => 196,
			'postfix_expression' => 210,
			'exclusive_OR_expression' => 211,
			'inclusive_OR_expression' => 205,
			'relational_expression' => 197,
			'AND_expression' => 188,
			'multiplicative_expression' => 206,
			'string_literal_list' => 212,
			'logical_AND_expression' => 213,
			'assignment_expression' => 471,
			'cast_expression' => 214
		}
	},
	{#State 445
		DEFAULT => -11
	},
	{#State 446
		DEFAULT => -10
	},
	{#State 447
		ACTIONS => {
			'SIZEOF_TOKEN' => 207,
			'AMP_OPR' => 110,
			'IDENTIFIER_ORG' => 39,
			'INTEGER_LITERAL' => 191,
			'MINUS_OPR' => 134,
			'SQL_TOKEN' => 45,
			'SECTION_TOKEN' => 40,
			'DECLARE_TOKEN' => 46,
			'FLOAT_LITERAL' => 200,
			'ORACLE_TOKEN' => 41,
			'EXEC_TOKEN' => 47,
			'POSTFIX_OPR' => 194,
			'LP_TOKEN' => 195,
			'PLUS_OPR' => 100,
			'CHAR_LITERAL' => 204,
			'ASTARI_OPR' => 127,
			'END_TOKEN' => 48,
			'BEGIN_TOKEN' => 43,
			'PREFIX_OPR' => 106,
			'STRING_LITERAL' => 198,
			'TOOLS_TOKEN' => 49
		},
		GOTOS => {
			'logical_OR_expression' => 208,
			'conditional_expression' => 199,
			'primary_expression' => 209,
			'expression' => 472,
			'unary_operator' => 187,
			'unary_expression' => 193,
			'equality_expression' => 201,
			'IDENTIFIER' => 202,
			'shift_expression' => 203,
			'additive_expression' => 196,
			'postfix_expression' => 210,
			'exclusive_OR_expression' => 211,
			'inclusive_OR_expression' => 205,
			'relational_expression' => 197,
			'string_literal_list' => 212,
			'AND_expression' => 188,
			'multiplicative_expression' => 206,
			'logical_AND_expression' => 213,
			'assignment_expression' => 221,
			'cast_expression' => 214
		}
	},
	{#State 448
		ACTIONS => {
			'SIZEOF_TOKEN' => 207,
			'AMP_OPR' => 110,
			'IDENTIFIER_ORG' => 39,
			'RP_TOKEN' => 473,
			'INTEGER_LITERAL' => 191,
			'MINUS_OPR' => 134,
			'SQL_TOKEN' => 45,
			'SECTION_TOKEN' => 40,
			'DECLARE_TOKEN' => 46,
			'FLOAT_LITERAL' => 200,
			'ORACLE_TOKEN' => 41,
			'EXEC_TOKEN' => 47,
			'POSTFIX_OPR' => 194,
			'LP_TOKEN' => 195,
			'PLUS_OPR' => 100,
			'CHAR_LITERAL' => 204,
			'ASTARI_OPR' => 127,
			'END_TOKEN' => 48,
			'BEGIN_TOKEN' => 43,
			'PREFIX_OPR' => 106,
			'STRING_LITERAL' => 198,
			'TOOLS_TOKEN' => 49
		},
		GOTOS => {
			'logical_OR_expression' => 208,
			'conditional_expression' => 199,
			'primary_expression' => 209,
			'expression' => 474,
			'unary_operator' => 187,
			'unary_expression' => 193,
			'equality_expression' => 201,
			'IDENTIFIER' => 202,
			'shift_expression' => 203,
			'additive_expression' => 196,
			'postfix_expression' => 210,
			'exclusive_OR_expression' => 211,
			'inclusive_OR_expression' => 205,
			'relational_expression' => 197,
			'string_literal_list' => 212,
			'AND_expression' => 188,
			'multiplicative_expression' => 206,
			'logical_AND_expression' => 213,
			'assignment_expression' => 221,
			'cast_expression' => 214
		}
	},
	{#State 449
		ACTIONS => {
			'CM_TOKEN' => 331,
			'SMC_TOKEN' => 475
		}
	},
	{#State 450
		ACTIONS => {
			'SIZEOF_TOKEN' => 207,
			'AMP_OPR' => 110,
			'IDENTIFIER_ORG' => 39,
			'RP_TOKEN' => 476,
			'INTEGER_LITERAL' => 191,
			'MINUS_OPR' => 134,
			'SQL_TOKEN' => 45,
			'SECTION_TOKEN' => 40,
			'DECLARE_TOKEN' => 46,
			'FLOAT_LITERAL' => 200,
			'ORACLE_TOKEN' => 41,
			'EXEC_TOKEN' => 47,
			'POSTFIX_OPR' => 194,
			'LP_TOKEN' => 195,
			'PLUS_OPR' => 100,
			'CHAR_LITERAL' => 204,
			'ASTARI_OPR' => 127,
			'END_TOKEN' => 48,
			'BEGIN_TOKEN' => 43,
			'PREFIX_OPR' => 106,
			'STRING_LITERAL' => 198,
			'TOOLS_TOKEN' => 49
		},
		GOTOS => {
			'logical_OR_expression' => 208,
			'conditional_expression' => 199,
			'primary_expression' => 209,
			'expression' => 477,
			'unary_operator' => 187,
			'unary_expression' => 193,
			'equality_expression' => 201,
			'IDENTIFIER' => 202,
			'shift_expression' => 203,
			'additive_expression' => 196,
			'postfix_expression' => 210,
			'exclusive_OR_expression' => 211,
			'inclusive_OR_expression' => 205,
			'relational_expression' => 197,
			'string_literal_list' => 212,
			'AND_expression' => 188,
			'multiplicative_expression' => 206,
			'logical_AND_expression' => 213,
			'assignment_expression' => 221,
			'cast_expression' => 214
		}
	},
	{#State 451
		ACTIONS => {
			'CM_TOKEN' => 331,
			'SMC_TOKEN' => 478
		}
	},
	{#State 452
		ACTIONS => {
			'SIZEOF_TOKEN' => 207,
			'AMP_OPR' => 110,
			'IDENTIFIER_ORG' => 39,
			'INTEGER_LITERAL' => 191,
			'MINUS_OPR' => 134,
			'SMC_TOKEN' => 479,
			'SQL_TOKEN' => 45,
			'SECTION_TOKEN' => 40,
			'DECLARE_TOKEN' => 46,
			'FLOAT_LITERAL' => 200,
			'ORACLE_TOKEN' => 41,
			'EXEC_TOKEN' => 47,
			'POSTFIX_OPR' => 194,
			'LP_TOKEN' => 195,
			'PLUS_OPR' => 100,
			'CHAR_LITERAL' => 204,
			'ASTARI_OPR' => 127,
			'END_TOKEN' => 48,
			'BEGIN_TOKEN' => 43,
			'PREFIX_OPR' => 106,
			'STRING_LITERAL' => 198,
			'TOOLS_TOKEN' => 49
		},
		GOTOS => {
			'logical_OR_expression' => 208,
			'conditional_expression' => 199,
			'primary_expression' => 209,
			'expression' => 480,
			'unary_operator' => 187,
			'unary_expression' => 193,
			'equality_expression' => 201,
			'IDENTIFIER' => 202,
			'shift_expression' => 203,
			'additive_expression' => 196,
			'postfix_expression' => 210,
			'exclusive_OR_expression' => 211,
			'inclusive_OR_expression' => 205,
			'relational_expression' => 197,
			'string_literal_list' => 212,
			'AND_expression' => 188,
			'multiplicative_expression' => 206,
			'logical_AND_expression' => 213,
			'assignment_expression' => 221,
			'cast_expression' => 214
		}
	},
	{#State 453
		ACTIONS => {
			'DEFAULT_TOKEN' => 227,
			'IDENTIFIER_ORG' => 39,
			'MINUS_OPR' => 134,
			'SMC_TOKEN' => 229,
			'SECTION_TOKEN' => 40,
			'DO_TOKEN' => 216,
			'WHILE_TOKEN' => 231,
			'CASE_TOKEN' => 233,
			'FLOAT_LITERAL' => 200,
			'ORACLE_TOKEN' => 41,
			'PLUS_OPR' => 100,
			'FOR_TOKEN' => 218,
			'CHAR_LITERAL' => 204,
			'SWITCH_TOKEN' => 220,
			'BEGIN_TOKEN' => 43,
			'PREFIX_OPR' => 106,
			'SIZEOF_TOKEN' => 207,
			'AMP_OPR' => 110,
			'RETURN_TOKEN' => 223,
			'INTEGER_LITERAL' => 191,
			'LCB_TOKEN' => 80,
			'SQL_TOKEN' => 45,
			'DECLARE_TOKEN' => 46,
			'CONTINUE_TOKEN' => 238,
			'GOTO_TOKEN' => 239,
			'EXEC_TOKEN' => 225,
			'POSTFIX_OPR' => 194,
			'LP_TOKEN' => 195,
			'BREAK_TOKEN' => 240,
			'IF_TOKEN' => 241,
			'ASTARI_OPR' => 127,
			'END_TOKEN' => 48,
			'STRING_LITERAL' => 198,
			'TOOLS_TOKEN' => 49
		},
		GOTOS => {
			'jump_statement' => 237,
			'iteration_statement' => 215,
			'logical_OR_expression' => 208,
			'expression_statement' => 228,
			'conditional_expression' => 199,
			'primary_expression' => 209,
			'embedded_sql' => 230,
			'statement' => 481,
			'expression' => 232,
			'unary_operator' => 187,
			'unary_expression' => 193,
			'equality_expression' => 201,
			'IDENTIFIER' => 236,
			'compound_statement' => 226,
			'labeled_statement' => 242,
			'shift_expression' => 203,
			'postfix_expression' => 210,
			'additive_expression' => 196,
			'exclusive_OR_expression' => 211,
			'inclusive_OR_expression' => 205,
			'relational_expression' => 197,
			'string_literal_list' => 212,
			'multiplicative_expression' => 206,
			'AND_expression' => 188,
			'logical_AND_expression' => 213,
			'assignment_expression' => 221,
			'cast_expression' => 214,
			'selection_statement' => 222
		}
	},
	{#State 454
		ACTIONS => {
			'DEFAULT_TOKEN' => 227,
			'IDENTIFIER_ORG' => 39,
			'MINUS_OPR' => 134,
			'SMC_TOKEN' => 229,
			'SECTION_TOKEN' => 40,
			'DO_TOKEN' => 216,
			'WHILE_TOKEN' => 231,
			'CASE_TOKEN' => 233,
			'FLOAT_LITERAL' => 200,
			'ORACLE_TOKEN' => 41,
			'PLUS_OPR' => 100,
			'FOR_TOKEN' => 218,
			'CHAR_LITERAL' => 204,
			'SWITCH_TOKEN' => 220,
			'BEGIN_TOKEN' => 43,
			'PREFIX_OPR' => 106,
			'SIZEOF_TOKEN' => 207,
			'AMP_OPR' => 110,
			'RETURN_TOKEN' => 223,
			'INTEGER_LITERAL' => 191,
			'LCB_TOKEN' => 80,
			'SQL_TOKEN' => 45,
			'DECLARE_TOKEN' => 46,
			'CONTINUE_TOKEN' => 238,
			'GOTO_TOKEN' => 239,
			'EXEC_TOKEN' => 225,
			'POSTFIX_OPR' => 194,
			'LP_TOKEN' => 195,
			'BREAK_TOKEN' => 240,
			'IF_TOKEN' => 241,
			'ASTARI_OPR' => 127,
			'END_TOKEN' => 48,
			'STRING_LITERAL' => 198,
			'TOOLS_TOKEN' => 49
		},
		GOTOS => {
			'jump_statement' => 237,
			'iteration_statement' => 215,
			'logical_OR_expression' => 208,
			'expression_statement' => 228,
			'conditional_expression' => 199,
			'primary_expression' => 209,
			'embedded_sql' => 230,
			'statement' => 482,
			'expression' => 232,
			'unary_operator' => 187,
			'unary_expression' => 193,
			'equality_expression' => 201,
			'IDENTIFIER' => 236,
			'compound_statement' => 226,
			'labeled_statement' => 242,
			'shift_expression' => 203,
			'postfix_expression' => 210,
			'additive_expression' => 196,
			'exclusive_OR_expression' => 211,
			'inclusive_OR_expression' => 205,
			'relational_expression' => 197,
			'string_literal_list' => 212,
			'multiplicative_expression' => 206,
			'AND_expression' => 188,
			'logical_AND_expression' => 213,
			'assignment_expression' => 221,
			'cast_expression' => 214,
			'selection_statement' => 222
		}
	},
	{#State 455
		DEFAULT => -197
	},
	{#State 456
		ACTIONS => {
			'DEFAULT_TOKEN' => 227,
			'IDENTIFIER_ORG' => 39,
			'MINUS_OPR' => 134,
			'SMC_TOKEN' => 229,
			'SECTION_TOKEN' => 40,
			'DO_TOKEN' => 216,
			'WHILE_TOKEN' => 231,
			'CASE_TOKEN' => 233,
			'FLOAT_LITERAL' => 200,
			'ORACLE_TOKEN' => 41,
			'PLUS_OPR' => 100,
			'FOR_TOKEN' => 218,
			'CHAR_LITERAL' => 204,
			'SWITCH_TOKEN' => 220,
			'BEGIN_TOKEN' => 43,
			'PREFIX_OPR' => 106,
			'SIZEOF_TOKEN' => 207,
			'AMP_OPR' => 110,
			'RETURN_TOKEN' => 223,
			'INTEGER_LITERAL' => 191,
			'LCB_TOKEN' => 80,
			'SQL_TOKEN' => 45,
			'DECLARE_TOKEN' => 46,
			'CONTINUE_TOKEN' => 238,
			'GOTO_TOKEN' => 239,
			'EXEC_TOKEN' => 225,
			'POSTFIX_OPR' => 194,
			'LP_TOKEN' => 195,
			'BREAK_TOKEN' => 240,
			'IF_TOKEN' => 241,
			'ASTARI_OPR' => 127,
			'END_TOKEN' => 48,
			'STRING_LITERAL' => 198,
			'TOOLS_TOKEN' => 49
		},
		GOTOS => {
			'jump_statement' => 237,
			'iteration_statement' => 215,
			'logical_OR_expression' => 208,
			'expression_statement' => 228,
			'conditional_expression' => 199,
			'primary_expression' => 209,
			'embedded_sql' => 230,
			'statement' => 483,
			'expression' => 232,
			'unary_operator' => 187,
			'unary_expression' => 193,
			'equality_expression' => 201,
			'IDENTIFIER' => 236,
			'compound_statement' => 226,
			'labeled_statement' => 242,
			'shift_expression' => 203,
			'postfix_expression' => 210,
			'additive_expression' => 196,
			'exclusive_OR_expression' => 211,
			'inclusive_OR_expression' => 205,
			'relational_expression' => 197,
			'string_literal_list' => 212,
			'multiplicative_expression' => 206,
			'AND_expression' => 188,
			'logical_AND_expression' => 213,
			'assignment_expression' => 221,
			'cast_expression' => 214,
			'selection_statement' => 222
		}
	},
	{#State 457
		DEFAULT => -140
	},
	{#State 458
		DEFAULT => -138
	},
	{#State 459
		DEFAULT => -166
	},
	{#State 460
		DEFAULT => -174
	},
	{#State 461
		DEFAULT => -169
	},
	{#State 462
		DEFAULT => -172
	},
	{#State 463
		DEFAULT => -175
	},
	{#State 464
		ACTIONS => {
			'RP_TOKEN' => 484
		}
	},
	{#State 465
		ACTIONS => {
			'RSB_TOKEN' => 485
		}
	},
	{#State 466
		ACTIONS => {
			'RSB_TOKEN' => 486
		},
		DEFAULT => -26
	},
	{#State 467
		DEFAULT => -168
	},
	{#State 468
		DEFAULT => -182
	},
	{#State 469
		ACTIONS => {
			'CM_TOKEN' => 487,
			'RCB_TOKEN' => 488
		}
	},
	{#State 470
		DEFAULT => -57
	},
	{#State 471
		DEFAULT => -19
	},
	{#State 472
		ACTIONS => {
			'CM_TOKEN' => 331,
			'RP_TOKEN' => 489
		}
	},
	{#State 473
		ACTIONS => {
			'DEFAULT_TOKEN' => 227,
			'IDENTIFIER_ORG' => 39,
			'MINUS_OPR' => 134,
			'SMC_TOKEN' => 229,
			'SECTION_TOKEN' => 40,
			'DO_TOKEN' => 216,
			'WHILE_TOKEN' => 231,
			'CASE_TOKEN' => 233,
			'FLOAT_LITERAL' => 200,
			'ORACLE_TOKEN' => 41,
			'PLUS_OPR' => 100,
			'FOR_TOKEN' => 218,
			'CHAR_LITERAL' => 204,
			'SWITCH_TOKEN' => 220,
			'BEGIN_TOKEN' => 43,
			'PREFIX_OPR' => 106,
			'SIZEOF_TOKEN' => 207,
			'AMP_OPR' => 110,
			'RETURN_TOKEN' => 223,
			'INTEGER_LITERAL' => 191,
			'LCB_TOKEN' => 80,
			'SQL_TOKEN' => 45,
			'DECLARE_TOKEN' => 46,
			'CONTINUE_TOKEN' => 238,
			'GOTO_TOKEN' => 239,
			'EXEC_TOKEN' => 225,
			'POSTFIX_OPR' => 194,
			'LP_TOKEN' => 195,
			'BREAK_TOKEN' => 240,
			'IF_TOKEN' => 241,
			'ASTARI_OPR' => 127,
			'END_TOKEN' => 48,
			'STRING_LITERAL' => 198,
			'TOOLS_TOKEN' => 49
		},
		GOTOS => {
			'jump_statement' => 237,
			'iteration_statement' => 215,
			'logical_OR_expression' => 208,
			'expression_statement' => 228,
			'conditional_expression' => 199,
			'primary_expression' => 209,
			'embedded_sql' => 230,
			'statement' => 490,
			'expression' => 232,
			'unary_operator' => 187,
			'unary_expression' => 193,
			'equality_expression' => 201,
			'IDENTIFIER' => 236,
			'compound_statement' => 226,
			'labeled_statement' => 242,
			'shift_expression' => 203,
			'postfix_expression' => 210,
			'additive_expression' => 196,
			'exclusive_OR_expression' => 211,
			'inclusive_OR_expression' => 205,
			'relational_expression' => 197,
			'string_literal_list' => 212,
			'multiplicative_expression' => 206,
			'AND_expression' => 188,
			'logical_AND_expression' => 213,
			'assignment_expression' => 221,
			'cast_expression' => 214,
			'selection_statement' => 222
		}
	},
	{#State 474
		ACTIONS => {
			'CM_TOKEN' => 331,
			'RP_TOKEN' => 491
		}
	},
	{#State 475
		ACTIONS => {
			'SIZEOF_TOKEN' => 207,
			'AMP_OPR' => 110,
			'IDENTIFIER_ORG' => 39,
			'RP_TOKEN' => 492,
			'INTEGER_LITERAL' => 191,
			'MINUS_OPR' => 134,
			'SQL_TOKEN' => 45,
			'SECTION_TOKEN' => 40,
			'DECLARE_TOKEN' => 46,
			'FLOAT_LITERAL' => 200,
			'ORACLE_TOKEN' => 41,
			'EXEC_TOKEN' => 47,
			'POSTFIX_OPR' => 194,
			'LP_TOKEN' => 195,
			'PLUS_OPR' => 100,
			'CHAR_LITERAL' => 204,
			'ASTARI_OPR' => 127,
			'END_TOKEN' => 48,
			'BEGIN_TOKEN' => 43,
			'PREFIX_OPR' => 106,
			'STRING_LITERAL' => 198,
			'TOOLS_TOKEN' => 49
		},
		GOTOS => {
			'logical_OR_expression' => 208,
			'conditional_expression' => 199,
			'primary_expression' => 209,
			'expression' => 493,
			'unary_operator' => 187,
			'unary_expression' => 193,
			'equality_expression' => 201,
			'IDENTIFIER' => 202,
			'shift_expression' => 203,
			'additive_expression' => 196,
			'postfix_expression' => 210,
			'exclusive_OR_expression' => 211,
			'inclusive_OR_expression' => 205,
			'relational_expression' => 197,
			'string_literal_list' => 212,
			'AND_expression' => 188,
			'multiplicative_expression' => 206,
			'logical_AND_expression' => 213,
			'assignment_expression' => 221,
			'cast_expression' => 214
		}
	},
	{#State 476
		ACTIONS => {
			'DEFAULT_TOKEN' => 227,
			'IDENTIFIER_ORG' => 39,
			'MINUS_OPR' => 134,
			'SMC_TOKEN' => 229,
			'SECTION_TOKEN' => 40,
			'DO_TOKEN' => 216,
			'WHILE_TOKEN' => 231,
			'CASE_TOKEN' => 233,
			'FLOAT_LITERAL' => 200,
			'ORACLE_TOKEN' => 41,
			'PLUS_OPR' => 100,
			'FOR_TOKEN' => 218,
			'CHAR_LITERAL' => 204,
			'SWITCH_TOKEN' => 220,
			'BEGIN_TOKEN' => 43,
			'PREFIX_OPR' => 106,
			'SIZEOF_TOKEN' => 207,
			'AMP_OPR' => 110,
			'RETURN_TOKEN' => 223,
			'INTEGER_LITERAL' => 191,
			'LCB_TOKEN' => 80,
			'SQL_TOKEN' => 45,
			'DECLARE_TOKEN' => 46,
			'CONTINUE_TOKEN' => 238,
			'GOTO_TOKEN' => 239,
			'EXEC_TOKEN' => 225,
			'POSTFIX_OPR' => 194,
			'LP_TOKEN' => 195,
			'BREAK_TOKEN' => 240,
			'IF_TOKEN' => 241,
			'ASTARI_OPR' => 127,
			'END_TOKEN' => 48,
			'STRING_LITERAL' => 198,
			'TOOLS_TOKEN' => 49
		},
		GOTOS => {
			'jump_statement' => 237,
			'iteration_statement' => 215,
			'logical_OR_expression' => 208,
			'expression_statement' => 228,
			'conditional_expression' => 199,
			'primary_expression' => 209,
			'embedded_sql' => 230,
			'statement' => 494,
			'expression' => 232,
			'unary_operator' => 187,
			'unary_expression' => 193,
			'equality_expression' => 201,
			'IDENTIFIER' => 236,
			'compound_statement' => 226,
			'labeled_statement' => 242,
			'shift_expression' => 203,
			'postfix_expression' => 210,
			'additive_expression' => 196,
			'exclusive_OR_expression' => 211,
			'inclusive_OR_expression' => 205,
			'relational_expression' => 197,
			'string_literal_list' => 212,
			'multiplicative_expression' => 206,
			'AND_expression' => 188,
			'logical_AND_expression' => 213,
			'assignment_expression' => 221,
			'cast_expression' => 214,
			'selection_statement' => 222
		}
	},
	{#State 477
		ACTIONS => {
			'CM_TOKEN' => 331,
			'RP_TOKEN' => 495
		}
	},
	{#State 478
		ACTIONS => {
			'SIZEOF_TOKEN' => 207,
			'AMP_OPR' => 110,
			'IDENTIFIER_ORG' => 39,
			'RP_TOKEN' => 496,
			'INTEGER_LITERAL' => 191,
			'MINUS_OPR' => 134,
			'SQL_TOKEN' => 45,
			'SECTION_TOKEN' => 40,
			'DECLARE_TOKEN' => 46,
			'FLOAT_LITERAL' => 200,
			'ORACLE_TOKEN' => 41,
			'EXEC_TOKEN' => 47,
			'POSTFIX_OPR' => 194,
			'LP_TOKEN' => 195,
			'PLUS_OPR' => 100,
			'CHAR_LITERAL' => 204,
			'ASTARI_OPR' => 127,
			'END_TOKEN' => 48,
			'BEGIN_TOKEN' => 43,
			'PREFIX_OPR' => 106,
			'STRING_LITERAL' => 198,
			'TOOLS_TOKEN' => 49
		},
		GOTOS => {
			'logical_OR_expression' => 208,
			'conditional_expression' => 199,
			'primary_expression' => 209,
			'expression' => 497,
			'unary_operator' => 187,
			'unary_expression' => 193,
			'equality_expression' => 201,
			'IDENTIFIER' => 202,
			'shift_expression' => 203,
			'additive_expression' => 196,
			'postfix_expression' => 210,
			'exclusive_OR_expression' => 211,
			'inclusive_OR_expression' => 205,
			'relational_expression' => 197,
			'string_literal_list' => 212,
			'AND_expression' => 188,
			'multiplicative_expression' => 206,
			'logical_AND_expression' => 213,
			'assignment_expression' => 221,
			'cast_expression' => 214
		}
	},
	{#State 479
		ACTIONS => {
			'SIZEOF_TOKEN' => 207,
			'AMP_OPR' => 110,
			'IDENTIFIER_ORG' => 39,
			'RP_TOKEN' => 498,
			'INTEGER_LITERAL' => 191,
			'MINUS_OPR' => 134,
			'SQL_TOKEN' => 45,
			'SECTION_TOKEN' => 40,
			'DECLARE_TOKEN' => 46,
			'FLOAT_LITERAL' => 200,
			'ORACLE_TOKEN' => 41,
			'EXEC_TOKEN' => 47,
			'POSTFIX_OPR' => 194,
			'LP_TOKEN' => 195,
			'PLUS_OPR' => 100,
			'CHAR_LITERAL' => 204,
			'ASTARI_OPR' => 127,
			'END_TOKEN' => 48,
			'BEGIN_TOKEN' => 43,
			'PREFIX_OPR' => 106,
			'STRING_LITERAL' => 198,
			'TOOLS_TOKEN' => 49
		},
		GOTOS => {
			'logical_OR_expression' => 208,
			'conditional_expression' => 199,
			'primary_expression' => 209,
			'expression' => 499,
			'unary_operator' => 187,
			'unary_expression' => 193,
			'equality_expression' => 201,
			'IDENTIFIER' => 202,
			'shift_expression' => 203,
			'additive_expression' => 196,
			'postfix_expression' => 210,
			'exclusive_OR_expression' => 211,
			'inclusive_OR_expression' => 205,
			'relational_expression' => 197,
			'string_literal_list' => 212,
			'AND_expression' => 188,
			'multiplicative_expression' => 206,
			'logical_AND_expression' => 213,
			'assignment_expression' => 221,
			'cast_expression' => 214
		}
	},
	{#State 480
		ACTIONS => {
			'CM_TOKEN' => 331,
			'SMC_TOKEN' => 500
		}
	},
	{#State 481
		DEFAULT => -209
	},
	{#State 482
		DEFAULT => -210
	},
	{#State 483
		ACTIONS => {
			'ELSE_TOKEN' => 501
		},
		DEFAULT => -207
	},
	{#State 484
		DEFAULT => -176
	},
	{#State 485
		DEFAULT => -170
	},
	{#State 486
		DEFAULT => -171
	},
	{#State 487
		ACTIONS => {
			'SIZEOF_TOKEN' => 207,
			'AMP_OPR' => 110,
			'IDENTIFIER_ORG' => 39,
			'INTEGER_LITERAL' => 191,
			'MINUS_OPR' => 134,
			'LCB_TOKEN' => 192,
			'SQL_TOKEN' => 45,
			'LSB_TOKEN' => 287,
			'SECTION_TOKEN' => 40,
			'DECLARE_TOKEN' => 46,
			'FLOAT_LITERAL' => 200,
			'ORACLE_TOKEN' => 41,
			'LP_TOKEN' => 195,
			'EXEC_TOKEN' => 47,
			'POSTFIX_OPR' => 194,
			'DOT_TOKEN' => 289,
			'PLUS_OPR' => 100,
			'RCB_TOKEN' => 502,
			'CHAR_LITERAL' => 204,
			'ASTARI_OPR' => 127,
			'END_TOKEN' => 48,
			'BEGIN_TOKEN' => 43,
			'PREFIX_OPR' => 106,
			'STRING_LITERAL' => 198,
			'TOOLS_TOKEN' => 49
		},
		GOTOS => {
			'logical_OR_expression' => 208,
			'conditional_expression' => 199,
			'primary_expression' => 209,
			'designation' => 438,
			'unary_operator' => 187,
			'unary_expression' => 193,
			'equality_expression' => 201,
			'IDENTIFIER' => 202,
			'designator_list' => 290,
			'shift_expression' => 203,
			'postfix_expression' => 210,
			'additive_expression' => 196,
			'exclusive_OR_expression' => 211,
			'designator' => 291,
			'inclusive_OR_expression' => 205,
			'relational_expression' => 197,
			'string_literal_list' => 212,
			'AND_expression' => 188,
			'multiplicative_expression' => 206,
			'logical_AND_expression' => 213,
			'assignment_expression' => 189,
			'cast_expression' => 214,
			'initializer' => 437
		}
	},
	{#State 488
		DEFAULT => -16
	},
	{#State 489
		ACTIONS => {
			'SMC_TOKEN' => 503
		}
	},
	{#State 490
		DEFAULT => -223
	},
	{#State 491
		ACTIONS => {
			'DEFAULT_TOKEN' => 227,
			'IDENTIFIER_ORG' => 39,
			'MINUS_OPR' => 134,
			'SMC_TOKEN' => 229,
			'SECTION_TOKEN' => 40,
			'DO_TOKEN' => 216,
			'WHILE_TOKEN' => 231,
			'CASE_TOKEN' => 233,
			'FLOAT_LITERAL' => 200,
			'ORACLE_TOKEN' => 41,
			'PLUS_OPR' => 100,
			'FOR_TOKEN' => 218,
			'CHAR_LITERAL' => 204,
			'SWITCH_TOKEN' => 220,
			'BEGIN_TOKEN' => 43,
			'PREFIX_OPR' => 106,
			'SIZEOF_TOKEN' => 207,
			'AMP_OPR' => 110,
			'RETURN_TOKEN' => 223,
			'INTEGER_LITERAL' => 191,
			'LCB_TOKEN' => 80,
			'SQL_TOKEN' => 45,
			'DECLARE_TOKEN' => 46,
			'CONTINUE_TOKEN' => 238,
			'GOTO_TOKEN' => 239,
			'EXEC_TOKEN' => 225,
			'POSTFIX_OPR' => 194,
			'LP_TOKEN' => 195,
			'BREAK_TOKEN' => 240,
			'IF_TOKEN' => 241,
			'ASTARI_OPR' => 127,
			'END_TOKEN' => 48,
			'STRING_LITERAL' => 198,
			'TOOLS_TOKEN' => 49
		},
		GOTOS => {
			'jump_statement' => 237,
			'iteration_statement' => 215,
			'logical_OR_expression' => 208,
			'expression_statement' => 228,
			'conditional_expression' => 199,
			'primary_expression' => 209,
			'embedded_sql' => 230,
			'statement' => 504,
			'expression' => 232,
			'unary_operator' => 187,
			'unary_expression' => 193,
			'equality_expression' => 201,
			'IDENTIFIER' => 236,
			'compound_statement' => 226,
			'labeled_statement' => 242,
			'shift_expression' => 203,
			'postfix_expression' => 210,
			'additive_expression' => 196,
			'exclusive_OR_expression' => 211,
			'inclusive_OR_expression' => 205,
			'relational_expression' => 197,
			'string_literal_list' => 212,
			'multiplicative_expression' => 206,
			'AND_expression' => 188,
			'logical_AND_expression' => 213,
			'assignment_expression' => 221,
			'cast_expression' => 214,
			'selection_statement' => 222
		}
	},
	{#State 492
		ACTIONS => {
			'DEFAULT_TOKEN' => 227,
			'IDENTIFIER_ORG' => 39,
			'MINUS_OPR' => 134,
			'SMC_TOKEN' => 229,
			'SECTION_TOKEN' => 40,
			'DO_TOKEN' => 216,
			'WHILE_TOKEN' => 231,
			'CASE_TOKEN' => 233,
			'FLOAT_LITERAL' => 200,
			'ORACLE_TOKEN' => 41,
			'PLUS_OPR' => 100,
			'FOR_TOKEN' => 218,
			'CHAR_LITERAL' => 204,
			'SWITCH_TOKEN' => 220,
			'BEGIN_TOKEN' => 43,
			'PREFIX_OPR' => 106,
			'SIZEOF_TOKEN' => 207,
			'AMP_OPR' => 110,
			'RETURN_TOKEN' => 223,
			'INTEGER_LITERAL' => 191,
			'LCB_TOKEN' => 80,
			'SQL_TOKEN' => 45,
			'DECLARE_TOKEN' => 46,
			'CONTINUE_TOKEN' => 238,
			'GOTO_TOKEN' => 239,
			'EXEC_TOKEN' => 225,
			'POSTFIX_OPR' => 194,
			'LP_TOKEN' => 195,
			'BREAK_TOKEN' => 240,
			'IF_TOKEN' => 241,
			'ASTARI_OPR' => 127,
			'END_TOKEN' => 48,
			'STRING_LITERAL' => 198,
			'TOOLS_TOKEN' => 49
		},
		GOTOS => {
			'jump_statement' => 237,
			'iteration_statement' => 215,
			'logical_OR_expression' => 208,
			'expression_statement' => 228,
			'conditional_expression' => 199,
			'primary_expression' => 209,
			'embedded_sql' => 230,
			'statement' => 505,
			'expression' => 232,
			'unary_operator' => 187,
			'unary_expression' => 193,
			'equality_expression' => 201,
			'IDENTIFIER' => 236,
			'compound_statement' => 226,
			'labeled_statement' => 242,
			'shift_expression' => 203,
			'postfix_expression' => 210,
			'additive_expression' => 196,
			'exclusive_OR_expression' => 211,
			'inclusive_OR_expression' => 205,
			'relational_expression' => 197,
			'string_literal_list' => 212,
			'multiplicative_expression' => 206,
			'AND_expression' => 188,
			'logical_AND_expression' => 213,
			'assignment_expression' => 221,
			'cast_expression' => 214,
			'selection_statement' => 222
		}
	},
	{#State 493
		ACTIONS => {
			'CM_TOKEN' => 331,
			'RP_TOKEN' => 506
		}
	},
	{#State 494
		DEFAULT => -212
	},
	{#State 495
		ACTIONS => {
			'DEFAULT_TOKEN' => 227,
			'IDENTIFIER_ORG' => 39,
			'MINUS_OPR' => 134,
			'SMC_TOKEN' => 229,
			'SECTION_TOKEN' => 40,
			'DO_TOKEN' => 216,
			'WHILE_TOKEN' => 231,
			'CASE_TOKEN' => 233,
			'FLOAT_LITERAL' => 200,
			'ORACLE_TOKEN' => 41,
			'PLUS_OPR' => 100,
			'FOR_TOKEN' => 218,
			'CHAR_LITERAL' => 204,
			'SWITCH_TOKEN' => 220,
			'BEGIN_TOKEN' => 43,
			'PREFIX_OPR' => 106,
			'SIZEOF_TOKEN' => 207,
			'AMP_OPR' => 110,
			'RETURN_TOKEN' => 223,
			'INTEGER_LITERAL' => 191,
			'LCB_TOKEN' => 80,
			'SQL_TOKEN' => 45,
			'DECLARE_TOKEN' => 46,
			'CONTINUE_TOKEN' => 238,
			'GOTO_TOKEN' => 239,
			'EXEC_TOKEN' => 225,
			'POSTFIX_OPR' => 194,
			'LP_TOKEN' => 195,
			'BREAK_TOKEN' => 240,
			'IF_TOKEN' => 241,
			'ASTARI_OPR' => 127,
			'END_TOKEN' => 48,
			'STRING_LITERAL' => 198,
			'TOOLS_TOKEN' => 49
		},
		GOTOS => {
			'jump_statement' => 237,
			'iteration_statement' => 215,
			'logical_OR_expression' => 208,
			'expression_statement' => 228,
			'conditional_expression' => 199,
			'primary_expression' => 209,
			'embedded_sql' => 230,
			'statement' => 507,
			'expression' => 232,
			'unary_operator' => 187,
			'unary_expression' => 193,
			'equality_expression' => 201,
			'IDENTIFIER' => 236,
			'compound_statement' => 226,
			'labeled_statement' => 242,
			'shift_expression' => 203,
			'postfix_expression' => 210,
			'additive_expression' => 196,
			'exclusive_OR_expression' => 211,
			'inclusive_OR_expression' => 205,
			'relational_expression' => 197,
			'string_literal_list' => 212,
			'multiplicative_expression' => 206,
			'AND_expression' => 188,
			'logical_AND_expression' => 213,
			'assignment_expression' => 221,
			'cast_expression' => 214,
			'selection_statement' => 222
		}
	},
	{#State 496
		ACTIONS => {
			'DEFAULT_TOKEN' => 227,
			'IDENTIFIER_ORG' => 39,
			'MINUS_OPR' => 134,
			'SMC_TOKEN' => 229,
			'SECTION_TOKEN' => 40,
			'DO_TOKEN' => 216,
			'WHILE_TOKEN' => 231,
			'CASE_TOKEN' => 233,
			'FLOAT_LITERAL' => 200,
			'ORACLE_TOKEN' => 41,
			'PLUS_OPR' => 100,
			'FOR_TOKEN' => 218,
			'CHAR_LITERAL' => 204,
			'SWITCH_TOKEN' => 220,
			'BEGIN_TOKEN' => 43,
			'PREFIX_OPR' => 106,
			'SIZEOF_TOKEN' => 207,
			'AMP_OPR' => 110,
			'RETURN_TOKEN' => 223,
			'INTEGER_LITERAL' => 191,
			'LCB_TOKEN' => 80,
			'SQL_TOKEN' => 45,
			'DECLARE_TOKEN' => 46,
			'CONTINUE_TOKEN' => 238,
			'GOTO_TOKEN' => 239,
			'EXEC_TOKEN' => 225,
			'POSTFIX_OPR' => 194,
			'LP_TOKEN' => 195,
			'BREAK_TOKEN' => 240,
			'IF_TOKEN' => 241,
			'ASTARI_OPR' => 127,
			'END_TOKEN' => 48,
			'STRING_LITERAL' => 198,
			'TOOLS_TOKEN' => 49
		},
		GOTOS => {
			'jump_statement' => 237,
			'iteration_statement' => 215,
			'logical_OR_expression' => 208,
			'expression_statement' => 228,
			'conditional_expression' => 199,
			'primary_expression' => 209,
			'embedded_sql' => 230,
			'statement' => 508,
			'expression' => 232,
			'unary_operator' => 187,
			'unary_expression' => 193,
			'equality_expression' => 201,
			'IDENTIFIER' => 236,
			'compound_statement' => 226,
			'labeled_statement' => 242,
			'shift_expression' => 203,
			'postfix_expression' => 210,
			'additive_expression' => 196,
			'exclusive_OR_expression' => 211,
			'inclusive_OR_expression' => 205,
			'relational_expression' => 197,
			'string_literal_list' => 212,
			'multiplicative_expression' => 206,
			'AND_expression' => 188,
			'logical_AND_expression' => 213,
			'assignment_expression' => 221,
			'cast_expression' => 214,
			'selection_statement' => 222
		}
	},
	{#State 497
		ACTIONS => {
			'CM_TOKEN' => 331,
			'RP_TOKEN' => 509
		}
	},
	{#State 498
		ACTIONS => {
			'DEFAULT_TOKEN' => 227,
			'IDENTIFIER_ORG' => 39,
			'MINUS_OPR' => 134,
			'SMC_TOKEN' => 229,
			'SECTION_TOKEN' => 40,
			'DO_TOKEN' => 216,
			'WHILE_TOKEN' => 231,
			'CASE_TOKEN' => 233,
			'FLOAT_LITERAL' => 200,
			'ORACLE_TOKEN' => 41,
			'PLUS_OPR' => 100,
			'FOR_TOKEN' => 218,
			'CHAR_LITERAL' => 204,
			'SWITCH_TOKEN' => 220,
			'BEGIN_TOKEN' => 43,
			'PREFIX_OPR' => 106,
			'SIZEOF_TOKEN' => 207,
			'AMP_OPR' => 110,
			'RETURN_TOKEN' => 223,
			'INTEGER_LITERAL' => 191,
			'LCB_TOKEN' => 80,
			'SQL_TOKEN' => 45,
			'DECLARE_TOKEN' => 46,
			'CONTINUE_TOKEN' => 238,
			'GOTO_TOKEN' => 239,
			'EXEC_TOKEN' => 225,
			'POSTFIX_OPR' => 194,
			'LP_TOKEN' => 195,
			'BREAK_TOKEN' => 240,
			'IF_TOKEN' => 241,
			'ASTARI_OPR' => 127,
			'END_TOKEN' => 48,
			'STRING_LITERAL' => 198,
			'TOOLS_TOKEN' => 49
		},
		GOTOS => {
			'jump_statement' => 237,
			'iteration_statement' => 215,
			'logical_OR_expression' => 208,
			'expression_statement' => 228,
			'conditional_expression' => 199,
			'primary_expression' => 209,
			'embedded_sql' => 230,
			'statement' => 510,
			'expression' => 232,
			'unary_operator' => 187,
			'unary_expression' => 193,
			'equality_expression' => 201,
			'IDENTIFIER' => 236,
			'compound_statement' => 226,
			'labeled_statement' => 242,
			'shift_expression' => 203,
			'postfix_expression' => 210,
			'additive_expression' => 196,
			'exclusive_OR_expression' => 211,
			'inclusive_OR_expression' => 205,
			'relational_expression' => 197,
			'string_literal_list' => 212,
			'multiplicative_expression' => 206,
			'AND_expression' => 188,
			'logical_AND_expression' => 213,
			'assignment_expression' => 221,
			'cast_expression' => 214,
			'selection_statement' => 222
		}
	},
	{#State 499
		ACTIONS => {
			'CM_TOKEN' => 331,
			'RP_TOKEN' => 511
		}
	},
	{#State 500
		ACTIONS => {
			'SIZEOF_TOKEN' => 207,
			'AMP_OPR' => 110,
			'IDENTIFIER_ORG' => 39,
			'RP_TOKEN' => 512,
			'INTEGER_LITERAL' => 191,
			'MINUS_OPR' => 134,
			'SQL_TOKEN' => 45,
			'SECTION_TOKEN' => 40,
			'DECLARE_TOKEN' => 46,
			'FLOAT_LITERAL' => 200,
			'ORACLE_TOKEN' => 41,
			'EXEC_TOKEN' => 47,
			'POSTFIX_OPR' => 194,
			'LP_TOKEN' => 195,
			'PLUS_OPR' => 100,
			'CHAR_LITERAL' => 204,
			'ASTARI_OPR' => 127,
			'END_TOKEN' => 48,
			'BEGIN_TOKEN' => 43,
			'PREFIX_OPR' => 106,
			'STRING_LITERAL' => 198,
			'TOOLS_TOKEN' => 49
		},
		GOTOS => {
			'logical_OR_expression' => 208,
			'conditional_expression' => 199,
			'primary_expression' => 209,
			'expression' => 513,
			'unary_operator' => 187,
			'unary_expression' => 193,
			'equality_expression' => 201,
			'IDENTIFIER' => 202,
			'shift_expression' => 203,
			'additive_expression' => 196,
			'postfix_expression' => 210,
			'exclusive_OR_expression' => 211,
			'inclusive_OR_expression' => 205,
			'relational_expression' => 197,
			'string_literal_list' => 212,
			'AND_expression' => 188,
			'multiplicative_expression' => 206,
			'logical_AND_expression' => 213,
			'assignment_expression' => 221,
			'cast_expression' => 214
		}
	},
	{#State 501
		ACTIONS => {
			'DEFAULT_TOKEN' => 227,
			'IDENTIFIER_ORG' => 39,
			'MINUS_OPR' => 134,
			'SMC_TOKEN' => 229,
			'SECTION_TOKEN' => 40,
			'DO_TOKEN' => 216,
			'WHILE_TOKEN' => 231,
			'CASE_TOKEN' => 233,
			'FLOAT_LITERAL' => 200,
			'ORACLE_TOKEN' => 41,
			'PLUS_OPR' => 100,
			'FOR_TOKEN' => 218,
			'CHAR_LITERAL' => 204,
			'SWITCH_TOKEN' => 220,
			'BEGIN_TOKEN' => 43,
			'PREFIX_OPR' => 106,
			'SIZEOF_TOKEN' => 207,
			'AMP_OPR' => 110,
			'RETURN_TOKEN' => 223,
			'INTEGER_LITERAL' => 191,
			'LCB_TOKEN' => 80,
			'SQL_TOKEN' => 45,
			'DECLARE_TOKEN' => 46,
			'CONTINUE_TOKEN' => 238,
			'GOTO_TOKEN' => 239,
			'EXEC_TOKEN' => 225,
			'POSTFIX_OPR' => 194,
			'LP_TOKEN' => 195,
			'BREAK_TOKEN' => 240,
			'IF_TOKEN' => 241,
			'ASTARI_OPR' => 127,
			'END_TOKEN' => 48,
			'STRING_LITERAL' => 198,
			'TOOLS_TOKEN' => 49
		},
		GOTOS => {
			'jump_statement' => 237,
			'iteration_statement' => 215,
			'logical_OR_expression' => 208,
			'expression_statement' => 228,
			'conditional_expression' => 199,
			'primary_expression' => 209,
			'embedded_sql' => 230,
			'statement' => 514,
			'expression' => 232,
			'unary_operator' => 187,
			'unary_expression' => 193,
			'equality_expression' => 201,
			'IDENTIFIER' => 236,
			'compound_statement' => 226,
			'labeled_statement' => 242,
			'shift_expression' => 203,
			'postfix_expression' => 210,
			'additive_expression' => 196,
			'exclusive_OR_expression' => 211,
			'inclusive_OR_expression' => 205,
			'relational_expression' => 197,
			'string_literal_list' => 212,
			'multiplicative_expression' => 206,
			'AND_expression' => 188,
			'logical_AND_expression' => 213,
			'assignment_expression' => 221,
			'cast_expression' => 214,
			'selection_statement' => 222
		}
	},
	{#State 502
		DEFAULT => -17
	},
	{#State 503
		DEFAULT => -211
	},
	{#State 504
		DEFAULT => -221
	},
	{#State 505
		DEFAULT => -222
	},
	{#State 506
		ACTIONS => {
			'DEFAULT_TOKEN' => 227,
			'IDENTIFIER_ORG' => 39,
			'MINUS_OPR' => 134,
			'SMC_TOKEN' => 229,
			'SECTION_TOKEN' => 40,
			'DO_TOKEN' => 216,
			'WHILE_TOKEN' => 231,
			'CASE_TOKEN' => 233,
			'FLOAT_LITERAL' => 200,
			'ORACLE_TOKEN' => 41,
			'PLUS_OPR' => 100,
			'FOR_TOKEN' => 218,
			'CHAR_LITERAL' => 204,
			'SWITCH_TOKEN' => 220,
			'BEGIN_TOKEN' => 43,
			'PREFIX_OPR' => 106,
			'SIZEOF_TOKEN' => 207,
			'AMP_OPR' => 110,
			'RETURN_TOKEN' => 223,
			'INTEGER_LITERAL' => 191,
			'LCB_TOKEN' => 80,
			'SQL_TOKEN' => 45,
			'DECLARE_TOKEN' => 46,
			'CONTINUE_TOKEN' => 238,
			'GOTO_TOKEN' => 239,
			'EXEC_TOKEN' => 225,
			'POSTFIX_OPR' => 194,
			'LP_TOKEN' => 195,
			'BREAK_TOKEN' => 240,
			'IF_TOKEN' => 241,
			'ASTARI_OPR' => 127,
			'END_TOKEN' => 48,
			'STRING_LITERAL' => 198,
			'TOOLS_TOKEN' => 49
		},
		GOTOS => {
			'jump_statement' => 237,
			'iteration_statement' => 215,
			'logical_OR_expression' => 208,
			'expression_statement' => 228,
			'conditional_expression' => 199,
			'primary_expression' => 209,
			'embedded_sql' => 230,
			'statement' => 515,
			'expression' => 232,
			'unary_operator' => 187,
			'unary_expression' => 193,
			'equality_expression' => 201,
			'IDENTIFIER' => 236,
			'compound_statement' => 226,
			'labeled_statement' => 242,
			'shift_expression' => 203,
			'postfix_expression' => 210,
			'additive_expression' => 196,
			'exclusive_OR_expression' => 211,
			'inclusive_OR_expression' => 205,
			'relational_expression' => 197,
			'string_literal_list' => 212,
			'multiplicative_expression' => 206,
			'AND_expression' => 188,
			'logical_AND_expression' => 213,
			'assignment_expression' => 221,
			'cast_expression' => 214,
			'selection_statement' => 222
		}
	},
	{#State 507
		DEFAULT => -215
	},
	{#State 508
		DEFAULT => -214
	},
	{#State 509
		ACTIONS => {
			'DEFAULT_TOKEN' => 227,
			'IDENTIFIER_ORG' => 39,
			'MINUS_OPR' => 134,
			'SMC_TOKEN' => 229,
			'SECTION_TOKEN' => 40,
			'DO_TOKEN' => 216,
			'WHILE_TOKEN' => 231,
			'CASE_TOKEN' => 233,
			'FLOAT_LITERAL' => 200,
			'ORACLE_TOKEN' => 41,
			'PLUS_OPR' => 100,
			'FOR_TOKEN' => 218,
			'CHAR_LITERAL' => 204,
			'SWITCH_TOKEN' => 220,
			'BEGIN_TOKEN' => 43,
			'PREFIX_OPR' => 106,
			'SIZEOF_TOKEN' => 207,
			'AMP_OPR' => 110,
			'RETURN_TOKEN' => 223,
			'INTEGER_LITERAL' => 191,
			'LCB_TOKEN' => 80,
			'SQL_TOKEN' => 45,
			'DECLARE_TOKEN' => 46,
			'CONTINUE_TOKEN' => 238,
			'GOTO_TOKEN' => 239,
			'EXEC_TOKEN' => 225,
			'POSTFIX_OPR' => 194,
			'LP_TOKEN' => 195,
			'BREAK_TOKEN' => 240,
			'IF_TOKEN' => 241,
			'ASTARI_OPR' => 127,
			'END_TOKEN' => 48,
			'STRING_LITERAL' => 198,
			'TOOLS_TOKEN' => 49
		},
		GOTOS => {
			'jump_statement' => 237,
			'iteration_statement' => 215,
			'logical_OR_expression' => 208,
			'expression_statement' => 228,
			'conditional_expression' => 199,
			'primary_expression' => 209,
			'embedded_sql' => 230,
			'statement' => 516,
			'expression' => 232,
			'unary_operator' => 187,
			'unary_expression' => 193,
			'equality_expression' => 201,
			'IDENTIFIER' => 236,
			'compound_statement' => 226,
			'labeled_statement' => 242,
			'shift_expression' => 203,
			'postfix_expression' => 210,
			'additive_expression' => 196,
			'exclusive_OR_expression' => 211,
			'inclusive_OR_expression' => 205,
			'relational_expression' => 197,
			'string_literal_list' => 212,
			'multiplicative_expression' => 206,
			'AND_expression' => 188,
			'logical_AND_expression' => 213,
			'assignment_expression' => 221,
			'cast_expression' => 214,
			'selection_statement' => 222
		}
	},
	{#State 510
		DEFAULT => -213
	},
	{#State 511
		ACTIONS => {
			'DEFAULT_TOKEN' => 227,
			'IDENTIFIER_ORG' => 39,
			'MINUS_OPR' => 134,
			'SMC_TOKEN' => 229,
			'SECTION_TOKEN' => 40,
			'DO_TOKEN' => 216,
			'WHILE_TOKEN' => 231,
			'CASE_TOKEN' => 233,
			'FLOAT_LITERAL' => 200,
			'ORACLE_TOKEN' => 41,
			'PLUS_OPR' => 100,
			'FOR_TOKEN' => 218,
			'CHAR_LITERAL' => 204,
			'SWITCH_TOKEN' => 220,
			'BEGIN_TOKEN' => 43,
			'PREFIX_OPR' => 106,
			'SIZEOF_TOKEN' => 207,
			'AMP_OPR' => 110,
			'RETURN_TOKEN' => 223,
			'INTEGER_LITERAL' => 191,
			'LCB_TOKEN' => 80,
			'SQL_TOKEN' => 45,
			'DECLARE_TOKEN' => 46,
			'CONTINUE_TOKEN' => 238,
			'GOTO_TOKEN' => 239,
			'EXEC_TOKEN' => 225,
			'POSTFIX_OPR' => 194,
			'LP_TOKEN' => 195,
			'BREAK_TOKEN' => 240,
			'IF_TOKEN' => 241,
			'ASTARI_OPR' => 127,
			'END_TOKEN' => 48,
			'STRING_LITERAL' => 198,
			'TOOLS_TOKEN' => 49
		},
		GOTOS => {
			'jump_statement' => 237,
			'iteration_statement' => 215,
			'logical_OR_expression' => 208,
			'expression_statement' => 228,
			'conditional_expression' => 199,
			'primary_expression' => 209,
			'embedded_sql' => 230,
			'statement' => 517,
			'expression' => 232,
			'unary_operator' => 187,
			'unary_expression' => 193,
			'equality_expression' => 201,
			'IDENTIFIER' => 236,
			'compound_statement' => 226,
			'labeled_statement' => 242,
			'shift_expression' => 203,
			'postfix_expression' => 210,
			'additive_expression' => 196,
			'exclusive_OR_expression' => 211,
			'inclusive_OR_expression' => 205,
			'relational_expression' => 197,
			'string_literal_list' => 212,
			'multiplicative_expression' => 206,
			'AND_expression' => 188,
			'logical_AND_expression' => 213,
			'assignment_expression' => 221,
			'cast_expression' => 214,
			'selection_statement' => 222
		}
	},
	{#State 512
		ACTIONS => {
			'DEFAULT_TOKEN' => 227,
			'IDENTIFIER_ORG' => 39,
			'MINUS_OPR' => 134,
			'SMC_TOKEN' => 229,
			'SECTION_TOKEN' => 40,
			'DO_TOKEN' => 216,
			'WHILE_TOKEN' => 231,
			'CASE_TOKEN' => 233,
			'FLOAT_LITERAL' => 200,
			'ORACLE_TOKEN' => 41,
			'PLUS_OPR' => 100,
			'FOR_TOKEN' => 218,
			'CHAR_LITERAL' => 204,
			'SWITCH_TOKEN' => 220,
			'BEGIN_TOKEN' => 43,
			'PREFIX_OPR' => 106,
			'SIZEOF_TOKEN' => 207,
			'AMP_OPR' => 110,
			'RETURN_TOKEN' => 223,
			'INTEGER_LITERAL' => 191,
			'LCB_TOKEN' => 80,
			'SQL_TOKEN' => 45,
			'DECLARE_TOKEN' => 46,
			'CONTINUE_TOKEN' => 238,
			'GOTO_TOKEN' => 239,
			'EXEC_TOKEN' => 225,
			'POSTFIX_OPR' => 194,
			'LP_TOKEN' => 195,
			'BREAK_TOKEN' => 240,
			'IF_TOKEN' => 241,
			'ASTARI_OPR' => 127,
			'END_TOKEN' => 48,
			'STRING_LITERAL' => 198,
			'TOOLS_TOKEN' => 49
		},
		GOTOS => {
			'jump_statement' => 237,
			'iteration_statement' => 215,
			'logical_OR_expression' => 208,
			'expression_statement' => 228,
			'conditional_expression' => 199,
			'primary_expression' => 209,
			'embedded_sql' => 230,
			'statement' => 518,
			'expression' => 232,
			'unary_operator' => 187,
			'unary_expression' => 193,
			'equality_expression' => 201,
			'IDENTIFIER' => 236,
			'compound_statement' => 226,
			'labeled_statement' => 242,
			'shift_expression' => 203,
			'postfix_expression' => 210,
			'additive_expression' => 196,
			'exclusive_OR_expression' => 211,
			'inclusive_OR_expression' => 205,
			'relational_expression' => 197,
			'string_literal_list' => 212,
			'multiplicative_expression' => 206,
			'AND_expression' => 188,
			'logical_AND_expression' => 213,
			'assignment_expression' => 221,
			'cast_expression' => 214,
			'selection_statement' => 222
		}
	},
	{#State 513
		ACTIONS => {
			'CM_TOKEN' => 331,
			'RP_TOKEN' => 519
		}
	},
	{#State 514
		DEFAULT => -208
	},
	{#State 515
		DEFAULT => -220
	},
	{#State 516
		DEFAULT => -216
	},
	{#State 517
		DEFAULT => -217
	},
	{#State 518
		DEFAULT => -218
	},
	{#State 519
		ACTIONS => {
			'DEFAULT_TOKEN' => 227,
			'IDENTIFIER_ORG' => 39,
			'MINUS_OPR' => 134,
			'SMC_TOKEN' => 229,
			'SECTION_TOKEN' => 40,
			'DO_TOKEN' => 216,
			'WHILE_TOKEN' => 231,
			'CASE_TOKEN' => 233,
			'FLOAT_LITERAL' => 200,
			'ORACLE_TOKEN' => 41,
			'PLUS_OPR' => 100,
			'FOR_TOKEN' => 218,
			'CHAR_LITERAL' => 204,
			'SWITCH_TOKEN' => 220,
			'BEGIN_TOKEN' => 43,
			'PREFIX_OPR' => 106,
			'SIZEOF_TOKEN' => 207,
			'AMP_OPR' => 110,
			'RETURN_TOKEN' => 223,
			'INTEGER_LITERAL' => 191,
			'LCB_TOKEN' => 80,
			'SQL_TOKEN' => 45,
			'DECLARE_TOKEN' => 46,
			'CONTINUE_TOKEN' => 238,
			'GOTO_TOKEN' => 239,
			'EXEC_TOKEN' => 225,
			'POSTFIX_OPR' => 194,
			'LP_TOKEN' => 195,
			'BREAK_TOKEN' => 240,
			'IF_TOKEN' => 241,
			'ASTARI_OPR' => 127,
			'END_TOKEN' => 48,
			'STRING_LITERAL' => 198,
			'TOOLS_TOKEN' => 49
		},
		GOTOS => {
			'jump_statement' => 237,
			'iteration_statement' => 215,
			'logical_OR_expression' => 208,
			'expression_statement' => 228,
			'conditional_expression' => 199,
			'primary_expression' => 209,
			'embedded_sql' => 230,
			'statement' => 520,
			'expression' => 232,
			'unary_operator' => 187,
			'unary_expression' => 193,
			'equality_expression' => 201,
			'IDENTIFIER' => 236,
			'compound_statement' => 226,
			'labeled_statement' => 242,
			'shift_expression' => 203,
			'postfix_expression' => 210,
			'additive_expression' => 196,
			'exclusive_OR_expression' => 211,
			'inclusive_OR_expression' => 205,
			'relational_expression' => 197,
			'string_literal_list' => 212,
			'multiplicative_expression' => 206,
			'AND_expression' => 188,
			'logical_AND_expression' => 213,
			'assignment_expression' => 221,
			'cast_expression' => 214,
			'selection_statement' => 222
		}
	},
	{#State 520
		DEFAULT => -219
	}
],
                                  yyrules  =>
[
	[#Rule 0
		 '$start', 2, undef
	],
	[#Rule 1
		 'primary_expression', 1,
sub {
		printDebugLog("primary_expression:IDENTIFIER");
		['N_primary_expression', $_[1]];
	}
	],
	[#Rule 2
		 'primary_expression', 1,
sub {
		printDebugLog("primary_expression:INTEGER_LITERAL");
		['N_primary_expression', $_[1]];
	}
	],
	[#Rule 3
		 'primary_expression', 1,
sub {
		printDebugLog("primary_expression:FLOAT_LITERAL");
		['N_primary_expression', $_[1]];
	}
	],
	[#Rule 4
		 'primary_expression', 1,
sub {
		printDebugLog("primary_expression:CHAR_LITERAL");
		['N_primary_expression', $_[1]];
	}
	],
	[#Rule 5
		 'primary_expression', 1,
sub {
		printDebugLog("primary_expression:string_literal_list");
        ['N_primary_expression', $_[1]];
    }
	],
	[#Rule 6
		 'primary_expression', 3,
sub {
		printDebugLog("primary_expression:( expression )");
		['N_primary_expression', $_[2]];
	}
	],
	[#Rule 7
		 'string_literal_list', 1,
sub {
		printDebugLog("string_literal_list:STRING_LITERAL");
        $_[1]->{TOKEN} =~ s{\A"}{}xms;
        $_[1]->{TOKEN} =~ s{"\z}{}xms;
        $_[1];
    }
	],
	[#Rule 8
		 'string_literal_list', 2,
sub {
		printDebugLog("string_literal_list:string_literal_list STRING_LITERAL");
        $_[2]->{TOKEN} =~ s{\A"}{}xms;
        $_[2]->{TOKEN} =~ s{"\z}{}xms;
        $_[1]->{TOKEN} = $_[1]->{TOKEN} . $_[2]->{TOKEN};
		$_[1];
    }
	],
	[#Rule 9
		 'postfix_expression', 1,
sub {
		printDebugLog("postfix_expression:primary_expression");
		$_[1];
	}
	],
	[#Rule 10
		 'postfix_expression', 4,
sub {
		printDebugLog("postfix_expression:postfix_expression [ expression ]");
		['N_postfix_expression' , $_[1]];
	}
	],
	[#Rule 11
		 'postfix_expression', 4,
sub {
		printDebugLog("postfix_expression:postfix_expression ( argument_expression_list )");
		['N_postfix_expression' , $_[1] , $_[2] , $_[3] , $_[4]];
	}
	],
	[#Rule 12
		 'postfix_expression', 3,
sub {
		printDebugLog("postfix_expression:postfix_expression ( )");
		['N_postfix_expression' , $_[1] , $_[2] , $_[3]];
	}
	],
	[#Rule 13
		 'postfix_expression', 3,
sub {
		printDebugLog("postfix_expression:postfix_expression . IDENTIFIER");
		['N_postfix_expression' , $_[1]];
	}
	],
	[#Rule 14
		 'postfix_expression', 3,
sub {
		printDebugLog("postfix_expression:postfix_expression -> IDENTIFIER");
		['N_postfix_expression' , $_[1]];
	}
	],
	[#Rule 15
		 'postfix_expression', 2,
sub {
		printDebugLog("postfix_expression:postfix_expression [++|--]");
		['N_postfix_expression' , $_[1]];
	}
	],
	[#Rule 16
		 'postfix_expression', 6,
sub {
		printDebugLog("postfix_expression:( type_name ) { initializer_list }");
		['N_postfix_expression'];
	}
	],
	[#Rule 17
		 'postfix_expression', 7,
sub {
		printDebugLog("postfix_expression:( type_name ) { initializer_list , }");
		['N_postfix_expression'];
	}
	],
	[#Rule 18
		 'argument_expression_list', 1,
sub {
		printDebugLog("argument_expression_list:assignment_expression");
		['N_argument_expression_list', $_[1]];
	}
	],
	[#Rule 19
		 'argument_expression_list', 3,
sub {
		printDebugLog("argument_expression_list:argument_expression_list , assignment_expression");
        push(@{$_[1]}, $_[2]);
        push(@{$_[1]}, $_[3]);
        $_[1];
	}
	],
	[#Rule 20
		 'unary_expression', 1,
sub {
		printDebugLog("unary_expression:postfix_expression");
		$_[1];
	}
	],
	[#Rule 21
		 'unary_expression', 2,
sub {
		printDebugLog("unary_expression:[++|--] unary_expression");
		['N_unary_expression', $_[2]];
	}
	],
	[#Rule 22
		 'unary_expression', 2,
sub {
		printDebugLog("unary_expression:unary_operator cast_expression");
		['N_unary_expression', $_[2]];
	}
	],
	[#Rule 23
		 'unary_expression', 2,
sub {
		printDebugLog("unary_expression:sizeof unary_expression");
		['N_unary_expression', $_[2]];
	}
	],
	[#Rule 24
		 'unary_expression', 4,
sub {
		printDebugLog("unary_expression:sizeof ( type_name )");
		['N_unary_expression'];
	}
	],
	[#Rule 25
		 'unary_operator', 1,
sub {
		printDebugLog("unary_operator:&");
		$_[1];
	}
	],
	[#Rule 26
		 'unary_operator', 1,
sub {
		printDebugLog("unary_operator:*");
		$_[1];
	}
	],
	[#Rule 27
		 'unary_operator', 1,
sub {
		printDebugLog("unary_operator:+");
		$_[1];
	}
	],
	[#Rule 28
		 'unary_operator', 1,
sub {
		printDebugLog("unary_operator:-");
		$_[1];
	}
	],
	[#Rule 29
		 'unary_operator', 1,
sub {
		printDebugLog("unary_operator:!~");
		$_[1];
	}
	],
	[#Rule 30
		 'cast_expression', 1,
sub {
		printDebugLog("cast_expression:unary_expression");
		$_[1];
	}
	],
	[#Rule 31
		 'cast_expression', 4,
sub {
		printDebugLog("cast_expression:( type_name ) cast_expression");
		['N_cast_expression', $_[4]];
	}
	],
	[#Rule 32
		 'multiplicative_expression', 1,
sub {
		printDebugLog("multiplicative_expression:cast_expression");
		$_[1];
	}
	],
	[#Rule 33
		 'multiplicative_expression', 3,
sub {
		printDebugLog("multiplicative_expression:multiplicative_expression * cast_expression");
		['N_multiplicative_expression', $_[1], $_[2], $_[3]];
	}
	],
	[#Rule 34
		 'multiplicative_expression', 3,
sub {
		printDebugLog("multiplicative_expression:multiplicative_expression [/|%] cast_expression");
		['N_multiplicative_expression', $_[1], $_[2], $_[3]];
	}
	],
	[#Rule 35
		 'additive_expression', 1,
sub {
		printDebugLog("additive_expression:multiplicative_expression");
		$_[1];
	}
	],
	[#Rule 36
		 'additive_expression', 3,
sub {
		printDebugLog("additive_expression:additive_expression + multiplicative_expression");
		['N_additive_expression', $_[1], $_[2], $_[3]];
	}
	],
	[#Rule 37
		 'additive_expression', 3,
sub {
		printDebugLog("additive_expression:additive_expression - multiplicative_expression");
		['N_additive_expression', $_[1], $_[2], $_[3]];
	}
	],
	[#Rule 38
		 'shift_expression', 1,
sub {
		printDebugLog("shift_expression:additive_expression");
		$_[1];
	}
	],
	[#Rule 39
		 'shift_expression', 3,
sub {
		printDebugLog("shift_expression:shift_expression [<<|>>] additive_expression");
		['N_shift_expression', $_[1], $_[2], $_[3]];
	}
	],
	[#Rule 40
		 'relational_expression', 1,
sub {
		printDebugLog("relational_expression:shift_expression");
		$_[1];
	}
	],
	[#Rule 41
		 'relational_expression', 3,
sub {
		printDebugLog("relational_expression:relational_expression < shift_expression");
		['N_relational_expression', $_[1], $_[2], $_[3]];
	}
	],
	[#Rule 42
		 'relational_expression', 3,
sub {
		printDebugLog("relational_expression:relational_expression > shift_expression");
		['N_relational_expression', $_[1], $_[2], $_[3]];
	}
	],
	[#Rule 43
		 'relational_expression', 3,
sub {
		printDebugLog("relational_expression:relational_expression [<=|=>] shift_expression");
		['N_relational_expression', $_[1], $_[2], $_[3]];
	}
	],
	[#Rule 44
		 'equality_expression', 1,
sub {
		printDebugLog("equality_expression:relational_expression");
		$_[1];
	}
	],
	[#Rule 45
		 'equality_expression', 3,
sub {
		printDebugLog("equality_expression:equality_expression [!|=]= relational_expression");
		['N_equality_expression', $_[1], $_[2], $_[3]];
	}
	],
	[#Rule 46
		 'AND_expression', 1,
sub {
		printDebugLog("AND_expression:equality_expression");
		$_[1];
	}
	],
	[#Rule 47
		 'AND_expression', 3,
sub {
		printDebugLog("AND_expression:AND_expression & equality_expression");
		['N_AND_expression', $_[1], $_[2], $_[3]];
	}
	],
	[#Rule 48
		 'exclusive_OR_expression', 1,
sub {
		printDebugLog("exclusive_OR_expression:AND_expression");
		$_[1];
	}
	],
	[#Rule 49
		 'exclusive_OR_expression', 3,
sub {
		printDebugLog("exclusive_OR_expression:exclusive_OR_expression ^ AND_expression");
		['N_exclusive_OR_expression', $_[1], $_[2], $_[3]];
	}
	],
	[#Rule 50
		 'inclusive_OR_expression', 1,
sub {
		printDebugLog("inclusive_OR_expression:exclusive_OR_expression");
		$_[1];
	}
	],
	[#Rule 51
		 'inclusive_OR_expression', 3,
sub {
		printDebugLog("inclusive_OR_expression:inclusive_OR_expression | exclusive_OR_expression");
		 ['N_inclusive_OR_expression', $_[1], $_[2], $_[3]];
	}
	],
	[#Rule 52
		 'logical_AND_expression', 1,
sub {
		printDebugLog("logical_AND_expression:inclusive_OR_expression");
		$_[1];
	}
	],
	[#Rule 53
		 'logical_AND_expression', 3,
sub {
		printDebugLog("logical_AND_expression:logical_AND_expression && inclusive_OR_expression");
 		['N_logical_AND_expression', $_[1], $_[2], $_[3]];
	}
	],
	[#Rule 54
		 'logical_OR_expression', 1,
sub {
		printDebugLog("logical_OR_expression:logical_AND_expression");
		$_[1];
	}
	],
	[#Rule 55
		 'logical_OR_expression', 3,
sub {
		printDebugLog("logical_OR_expression:logical_OR_expression || logical_AND_expression");
		['N_logical_OR_expression', $_[1], $_[2], $_[3]];
	}
	],
	[#Rule 56
		 'conditional_expression', 1,
sub {
		printDebugLog("conditional_expression:logical_OR_expression");
		$_[1];
	}
	],
	[#Rule 57
		 'conditional_expression', 5,
sub {
		printDebugLog("conditional_expression:logical_OR_expression ? expression : conditional_expression");
		['N_logical_OR_expression', $_[1], $_[2], $_[3], $_[4], $_[5] ];
	}
	],
	[#Rule 58
		 'assignment_expression', 1,
sub {
		printDebugLog("assignment_expression:conditional_expression");
		$_[1];
	}
	],
	[#Rule 59
		 'assignment_expression', 3,
sub {
		printDebugLog("assignment_expression:unary_expression assignment_operator assignment_expression");
        my $leftside = pop(@{$_[1]});
        push(@{$_[1]}, [ 'N_assignment_operator', $leftside, $_[2], $_[3] ]);
        $_[1];
	}
	],
	[#Rule 60
		 'assignment_operator', 1, undef
	],
	[#Rule 61
		 'assignment_operator', 1, undef
	],
	[#Rule 62
		 'assignment_operator', 1, undef
	],
	[#Rule 63
		 'expression', 1,
sub {
		printDebugLog("expression:assignment_expression");
		['N_expression', $_[1]];
	}
	],
	[#Rule 64
		 'expression', 3,
sub {
		printDebugLog("expression:expression , assignment_expression");
        push(@{$_[1]}, $_[3]);
        $_[1];	
	}
	],
	[#Rule 65
		 'constant_expression', 1,
sub {
		printDebugLog("constant_expression:conditional_expression");
		$_[1];
	}
	],
	[#Rule 66
		 'declaration', 3,
sub {
		printDebugLog("declaration:declaration_specifiers init_declarator_list;");
		if(defined $_[1]->[1]){
			if($G_typedef_flg){
				$G_typedef_flg = 0;
                undef;
			}else{
			    {VARIABLE => [$_[1],$_[2]] };
            }
		}
		else{
			undef;
		}
	}
	],
	[#Rule 67
		 'declaration', 2,
sub {
		printDebugLog("declaration:declaration_specifiers ;") ;
		undef;
	}
	],
	[#Rule 68
		 'declaration_specifiers', 1,
sub {
		printDebugLog("declaration_specifiers:storage_class_specifier");
		['N_declaration_specifiers', $_[1]];
	}
	],
	[#Rule 69
		 'declaration_specifiers', 2,
sub {
		printDebugLog("declaration_specifiers:storage_class_specifier declaration_specifiers");
		shift @{$_[2]};
		unshift @{$_[2]} , $_[1];
		unshift @{$_[2]} , 'N_declaration_specifiers';
		$_[2];
	}
	],
	[#Rule 70
		 'declaration_specifiers', 1,
sub {
		printDebugLog("declaration_specifiers:type_specifier");
		['N_declaration_specifiers', $_[1]];
	}
	],
	[#Rule 71
		 'declaration_specifiers', 2,
sub {
		printDebugLog("declaration_specifiers:type_specifier declaration_specifiers");
		shift @{$_[2]};
		unshift @{$_[2]} , $_[1];
		unshift @{$_[2]} , 'N_declaration_specifiers';
		$_[2];
	}
	],
	[#Rule 72
		 'declaration_specifiers', 1,
sub {
		printDebugLog("declaration_specifiers:type_qualifier");
		['N_declaration_specifiers', $_[1]];
	}
	],
	[#Rule 73
		 'declaration_specifiers', 2,
sub {
		printDebugLog("declaration_specifiers:type_qualifier declaration_specifiers");
		shift @{$_[2]};
		unshift @{$_[2]} , $_[1];
		unshift @{$_[2]} , 'N_declaration_specifiers';
		$_[2];
	}
	],
	[#Rule 74
		 'declaration_specifiers', 1,
sub {
		printDebugLog("declaration_specifiers:function_specifier");
		['N_declaration_specifiers'];
	}
	],
	[#Rule 75
		 'declaration_specifiers', 2,
sub {
		printDebugLog("declaration_specifiers:function_specifier declaration_specifiers");
		$_[2];
	}
	],
	[#Rule 76
		 'init_declarator_list', 1,
sub {
		printDebugLog("init_declarator_list:init_declarator");
		['N_init_declarator_list', $_[1]]
	}
	],
	[#Rule 77
		 'init_declarator_list', 3,
sub {
		printDebugLog("init_declarator_list:init_declarator_list, init_declarator");
        push(@{$_[1]}, $_[2]); push(@{$_[1]}, $_[3]); 
        $_[1];
	}
	],
	[#Rule 78
		 'init_declarator', 1,
sub {
		printDebugLog("init_declarator:declarator");
		my $metanode = shift @{$_[1]};
        my $decl = $metanode->[1];
        if( !defined $decl->{type} or $decl->{type} ne 'ARRAY'){
        	$decl->{type} = 'NORMAL';
        }
		unshift @{$_[1]} , $metanode;
		unshift @{$_[1]} , 'N_init_declarator';
		if($G_typedef_flg){
		    if(exists($_[1]->[1]->[1]->{name})){
		        $lex->set_typedefname($_[1]->[1]->[1]->{name}->{TOKEN},0);
            }elsif(exists($_[1]->[1]->[1]->{TOKEN})){
                $lex->set_typedefname($_[1]->[1]->[1]->{TOKEN},0);
            }
        }
		$_[1];
	}
	],
	[#Rule 79
		 'init_declarator', 3,
sub {
		my @initializer;
		printDebugLog("init_declarator:declarator = initializer");
		push(@initializer , $_[2]);
		push(@initializer , $_[3]);
		
        my $metanode = shift @{$_[1]};
        my $decl = $metanode->[1];
        if( !defined $decl->{type} or $decl->{type} ne 'ARRAY'){
        	$decl->{type} = 'NORMAL';
        }
        $decl->{value} = $_[3];
		
		push(@{$_[1]} , @initializer);
		unshift @{$_[1]} , $metanode;
		unshift @{$_[1]} , 'N_init_declarator'; 
		$_[1];
	}
	],
	[#Rule 80
		 'storage_class_specifier', 1,
sub {
		$G_typedef_flg = 1;
		printDebugLog("storage_class_specifier:TYPEDEF_TOKEN");
        $_[1];
	}
	],
	[#Rule 81
		 'storage_class_specifier', 1,
sub {
		printDebugLog("storage_class_specifier:EXTERN_TOKEN");
        $_[1];
	}
	],
	[#Rule 82
		 'storage_class_specifier', 1,
sub {
		printDebugLog("storage_class_specifier:STATIC_TOKEN");
        $_[1];
	}
	],
	[#Rule 83
		 'storage_class_specifier', 1,
sub {
		printDebugLog("storage_class_specifier:AUTO_TOKEN");
        $_[1];
	}
	],
	[#Rule 84
		 'storage_class_specifier', 1,
sub {
		printDebugLog("storage_class_specifier:REGISTER_TOKEN");
        $_[1];
	}
	],
	[#Rule 85
		 'type_specifier', 1,
sub {
		printDebugLog("type_specifier:VOID_TOKEN");
		['N_type_specifier', $_[1] ];
	}
	],
	[#Rule 86
		 'type_specifier', 1,
sub {
		printDebugLog("type_specifier:CHAR_TOKEN");
		['N_type_specifier', $_[1] ];
	}
	],
	[#Rule 87
		 'type_specifier', 1,
sub {
		printDebugLog("type_specifier:SHORT_TOKEN");
		['N_type_specifier', $_[1] ];
	}
	],
	[#Rule 88
		 'type_specifier', 1,
sub {
		printDebugLog("type_specifier:INT_TOKEN");
		['N_type_specifier', $_[1] ];
	}
	],
	[#Rule 89
		 'type_specifier', 1,
sub {
		printDebugLog("type_specifier:LONG_TOKEN");
		['N_type_specifier', $_[1] ];
	}
	],
	[#Rule 90
		 'type_specifier', 1,
sub {
		printDebugLog("type_specifier:FLOAT_TOKEN");
		['N_type_specifier', $_[1] ];
	}
	],
	[#Rule 91
		 'type_specifier', 1,
sub {
		printDebugLog("type_specifier:DOUBLE_TOKEN");
		['N_type_specifier', $_[1] ];
	}
	],
	[#Rule 92
		 'type_specifier', 1,
sub {
		printDebugLog("type_specifier:SIGNED_TOKEN");
		['N_type_specifier', $_[1] ];
	}
	],
	[#Rule 93
		 'type_specifier', 1,
sub {
		printDebugLog("type_specifier:UNSIGNED_TOKEN");
		['N_type_specifier', $_[1] ];
	}
	],
	[#Rule 94
		 'type_specifier', 1,
sub {
		printDebugLog("type_specifier:_BOOL_TOKEN");
		['N_type_specifier', $_[1] ];
	}
	],
	[#Rule 95
		 'type_specifier', 1,
sub {
		printDebugLog("type_specifier:_COMPLEX_TOKEN");
		['N_type_specifier', $_[1] ];
	}
	],
	[#Rule 96
		 'type_specifier', 1,
sub {
		printDebugLog("type_specifier:struct_or_union_specifier");
		undef;
	}
	],
	[#Rule 97
		 'type_specifier', 1,
sub {
		printDebugLog("type_specifier:enum_specifier");
		undef;
	}
	],
	[#Rule 98
		 'type_specifier', 1,
sub {
    	printDebugLog("type_specifier:TNAME_TOKEN");
 		['N_type_specifier', $_[1] ];
    }
	],
	[#Rule 99
		 'struct_or_union_specifier', 5,
sub {
		printDebugLog("struct_or_union_specifier:struct_or_union IDENTIFIER { struct_declaration_list }");
		undef;
	}
	],
	[#Rule 100
		 'struct_or_union_specifier', 4,
sub {
		printDebugLog("struct_or_union_specifier:struct_or_union { struct_declaration_list }");
		undef;
	}
	],
	[#Rule 101
		 'struct_or_union_specifier', 2,
sub {
		printDebugLog("struct_or_union_specifier:struct_or_union IDENTIFIER");
		undef;
	}
	],
	[#Rule 102
		 'struct_or_union', 1,
sub {
		printDebugLog("struct_or_union:STRUCT_TOKEN");
		$_[1];
	}
	],
	[#Rule 103
		 'struct_or_union', 1,
sub {
		printDebugLog("struct_or_union:UNION_TOKEN");
		$_[1];
	}
	],
	[#Rule 104
		 'struct_declaration_list', 1,
sub {
		printDebugLog("struct_declaration_list:struct_declaration");
		undef;
	}
	],
	[#Rule 105
		 'struct_declaration_list', 2,
sub {
		printDebugLog("struct_declaration_list:struct_declaration_list struct_declaration");
		undef;
	}
	],
	[#Rule 106
		 'struct_declaration', 3,
sub {
		printDebugLog("struct_declaration:specifier_qualifier_list struct_declarator_list ;");
		undef;
	}
	],
	[#Rule 107
		 'specifier_qualifier_list', 2,
sub {
		printDebugLog("specifier_qualifier_list:type_specifier specifier_qualifier_list");
		undef;
	}
	],
	[#Rule 108
		 'specifier_qualifier_list', 1,
sub {
		printDebugLog("specifier_qualifier_list:type_specifier");
		undef;
	}
	],
	[#Rule 109
		 'specifier_qualifier_list', 2,
sub {
		printDebugLog("specifier_qualifier_list:type_qualifier specifier_qualifier_list");
		undef;
	}
	],
	[#Rule 110
		 'specifier_qualifier_list', 1,
sub {
		printDebugLog("specifier_qualifier_list:type_qualifier");
		undef;
	}
	],
	[#Rule 111
		 'struct_declarator_list', 1,
sub {
		printDebugLog("struct_declarator_list:struct_declarator");
		undef;
	}
	],
	[#Rule 112
		 'struct_declarator_list', 3,
sub {
		printDebugLog("struct_declarator_list:struct_declarator_list , struct_declarator");
		undef;
	}
	],
	[#Rule 113
		 'struct_declarator', 1,
sub {
		printDebugLog("struct_declarator:declarator");
		undef;
	}
	],
	[#Rule 114
		 'struct_declarator', 3,
sub {
		printDebugLog("struct_declarator:declarator : constant_expression");
		undef;
	}
	],
	[#Rule 115
		 'struct_declarator', 2,
sub {
		printDebugLog("struct_declarator: : constant_expression");
		undef;
	}
	],
	[#Rule 116
		 'enum_specifier', 5,
sub {
		printDebugLog("enum_specifier:enum IDENTIFIER { enumerator_list }");
		undef;
	}
	],
	[#Rule 117
		 'enum_specifier', 4,
sub {
		printDebugLog("enum_specifier:enum { enumerator_list }");
		undef;
	}
	],
	[#Rule 118
		 'enum_specifier', 6,
sub {
		printDebugLog("enum_specifier:enum IDENTIFIER { enumerator_list , }");
		undef;
	}
	],
	[#Rule 119
		 'enum_specifier', 5,
sub {
		printDebugLog("enum_specifier:enum { enumerator_list , }");
		undef;
	}
	],
	[#Rule 120
		 'enum_specifier', 2,
sub {
		printDebugLog("enum_specifier:enum IDENTIFIER");
		undef;
	}
	],
	[#Rule 121
		 'enumerator_list', 1,
sub {
		printDebugLog("enumerator_list:enumerator");
		undef;
	}
	],
	[#Rule 122
		 'enumerator_list', 3,
sub {
		printDebugLog("enumerator_list:enumerator_list , enumerator");
		undef;
	}
	],
	[#Rule 123
		 'enumerator', 1,
sub {
		printDebugLog("enumerator:enumeration_constant");
		undef;
	}
	],
	[#Rule 124
		 'enumerator', 3,
sub {
		printDebugLog("enumerator:enumeration_constant ~ constant_expression");
		undef;
	}
	],
	[#Rule 125
		 'enumeration_constant', 1,
sub {
		printDebugLog("enumeration_constant:IDENTIFIER");
		$_[1];
	}
	],
	[#Rule 126
		 'type_qualifier', 1,
sub {
		printDebugLog("type_qualifier:CONST_TOKEN");
		$_[1];
	}
	],
	[#Rule 127
		 'type_qualifier', 1,
sub {
		printDebugLog("type_qualifier:RESTRICT_TOKEN");
		$_[1];
	}
	],
	[#Rule 128
		 'type_qualifier', 1,
sub {
		printDebugLog("type_qualifier:VOLATILE_TOKEN");
		$_[1];
	}
	],
	[#Rule 129
		 'function_specifier', 1,
sub {
		printDebugLog("function_specifier:INLINE_TOKEN");
		$_[1];
	}
	],
	[#Rule 130
		 'declarator', 2,
sub {
		printDebugLog("declarator:pointer direct_declarator");
        $_[2];
	}
	],
	[#Rule 131
		 'declarator', 1,
sub {
		printDebugLog("declarator:direct_declarator");
		$_[1];
	}
	],
	[#Rule 132
		 'direct_declarator', 1,
sub {
		printDebugLog("direct_declarator:IDENTIFIER");
		[['N_MetaNode', {name => $_[1]}], $_[1] ];
	}
	],
	[#Rule 133
		 'direct_declarator', 3,
sub {
		printDebugLog("direct_declarator:( declarator )");
		$_[2];
	}
	],
	[#Rule 134
		 'direct_declarator', 5,
sub {
		printDebugLog("direct_declarator:direct_declarator [ type_qualifier_list assignment_expression ]");
		my $metanode = shift @{$_[1]};
        my $decl = $metanode->[1];
        $decl->{type} = 'ARRAY';
		[ $metanode , $_[1] ];
	}
	],
	[#Rule 135
		 'direct_declarator', 4,
sub {
		printDebugLog("direct_declarator:direct_declarator [ assignment_expression ]");
		my $metanode = shift @{$_[1]};
        my $decl = $metanode->[1];
        $decl->{type} = 'ARRAY';
		[ $metanode , $_[1] ];
	}
	],
	[#Rule 136
		 'direct_declarator', 4,
sub {
		printDebugLog("direct_declarator:direct_declarator [ type_qualifier_list ]");
		my $metanode = shift @{$_[1]};
        my $decl = $metanode->[1];
        $decl->{type} = 'ARRAY';
		[ $metanode , $_[1] ];
	}
	],
	[#Rule 137
		 'direct_declarator', 3,
sub {
		printDebugLog("direct_declarator:direct_declarator[]");
		my $metanode = shift @{$_[1]};
        my $decl = $metanode->[1];
        $decl->{type} = 'ARRAY';
		[ $metanode , $_[1] ];
	}
	],
	[#Rule 138
		 'direct_declarator', 6,
sub {
		printDebugLog("direct_declarator:direct_declarator [ static type_qualifier_list assignment_expression ]");
		my $metanode = shift @{$_[1]};
        my $decl = $metanode->[1];
        $decl->{type} = 'ARRAY';
		[ $metanode , $_[1] ];
	}
	],
	[#Rule 139
		 'direct_declarator', 5,
sub {
		printDebugLog("direct_declarator:direct_declarator [ static assignment_expression ]");
		my $metanode = shift @{$_[1]};
        my $decl = $metanode->[1];
        $decl->{type} = 'ARRAY';
		[ $metanode , $_[1] ];
	}
	],
	[#Rule 140
		 'direct_declarator', 6,
sub {
		printDebugLog("direct_declarator:");
		my $metanode = shift @{$_[1]};
        my $decl = $metanode->[1];
        $decl->{type} = 'ARRAY';
		[ $metanode , $_[1] ];
	}
	],
	[#Rule 141
		 'direct_declarator', 5,
sub {
		printDebugLog("direct_declarator:direct_declarator [ type_qualifier_list * ]");
		my $metanode = shift @{$_[1]};
        my $decl = $metanode->[1];
        $decl->{type} = 'ARRAY';
		[ $metanode , $_[1] ];
	}
	],
	[#Rule 142
		 'direct_declarator', 4,
sub {
		printDebugLog("direct_declarator:direct_declarator [ * ]");
		my $metanode = shift @{$_[1]};
        my $decl = $metanode->[1];
        $decl->{type} = 'ARRAY';
		[ $metanode , $_[1] ];
	}
	],
	[#Rule 143
		 'direct_declarator', 4,
sub {
		printDebugLog("direct_declarator:direct_declarator ( parameter_type_list )");
		[ $_[1] , [] ];
	}
	],
	[#Rule 144
		 'direct_declarator', 4,
sub {
		printDebugLog("direct_declarator:direct_declarator ( identifier_list )");
		[ $_[1] , [] ];
	}
	],
	[#Rule 145
		 'direct_declarator', 3,
sub {
		printDebugLog("direct_declarator:direct_declarator ( )");
		[ $_[1] , [] ];
	}
	],
	[#Rule 146
		 'pointer', 2,
sub {
		printDebugLog("pointer: * type_qualifier_list");
		undef;
	}
	],
	[#Rule 147
		 'pointer', 1,
sub {
		printDebugLog("pointer: * ");
		undef;
	}
	],
	[#Rule 148
		 'pointer', 3,
sub {
		printDebugLog("pointer: * type_qualifier_list pointer");
		undef;
	}
	],
	[#Rule 149
		 'pointer', 2,
sub {
		printDebugLog("pointer: * pointer");
		undef;
	}
	],
	[#Rule 150
		 'type_qualifier_list', 1,
sub {
		printDebugLog("type_qualifier_list:type_qualifier");
		undef;
	}
	],
	[#Rule 151
		 'type_qualifier_list', 2,
sub {
		printDebugLog("type_qualifier_list:type_qualifier_list type_qualifier");
		undef;
	}
	],
	[#Rule 152
		 'parameter_type_list', 1,
sub {
		printDebugLog("parameter_type_list:parameter_list");
		undef;
	}
	],
	[#Rule 153
		 'parameter_type_list', 3,
sub {
		printDebugLog("parameter_type_list:parameter_list , ...");
		undef;
	}
	],
	[#Rule 154
		 'parameter_list', 1,
sub {
		printDebugLog("parameter_list:parameter_declaration");
		undef;
	}
	],
	[#Rule 155
		 'parameter_list', 3,
sub {
		printDebugLog("parameter_list:parameter_list , parameter_declaration");
		undef;
	}
	],
	[#Rule 156
		 'parameter_declaration', 2,
sub {
		printDebugLog("parameter_declaration:declaration_specifiers declarator");
		undef;
	}
	],
	[#Rule 157
		 'parameter_declaration', 2,
sub {
		printDebugLog("parameter_declaration:declaration_specifiers abstract_declarator");
		undef;
	}
	],
	[#Rule 158
		 'parameter_declaration', 1,
sub {
		printDebugLog("parameter_declaration:declaration_specifiers");
		undef;
	}
	],
	[#Rule 159
		 'identifier_list', 1,
sub {
		printDebugLog("identifier_list:IDENTIFIER");
		undef;
	}
	],
	[#Rule 160
		 'identifier_list', 3,
sub {
		printDebugLog("identifier_list:identifier_list , IDENTIFIER");
		undef;
	}
	],
	[#Rule 161
		 'type_name', 2,
sub {
		printDebugLog("type_name:speficier_qualifier_list abstract_declarator");
		undef;
	}
	],
	[#Rule 162
		 'type_name', 1,
sub {
		printDebugLog("type_name:speficier_qualifier_list");
		undef;
	}
	],
	[#Rule 163
		 'abstract_declarator', 1,
sub {
		printDebugLog("abstract_declarator:pointer");
		undef;
	}
	],
	[#Rule 164
		 'abstract_declarator', 2,
sub {
		printDebugLog("abstract_declarator:pointer direct_abstract_declarator");
		undef;
	}
	],
	[#Rule 165
		 'abstract_declarator', 1,
sub {
		printDebugLog("abstract_declarator:direct_abstract_declarator");
		undef;
	}
	],
	[#Rule 166
		 'direct_abstract_declarator', 3,
sub {
		printDebugLog("direct_abstract_declarator: ( abstract_declarator )");
		undef;
	}
	],
	[#Rule 167
		 'direct_abstract_declarator', 2,
sub {
		printDebugLog("direct_abstract_declarator: [ ]");
		undef;
	}
	],
	[#Rule 168
		 'direct_abstract_declarator', 3,
sub {
		printDebugLog("direct_abstract_declarator: direct_abstract_declarator [ ]");
		undef;
	}
	],
	[#Rule 169
		 'direct_abstract_declarator', 3,
sub {
		printDebugLog("direct_abstract_declarator: [ assignment_expression ]");
		undef;
	}
	],
	[#Rule 170
		 'direct_abstract_declarator', 4,
sub {
		printDebugLog("direct_abstract_declarator: direct_abstract_declarator [ assignment_expression ]");
		undef;
	}
	],
	[#Rule 171
		 'direct_abstract_declarator', 4,
sub {
		printDebugLog("direct_abstract_declarator: direct_abstract_declarator [ * ]");
		undef;
	}
	],
	[#Rule 172
		 'direct_abstract_declarator', 3,
sub {
		printDebugLog("direct_abstract_declarator: [ * ]");
		undef;
	}
	],
	[#Rule 173
		 'direct_abstract_declarator', 2,
sub {
		printDebugLog("direct_abstract_declarator: ( )");
		undef;
	}
	],
	[#Rule 174
		 'direct_abstract_declarator', 3,
sub {
		printDebugLog("direct_abstract_declarator: ( parameter_type_list )");
		undef;
	}
	],
	[#Rule 175
		 'direct_abstract_declarator', 3,
sub {
		printDebugLog("direct_abstract_declarator: direct_abstract_declarator ( )");
		undef;
	}
	],
	[#Rule 176
		 'direct_abstract_declarator', 4,
sub {
		printDebugLog("direct_abstract_declarator: direct_abstract_declarator ( parameter_type_list )");
		undef;
	}
	],
	[#Rule 177
		 'initializer', 1,
sub {
		printDebugLog("initializer:assignment_expression");
		$_[1];
	}
	],
	[#Rule 178
		 'initializer', 3,
sub {	
		printDebugLog("initializer:{ initializer_list }");
        defined $_[2] ? ['N_ScopeInfo', create_scopeinfo($_[2])] : undef
	}
	],
	[#Rule 179
		 'initializer', 4,
sub {
		printDebugLog("initializer:{ initializer_list , }");
		defined $_[2] ? ['N_ScopeInfo', create_scopeinfo($_[2])] : undef
	}
	],
	[#Rule 180
		 'initializer_list', 2,
sub {
		printDebugLog("initializer_list:designation initializer");
		undef;
	}
	],
	[#Rule 181
		 'initializer_list', 1,
sub {
		printDebugLog("initializer_list:initializer");
		['N_initializer_list', $_[1]];
	}
	],
	[#Rule 182
		 'initializer_list', 4,
sub {
		printDebugLog("initializer_list:initializer_list , designation initializer");
		undef;
	}
	],
	[#Rule 183
		 'initializer_list', 3,
sub {
		printDebugLog("initializer_list:initializer_list , initializer");
        push(@{$_[1]}, $_[2], $_[3]);
        $_[1];
	}
	],
	[#Rule 184
		 'designation', 2,
sub {
		printDebugLog("designation:designator_list =");
		undef;
	}
	],
	[#Rule 185
		 'designator_list', 1,
sub {
		printDebugLog("designator_list:designator");
		undef;
	}
	],
	[#Rule 186
		 'designator_list', 2,
sub {
		printDebugLog("designator_list:designator_list designator");
		undef;
	}
	],
	[#Rule 187
		 'designator', 3,
sub {
		printDebugLog("designator: [ constant_expression ]");
		undef;
	}
	],
	[#Rule 188
		 'designator', 2,
sub {
		printDebugLog("designator: . IDENTIFIER");
		undef;
	}
	],
	[#Rule 189
		 'statement', 1,
sub {
		printDebugLog("statement:labeled_statement");
		$_[1];
	}
	],
	[#Rule 190
		 'statement', 1,
sub {
		printDebugLog("statement:compound_statement");
		$_[1];
	}
	],
	[#Rule 191
		 'statement', 1,
sub {
		printDebugLog("statement:expression_statement");
		$_[1];
	}
	],
	[#Rule 192
		 'statement', 1,
sub {
		printDebugLog("statement:selection_statement");
		$_[1];
	}
	],
	[#Rule 193
		 'statement', 1,
sub {
		printDebugLog("statement:iteration_statement");
		$_[1];
	}
	],
	[#Rule 194
		 'statement', 1,
sub {
		printDebugLog("statement:jump_statement");
		$_[1];
	}
	],
	[#Rule 195
		 'statement', 1,
sub {
		printDebugLog("statement:embedded_sql");
		$_[1];
	}
	],
	[#Rule 196
		 'labeled_statement', 3,
sub {
		printDebugLog("labeled_statment: IDENTIFIER : statement");
        $_[3];
	}
	],
	[#Rule 197
		 'labeled_statement', 4,
sub {
		printDebugLog("labeled_statment: case constant_expression : statement");

		if(defined $_[4]){
			shift @{$_[4]};
        	my $first_block_stmt = shift @{$_[4]};
        	[ 'stmt', [ 'N_SwitchLabel', create_linenode($_[1]),  $first_block_stmt ], @{$_[4]} ];
		} 
		else{
			['line', create_linenode($_[1])];
		}
	}
	],
	[#Rule 198
		 'labeled_statement', 3,
sub {
		printDebugLog("labeled_statment: default : statement");
		if(defined $_[3]){
			shift @{$_[3]};
        	my $first_block_stmt = shift @{$_[3]};
        	[ 'stmt', [ 'N_SwitchLabel', create_linenode($_[1]),  $first_block_stmt ], @{$_[3]} ];
		} 
		else{
			['line', create_linenode($_[1])];
		}
	}
	],
	[#Rule 199
		 'compound_statement', 2,
sub {
		printDebugLog("compound_statement: { }");
		[ 'N_ScopeInfo' , create_scopeinfo(['N_block_item_list'])];
	}
	],
	[#Rule 200
		 'compound_statement', 3,
sub {
		printDebugLog("compound_statement: { block_item_list }");
		[ 'N_ScopeInfo' , create_scopeinfo($_[2])];
	}
	],
	[#Rule 201
		 'block_item_list', 1,
sub {
		printDebugLog("block_item_list:block_item");
        my $blockitemlist = ['N_block_item_list'];
        defined $_[1] and push(@{$blockitemlist}, $_[1]);
        $blockitemlist;
	}
	],
	[#Rule 202
		 'block_item_list', 2,
sub {
		printDebugLog("block_item_list:block_item_list block_item");
        defined $_[2] and push(@{$_[1]}, $_[2]);
        $_[1];
	}
	],
	[#Rule 203
		 'block_item', 1,
sub {
		printDebugLog("block_item:declaration");
        
        my $memberdecl = $_[1];
		
		if(exists($memberdecl->{VARIABLE})) {
			
			my $type         = $memberdecl->{VARIABLE}->[0];
       		my $variabledecl = $memberdecl->{VARIABLE}->[1];
            
            my @varlist = ();
            for my $current_vardecl (@{$variabledecl}) {
            
                my $decl = refer_metanode($current_vardecl);
                
                if(defined $decl) {
 		            my $varinfo = create_VariableInfo($decl->{name}, $type, $decl->{type}, $decl->{value});
                    push(@varlist, $varinfo);
                }
            }
            undef $memberdecl->{VARIABLE};
            $memberdecl->{VARIABLE} = \@varlist;
            $memberdecl;

        }
		else{
			undef;
		}
		
	}
	],
	[#Rule 204
		 'block_item', 1,
sub {
		printDebugLog("block_item:statement");
		$_[1];
	}
	],
	[#Rule 205
		 'expression_statement', 2,
sub {
		printDebugLog("expression_statement: expression ;");
		$_[1];
	}
	],
	[#Rule 206
		 'expression_statement', 1,
sub {
		printDebugLog("expression_statement: ;");
		undef;
	}
	],
	[#Rule 207
		 'selection_statement', 5,
sub {
		printDebugLog("selection_statement: if ( expression ) statement");
		 ['N_if', create_linenode($_[1]),  ['N_ParExpression', $_[3]], ['N_Delimiter'], $_[5]];
	}
	],
	[#Rule 208
		 'selection_statement', 7,
sub {
		printDebugLog("selection_statement: if ( expression ) statement else statement");
		 ['N_if', create_linenode($_[1]), ['N_ParExpression', $_[3]] , ['N_Delimiter'], $_[5], ['N_Delimiter'], ['N_else', create_addcode(), create_linenode($_[6]), $_[7]]];
	}
	],
	[#Rule 209
		 'selection_statement', 5,
sub {
		printDebugLog("selection_statement: switch ( expression ) statement");
		 ['N_switch',  create_linenode($_[1]), ['N_ParExpression', $_[3]] , $_[5]];
	}
	],
	[#Rule 210
		 'iteration_statement', 5,
sub {
		printDebugLog("iteration_statement: while ( expression ) statement");
		['N_while', create_linenode($_[1]), ['N_ParExpression', $_[3]] , ['N_Delimiter'], $_[5]];
	}
	],
	[#Rule 211
		 'iteration_statement', 7,
sub {
		printDebugLog("iteration_statement: do statement while ( expression ) ;");
		['N_while', create_linenode($_[1]), $_[2], ['N_Delimiter'], create_addcode(), create_linenode($_[3]), ['N_ParExpression', $_[5]]];
	}
	],
	[#Rule 212
		 'iteration_statement', 6,
sub {
		printDebugLog("iteration_statement: for ( ; ; ) statement");
        ['N_for', create_linenode($_[1]),  undef, ['N_Delimiter'], $_[6]];
	}
	],
	[#Rule 213
		 'iteration_statement', 7,
sub {
		printDebugLog("iteration_statement: for ( expression ; ; ) statement");
        my @result_forcontrol = ('N_ForControl');
        my @result_forinit = ('N_ForInit');
        defined $_[3] and do { push(@result_forinit, $_[3]);  };
        defined $_[3] and do { push(@result_forcontrol, \@result_forinit);  };
        ['N_for', create_linenode($_[1]), \@result_forcontrol , ['N_Delimiter'], $_[7]];
	}
	],
	[#Rule 214
		 'iteration_statement', 7,
sub {
		printDebugLog("iteration_statement: for ( ; expression ; ) statement");
        my @result_forcontrol = ('N_ForControl');
        defined $_[4] and do { push(@result_forcontrol, create_addcode()); push(@result_forcontrol, $_[4]);  };
        ['N_for', create_linenode($_[1]), \@result_forcontrol , ['N_Delimiter'], $_[7]];
	}
	],
	[#Rule 215
		 'iteration_statement', 7,
sub {
		printDebugLog("iteration_statement: for ( ; ; expression ) statement");
        my @result_forcontrol = ('N_ForControl');
        my @result_forupdate = ('N_ForUpdate');
        defined $_[5] and do { push(@result_forupdate, $_[5]);  };
        defined $_[5] and do { push(@result_forcontrol, create_addcode()); push(@result_forcontrol, \@result_forupdate);  };
        ['N_for', create_linenode($_[1]), \@result_forcontrol , ['N_Delimiter'], $_[7]];
	}
	],
	[#Rule 216
		 'iteration_statement', 8,
sub {
		printDebugLog("iteration_statement: for ( ; expression ; expression ) statement");
        my @result_forcontrol = ('N_ForControl');
        my @result_forupdate = ('N_ForUpdate');
        defined $_[6] and do { push(@result_forupdate, $_[6]);  };
        defined $_[4] and do { push(@result_forcontrol, create_addcode()); push(@result_forcontrol, $_[4]);  };
        defined $_[6] and do { push(@result_forcontrol, create_addcode()); push(@result_forcontrol, \@result_forupdate);  };
        ['N_for', create_linenode($_[1]), \@result_forcontrol , ['N_Delimiter'], $_[8]];
	}
	],
	[#Rule 217
		 'iteration_statement', 8,
sub {
		printDebugLog("iteration_statement: for ( expression ; ; expression ) statement");
        my @result_forcontrol = ('N_ForControl');
        my @result_forinit = ('N_ForInit');
        my @result_forupdate = ('N_ForUpdate');
        defined $_[3] and do { push(@result_forinit, $_[3]);  };
        defined $_[6] and do { push(@result_forupdate, $_[6]);  };
        defined $_[3] and do { push(@result_forcontrol, \@result_forinit);  };
        defined $_[6] and do { push(@result_forcontrol, create_addcode()); push(@result_forcontrol, \@result_forupdate);  };
        ['N_for', create_linenode($_[1]), \@result_forcontrol , ['N_Delimiter'], $_[8]];
	}
	],
	[#Rule 218
		 'iteration_statement', 8,
sub {
		printDebugLog("iteration_statement: for ( expression ; expression ; ) statement");
        my @result_forcontrol = ('N_ForControl');
        my @result_forinit = ('N_ForInit');
        defined $_[3] and do { push(@result_forinit, $_[3]);  };
        defined $_[3] and do { push(@result_forcontrol, \@result_forinit);  };
        defined $_[5] and do { push(@result_forcontrol, create_addcode()); push(@result_forcontrol, $_[5]);  };
        ['N_for', create_linenode($_[1]), \@result_forcontrol , ['N_Delimiter'], $_[8]];
	}
	],
	[#Rule 219
		 'iteration_statement', 9,
sub {
		printDebugLog("iteration_statement: for ( expression ; expression ; expression ) statement");
        my @result_forcontrol = ('N_ForControl');
        my @result_forinit = ('N_ForInit');
        my @result_forupdate = ('N_ForUpdate');
        defined $_[3] and do { push(@result_forinit, $_[3]);  };
        defined $_[7] and do { push(@result_forupdate, $_[7]);  };
        defined $_[3] and do { push(@result_forcontrol, \@result_forinit);  };
        defined $_[5] and do { push(@result_forcontrol, create_addcode()); push(@result_forcontrol, $_[5]);  };
        defined $_[7] and do { push(@result_forcontrol, create_addcode()); push(@result_forcontrol, \@result_forupdate);  };
        ['N_for', create_linenode($_[1]), \@result_forcontrol , ['N_Delimiter'], $_[9]];
	}
	],
	[#Rule 220
		 'iteration_statement', 8,
sub {
		printDebugLog("iteration_statement: for ( declaration expression ; expression ) statement");
        my @result_forupdate = ('N_ForUpdate');
        my $result_forvar = undef;
        
        defined $_[6] and do { push(@result_forupdate, $_[6]);  };
        
        if(defined $_[3]->{VARIABLE}){
        	my $result_forvar_1 = $_[3]->{VARIABLE}->[0];
        	my $result_forvar_2 = [ 'N_NormalFor' , $_[3]->{VARIABLE}->[1] , $_[4] , \@result_forupdate ];
        	$result_forvar = create_forvar_control($result_forvar_1, $result_forvar_2);
        }
        
        ['N_for' , create_linenode($_[1]), $result_forvar , ['N_Delimiter'], $_[8]];
	}
	],
	[#Rule 221
		 'iteration_statement', 7,
sub {
		printDebugLog("iteration_statement: for ( declaration ; expression ) statement");
        my @result_forupdate = ('N_ForUpdate');
        my $result_forvar = undef;
        
        defined $_[5] and do { push(@result_forupdate, $_[5]);  };
        
        if(defined $_[3]->{VARIABLE}){
        	my $result_forvar_1 = $_[3]->{VARIABLE}->[0];
        	my $result_forvar_2 = [ 'N_NormalFor' , $_[3]->{VARIABLE}->[1] , undef , \@result_forupdate ];
        	$result_forvar = create_forvar_control($result_forvar_1, $result_forvar_2);
        }
        
        ['N_for' , create_linenode($_[1]), $result_forvar , ['N_Delimiter'], $_[7]];
	}
	],
	[#Rule 222
		 'iteration_statement', 7,
sub {
		printDebugLog("iteration_statement: for ( declaration expression ; ) statement");
        my $result_forvar = undef;
        
        if(defined $_[3]->{VARIABLE}){
        	my $result_forvar_1 = $_[3]->{VARIABLE}->[0];
        	my $result_forvar_2 = [ 'N_NormalFor' , $_[3]->{VARIABLE}->[1] , $_[4] , undef ];
        	$result_forvar = create_forvar_control($result_forvar_1, $result_forvar_2);
        }
        
        ['N_for' , create_linenode($_[1]), $result_forvar , ['N_Delimiter'], $_[7]];
	}
	],
	[#Rule 223
		 'iteration_statement', 6,
sub {
		printDebugLog("iteration_statement: for ( declaration ; ) statement");
        my $result_forvar = undef;
        
        if(defined $_[3]->{VARIABLE}){
        	my $result_forvar_1 = $_[3]->{VARIABLE}->[0];
        	my $result_forvar_2 = [ 'N_NormalFor' , $_[3]->{VARIABLE}->[1] , undef , undef ];
        	$result_forvar = create_forvar_control($result_forvar_1, $result_forvar_2);
        }
        
        ['N_for' , create_linenode($_[1]), $result_forvar , ['N_Delimiter'], $_[7]];
	}
	],
	[#Rule 224
		 'jump_statement', 3,
sub {
		printDebugLog("jump_statement: goto IDENTIFIER ;");
		undef;
	}
	],
	[#Rule 225
		 'jump_statement', 2,
sub {
		printDebugLog("jump_statement: continue ;");
		undef;
	}
	],
	[#Rule 226
		 'jump_statement', 2,
sub {
		printDebugLog("jump_statement: break ;");
		undef;
	}
	],
	[#Rule 227
		 'jump_statement', 3,
sub {
		printDebugLog("jump_statement: return expression ;");
		['N_return',  create_linenode($_[1]), $_[2]];
	}
	],
	[#Rule 228
		 'jump_statement', 2,
sub {
		printDebugLog("jump_statement: return ;");
		undef;
	}
	],
	[#Rule 229
		 'translation_unit', 0, undef
	],
	[#Rule 230
		 'translation_unit', 1,
sub {
		printDebugLog("translation_unit:external_declaration");
		if(defined $_[1]) {
            if(ref($_[1]) eq "HASH" && exists($_[1]->{VARIABLE})) {
                $G_fileinfo_ref->varlist($_[1]->{VARIABLE});
            }
    		if(ref($_[1]) eq "HASH" && exists($_[1]->{FUNCTION})) {
            	push(@{$G_fileinfo_ref->functionlist()}, $_[1]->{FUNCTION});
            }
        }
        $G_fileinfo_ref
	}
	],
	[#Rule 231
		 'translation_unit', 2,
sub {
		printDebugLog("translation_unit:translation_unit external_declaration");
		if(defined $_[2]) {
            if(ref($_[2]) eq "HASH" && exists($_[2]->{VARIABLE})) {
                push(@{$G_fileinfo_ref->varlist()}, @{$_[2]->{VARIABLE}});
            }
    		if(ref($_[2]) eq "HASH" && exists($_[2]->{FUNCTION})) {
            	push(@{$G_fileinfo_ref->functionlist()}, $_[2]->{FUNCTION});
            }
        }
        $G_fileinfo_ref
	}
	],
	[#Rule 232
		 'external_declaration', 1,
sub {
		printDebugLog("external_declaration:function_definition");
		if(defined $_[1]) {
            $_[1];
        }else{
            undef;
        }
	}
	],
	[#Rule 233
		 'external_declaration', 1,
sub {
		printDebugLog("external_declaration:declaration");

		my $memberdecl = $_[1];
		
		if(ref($memberdecl) eq "HASH" && exists($memberdecl->{VARIABLE})) {
			
			my $type         = $memberdecl->{VARIABLE}->[0];
       		my $variabledecl = $memberdecl->{VARIABLE}->[1];
            
            my @varlist = ();
            for my $current_vardecl (@{$variabledecl}) {
            
                my $decl = refer_metanode($current_vardecl);
                
                if(defined $decl) {
 		            my $varinfo = create_VariableInfo($decl->{name}, $type, $decl->{type}, $decl->{value});
                    push(@varlist, $varinfo);
                }
            }
            undef $memberdecl->{VARIABLE};
            $memberdecl->{VARIABLE} = \@varlist;
            $memberdecl;
            
        }
        else{
			undef;
		}
        
	}
	],
	[#Rule 234
		 'external_declaration', 1,
sub {
		printDebugLog("external_declaration:embedded_sql");
		$_[1];
	}
	],
	[#Rule 235
		 'function_definition', 3,
sub {
		printDebugLog("function_definition:declaration_specifiers declarator compund_statement");
		my $method_decl = {TYPELIST => $_[2]->[1] , FUNCTIONNAME => $_[2]->[0]->[0]->[1]->{name}->{TOKEN}};
        $method_decl->{SCOPE} = $_[3];
		my $result = create_functioninfo($method_decl->{FUNCTIONNAME}, $method_decl->{SCOPE});
        if (defined $result){
            {FUNCTION => $result};
        }else{
            undef;
        }
	}
	],
	[#Rule 236
		 'function_definition', 4,
sub {
		printDebugLog("function_definition:declaration_specifiers declarator declaration_list compund_statement");
		my $method_decl = {TYPELIST => $_[2]->[1] , FUNCTIONNAME => $_[2]->[0]->[0]->[1]->{name}->{TOKEN}};
        $method_decl->{SCOPE} = $_[4];
		my $result = create_functioninfo($method_decl->{FUNCTIONNAME}, $method_decl->{SCOPE});
        if (defined $result){
            {FUNCTION => $result};
        }else{
            undef;
        }
	}
	],
	[#Rule 237
		 'declaration_list', 1,
sub {
		printDebugLog("declaration_list:declaration");
		undef;
	}
	],
	[#Rule 238
		 'declaration_list', 2,
sub {
		printDebugLog("declaration_list:declaration_list declaration");
		undef;
	}
	],
	[#Rule 239
		 'embedded_sql', 4,
sub {
		printDebugLog("embedded_sql:EXEC SQL emb_declare ;");
		undef;
	}
	],
	[#Rule 240
		 'embedded_sql', 4,
sub {
		printDebugLog("embedded_sql:EXEC SQL emb_string_list ;");
		my @result;
		push( @result , $_[1]);
		push( @result , $_[2]);
		push( @result , $_[3]);
		push( @result , $_[4]);
		\@result;
	}
	],
	[#Rule 241
		 'embedded_sql', 4,
sub {
		printDebugLog("embedded_sql:EXEC ORACLE emb_string_list ;");
		undef;
	}
	],
	[#Rule 242
		 'embedded_sql', 4,
sub {
		printDebugLog("embedded_sql:EXEC TOOLS emb_string_list ;");
		undef;
	}
	],
	[#Rule 243
		 'emb_declare', 3,
sub {
        $G_declaresection_flg=1;#ホスト宣言内のフラグを真に
		printDebugLog("emb_declare:BEGIN DECLARE SECTION");
		undef;
	}
	],
	[#Rule 244
		 'emb_declare', 3,
sub {
        $G_declaresection_flg=0;#ホスト宣言内のフラグを偽に
		printDebugLog("emb_declare:END DECLARE SECTION");
		undef;
	}
	],
	[#Rule 245
		 'emb_string_list', 1,
sub {
		printDebugLog("emb_string_list:emb_constant_string");
        my $current_line;
        if( ref($_[1]) eq "HASH" ){
            $current_line=$_[1]->{LINE};
        }else{
            $current_line=$_[1]-[1]->{LINE};
        }
		if( $G_ansi_comment_line == $current_line ){
            undef;
        }else{
            [ $_[1] ];
        }
	}
	],
	[#Rule 246
		 'emb_string_list', 2,
sub {
		printDebugLog("emb_string_list:emb_string_list emb_constant_string");
        my $current_line;
        if( ref($_[2]) eq "HASH" ){
            $current_line=$_[2]->{LINE};
        }else{
            $current_line=$_[2]->[1]->{LINE};
        }
		if( $G_ansi_comment_line == $current_line ){
    		$_[1];
        }else{
    		push( @{$_[1]} , $_[2]);
    		$_[1];
        }
	}
	],
	[#Rule 247
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:IDENTIFIER_ORG");
		 $_[1];
	}
	],
	[#Rule 248
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:FLOAT_LITERAL");
		 $_[1];
	}
	],
	[#Rule 249
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:INTEGER_LITERAL");
		 $_[1];
	}
	],
	[#Rule 250
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:CHAR_LITERAL");
		 $_[1];
	}
	],
	[#Rule 251
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:STRING_LITERAL");
		 $_[1];
	}
	],
	[#Rule 252
		 'emb_constant_string', 2,
sub {
		printDebugLog("emb_constant_string: : IDENTIFIER_ORG");
		[ $_[1] , $_[2] ];
	}
	],
	[#Rule 253
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:DECLARE");
		 $_[1];
	}
	],
	[#Rule 254
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:do");
		 $_[1];
	}
	],
	[#Rule 255
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:break");
		 $_[1];
	}
	],
	[#Rule 256
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:continue");
		 $_[1];
	}
	],
	[#Rule 257
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:goto");
		 $_[1];
	}
	],
	[#Rule 258
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:unary_operator:&,*,+,-,!~");
		$_[1];
	}
	],
	[#Rule 259
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:=");
		 $_[1];
	}
	],
	[#Rule 260
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:(");
		 $_[1];
	}
	],
	[#Rule 261
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:)");
		 $_[1];
	}
	],
	[#Rule 262
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:;");
		 $_[1];
	}
	],
	[#Rule 263
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:,");
		 $_[1];
	}
	],
	[#Rule 264
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:.");
		 $_[1];
	}
	],
	[#Rule 265
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:?");
		 $_[1];
	}
	],
	[#Rule 266
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:>");
		 $_[1];
	}
	],
	[#Rule 267
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:<");
		 $_[1];
	}
	],
	[#Rule 268
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:[<>]=");
		 $_[1];
	}
	],
	[#Rule 269
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:_Bool");
		 $_[1];
	}
	],
	[#Rule 270
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:_Complex");
		 $_[1];
	}
	],
	[#Rule 271
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:_Imaginary");
		 $_[1];
	}
	],
	[#Rule 272
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:auto");
		 $_[1];
	}
	],
	[#Rule 273
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:case");
		 $_[1];
	}
	],
	[#Rule 274
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:char");
		 $_[1];
	}
	],
	[#Rule 275
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:const");
		 $_[1];
	}
	],
	[#Rule 276
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:default");
		 $_[1];
	}
	],
	[#Rule 277
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:double");
		 $_[1];
	}
	],
	[#Rule 278
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:else");
		 $_[1];
	}
	],
	[#Rule 279
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:enum");
		 $_[1];
	}
	],
	[#Rule 280
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:extern");
		 $_[1];
	}
	],
	[#Rule 281
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:float");
		 $_[1];
	}
	],
	[#Rule 282
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:for");
		 $_[1];
	}
	],
	[#Rule 283
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:if");
		 $_[1];
	}
	],
	[#Rule 284
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:inline");
		 $_[1];
	}
	],
	[#Rule 285
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:int");
		 $_[1];
	}
	],
	[#Rule 286
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:long");
		 $_[1];
	}
	],
	[#Rule 287
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:new");
		 $_[1];
	}
	],
	[#Rule 288
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:private");
		 $_[1];
	}
	],
	[#Rule 289
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:protected");
		 $_[1];
	}
	],
	[#Rule 290
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:public");
		 $_[1];
	}
	],
	[#Rule 291
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:register");
		 $_[1];
	}
	],
	[#Rule 292
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:restrict");
		 $_[1];
	}
	],
	[#Rule 293
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:return");
		 $_[1];
	}
	],
	[#Rule 294
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:short");
		 $_[1];
	}
	],
	[#Rule 295
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:signed");
		 $_[1];
	}
	],
	[#Rule 296
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:sizeof");
		 $_[1];
	}
	],
	[#Rule 297
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:static");
		 $_[1];
	}
	],
	[#Rule 298
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:struct");
		 $_[1];
	}
	],
	[#Rule 299
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:switch");
		 $_[1];
	}
	],
	[#Rule 300
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:typedef");
		 $_[1];
	}
	],
	[#Rule 301
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:union");
		 $_[1];
	}
	],
	[#Rule 302
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:unsigned");
		 $_[1];
	}
	],
	[#Rule 303
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:volatile");
		 $_[1];
	}
	],
	[#Rule 304
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:void");
		 $_[1];
	}
	],
	[#Rule 305
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:while");
		 $_[1];
	}
	],
	[#Rule 306
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:begin");
		 $_[1];
	}
	],
	[#Rule 307
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:end");
		 $_[1];
	}
	],
	[#Rule 308
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:@");
		 $_[1];
	}
	],
	[#Rule 309
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:TNAME_TOKEN");
		 $_[1];
	}
	],
	[#Rule 310
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:(++|--)");
		$G_ansi_comment_line=$_[1]->{LINE};
        $_[1];
	}
	],
	[#Rule 311
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:[!|=]=");
        $_[1];
	}
	],
	[#Rule 312
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:(! *=,/=,%=,-=,<<=,>>=,&=,^=,|=)");
        $_[1];
	}
	],
	[#Rule 313
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:||");
        $_[1];
	}
	],
	[#Rule 314
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:<>");
        $_[1];
	}
	],
	[#Rule 315
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:[");
        $_[1];
	}
	],
	[#Rule 316
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:]");
        $_[1];
	}
	],
	[#Rule 317
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:/");
        $_[1];
	}
	],
	[#Rule 318
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:exec");
		 $_[1];
	}
	],
	[#Rule 319
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:->");
		 $_[1];
	}
	],
	[#Rule 320
		 'IDENTIFIER', 1, undef
	],
	[#Rule 321
		 'IDENTIFIER', 1, undef
	],
	[#Rule 322
		 'IDENTIFIER', 1, undef
	],
	[#Rule 323
		 'IDENTIFIER', 1, undef
	],
	[#Rule 324
		 'IDENTIFIER', 1, undef
	],
	[#Rule 325
		 'IDENTIFIER', 1, undef
	],
	[#Rule 326
		 'IDENTIFIER', 1, undef
	],
	[#Rule 327
		 'IDENTIFIER', 1, undef
	],
	[#Rule 328
		 'IDENTIFIER', 1, undef
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
    if(!defined $curval->{LINE}) {
        $curval->{LINE}=0;
    }
    if(!defined $curval->{TOKEN}) {
        $curval->{TOKEN}="";
    }
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

	# Parser プロト確認用。SQL抽出に埋め込むときに削除すること！
#	set_loglevel(7);

	$G_static_number = 0;
	$G_fileinfo_ref = CFileInfo->new();
	@G_classname_ident = ();

	$lex->setTarget($self->{YYData}->{INPUT});
	defined($self->{YYData}->{loglevel}) and  $self->{YYData}->{loglevel} > 10
					and $parser_debug_flg = 0x1F;
	$lex->setDebugMode($parser_debug_flg);

	$self->YYParse( yylex => \&_Lexer, yyerror => \&_Error, yydebug => $parser_debug_flg);
}

#####################################################################
# Function: printDebugLog
#
# 概要:
# Parserのデバッグ情報を(DEBUG 7)として標準エラー出力に出力する
#
# パラメータ:
# 引数をそのままprintfに引き渡す
# フォーマットの指定は不可
#
# 戻り値:
# なし
#
# 例外:
# なし
#
# 特記事項:
# なし
#
#####################################################################
sub printDebugLog {
	my ($log) = @_; # 引数の格納
	get_loglevel() > 6 and printf(STDERR "%s (DEBUG7) %s\n", get_localtime(), $log);
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
        croak "Parse error %%s :-- (unkown node in scantree)\n";
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
        # 当該トークン(ノード)が変数情報の場合は、そのトークン
        # に対する変数情報をスコープ情報に格納する
        elsif(ref($node) eq 'HASH' and exists $node->{VARIABLE}){

        	push(@{$scope_info->varlist()} , @{$node->{VARIABLE}});
        	
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
    # （C言語版では処理を行わない）
    #
    #if(defined($typetype) and $typetype eq 'ARRAY') {
    #    $typename = $typename . '[]';
    #}
	#

    my $declarationType = 0;

    #
    # ホスト変数宣言内の場合、フラグを真にする
    #
    if($G_declaresection_flg) {
        $declarationType = int($declarationType) | TYPE_HOST;
    }

    my $var_info = CVariableInfo->new(name => $name->{TOKEN}, type => $typename, linenumber => $line, declarationType => $declarationType);

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
# Function: create_functioninfo
#
#
# 概要:
# メソッド情報を新規に生成する。
#
# パラメータ:
# name      - メソッド名
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
sub create_functioninfo {
    my ($name, $scope) = @_;
    
    my $function = FunctionInfo->new();
    $function->functionname($name);
    $function->rootscope_ref($scope->[1]);
    
    return $function;
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
# N_ForControlノードを生成し、返却する。
#
# パラメータ:
# type - PrimaryTypeの内容
# rest - ForVarControlRestの内容
# 
#
# 戻り値:
# N_ForControlノード
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
    my $for_init = ['N_forInit', $type, $rest->[1]];
    my $for_ctrl = ['N_ForControl', $for_init, create_addcode(), $rest->[2], create_addcode(), $rest->[3]];
    $for_ctrl
}

1;
