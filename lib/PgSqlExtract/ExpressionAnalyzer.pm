#############################################################################
#  Copyright (C) 2008 NTT
#############################################################################

#####################################################################
# Function: ExpressionAnalyzer.pm
#
#
# 概要:
# 式解析の制御を行う。
# 抽出対象辞書のコード情報に対して、AnalyzerListに登録されている
# 解析モジュールを実行するための制御を行う。
#
# 特記事項:
# なし
#
#####################################################################

package PgSqlExtract::ExpressionAnalyzer;
use warnings;
use strict;
use Carp;
use base qw(Exporter);
use utf8;
use PgSqlExtract::ExpressionAnalyzer::AnalyzerList;

our @EXPORT_OK = qw(analyze_target analyze_a_file analyze_a_class analyze_a_method);


#
# variable: G_iterator
# AnalyzerListオブジェクト
#
my $G_iterator = undef;


#####################################################################
# Function: analyze_target
#
#
# 概要:
# 抽出対象辞書に登録されているすべてのファイル情報について式解析を実行する。
#
# パラメータ:
# target_dic_ref - 抽出対象辞書
#
# 戻り値:
# result_list - 式解析結果（ファイル）のリファレンスのリスト
#
# 例外:
# なし
#
# 特記事項:
# なし
#
#####################################################################
sub analyze_target {
    my ($target_dic_ref) = @_;
    my @result_list = ();     #式解析結果(ファイル)のリファレンスのリスト
    
    for my $fileinfo (@{$target_dic_ref}) {
        my $report_at_file = analyze_a_file($fileinfo);
        push(@result_list, $report_at_file);
    }
    
    return \@result_list;
}

#####################################################################
# Function: analyze_a_file
#
#
# 概要:
# ファイル情報に登録されているすべてのクラス情報について式解析を実行する。
#
# パラメータ:
# fileinfo_ref - ファイル情報
#
# 戻り値:
# result_at_file - 式解析結果（ファイル）のリファレンス
#
# 例外:
# なし
#
# 特記事項:
# なし
#
#####################################################################
sub analyze_a_file {
    my ($fileinfo_ref) = @_;
    
    #
    # 式解析結果(ファイル)のオブジェクトを新規に生成する
    #
    my $result_at_file = AnalysisResultsFile->new();
    $result_at_file->fileinfo_ref($fileinfo_ref);
    
    #
    # すべてのクラス情報について式解析を実行する
    #
    for my $classinfo (@{$fileinfo_ref->classlist()}) {
        my $result_at_class = analyze_a_class($classinfo);
        
        push(@{ $result_at_file->classlist() },  $result_at_class);
    }
    
    return $result_at_file;
}


#####################################################################
# Function: analyze_a_class
#
#
# 概要:
# クラス情報に登録されているすべてのメソッド情報について式解析を実行する。
#
# パラメータ:
# classinfo_ref - クラス情報
#
# 戻り値:
# result_at_class - 式解析結果（クラス）のリファレンスのリスト
#
# 例外:
# なし
#
# 特記事項:
# なし
#
#####################################################################
sub analyze_a_class {
   my ($classinfo_ref) = @_;
    
    #
    # 式解析結果(クラス)のオブジェクトを新規に生成する
    #
    my $result_at_class = AnalysisResultsClass->new();
    $result_at_class->classinfo_ref($classinfo_ref);

    #
    # 解析モジュールのイテレータ生成
    #
    my $iterator = get_iterator();
   
    #
    # すべてのモジュールについて解析を実行する
    #
    while(my $module = $iterator->get_next_analyzer()) {
        my @result_at_codes = ();
        
        $module->analyze($classinfo_ref, \@result_at_codes);
        push(@{ $result_at_class->methodlist() }, @result_at_codes);       
    }
    
    return $result_at_class;
}


#####################################################################
# Function: get_iterator
#
# 概要:
# AnalyzerListオブジェクトを取得する。オブジェクトが存在しない場合は
# 新規に生成する。
#
# パラメータ:
# なし
#
# 戻り値:
# iterator - AnalyzerListオブジェクト
#
# 例外:
# なし
#
# 特記事項:
# なし
#
#####################################################################
sub get_iterator {
    
    if(!defined $G_iterator) {
        $G_iterator = PgSqlExtract::ExpressionAnalyzer::AnalyzerList->new();
    }
    
    $G_iterator->clear();
    
    return $G_iterator;
}

1;
