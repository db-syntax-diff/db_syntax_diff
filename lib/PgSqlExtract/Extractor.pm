#!/usr/bin/perl
#############################################################################
#  Copyright (C) 2007-2011 NTT
#############################################################################

#####################################################################
# Function: Extractor.pm
#
#
# 概要:
# パターン抽出機能を定義する。
# パターン抽出機能は、入力ファイル解析機能で作成された関数辞書に格納
# されているすべてのコード情報に対して、パターン抽出を実行する。
#
# 特記事項:
# なし
#
#
#####################################################################

package PgSqlExtract::Extractor;
use warnings;
no warnings "recursion";
use strict;
use Carp;
use PgSqlExtract::Common;
use PgSqlExtract::ExpressionAnalyzer qw(analyze_target);
use PgSqlExtract::CExpressionAnalyzer qw(Canalyze_target);
use utf8;

use base qw(Exporter);

our @EXPORT_OK = qw( 
    execute_plan_for_analysis_results_C 
    execute_plan_for_analysis_results execute_plan_a_file execute_plan_a_class
    execute_plan_a_method extract_string extract_sql_at_string
    extract_pattern create_execute_plan execute_plan execute_plan_by_function 
    extract_execsql extract_sql_at_literal extract_sql_at_literal_common 
    extract_embedded_sql extract_sql extract_function extract_type 
    extract_pattern_at_type extract_one_pattern get_devolve_pattern_id create_matching 
    clear_scope
);

#####################################################################
# Function: extract_pattern
#
#
# 概要:
# 関数辞書に格納されているすべてのコード情報に対して、パターン抽出を実行
# する。
# 動作モードが(Java抽出モード)の場合、抽出対象辞書に対する式解析を実施し、
# その結果（式解析結果(ファイル)）に対するパターン抽出を実行する。
#
#
# パラメータ:
# func_dic_ref    - 関数辞書
# pattern_dic_ref - パターン辞書
# mode            - 動作モード
# result_ref      - 報告結果配列(出力用)
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

sub extract_pattern {
    my ( $func_dic_ref, $pattern_dic_ref, $mode, $result_ref ) =
      @_;
    
    #
    # 動作モードに対して実行するモジュールへのリファレンスリストを
    # 作成する
    #
    my $module_list_ref = create_execute_plan($mode);
       

    my $parameter = {
        module_list_ref => $module_list_ref,
        pattern_dic_ref => $pattern_dic_ref,
        result_ref      => $result_ref
    };
     
    if($mode eq MODE_JAVA) {
        
        #
        # 動作モードが(Java抽出モード)の場合、抽出対象辞書に対する式解析を実施
        # し、その結果（式解析結果(ファイル)）に対するパターン抽出を実行する
        #
        my $analysis_results = analyze_target($func_dic_ref);
        $parameter->{'func_dic_ref'} = $analysis_results;
        
        execute_plan_for_analysis_results($parameter);
        undef $analysis_results;
        undef $parameter->{'func_dic_ref'};
        #
        # すべてのファイルについて実行する
        #
        for my $fileinfo_ref (@{$func_dic_ref}) {
            #
            # すべてのクラス情報について実行する
            #
            for my $classinfo (@{$fileinfo_ref->classlist()}) {

                #
                # すべてのメソッド情報について式解析を実行する
                #
                for my $methodinfo (@{$classinfo->methodlist()}) {
                    clear_scope($methodinfo->rootscope_ref);
                }# すべてのメソッド情報について式解析を実行終了
            }# すべてのクラス情報について実行終了
        }# すべてのファイルについて実行終了
    } elsif($mode eq MODE_C) {
        #
        # 動作モードが(埋め込み抽出モード)の場合、抽出対象辞書に対する式解析を実施
        # し、その結果（式解析結果(ファイル)）に対するパターン抽出を実行する
        #
        my $Canalysis_results = Canalyze_target($func_dic_ref);
        $parameter->{'func_dic_ref'} = $Canalysis_results;
        
        execute_plan_for_analysis_results_C($parameter);
        undef $Canalysis_results;
        undef $parameter->{'func_dic_ref'};
        
        #
        # すべてのファイルについて実行する
        #
        for my $fileinfo_ref (@{$func_dic_ref}) {
            #
            # すべての関数情報について実行する
            #
            for my $functioninfo (@{$fileinfo_ref->functionlist()}) {
                clear_scope($functioninfo->rootscope_ref);
            }# すべての関数情報について実行終了
        }# すべてのファイルについて実行終了
    } else {
        #
        # パターン抽出を実行する
        # 抽出結果は、報告結果配列($result_ref)に格納される
        #
        $parameter->{'func_dic_ref'} = $func_dic_ref;
        execute_plan($parameter);
    }
    

    return;
}

#####################################################################
# Function: clear_scope
#
#
# 概要:
# スコープ情報に格納されているすべてのコード情報に対してundefを実行する。
# 親スコープ情報を保持している場合は再帰的にモジュールを呼び出す。
#
# パラメータ:
# scopeinfo    - スコープ情報
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

sub clear_scope {
    my ( $scopeinfo ) = @_;
    
    #
    # スコープに属するすべてのコード情報について実行する
    #
    for my $code (@{ $scopeinfo->codelist() }) {
        #
        # コード情報をクリア
        #
        undef $code;
    }

    #
    # 親スコープ情報が存在する場合はコード情報をクリアするモジュールを
    # 再帰的に呼び出す。
    if(defined $scopeinfo->parent){
         clear_scope($scopeinfo->parent);
    }

}


#####################################################################
# Function: create_execute_plan
#
#
# 概要:
# 動作モードに対して実行するモジュールへのリファレンスリストを作成する。
#
# パラメータ:
# mode            - 動作モード
#
# 戻り値:
# module_list_ref - 実行するモジュールリスト
#
# 例外:
# なし
#
# 特記事項:
# 実行するモジュールリストは以下の構造を持つ。
# 以下、抽出パターンモジュールリストは、その動作モードに必要なモジュール
# のみが登録される。
#
#
#|<抽出パターンモジュールリスト>
#|{
#|  module         => ["通常のパターン抽出を実行する関数へのリファレンス"]
#|  execsql_module => ["EXEC SQL文を検出した場合のパターン抽出を実行する関数へのリファレンス"]
#|  define_phase   => #define文の検出を行う関数へのリファレンス
#|  is_chaser_mode => 変数追跡構文が存在した場合に追跡を行うかを指定するフラグ
#|                    TRUEの場合、追跡を行う
#|  is_analyze_type=> 関数辞書内の型情報について、ホスト変数抽出を行うかを
#|                    指定するフラグ。 TRUEの場合、処理を実行する
#|
#|}
#
#####################################################################
sub create_execute_plan {
    my ($mode) = @_;

    #
    # 動作モードごとにモジュールリストを作成する。
    #
    my $modulelist = {};

    #
    # 埋め込みSQL抽出モードの場合
    #
    if ( $mode eq MODE_C ) {
        my @module         = (
            \&extract_sql,
            \&extract_function
        );
        my @execsql_module = (
            \&extract_embedded_sql,
            \&extract_sql,
            \&extract_function
        );
        $modulelist->{module}         = \@module;
        $modulelist->{execsql_module} = \@execsql_module;
    }

    #
    # SQL抽出モードの場合
    #
    elsif ( $mode eq MODE_SQL ) {
        my @module = (
            \&extract_type,
            \&extract_sql,
            \&extract_function
        );
        $modulelist->{module} = \@module;
    }

    #
    # 簡易抽出モードの場合
    #
    elsif ( $mode eq MODE_SIMPLE) {
        my @module = (
            \&extract_sql_at_literal
        );
        my @execsql_module = (
            \&extract_embedded_sql,
            \&extract_function
        );
        $modulelist->{module}         = \@module;
        $modulelist->{execsql_module} = \@execsql_module;
    }
    
    #
    # Javaソースコード対応モードの場合
    #
    else {
        my @module = (
            \&extract_sql,
            \&extract_function
        );
        $modulelist->{module} = \@module;
    }

    return $modulelist;

}

#####################################################################
# Function: execute_plan_for_analysis_results
#
#
# 概要:
# すべての式解析結果（ファイル）について、パターン抽出を行う。
# - 式解析結果（ファイル）の内容について、モジュールリストに登録されている
#   パターン抽出モジュールを実行する。
#
# パラメータ:
# parameter - パラメータ情報。以下の情報を格納するハッシュである
# - module_list_ref - モジュールリスト
# - func_dic_ref    - 式解析結果(ファイル)
# - pattern_dic_ref - パターン辞書
# - result_ref      - 報告結果配列(出力用)
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
sub execute_plan_for_analysis_results {
    my ($parameter) = @_;
    
    my $filelist = $parameter->{func_dic_ref};
    
    for my $fileinfo (@{$filelist}) {
        execute_plan_a_file($parameter, $fileinfo);    
    }
}


#####################################################################
# Function: execute_plan_a_file
#
#
# 概要:
# 式解析結果(ファイル)について、パターン抽出を行う。
# - 式解析結果(ファイル)に存在する、すべての式解析結果(クラス)の内容について、
#   モジュールリストに登録されているパターン抽出モジュールを実行する。
# - 報告結果(ファイル)を新規に生成し、パターン抽出した結果を報告結果配列(出力用)
#   に登録する。
#
# パラメータ:
# parameter - パラメータ情報。以下の情報を格納するハッシュである
# - module_list_ref - モジュールリスト
# - func_dic_ref    - 式解析結果(ファイル)
# - pattern_dic_ref - パターン辞書
# - result_ref      - 報告結果配列(出力用)
# fileinfo  - ファイル情報
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
sub execute_plan_a_file {
    my ($parameter, $fileinfo) = @_;
    my $result_ref = $parameter->{result_ref};
    
    my $classlist = $fileinfo->classlist();
    my $extract_results = ExtractResultsFile->new();
    
    my $filename = $fileinfo->fileinfo_ref()->filename();
    $extract_results->filename($filename);
    
    for my $classinfo (@{$classlist}) {
        execute_plan_a_class($parameter, $classinfo, $extract_results);    
    }
    
    push(@{$result_ref}, $extract_results);
    
}

#####################################################################
# Function: execute_plan_a_class
#
#
# 概要:
# 式解析結果(クラス)について、パターン抽出を行う。
# - 式解析結果(クラス)に存在する、すべての式解析結果(メソッド)の内容について、
#   モジュールリストに登録されているパターン抽出モジュールを実行する。
#
# パラメータ:
# parameter - パラメータ情報。以下の情報を格納するハッシュである
# - module_list_ref - モジュールリスト
# - func_dic_ref    - 式解析結果(ファイル)
# - pattern_dic_ref - パターン辞書
# - result_ref      - 報告結果配列(出力用)
# - classname      - 解析クラス名(出力用)
# classinfo - クラス情報
# result     - 報告結果(ファイル)
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
sub execute_plan_a_class {
    my ($parameter, $classinfo, $result) = @_;
    
    my $methodlist = $classinfo->methodlist();
    
    #
    #報告用にクラス名を格納
    #
    $parameter->{classname} = $classinfo->classinfo_ref->classname();
    for my $methodinfo (@{$methodlist}) {
        execute_plan_a_method($parameter, $methodinfo, $result);    
    }
}

#####################################################################
# Function: execute_plan_a_method
#
# 概要:
# 式解析結果(メソッド)について、パターン抽出を行う。
# - 式解析結果(メソッド)に存在する、すべての式解析結果(コード)の内容について、
#   文字列リテラルの抽出、およびパターン抽出を行い、その結果を報告結果(ファイル)
#   に登録する。
#
# パラメータ:
# parameter  - パラメータ情報。以下の情報を格納するハッシュである
# - module_list_ref - モジュールリスト
# - func_dic_ref    - 式解析結果(ファイル)
# - pattern_dic_ref - パターン辞書
# - result_ref      - 報告結果配列(出力用)
# - classname      - 解析クラス名(出力用)
# - code_body       - 1コード
# - line_number     - 1コードの行番号
# - methodname      - 解析メソッド名(出力用)
# - details      - 文字列位置情報(出力用)
# - variablename      - 解析変数名(出力用)
# methodinfo - メソッド情報
# result     - 報告結果(ファイル)
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
sub execute_plan_a_method {
    my ($parameter, $methodinfo, $result) = @_;
    
    my $methodlist = $methodinfo->codelist();
    
    #
    #メソッド名の有無を確認し、報告用メソッド名を格納
    #
    if( defined $methodinfo->methodinfo_ref ){
        $parameter->{methodname} = $methodinfo->methodinfo_ref->name();
    }else{
        $parameter->{methodname} = '[class variable]';
    }

    for my $codeinfo (@{$methodlist}) {
        #
        # パターン抽出対象のコード、行数、文字列位置情報
        # 変数名をパラメータ情報に設定
        #
        $parameter->{code_body}   = $codeinfo->target();
        $parameter->{line_number} = $codeinfo->linenumber();
        $parameter->{details} = $codeinfo->details();
        $parameter->{variablename} = $codeinfo->variablename();
        
        #
        # パターン抽出対象文字列を報告結果に登録する
        #
        my $string_result = extract_string($parameter);
        if($string_result) {
            push(@{$result->string_list}, $string_result);
        }
        
        #
        # パターン抽出を行い、その結果を報告結果に登録する
        #
        my $pattern_result = extract_sql_at_string($parameter, PATTERN_TYPE_SQL);
        if($pattern_result) {
            push(@{$result->pattern_list}, @{$pattern_result});
        }
        undef $codeinfo;
        undef $parameter->{details};
    }
}

#####################################################################
# Function: execute_plan_for_analysis_results_C
#
#
# 概要:
# すべての式解析結果（ファイル）について、パターン抽出を行う。
# - 式解析結果（ファイル）の内容について、モジュールリストに登録されている
#   パターン抽出モジュールを実行する。
#
# パラメータ:
# parameter - パラメータ情報。以下の情報を格納するハッシュである
# - module_list_ref - モジュールリスト
# - func_dic_ref    - 式解析結果(ファイル)
# - pattern_dic_ref - パターン辞書
# - result_ref      - 報告結果配列(出力用)
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
sub execute_plan_for_analysis_results_C {
    my ($parameter) = @_;
    
    my $filelist = $parameter->{func_dic_ref};
    my $result_ref = $parameter->{result_ref};

    for my $fileinfo (@{$filelist}) {
        my $extract_results = ExtractResultsFile->new();
        
        my $filename = $fileinfo->filename();
        $extract_results->filename($filename);
        
        for my $functioninfo (@{$fileinfo->functionlist()}) {
            #
            #報告用にクラス名を格納
            #
            $parameter->{classname} = $functioninfo->functionname();
            execute_plan_a_function($parameter, $functioninfo, $extract_results, PATTERN_TYPE_SQL);    
            execute_plan_a_function($parameter, $functioninfo, $extract_results, PATTERN_TYPE_EMBSQL);    
            execute_plan_a_hostvariable($parameter, $functioninfo->host_variable(), $extract_results);    
        }
        
        push(@{$result_ref}, $extract_results);
    }
}

#####################################################################
# Function: execute_plan_a_function
#
# 概要:
# 式解析結果(関数)について、パターン抽出を行う。
# - 式解析結果(関数)に存在する、すべての式解析結果(コード)または(埋め込みSQL)
#   の内容について、文字列リテラルの抽出およびパターン抽出を行い、
#   その結果を報告結果(ファイル)に登録する。
#
# パラメータ:
# parameter  - パラメータ情報。以下の情報を格納するハッシュである
# - module_list_ref - モジュールリスト
# - func_dic_ref    - 式解析結果(ファイル)
# - pattern_dic_ref - パターン辞書
# - result_ref      - 報告結果配列(出力用)
# - classname      - 解析クラス名(出力用)
# - code_body       - 1コード
# - line_number     - 1コードの行番号
# - methodname      - 解析メソッド名(出力用)
# - details      - 文字列位置情報(出力用)
# - variablename      - 解析変数名(出力用)
# functioninfo - 関数情報
# result     - 報告結果(ファイル)
# mode  - 式解析結果(コード)または(埋め込みSQL)の種別
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
sub execute_plan_a_function {
    my ($parameter, $functioninfo, $result, $mode) = @_;
    my $codelist = undef;
    if($mode eq PATTERN_TYPE_SQL ) {
        $codelist = $functioninfo->codelist();
    }else{
        $codelist = $functioninfo->embcodelist();
    }
    

    for my $codeinfo (@{$codelist}) {
        #
        # パターン抽出対象のコード、行数、文字列位置情報
        # 変数名をパラメータ情報に設定
        #
        $parameter->{code_body}   = $codeinfo->target();
        $parameter->{line_number} = $codeinfo->linenumber();
        $parameter->{details} = $codeinfo->details();
        if($mode eq PATTERN_TYPE_SQL ) {
            $parameter->{variablename} = $codeinfo->variablename();
        }
        
        #
        # パターン抽出対象文字列を報告結果に登録する
        #
        my $string_result = extract_string($parameter);
        if($string_result) {
            push(@{$result->string_list}, $string_result);
        }
        
        #
        # パターン抽出を行い、その結果を報告結果に登録する
        #
        my $pattern_result = extract_sql_at_string($parameter, $mode);
        
        if($pattern_result) {
            push(@{$result->pattern_list}, @{$pattern_result});
        }
        undef $codeinfo;
        undef $parameter->{details};
    }
    
    # 埋め込みSQL、ホスト変数宣言判定時に変数名が誤って報告されないように初期化
    if($mode eq PATTERN_TYPE_SQL ) {
        $parameter->{variablename} = undef;
    }

}

#####################################################################
# Function: execute_plan_a_hostvariable
#
# 概要:
# 式解析結果(ホスト変数名)について、報告結果を作成する。
# - 式解析結果(関数)に存在する、式解析結果(ホスト変数名)
#   の内容について、報告結果(ファイル)に登録する。
#
# パラメータ:
# parameter  - パラメータ情報。以下の情報を格納するハッシュである
# - module_list_ref - モジュールリスト
# - func_dic_ref    - 式解析結果(ファイル)
# - pattern_dic_ref - パターン辞書
# - result_ref      - 報告結果配列(出力用)
# - classname      - 解析クラス名(出力用)
# - code_body       - 1コード
# - line_number     - 1コードの行番号
# - methodname      - 解析メソッド名(出力用)
# - details      - 文字列位置情報(出力用)
# - variablename      - 解析変数名(出力用)
# host_variable - 式解析結果(ホスト変数名)
# result     - 報告結果(ファイル)
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
sub execute_plan_a_hostvariable {
    my ($parameter, $host_variable, $result) = @_;

    # ターゲット情報に設定されてしまうため、最終行の情報をクリア
    $parameter->{code_body} = undef;    

    for my $host_info (keys( %$host_variable )) {
        #
        # ホスト変数情報をホスト変数名と行数に分割
        #
        my @host_variable = split(':',$host_info);
        my $one_matching = create_matching_from_id($parameter->{pattern_dic_ref}, "VAR-001-001", $host_variable[0]);
        
        create_result($parameter, $one_matching, $result, $host_variable[1]);

    }

}

#####################################################################
# Function: extract_string
#
# 概要:
# パターン抽出モジュールのひとつである。
# 式解析結果(コード)のパターン抽出対象文字列と行番号を、新規に生成した報告結果
# (文字列)に格納後、返却する。
#
# パラメータ:
# parameter  - パラメータ情報。以下の情報を格納するハッシュである
# - module_list_ref - モジュールリスト
# - func_dic_ref    - 式解析結果(ファイル)
# - pattern_dic_ref - パターン辞書
# - result_ref      - 報告結果配列(出力用)
# - classname      - 解析クラス名(出力用)
# - code_body       - 1コード
# - line_number     - 1コードの行番号
# - methodname      - 解析メソッド名(出力用)
# - details      - 文字列位置情報(出力用)
# - variablename      - 解析変数名(出力用)
#
# 戻り値:
# 報告結果(文字列)
#
# 例外:
# なし
#
# 特記事項:
# なし
#
#####################################################################
sub extract_string {
    my ($parameter) = @_;
    
    my $string_result = ExtractResultsString->new();
    
    $string_result->string($parameter->{code_body});
    $string_result->linenumber($parameter->{line_number});
    
    return $string_result;
}


#####################################################################
# Function: extract_sql_at_string
#
# 概要:
# パターン抽出モジュールのひとつである。
# - 式解析結果(コード)のパターン抽出対象文字列と行番号を入力としてモジュールリスト
#   に登録されているモジュールを実行する。
# - 実行結果を新規に生成した報告結果（パターン）に格納する。
#
# パラメータ:
# parameter  - パラメータ情報。以下の情報を格納するハッシュである
# - module_list_ref - モジュールリスト
# - func_dic_ref    - 式解析結果(ファイル)
# - pattern_dic_ref - パターン辞書
# - result_ref      - 報告結果配列(出力用)
# - classname      - 解析クラス名(出力用)
# - code_body       - 1コード
# - line_number     - 1コードの行番号
# - methodname      - 解析メソッド名(出力用)
# - details      - 文字列位置情報(出力用)
# - variablename      - 解析変数名(出力用)
#
# 戻り値:
# resultlist - 報告結果(パターン)のリストのリファレンス
#
# 例外:
# なし
#
# 特記事項:
# なし
#
#####################################################################
sub extract_sql_at_string {
    my ($parameter, $mode) = @_;
    my $module_list = undef;

    if($mode eq PATTERN_TYPE_SQL ) {
        $module_list = $parameter->{module_list_ref}->{module};
    }else{
        $module_list = $parameter->{module_list_ref}->{execsql_module};
    }
    
    my @resultlist = ();

    for my $module_ref (@{ $module_list }) {
        my $matching_info = $module_ref->($parameter);
        
        if($matching_info) {
            #
            #複数報告分ループして報告結果を作成
            #
            foreach my $matching (@{ $matching_info }) {
                my $pattern_result = ExtractResultsPattern->new();
                my ($linenumber, $one_matching) = each %{$matching};
                
                #
                #位置判定用変数の初期化
                #
                my $pos_buff = 0;
                my $last_pos_buff = 0;
                my %line_pos_buff=();
                #
                #文字列位置情報でループ
                #
                foreach my $detail ( @{ $parameter->{details} } ){
                    #
                    #累積文字数の退避
                    #
                    $last_pos_buff = $pos_buff;
                    #
                    #累積文字数の加算
                    #
                    $pos_buff += $detail->length;
                    #
                    #解析済みブロック登録のキー構築
                    #
                    my $line_key_buff=$detail->code_count."_".$detail->block_count;
                    #
                    #報告対象ブロックか判定
                    #
                    if( $pos_buff > $one_matching->{pattern_pos}[0]){
                        my $line_length=0;
                        $pattern_result->linenumber($detail->line);
                        #
                        #報告行と同じ解析済みブロックが存在するか確認
                        #
                        if(exists $line_pos_buff{$detail->line}){
                            #
                            #解析済みブロックのキーでループ
                            #
                            foreach my $line_key (keys( %{ $line_pos_buff{$detail->line}  } )){
                                #
                                #解析済みブロックで
                                #報告対象ブロック以外の同一行すべでのブロックの文字数を合計する
                                #
                                if($line_key ne $line_key_buff){
                                    $line_length += $line_pos_buff{$detail->line}->{$line_key};
                                }
                            }
                        }
                        $pattern_result->pattern_pos( $one_matching->{pattern_pos}[0] - $last_pos_buff + $line_length );
                        last;
                    }
                    #
                    #解析ブロックの文字数を登録
                    #同一ブロック登録済みの場合は上書き
                    #
                    $line_pos_buff{$detail->line}->{$line_key_buff} = $detail->length;
                }

                $pattern_result->message_id($one_matching->{message_id});
                $pattern_result->pattern_type($one_matching->{pattern_type});
                $pattern_result->level($one_matching->{report_level});
                $pattern_result->struct($one_matching->{pattern_body});
                $pattern_result->target($parameter->{code_body});
                $pattern_result->message($one_matching->{message_body});
                
                #
                #クラス名、メソッド名、変数名を報告結果に格納する。
                #
                $pattern_result->variablename($parameter->{variablename});
                $pattern_result->methodname($parameter->{methodname});
                $pattern_result->classname($parameter->{classname});
                
                #
                #TARGETDBMSノードが存在する場合は
                #報告結果へ格納
                #
                if(defined $one_matching->{targetdbms}){
                	$pattern_result->targetdbms($one_matching->{targetdbms});
                }

                push(@resultlist, $pattern_result);
            }
        }
    }
    
    return \@resultlist;
}

#####################################################################
# Function: execute_plan
#
#
# 概要:
# 関数辞書に格納されているすべての1関数辞書について、モジュールリスト
# に格納されている処理を順番に実行する。
#
# 実行する。
#
# パラメータ:
# parameter - パラメータ情報。以下の情報を格納するハッシュである
# module_list_ref - モジュールリスト
# func_dic_ref    - 関数辞書
# pattern_dic_ref - パターン辞書
# result_ref      - 報告結果配列(出力用)
#
# 戻り値:
# なし
#
# 例外:
# なし
#
# 特記事項:
#
#####################################################################

sub execute_plan {
    my ($parameter) = @_;

    my $module_list_ref = $parameter->{module_list_ref};
    my $filelist = $parameter->{func_dic_ref};
    my $result_ref = $parameter->{result_ref};

    #
    # ファイル単位で処理を繰り返す
    #
    for my $fileinfo (@{$filelist}) {

        my $extract_results = ExtractResultsFile->new();
        my $filename = $fileinfo->{filename};
        my $func_dic_ref = $fileinfo->{func_dic_ref};
        my $function_number = scalar keys %{ $func_dic_ref}; # 解析対象関数の数
        my $finished_number = 0;                             # 解析完了した関数の数

        $extract_results->filename($filename);
        $function_number-- if(exists $func_dic_ref->{'%literal_stack'});
        $parameter->{func_dic_ref} = $func_dic_ref;
        get_loglevel() > 0 and print_log("(INFO) | $function_number target functions at $filename.");

        #
        # すべての関数情報について処理を繰り返す
        #
        for my $funcname (keys %{ $func_dic_ref }) {

            next if $funcname eq '%literal_stack';
            my @matching_pattern = ();    # パターン抽出の結果

            #
            # 入力パラメータの追加：
            # - 処理対象となる関数名
            #
            $parameter->{funcname} = $funcname;

            #
            # すべてのコード情報について、モジュールリストに格納されている処理を
            # 順番に実行する
            #
            my $matching_pattern_ref = execute_plan_by_function($parameter);
            if($matching_pattern_ref) {
                push(@matching_pattern, @{ $matching_pattern_ref });
                undef @{ $matching_pattern_ref }; 
            }

            #
            # 関数ごとの報告結果配列に報告内容を格納する
            #
            for my $pattern_info (@matching_pattern) {
                my ($line_number, $matching_info) = each %{ $pattern_info };
                create_result($parameter, $matching_info, $extract_results, $line_number);
            }
            undef @matching_pattern;

            $finished_number++;
            if(get_loglevel() > 0 and $finished_number % int($function_number / 10 + 1) == 0) {
                print_log("(INFO) | $finished_number / $function_number finished.");
            }
        }
        push(@{$result_ref}, $extract_results);
        get_loglevel() > 0 and print_log("(INFO) | all functions $finished_number / $function_number finished.");
    }
    return;
}

#####################################################################
# Function: execute_plan_by_function
#
#
# 概要:
# 1関数辞書に格納されているすべてのコード情報について、モジュールリスト
# に格納されている処理を順番に実行する。
#
# パラメータ:
# parameter - パラメータ情報。以下の情報を格納するハッシュである
# - module_list_ref - モジュールリスト
# - func_dic_ref    - 関数辞書
# - pattern_dic_ref - パターン辞書
# - result_ref      - 報告結果配列(出力用)
# - funcname        - 関数名
#
# 戻り値:
# matching_pattern_ref - 1関数辞書における報告結果
#
# 例外:
# なし
#
# 特記事項:
#
#####################################################################

sub execute_plan_by_function {

    my ($parameter) = @_;
    
    my $module_list_ref = $parameter->{module_list_ref};
    my $func_dic_ref = $parameter->{func_dic_ref};
    my $funcname = $parameter->{funcname};

    my $one_func_dic_ref = $func_dic_ref->{$funcname};       # 1関数辞書
    my $code_info       = $one_func_dic_ref->{code_info};    # コード情報
    my $max_code_number = $#{$code_info};                    # コード情報数
    my @matching_pattern = ();                  # 1関数辞書における報告結果

        #
        # すべてのコード情報について、モジュールリストに格納されている処理を
        # 順番に実行する
        #
    get_loglevel() > 4 and print_log("(DEBUG 5) | function = $funcname.");
    for (my $current_line = 0;
            $current_line <= $max_code_number;
            $current_line++
        ) {

        my $code_body   = $code_info->[$current_line]->{code_body};
        my $line_number = $code_info->[$current_line]->{line_number};

        get_loglevel() > 4 and print_log("(DEBUG 5) | code = $line_number : $code_body");
        
        #
        # 入力パラメータの追加：
        # - コード
        # - コード情報を示す位置
        # - コードの行番号
        $parameter->{code_body} = $code_body;
        $parameter->{current_line} = $current_line;
        $parameter->{line_number} = $line_number;

        #
        # 通常実行するモジュールを実行する
        #
        for my $module_ref (@{ $module_list_ref->{module} }) {
            my $matching_info = $module_ref->($parameter);
            if($matching_info) {
                push(@matching_pattern, @{ $matching_info });
            }
        }

        # ターゲット情報に設定されてしまうため、最終行の情報をクリア
        $parameter->{code_body} = undef;

        #
        # EXEC SQL文を検出した場合に実行するモジュールを実行する
        # モジュール登録がない場合は、EXEC SQL文の検出は行わない
        #
        if($module_list_ref->{execsql_module}) {
            if (my $sql_string = extract_execsql($code_body)) {
                
                $parameter->{code_body} = $sql_string;

                #
                # モジュールリストよりモジュールを1つずつ取得し実行する
                #
                for my $module_ref ( @{ $module_list_ref->{execsql_module} }) {
                    my $matching_info = $module_ref->($parameter);

                    if($matching_info) {
                        push( @matching_pattern, @{ $matching_info });
                    }
                }
                # ターゲット情報に設定されてしまうため、最終行の情報をクリア
                $parameter->{code_body} = undef;
            }
        }
    }
    
    if(scalar @matching_pattern > 0) {
        return \@matching_pattern;
    }
    return;
    
}

#####################################################################
# Function: extract_execsql
#
#
# 概要:
# EXEC SQL文の検出を行う。
# コード内にEXEC SQL文が存在する場合は、EXEC SQL以降のSQL文字列を
# 返却する。ただし、ホスト変数宣言部(DECLARE SECTION)の場合は結果
# なしを返却する。
#
# パラメータ:
# code - コード
#
# 戻り値:
# sql_string - EXEC SQL文を検出した場合、EXEC SQL以降のSQL文字列
#
# 例外:
# なし
#
# 特記事項:
#
#####################################################################

sub extract_execsql {
    my ($code) = @_;
    my $sql_string = undef;    # EXEC SQL以降の文字列

    if ( $code =~ m{(?:\A | [^\w_]) EXEC\s+SQL\s+(.*)}xms ) {
        $sql_string = $1;

        if ( $sql_string =~ m{DECLARE\s+SECTION}xms ) {
            $sql_string = undef;
        }
    }

    return $sql_string;
}

#####################################################################
# Function: extract_sql_at_literal
#
#
# 概要:
# リテラル内SQLの抽出を実行する。
#
# パラメータ:
# parameter - パラメータ情報。以下の情報を格納するハッシュである
# - module_list_ref - モジュールリスト
# - func_dic_ref    - 関数辞書
# - pattern_dic_ref - パターン辞書
# - result_ref      - 報告結果配列(出力用)
# - funcname        - 関数名
# - code_body       - 1コード
# - line_number     - 1コードの行番号
#
# 戻り値:
# matching_info - 合致パターンの情報の配列
#
# 例外:
# なし
#
# 特記事項:
# 合致パターンの情報は以下の構造を持つ。なお、"パターンを検出した関数名"は、
# 報告内容に設定するファイル名が抽出開始時と異なる場合に設定される
#|<合致パターンの基本情報>
#|{
#|  message_id => "メッセージID",
#|  pattern_type => "抽出パターン種別",
#|  report_level => "報告レベル",
#|  pattern_body => "抽出パターン定義",
#|  message_body => "メッセージ内容"
#|  current_function => "パターンを検出した関数名"
#|}
#|
#|<合致パターンの情報>
#|{
#|  line_number(コードに対する行番号) => "<合致パターンの基本情報>"
#|}
#
#####################################################################

sub extract_sql_at_literal {
    my ($parameter) = @_;
    
    my $code = $parameter->{code_body};
    my @matching_pattern = ();
    
    while($code =~ m{(""\d+")}xmsg) {
        my $matching_info = extract_sql_at_literal_common($parameter, $1, TRUE);
        if($matching_info) {
            push( @matching_pattern, @{ $matching_info });
        }
    }
    
    if(scalar @matching_pattern > 0) {
        return \@matching_pattern;
    }
    return;
}


#####################################################################
# Function: extract_sql_at_literal_common
#
#
# 概要:
# リテラル内SQLの抽出を実行する。
#
# パラメータ:
# parameter - パラメータ情報。以下の情報を格納するハッシュである
# - module_list_ref - モジュールリスト
# - func_dic_ref    - 関数辞書
# - pattern_dic_ref - パターン辞書
# - result_ref      - 報告結果配列(出力用)
# - funcname        - 関数名
# - code_body       - 1コード
# - line_number     - 1コードの行番号
# code      - パターン抽出の対象となるSQL
# is_prepattern_matching - プレパターンによるパターン抽出の実施有無
#
# 戻り値:
# matching_info - 合致パターンの情報の配列
#
# 例外:
# なし
#
# 特記事項:
# 合致パターンの情報は以下の構造を持つ。なお、"パターンを検出した関数名"は、
# 報告内容に設定するファイル名が抽出開始時と異なる場合に設定される
#|<合致パターンの基本情報>
#|{
#|  message_id => "メッセージID",
#|  pattern_type => "抽出パターン種別",
#|  report_level => "報告レベル",
#|  pattern_body => "抽出パターン定義",
#|  message_body => "メッセージ内容"
#|  current_function => "パターンを検出した関数名"
#|}
#|
#|<合致パターンの情報>
#|{
#|  line_number(コードに対する行番号) => "<合致パターンの基本情報>"
#|}
#
#####################################################################

sub extract_sql_at_literal_common {
    my ($parameter, $code, $is_prepattern_matching) = @_;

    get_loglevel() > 2 and print_log("(DEBUG 3) | [in] extract_sql_at_literal_common");
    
    my $pattern_dic_ref = $parameter->{pattern_dic_ref};
    my $func_dic_ref = $parameter->{func_dic_ref};
    my $funcname = $parameter->{funcname};

    my $target = decode_literal($parameter, $code);
                                        # リテラル値のデコード
    #
    # リテラル内よりSQL構文が抽出可能かプレパターンを使用して
    # 判定する
    #
    my @matching_info = ();             # 合致パターンの情報の集合
    my $matching = undef;               # 合致パターンの情報


    #
    # プレパターンによるパターン抽出を実施する条件において
    # プレパターンに合致しない場合は何もしないで終了する
    # それ以外の条件の場合は以降の処理にてパターン抽出を行う
    #
    get_loglevel() > 6 and print_log("(DEBUG 5) | prepattern target ->" . $target);
    my $prepattern = $pattern_dic_ref->{prepattern};
    if($is_prepattern_matching and $prepattern ne '') {
        if($target !~ m{ ($prepattern) }xmsio) {
            get_loglevel() > 6 and print_log("(DEBUG 5) | ignores ->" . $target);
            return;
        }
    }

    $matching =
          extract_pattern_at_type($target, $pattern_dic_ref, PATTERN_TYPE_SQL);
    foreach my $one_matching (@{ $matching }) {
        push(@matching_info, {$parameter->{line_number} => $one_matching});
    }


    $matching =
      extract_pattern_at_type($target, $pattern_dic_ref, PATTERN_TYPE_FUNC);
    foreach my $one_matching (@{ $matching }) {
        push(@matching_info, {$parameter->{line_number} => $one_matching});
    }

    get_loglevel() > 2 and print_log("(DEBUG 3) | [out] extract_sql_at_literal_common");
    
    if(scalar @matching_info > 0) {
        return \@matching_info;
    }
    return; 
}




#####################################################################
# Function: extract_embedded_sql
#
#
# 概要:
# 埋め込みSQL構文の抽出を実行する。
#
# パラメータ:
# parameter - パラメータ情報。以下の情報を格納するハッシュである
# - module_list_ref - モジュールリスト
# - func_dic_ref    - 関数辞書
# - pattern_dic_ref - パターン辞書
# - result_ref      - 報告結果配列(出力用)
# - funcname        - 関数名
# - code_body       - 1コード
# - line_number     - 1コードの行番号
#
# 戻り値:
# matching_info - 合致パターンの情報の集合
#
# 例外:
# なし
#
# 特記事項:
# 合致パターンの情報は以下の構造を持つ。なお、"パターンを検出した関数名"は、
# 報告内容に設定するファイル名が抽出開始時と異なる場合に設定される
#|<合致パターンの基本情報>
#|{
#|  message_id => "メッセージID",
#|  pattern_type => "抽出パターン種別",
#|  report_level => "報告レベル",
#|  pattern_body => "抽出パターン定義",
#|  message_body => "メッセージ内容"
#|  current_function => "パターンを検出した関数名"
#|}
#|
#|<合致パターンの情報>
#|{
#|  line_number(コードに対する行番号) => "<合致パターンの基本情報>"
#|}
#
#####################################################################

sub extract_embedded_sql {
    my ($parameter) = @_;
    
    my $code = $parameter->{code_body};
    my $pattern_dic_ref = $parameter->{pattern_dic_ref};

    get_loglevel() > 2 and print_log("(DEBUG 3) | [in] extract_embedded_sql");

    my @matching_info = ();             # 合致パターンの情報の集合
    my $matching = undef;               # 合致パターンの情報

    #
    # 埋め込みSQL構文について抽出を行う
    #
    $matching =
      extract_pattern_at_type($code, $pattern_dic_ref, PATTERN_TYPE_EMBSQL);
    foreach my $one_matching (@{ $matching }) {
        push(@matching_info, {$parameter->{line_number} => $one_matching});
    }

    get_loglevel() > 2 and print_log("(DEBUG 3) | [out] extract_embedded_sql");

    if(scalar @matching_info > 0) {
        return \@matching_info;
    }
    return; 
}

#####################################################################
# Function: extract_sql
#
#
# 概要:
# SQL構文の抽出を実行する。
#
# パラメータ:
# parameter - パラメータ情報。以下の情報を格納するハッシュである
# - module_list_ref - モジュールリスト
# - func_dic_ref    - 関数辞書
# - pattern_dic_ref - パターン辞書
# - result_ref      - 報告結果配列(出力用)
# - funcname        - 関数名
# - classname      - 解析クラス名(出力用)
# - code_body       - 1コード
# - line_number     - 1コードの行番号
# - methodname      - 解析メソッド名(出力用)
# - details      - 文字列位置情報(出力用)
# - variablename      - 解析変数名(出力用)
#
# 戻り値:
# matching_info - 合致パターンの情報
#
# 例外:
# なし
#
# 特記事項:
# 合致パターンの情報は以下の構造を持つ。なお、"パターンを検出した関数名"は、
# 報告内容に設定するファイル名が抽出開始時と異なる場合に設定される
#|<合致パターンの基本情報>
#|{
#|  message_id => "メッセージID",
#|  pattern_type => "抽出パターン種別",
#|  report_level => "報告レベル",
#|  pattern_body => "抽出パターン定義",
#|  message_body => "メッセージ内容"
#|  current_function => "パターンを検出した関数名"
#|}
#|
#|<合致パターンの情報>
#|{
#|  line_number(コードに対する行番号) => "<合致パターンの基本情報>"
#|}
#
#####################################################################

sub extract_sql {
    my ($parameter) = @_;
    
    get_loglevel() > 2 and print_log("(DEBUG 3) | [in] extract_sql");

    my $code = $parameter->{code_body};
    my $pattern_dic_ref = $parameter->{pattern_dic_ref};
    #
    #複数報告格納リストの初期化
    #
    my @matching_info = ();
    my $details = $parameter->{details};

    my $matching =
      extract_pattern_at_type($code, $pattern_dic_ref, PATTERN_TYPE_SQL, $details );
    foreach my $one_matching (@{ $matching }) {
        push(@matching_info, {$parameter->{line_number} => $one_matching});
    }

    get_loglevel() > 2 and print_log("(DEBUG 3) | [out] extract_sql");

    if(scalar @matching_info > 0) {
        return \@matching_info;
    }
    return;
}

#####################################################################
# Function: extract_function
#
#
# 概要:
# SQL関数の抽出を実行する。
#
# パラメータ:
# parameter - パラメータ情報。以下の情報を格納するハッシュである
# - module_list_ref - モジュールリスト
# - func_dic_ref    - 関数辞書
# - pattern_dic_ref - パターン辞書
# - result_ref      - 報告結果配列(出力用)
# - funcname        - 関数名
# - classname      - 解析クラス名(出力用)
# - code_body       - 1コード
# - line_number     - 1コードの行番号
# - methodname      - 解析メソッド名(出力用)
# - details      - 文字列位置情報(出力用)
# - variablename      - 解析変数名(出力用)
#
# 戻り値:
# pattern_ref - 合致パターンの情報
#
# 例外:
# なし
#
# 特記事項:
# 合致パターンの情報は以下の構造を持つ。なお、"パターンを検出した関数名"は、
# 報告内容に設定するファイル名が抽出開始時と異なる場合に設定される
#|<合致パターンの基本情報>
#|{
#|  message_id => "メッセージID",
#|  pattern_type => "抽出パターン種別",
#|  report_level => "報告レベル",
#|  pattern_body => "抽出パターン定義",
#|  message_body => "メッセージ内容"
#|  current_function => "パターンを検出した関数名"
#|}
#|
#|<合致パターンの情報>
#|{
#|  line_number(コードに対する行番号) => "<合致パターンの基本情報>"
#|}
#
#####################################################################

sub extract_function {
    my ($parameter) = @_;

    get_loglevel() > 2 and print_log("(DEBUG 3) | [in] extract_function");
    
    my $code = $parameter->{code_body};
    my $pattern_dic_ref = $parameter->{pattern_dic_ref};
    #
    #複数報告格納リストの初期化
    #
    my @matching_info = ();
    my $details = $parameter->{details};

    my $matching =
      extract_pattern_at_type($code, $pattern_dic_ref, PATTERN_TYPE_FUNC, $details );
    foreach my $one_matching (@{ $matching }) {
        push(@matching_info, {$parameter->{line_number} => $one_matching});
    }

    get_loglevel() > 2 and print_log("(DEBUG 3) | [out] extract_function");

    if(scalar @matching_info > 0) {
        return \@matching_info;
    }
    return;
}

#####################################################################
# Function: extract_type
#
#
# 概要:
# SQL定義における型の抽出を実行する。
#
# パラメータ:
# parameter - パラメータ情報。以下の情報を格納するハッシュである
# - module_list_ref - モジュールリスト
# - func_dic_ref    - 関数辞書
# - pattern_dic_ref - パターン辞書
# - result_ref      - 報告結果配列(出力用)
# - funcname        - 関数名
# - code_body       - 1コード
# - line_number     - 1コードの行番号
#
# 戻り値:
# pattern_ref - 合致パターンの情報
#
# 例外:
# なし
#
# 特記事項:
# 合致パターンの情報は以下の構造を持つ。なお、"パターンを検出した関数名"は、
# 報告内容に設定するファイル名が抽出開始時と異なる場合に設定される
#|<合致パターンの基本情報>
#|{
#|  message_id => "メッセージID",
#|  pattern_type => "抽出パターン種別",
#|  report_level => "報告レベル",
#|  pattern_body => "抽出パターン定義",
#|  message_body => "メッセージ内容"
#|  current_function => "パターンを検出した関数名"
#|}
#|
#|<合致パターンの情報>
#|{
#|  line_number(コードに対する行番号) => "<合致パターンの基本情報>"
#|}
#
#####################################################################

sub extract_type {
    my ($parameter) = @_;

    get_loglevel() > 2 and print_log("(DEBUG 3) | [in] extract_type");
    
    my $code = $parameter->{code_body};
    my $pattern_dic_ref = $parameter->{pattern_dic_ref};
    my @matching_info = ();

    my $matching =
      extract_pattern_at_type($code, $pattern_dic_ref, PATTERN_TYPE_TYPE);
    foreach my $one_matching (@{ $matching }) {
        push(@matching_info, {$parameter->{line_number} => $one_matching});
    }

    get_loglevel() > 2 and print_log("(DEBUG 3) | [out] extract_type");

    if(scalar @matching_info > 0) {
        return \@matching_info;
    }
    return;
}

#####################################################################
# Function: extract_pattern_at_type
#
#
# 概要:
# 指定された抽出パターン種別についてのパターン抽出を実行する。
#
# パラメータ:
# code            - コード
# pattern_dic_ref - パターン辞書
# pattern_type    - 抽出パターン種別
# details         - 連結文字列情報
#
# 戻り値:
# matching_info - 合致パターンの情報
#
# 例外:
# なし
#
# 特記事項:
# 合致パターンの情報は以下の構造を持つ。なお、"パターンを検出した関数名"は、
# 報告内容に設定するファイル名が抽出開始時と異なる場合に設定される
#|<合致パターンの基本情報>
#|{
#|  message_id => "メッセージID",
#|  pattern_type => "抽出パターン種別",
#|  report_level => "報告レベル",
#|  pattern_body => "抽出パターン定義",
#|  message_body => "メッセージ内容"
#|  current_function => "パターンを検出した関数名"
#|}
#|
#|<合致パターンの情報>
#|{
#|  line_number(コードに対する行番号) => "<合致パターンの基本情報>"
#|}
#
#####################################################################

sub extract_pattern_at_type {
    my ($code, $pattern_dic_ref, $pattern_type, $details) = @_;
    
    my $typepattern_dic_ref = $pattern_dic_ref->{type}->{$pattern_type};
                                        # 抽出パターン種別ごとの1パターン辞書
    my $matching_pattern = undef;       # 合致パターンの1パターン辞書
    my $matching = undef;               # 合致パターンの情報
    my @matching_list = ();             # 合致パターンの情報（返却用）
    
    for my $one_matching_info (@{ $typepattern_dic_ref }) {
        $matching =
            extract_one_pattern($code, $one_matching_info, $pattern_type, $pattern_dic_ref, $details );
        push(@matching_list, @{ $matching });       
    }
    
    return \@matching_list;
}

#####################################################################
# Function: extract_one_pattern
#
#
# 概要:
# 指定された1抽出パターンについてのパターン抽出を実行する。
# 抽出パターンに委譲が存在する場合は、パターン抽出の委譲を行う。
#
# パラメータ:
# code            - コード
# one_pattern_ref - 1パターン辞書
# pattern_type    - 抽出パターン種別
# pattern_dic_ref - パターン辞書
# details         - 連結文字列情報
# 
# 戻り値:
# matching_info - 合致パターンの基本情報
#
# 例外:
# なし
#
# 特記事項:
# 合致パターンの情報は以下の構造を持つ。なお、"パターンを検出した関数名"は、
# 報告内容に設定するファイル名が抽出開始時と異なる場合に設定される
#|<合致パターンの基本情報>
#|{
#|  message_id => "メッセージID",
#|  pattern_type => "抽出パターン種別",
#|  report_level => "報告レベル",
#|  pattern_body => "抽出パターン定義",
#|  message_body => "メッセージ内容"
#|  current_function => "パターンを検出した関数名"
#|}
#|
#|<合致パターンの情報>
#|{
#|  line_number(コードに対する行番号) => "<合致パターンの基本情報>"
#|}
#
#####################################################################

sub extract_one_pattern {
    my ($code, $one_pattern_ref, $pattern_type, $pattern_dic_ref, $details) = @_;
    
    my @matching_list = ();             # 合致パターンの情報（返却用）
    my @maches_list = ();               # パターン抽出結果
    my @same_maches_list = ();          # 同一パターン抽出結果

    #
    # 1パターン辞書に格納されている抽出パターンで抽出を行う
    # !付き抽出パターンか判定し、パターンマッチングを場合分けする
    #
    my $evaluater = $one_pattern_ref->{pattern_body}->{pattern_evaluater};
    if(!defined $evaluater) {
        get_loglevel() > 4 and print_log("(DEBUG 5) | [extract_one_pattern] detect devoided pattern in normal pattern matching!");
        return;
    }
    $_ = $code;
    @maches_list = $evaluater->();

    #
    # パターン抽出に成功した場合、サブ抽出パターンの存在を確認する
    # サブ抽出パターンが存在する場合はさらにパターン抽出を続行する
    #
    if(@maches_list > 1 or (defined $maches_list[0] and $maches_list[0] ne '')) {

        get_loglevel() > 4 and print_log("(DEBUG 5) | [extract_one_pattern] matching at -> $one_pattern_ref->{pattern_body}->{pattern_body}");
        get_loglevel() > 4 and print_log("(DEBUG 5) | [extract_one_pattern] subpattern  -> " . join(",", @maches_list));

        if($one_pattern_ref->{subpattern_body}) {
            # サブ抽出パターンによるパターン抽出を行う
        
            for my $subpatterndef_ref (@{ $one_pattern_ref->{subpattern_body} }) {
                my $subpattern_pos = scalar $subpatterndef_ref->{subpattern_pos};
                
                #
                # 「$+数値」で与えられたサブパターンの抽出位置を配列の添え字に変換
                # する
                # $1..$nの抽出結果は、@maches_listに格納されている
                #
                $subpattern_pos =~ s{\$ (\d+)}{$1}xmsg;
                $subpattern_pos--;
                my $subcode;
                if($subpattern_pos < 0) {
                    $subcode = $code;
                }
                else {
                    $subcode = $maches_list[$subpattern_pos];
                }
                if(!defined $subcode) {
                    $subcode = '';
                }
                my $subpattern_string = $subpatterndef_ref->{pattern_body};
                
                #
                # サブ抽出パターンにパターン抽出の委譲が存在する場合は
                # 委譲し、その結果が存在する場合は、委譲の結果を本パターン
                # 抽出の結果とする
                # 委譲の結果が存在しない場合は、パターン抽出を続行する
                #
                if(my $pattern_id = get_devolve_pattern_id($subpattern_string)) {
                    my $devolved_pattern_ref = $pattern_dic_ref->
                                                {pattern}->{$pattern_id};
                    #
                    # 委譲パターンの抽出
                    #
                    my $devolved_matching_list = extract_one_pattern($subcode,
                        $devolved_pattern_ref, $pattern_type, $pattern_dic_ref);
                    #
                    # 委譲パターンの抽出位置から全体での抽出位置に修正
                    #
                    foreach my $result_pos (@{ $devolved_matching_list }){
                        $result_pos->{pattern_pos}[0]+=$one_pattern_ref->{pattern_body}->{pattern_pos}[$subpattern_pos + 1];
                    }                    #
                    # 委譲結果の格納
                    #
                    push(@matching_list, @{ $devolved_matching_list });
                }
                #
                # サブ抽出パターンによるパターン抽出が行われた場合は
                # パターン抽出を終了する
                # create_matching関数への入力形式にあわせるため、
                # sub_one_pattern_refを作成する
                # 
                else {
                    $evaluater = $subpatterndef_ref->{pattern_evaluater};
                    my $sub_one_pattern_ref = {
                        pattern_name => $subpatterndef_ref->{pattern_name},
                        pattern_type => $one_pattern_ref->{pattern_type},
                        pattern_body => $subpatterndef_ref,
                    };

                    $_ = $subcode;
                    if($evaluater->()) {
                        #
                        #空白文字数のカウント
                        #
                        my $sub_blank_number = get_blank_number($subcode, $sub_one_pattern_ref);
                        #
                        #否定パターンか判定
                        #否定パターンでない場合は、
                        #サブパターン抽出開始位置を全体文字列に修正
                        #(サブパターン抽出開始位置＋サブ文字列中のサブパターン抽出開始位置＋空白文字数)
                        #サブパターン抽出終端位置を全体文字列に修正
                        #(サブパターン抽出開始位置＋サブ文字列中のサブパターン抽出終端位置)
                        #否定パターンの場合は、サブパターン抽出開始位置にパターン抽出の終端位置を格納
                        #
                        if($sub_one_pattern_ref->{pattern_body}->{next_pos}){
                            $sub_one_pattern_ref->{pattern_body}->{pattern_pos}[0] += $one_pattern_ref->{pattern_body}->{pattern_pos}[$subpattern_pos + 1]+$sub_blank_number;
                            $sub_one_pattern_ref->{pattern_body}->{next_pos}[0] += $one_pattern_ref->{pattern_body}->{pattern_pos}[$subpattern_pos + 1];
                        }else{
                            $sub_one_pattern_ref->{pattern_body}->{pattern_pos}[0] = $one_pattern_ref->{pattern_body}->{pattern_pos}[$subpattern_pos + 1];
                        }

                        #
                        # プラグインが指定されているか判定
                        #
                        if($sub_one_pattern_ref->{pattern_body}->{library} and $sub_one_pattern_ref->{pattern_body}->{procedure} ){
                            #
                            #プラグインのライブラリ読み込み
                            #
                            require $sub_one_pattern_ref->{pattern_body}->{library};
                            
                            #
                            #プラグインの呼び出し
                            #
                            
                            #結果格納用リストの初期化
                            my @plugin_maches_list=();
                            
                            #プラグイン引数用のハッシュを構築
                            my $plugin_ref = {
                                    code => substr($code, $sub_one_pattern_ref->{pattern_body}->{pattern_pos}[0]),
                                    pattern_name => $sub_one_pattern_ref->{pattern_body}->{pattern_name},
                                    pattern_type => $sub_one_pattern_ref->{pattern_type},
                                    pattern_pos => $sub_one_pattern_ref->{pattern_body}->{pattern_pos},
                            };
                            
                            #プロシージャの呼び出し
                            my $procedure_buff = '@plugin_maches_list = ' . $sub_one_pattern_ref->{pattern_body}->{procedure} . '($plugin_ref);';
                            eval $procedure_buff;
            
                            #
                            # プロシージャの呼び出し中に例外が発生した場合は、エラーメッセージを出力する
                            #
                            if($@) {
                                print_log($@);
                            }
                            
                            #報告結果の有無を判定し格納
                            if(@plugin_maches_list){
                                push(@matching_list, @plugin_maches_list);
                            }
                        }else{

                            push(@matching_list,
                        	    create_matching($pattern_dic_ref, $sub_one_pattern_ref));
                        }
                        
                        #
                        # next_pos以降の文字列で同一パターンがないか再検索する
                        #
                        @same_maches_list = extract_same_pattern($code, $sub_one_pattern_ref, $pattern_dic_ref);
                        if(@same_maches_list){
                            push(@matching_list, @same_maches_list);
                        }
                    }
                }
            }
        }
        #
        # サブ抽出パターンが存在しない場合は、パターン抽出を終了する
        #
        else {
            #
            #空白文字数のカウント
            #
            my $blank_number = get_blank_number($code, $one_pattern_ref);
            $one_pattern_ref->{pattern_body}->{pattern_pos}[0] += $blank_number;

            #
            # プラグインが指定されているか判定
            #
            if($one_pattern_ref->{pattern_body}->{library} and $one_pattern_ref->{pattern_body}->{procedure} ){
                #
                #プラグインのライブラリ読み込み
                #
                require $one_pattern_ref->{pattern_body}->{library};
                
                #
                #プラグインの呼び出し
                #
                
                #結果格納用リストの初期化
                my @plugin_maches_list=();
                
                #プラグイン引数用のハッシュを構築
                my $plugin_ref = {
                        code => substr($code, $one_pattern_ref->{pattern_body}->{pattern_pos}[0]),
                        pattern_name => $one_pattern_ref->{pattern_body}->{pattern_name},
                        pattern_type => $one_pattern_ref->{pattern_type},
                        pattern_pos => $one_pattern_ref->{pattern_body}->{pattern_pos},
                };
                
                #プロシージャの呼び出し
                my $procedure_buff = '@plugin_maches_list = ' . $one_pattern_ref->{pattern_body}->{procedure} . '($plugin_ref);';
                eval $procedure_buff;

                #
                # プロシージャの呼び出し中に例外が発生した場合は、エラーメッセージを出力する
                #
                if($@) {
                    print_log($@);
                }
                
                #報告結果の有無を判定し格納
                if(@plugin_maches_list){
                    push(@matching_list, @plugin_maches_list);
                }
            }else{
                push(@matching_list, create_matching($pattern_dic_ref, $one_pattern_ref));
            }

            #
            # next_pos以降の文字列で同一パターンがないか再検索する
            #
            @same_maches_list = extract_same_pattern($code, $one_pattern_ref, $pattern_dic_ref);
            if(@same_maches_list){
                push(@matching_list, @same_maches_list);
            }
        }
    }
    
    return \@matching_list;
}

#####################################################################
# Function: extract_same_pattern
#
#
# 概要:
# 指定された1抽出パターンについての同一パターン抽出を実行する。
# パターン抽出時は抽出文字列以降に同一パターンがないかパターンマッチを行なう。
#
# パラメータ:
# code            - コード
# one_pattern_ref - 1パターン辞書
# pattern_dic_ref - パターン辞書
# 
# 戻り値:
# matching_list - 合致パターンの基本情報のリスト
#
# 例外:
# なし
#
# 特記事項:
# 合致パターンの情報は以下の構造を持つ。なお、"パターンを検出した関数名"は、
# 報告内容に設定するファイル名が抽出開始時と異なる場合に設定される
#|<合致パターンの基本情報>
#|{
#|  message_id => "メッセージID",
#|  pattern_type => "抽出パターン種別",
#|  report_level => "報告レベル",
#|  pattern_body => "抽出パターン定義",
#|  message_body => "メッセージ内容"
#|  current_function => "パターンを検出した関数名"
#|}
#|
#|<合致パターンの情報>
#|{
#|  line_number(コードに対する行番号) => "<合致パターンの基本情報>"
#|}
#
#####################################################################

sub extract_same_pattern {
    my ($code, $one_pattern_ref, $pattern_dic_ref) = @_;
    my @matching_list = ();             # 合致パターンの情報（返却用）
    my @same_maches_list = ();          # 同一パターン抽出結果
    my @maches_list = ();               # パターン抽出結果
    my $next_pos=undef;                 # 抽出対象文字列の切り出し位置
    
    #
    # 1パターン辞書に格納されている抽出パターンで指定の位置移行の文字列に対して抽出を行う
    #
    my $evaluater = $one_pattern_ref->{pattern_body}->{pattern_evaluater};

    #
    #否定パターンか判定
    #否定パターンの場合は、同一パターンは存在しないので終了
    #
    if($one_pattern_ref->{pattern_body}->{next_pos}){
        $next_pos = $one_pattern_ref->{pattern_body}->{next_pos}[0];
    }else{
        return;
    }

    $_ = substr($code, $next_pos);

    #
    # 指定位置以降に文字列が無い場合は終了
    #
    if($_ eq ''){
        return;
    }

    @maches_list = $evaluater->();

    #
    # パターン抽出に成功した場合、さらにパターン抽出を続行する
    #
    if(@maches_list > 1 or (defined $maches_list[0] and $maches_list[0] ne '')) {
        get_loglevel() > 4 and print_log("(DEBUG 5) | [extract_one_pattern] matching at -> $one_pattern_ref->{pattern_body}->{pattern_body}");
        $one_pattern_ref->{pattern_body}->{pattern_pos}[0] += $next_pos;
        $one_pattern_ref->{pattern_body}->{next_pos}[0] += $next_pos;

        #
        #空白文字数のカウント
        #
        my $blank_number = get_blank_number($code, $one_pattern_ref);
        $one_pattern_ref->{pattern_body}->{pattern_pos}[0] += $blank_number;

        #
        # プラグインが指定されているか判定
        #
        if($one_pattern_ref->{pattern_body}->{library} and $one_pattern_ref->{pattern_body}->{procedure} ){
            #
            #プラグインの呼び出し
            #
            
            #結果格納用リストの初期化
            my @plugin_maches_list=();
            
            #プラグイン引数用のハッシュを構築
            my $plugin_ref = {
                    code => substr($code, $one_pattern_ref->{pattern_body}->{pattern_pos}[0]),
                    pattern_name => $one_pattern_ref->{pattern_body}->{pattern_name},
                    pattern_type => $one_pattern_ref->{pattern_type},
                    pattern_pos => $one_pattern_ref->{pattern_body}->{pattern_pos},
            };
            
            #プロシージャの呼び出し
            my $procedure_buff = '@plugin_maches_list = ' . $one_pattern_ref->{pattern_body}->{procedure} . '($plugin_ref);';
            eval $procedure_buff;
            
            #報告結果の有無を判定し格納
            if(@plugin_maches_list){
                push(@matching_list, @plugin_maches_list);
            }
        }else{
            push(@matching_list, create_matching($pattern_dic_ref, $one_pattern_ref));
        }

        #
        # next_pos以降の文字列で同一パターンがないか再検索する
        #
        @same_maches_list = extract_same_pattern($code, $one_pattern_ref, $pattern_dic_ref);
        if(@same_maches_list){
            push(@matching_list, @same_maches_list);
        }
        return @matching_list;
    }
    return;
}

#####################################################################
# Function: get_devolve_pattern_id
#
#
# 概要:
# 指定された抽出パターンがパターン抽出の委譲を示す形式（抽出パターンID)か判定し、
# 委譲を示す形式の場合は、その抽出パターンIDを返却する。
#
# パラメータ:
# pattern_string - 抽出パターン
# 
# 戻り値:
# pattern_id - 移譲先となる抽出パターンID
#
# 例外:
# なし
#
#####################################################################

sub get_devolve_pattern_id {
    my ($pattern_string) = @_;
    my $pattern_id = undef;         # 移譲先となる抽出パターンID
    
    if($pattern_string =~ m{([A-Z]+-\d\d\d(?:-\d\d\d)?)}xms) {
        $pattern_id = $1;
    }
    
    return $pattern_id;
}

#####################################################################
# Function: create_matching
#
#
# 概要:
# 指定された1パターン辞書に対する合致パターン情報を作成する。
# マクロ変数が使用されている場合は変換する。
#
# パラメータ:
# pattern_dic_ref     - パターン辞書
# one_pattern_dic_ref - 1パターン辞書
# replace_string      - %keyword%, %pattern%で置換させる文字列(オプション)
# 
# 戻り値:
# one_matching - 合致パターンの基本情報
#
# 例外:
# なし
#
#####################################################################

sub create_matching {
    my ($pattern_dic_ref, $one_pattern_dic_ref, $replace_string) = @_;
    
    my $one_matching = {
        message_id   => $one_pattern_dic_ref->{pattern_body}->{message_id},
        pattern_type => $one_pattern_dic_ref->{pattern_type},
        report_level => $one_pattern_dic_ref->{pattern_body}->{report_level},
        pattern_body => $one_pattern_dic_ref->{pattern_body}->{pattern_body},
        pattern_pos => $one_pattern_dic_ref->{pattern_body}->{pattern_pos},
    };
    
    #
    # マクロ定義を置換する
    #
    my $message = $one_pattern_dic_ref->{pattern_body}->{message_body};
    if(defined $message) {
        my $macro_dic = $pattern_dic_ref->{macros};
        for my $macro_name (keys %{ $macro_dic }) {
            my $macro_value = $macro_dic->{$macro_name};
            $message =~ s{$macro_name}{$macro_value}xmsg;
        }
        
        #
        # %pattern%, %keyword%マクロを置換する
        #
        my $str = undef;
        if(defined $replace_string) {
            $str = $replace_string;
        }
        else {
            $str = $one_pattern_dic_ref->{pattern_name};
        }
        
        $message =~ s{%pattern%|%keyword%}{$str}xmgs;
    }

    $one_matching->{message_body} = $message;

    #
    #TARGETDBMSノードが存在する場合は追加
    #
    if(defined $one_pattern_dic_ref->{pattern_body}->{targetdbms}){
        $one_matching->{targetdbms} = $one_pattern_dic_ref->{pattern_body}->{targetdbms};
    }

    return $one_matching;
}

#####################################################################
# Function: create_matching_from_id
#
#
# 概要:
# 指定されたメッセージIDに対する合致パターン情報を作成する。
# 指定されたメッセージIDに対する1パターン辞書が取得できない場合は
# 固定のエラーメッセージを格納する
#
# パラメータ:
# pattern_dic_ref     - パターン辞書
# message_id          - メッセージID
# replace_string      - %keyword%, %pattern%で置換させる文字列(オプション)
# 
# 戻り値:
# one_matching - 合致パターンの基本情報
#
# 例外:
# なし
#
#####################################################################

sub create_matching_from_id {
    my ($pattern_dic_ref, $message_id, $replace_string) = @_;
    
    my $one_pattern_dic_ref = $pattern_dic_ref->{pattern}->{$message_id};
    
    #
    # 1パターン辞書が取得できなかった場合は固定のエラーメッセージを格納した
    # 擬似的な1パターン辞書を作成する
    #
    if(!defined $one_pattern_dic_ref) {
        $one_pattern_dic_ref = {
            pattern_type => PATTERN_TYPE_COMMON,
            pattern_body => {
                message_id   => '',
                report_level => 'FATAL',
                pattern_body => '',
                message_body => FATAL_MESSAGE
            },
        };
        $replace_string = $message_id;
    }
    
    return create_matching($pattern_dic_ref, $one_pattern_dic_ref, $replace_string);
}

#####################################################################
# Function: create_result
#
#
# 概要:
# 合致パターン情報から報告結果を作成する。
#
# パラメータ:
# parameter       - パラメータ情報
# pattern_info    - 合致パターン情報
# extract_results - 報告結果情報(出力用)
# line_number     - 行数
# 
# 戻り値:
# なし
#
# 例外:
# なし
#
#####################################################################

sub create_result {
    my ($parameter, $pattern_info, $extract_results, $line_number) = @_;

    my $extract_pattern = ExtractResultsPattern->new();

    my $current_funcname = defined $pattern_info->{current_function} ?
                            $pattern_info->{current_function} : $parameter->{funcname};
    $extract_pattern->pattern_pos($pattern_info->{pattern_pos}[0]);
    $extract_pattern->linenumber($line_number);
    $extract_pattern->message_id($pattern_info->{message_id});
    $extract_pattern->pattern_type($pattern_info->{pattern_type});
    $extract_pattern->level($pattern_info->{report_level});
    $extract_pattern->struct($pattern_info->{pattern_body});
    $extract_pattern->target($parameter->{code_body});
    $extract_pattern->message($pattern_info->{message_body});

    #
    #クラス名、メソッド名、変数名を報告結果に格納する。
    #
    $extract_pattern->variablename($parameter->{variablename});
    $extract_pattern->classname($parameter->{funcname});

    #
    #TARGETDBMSノードが存在する場合は
    #報告結果へ格納
    #
    if(defined $pattern_info->{targetdbms}){
    	$extract_pattern->targetdbms($pattern_info->{targetdbms});
    }
    push(@{$extract_results->pattern_list}, $extract_pattern);
}

#####################################################################
# Function: decode_literal
#
# 概要:
# 指定されたリテラル値が文字位置の場合、本来の値を返却する。
# 本来の値が指定された場合は何もしないでそのまま本来の値を返却する。
#
# パラメータ:
# parameter    - パラメータ情報。以下の情報を格納するハッシュである
# - module_list_ref - モジュールリスト
# - func_dic_ref    - 関数辞書
# - pattern_dic_ref - パターン辞書
# - result_ref      - 報告結果配列(出力用)
# - funcname        - 関数名(変数追跡構文が存在する関数名)
# - code_body       - 1コード(変数追跡構文が存在するコード)
# - current_line    - コードを格納する位置情報(変数追跡構文が存在する位置)
# - line_number     - 1コードの行番号
# funcname     - 関数内解析を実施する関数名
# current_line - 関数内解析を開始するコードを格納する位置
# target       - 対象（デコード対象となる文字リテラル）
# 
# 戻り値:
# decoded_literal - デコード後のリテラル値
#
# 特記事項:
# 処理中に使用するデータ構造は以下の通りである。
#
# 例外:
# なし
#
#####################################################################

sub decode_literal {
    
    my ($parameter, $target) = @_;

    my $func_dic_ref = $parameter->{func_dic_ref};

    #
    # リテラル値が文字位置か判定する
    # 文字位置の場合は「" + 数値」となっている
    #    
    if($target =~ m{ "? (" \d+) "? }xms) {
        $target = $func_dic_ref->{'%literal_stack'}->{$1};
    }
    return $target;
}

#####################################################################
# Function: get_blank_number
#
#
# 概要:
# パターンマッチ時のキーワード前の空白文字等の文字数を取得する。
#
# パラメータ:
# code    - パターンマッチ対象文字列
# one_pattern_ref   - 1パターン辞書。以下の情報を格納するハッシュである
#|  pattern_type => "抽出パターン種別",
#|  pattern_body => pattern_pos => "抽出位置のリスト",
# 
# 戻り値:
# blank_number - キーワード前の文字数
#
# 例外:
# なし
#
#####################################################################

sub get_blank_number {
    my ($code, $one_pattern_ref) = @_;
    my $blank_number = 0;

    #
    #否定パターンか判定
    #否定パターンの場合は、空白文字等は存在しないので終了
    #
    if(!$one_pattern_ref->{pattern_body}->{next_pos}){
        return $blank_number;
    }
    #
    #対象コードからパターンマッチ位置以降を切り出し
    #
    my $pos_buff_code = substr($code, $one_pattern_ref->{pattern_body}->{pattern_pos}[0]);
    #
    #パターンタイプがSQL構文の正規表現で文字数をカウント
    #
    if($one_pattern_ref->{pattern_type} eq PATTERN_TYPE_SQL){
        $pos_buff_code =~ m/^\s*/xmsio;
        $blank_number = $+[0];
    }
    
    #
    #SQL構文で空白がない場合、ターンタイプがSQL構文の正規表現で再度、文字数をカウント
    #
    if($blank_number eq 0){
        $pos_buff_code =~ m/^[^\w\d_]*/xmsio;
        $blank_number = $+[0];
    }
    
    return $blank_number;
}

1;

