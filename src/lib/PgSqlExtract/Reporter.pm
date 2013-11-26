#!/usr/bin/perl
#############################################################################
#  Copyright (C) 2007-2013 NTT
#############################################################################

# $Id: Reporter.pm,v 1.24 2006/12/29 10:46:14 okayama Exp $

#####################################################################
# Function: Reporter.pm
#
#
# 概要:
#
# パターン抽出機能により抽出した項目とその報告内容を報告結果ファイルの形式に成形し、
# ファイル又は標準出力に出力する。
#
# 特記事項:
#
#
#
#####################################################################

package PgSqlExtract::Reporter;
use warnings;
no warnings "utf8";
use strict;
use Carp;
use PgSqlExtract::Common;
use XML::LibXML;
use Encode;
use base qw(Exporter);
use utf8;

our @EXPORT_OK = qw( 
    create_report create_file_node create_report_item_node create_string_item_node 
    write_report write_report_by_plane set_metadata set_starttime set_finishtime
);

#
# variable: G_metadata_list
# メタデータとして格納する文字列と、そのノード名のペアを管理するリスト。
#
my @G_metadata_list = ();

#
# variable: G_starttime
# 実行開始時間として報告する時間文字列を設定する。
#
my $G_starttime;

#####################################################################
# Function: create_report
#
#
# 概要:
#
# 報告結果をXML形式に成形する。
#
# パラメータ:
# report_ref        - 報告結果(ファイル)のリファレンスのリスト
# encoding          - エンコーディング文字列
#
# 戻り値:
# report_dom        - 報告結果から作成したDOMツリー
#
# 例外:
# なし
#
# 特記事項:
# なし
#
#
#####################################################################
sub create_report{
    my ($report_ref,$encoding,$mode) = @_; #引数の格納
    
    
    #
    #エンコード確認
    #
    if($encoding eq ENCODE_EUCJP){
        $encoding = SET_ENCODE_EUCJP;
    }
    elsif($encoding eq ENCODE_SHIFTJIS){
        $encoding = SET_ENCODE_SHIFTJIS;
    }
    elsif($encoding eq ENCODE_UTF8){
        $encoding = SET_ENCODE_UTF8;
    }
    
    my $report_dom = XML::LibXML::Document->createDocument(REPORT_XML_VERSION, $encoding);
    my $node = XML::LibXML::Element->new(REPORT_ROOT_NAME);

    #
    # すべての報告結果について、ファイル単位にDOMノードを生成する
    #
    for my $report_at_file (@{$report_ref}) {

        #
        #FILEノードの生成
        #
        my $filenode = create_file_node($report_at_file,$mode);

        #
        #REPORTノードへの登録
        #   
        $node->appendChild($filenode);
    }
    #
    # file_number、start_time、end_timeの格納
    #
    my $filenode_number = scalar @{$report_ref};
    $node->setAttribute(REPORT_FILE_NUMBER, $filenode_number); 
    $node->setAttribute(REPORT_START_TIME, $G_starttime); 
    
    #
    # METADATAノードの格納
    # METADATAノードは、FILEノードの直前に挿入する
    #
    my $metadatanode = create_metadata_node();
    $node->insertBefore($metadatanode, $node->firstChild);
        
    $report_dom->setDocumentElement($node);
    
    return($report_dom);
}


#####################################################################
# Function: create_metadata_node
#
# 概要:
#
# メタデータの成形を行う。
# - 登録されたテキストノード名でテキストノードを生成し、その内容を格納する。
# - 「METADATA」ノードを生成し、生成したテキストノードを追加する。
#
# パラメータ:
# なし
#
# 戻り値:
# metadatanode  - DOMノード(METADATA)
#
# 例外:
# なし
#
# 特記事項:
# なし
#
#
#####################################################################
sub create_metadata_node {

    my $metadatanode = XML::LibXML::Element->new(REPORT_METADATA_NAME);
    
    for my $metaitem (@G_metadata_list) {
        my ($node_name, $node_value ) = each %{$metaitem}; each %{$metaitem};
        my $metaitemnode = XML::LibXML::Element->new($node_name);
        $metaitemnode->appendText($node_value);
        $metadatanode->appendChild($metaitemnode);
    }
    
    return $metadatanode;
}


#####################################################################
# Function: create_file_node
#
#
# 概要:
#
# 1ファイルに対する報告内容を作成する。
#
# パラメータ:
# report_at_file    - 報告結果(ファイル)
#
# 戻り値:
# filenode          - FILEノード
#
# 例外:
# なし
#
# 特記事項:
# なし
#
#
#####################################################################
sub create_file_node{
    my ($report_at_file,$mode) = @_;   #引数の格納
    
    my $string_item_number = 0;  # STRING_ITEMノードの個数
    my $report_item_number = 0;  # REPORT_ITEMノードの個数
    
    my $filenode = XML::LibXML::Element->new(REPORT_FILE_NAME);


    #
    # STRING_ITEMノードの格納
    #
    my $string_item_nodes = $report_at_file->string_list();
    for my $string_item (@{$string_item_nodes}) {
        my $string_item_node = create_string_item_node($string_item);
            
        $filenode->appendChild($string_item_node);
        $string_item_number++;
            
    }

    #
    #ITEMノードの格納
    #
    my $report_item_nodes = $report_at_file->pattern_list();
    for my $report_item (@{$report_item_nodes}) {
        my $report_item_node = create_report_item_node($report_item,$mode);

        $filenode->appendChild($report_item_node);
        $report_item_number++;
    }

    #
    #name、item_numberの格納
    #
    $filenode->setAttribute(REPORT_NAME, $report_at_file->filename());
    $filenode->setAttribute(REPORT_STRING_ITEM_NUMBER, $string_item_number); 
    $filenode->setAttribute(REPORT_REPORT_ITEM_NUMBER, $report_item_number); 
    $filenode->setAttribute(REPORT_ITEM_NUMBER, 
                                $string_item_number + $report_item_number); 

    return($filenode);
}

#####################################################################
# Function: create_string_item_node
#
#
# 概要:
#
# 報告結果(文字列)の内容を格納する、STRING_ITEMノードを作成する。
#
# パラメータ:
# report_at_string - 報告結果(文字列)
#
# 戻り値:
# stringt_item_node  - REPORT_ITEMノード
#
# 例外:
# なし
#
# 特記事項:
# なし
#
#
#####################################################################
sub create_string_item_node {
    my ($report_at_string) = @_; #引数の格納
    
    
    my $itemnode = XML::LibXML::Element->new(REPORT_STRING_ITEM_NAME);
    #
    #id、line、type、levelの格納
    #
    $itemnode->setAttribute(REPORT_LINE, $report_at_string->linenumber());

    #
    #TARGETノードの作成
    #
    my $targetnode = XML::LibXML::Element->new(REPORT_TARGET_NAME);
    $targetnode->appendText($report_at_string->string());

    #
    #アイテムノードへの登録
    #   
    $itemnode->appendChild($targetnode);

    return($itemnode);
}


#####################################################################
# Function: create_report_item_node
#
#
# 概要:
#
# 報告結果(パターン)の内容を格納する、REPORT_ITEMノードを作成する。
#
# パラメータ:
# report_at_pattern - 報告結果(パターン)
#
# 戻り値:
# report_item_node  - REPORT_ITEMノード
#
# 例外:
# なし
#
# 特記事項:
# なし
#
#
#####################################################################
sub create_report_item_node {
    my ($report_at_pattern,$mode) = @_; #引数の格納
    
    
    my $itemnode = XML::LibXML::Element->new(REPORT_REPORT_ITEM_NAME);
    #
    #id、type、level、scoreの格納
    #
    $itemnode->setAttribute(REPORT_ID, $report_at_pattern->message_id());
    $itemnode->setAttribute(REPORT_TYPE, $report_at_pattern->pattern_type());
    $itemnode->setAttribute(REPORT_LEVEL, $report_at_pattern->level());
    $itemnode->setAttribute(REPORT_SCORE, $report_at_pattern->score());

    #
    #STRUCTノードの作成
    #
    my $stuctnode = XML::LibXML::Element->new(REPORT_STRUCT_NAME);
    $stuctnode->appendText($report_at_pattern->struct());

    #
    #TARGETノードの作成
    #
    my $targetnode = XML::LibXML::Element->new(REPORT_TARGET_NAME);
    if(defined $report_at_pattern->target){
        $targetnode->appendText($report_at_pattern->target());
    }else{
        $targetnode->appendText("[no target value]");
    }

    #
    #MESSAGEノードの作成
    #
    my $messagenode = XML::LibXML::Element->new(REPORT_MESSAGE_NAME);
    my $message=$report_at_pattern->message();
    #
    #メッセージ有無の判定
    #
    if(!defined $message){
        $message="";
    }
    $messagenode->appendText("$message");

    #
    #SOURCEノードの作成
    #
    my $sourcenode = XML::LibXML::Element->new(REPORT_SOURCE_NAME);

    #
    #CLASSノードの作成
    #
    my $classnode = XML::LibXML::Element->new(REPORT_CLASS_NAME);
    if(defined $report_at_pattern->classname){
        $classnode->appendText($report_at_pattern->classname());
    }else{
        $classnode->appendText("[no class name]");
    }

    #
    #METHODノードの作成
    #
    my $methodnode = XML::LibXML::Element->new(REPORT_METHOD_NAME);
    if(defined $report_at_pattern->methodname){
        $methodnode->appendText($report_at_pattern->methodname());
    }else{
        $methodnode->appendText("[no method name]");
    }

    #
    #VARIABLEノードの作成
    #
    my $variablenode = XML::LibXML::Element->new(REPORT_VARIABLE_NAME);
    if(defined $report_at_pattern->variablename){
        $variablenode->appendText($report_at_pattern->variablename());
    }else{
        $variablenode->appendText("[no variable name]");
    }

    #
    #LINEノードの作成
    #
    my $linenode = XML::LibXML::Element->new(REPORT_LINE_NAME);
    $linenode->appendText($report_at_pattern->linenumber());

    #
    #COLUMNノードの作成
    #
    my $columnnode = XML::LibXML::Element->new(REPORT_COLUMN_NAME);
    if(defined $report_at_pattern->pattern_pos){
        $columnnode->appendText($report_at_pattern->pattern_pos());
    }else{
        $columnnode->appendText("[no column value]");
    }

    #
    #SOURCEノードへの登録
    # 
    $sourcenode->appendChild($classnode);
    $sourcenode->appendChild($methodnode);
    $sourcenode->appendChild($linenode);
    $sourcenode->appendChild($columnnode);
    $sourcenode->appendChild($variablenode);

    #
    #アイテムノードへの登録
    #   
    $itemnode->appendChild($sourcenode);
    $itemnode->appendChild($stuctnode);
    $itemnode->appendChild($targetnode);
    $itemnode->appendChild($messagenode);

    #
    #TARGETDBMSノードが存在する場合は
    #アイテムノードへ登録
    #   
    if(defined $report_at_pattern->targetdbms){
        $itemnode->appendChild($report_at_pattern->targetdbms->cloneNode(1));
    }
    
    #
    #SQLモードのときのみ、REPLACEPATTERNノードをアイテムノードへ登録
    # 
    if($mode eq MODE_SQL){
        my $replacepatternnode = XML::LibXML::Element->new(REPORT_REPLACE_PATTERN_NAME);
        if(defined $report_at_pattern->replace_pattern){
        	$replacepatternnode->appendText($report_at_pattern->replace_pattern);

            #
            #replace_flagの格納
            #
            $replacepatternnode->setAttribute(REPORT_REPLACE_FLAG, $report_at_pattern->replace_flag()); 
        }
        else{
    	    $replacepatternnode->appendText("");
    	
    	    #
            #replace_flagの格納
            #
    	    $replacepatternnode->setAttribute(REPORT_REPLACE_FLAG, "no replace");
        }
    
        $itemnode->appendChild($replacepatternnode);
    }
    
    return($itemnode);
}

#####################################################################
# Function: write_report
#
#
# 概要:
#
# 報告結果の内容を指定されたエンコーディングに変換して、出力する。
#
# パラメータ:
# dom               - 報告結果DOMツリー
# output_file_name  - 出力ファイル名
#
# 戻り値:
# 0 - 正常終了
# 1 - 異常終了
#
# 例外:
# なし
#
# 特記事項:
# なし
#
#
#####################################################################
sub write_report{
    my ($dom,$output_file_name) = @_; #引数の格納
    my $exit_status = 0;           #実行結果


    eval {
        #
        # 出力ファイル名が指定されている場合はそのファイル名、指定されて
        # いない場合は標準出力へ出力する。
        #
        if(defined $output_file_name) {
            $dom->toFile($output_file_name, 2) or croak "Cannot create file $output_file_name($!)\n";
        }
    };

    #
    #ファイルの出力時のエラー判定
    #
    if($@){
        $exit_status = 1;
        #
        #エラーメッセージの出力
        #
        print_log($@);
        
        #
        # エラー時には標準出力へ出力する
        #
        undef $output_file_name;
    }
    
    if(!defined $output_file_name) {
        eval {
        	my $xml = $dom->toString(2);
            utf8::is_utf8($xml) ? print(encode('utf-8', $xml)) : print($xml);
        };
        if($@) {
            $exit_status = 1;
            print_log("The output format was changed from the XML format to the CSV format");
            
            croak($@);
        }
    }
    
    return $exit_status;
}

#####################################################################
# Function: write_report_by_plane
#
#
# 概要:
#
# 現時点での報告結果の内容を標準出力にカンマ区切りの形式で出力する。
#
# パラメータ:
# result_array      - 報告結果(ファイル)のリファレンスのリスト
# encoding_name     - エンコーディング
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
#
#####################################################################
sub write_report_by_plane {
    my ($result_array, $encoding_name) = @_; #引数の格納
    
    my @print_item_list = ();
    
    #
    # すべての報告結果について、内容を標準出力へ出力する
    #
    for my $report_at_file (@{$result_array}) {
        
        my $filename = $report_at_file->filename();

        for my $report_at_string (@{ $report_at_file->string_list() }) {
            my $string = Encode::encode($encoding_name, $report_at_string->string());

            printf "%s,%s,%s,%s,%s,%s,%s,%s,%s\n", 
                $filename,
                $string,
                "",
                $report_at_string->linenumber(),
                "","","","",""
            ;
        }
        
        for my $report_at_pattern (@{$report_at_file->pattern_list()}) {
            my $target  = Encode::encode($encoding_name, $report_at_pattern->target());
            my $body    = Encode::encode($encoding_name, $report_at_pattern->struct());
            my $message = Encode::encode($encoding_name, $report_at_pattern->message());

            printf "%s,%s,%s,%s,%s,%s,%s,%s,%s\n",
                $filename,
                $target,
                $report_at_pattern->message_id(),
                $report_at_pattern->linenumber(),
                $report_at_pattern->pattern_type(),
                $report_at_pattern->level(),
                $body,
                $target,
                $message
            ;
            
        }
    }
}

#####################################################################
# Function: set_metadata
#
# 概要:
#
# メタデータとして出力する内容と、そのテキストノード名を設定する。
#
# パラメータ:
# - メタデータを出力するテキストノード名
# - メタデータ内容となる文字列
#
# 戻り値:
# なし
#
# 例外:
# なし
#
# 特記事項:
# - 当メソッドを繰り返し呼び出す度に、METADATAノードへのノード追加
#   が行われる。
#
#
#####################################################################
sub set_metadata {
    my ($node_name, $node_value) = @_;
    push(@G_metadata_list, {$node_name => $node_value});
}

#####################################################################
# Function: set_starttime
#
# 概要:
#
# 実行開始時間として報告する時間文字列を設定する。
#
# パラメータ:
# - 時間文字列
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
#
#####################################################################
sub set_starttime {
    $G_starttime = $_[0];
}

#####################################################################
# Function: set_finishtime
#
# 概要:
#
# 実行終了時間として報告する時間文字列を設定する。
#
# パラメータ:
# - REPORTノード
# - 時間文字列
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
#
#####################################################################
sub set_finishtime {
    $_[0]->documentElement()->setAttribute(REPORT_FINISH_TIME, $_[1]); 
}


1;




