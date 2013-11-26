#!/usr/bin/perl
#############################################################################
#  Copyright (C) 2007-2010 NTT
#############################################################################

#####################################################################
# Function: Loader.pm
#
#
# 概要:
#
# 抽出対象ファイルを解析し、パターン抽出に必要となる情報を収集する。
#
# 特記事項:
#
# 
#
#####################################################################
package PgSqlExtract::Loader;
use warnings;
use strict;
use Carp;
use PgSqlExtract::Common;
use PgSqlExtract::Extractor qw(get_devolve_pattern_id);
use XML::LibXML;
use utf8;

use base qw(Exporter);

our @EXPORT_OK = qw( 
    load_definition_file create_pattern_dictionary create_macro_dictionary
    create_one_dictionary create_pattern_definition create_prepattern
);

#
# variable: G_IGNORE_NODE
# 辞書に格納しないノード名を示す正規表現 
#
my $G_IGNORE_NODE = '[#]?(?:' . DELETE_NODE_NAME . ')';

{

#
# variable: schema
# 報告対象定義ファイルのスキーマオブジェクト 
#
    my $schema = undef;

#####################################################################
# Function: load_definition_file
#
#
# 概要:
#
# 報告対象定義ファイルの解析を行い、パターン辞書を作成、返却する。
#
# パラメータ:
# definition_file    - 報告対象定義ファイル名
# filter    - フィルターキーワード
#
# 戻り値:
# definition_ref     - パターン辞書
#
# 例外:
# なし
#
# 特記事項:
#
#
#####################################################################
    sub load_definition_file{
        my ($definition_file, $filter) = @_; #引数の格納
        my $definition_ref= undef;#パターン辞書
        my $parser = undef;#パーサ格納用
        my $dom = undef;#DOMツリー格納用
        my $schema_def = undef;#スキーマの一時格納用
    
        #
        #スキーマファイルの読み込み
        #
        if(!defined $schema) {
            $schema_def = do {local $/; <DATA>};
            $schema = XML::LibXML::Schema->new( string => $schema_def);
        }
    
        #
        #パーサの作成
        #
        $parser = XML::LibXML->new();
    
        #
        #報告対象定義ファイルの読み込み
        #
        $dom = $parser->parse_file( $definition_file );
        
        #
        #定義ファイルの整合性チェック
        #
        $schema->validate($dom);
        
        #
        #パターン辞書の作成
        #
        $definition_ref = create_pattern_dictionary($dom, $filter);
        
        return($definition_ref);
    
    }
}

#####################################################################
# Function: create_pattern_dictionary
#
#
# 概要:
#
# パターン辞書を作成する。
#
# パラメータ:
# dom    - DOMノード
# filter    - フィルターキーワード
#
# 戻り値:
# definition_ref     - パターン辞書のリファレンス
#
# 例外:
# なし
#
# 特記事項:
#
#
#####################################################################
sub create_pattern_dictionary{
    my ($dom,$filter) = @_; #引数の格納
    my $macro_dictionary_ref = {};#マクロ辞書のリファレンス
    my @nodelist = ();#ノードリスト
    my %pattern_hash = ();#パターン辞書本体ハッシュ
    my %sqlda_pattern_hash = ();#SQLDAのパターン辞書本体ハッシュ
    my @chaser_pattern_list = (); #変数追跡構文の集合を保持するリスト
    my @type_pattern_list = ();#種別TYPEのパターンリスト
    my @embsql_pattern_list = ();#種別EMBSQLのパターンリスト
    my @sql_pattern_list = ();#種別SQLのパターンリスト
    my @func_pattern_list = ();#種別FUNCのパターンリスト
    my @sqlda_pattern_list = ();#種別SQLDAのパターンリスト
    my @sqlca_pattern_list = ();#種別SQLCAのパターンリスト
    my @oraca_pattern_list = ();#種別ORACAのパターンリスト
    my %type_pattern_hash = ();#種別毎のパターン辞書ハッシュ
    my $definition_ref = undef;#パターン辞書のリファレンス
    my $root_node = undef;#ルートノード

    #
    #ルートノードの取得
    #
    $root_node = $dom->documentElement();
    @nodelist = $root_node->childNodes;
    #
    #対象外ノードの削除
    #
    @nodelist = grep{  $_->nodeName !~ m{$G_IGNORE_NODE} } @nodelist;

    #
    #COMMONノードの判定
    #
    if(defined $nodelist[0] and $nodelist[0]->nodeName eq DEFINITION_COMMON_NAME){
        my $common_node = shift @nodelist;
        $macro_dictionary_ref = create_macro_dictionary($common_node);
        #
        #パターン辞書にマクロ辞書を登録
        #
        $definition_ref->{macros} = $macro_dictionary_ref;
    }

    #
    #1パターン辞書の作成
    #
    for my $patterndef_node (@nodelist) {
        #
        #1パターン辞書の作成
        #
        my $one_definition_ref = create_one_dictionary($patterndef_node, $filter);
        
        #
        #FILTERチェックの判定
        #
        if(!defined $one_definition_ref) {
            next;
        }
        
        #
        #種別毎のパターン辞書の配列に格納
        #ただし、パターン定義の内容が空の場合は、種別毎のパターン辞書には
        #格納しない
        #
        my $patid = $patterndef_node->getAttribute(DEFINITION_PATID);
        
        
        if($one_definition_ref->{pattern_body}->{pattern_body} ne '') {
            if($one_definition_ref->{pattern_type} eq PATTERN_TYPE_TYPE){
                push(@type_pattern_list, $one_definition_ref);
            }
            elsif($one_definition_ref->{pattern_type} eq PATTERN_TYPE_EMBSQL){
                push(@embsql_pattern_list, $one_definition_ref);
                
                #
                # 変数追跡構文を収集する
                #
                if(    defined $one_definition_ref->{is_chaser}
                   and $one_definition_ref->{is_chaser} eq 'yes') {
                    my $pattern = $one_definition_ref->{pattern_name};
                    $pattern =~ s{\s+}{\\s+}xmsg;
                    $pattern = PATTERN_BODY_FIRST . $pattern . PATTERN_BODY_LAST;
                    push(@chaser_pattern_list, $pattern);
                }
                
            }
            elsif($one_definition_ref->{pattern_type} eq PATTERN_TYPE_SQL){
                push(@sql_pattern_list, $one_definition_ref);
            }
            elsif($one_definition_ref->{pattern_type} eq PATTERN_TYPE_FUNC){
                push(@func_pattern_list, $one_definition_ref);
            }
            elsif($one_definition_ref->{pattern_type} eq PATTERN_TYPE_SQLDA){
                push(@sqlda_pattern_list, $one_definition_ref);
            }
            elsif($one_definition_ref->{pattern_type} eq PATTERN_TYPE_SQLCA){
                push(@sqlca_pattern_list, $one_definition_ref);
            }
            elsif($one_definition_ref->{pattern_type} eq PATTERN_TYPE_ORACA){
                push(@oraca_pattern_list, $one_definition_ref);
            }
            else{
                #
                # COMMONノードは種別毎のパターン辞書に格納しない
                #
            }
        }
        
        #
        #パターン辞書本体ハッシュに格納
        #       
        $pattern_hash{$patid } = $one_definition_ref;
    }
    
    
    #
    #種別毎のパターン辞書の配列をハッシュに登録
    #
    $type_pattern_hash{TYPE} = \@type_pattern_list;
    $type_pattern_hash{EMBSQL} = \@embsql_pattern_list;
    $type_pattern_hash{SQL} = \@sql_pattern_list;
    $type_pattern_hash{FUNC} = \@func_pattern_list;
    $type_pattern_hash{SQLDA} = \@sqlda_pattern_list;
    $type_pattern_hash{SQLCA} = \@sqlca_pattern_list;
    $type_pattern_hash{ORACA} = \@oraca_pattern_list;
    
    #
    #準備した情報をパターン辞書へ登録
    #
    $definition_ref->{macros} = $macro_dictionary_ref;
    $definition_ref->{pattern} = \%pattern_hash;
#    $definition_ref->{sqlda} = \%sqlda_pattern_hash;
    $definition_ref->{type} = \%type_pattern_hash;

    #
    #プレパターンの登録
    #
    create_prepattern($definition_ref);
    
    #
    #変数追跡構文の抽出パターンの登録
    #
    $definition_ref->{chaserpattern} = join('|', @chaser_pattern_list);
    set_chaserpattern($definition_ref->{chaserpattern});
    
    return($definition_ref);

}

#####################################################################
# Function: create_macro_dictionary
#
#
# 概要:
#
# COMMONノードから、マクロ辞書を作成、返却する。
#
# パラメータ:
# common_node       - COMMONノード
#
# 戻り値:
# macro_hash        - マクロ辞書ハッシュのリファレンス
#
# 例外:
# なし
#
# 特記事項:
#
#
#####################################################################
sub create_macro_dictionary{
    my ($common_node) = @_; #引数の格納
    my @macro_nodelist = ();#MACROノードのリスト
    my $macro_node = undef;#MACROノード
    my %macro_hash = ();#マクロ辞書のハッシュ
    my $name = undef;#NAME
    my $value = undef;#VALUE
    my @nodelist = ();#ノードのリスト

    #
    #マクロノードの取得
    #
    @macro_nodelist = $common_node->childNodes;
    #
    #対象外ノードの削除
    #
    @macro_nodelist = grep{  $_->nodeName !~ m{$G_IGNORE_NODE} } @macro_nodelist;
    for $macro_node (@macro_nodelist){
        
        @nodelist = $macro_node->childNodes;
        #
        #対象外ノードの削除
        #
        @nodelist = grep{  $_->nodeName !~ m{$G_IGNORE_NODE} } @nodelist;
                
        #
        #NAMEの取得
        #           
        $name = $nodelist[0]->textContent;

        #
        #VALUEの取得
        #   
        $value = $nodelist[1]->textContent;

        #
        #マクロ辞書へ登録
        #   
        $macro_hash{$name} = $value;
        
    }#マクロノードの取得ループの終端
    
    return(\%macro_hash);
}

#####################################################################
# Function: create_one_dictionary
#
#
# 概要:
#
# PATTERNDEFノードから、1パターン辞書を作成、返却する。
#
# パラメータ:
# patterndef_node       - PATTERNDEFノード
# filter    - フィルターキーワード
#
# 戻り値:
# one_dictionary_hash       - 1パターン辞書ハッシュのリファレンス
#
# 例外:
# なし
#
# 特記事項:
#
#
#####################################################################
sub create_one_dictionary{
    my ($patterndef_node,$filter) = @_; #引数の格納
    my %one_dictionary_hash = ();#パターン辞書のハッシュ
    my $name = undef;#NAME
    my $type = undef;#TYPE
    my $chaser = undef;#CHASER
    my @sub_pattern_nodelist = ();#SUB_PATTERNノードのリスト
    my $sub_pattern = undef;#SUB_PATTERN
    my @sub_pattern_list = ();#SUB_PATTERNのリスト
    my $access_type = undef;#ACCESS_TYPE
    my $pattern_definition = undef;#パターン定義

    #
    #TYPEの取得
    #   
    $type = $patterndef_node->getAttribute(DEFINITION_TYPE);
    
    #
    #パターン定義の作成
    #
    $pattern_definition = create_pattern_definition($patterndef_node,$filter,$type, DEFINITION_PATTERNDEF_NAME); 
    
    #
    #FILTERチェックの判定
    #
    if(!$pattern_definition){
        return; 
    }

    #
    #NAMEの取得
    #           
    $name = $pattern_definition->{pattern_name};
    


    #
    #CHASERの取得
    #   
    if($patterndef_node->hasAttribute(DEFINITION_CHASER)){
        $chaser = $patterndef_node->getAttribute(DEFINITION_CHASER);
        #
        #CHASERの登録
        #
        $one_dictionary_hash{is_chaser} = $chaser;
    }

    #
    #SUBPATTERNの取得
    #   
    @sub_pattern_nodelist = $patterndef_node->childNodes;
    #
    #対象外ノードの削除
    #
    @sub_pattern_nodelist = grep{ $_->nodeName eq DEFINITION_KEYWORDDEF_NAME } @sub_pattern_nodelist;   
    for my $sub_pattern_node (@sub_pattern_nodelist){
        #
        #パターン定義の取得
        #
        $sub_pattern = create_pattern_definition($sub_pattern_node,$filter,$type);
        push(@sub_pattern_list, $sub_pattern) if defined $sub_pattern;
    }

    #
    #ACCESS_TYPEの存在判定
    #   
    if(exists($pattern_definition->{access_type})){
        #
        #ACCESS_TYPEの登録
        #
        $one_dictionary_hash{access_type} = $pattern_definition->{access_type};
    }

    #
    #パターン辞書への登録
    #サブ抽出パターンは存在する場合のみ登録する
    #
    $one_dictionary_hash{pattern_name} = $name;
    $one_dictionary_hash{pattern_type} = $type;
    $one_dictionary_hash{pattern_body} = $pattern_definition;
    if(scalar @sub_pattern_list != 0) {
        $one_dictionary_hash{subpattern_body} = \@sub_pattern_list;
    }
            
    return(\%one_dictionary_hash);
}

#####################################################################
# Function: create_pattern_definition
#
#
# 概要:
#
# PATTERNDEFノードまたはKEYWORDDEFノードから、パターン定義を作成、返却する。
#
# パラメータ:
# node      - PATTERNDEFノードまたはKEYWORDDEFノード
# filter    - フィルターキーワード
# type      - 抽出パターン種別
# nodetype  - PATTERNDEFノードかKEYWORDDEFノードかの種別。省略可能でデフォルト
#             の場合、KEYWORDDEFノードと認識する
# 戻り値:
# pattern_definition_hash       - パターン定義ハッシュのリファレンス
#
# 例外:
# なし
#
# 特記事項:
#
#
#####################################################################
sub create_pattern_definition{
    my ($node,$filter,$type, $nodetype) = @_; #引数の格納
    my @child_nodelist = ();#子ノードのリスト
    my $child_node = ();#子ノード
    my %pattern_definition_hash = ();#パターン定義のハッシュ
    my $pattern_body = undef;#パターン格納

    #
    #FILTERの判定
    #
    if($node->hasAttribute(DEFINITION_FILTER)){
        my $filter_def = $node->getAttribute(DEFINITION_FILTER);
        if(   $filter_def eq $filter
           || $filter eq FILTER_ALL){
            $pattern_definition_hash{filter_word} = $filter_def;
        }
        else{
            return;
        }
    }

    #
    #POSの登録
    #   
    if($node->hasAttribute(DEFINITION_POS)){
        $pattern_definition_hash{subpattern_pos} = $node->getAttribute(DEFINITION_POS);
    }
    
    
    #
    #子ノードの取得
    #   
    @child_nodelist = $node->childNodes;
    #
    #対象外ノードの削除
    #
    @child_nodelist = grep{  $_->nodeName !~ m{$G_IGNORE_NODE} } @child_nodelist;
    
    #
    #NAMEの登録
    #           
    $pattern_definition_hash{pattern_name} = $child_nodelist[0]->textContent;
    
    #
    #PATTERN_BODYの登録
    #
    $pattern_body = $child_nodelist[1]->textContent;

    #
    #対象の抽出パターンがパターン委譲か判定する
    #パターン委譲ではない場合は、そのパターンの整形およびクロージャの定義を行う
    #
    my $is_dineded_pattern = $pattern_body =~ s{^[!]}{}xms;
    if(!get_devolve_pattern_id($pattern_body)) {
        #
        #抽出パターンの整形を行う
        #抽出パターン種別がSQLDAおよびCOMMONのものは除く
        #
        if($type ne PATTERN_TYPE_SQLDA
        and $type ne PATTERN_TYPE_COMMON
        and $pattern_body ne ''){
    
            #
            #PATTERN_BODYの整形
            #
    
            $pattern_body =~ s{\s+}{\\s+}xmsg;
            $pattern_body =~ s{\(?\$[\d]+\)?}{(.*)}xmsg;
            my $pattern_body_first = PATTERN_BODY_FIRST;
            
            if(    defined $nodetype 
               and $nodetype eq DEFINITION_PATTERNDEF_NAME
               and $type eq PATTERN_TYPE_SQL) {
                $pattern_body_first = PATTERN_BODY_FIRST_FOR_SQL;
            }
    
            #
            #抽出パターン種別がFUNCか判定
            #
            if($type eq PATTERN_TYPE_FUNC){
                $pattern_body = $pattern_body_first.$pattern_body;
            }
            else{
                $pattern_body = $pattern_body_first.$pattern_body.PATTERN_BODY_LAST;
            }
        }       
    
        #
        # 抽出パターンを評価するクロージャを定義する
        # 否定パターンについて、同時に抽出パターン文字列の編集を行う
        #
        my $expr;
        my $evaluated_pattern = $pattern_body;
        $evaluated_pattern =~ s{([\$\@%])}{\\$1}xmsg;
        if($is_dineded_pattern) {
            $expr = '$_ !~ m{' . $evaluated_pattern . '}xmsio;';
            $pattern_body = '!' . $pattern_body;    # 結果出力用に否定文字を付与
        }
        else {
            #
            # 抽出パターンを評価時に抽出先頭位置と抽出終端位置を格納する
            #
            $expr = 'my @result = $_ =~ m{' . $evaluated_pattern . '}xmsio;
                    my @pattern_pos = @-;
                    $pattern_definition_hash{pattern_pos} = \@pattern_pos;
                    my @next_pos = @+;
                    $pattern_definition_hash{next_pos} = \@next_pos;
                    return @result;';
        }
        $pattern_definition_hash{pattern_evaluater} = eval "sub{ $expr }";
    }
    #
    # 抽出先頭位置と抽出終端位置の格納用
    #
    $pattern_definition_hash{pattern_pos} = ();
    $pattern_definition_hash{next_pos} = ();
    $pattern_definition_hash{pattern_body} = $pattern_body;

    
    #
    # ポインタ参照の有無を登録する
    #
    if($child_nodelist[1]->hasAttribute(DEFINITION_ACCESS_TYPE)){
        #
        #ACCESS_TYPEの登録
        #
        $pattern_definition_hash{access_type} = $child_nodelist[1]->getAttribute(DEFINITION_ACCESS_TYPE);
    }       
        
    #
    #MESSAGEノードの取得
    #   
    if(defined $child_nodelist[2] and $child_nodelist[2]->nodeName eq DEFINITION_MESSAGE_NAME){
        #
        #MESSAGE_IDの登録
        #
        $pattern_definition_hash{message_id} = $child_nodelist[2]->getAttribute(DEFINITION_MESSAGE_ID);

        #
        #REPORT_LEVELの登録
        #
        $pattern_definition_hash{report_level} = $child_nodelist[2]->getAttribute(DEFINITION_MESSAGE_LEVEL);

        #
        #MESSAGE_BODYの登録
        #
        $pattern_definition_hash{message_body} = $child_nodelist[2]->textContent;
    }elsif(defined $child_nodelist[2] and $child_nodelist[2]->nodeName eq DEFINITION_PLUGIN_NAME){
        #
        #LIBRARYの登録
        #
        $pattern_definition_hash{library} = $child_nodelist[2]->getAttribute(DEFINITION_LIBRARY);

        #
        #PROCEDUREの登録
        #
        $pattern_definition_hash{procedure} = $child_nodelist[2]->getAttribute(DEFINITION_PROCEDURE);
    }


    #
    #TARGETDBMSノードの取得
    #
    if($child_nodelist[$#child_nodelist]->nodeName eq DEFINITION_TARGETDBMS_NAME){
        $pattern_definition_hash{targetdbms} = $child_nodelist[$#child_nodelist];
    }
        
    return(\%pattern_definition_hash);
}


#####################################################################
# Function: create_prepattern
#
#
# 概要:
#
# パターン辞書から、プレパターンを作成し、登録する。
#
# パラメータ:
# definition_ref        - パターン辞書ハッシュのリファレンス
#
# 戻り値:
# なし
#
# 例外:
# なし
#
# 特記事項:
#
#
#####################################################################
sub create_prepattern{
    my ($definition_ref) = @_; #引数の格納
    my $one_pattern_dictionary = undef;#1パターン辞書本体
    my $pattern_id = undef;#抽出パターンID
    my $name = undef;#抽出パターン名
    my @pattern_name_list = ();#抽出パターン名格納リスト
    my %pattern_id_hash = ();#プレパターンとの対応辞書

    #
    #抽出パターンIDの取得
    #
    for $pattern_id (keys(%{$definition_ref->{pattern}})){
        #
        #1パターン辞書の取得
        #           
        $one_pattern_dictionary  = $definition_ref->{pattern}->{$pattern_id};

        #
        #パターン種別の判定
        #           
        if($one_pattern_dictionary->{pattern_type} ne PATTERN_TYPE_SQL) {
            next;
        }

        #
        #抽出パターン名の取得
        #
        $name = $one_pattern_dictionary->{pattern_name};
        #
        #抽出パターン名格納リストに登録
        #
        push(@pattern_name_list, $name);
        
        #
        #プレパターンとの対応辞書に登録
        #   
        $pattern_id_hash{$name} = $pattern_id;
        
    }#抽出パターンIDの取得ループの終端
    
    #
    #プレパターンの登録
    #
    $definition_ref->{prepattern} = join('|',@pattern_name_list);
    $definition_ref->{prepattern} =~ s{\s+}{\\s\+}xmsg;

    #
    #プレパターンとの対応辞書の登録
    #
    $definition_ref->{pattern_id} = \%pattern_id_hash;
    
    
    return;
}

1;  

__DATA__
<?xml version="1.0" encoding="UTF-8"?>
<xsd:schema xmlns:xsd="http://www.w3.org/2001/XMLSchema">

  <xsd:element name="COMMON" type="CommonType"/>
  <xsd:element name="MACRO" type="MacroType"/>
  <xsd:element name="PATTERNDEF" type="PatternDefType"/>
  <xsd:element name="KEYWORDDEF" type="KeywordDefType"/>
  <xsd:element name="NAME" type="xsd:string"/>
  <xsd:element name="VALUE" type="xsd:string"/>
  <xsd:element name="MESSAGE" type="MessageType"/>
  <xsd:element name="PATTERN" type="PatternType"/>
  <xsd:element name="PLUGIN" type="PluginType"/>
  <xsd:element name="TARGETDBMS" type="TargetDBMSType"/>
  <xsd:element name="DBMS" type="DBMSType"/>

  <!-- Definition for DEFINITION NODE -->
  <xsd:element name="DEFINITION">
    <xsd:complexType>
      <xsd:sequence>
        <xsd:element ref="COMMON" minOccurs="0" maxOccurs="1"/>
        <xsd:element ref="PATTERNDEF" minOccurs="0" maxOccurs="unbounded"/>
      </xsd:sequence>
    </xsd:complexType>
  </xsd:element>

  <!-- Definition for COMMON NODE -->
  <xsd:complexType name="CommonType">
    <xsd:sequence>
      <xsd:element ref="MACRO" minOccurs="0" maxOccurs="unbounded"/>
    </xsd:sequence>
  </xsd:complexType>

  <!-- Definition for MACRO NODE -->
  <xsd:complexType name="MacroType">
    <xsd:sequence>
      <xsd:element ref="NAME" minOccurs="1" maxOccurs="1"/>
      <xsd:element ref="VALUE" minOccurs="1" maxOccurs="1"/>
    </xsd:sequence>
  </xsd:complexType>

  <!-- Definition for PATTERNDEF NODE -->
  <xsd:complexType name="PatternDefType">
    <xsd:sequence>
      <xsd:element ref="NAME" minOccurs="1" maxOccurs="1"/>
      <xsd:element ref="PATTERN" minOccurs="1" maxOccurs="1" />
      <xsd:choice>
        <xsd:element ref="MESSAGE" minOccurs="1" maxOccurs="1"/>
        <xsd:element ref="KEYWORDDEF" minOccurs="1" maxOccurs="unbounded"/>
        <xsd:element ref="PLUGIN" minOccurs="1" maxOccurs="1"/>
      </xsd:choice>
      <xsd:element ref="TARGETDBMS" minOccurs="0" maxOccurs="1"/>
    </xsd:sequence>
    <xsd:attribute name="patid" type="xsd:string" use="required"/>
    <xsd:attribute name="type" use="required">
    <xsd:simpleType>
      <xsd:restriction base="xsd:string">
        <xsd:enumeration value="TYPE"/>
        <xsd:enumeration value="EMBSQL"/>
        <xsd:enumeration value="SQL"/>
        <xsd:enumeration value="FUNC"/>
        <xsd:enumeration value="SQLDA"/>
        <xsd:enumeration value="SQLCA"/>
        <xsd:enumeration value="ORACA"/>
        <xsd:enumeration value="COMMON"/>
      </xsd:restriction>
    </xsd:simpleType>
    </xsd:attribute>
    <xsd:attribute name="filter" type="xsd:string"/>
    <xsd:attribute name="chaser" type="xsd:string"/>
  </xsd:complexType>

  <!-- Definition for KEYWORDDEF NODE -->
  <xsd:complexType name="KeywordDefType">
    <xsd:sequence>
      <xsd:element ref="NAME" minOccurs="1" maxOccurs="1"/>
      <xsd:element ref="PATTERN" minOccurs="1" maxOccurs="1" />
      <xsd:choice>
        <xsd:element ref="MESSAGE" minOccurs="1" maxOccurs="1"/>
        <xsd:element ref="PLUGIN" minOccurs="1" maxOccurs="1"/>
      </xsd:choice>
      <xsd:element ref="TARGETDBMS" minOccurs="0" maxOccurs="1"/>
    </xsd:sequence>
    <xsd:attribute name="pos" type="xsd:string" use="required"/>
    <xsd:attribute name="filter" type="xsd:string"/>
  </xsd:complexType>

  <!-- Definition for MESSAGE NODE -->
  <xsd:complexType name="MessageType">
    <xsd:simpleContent>
      <xsd:extension base="xsd:string">
        <xsd:attribute name="id" type="xsd:string" use="required"/>
        <xsd:attribute name="level" type="xsd:string" use="required"/>
        </xsd:extension>
      </xsd:simpleContent>
  </xsd:complexType>

  <!-- Definition for PATTERN NODE -->
  <xsd:complexType name="PatternType">
    <xsd:simpleContent>
      <xsd:extension base="xsd:string">
        <xsd:attribute name="accessType" type="xsd:string"/>
        </xsd:extension>
      </xsd:simpleContent>
  </xsd:complexType>

  <!-- Definition for PLUGIN NODE -->
  <xsd:complexType name="PluginType">
    <xsd:attribute name="library" type="xsd:string" use="required"/>
    <xsd:attribute name="procedure" type="xsd:string" use="required"/>
  </xsd:complexType>

  <!-- Target DBMS Version -->
  <xsd:complexType name="TargetDBMSType">
    <xsd:sequence>
      <xsd:element ref="DBMS" minOccurs="1" maxOccurs="unbounded"/>
    </xsd:sequence>
  </xsd:complexType>

  <!-- Definition for DBMS NODE -->
  <xsd:complexType name="DBMSType">
    <xsd:sequence>
      <xsd:element name="PRODUCT" type="xsd:string" minOccurs="1" maxOccurs="1"/>
      <xsd:element name="VERSION" type="xsd:string" minOccurs="1" maxOccurs="1"/>
    </xsd:sequence>
  </xsd:complexType>

</xsd:schema>
