#!/usr/bin/perl
#############################################################################
#  Copyright (C) 2013 NTT
#############################################################################

##################################################################
# Function: db_ddl_replace_formatter.pl
#
#
# 概要:
# OracleのSQLファイルを整形する。
# 
#[1] 整形対象SQLファイルに正規化処理を行い、SQL部分だけを取り出す。
#[2] 整形前SQLファイルの全行を 、SQL、コメントを問わず、「--」を行頭に付与し、コメントアウトする。
#[3] コメントアウトしたSQLとは別に1行1ステートメントに整形し、リテラル外の連続空白は削除する。
#[4] [2], [3]を交互に繰り返し、ユーザが整形前と整形後の SQLを確認できる形にする。
#[5] 整形後のSQLファイルは、「imd_置換対象SQLファイル名」(imd は intermediate の略) として出力する。
#
# 特記事項:
# SQL*Plus のコマンドは解析しない
# 
#
###################################################################

use warnings;
use strict;
use Carp;
use Getopt::Long qw(:config no_ignore_case);
use File::Path qw(rmtree);
use File::Basename;
use FindBin;
use utf8;
use PgSqlExtract::Common;
use PgSqlExtract::Reporter qw(set_starttime set_finishtime);

main();

1;

####################################################################
# Function: main
#
#
# 概要:
#
# OracleのSQL整形の主制御を行う
#
# パラメータ:
# ARGV - パラメータリスト
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
#####################################################################
sub main{
	
	#
    # 終了コード
    #
	my $exit_status = 0;
	
	#
    # オプション解析結果
    #
    my $options = undef;

    eval {
    	
        #
        # 実行開始時間の取得
        #
        set_starttime(get_localtime());
        
        #
    	# オプション解析実行
    	#
    	$options = analyze_option();
    	
    	
    	get_loglevel() > 0 and print_log('(INFO) db_ddl_replace_formatter was started.');
        
        get_loglevel() > 0 and print_log('(INFO) [start]  format sql.');
        
        #
        # SQLファイルを解析して、SQLを1行1ステートメントにまとめて格納する。
        #
        my $formatted_sqlfiles_info = format_sqlfiles($options->{input_dir},
            $options->{suffix_list},
            $options->{input_file_list},
            $options->{encodingname}
        );
        
        get_loglevel() > 0 and print_log('(INFO) [finish] format sql.');
        
        get_loglevel() > 0 and print_log('(INFO) [start]  output formatted sql file.');
        
        #
        # 整形したSQLの情報をファイルに出力
        #
        output_formatted_sqlfile_info($formatted_sqlfiles_info, $options->{output_dir}, $options->{encodingname});
        
        get_loglevel() > 0 and print_log('(INFO) [finish] output formatted sql file.');
        
        get_loglevel() > 0 and print_log('(INFO) db_ddl_replace_formatter was finished.');
    };
    
    #
    # SQL整形中に例外が発生した場合は、その旨を出力して終了する。
    #
    if($@) {
        $exit_status = 1;
        print_log($@);

    }
    exit($exit_status);
}
#####################################################################
# Function: format_sqlfiles
#
#
# 概要:
#
# OracleのSQLの整形を行う
# 
#
# パラメータ:
# input_dir         - 入力ファイル格納フォルダ
# suffix_list       - 拡張子リスト
# file_list         - 直接指定された入力ファイルのリスト
# encoding_name     - エンコード
#
# 戻り値:
# formatted_sqlfiles_info    - 整形したSQLの情報を格納したハッシュのリファレンス
#
# 例外:
# なし
#
# 特記事項:
#
#
#####################################################################
sub format_sqlfiles {
    my ($input_dir, $suffix_list, $file_list, $encoding_name) = @_;
    
    # 整形したSQLの情報を格納したハッシュのリファレンス
    my $formatted_sqlfiles_info = undef;
    # 正規化したSQLの情報を格納したハッシュのリファレンス
    my $normalized_sqlfiles_info = undef;
    # 整形対象SQLファイル名リスト
    my $file_name_list = undef;

    #
    # 整形対象SQLファイル名リストの作成
    #
    $file_name_list = create_input_file_list($input_dir, $suffix_list, $file_list);
    
    #
    # 整形対象のSQLファイルを整形をするための正規化を行う
    #
    $normalized_sqlfiles_info = normalize_sql($file_name_list, $encoding_name);
    
    #
    # 正規化したSQLを整形
    #
    $formatted_sqlfiles_info = adjust_line_position($normalized_sqlfiles_info);

    return $formatted_sqlfiles_info
}
#####################################################################
# Function: normalize_sql
#
#
# 概要:
#
# 置換対象SQLファイル内容についてSQLステートメントの正規化を行う。
# 
#
# パラメータ:
# file_name_list    - ファイル名リスト
# encoding_name     - エンコード
#
# 戻り値:
# normalized_sqlfiles_info - 正規化したSQLの情報を格納したハッシュのリファレンス
#
# 例外:
# なし
#
# 特記事項:
#
#
#####################################################################
sub normalize_sql {
    my ($file_name_list, $encoding_name) = @_; #引数の格納
    #　正規化したSQLの情報を格納したハッシュ
    my %normalized_sqlfiles_info = ();
    # SQLファイル名
    my $file_name = "";
    
    #
    #　正規化したSQLの情報を格納したハッシュの作成
    #
    foreach $file_name (@{$file_name_list}){
        get_loglevel() > 0 and print_log('(INFO) | normalize file -- ' . $file_name);

        eval {  
            #
            # ファイルの読み込みと正規化を行う
            #
            my @one_normalized_sqlfile_info = normalize_sql_of_onefile(read_input_file($file_name, $encoding_name));

            $normalized_sqlfiles_info{$file_name} = \@one_normalized_sqlfile_info;
        };
        
        #
        # SQLファイルの正規化中にエラーが発生した場合は、そのファイルにおける
        # 正規化は中断し、次のファイルについて正規化を行う
        #
        if($@) {
            print_log($@);
        }

    }
    return \%normalized_sqlfiles_info
}
#####################################################################
# Function: normalize_sql_of_onefile
#
#
# 概要:
#
# 1SQLファイルについてSQLステートメントの正規化を行う。
# 
#
# パラメータ:
# file_strings      - ファイル内容
#
# 戻り値:
# one_normalized_sqlfile_info         - 正規化したSQL情報を格納する配列
#
# 例外:
# なし
#
# 特記事項:
#
#####################################################################
sub normalize_sql_of_onefile {
    my ($file_strings) = @_; # 引数の格納
    my $line_count = 1; # 行番号のカウンタ
    my $code_line_count = 1; # 正規化したコードの行番号
    my $code = undef; # SQLリテラル前後の正規化対象コード
    my @one_sql = (); # 文字リテラル開始・終了の前後でSQLを分割して格納する配列
    my $sql = ""; # 正規化した1SQLを格納する変数
    my @one_normalized_sqlfile_info = (); # 正規化したSQL情報を格納する配列
    my @code_char = (); # 一文字づつのコード配列
    my $code_char_max = 0; # 一文字づつのコード配列の添え字
    my $brace_count = 0; # 括弧のカウンタ
    my $in_comment_flg = FALSE; # コメント又はリテラル内かのフラグ
    my $is_preserve_comment = FALSE;  # 保持すべきコメント文字列であるかの真偽値
    my $literal_buff = "";         # 文字リテラルの一時保存領域
    my $line_body = "-- "; # 一行ごとの情報を格納
    
    get_loglevel() > 2 and print_log("(DEBUG 3) | [in] normalize_codes");
    
    #
    # SQLの正規化
    #
    
    # 一文字づつ配列に格納
    @code_char = split(//, $file_strings."\n");
    
    # 最大添え字を取得
    $code_char_max = $#code_char;
    
    # 最終文字+1まで判定するため最後に要素を追加
    push(@code_char , '');
    
    # コメントの削除、リテラルの退避
    for(my $char_count = 0; $char_count <= $code_char_max; $char_count++) {
        # 一行ごとの文字列に追加
        $line_body .= $code_char[$char_count];
        if($code_char[$char_count] eq "\n"){
            # 一行ごとの文字列を追加
            push(@one_normalized_sqlfile_info, $line_body);  
            # 一行ごとの文字列を格納する変数を初期化
            $line_body = "-- ";
            
            #
            # 行番号のインクリメント
            #
            $line_count++;
            
            #
            # 改行の格納
            # ただしリテラル内リテラル解析中以外の場合に改行文字を格納する
            # リテラル内リテラル中に行の継続が存在するケースが改行文字を
            # 格納しないケースである
            #
            if($in_comment_flg == LITERAL
            or $in_comment_flg == SQL_LITERAL) {
                $literal_buff .= $code_char[$char_count];
            }
            elsif($in_comment_flg != LITERAL_LITERAL){
                # 改行後に空白がない場合があるため、空白を挿入して文字列を追加
                # 連続空白となる場合は後の処理にで削除
                $code .= " ".$code_char[$char_count];
            }

            if($is_preserve_comment) {
                $code =~ s{(.*)(--.*$)}{$1}xms;
                $is_preserve_comment = FALSE;
                $in_comment_flg = NOT_COMMENT;
            }
            
            #
            # 行の継続の判定
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
            
            # 「--」コメント・「//」コメント・前処理指令の終了判定
            if($in_comment_flg == SIMPLE_COMMENT){
                $in_comment_flg = NOT_COMMENT;
            }
            
            #
            # 空白行か判定
            #
            if($code =~ m/\A \s* \z/xms){
                #
                # コード行番号のインクリメント
                #
                $code_line_count++;
                next;
            }
            
            next;
        }
        # 「/*」コメントの開始判定
        elsif($in_comment_flg == NOT_COMMENT 
        and $code_char[$char_count] eq '/' 
        and $code_char[$char_count+1] eq '*') {
        	# 一行ごとの文字列に'*'を追加
            $line_body .= $code_char[$char_count+1];
            $char_count++;
            $in_comment_flg = MULTI_COMMENT;
            next;
        }
        # 「/*」コメントの終了判定
        elsif($in_comment_flg == MULTI_COMMENT 
        and $code_char[$char_count] eq '*' 
        and $code_char[$char_count+1] eq '/') {
        	# 一行ごとの文字列に'/'を追加
        	$line_body .= $code_char[$char_count+1];
            $char_count++;
            $in_comment_flg = NOT_COMMENT;
            next;
        }
        # 「--」コメントの開始判定
        elsif($in_comment_flg == NOT_COMMENT 
        and $code_char[$char_count] eq '-' 
        and $code_char[$char_count+1] eq '-') {
            $char_count++;
        	# 一行ごとの文字列に'-'を追加
        	$line_body .= $code_char[$char_count];
            $in_comment_flg = SIMPLE_COMMENT;
            $is_preserve_comment = TRUE;
            next;
        }
        # 「'」リテラルの開始判定
        elsif($in_comment_flg == NOT_COMMENT 
        and $code_char[$char_count] eq '\''){
            $in_comment_flg = SQL_LITERAL;
            $code .= $code_char[$char_count];
            
            # リテラル開始までのSQLから連続空白を削除
            $code =~ s/\s{2,}/ /g;
            
            # SQLの先頭に余計な空白がある場合は削除
            $code =~ s/^\s//g;
            
            # リテラル開始までを追加
            push(@one_sql, $code);
            # コードを初期化
            $code = ""; 
            
            next;
        }
        # 「'」リテラルの終了判定
        elsif($in_comment_flg == SQL_LITERAL 
        and $code_char[$char_count] eq '\''){
            #「'」文字のエスケープ処理判定「\」
            if($code_char[$char_count-1] eq '\\') {
                $literal_buff .= $code_char[$char_count];
                next;
            }
            # 「'」文字のエスケープ処理判定「'」
            elsif($code_char[$char_count+1] eq '\'') {
                $literal_buff .= $code_char[$char_count];
                $char_count++;
                # 一行ごとの文字列に追加
                $line_body .= $code_char[$char_count];
                $literal_buff .= $code_char[$char_count];
                next;
            }
            else{
                $in_comment_flg = NOT_COMMENT;
                # リテラル内の文字列を追加
                push(@one_sql, $literal_buff);
                #
                # リテラル一時保存領域の初期化
                #
                $literal_buff="";
                $code .= $code_char[$char_count];
                next;
            }
        }
        # 「"」リテラルの開始判定
        elsif($in_comment_flg == NOT_COMMENT 
        and $code_char[$char_count] eq '"'){
            $in_comment_flg = LITERAL;
            $code .= $code_char[$char_count];
            
            # リテラル開始までのSQLから連続空白を削除
            $code =~ s/\s{2,}/ /g;
            
            # SQLの先頭に余計な空白がある場合は削除
            $code =~ s/^\s//g;
            
            # リテラル開始までを追加
            push(@one_sql, $code);
            # コードを初期化
            $code = ""; 
            
            next;
        }
        #「"」リテラルの終了判定
        elsif($in_comment_flg == LITERAL 
        and $code_char[$char_count] eq '"'){
            #「"」文字のエスケープ処理判定
            if($code_char[$char_count-1] eq '\\') {
                $in_comment_flg = LITERAL_LITERAL;
                $literal_buff .= $code_char[$char_count];
                # 一行ごとの文字列に追加
                $line_body .= $code_char[$char_count];
                next;
            }
            else{
                $in_comment_flg = NOT_COMMENT;
                # リテラル内の文字列を追加
                push(@one_sql, $literal_buff);
                #
                # リテラル一時保存領域の初期化
                #
                $literal_buff=""; 
                $code .= $code_char[$char_count];
                next;
            }
        }
        # 「\」リテラル内リテラルの終了判定
        elsif($in_comment_flg == LITERAL_LITERAL 
        and $code_char[$char_count] eq '\\'
        and $code_char[$char_count+1] eq '"'){
            $in_comment_flg = LITERAL;
            $literal_buff .= $code_char[$char_count];
            $char_count++;
            $literal_buff .= $code_char[$char_count];
            next;
        }
        # 「"」リテラル内リテラルの終了判定
        elsif($in_comment_flg == LITERAL_LITERAL
        and $code_char[$char_count] eq '"'){
            $in_comment_flg = NOT_COMMENT;
            $code .= $literal_buff;
            #
            #リテラル一時保存領域の初期化
            #
            $literal_buff="";
            $code .= $code_char[$char_count];
            next;
        }
        # 「;」セミコロンの判定
        elsif($in_comment_flg == NOT_COMMENT 
        and $code_char[$char_count] eq ';'){
            $code .= $code_char[$char_count];
            
            #
            # 前後空白の削除
            #
            $code =~ s{\A \s*(.*)\s* \z}{$1}xms;           
            
            #
            # SQL中にリテラルがあった場合の処理
            #
            
            # リテラル終了後までのSQLから連続空白を削除
            $code =~ s/\s{2,}/ /g;
            
            # リテラル終了直後が";"でない場合、空白が全部削除される
            # ことがあるため、その場合はリテラル終了直後に空白を挿入する
            if($code !~ /^';/ && $code !~ /^";/) {
                $code =~ s/^'([^\s])/' $1/;
                $code =~ s/^"([^\s])/" $1/;
            }
            
            # セミコロンの直前の空白は削除 
            if($code =~ /\s+;$/) {
                $code =~ s/\s+;$/;/;
            }
            # リテラル終了後までを追加
            push(@one_sql, $code);
            
            # 要素を変数にまとめる
            foreach my $tmp_sql(@one_sql) {
            	$sql .= $tmp_sql;
            }
            
            $sql =~ s/\n//g;
            
            #
            # コード情報の格納
            #
            get_loglevel() > 4 and print_log("(DEBUG 5) | " . $code_line_count . ": $sql");
            
            # 正規化したSQLを追加
            push(@one_normalized_sqlfile_info, $sql);
            
            #
            #　格納した行を次の格納行番号として格納
            #
            $code_line_count = $line_count;

            #
            #　コード格納領域の初期化
            #
            $code = "";
            
            # SQLを格納する変数を初期化
            $sql = "";
            # 1SQLを分割して格納する配列
            @one_sql = ();
            
            next;
        }
    
        #
        # 通常の場合は文字を格納
        #
        if($in_comment_flg == NOT_COMMENT ) {
            $code .= $code_char[$char_count];
        }
        #
        # リテラル内の場合は一時バッファに文字を格納
        #
        elsif($in_comment_flg == LITERAL
        or $in_comment_flg == SQL_LITERAL ) {
            $literal_buff .= $code_char[$char_count];
        }
        elsif($code_char[$char_count] eq '\\') {
            $code .= $code_char[$char_count];
        }
    } # コードの正規化ループの終端
    
    get_loglevel() > 2 and print_log("(DEBUG 3) | [out] normalize_codes");
    return  @one_normalized_sqlfile_info
}

#####################################################################
# Function: adjust_line_position
#
# 概要:
#
# 正規化された各SQLのファイル内の行位置の調整を行う
#
# パラメータ:
# input_dir         - 入力ファイル格納フォルダ
# suffix_list       - 拡張子リスト
# file_list         - 直接指定された入力ファイルのリスト
# encoding_name     - エンコード
# 
# 戻り値:
# sql_file_info     - 行位置を調整したSQLファイルの内容
# 
#
# 例外:
# なし
#
# 特記事項:
# なし
######################################################################
sub adjust_line_position {
    #　引数受け取り
    my ($normalized_sqlfiles_info) = @_; 
    #　調整後のSQLファイルの情報を格納するハッシュ
    my %formatted_sqlfile_info = ();
    
    # 行位置調整対象SQLファイル毎に調整する
    foreach my $one_sqlfile_name(sort keys %{$normalized_sqlfiles_info}) {
        get_loglevel() > 0 and print_log('(INFO) | format sqlfile -- ' . $one_sqlfile_name);
    	# 1行位置調整対象SQLの情報を格納
    	my $one_sqlfile_info = $normalized_sqlfiles_info->{$one_sqlfile_name};
    	
        $formatted_sqlfile_info{$one_sqlfile_name} = adjust_line_position_of_onefile($one_sqlfile_info);
    }
    return \%formatted_sqlfile_info
}
#####################################################################
# Function: adjust_line_position_of_onefile
#
# 概要:
#
# 1行位置調整対象SQLファイルの調整を行う
#
# パラメータ:
# one_sqlfile_info  - 入力ファイル格納フォルダ
#
# 戻り値:
# sql_file_info     - 行位置を調整したSQLファイルの内容
# 
#
# 例外:
# なし
#
# 特記事項:
# なし
######################################################################
sub adjust_line_position_of_onefile {
    #　引数受け取り
    my ($one_sqlfile_info) = @_; 
    #　整形後のSQLファイルの情報を格納する配列
    my @one_formatted_sqlfile_info = ();
    # 要素番号をカウントする変数
    my $count = 0;
    # SQLがどの何要素目であるか確認するための変数
    my $sql_point = undef;
    # 1SQLを一時的に格納する変数
    my $sql = "";
    
    # 整形対象SQLファイル毎にSQLの位置を調整する
    foreach my $line(@{$one_sqlfile_info}) {
        
        # 改行コードを変換
        $line =~ s/\r\n/\n/g;

        # 空白行の確認
        if($line =~ /^\s*--\s*$/){
            push(@one_formatted_sqlfile_info, "");
        }
        #『--』で始まるコメントか確認
        elsif($line =~ /^\s*-+/) {
        	#
        	# SQLとコメントの情報の格納順番が以下のようになっているため、
        	# 順番を入れ替える処理を行う
        	# REVOKE INSERT ON T_TEST FROM USER1;
        	# -- REVOKE INSERT ON T_TEST FROM USER1;
        	#
        	if(defined $sql_point) {
        		# 1SQLを待避
        		$sql = $one_formatted_sqlfile_info[$sql_point];
        		# SQLが格納されていた場所にSQLの直後のコメントを格納
        		$one_formatted_sqlfile_info[$sql_point] = $line;
        		# 改めてSQLを格納
        		push(@one_formatted_sqlfile_info, $sql);
        		$sql_point = undef;
        	}
        	else {
        		push(@one_formatted_sqlfile_info, $line);
        	}
        }
        # これまで以外の分岐以外は全てSQL
        else {
        	# SQL内の改行を削除
            $line =~ s/\n//g;
            # SQLの最初と最後に改行コードを付与
            $line = "\n".$line."\n\n";
            push(@one_formatted_sqlfile_info, $line);
            # SQLが格納されている要素番号を格納
            $sql_point = $count;
        }
        ++$count;
    }
    return \@one_formatted_sqlfile_info
}
#####################################################################
# Function: output_formatted_sql_file
#
# 概要:
# 整形後のSQL情報を格納したハッシュを用いて
# 整形後SQLファイルに出力する
#
# パラメータ:
# formatted_sqlfile_info  - 整形後のSQLファイルの情報を格納した配列のリファレンス
# output_dir              - 整形後SQLファイルを出力するディレクトリ
# encoding_name           - 文字エンコーディング設定
#
# 戻り値:
# なし
#
# 例外:
# 　- ファイルのopen失敗
#
# 特記事項:
# なし
#####################################################################
sub output_formatted_sqlfile_info {
    # 引数受け取り
    my ($formatted_sqlfile_info, $output_dir, $encoding_name) = @_;
    
    # 整形対象SQLファイルに対応するように整形後SQLファイルを出力する
    foreach my $one_formatted_sqlfile_name (sort keys %{$formatted_sqlfile_info}) {
    	# 整形対象SQLファイルに対応する整形後SQL情報を取得
    	my $one_formatted_sqlfile_info = $formatted_sqlfile_info->{$one_formatted_sqlfile_name};
    	# 整形対象SQLファイル名からパスを削除
    	my ($base_sqlfile_name, $dir_name) = fileparse $one_formatted_sqlfile_name;
    	
    	# 出力先ディレクトリが指定されているか確認
    	if(!defined $output_dir) {
    		$output_dir = $dir_name;
    	}
    	elsif($output_dir !~ /\/$/) {
    		$output_dir = $output_dir."/";
    	}
    	
    	# 整形後SQLファイル名の付与
    	$base_sqlfile_name = "imd_".$base_sqlfile_name;
    	
    	# ファイルのオープン
        open(my $fh, ">:encoding($encoding_name)",$output_dir.$base_sqlfile_name)
            or croak "Cannot create $output_dir$base_sqlfile_name for write: $!";

        # 一行ごとに書き込み
        foreach my $sql_items(@{$one_formatted_sqlfile_info}) {
            print $fh $sql_items;
        }
        close $fh;
    }
}
#####################################################################
# Function: analyze_option
#
#
# 概要:
#
# オプション解析および指定値の意味解析を行い、オプションの解析結果を返却する。
#| (1) オプションにデフォルト値を設定する。
#| (2) オプションに指定された値を取得する。
#| (3) 認識不能オプションの判定
#|     認識不能なオプションが指定された場合はエラーとする。
#| (4) -hオプションの判定
#|     -hオプションが指定された場合、他のオプション指定に関わらず、Usageを出力して正常終了する。
#| (5) -eオプションの判定
#|     「utf8」、「shiftjis」、「eucjp」以外の値か、オプションを指定して値の指定がない場合は異常終了する。
#| (6) -iオプションの判定
#| (7) -oオプション指定時の処理
#|     オプションを指定して値の指定がない場合は異常終了する。
#
# パラメータ:
# なし
#
# 戻り値:
# option_analytical_result - オプション解析結果を格納したハッシュ
#
# 例外:
# 
# - オプションの値指定無し
# - オプションの異常値指定
# - ファイルのopen失敗
# 
# 特記事項:
# オプション解析結果は以下の構造を持つ
#|<オプション解析結果>
#|{
#|  encodingname =>"エンコーディング名",
#|  input_dir =>"整形対象SQLファイル格納ディレクトリ",
#|  suffix_list => "整形対象SQLファイルの拡張子",
#|  input_file_list => "整形対象SQLファイルのリスト",
#|  verbose =>"出力レベル"
#|  output_dir =>"整形後SQLを出力するディレクトリ"
#|}
#
#####################################################################
sub analyze_option {
    my %option_analytical_result; #オプション解析結果のハッシュ
    my $help_option_flg = FALSE; #helpオプション有り無しフラグ

    #
    #オプションの初期化
    #
    $option_analytical_result{encodingname}    = ENCODE_EUCJP;
    $option_analytical_result{input_dir}       = undef;
    $option_analytical_result{output_dir}      = undef;
    $option_analytical_result{verbose}         = 0;
    $option_analytical_result{suffix_list}     = ['sql'];
    $option_analytical_result{input_file_list} = [];

    #
    #GetOptionsでオプションをハッシュに格納
    #
    my $GetOptions_result = GetOptions(
        'encoding=s' => \$option_analytical_result{encodingname},
        'inputsqldir=s' => \$option_analytical_result{input_dir},
        'outputsqldir=s' => \$option_analytical_result{output_dir},
        'help' => \$help_option_flg,
        'verbose:1' => \$option_analytical_result{verbose},
    );
    #
    #認識不能オプションの判定
    #
    if($GetOptions_result ne TRUE){
        croak();
    }
    #
    #-hオプションの判定
    #
    if($help_option_flg eq TRUE){
        printUsage();
        exit(0);
    }

    #
    #-eオプションの判定
    #
    if($option_analytical_result{encodingname} eq ENCODE_EUCJP) {
        $option_analytical_result{encodingname} = INOUT_ENCODE_EUCJP;
    }
    elsif($option_analytical_result{encodingname} eq ENCODE_SHIFTJIS) {
        $option_analytical_result{encodingname} = INOUT_ENCODE_SHIFTJIS;
    }
    elsif($option_analytical_result{encodingname} eq ENCODE_UTF8) {
        $option_analytical_result{encodingname} = INOUT_ENCODE_UTF8;
    }
    else {
        # パラメータの不正指定
        croak("Option --encodeing: Invalid argument");
    }

    #
    #-iオプションの判定
    #拡張子指定が存在する場合は格納する
    #ディレクトリが存在しない場合はエラー
    #
    if($option_analytical_result{input_dir}) {
        my @input_spec = split(/,/, $option_analytical_result{input_dir});
        $option_analytical_result{input_dir} = shift(@input_spec);
        if($#input_spec > -1) {
            $option_analytical_result{suffix_list} = \@input_spec;
        }
        
        #ディレクトリの存在と読み込み権限の有無を確認する
        if(!(-d $option_analytical_result{input_dir})) {
            croak("Option --inputsqldir: No such directory $option_analytical_result{input_dir}");
        }    
        elsif(!(-r $option_analytical_result{input_dir})) {
            croak("Option --inputsqldir: Access denied $option_analytical_result{input_dir}");
        }
    }
    
    #
    #-oオプションの判定
    #
    if($option_analytical_result{output_dir}) {
        #ディレクトリの存在有無を確認する
        if(!(-d $option_analytical_result{output_dir})) {
            croak("Option --outputsqldir: No such directory $option_analytical_result{output_dir}");
        }
    }

    #
    # -vオプションの取得
    # -vオプションに数値が指定されている場合はその数値をログ出力
    # レベルとして設定する
    #
    set_loglevel($option_analytical_result{verbose});

    #
    # 置換対象SQLファイルのリスト指定を取得する
    #
    if($#ARGV >= 0) {
        my @args = @ARGV;
        my @file_list=(); #ファイルリスト一時格納領域
        
        # ファイルの存在有無を確認する
        for my $file (@args) {
            if(!(-e $file)) {
                eval {
                    croak("File open error $file($!)\n");
                };
                #
                # ファイルが存在しない場合は、エラーメッセージを表示し次のファイルについて処理を行う
                #
                if($@) {
                    print_log($@);
                }
            }
            else {
                #
                # ファイルが存在する場合は、ファイルリストに格納
                #
                push(@file_list, $file);
            }
        }
        $option_analytical_result{input_file_list} = \@file_list;
    }
    
    #
    # -iオプションおよび抽出対象ファイルのリスト指定の両方が存在
    # しない場合はエラーとする
    #
    if(!defined $option_analytical_result{input_dir}
       and scalar @{$option_analytical_result{input_file_list}} == 0) {
        croak("Requires option --inputsqldir or inputsqlfilename");
    }   
    #
    # 戻り値の設定
    #
    return(\%option_analytical_result);
}
#####################################################################
# Function: printUsage
#
#
# 概要:
#
# Usageを表示する。
# 
# パラメータ:
# なし
#
# 戻り値:
# なし
#
# 特記事項:
# なし
#
#
#####################################################################
sub printUsage {
	print STDOUT <<_USAGE_;

db_ddl_replace_formatter version 3.0
The tool to format SQL.

Usage:db_ddl_replace_formatter.pl [-e encodingname]
[-i inputsqldir[,suffix1[,suffix2]...] ] [-o outputsqldir]
[-h][-v][inputsqlfilename]...

    -e encodingname, --encoding=encodingname  File encoding. The value which can be specified is "utf8" and "shiftjis" and "eucjp". [default: eucjp]
    -i inputsqldir, --input=inputsqldir  Input-sql-file directory. [default suffix: sql]
    -o outputsqldir, --output=outputdir     Output-sql-file directory. 
    -h, --help    Print usage and exit.
    -v, --verbose Print progress of the practice to STDERR and replacement result to STDOUT. The value which can be specified is "1" and "3". [default: none]
    inputsqlfilename  Input-sql file name.

_USAGE_

}                
__END__
