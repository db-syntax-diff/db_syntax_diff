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
#! 再帰Parserのために追加したもの
#!
use PgSqlExtract::Analyzer::CParser;
use PgSqlExtract::Analyzer::PreprocessAnalyzer;
my $G_file_name = ""; #! Analyzer.pmで実施していた抽出した変数の行数にファイル名を付与するために追加。
my %G_parent_include_filename = (); #! key:子includefile_name  value:親includefile_name
my $G_fileinfo_ref_tmp = CFileInfo->new(); #! $G_fileinfo_refの退避用の構造体。関数内Include対応として追加

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
		typedef	union		unsigned	void		volatile	while		includefordbsyntaxdiff
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
)
;

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
			'VOLATILE_TOKEN' => 22,
			'EXTERN_TOKEN' => 3,
			'SHORT_TOKEN' => 2,
			'ENUM_TOKEN' => 1,
			'LONG_TOKEN' => 5,
			'VOID_TOKEN' => 24,
			'DOUBLE_TOKEN' => 26,
			'INCLUDEFORDBSYNTAXDIFF_TOKEN' => 6,
			'INT_TOKEN' => 28,
			'_BOOL_TOKEN' => 29,
			'INLINE_TOKEN' => 9,
			'TYPEDEF_TOKEN' => 31,
			'EXEC_TOKEN' => 33,
			'_COMPLEX_TOKEN' => 34,
			'SIGNED_TOKEN' => 13,
			'CHAR_TOKEN' => 14,
			'REGISTER_TOKEN' => 36,
			'CONST_TOKEN' => 15,
			'RESTRICT_TOKEN' => 37,
			'UNION_TOKEN' => 38,
			'STRUCT_TOKEN' => 16,
			'STATIC_TOKEN' => 39,
			'TNAME_TOKEN' => 17,
			'UNSIGNED_TOKEN' => 18,
			'FLOAT_TOKEN' => 19,
			'AUTO_TOKEN' => 20
		},
		DEFAULT => -230,
		GOTOS => {
			'struct_or_union' => 35,
			'preproccess_include' => 23,
			'function_specifier' => 4,
			'external_declaration' => 25,
			'declaration' => 27,
			'embedded_sql' => 7,
			'declaration_specifiers' => 8,
			'struct_or_union_specifier' => 30,
			'type_specifier' => 40,
			'type_qualifier' => 10,
			'storage_class_specifier' => 11,
			'function_definition' => 12,
			'enum_specifier' => 32,
			'translation_unit' => 21
		}
	},
	{#State 1
		ACTIONS => {
			'IDENTIFIER_ORG' => 41,
			'LCB_TOKEN' => 46,
			'END_TOKEN' => 50,
			'SQL_TOKEN' => 47,
			'SECTION_TOKEN' => 42,
			'BEGIN_TOKEN' => 45,
			'DECLARE_TOKEN' => 48,
			'TOOLS_TOKEN' => 51,
			'ORACLE_TOKEN' => 43,
			'EXEC_TOKEN' => 49
		},
		GOTOS => {
			'IDENTIFIER' => 44
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
			'INLINE_TOKEN' => 9,
			'SIGNED_TOKEN' => 13,
			'CHAR_TOKEN' => 14,
			'CONST_TOKEN' => 15,
			'STRUCT_TOKEN' => 16,
			'TNAME_TOKEN' => 17,
			'UNSIGNED_TOKEN' => 18,
			'FLOAT_TOKEN' => 19,
			'AUTO_TOKEN' => 20,
			'VOLATILE_TOKEN' => 22,
			'VOID_TOKEN' => 24,
			'DOUBLE_TOKEN' => 26,
			'INT_TOKEN' => 28,
			'_BOOL_TOKEN' => 29,
			'TYPEDEF_TOKEN' => 31,
			'_COMPLEX_TOKEN' => 34,
			'REGISTER_TOKEN' => 36,
			'RESTRICT_TOKEN' => 37,
			'UNION_TOKEN' => 38,
			'STATIC_TOKEN' => 39
		},
		DEFAULT => -74,
		GOTOS => {
			'struct_or_union' => 35,
			'function_specifier' => 4,
			'declaration_specifiers' => 52,
			'struct_or_union_specifier' => 30,
			'type_qualifier' => 10,
			'type_specifier' => 40,
			'storage_class_specifier' => 11,
			'enum_specifier' => 32
		}
	},
	{#State 5
		DEFAULT => -89
	},
	{#State 6
		ACTIONS => {
			'STRING_LITERAL' => 53
		}
	},
	{#State 7
		DEFAULT => -235
	},
	{#State 8
		ACTIONS => {
			'IDENTIFIER_ORG' => 41,
			'ASTARI_OPR' => 62,
			'SMC_TOKEN' => 55,
			'END_TOKEN' => 50,
			'SQL_TOKEN' => 47,
			'SECTION_TOKEN' => 42,
			'BEGIN_TOKEN' => 45,
			'DECLARE_TOKEN' => 48,
			'TOOLS_TOKEN' => 51,
			'LP_TOKEN' => 60,
			'ORACLE_TOKEN' => 43,
			'EXEC_TOKEN' => 49
		},
		GOTOS => {
			'direct_declarator' => 61,
			'init_declarator' => 54,
			'IDENTIFIER' => 56,
			'pointer' => 58,
			'declarator' => 59,
			'init_declarator_list' => 57
		}
	},
	{#State 9
		DEFAULT => -129
	},
	{#State 10
		ACTIONS => {
			'EXTERN_TOKEN' => 3,
			'SHORT_TOKEN' => 2,
			'ENUM_TOKEN' => 1,
			'LONG_TOKEN' => 5,
			'INLINE_TOKEN' => 9,
			'SIGNED_TOKEN' => 13,
			'CHAR_TOKEN' => 14,
			'CONST_TOKEN' => 15,
			'STRUCT_TOKEN' => 16,
			'TNAME_TOKEN' => 17,
			'UNSIGNED_TOKEN' => 18,
			'FLOAT_TOKEN' => 19,
			'AUTO_TOKEN' => 20,
			'VOLATILE_TOKEN' => 22,
			'VOID_TOKEN' => 24,
			'DOUBLE_TOKEN' => 26,
			'INT_TOKEN' => 28,
			'_BOOL_TOKEN' => 29,
			'TYPEDEF_TOKEN' => 31,
			'_COMPLEX_TOKEN' => 34,
			'REGISTER_TOKEN' => 36,
			'RESTRICT_TOKEN' => 37,
			'UNION_TOKEN' => 38,
			'STATIC_TOKEN' => 39
		},
		DEFAULT => -72,
		GOTOS => {
			'struct_or_union' => 35,
			'function_specifier' => 4,
			'declaration_specifiers' => 63,
			'struct_or_union_specifier' => 30,
			'type_qualifier' => 10,
			'type_specifier' => 40,
			'storage_class_specifier' => 11,
			'enum_specifier' => 32
		}
	},
	{#State 11
		ACTIONS => {
			'EXTERN_TOKEN' => 3,
			'SHORT_TOKEN' => 2,
			'ENUM_TOKEN' => 1,
			'LONG_TOKEN' => 5,
			'INLINE_TOKEN' => 9,
			'SIGNED_TOKEN' => 13,
			'CHAR_TOKEN' => 14,
			'CONST_TOKEN' => 15,
			'STRUCT_TOKEN' => 16,
			'TNAME_TOKEN' => 17,
			'UNSIGNED_TOKEN' => 18,
			'FLOAT_TOKEN' => 19,
			'AUTO_TOKEN' => 20,
			'VOLATILE_TOKEN' => 22,
			'VOID_TOKEN' => 24,
			'DOUBLE_TOKEN' => 26,
			'INT_TOKEN' => 28,
			'_BOOL_TOKEN' => 29,
			'TYPEDEF_TOKEN' => 31,
			'_COMPLEX_TOKEN' => 34,
			'REGISTER_TOKEN' => 36,
			'RESTRICT_TOKEN' => 37,
			'UNION_TOKEN' => 38,
			'STATIC_TOKEN' => 39
		},
		DEFAULT => -68,
		GOTOS => {
			'struct_or_union' => 35,
			'function_specifier' => 4,
			'declaration_specifiers' => 64,
			'struct_or_union_specifier' => 30,
			'type_qualifier' => 10,
			'type_specifier' => 40,
			'storage_class_specifier' => 11,
			'enum_specifier' => 32
		}
	},
	{#State 12
		DEFAULT => -233
	},
	{#State 13
		DEFAULT => -92
	},
	{#State 14
		DEFAULT => -86
	},
	{#State 15
		DEFAULT => -126
	},
	{#State 16
		DEFAULT => -102
	},
	{#State 17
		DEFAULT => -98
	},
	{#State 18
		DEFAULT => -93
	},
	{#State 19
		DEFAULT => -90
	},
	{#State 20
		DEFAULT => -83
	},
	{#State 21
		ACTIONS => {
			'VOLATILE_TOKEN' => 22,
			'' => 65,
			'EXTERN_TOKEN' => 3,
			'SHORT_TOKEN' => 2,
			'ENUM_TOKEN' => 1,
			'LONG_TOKEN' => 5,
			'VOID_TOKEN' => 24,
			'DOUBLE_TOKEN' => 26,
			'INCLUDEFORDBSYNTAXDIFF_TOKEN' => 6,
			'INT_TOKEN' => 28,
			'_BOOL_TOKEN' => 29,
			'INLINE_TOKEN' => 9,
			'TYPEDEF_TOKEN' => 31,
			'EXEC_TOKEN' => 33,
			'_COMPLEX_TOKEN' => 34,
			'SIGNED_TOKEN' => 13,
			'CHAR_TOKEN' => 14,
			'REGISTER_TOKEN' => 36,
			'CONST_TOKEN' => 15,
			'RESTRICT_TOKEN' => 37,
			'UNION_TOKEN' => 38,
			'STRUCT_TOKEN' => 16,
			'STATIC_TOKEN' => 39,
			'TNAME_TOKEN' => 17,
			'UNSIGNED_TOKEN' => 18,
			'FLOAT_TOKEN' => 19,
			'AUTO_TOKEN' => 20
		},
		GOTOS => {
			'struct_or_union' => 35,
			'preproccess_include' => 23,
			'function_specifier' => 4,
			'external_declaration' => 66,
			'embedded_sql' => 7,
			'declaration_specifiers' => 8,
			'declaration' => 27,
			'struct_or_union_specifier' => 30,
			'type_specifier' => 40,
			'type_qualifier' => 10,
			'storage_class_specifier' => 11,
			'function_definition' => 12,
			'enum_specifier' => 32
		}
	},
	{#State 22
		DEFAULT => -128
	},
	{#State 23
		DEFAULT => -236
	},
	{#State 24
		DEFAULT => -85
	},
	{#State 25
		DEFAULT => -231
	},
	{#State 26
		DEFAULT => -91
	},
	{#State 27
		DEFAULT => -234
	},
	{#State 28
		DEFAULT => -88
	},
	{#State 29
		DEFAULT => -94
	},
	{#State 30
		DEFAULT => -96
	},
	{#State 31
		DEFAULT => -80
	},
	{#State 32
		DEFAULT => -97
	},
	{#State 33
		ACTIONS => {
			'SQL_TOKEN' => 68,
			'TOOLS_TOKEN' => 69,
			'ORACLE_TOKEN' => 67
		}
	},
	{#State 34
		DEFAULT => -95
	},
	{#State 35
		ACTIONS => {
			'IDENTIFIER_ORG' => 41,
			'LCB_TOKEN' => 71,
			'END_TOKEN' => 50,
			'SQL_TOKEN' => 47,
			'SECTION_TOKEN' => 42,
			'BEGIN_TOKEN' => 45,
			'DECLARE_TOKEN' => 48,
			'TOOLS_TOKEN' => 51,
			'ORACLE_TOKEN' => 43,
			'EXEC_TOKEN' => 49
		},
		GOTOS => {
			'IDENTIFIER' => 70
		}
	},
	{#State 36
		DEFAULT => -84
	},
	{#State 37
		DEFAULT => -127
	},
	{#State 38
		DEFAULT => -103
	},
	{#State 39
		DEFAULT => -82
	},
	{#State 40
		ACTIONS => {
			'EXTERN_TOKEN' => 3,
			'SHORT_TOKEN' => 2,
			'ENUM_TOKEN' => 1,
			'LONG_TOKEN' => 5,
			'INLINE_TOKEN' => 9,
			'SIGNED_TOKEN' => 13,
			'CHAR_TOKEN' => 14,
			'CONST_TOKEN' => 15,
			'STRUCT_TOKEN' => 16,
			'TNAME_TOKEN' => 17,
			'UNSIGNED_TOKEN' => 18,
			'FLOAT_TOKEN' => 19,
			'AUTO_TOKEN' => 20,
			'VOLATILE_TOKEN' => 22,
			'VOID_TOKEN' => 24,
			'DOUBLE_TOKEN' => 26,
			'INT_TOKEN' => 28,
			'_BOOL_TOKEN' => 29,
			'TYPEDEF_TOKEN' => 31,
			'_COMPLEX_TOKEN' => 34,
			'REGISTER_TOKEN' => 36,
			'RESTRICT_TOKEN' => 37,
			'UNION_TOKEN' => 38,
			'STATIC_TOKEN' => 39
		},
		DEFAULT => -70,
		GOTOS => {
			'struct_or_union' => 35,
			'function_specifier' => 4,
			'declaration_specifiers' => 72,
			'struct_or_union_specifier' => 30,
			'type_qualifier' => 10,
			'type_specifier' => 40,
			'storage_class_specifier' => 11,
			'enum_specifier' => 32
		}
	},
	{#State 41
		DEFAULT => -324
	},
	{#State 42
		DEFAULT => -332
	},
	{#State 43
		DEFAULT => -327
	},
	{#State 44
		ACTIONS => {
			'LCB_TOKEN' => 73
		},
		DEFAULT => -120
	},
	{#State 45
		DEFAULT => -329
	},
	{#State 46
		ACTIONS => {
			'IDENTIFIER_ORG' => 41,
			'SQL_TOKEN' => 47,
			'END_TOKEN' => 50,
			'SECTION_TOKEN' => 42,
			'BEGIN_TOKEN' => 45,
			'DECLARE_TOKEN' => 48,
			'TOOLS_TOKEN' => 51,
			'ORACLE_TOKEN' => 43,
			'EXEC_TOKEN' => 49
		},
		GOTOS => {
			'enumeration_constant' => 77,
			'enumerator' => 76,
			'IDENTIFIER' => 75,
			'enumerator_list' => 74
		}
	},
	{#State 47
		DEFAULT => -326
	},
	{#State 48
		DEFAULT => -331
	},
	{#State 49
		DEFAULT => -325
	},
	{#State 50
		DEFAULT => -330
	},
	{#State 51
		DEFAULT => -328
	},
	{#State 52
		DEFAULT => -75
	},
	{#State 53
		DEFAULT => -237
	},
	{#State 54
		DEFAULT => -76
	},
	{#State 55
		DEFAULT => -67
	},
	{#State 56
		DEFAULT => -132
	},
	{#State 57
		ACTIONS => {
			'CM_TOKEN' => 79,
			'SMC_TOKEN' => 78
		}
	},
	{#State 58
		ACTIONS => {
			'IDENTIFIER_ORG' => 41,
			'END_TOKEN' => 50,
			'SQL_TOKEN' => 47,
			'SECTION_TOKEN' => 42,
			'BEGIN_TOKEN' => 45,
			'DECLARE_TOKEN' => 48,
			'TOOLS_TOKEN' => 51,
			'ORACLE_TOKEN' => 43,
			'EXEC_TOKEN' => 49,
			'LP_TOKEN' => 60
		},
		GOTOS => {
			'direct_declarator' => 80,
			'IDENTIFIER' => 56
		}
	},
	{#State 59
		ACTIONS => {
			'VOLATILE_TOKEN' => 22,
			'EXTERN_TOKEN' => 3,
			'SHORT_TOKEN' => 2,
			'ENUM_TOKEN' => 1,
			'LONG_TOKEN' => 5,
			'VOID_TOKEN' => 24,
			'LCB_TOKEN' => 83,
			'DOUBLE_TOKEN' => 26,
			'INT_TOKEN' => 28,
			'_BOOL_TOKEN' => 29,
			'INLINE_TOKEN' => 9,
			'TYPEDEF_TOKEN' => 31,
			'_COMPLEX_TOKEN' => 34,
			'SIGNED_TOKEN' => 13,
			'CHAR_TOKEN' => 14,
			'REGISTER_TOKEN' => 36,
			'CONST_TOKEN' => 15,
			'RESTRICT_TOKEN' => 37,
			'UNION_TOKEN' => 38,
			'STRUCT_TOKEN' => 16,
			'EQUAL_OPR' => 82,
			'STATIC_TOKEN' => 39,
			'TNAME_TOKEN' => 17,
			'UNSIGNED_TOKEN' => 18,
			'FLOAT_TOKEN' => 19,
			'AUTO_TOKEN' => 20
		},
		DEFAULT => -78,
		GOTOS => {
			'struct_or_union' => 35,
			'function_specifier' => 4,
			'compound_statement' => 85,
			'declaration_specifiers' => 81,
			'declaration' => 84,
			'struct_or_union_specifier' => 30,
			'type_specifier' => 40,
			'type_qualifier' => 10,
			'declaration_list' => 86,
			'storage_class_specifier' => 11,
			'enum_specifier' => 32
		}
	},
	{#State 60
		ACTIONS => {
			'IDENTIFIER_ORG' => 41,
			'ASTARI_OPR' => 62,
			'END_TOKEN' => 50,
			'SQL_TOKEN' => 47,
			'SECTION_TOKEN' => 42,
			'BEGIN_TOKEN' => 45,
			'DECLARE_TOKEN' => 48,
			'TOOLS_TOKEN' => 51,
			'ORACLE_TOKEN' => 43,
			'EXEC_TOKEN' => 49,
			'LP_TOKEN' => 60
		},
		GOTOS => {
			'direct_declarator' => 61,
			'IDENTIFIER' => 56,
			'pointer' => 58,
			'declarator' => 87
		}
	},
	{#State 61
		ACTIONS => {
			'LSB_TOKEN' => 88,
			'LP_TOKEN' => 89
		},
		DEFAULT => -131
	},
	{#State 62
		ACTIONS => {
			'VOLATILE_TOKEN' => 22,
			'CONST_TOKEN' => 15,
			'RESTRICT_TOKEN' => 37,
			'ASTARI_OPR' => 62
		},
		DEFAULT => -147,
		GOTOS => {
			'pointer' => 91,
			'type_qualifier' => 90,
			'type_qualifier_list' => 92
		}
	},
	{#State 63
		DEFAULT => -73
	},
	{#State 64
		DEFAULT => -69
	},
	{#State 65
		DEFAULT => 0
	},
	{#State 66
		DEFAULT => -232
	},
	{#State 67
		ACTIONS => {
			'ENUM_TOKEN' => 95,
			'EXTERN_TOKEN' => 94,
			'SHORT_TOKEN' => 93,
			'LONG_TOKEN' => 96,
			'CM_TOKEN' => 97,
			'INLINE_TOKEN' => 98,
			'DO_TOKEN' => 99,
			'SIGNED_TOKEN' => 101,
			'CONST_TOKEN' => 102,
			'PLUS_OPR' => 103,
			'FOR_TOKEN' => 104,
			'PUBLIC_TOKEN' => 105,
			'SWITCH_TOKEN' => 106,
			'UNSIGNED_TOKEN' => 107,
			'CLN_TOKEN' => 108,
			'PREFIX_OPR' => 109,
			'FLOAT_TOKEN' => 110,
			'AUTO_TOKEN' => 111,
			'AMP_OPR' => 113,
			'RETURN_TOKEN' => 114,
			'RP_TOKEN' => 115,
			'INTEGER_LITERAL' => 116,
			'VOID_TOKEN' => 117,
			'COR_OPR' => 119,
			'DOUBLE_TOKEN' => 120,
			'GT_OPR' => 121,
			'MULTI_OPR' => 122,
			'TYPEDEF_TOKEN' => 123,
			'EXEC_TOKEN' => 124,
			'POSTFIX_OPR' => 125,
			'LP_TOKEN' => 126,
			'_COMPLEX_TOKEN' => 127,
			'REGISTER_TOKEN' => 128,
			'RESTRICT_TOKEN' => 129,
			'ASTARI_OPR' => 130,
			'PRIVATE_TOKEN' => 131,
			'ATMARK_TOKEN' => 132,
			'STRING_LITERAL' => 133,
			'DEFAULT_TOKEN' => 134,
			'IDENTIFIER_ORG' => 135,
			'INEQUALITY_OPR' => 136,
			'MINUS_OPR' => 137,
			'SMC_TOKEN' => 138,
			'LSB_TOKEN' => 139,
			'WHILE_TOKEN' => 140,
			'ELSE_TOKEN' => 141,
			'PTR_OPR' => 142,
			'CASE_TOKEN' => 143,
			'FLOAT_LITERAL' => 144,
			'DOT_TOKEN' => 145,
			'CHAR_TOKEN' => 146,
			'CHAR_LITERAL' => 147,
			'STRUCT_TOKEN' => 148,
			'EQUAL_OPR' => 149,
			'TNAME_TOKEN' => 150,
			'BEGIN_TOKEN' => 151,
			'SIZEOF_TOKEN' => 152,
			'VOLATILE_TOKEN' => 153,
			'_IMAGINARY_TOKEN' => 154,
			'PROTECTED_TOKEN' => 155,
			'INT_TOKEN' => 156,
			'DECLARE_TOKEN' => 157,
			'CONTINUE_TOKEN' => 158,
			'_BOOL_TOKEN' => 159,
			'GOTO_TOKEN' => 160,
			'RSB_TOKEN' => 161,
			'IF_TOKEN' => 163,
			'BREAK_TOKEN' => 162,
			'ASSIGN_OPR' => 164,
			'UNION_TOKEN' => 165,
			'EQUALITY_OPR' => 166,
			'END_TOKEN' => 167,
			'STATIC_TOKEN' => 169,
			'RELATIONAL_OPR' => 168,
			'NEW_TOKEN' => 171,
			'LT_OPR' => 170,
			'QUES_TOKEN' => 172
		},
		GOTOS => {
			'unary_operator' => 100,
			'emb_string_list' => 118,
			'emb_constant_string' => 112
		}
	},
	{#State 68
		ACTIONS => {
			'ENUM_TOKEN' => 95,
			'EXTERN_TOKEN' => 94,
			'SHORT_TOKEN' => 93,
			'LONG_TOKEN' => 96,
			'CM_TOKEN' => 97,
			'INLINE_TOKEN' => 98,
			'DO_TOKEN' => 99,
			'SIGNED_TOKEN' => 101,
			'CONST_TOKEN' => 102,
			'PLUS_OPR' => 103,
			'FOR_TOKEN' => 104,
			'PUBLIC_TOKEN' => 105,
			'SWITCH_TOKEN' => 106,
			'UNSIGNED_TOKEN' => 107,
			'CLN_TOKEN' => 108,
			'PREFIX_OPR' => 109,
			'FLOAT_TOKEN' => 110,
			'AUTO_TOKEN' => 111,
			'AMP_OPR' => 113,
			'RETURN_TOKEN' => 114,
			'RP_TOKEN' => 115,
			'INTEGER_LITERAL' => 116,
			'VOID_TOKEN' => 117,
			'COR_OPR' => 119,
			'DOUBLE_TOKEN' => 120,
			'GT_OPR' => 121,
			'MULTI_OPR' => 122,
			'TYPEDEF_TOKEN' => 123,
			'EXEC_TOKEN' => 124,
			'POSTFIX_OPR' => 125,
			'LP_TOKEN' => 126,
			'_COMPLEX_TOKEN' => 127,
			'REGISTER_TOKEN' => 128,
			'RESTRICT_TOKEN' => 129,
			'ASTARI_OPR' => 130,
			'PRIVATE_TOKEN' => 131,
			'ATMARK_TOKEN' => 132,
			'STRING_LITERAL' => 133,
			'DEFAULT_TOKEN' => 134,
			'IDENTIFIER_ORG' => 135,
			'INEQUALITY_OPR' => 136,
			'MINUS_OPR' => 137,
			'SMC_TOKEN' => 138,
			'LSB_TOKEN' => 139,
			'WHILE_TOKEN' => 140,
			'ELSE_TOKEN' => 141,
			'PTR_OPR' => 142,
			'CASE_TOKEN' => 143,
			'FLOAT_LITERAL' => 144,
			'DOT_TOKEN' => 145,
			'CHAR_TOKEN' => 146,
			'CHAR_LITERAL' => 147,
			'STRUCT_TOKEN' => 148,
			'EQUAL_OPR' => 149,
			'TNAME_TOKEN' => 150,
			'BEGIN_TOKEN' => 175,
			'VOLATILE_TOKEN' => 153,
			'SIZEOF_TOKEN' => 152,
			'_IMAGINARY_TOKEN' => 154,
			'PROTECTED_TOKEN' => 155,
			'INT_TOKEN' => 156,
			'_BOOL_TOKEN' => 159,
			'CONTINUE_TOKEN' => 158,
			'DECLARE_TOKEN' => 157,
			'GOTO_TOKEN' => 160,
			'RSB_TOKEN' => 161,
			'BREAK_TOKEN' => 162,
			'IF_TOKEN' => 163,
			'ASSIGN_OPR' => 164,
			'UNION_TOKEN' => 165,
			'EQUALITY_OPR' => 166,
			'END_TOKEN' => 176,
			'RELATIONAL_OPR' => 168,
			'STATIC_TOKEN' => 169,
			'LT_OPR' => 170,
			'NEW_TOKEN' => 171,
			'QUES_TOKEN' => 172
		},
		GOTOS => {
			'emb_declare' => 174,
			'unary_operator' => 100,
			'emb_string_list' => 173,
			'emb_constant_string' => 112
		}
	},
	{#State 69
		ACTIONS => {
			'ENUM_TOKEN' => 95,
			'EXTERN_TOKEN' => 94,
			'SHORT_TOKEN' => 93,
			'LONG_TOKEN' => 96,
			'CM_TOKEN' => 97,
			'INLINE_TOKEN' => 98,
			'DO_TOKEN' => 99,
			'SIGNED_TOKEN' => 101,
			'CONST_TOKEN' => 102,
			'PLUS_OPR' => 103,
			'FOR_TOKEN' => 104,
			'PUBLIC_TOKEN' => 105,
			'SWITCH_TOKEN' => 106,
			'UNSIGNED_TOKEN' => 107,
			'CLN_TOKEN' => 108,
			'PREFIX_OPR' => 109,
			'FLOAT_TOKEN' => 110,
			'AUTO_TOKEN' => 111,
			'AMP_OPR' => 113,
			'RETURN_TOKEN' => 114,
			'RP_TOKEN' => 115,
			'INTEGER_LITERAL' => 116,
			'VOID_TOKEN' => 117,
			'COR_OPR' => 119,
			'DOUBLE_TOKEN' => 120,
			'GT_OPR' => 121,
			'MULTI_OPR' => 122,
			'TYPEDEF_TOKEN' => 123,
			'EXEC_TOKEN' => 124,
			'POSTFIX_OPR' => 125,
			'LP_TOKEN' => 126,
			'_COMPLEX_TOKEN' => 127,
			'REGISTER_TOKEN' => 128,
			'RESTRICT_TOKEN' => 129,
			'ASTARI_OPR' => 130,
			'PRIVATE_TOKEN' => 131,
			'ATMARK_TOKEN' => 132,
			'STRING_LITERAL' => 133,
			'DEFAULT_TOKEN' => 134,
			'IDENTIFIER_ORG' => 135,
			'INEQUALITY_OPR' => 136,
			'MINUS_OPR' => 137,
			'SMC_TOKEN' => 138,
			'LSB_TOKEN' => 139,
			'WHILE_TOKEN' => 140,
			'ELSE_TOKEN' => 141,
			'PTR_OPR' => 142,
			'CASE_TOKEN' => 143,
			'FLOAT_LITERAL' => 144,
			'DOT_TOKEN' => 145,
			'CHAR_TOKEN' => 146,
			'CHAR_LITERAL' => 147,
			'STRUCT_TOKEN' => 148,
			'EQUAL_OPR' => 149,
			'TNAME_TOKEN' => 150,
			'BEGIN_TOKEN' => 151,
			'VOLATILE_TOKEN' => 153,
			'SIZEOF_TOKEN' => 152,
			'_IMAGINARY_TOKEN' => 154,
			'PROTECTED_TOKEN' => 155,
			'INT_TOKEN' => 156,
			'_BOOL_TOKEN' => 159,
			'CONTINUE_TOKEN' => 158,
			'DECLARE_TOKEN' => 157,
			'GOTO_TOKEN' => 160,
			'RSB_TOKEN' => 161,
			'BREAK_TOKEN' => 162,
			'IF_TOKEN' => 163,
			'ASSIGN_OPR' => 164,
			'UNION_TOKEN' => 165,
			'EQUALITY_OPR' => 166,
			'END_TOKEN' => 167,
			'RELATIONAL_OPR' => 168,
			'STATIC_TOKEN' => 169,
			'LT_OPR' => 170,
			'NEW_TOKEN' => 171,
			'QUES_TOKEN' => 172
		},
		GOTOS => {
			'unary_operator' => 100,
			'emb_string_list' => 177,
			'emb_constant_string' => 112
		}
	},
	{#State 70
		ACTIONS => {
			'LCB_TOKEN' => 178
		},
		DEFAULT => -101
	},
	{#State 71
		ACTIONS => {
			'VOLATILE_TOKEN' => 22,
			'SHORT_TOKEN' => 2,
			'ENUM_TOKEN' => 1,
			'LONG_TOKEN' => 5,
			'VOID_TOKEN' => 24,
			'DOUBLE_TOKEN' => 26,
			'INT_TOKEN' => 28,
			'_BOOL_TOKEN' => 29,
			'_COMPLEX_TOKEN' => 34,
			'SIGNED_TOKEN' => 13,
			'CHAR_TOKEN' => 14,
			'CONST_TOKEN' => 15,
			'RESTRICT_TOKEN' => 37,
			'UNION_TOKEN' => 38,
			'STRUCT_TOKEN' => 16,
			'UNSIGNED_TOKEN' => 18,
			'TNAME_TOKEN' => 17,
			'FLOAT_TOKEN' => 19
		},
		GOTOS => {
			'struct_or_union' => 35,
			'struct_or_union_specifier' => 30,
			'type_qualifier' => 181,
			'type_specifier' => 180,
			'struct_declaration_list' => 183,
			'enum_specifier' => 32,
			'specifier_qualifier_list' => 182,
			'struct_declaration' => 179
		}
	},
	{#State 72
		DEFAULT => -71
	},
	{#State 73
		ACTIONS => {
			'IDENTIFIER_ORG' => 41,
			'END_TOKEN' => 50,
			'SQL_TOKEN' => 47,
			'SECTION_TOKEN' => 42,
			'BEGIN_TOKEN' => 45,
			'DECLARE_TOKEN' => 48,
			'EXEC_TOKEN' => 49,
			'TOOLS_TOKEN' => 51,
			'ORACLE_TOKEN' => 43
		},
		GOTOS => {
			'enumeration_constant' => 77,
			'IDENTIFIER' => 75,
			'enumerator' => 76,
			'enumerator_list' => 184
		}
	},
	{#State 74
		ACTIONS => {
			'CM_TOKEN' => 185,
			'RCB_TOKEN' => 186
		}
	},
	{#State 75
		DEFAULT => -125
	},
	{#State 76
		DEFAULT => -121
	},
	{#State 77
		ACTIONS => {
			'EQUAL_OPR' => 187
		},
		DEFAULT => -123
	},
	{#State 78
		DEFAULT => -66
	},
	{#State 79
		ACTIONS => {
			'IDENTIFIER_ORG' => 41,
			'ASTARI_OPR' => 62,
			'END_TOKEN' => 50,
			'SQL_TOKEN' => 47,
			'SECTION_TOKEN' => 42,
			'BEGIN_TOKEN' => 45,
			'DECLARE_TOKEN' => 48,
			'EXEC_TOKEN' => 49,
			'LP_TOKEN' => 60,
			'TOOLS_TOKEN' => 51,
			'ORACLE_TOKEN' => 43
		},
		GOTOS => {
			'direct_declarator' => 61,
			'init_declarator' => 188,
			'IDENTIFIER' => 56,
			'pointer' => 58,
			'declarator' => 189
		}
	},
	{#State 80
		ACTIONS => {
			'LSB_TOKEN' => 88,
			'LP_TOKEN' => 89
		},
		DEFAULT => -130
	},
	{#State 81
		ACTIONS => {
			'IDENTIFIER_ORG' => 41,
			'SMC_TOKEN' => 55,
			'ASTARI_OPR' => 62,
			'END_TOKEN' => 50,
			'SQL_TOKEN' => 47,
			'SECTION_TOKEN' => 42,
			'DECLARE_TOKEN' => 48,
			'BEGIN_TOKEN' => 45,
			'EXEC_TOKEN' => 49,
			'LP_TOKEN' => 60,
			'TOOLS_TOKEN' => 51,
			'ORACLE_TOKEN' => 43
		},
		GOTOS => {
			'direct_declarator' => 61,
			'init_declarator' => 54,
			'IDENTIFIER' => 56,
			'pointer' => 58,
			'init_declarator_list' => 57,
			'declarator' => 189
		}
	},
	{#State 82
		ACTIONS => {
			'SIZEOF_TOKEN' => 210,
			'AMP_OPR' => 113,
			'IDENTIFIER_ORG' => 41,
			'INTEGER_LITERAL' => 194,
			'MINUS_OPR' => 137,
			'LCB_TOKEN' => 195,
			'SQL_TOKEN' => 47,
			'SECTION_TOKEN' => 42,
			'DECLARE_TOKEN' => 48,
			'FLOAT_LITERAL' => 203,
			'ORACLE_TOKEN' => 43,
			'EXEC_TOKEN' => 49,
			'POSTFIX_OPR' => 197,
			'LP_TOKEN' => 198,
			'PLUS_OPR' => 103,
			'CHAR_LITERAL' => 207,
			'ASTARI_OPR' => 130,
			'END_TOKEN' => 50,
			'BEGIN_TOKEN' => 45,
			'PREFIX_OPR' => 109,
			'STRING_LITERAL' => 201,
			'TOOLS_TOKEN' => 51
		},
		GOTOS => {
			'logical_OR_expression' => 211,
			'conditional_expression' => 202,
			'primary_expression' => 212,
			'unary_operator' => 190,
			'unary_expression' => 196,
			'equality_expression' => 204,
			'IDENTIFIER' => 205,
			'shift_expression' => 206,
			'additive_expression' => 199,
			'postfix_expression' => 213,
			'exclusive_OR_expression' => 214,
			'inclusive_OR_expression' => 208,
			'relational_expression' => 200,
			'string_literal_list' => 215,
			'AND_expression' => 191,
			'multiplicative_expression' => 209,
			'logical_AND_expression' => 216,
			'assignment_expression' => 192,
			'cast_expression' => 217,
			'initializer' => 193
		}
	},
	{#State 83
		ACTIONS => {
			'DEFAULT_TOKEN' => 230,
			'EXTERN_TOKEN' => 3,
			'SHORT_TOKEN' => 2,
			'ENUM_TOKEN' => 1,
			'IDENTIFIER_ORG' => 41,
			'LONG_TOKEN' => 5,
			'MINUS_OPR' => 137,
			'SMC_TOKEN' => 232,
			'INCLUDEFORDBSYNTAXDIFF_TOKEN' => 6,
			'SECTION_TOKEN' => 42,
			'DO_TOKEN' => 219,
			'INLINE_TOKEN' => 9,
			'WHILE_TOKEN' => 234,
			'CASE_TOKEN' => 236,
			'FLOAT_LITERAL' => 203,
			'ORACLE_TOKEN' => 43,
			'CHAR_TOKEN' => 14,
			'SIGNED_TOKEN' => 13,
			'CONST_TOKEN' => 15,
			'PLUS_OPR' => 103,
			'FOR_TOKEN' => 221,
			'RCB_TOKEN' => 222,
			'CHAR_LITERAL' => 207,
			'STRUCT_TOKEN' => 16,
			'SWITCH_TOKEN' => 223,
			'TNAME_TOKEN' => 17,
			'UNSIGNED_TOKEN' => 18,
			'BEGIN_TOKEN' => 45,
			'PREFIX_OPR' => 109,
			'FLOAT_TOKEN' => 19,
			'AUTO_TOKEN' => 20,
			'SIZEOF_TOKEN' => 210,
			'VOLATILE_TOKEN' => 22,
			'AMP_OPR' => 113,
			'RETURN_TOKEN' => 226,
			'INTEGER_LITERAL' => 194,
			'VOID_TOKEN' => 24,
			'LCB_TOKEN' => 83,
			'SQL_TOKEN' => 47,
			'DOUBLE_TOKEN' => 26,
			'INT_TOKEN' => 28,
			'_BOOL_TOKEN' => 29,
			'CONTINUE_TOKEN' => 242,
			'DECLARE_TOKEN' => 48,
			'GOTO_TOKEN' => 243,
			'TYPEDEF_TOKEN' => 31,
			'EXEC_TOKEN' => 228,
			'POSTFIX_OPR' => 197,
			'LP_TOKEN' => 198,
			'_COMPLEX_TOKEN' => 34,
			'IF_TOKEN' => 245,
			'BREAK_TOKEN' => 244,
			'REGISTER_TOKEN' => 36,
			'RESTRICT_TOKEN' => 37,
			'UNION_TOKEN' => 38,
			'ASTARI_OPR' => 130,
			'END_TOKEN' => 50,
			'STATIC_TOKEN' => 39,
			'STRING_LITERAL' => 201,
			'TOOLS_TOKEN' => 51
		},
		GOTOS => {
			'function_specifier' => 4,
			'iteration_statement' => 218,
			'expression_statement' => 231,
			'conditional_expression' => 202,
			'embedded_sql' => 233,
			'declaration_specifiers' => 81,
			'statement' => 220,
			'expression' => 235,
			'type_qualifier' => 10,
			'storage_class_specifier' => 11,
			'unary_operator' => 190,
			'block_item_list' => 237,
			'block_item' => 238,
			'IDENTIFIER' => 239,
			'equality_expression' => 204,
			'shift_expression' => 206,
			'inclusive_OR_expression' => 208,
			'multiplicative_expression' => 209,
			'AND_expression' => 191,
			'assignment_expression' => 224,
			'selection_statement' => 225,
			'preproccess_include' => 240,
			'jump_statement' => 241,
			'logical_OR_expression' => 211,
			'primary_expression' => 212,
			'declaration' => 227,
			'struct_or_union_specifier' => 30,
			'unary_expression' => 196,
			'enum_specifier' => 32,
			'struct_or_union' => 35,
			'compound_statement' => 229,
			'labeled_statement' => 246,
			'postfix_expression' => 213,
			'additive_expression' => 199,
			'exclusive_OR_expression' => 214,
			'relational_expression' => 200,
			'string_literal_list' => 215,
			'type_specifier' => 40,
			'logical_AND_expression' => 216,
			'cast_expression' => 217
		}
	},
	{#State 84
		DEFAULT => -240
	},
	{#State 85
		DEFAULT => -238
	},
	{#State 86
		ACTIONS => {
			'VOLATILE_TOKEN' => 22,
			'EXTERN_TOKEN' => 3,
			'SHORT_TOKEN' => 2,
			'ENUM_TOKEN' => 1,
			'LONG_TOKEN' => 5,
			'VOID_TOKEN' => 24,
			'LCB_TOKEN' => 83,
			'DOUBLE_TOKEN' => 26,
			'INT_TOKEN' => 28,
			'_BOOL_TOKEN' => 29,
			'INLINE_TOKEN' => 9,
			'TYPEDEF_TOKEN' => 31,
			'_COMPLEX_TOKEN' => 34,
			'CHAR_TOKEN' => 14,
			'SIGNED_TOKEN' => 13,
			'CONST_TOKEN' => 15,
			'REGISTER_TOKEN' => 36,
			'RESTRICT_TOKEN' => 37,
			'UNION_TOKEN' => 38,
			'STRUCT_TOKEN' => 16,
			'STATIC_TOKEN' => 39,
			'TNAME_TOKEN' => 17,
			'UNSIGNED_TOKEN' => 18,
			'FLOAT_TOKEN' => 19,
			'AUTO_TOKEN' => 20
		},
		GOTOS => {
			'struct_or_union' => 35,
			'function_specifier' => 4,
			'compound_statement' => 248,
			'declaration_specifiers' => 81,
			'declaration' => 247,
			'struct_or_union_specifier' => 30,
			'type_specifier' => 40,
			'type_qualifier' => 10,
			'storage_class_specifier' => 11,
			'enum_specifier' => 32
		}
	},
	{#State 87
		ACTIONS => {
			'RP_TOKEN' => 249
		}
	},
	{#State 88
		ACTIONS => {
			'SIZEOF_TOKEN' => 210,
			'VOLATILE_TOKEN' => 22,
			'AMP_OPR' => 113,
			'IDENTIFIER_ORG' => 41,
			'INTEGER_LITERAL' => 194,
			'MINUS_OPR' => 137,
			'SQL_TOKEN' => 47,
			'SECTION_TOKEN' => 42,
			'DECLARE_TOKEN' => 48,
			'RSB_TOKEN' => 253,
			'FLOAT_LITERAL' => 203,
			'ORACLE_TOKEN' => 43,
			'EXEC_TOKEN' => 49,
			'POSTFIX_OPR' => 197,
			'LP_TOKEN' => 198,
			'CONST_TOKEN' => 15,
			'PLUS_OPR' => 103,
			'RESTRICT_TOKEN' => 37,
			'CHAR_LITERAL' => 207,
			'ASTARI_OPR' => 252,
			'END_TOKEN' => 50,
			'STATIC_TOKEN' => 254,
			'BEGIN_TOKEN' => 45,
			'PREFIX_OPR' => 109,
			'STRING_LITERAL' => 201,
			'TOOLS_TOKEN' => 51
		},
		GOTOS => {
			'logical_OR_expression' => 211,
			'conditional_expression' => 202,
			'primary_expression' => 212,
			'type_qualifier_list' => 251,
			'type_qualifier' => 90,
			'unary_operator' => 190,
			'unary_expression' => 196,
			'equality_expression' => 204,
			'IDENTIFIER' => 205,
			'shift_expression' => 206,
			'postfix_expression' => 213,
			'additive_expression' => 199,
			'exclusive_OR_expression' => 214,
			'inclusive_OR_expression' => 208,
			'relational_expression' => 200,
			'string_literal_list' => 215,
			'AND_expression' => 191,
			'multiplicative_expression' => 209,
			'logical_AND_expression' => 216,
			'assignment_expression' => 250,
			'cast_expression' => 217
		}
	},
	{#State 89
		ACTIONS => {
			'EXTERN_TOKEN' => 3,
			'SHORT_TOKEN' => 2,
			'ENUM_TOKEN' => 1,
			'IDENTIFIER_ORG' => 41,
			'LONG_TOKEN' => 5,
			'SECTION_TOKEN' => 42,
			'INLINE_TOKEN' => 9,
			'ORACLE_TOKEN' => 43,
			'CHAR_TOKEN' => 14,
			'SIGNED_TOKEN' => 13,
			'CONST_TOKEN' => 15,
			'STRUCT_TOKEN' => 16,
			'TNAME_TOKEN' => 17,
			'UNSIGNED_TOKEN' => 18,
			'BEGIN_TOKEN' => 45,
			'FLOAT_TOKEN' => 19,
			'AUTO_TOKEN' => 20,
			'VOLATILE_TOKEN' => 22,
			'RP_TOKEN' => 258,
			'VOID_TOKEN' => 24,
			'DOUBLE_TOKEN' => 26,
			'SQL_TOKEN' => 47,
			'INT_TOKEN' => 28,
			'DECLARE_TOKEN' => 48,
			'_BOOL_TOKEN' => 29,
			'TYPEDEF_TOKEN' => 31,
			'EXEC_TOKEN' => 49,
			'_COMPLEX_TOKEN' => 34,
			'REGISTER_TOKEN' => 36,
			'RESTRICT_TOKEN' => 37,
			'UNION_TOKEN' => 38,
			'END_TOKEN' => 50,
			'STATIC_TOKEN' => 39,
			'TOOLS_TOKEN' => 51
		},
		GOTOS => {
			'parameter_type_list' => 261,
			'struct_or_union' => 35,
			'IDENTIFIER' => 259,
			'function_specifier' => 4,
			'parameter_declaration' => 255,
			'declaration_specifiers' => 256,
			'identifier_list' => 257,
			'struct_or_union_specifier' => 30,
			'type_specifier' => 40,
			'type_qualifier' => 10,
			'storage_class_specifier' => 11,
			'enum_specifier' => 32,
			'parameter_list' => 260
		}
	},
	{#State 90
		DEFAULT => -150
	},
	{#State 91
		DEFAULT => -149
	},
	{#State 92
		ACTIONS => {
			'VOLATILE_TOKEN' => 22,
			'CONST_TOKEN' => 15,
			'RESTRICT_TOKEN' => 37,
			'ASTARI_OPR' => 62
		},
		DEFAULT => -146,
		GOTOS => {
			'pointer' => 263,
			'type_qualifier' => 262
		}
	},
	{#State 93
		DEFAULT => -298
	},
	{#State 94
		DEFAULT => -284
	},
	{#State 95
		DEFAULT => -283
	},
	{#State 96
		DEFAULT => -290
	},
	{#State 97
		DEFAULT => -267
	},
	{#State 98
		DEFAULT => -288
	},
	{#State 99
		DEFAULT => -258
	},
	{#State 100
		DEFAULT => -262
	},
	{#State 101
		DEFAULT => -299
	},
	{#State 102
		DEFAULT => -279
	},
	{#State 103
		DEFAULT => -27
	},
	{#State 104
		DEFAULT => -286
	},
	{#State 105
		DEFAULT => -294
	},
	{#State 106
		DEFAULT => -303
	},
	{#State 107
		DEFAULT => -306
	},
	{#State 108
		ACTIONS => {
			'SQL_TOKEN' => 265,
			'IDENTIFIER_ORG' => 264
		}
	},
	{#State 109
		DEFAULT => -29
	},
	{#State 110
		DEFAULT => -285
	},
	{#State 111
		DEFAULT => -276
	},
	{#State 112
		DEFAULT => -248
	},
	{#State 113
		DEFAULT => -25
	},
	{#State 114
		DEFAULT => -297
	},
	{#State 115
		DEFAULT => -265
	},
	{#State 116
		DEFAULT => -252
	},
	{#State 117
		DEFAULT => -308
	},
	{#State 118
		ACTIONS => {
			'ENUM_TOKEN' => 95,
			'EXTERN_TOKEN' => 94,
			'SHORT_TOKEN' => 93,
			'LONG_TOKEN' => 96,
			'CM_TOKEN' => 97,
			'INLINE_TOKEN' => 98,
			'DO_TOKEN' => 99,
			'SIGNED_TOKEN' => 101,
			'CONST_TOKEN' => 102,
			'PLUS_OPR' => 103,
			'FOR_TOKEN' => 104,
			'PUBLIC_TOKEN' => 105,
			'SWITCH_TOKEN' => 106,
			'UNSIGNED_TOKEN' => 107,
			'CLN_TOKEN' => 108,
			'PREFIX_OPR' => 109,
			'FLOAT_TOKEN' => 110,
			'AUTO_TOKEN' => 111,
			'AMP_OPR' => 113,
			'RETURN_TOKEN' => 114,
			'RP_TOKEN' => 115,
			'INTEGER_LITERAL' => 116,
			'VOID_TOKEN' => 117,
			'COR_OPR' => 119,
			'DOUBLE_TOKEN' => 120,
			'GT_OPR' => 121,
			'MULTI_OPR' => 122,
			'TYPEDEF_TOKEN' => 123,
			'EXEC_TOKEN' => 124,
			'POSTFIX_OPR' => 125,
			'LP_TOKEN' => 126,
			'_COMPLEX_TOKEN' => 127,
			'REGISTER_TOKEN' => 128,
			'RESTRICT_TOKEN' => 129,
			'ASTARI_OPR' => 130,
			'PRIVATE_TOKEN' => 131,
			'ATMARK_TOKEN' => 132,
			'STRING_LITERAL' => 133,
			'DEFAULT_TOKEN' => 134,
			'IDENTIFIER_ORG' => 135,
			'INEQUALITY_OPR' => 136,
			'MINUS_OPR' => 137,
			'SMC_TOKEN' => 267,
			'LSB_TOKEN' => 139,
			'WHILE_TOKEN' => 140,
			'ELSE_TOKEN' => 141,
			'PTR_OPR' => 142,
			'CASE_TOKEN' => 143,
			'FLOAT_LITERAL' => 144,
			'DOT_TOKEN' => 145,
			'CHAR_TOKEN' => 146,
			'CHAR_LITERAL' => 147,
			'STRUCT_TOKEN' => 148,
			'EQUAL_OPR' => 149,
			'TNAME_TOKEN' => 150,
			'BEGIN_TOKEN' => 151,
			'VOLATILE_TOKEN' => 153,
			'SIZEOF_TOKEN' => 152,
			'_IMAGINARY_TOKEN' => 154,
			'PROTECTED_TOKEN' => 155,
			'INT_TOKEN' => 156,
			'_BOOL_TOKEN' => 159,
			'CONTINUE_TOKEN' => 158,
			'DECLARE_TOKEN' => 157,
			'GOTO_TOKEN' => 160,
			'RSB_TOKEN' => 161,
			'BREAK_TOKEN' => 162,
			'IF_TOKEN' => 163,
			'ASSIGN_OPR' => 164,
			'UNION_TOKEN' => 165,
			'EQUALITY_OPR' => 166,
			'END_TOKEN' => 167,
			'RELATIONAL_OPR' => 168,
			'STATIC_TOKEN' => 169,
			'LT_OPR' => 170,
			'NEW_TOKEN' => 171,
			'QUES_TOKEN' => 172
		},
		GOTOS => {
			'unary_operator' => 100,
			'emb_constant_string' => 266
		}
	},
	{#State 119
		DEFAULT => -317
	},
	{#State 120
		DEFAULT => -281
	},
	{#State 121
		DEFAULT => -270
	},
	{#State 122
		DEFAULT => -321
	},
	{#State 123
		DEFAULT => -304
	},
	{#State 124
		DEFAULT => -322
	},
	{#State 125
		DEFAULT => -314
	},
	{#State 126
		DEFAULT => -264
	},
	{#State 127
		DEFAULT => -274
	},
	{#State 128
		DEFAULT => -295
	},
	{#State 129
		DEFAULT => -296
	},
	{#State 130
		DEFAULT => -26
	},
	{#State 131
		DEFAULT => -292
	},
	{#State 132
		DEFAULT => -312
	},
	{#State 133
		DEFAULT => -254
	},
	{#State 134
		DEFAULT => -280
	},
	{#State 135
		DEFAULT => -250
	},
	{#State 136
		DEFAULT => -318
	},
	{#State 137
		DEFAULT => -28
	},
	{#State 138
		DEFAULT => -266
	},
	{#State 139
		DEFAULT => -319
	},
	{#State 140
		DEFAULT => -309
	},
	{#State 141
		DEFAULT => -282
	},
	{#State 142
		DEFAULT => -323
	},
	{#State 143
		DEFAULT => -277
	},
	{#State 144
		DEFAULT => -251
	},
	{#State 145
		DEFAULT => -268
	},
	{#State 146
		DEFAULT => -278
	},
	{#State 147
		DEFAULT => -253
	},
	{#State 148
		DEFAULT => -302
	},
	{#State 149
		DEFAULT => -263
	},
	{#State 150
		DEFAULT => -313
	},
	{#State 151
		DEFAULT => -310
	},
	{#State 152
		DEFAULT => -300
	},
	{#State 153
		DEFAULT => -307
	},
	{#State 154
		DEFAULT => -275
	},
	{#State 155
		DEFAULT => -293
	},
	{#State 156
		DEFAULT => -289
	},
	{#State 157
		DEFAULT => -257
	},
	{#State 158
		DEFAULT => -260
	},
	{#State 159
		DEFAULT => -273
	},
	{#State 160
		DEFAULT => -261
	},
	{#State 161
		DEFAULT => -320
	},
	{#State 162
		DEFAULT => -259
	},
	{#State 163
		DEFAULT => -287
	},
	{#State 164
		DEFAULT => -316
	},
	{#State 165
		DEFAULT => -305
	},
	{#State 166
		DEFAULT => -315
	},
	{#State 167
		DEFAULT => -311
	},
	{#State 168
		DEFAULT => -272
	},
	{#State 169
		DEFAULT => -301
	},
	{#State 170
		DEFAULT => -271
	},
	{#State 171
		DEFAULT => -291
	},
	{#State 172
		DEFAULT => -269
	},
	{#State 173
		ACTIONS => {
			'ENUM_TOKEN' => 95,
			'EXTERN_TOKEN' => 94,
			'SHORT_TOKEN' => 93,
			'LONG_TOKEN' => 96,
			'CM_TOKEN' => 97,
			'INLINE_TOKEN' => 98,
			'DO_TOKEN' => 99,
			'SIGNED_TOKEN' => 101,
			'CONST_TOKEN' => 102,
			'PLUS_OPR' => 103,
			'FOR_TOKEN' => 104,
			'PUBLIC_TOKEN' => 105,
			'SWITCH_TOKEN' => 106,
			'UNSIGNED_TOKEN' => 107,
			'CLN_TOKEN' => 108,
			'PREFIX_OPR' => 109,
			'FLOAT_TOKEN' => 110,
			'AUTO_TOKEN' => 111,
			'AMP_OPR' => 113,
			'RETURN_TOKEN' => 114,
			'RP_TOKEN' => 115,
			'INTEGER_LITERAL' => 116,
			'VOID_TOKEN' => 117,
			'COR_OPR' => 119,
			'DOUBLE_TOKEN' => 120,
			'GT_OPR' => 121,
			'MULTI_OPR' => 122,
			'TYPEDEF_TOKEN' => 123,
			'EXEC_TOKEN' => 124,
			'POSTFIX_OPR' => 125,
			'LP_TOKEN' => 126,
			'_COMPLEX_TOKEN' => 127,
			'REGISTER_TOKEN' => 128,
			'RESTRICT_TOKEN' => 129,
			'ASTARI_OPR' => 130,
			'PRIVATE_TOKEN' => 131,
			'ATMARK_TOKEN' => 132,
			'STRING_LITERAL' => 133,
			'DEFAULT_TOKEN' => 134,
			'IDENTIFIER_ORG' => 135,
			'INEQUALITY_OPR' => 136,
			'MINUS_OPR' => 137,
			'SMC_TOKEN' => 268,
			'LSB_TOKEN' => 139,
			'WHILE_TOKEN' => 140,
			'ELSE_TOKEN' => 141,
			'PTR_OPR' => 142,
			'CASE_TOKEN' => 143,
			'FLOAT_LITERAL' => 144,
			'DOT_TOKEN' => 145,
			'CHAR_TOKEN' => 146,
			'CHAR_LITERAL' => 147,
			'STRUCT_TOKEN' => 148,
			'EQUAL_OPR' => 149,
			'TNAME_TOKEN' => 150,
			'BEGIN_TOKEN' => 151,
			'VOLATILE_TOKEN' => 153,
			'SIZEOF_TOKEN' => 152,
			'_IMAGINARY_TOKEN' => 154,
			'PROTECTED_TOKEN' => 155,
			'INT_TOKEN' => 156,
			'_BOOL_TOKEN' => 159,
			'CONTINUE_TOKEN' => 158,
			'DECLARE_TOKEN' => 157,
			'GOTO_TOKEN' => 160,
			'RSB_TOKEN' => 161,
			'BREAK_TOKEN' => 162,
			'IF_TOKEN' => 163,
			'ASSIGN_OPR' => 164,
			'UNION_TOKEN' => 165,
			'EQUALITY_OPR' => 166,
			'END_TOKEN' => 167,
			'RELATIONAL_OPR' => 168,
			'STATIC_TOKEN' => 169,
			'LT_OPR' => 170,
			'NEW_TOKEN' => 171,
			'QUES_TOKEN' => 172
		},
		GOTOS => {
			'unary_operator' => 100,
			'emb_constant_string' => 266
		}
	},
	{#State 174
		ACTIONS => {
			'SMC_TOKEN' => 269
		}
	},
	{#State 175
		ACTIONS => {
			'DECLARE_TOKEN' => 270
		},
		DEFAULT => -310
	},
	{#State 176
		ACTIONS => {
			'DECLARE_TOKEN' => 271
		},
		DEFAULT => -311
	},
	{#State 177
		ACTIONS => {
			'ENUM_TOKEN' => 95,
			'EXTERN_TOKEN' => 94,
			'SHORT_TOKEN' => 93,
			'LONG_TOKEN' => 96,
			'CM_TOKEN' => 97,
			'INLINE_TOKEN' => 98,
			'DO_TOKEN' => 99,
			'SIGNED_TOKEN' => 101,
			'CONST_TOKEN' => 102,
			'PLUS_OPR' => 103,
			'FOR_TOKEN' => 104,
			'PUBLIC_TOKEN' => 105,
			'SWITCH_TOKEN' => 106,
			'UNSIGNED_TOKEN' => 107,
			'CLN_TOKEN' => 108,
			'PREFIX_OPR' => 109,
			'FLOAT_TOKEN' => 110,
			'AUTO_TOKEN' => 111,
			'AMP_OPR' => 113,
			'RETURN_TOKEN' => 114,
			'RP_TOKEN' => 115,
			'INTEGER_LITERAL' => 116,
			'VOID_TOKEN' => 117,
			'COR_OPR' => 119,
			'DOUBLE_TOKEN' => 120,
			'GT_OPR' => 121,
			'MULTI_OPR' => 122,
			'TYPEDEF_TOKEN' => 123,
			'EXEC_TOKEN' => 124,
			'POSTFIX_OPR' => 125,
			'LP_TOKEN' => 126,
			'_COMPLEX_TOKEN' => 127,
			'REGISTER_TOKEN' => 128,
			'RESTRICT_TOKEN' => 129,
			'ASTARI_OPR' => 130,
			'PRIVATE_TOKEN' => 131,
			'ATMARK_TOKEN' => 132,
			'STRING_LITERAL' => 133,
			'DEFAULT_TOKEN' => 134,
			'IDENTIFIER_ORG' => 135,
			'INEQUALITY_OPR' => 136,
			'MINUS_OPR' => 137,
			'SMC_TOKEN' => 272,
			'LSB_TOKEN' => 139,
			'WHILE_TOKEN' => 140,
			'ELSE_TOKEN' => 141,
			'PTR_OPR' => 142,
			'CASE_TOKEN' => 143,
			'FLOAT_LITERAL' => 144,
			'DOT_TOKEN' => 145,
			'CHAR_TOKEN' => 146,
			'CHAR_LITERAL' => 147,
			'STRUCT_TOKEN' => 148,
			'EQUAL_OPR' => 149,
			'TNAME_TOKEN' => 150,
			'BEGIN_TOKEN' => 151,
			'VOLATILE_TOKEN' => 153,
			'SIZEOF_TOKEN' => 152,
			'_IMAGINARY_TOKEN' => 154,
			'PROTECTED_TOKEN' => 155,
			'INT_TOKEN' => 156,
			'_BOOL_TOKEN' => 159,
			'CONTINUE_TOKEN' => 158,
			'DECLARE_TOKEN' => 157,
			'GOTO_TOKEN' => 160,
			'RSB_TOKEN' => 161,
			'BREAK_TOKEN' => 162,
			'IF_TOKEN' => 163,
			'ASSIGN_OPR' => 164,
			'UNION_TOKEN' => 165,
			'EQUALITY_OPR' => 166,
			'END_TOKEN' => 167,
			'RELATIONAL_OPR' => 168,
			'STATIC_TOKEN' => 169,
			'LT_OPR' => 170,
			'NEW_TOKEN' => 171,
			'QUES_TOKEN' => 172
		},
		GOTOS => {
			'unary_operator' => 100,
			'emb_constant_string' => 266
		}
	},
	{#State 178
		ACTIONS => {
			'VOLATILE_TOKEN' => 22,
			'SHORT_TOKEN' => 2,
			'ENUM_TOKEN' => 1,
			'LONG_TOKEN' => 5,
			'VOID_TOKEN' => 24,
			'DOUBLE_TOKEN' => 26,
			'INT_TOKEN' => 28,
			'_BOOL_TOKEN' => 29,
			'_COMPLEX_TOKEN' => 34,
			'SIGNED_TOKEN' => 13,
			'CHAR_TOKEN' => 14,
			'CONST_TOKEN' => 15,
			'RESTRICT_TOKEN' => 37,
			'UNION_TOKEN' => 38,
			'STRUCT_TOKEN' => 16,
			'UNSIGNED_TOKEN' => 18,
			'TNAME_TOKEN' => 17,
			'FLOAT_TOKEN' => 19
		},
		GOTOS => {
			'struct_or_union' => 35,
			'struct_or_union_specifier' => 30,
			'type_qualifier' => 181,
			'type_specifier' => 180,
			'struct_declaration_list' => 273,
			'enum_specifier' => 32,
			'specifier_qualifier_list' => 182,
			'struct_declaration' => 179
		}
	},
	{#State 179
		DEFAULT => -104
	},
	{#State 180
		ACTIONS => {
			'SHORT_TOKEN' => 2,
			'ENUM_TOKEN' => 1,
			'LONG_TOKEN' => 5,
			'SIGNED_TOKEN' => 13,
			'CHAR_TOKEN' => 14,
			'CONST_TOKEN' => 15,
			'STRUCT_TOKEN' => 16,
			'UNSIGNED_TOKEN' => 18,
			'TNAME_TOKEN' => 17,
			'FLOAT_TOKEN' => 19,
			'VOLATILE_TOKEN' => 22,
			'VOID_TOKEN' => 24,
			'DOUBLE_TOKEN' => 26,
			'INT_TOKEN' => 28,
			'_BOOL_TOKEN' => 29,
			'_COMPLEX_TOKEN' => 34,
			'RESTRICT_TOKEN' => 37,
			'UNION_TOKEN' => 38
		},
		DEFAULT => -108,
		GOTOS => {
			'struct_or_union' => 35,
			'struct_or_union_specifier' => 30,
			'type_qualifier' => 181,
			'type_specifier' => 180,
			'enum_specifier' => 32,
			'specifier_qualifier_list' => 274
		}
	},
	{#State 181
		ACTIONS => {
			'SHORT_TOKEN' => 2,
			'ENUM_TOKEN' => 1,
			'LONG_TOKEN' => 5,
			'SIGNED_TOKEN' => 13,
			'CHAR_TOKEN' => 14,
			'CONST_TOKEN' => 15,
			'STRUCT_TOKEN' => 16,
			'UNSIGNED_TOKEN' => 18,
			'TNAME_TOKEN' => 17,
			'FLOAT_TOKEN' => 19,
			'VOLATILE_TOKEN' => 22,
			'VOID_TOKEN' => 24,
			'DOUBLE_TOKEN' => 26,
			'INT_TOKEN' => 28,
			'_BOOL_TOKEN' => 29,
			'_COMPLEX_TOKEN' => 34,
			'RESTRICT_TOKEN' => 37,
			'UNION_TOKEN' => 38
		},
		DEFAULT => -110,
		GOTOS => {
			'struct_or_union' => 35,
			'struct_or_union_specifier' => 30,
			'type_qualifier' => 181,
			'type_specifier' => 180,
			'enum_specifier' => 32,
			'specifier_qualifier_list' => 275
		}
	},
	{#State 182
		ACTIONS => {
			'IDENTIFIER_ORG' => 41,
			'ASTARI_OPR' => 62,
			'END_TOKEN' => 50,
			'SQL_TOKEN' => 47,
			'SECTION_TOKEN' => 42,
			'DECLARE_TOKEN' => 48,
			'BEGIN_TOKEN' => 45,
			'CLN_TOKEN' => 276,
			'EXEC_TOKEN' => 49,
			'LP_TOKEN' => 60,
			'TOOLS_TOKEN' => 51,
			'ORACLE_TOKEN' => 43
		},
		GOTOS => {
			'direct_declarator' => 61,
			'IDENTIFIER' => 56,
			'pointer' => 58,
			'struct_declarator_list' => 278,
			'declarator' => 277,
			'struct_declarator' => 279
		}
	},
	{#State 183
		ACTIONS => {
			'VOLATILE_TOKEN' => 22,
			'SHORT_TOKEN' => 2,
			'ENUM_TOKEN' => 1,
			'LONG_TOKEN' => 5,
			'VOID_TOKEN' => 24,
			'DOUBLE_TOKEN' => 26,
			'INT_TOKEN' => 28,
			'_BOOL_TOKEN' => 29,
			'_COMPLEX_TOKEN' => 34,
			'SIGNED_TOKEN' => 13,
			'CHAR_TOKEN' => 14,
			'CONST_TOKEN' => 15,
			'RCB_TOKEN' => 280,
			'RESTRICT_TOKEN' => 37,
			'UNION_TOKEN' => 38,
			'STRUCT_TOKEN' => 16,
			'UNSIGNED_TOKEN' => 18,
			'TNAME_TOKEN' => 17,
			'FLOAT_TOKEN' => 19
		},
		GOTOS => {
			'struct_or_union' => 35,
			'struct_or_union_specifier' => 30,
			'type_qualifier' => 181,
			'type_specifier' => 180,
			'enum_specifier' => 32,
			'specifier_qualifier_list' => 182,
			'struct_declaration' => 281
		}
	},
	{#State 184
		ACTIONS => {
			'CM_TOKEN' => 282,
			'RCB_TOKEN' => 283
		}
	},
	{#State 185
		ACTIONS => {
			'RCB_TOKEN' => 285,
			'IDENTIFIER_ORG' => 41,
			'END_TOKEN' => 50,
			'SQL_TOKEN' => 47,
			'SECTION_TOKEN' => 42,
			'BEGIN_TOKEN' => 45,
			'DECLARE_TOKEN' => 48,
			'EXEC_TOKEN' => 49,
			'TOOLS_TOKEN' => 51,
			'ORACLE_TOKEN' => 43
		},
		GOTOS => {
			'enumeration_constant' => 77,
			'IDENTIFIER' => 75,
			'enumerator' => 284
		}
	},
	{#State 186
		DEFAULT => -117
	},
	{#State 187
		ACTIONS => {
			'SIZEOF_TOKEN' => 210,
			'AMP_OPR' => 113,
			'IDENTIFIER_ORG' => 41,
			'INTEGER_LITERAL' => 194,
			'MINUS_OPR' => 137,
			'SQL_TOKEN' => 47,
			'SECTION_TOKEN' => 42,
			'DECLARE_TOKEN' => 48,
			'FLOAT_LITERAL' => 203,
			'ORACLE_TOKEN' => 43,
			'EXEC_TOKEN' => 49,
			'POSTFIX_OPR' => 197,
			'LP_TOKEN' => 198,
			'PLUS_OPR' => 103,
			'CHAR_LITERAL' => 207,
			'ASTARI_OPR' => 130,
			'END_TOKEN' => 50,
			'BEGIN_TOKEN' => 45,
			'PREFIX_OPR' => 109,
			'STRING_LITERAL' => 201,
			'TOOLS_TOKEN' => 51
		},
		GOTOS => {
			'logical_OR_expression' => 211,
			'conditional_expression' => 287,
			'primary_expression' => 212,
			'unary_operator' => 190,
			'unary_expression' => 286,
			'equality_expression' => 204,
			'IDENTIFIER' => 205,
			'constant_expression' => 288,
			'shift_expression' => 206,
			'additive_expression' => 199,
			'postfix_expression' => 213,
			'exclusive_OR_expression' => 214,
			'inclusive_OR_expression' => 208,
			'relational_expression' => 200,
			'AND_expression' => 191,
			'multiplicative_expression' => 209,
			'string_literal_list' => 215,
			'logical_AND_expression' => 216,
			'cast_expression' => 217
		}
	},
	{#State 188
		DEFAULT => -77
	},
	{#State 189
		ACTIONS => {
			'EQUAL_OPR' => 82
		},
		DEFAULT => -78
	},
	{#State 190
		ACTIONS => {
			'SIZEOF_TOKEN' => 210,
			'AMP_OPR' => 113,
			'IDENTIFIER_ORG' => 41,
			'INTEGER_LITERAL' => 194,
			'MINUS_OPR' => 137,
			'SQL_TOKEN' => 47,
			'SECTION_TOKEN' => 42,
			'DECLARE_TOKEN' => 48,
			'FLOAT_LITERAL' => 203,
			'ORACLE_TOKEN' => 43,
			'EXEC_TOKEN' => 49,
			'POSTFIX_OPR' => 197,
			'LP_TOKEN' => 198,
			'PLUS_OPR' => 103,
			'CHAR_LITERAL' => 207,
			'ASTARI_OPR' => 130,
			'END_TOKEN' => 50,
			'BEGIN_TOKEN' => 45,
			'PREFIX_OPR' => 109,
			'STRING_LITERAL' => 201,
			'TOOLS_TOKEN' => 51
		},
		GOTOS => {
			'IDENTIFIER' => 205,
			'string_literal_list' => 215,
			'unary_operator' => 190,
			'cast_expression' => 289,
			'primary_expression' => 212,
			'unary_expression' => 286,
			'postfix_expression' => 213
		}
	},
	{#State 191
		ACTIONS => {
			'AMP_OPR' => 290
		},
		DEFAULT => -48
	},
	{#State 192
		DEFAULT => -177
	},
	{#State 193
		DEFAULT => -79
	},
	{#State 194
		DEFAULT => -2
	},
	{#State 195
		ACTIONS => {
			'SIZEOF_TOKEN' => 210,
			'AMP_OPR' => 113,
			'IDENTIFIER_ORG' => 41,
			'INTEGER_LITERAL' => 194,
			'MINUS_OPR' => 137,
			'LCB_TOKEN' => 195,
			'SQL_TOKEN' => 47,
			'LSB_TOKEN' => 292,
			'SECTION_TOKEN' => 42,
			'DECLARE_TOKEN' => 48,
			'FLOAT_LITERAL' => 203,
			'ORACLE_TOKEN' => 43,
			'EXEC_TOKEN' => 49,
			'POSTFIX_OPR' => 197,
			'LP_TOKEN' => 198,
			'DOT_TOKEN' => 294,
			'PLUS_OPR' => 103,
			'CHAR_LITERAL' => 207,
			'ASTARI_OPR' => 130,
			'END_TOKEN' => 50,
			'BEGIN_TOKEN' => 45,
			'PREFIX_OPR' => 109,
			'STRING_LITERAL' => 201,
			'TOOLS_TOKEN' => 51
		},
		GOTOS => {
			'initializer_list' => 297,
			'logical_OR_expression' => 211,
			'conditional_expression' => 202,
			'primary_expression' => 212,
			'designation' => 293,
			'unary_operator' => 190,
			'unary_expression' => 196,
			'equality_expression' => 204,
			'IDENTIFIER' => 205,
			'designator_list' => 295,
			'shift_expression' => 206,
			'postfix_expression' => 213,
			'additive_expression' => 199,
			'exclusive_OR_expression' => 214,
			'designator' => 296,
			'inclusive_OR_expression' => 208,
			'relational_expression' => 200,
			'string_literal_list' => 215,
			'AND_expression' => 191,
			'multiplicative_expression' => 209,
			'logical_AND_expression' => 216,
			'assignment_expression' => 192,
			'cast_expression' => 217,
			'initializer' => 291
		}
	},
	{#State 196
		ACTIONS => {
			'ASSIGN_P_OPR' => 298,
			'ASSIGN_OPR' => 301,
			'EQUAL_OPR' => 300
		},
		DEFAULT => -30,
		GOTOS => {
			'assignment_operator' => 299
		}
	},
	{#State 197
		ACTIONS => {
			'SIZEOF_TOKEN' => 210,
			'AMP_OPR' => 113,
			'IDENTIFIER_ORG' => 41,
			'INTEGER_LITERAL' => 194,
			'MINUS_OPR' => 137,
			'SQL_TOKEN' => 47,
			'SECTION_TOKEN' => 42,
			'DECLARE_TOKEN' => 48,
			'FLOAT_LITERAL' => 203,
			'ORACLE_TOKEN' => 43,
			'EXEC_TOKEN' => 49,
			'POSTFIX_OPR' => 197,
			'LP_TOKEN' => 303,
			'PLUS_OPR' => 103,
			'CHAR_LITERAL' => 207,
			'ASTARI_OPR' => 130,
			'END_TOKEN' => 50,
			'BEGIN_TOKEN' => 45,
			'PREFIX_OPR' => 109,
			'STRING_LITERAL' => 201,
			'TOOLS_TOKEN' => 51
		},
		GOTOS => {
			'IDENTIFIER' => 205,
			'string_literal_list' => 215,
			'unary_operator' => 190,
			'primary_expression' => 212,
			'unary_expression' => 302,
			'postfix_expression' => 213
		}
	},
	{#State 198
		ACTIONS => {
			'SHORT_TOKEN' => 2,
			'ENUM_TOKEN' => 1,
			'IDENTIFIER_ORG' => 41,
			'LONG_TOKEN' => 5,
			'MINUS_OPR' => 137,
			'SECTION_TOKEN' => 42,
			'FLOAT_LITERAL' => 203,
			'ORACLE_TOKEN' => 43,
			'CHAR_TOKEN' => 14,
			'SIGNED_TOKEN' => 13,
			'CONST_TOKEN' => 15,
			'PLUS_OPR' => 103,
			'CHAR_LITERAL' => 207,
			'STRUCT_TOKEN' => 16,
			'TNAME_TOKEN' => 17,
			'UNSIGNED_TOKEN' => 18,
			'BEGIN_TOKEN' => 45,
			'PREFIX_OPR' => 109,
			'FLOAT_TOKEN' => 19,
			'VOLATILE_TOKEN' => 22,
			'SIZEOF_TOKEN' => 210,
			'AMP_OPR' => 113,
			'INTEGER_LITERAL' => 194,
			'VOID_TOKEN' => 24,
			'SQL_TOKEN' => 47,
			'DOUBLE_TOKEN' => 26,
			'INT_TOKEN' => 28,
			'_BOOL_TOKEN' => 29,
			'DECLARE_TOKEN' => 48,
			'EXEC_TOKEN' => 49,
			'POSTFIX_OPR' => 197,
			'LP_TOKEN' => 198,
			'_COMPLEX_TOKEN' => 34,
			'RESTRICT_TOKEN' => 37,
			'UNION_TOKEN' => 38,
			'ASTARI_OPR' => 130,
			'END_TOKEN' => 50,
			'STRING_LITERAL' => 201,
			'TOOLS_TOKEN' => 51
		},
		GOTOS => {
			'logical_OR_expression' => 211,
			'conditional_expression' => 202,
			'primary_expression' => 212,
			'struct_or_union_specifier' => 30,
			'expression' => 305,
			'type_qualifier' => 181,
			'unary_operator' => 190,
			'unary_expression' => 196,
			'enum_specifier' => 32,
			'specifier_qualifier_list' => 306,
			'type_name' => 304,
			'struct_or_union' => 35,
			'equality_expression' => 204,
			'IDENTIFIER' => 205,
			'shift_expression' => 206,
			'postfix_expression' => 213,
			'additive_expression' => 199,
			'exclusive_OR_expression' => 214,
			'inclusive_OR_expression' => 208,
			'relational_expression' => 200,
			'string_literal_list' => 215,
			'type_specifier' => 180,
			'AND_expression' => 191,
			'multiplicative_expression' => 209,
			'logical_AND_expression' => 216,
			'assignment_expression' => 224,
			'cast_expression' => 217
		}
	},
	{#State 199
		ACTIONS => {
			'MINUS_OPR' => 308,
			'PLUS_OPR' => 307
		},
		DEFAULT => -38
	},
	{#State 200
		ACTIONS => {
			'GT_OPR' => 309,
			'RELATIONAL_OPR' => 310,
			'LT_OPR' => 311
		},
		DEFAULT => -44
	},
	{#State 201
		DEFAULT => -7
	},
	{#State 202
		DEFAULT => -58
	},
	{#State 203
		DEFAULT => -3
	},
	{#State 204
		ACTIONS => {
			'EQUALITY_OPR' => 312
		},
		DEFAULT => -46
	},
	{#State 205
		DEFAULT => -1
	},
	{#State 206
		ACTIONS => {
			'SHIFT_OPR' => 313
		},
		DEFAULT => -40
	},
	{#State 207
		DEFAULT => -4
	},
	{#State 208
		ACTIONS => {
			'OR_OPR' => 314
		},
		DEFAULT => -52
	},
	{#State 209
		ACTIONS => {
			'MULTI_OPR' => 315,
			'ASTARI_OPR' => 316
		},
		DEFAULT => -35
	},
	{#State 210
		ACTIONS => {
			'SIZEOF_TOKEN' => 210,
			'AMP_OPR' => 113,
			'IDENTIFIER_ORG' => 41,
			'INTEGER_LITERAL' => 194,
			'MINUS_OPR' => 137,
			'SQL_TOKEN' => 47,
			'SECTION_TOKEN' => 42,
			'DECLARE_TOKEN' => 48,
			'FLOAT_LITERAL' => 203,
			'ORACLE_TOKEN' => 43,
			'EXEC_TOKEN' => 49,
			'POSTFIX_OPR' => 197,
			'LP_TOKEN' => 318,
			'PLUS_OPR' => 103,
			'CHAR_LITERAL' => 207,
			'ASTARI_OPR' => 130,
			'END_TOKEN' => 50,
			'BEGIN_TOKEN' => 45,
			'PREFIX_OPR' => 109,
			'STRING_LITERAL' => 201,
			'TOOLS_TOKEN' => 51
		},
		GOTOS => {
			'IDENTIFIER' => 205,
			'string_literal_list' => 215,
			'unary_operator' => 190,
			'primary_expression' => 212,
			'unary_expression' => 317,
			'postfix_expression' => 213
		}
	},
	{#State 211
		ACTIONS => {
			'COR_OPR' => 319,
			'QUES_TOKEN' => 320
		},
		DEFAULT => -56
	},
	{#State 212
		DEFAULT => -9
	},
	{#State 213
		ACTIONS => {
			'LSB_TOKEN' => 323,
			'PTR_OPR' => 324,
			'POSTFIX_OPR' => 321,
			'LP_TOKEN' => 322,
			'DOT_TOKEN' => 325
		},
		DEFAULT => -20
	},
	{#State 214
		ACTIONS => {
			'NOR_OPR' => 326
		},
		DEFAULT => -50
	},
	{#State 215
		ACTIONS => {
			'STRING_LITERAL' => 327
		},
		DEFAULT => -5
	},
	{#State 216
		ACTIONS => {
			'CAND_OPR' => 328
		},
		DEFAULT => -54
	},
	{#State 217
		DEFAULT => -32
	},
	{#State 218
		DEFAULT => -193
	},
	{#State 219
		ACTIONS => {
			'DEFAULT_TOKEN' => 230,
			'IDENTIFIER_ORG' => 41,
			'MINUS_OPR' => 137,
			'SMC_TOKEN' => 232,
			'SECTION_TOKEN' => 42,
			'DO_TOKEN' => 219,
			'WHILE_TOKEN' => 234,
			'CASE_TOKEN' => 236,
			'FLOAT_LITERAL' => 203,
			'ORACLE_TOKEN' => 43,
			'PLUS_OPR' => 103,
			'FOR_TOKEN' => 221,
			'CHAR_LITERAL' => 207,
			'SWITCH_TOKEN' => 223,
			'BEGIN_TOKEN' => 45,
			'PREFIX_OPR' => 109,
			'SIZEOF_TOKEN' => 210,
			'AMP_OPR' => 113,
			'RETURN_TOKEN' => 226,
			'INTEGER_LITERAL' => 194,
			'LCB_TOKEN' => 83,
			'SQL_TOKEN' => 47,
			'DECLARE_TOKEN' => 48,
			'CONTINUE_TOKEN' => 242,
			'GOTO_TOKEN' => 243,
			'EXEC_TOKEN' => 228,
			'POSTFIX_OPR' => 197,
			'LP_TOKEN' => 198,
			'BREAK_TOKEN' => 244,
			'IF_TOKEN' => 245,
			'ASTARI_OPR' => 130,
			'END_TOKEN' => 50,
			'STRING_LITERAL' => 201,
			'TOOLS_TOKEN' => 51
		},
		GOTOS => {
			'jump_statement' => 241,
			'iteration_statement' => 218,
			'logical_OR_expression' => 211,
			'expression_statement' => 231,
			'conditional_expression' => 202,
			'primary_expression' => 212,
			'embedded_sql' => 233,
			'statement' => 329,
			'expression' => 235,
			'unary_operator' => 190,
			'unary_expression' => 196,
			'equality_expression' => 204,
			'IDENTIFIER' => 239,
			'compound_statement' => 229,
			'labeled_statement' => 246,
			'shift_expression' => 206,
			'postfix_expression' => 213,
			'additive_expression' => 199,
			'exclusive_OR_expression' => 214,
			'inclusive_OR_expression' => 208,
			'relational_expression' => 200,
			'string_literal_list' => 215,
			'multiplicative_expression' => 209,
			'AND_expression' => 191,
			'logical_AND_expression' => 216,
			'assignment_expression' => 224,
			'cast_expression' => 217,
			'selection_statement' => 225
		}
	},
	{#State 220
		DEFAULT => -204
	},
	{#State 221
		ACTIONS => {
			'LP_TOKEN' => 330
		}
	},
	{#State 222
		DEFAULT => -199
	},
	{#State 223
		ACTIONS => {
			'LP_TOKEN' => 331
		}
	},
	{#State 224
		DEFAULT => -63
	},
	{#State 225
		DEFAULT => -192
	},
	{#State 226
		ACTIONS => {
			'SIZEOF_TOKEN' => 210,
			'AMP_OPR' => 113,
			'IDENTIFIER_ORG' => 41,
			'INTEGER_LITERAL' => 194,
			'MINUS_OPR' => 137,
			'SMC_TOKEN' => 332,
			'SQL_TOKEN' => 47,
			'SECTION_TOKEN' => 42,
			'DECLARE_TOKEN' => 48,
			'FLOAT_LITERAL' => 203,
			'ORACLE_TOKEN' => 43,
			'EXEC_TOKEN' => 49,
			'POSTFIX_OPR' => 197,
			'LP_TOKEN' => 198,
			'PLUS_OPR' => 103,
			'CHAR_LITERAL' => 207,
			'ASTARI_OPR' => 130,
			'END_TOKEN' => 50,
			'BEGIN_TOKEN' => 45,
			'PREFIX_OPR' => 109,
			'STRING_LITERAL' => 201,
			'TOOLS_TOKEN' => 51
		},
		GOTOS => {
			'logical_OR_expression' => 211,
			'conditional_expression' => 202,
			'primary_expression' => 212,
			'expression' => 333,
			'unary_operator' => 190,
			'unary_expression' => 196,
			'equality_expression' => 204,
			'IDENTIFIER' => 205,
			'shift_expression' => 206,
			'additive_expression' => 199,
			'postfix_expression' => 213,
			'exclusive_OR_expression' => 214,
			'inclusive_OR_expression' => 208,
			'relational_expression' => 200,
			'string_literal_list' => 215,
			'AND_expression' => 191,
			'multiplicative_expression' => 209,
			'logical_AND_expression' => 216,
			'assignment_expression' => 224,
			'cast_expression' => 217
		}
	},
	{#State 227
		DEFAULT => -203
	},
	{#State 228
		ACTIONS => {
			'SQL_TOKEN' => 68,
			'ORACLE_TOKEN' => 67,
			'TOOLS_TOKEN' => 69
		},
		DEFAULT => -325
	},
	{#State 229
		DEFAULT => -190
	},
	{#State 230
		ACTIONS => {
			'CLN_TOKEN' => 334
		}
	},
	{#State 231
		DEFAULT => -191
	},
	{#State 232
		DEFAULT => -207
	},
	{#State 233
		DEFAULT => -195
	},
	{#State 234
		ACTIONS => {
			'LP_TOKEN' => 335
		}
	},
	{#State 235
		ACTIONS => {
			'CM_TOKEN' => 336,
			'SMC_TOKEN' => 337
		}
	},
	{#State 236
		ACTIONS => {
			'SIZEOF_TOKEN' => 210,
			'AMP_OPR' => 113,
			'IDENTIFIER_ORG' => 41,
			'INTEGER_LITERAL' => 194,
			'MINUS_OPR' => 137,
			'SQL_TOKEN' => 47,
			'SECTION_TOKEN' => 42,
			'DECLARE_TOKEN' => 48,
			'FLOAT_LITERAL' => 203,
			'ORACLE_TOKEN' => 43,
			'EXEC_TOKEN' => 49,
			'POSTFIX_OPR' => 197,
			'LP_TOKEN' => 198,
			'PLUS_OPR' => 103,
			'CHAR_LITERAL' => 207,
			'ASTARI_OPR' => 130,
			'END_TOKEN' => 50,
			'BEGIN_TOKEN' => 45,
			'PREFIX_OPR' => 109,
			'STRING_LITERAL' => 201,
			'TOOLS_TOKEN' => 51
		},
		GOTOS => {
			'logical_OR_expression' => 211,
			'conditional_expression' => 287,
			'primary_expression' => 212,
			'unary_operator' => 190,
			'unary_expression' => 286,
			'equality_expression' => 204,
			'IDENTIFIER' => 205,
			'constant_expression' => 338,
			'shift_expression' => 206,
			'additive_expression' => 199,
			'postfix_expression' => 213,
			'exclusive_OR_expression' => 214,
			'inclusive_OR_expression' => 208,
			'relational_expression' => 200,
			'AND_expression' => 191,
			'multiplicative_expression' => 209,
			'string_literal_list' => 215,
			'logical_AND_expression' => 216,
			'cast_expression' => 217
		}
	},
	{#State 237
		ACTIONS => {
			'DEFAULT_TOKEN' => 230,
			'EXTERN_TOKEN' => 3,
			'SHORT_TOKEN' => 2,
			'ENUM_TOKEN' => 1,
			'IDENTIFIER_ORG' => 41,
			'LONG_TOKEN' => 5,
			'MINUS_OPR' => 137,
			'SMC_TOKEN' => 232,
			'INCLUDEFORDBSYNTAXDIFF_TOKEN' => 6,
			'SECTION_TOKEN' => 42,
			'DO_TOKEN' => 219,
			'INLINE_TOKEN' => 9,
			'WHILE_TOKEN' => 234,
			'CASE_TOKEN' => 236,
			'FLOAT_LITERAL' => 203,
			'ORACLE_TOKEN' => 43,
			'CHAR_TOKEN' => 14,
			'SIGNED_TOKEN' => 13,
			'CONST_TOKEN' => 15,
			'PLUS_OPR' => 103,
			'FOR_TOKEN' => 221,
			'RCB_TOKEN' => 339,
			'CHAR_LITERAL' => 207,
			'STRUCT_TOKEN' => 16,
			'SWITCH_TOKEN' => 223,
			'TNAME_TOKEN' => 17,
			'UNSIGNED_TOKEN' => 18,
			'BEGIN_TOKEN' => 45,
			'PREFIX_OPR' => 109,
			'FLOAT_TOKEN' => 19,
			'AUTO_TOKEN' => 20,
			'SIZEOF_TOKEN' => 210,
			'VOLATILE_TOKEN' => 22,
			'AMP_OPR' => 113,
			'RETURN_TOKEN' => 226,
			'INTEGER_LITERAL' => 194,
			'VOID_TOKEN' => 24,
			'LCB_TOKEN' => 83,
			'SQL_TOKEN' => 47,
			'DOUBLE_TOKEN' => 26,
			'INT_TOKEN' => 28,
			'_BOOL_TOKEN' => 29,
			'CONTINUE_TOKEN' => 242,
			'DECLARE_TOKEN' => 48,
			'GOTO_TOKEN' => 243,
			'TYPEDEF_TOKEN' => 31,
			'EXEC_TOKEN' => 228,
			'POSTFIX_OPR' => 197,
			'LP_TOKEN' => 198,
			'_COMPLEX_TOKEN' => 34,
			'IF_TOKEN' => 245,
			'BREAK_TOKEN' => 244,
			'REGISTER_TOKEN' => 36,
			'RESTRICT_TOKEN' => 37,
			'UNION_TOKEN' => 38,
			'ASTARI_OPR' => 130,
			'END_TOKEN' => 50,
			'STATIC_TOKEN' => 39,
			'STRING_LITERAL' => 201,
			'TOOLS_TOKEN' => 51
		},
		GOTOS => {
			'function_specifier' => 4,
			'iteration_statement' => 218,
			'expression_statement' => 231,
			'conditional_expression' => 202,
			'embedded_sql' => 233,
			'declaration_specifiers' => 81,
			'statement' => 220,
			'expression' => 235,
			'type_qualifier' => 10,
			'storage_class_specifier' => 11,
			'unary_operator' => 190,
			'block_item' => 340,
			'IDENTIFIER' => 239,
			'equality_expression' => 204,
			'shift_expression' => 206,
			'inclusive_OR_expression' => 208,
			'multiplicative_expression' => 209,
			'AND_expression' => 191,
			'assignment_expression' => 224,
			'selection_statement' => 225,
			'preproccess_include' => 240,
			'jump_statement' => 241,
			'logical_OR_expression' => 211,
			'primary_expression' => 212,
			'declaration' => 227,
			'struct_or_union_specifier' => 30,
			'unary_expression' => 196,
			'enum_specifier' => 32,
			'struct_or_union' => 35,
			'compound_statement' => 229,
			'labeled_statement' => 246,
			'postfix_expression' => 213,
			'additive_expression' => 199,
			'exclusive_OR_expression' => 214,
			'relational_expression' => 200,
			'string_literal_list' => 215,
			'type_specifier' => 40,
			'logical_AND_expression' => 216,
			'cast_expression' => 217
		}
	},
	{#State 238
		DEFAULT => -201
	},
	{#State 239
		ACTIONS => {
			'CLN_TOKEN' => 341
		},
		DEFAULT => -1
	},
	{#State 240
		DEFAULT => -205
	},
	{#State 241
		DEFAULT => -194
	},
	{#State 242
		ACTIONS => {
			'SMC_TOKEN' => 342
		}
	},
	{#State 243
		ACTIONS => {
			'IDENTIFIER_ORG' => 41,
			'END_TOKEN' => 50,
			'SQL_TOKEN' => 47,
			'SECTION_TOKEN' => 42,
			'BEGIN_TOKEN' => 45,
			'DECLARE_TOKEN' => 48,
			'EXEC_TOKEN' => 49,
			'TOOLS_TOKEN' => 51,
			'ORACLE_TOKEN' => 43
		},
		GOTOS => {
			'IDENTIFIER' => 343
		}
	},
	{#State 244
		ACTIONS => {
			'SMC_TOKEN' => 344
		}
	},
	{#State 245
		ACTIONS => {
			'LP_TOKEN' => 345
		}
	},
	{#State 246
		DEFAULT => -189
	},
	{#State 247
		DEFAULT => -241
	},
	{#State 248
		DEFAULT => -239
	},
	{#State 249
		DEFAULT => -133
	},
	{#State 250
		ACTIONS => {
			'RSB_TOKEN' => 346
		}
	},
	{#State 251
		ACTIONS => {
			'SIZEOF_TOKEN' => 210,
			'VOLATILE_TOKEN' => 22,
			'AMP_OPR' => 113,
			'IDENTIFIER_ORG' => 41,
			'INTEGER_LITERAL' => 194,
			'MINUS_OPR' => 137,
			'SQL_TOKEN' => 47,
			'SECTION_TOKEN' => 42,
			'DECLARE_TOKEN' => 48,
			'RSB_TOKEN' => 349,
			'FLOAT_LITERAL' => 203,
			'ORACLE_TOKEN' => 43,
			'EXEC_TOKEN' => 49,
			'POSTFIX_OPR' => 197,
			'LP_TOKEN' => 198,
			'CONST_TOKEN' => 15,
			'PLUS_OPR' => 103,
			'RESTRICT_TOKEN' => 37,
			'CHAR_LITERAL' => 207,
			'ASTARI_OPR' => 348,
			'END_TOKEN' => 50,
			'STATIC_TOKEN' => 350,
			'BEGIN_TOKEN' => 45,
			'PREFIX_OPR' => 109,
			'STRING_LITERAL' => 201,
			'TOOLS_TOKEN' => 51
		},
		GOTOS => {
			'logical_OR_expression' => 211,
			'conditional_expression' => 202,
			'primary_expression' => 212,
			'type_qualifier' => 262,
			'unary_operator' => 190,
			'unary_expression' => 196,
			'equality_expression' => 204,
			'IDENTIFIER' => 205,
			'shift_expression' => 206,
			'additive_expression' => 199,
			'postfix_expression' => 213,
			'exclusive_OR_expression' => 214,
			'inclusive_OR_expression' => 208,
			'relational_expression' => 200,
			'string_literal_list' => 215,
			'AND_expression' => 191,
			'multiplicative_expression' => 209,
			'logical_AND_expression' => 216,
			'assignment_expression' => 347,
			'cast_expression' => 217
		}
	},
	{#State 252
		ACTIONS => {
			'RSB_TOKEN' => 351
		},
		DEFAULT => -26
	},
	{#State 253
		DEFAULT => -137
	},
	{#State 254
		ACTIONS => {
			'SIZEOF_TOKEN' => 210,
			'VOLATILE_TOKEN' => 22,
			'AMP_OPR' => 113,
			'IDENTIFIER_ORG' => 41,
			'INTEGER_LITERAL' => 194,
			'MINUS_OPR' => 137,
			'SQL_TOKEN' => 47,
			'SECTION_TOKEN' => 42,
			'DECLARE_TOKEN' => 48,
			'FLOAT_LITERAL' => 203,
			'ORACLE_TOKEN' => 43,
			'EXEC_TOKEN' => 49,
			'POSTFIX_OPR' => 197,
			'LP_TOKEN' => 198,
			'CONST_TOKEN' => 15,
			'PLUS_OPR' => 103,
			'RESTRICT_TOKEN' => 37,
			'CHAR_LITERAL' => 207,
			'ASTARI_OPR' => 130,
			'END_TOKEN' => 50,
			'BEGIN_TOKEN' => 45,
			'PREFIX_OPR' => 109,
			'STRING_LITERAL' => 201,
			'TOOLS_TOKEN' => 51
		},
		GOTOS => {
			'logical_OR_expression' => 211,
			'conditional_expression' => 202,
			'primary_expression' => 212,
			'type_qualifier_list' => 353,
			'type_qualifier' => 90,
			'unary_operator' => 190,
			'unary_expression' => 196,
			'equality_expression' => 204,
			'IDENTIFIER' => 205,
			'shift_expression' => 206,
			'postfix_expression' => 213,
			'additive_expression' => 199,
			'exclusive_OR_expression' => 214,
			'inclusive_OR_expression' => 208,
			'relational_expression' => 200,
			'string_literal_list' => 215,
			'AND_expression' => 191,
			'multiplicative_expression' => 209,
			'logical_AND_expression' => 216,
			'assignment_expression' => 352,
			'cast_expression' => 217
		}
	},
	{#State 255
		DEFAULT => -154
	},
	{#State 256
		ACTIONS => {
			'IDENTIFIER_ORG' => 41,
			'ASTARI_OPR' => 62,
			'END_TOKEN' => 50,
			'SQL_TOKEN' => 47,
			'LSB_TOKEN' => 357,
			'SECTION_TOKEN' => 42,
			'DECLARE_TOKEN' => 48,
			'BEGIN_TOKEN' => 45,
			'EXEC_TOKEN' => 49,
			'LP_TOKEN' => 355,
			'TOOLS_TOKEN' => 51,
			'ORACLE_TOKEN' => 43
		},
		DEFAULT => -158,
		GOTOS => {
			'direct_declarator' => 61,
			'direct_abstract_declarator' => 358,
			'IDENTIFIER' => 56,
			'pointer' => 359,
			'declarator' => 354,
			'abstract_declarator' => 356
		}
	},
	{#State 257
		ACTIONS => {
			'CM_TOKEN' => 360,
			'RP_TOKEN' => 361
		}
	},
	{#State 258
		DEFAULT => -145
	},
	{#State 259
		DEFAULT => -159
	},
	{#State 260
		ACTIONS => {
			'CM_TOKEN' => 362
		},
		DEFAULT => -152
	},
	{#State 261
		ACTIONS => {
			'RP_TOKEN' => 363
		}
	},
	{#State 262
		DEFAULT => -151
	},
	{#State 263
		DEFAULT => -148
	},
	{#State 264
		DEFAULT => -256
	},
	{#State 265
		DEFAULT => -255
	},
	{#State 266
		DEFAULT => -249
	},
	{#State 267
		ACTIONS => {
			'CM_TOKEN' => -266,
			'PUBLIC_TOKEN' => -266,
			'CLN_TOKEN' => -266,
			'RP_TOKEN' => -266,
			'COR_OPR' => -266,
			'GT_OPR' => -266,
			'MULTI_OPR' => -266,
			'PRIVATE_TOKEN' => -266,
			'ATMARK_TOKEN' => -266,
			'INEQUALITY_OPR' => -266,
			'LSB_TOKEN' => -266,
			'PTR_OPR' => -266,
			'DOT_TOKEN' => -266,
			'EQUAL_OPR' => -266,
			'_IMAGINARY_TOKEN' => -266,
			'PROTECTED_TOKEN' => -266,
			'RSB_TOKEN' => -266,
			'ASSIGN_OPR' => -266,
			'EQUALITY_OPR' => -266,
			'RELATIONAL_OPR' => -266,
			'NEW_TOKEN' => -266,
			'LT_OPR' => -266,
			'QUES_TOKEN' => -266
		},
		DEFAULT => -244
	},
	{#State 268
		ACTIONS => {
			'CM_TOKEN' => -266,
			'PUBLIC_TOKEN' => -266,
			'CLN_TOKEN' => -266,
			'RP_TOKEN' => -266,
			'COR_OPR' => -266,
			'GT_OPR' => -266,
			'MULTI_OPR' => -266,
			'PRIVATE_TOKEN' => -266,
			'ATMARK_TOKEN' => -266,
			'INEQUALITY_OPR' => -266,
			'LSB_TOKEN' => -266,
			'PTR_OPR' => -266,
			'DOT_TOKEN' => -266,
			'EQUAL_OPR' => -266,
			'_IMAGINARY_TOKEN' => -266,
			'PROTECTED_TOKEN' => -266,
			'RSB_TOKEN' => -266,
			'ASSIGN_OPR' => -266,
			'EQUALITY_OPR' => -266,
			'RELATIONAL_OPR' => -266,
			'NEW_TOKEN' => -266,
			'LT_OPR' => -266,
			'QUES_TOKEN' => -266
		},
		DEFAULT => -243
	},
	{#State 269
		DEFAULT => -242
	},
	{#State 270
		ACTIONS => {
			'SECTION_TOKEN' => 364
		}
	},
	{#State 271
		ACTIONS => {
			'SECTION_TOKEN' => 365
		}
	},
	{#State 272
		ACTIONS => {
			'CM_TOKEN' => -266,
			'PUBLIC_TOKEN' => -266,
			'CLN_TOKEN' => -266,
			'RP_TOKEN' => -266,
			'COR_OPR' => -266,
			'GT_OPR' => -266,
			'MULTI_OPR' => -266,
			'PRIVATE_TOKEN' => -266,
			'ATMARK_TOKEN' => -266,
			'INEQUALITY_OPR' => -266,
			'LSB_TOKEN' => -266,
			'PTR_OPR' => -266,
			'DOT_TOKEN' => -266,
			'EQUAL_OPR' => -266,
			'_IMAGINARY_TOKEN' => -266,
			'PROTECTED_TOKEN' => -266,
			'RSB_TOKEN' => -266,
			'ASSIGN_OPR' => -266,
			'EQUALITY_OPR' => -266,
			'RELATIONAL_OPR' => -266,
			'NEW_TOKEN' => -266,
			'LT_OPR' => -266,
			'QUES_TOKEN' => -266
		},
		DEFAULT => -245
	},
	{#State 273
		ACTIONS => {
			'VOLATILE_TOKEN' => 22,
			'SHORT_TOKEN' => 2,
			'ENUM_TOKEN' => 1,
			'LONG_TOKEN' => 5,
			'VOID_TOKEN' => 24,
			'DOUBLE_TOKEN' => 26,
			'INT_TOKEN' => 28,
			'_BOOL_TOKEN' => 29,
			'_COMPLEX_TOKEN' => 34,
			'SIGNED_TOKEN' => 13,
			'CHAR_TOKEN' => 14,
			'CONST_TOKEN' => 15,
			'RCB_TOKEN' => 366,
			'RESTRICT_TOKEN' => 37,
			'UNION_TOKEN' => 38,
			'STRUCT_TOKEN' => 16,
			'UNSIGNED_TOKEN' => 18,
			'TNAME_TOKEN' => 17,
			'FLOAT_TOKEN' => 19
		},
		GOTOS => {
			'struct_or_union' => 35,
			'struct_or_union_specifier' => 30,
			'type_qualifier' => 181,
			'type_specifier' => 180,
			'enum_specifier' => 32,
			'specifier_qualifier_list' => 182,
			'struct_declaration' => 281
		}
	},
	{#State 274
		DEFAULT => -107
	},
	{#State 275
		DEFAULT => -109
	},
	{#State 276
		ACTIONS => {
			'SIZEOF_TOKEN' => 210,
			'AMP_OPR' => 113,
			'IDENTIFIER_ORG' => 41,
			'INTEGER_LITERAL' => 194,
			'MINUS_OPR' => 137,
			'SQL_TOKEN' => 47,
			'SECTION_TOKEN' => 42,
			'DECLARE_TOKEN' => 48,
			'FLOAT_LITERAL' => 203,
			'ORACLE_TOKEN' => 43,
			'EXEC_TOKEN' => 49,
			'POSTFIX_OPR' => 197,
			'LP_TOKEN' => 198,
			'PLUS_OPR' => 103,
			'CHAR_LITERAL' => 207,
			'ASTARI_OPR' => 130,
			'END_TOKEN' => 50,
			'BEGIN_TOKEN' => 45,
			'PREFIX_OPR' => 109,
			'STRING_LITERAL' => 201,
			'TOOLS_TOKEN' => 51
		},
		GOTOS => {
			'logical_OR_expression' => 211,
			'conditional_expression' => 287,
			'primary_expression' => 212,
			'unary_operator' => 190,
			'unary_expression' => 286,
			'equality_expression' => 204,
			'IDENTIFIER' => 205,
			'constant_expression' => 367,
			'shift_expression' => 206,
			'additive_expression' => 199,
			'postfix_expression' => 213,
			'exclusive_OR_expression' => 214,
			'inclusive_OR_expression' => 208,
			'relational_expression' => 200,
			'AND_expression' => 191,
			'multiplicative_expression' => 209,
			'string_literal_list' => 215,
			'logical_AND_expression' => 216,
			'cast_expression' => 217
		}
	},
	{#State 277
		ACTIONS => {
			'CLN_TOKEN' => 368
		},
		DEFAULT => -113
	},
	{#State 278
		ACTIONS => {
			'CM_TOKEN' => 369,
			'SMC_TOKEN' => 370
		}
	},
	{#State 279
		DEFAULT => -111
	},
	{#State 280
		DEFAULT => -100
	},
	{#State 281
		DEFAULT => -105
	},
	{#State 282
		ACTIONS => {
			'RCB_TOKEN' => 371,
			'IDENTIFIER_ORG' => 41,
			'END_TOKEN' => 50,
			'SQL_TOKEN' => 47,
			'SECTION_TOKEN' => 42,
			'BEGIN_TOKEN' => 45,
			'DECLARE_TOKEN' => 48,
			'EXEC_TOKEN' => 49,
			'TOOLS_TOKEN' => 51,
			'ORACLE_TOKEN' => 43
		},
		GOTOS => {
			'enumeration_constant' => 77,
			'IDENTIFIER' => 75,
			'enumerator' => 284
		}
	},
	{#State 283
		DEFAULT => -116
	},
	{#State 284
		DEFAULT => -122
	},
	{#State 285
		DEFAULT => -119
	},
	{#State 286
		DEFAULT => -30
	},
	{#State 287
		DEFAULT => -65
	},
	{#State 288
		DEFAULT => -124
	},
	{#State 289
		DEFAULT => -22
	},
	{#State 290
		ACTIONS => {
			'SIZEOF_TOKEN' => 210,
			'AMP_OPR' => 113,
			'IDENTIFIER_ORG' => 41,
			'INTEGER_LITERAL' => 194,
			'MINUS_OPR' => 137,
			'SQL_TOKEN' => 47,
			'SECTION_TOKEN' => 42,
			'DECLARE_TOKEN' => 48,
			'FLOAT_LITERAL' => 203,
			'ORACLE_TOKEN' => 43,
			'EXEC_TOKEN' => 49,
			'POSTFIX_OPR' => 197,
			'LP_TOKEN' => 198,
			'PLUS_OPR' => 103,
			'CHAR_LITERAL' => 207,
			'ASTARI_OPR' => 130,
			'END_TOKEN' => 50,
			'BEGIN_TOKEN' => 45,
			'PREFIX_OPR' => 109,
			'STRING_LITERAL' => 201,
			'TOOLS_TOKEN' => 51
		},
		GOTOS => {
			'equality_expression' => 372,
			'IDENTIFIER' => 205,
			'primary_expression' => 212,
			'shift_expression' => 206,
			'postfix_expression' => 213,
			'additive_expression' => 199,
			'relational_expression' => 200,
			'string_literal_list' => 215,
			'multiplicative_expression' => 209,
			'unary_operator' => 190,
			'cast_expression' => 217,
			'unary_expression' => 286
		}
	},
	{#State 291
		DEFAULT => -181
	},
	{#State 292
		ACTIONS => {
			'SIZEOF_TOKEN' => 210,
			'AMP_OPR' => 113,
			'IDENTIFIER_ORG' => 41,
			'INTEGER_LITERAL' => 194,
			'MINUS_OPR' => 137,
			'SQL_TOKEN' => 47,
			'SECTION_TOKEN' => 42,
			'DECLARE_TOKEN' => 48,
			'FLOAT_LITERAL' => 203,
			'ORACLE_TOKEN' => 43,
			'EXEC_TOKEN' => 49,
			'POSTFIX_OPR' => 197,
			'LP_TOKEN' => 198,
			'PLUS_OPR' => 103,
			'CHAR_LITERAL' => 207,
			'ASTARI_OPR' => 130,
			'END_TOKEN' => 50,
			'BEGIN_TOKEN' => 45,
			'PREFIX_OPR' => 109,
			'STRING_LITERAL' => 201,
			'TOOLS_TOKEN' => 51
		},
		GOTOS => {
			'logical_OR_expression' => 211,
			'conditional_expression' => 287,
			'primary_expression' => 212,
			'unary_operator' => 190,
			'unary_expression' => 286,
			'equality_expression' => 204,
			'IDENTIFIER' => 205,
			'constant_expression' => 373,
			'shift_expression' => 206,
			'additive_expression' => 199,
			'postfix_expression' => 213,
			'exclusive_OR_expression' => 214,
			'inclusive_OR_expression' => 208,
			'relational_expression' => 200,
			'AND_expression' => 191,
			'multiplicative_expression' => 209,
			'string_literal_list' => 215,
			'logical_AND_expression' => 216,
			'cast_expression' => 217
		}
	},
	{#State 293
		ACTIONS => {
			'SIZEOF_TOKEN' => 210,
			'AMP_OPR' => 113,
			'IDENTIFIER_ORG' => 41,
			'INTEGER_LITERAL' => 194,
			'MINUS_OPR' => 137,
			'LCB_TOKEN' => 195,
			'SQL_TOKEN' => 47,
			'SECTION_TOKEN' => 42,
			'DECLARE_TOKEN' => 48,
			'FLOAT_LITERAL' => 203,
			'ORACLE_TOKEN' => 43,
			'EXEC_TOKEN' => 49,
			'POSTFIX_OPR' => 197,
			'LP_TOKEN' => 198,
			'PLUS_OPR' => 103,
			'CHAR_LITERAL' => 207,
			'ASTARI_OPR' => 130,
			'END_TOKEN' => 50,
			'BEGIN_TOKEN' => 45,
			'PREFIX_OPR' => 109,
			'STRING_LITERAL' => 201,
			'TOOLS_TOKEN' => 51
		},
		GOTOS => {
			'logical_OR_expression' => 211,
			'conditional_expression' => 202,
			'primary_expression' => 212,
			'unary_operator' => 190,
			'unary_expression' => 196,
			'equality_expression' => 204,
			'IDENTIFIER' => 205,
			'shift_expression' => 206,
			'additive_expression' => 199,
			'postfix_expression' => 213,
			'exclusive_OR_expression' => 214,
			'inclusive_OR_expression' => 208,
			'relational_expression' => 200,
			'string_literal_list' => 215,
			'AND_expression' => 191,
			'multiplicative_expression' => 209,
			'logical_AND_expression' => 216,
			'assignment_expression' => 192,
			'cast_expression' => 217,
			'initializer' => 374
		}
	},
	{#State 294
		ACTIONS => {
			'IDENTIFIER_ORG' => 41,
			'END_TOKEN' => 50,
			'SQL_TOKEN' => 47,
			'SECTION_TOKEN' => 42,
			'BEGIN_TOKEN' => 45,
			'DECLARE_TOKEN' => 48,
			'EXEC_TOKEN' => 49,
			'TOOLS_TOKEN' => 51,
			'ORACLE_TOKEN' => 43
		},
		GOTOS => {
			'IDENTIFIER' => 375
		}
	},
	{#State 295
		ACTIONS => {
			'EQUAL_OPR' => 377,
			'DOT_TOKEN' => 294,
			'LSB_TOKEN' => 292
		},
		GOTOS => {
			'designator' => 376
		}
	},
	{#State 296
		DEFAULT => -185
	},
	{#State 297
		ACTIONS => {
			'CM_TOKEN' => 378,
			'RCB_TOKEN' => 379
		}
	},
	{#State 298
		DEFAULT => -62
	},
	{#State 299
		ACTIONS => {
			'SIZEOF_TOKEN' => 210,
			'AMP_OPR' => 113,
			'IDENTIFIER_ORG' => 41,
			'INTEGER_LITERAL' => 194,
			'MINUS_OPR' => 137,
			'SQL_TOKEN' => 47,
			'SECTION_TOKEN' => 42,
			'DECLARE_TOKEN' => 48,
			'FLOAT_LITERAL' => 203,
			'ORACLE_TOKEN' => 43,
			'EXEC_TOKEN' => 49,
			'POSTFIX_OPR' => 197,
			'LP_TOKEN' => 198,
			'PLUS_OPR' => 103,
			'CHAR_LITERAL' => 207,
			'ASTARI_OPR' => 130,
			'END_TOKEN' => 50,
			'BEGIN_TOKEN' => 45,
			'PREFIX_OPR' => 109,
			'STRING_LITERAL' => 201,
			'TOOLS_TOKEN' => 51
		},
		GOTOS => {
			'logical_OR_expression' => 211,
			'conditional_expression' => 202,
			'primary_expression' => 212,
			'unary_operator' => 190,
			'unary_expression' => 196,
			'equality_expression' => 204,
			'IDENTIFIER' => 205,
			'shift_expression' => 206,
			'additive_expression' => 199,
			'postfix_expression' => 213,
			'exclusive_OR_expression' => 214,
			'inclusive_OR_expression' => 208,
			'relational_expression' => 200,
			'AND_expression' => 191,
			'multiplicative_expression' => 209,
			'string_literal_list' => 215,
			'logical_AND_expression' => 216,
			'assignment_expression' => 380,
			'cast_expression' => 217
		}
	},
	{#State 300
		DEFAULT => -60
	},
	{#State 301
		DEFAULT => -61
	},
	{#State 302
		DEFAULT => -21
	},
	{#State 303
		ACTIONS => {
			'SHORT_TOKEN' => 2,
			'ENUM_TOKEN' => 1,
			'IDENTIFIER_ORG' => 41,
			'LONG_TOKEN' => 5,
			'MINUS_OPR' => 137,
			'SECTION_TOKEN' => 42,
			'FLOAT_LITERAL' => 203,
			'ORACLE_TOKEN' => 43,
			'CHAR_TOKEN' => 14,
			'SIGNED_TOKEN' => 13,
			'CONST_TOKEN' => 15,
			'PLUS_OPR' => 103,
			'CHAR_LITERAL' => 207,
			'STRUCT_TOKEN' => 16,
			'TNAME_TOKEN' => 17,
			'UNSIGNED_TOKEN' => 18,
			'BEGIN_TOKEN' => 45,
			'PREFIX_OPR' => 109,
			'FLOAT_TOKEN' => 19,
			'VOLATILE_TOKEN' => 22,
			'SIZEOF_TOKEN' => 210,
			'AMP_OPR' => 113,
			'INTEGER_LITERAL' => 194,
			'VOID_TOKEN' => 24,
			'SQL_TOKEN' => 47,
			'DOUBLE_TOKEN' => 26,
			'INT_TOKEN' => 28,
			'_BOOL_TOKEN' => 29,
			'DECLARE_TOKEN' => 48,
			'EXEC_TOKEN' => 49,
			'POSTFIX_OPR' => 197,
			'LP_TOKEN' => 198,
			'_COMPLEX_TOKEN' => 34,
			'RESTRICT_TOKEN' => 37,
			'UNION_TOKEN' => 38,
			'ASTARI_OPR' => 130,
			'END_TOKEN' => 50,
			'STRING_LITERAL' => 201,
			'TOOLS_TOKEN' => 51
		},
		GOTOS => {
			'logical_OR_expression' => 211,
			'conditional_expression' => 202,
			'primary_expression' => 212,
			'struct_or_union_specifier' => 30,
			'expression' => 305,
			'type_qualifier' => 181,
			'unary_operator' => 190,
			'unary_expression' => 196,
			'enum_specifier' => 32,
			'specifier_qualifier_list' => 306,
			'type_name' => 381,
			'struct_or_union' => 35,
			'equality_expression' => 204,
			'IDENTIFIER' => 205,
			'shift_expression' => 206,
			'postfix_expression' => 213,
			'additive_expression' => 199,
			'exclusive_OR_expression' => 214,
			'inclusive_OR_expression' => 208,
			'relational_expression' => 200,
			'string_literal_list' => 215,
			'type_specifier' => 180,
			'AND_expression' => 191,
			'multiplicative_expression' => 209,
			'logical_AND_expression' => 216,
			'assignment_expression' => 224,
			'cast_expression' => 217
		}
	},
	{#State 304
		ACTIONS => {
			'RP_TOKEN' => 382
		}
	},
	{#State 305
		ACTIONS => {
			'CM_TOKEN' => 336,
			'RP_TOKEN' => 383
		}
	},
	{#State 306
		ACTIONS => {
			'LSB_TOKEN' => 357,
			'ASTARI_OPR' => 62,
			'LP_TOKEN' => 384
		},
		DEFAULT => -162,
		GOTOS => {
			'direct_abstract_declarator' => 358,
			'pointer' => 386,
			'abstract_declarator' => 385
		}
	},
	{#State 307
		ACTIONS => {
			'SIZEOF_TOKEN' => 210,
			'AMP_OPR' => 113,
			'IDENTIFIER_ORG' => 41,
			'INTEGER_LITERAL' => 194,
			'MINUS_OPR' => 137,
			'SQL_TOKEN' => 47,
			'SECTION_TOKEN' => 42,
			'DECLARE_TOKEN' => 48,
			'FLOAT_LITERAL' => 203,
			'ORACLE_TOKEN' => 43,
			'EXEC_TOKEN' => 49,
			'POSTFIX_OPR' => 197,
			'LP_TOKEN' => 198,
			'PLUS_OPR' => 103,
			'CHAR_LITERAL' => 207,
			'ASTARI_OPR' => 130,
			'END_TOKEN' => 50,
			'BEGIN_TOKEN' => 45,
			'PREFIX_OPR' => 109,
			'STRING_LITERAL' => 201,
			'TOOLS_TOKEN' => 51
		},
		GOTOS => {
			'IDENTIFIER' => 205,
			'primary_expression' => 212,
			'postfix_expression' => 213,
			'multiplicative_expression' => 387,
			'string_literal_list' => 215,
			'unary_operator' => 190,
			'unary_expression' => 286,
			'cast_expression' => 217
		}
	},
	{#State 308
		ACTIONS => {
			'SIZEOF_TOKEN' => 210,
			'AMP_OPR' => 113,
			'IDENTIFIER_ORG' => 41,
			'INTEGER_LITERAL' => 194,
			'MINUS_OPR' => 137,
			'SQL_TOKEN' => 47,
			'SECTION_TOKEN' => 42,
			'DECLARE_TOKEN' => 48,
			'FLOAT_LITERAL' => 203,
			'ORACLE_TOKEN' => 43,
			'EXEC_TOKEN' => 49,
			'POSTFIX_OPR' => 197,
			'LP_TOKEN' => 198,
			'PLUS_OPR' => 103,
			'CHAR_LITERAL' => 207,
			'ASTARI_OPR' => 130,
			'END_TOKEN' => 50,
			'BEGIN_TOKEN' => 45,
			'PREFIX_OPR' => 109,
			'STRING_LITERAL' => 201,
			'TOOLS_TOKEN' => 51
		},
		GOTOS => {
			'IDENTIFIER' => 205,
			'primary_expression' => 212,
			'postfix_expression' => 213,
			'multiplicative_expression' => 388,
			'string_literal_list' => 215,
			'unary_operator' => 190,
			'unary_expression' => 286,
			'cast_expression' => 217
		}
	},
	{#State 309
		ACTIONS => {
			'SIZEOF_TOKEN' => 210,
			'AMP_OPR' => 113,
			'IDENTIFIER_ORG' => 41,
			'INTEGER_LITERAL' => 194,
			'MINUS_OPR' => 137,
			'SQL_TOKEN' => 47,
			'SECTION_TOKEN' => 42,
			'DECLARE_TOKEN' => 48,
			'FLOAT_LITERAL' => 203,
			'ORACLE_TOKEN' => 43,
			'EXEC_TOKEN' => 49,
			'POSTFIX_OPR' => 197,
			'LP_TOKEN' => 198,
			'PLUS_OPR' => 103,
			'CHAR_LITERAL' => 207,
			'ASTARI_OPR' => 130,
			'END_TOKEN' => 50,
			'BEGIN_TOKEN' => 45,
			'PREFIX_OPR' => 109,
			'STRING_LITERAL' => 201,
			'TOOLS_TOKEN' => 51
		},
		GOTOS => {
			'IDENTIFIER' => 205,
			'primary_expression' => 212,
			'shift_expression' => 389,
			'postfix_expression' => 213,
			'additive_expression' => 199,
			'string_literal_list' => 215,
			'multiplicative_expression' => 209,
			'unary_operator' => 190,
			'cast_expression' => 217,
			'unary_expression' => 286
		}
	},
	{#State 310
		ACTIONS => {
			'SIZEOF_TOKEN' => 210,
			'AMP_OPR' => 113,
			'IDENTIFIER_ORG' => 41,
			'INTEGER_LITERAL' => 194,
			'MINUS_OPR' => 137,
			'SQL_TOKEN' => 47,
			'SECTION_TOKEN' => 42,
			'DECLARE_TOKEN' => 48,
			'FLOAT_LITERAL' => 203,
			'ORACLE_TOKEN' => 43,
			'EXEC_TOKEN' => 49,
			'POSTFIX_OPR' => 197,
			'LP_TOKEN' => 198,
			'PLUS_OPR' => 103,
			'CHAR_LITERAL' => 207,
			'ASTARI_OPR' => 130,
			'END_TOKEN' => 50,
			'BEGIN_TOKEN' => 45,
			'PREFIX_OPR' => 109,
			'STRING_LITERAL' => 201,
			'TOOLS_TOKEN' => 51
		},
		GOTOS => {
			'IDENTIFIER' => 205,
			'primary_expression' => 212,
			'shift_expression' => 390,
			'postfix_expression' => 213,
			'additive_expression' => 199,
			'string_literal_list' => 215,
			'multiplicative_expression' => 209,
			'unary_operator' => 190,
			'cast_expression' => 217,
			'unary_expression' => 286
		}
	},
	{#State 311
		ACTIONS => {
			'SIZEOF_TOKEN' => 210,
			'AMP_OPR' => 113,
			'IDENTIFIER_ORG' => 41,
			'INTEGER_LITERAL' => 194,
			'MINUS_OPR' => 137,
			'SQL_TOKEN' => 47,
			'SECTION_TOKEN' => 42,
			'DECLARE_TOKEN' => 48,
			'FLOAT_LITERAL' => 203,
			'ORACLE_TOKEN' => 43,
			'EXEC_TOKEN' => 49,
			'POSTFIX_OPR' => 197,
			'LP_TOKEN' => 198,
			'PLUS_OPR' => 103,
			'CHAR_LITERAL' => 207,
			'ASTARI_OPR' => 130,
			'END_TOKEN' => 50,
			'BEGIN_TOKEN' => 45,
			'PREFIX_OPR' => 109,
			'STRING_LITERAL' => 201,
			'TOOLS_TOKEN' => 51
		},
		GOTOS => {
			'IDENTIFIER' => 205,
			'primary_expression' => 212,
			'shift_expression' => 391,
			'postfix_expression' => 213,
			'additive_expression' => 199,
			'string_literal_list' => 215,
			'multiplicative_expression' => 209,
			'unary_operator' => 190,
			'cast_expression' => 217,
			'unary_expression' => 286
		}
	},
	{#State 312
		ACTIONS => {
			'SIZEOF_TOKEN' => 210,
			'AMP_OPR' => 113,
			'IDENTIFIER_ORG' => 41,
			'INTEGER_LITERAL' => 194,
			'MINUS_OPR' => 137,
			'SQL_TOKEN' => 47,
			'SECTION_TOKEN' => 42,
			'DECLARE_TOKEN' => 48,
			'FLOAT_LITERAL' => 203,
			'ORACLE_TOKEN' => 43,
			'EXEC_TOKEN' => 49,
			'POSTFIX_OPR' => 197,
			'LP_TOKEN' => 198,
			'PLUS_OPR' => 103,
			'CHAR_LITERAL' => 207,
			'ASTARI_OPR' => 130,
			'END_TOKEN' => 50,
			'BEGIN_TOKEN' => 45,
			'PREFIX_OPR' => 109,
			'STRING_LITERAL' => 201,
			'TOOLS_TOKEN' => 51
		},
		GOTOS => {
			'IDENTIFIER' => 205,
			'primary_expression' => 212,
			'shift_expression' => 206,
			'postfix_expression' => 213,
			'additive_expression' => 199,
			'relational_expression' => 392,
			'string_literal_list' => 215,
			'multiplicative_expression' => 209,
			'unary_operator' => 190,
			'cast_expression' => 217,
			'unary_expression' => 286
		}
	},
	{#State 313
		ACTIONS => {
			'SIZEOF_TOKEN' => 210,
			'AMP_OPR' => 113,
			'IDENTIFIER_ORG' => 41,
			'INTEGER_LITERAL' => 194,
			'MINUS_OPR' => 137,
			'SQL_TOKEN' => 47,
			'SECTION_TOKEN' => 42,
			'DECLARE_TOKEN' => 48,
			'FLOAT_LITERAL' => 203,
			'ORACLE_TOKEN' => 43,
			'EXEC_TOKEN' => 49,
			'POSTFIX_OPR' => 197,
			'LP_TOKEN' => 198,
			'PLUS_OPR' => 103,
			'CHAR_LITERAL' => 207,
			'ASTARI_OPR' => 130,
			'END_TOKEN' => 50,
			'BEGIN_TOKEN' => 45,
			'PREFIX_OPR' => 109,
			'STRING_LITERAL' => 201,
			'TOOLS_TOKEN' => 51
		},
		GOTOS => {
			'IDENTIFIER' => 205,
			'primary_expression' => 212,
			'postfix_expression' => 213,
			'additive_expression' => 393,
			'multiplicative_expression' => 209,
			'string_literal_list' => 215,
			'unary_operator' => 190,
			'cast_expression' => 217,
			'unary_expression' => 286
		}
	},
	{#State 314
		ACTIONS => {
			'SIZEOF_TOKEN' => 210,
			'AMP_OPR' => 113,
			'IDENTIFIER_ORG' => 41,
			'INTEGER_LITERAL' => 194,
			'MINUS_OPR' => 137,
			'SQL_TOKEN' => 47,
			'SECTION_TOKEN' => 42,
			'DECLARE_TOKEN' => 48,
			'FLOAT_LITERAL' => 203,
			'ORACLE_TOKEN' => 43,
			'EXEC_TOKEN' => 49,
			'POSTFIX_OPR' => 197,
			'LP_TOKEN' => 198,
			'PLUS_OPR' => 103,
			'CHAR_LITERAL' => 207,
			'ASTARI_OPR' => 130,
			'END_TOKEN' => 50,
			'BEGIN_TOKEN' => 45,
			'PREFIX_OPR' => 109,
			'STRING_LITERAL' => 201,
			'TOOLS_TOKEN' => 51
		},
		GOTOS => {
			'IDENTIFIER' => 205,
			'equality_expression' => 204,
			'primary_expression' => 212,
			'shift_expression' => 206,
			'postfix_expression' => 213,
			'additive_expression' => 199,
			'exclusive_OR_expression' => 394,
			'relational_expression' => 200,
			'string_literal_list' => 215,
			'multiplicative_expression' => 209,
			'AND_expression' => 191,
			'unary_operator' => 190,
			'cast_expression' => 217,
			'unary_expression' => 286
		}
	},
	{#State 315
		ACTIONS => {
			'SIZEOF_TOKEN' => 210,
			'AMP_OPR' => 113,
			'IDENTIFIER_ORG' => 41,
			'INTEGER_LITERAL' => 194,
			'MINUS_OPR' => 137,
			'SQL_TOKEN' => 47,
			'SECTION_TOKEN' => 42,
			'DECLARE_TOKEN' => 48,
			'FLOAT_LITERAL' => 203,
			'ORACLE_TOKEN' => 43,
			'EXEC_TOKEN' => 49,
			'POSTFIX_OPR' => 197,
			'LP_TOKEN' => 198,
			'PLUS_OPR' => 103,
			'CHAR_LITERAL' => 207,
			'ASTARI_OPR' => 130,
			'END_TOKEN' => 50,
			'BEGIN_TOKEN' => 45,
			'PREFIX_OPR' => 109,
			'STRING_LITERAL' => 201,
			'TOOLS_TOKEN' => 51
		},
		GOTOS => {
			'IDENTIFIER' => 205,
			'string_literal_list' => 215,
			'unary_operator' => 190,
			'cast_expression' => 395,
			'primary_expression' => 212,
			'unary_expression' => 286,
			'postfix_expression' => 213
		}
	},
	{#State 316
		ACTIONS => {
			'SIZEOF_TOKEN' => 210,
			'AMP_OPR' => 113,
			'IDENTIFIER_ORG' => 41,
			'INTEGER_LITERAL' => 194,
			'MINUS_OPR' => 137,
			'SQL_TOKEN' => 47,
			'SECTION_TOKEN' => 42,
			'DECLARE_TOKEN' => 48,
			'FLOAT_LITERAL' => 203,
			'ORACLE_TOKEN' => 43,
			'EXEC_TOKEN' => 49,
			'POSTFIX_OPR' => 197,
			'LP_TOKEN' => 198,
			'PLUS_OPR' => 103,
			'CHAR_LITERAL' => 207,
			'ASTARI_OPR' => 130,
			'END_TOKEN' => 50,
			'BEGIN_TOKEN' => 45,
			'PREFIX_OPR' => 109,
			'STRING_LITERAL' => 201,
			'TOOLS_TOKEN' => 51
		},
		GOTOS => {
			'IDENTIFIER' => 205,
			'string_literal_list' => 215,
			'unary_operator' => 190,
			'cast_expression' => 396,
			'primary_expression' => 212,
			'unary_expression' => 286,
			'postfix_expression' => 213
		}
	},
	{#State 317
		DEFAULT => -23
	},
	{#State 318
		ACTIONS => {
			'SHORT_TOKEN' => 2,
			'ENUM_TOKEN' => 1,
			'IDENTIFIER_ORG' => 41,
			'LONG_TOKEN' => 5,
			'MINUS_OPR' => 137,
			'SECTION_TOKEN' => 42,
			'FLOAT_LITERAL' => 203,
			'ORACLE_TOKEN' => 43,
			'CHAR_TOKEN' => 14,
			'SIGNED_TOKEN' => 13,
			'CONST_TOKEN' => 15,
			'PLUS_OPR' => 103,
			'CHAR_LITERAL' => 207,
			'STRUCT_TOKEN' => 16,
			'TNAME_TOKEN' => 17,
			'UNSIGNED_TOKEN' => 18,
			'BEGIN_TOKEN' => 45,
			'PREFIX_OPR' => 109,
			'FLOAT_TOKEN' => 19,
			'VOLATILE_TOKEN' => 22,
			'SIZEOF_TOKEN' => 210,
			'AMP_OPR' => 113,
			'INTEGER_LITERAL' => 194,
			'VOID_TOKEN' => 24,
			'SQL_TOKEN' => 47,
			'DOUBLE_TOKEN' => 26,
			'INT_TOKEN' => 28,
			'_BOOL_TOKEN' => 29,
			'DECLARE_TOKEN' => 48,
			'EXEC_TOKEN' => 49,
			'POSTFIX_OPR' => 197,
			'LP_TOKEN' => 198,
			'_COMPLEX_TOKEN' => 34,
			'RESTRICT_TOKEN' => 37,
			'UNION_TOKEN' => 38,
			'ASTARI_OPR' => 130,
			'END_TOKEN' => 50,
			'STRING_LITERAL' => 201,
			'TOOLS_TOKEN' => 51
		},
		GOTOS => {
			'logical_OR_expression' => 211,
			'conditional_expression' => 202,
			'primary_expression' => 212,
			'struct_or_union_specifier' => 30,
			'expression' => 305,
			'type_qualifier' => 181,
			'unary_operator' => 190,
			'unary_expression' => 196,
			'enum_specifier' => 32,
			'specifier_qualifier_list' => 306,
			'type_name' => 397,
			'struct_or_union' => 35,
			'equality_expression' => 204,
			'IDENTIFIER' => 205,
			'shift_expression' => 206,
			'postfix_expression' => 213,
			'additive_expression' => 199,
			'exclusive_OR_expression' => 214,
			'inclusive_OR_expression' => 208,
			'relational_expression' => 200,
			'string_literal_list' => 215,
			'type_specifier' => 180,
			'AND_expression' => 191,
			'multiplicative_expression' => 209,
			'logical_AND_expression' => 216,
			'assignment_expression' => 224,
			'cast_expression' => 217
		}
	},
	{#State 319
		ACTIONS => {
			'SIZEOF_TOKEN' => 210,
			'AMP_OPR' => 113,
			'IDENTIFIER_ORG' => 41,
			'INTEGER_LITERAL' => 194,
			'MINUS_OPR' => 137,
			'SQL_TOKEN' => 47,
			'SECTION_TOKEN' => 42,
			'DECLARE_TOKEN' => 48,
			'FLOAT_LITERAL' => 203,
			'ORACLE_TOKEN' => 43,
			'EXEC_TOKEN' => 49,
			'POSTFIX_OPR' => 197,
			'LP_TOKEN' => 198,
			'PLUS_OPR' => 103,
			'CHAR_LITERAL' => 207,
			'ASTARI_OPR' => 130,
			'END_TOKEN' => 50,
			'BEGIN_TOKEN' => 45,
			'PREFIX_OPR' => 109,
			'STRING_LITERAL' => 201,
			'TOOLS_TOKEN' => 51
		},
		GOTOS => {
			'primary_expression' => 212,
			'unary_operator' => 190,
			'unary_expression' => 286,
			'equality_expression' => 204,
			'IDENTIFIER' => 205,
			'shift_expression' => 206,
			'additive_expression' => 199,
			'postfix_expression' => 213,
			'exclusive_OR_expression' => 214,
			'inclusive_OR_expression' => 208,
			'relational_expression' => 200,
			'AND_expression' => 191,
			'multiplicative_expression' => 209,
			'string_literal_list' => 215,
			'logical_AND_expression' => 398,
			'cast_expression' => 217
		}
	},
	{#State 320
		ACTIONS => {
			'SIZEOF_TOKEN' => 210,
			'AMP_OPR' => 113,
			'IDENTIFIER_ORG' => 41,
			'INTEGER_LITERAL' => 194,
			'MINUS_OPR' => 137,
			'SQL_TOKEN' => 47,
			'SECTION_TOKEN' => 42,
			'DECLARE_TOKEN' => 48,
			'FLOAT_LITERAL' => 203,
			'ORACLE_TOKEN' => 43,
			'EXEC_TOKEN' => 49,
			'POSTFIX_OPR' => 197,
			'LP_TOKEN' => 198,
			'PLUS_OPR' => 103,
			'CHAR_LITERAL' => 207,
			'ASTARI_OPR' => 130,
			'END_TOKEN' => 50,
			'BEGIN_TOKEN' => 45,
			'PREFIX_OPR' => 109,
			'STRING_LITERAL' => 201,
			'TOOLS_TOKEN' => 51
		},
		GOTOS => {
			'logical_OR_expression' => 211,
			'conditional_expression' => 202,
			'primary_expression' => 212,
			'expression' => 399,
			'unary_operator' => 190,
			'unary_expression' => 196,
			'equality_expression' => 204,
			'IDENTIFIER' => 205,
			'shift_expression' => 206,
			'additive_expression' => 199,
			'postfix_expression' => 213,
			'exclusive_OR_expression' => 214,
			'inclusive_OR_expression' => 208,
			'relational_expression' => 200,
			'string_literal_list' => 215,
			'AND_expression' => 191,
			'multiplicative_expression' => 209,
			'logical_AND_expression' => 216,
			'assignment_expression' => 224,
			'cast_expression' => 217
		}
	},
	{#State 321
		DEFAULT => -15
	},
	{#State 322
		ACTIONS => {
			'SIZEOF_TOKEN' => 210,
			'AMP_OPR' => 113,
			'IDENTIFIER_ORG' => 41,
			'RP_TOKEN' => 401,
			'INTEGER_LITERAL' => 194,
			'MINUS_OPR' => 137,
			'SQL_TOKEN' => 47,
			'SECTION_TOKEN' => 42,
			'DECLARE_TOKEN' => 48,
			'FLOAT_LITERAL' => 203,
			'ORACLE_TOKEN' => 43,
			'EXEC_TOKEN' => 49,
			'POSTFIX_OPR' => 197,
			'LP_TOKEN' => 198,
			'PLUS_OPR' => 103,
			'CHAR_LITERAL' => 207,
			'ASTARI_OPR' => 130,
			'END_TOKEN' => 50,
			'BEGIN_TOKEN' => 45,
			'PREFIX_OPR' => 109,
			'STRING_LITERAL' => 201,
			'TOOLS_TOKEN' => 51
		},
		GOTOS => {
			'logical_OR_expression' => 211,
			'conditional_expression' => 202,
			'primary_expression' => 212,
			'argument_expression_list' => 402,
			'unary_operator' => 190,
			'unary_expression' => 196,
			'equality_expression' => 204,
			'IDENTIFIER' => 205,
			'shift_expression' => 206,
			'additive_expression' => 199,
			'postfix_expression' => 213,
			'exclusive_OR_expression' => 214,
			'inclusive_OR_expression' => 208,
			'relational_expression' => 200,
			'string_literal_list' => 215,
			'AND_expression' => 191,
			'multiplicative_expression' => 209,
			'logical_AND_expression' => 216,
			'assignment_expression' => 400,
			'cast_expression' => 217
		}
	},
	{#State 323
		ACTIONS => {
			'SIZEOF_TOKEN' => 210,
			'AMP_OPR' => 113,
			'IDENTIFIER_ORG' => 41,
			'INTEGER_LITERAL' => 194,
			'MINUS_OPR' => 137,
			'SQL_TOKEN' => 47,
			'SECTION_TOKEN' => 42,
			'DECLARE_TOKEN' => 48,
			'FLOAT_LITERAL' => 203,
			'ORACLE_TOKEN' => 43,
			'EXEC_TOKEN' => 49,
			'POSTFIX_OPR' => 197,
			'LP_TOKEN' => 198,
			'PLUS_OPR' => 103,
			'CHAR_LITERAL' => 207,
			'ASTARI_OPR' => 130,
			'END_TOKEN' => 50,
			'BEGIN_TOKEN' => 45,
			'PREFIX_OPR' => 109,
			'STRING_LITERAL' => 201,
			'TOOLS_TOKEN' => 51
		},
		GOTOS => {
			'logical_OR_expression' => 211,
			'conditional_expression' => 202,
			'primary_expression' => 212,
			'expression' => 403,
			'unary_operator' => 190,
			'unary_expression' => 196,
			'equality_expression' => 204,
			'IDENTIFIER' => 205,
			'shift_expression' => 206,
			'additive_expression' => 199,
			'postfix_expression' => 213,
			'exclusive_OR_expression' => 214,
			'inclusive_OR_expression' => 208,
			'relational_expression' => 200,
			'string_literal_list' => 215,
			'AND_expression' => 191,
			'multiplicative_expression' => 209,
			'logical_AND_expression' => 216,
			'assignment_expression' => 224,
			'cast_expression' => 217
		}
	},
	{#State 324
		ACTIONS => {
			'IDENTIFIER_ORG' => 41,
			'END_TOKEN' => 50,
			'SQL_TOKEN' => 47,
			'SECTION_TOKEN' => 42,
			'BEGIN_TOKEN' => 45,
			'DECLARE_TOKEN' => 48,
			'EXEC_TOKEN' => 49,
			'TOOLS_TOKEN' => 51,
			'ORACLE_TOKEN' => 43
		},
		GOTOS => {
			'IDENTIFIER' => 404
		}
	},
	{#State 325
		ACTIONS => {
			'IDENTIFIER_ORG' => 41,
			'END_TOKEN' => 50,
			'SQL_TOKEN' => 47,
			'SECTION_TOKEN' => 42,
			'BEGIN_TOKEN' => 45,
			'DECLARE_TOKEN' => 48,
			'EXEC_TOKEN' => 49,
			'TOOLS_TOKEN' => 51,
			'ORACLE_TOKEN' => 43
		},
		GOTOS => {
			'IDENTIFIER' => 405
		}
	},
	{#State 326
		ACTIONS => {
			'SIZEOF_TOKEN' => 210,
			'AMP_OPR' => 113,
			'IDENTIFIER_ORG' => 41,
			'INTEGER_LITERAL' => 194,
			'MINUS_OPR' => 137,
			'SQL_TOKEN' => 47,
			'SECTION_TOKEN' => 42,
			'DECLARE_TOKEN' => 48,
			'FLOAT_LITERAL' => 203,
			'ORACLE_TOKEN' => 43,
			'EXEC_TOKEN' => 49,
			'POSTFIX_OPR' => 197,
			'LP_TOKEN' => 198,
			'PLUS_OPR' => 103,
			'CHAR_LITERAL' => 207,
			'ASTARI_OPR' => 130,
			'END_TOKEN' => 50,
			'BEGIN_TOKEN' => 45,
			'PREFIX_OPR' => 109,
			'STRING_LITERAL' => 201,
			'TOOLS_TOKEN' => 51
		},
		GOTOS => {
			'IDENTIFIER' => 205,
			'equality_expression' => 204,
			'primary_expression' => 212,
			'shift_expression' => 206,
			'postfix_expression' => 213,
			'additive_expression' => 199,
			'relational_expression' => 200,
			'string_literal_list' => 215,
			'multiplicative_expression' => 209,
			'AND_expression' => 406,
			'unary_operator' => 190,
			'cast_expression' => 217,
			'unary_expression' => 286
		}
	},
	{#State 327
		DEFAULT => -8
	},
	{#State 328
		ACTIONS => {
			'SIZEOF_TOKEN' => 210,
			'AMP_OPR' => 113,
			'IDENTIFIER_ORG' => 41,
			'INTEGER_LITERAL' => 194,
			'MINUS_OPR' => 137,
			'SQL_TOKEN' => 47,
			'SECTION_TOKEN' => 42,
			'DECLARE_TOKEN' => 48,
			'FLOAT_LITERAL' => 203,
			'ORACLE_TOKEN' => 43,
			'EXEC_TOKEN' => 49,
			'POSTFIX_OPR' => 197,
			'LP_TOKEN' => 198,
			'PLUS_OPR' => 103,
			'CHAR_LITERAL' => 207,
			'ASTARI_OPR' => 130,
			'END_TOKEN' => 50,
			'BEGIN_TOKEN' => 45,
			'PREFIX_OPR' => 109,
			'STRING_LITERAL' => 201,
			'TOOLS_TOKEN' => 51
		},
		GOTOS => {
			'IDENTIFIER' => 205,
			'equality_expression' => 204,
			'primary_expression' => 212,
			'shift_expression' => 206,
			'postfix_expression' => 213,
			'additive_expression' => 199,
			'exclusive_OR_expression' => 214,
			'inclusive_OR_expression' => 407,
			'relational_expression' => 200,
			'string_literal_list' => 215,
			'multiplicative_expression' => 209,
			'AND_expression' => 191,
			'unary_operator' => 190,
			'cast_expression' => 217,
			'unary_expression' => 286
		}
	},
	{#State 329
		ACTIONS => {
			'WHILE_TOKEN' => 408
		}
	},
	{#State 330
		ACTIONS => {
			'EXTERN_TOKEN' => 3,
			'SHORT_TOKEN' => 2,
			'ENUM_TOKEN' => 1,
			'IDENTIFIER_ORG' => 41,
			'LONG_TOKEN' => 5,
			'MINUS_OPR' => 137,
			'SMC_TOKEN' => 410,
			'SECTION_TOKEN' => 42,
			'INLINE_TOKEN' => 9,
			'FLOAT_LITERAL' => 203,
			'ORACLE_TOKEN' => 43,
			'CHAR_TOKEN' => 14,
			'SIGNED_TOKEN' => 13,
			'CONST_TOKEN' => 15,
			'PLUS_OPR' => 103,
			'CHAR_LITERAL' => 207,
			'STRUCT_TOKEN' => 16,
			'TNAME_TOKEN' => 17,
			'UNSIGNED_TOKEN' => 18,
			'BEGIN_TOKEN' => 45,
			'PREFIX_OPR' => 109,
			'FLOAT_TOKEN' => 19,
			'AUTO_TOKEN' => 20,
			'SIZEOF_TOKEN' => 210,
			'VOLATILE_TOKEN' => 22,
			'AMP_OPR' => 113,
			'INTEGER_LITERAL' => 194,
			'VOID_TOKEN' => 24,
			'SQL_TOKEN' => 47,
			'DOUBLE_TOKEN' => 26,
			'INT_TOKEN' => 28,
			'_BOOL_TOKEN' => 29,
			'DECLARE_TOKEN' => 48,
			'TYPEDEF_TOKEN' => 31,
			'EXEC_TOKEN' => 49,
			'POSTFIX_OPR' => 197,
			'LP_TOKEN' => 198,
			'_COMPLEX_TOKEN' => 34,
			'REGISTER_TOKEN' => 36,
			'RESTRICT_TOKEN' => 37,
			'UNION_TOKEN' => 38,
			'ASTARI_OPR' => 130,
			'END_TOKEN' => 50,
			'STATIC_TOKEN' => 39,
			'STRING_LITERAL' => 201,
			'TOOLS_TOKEN' => 51
		},
		GOTOS => {
			'function_specifier' => 4,
			'logical_OR_expression' => 211,
			'conditional_expression' => 202,
			'primary_expression' => 212,
			'declaration_specifiers' => 81,
			'declaration' => 409,
			'struct_or_union_specifier' => 30,
			'expression' => 411,
			'type_qualifier' => 10,
			'storage_class_specifier' => 11,
			'unary_operator' => 190,
			'unary_expression' => 196,
			'enum_specifier' => 32,
			'struct_or_union' => 35,
			'IDENTIFIER' => 205,
			'equality_expression' => 204,
			'shift_expression' => 206,
			'postfix_expression' => 213,
			'additive_expression' => 199,
			'exclusive_OR_expression' => 214,
			'inclusive_OR_expression' => 208,
			'relational_expression' => 200,
			'string_literal_list' => 215,
			'multiplicative_expression' => 209,
			'AND_expression' => 191,
			'type_specifier' => 40,
			'logical_AND_expression' => 216,
			'assignment_expression' => 224,
			'cast_expression' => 217
		}
	},
	{#State 331
		ACTIONS => {
			'SIZEOF_TOKEN' => 210,
			'AMP_OPR' => 113,
			'IDENTIFIER_ORG' => 41,
			'INTEGER_LITERAL' => 194,
			'MINUS_OPR' => 137,
			'SQL_TOKEN' => 47,
			'SECTION_TOKEN' => 42,
			'DECLARE_TOKEN' => 48,
			'FLOAT_LITERAL' => 203,
			'ORACLE_TOKEN' => 43,
			'EXEC_TOKEN' => 49,
			'POSTFIX_OPR' => 197,
			'LP_TOKEN' => 198,
			'PLUS_OPR' => 103,
			'CHAR_LITERAL' => 207,
			'ASTARI_OPR' => 130,
			'END_TOKEN' => 50,
			'BEGIN_TOKEN' => 45,
			'PREFIX_OPR' => 109,
			'STRING_LITERAL' => 201,
			'TOOLS_TOKEN' => 51
		},
		GOTOS => {
			'logical_OR_expression' => 211,
			'conditional_expression' => 202,
			'primary_expression' => 212,
			'expression' => 412,
			'unary_operator' => 190,
			'unary_expression' => 196,
			'equality_expression' => 204,
			'IDENTIFIER' => 205,
			'shift_expression' => 206,
			'additive_expression' => 199,
			'postfix_expression' => 213,
			'exclusive_OR_expression' => 214,
			'inclusive_OR_expression' => 208,
			'relational_expression' => 200,
			'string_literal_list' => 215,
			'AND_expression' => 191,
			'multiplicative_expression' => 209,
			'logical_AND_expression' => 216,
			'assignment_expression' => 224,
			'cast_expression' => 217
		}
	},
	{#State 332
		DEFAULT => -229
	},
	{#State 333
		ACTIONS => {
			'CM_TOKEN' => 336,
			'SMC_TOKEN' => 413
		}
	},
	{#State 334
		ACTIONS => {
			'DEFAULT_TOKEN' => 230,
			'IDENTIFIER_ORG' => 41,
			'MINUS_OPR' => 137,
			'SMC_TOKEN' => 232,
			'SECTION_TOKEN' => 42,
			'DO_TOKEN' => 219,
			'WHILE_TOKEN' => 234,
			'CASE_TOKEN' => 236,
			'FLOAT_LITERAL' => 203,
			'ORACLE_TOKEN' => 43,
			'PLUS_OPR' => 103,
			'FOR_TOKEN' => 221,
			'CHAR_LITERAL' => 207,
			'SWITCH_TOKEN' => 223,
			'BEGIN_TOKEN' => 45,
			'PREFIX_OPR' => 109,
			'SIZEOF_TOKEN' => 210,
			'AMP_OPR' => 113,
			'RETURN_TOKEN' => 226,
			'INTEGER_LITERAL' => 194,
			'LCB_TOKEN' => 83,
			'SQL_TOKEN' => 47,
			'DECLARE_TOKEN' => 48,
			'CONTINUE_TOKEN' => 242,
			'GOTO_TOKEN' => 243,
			'EXEC_TOKEN' => 228,
			'POSTFIX_OPR' => 197,
			'LP_TOKEN' => 198,
			'BREAK_TOKEN' => 244,
			'IF_TOKEN' => 245,
			'ASTARI_OPR' => 130,
			'END_TOKEN' => 50,
			'STRING_LITERAL' => 201,
			'TOOLS_TOKEN' => 51
		},
		GOTOS => {
			'jump_statement' => 241,
			'iteration_statement' => 218,
			'logical_OR_expression' => 211,
			'expression_statement' => 231,
			'conditional_expression' => 202,
			'primary_expression' => 212,
			'embedded_sql' => 233,
			'statement' => 414,
			'expression' => 235,
			'unary_operator' => 190,
			'unary_expression' => 196,
			'equality_expression' => 204,
			'IDENTIFIER' => 239,
			'compound_statement' => 229,
			'labeled_statement' => 246,
			'shift_expression' => 206,
			'postfix_expression' => 213,
			'additive_expression' => 199,
			'exclusive_OR_expression' => 214,
			'inclusive_OR_expression' => 208,
			'relational_expression' => 200,
			'string_literal_list' => 215,
			'multiplicative_expression' => 209,
			'AND_expression' => 191,
			'logical_AND_expression' => 216,
			'assignment_expression' => 224,
			'cast_expression' => 217,
			'selection_statement' => 225
		}
	},
	{#State 335
		ACTIONS => {
			'SIZEOF_TOKEN' => 210,
			'AMP_OPR' => 113,
			'IDENTIFIER_ORG' => 41,
			'INTEGER_LITERAL' => 194,
			'MINUS_OPR' => 137,
			'SQL_TOKEN' => 47,
			'SECTION_TOKEN' => 42,
			'DECLARE_TOKEN' => 48,
			'FLOAT_LITERAL' => 203,
			'ORACLE_TOKEN' => 43,
			'EXEC_TOKEN' => 49,
			'POSTFIX_OPR' => 197,
			'LP_TOKEN' => 198,
			'PLUS_OPR' => 103,
			'CHAR_LITERAL' => 207,
			'ASTARI_OPR' => 130,
			'END_TOKEN' => 50,
			'BEGIN_TOKEN' => 45,
			'PREFIX_OPR' => 109,
			'STRING_LITERAL' => 201,
			'TOOLS_TOKEN' => 51
		},
		GOTOS => {
			'logical_OR_expression' => 211,
			'conditional_expression' => 202,
			'primary_expression' => 212,
			'expression' => 415,
			'unary_operator' => 190,
			'unary_expression' => 196,
			'equality_expression' => 204,
			'IDENTIFIER' => 205,
			'shift_expression' => 206,
			'additive_expression' => 199,
			'postfix_expression' => 213,
			'exclusive_OR_expression' => 214,
			'inclusive_OR_expression' => 208,
			'relational_expression' => 200,
			'string_literal_list' => 215,
			'AND_expression' => 191,
			'multiplicative_expression' => 209,
			'logical_AND_expression' => 216,
			'assignment_expression' => 224,
			'cast_expression' => 217
		}
	},
	{#State 336
		ACTIONS => {
			'SIZEOF_TOKEN' => 210,
			'AMP_OPR' => 113,
			'IDENTIFIER_ORG' => 41,
			'INTEGER_LITERAL' => 194,
			'MINUS_OPR' => 137,
			'SQL_TOKEN' => 47,
			'SECTION_TOKEN' => 42,
			'DECLARE_TOKEN' => 48,
			'FLOAT_LITERAL' => 203,
			'ORACLE_TOKEN' => 43,
			'EXEC_TOKEN' => 49,
			'POSTFIX_OPR' => 197,
			'LP_TOKEN' => 198,
			'PLUS_OPR' => 103,
			'CHAR_LITERAL' => 207,
			'ASTARI_OPR' => 130,
			'END_TOKEN' => 50,
			'BEGIN_TOKEN' => 45,
			'PREFIX_OPR' => 109,
			'STRING_LITERAL' => 201,
			'TOOLS_TOKEN' => 51
		},
		GOTOS => {
			'logical_OR_expression' => 211,
			'conditional_expression' => 202,
			'primary_expression' => 212,
			'unary_operator' => 190,
			'unary_expression' => 196,
			'equality_expression' => 204,
			'IDENTIFIER' => 205,
			'shift_expression' => 206,
			'additive_expression' => 199,
			'postfix_expression' => 213,
			'exclusive_OR_expression' => 214,
			'inclusive_OR_expression' => 208,
			'relational_expression' => 200,
			'AND_expression' => 191,
			'multiplicative_expression' => 209,
			'string_literal_list' => 215,
			'logical_AND_expression' => 216,
			'assignment_expression' => 416,
			'cast_expression' => 217
		}
	},
	{#State 337
		DEFAULT => -206
	},
	{#State 338
		ACTIONS => {
			'CLN_TOKEN' => 417
		}
	},
	{#State 339
		DEFAULT => -200
	},
	{#State 340
		DEFAULT => -202
	},
	{#State 341
		ACTIONS => {
			'DEFAULT_TOKEN' => 230,
			'IDENTIFIER_ORG' => 41,
			'MINUS_OPR' => 137,
			'SMC_TOKEN' => 232,
			'SECTION_TOKEN' => 42,
			'DO_TOKEN' => 219,
			'WHILE_TOKEN' => 234,
			'CASE_TOKEN' => 236,
			'FLOAT_LITERAL' => 203,
			'ORACLE_TOKEN' => 43,
			'PLUS_OPR' => 103,
			'FOR_TOKEN' => 221,
			'CHAR_LITERAL' => 207,
			'SWITCH_TOKEN' => 223,
			'BEGIN_TOKEN' => 45,
			'PREFIX_OPR' => 109,
			'SIZEOF_TOKEN' => 210,
			'AMP_OPR' => 113,
			'RETURN_TOKEN' => 226,
			'INTEGER_LITERAL' => 194,
			'LCB_TOKEN' => 83,
			'SQL_TOKEN' => 47,
			'DECLARE_TOKEN' => 48,
			'CONTINUE_TOKEN' => 242,
			'GOTO_TOKEN' => 243,
			'EXEC_TOKEN' => 228,
			'POSTFIX_OPR' => 197,
			'LP_TOKEN' => 198,
			'BREAK_TOKEN' => 244,
			'IF_TOKEN' => 245,
			'ASTARI_OPR' => 130,
			'END_TOKEN' => 50,
			'STRING_LITERAL' => 201,
			'TOOLS_TOKEN' => 51
		},
		GOTOS => {
			'jump_statement' => 241,
			'iteration_statement' => 218,
			'logical_OR_expression' => 211,
			'expression_statement' => 231,
			'conditional_expression' => 202,
			'primary_expression' => 212,
			'embedded_sql' => 233,
			'statement' => 418,
			'expression' => 235,
			'unary_operator' => 190,
			'unary_expression' => 196,
			'equality_expression' => 204,
			'IDENTIFIER' => 239,
			'compound_statement' => 229,
			'labeled_statement' => 246,
			'shift_expression' => 206,
			'postfix_expression' => 213,
			'additive_expression' => 199,
			'exclusive_OR_expression' => 214,
			'inclusive_OR_expression' => 208,
			'relational_expression' => 200,
			'string_literal_list' => 215,
			'multiplicative_expression' => 209,
			'AND_expression' => 191,
			'logical_AND_expression' => 216,
			'assignment_expression' => 224,
			'cast_expression' => 217,
			'selection_statement' => 225
		}
	},
	{#State 342
		DEFAULT => -226
	},
	{#State 343
		ACTIONS => {
			'SMC_TOKEN' => 419
		}
	},
	{#State 344
		DEFAULT => -227
	},
	{#State 345
		ACTIONS => {
			'SIZEOF_TOKEN' => 210,
			'AMP_OPR' => 113,
			'IDENTIFIER_ORG' => 41,
			'INTEGER_LITERAL' => 194,
			'MINUS_OPR' => 137,
			'SQL_TOKEN' => 47,
			'SECTION_TOKEN' => 42,
			'DECLARE_TOKEN' => 48,
			'FLOAT_LITERAL' => 203,
			'ORACLE_TOKEN' => 43,
			'EXEC_TOKEN' => 49,
			'POSTFIX_OPR' => 197,
			'LP_TOKEN' => 198,
			'PLUS_OPR' => 103,
			'CHAR_LITERAL' => 207,
			'ASTARI_OPR' => 130,
			'END_TOKEN' => 50,
			'BEGIN_TOKEN' => 45,
			'PREFIX_OPR' => 109,
			'STRING_LITERAL' => 201,
			'TOOLS_TOKEN' => 51
		},
		GOTOS => {
			'logical_OR_expression' => 211,
			'conditional_expression' => 202,
			'primary_expression' => 212,
			'expression' => 420,
			'unary_operator' => 190,
			'unary_expression' => 196,
			'equality_expression' => 204,
			'IDENTIFIER' => 205,
			'shift_expression' => 206,
			'additive_expression' => 199,
			'postfix_expression' => 213,
			'exclusive_OR_expression' => 214,
			'inclusive_OR_expression' => 208,
			'relational_expression' => 200,
			'string_literal_list' => 215,
			'AND_expression' => 191,
			'multiplicative_expression' => 209,
			'logical_AND_expression' => 216,
			'assignment_expression' => 224,
			'cast_expression' => 217
		}
	},
	{#State 346
		DEFAULT => -135
	},
	{#State 347
		ACTIONS => {
			'RSB_TOKEN' => 421
		}
	},
	{#State 348
		ACTIONS => {
			'RSB_TOKEN' => 422
		},
		DEFAULT => -26
	},
	{#State 349
		DEFAULT => -136
	},
	{#State 350
		ACTIONS => {
			'SIZEOF_TOKEN' => 210,
			'AMP_OPR' => 113,
			'IDENTIFIER_ORG' => 41,
			'INTEGER_LITERAL' => 194,
			'MINUS_OPR' => 137,
			'SQL_TOKEN' => 47,
			'SECTION_TOKEN' => 42,
			'DECLARE_TOKEN' => 48,
			'FLOAT_LITERAL' => 203,
			'ORACLE_TOKEN' => 43,
			'EXEC_TOKEN' => 49,
			'POSTFIX_OPR' => 197,
			'LP_TOKEN' => 198,
			'PLUS_OPR' => 103,
			'CHAR_LITERAL' => 207,
			'ASTARI_OPR' => 130,
			'END_TOKEN' => 50,
			'BEGIN_TOKEN' => 45,
			'PREFIX_OPR' => 109,
			'STRING_LITERAL' => 201,
			'TOOLS_TOKEN' => 51
		},
		GOTOS => {
			'logical_OR_expression' => 211,
			'conditional_expression' => 202,
			'primary_expression' => 212,
			'unary_operator' => 190,
			'unary_expression' => 196,
			'equality_expression' => 204,
			'IDENTIFIER' => 205,
			'shift_expression' => 206,
			'additive_expression' => 199,
			'postfix_expression' => 213,
			'exclusive_OR_expression' => 214,
			'inclusive_OR_expression' => 208,
			'relational_expression' => 200,
			'AND_expression' => 191,
			'multiplicative_expression' => 209,
			'string_literal_list' => 215,
			'logical_AND_expression' => 216,
			'assignment_expression' => 423,
			'cast_expression' => 217
		}
	},
	{#State 351
		DEFAULT => -142
	},
	{#State 352
		ACTIONS => {
			'RSB_TOKEN' => 424
		}
	},
	{#State 353
		ACTIONS => {
			'SIZEOF_TOKEN' => 210,
			'VOLATILE_TOKEN' => 22,
			'AMP_OPR' => 113,
			'IDENTIFIER_ORG' => 41,
			'INTEGER_LITERAL' => 194,
			'MINUS_OPR' => 137,
			'SQL_TOKEN' => 47,
			'SECTION_TOKEN' => 42,
			'DECLARE_TOKEN' => 48,
			'FLOAT_LITERAL' => 203,
			'ORACLE_TOKEN' => 43,
			'EXEC_TOKEN' => 49,
			'POSTFIX_OPR' => 197,
			'LP_TOKEN' => 198,
			'CONST_TOKEN' => 15,
			'PLUS_OPR' => 103,
			'RESTRICT_TOKEN' => 37,
			'CHAR_LITERAL' => 207,
			'ASTARI_OPR' => 130,
			'END_TOKEN' => 50,
			'BEGIN_TOKEN' => 45,
			'PREFIX_OPR' => 109,
			'STRING_LITERAL' => 201,
			'TOOLS_TOKEN' => 51
		},
		GOTOS => {
			'logical_OR_expression' => 211,
			'conditional_expression' => 202,
			'primary_expression' => 212,
			'type_qualifier' => 262,
			'unary_operator' => 190,
			'unary_expression' => 196,
			'equality_expression' => 204,
			'IDENTIFIER' => 205,
			'shift_expression' => 206,
			'additive_expression' => 199,
			'postfix_expression' => 213,
			'exclusive_OR_expression' => 214,
			'inclusive_OR_expression' => 208,
			'relational_expression' => 200,
			'string_literal_list' => 215,
			'AND_expression' => 191,
			'multiplicative_expression' => 209,
			'logical_AND_expression' => 216,
			'assignment_expression' => 425,
			'cast_expression' => 217
		}
	},
	{#State 354
		DEFAULT => -156
	},
	{#State 355
		ACTIONS => {
			'EXTERN_TOKEN' => 3,
			'SHORT_TOKEN' => 2,
			'ENUM_TOKEN' => 1,
			'IDENTIFIER_ORG' => 41,
			'LONG_TOKEN' => 5,
			'LSB_TOKEN' => 357,
			'SECTION_TOKEN' => 42,
			'INLINE_TOKEN' => 9,
			'ORACLE_TOKEN' => 43,
			'CHAR_TOKEN' => 14,
			'SIGNED_TOKEN' => 13,
			'CONST_TOKEN' => 15,
			'STRUCT_TOKEN' => 16,
			'TNAME_TOKEN' => 17,
			'UNSIGNED_TOKEN' => 18,
			'BEGIN_TOKEN' => 45,
			'FLOAT_TOKEN' => 19,
			'AUTO_TOKEN' => 20,
			'VOLATILE_TOKEN' => 22,
			'RP_TOKEN' => 426,
			'VOID_TOKEN' => 24,
			'DOUBLE_TOKEN' => 26,
			'SQL_TOKEN' => 47,
			'INT_TOKEN' => 28,
			'_BOOL_TOKEN' => 29,
			'DECLARE_TOKEN' => 48,
			'TYPEDEF_TOKEN' => 31,
			'EXEC_TOKEN' => 49,
			'LP_TOKEN' => 355,
			'_COMPLEX_TOKEN' => 34,
			'REGISTER_TOKEN' => 36,
			'RESTRICT_TOKEN' => 37,
			'UNION_TOKEN' => 38,
			'ASTARI_OPR' => 62,
			'END_TOKEN' => 50,
			'STATIC_TOKEN' => 39,
			'TOOLS_TOKEN' => 51
		},
		GOTOS => {
			'function_specifier' => 4,
			'declarator' => 87,
			'parameter_declaration' => 255,
			'declaration_specifiers' => 256,
			'struct_or_union_specifier' => 30,
			'type_qualifier' => 10,
			'storage_class_specifier' => 11,
			'enum_specifier' => 32,
			'parameter_list' => 260,
			'abstract_declarator' => 427,
			'direct_declarator' => 61,
			'parameter_type_list' => 428,
			'struct_or_union' => 35,
			'IDENTIFIER' => 56,
			'direct_abstract_declarator' => 358,
			'pointer' => 359,
			'type_specifier' => 40
		}
	},
	{#State 356
		DEFAULT => -157
	},
	{#State 357
		ACTIONS => {
			'SIZEOF_TOKEN' => 210,
			'AMP_OPR' => 113,
			'IDENTIFIER_ORG' => 41,
			'INTEGER_LITERAL' => 194,
			'MINUS_OPR' => 137,
			'SQL_TOKEN' => 47,
			'SECTION_TOKEN' => 42,
			'DECLARE_TOKEN' => 48,
			'RSB_TOKEN' => 431,
			'FLOAT_LITERAL' => 203,
			'ORACLE_TOKEN' => 43,
			'EXEC_TOKEN' => 49,
			'POSTFIX_OPR' => 197,
			'LP_TOKEN' => 198,
			'PLUS_OPR' => 103,
			'CHAR_LITERAL' => 207,
			'ASTARI_OPR' => 430,
			'END_TOKEN' => 50,
			'BEGIN_TOKEN' => 45,
			'PREFIX_OPR' => 109,
			'STRING_LITERAL' => 201,
			'TOOLS_TOKEN' => 51
		},
		GOTOS => {
			'logical_OR_expression' => 211,
			'conditional_expression' => 202,
			'primary_expression' => 212,
			'unary_operator' => 190,
			'unary_expression' => 196,
			'equality_expression' => 204,
			'IDENTIFIER' => 205,
			'shift_expression' => 206,
			'additive_expression' => 199,
			'postfix_expression' => 213,
			'exclusive_OR_expression' => 214,
			'inclusive_OR_expression' => 208,
			'relational_expression' => 200,
			'AND_expression' => 191,
			'multiplicative_expression' => 209,
			'string_literal_list' => 215,
			'logical_AND_expression' => 216,
			'assignment_expression' => 429,
			'cast_expression' => 217
		}
	},
	{#State 358
		ACTIONS => {
			'LSB_TOKEN' => 433,
			'LP_TOKEN' => 432
		},
		DEFAULT => -165
	},
	{#State 359
		ACTIONS => {
			'IDENTIFIER_ORG' => 41,
			'END_TOKEN' => 50,
			'SQL_TOKEN' => 47,
			'LSB_TOKEN' => 357,
			'SECTION_TOKEN' => 42,
			'DECLARE_TOKEN' => 48,
			'BEGIN_TOKEN' => 45,
			'EXEC_TOKEN' => 49,
			'LP_TOKEN' => 355,
			'TOOLS_TOKEN' => 51,
			'ORACLE_TOKEN' => 43
		},
		DEFAULT => -163,
		GOTOS => {
			'direct_declarator' => 80,
			'direct_abstract_declarator' => 434,
			'IDENTIFIER' => 56
		}
	},
	{#State 360
		ACTIONS => {
			'IDENTIFIER_ORG' => 41,
			'END_TOKEN' => 50,
			'SQL_TOKEN' => 47,
			'SECTION_TOKEN' => 42,
			'BEGIN_TOKEN' => 45,
			'DECLARE_TOKEN' => 48,
			'EXEC_TOKEN' => 49,
			'TOOLS_TOKEN' => 51,
			'ORACLE_TOKEN' => 43
		},
		GOTOS => {
			'IDENTIFIER' => 435
		}
	},
	{#State 361
		DEFAULT => -144
	},
	{#State 362
		ACTIONS => {
			'VOLATILE_TOKEN' => 22,
			'EXTERN_TOKEN' => 3,
			'SHORT_TOKEN' => 2,
			'ENUM_TOKEN' => 1,
			'LONG_TOKEN' => 5,
			'VOID_TOKEN' => 24,
			'DOUBLE_TOKEN' => 26,
			'INT_TOKEN' => 28,
			'_BOOL_TOKEN' => 29,
			'INLINE_TOKEN' => 9,
			'ELLIPSIS_TOKEN' => 437,
			'TYPEDEF_TOKEN' => 31,
			'_COMPLEX_TOKEN' => 34,
			'CHAR_TOKEN' => 14,
			'SIGNED_TOKEN' => 13,
			'CONST_TOKEN' => 15,
			'REGISTER_TOKEN' => 36,
			'RESTRICT_TOKEN' => 37,
			'UNION_TOKEN' => 38,
			'STRUCT_TOKEN' => 16,
			'STATIC_TOKEN' => 39,
			'TNAME_TOKEN' => 17,
			'UNSIGNED_TOKEN' => 18,
			'FLOAT_TOKEN' => 19,
			'AUTO_TOKEN' => 20
		},
		GOTOS => {
			'struct_or_union' => 35,
			'function_specifier' => 4,
			'parameter_declaration' => 436,
			'declaration_specifiers' => 256,
			'struct_or_union_specifier' => 30,
			'type_specifier' => 40,
			'type_qualifier' => 10,
			'storage_class_specifier' => 11,
			'enum_specifier' => 32
		}
	},
	{#State 363
		DEFAULT => -143
	},
	{#State 364
		DEFAULT => -246
	},
	{#State 365
		DEFAULT => -247
	},
	{#State 366
		DEFAULT => -99
	},
	{#State 367
		DEFAULT => -115
	},
	{#State 368
		ACTIONS => {
			'SIZEOF_TOKEN' => 210,
			'AMP_OPR' => 113,
			'IDENTIFIER_ORG' => 41,
			'INTEGER_LITERAL' => 194,
			'MINUS_OPR' => 137,
			'SQL_TOKEN' => 47,
			'SECTION_TOKEN' => 42,
			'DECLARE_TOKEN' => 48,
			'FLOAT_LITERAL' => 203,
			'ORACLE_TOKEN' => 43,
			'EXEC_TOKEN' => 49,
			'POSTFIX_OPR' => 197,
			'LP_TOKEN' => 198,
			'PLUS_OPR' => 103,
			'CHAR_LITERAL' => 207,
			'ASTARI_OPR' => 130,
			'END_TOKEN' => 50,
			'BEGIN_TOKEN' => 45,
			'PREFIX_OPR' => 109,
			'STRING_LITERAL' => 201,
			'TOOLS_TOKEN' => 51
		},
		GOTOS => {
			'logical_OR_expression' => 211,
			'conditional_expression' => 287,
			'primary_expression' => 212,
			'unary_operator' => 190,
			'unary_expression' => 286,
			'equality_expression' => 204,
			'IDENTIFIER' => 205,
			'constant_expression' => 438,
			'shift_expression' => 206,
			'additive_expression' => 199,
			'postfix_expression' => 213,
			'exclusive_OR_expression' => 214,
			'inclusive_OR_expression' => 208,
			'relational_expression' => 200,
			'AND_expression' => 191,
			'multiplicative_expression' => 209,
			'string_literal_list' => 215,
			'logical_AND_expression' => 216,
			'cast_expression' => 217
		}
	},
	{#State 369
		ACTIONS => {
			'IDENTIFIER_ORG' => 41,
			'ASTARI_OPR' => 62,
			'END_TOKEN' => 50,
			'SQL_TOKEN' => 47,
			'SECTION_TOKEN' => 42,
			'DECLARE_TOKEN' => 48,
			'BEGIN_TOKEN' => 45,
			'CLN_TOKEN' => 276,
			'EXEC_TOKEN' => 49,
			'LP_TOKEN' => 60,
			'TOOLS_TOKEN' => 51,
			'ORACLE_TOKEN' => 43
		},
		GOTOS => {
			'direct_declarator' => 61,
			'IDENTIFIER' => 56,
			'pointer' => 58,
			'declarator' => 277,
			'struct_declarator' => 439
		}
	},
	{#State 370
		DEFAULT => -106
	},
	{#State 371
		DEFAULT => -118
	},
	{#State 372
		ACTIONS => {
			'EQUALITY_OPR' => 312
		},
		DEFAULT => -47
	},
	{#State 373
		ACTIONS => {
			'RSB_TOKEN' => 440
		}
	},
	{#State 374
		DEFAULT => -180
	},
	{#State 375
		DEFAULT => -188
	},
	{#State 376
		DEFAULT => -186
	},
	{#State 377
		DEFAULT => -184
	},
	{#State 378
		ACTIONS => {
			'SIZEOF_TOKEN' => 210,
			'AMP_OPR' => 113,
			'IDENTIFIER_ORG' => 41,
			'INTEGER_LITERAL' => 194,
			'MINUS_OPR' => 137,
			'LCB_TOKEN' => 195,
			'SQL_TOKEN' => 47,
			'LSB_TOKEN' => 292,
			'SECTION_TOKEN' => 42,
			'DECLARE_TOKEN' => 48,
			'FLOAT_LITERAL' => 203,
			'ORACLE_TOKEN' => 43,
			'LP_TOKEN' => 198,
			'EXEC_TOKEN' => 49,
			'POSTFIX_OPR' => 197,
			'DOT_TOKEN' => 294,
			'PLUS_OPR' => 103,
			'RCB_TOKEN' => 441,
			'CHAR_LITERAL' => 207,
			'ASTARI_OPR' => 130,
			'END_TOKEN' => 50,
			'BEGIN_TOKEN' => 45,
			'PREFIX_OPR' => 109,
			'STRING_LITERAL' => 201,
			'TOOLS_TOKEN' => 51
		},
		GOTOS => {
			'logical_OR_expression' => 211,
			'conditional_expression' => 202,
			'primary_expression' => 212,
			'designation' => 443,
			'unary_operator' => 190,
			'unary_expression' => 196,
			'equality_expression' => 204,
			'IDENTIFIER' => 205,
			'designator_list' => 295,
			'shift_expression' => 206,
			'postfix_expression' => 213,
			'additive_expression' => 199,
			'exclusive_OR_expression' => 214,
			'designator' => 296,
			'inclusive_OR_expression' => 208,
			'relational_expression' => 200,
			'string_literal_list' => 215,
			'AND_expression' => 191,
			'multiplicative_expression' => 209,
			'logical_AND_expression' => 216,
			'assignment_expression' => 192,
			'cast_expression' => 217,
			'initializer' => 442
		}
	},
	{#State 379
		DEFAULT => -178
	},
	{#State 380
		DEFAULT => -59
	},
	{#State 381
		ACTIONS => {
			'RP_TOKEN' => 444
		}
	},
	{#State 382
		ACTIONS => {
			'SIZEOF_TOKEN' => 210,
			'AMP_OPR' => 113,
			'IDENTIFIER_ORG' => 41,
			'INTEGER_LITERAL' => 194,
			'MINUS_OPR' => 137,
			'LCB_TOKEN' => 445,
			'SQL_TOKEN' => 47,
			'SECTION_TOKEN' => 42,
			'DECLARE_TOKEN' => 48,
			'FLOAT_LITERAL' => 203,
			'ORACLE_TOKEN' => 43,
			'EXEC_TOKEN' => 49,
			'POSTFIX_OPR' => 197,
			'LP_TOKEN' => 198,
			'PLUS_OPR' => 103,
			'CHAR_LITERAL' => 207,
			'ASTARI_OPR' => 130,
			'END_TOKEN' => 50,
			'BEGIN_TOKEN' => 45,
			'PREFIX_OPR' => 109,
			'STRING_LITERAL' => 201,
			'TOOLS_TOKEN' => 51
		},
		GOTOS => {
			'IDENTIFIER' => 205,
			'string_literal_list' => 215,
			'unary_operator' => 190,
			'cast_expression' => 446,
			'primary_expression' => 212,
			'unary_expression' => 286,
			'postfix_expression' => 213
		}
	},
	{#State 383
		DEFAULT => -6
	},
	{#State 384
		ACTIONS => {
			'VOLATILE_TOKEN' => 22,
			'EXTERN_TOKEN' => 3,
			'SHORT_TOKEN' => 2,
			'ENUM_TOKEN' => 1,
			'RP_TOKEN' => 426,
			'LONG_TOKEN' => 5,
			'VOID_TOKEN' => 24,
			'LSB_TOKEN' => 357,
			'DOUBLE_TOKEN' => 26,
			'INT_TOKEN' => 28,
			'_BOOL_TOKEN' => 29,
			'INLINE_TOKEN' => 9,
			'TYPEDEF_TOKEN' => 31,
			'LP_TOKEN' => 384,
			'_COMPLEX_TOKEN' => 34,
			'CHAR_TOKEN' => 14,
			'SIGNED_TOKEN' => 13,
			'CONST_TOKEN' => 15,
			'REGISTER_TOKEN' => 36,
			'RESTRICT_TOKEN' => 37,
			'UNION_TOKEN' => 38,
			'STRUCT_TOKEN' => 16,
			'ASTARI_OPR' => 62,
			'STATIC_TOKEN' => 39,
			'TNAME_TOKEN' => 17,
			'UNSIGNED_TOKEN' => 18,
			'FLOAT_TOKEN' => 19,
			'AUTO_TOKEN' => 20
		},
		GOTOS => {
			'parameter_type_list' => 428,
			'struct_or_union' => 35,
			'function_specifier' => 4,
			'parameter_declaration' => 255,
			'direct_abstract_declarator' => 358,
			'declaration_specifiers' => 256,
			'struct_or_union_specifier' => 30,
			'pointer' => 386,
			'type_specifier' => 40,
			'type_qualifier' => 10,
			'storage_class_specifier' => 11,
			'enum_specifier' => 32,
			'parameter_list' => 260,
			'abstract_declarator' => 427
		}
	},
	{#State 385
		DEFAULT => -161
	},
	{#State 386
		ACTIONS => {
			'LSB_TOKEN' => 357,
			'LP_TOKEN' => 384
		},
		DEFAULT => -163,
		GOTOS => {
			'direct_abstract_declarator' => 434
		}
	},
	{#State 387
		ACTIONS => {
			'MULTI_OPR' => 315,
			'ASTARI_OPR' => 316
		},
		DEFAULT => -36
	},
	{#State 388
		ACTIONS => {
			'MULTI_OPR' => 315,
			'ASTARI_OPR' => 316
		},
		DEFAULT => -37
	},
	{#State 389
		ACTIONS => {
			'SHIFT_OPR' => 313
		},
		DEFAULT => -42
	},
	{#State 390
		ACTIONS => {
			'SHIFT_OPR' => 313
		},
		DEFAULT => -43
	},
	{#State 391
		ACTIONS => {
			'SHIFT_OPR' => 313
		},
		DEFAULT => -41
	},
	{#State 392
		ACTIONS => {
			'GT_OPR' => 309,
			'RELATIONAL_OPR' => 310,
			'LT_OPR' => 311
		},
		DEFAULT => -45
	},
	{#State 393
		ACTIONS => {
			'MINUS_OPR' => 308,
			'PLUS_OPR' => 307
		},
		DEFAULT => -39
	},
	{#State 394
		ACTIONS => {
			'NOR_OPR' => 326
		},
		DEFAULT => -51
	},
	{#State 395
		DEFAULT => -34
	},
	{#State 396
		DEFAULT => -33
	},
	{#State 397
		ACTIONS => {
			'RP_TOKEN' => 447
		}
	},
	{#State 398
		ACTIONS => {
			'CAND_OPR' => 328
		},
		DEFAULT => -55
	},
	{#State 399
		ACTIONS => {
			'CM_TOKEN' => 336,
			'CLN_TOKEN' => 448
		}
	},
	{#State 400
		DEFAULT => -18
	},
	{#State 401
		DEFAULT => -12
	},
	{#State 402
		ACTIONS => {
			'CM_TOKEN' => 449,
			'RP_TOKEN' => 450
		}
	},
	{#State 403
		ACTIONS => {
			'CM_TOKEN' => 336,
			'RSB_TOKEN' => 451
		}
	},
	{#State 404
		DEFAULT => -14
	},
	{#State 405
		DEFAULT => -13
	},
	{#State 406
		ACTIONS => {
			'AMP_OPR' => 290
		},
		DEFAULT => -49
	},
	{#State 407
		ACTIONS => {
			'OR_OPR' => 314
		},
		DEFAULT => -53
	},
	{#State 408
		ACTIONS => {
			'LP_TOKEN' => 452
		}
	},
	{#State 409
		ACTIONS => {
			'SIZEOF_TOKEN' => 210,
			'AMP_OPR' => 113,
			'IDENTIFIER_ORG' => 41,
			'INTEGER_LITERAL' => 194,
			'MINUS_OPR' => 137,
			'SMC_TOKEN' => 453,
			'SQL_TOKEN' => 47,
			'SECTION_TOKEN' => 42,
			'DECLARE_TOKEN' => 48,
			'FLOAT_LITERAL' => 203,
			'ORACLE_TOKEN' => 43,
			'EXEC_TOKEN' => 49,
			'POSTFIX_OPR' => 197,
			'LP_TOKEN' => 198,
			'PLUS_OPR' => 103,
			'CHAR_LITERAL' => 207,
			'ASTARI_OPR' => 130,
			'END_TOKEN' => 50,
			'BEGIN_TOKEN' => 45,
			'PREFIX_OPR' => 109,
			'STRING_LITERAL' => 201,
			'TOOLS_TOKEN' => 51
		},
		GOTOS => {
			'logical_OR_expression' => 211,
			'conditional_expression' => 202,
			'primary_expression' => 212,
			'expression' => 454,
			'unary_operator' => 190,
			'unary_expression' => 196,
			'equality_expression' => 204,
			'IDENTIFIER' => 205,
			'shift_expression' => 206,
			'additive_expression' => 199,
			'postfix_expression' => 213,
			'exclusive_OR_expression' => 214,
			'inclusive_OR_expression' => 208,
			'relational_expression' => 200,
			'string_literal_list' => 215,
			'AND_expression' => 191,
			'multiplicative_expression' => 209,
			'logical_AND_expression' => 216,
			'assignment_expression' => 224,
			'cast_expression' => 217
		}
	},
	{#State 410
		ACTIONS => {
			'SIZEOF_TOKEN' => 210,
			'AMP_OPR' => 113,
			'IDENTIFIER_ORG' => 41,
			'INTEGER_LITERAL' => 194,
			'MINUS_OPR' => 137,
			'SMC_TOKEN' => 455,
			'SQL_TOKEN' => 47,
			'SECTION_TOKEN' => 42,
			'DECLARE_TOKEN' => 48,
			'FLOAT_LITERAL' => 203,
			'ORACLE_TOKEN' => 43,
			'EXEC_TOKEN' => 49,
			'POSTFIX_OPR' => 197,
			'LP_TOKEN' => 198,
			'PLUS_OPR' => 103,
			'CHAR_LITERAL' => 207,
			'ASTARI_OPR' => 130,
			'END_TOKEN' => 50,
			'BEGIN_TOKEN' => 45,
			'PREFIX_OPR' => 109,
			'STRING_LITERAL' => 201,
			'TOOLS_TOKEN' => 51
		},
		GOTOS => {
			'logical_OR_expression' => 211,
			'conditional_expression' => 202,
			'primary_expression' => 212,
			'expression' => 456,
			'unary_operator' => 190,
			'unary_expression' => 196,
			'equality_expression' => 204,
			'IDENTIFIER' => 205,
			'shift_expression' => 206,
			'additive_expression' => 199,
			'postfix_expression' => 213,
			'exclusive_OR_expression' => 214,
			'inclusive_OR_expression' => 208,
			'relational_expression' => 200,
			'string_literal_list' => 215,
			'AND_expression' => 191,
			'multiplicative_expression' => 209,
			'logical_AND_expression' => 216,
			'assignment_expression' => 224,
			'cast_expression' => 217
		}
	},
	{#State 411
		ACTIONS => {
			'CM_TOKEN' => 336,
			'SMC_TOKEN' => 457
		}
	},
	{#State 412
		ACTIONS => {
			'CM_TOKEN' => 336,
			'RP_TOKEN' => 458
		}
	},
	{#State 413
		DEFAULT => -228
	},
	{#State 414
		DEFAULT => -198
	},
	{#State 415
		ACTIONS => {
			'CM_TOKEN' => 336,
			'RP_TOKEN' => 459
		}
	},
	{#State 416
		DEFAULT => -64
	},
	{#State 417
		ACTIONS => {
			'DEFAULT_TOKEN' => 230,
			'IDENTIFIER_ORG' => 41,
			'MINUS_OPR' => 137,
			'SMC_TOKEN' => 232,
			'SECTION_TOKEN' => 42,
			'DO_TOKEN' => 219,
			'WHILE_TOKEN' => 234,
			'CASE_TOKEN' => 236,
			'FLOAT_LITERAL' => 203,
			'ORACLE_TOKEN' => 43,
			'PLUS_OPR' => 103,
			'FOR_TOKEN' => 221,
			'CHAR_LITERAL' => 207,
			'SWITCH_TOKEN' => 223,
			'BEGIN_TOKEN' => 45,
			'PREFIX_OPR' => 109,
			'SIZEOF_TOKEN' => 210,
			'AMP_OPR' => 113,
			'RETURN_TOKEN' => 226,
			'INTEGER_LITERAL' => 194,
			'LCB_TOKEN' => 83,
			'SQL_TOKEN' => 47,
			'DECLARE_TOKEN' => 48,
			'CONTINUE_TOKEN' => 242,
			'GOTO_TOKEN' => 243,
			'EXEC_TOKEN' => 228,
			'POSTFIX_OPR' => 197,
			'LP_TOKEN' => 198,
			'BREAK_TOKEN' => 244,
			'IF_TOKEN' => 245,
			'ASTARI_OPR' => 130,
			'END_TOKEN' => 50,
			'STRING_LITERAL' => 201,
			'TOOLS_TOKEN' => 51
		},
		GOTOS => {
			'jump_statement' => 241,
			'iteration_statement' => 218,
			'logical_OR_expression' => 211,
			'expression_statement' => 231,
			'conditional_expression' => 202,
			'primary_expression' => 212,
			'embedded_sql' => 233,
			'statement' => 460,
			'expression' => 235,
			'unary_operator' => 190,
			'unary_expression' => 196,
			'equality_expression' => 204,
			'IDENTIFIER' => 239,
			'compound_statement' => 229,
			'labeled_statement' => 246,
			'shift_expression' => 206,
			'postfix_expression' => 213,
			'additive_expression' => 199,
			'exclusive_OR_expression' => 214,
			'inclusive_OR_expression' => 208,
			'relational_expression' => 200,
			'string_literal_list' => 215,
			'multiplicative_expression' => 209,
			'AND_expression' => 191,
			'logical_AND_expression' => 216,
			'assignment_expression' => 224,
			'cast_expression' => 217,
			'selection_statement' => 225
		}
	},
	{#State 418
		DEFAULT => -196
	},
	{#State 419
		DEFAULT => -225
	},
	{#State 420
		ACTIONS => {
			'CM_TOKEN' => 336,
			'RP_TOKEN' => 461
		}
	},
	{#State 421
		DEFAULT => -134
	},
	{#State 422
		DEFAULT => -141
	},
	{#State 423
		ACTIONS => {
			'RSB_TOKEN' => 462
		}
	},
	{#State 424
		DEFAULT => -139
	},
	{#State 425
		ACTIONS => {
			'RSB_TOKEN' => 463
		}
	},
	{#State 426
		DEFAULT => -173
	},
	{#State 427
		ACTIONS => {
			'RP_TOKEN' => 464
		}
	},
	{#State 428
		ACTIONS => {
			'RP_TOKEN' => 465
		}
	},
	{#State 429
		ACTIONS => {
			'RSB_TOKEN' => 466
		}
	},
	{#State 430
		ACTIONS => {
			'RSB_TOKEN' => 467
		},
		DEFAULT => -26
	},
	{#State 431
		DEFAULT => -167
	},
	{#State 432
		ACTIONS => {
			'VOLATILE_TOKEN' => 22,
			'EXTERN_TOKEN' => 3,
			'SHORT_TOKEN' => 2,
			'ENUM_TOKEN' => 1,
			'RP_TOKEN' => 468,
			'LONG_TOKEN' => 5,
			'VOID_TOKEN' => 24,
			'DOUBLE_TOKEN' => 26,
			'INT_TOKEN' => 28,
			'_BOOL_TOKEN' => 29,
			'INLINE_TOKEN' => 9,
			'TYPEDEF_TOKEN' => 31,
			'_COMPLEX_TOKEN' => 34,
			'CHAR_TOKEN' => 14,
			'SIGNED_TOKEN' => 13,
			'CONST_TOKEN' => 15,
			'REGISTER_TOKEN' => 36,
			'RESTRICT_TOKEN' => 37,
			'UNION_TOKEN' => 38,
			'STRUCT_TOKEN' => 16,
			'STATIC_TOKEN' => 39,
			'TNAME_TOKEN' => 17,
			'UNSIGNED_TOKEN' => 18,
			'FLOAT_TOKEN' => 19,
			'AUTO_TOKEN' => 20
		},
		GOTOS => {
			'parameter_type_list' => 469,
			'struct_or_union' => 35,
			'function_specifier' => 4,
			'parameter_declaration' => 255,
			'declaration_specifiers' => 256,
			'struct_or_union_specifier' => 30,
			'type_specifier' => 40,
			'type_qualifier' => 10,
			'storage_class_specifier' => 11,
			'enum_specifier' => 32,
			'parameter_list' => 260
		}
	},
	{#State 433
		ACTIONS => {
			'SIZEOF_TOKEN' => 210,
			'AMP_OPR' => 113,
			'IDENTIFIER_ORG' => 41,
			'INTEGER_LITERAL' => 194,
			'MINUS_OPR' => 137,
			'SQL_TOKEN' => 47,
			'SECTION_TOKEN' => 42,
			'DECLARE_TOKEN' => 48,
			'RSB_TOKEN' => 472,
			'FLOAT_LITERAL' => 203,
			'ORACLE_TOKEN' => 43,
			'EXEC_TOKEN' => 49,
			'POSTFIX_OPR' => 197,
			'LP_TOKEN' => 198,
			'PLUS_OPR' => 103,
			'CHAR_LITERAL' => 207,
			'ASTARI_OPR' => 471,
			'END_TOKEN' => 50,
			'BEGIN_TOKEN' => 45,
			'PREFIX_OPR' => 109,
			'STRING_LITERAL' => 201,
			'TOOLS_TOKEN' => 51
		},
		GOTOS => {
			'logical_OR_expression' => 211,
			'conditional_expression' => 202,
			'primary_expression' => 212,
			'unary_operator' => 190,
			'unary_expression' => 196,
			'equality_expression' => 204,
			'IDENTIFIER' => 205,
			'shift_expression' => 206,
			'additive_expression' => 199,
			'postfix_expression' => 213,
			'exclusive_OR_expression' => 214,
			'inclusive_OR_expression' => 208,
			'relational_expression' => 200,
			'AND_expression' => 191,
			'multiplicative_expression' => 209,
			'string_literal_list' => 215,
			'logical_AND_expression' => 216,
			'assignment_expression' => 470,
			'cast_expression' => 217
		}
	},
	{#State 434
		ACTIONS => {
			'LSB_TOKEN' => 433,
			'LP_TOKEN' => 432
		},
		DEFAULT => -164
	},
	{#State 435
		DEFAULT => -160
	},
	{#State 436
		DEFAULT => -155
	},
	{#State 437
		DEFAULT => -153
	},
	{#State 438
		DEFAULT => -114
	},
	{#State 439
		DEFAULT => -112
	},
	{#State 440
		DEFAULT => -187
	},
	{#State 441
		DEFAULT => -179
	},
	{#State 442
		DEFAULT => -183
	},
	{#State 443
		ACTIONS => {
			'SIZEOF_TOKEN' => 210,
			'AMP_OPR' => 113,
			'IDENTIFIER_ORG' => 41,
			'INTEGER_LITERAL' => 194,
			'MINUS_OPR' => 137,
			'LCB_TOKEN' => 195,
			'SQL_TOKEN' => 47,
			'SECTION_TOKEN' => 42,
			'DECLARE_TOKEN' => 48,
			'FLOAT_LITERAL' => 203,
			'ORACLE_TOKEN' => 43,
			'EXEC_TOKEN' => 49,
			'POSTFIX_OPR' => 197,
			'LP_TOKEN' => 198,
			'PLUS_OPR' => 103,
			'CHAR_LITERAL' => 207,
			'ASTARI_OPR' => 130,
			'END_TOKEN' => 50,
			'BEGIN_TOKEN' => 45,
			'PREFIX_OPR' => 109,
			'STRING_LITERAL' => 201,
			'TOOLS_TOKEN' => 51
		},
		GOTOS => {
			'logical_OR_expression' => 211,
			'conditional_expression' => 202,
			'primary_expression' => 212,
			'unary_operator' => 190,
			'unary_expression' => 196,
			'equality_expression' => 204,
			'IDENTIFIER' => 205,
			'shift_expression' => 206,
			'additive_expression' => 199,
			'postfix_expression' => 213,
			'exclusive_OR_expression' => 214,
			'inclusive_OR_expression' => 208,
			'relational_expression' => 200,
			'string_literal_list' => 215,
			'AND_expression' => 191,
			'multiplicative_expression' => 209,
			'logical_AND_expression' => 216,
			'assignment_expression' => 192,
			'cast_expression' => 217,
			'initializer' => 473
		}
	},
	{#State 444
		ACTIONS => {
			'LCB_TOKEN' => 445
		}
	},
	{#State 445
		ACTIONS => {
			'SIZEOF_TOKEN' => 210,
			'AMP_OPR' => 113,
			'IDENTIFIER_ORG' => 41,
			'INTEGER_LITERAL' => 194,
			'MINUS_OPR' => 137,
			'LCB_TOKEN' => 195,
			'SQL_TOKEN' => 47,
			'LSB_TOKEN' => 292,
			'SECTION_TOKEN' => 42,
			'DECLARE_TOKEN' => 48,
			'FLOAT_LITERAL' => 203,
			'ORACLE_TOKEN' => 43,
			'EXEC_TOKEN' => 49,
			'POSTFIX_OPR' => 197,
			'LP_TOKEN' => 198,
			'DOT_TOKEN' => 294,
			'PLUS_OPR' => 103,
			'CHAR_LITERAL' => 207,
			'ASTARI_OPR' => 130,
			'END_TOKEN' => 50,
			'BEGIN_TOKEN' => 45,
			'PREFIX_OPR' => 109,
			'STRING_LITERAL' => 201,
			'TOOLS_TOKEN' => 51
		},
		GOTOS => {
			'initializer_list' => 474,
			'logical_OR_expression' => 211,
			'conditional_expression' => 202,
			'primary_expression' => 212,
			'designation' => 293,
			'unary_operator' => 190,
			'unary_expression' => 196,
			'equality_expression' => 204,
			'IDENTIFIER' => 205,
			'designator_list' => 295,
			'shift_expression' => 206,
			'postfix_expression' => 213,
			'additive_expression' => 199,
			'exclusive_OR_expression' => 214,
			'designator' => 296,
			'inclusive_OR_expression' => 208,
			'relational_expression' => 200,
			'string_literal_list' => 215,
			'AND_expression' => 191,
			'multiplicative_expression' => 209,
			'logical_AND_expression' => 216,
			'assignment_expression' => 192,
			'cast_expression' => 217,
			'initializer' => 291
		}
	},
	{#State 446
		DEFAULT => -31
	},
	{#State 447
		ACTIONS => {
			'LCB_TOKEN' => 445
		},
		DEFAULT => -24
	},
	{#State 448
		ACTIONS => {
			'SIZEOF_TOKEN' => 210,
			'AMP_OPR' => 113,
			'IDENTIFIER_ORG' => 41,
			'INTEGER_LITERAL' => 194,
			'MINUS_OPR' => 137,
			'SQL_TOKEN' => 47,
			'SECTION_TOKEN' => 42,
			'DECLARE_TOKEN' => 48,
			'FLOAT_LITERAL' => 203,
			'ORACLE_TOKEN' => 43,
			'EXEC_TOKEN' => 49,
			'POSTFIX_OPR' => 197,
			'LP_TOKEN' => 198,
			'PLUS_OPR' => 103,
			'CHAR_LITERAL' => 207,
			'ASTARI_OPR' => 130,
			'END_TOKEN' => 50,
			'BEGIN_TOKEN' => 45,
			'PREFIX_OPR' => 109,
			'STRING_LITERAL' => 201,
			'TOOLS_TOKEN' => 51
		},
		GOTOS => {
			'logical_OR_expression' => 211,
			'conditional_expression' => 475,
			'primary_expression' => 212,
			'unary_operator' => 190,
			'unary_expression' => 286,
			'equality_expression' => 204,
			'IDENTIFIER' => 205,
			'shift_expression' => 206,
			'additive_expression' => 199,
			'postfix_expression' => 213,
			'exclusive_OR_expression' => 214,
			'inclusive_OR_expression' => 208,
			'relational_expression' => 200,
			'AND_expression' => 191,
			'multiplicative_expression' => 209,
			'string_literal_list' => 215,
			'logical_AND_expression' => 216,
			'cast_expression' => 217
		}
	},
	{#State 449
		ACTIONS => {
			'SIZEOF_TOKEN' => 210,
			'AMP_OPR' => 113,
			'IDENTIFIER_ORG' => 41,
			'INTEGER_LITERAL' => 194,
			'MINUS_OPR' => 137,
			'SQL_TOKEN' => 47,
			'SECTION_TOKEN' => 42,
			'DECLARE_TOKEN' => 48,
			'FLOAT_LITERAL' => 203,
			'ORACLE_TOKEN' => 43,
			'EXEC_TOKEN' => 49,
			'POSTFIX_OPR' => 197,
			'LP_TOKEN' => 198,
			'PLUS_OPR' => 103,
			'CHAR_LITERAL' => 207,
			'ASTARI_OPR' => 130,
			'END_TOKEN' => 50,
			'BEGIN_TOKEN' => 45,
			'PREFIX_OPR' => 109,
			'STRING_LITERAL' => 201,
			'TOOLS_TOKEN' => 51
		},
		GOTOS => {
			'logical_OR_expression' => 211,
			'conditional_expression' => 202,
			'primary_expression' => 212,
			'unary_operator' => 190,
			'unary_expression' => 196,
			'equality_expression' => 204,
			'IDENTIFIER' => 205,
			'shift_expression' => 206,
			'additive_expression' => 199,
			'postfix_expression' => 213,
			'exclusive_OR_expression' => 214,
			'inclusive_OR_expression' => 208,
			'relational_expression' => 200,
			'AND_expression' => 191,
			'multiplicative_expression' => 209,
			'string_literal_list' => 215,
			'logical_AND_expression' => 216,
			'assignment_expression' => 476,
			'cast_expression' => 217
		}
	},
	{#State 450
		DEFAULT => -11
	},
	{#State 451
		DEFAULT => -10
	},
	{#State 452
		ACTIONS => {
			'SIZEOF_TOKEN' => 210,
			'AMP_OPR' => 113,
			'IDENTIFIER_ORG' => 41,
			'INTEGER_LITERAL' => 194,
			'MINUS_OPR' => 137,
			'SQL_TOKEN' => 47,
			'SECTION_TOKEN' => 42,
			'DECLARE_TOKEN' => 48,
			'FLOAT_LITERAL' => 203,
			'ORACLE_TOKEN' => 43,
			'EXEC_TOKEN' => 49,
			'POSTFIX_OPR' => 197,
			'LP_TOKEN' => 198,
			'PLUS_OPR' => 103,
			'CHAR_LITERAL' => 207,
			'ASTARI_OPR' => 130,
			'END_TOKEN' => 50,
			'BEGIN_TOKEN' => 45,
			'PREFIX_OPR' => 109,
			'STRING_LITERAL' => 201,
			'TOOLS_TOKEN' => 51
		},
		GOTOS => {
			'logical_OR_expression' => 211,
			'conditional_expression' => 202,
			'primary_expression' => 212,
			'expression' => 477,
			'unary_operator' => 190,
			'unary_expression' => 196,
			'equality_expression' => 204,
			'IDENTIFIER' => 205,
			'shift_expression' => 206,
			'additive_expression' => 199,
			'postfix_expression' => 213,
			'exclusive_OR_expression' => 214,
			'inclusive_OR_expression' => 208,
			'relational_expression' => 200,
			'string_literal_list' => 215,
			'AND_expression' => 191,
			'multiplicative_expression' => 209,
			'logical_AND_expression' => 216,
			'assignment_expression' => 224,
			'cast_expression' => 217
		}
	},
	{#State 453
		ACTIONS => {
			'SIZEOF_TOKEN' => 210,
			'AMP_OPR' => 113,
			'IDENTIFIER_ORG' => 41,
			'RP_TOKEN' => 478,
			'INTEGER_LITERAL' => 194,
			'MINUS_OPR' => 137,
			'SQL_TOKEN' => 47,
			'SECTION_TOKEN' => 42,
			'DECLARE_TOKEN' => 48,
			'FLOAT_LITERAL' => 203,
			'ORACLE_TOKEN' => 43,
			'EXEC_TOKEN' => 49,
			'POSTFIX_OPR' => 197,
			'LP_TOKEN' => 198,
			'PLUS_OPR' => 103,
			'CHAR_LITERAL' => 207,
			'ASTARI_OPR' => 130,
			'END_TOKEN' => 50,
			'BEGIN_TOKEN' => 45,
			'PREFIX_OPR' => 109,
			'STRING_LITERAL' => 201,
			'TOOLS_TOKEN' => 51
		},
		GOTOS => {
			'logical_OR_expression' => 211,
			'conditional_expression' => 202,
			'primary_expression' => 212,
			'expression' => 479,
			'unary_operator' => 190,
			'unary_expression' => 196,
			'equality_expression' => 204,
			'IDENTIFIER' => 205,
			'shift_expression' => 206,
			'additive_expression' => 199,
			'postfix_expression' => 213,
			'exclusive_OR_expression' => 214,
			'inclusive_OR_expression' => 208,
			'relational_expression' => 200,
			'string_literal_list' => 215,
			'AND_expression' => 191,
			'multiplicative_expression' => 209,
			'logical_AND_expression' => 216,
			'assignment_expression' => 224,
			'cast_expression' => 217
		}
	},
	{#State 454
		ACTIONS => {
			'CM_TOKEN' => 336,
			'SMC_TOKEN' => 480
		}
	},
	{#State 455
		ACTIONS => {
			'SIZEOF_TOKEN' => 210,
			'AMP_OPR' => 113,
			'IDENTIFIER_ORG' => 41,
			'RP_TOKEN' => 481,
			'INTEGER_LITERAL' => 194,
			'MINUS_OPR' => 137,
			'SQL_TOKEN' => 47,
			'SECTION_TOKEN' => 42,
			'DECLARE_TOKEN' => 48,
			'FLOAT_LITERAL' => 203,
			'ORACLE_TOKEN' => 43,
			'EXEC_TOKEN' => 49,
			'POSTFIX_OPR' => 197,
			'LP_TOKEN' => 198,
			'PLUS_OPR' => 103,
			'CHAR_LITERAL' => 207,
			'ASTARI_OPR' => 130,
			'END_TOKEN' => 50,
			'BEGIN_TOKEN' => 45,
			'PREFIX_OPR' => 109,
			'STRING_LITERAL' => 201,
			'TOOLS_TOKEN' => 51
		},
		GOTOS => {
			'logical_OR_expression' => 211,
			'conditional_expression' => 202,
			'primary_expression' => 212,
			'expression' => 482,
			'unary_operator' => 190,
			'unary_expression' => 196,
			'equality_expression' => 204,
			'IDENTIFIER' => 205,
			'shift_expression' => 206,
			'additive_expression' => 199,
			'postfix_expression' => 213,
			'exclusive_OR_expression' => 214,
			'inclusive_OR_expression' => 208,
			'relational_expression' => 200,
			'string_literal_list' => 215,
			'AND_expression' => 191,
			'multiplicative_expression' => 209,
			'logical_AND_expression' => 216,
			'assignment_expression' => 224,
			'cast_expression' => 217
		}
	},
	{#State 456
		ACTIONS => {
			'CM_TOKEN' => 336,
			'SMC_TOKEN' => 483
		}
	},
	{#State 457
		ACTIONS => {
			'SIZEOF_TOKEN' => 210,
			'AMP_OPR' => 113,
			'IDENTIFIER_ORG' => 41,
			'INTEGER_LITERAL' => 194,
			'MINUS_OPR' => 137,
			'SMC_TOKEN' => 484,
			'SQL_TOKEN' => 47,
			'SECTION_TOKEN' => 42,
			'DECLARE_TOKEN' => 48,
			'FLOAT_LITERAL' => 203,
			'ORACLE_TOKEN' => 43,
			'EXEC_TOKEN' => 49,
			'POSTFIX_OPR' => 197,
			'LP_TOKEN' => 198,
			'PLUS_OPR' => 103,
			'CHAR_LITERAL' => 207,
			'ASTARI_OPR' => 130,
			'END_TOKEN' => 50,
			'BEGIN_TOKEN' => 45,
			'PREFIX_OPR' => 109,
			'STRING_LITERAL' => 201,
			'TOOLS_TOKEN' => 51
		},
		GOTOS => {
			'logical_OR_expression' => 211,
			'conditional_expression' => 202,
			'primary_expression' => 212,
			'expression' => 485,
			'unary_operator' => 190,
			'unary_expression' => 196,
			'equality_expression' => 204,
			'IDENTIFIER' => 205,
			'shift_expression' => 206,
			'additive_expression' => 199,
			'postfix_expression' => 213,
			'exclusive_OR_expression' => 214,
			'inclusive_OR_expression' => 208,
			'relational_expression' => 200,
			'string_literal_list' => 215,
			'AND_expression' => 191,
			'multiplicative_expression' => 209,
			'logical_AND_expression' => 216,
			'assignment_expression' => 224,
			'cast_expression' => 217
		}
	},
	{#State 458
		ACTIONS => {
			'DEFAULT_TOKEN' => 230,
			'IDENTIFIER_ORG' => 41,
			'MINUS_OPR' => 137,
			'SMC_TOKEN' => 232,
			'SECTION_TOKEN' => 42,
			'DO_TOKEN' => 219,
			'WHILE_TOKEN' => 234,
			'CASE_TOKEN' => 236,
			'FLOAT_LITERAL' => 203,
			'ORACLE_TOKEN' => 43,
			'PLUS_OPR' => 103,
			'FOR_TOKEN' => 221,
			'CHAR_LITERAL' => 207,
			'SWITCH_TOKEN' => 223,
			'BEGIN_TOKEN' => 45,
			'PREFIX_OPR' => 109,
			'SIZEOF_TOKEN' => 210,
			'AMP_OPR' => 113,
			'RETURN_TOKEN' => 226,
			'INTEGER_LITERAL' => 194,
			'LCB_TOKEN' => 83,
			'SQL_TOKEN' => 47,
			'DECLARE_TOKEN' => 48,
			'CONTINUE_TOKEN' => 242,
			'GOTO_TOKEN' => 243,
			'EXEC_TOKEN' => 228,
			'POSTFIX_OPR' => 197,
			'LP_TOKEN' => 198,
			'BREAK_TOKEN' => 244,
			'IF_TOKEN' => 245,
			'ASTARI_OPR' => 130,
			'END_TOKEN' => 50,
			'STRING_LITERAL' => 201,
			'TOOLS_TOKEN' => 51
		},
		GOTOS => {
			'jump_statement' => 241,
			'iteration_statement' => 218,
			'logical_OR_expression' => 211,
			'expression_statement' => 231,
			'conditional_expression' => 202,
			'primary_expression' => 212,
			'embedded_sql' => 233,
			'statement' => 486,
			'expression' => 235,
			'unary_operator' => 190,
			'unary_expression' => 196,
			'equality_expression' => 204,
			'IDENTIFIER' => 239,
			'compound_statement' => 229,
			'labeled_statement' => 246,
			'shift_expression' => 206,
			'postfix_expression' => 213,
			'additive_expression' => 199,
			'exclusive_OR_expression' => 214,
			'inclusive_OR_expression' => 208,
			'relational_expression' => 200,
			'string_literal_list' => 215,
			'multiplicative_expression' => 209,
			'AND_expression' => 191,
			'logical_AND_expression' => 216,
			'assignment_expression' => 224,
			'cast_expression' => 217,
			'selection_statement' => 225
		}
	},
	{#State 459
		ACTIONS => {
			'DEFAULT_TOKEN' => 230,
			'IDENTIFIER_ORG' => 41,
			'MINUS_OPR' => 137,
			'SMC_TOKEN' => 232,
			'SECTION_TOKEN' => 42,
			'DO_TOKEN' => 219,
			'WHILE_TOKEN' => 234,
			'CASE_TOKEN' => 236,
			'FLOAT_LITERAL' => 203,
			'ORACLE_TOKEN' => 43,
			'PLUS_OPR' => 103,
			'FOR_TOKEN' => 221,
			'CHAR_LITERAL' => 207,
			'SWITCH_TOKEN' => 223,
			'BEGIN_TOKEN' => 45,
			'PREFIX_OPR' => 109,
			'SIZEOF_TOKEN' => 210,
			'AMP_OPR' => 113,
			'RETURN_TOKEN' => 226,
			'INTEGER_LITERAL' => 194,
			'LCB_TOKEN' => 83,
			'SQL_TOKEN' => 47,
			'DECLARE_TOKEN' => 48,
			'CONTINUE_TOKEN' => 242,
			'GOTO_TOKEN' => 243,
			'EXEC_TOKEN' => 228,
			'POSTFIX_OPR' => 197,
			'LP_TOKEN' => 198,
			'BREAK_TOKEN' => 244,
			'IF_TOKEN' => 245,
			'ASTARI_OPR' => 130,
			'END_TOKEN' => 50,
			'STRING_LITERAL' => 201,
			'TOOLS_TOKEN' => 51
		},
		GOTOS => {
			'jump_statement' => 241,
			'iteration_statement' => 218,
			'logical_OR_expression' => 211,
			'expression_statement' => 231,
			'conditional_expression' => 202,
			'primary_expression' => 212,
			'embedded_sql' => 233,
			'statement' => 487,
			'expression' => 235,
			'unary_operator' => 190,
			'unary_expression' => 196,
			'equality_expression' => 204,
			'IDENTIFIER' => 239,
			'compound_statement' => 229,
			'labeled_statement' => 246,
			'shift_expression' => 206,
			'postfix_expression' => 213,
			'additive_expression' => 199,
			'exclusive_OR_expression' => 214,
			'inclusive_OR_expression' => 208,
			'relational_expression' => 200,
			'string_literal_list' => 215,
			'multiplicative_expression' => 209,
			'AND_expression' => 191,
			'logical_AND_expression' => 216,
			'assignment_expression' => 224,
			'cast_expression' => 217,
			'selection_statement' => 225
		}
	},
	{#State 460
		DEFAULT => -197
	},
	{#State 461
		ACTIONS => {
			'DEFAULT_TOKEN' => 230,
			'IDENTIFIER_ORG' => 41,
			'MINUS_OPR' => 137,
			'SMC_TOKEN' => 232,
			'SECTION_TOKEN' => 42,
			'DO_TOKEN' => 219,
			'WHILE_TOKEN' => 234,
			'CASE_TOKEN' => 236,
			'FLOAT_LITERAL' => 203,
			'ORACLE_TOKEN' => 43,
			'PLUS_OPR' => 103,
			'FOR_TOKEN' => 221,
			'CHAR_LITERAL' => 207,
			'SWITCH_TOKEN' => 223,
			'BEGIN_TOKEN' => 45,
			'PREFIX_OPR' => 109,
			'SIZEOF_TOKEN' => 210,
			'AMP_OPR' => 113,
			'RETURN_TOKEN' => 226,
			'INTEGER_LITERAL' => 194,
			'LCB_TOKEN' => 83,
			'SQL_TOKEN' => 47,
			'DECLARE_TOKEN' => 48,
			'CONTINUE_TOKEN' => 242,
			'GOTO_TOKEN' => 243,
			'EXEC_TOKEN' => 228,
			'POSTFIX_OPR' => 197,
			'LP_TOKEN' => 198,
			'BREAK_TOKEN' => 244,
			'IF_TOKEN' => 245,
			'ASTARI_OPR' => 130,
			'END_TOKEN' => 50,
			'STRING_LITERAL' => 201,
			'TOOLS_TOKEN' => 51
		},
		GOTOS => {
			'jump_statement' => 241,
			'iteration_statement' => 218,
			'logical_OR_expression' => 211,
			'expression_statement' => 231,
			'conditional_expression' => 202,
			'primary_expression' => 212,
			'embedded_sql' => 233,
			'statement' => 488,
			'expression' => 235,
			'unary_operator' => 190,
			'unary_expression' => 196,
			'equality_expression' => 204,
			'IDENTIFIER' => 239,
			'compound_statement' => 229,
			'labeled_statement' => 246,
			'shift_expression' => 206,
			'postfix_expression' => 213,
			'additive_expression' => 199,
			'exclusive_OR_expression' => 214,
			'inclusive_OR_expression' => 208,
			'relational_expression' => 200,
			'string_literal_list' => 215,
			'multiplicative_expression' => 209,
			'AND_expression' => 191,
			'logical_AND_expression' => 216,
			'assignment_expression' => 224,
			'cast_expression' => 217,
			'selection_statement' => 225
		}
	},
	{#State 462
		DEFAULT => -140
	},
	{#State 463
		DEFAULT => -138
	},
	{#State 464
		DEFAULT => -166
	},
	{#State 465
		DEFAULT => -174
	},
	{#State 466
		DEFAULT => -169
	},
	{#State 467
		DEFAULT => -172
	},
	{#State 468
		DEFAULT => -175
	},
	{#State 469
		ACTIONS => {
			'RP_TOKEN' => 489
		}
	},
	{#State 470
		ACTIONS => {
			'RSB_TOKEN' => 490
		}
	},
	{#State 471
		ACTIONS => {
			'RSB_TOKEN' => 491
		},
		DEFAULT => -26
	},
	{#State 472
		DEFAULT => -168
	},
	{#State 473
		DEFAULT => -182
	},
	{#State 474
		ACTIONS => {
			'CM_TOKEN' => 492,
			'RCB_TOKEN' => 493
		}
	},
	{#State 475
		DEFAULT => -57
	},
	{#State 476
		DEFAULT => -19
	},
	{#State 477
		ACTIONS => {
			'CM_TOKEN' => 336,
			'RP_TOKEN' => 494
		}
	},
	{#State 478
		ACTIONS => {
			'DEFAULT_TOKEN' => 230,
			'IDENTIFIER_ORG' => 41,
			'MINUS_OPR' => 137,
			'SMC_TOKEN' => 232,
			'SECTION_TOKEN' => 42,
			'DO_TOKEN' => 219,
			'WHILE_TOKEN' => 234,
			'CASE_TOKEN' => 236,
			'FLOAT_LITERAL' => 203,
			'ORACLE_TOKEN' => 43,
			'PLUS_OPR' => 103,
			'FOR_TOKEN' => 221,
			'CHAR_LITERAL' => 207,
			'SWITCH_TOKEN' => 223,
			'BEGIN_TOKEN' => 45,
			'PREFIX_OPR' => 109,
			'SIZEOF_TOKEN' => 210,
			'AMP_OPR' => 113,
			'RETURN_TOKEN' => 226,
			'INTEGER_LITERAL' => 194,
			'LCB_TOKEN' => 83,
			'SQL_TOKEN' => 47,
			'DECLARE_TOKEN' => 48,
			'CONTINUE_TOKEN' => 242,
			'GOTO_TOKEN' => 243,
			'EXEC_TOKEN' => 228,
			'POSTFIX_OPR' => 197,
			'LP_TOKEN' => 198,
			'BREAK_TOKEN' => 244,
			'IF_TOKEN' => 245,
			'ASTARI_OPR' => 130,
			'END_TOKEN' => 50,
			'STRING_LITERAL' => 201,
			'TOOLS_TOKEN' => 51
		},
		GOTOS => {
			'jump_statement' => 241,
			'iteration_statement' => 218,
			'logical_OR_expression' => 211,
			'expression_statement' => 231,
			'conditional_expression' => 202,
			'primary_expression' => 212,
			'embedded_sql' => 233,
			'statement' => 495,
			'expression' => 235,
			'unary_operator' => 190,
			'unary_expression' => 196,
			'equality_expression' => 204,
			'IDENTIFIER' => 239,
			'compound_statement' => 229,
			'labeled_statement' => 246,
			'shift_expression' => 206,
			'postfix_expression' => 213,
			'additive_expression' => 199,
			'exclusive_OR_expression' => 214,
			'inclusive_OR_expression' => 208,
			'relational_expression' => 200,
			'string_literal_list' => 215,
			'multiplicative_expression' => 209,
			'AND_expression' => 191,
			'logical_AND_expression' => 216,
			'assignment_expression' => 224,
			'cast_expression' => 217,
			'selection_statement' => 225
		}
	},
	{#State 479
		ACTIONS => {
			'CM_TOKEN' => 336,
			'RP_TOKEN' => 496
		}
	},
	{#State 480
		ACTIONS => {
			'SIZEOF_TOKEN' => 210,
			'AMP_OPR' => 113,
			'IDENTIFIER_ORG' => 41,
			'RP_TOKEN' => 497,
			'INTEGER_LITERAL' => 194,
			'MINUS_OPR' => 137,
			'SQL_TOKEN' => 47,
			'SECTION_TOKEN' => 42,
			'DECLARE_TOKEN' => 48,
			'FLOAT_LITERAL' => 203,
			'ORACLE_TOKEN' => 43,
			'EXEC_TOKEN' => 49,
			'POSTFIX_OPR' => 197,
			'LP_TOKEN' => 198,
			'PLUS_OPR' => 103,
			'CHAR_LITERAL' => 207,
			'ASTARI_OPR' => 130,
			'END_TOKEN' => 50,
			'BEGIN_TOKEN' => 45,
			'PREFIX_OPR' => 109,
			'STRING_LITERAL' => 201,
			'TOOLS_TOKEN' => 51
		},
		GOTOS => {
			'logical_OR_expression' => 211,
			'conditional_expression' => 202,
			'primary_expression' => 212,
			'expression' => 498,
			'unary_operator' => 190,
			'unary_expression' => 196,
			'equality_expression' => 204,
			'IDENTIFIER' => 205,
			'shift_expression' => 206,
			'additive_expression' => 199,
			'postfix_expression' => 213,
			'exclusive_OR_expression' => 214,
			'inclusive_OR_expression' => 208,
			'relational_expression' => 200,
			'string_literal_list' => 215,
			'AND_expression' => 191,
			'multiplicative_expression' => 209,
			'logical_AND_expression' => 216,
			'assignment_expression' => 224,
			'cast_expression' => 217
		}
	},
	{#State 481
		ACTIONS => {
			'DEFAULT_TOKEN' => 230,
			'IDENTIFIER_ORG' => 41,
			'MINUS_OPR' => 137,
			'SMC_TOKEN' => 232,
			'SECTION_TOKEN' => 42,
			'DO_TOKEN' => 219,
			'WHILE_TOKEN' => 234,
			'CASE_TOKEN' => 236,
			'FLOAT_LITERAL' => 203,
			'ORACLE_TOKEN' => 43,
			'PLUS_OPR' => 103,
			'FOR_TOKEN' => 221,
			'CHAR_LITERAL' => 207,
			'SWITCH_TOKEN' => 223,
			'BEGIN_TOKEN' => 45,
			'PREFIX_OPR' => 109,
			'SIZEOF_TOKEN' => 210,
			'AMP_OPR' => 113,
			'RETURN_TOKEN' => 226,
			'INTEGER_LITERAL' => 194,
			'LCB_TOKEN' => 83,
			'SQL_TOKEN' => 47,
			'DECLARE_TOKEN' => 48,
			'CONTINUE_TOKEN' => 242,
			'GOTO_TOKEN' => 243,
			'EXEC_TOKEN' => 228,
			'POSTFIX_OPR' => 197,
			'LP_TOKEN' => 198,
			'BREAK_TOKEN' => 244,
			'IF_TOKEN' => 245,
			'ASTARI_OPR' => 130,
			'END_TOKEN' => 50,
			'STRING_LITERAL' => 201,
			'TOOLS_TOKEN' => 51
		},
		GOTOS => {
			'jump_statement' => 241,
			'iteration_statement' => 218,
			'logical_OR_expression' => 211,
			'expression_statement' => 231,
			'conditional_expression' => 202,
			'primary_expression' => 212,
			'embedded_sql' => 233,
			'statement' => 499,
			'expression' => 235,
			'unary_operator' => 190,
			'unary_expression' => 196,
			'equality_expression' => 204,
			'IDENTIFIER' => 239,
			'compound_statement' => 229,
			'labeled_statement' => 246,
			'shift_expression' => 206,
			'postfix_expression' => 213,
			'additive_expression' => 199,
			'exclusive_OR_expression' => 214,
			'inclusive_OR_expression' => 208,
			'relational_expression' => 200,
			'string_literal_list' => 215,
			'multiplicative_expression' => 209,
			'AND_expression' => 191,
			'logical_AND_expression' => 216,
			'assignment_expression' => 224,
			'cast_expression' => 217,
			'selection_statement' => 225
		}
	},
	{#State 482
		ACTIONS => {
			'CM_TOKEN' => 336,
			'RP_TOKEN' => 500
		}
	},
	{#State 483
		ACTIONS => {
			'SIZEOF_TOKEN' => 210,
			'AMP_OPR' => 113,
			'IDENTIFIER_ORG' => 41,
			'RP_TOKEN' => 501,
			'INTEGER_LITERAL' => 194,
			'MINUS_OPR' => 137,
			'SQL_TOKEN' => 47,
			'SECTION_TOKEN' => 42,
			'DECLARE_TOKEN' => 48,
			'FLOAT_LITERAL' => 203,
			'ORACLE_TOKEN' => 43,
			'EXEC_TOKEN' => 49,
			'POSTFIX_OPR' => 197,
			'LP_TOKEN' => 198,
			'PLUS_OPR' => 103,
			'CHAR_LITERAL' => 207,
			'ASTARI_OPR' => 130,
			'END_TOKEN' => 50,
			'BEGIN_TOKEN' => 45,
			'PREFIX_OPR' => 109,
			'STRING_LITERAL' => 201,
			'TOOLS_TOKEN' => 51
		},
		GOTOS => {
			'logical_OR_expression' => 211,
			'conditional_expression' => 202,
			'primary_expression' => 212,
			'expression' => 502,
			'unary_operator' => 190,
			'unary_expression' => 196,
			'equality_expression' => 204,
			'IDENTIFIER' => 205,
			'shift_expression' => 206,
			'additive_expression' => 199,
			'postfix_expression' => 213,
			'exclusive_OR_expression' => 214,
			'inclusive_OR_expression' => 208,
			'relational_expression' => 200,
			'string_literal_list' => 215,
			'AND_expression' => 191,
			'multiplicative_expression' => 209,
			'logical_AND_expression' => 216,
			'assignment_expression' => 224,
			'cast_expression' => 217
		}
	},
	{#State 484
		ACTIONS => {
			'SIZEOF_TOKEN' => 210,
			'AMP_OPR' => 113,
			'IDENTIFIER_ORG' => 41,
			'RP_TOKEN' => 503,
			'INTEGER_LITERAL' => 194,
			'MINUS_OPR' => 137,
			'SQL_TOKEN' => 47,
			'SECTION_TOKEN' => 42,
			'DECLARE_TOKEN' => 48,
			'FLOAT_LITERAL' => 203,
			'ORACLE_TOKEN' => 43,
			'EXEC_TOKEN' => 49,
			'POSTFIX_OPR' => 197,
			'LP_TOKEN' => 198,
			'PLUS_OPR' => 103,
			'CHAR_LITERAL' => 207,
			'ASTARI_OPR' => 130,
			'END_TOKEN' => 50,
			'BEGIN_TOKEN' => 45,
			'PREFIX_OPR' => 109,
			'STRING_LITERAL' => 201,
			'TOOLS_TOKEN' => 51
		},
		GOTOS => {
			'logical_OR_expression' => 211,
			'conditional_expression' => 202,
			'primary_expression' => 212,
			'expression' => 504,
			'unary_operator' => 190,
			'unary_expression' => 196,
			'equality_expression' => 204,
			'IDENTIFIER' => 205,
			'shift_expression' => 206,
			'additive_expression' => 199,
			'postfix_expression' => 213,
			'exclusive_OR_expression' => 214,
			'inclusive_OR_expression' => 208,
			'relational_expression' => 200,
			'string_literal_list' => 215,
			'AND_expression' => 191,
			'multiplicative_expression' => 209,
			'logical_AND_expression' => 216,
			'assignment_expression' => 224,
			'cast_expression' => 217
		}
	},
	{#State 485
		ACTIONS => {
			'CM_TOKEN' => 336,
			'SMC_TOKEN' => 505
		}
	},
	{#State 486
		DEFAULT => -210
	},
	{#State 487
		DEFAULT => -211
	},
	{#State 488
		ACTIONS => {
			'ELSE_TOKEN' => 506
		},
		DEFAULT => -208
	},
	{#State 489
		DEFAULT => -176
	},
	{#State 490
		DEFAULT => -170
	},
	{#State 491
		DEFAULT => -171
	},
	{#State 492
		ACTIONS => {
			'SIZEOF_TOKEN' => 210,
			'AMP_OPR' => 113,
			'IDENTIFIER_ORG' => 41,
			'INTEGER_LITERAL' => 194,
			'MINUS_OPR' => 137,
			'LCB_TOKEN' => 195,
			'SQL_TOKEN' => 47,
			'LSB_TOKEN' => 292,
			'SECTION_TOKEN' => 42,
			'DECLARE_TOKEN' => 48,
			'FLOAT_LITERAL' => 203,
			'ORACLE_TOKEN' => 43,
			'LP_TOKEN' => 198,
			'EXEC_TOKEN' => 49,
			'POSTFIX_OPR' => 197,
			'DOT_TOKEN' => 294,
			'PLUS_OPR' => 103,
			'RCB_TOKEN' => 507,
			'CHAR_LITERAL' => 207,
			'ASTARI_OPR' => 130,
			'END_TOKEN' => 50,
			'BEGIN_TOKEN' => 45,
			'PREFIX_OPR' => 109,
			'STRING_LITERAL' => 201,
			'TOOLS_TOKEN' => 51
		},
		GOTOS => {
			'logical_OR_expression' => 211,
			'conditional_expression' => 202,
			'primary_expression' => 212,
			'designation' => 443,
			'unary_operator' => 190,
			'unary_expression' => 196,
			'equality_expression' => 204,
			'IDENTIFIER' => 205,
			'designator_list' => 295,
			'shift_expression' => 206,
			'postfix_expression' => 213,
			'additive_expression' => 199,
			'exclusive_OR_expression' => 214,
			'designator' => 296,
			'inclusive_OR_expression' => 208,
			'relational_expression' => 200,
			'string_literal_list' => 215,
			'AND_expression' => 191,
			'multiplicative_expression' => 209,
			'logical_AND_expression' => 216,
			'assignment_expression' => 192,
			'cast_expression' => 217,
			'initializer' => 442
		}
	},
	{#State 493
		DEFAULT => -16
	},
	{#State 494
		ACTIONS => {
			'SMC_TOKEN' => 508
		}
	},
	{#State 495
		DEFAULT => -224
	},
	{#State 496
		ACTIONS => {
			'DEFAULT_TOKEN' => 230,
			'IDENTIFIER_ORG' => 41,
			'MINUS_OPR' => 137,
			'SMC_TOKEN' => 232,
			'SECTION_TOKEN' => 42,
			'DO_TOKEN' => 219,
			'WHILE_TOKEN' => 234,
			'CASE_TOKEN' => 236,
			'FLOAT_LITERAL' => 203,
			'ORACLE_TOKEN' => 43,
			'PLUS_OPR' => 103,
			'FOR_TOKEN' => 221,
			'CHAR_LITERAL' => 207,
			'SWITCH_TOKEN' => 223,
			'BEGIN_TOKEN' => 45,
			'PREFIX_OPR' => 109,
			'SIZEOF_TOKEN' => 210,
			'AMP_OPR' => 113,
			'RETURN_TOKEN' => 226,
			'INTEGER_LITERAL' => 194,
			'LCB_TOKEN' => 83,
			'SQL_TOKEN' => 47,
			'DECLARE_TOKEN' => 48,
			'CONTINUE_TOKEN' => 242,
			'GOTO_TOKEN' => 243,
			'EXEC_TOKEN' => 228,
			'POSTFIX_OPR' => 197,
			'LP_TOKEN' => 198,
			'BREAK_TOKEN' => 244,
			'IF_TOKEN' => 245,
			'ASTARI_OPR' => 130,
			'END_TOKEN' => 50,
			'STRING_LITERAL' => 201,
			'TOOLS_TOKEN' => 51
		},
		GOTOS => {
			'jump_statement' => 241,
			'iteration_statement' => 218,
			'logical_OR_expression' => 211,
			'expression_statement' => 231,
			'conditional_expression' => 202,
			'primary_expression' => 212,
			'embedded_sql' => 233,
			'statement' => 509,
			'expression' => 235,
			'unary_operator' => 190,
			'unary_expression' => 196,
			'equality_expression' => 204,
			'IDENTIFIER' => 239,
			'compound_statement' => 229,
			'labeled_statement' => 246,
			'shift_expression' => 206,
			'postfix_expression' => 213,
			'additive_expression' => 199,
			'exclusive_OR_expression' => 214,
			'inclusive_OR_expression' => 208,
			'relational_expression' => 200,
			'string_literal_list' => 215,
			'multiplicative_expression' => 209,
			'AND_expression' => 191,
			'logical_AND_expression' => 216,
			'assignment_expression' => 224,
			'cast_expression' => 217,
			'selection_statement' => 225
		}
	},
	{#State 497
		ACTIONS => {
			'DEFAULT_TOKEN' => 230,
			'IDENTIFIER_ORG' => 41,
			'MINUS_OPR' => 137,
			'SMC_TOKEN' => 232,
			'SECTION_TOKEN' => 42,
			'DO_TOKEN' => 219,
			'WHILE_TOKEN' => 234,
			'CASE_TOKEN' => 236,
			'FLOAT_LITERAL' => 203,
			'ORACLE_TOKEN' => 43,
			'PLUS_OPR' => 103,
			'FOR_TOKEN' => 221,
			'CHAR_LITERAL' => 207,
			'SWITCH_TOKEN' => 223,
			'BEGIN_TOKEN' => 45,
			'PREFIX_OPR' => 109,
			'SIZEOF_TOKEN' => 210,
			'AMP_OPR' => 113,
			'RETURN_TOKEN' => 226,
			'INTEGER_LITERAL' => 194,
			'LCB_TOKEN' => 83,
			'SQL_TOKEN' => 47,
			'DECLARE_TOKEN' => 48,
			'CONTINUE_TOKEN' => 242,
			'GOTO_TOKEN' => 243,
			'EXEC_TOKEN' => 228,
			'POSTFIX_OPR' => 197,
			'LP_TOKEN' => 198,
			'BREAK_TOKEN' => 244,
			'IF_TOKEN' => 245,
			'ASTARI_OPR' => 130,
			'END_TOKEN' => 50,
			'STRING_LITERAL' => 201,
			'TOOLS_TOKEN' => 51
		},
		GOTOS => {
			'jump_statement' => 241,
			'iteration_statement' => 218,
			'logical_OR_expression' => 211,
			'expression_statement' => 231,
			'conditional_expression' => 202,
			'primary_expression' => 212,
			'embedded_sql' => 233,
			'statement' => 510,
			'expression' => 235,
			'unary_operator' => 190,
			'unary_expression' => 196,
			'equality_expression' => 204,
			'IDENTIFIER' => 239,
			'compound_statement' => 229,
			'labeled_statement' => 246,
			'shift_expression' => 206,
			'postfix_expression' => 213,
			'additive_expression' => 199,
			'exclusive_OR_expression' => 214,
			'inclusive_OR_expression' => 208,
			'relational_expression' => 200,
			'string_literal_list' => 215,
			'multiplicative_expression' => 209,
			'AND_expression' => 191,
			'logical_AND_expression' => 216,
			'assignment_expression' => 224,
			'cast_expression' => 217,
			'selection_statement' => 225
		}
	},
	{#State 498
		ACTIONS => {
			'CM_TOKEN' => 336,
			'RP_TOKEN' => 511
		}
	},
	{#State 499
		DEFAULT => -213
	},
	{#State 500
		ACTIONS => {
			'DEFAULT_TOKEN' => 230,
			'IDENTIFIER_ORG' => 41,
			'MINUS_OPR' => 137,
			'SMC_TOKEN' => 232,
			'SECTION_TOKEN' => 42,
			'DO_TOKEN' => 219,
			'WHILE_TOKEN' => 234,
			'CASE_TOKEN' => 236,
			'FLOAT_LITERAL' => 203,
			'ORACLE_TOKEN' => 43,
			'PLUS_OPR' => 103,
			'FOR_TOKEN' => 221,
			'CHAR_LITERAL' => 207,
			'SWITCH_TOKEN' => 223,
			'BEGIN_TOKEN' => 45,
			'PREFIX_OPR' => 109,
			'SIZEOF_TOKEN' => 210,
			'AMP_OPR' => 113,
			'RETURN_TOKEN' => 226,
			'INTEGER_LITERAL' => 194,
			'LCB_TOKEN' => 83,
			'SQL_TOKEN' => 47,
			'DECLARE_TOKEN' => 48,
			'CONTINUE_TOKEN' => 242,
			'GOTO_TOKEN' => 243,
			'EXEC_TOKEN' => 228,
			'POSTFIX_OPR' => 197,
			'LP_TOKEN' => 198,
			'BREAK_TOKEN' => 244,
			'IF_TOKEN' => 245,
			'ASTARI_OPR' => 130,
			'END_TOKEN' => 50,
			'STRING_LITERAL' => 201,
			'TOOLS_TOKEN' => 51
		},
		GOTOS => {
			'jump_statement' => 241,
			'iteration_statement' => 218,
			'logical_OR_expression' => 211,
			'expression_statement' => 231,
			'conditional_expression' => 202,
			'primary_expression' => 212,
			'embedded_sql' => 233,
			'statement' => 512,
			'expression' => 235,
			'unary_operator' => 190,
			'unary_expression' => 196,
			'equality_expression' => 204,
			'IDENTIFIER' => 239,
			'compound_statement' => 229,
			'labeled_statement' => 246,
			'shift_expression' => 206,
			'postfix_expression' => 213,
			'additive_expression' => 199,
			'exclusive_OR_expression' => 214,
			'inclusive_OR_expression' => 208,
			'relational_expression' => 200,
			'string_literal_list' => 215,
			'multiplicative_expression' => 209,
			'AND_expression' => 191,
			'logical_AND_expression' => 216,
			'assignment_expression' => 224,
			'cast_expression' => 217,
			'selection_statement' => 225
		}
	},
	{#State 501
		ACTIONS => {
			'DEFAULT_TOKEN' => 230,
			'IDENTIFIER_ORG' => 41,
			'MINUS_OPR' => 137,
			'SMC_TOKEN' => 232,
			'SECTION_TOKEN' => 42,
			'DO_TOKEN' => 219,
			'WHILE_TOKEN' => 234,
			'CASE_TOKEN' => 236,
			'FLOAT_LITERAL' => 203,
			'ORACLE_TOKEN' => 43,
			'PLUS_OPR' => 103,
			'FOR_TOKEN' => 221,
			'CHAR_LITERAL' => 207,
			'SWITCH_TOKEN' => 223,
			'BEGIN_TOKEN' => 45,
			'PREFIX_OPR' => 109,
			'SIZEOF_TOKEN' => 210,
			'AMP_OPR' => 113,
			'RETURN_TOKEN' => 226,
			'INTEGER_LITERAL' => 194,
			'LCB_TOKEN' => 83,
			'SQL_TOKEN' => 47,
			'DECLARE_TOKEN' => 48,
			'CONTINUE_TOKEN' => 242,
			'GOTO_TOKEN' => 243,
			'EXEC_TOKEN' => 228,
			'POSTFIX_OPR' => 197,
			'LP_TOKEN' => 198,
			'BREAK_TOKEN' => 244,
			'IF_TOKEN' => 245,
			'ASTARI_OPR' => 130,
			'END_TOKEN' => 50,
			'STRING_LITERAL' => 201,
			'TOOLS_TOKEN' => 51
		},
		GOTOS => {
			'jump_statement' => 241,
			'iteration_statement' => 218,
			'logical_OR_expression' => 211,
			'expression_statement' => 231,
			'conditional_expression' => 202,
			'primary_expression' => 212,
			'embedded_sql' => 233,
			'statement' => 513,
			'expression' => 235,
			'unary_operator' => 190,
			'unary_expression' => 196,
			'equality_expression' => 204,
			'IDENTIFIER' => 239,
			'compound_statement' => 229,
			'labeled_statement' => 246,
			'shift_expression' => 206,
			'postfix_expression' => 213,
			'additive_expression' => 199,
			'exclusive_OR_expression' => 214,
			'inclusive_OR_expression' => 208,
			'relational_expression' => 200,
			'string_literal_list' => 215,
			'multiplicative_expression' => 209,
			'AND_expression' => 191,
			'logical_AND_expression' => 216,
			'assignment_expression' => 224,
			'cast_expression' => 217,
			'selection_statement' => 225
		}
	},
	{#State 502
		ACTIONS => {
			'CM_TOKEN' => 336,
			'RP_TOKEN' => 514
		}
	},
	{#State 503
		ACTIONS => {
			'DEFAULT_TOKEN' => 230,
			'IDENTIFIER_ORG' => 41,
			'MINUS_OPR' => 137,
			'SMC_TOKEN' => 232,
			'SECTION_TOKEN' => 42,
			'DO_TOKEN' => 219,
			'WHILE_TOKEN' => 234,
			'CASE_TOKEN' => 236,
			'FLOAT_LITERAL' => 203,
			'ORACLE_TOKEN' => 43,
			'PLUS_OPR' => 103,
			'FOR_TOKEN' => 221,
			'CHAR_LITERAL' => 207,
			'SWITCH_TOKEN' => 223,
			'BEGIN_TOKEN' => 45,
			'PREFIX_OPR' => 109,
			'SIZEOF_TOKEN' => 210,
			'AMP_OPR' => 113,
			'RETURN_TOKEN' => 226,
			'INTEGER_LITERAL' => 194,
			'LCB_TOKEN' => 83,
			'SQL_TOKEN' => 47,
			'DECLARE_TOKEN' => 48,
			'CONTINUE_TOKEN' => 242,
			'GOTO_TOKEN' => 243,
			'EXEC_TOKEN' => 228,
			'POSTFIX_OPR' => 197,
			'LP_TOKEN' => 198,
			'BREAK_TOKEN' => 244,
			'IF_TOKEN' => 245,
			'ASTARI_OPR' => 130,
			'END_TOKEN' => 50,
			'STRING_LITERAL' => 201,
			'TOOLS_TOKEN' => 51
		},
		GOTOS => {
			'jump_statement' => 241,
			'iteration_statement' => 218,
			'logical_OR_expression' => 211,
			'expression_statement' => 231,
			'conditional_expression' => 202,
			'primary_expression' => 212,
			'embedded_sql' => 233,
			'statement' => 515,
			'expression' => 235,
			'unary_operator' => 190,
			'unary_expression' => 196,
			'equality_expression' => 204,
			'IDENTIFIER' => 239,
			'compound_statement' => 229,
			'labeled_statement' => 246,
			'shift_expression' => 206,
			'postfix_expression' => 213,
			'additive_expression' => 199,
			'exclusive_OR_expression' => 214,
			'inclusive_OR_expression' => 208,
			'relational_expression' => 200,
			'string_literal_list' => 215,
			'multiplicative_expression' => 209,
			'AND_expression' => 191,
			'logical_AND_expression' => 216,
			'assignment_expression' => 224,
			'cast_expression' => 217,
			'selection_statement' => 225
		}
	},
	{#State 504
		ACTIONS => {
			'CM_TOKEN' => 336,
			'RP_TOKEN' => 516
		}
	},
	{#State 505
		ACTIONS => {
			'SIZEOF_TOKEN' => 210,
			'AMP_OPR' => 113,
			'IDENTIFIER_ORG' => 41,
			'RP_TOKEN' => 517,
			'INTEGER_LITERAL' => 194,
			'MINUS_OPR' => 137,
			'SQL_TOKEN' => 47,
			'SECTION_TOKEN' => 42,
			'DECLARE_TOKEN' => 48,
			'FLOAT_LITERAL' => 203,
			'ORACLE_TOKEN' => 43,
			'EXEC_TOKEN' => 49,
			'POSTFIX_OPR' => 197,
			'LP_TOKEN' => 198,
			'PLUS_OPR' => 103,
			'CHAR_LITERAL' => 207,
			'ASTARI_OPR' => 130,
			'END_TOKEN' => 50,
			'BEGIN_TOKEN' => 45,
			'PREFIX_OPR' => 109,
			'STRING_LITERAL' => 201,
			'TOOLS_TOKEN' => 51
		},
		GOTOS => {
			'logical_OR_expression' => 211,
			'conditional_expression' => 202,
			'primary_expression' => 212,
			'expression' => 518,
			'unary_operator' => 190,
			'unary_expression' => 196,
			'equality_expression' => 204,
			'IDENTIFIER' => 205,
			'shift_expression' => 206,
			'additive_expression' => 199,
			'postfix_expression' => 213,
			'exclusive_OR_expression' => 214,
			'inclusive_OR_expression' => 208,
			'relational_expression' => 200,
			'string_literal_list' => 215,
			'AND_expression' => 191,
			'multiplicative_expression' => 209,
			'logical_AND_expression' => 216,
			'assignment_expression' => 224,
			'cast_expression' => 217
		}
	},
	{#State 506
		ACTIONS => {
			'DEFAULT_TOKEN' => 230,
			'IDENTIFIER_ORG' => 41,
			'MINUS_OPR' => 137,
			'SMC_TOKEN' => 232,
			'SECTION_TOKEN' => 42,
			'DO_TOKEN' => 219,
			'WHILE_TOKEN' => 234,
			'CASE_TOKEN' => 236,
			'FLOAT_LITERAL' => 203,
			'ORACLE_TOKEN' => 43,
			'PLUS_OPR' => 103,
			'FOR_TOKEN' => 221,
			'CHAR_LITERAL' => 207,
			'SWITCH_TOKEN' => 223,
			'BEGIN_TOKEN' => 45,
			'PREFIX_OPR' => 109,
			'SIZEOF_TOKEN' => 210,
			'AMP_OPR' => 113,
			'RETURN_TOKEN' => 226,
			'INTEGER_LITERAL' => 194,
			'LCB_TOKEN' => 83,
			'SQL_TOKEN' => 47,
			'DECLARE_TOKEN' => 48,
			'CONTINUE_TOKEN' => 242,
			'GOTO_TOKEN' => 243,
			'EXEC_TOKEN' => 228,
			'POSTFIX_OPR' => 197,
			'LP_TOKEN' => 198,
			'BREAK_TOKEN' => 244,
			'IF_TOKEN' => 245,
			'ASTARI_OPR' => 130,
			'END_TOKEN' => 50,
			'STRING_LITERAL' => 201,
			'TOOLS_TOKEN' => 51
		},
		GOTOS => {
			'jump_statement' => 241,
			'iteration_statement' => 218,
			'logical_OR_expression' => 211,
			'expression_statement' => 231,
			'conditional_expression' => 202,
			'primary_expression' => 212,
			'embedded_sql' => 233,
			'statement' => 519,
			'expression' => 235,
			'unary_operator' => 190,
			'unary_expression' => 196,
			'equality_expression' => 204,
			'IDENTIFIER' => 239,
			'compound_statement' => 229,
			'labeled_statement' => 246,
			'shift_expression' => 206,
			'postfix_expression' => 213,
			'additive_expression' => 199,
			'exclusive_OR_expression' => 214,
			'inclusive_OR_expression' => 208,
			'relational_expression' => 200,
			'string_literal_list' => 215,
			'multiplicative_expression' => 209,
			'AND_expression' => 191,
			'logical_AND_expression' => 216,
			'assignment_expression' => 224,
			'cast_expression' => 217,
			'selection_statement' => 225
		}
	},
	{#State 507
		DEFAULT => -17
	},
	{#State 508
		DEFAULT => -212
	},
	{#State 509
		DEFAULT => -222
	},
	{#State 510
		DEFAULT => -223
	},
	{#State 511
		ACTIONS => {
			'DEFAULT_TOKEN' => 230,
			'IDENTIFIER_ORG' => 41,
			'MINUS_OPR' => 137,
			'SMC_TOKEN' => 232,
			'SECTION_TOKEN' => 42,
			'DO_TOKEN' => 219,
			'WHILE_TOKEN' => 234,
			'CASE_TOKEN' => 236,
			'FLOAT_LITERAL' => 203,
			'ORACLE_TOKEN' => 43,
			'PLUS_OPR' => 103,
			'FOR_TOKEN' => 221,
			'CHAR_LITERAL' => 207,
			'SWITCH_TOKEN' => 223,
			'BEGIN_TOKEN' => 45,
			'PREFIX_OPR' => 109,
			'SIZEOF_TOKEN' => 210,
			'AMP_OPR' => 113,
			'RETURN_TOKEN' => 226,
			'INTEGER_LITERAL' => 194,
			'LCB_TOKEN' => 83,
			'SQL_TOKEN' => 47,
			'DECLARE_TOKEN' => 48,
			'CONTINUE_TOKEN' => 242,
			'GOTO_TOKEN' => 243,
			'EXEC_TOKEN' => 228,
			'POSTFIX_OPR' => 197,
			'LP_TOKEN' => 198,
			'BREAK_TOKEN' => 244,
			'IF_TOKEN' => 245,
			'ASTARI_OPR' => 130,
			'END_TOKEN' => 50,
			'STRING_LITERAL' => 201,
			'TOOLS_TOKEN' => 51
		},
		GOTOS => {
			'jump_statement' => 241,
			'iteration_statement' => 218,
			'logical_OR_expression' => 211,
			'expression_statement' => 231,
			'conditional_expression' => 202,
			'primary_expression' => 212,
			'embedded_sql' => 233,
			'statement' => 520,
			'expression' => 235,
			'unary_operator' => 190,
			'unary_expression' => 196,
			'equality_expression' => 204,
			'IDENTIFIER' => 239,
			'compound_statement' => 229,
			'labeled_statement' => 246,
			'shift_expression' => 206,
			'postfix_expression' => 213,
			'additive_expression' => 199,
			'exclusive_OR_expression' => 214,
			'inclusive_OR_expression' => 208,
			'relational_expression' => 200,
			'string_literal_list' => 215,
			'multiplicative_expression' => 209,
			'AND_expression' => 191,
			'logical_AND_expression' => 216,
			'assignment_expression' => 224,
			'cast_expression' => 217,
			'selection_statement' => 225
		}
	},
	{#State 512
		DEFAULT => -216
	},
	{#State 513
		DEFAULT => -215
	},
	{#State 514
		ACTIONS => {
			'DEFAULT_TOKEN' => 230,
			'IDENTIFIER_ORG' => 41,
			'MINUS_OPR' => 137,
			'SMC_TOKEN' => 232,
			'SECTION_TOKEN' => 42,
			'DO_TOKEN' => 219,
			'WHILE_TOKEN' => 234,
			'CASE_TOKEN' => 236,
			'FLOAT_LITERAL' => 203,
			'ORACLE_TOKEN' => 43,
			'PLUS_OPR' => 103,
			'FOR_TOKEN' => 221,
			'CHAR_LITERAL' => 207,
			'SWITCH_TOKEN' => 223,
			'BEGIN_TOKEN' => 45,
			'PREFIX_OPR' => 109,
			'SIZEOF_TOKEN' => 210,
			'AMP_OPR' => 113,
			'RETURN_TOKEN' => 226,
			'INTEGER_LITERAL' => 194,
			'LCB_TOKEN' => 83,
			'SQL_TOKEN' => 47,
			'DECLARE_TOKEN' => 48,
			'CONTINUE_TOKEN' => 242,
			'GOTO_TOKEN' => 243,
			'EXEC_TOKEN' => 228,
			'POSTFIX_OPR' => 197,
			'LP_TOKEN' => 198,
			'BREAK_TOKEN' => 244,
			'IF_TOKEN' => 245,
			'ASTARI_OPR' => 130,
			'END_TOKEN' => 50,
			'STRING_LITERAL' => 201,
			'TOOLS_TOKEN' => 51
		},
		GOTOS => {
			'jump_statement' => 241,
			'iteration_statement' => 218,
			'logical_OR_expression' => 211,
			'expression_statement' => 231,
			'conditional_expression' => 202,
			'primary_expression' => 212,
			'embedded_sql' => 233,
			'statement' => 521,
			'expression' => 235,
			'unary_operator' => 190,
			'unary_expression' => 196,
			'equality_expression' => 204,
			'IDENTIFIER' => 239,
			'compound_statement' => 229,
			'labeled_statement' => 246,
			'shift_expression' => 206,
			'postfix_expression' => 213,
			'additive_expression' => 199,
			'exclusive_OR_expression' => 214,
			'inclusive_OR_expression' => 208,
			'relational_expression' => 200,
			'string_literal_list' => 215,
			'multiplicative_expression' => 209,
			'AND_expression' => 191,
			'logical_AND_expression' => 216,
			'assignment_expression' => 224,
			'cast_expression' => 217,
			'selection_statement' => 225
		}
	},
	{#State 515
		DEFAULT => -214
	},
	{#State 516
		ACTIONS => {
			'DEFAULT_TOKEN' => 230,
			'IDENTIFIER_ORG' => 41,
			'MINUS_OPR' => 137,
			'SMC_TOKEN' => 232,
			'SECTION_TOKEN' => 42,
			'DO_TOKEN' => 219,
			'WHILE_TOKEN' => 234,
			'CASE_TOKEN' => 236,
			'FLOAT_LITERAL' => 203,
			'ORACLE_TOKEN' => 43,
			'PLUS_OPR' => 103,
			'FOR_TOKEN' => 221,
			'CHAR_LITERAL' => 207,
			'SWITCH_TOKEN' => 223,
			'BEGIN_TOKEN' => 45,
			'PREFIX_OPR' => 109,
			'SIZEOF_TOKEN' => 210,
			'AMP_OPR' => 113,
			'RETURN_TOKEN' => 226,
			'INTEGER_LITERAL' => 194,
			'LCB_TOKEN' => 83,
			'SQL_TOKEN' => 47,
			'DECLARE_TOKEN' => 48,
			'CONTINUE_TOKEN' => 242,
			'GOTO_TOKEN' => 243,
			'EXEC_TOKEN' => 228,
			'POSTFIX_OPR' => 197,
			'LP_TOKEN' => 198,
			'BREAK_TOKEN' => 244,
			'IF_TOKEN' => 245,
			'ASTARI_OPR' => 130,
			'END_TOKEN' => 50,
			'STRING_LITERAL' => 201,
			'TOOLS_TOKEN' => 51
		},
		GOTOS => {
			'jump_statement' => 241,
			'iteration_statement' => 218,
			'logical_OR_expression' => 211,
			'expression_statement' => 231,
			'conditional_expression' => 202,
			'primary_expression' => 212,
			'embedded_sql' => 233,
			'statement' => 522,
			'expression' => 235,
			'unary_operator' => 190,
			'unary_expression' => 196,
			'equality_expression' => 204,
			'IDENTIFIER' => 239,
			'compound_statement' => 229,
			'labeled_statement' => 246,
			'shift_expression' => 206,
			'postfix_expression' => 213,
			'additive_expression' => 199,
			'exclusive_OR_expression' => 214,
			'inclusive_OR_expression' => 208,
			'relational_expression' => 200,
			'string_literal_list' => 215,
			'multiplicative_expression' => 209,
			'AND_expression' => 191,
			'logical_AND_expression' => 216,
			'assignment_expression' => 224,
			'cast_expression' => 217,
			'selection_statement' => 225
		}
	},
	{#State 517
		ACTIONS => {
			'DEFAULT_TOKEN' => 230,
			'IDENTIFIER_ORG' => 41,
			'MINUS_OPR' => 137,
			'SMC_TOKEN' => 232,
			'SECTION_TOKEN' => 42,
			'DO_TOKEN' => 219,
			'WHILE_TOKEN' => 234,
			'CASE_TOKEN' => 236,
			'FLOAT_LITERAL' => 203,
			'ORACLE_TOKEN' => 43,
			'PLUS_OPR' => 103,
			'FOR_TOKEN' => 221,
			'CHAR_LITERAL' => 207,
			'SWITCH_TOKEN' => 223,
			'BEGIN_TOKEN' => 45,
			'PREFIX_OPR' => 109,
			'SIZEOF_TOKEN' => 210,
			'AMP_OPR' => 113,
			'RETURN_TOKEN' => 226,
			'INTEGER_LITERAL' => 194,
			'LCB_TOKEN' => 83,
			'SQL_TOKEN' => 47,
			'DECLARE_TOKEN' => 48,
			'CONTINUE_TOKEN' => 242,
			'GOTO_TOKEN' => 243,
			'EXEC_TOKEN' => 228,
			'POSTFIX_OPR' => 197,
			'LP_TOKEN' => 198,
			'BREAK_TOKEN' => 244,
			'IF_TOKEN' => 245,
			'ASTARI_OPR' => 130,
			'END_TOKEN' => 50,
			'STRING_LITERAL' => 201,
			'TOOLS_TOKEN' => 51
		},
		GOTOS => {
			'jump_statement' => 241,
			'iteration_statement' => 218,
			'logical_OR_expression' => 211,
			'expression_statement' => 231,
			'conditional_expression' => 202,
			'primary_expression' => 212,
			'embedded_sql' => 233,
			'statement' => 523,
			'expression' => 235,
			'unary_operator' => 190,
			'unary_expression' => 196,
			'equality_expression' => 204,
			'IDENTIFIER' => 239,
			'compound_statement' => 229,
			'labeled_statement' => 246,
			'shift_expression' => 206,
			'postfix_expression' => 213,
			'additive_expression' => 199,
			'exclusive_OR_expression' => 214,
			'inclusive_OR_expression' => 208,
			'relational_expression' => 200,
			'string_literal_list' => 215,
			'multiplicative_expression' => 209,
			'AND_expression' => 191,
			'logical_AND_expression' => 216,
			'assignment_expression' => 224,
			'cast_expression' => 217,
			'selection_statement' => 225
		}
	},
	{#State 518
		ACTIONS => {
			'CM_TOKEN' => 336,
			'RP_TOKEN' => 524
		}
	},
	{#State 519
		DEFAULT => -209
	},
	{#State 520
		DEFAULT => -221
	},
	{#State 521
		DEFAULT => -217
	},
	{#State 522
		DEFAULT => -218
	},
	{#State 523
		DEFAULT => -219
	},
	{#State 524
		ACTIONS => {
			'DEFAULT_TOKEN' => 230,
			'IDENTIFIER_ORG' => 41,
			'MINUS_OPR' => 137,
			'SMC_TOKEN' => 232,
			'SECTION_TOKEN' => 42,
			'DO_TOKEN' => 219,
			'WHILE_TOKEN' => 234,
			'CASE_TOKEN' => 236,
			'FLOAT_LITERAL' => 203,
			'ORACLE_TOKEN' => 43,
			'PLUS_OPR' => 103,
			'FOR_TOKEN' => 221,
			'CHAR_LITERAL' => 207,
			'SWITCH_TOKEN' => 223,
			'BEGIN_TOKEN' => 45,
			'PREFIX_OPR' => 109,
			'SIZEOF_TOKEN' => 210,
			'AMP_OPR' => 113,
			'RETURN_TOKEN' => 226,
			'INTEGER_LITERAL' => 194,
			'LCB_TOKEN' => 83,
			'SQL_TOKEN' => 47,
			'DECLARE_TOKEN' => 48,
			'CONTINUE_TOKEN' => 242,
			'GOTO_TOKEN' => 243,
			'EXEC_TOKEN' => 228,
			'POSTFIX_OPR' => 197,
			'LP_TOKEN' => 198,
			'BREAK_TOKEN' => 244,
			'IF_TOKEN' => 245,
			'ASTARI_OPR' => 130,
			'END_TOKEN' => 50,
			'STRING_LITERAL' => 201,
			'TOOLS_TOKEN' => 51
		},
		GOTOS => {
			'jump_statement' => 241,
			'iteration_statement' => 218,
			'logical_OR_expression' => 211,
			'expression_statement' => 231,
			'conditional_expression' => 202,
			'primary_expression' => 212,
			'embedded_sql' => 233,
			'statement' => 525,
			'expression' => 235,
			'unary_operator' => 190,
			'unary_expression' => 196,
			'equality_expression' => 204,
			'IDENTIFIER' => 239,
			'compound_statement' => 229,
			'labeled_statement' => 246,
			'shift_expression' => 206,
			'postfix_expression' => 213,
			'additive_expression' => 199,
			'exclusive_OR_expression' => 214,
			'inclusive_OR_expression' => 208,
			'relational_expression' => 200,
			'string_literal_list' => 215,
			'multiplicative_expression' => 209,
			'AND_expression' => 191,
			'logical_AND_expression' => 216,
			'assignment_expression' => 224,
			'cast_expression' => 217,
			'selection_statement' => 225
		}
	},
	{#State 525
		DEFAULT => -220
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
		 'block_item', 1,
sub {
        printDebugLog("block_item:preproccess_include include_file_name:$_[1]");
        my $txt  = $lex->{TEXT};
        my $pos  = $lex->{POSITION};
        my $line = $lex->{LINE};
        $G_parent_include_filename{$_[1]} = $G_file_name;
        $G_file_name = $_[1];
        my $recursive_cparser = PgSqlExtract::Analyzer::CParser->new();
        my $file_name_with_path = PgSqlExtract::Analyzer::PreprocessAnalyzer::include_file_hash_call($_[1]);
        my $encording_name = PgSqlExtract::Analyzer::PreprocessAnalyzer::return_parse_enc();
        if (defined $file_name_with_path){
            my $c_strings = read_input_file($file_name_with_path,"$encording_name");
            $recursive_cparser->{YYData}->{INPUT} = $c_strings;
            $recursive_cparser->{YYData}->{loglevel} = 7;
            $recursive_cparser->Run();
            printDebugLog("-------------- Run finish $_[1] --------------");
        }else{
            printDebugLog("No such file $_[1] ---------------------------");
        }
        $lex->{TEXT} = $txt;
        $lex->{POSITION} = $pos;
        $lex->{LINE} = $line;
        $G_file_name = $G_parent_include_filename{$_[1]};
        $G_fileinfo_ref;
    }
	],
	[#Rule 206
		 'expression_statement', 2,
sub {
		printDebugLog("expression_statement: expression ;");
		$_[1];
	}
	],
	[#Rule 207
		 'expression_statement', 1,
sub {
		printDebugLog("expression_statement: ;");
		undef;
	}
	],
	[#Rule 208
		 'selection_statement', 5,
sub {
		printDebugLog("selection_statement: if ( expression ) statement");
		 ['N_if', create_linenode($_[1]),  ['N_ParExpression', $_[3]], ['N_Delimiter'], $_[5]];
	}
	],
	[#Rule 209
		 'selection_statement', 7,
sub {
		printDebugLog("selection_statement: if ( expression ) statement else statement");
		 ['N_if', create_linenode($_[1]), ['N_ParExpression', $_[3]] , ['N_Delimiter'], $_[5], ['N_Delimiter'], ['N_else', create_addcode(), create_linenode($_[6]), $_[7]]];
	}
	],
	[#Rule 210
		 'selection_statement', 5,
sub {
		printDebugLog("selection_statement: switch ( expression ) statement");
		 ['N_switch',  create_linenode($_[1]), ['N_ParExpression', $_[3]] , $_[5]];
	}
	],
	[#Rule 211
		 'iteration_statement', 5,
sub {
		printDebugLog("iteration_statement: while ( expression ) statement");
		['N_while', create_linenode($_[1]), ['N_ParExpression', $_[3]] , ['N_Delimiter'], $_[5]];
	}
	],
	[#Rule 212
		 'iteration_statement', 7,
sub {
		printDebugLog("iteration_statement: do statement while ( expression ) ;");
		['N_while', create_linenode($_[1]), $_[2], ['N_Delimiter'], create_addcode(), create_linenode($_[3]), ['N_ParExpression', $_[5]]];
	}
	],
	[#Rule 213
		 'iteration_statement', 6,
sub {
		printDebugLog("iteration_statement: for ( ; ; ) statement");
        ['N_for', create_linenode($_[1]),  undef, ['N_Delimiter'], $_[6]];
	}
	],
	[#Rule 214
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
	[#Rule 215
		 'iteration_statement', 7,
sub {
		printDebugLog("iteration_statement: for ( ; expression ; ) statement");
        my @result_forcontrol = ('N_ForControl');
        defined $_[4] and do { push(@result_forcontrol, create_addcode()); push(@result_forcontrol, $_[4]);  };
        ['N_for', create_linenode($_[1]), \@result_forcontrol , ['N_Delimiter'], $_[7]];
	}
	],
	[#Rule 216
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
	[#Rule 217
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
	[#Rule 218
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
	[#Rule 219
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
	[#Rule 220
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
	[#Rule 221
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
	[#Rule 222
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
	[#Rule 223
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
	[#Rule 224
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
	[#Rule 225
		 'jump_statement', 3,
sub {
		printDebugLog("jump_statement: goto IDENTIFIER ;");
		undef;
	}
	],
	[#Rule 226
		 'jump_statement', 2,
sub {
		printDebugLog("jump_statement: continue ;");
		undef;
	}
	],
	[#Rule 227
		 'jump_statement', 2,
sub {
		printDebugLog("jump_statement: break ;");
		undef;
	}
	],
	[#Rule 228
		 'jump_statement', 3,
sub {
		printDebugLog("jump_statement: return expression ;");
		['N_return',  create_linenode($_[1]), $_[2]];
	}
	],
	[#Rule 229
		 'jump_statement', 2,
sub {
		printDebugLog("jump_statement: return ;");
		undef;
	}
	],
	[#Rule 230
		 'translation_unit', 0, undef
	],
	[#Rule 231
		 'translation_unit', 1,
sub {
		printDebugLog("translation_unit:external_declaration");
		if(defined $_[1]) {
            if(ref($_[1]) eq "HASH" && exists($_[1]->{VARIABLE})) {
                push(@{$G_fileinfo_ref_tmp->varlist()},@{$_[1]->{VARIABLE}});
            }
    		if(ref($_[1]) eq "HASH" && exists($_[1]->{FUNCTION})) {
                push(@{$G_fileinfo_ref_tmp->functionlist()},$_[1]->{FUNCTION});
            }
        }
        $G_fileinfo_ref
	}
	],
	[#Rule 232
		 'translation_unit', 2,
sub {
		printDebugLog("translation_unit:translation_unit external_declaration");
		if(defined $_[2]) {
            if(ref($_[2]) eq "HASH" && exists($_[2]->{VARIABLE})) {
                push(@{$G_fileinfo_ref_tmp->varlist()},@{$_[2]->{VARIABLE}});
            }
            if(ref($_[2]) eq "HASH" && exists($_[2]->{FUNCTION})) {
                push(@{$G_fileinfo_ref_tmp->functionlist()}, $_[2]->{FUNCTION});
            }
        }
        $G_fileinfo_ref
	}
	],
	[#Rule 233
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
	[#Rule 234
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
 		            my $varinfo = create_VariableInfo($decl->{name}, $type, $decl->{type}, $decl->{value}, $G_file_name);
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
	[#Rule 235
		 'external_declaration', 1,
sub {
		printDebugLog("external_declaration:embedded_sql");
		$_[1];
	}
	],
	[#Rule 236
		 'external_declaration', 1,
sub {
		printDebugLog("external_declaration:include preproccess include_file_name:$_[1]");
        #! 読込中のlexの情報を残しておく。
        #! 再帰的にParserを呼び出すため、情報が消されてしまう。
        my $txt  = $lex->{TEXT};
        my $pos  = $lex->{POSITION};
        my $line = $lex->{LINE};
        #! Includeファイルの親子関係を残す。再帰的にIncludeファイルが読み込まれている場合に必要となる。
        #! $G_file_nameには呼び出し元のIncludeファイルの名前が格納されている。
        $G_parent_include_filename{$_[1]} = $G_file_name;
        $G_file_name = $_[1];
        #! Parserの準備を行う。
        my $recursive_cparser = PgSqlExtract::Analyzer::CParser->new();
        #! Parserを掛ける対象はPreprocessAnalyzer.pmで解析が終わったファイルなので、ヘッダファイル名($_[1])を引数に
        #! 中間ファイルの相対パスを取得し、変数$file_name_with_pathに格納する。
        #! 次にその変数をread_input_fileの入力にする。Includeファイルがない場合、読み込み処理は行わない。
        my $file_name_with_path = PgSqlExtract::Analyzer::PreprocessAnalyzer::include_file_hash_call($_[1]);
        my $encording_name = PgSqlExtract::Analyzer::PreprocessAnalyzer::return_parse_enc();
        if (defined $file_name_with_path){
            my $c_strings = read_input_file($file_name_with_path,"$encording_name");
            $recursive_cparser->{YYData}->{INPUT} = $c_strings;
            $recursive_cparser->{YYData}->{loglevel} = 7;
            $recursive_cparser->Run();
            printDebugLog("-------------- Run finish $_[1] --------------");
        }else{
            printDebugLog("No such file $_[1] ---------------------------");
        }
        #! Parseが終わったら、元読んでいた(includefordbsyntaxdiff"hoge.h"を見つけた箇所)の情報を
        #! 戻して、以降のParseを続ける。
        $lex->{TEXT} = $txt;
        $lex->{POSITION} = $pos;
        $lex->{LINE} = $line;
        #! $G_file_nameに現在のIncludeファイルの名前を入れる。
        $G_file_name = $G_parent_include_filename{$_[1]};
        $G_fileinfo_ref;
	}
	],
	[#Rule 237
		 'preproccess_include', 2,
sub {
        printDebugLog("preproccess_include : INCLUDEFORDBSYNTAXDIFF_TOKEN STRING_LITERAL");
        #! Includeファイル名を取得するための処理。
        #! 1.STRING_LITERALのTOKEN("hoge.h"or"foo/hoge.h")を取得する。
        #!   この時点では()で示すように、変数には"付きでファイル名もしくはパス付きのファイル名が格納される。
        my $libfilename_withpath = $_[2]->{TOKEN};
        #! 2.変数内の文字列を"を空文字で置換して、"を消す。
        $libfilename_withpath =~ s/\"//g;
        #! 3."がなくなった変数内の文字列を/を区切り文字にして、分割した文字列を配列に格納する。
        my @libfilename = split(/\//,$libfilename_withpath);
        #! 配列の最後の要素(Includeファイルの名前)を返却する。
        $libfilename[-1];
    }
	],
	[#Rule 238
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
	[#Rule 239
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
	[#Rule 240
		 'declaration_list', 1,
sub {
		printDebugLog("declaration_list:declaration");
		undef;
	}
	],
	[#Rule 241
		 'declaration_list', 2,
sub {
		printDebugLog("declaration_list:declaration_list declaration");
		undef;
	}
	],
	[#Rule 242
		 'embedded_sql', 4,
sub {
		printDebugLog("embedded_sql:EXEC SQL emb_declare ;");
		undef;
	}
	],
	[#Rule 243
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
	[#Rule 244
		 'embedded_sql', 4,
sub {
		printDebugLog("embedded_sql:EXEC ORACLE emb_string_list ;");
		undef;
	}
	],
	[#Rule 245
		 'embedded_sql', 4,
sub {
		printDebugLog("embedded_sql:EXEC TOOLS emb_string_list ;");
		undef;
	}
	],
	[#Rule 246
		 'emb_declare', 3,
sub {
        $G_declaresection_flg=1;#ホスト宣言内のフラグを真に
		printDebugLog("emb_declare:BEGIN DECLARE SECTION");
		undef;
	}
	],
	[#Rule 247
		 'emb_declare', 3,
sub {
        $G_declaresection_flg=0;#ホスト宣言内のフラグを偽に
		printDebugLog("emb_declare:END DECLARE SECTION");
		undef;
	}
	],
	[#Rule 248
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
	[#Rule 249
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
	[#Rule 250
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:IDENTIFIER_ORG");
		 $_[1];
	}
	],
	[#Rule 251
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:FLOAT_LITERAL");
		 $_[1];
	}
	],
	[#Rule 252
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:INTEGER_LITERAL");
		 $_[1];
	}
	],
	[#Rule 253
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:CHAR_LITERAL");
		 $_[1];
	}
	],
	[#Rule 254
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:STRING_LITERAL");
		 $_[1];
	}
	],
	[#Rule 255
		 'emb_constant_string', 2,
sub {
        printDebugLog("emb_constant_string: : SQL_TOKEN");
        [ $_[1] , $_[2] ];
    }
	],
	[#Rule 256
		 'emb_constant_string', 2,
sub {
		printDebugLog("emb_constant_string: : IDENTIFIER_ORG");
		[ $_[1] , $_[2] ];
	}
	],
	[#Rule 257
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:DECLARE");
		 $_[1];
	}
	],
	[#Rule 258
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:do");
		 $_[1];
	}
	],
	[#Rule 259
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:break");
		 $_[1];
	}
	],
	[#Rule 260
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:continue");
		 $_[1];
	}
	],
	[#Rule 261
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:goto");
		 $_[1];
	}
	],
	[#Rule 262
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:unary_operator:&,*,+,-,!~");
		$_[1];
	}
	],
	[#Rule 263
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:=");
		 $_[1];
	}
	],
	[#Rule 264
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:(");
		 $_[1];
	}
	],
	[#Rule 265
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:)");
		 $_[1];
	}
	],
	[#Rule 266
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:;");
		 $_[1];
	}
	],
	[#Rule 267
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:,");
		 $_[1];
	}
	],
	[#Rule 268
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:.");
		 $_[1];
	}
	],
	[#Rule 269
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:?");
		 $_[1];
	}
	],
	[#Rule 270
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:>");
		 $_[1];
	}
	],
	[#Rule 271
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:<");
		 $_[1];
	}
	],
	[#Rule 272
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:[<>]=");
		 $_[1];
	}
	],
	[#Rule 273
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:_Bool");
		 $_[1];
	}
	],
	[#Rule 274
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:_Complex");
		 $_[1];
	}
	],
	[#Rule 275
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:_Imaginary");
		 $_[1];
	}
	],
	[#Rule 276
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:auto");
		 $_[1];
	}
	],
	[#Rule 277
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:case");
		 $_[1];
	}
	],
	[#Rule 278
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:char");
		 $_[1];
	}
	],
	[#Rule 279
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:const");
		 $_[1];
	}
	],
	[#Rule 280
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:default");
		 $_[1];
	}
	],
	[#Rule 281
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:double");
		 $_[1];
	}
	],
	[#Rule 282
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:else");
		 $_[1];
	}
	],
	[#Rule 283
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:enum");
		 $_[1];
	}
	],
	[#Rule 284
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:extern");
		 $_[1];
	}
	],
	[#Rule 285
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:float");
		 $_[1];
	}
	],
	[#Rule 286
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:for");
		 $_[1];
	}
	],
	[#Rule 287
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:if");
		 $_[1];
	}
	],
	[#Rule 288
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:inline");
		 $_[1];
	}
	],
	[#Rule 289
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:int");
		 $_[1];
	}
	],
	[#Rule 290
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:long");
		 $_[1];
	}
	],
	[#Rule 291
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:new");
		 $_[1];
	}
	],
	[#Rule 292
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:private");
		 $_[1];
	}
	],
	[#Rule 293
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:protected");
		 $_[1];
	}
	],
	[#Rule 294
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:public");
		 $_[1];
	}
	],
	[#Rule 295
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:register");
		 $_[1];
	}
	],
	[#Rule 296
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:restrict");
		 $_[1];
	}
	],
	[#Rule 297
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:return");
		 $_[1];
	}
	],
	[#Rule 298
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:short");
		 $_[1];
	}
	],
	[#Rule 299
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:signed");
		 $_[1];
	}
	],
	[#Rule 300
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:sizeof");
		 $_[1];
	}
	],
	[#Rule 301
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:static");
		 $_[1];
	}
	],
	[#Rule 302
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:struct");
		 $_[1];
	}
	],
	[#Rule 303
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:switch");
		 $_[1];
	}
	],
	[#Rule 304
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:typedef");
		 $_[1];
	}
	],
	[#Rule 305
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:union");
		 $_[1];
	}
	],
	[#Rule 306
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:unsigned");
		 $_[1];
	}
	],
	[#Rule 307
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:volatile");
		 $_[1];
	}
	],
	[#Rule 308
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:void");
		 $_[1];
	}
	],
	[#Rule 309
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:while");
		 $_[1];
	}
	],
	[#Rule 310
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:begin");
		 $_[1];
	}
	],
	[#Rule 311
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:end");
		 $_[1];
	}
	],
	[#Rule 312
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:@");
		 $_[1];
	}
	],
	[#Rule 313
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:TNAME_TOKEN");
		 $_[1];
	}
	],
	[#Rule 314
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:(++|--)");
		$G_ansi_comment_line=$_[1]->{LINE};
        $_[1];
	}
	],
	[#Rule 315
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:[!|=]=");
        $_[1];
	}
	],
	[#Rule 316
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:(! *=,/=,%=,-=,<<=,>>=,&=,^=,|=)");
        $_[1];
	}
	],
	[#Rule 317
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:||");
        $_[1];
	}
	],
	[#Rule 318
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:<>");
        $_[1];
	}
	],
	[#Rule 319
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:[");
        $_[1];
	}
	],
	[#Rule 320
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:]");
        $_[1];
	}
	],
	[#Rule 321
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:/");
        $_[1];
	}
	],
	[#Rule 322
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:exec");
		 $_[1];
	}
	],
	[#Rule 323
		 'emb_constant_string', 1,
sub {
		printDebugLog("emb_constant_string:->");
		 $_[1];
	}
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
	],
	[#Rule 329
		 'IDENTIFIER', 1, undef
	],
	[#Rule 330
		 'IDENTIFIER', 1, undef
	],
	[#Rule 331
		 'IDENTIFIER', 1, undef
	],
	[#Rule 332
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
    my ($name, $typeinfo, $typetype, $valueinfo, $in_file_name) = @_;

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

    #! SY-A-a-3による仕様変更に伴う修正。Parser内でinclude処理を行うように修正したため、
    #! Analyzer.pmで実施していた抽出した変数にファイル名を付与する処理をこの場所に
    #! 移動させた。
    my $line = $result_ref->[0]->{line};
    if ($in_file_name){
        $line = $in_file_name . ":" . $line;
    }

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


#####################################################################
# Function: ref_tmp_marge
#
#
# 概要:
# $G_fileinfo_ref_tmpに退避させていた抽出結果を$G_fileinfo_refに戻す。
# その際、ref_tmpはクリアする。
# ソースファイルの読み込みが終わったあとにAnalyzer.pmから呼び出される。
# Parserではひたすらref_tmpに情報が溜められる形になっている。
#
# パラメータ:
# なし
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
sub ref_tmp_marge {
  if(ref($G_fileinfo_ref_tmp)){
    push(@{$G_fileinfo_ref->varlist()}, @{$G_fileinfo_ref_tmp->varlist()});
    push(@{$G_fileinfo_ref->functionlist()}, @{$G_fileinfo_ref_tmp->functionlist()});
    $G_fileinfo_ref_tmp = CFileInfo->new();
  }
}


1;
