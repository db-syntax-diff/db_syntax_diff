#!/usr/bin/perl
#############################################################################
#  Copyright (C) 2010-2011 NTT
#############################################################################

#####################################################################
# Function: PreprocessAnalyzer.pm
#
#
# 概要:
# C言語のプリプロセスの構文解析を行う。
#
# 特記事項:
# なし
#
#####################################################################
package PgSqlExtract::Analyzer::PreprocessAnalyzer;
use Carp;
use File::Path;
use File::Basename;
use File::Spec::Unix;
use PgSqlExtract::Common;
use utf8;

our @EXPORT_OK = qw( prepare_intermediate_file_list set_pg_sqlextract_macro include_file_hash_call return_parse_enc);
#ファイルハンドル
my $fh_read_def = READ;
my $fh_out_def = OUT;
#ファイルハンドルカウンタ
my $count;

#ネストの深さ
my $depth;

#includeファイルのリスト（連想配列 key:ファイル名 value:中間ファイルの相対パス）
my %include_file_hash = ();

#二重インクルード対策用の配列
my @input_filelist=();
my $input_filelist_ref = \@analyzed_file_list;
my $parse_enc; #Parser用のエンコーディング情報
#プリプロセスのパターン
#if_group => #if|#ifdef|#ifndef
#elif_group => #elif
#else_group => #else
#endif_line => #endif
#control_line_define => #define
#control_line_others => #include|#undef|#line|#error|#pragma|#
#環境変数名
my $env_ifgroup = "PG_SQLEXTRACT_MACRO";
my @ifgroup_config = split(/\,/ , $ENV{$env_ifgroup});
#環境変数の設定方法
#export PG_SQLEXTRACT_MACRO=文字列A,文字列B

#####################################################################
# Function: include_file_hash_call
#
# 概要：
# Parserの再帰処理時にIncludeファイルの中間ファイルの置き場所を
# 指定するために使う。
# Parserでの利用のみを考えている。
#
#####################################################################

sub include_file_hash_call{
    my ($include_file_name_for_Parser) = @_;
    return $include_file_hash{$include_file_name_for_Parser};
}

#####################################################################
# Function: prepare_intermediate_file_list
#
#
# 概要:
# 本モジュールの入り口となる関数。
# カウントの初期化、プリプロセスの構文解析が終わったファイルの名前を
# 管理するリスト（配列）の宣言を行う。
# また、Perlの仕様上、リスト（配列）はリファレンス化し、サブルーチンに
# 引数として渡している。
#
# パラメータ：
# count - ファイルハンドル用のカウンタ（グローバル変数）
# depth - ネストの深さ用のカウンタ（グローバル変数）
# analyzed_flie_list - プリプロセス処理済みのファイル名のリスト
# analyzed_file_list_ref - 上記リストのリファレンス
# 
# 戻り値：
# @{$analyzed_file_list_ref} - リファレンスの実体（配列）
#
# 例外：
# なし
#
# 特記事項:
# なし
#
#
#####################################################################
sub prepare_intermediate_file_list {
    my ($filename, $varlist, $encoding_name, $include_dir_list) = @_;

    #グローバルで宣言しているファイルハンドルのカウントを初期化する。
	$count=0;
    #グローバルで宣言しているネストの深さのカウントを初期化する。
	$depth=0;

    #構文解析が終わったファイルの名前を格納するための配列を宣言する。
	my @analyzed_file_list=();

    #配列のリファレンスを作成する。以降の関数では引数としてリファレンスを渡す。
    ##配列のリファレンスを作成する理由
    # 呼び出した関数（サブルーチン）は与えられた引数の全てを配列"@_"に格納するため、
    # 引数に配列の実体を与えると配列の区切りがなくなってしまい、サブルーチン内で正しく
    # 配列を受け取ることができなくなる。
    my $analyzed_file_list_ref = \@analyzed_file_list;
    $parse_enc=$encoding_name;
    #二重インクルード予防のための入力ファイルリスト用配列を初期化する。
    @input_filelist=();
    $input_filelist_ref = \@analyzed_file_list;

	#中間ファイルを作成する関数を呼び出す
    $analyzed_file_list_ref=preprocess_analyzer_prev($filename, $varlist, $encoding_name, $include_dir_list, $analyzed_file_list_ref);

    #デリファレンスし、実体（配列）に戻し、最後の要素（ソースの中間ファイルのフルパス）を返却する。
    return pop @{$analyzed_file_list_ref};
}


#####################################################################
# Function: preprocess_analyzer_prev
#
#
# 概要:
# C言語ファイル名をもとに中間ファイルを作成する。
# その後、C言語のプリプロセスの構文解析を行い、解析結果を中間ファイルに出力する。
# また、プリプロセスのマクロの変数情報を変数情報のリストに格納する。
#
# パラメータ:
# filename - C言語ファイル名
# varlist - 変数情報のリスト(出力用)
# fh_read - 入力ファイルのファイルハンドル(グローバル変数)
# fh_out - 中間ファイルのファイルハンドル(グローバル変数)
# 
#
# 戻り値:
# filepath - プリプロセス解析後のC言語ファイル名
#
# 例外:
# なし
#
# 特記事項:
# なし
#
#
#####################################################################
sub preprocess_analyzer_prev {
	my ($filename, $varlist, $encoding_name, $include_dir_list, $analyzed_file_list_ref) = @_;
	my $filename_buff = $filename;

	#filenameからファイルパスとファイル名を分割する
	my $filedir = dirname($filename);
	if($filedir ne '\.'){
		$filename_buff =~ s{$filedir/}{}xmg;
	}
	$filedir = File::Spec::Unix->rel2abs($filedir);
	$filedir =~ s{^.*?/}{}xmg;

	my $output_filename = $filename_buff . "_preprocess.c";
	
	my $output_dir = ANALYZE_TEMPDIR . $filedir;
	
	#中間ファイルの作成
    if(!-d $output_dir){
    	mkpath($output_dir) or croak "mkpath create error $output_dir($!)";
    }
	open($fh_out_def, ">:encoding($encoding_name)", "$output_dir/$output_filename") or croak "File open error $output_dir/$output_filename($!)\n";
	close($fh_out_def);

	#ファイルハンドルの作成
    my $fh_read="$fh_read_def$count";
	my $fh_out="$fh_out_def$count";

	#ファイルのオープン
	open($fh_read, "<:encoding($encoding_name)", "$filename") or croak "File open error $filename($!)\n";
	open($fh_out, ">>:encoding($encoding_name)", "$output_dir/$output_filename") or croak "File open error $output_dir/$output_filename($!)\n";

	#プリプロセスの構文解析
	$analyzed_file_list_ref=preprocess_analyzer($fh_out, $fh_read, $varlist, $filename, $encoding_name, $include_dir_list,$analyzed_file_list_ref);

    #変数の値を修正する。hoge//huge.c -> hoge/hyge.c に修正する。
    my $output_filepath = "$output_dir/$output_filename";
    $output_filepath =~ s/\/\//\//g;

	#構文解析の終わったファイル名を配列に追加する
    push(@{$input_filelist_ref},$filename);
    push(@{$analyzed_file_list_ref},$output_filepath);

    #includeファイルだけのリスト（連想配列）を作成する。あとで、CParser.pmから参照する。
    #但し、同じ名称のヘッダファイルが存在する場合、valueが上書きされるため、WARNログを出力する。
    if(exists $include_file_hash{basename($filename)}){
        print_log("(WARN) | value of hash was overwritten.");
    }
    $include_file_hash{basename($filename)} = "$output_filepath"if(!$depth == 0);
	#ファイルのクローズ
	close($fh_read);
	close($fh_out);

	return $analyzed_file_list_ref;

}

#####################################################################
# Function: preprocess_analyzer
#
#
# 概要:
# 入力ファイルのソースを１行ずつ判定する。
# 判定した結果、プリプロセスの場合は改行に置換する。
# さらに、ifグループ、マクロに該当した場合は、解析処理を行う。
# また、プリプロセス以外の場合はそのまま中間ファイルに出力する。
#
# パラメータ:
# fh_read - 入力ファイルのファイルハンドル(グローバル変数)
# fh_out - 中間ファイルのファイルハンドル(グローバル変数)
# varlist - 変数情報のリスト(出力用)
#
# 戻り値:
# なし
#
# 例外:
# なし
#
# 特記事項:
# ifグループ内、または、マクロの処理中の行に関しては
# 他の関数で処理をしているため、ここでの処理は行っていない。
#
#
#####################################################################
sub preprocess_analyzer {
	my ($fh_out, $fh_read, $varlist, $filename, $encoding_name, $include_dir_list, $analyzed_file_list_ref) = @_;
	
	#if_groupの条件
	my $ifgroup_condition = "";
	
	#入力ファイルのソースを１行ずつ解析
	while( my $line = readline $fh_read ){ 
	
		#if_groupの場合
		if( $line =~ m{^\s*(\#\s*if\s+\S+|\#\s*ifdef\s+\S+|\#\s*ifndef\s+\S+)}xmg ){
			print $fh_out "\n";
			$ifgroup_condition = if_group_condition_analyzer($line);
			$analyzed_file_list_ref=if_group_analyzer($fh_out, $fh_read, $ifgroup_condition, 1, $varlist, $filename, $encoding_name, $include_dir_list, $analyzed_file_list_ref);
		}
		#control_line(define)の場合
		elsif( $line =~ m{^\s*\#\s*define\s*(.*)}xmg ){
			print $fh_out "\n";
			define_analyzer($fh_out, $fh_read, $1, $varlist, $filename);
		}
		#control_line(include"")の場合
		elsif( $line =~ m{^\s*\#\s*include\s*["](.*\.h)["]}xmg ){

            #パターンマッチしたincludeファイルの名前を変数に格納する。 
            my $include_file_name = $1;

            #Parser用の二重インクルード対策
            my @line_block = split(/"/,$line);
            my $include_block = @line_block[1]."_preprocess.c";
            if (!grep /\S*$include_block$/,@{$analyzed_file_list_ref}){

                #$lineを"#"で検索し、postmatch部分(#以降の文字列'include"hoge.h"')を$lineに代入する。
                #処理内容：$line = #include"hoge.h" -> $line = include"hoge.h"
                $line =~ m/\#/;
                $line = $';

                #CParser.yp内で再帰的にParserを呼び出す際にトリガーとなるTOKENに置き換える
                #INCLUDEFORPARSE_TOKENと、STRING_LITERAL("を含むTOKEN)の形に整形している。
                #処理内容：$line = include"hoge.h" -> $line = includefordbsyntaxdiff"hoge.h"
                $line =~ s/include/includefordbsyntaxdiff/;

                #includefordbsyntaxdiff"hoge.h"が中間ファイルに出力される。
                print $fh_out $line;

            }else{
                #既に処理済みのIncludeであれば、改行のみ出力する。
                print $fh_out "\n";
            }

            $analyzed_file_list_ref = include_analyzer($include_file_name, $varlist, $filename, $encoding_name, $include_dir_list, $analyzed_file_list_ref);
        }
		#control_line(include<>)の場合
		elsif( $line =~ m{^\s*\#\s*include\s*[<](.*\.h)[>]}xmg ){
			print $fh_out "\n";
			get_loglevel() > 0 and print_log("(INFO) | No analyze include file: filename=$1 analyze_file=$filename:$.");
		}
		#control_line(others)の場合
		elsif( $line =~ m{^\s*(\#\s*undef|\#\s*line|\#\s*error|\#\s*pragma|\#\s*)}xmg ){
			print $fh_out "\n";
		}
		#該当なしの場合
		else{
			print $fh_out $line;
		}
	}
    return $analyzed_file_list_ref;
}

#####################################################################
# Function: if_group_analyzer
#
#
# 概要:
# ifグループの条件がマッチしているかどうか判定し、以降処理するか否かのフラグを設定する。
# endifが見つかるまで、入力ファイルのソースを１行ずつ解析する。
# 解析中、プリプロセスの場合、プリプロセスの場合は改行に置換し、その種類に合った解析を行う。
# また、プリプロセス以外の場合はそのまま中間ファイルに出力する。
#
# 以降処理するか否かのフラグは2種類ある。
#   処理フラグ：Cソースとして有効かのフラグ、無効時は中間ファイルとしては空行に変換する
#   マッチフラグ：ifの条件判定に一度でもマッチしたのかのフラグ
#
# パラメータ:
# pre_ifgroup_condition - ifグループの条件
# pre_exec_flg - ifがネストしている場合の親スコープでの処理フラグ
# fh_read - 入力ファイルのファイルハンドル(グローバル変数)
# fh_out - 中間ファイルのファイルハンドル(グローバル変数)
# varlist - 変数情報のリスト(出力用)
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
sub if_group_analyzer {
	my ($fh_out, $fh_read, $pre_ifgroup_condition, $pre_exec_flg, $varlist, $filename, $encoding_name, $include_dir_list, $analyzed_file_list_ref) = @_;
		
	#処理フラグ
	my $exec_flg= 1;

	#マッチフラグ
	my $match_flg= 0;
	
	#if_groupの条件
	my $ifgroup_condition = "";
	
	#条件とマッチした結果
	my $match_result = undef;
	
	#条件にマッチするかチェック
	$match_result = if_condition_match($pre_ifgroup_condition);
	if( $match_result ){ 
		$exec_flg = 1;
		$match_flg = 1;
	}
	else{
		$exec_flg = 0;
		$match_flg = 0;	
	}

	#endif_lineを見つけるまでループ
	while( my $line = readline $fh_read ){ 

		#親スコープで処理を行っている場合
		if( $pre_exec_flg == 1){
			#elif_groupの場合
			if( $line =~ m{^\s*\#\s*elif\s+(.+)}xmg ){
				print $fh_out "\n";
				if($match_flg == 0){
					$ifgroup_condition = if_condition_analyzer($1);
					#条件にマッチするかチェック
					$match_result = if_condition_match($ifgroup_condition);
					if( $match_result ){ 
						$exec_flg = 1;
						$match_flg = 1;
					}
					else{
						$exec_flg = 0;
					}
				}
				else{
					$exec_flg = 0;
				}
			}
			#else_groupの場合
			elsif( $line =~ m{^\s*\#\s*else}xmg ){
				print $fh_out "\n";
				if($match_flg == 0){
					$exec_flg = 1;
				}
				else{
					$exec_flg = 0;
				}
			}
			#endif_lineの場合
			elsif( $line =~ m{^\s*\#\s*endif}xmg ){
				print $fh_out "\n";
				last;
			}	
			#if_groupの場合
			elsif( $line =~ m{^\s*(\#\s*if\s+\S+|\#\s*ifdef\s+\S+|\#\s*ifndef\s+\S+)}xmg ){
				print $fh_out "\n";
				$ifgroup_condition = if_group_condition_analyzer($line);
				$analyzed_file_list_ref=if_group_analyzer($fh_out, $fh_read, $ifgroup_condition, $exec_flg, $varlist, $filename, $encoding_name, $include_dir_list, $analyzed_file_list_ref);
			}
			#control_line(define)の場合
			elsif( $line =~ m{^\s*\#\s*define\s*(.*)}xmg ){
				print $fh_out "\n";
				if($exec_flg == 1){
					define_analyzer($fh_out, $fh_read, $1, $varlist, $filename);
				}
			}
			#control_line(include"")の場合
			elsif( $line =~ m{^\s*\#\s*include\s*["](.*\.h)["]}xmg ){

                #パターンマッチしたincludeファイルの名前を変数に格納する。 
                my $include_file_name = $1;

                #Parser用の二重インクルード対策
                my @line_block = split(/"/,$line);
                my $include_block = @line_block[1]."_preprocess.c";
                if($exec_flg ==1){
                    if (!grep /\S*$include_block$/,@{$analyzed_file_list_ref}){

                        #$lineを"#"で検索し、postmatch部分(#以降の文字列'include"hoge.h"')を$lineに代入する。
                        #処理内容：$line = #include"hoge.h" -> $line = include"hoge.h"
                        $line =~ m/\#/;
                        $line = $';

                        #CParser.yp内で再帰的にParserを呼び出す際にトリガーとなるTOKENに置き換える
                        #INCLUDEFORPARSE_TOKENと、STRING_LITERAL("を含むTOKEN)の形に整形している。
                        #処理内容：$line = include"hoge.h" -> $line = includefordbsyntaxdiff"hoge.h"
                        $line =~ s/include/includefordbsyntaxdiff/;

                        #includefordbsyntaxdiff"hoge.h"を中間ファイルに出力する。
                        print $fh_out $line;

                    }else{
                        #既に処理済みのIncludeファイルであれば、改行のみ出力する。
                        print $fh_out "\n";
                    }
                }else{
                    #実行しないifグループは改行を出力する
                    print $fh_out "\n";
                }

				if($exec_flg == 1){
					$analyzed_file_list_ref = include_analyzer($include_file_name, $varlist, $filename, $encoding_name, $include_dir_list, $analyzed_file_list_ref);
				}
			}
			#control_line(include<>)の場合
			elsif( $line =~ m{^\s*\#\s*include\s*[<](.*\.h)[>]}xmg ){
				print $fh_out "\n";
				if($exec_flg == 1){
					get_loglevel() > 0 and print_log("(INFO) | No analyze include file: filename=$1 analyze_file=$filename:$.");
				}
			}
			#control_line(others)の場合
			elsif( $line =~ m{^\s*(\#\s*undef|\#\s*line|\#\s*error|\#\s*pragma|\#\s*)}xmg ){
				print $fh_out "\n";
			}
			#該当なしの場合
			else{
				if($exec_flg == 1){
					print $fh_out $line;
				}
				else{
					print $fh_out "\n";
				}
			}
		 }
		 #親スコープで処理を行っていない場合
		 else{
		 	#endif_lineの場合
	   	 	if( $line =~ m{^\s*\#\s*endif}xmg ){
				print $fh_out "\n";
				last;
			}
			#if_groupの場合
			elsif( $line =~ m{^\s*(\#\s*if\s+\S+|\#\s*ifdef\s+\S+|\#\s*ifndef\s+\S+)}xmg ){
				print $fh_out "\n";
				$ifgroup_condition = if_group_condition_analyzer($line);
				$analyzed_file_list_ref=if_group_analyzer($fh_out, $fh_read, $ifgroup_condition, $exec_flg, $varlist, $filename, $encoding_name, $include_dir_list, $analyzed_file_list_ref);
			}
			#endif_lineでない場合
			else{
				print $fh_out "\n";
			}
	   	 }
   	 }
	return $analyzed_file_list_ref;
}

#####################################################################
# Function: if_group_condition_analyzer
#
#
# 概要:
# ifグループの種類に合わせて条件を整形する。
# if、ifdef、ifndefに該当する場合、その条件に合わせた形にif条件を整形する。
#
# パラメータ:
# ifgroup_line - ifグループの行
#
# 戻り値:
# ifgroup_condition - 整形したifグループの条件
#
# 例外:
# なし
#
# 特記事項:
# なし
#
#
#####################################################################
sub if_group_condition_analyzer {
	my ($ifgroup_line) = @_;

	#if_groupの条件
	my $ifgroup_condition = "";

	#コメント/* */があったら削除する
	$ifgroup_line =~ s{\/\*.*?\*\/}{}xmg;
	
	#ifの場合
	if( $ifgroup_line =~ m{^\s*\#\s*if\s+(.+)}xmg ){
		$ifgroup_condition = if_condition_analyzer($1);
	}
	#ifdefの場合
	elsif( $ifgroup_line =~ m{^\s*\#\s*ifdef\s+(.+)}xmg ){
		$ifgroup_condition = $1;
	}
	#ifndefの場合
	elsif( $ifgroup_line =~ m{^\s*\#\s*ifndef\s+(.+)}xmg ){
		$ifgroup_condition = "\!" .$1;
	}

	return $ifgroup_condition;
}

#####################################################################
# Function: if_condition_analyzer
#
#
# 概要:
# ifの条件の種類に合わせて条件を整形する。
# 条件がdefine、!define、「0」か「1」の数値に該当する場合、その条件に合わせた形にifの条件を整形する。
# また該当しない場合、if条件を空文字に整形する。
#
# パラメータ:
# if_condition - if条件
#
# 戻り値:
# if_condition - 整形したif条件
#
# 例外:
# なし
#
# 特記事項:
# なし
#
#
#####################################################################
sub if_condition_analyzer {
	my ($if_condition) = @_;
	
	#if_defineの場合
	if( $if_condition =~ m{^defined\s*\(\s*(\S+)\s*\)$}xmg ){
		$if_condition = $1;	
	}
	#if_!defineの場合
	elsif( $if_condition =~ m{^\!defined\s*\(\s*(\S+)\s*\)$}xmg ){
		$if_condition = "\!" . $1;	
	}
	#if_数値（0 or 1）の場合
	elsif( $if_condition =~ m{^([01])$}xmg ){
		$if_condition = $1;
	}
	#その他
	else{
		$if_condition = "";
	}

	return $if_condition;

}

#####################################################################
# Function: if_condition_match
#
#
# 概要:
# ifグループの条件がマッチしているか判定する。
# ifグループの条件が文字列の場合、環境変数で設定した変数名のリストにその文字列があるか判定する。
# ただし、否定条件の場合は、先頭の「!」を削除して判定し、マッチしない場合に結果を真とする。
# ifグループの条件が数値の場合、0かどうか判定する。
#
# パラメータ:
# if_condition - 整形されたifグループの条件
# ifgroup_config - 環境変数で設定した変数名のリスト(グローバル変数)
#
# 戻り値:
# match_result - マッチ判定の結果
#
# 例外:
# なし
#
# 特記事項:
# なし
#
#
#####################################################################
sub if_condition_match {
	#if(or elif)の条件($if_condition) #先頭が「!」の場合は否定条件
	my ($if_condition) = @_;
	
	#条件にマッチした結果
	my $match_result = undef;
	
	#否定条件の場合
	if( $if_condition =~ m{^!}xmg ){
		
		#「!」の削除
		$if_condition = substr($if_condition,1);
		
		#条件が数値の場合
		if( $if_condition =~ m{^[0-9]+}xmg ){
			if( $if_condition ne 0 ){
				$match_result = 0;
			}
			else{
				$match_result = 1;
			}
		}
		#条件が文字列の場合
		else{
			my @match_string = ();
			@match_string = grep($_ eq $if_condition , @ifgroup_config);
			if(!@match_string){
				$match_result = 1;
			}
			else{
				$match_result = 0;
			}
		}
	}
	#通常条件の場合
	else{
		#条件が数値の場合
		if( $if_condition =~ m{^[0-9]+}xmg ){
			if( $if_condition eq 0 ){
				$match_result = 0;
			}
			else{
				$match_result = 1;
			}
		}
		#条件が文字列の場合
		else{
			my @match_string = ();
			@match_string = grep($_ eq $if_condition , @ifgroup_config);
			if(@match_string){
				$match_result = 1;
			}
			else{
				$match_result = 0;
			}
		}
	}

	return $match_result;

}

#####################################################################
# Function: define_analyzer
#
#
# 概要:
# define以降の文字列のコメントを削除する。
# その際、文字列の最後に「\」が記述されていた場合、次の行も解析を行う。
# 整形したdefine以降の文字列からマクロの種類を判定し、その種類に合った解析を行う。
#
# 上記を次の順序で処理を行う。
#  - define以降の文字列にリテラルがあった場合、リテラルを退避する。
#  - define以降の文字列内のコメントを削除、または「\」に置換する。
#  - define以降の文字列の末尾に「\」がある場合は、「\」を削除し次の行もdefine以降の文字列として扱う。
#    その際、中間ファイルに空行を出力する。以降、「\」が末尾になくなるまで繰り返し処理する。
#  - 退避したリテラルを戻す。
#  - マクロ、または、マクロ関数に該当した場合は解析処理を行う。
#
# パラメータ:
# define_restring - define以降の文字列
# varlist - 変数情報のリスト(出力用)
#
# 戻り値:
# なし
#
# 例外:
# なし
#
# 特記事項:
# コメントの「/* */」内に「"」が記述されている場合、正確な解析を行えない可能性がある。
#
#
#####################################################################
sub define_analyzer {
	my ($fh_out, $fh_read, $define_restring, $varlist, $filename) = @_;
	
	#define解析結果一つのメモリ格納
	my $define_macro_function_one_result = undef;
	my $define_macro_one_result = undef;
	
	my @literal_list = ();
	
	my $comment_flg = 0 ;
	
	#defineの行数を取得する
	my $linenumber = $.;
	
	#リテラルを取得し、置き換える
	create_literal_list( \$define_restring , \@literal_list );

	#コメントを削除（または\に置換）する
	comment_delete( \$define_restring , \$comment_flg );

	#\が最後に記述された場合、次の行もdefine_restringとして扱う
	if ( $define_restring =~ m{\\\s*$}xmg ){
		
		#\を削除する
		$define_restring =~ s{\\\s*$}{}xmg;
		
		while( my $line = readline $fh_read ){
			print $fh_out "\n";
        	#フラグがONの場合、*/までを削除し、フラグをOFFにする
        	#*/がなかった場合、全ての行を\に置き換える
        	if($comment_flg == 1){
        		if($line !~ m{^.*?\*\/}xm){
        			$line = "\\";
        		}
        		else{
        			$line =~ s{^.*?\*\/}{}xm;
        			$comment_flg = 0;
        		}
        	}
			#マクロ関数の文字列として連結
			$define_restring =  $define_restring . $line;
			#リテラルを取得し、置き換える
			create_literal_list( \$define_restring , \@literal_list );
			#コメントを削除（または\に置換）する
			comment_delete( \$define_restring , \$comment_flg );

			if ( $define_restring !~ m{\\\s*$}xmg ){
				last;
			}
			else{
				#\を削除する
				$define_restring =~ s{\\\s*$}{}xmg;
			}
		}
	}	
	
	#リテラルをdefine_restringにもとに戻す
	for( my $i=0; $i<@literal_list; $i++){
		my $reliteral = $literal_list[$i];
		$define_restring =~ s{\#$i}{$reliteral}xmg;
	}
	
	#マクロ関数の場合
	if( $define_restring =~ m{^\S+\s*\(}xmg ){
		define_macro_functoin_analyzer($define_restring , $linenumber);
	}
	#マクロ変数の場合
	elsif( $define_restring =~ m{^\S+}xmg ){
		define_macro_analyzer($define_restring , $linenumber, $varlist, $filename);
	}
	#マクロ変数or関数以外の場合
	else{

	}
	

}

#####################################################################
# Function: define_macro_analyzer
#
#
# 概要:
# マクロの解析を行う。。
# グローバル変数の変数情報のリストに解析結果を格納する
#
# 上記を次の順序で処理を行う。
#  - define以降の文字列からマクロ名と値を取得する。
#  - グローバル変数の変数情報のリストに解析結果を格納する。
#    その際、型名をundef、宣言種別をTYPE_DEFINEで格納する
#
# パラメータ:
# define_restring - define以降の文字列
# linenumber - 行数
#
# 戻り値:
# varlist_ref - プリプロセスの変数情報のリスト(グローバル変数)
# varlist - 変数情報のリスト(出力用)
#
# 例外:
# なし
#
# 特記事項:
# なし
#
#
#####################################################################
sub define_macro_analyzer {
	my ($define_restring , $linenumber, $varlist, $filename) = @_;

	my $macro_variable_name = undef;
	my $macro_variable_value = undef;

	#マクロ名と値の取得
	if($define_restring =~ m{^(\S+)\s+(.*)\s*$}xmg){
		$macro_variable_name = $1;
		$macro_variable_value = Token->new(token => $2);
		#ヘッダファイルのマクロか判定
        if($ARGV[0] eq $filename){
            $linenumber = $linenumber;
        }else{
            # ファイル名を取得する
            my $filename_tmp = basename($filename);
            $linenumber = $filename_tmp . ":" . $linenumber;
        }
	}
	elsif($define_restring =~ m{^(\S+)\s*$}xmg){
		$macro_variable_name = $1;
		$macro_variable_value = Token->new(token => "");
	}

	#データの格納
	my $var = CVariableInfo->new(name => $macro_variable_name, type => RESTYPE_CHAR, linenumber => $linenumber, declarationType => TYPE_DEFINE, value => [$macro_variable_value]);
	push ( @{ $varlist } , $var );
	#ifの条件にマクロ名を追加
	push ( @ifgroup_config , $macro_variable_name );
}

#####################################################################
# Function: define_macro_functoin_analyzer
#
#
# 概要:
# マクロ関数の解析を行う。
# マクロ関数はデータ構造に格納しない。
#
# パラメータ:
# define_restring - define以降の文字列
# linenumber - 行数
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
sub define_macro_functoin_analyzer {
	my ($define_restring , $linenumber) = @_;

	#マクロ関数はデータ構造に格納しない
	
}

#####################################################################
# Function: create_literal_list
#
#
# 概要:
# define以降の文字列に記述されているリテラルを取得する。
#
# 上記を次の順序で処理を行う。
#  - ""で囲まれた文字列をリテラルのリストに格納する。
#  - ""で囲まれた文字列を「#数値(0～)」に置換する。
#
# パラメータ:
# define_restring - define以降の文字列(出力用)
# literal_list - リテラルのリスト(出力用)
#
# 戻り値:
# define_restring - define以降の文字列
# literal_list - リテラルのリスト
#
# 例外:
# なし
#
# 特記事項:
# なし
#
#
#####################################################################
sub create_literal_list {
	my ($define_restring , $literal_list) = @_;
	
	my $literal_count_prev = $#{$literal_list} + 1;
	my $literal_count = $literal_count_prev;
	
	#リテラルを取得する
	map {
		++$literal_count;
		push( @{$literal_list} , $_);
	} ($$define_restring =~ m{\"(.*?)\"}xmg);
	
	#リテラルを#数値に置き換える
	for(my $i=$literal_count_prev; $i<$literal_count; $i++){
		$$define_restring =~ s{\".*?\"}{\#$i}xm;
	}
	
}

#####################################################################
# Function: comment_delete
#
#
# 概要:
# define以降の文字列に記述されているコメントを削除する。
# コメント内に改行が記述されている場合、「\」に置換する。
#
# 上記を次の順序で処理を行う。
#  - コメントが「/* */」で囲まれた文字列を削除する。
#  - コメントの「/*」がある場合、以降を「\」に置換し、コメントのフラグをONにする。
#
# パラメータ:
# define_restring - define以降の文字列(出力用)
# comment_flg - コメントのフラグ(出力用)
#
# 戻り値:
# define_restring - define以降の文字列
# comment_flg - コメントのフラグ
#
# 例外:
# なし
#
# 特記事項:
# なし
#
#
#####################################################################
sub comment_delete {
	my ($define_restring , $comment_flg) = @_;
	#コメント/* */があったら削除する
	$$define_restring =~ s{\/\*.*?\*\/}{}xmg;
	
	#コメント/* があったらフラグをONし、改行までを\に置き換える
    if($$define_restring =~ m{\/\*.*$}xm){
    	$$comment_flg = 1;
    	$$define_restring =~ s{\/\*.*$}{\\}xm;
    }
}

#####################################################################
# Function: include_analyzer
#
#
# 概要:
# includeファイルに記述されているtypedef文を1行にまとめて返却する。
#
# 上記を次の順序で処理を行う。
#
# パラメータ:
#
# 戻り値:
#
# 例外:
# なし
#
# 特記事項:
# なし
#
#
#####################################################################
sub include_analyzer {
	my ($include_restring, $varlist, $filename, $encoding_name, $include_dir_list, $analyzed_file_list_ref) = @_;
	
	my $includefilename=search_includefile($include_restring, $filename, $include_dir_list);

	if(!defined $includefilename){
	    return;
	}
	
	my $includefilename_prev = "./.pg_sqlextract_tmp/" . $includefilename . "_preprocess.c";
    $includefilename_prev =~ s/\/\//\//g;

	#インクルード済みか判定
	if (!grep /^$includefilename$/,@{$input_filelist_ref}){
	    get_loglevel() > 0 and print_log("(INFO) | analyze include file -- $include_restring");
		
		#ネストの深さをインクリメントする
	    $depth++;
		get_loglevel() > 2 and print_log("(DEBUG 3) | " . basename($includefilename) . " :  depth = $depth");
		#ハンドル用のカウンタをインクリメントする
	    $count++;
	    #インクルードファイルの中間ファイル作成
	    $analyzed_file_list_ref=preprocess_analyzer_prev($includefilename, $varlist, $encoding_name, $include_dir_list, $analyzed_file_list_ref);

		#ネストの深さをデクリメントする
	    $depth--;
	}
	
	return $analyzed_file_list_ref;
}

#####################################################################
# Function: search_includefile
#
#
# 概要:
# includeファイルが存在するか確認する。
# includeファイルが絶対パスで指定された場合は指定のパスのみで存在確認を行ない、
# それ以外の指定の場合はカレントディレクトリ、インクルードディレクトリに指定されたフォルダを順に検索する。
# ファイルの存在が確認できた時点で検索を終了し、確認したパスを返却する。
# なお、ファイルが確認できなかった場合は、その旨を出力し、undefを返却する。
#
# パラメータ:
#
# 戻り値:
#
# 例外:
# なし
#
# 特記事項:
# なし
#
#
#####################################################################
sub search_includefile {
	my ($include_restring, $filename, $include_dir_list) = @_;
	
	#インクルードファイル指定が絶対パスか判定
	if($include_restring =~ m{^\s*[/]}xmg){
        #絶対パスのインクルードファイルの存在有無を確認する
        if(-f $include_restring) {
            return $include_restring;
        }else{
            print_log("(WARN) | No such include file $include_restring");
            return undef;
        }
	}
		
	#filenameからファイルパスとファイル名を分割する
	my $currentdir = dirname($filename);
	#ファイルパスにインクルードファイル名を連結する
	my $includefilename=$currentdir . "/" . $include_restring;
    #カレントディレクトリのインクルードファイルの存在有無を確認する
    if(-f $includefilename) {
        return $includefilename;
    }
    foreach my $includedir (@{$include_dir_list}){
    	#インクルードディレクトリにインクルードファイル名を連結する
    	my $includefilename=$includedir . "/" . $include_restring;

        #インクルードディレクトリのインクルードファイルの存在有無を確認する
        if(-f $includefilename) {
            return $includefilename;
        }
    }

    print_log("(WARN) | No such include file $include_restring");
    return undef;
}

#####################################################################
# Function: set_pg_sqlextract_macro
#
#
# 概要:
#
# @ifgroup_configを初期化する。
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
sub set_pg_sqlextract_macro {
    @ifgroup_config = split(/\,/ , $ENV{$env_ifgroup});
}

##########################################################
# Function: return_parse_enc
#
# 概要：Parserがエンコーディング情報を取得するための関数
##########################################################
sub return_parse_enc{
    return $parse_enc;
}

1;
