#!/usr/bin/perl
#############################################################################
#  Copyright (C) 2008-2010 NTT
#############################################################################

#####################################################################
# Function: InputAnalyzer.pm
#
#
# 概要:
# 入力情報を解析し、パターン抽出機能に必要となる情報を収集し、
# その内容を抽出対象辞書に格納する。
#
# 特記事項:
# なし
#
#
#####################################################################
package PgSqlExtract::InputAnalyzer;

use warnings;
use strict;
use Carp;
use PgSqlExtract::Common;
use PgSqlExtract::InputAnalyzer::JSPParser;
use PgSqlExtract::InputAnalyzer::JavaParser;
use Encode;
use File::Basename;
use File::Find;
use base qw(Exporter);
use utf8;



our @EXPORT_OK = qw(
    analyze_input_files_java create_target_dictionary
    create_fileInfo_for_a_javafile create_fileInfo_for_a_jspfile
    get_java_parser get_jsp_parser
    );

#
# variable: G_javaparser
# Javaソースコードのパーサオブジェクト。
#
my $G_javaparser = undef;

#
# variable: G_jspparser
# jspソースコードのパーサオブジェクト。
#
my $G_jspparser  = undef;


#####################################################################
# Function: analyze_input_files_java
#
#
# 概要:
#
# 抽出対象ファイル名リストの作成し、返却する
#
# パラメータ:
# input_dir         - 入力ファイル格納フォルダ
# suffix_list       - 拡張子リスト
# file_list         - 直接指定された入力ファイルのリスト
# encoding_name     - エンコード
# mode              - 動作モードのリファレンス（入出力）
#
# 戻り値:
# file_name_list    - 抽出対象ファイル名リスト
#
# 例外:
# なし
#
# 特記事項:
# なし
#
#
#####################################################################
sub analyze_input_files_java{
    my ($input_dir, $suffix_list, $file_list, $encoding_name, $mode) = @_;
    my $file_name_list = undef;#ファイル名リスト

    #
    #抽出対象ファイル名リストの作成
    #
    $file_name_list = create_input_file_list($input_dir, $suffix_list, $file_list);

    return $file_name_list;
}

#####################################################################
# Function: create_target_dictionary
#
#
# 概要:
#
# 全入力ファイルに対して抽出対象辞書を作成する。
# - ファイル名のリストから１件ずつファイル名を取得し、そのファイルの内容を取得
#   する。
# - 該当ファイルがJavaファイルの場合、Javaファイルに対するファイル情報を取得する。
# - 当該ファイルがJSPファイルの場合、JSPファイルに対するファイル情報を取得する。
# - ファイル情報を抽出対象辞書に格納する。
# - 抽出対象ファイルの内容を解析し、パターン抽出機能に必要となる情報を収集し、
#   その内容を関数辞書に格納する。
#
# パラメータ:
# file_name_list    - ファイル名リスト
# encoding_name     - エンコード
#
# 戻り値:
# target_dictionary - 抽出対象辞書
#
# 例外:
# なし
#
# 特記事項:
# なし
#
#
#####################################################################
sub create_target_dictionary{
    my ($file_name, $encoding_name) = @_; #引数の格納
    
    # 抽出対象辞書
    my @target_dictionary = ();

    #
    #ファイル内容を取得する
    #
    get_loglevel() > 0 and print_log('(INFO) | analyze file -- ' . $file_name);

    eval {
        my $new_target_dic;
        
        if($file_name =~ m{\.java$}xmsi) {
            #
            # 該当ファイルがJavaファイルの場合、Javaファイルに対するファイル
            # 情報を取得する
            $new_target_dic = create_fileInfo_for_a_javafile($file_name, $encoding_name);
            push(@target_dictionary, $new_target_dic);
        } elsif($file_name =~ m{\.jsp$}xmsi) {
            #
            # 該当ファイルがJSPファイルの場合、JSPファイルに対するファイル
            # 情報を取得する
            $new_target_dic = create_fileInfo_for_a_jspfile($file_name, $encoding_name);
            push(@target_dictionary, $new_target_dic);
        }
    };
    
    #
    # 抽出対象ファイル作成中にエラーが発生した場合は、そのファイルにおける
    # 解析は中断し、次のファイルについて処理を行う
    #
    if($@) {
        print_log($@);
    }

    return \@target_dictionary;
}

#####################################################################
# Function: create_fileInfo_for_a_javafile
#
#
# 概要:
#
#
# Javaファイルに対するファイル情報を生成する。
# - 入力ファイルを読み込む。
# - 入力ファイル内容をJavaパーサによりパースし、ファイル情報を取得する。
#
# パラメータ:
# $filename         - ファイル名リスト
# encoding_name     - エンコード
#
# 戻り値:
# file_info_ref - ファイル情報
#
# 例外:
# - 入力ファイルのオープンに失敗した場合。
# - 構文解析中にエラーが発生した場合。
#
# 特記事項:
# なし
#
#
#####################################################################
sub create_fileInfo_for_a_javafile {
    my ($filename, $encoding_name) = @_;
    
    #
    # 入力ファイルを読み込む
    #
    my $java_strings = read_input_file($filename, $encoding_name);
    
    
    #
    # 入力ファイル内容をJavaパーサによりパースし、ファイル情報を取得する
    #
    my $parser = get_java_parser();
    $parser->{YYData}->{INPUT} = $java_strings;
    my $file_info = $parser->Run();

    #
    # 構文解析中にエラーが発生した場合は例外を送出する
    #
    $parser->{YYData}->{ERRMES} and do {
        undef $G_javaparser;
        croak(sprintf($parser->{YYData}->{ERRMES}, $filename));
    };

    $file_info->filename($filename); 

    return $file_info;    
}


#####################################################################
# Function: create_fileInfo_for_a_jspfile
#
#
# 概要:
#
# Javaファイルに対するファイル情報を生成する。
# - 入力ファイルを読み込む。
# - 入力ファイル内容をJSPパーサによりパースし、擬似的なJavaソースコードを生成
#   する。
# - 擬似的なJavaソースコードをJavaパーサによりパースし、ファイル情報を
#   取得する。
#
# パラメータ:
# $filename         - ファイル名リスト
# encoding_name     - エンコード
#
# 戻り値:
# file_info_ref - ファイル情報
#
# 例外:
# - 入力ファイルのオープンに失敗した場合。
# - 構文解析中にエラーが発生した場合。
#
# 特記事項:
# なし
#
#
#####################################################################
sub create_fileInfo_for_a_jspfile {
    my ($filename, $encoding_name) = @_;
    
    #
    # 入力ファイルを読み込む
    #
    my $jsp_strings = read_input_file($filename, $encoding_name);
    
    
    #
    # 入力ファイル内容をJSPパーサによりパースし、擬似的なJavaソースコードを
    # 生成する
    #
    my $parser = get_jsp_parser();
    $parser->set_input($jsp_strings);
    
    my $java_strings = undef;
    eval {
        $java_strings = $parser->run();
    };
    if($@) {
        croak(sprintf($@, $filename));
    }
    
    # 擬似的なJavaソースコードをJavaパーサによりパースし、ファイル情報を
    # 取得する
    $parser = get_java_parser();
    get_loglevel() > 9 and print_log("jsp converted code.\n" . $java_strings);
    
    $parser->{YYData}->{INPUT} = $java_strings;
    my $file_info = $parser->Run();

    #
    # 構文解析中にエラーが発生した場合は例外を送出する
    #
    $parser->{YYData}->{ERRMES} and do {
        undef $G_javaparser;
        croak(sprintf($parser->{YYData}->{ERRMES}, $filename));
    };

    $file_info->filename($filename); 

    return $file_info;    
}

#####################################################################
# Function: get_java_parser
#
#
# 概要:
#
# Javaパーサオブジェクトを返却する。オブジェクトが生成されていない
# 場合は新規に生成する。
# 
#
# パラメータ:
# なし
#
# 戻り値:
# $G_javaparser  - Javaパーサオブジェクト
#
# 例外:
# なし
#
# 特記事項:
# - Javaパーサオブジェクトは、グローバル変数 G_javaparserに格納する。
#
#####################################################################
sub get_java_parser {
    
    if(!defined $G_javaparser) {
        $G_javaparser = PgSqlExtract::InputAnalyzer::JavaParser->new();
        $G_javaparser->{YYData}->{loglevel} = get_loglevel();
    }
    return $G_javaparser;
}

#####################################################################
# Function: get_jsp_parser
#
#
# 概要:
#
# jspパーサオブジェクトを返却する。オブジェクトが生成されていない
# 場合は新規に生成する。
# 
#
# パラメータ:
# なし
#
# 戻り値:
# $G_jspparser  - jspパーサオブジェクト
#
# 例外:
# なし
#
# 特記事項:
# - jspパーサオブジェクトは、グローバル変数 G_jspparserに格納する。
#
#####################################################################
sub get_jsp_parser {
    
    if(!defined $G_jspparser) {
        $G_jspparser = PgSqlExtract::InputAnalyzer::JSPParser->new();
    }
    return $G_jspparser;
}

1;