#!/usr/bin/perl
#############################################################################
#  Copyright (C) 2007-2011 NTT
#############################################################################

#####################################################################
# Function: Analyzer.pm
#
#
# 概要:
# 入力情報を解析し、パターン抽出機能に必要となる情報を収集し、
# その内容を関数辞書に格納する。
#
# 特記事項:
#
#
#
#####################################################################
package PgSqlExtract::Analyzer;
use PgSqlExtract::Analyzer::CParser;
use PgSqlExtract::Analyzer::PreprocessAnalyzer qw( preprocess_analyzer_prev set_pg_sqlextract_macro );
use warnings;
use strict;
use Carp;
use PgSqlExtract::Common;
use PgSqlExtract::Common::Lexer qw(clear_typedef_name set_typedefname all_clear_typedef_name);
use Encode;
use File::Basename;
use File::Find;
use FindBin;
use base qw(Exporter);
use utf8;

our @EXPORT_OK = qw( 
    analyze_input_files create_function_dictionary 
    create_function_dictionary_for_a_file normalize_codes 
    create_absolute_dictionary create_simple_dictionary 
    set_function_init_data_storage_function get_c_parser
    );

#
# variable: G_literal_number
# 文字リテラルの退避位置 
#
my $G_literal_number = 0;                # 文字リテラルの退避位置

#
# variable: G_cparser
# Cソースコードのパーサオブジェクト。
#
my $G_cparser = undef;

#####################################################################
# Function: analyze_input_files
#
#
# 概要:
#
# 抽出対象ファイルの内容を解析し、パターン抽出機能に必要となる情報を収集し、
#その内容を関数辞書に格納する。
# 
#
# パラメータ:
# input_dir         - 入力ファイル格納フォルダ
# suffix_list       - 拡張子リスト
# file_list         - 直接指定された入力ファイルのリスト
# encoding_name     - エンコード
# mode              - 動作モードのリファレンス（入出力）
# deffile_path      - 報告対象定義ファイルのパス
#
# 戻り値:
# function_ref      - 関数辞書
#
# 例外:
# なし
#
# 特記事項:
#
#
#####################################################################
sub analyze_input_files{
    my ($input_dir, $suffix_list, $file_list, $encoding_name, $mode, $include_dir_list, $deffile_path) = @_;
    my $function_ref= "";#関数辞書
    my $file_name_list = undef;#ファイル名リスト

    #
    #抽出対象ファイル名リストの作成
    #
    $file_name_list = create_input_file_list($input_dir, $suffix_list, $file_list);

    #
    #関数辞書の作成
    #
    $function_ref = create_function_dictionary($file_name_list, $encoding_name, $mode, $include_dir_list, $deffile_path);
    $G_literal_number = 0;

    return $function_ref;
}

#####################################################################
# Function: create_function_dictionary
#
#
# 概要:
#
# 抽出対象ファイルの内容を解析し、パターン抽出機能に必要となる情報を収集し、
#その内容を関数辞書に格納する。
# 
#
# パラメータ:
# file_name_list    - ファイル名リスト
# encoding_name     - エンコード
# mode              - 動作モードのリファレンス（入出力）
# deffile_path      - 報告対象定義ファイルのパス
#
# 戻り値:
# function_dictionary      - 関数辞書
#
# 例外:
# なし
#
# 特記事項:
#
#
#####################################################################
sub create_function_dictionary{
    my ($file_name_list, $encoding_name, $mode, $include_dir_list, $deffile_path) = @_; #引数の格納
    # 抽出対象辞書
    my @target_dictionary = ();
    my $file_name = "";#ファイル名
    #
    #関数辞書の作成
    #
    foreach $file_name (@{$file_name_list}){
        get_loglevel() > 0 and print_log('(INFO) | analyze file -- ' . $file_name);

        eval {
            #
            #関数辞書ハッシュに1ファイル分の関数情報を追加する
            #
            #
            #「埋め込みSQL抽出モード」か判定
            #
            if(${ $mode } eq MODE_C){
                #
                #関数辞書の作成
                #
                my $file_info = create_absolute_dictionary($encoding_name, $file_name, $include_dir_list, $deffile_path);
                push(@target_dictionary, $file_info);
            }
            else{
                my %new_target_dic = ();#ファイル
                my %function_dictionary= ();#関数辞書
                my %literal_stack = (); #文字リテラルの退避用リテラルスタック
                
                #
                #ファイルの読み込み,正規化
                #
                my $code_data = normalize_codes(read_input_file($file_name, $encoding_name),$mode,\%literal_stack);

                #
                #簡易モードでの関数辞書の作成
                #
                my $new_simple_function_dic = create_simple_dictionary($code_data, $file_name);

                #
                # リテラルスタックを格納する
                #
                $new_simple_function_dic->{'%literal_stack'} = \%literal_stack;
                                                
                while(my ($key, $value) = each %{ $new_simple_function_dic }) {
                    if($key eq '%literal_stack') {
                        while(my ($stack_key, $stack_value) = each %{ $new_simple_function_dic->{$key}}) {
                            $function_dictionary{'%literal_stack'}->{$stack_key} = $stack_value; 
                        }
                    }
                    else {
                        $function_dictionary{$key} = $value;
                    }
                }
                $new_target_dic{func_dic_ref} = \%function_dictionary;
                $new_target_dic{filename} = $file_name;
                push(@target_dictionary, \%new_target_dic);
            }
        };
        
        #
        # 抽出対象ファイル作成中にエラーが発生した場合は、そのファイルにおける
        # 解析は中断し、次のファイルについて処理を行う
        #
        if($@) {
            print_log($@);
        }

    }
    return \@target_dictionary;
}

#####################################################################
# Function: normalize_codes
#
#
# 概要:
#
# ファイル内容についてコードの正規化を行う。
# 関数スコープを示す中括弧の対応が不正と認識された場合は、動作モード
# を簡易抽出モードへ変更する。
# 
#
# パラメータ:
# file_strings      - ファイル内容
# mode              - 動作モード(出力用)
# function_hash     - 関数ハッシュ(出力用)
#
# 戻り値:
# code_info         - コード情報の配列
#
# 例外:
# なし
#
# 特記事項:
#
#####################################################################
sub normalize_codes{
    my ($file_strings,$mode,$literal_stack) = @_; #引数の格納
    my $line_count = 1;#行番号のカウンタ
    my $code_line_count = 1;#正規化したコードの行番号
    my $code = undef;#正規化対象コード
    my @code_info = ();#コード情報配列
    my $struct_brace_count = 0;     #構造体解析中のネスト数
    my $in_the_struct = FALSE;      #構造体の解析状態。構造体解析中の場合は真
    my @code_char = ();#一文字づつのコード配列
    my $code_char_max = 0;#一文字づつのコード配列の添え字
    my $brace_count = 0;#括弧のカウンタ
    my $in_comment_flg = FALSE;#コメント又はリテラル内かのフラグ
    my $preprocessor_flg = FALSE;#前処理指令のフラグ
    my $is_preserve_comment = FALSE;  # 保持すべきコメント文字列であるかの真偽値
    my $literal_buff = "";         # 文字リテラルの一時保存領域

    get_loglevel() > 2 and print_log("(DEBUG 3) | [in] normalize_codes");
    #
    #コードの正規化
    #
    
    #一文字づつ配列に格納
    @code_char = split(//, $file_strings);
    
    #最大添え字を取得
    $code_char_max = $#code_char;
    
    #最終文字+1まで判定するため最後に要素を追加
    push(@code_char , '');
    
    #コメントの削除、リテラルの退避
    for(my $char_count = 0; $char_count <= $code_char_max; $char_count++) {
        
        if($code_char[$char_count] eq "\n"){
            #
            #行番号のインクリメント
            #
            $line_count++;
            
            #
            #改行の格納
            #ただしリテラル内リテラル解析中以外の場合に改行文字を格納する
            #リテラル内リテラル中に行の継続が存在するケースが改行文字を
            #格納しないケースである
            #
            if($in_comment_flg == LITERAL
            or $in_comment_flg == SQL_LITERAL) {
                $literal_buff .= $code_char[$char_count];
            }
            elsif($in_comment_flg != LITERAL_LITERAL){
                $code .= $code_char[$char_count];
            }

            if($is_preserve_comment) {
                $code =~ s{(.*)(--.*$)}{$1}xms;
                $is_preserve_comment = FALSE;
                $in_comment_flg = NOT_COMMENT;
            }
            
            #
            #行の継続の判定
            #       
            if($in_comment_flg == LITERAL
            or $in_comment_flg == SQL_LITERAL) {
                if($literal_buff =~ s{(.*)?\\[\s\t]* \z}{$1}xms){
                    next;
                }
            }
            else{
                if($code =~ s{(.*)?\\[\s\t]* \z}{$1}xms){
                    next;
                }
            }
            
            #「--」コメント・「//」コメント・前処理指令の終了判定
            if($in_comment_flg == SIMPLE_COMMENT){
                $in_comment_flg = NOT_COMMENT;
            }
            
            #
            #空白行か判定
            #
            if($code =~ m/\A \s* \z/xms){
                #
                #コード行番号のインクリメント
                #
                $code_line_count++;
                next;
            }
                            
            #
            # 構造体解析中の場合は改行文字を正規化判定文字としない
            #
            if($in_the_struct) {
                next;
            }
            
            #
            # 正規化判定文字によるコードの格納
            #
            if($preprocessor_flg){
                #
                #前後空白の削除
                #
                $code =~ s{\A \s*(.*)\s* \z}{$1}xms;
                
                #
                #コード情報の格納
                #
                get_loglevel() > 6 and print_log("(DEBUG 7) | " . $code_line_count . ": $code");
                push(@code_info,{line_number => $code_line_count, code_body => $code});
                
                #
                #格納した次の行を次の格納行番号として格納
                #
                $code_line_count = $line_count;
                
                #
                #コード格納領域の初期化
                #
                $code = "";
                
                #
                #フラグの初期化
                #
                $preprocessor_flg = FALSE;
            }
            next;
        }
        #「/*」コメントの開始判定
        elsif($in_comment_flg == NOT_COMMENT 
        and $code_char[$char_count] eq '/' 
        and $code_char[$char_count+1] eq '*'){
            $char_count++;
            $in_comment_flg = MULTI_COMMENT;
            next;
        }
        #「/*」コメントの終了判定
        elsif($in_comment_flg == MULTI_COMMENT 
        and $code_char[$char_count] eq '*' 
        and $code_char[$char_count+1] eq '/'){
            $char_count++;
            $in_comment_flg = NOT_COMMENT;
            next;
        }
        #「--」コメントの開始判定
        elsif($in_comment_flg == NOT_COMMENT 
        and $code_char[$char_count] eq '-' 
        and $code_char[$char_count+1] eq '-'){
			if(${ $mode } eq MODE_SQL) {
                $char_count++;
                $in_comment_flg = SIMPLE_COMMENT;
                $is_preserve_comment = TRUE;
                next;
			}
            if(defined($code) and $code =~ m{\bEXEC\b\s+\bSQL\b}ixms){
                $char_count++;
                $in_comment_flg = SIMPLE_COMMENT;
                $is_preserve_comment = TRUE;
                next;
            }
        }
        #「//」コメントの開始判定
        elsif($in_comment_flg == NOT_COMMENT 
        and $code_char[$char_count] eq '/' 
        and $code_char[$char_count+1] eq '/'){
            $char_count++;
            $in_comment_flg = SIMPLE_COMMENT;
            next;
        }
        #「{」正規化判定文字の開始判定
        elsif($in_comment_flg == NOT_COMMENT
        and $code_char[$char_count] eq '{'){
            $brace_count++;
			get_loglevel() > 6 and print_log("(DEBUG 7) | $line_count : brace_count " . $brace_count);
            $code .= $code_char[$char_count];
            
            #
            # 構造体宣言における中括弧か判断する
            # 構造体宣言の場合は、閉じ括弧"}"までを1つの正規化行とする
            #
            if($code =~ m/\b struct (?:\s+[\w_]+)? \s* {/xms) {
                $in_the_struct = TRUE;
            }
            
            #
            # 構造体の処理中の場合は正規化判定文字としない
            #
            if($in_the_struct){
                $struct_brace_count++;
                next;
            }
            else{ 
                #
                #前後空白の削除
                #
                $code =~ s{\A \s*(.*)\s* \z}{$1}xms;
                
                #
                #コード情報の格納
                #
                push(@code_info,{line_number => $code_line_count, code_body => $code});
                #
                #格納した行を次の格納行番号として格納
                #
                $code_line_count = $line_count;
                #
                #コード格納領域の初期化
                #
                $code = "";
                #
                #フラグの初期化
                #
                $preprocessor_flg = FALSE;

                next;
            }
        }
        #「}」正規化判定文字の終了判定
        elsif($in_comment_flg == NOT_COMMENT
        and $code_char[$char_count] eq '}'){
            $brace_count--;
			get_loglevel() > 6 and print_log("(DEBUG 7) | $line_count : brace_count " . $brace_count);
            $code .= $code_char[$char_count];
            
            #
            # 構造体の処理中の場合は正規化判定文字としない
            #
            if($in_the_struct){
                $struct_brace_count--;
                next;
            }
            else{ 
                #
                #前後空白の削除
                #
                $code =~ s{\A \s*(.*)\s* \z}{$1}xms;
                
                #
                #コード情報の格納
                #
                push(@code_info,{line_number => $code_line_count, code_body => $code});
                get_loglevel() > 6 and print_log("(DEBUG 7) | " . $code_line_count . ": $code");
                
                #
                #格納した行を次の格納行番号として格納
                #
                $code_line_count = $line_count;
                
                #
                #コード格納領域の初期化
                #
                $code = "";

                #
                #フラグの初期化
                #
                $preprocessor_flg = FALSE;
                next;
            }
        }
        #「'」リテラルの開始判定
        elsif($in_comment_flg == NOT_COMMENT 
        and $code_char[$char_count] eq '\''){
            $in_comment_flg = SQL_LITERAL;
            $code .= $code_char[$char_count];
            next;
        }
        #「'」リテラルの終了判定
        elsif($in_comment_flg == SQL_LITERAL 
        and $code_char[$char_count] eq '\''){
            #「'」文字のエスケープ処理判定「\」
            if($code_char[$char_count-1] eq '\\') {
                $literal_buff .= $code_char[$char_count];
                next;
            }
            #「'」文字のエスケープ処理判定「'」
            elsif($code_char[$char_count+1] eq '\'') {
                $literal_buff .= $code_char[$char_count];
                $char_count++;
                $literal_buff .= $code_char[$char_count];
                next;
            }
            else{
                $in_comment_flg = NOT_COMMENT;
                #
                #リテラルをスタックに格納
                #
                if(${ $mode } ne MODE_SQL){
                    $code .= '"' .$G_literal_number;
                    $literal_stack->{'"' . $G_literal_number} = $literal_buff;
                    $G_literal_number++;
                    #
                    #リテラル一時保存領域の初期化
                    #
                    $literal_buff="";
                }
                $code .= $code_char[$char_count];
                next;
            }
        }
        #「"」リテラルの開始判定
        elsif($in_comment_flg == NOT_COMMENT 
        and $code_char[$char_count] eq '"'){
            $in_comment_flg = LITERAL;
            $code .= $code_char[$char_count];
            next;
        }
        #「"」リテラルの終了判定
        elsif($in_comment_flg == LITERAL 
        and $code_char[$char_count] eq '"'){
            #「"」文字のエスケープ処理判定
            if($code_char[$char_count-1] eq '\\') {
                $in_comment_flg = LITERAL_LITERAL;
                $literal_buff .= $code_char[$char_count];
                next;
            }
            else{
                $in_comment_flg = NOT_COMMENT;
                #
                #リテラルをスタックに格納
                #
                if(${ $mode } ne MODE_SQL){
                    $code .= '"' .$G_literal_number;
                    $literal_buff =~ s{(?:['][']|[\\]['])}{}xmsg;
                    $literal_buff =~ s{['].*?[']}{''}xmsg;
                    $literal_stack->{'"' . $G_literal_number} = $literal_buff;
                    $G_literal_number++;
                    #
                    #リテラル一時保存領域の初期化
                    #
                    $literal_buff="";
                }
                $code .= $code_char[$char_count];
                next;
            }
        }
        #「\」リテラル内リテラルの終了判定
        elsif($in_comment_flg == LITERAL_LITERAL 
        and $code_char[$char_count] eq '\\'
        and $code_char[$char_count+1] eq '"'){
            $in_comment_flg = LITERAL;
            $literal_buff .= $code_char[$char_count];
            $char_count++;
            $literal_buff .= $code_char[$char_count];
            next;
        }
        #「"」リテラル内リテラルの終了判定
        elsif($in_comment_flg == LITERAL_LITERAL
        and $code_char[$char_count] eq '"'){
            $in_comment_flg = NOT_COMMENT;
            #
            #リテラルをスタックに格納
            #
            if(${ $mode } ne MODE_SQL){
                $code .= '"' .$G_literal_number;
                $literal_buff =~ s{(?:['][']|[\\]['])}{}xmsg;
                $literal_buff =~ s{['].*?[']}{''}xmsg;
                $literal_stack->{'"' . $G_literal_number} = $literal_buff;
                $G_literal_number++;
                #
                #リテラル一時保存領域の初期化
                #
                $literal_buff="";
            }

            $code .= $code_char[$char_count];
            next;
        }
        #「#」前処理指令の判定
        elsif($in_comment_flg == NOT_COMMENT 
        and $code_char[$char_count] eq '#'){
            $preprocessor_flg = TRUE;
            $code .= $code_char[$char_count];
            next;
        }
        #「;」セミコロンの判定
        elsif($in_comment_flg == NOT_COMMENT 
        and $code_char[$char_count] eq ';'){
            $code .= $code_char[$char_count];
            #
            #構造体の解析中である場合は正規化判定文字としない
            #
            if($struct_brace_count > 0){
                next;
            }
            #
            #構造体のネスト数と構造体の解析状態を初期化
            #
            $struct_brace_count = 0;
            $in_the_struct = FALSE;
            
            #
            #前後空白の削除
            #
            $code =~ s{\A \s*(.*)\s* \z}{$1}xms;           

            #
            #コード情報の格納
            #
            push(@code_info,{line_number => $code_line_count, code_body => $code});
            get_loglevel() > 6 and print_log("(DEBUG 7) | " . $code_line_count . ": $code");

            #
            #格納した行を次の格納行番号として格納
            #
            $code_line_count = $line_count;

            #
            #コード格納領域の初期化
            #
            $code = "";

            #
            #フラグの初期化
            #
            $preprocessor_flg = FALSE;
            next;
        }
    
        #
        #通常の場合は文字を格納
        #
        if($in_comment_flg == NOT_COMMENT ) {
            $code .= $code_char[$char_count];
        }
        #
        #リテラル内の場合は一時バッファに文字を格納
        #
        elsif($in_comment_flg == LITERAL
        or $in_comment_flg == SQL_LITERAL ) {
            $literal_buff .= $code_char[$char_count];
        }
        elsif($code_char[$char_count] eq '\\') {
            $code .= $code_char[$char_count];
        }
    }#コードの正規化ループの終端
    
    get_loglevel() > 2 and print_log("(DEBUG 3) | [out] normalize_codes");
    return \@code_info;
}

#####################################################################
# Function: create_absolute_dictionary
#
#
# 概要:
#
# 動作モードが『埋め込みSQL抽出モード』の場合に使用する関数辞書を作成する。
# 
#
# パラメータ:
# encoding_name     - エンコード
# file_name         - ファイル名
# deffile_path      - 報告対象定義ファイルのパス
#
# 戻り値:
# function_hash      - 関数辞書
#
# 例外:
# なし
#
# 特記事項:
#
#
#####################################################################
sub create_absolute_dictionary{
    my ($encoding_name, $file_name, $include_dir_list, $deffile_path) = @_; #引数の格納

    my @varlist=();#プリプロセスdefine格納
    my $file_info=undef;#ファイル情報格納
    
    #
    # 中間ファイルの作成
    #
    my @intermediate_file_list = PgSqlExtract::Analyzer::PreprocessAnalyzer::preprocess_analyzer_prev($file_name, \@varlist, $encoding_name, $include_dir_list);

    #パーサの準備
    my $parser = get_c_parser($deffile_path);
    foreach my $intermediate_file_name (@intermediate_file_list){

        #
        # 入力ファイルを読み込む
        #
        my $c_strings = read_input_file($intermediate_file_name, $encoding_name);
    
        #
        # 入力ファイル内容をJavaパーサによりパースし、ファイル情報を取得する
        #
        $parser->{YYData}->{INPUT} = $c_strings;
        $file_info = $parser->Run();
    

        # ファイル名を取得する
        my $pre_filename = basename($intermediate_file_name);
        $pre_filename =~ m{(.*)_preprocess\.c$}xmg;
        $pre_filename = $1;

        #
        # 構文解析中にエラーが発生した場合は例外を送出する
        #
        $parser->{YYData}->{ERRMES} and do {
            undef $G_cparser;
            
            # typedefを空にする
            all_clear_typedef_name();  
            
            # エラーメッセージを表示する
            croak(sprintf($parser->{YYData}->{ERRMES}, $pre_filename));
        };
        #
        # ヘッダファイルの解析時は変数情報をdefine情報に追加する
        #
        if($pre_filename ne basename($file_name)){
            if(defined $file_info && defined $file_info->varlist()){
                my $var_tmp = $file_info->varlist();
                foreach my $var_info ( @$var_tmp ){
                    $var_info->linenumber($pre_filename . ":" .$var_info->linenumber());
                    push(@varlist,$var_info);
                }
            }
        }
        
    }
    clear_typedef_name(); # typedefの初期化する
    PgSqlExtract::Analyzer::PreprocessAnalyzer::set_pg_sqlextract_macro();# macroの初期化する
    if(!defined $file_info){
        $file_info=CFileInfo->new();
    }
    $file_info->filename($file_name);
    if(scalar @varlist > 0){
        if(!defined $file_info->varlist()){
            $file_info->varlist([@varlist]);
        }else{
            my $varlist_tmp = $file_info->varlist();
            foreach my $var_info ( @varlist ){
                my $much_flg=1;
                foreach my $func_var_info ( @$varlist_tmp ){
                    if($func_var_info->name() eq $var_info->name()){
                        $much_flg=0;
                        last;
                    }
                }
                if($much_flg){
                    push(@$varlist_tmp,$var_info);
                }
            }
        }
    }
    
    return $file_info;
}

#####################################################################
# Function: create_simple_dictionary
#
#
# 概要:
#
# 動作モードが『埋め込みSQL抽出モード』以外の場合に使用する関数辞書を作成する。
# 
#
# パラメータ:
# code_data         - コード情報
# file_name         - ファイル名
#
# 戻り値:
# function_hash      - 関数辞書
#
# 例外:
# なし
#
# 特記事項:
#
#
#####################################################################
sub create_simple_dictionary{
    my ($code_data, $file_name) = @_; #引数の格納
    my %function_hash = ();#関数辞書ハッシュ
    my $function_name = $file_name."=".GLOBAL;

    #
    #1関数辞書の作成
    #           
    $function_hash{$function_name} = set_function_init_data_storage_function($function_name, "", $file_name);

    #
    #コード情報の登録
    #           
    $function_hash{$function_name}->{code_info} = $code_data;
    
    return \%function_hash;
}

#####################################################################
# Function: set_function_init_data_storage_function
#
#
# 概要:
#
# 1関数辞書のハッシュを作成し返却する。
# 
# パラメータ:
# function_name     - 関数名
# argument_declare  - 引数
# file_name         - ファイル名
#
# 戻り値:
# function_hash - 1関数のハッシュのリファレンス
#
# 例外:
# なし
#
# 特記事項:
#
#
#####################################################################
sub set_function_init_data_storage_function{
    my ($function_name, $argument_declare, $file_name) = @_; #引数の格納
    my %function_hash = (); #1関数辞書のハッシュ
    
    #
    #1関数辞書のハッシュに情報を格納
    #
    $function_hash{file_name} = $file_name;
    $function_hash{function_name} = $function_name;

    my @params_list = split(/,+/,$argument_declare);  
    for my $param (@params_list) {
        $param =~ s{\s+ \z}{}xms;
        $param =~ s{\A .* \s ([^\s]+) \z}{$1}xms;
        $param =~ s{[][*]}{}xmsg;
    }
    

    $function_hash{params_list} = \@params_list;
    #
    #ファイル種別の判定
    #
    if($file_name =~ m{[.]h\s*$}xms){
        $function_hash{file_type} = FILETYPE_HEADER;
    }
    else{
        $function_hash{file_type} = FILETYPE_OTHER;
    }
    return \%function_hash;
}

#####################################################################
# Function: get_c_parser
#
#
# 概要:
#
# Cパーサオブジェクトを返却する。
# オブジェクトが生成されていない場合は
# 新規にパーサを生成し、
# Cの標準ヘッダとProCの型定義ファイルからtypedef宣言の型情報を取得する。
# 
#
# パラメータ:
# deffile_path      - 報告対象定義ファイルのパス
#
# 戻り値:
# $G_cparser  - Cパーサオブジェクト
#
# 例外:
# なし
#
# 特記事項:
# - Cパーサオブジェクトは、グローバル変数 G_cparserに格納する。
#
#####################################################################
sub get_c_parser {
    my ($deffile_path) = @_; #引数の格納
    
    if(!defined $G_cparser) {
        $G_cparser = PgSqlExtract::Analyzer::CParser->new();
        $G_cparser->{YYData}->{loglevel} = get_loglevel();
        read_standard_type($deffile_path);
    }
    return $G_cparser;
}

#####################################################################
# Function: read_standard_type
#
#
# 概要:
# Cの標準ヘッダとProCの型定義ファイルを読み込み
# typedef宣言の型情報を取得する。
#
#
# パラメータ:
# deffile_path      - 報告対象定義ファイルのパス
#
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
sub read_standard_type {
    my ($deffile_path) = @_; #引数の格納
    
    #
    # Cの標準ヘッダとProCの型定義ファイルを検索
    # -dオプションで指定したパスを検索する
    # ファイルを検索できなかった場合、その旨を表示する
    # ファイルを検索できた場合、型定義ファイルを読み込み、処理を続行する
    #
    my $define_type_file = $deffile_path . "/define_type.txt";
    
    if(!(-e $define_type_file)) {
       get_loglevel() > 0 and print_log("(INFO) | loading define_type file: No such file $define_type_file");
       get_loglevel() > 0 and print_log("(INFO) | loading define_type file: No loading define_type file");
    }
    elsif(!(-r $define_type_file)) {
       get_loglevel() > 0 and print_log("(INFO) | loading define_type file: Access denied $define_type_file");
       get_loglevel() > 0 and print_log("(INFO) | loading define_type file: No loading define_type file");
    }
    else{
        get_loglevel() > 0 and print_log("(INFO) | loading define_type file: loading $define_type_file");
        
        #標準ヘッダの型定義ファイル読み込み
        open(IN, "<:encoding(utf8)", "$define_type_file");
        
        #他のtypedef型宣言と区別するためのフラグ
        my $flag = 1;
        
        while(my $line = readline IN){
            chomp $line;
            
            # タブを半角スペースに変換
            $line =~ s{\t}{ }xmg;
            
            # #で始まる行または空行を読み込まないための処理
            if($line !~ m{^\s*\#}xmg and $line ne ""){ 
            
                $line =~ m{^\s*(\S+)\s*}xmg;
                
                my @tname=('',$1);
                
                #型をハッシュに格納するための関数呼び出し
                set_typedefname(@tname,$flag);
            }
            
        }
        close(IN);
     }
     
}

1;
