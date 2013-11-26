#!/usr/bin/perl
#############################################################################
#  Copyright (C) 2007-2010 NTT
#############################################################################

#####################################################################
# Function: Common.pm
#
#
# 概要:
# 共通で利用される関数を定義する。
#
# 特記事項:
# なし
#
#####################################################################


package PgSqlExtract::Common;
use warnings;
use strict;
use Carp;
use utf8;
use Class::Struct;
use File::Basename;
use File::Find;

use base qw( Exporter );
our @EXPORT = qw(
        MODE_C MODE_SQL MODE_SIMPLE MODE_JAVA ENCODE_EUCJP ENCODE_SHIFTJIS ENCODE_UTF8
        SET_ENCODE_EUCJP SET_ENCODE_SHIFTJIS SET_ENCODE_UTF8
        DEFAULT_INPUT DEFAULT_OUTPUT FILTER_ORACLE8 FILTER_ORACLE8i
        FILTER_ALL PATTERN_TYPE_TYPE PATTERN_TYPE_EMBSQL PATTERN_TYPE_SQL
        PATTERN_TYPE_FUNC PATTERN_TYPE_SQLDA PATTERN_TYPE_SQLCA PATTERN_TYPE_ORACA PATTERN_TYPE_COMMON
        TRUE FALSE TYPE_SQLDA TYPE_BASIC TYPE_TYPE TYPE_HOST TYPE_DEFINE
        FILETYPE_HEADER FILETYPE_OTHER NOT_COMMENT SIMPLE_COMMENT MULTI_COMMENT
        LITERAL LITERAL_LITERAL SQL_LITERAL GLOBAL MACRO
        REPORT_XML_VERSION REPORT_ROOT_NAME REPORT_FILE_NUMBER REPORT_FILE_NAME
        REPORT_NAME REPORT_ITEM_NUMBER REPORT_ITEM_NAME REPORT_ID REPORT_LINE
        REPORT_TYPE REPORT_LEVEL REPORT_STRUCT_NAME REPORT_MESSAGE_NAME
        REPORT_START_TIME REPORT_FINISH_TIME REPORT_METADATA_NAME
        REPORT_PARAMETER_NAME REPORT_STRING_ITEM_NUMBER REPORT_REPORT_ITEM_NUMBER
        REPORT_STRING_ITEM_NAME REPORT_REPORT_ITEM_NAME REPORT_TARGET_NAME
        REPORT_SOURCE_NAME REPORT_CLASS_NAME REPORT_METHOD_NAME REPORT_VARIABLE_NAME REPORT_LINE_NAME REPORT_COLUMN_NAME
        DEFINITION_COMMON_NAME DEFINITION_PATTERNDEF_NAME DEFINITION_PATID
        DEFINITION_MACRO_NAME DEFINITION_NAME_NAME DEFINITION_VALUE_NAME
        DEFINITION_PATTERN_NAME DEFINITION_TYPE DEFINITION_CHASER DEFINITION_KEYWORDDEF_NAME
        DEFINITION_ACCESS_TYPE DEFINITION_MESSAGE_NAME DEFINITION_MESSAGE_ID
        DEFINITION_MESSAGE_LEVEL DEFINITION_FILTER DEFINITION_POS DEFINITION_TARGETDBMS_NAME
        DEFINITION_PLUGIN_NAME DEFINITION_LIBRARY DEFINITION_PROCEDURE
        INOUT_ENCODE_EUCJP INOUT_ENCODE_SHIFTJIS INOUT_ENCODE_UTF8 NULL DELETE_NODE_NAME
        PATTERN_BODY_FIRST PATTERN_BODY_LAST PATTERN_BODY_FIRST_FOR_SQL 
        FATAL_MESSAGE ALLOW_RECURSIVE_NUMBER EXEC_SQL
        CODETYPE_CODE CODETYPE_SCOPE RESTYPE_STRING RESTYPE_SB RESTYPE_CHAR RESTYPE_OTHER 
        MNAME_STRING MNAME_SB MNAME_TOSTRING MNAME_APPEND ANALYZE_TEMPDIR
        set_loglevel get_loglevel push_report print_log get_localtime
        read_input_file create_input_file_list set_chaserpattern get_chaserpattern
        %tokenId
     );

#
# variable: loglevel
#
# ログ出力レベル。
#
my $G_loglevel = 0;

#
# variable: chaserpattern
#
# 変数追跡対象パターン。
#
my $G_chaserpattern = undef;

#
# variable: tokenId
# 構文解析結果のトークンIDを数値に変換するハッシュ。
#
my %tokenId = ();


#
# Constants: 定数定義
# MODE_C          - オプション：動作モード（埋め込みSQL抽出モード）
# MODE_SQL        - オプション：動作モード（SQL抽出モード）
# MODE_SIMPLE     - オプション：動作モード（簡易抽出モード）
# MODE_JAVA       - オプション：動作モード（Javaソース対応モード）
# ENCODE_EUCJP    - オプション：エンコード（EUC_JP）
# ENCODE_SHIFTJIS - オプション：エンコード（SHIFT-JIS）
# ENCODE_UTF8     - オプション：エンコード（UTF-8）
# SET_ENCODE_EUCJP    - DOM設定エンコード文字列（EUC-JP）
# SET_ENCODE_SHIFTJIS - DOM設定エンコード文字列（SHIFT-JIS）
# SET_ENCODE_UTF8     - DOM設定エンコード文字列（UTF-8）
# INOUT_ENCODE_EUCJP    - 入出力時のエンコード指定文字列(EUC_JP)
# INOUT_ENCODE_SHIFTJIS - 入出力時のエンコード指定文字列(SHIFT-JIS)
# INOUT_ENCODE_UTF8     - 入出力時のエンコード指定文字列(UTF-8)
# DEFAULT_INPUT   - デフォルト抽出対象ディレクトリ
# DEFAULT_OUTPUT  - デフォルト報告結果ファイル名
# FILTER_ORACLE8  - 抽出パターンキーワード（Oracle8）
# FILTER_ORACLE8i - 抽出パターンキーワード（Oracle8i）
# FILTER_ALL      - 抽出パターンキーワード（全て）
# GETOPTION_ERROR - エラー発生時のGetOptionsの戻り値
# PATTERN_TYPE_TYPE   - 抽出パターン種別(TYPE)
# PATTERN_TYPE_EMBSQL - 抽出パターン種別(EMBSQL)
# PATTERN_TYPE_SQL    - 抽出パターン種別(SQL)
# PATTERN_TYPE_FUNC   - 抽出パターン種別(FUNC)
# PATTERN_TYPE_SQLDA  - 抽出パターン種別(SQLDA)
# PATTERN_TYPE_SQLCA  - 抽出パターン種別(SQLCA)
# PATTERN_TYPE_ORACA  - 抽出パターン種別(ORACA)
# PATTERN_TYPE_COMMON - 抽出パターン種別(COMMON)
# TURE   - 真
# FALSE  - 偽
# TYPE_SQLDA    - 宣言種別(SQLDA)
# TYPE_BASIC    - 宣言種別(基本型)
# TYPE_TYPE     - 宣言種別(型名)
# TYPE_HOST     - 宣言種別(ホスト変数)
# TYPE_DEFINE   - 宣言種別(前処理指令/定義指令)
# FILETYPE_HEADER - ファイル種別（ヘッダファイル）
# FILETYPE_OTHER  - ファイル種別（ソースコード）
# NOT_COMMENT       - 正規化フラグ（コメント外）
# SIMPLE_COMMENT    - 正規化フラグ（一行コメント内）
# MULTI_COMMENT     - 正規化フラグ（複数行可コメント内）
# LITERAL           - 正規化フラグ（リテラル内）
# LITERAL_LITERAL   - 正規化フラグ（リテラル内リテラルの中）
# SQL_LITERAL       - 正規化フラグ（SQLリテラル内）
# GLOBAL    - グローバル関数名
# MACRO     - マクロの置換文字列に埋め込む文字列
# REPORT_XML_VERSION    - 報告結果XMLversion
# REPORT_ROOT_NAME  - 報告結果DOMツリーROOTノード名
# REPORT_FILE_NUMBER    - 報告結果DOMツリーROOTノードアトリビュート(file_number)
# REPORT_START_TIME     - 報告結果DOMツリーROOTノードアトリビュート(start_time)
# REPORT_FINISH_TIME    - 報告結果DOMツリーROOTノードアトリビュート(finish_time)
# REPORT_METADATA_NAME  - 報告結果DOMツリーMETADATAノード名
# REPORT_PARAMETER_NAME - 報告結果DOMツリーPARAMETERノード名
# REPORT_FILE_NAME      - 報告結果DOMツリーFILEノード名
# REPORT_NAME           - 報告結果DOMツリーFILEノードアトリビュート(name)
# REPORT_ITEM_NUMBER    - 報告結果DOMツリーFILEノードアトリビュート(item_number)
# REPORT_STRING_ITEM_NUMBER    - 報告結果DOMツリーFILEノードアトリビュート(string_item_number)
# REPORT_REPORT_ITEM_NUMBER    - 報告結果DOMツリーFILEノードアトリビュート(report_item_number)
# REPORT_STRING_ITEM_NAME      - 報告結果DOMツリーSTRING_ITEMノード名
# REPORT_REPORT_ITEM_NAME      - 報告結果DOMツリーREPORT_ITEMノード名
# REPORT_ID - 報告結果DOMツリーITEMノードアトリビュート(id)
# REPORT_LINE   - 報告結果DOMツリーXX_ITEMノードアトリビュート(line)
# REPORT_TYPE   - 報告結果DOMツリーITEMノードアトリビュート(type)
# REPORT_LEVEL  - 報告結果DOMツリーITEMノードアトリビュート(level)
# REPORT_STRUCT_NAME    - 報告結果DOMツリーSTRUCTノード名
# REPORT_TARGET_NAME    - 報告結果DOMツリーTARGETノード名
# REPORT_MESSAGE_NAME   - 報告結果DOMツリーMESSAGEノード名
# REPORT_SOURCE_NAME   - 報告結果DOMツリーSOURCEノード名
# REPORT_CLASS_NAME   - 報告結果DOMツリーCLASSノード名
# REPORT_METHOD_NAME   - 報告結果DOMツリーMETHODノード名
# REPORT_VARIABLE_NAME   - 報告結果DOMツリーVARIABLEノード名
# REPORT_LINE_NAME   - 報告結果DOMツリーLINEノード名
# REPORT_COLUMN_NAME   - 報告結果DOMツリーCOLUMNノード名
# DEFINITION_COMMON_NAME        - 報告結果DOMツリーCOMMON
# DEFINITION_PATTERNDEF_NAME    - 報告結果DOMツリーPATTERNDEF
# DEFINITION_PATID              - 報告結果DOMツリーMESSAGE
# DEFINITION_MACRO_NAME         - 報告結果DOMツリーMACRO
# DEFINITION_NAME_NAME          - 報告結果DOMツリーNAME
# DEFINITION_VALUE_NAME         - 報告結果DOMツリーVALUE
# DEFINITION_PATTERN_NAME       - 報告結果DOMツリーPATTERN
# DEFINITION_TYPE               - 報告結果DOMツリーTYPE
# DEFINITION_CHASER             - 報告結果DOMツリーCHASER
# DEFINITION_KEYWORDDEF_NAME    - 報告結果DOMツリーKEYWORDDEF
# DEFINITION_ACCESS_TYPE        - 報告結果DOMツリーACCESS
# DEFINITION_MESSAGE_NAME       - 報告結果DOMツリーMESSAGE
# DEFINITION_MESSAGE_ID         - 報告結果DOMツリーMESSAGE_ID
# DEFINITION_MESSAGE_LEVEL      - 報告結果DOMツリーMESSAGE_LEVEL
# DEFINITION_FILTER             - 報告結果DOMツリーFILTER
# DEFINITION_POS                - 報告結果DOMツリーPOS
# DEFINITION_TARGETDBMS_NAME    - 報告結果DOMツリーTARGETDBMS
# DEFINITION_PLUGIN_NAME        - 報告結果DOMツリーPLUGIN
# DEFINITION_LIBRARY            - 報告結果DOMツリーLIBRARY
# DEFINITION_PROCEDURE          - 報告結果DOMツリーPROCEDURE
# NULL  - NULL文字
# DELETE_NODE_NAME - 削除対象ノード名
# PATTERN_BODY_FIRST  - 抽出パターン先頭追加文字列
# PATTERN_BODY_FIRST_FOR_SQL  - 抽出パターン先頭追加文字列(抽出パターン種別がSQLの場合)
# PATTERN_BODY_LAST   - 抽出パターン終端追加文字列
# FATAL_MESSAGE       - 報告対象定義ファイルエラーのメッセージ内容
# EXEC_SQL       - 埋め込み構文キーワード
# CODETYPE_CODE  - コード情報のコード種別(コード情報)
# CODETYPE_SCOPE - コード情報のコード種別(スコープ情報)
# RESTYPE_STRING - 変数辞書における解析結果の型名(String)
# RESTYPE_SB     - 変数辞書における解析結果の型名(StringBuffer)
# RESTYPE_CHAR   - 変数辞書における解析結果の型名(char)
# RESTYPE_OTHER  - 変数辞書における解析結果の型名(その他)
# MNAME_STRING   - メソッド解析におけるメソッド名(String)
# MNAME_SB       - メソッド解析におけるメソッド名(StringBuffer)
# MNAME_TOSTRING - メソッド解析におけるメソッド名(toString)
# MNAME_APPEND   - メソッド解析におけるメソッド名(append)
# ANALYZE_TEMPDIR   - 中間ファイル格納ディレクトリ

use constant {
    MODE_C                      => "c",
    MODE_SQL                    => "sql",
    MODE_JAVA                   => "java",
    MODE_SIMPLE                 => "cpp",
    ENCODE_EUCJP                => "eucjp",
    ENCODE_SHIFTJIS             => "shiftjis",
    ENCODE_UTF8                 => "utf8",
    SET_ENCODE_EUCJP            => "EUC-JP",
    SET_ENCODE_SHIFTJIS         => "SHIFT_JIS",
    SET_ENCODE_UTF8             => "UTF-8",
    INOUT_ENCODE_EUCJP      => "euc-jp",
    INOUT_ENCODE_SHIFTJIS   => "shiftjis",
    INOUT_ENCODE_UTF8       => "utf8",
    DEFAULT_INPUT               => "./",
    DEFAULT_OUTPUT              => "-",
    FILTER_ORACLE8              => "Oracle8",
    FILTER_ORACLE8i             => "Oracle8i",
    FILTER_ALL                  => "ALL",
    PATTERN_TYPE_TYPE           => "TYPE",
    PATTERN_TYPE_EMBSQL         => "EMBSQL",
    PATTERN_TYPE_SQL            => "SQL",
    PATTERN_TYPE_FUNC           => "FUNC",
    PATTERN_TYPE_SQLDA          => "SQLDA",
    PATTERN_TYPE_SQLCA          => "SQLCA",
    PATTERN_TYPE_ORACA          => "ORACA",
    PATTERN_TYPE_COMMON         => "COMMON",
    FALSE                       => "0",
    TRUE                        => "1",
    TYPE_SQLDA                  => "1",
    TYPE_BASIC                  => "2",
    TYPE_TYPE                   => "4",
    TYPE_HOST                   => "8",
    TYPE_DEFINE                 => "16",
    FILETYPE_HEADER             => "1",
    FILETYPE_OTHER              => "2",
    NOT_COMMENT                 => "0",
    SIMPLE_COMMENT              => "1",
    MULTI_COMMENT               => "2",
    LITERAL                     => "3",
    LITERAL_LITERAL             => "4",
    SQL_LITERAL                 => "5",
    GLOBAL                      => "%Global",
    MACRO                       => "%MACRO",
    REPORT_XML_VERSION          => "1.0",
    REPORT_ROOT_NAME            => "REPORT",
    REPORT_FILE_NUMBER          => "file_number",
    REPORT_FILE_NAME            => "FILE",
    REPORT_NAME                 => "name",
    REPORT_ITEM_NUMBER          => "item_number",
    REPORT_ID                   => "id",
    REPORT_LINE                 => "line",
    REPORT_TYPE                 => "type",
    REPORT_LEVEL                => "level",
    REPORT_STRUCT_NAME          => "STRUCT",
    REPORT_MESSAGE_NAME         => "MESSAGE",
    REPORT_START_TIME           => "start_time",
    REPORT_FINISH_TIME          => "finish_time",
    REPORT_METADATA_NAME        => "METADATA",
    REPORT_PARAMETER_NAME       => "PARAMETER",
    REPORT_STRING_ITEM_NUMBER   => "string_item_number",
    REPORT_REPORT_ITEM_NUMBER   => "report_item_number",
    REPORT_STRING_ITEM_NAME     => "STRING_ITEM",
    REPORT_REPORT_ITEM_NAME     => "REPORT_ITEM",
    REPORT_TARGET_NAME          => "TARGET",
    REPORT_SOURCE_NAME          => "SOURCE",
    REPORT_CLASS_NAME           => "CLASS",
    REPORT_METHOD_NAME          => "METHOD",
    REPORT_VARIABLE_NAME          => "VARIABLE",
    REPORT_LINE_NAME          => "LINE",
    REPORT_COLUMN_NAME          => "COLUMN",
    DEFINITION_COMMON_NAME      => "COMMON",
    DEFINITION_PATTERNDEF_NAME  => "PATTERNDEF",
    DEFINITION_PATID            => "patid",
    DEFINITION_MACRO_NAME       => "MACRO",
    DEFINITION_NAME_NAME        => "NAME",
    DEFINITION_VALUE_NAME       => "VALUE",
    DEFINITION_PATTERN_NAME     => "PATTERN",
    DEFINITION_TYPE             => "type",
    DEFINITION_CHASER           => "chaser",
    DEFINITION_KEYWORDDEF_NAME  => "KEYWORDDEF",
    DEFINITION_ACCESS_TYPE      => "accessType",
    DEFINITION_MESSAGE_NAME     => "MESSAGE",
    DEFINITION_MESSAGE_ID       => "id",
    DEFINITION_MESSAGE_LEVEL    => "level",
    DEFINITION_FILTER           => "filter",
    DEFINITION_POS              => "pos",
    DEFINITION_TARGETDBMS_NAME  => "TARGETDBMS",
    DEFINITION_PLUGIN_NAME      => "PLUGIN",
    DEFINITION_LIBRARY          => "library",
    DEFINITION_PROCEDURE        => "procedure",
    NULL                        => "NULL",
    DELETE_NODE_NAME            => "text|comment",
    PATTERN_BODY_FIRST          => '(?:[^\w\d_]|\A)',
    PATTERN_BODY_LAST           => '(?:[^\w\d_]|\z)',
    PATTERN_BODY_FIRST_FOR_SQL  => '\A \s* ',
    FATAL_MESSAGE               => 'メッセージID %keyword% は報告対象定義ファイルに定義されていません',
    ALLOW_RECURSIVE_NUMBER      => 6,
    EXEC_SQL                    => 'EXEC SQL ',
    CODETYPE_CODE               => 1,
    CODETYPE_SCOPE              => 2,

    RESTYPE_STRING              => 'String',
    RESTYPE_SB                  => 'StringBuffer',
    RESTYPE_CHAR                => 'char',
    RESTYPE_OTHER               => 'Other',
    MNAME_STRING                => 'String',
    MNAME_SB                    => 'StringBuffer',
    MNAME_TOSTRING              => 'toString',
    MNAME_APPEND                => 'append',
    ANALYZE_TEMPDIR             => './.pg_sqlextract_tmp/',

};

#####################################################################
# Constants: ファイル情報の構造体定義
#
# 概要:
# パターン抽出対象となる情報をファイル単位で管理する。
#
# 構造:
# filename    - ファイル名
# packagename - パッケージ名
# classlist   - クラス情報のリファレンスのリスト
#
# 特記事項:
# なし
#
#
#####################################################################
struct FileInfo => {
    filename    => '$',
    packagename => '$',
    classlist   => '@',
};


#####################################################################
# Constants: クラス情報の構造体定義
#
# 概要:
# パターン抽出対象となる情報をクラス単位で管理する。
#
# 構造:
# classname  - クラス名
# methodlist - メソッド情報のリファレンスのリスト
# varlist    - 変数情報のリファレンスのリスト
#
# 特記事項:
# なし
#
#
#####################################################################
struct ClassInfo => {
    classname  => '$',
    methodlist => '@',
    varlist    => '@',
};


#####################################################################
# Constants: 変数情報の構造体定義
#
# 概要:
# クラス内のメンバ変数の情報を管理する。
#
# 構造:
# linenumber - 行番号
# name       - 変数名
# type       - 型名
# value      - 値
#
# 特記事項:
# - 型名として格納される内容は下記の通り
# - String(Stringオブジェクト)
# - StringBuffer(StringBufferオブジェクト)
# - String[](Stringオブジェクトの配列)
# - StringBuffer[](StringBufferの配列)
# - 上記以外の型名
# - 値として格納される内容はトークンリストとなる
# - ArrayInitializer(配列の初期化子)の場合は、中括弧を外して平坦化
#   した状態で格納する。各々の要素はコンマ区切りで格納する
#
#####################################################################
struct VariableInfo => {
    linenumber => '$',
    name       => '$',
    type       => '$',
    value      => '@',
};


#####################################################################
# Constants: メソッド情報の構造体定義
#
# 概要:
# パターン抽出対象となる情報をメソッド単位で管理する。
#
# 構造:
# ident         - メソッド識別子
# name          - メソッド名
# rootscope_ref - ルートスコープ情報のリファレンス
# codelist      - メソッド内に記述されているコードのコード情報の
#                 リファレンスのリスト
# 特記事項:
# なし
#
#####################################################################
struct MethodInfo => {
  ident         => '$',
  name          => '$',
  rootscope_ref => 'Scope',
  codelist      => '@',
};


#####################################################################
# Constants: スコープ情報の構造体定義
#
# 概要:
# パターン抽出対象となる情報をスコープ単位で管理する。
#
# 構造:
# parent        - 親スコープ情報
# codelist      - スコープ内に記述されているコードのコード情報の
#                 リファレンスのリスト
# 特記事項:
# - 子スコープ情報の集合は、codelistにて管理する
#
#####################################################################
struct Scope => {
    parent   => 'Scope',
    codelist => '@',
    varlist => '@',
};


#####################################################################
# Constants: コード情報の構造体定義
#
# 概要:
# 正規化されたコードに対する情報を管理する。
#
# 構造:
# linenumber    - 行番号 
# codeType      - 格納しているコードの種別を格納する。
#                 トークンリストのリファレンス(0x01)か
#                 スコープ情報へのリファレンス(0x02)を値をして保持する
# tokenlist      - トークンリストのリファレンスまたは、スコープ情報の
#                  リファレンス
# exprlist       - 式情報リストのリファレンスのリスト
#
# 特記事項:
# - トークンリストは、字句解析（レクサ）の返却結果を要素、とした、簡易的な
#   ツリー構造を形成する。ツリー構造により、構文の構造情報を保持する。
#   ツリー構造のノードは基本的に構文定義ごとに下記の構造で生成する。
# |　
# |　
# | ノードの情報はリスト(配列)で管理する
# | 第１要素は、ノード名（'N_****'という文字列)
# | 第２要素以降は、当該ノードの子ノード
# |　
# |　
# |　
# | 例) if(condition) value += "WHERE"; という構文に対するトークンリスト
# |　
# | N_ifノード 
# | ('N_if', N_Expression(1), N_Delimiter, N_Expression)
# |　
# | N_Expressionノード (1)
# | ('N_Expression', N_Primary(1))
# |　
# | N_Primaryノード(1)
# | ('N_Primary', 要素(condition))  <-- conditionに対するIDENTIFIER要素
# |　
# | N_Expressionノード (2)
# | ('N_Expression', N_AssignmentOperator)
# |　
# | N_AssignmentOperatorノード
# | ('N_AssignmentOperator', N_Primary(2), 要素(+=), N_Primary(3))
# |　
# | N_Primaryノード(2)
# | ('N_Primary', 要素(value))  <-- valueに対するIDENTIFIER要素
# |　
# | N_Primaryノード(3)
# | ('N_Primary', 要素("WHERE"))  <-- "WHERE"に対するSTRING_LITERAL要素
# |　
# |　
#
# - トークンリストは、以降に示す「式情報リスト」を作成するための情報収集のために
#   作成される。「スコープを意識した式解析」においては以降で示す「式情報リスト」
#   を使用し、トークンリストは使用しない。しかし、今後の拡張性を考慮して、収集した
#   情報自体は参照可能なように保持する。
#
# - 式情報リストは、スコープを意識した式解析に特化した情報を収集した集合である。
#   当式解析では不要な情報（if文などの制御文情報)を削除し、Expressions構文を示す
#   トークンの情報のみを管理する（ツリー構造自体も保持しない）。
# |　
# |　
# | 例) if(condition) value += "WHERE"; という構文に対する式情報リスト
# |     ParExpression構文(condition)と、Statement構文(value += "WHERE")の情報
# |     を管理する。
# |　
# |　
# | exprlist = (
# |   [要素(condition)],                     --- (1)
# |   [要素(value), 要素(+=), 要素("WHERE")] --- (2)
# | )
# |　
# |　
# | ここで、[]はリストのリファレンスを示す。
# | つまり、(1)(2)それぞれのリストのリファレンスを式情報リストは管理している。
#
#
#####################################################################
struct CodeSet => {
    linenumber    => '$',
    codeType      => '$',
    tokenlist     => '@',
    exprlist      => '@'
};


#####################################################################
# Constants: トークン情報の構造体定義
#
# 概要:
# 1トークンの情報を管理する。
#
# 構造:
# token - トークン実体(文字列) 
# id    - トークンを一意に識別するためのID
#
# 特記事項:
# トークンの種別を判断する場合は、idによる判定を行うこと。トークン
# 識別子とidとの対応は、グローバル定義されている「tokenId」ハッシュ
# を参照することで取得できる。
# |　
# |　
# | 例) CLASS_TOKEN("class")を識別する場合
# |　
# | if(currentToken->id() == $tokenId{'CLASS_TOKEN'})) {
# |    #classだった場合の処理
# | }
# |　
#
#####################################################################
struct Token => {
    token => '$',
    id    => '$'
};

#####################################################################
# Constants: 式解析結果(ファイル)の構造体定義
#
# 概要:
# ファイル単位の式解析結果を管理する。
#
# 構造:
# fileinfo_ref - 式解析対象元となるファイルのファイル情報
# classlist   - 式解析結果（クラス）のリスト
#
# 特記事項:
# なし
#
#####################################################################
struct AnalysisResultsFile => {
    fileinfo_ref => 'FileInfo',
    classlist    => '@'
};


#####################################################################
# Constants: 式解析結果(クラス)の構造体定義
#
# 概要:
# クラス単位の式解析結果を管理する。
#
# 構造:
# classset_ref - 式解析対象元となるファイルのクラス情報
# methodlist   - 式解析結果（メソッド）のリスト
#
# 特記事項:
# なし
#
#####################################################################
struct AnalysisResultsClass => {
    classinfo_ref => 'ClassInfo',
    methodlist    => '@'
};

#####################################################################
# Constants: 式解析結果(メソッド)の構造体定義
#
# 概要:
# メソッド単位の式解析結果を管理する。
#
# 構造:
# methodinfo_ref - 式解析対象元となるファイルのメソッド情報
# codelist   - 式解析結果（コード）のリスト
#
# 特記事項:
# なし
#
#####################################################################
struct AnalysisResultsMethod => {
    methodinfo_ref => 'MethodInfo',
    codelist       => '@'
};

#####################################################################
# Constants: 式解析結果(コード)の構造体定義
#
# 概要:
# 式解析結果を管理する。
#
# 構造:
# target     - 式解析対象元となるファイルのメソッド情報
# linenumber - 式解析結果（コード）のリスト
# variablename - コードを保持する変数名
# details    - 構成情報(連結文字列情報)のリスト
#
# 特記事項:
# なし
#
#####################################################################
struct AnalysisResultsCode => {
    target     => '$',
    linenumber => '$',
    variablename => '$',
    details      => '@'
};


#####################################################################
# Constants: 報告結果(ファイル)の構造体定義
#
# 概要:
# パターン抽出結果をファイル単位で管理する。
#
# 構造:
# filename     - ファイル名
# string_list  - 報告結果(文字列)のリスト
# pattern_list - 報告結果(パターン)のリスト
#
# 特記事項:
# なし
#
#####################################################################
struct ExtractResultsFile => {
    filename     => '$',
    string_list  => '@',
    pattern_list => '@'
};

#####################################################################
# Constants: 報告結果(文字列)の構造体定義
#
# 概要:
# 抽出した文字列リテラルを管理する。
#
# 構造:
# string     - 抽出した文字列リテラル
# linenumber - 文字列の行番号 
#
# 特記事項:
# なし
#
#####################################################################
struct ExtractResultsString => {
    string      => '$',
    linenumber  => '$',
};

#####################################################################
# Constants: 報告結果(パターン)の構造体定義
#
# 概要:
# 抽出したパターンと報告内容を管理する。
#
# 構造:
# message_id   - メッセージID
# linenumber   - 行番号
# pattern_type - 抽出パターン種別
# level        - 報告レベル
# struct       - 抽出時に使用したパターン文字列
# target       - 抽出対象となったSQL文字列
# message      - 抽出パターンに対する報告内容
# pattern_pos  - 抽出対象位置
# variablename - 抽出対象の変数名
# methodname   - 抽出対象のメソッド名
# classname    - 抽出対象のクラス名
# targetdbms   - 辞書バージョン情報DOMツリー
#
# 特記事項:
# なし
#
#####################################################################
struct ExtractResultsPattern => {
    message_id    => '$',
    linenumber    => '$',
    pattern_type  => '$',
    level         => '$',
    struct        => '$',
    target        => '$',
    message       => '$',
    pattern_pos   => '$',
    variablename  => '$',
    methodname    => '$',
    classname     => '$',
    targetdbms    => '$',
};


#####################################################################
# Constants: 変数辞書の構造体定義
#
# 概要:
# 変数情報をスコープ単位で管理する。
#
# 構造:
# parent                - 親変数辞書
# variable_contents_ref - 変数名と変数情報を管理するハッシュ 
#
# 特記事項:
# なし
#
#####################################################################
struct VariableDic => {
	parent                  => 'VariableDic',
	variable_contents_ref	=> '%'
};


#####################################################################
# Constants: 変数情報(変数辞書)の構造体定義
#
# 概要:
# 変数辞書が管理する、変数情報の実体である。
#
# 構造:
# codeType     - 型
# name         - 変数名
# value        - 値
# line         - 行番号
# ref_flg      - 当該変数が参照された場合に真となるフラグ
# prev_ref_flg - 当該変数が一度でも参照された場合に真となるフラグ
# copy         - 親の変数辞書からコピーした際に真となるフラグ
# component    - 変数の構成情報(連結文字列情報)
# declarationType    - 宣言種別(C言語用)
#
# 特記事項:
# - ref_flgは、当該変数が、処理上、ソースコード中のロジック上に関わらず
# 参照された場合に真となる。prev_ref_flgは、そのうち、ソースコード中
# のロジック上で参照されたと判断できた場合にのみ真となる。処理上の参照
# の場合は、prev_ref_flgは真とならず、また、ref_flgも偽に戻される。
#
#####################################################################
struct VariableContent => {
	codeType   => '$',
	name	   => '$',
	value      => '$',
	line       => '$',
	ref_flg	   => '$',   #参照フラグ
	prev_ref_flg => '$', #前回参照されていたか示すフラグ
    copy       => '$',   #親の変数辞書からコピーした際に真となる
    component  => '@',   #変数の構成情報
	declarationType => '$'  #宣言種別
};


#####################################################################
# Constants: 一時辞書内容の構造体定義
#
# 概要:
# 解析中の情報を管理する。
#
# 構造:
# codeType - データ型
# name     - 変数名
# value    - 値
# val_flg  - 評価対象である場合は真
# line     - 解析を実行した行番号 
# component - 変数の構成情報(連結文字列情報)
#
# 特記事項:
# なし
#
#####################################################################
struct Temp_Content => {
	codeType   => '$',
	name	   => '$',
	value      => '$',
	val_flg	   => '$',
	line       => '$',
	component  => '@'  #変数の構成情報
};


#####################################################################
# Constants: 連結文字列情報の構造体定義
#
# 概要:
# 連結文字列の連結単位の情報を管理する。
#
# 構造:
# line     - 連結を行なった行番号 
# value    - 文字列
# length   - 文字列のサイズ
# code_count  - 論理行のカウンタ
# block_count - 文字列ブロックのカウンタ
#
# 特記事項:
# なし
#
#####################################################################
struct VariableComponent => {
	line   => '$', #変数宣言 or 文字列連結を行っている行番号
	length => '$', #連結文字列のサイズ
	code_count => '$', #論理行のカウンタ
	block_count => '$' #文字列ブロックのカウンタ
};

#####################################################################
# Constants: Cファイル情報の構造体定義
#
# 概要:
# パターン抽出対象となる情報をファイル単位で管理する。
#
# 構造:
# filename    - ファイル名
# functionlist   - 関数情報のリファレンスのリスト
# varlist   - 変数情報のリファレンスのリスト
#
# 特記事項:
# なし
#
#
#####################################################################
struct CFileInfo => {
    filename        => '$',
    functionlist    => '@',
    varlist         => '@',
};

#####################################################################
# Constants: 関数情報の構造体定義
#
# 概要:
# パターン抽出対象となる情報を関数単位で管理する。
#
# 構造:
# functionname  - 関数名
# rootscope_ref - ルートスコープ情報のリファレンス
# codelist - コード情報のリファレンスのリスト
#
# 特記事項:
# なし
#
#
#####################################################################
struct FunctionInfo => {
    functionname  => '$',
    rootscope_ref => 'Scope',
    codelist => '@',
};

#####################################################################
# Constants: C言語の変数情報の構造体定義
#
# 概要:
# C言語の変数の情報を管理する。
#
# 構造:
# linenumber - 行番号
# name       - 変数名
# type       - 型名
# value      - 値
#
# 特記事項:
# - 型名として格納される内容は下記の通り
# - Char
# - 上記以外の型名
# - 値として格納される内容はトークンリストとなる
# - ArrayInitializer(配列の初期化子)の場合は、中括弧を外して平坦化
#   した状態で格納する。各々の要素はコンマ区切りで格納する
#
#####################################################################
struct CVariableInfo => {
    linenumber => '$',
    name       => '$',
    type       => '$',
    declarationType       => '$',
    value      => '@',
};

#####################################################################
# Constants: C言語 式解析結果(ファイル)の構造体定義
#
# 概要:
# C言語モードのファイル単位の式解析結果を管理する。
#
# 構造:
# filename - ファイル名
# functionlist   - 式解析結果（関数）のリスト
#
# 特記事項:
# なし
#
#####################################################################
struct CAnalysisResultsFile => {
    filename        => '$',
    functionlist    => '@'
};

#####################################################################
# Constants: 式解析結果(関数)の構造体定義
#
# 概要:
# 関数単位の式解析結果を管理する。
#
# 構造:
# functionname  - 関数名
# embcodelist   - 式解析結果（埋め込みSQL）のリスト
# codelist      - 式解析結果（コード）のリスト
# host_variable - 式解析結果（ホスト名）
#
# 特記事項:
# なし
#
#####################################################################
struct AnalysisResultsFunction => {
    functionname    => '$',
    embcodelist     => '@',
    codelist        => '@',
    host_variable   => '%'
};

#####################################################################
# Constants: 式解析結果(埋め込みSQL)の構造体定義
#
# 概要:
# 式解析結果を管理する。
#
# 構造:
# target     - 式解析対象元となる文字列
# linenumber - 式解析結果（埋め込みSQL）のリスト
# details    - 構成情報(連結文字列情報)のリスト
#
# 特記事項:
# なし
#
#####################################################################
struct AnalysisResultsEmbCode => {
    target     => '$',
    linenumber => '$',
    details      => '@'
};

#####################################################################
# Function: set_loglevel
#
#
# 概要:
#
# ログ出力レベルを設定する。
#
# パラメータ:
# loglevel - ログ出力レベル
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

sub set_loglevel {
    my ($level) = @_;
    $G_loglevel = $level;
}


#####################################################################
# Function: get_loglevel
#
#
# 概要:
#
# ログ出力レベルを返却する。
#
# パラメータ:
# なし
#
# 戻り値:
# loglevel - ログ出力レベル
#
# 例外:
# なし
#
# 特記事項:
# なし
#
#####################################################################

sub get_loglevel {
    return $G_loglevel;
}

#####################################################################
# Function: push_report
#
#
# 概要:
#
# 1報告内容を作成し、報告結果配列に格納する。
#
# パラメータ:
# result       - 報告結果配列
# filename     - ファイル名
# message_id   - メッセージID
# line_number  - 行番号
# pattern_type - 抽出パターン種別
# report_level - 報告レベル
# pattern_body - 抽出パターン定義
# message_body - メッセージ内容
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


sub push_report {
    my ($result , $filename, $message_id, $line_number, $pattern_type
    , $report_level, $pattern_body, $message_body) = @_; #引数の格納
    
    #
    #報告結果ファイルの格納
    #
    push(@{ $result->{$filename} },
            {
                message_id   => $message_id,
                line_number  => $line_number,
                pattern_type => $pattern_type,
                report_level => $report_level,
                pattern_body => $pattern_body,
                message      => $message_body,
            }
   );
}

#####################################################################
# Function: print_log
#
#
# 概要:
#
# ログ出力を行う。
#
# パラメータ:
# なし
#
# 戻り値:
# log - ログ出力内容
#
# 例外:
# なし
#
# 特記事項:
# なし
#
#####################################################################

sub print_log {
    my ($log) = @_;   #引数の格納
	printf(STDERR "%s %s\n", get_localtime(), $log);
}

#####################################################################
# Function: get_localtime
#
#
# 概要:
#
# 現在時刻を示す文字列を取得する。
#
# パラメータ:
# なし
#
# 戻り値:
# time_string - 現在時刻を示す文字列
#
# 例外:
# なし
#
# 特記事項:
# なし
#
#####################################################################
sub get_localtime {
    my ($sec,$min,$hour,$mday,$mon,$year) = (localtime(time))[0..5];
    $year += 1900;
    $mon += 1;
    return sprintf("%s/%s/%s %.2d:%.2d:%.2d",
		$year, $mon, $mday, $hour, $min, $sec);
    
}

#####################################################################
# Function: read_input_file
#
#
# 概要:
#
# 指定されたファイルをオープンしその内容を読み込む。
# 
#
# パラメータ:
# file_name     - ファイル名
# encoding_name - エンコード
#
# 戻り値:
# file_strings  - ファイル内容
#
# 例外:
# - ファイルオープンエラーが発生した場合。
#
# 特記事項:
# なし
#
#
#####################################################################
sub read_input_file{
    my ($file_name, $encoding_name) = @_; #引数の格納
    my $file_strings = "";#ファイル内容文字列
    #
    #ファイルのオープン
    #
    open(READ, "<:encoding($encoding_name)", $file_name) or croak "File open error $file_name($!)\n";
    #
    #ファイル内容の読み込み
    #
    $file_strings = do { local $/; <READ> };
    
    #
    #ファイルのクローズ
    #
    close(READ);
    
    return $file_strings;
}

#####################################################################
# Function: create_input_file_list
#
#
# 概要:
#
# 入力ファイルを格納するディレクトリ内に存在する、全ての抽出対象ファイル名
#を格納するリストを作成する。
#
# パラメータ:
# input_dir         - 入力ファイル格納フォルダ
# suffix_list       - 拡張子リスト
# file_list         - 直接指定された入力ファイルのリスト
#
# 戻り値:
# file_name_list    - ファイル名のリスト
#
# 例外:
# なし
#
# 特記事項:
# なし
#
#
#####################################################################
sub create_input_file_list{
    my ($input_dir,$suffix_list, $file_list) = @_; #引数の格納
    my @file_name_list = ();#ファイル名リスト
    my $suffix = "";#拡張子
    my $suffix_pattern = undef;#拡張子
    my $file_name = "";#ファイル名
    get_loglevel() > 2 and print_log("(DEBUG 3) | [in] create_input_file_list");
    if(defined $input_dir) {
        #
        #拡張子リストの作成
        #
        if(scalar @{ $suffix_list } != 0) {
            $suffix_pattern = '(?:' . join('|', @{ $suffix_list }) . ')';
        }
        
        #
        #fileリストの作成
        #
        find(sub{
                    $file_name = $File::Find::name;
                    #
                    #ファイル名の格納
                    #
                    if(defined $suffix_pattern) {
                        if(-f basename($file_name)
                            and $file_name =~ m{.*[.]$suffix_pattern$}xmsi) {
                            push(@file_name_list,$file_name);
                            get_loglevel() > 6 and print_log("(DEBUG 7) | file name [$file_name]");
                        }
                    }
                    else {
                        if(-f basename($file_name)) {
                            push(@file_name_list,$file_name);
                            get_loglevel() > 6 and print_log("(DEBUG 7) | file name [$file_name]");
                        }
                    }
    
                } , $input_dir);
    
    }
    #
    # 入力ファイルリストを追加する
    #
    if(scalar @{ $file_list} > 0) {
        push(@file_name_list, @{ $file_list });
    }
    get_loglevel() > 2 and print_log("(DEBUG 3) | [out] create_input_file_list");

    return \@file_name_list;
}

#####################################################################
# Function: set_loglevel
#
#
# 概要:
#
# 変数追跡対象パターンを設定する。
#
# パラメータ:
# chaserpattern - 変数追跡対象パターン
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
sub set_chaserpattern {
    my ($chaserpattern) = @_;
    $G_chaserpattern = $chaserpattern;
}

#####################################################################
# Function: get_chaserpattern
#
#
# 概要:
#
# 変数追跡対象パターンを返却する。
#
# パラメータ:
# なし
#
# 戻り値:
# chaserpattern - 変数追跡対象パターン
#
# 例外:
# なし
#
# 特記事項:
# なし
#
#####################################################################
sub get_chaserpattern {
    return $G_chaserpattern;
}

1;
