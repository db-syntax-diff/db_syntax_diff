#!/usr/bin/perl
#############################################################################
#  Copyright (C) 2013 NTT
#############################################################################

######################################################################
# Function: db_ddl_replace_prot.pl
#
#
# 概要:
# OracleのSQLファイル内のDDLをPostgreSQLのDDL
# に置換するモジュールのプロトタイプ第三段階
# 
# 特記事項:
# 置換するDDLは入力する置換候補ファイルに依存する
#
######################################################################

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

binmode(STDOUT, ":utf8"); # PerlIOレイヤ
main();

1;

######################################################################
# Function: main
#
#
# 概要:
#　DDL置換ツールの主制御を行う
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
######################################################################
sub main {
	
    #
    # 終了コード
    #
	my $exit_status = 0;
	
    #
    # オプション解析結果
    #
    my $options = undef;
    
    #
    # 一括置換候補ファイルの解析結果
    #
    my $group_replacement_candidate_info = undef;
    
    #
    # 個別置換候補ファイルの解析結果
    #
    my $replacement_candidate_info = undef;
    
    #
    # 置換結果の統計情報を格納するハッシュ
    #
    my %replacement_summary;
    
    eval {
    	
        #
        # 実行開始時間の取得
        #
        set_starttime(get_localtime());
        
        #
    	# オプション解析実行
    	#
    	$options = analyze_option();

        get_loglevel() > 0 and print_log('(INFO) db_ddl_replace was started.');
 
        #
        # 一括置換モードか個別置換モードか判定
        #
        if(defined $options->{group_replacement_candidatefile}) {
            get_loglevel() > 0 and print_log('(INFO) [start]  loading group replacement candaidate file.');
            
            # 一括置換候補ファイルを解析して情報を格納
            $group_replacement_candidate_info = analyze_group_replacement_candidate($options->{group_replacement_candidatefile});
            
            get_loglevel() > 0 and print_log('(INFO) [finish] loading group replacement candaidate file.');
            
        }
        
        get_loglevel() > 0 and print_log('(INFO) [start]  loading replacement candaidate file.');
            
        # 個別置換候補ファイルを解析して情報を格納
        $replacement_candidate_info = analyze_replacement_candidate($options->{replacement_candidatefile}, $group_replacement_candidate_info);
            
        get_loglevel() > 0 and print_log('(INFO) [finish] loading replacement candaidate file.');

        get_loglevel() > 0 and print_log('(INFO) [start]  analyze SQL files.');
        
        #
        # 置換対象SQLファイルを解析して配列に格納
        #
        my $sql_info = analyze_sqlfile($options->{input_dir},
            $options->{suffix_list},
            $options->{input_file_list},
            $options->{encodingname}
        );
        
        get_loglevel() > 0 and print_log('(INFO) [finish] analyze SQL files.');
        
        get_loglevel() > 0 and print_log('(INFO) [start]  replace ddl.');

        #
        # DDLの置換処理
        #
        my $replaced_sqlfile_info = replace_ddl($replacement_candidate_info, $sql_info, \%replacement_summary);

        get_loglevel() > 0 and print_log('(INFO) [finish] replace ddl.');
        
        get_loglevel() > 0 and print_log('(INFO) [start]  output replaced sql file.');
        
        #
        # 置換したDDLの情報をファイルに出力
        #
        output_replaced_sqlfile($replaced_sqlfile_info, $options->{output_dir}, $options->{encodingname});
        
        get_loglevel() > 0 and print_log('(INFO) [finish] output replaced sql file.');
        
        get_loglevel() > 0 and print_log('(INFO) db_ddl_replace was finished.');
        
        #
        # 置換結果の統計情報を標準出力
        #
        output_replacement_summary(\%replacement_summary);
    };
    
    #
    # DDL置換中に例外が発生した場合は、その旨を出力して終了する。
    #
    if($@) {
        $exit_status = 1;
        print_log($@);

    }
    exit($exit_status);
}

######################################################################
# Function: analyze_group_replacement_candidate
#
# 概要:
#
# 一括置換候補ファイルの情報を置換対象のSQLファイル毎にハッシュで情報を
# 格納する。
#
# パラメータ:
# replacementt_candidate_file  - 解析する置換候補ファイル名
# encoding_name      - 文字エンコーディング設定
#
# 戻り値:
# replacement_candidate_info  - 解析した置換候補ファイルの情報のハッシュのリファレンス
#
# 例外:
#  - ファイルのopen失敗
#
# 特記事項:
# 配列 @replacement_candidate_items の各要素には以下の値が入る
# [0] - 置換フラグ(replace, delete, no replace)
# [1] - メッセージID
#
######################################################################
sub analyze_group_replacement_candidate {
    # 引数受け取り
    my ($group_replacement_candidate_file) = @_;
    # 一括置換候補ファイルの情報を格納するハッシュ
    my %group_replacement_candidate_info = ();
    
    # 一括置換候補ファイルオープン
    open(my $fh, "<:encoding(utf8)",$group_replacement_candidate_file)
        or croak "Cannot open group_replacement_candidate_file for read: $!";    
    
    while(my $line = <$fh>) {
    	my @replacement_candidate_items = (); #　各行のデータを格納する配列
        
        #
        # CSV解析
        #
        
        # SQL抽出パターンに","が含まれていることがあるため、
    	# 一時的にSQL抽出パターンを後方参照用変数に退避して、
    	# 後から配列に格納する。
    	$line =~ s/(?:¥x0D¥x0A|[¥x0D¥x0A])?$/,/;
    	@replacement_candidate_items = map {/^"(.*)"$/ ? scalar($_ = $1, s/""/"/g, $_) : $_}
                                           ($line =~ /("[^"]*(?:""[^"]*)*"|[^,]*),/g);
        
        # ハッシュに情報追加
        $group_replacement_candidate_info{$replacement_candidate_items[1]} = $replacement_candidate_items[0];
    }
    close $fh;
    return \%group_replacement_candidate_info;
}

######################################################################
# Function: analyze_replacement_candidate
#
# 概要:
#
# 個別置換候補ファイルの情報を置換対象のSQLファイル毎にハッシュで情報を
# 格納する。
#
# パラメータ:
# replacemnet_candidate_file  - 解析する置換候補ファイル名
# group_replacement_candidate_info  - 置換フラグの書き換えに使用する一括置換候補ファイルの情報
# encoding_name      - 文字エンコーディング設定
#
# 戻り値:
# replacement_candidate_info  - 解析した置換候補ファイルの情報のハッシュのリファレンス
#
# 例外:
# - ファイルのopen失敗
#
# 特記事項:
# 配列 @replacement_candidate_items の各要素には以下の値が入る
# [0] - 置換フラグ(replace, delete, no replace)
# [1] - 置換パターン
# [2] - 抽出パターン
# [3] - 行数
# [4] - カラム位置
# [5] - フルパス
# [6] - メッセージID
# [7] - タイプ
# [8] - メッセージ
######################################################################
sub analyze_replacement_candidate {
    # 引数受け取り
    my ($replacement_candidate_file, $group_replacement_candidate_info) = @_; 
    # 個別置換候補ファイルの情報を格納するハッシュ
    my %replacement_candidate_info = ();
    # 個別置換候補ファイルに存在する置換対象SQLファイル名
    my $sqlfile_name = "";
    # ディレクトリ部分を除いた置換対象SQLファイル名
    my $base_sqlfile_name = "";
    # 1置換対象SQLファイルごとの情報を格納する配列
    my @replacement_candidate_info_of_onefile = ();
    
    # 個別置換候補ファイルオープン
    open(my $fh, "<:encoding(utf8)", $replacement_candidate_file)
        or croak "Cannot replacement_candidate_file for read: $!";                  

    # 個別置換候補ファイルの中身を置換対象SQLファイルごとに配列に格納し、
    # その配列を値、置換対象SQLファイル名をキーとしてハッシュに格納する。
    while(my $line = <$fh>) {
    	# 各行のデータを格納する配列
    	my @replacement_candidate_items = ();
    	
    	#
    	# CSV形式の解析
    	#
    	
    	# SQL抽出パターンに","が含まれていることがあるため、
    	# 一時的にSQL抽出パターンを後方参照用変数に退避して、
    	# 後から配列に格納する。
    	$line =~ s/(?:¥x0D¥x0A|[¥x0D¥x0A])?$/,/;
    	@replacement_candidate_items = map {/^"(.*)"$/ ? scalar($_ = $1, s/""/"/g, $_) : $_}
                                           ($line =~ /("[^"]*(?:""[^"]*)*"|[^,]*),/g);

        # 一括置換候補ファイルの情報が存在する場合は、個別置換候補ファイルの置換フラグを書き換えて格納する
        if(defined $group_replacement_candidate_info->{$replacement_candidate_items[6]}) {
            $replacement_candidate_items[0] = $group_replacement_candidate_info->{$replacement_candidate_items[6]}
        }
        
        # 最初に置換候補情報を格納する置換対象SQLファイル名を初期化する
        if(!defined $sqlfile_name) {
            $sqlfile_name = $replacement_candidate_items[5];
        }
        
        #
        # 次の置換対象ファイル名が出てくるまで同じ配列に置換候補情報を格納する。
        # 置換フラグが no replace のものは格納しない。
        #
        if($sqlfile_name eq $replacement_candidate_items[5] && 
            ($replacement_candidate_items[0] eq "replace" or $replacement_candidate_items[0] eq "delete")) {
            push (@replacement_candidate_info_of_onefile, \@replacement_candidate_items); # 各行のデータを格納した配列のリファレンスを格納
        }
        #
        # 次の置換対象ファイル名が出てきたら、一つの置換対象SQLファイルの置換情報を格納した配列を
        # 置換対象ファイル名をキーにしてハッシュに格納する。
        # ハッシュの値に配列を格納すると配列の要素数が格納されてしまうので、配列のリファレンスを格納する。
        #
        elsif($sqlfile_name ne $replacement_candidate_items[5]) {
        	
            # 初めてこの分岐に入ったときは 置換対象SQLファイル名にディレクトリ名が残っているので削除
            if($base_sqlfile_name eq "") {
                $base_sqlfile_name = basename $sqlfile_name; #　ディレクトリ名を削除し、ファイル名だけを取得
            }
        
            # @replacement_candidate_info_of_onefileのリファレンスをハッシュの値にすると、次の置換対象SQLファイルの
            # 情報上書かれてしまうので、@replacement_candidate_info_of_onefileの情報を複製して、
            # その配列のリファレンスをハッシュの値として格納する。
            my @temp_replacement_candidate_info = @replacement_candidate_info_of_onefile; 

      	    # ファイル名をキーにして、置換候補情報を格納した配列のリファレンスを値として格納
            $replacement_candidate_info{$base_sqlfile_name} = \@temp_replacement_candidate_info;
      
            # 次の置換対象SQLファイル名を格納
            $sqlfile_name = $replacement_candidate_items[5];

            # 次の置換対象SQLファイル名からディレクトリ名を削除し、ファイル名だけを取得
            $base_sqlfile_name = basename $sqlfile_name;
        
            # 1置換対象SQLファイルの情報を格納する配列を初期化
            @replacement_candidate_info_of_onefile = ();
        	
            # 置換フラグが replace または delete のときのみ情報を格納する。
            if ($replacement_candidate_items[0] eq "replace" or $replacement_candidate_items[0] eq "delete") {
                push (@replacement_candidate_info_of_onefile, \@replacement_candidate_items); # 各行のデータを格納した配列のリファレンスを格納
            } 
            # 2個目以降の置換対象SQLファイルに対する置換候補情報を格納するとき、それ対応する置換候補情報の置換フラグに replace または delete
            # しかない場合、その置換対象SQLファイルのキーが作成されなくなるため、ここでキーと値を初期化する。
            else {
       		$replacement_candidate_info{$base_sqlfile_name} =[]; # 値を無名配列のリファレンスで初期化
                
            }
        }
    }
    close $fh;
    
    #
    #　個別置換候補ファイルの最後に記載されている置換対象SQLァイルの情報は、
    #　直前のwhileループ内ではハッシュに追加されないため、以下で追加する
    #
    $base_sqlfile_name = basename $sqlfile_name; #　ディレクトリ名を削除する
    # ファイル名をキーにして、配列のリファレンスを格納
    $replacement_candidate_info{$base_sqlfile_name} = \@replacement_candidate_info_of_onefile;
    return \%replacement_candidate_info;
}

#####################################################################
# Function: analyze_sqlfile
#
# 概要:
# SQLファイル内の要素をコメント、空白行、SQLの属性に分けて、
# 文本体と共に配列に格納する。
#
# パラメータ:
# input_dir         - 入力ファイル格納フォルダ
# suffix_list       - 拡張子リスト
# file_list         - 直接指定された入力ファイルのリスト
# encoding_name     - エンコード
#
# 戻り値:
# sqlfile_info     - 解析したSQLファイルの中身を格納した配列
#                     
#
# 例外:
#  - ファイルのopen失敗
#
# 特記事項:
# 配列 @sql_items の各要素には以下の値が入る
# [0] - 属性(COMMENT、BRANK、SQL)
# [1] - SQLファイルの一行ごとの文字列
#####################################################################
sub analyze_sqlfile{
	#　引数受け取り
    my ($input_dir, $suffix_list, $file_list, $encoding_name) = @_; 
    #　置換対象SQLファイルの情報を格納するハッシュ
    my %sqlfile_info = ();
    # 置換対象SQLファイル名リスト
    my $file_name_list = undef; 

    #
    #　置換対象SQLファイル名のリスト作成
    #
    $file_name_list = create_input_file_list($input_dir, $suffix_list, $file_list);
    
    # 置換対象SQLファイル毎に情報を格納する。
    foreach my $sqlfile(sort @{$file_name_list}) {
    	get_loglevel() > 0 and print_log('(INFO) | analyze file -- ' . $sqlfile);
        my @one_sqlfile_info = ();
        #　SQLファイルをオープン
        open( my $fh, "<:encoding($encoding_name)", $sqlfile )
            or croak "File open error $sqlfile($!)";
        #　SQLファイルの情報を格納する
        while(my $line =<$fh>){
            my @sql_items = (); #　一行ごとのSQLファイルのデータを格納する配列
            #　『--』で始まるコメントか確認
            if($line =~ /^\s*-+/){
                push(@sql_items, 'COMMENT');
                push(@sql_items, $line);
            }
            # 空白行であることの確認
            elsif($line =~ /^\s*$/){
                push(@sql_items, 'BRANK');
                push(@sql_items, $line);
            }
            # これまで以外の分岐以外は全てSQL
            else{
                push(@sql_items, 'SQL');
                push(@sql_items, $line);
            }
        # 各行ごとの解析結果を格納した配列のリファレンスを格納
        push(@one_sqlfile_info, \@sql_items);
        }
        close $fh;
        
        # SQLファイルごとの情報をハッシュに追加
        $sqlfile_info{$sqlfile} = \@one_sqlfile_info;
    }
    return \%sqlfile_info
}

#####################################################################
# Function: replace_ddl
#
# 概要:
# 置換候補ファイルの情報と置換対象SQLファイルの情報をもとに
# DDLの置換を行う
#
# パラメータ:
# replacement_candidate_info - 個別置換候補ファイルの情報を格納したハッシュのリファレンス
# sqlfile_info               - 全置換対象SQLファイルの情報を格納したハッシュのリファレンス
#　replacement_summary         - 置換結果の統計情報を格納するハッシュのリファレンス
#
# 戻り値:
# one_replaced_sqlfile_info  - 置換したDDLの全情報を追加したハッシュのリファレンス
#
# 例外:
# なし
#
# 特記事項:
# なし
#
#####################################################################
sub replace_ddl {
    # 引数受け取り
    my($replacement_candidate_info, $sqlfile_info, $replacement_summary) = @_;
    
    # パスを除いた置換対象SQLファイル名
    my $base_sqlfile_name = "";
    # 置換後のSQL情報を全て格納するハッシュ
    my %replaced_sqlfile_info = ();

    # 個々の置換対象のSQLファイルごとに置換実行
    foreach my $one_sqlfile_name(sort keys %{$sqlfile_info}) {
    	get_loglevel() > 0 and print_log('(INFO) | replace file -- ' . $one_sqlfile_name);
        # 置換対象SQLファイルからパスとファイル名を分離して格納
        my ($base_sqlfile_name, $dirname) = fileparse $one_sqlfile_name;
        # 置換対象SQLファイルの情報を格納
    	my $one_sqlfile_info = $sqlfile_info->{$one_sqlfile_name};
    	# 置換対象SQLファイルに対応する置換候補情報を格納
    	my $replacement_candidate_info_of_onefile = $replacement_candidate_info->{$base_sqlfile_name};	
    	# 1置換対象SQLファイルの置換結果を格納するハッシュ
        my %replacement_summary_of_onefile;
    	
    	# 置換対象SQLファイルに対応する置換候補情報が存在しない場合、次のループに移る
    	if(!defined $replacement_candidate_info_of_onefile) {
    	    print_log("(WARN) | No information of $base_sqlfile_name in replacement candidate file");
    	    
    	    # 置換できない置換対象SQLであっても結果をハッシュに格納
    	    $$replacement_summary{$one_sqlfile_name} = {};
    	    #
    		#　1置換対象SQLファイルの情報をそのままハッシュに格納する
    		#
    		$replaced_sqlfile_info{$one_sqlfile_name} = no_replace_ddl_of_onefile($one_sqlfile_info);
    	    next;
    	} 
    	# 置換対象SQLファイルに対応する置換候補情報は存在するが、置換可能なDDLが存在しない場合、
    	# 置換しないそのままの置換対象SQL情報をハッシュに格納する
    	elsif(!defined @$replacement_candidate_info_of_onefile) {
    		print_log("(WARN) | No information of can be replaced DDL in replacement candidate file");
    		
    		# 置換できない置換対象SQLであっても結果をハッシュに格納
    		$$replacement_summary{$one_sqlfile_name} = {};
    		#
    		#　1置換対象SQLファイルの情報をそのままハッシュに格納する
    		#
    		$replaced_sqlfile_info{$one_sqlfile_name} = no_replace_ddl_of_onefile($one_sqlfile_info);
    		next;
    	}
    	
    	#
    	# 1置換対象SQLファイルの情報を置換してハッシュに格納する
    	#
    	$replaced_sqlfile_info{$one_sqlfile_name} = replace_ddl_of_onefile($one_sqlfile_info, $replacement_candidate_info_of_onefile, \%replacement_summary_of_onefile);
        
        #
        # 1置換対象SQLファイルの置換結果をハッシュに格納
        #
        $$replacement_summary{$one_sqlfile_name} = \%replacement_summary_of_onefile;
    }
    return \%replaced_sqlfile_info
}
#####################################################################
# Function: no_replace_ddl_of_onefile
#
# 概要:
# 1置換対象SQLファイルの情報からコメントを含めた
# 文章のみを取り出し配列に格納する
#
#
# パラメータ:
# one_sqlfile_info       - 1置換対象SQLファイルの情報を格納した配列のリファレンス
#
# 戻り値:
# plane_sql_info          - 1置換対象SQLファイルの文章のみを格納した配列のリファレンス
#
#
# 例外:
# なし
#
# 特記事項:
# なし
#
#####################################################################
sub no_replace_ddl_of_onefile {
    # 引数受け取り
    my($one_sqlfile_info) = @_;
    # ファイルの文章のみを格納する配列
    my @plane_sql_info =();
    # SQLファイルの情報を格納した配列を、各要素ごとに処理する
    foreach my $sql_items(@{$one_sqlfile_info}) {
    	# SQLファイルの中身を一行ごとに格納
        my $line_body = $$sql_items[1];
        # 配列に文章を追加
        push(@plane_sql_info, $line_body);
    }
    
    return \@plane_sql_info
}
#####################################################################
# Function: replace_ddl_of_onefile
#
# 概要:
# 1置換対象SQLファイルのDDLを置換候補情報をもとに
# 置換を行う
#
# パラメータ:
# replacement_candidate_info_of_onefile - 1SQLファイルの置換候補情報の情報を格納したハッシュのリファレンス
# one_sqlfile_info                     - 1置換対象SQLファイルの情報を格納したハッシュのリファレンス
#　replacement_summary_of_onefile         - 1置換対象SQLファイルの統計情報を格納したハッシュのリファレンス
#
# 戻り値:
# one_replaced_sqlfile_info          - 1置換後SQLファイルの情報を格納した配列のリファレンス
#
#
# 例外:
# なし
#
# 特記事項:
# なし
#
#####################################################################
sub replace_ddl_of_onefile {
    # 引数受け取り
    my($one_sqlfile_info, $replacement_candidate_info_of_onefile, $replacement_summary_of_onefile) = @_;
	
    # SQLファイルの行番号
    my $line_number = 0;
    # 置換したDDLの情報を格納する配列
    my @one_replaced_sqlfile_info = (); 
    
    # SQLファイルの情報を格納した配列を、各要素ごとに処理する
    foreach my $sql_items(@{$one_sqlfile_info}) {
        # SQLファイルの行番号をインクリメント
        ++$line_number;
        # SQLファイルの中身を一行ごとに格納
        my $line_body = $$sql_items[1];
        
        # 属性がSQLのとき置換処理を実行する
        if($$sql_items[0] eq "SQL") {
            #
            # 1ステートメントごとに置換実行位置に改行コードを目印として付ける
            #
            my $marked_ddl_body = mark_replacement_position($line_body, $replacement_candidate_info_of_onefile, $line_number);
            #
            # 改行コードを付けた1ステートメントを置換する
            #
            my $replaced_ddl_body = replace_ddl_of_oneline($marked_ddl_body, $replacement_candidate_info_of_onefile, $line_number, $replacement_summary_of_onefile);

            push(@one_replaced_sqlfile_info, $replaced_ddl_body);
        }
        #　属性がSQLでなければ置換せずにそのまま格納
        else{
            push(@one_replaced_sqlfile_info, $line_body);
        }
    }
    return \@one_replaced_sqlfile_info;
}
#####################################################################
# Function: mark_replacement_position
#
# 概要:
# 1ステートメントごとに置換実行位置に改行コードを目印として付ける
#
# パラメータ:
# replacement_candidate_info_of_onefile - 1SQLファイルの置換候補情報の情報を格納したハッシュのリファレンス
# one_sqlfile_info                     - 1置換対象SQLファイルの情報を格納したハッシュのリファレンス
# line_number                           - SQLの行番号
#
# 戻り値:
# marked_line_body                      - 置換実行予定箇所に目印を付けた1ステートメント
#
# 例外:
# なし
#
# 特記事項:
# なし
#
#####################################################################
sub mark_replacement_position {
    # 引数受け取り
    my($line_body, $replacement_candidate_info_of_onefile, $line_number) = @_;
    # 改行コード削除
    $line_body =~ s/\n//;
    # SQL文を一文字ずつに分けて配列に格納
    my @sql_body = split(//, $line_body);
    # 置換箇所に改行コードを付けたSQL文を格納する変数
    my $marked_line_body = "";
    # 置換箇所があったどうかを判断するカウンター
    my $count = 0;
    # 置換候補ファイルの情報を使用して、置換を実行するDDLに置換実行位置の目印を付ける
    foreach my $replacement_candidate_items(@{$replacement_candidate_info_of_onefile}) {
        # SQLファイルの行番号と置換候補ファイルにある行番号が一致しない、
        # または置換実行フラグが"no replace"のときは次のループへ移る
        if($line_number != $$replacement_candidate_items[3]) {
            next;
        }
        # 置換箇所が初めて見つかったときのみ置換対象のDDLをログに出力する
    	if($count == 0) {
    		get_loglevel() > 2 and print_log("(DEBUG 3) | [target_ddl]    $line_body");
    	}
    	
        # 置換候補ファイルにあるカラム位置を一行のSQL文を一文字ずつ格納した配列の要素番号とし、
        # 改行コードを付与して、置換実行位置の目印とする
        $sql_body[$$replacement_candidate_items[4]] = "\n".$sql_body[$$replacement_candidate_items[4]];
        get_loglevel() > 4 and print_log("(DEBUG 5) | [mark]    line_bumber $line_number, column_number $$replacement_candidate_items[4], ID = $$replacement_candidate_items[6]");
        
        ++$count;
    }

    # SQLの文字列を一行に戻して格納
    foreach my $sql_char(@sql_body) {
        $marked_line_body .= $sql_char; 
    }

    return $marked_line_body;	
}
#####################################################################
# Function: replace_ddl_of_oneline
#
# 概要:
# 1ステートメントごとに置換実行位置に改行コードを目印として付ける
#
# パラメータ:
# replacement_candidate_info_of_onefile - 1SQLファイルの置換候補情報の情報を格納したハッシュのリファレンス
# marked_ddl_body                       - 置換実行予定箇所に目印をつけた1ステートメント
# line_number                           - SQLの行番号
# replacement_summary_of_onefile         - 1置換対象SQLファイルの統計情報を格納したハッシュのリファレンス
#
# 戻り値:
# replaced_ddl_body          - 置換実行後の1ステートメント
#
# 例外:
# なし
#
# 特記事項:
# 配列 @replacement_candidate_items の各要素には以下の値が入る
# [0] - 置換フラグ(replace, delete, no replace)
# [1] - 置換パターン
# [2]　- 抽出パターン
# [3] - 行数
# [4] - カラム位置
# [5] - フルパス
# [6] - メッセージID
# [7] - タイプ
# [8] - メッセージ
#####################################################################
sub replace_ddl_of_oneline {
	# 引数受け取り
	my($marked_ddl_body, $replacement_candidate_info_of_onefile, $line_number, $replacement_summary_of_onefile) = @_;
	# 抽出結果パターン
    my $pattern = "";
    # 置換後のDDLパターン
    my $replace_pattern = "";
	# 置換後のDDLを初期化
	my $replaced_ddl_body = $marked_ddl_body;
	# 実際に置換、あるいは単純削除されたか判断するカウンター
	my $count = 0;
	# 置換実行位置の目印を利用して置換を実行する
    foreach my $replacement_candidate_items(@{$replacement_candidate_info_of_onefile}) {
        # SQLファイルの行番号と置換候補情報の行番号が一致しないときは次に移る
        if($line_number != $$replacement_candidate_items[3]) {
            next;
        }         
        # 抽出パターンの構造のままでは置換ができないので、余計な情報を除いて実際に使用する抽出パターンを取得
        if($$replacement_candidate_items[2] =~ /\Q(?:[^\w\d_]|\A)\E(.*)\Q(?:[^\w\d_]|\z)\E/
            || $$replacement_candidate_items[2] =~ /\Q\A \s*\E(.*)\Q(?:[^\w\d_]|\z)\E/) {

            $pattern = $1;
        }
        
        # 抽出パターンの先頭に後方参照用の ( と メタ文字 ^ が続けて、あるいは単体で存在すると、
        # 改行コードでパターンマッチできない。
        # そこでメタ文字 ^ を削除して改行コードを先頭に追加する。
        # 例. (^\s*[^\s].*?\s+)NOMINVALUE -> \n(\s*[^\s].*?\s+)NOMINVALUE
        if($pattern =~ /\Q(^\E(.*)/) {
            $pattern = "\n(".$1;
        }
        else {
            $pattern = "\n".$1;
        }
    
        # 置換実行フラグが"replace"のとき置換を実行する
        if($$replacement_candidate_items[0] eq "replace") {
            # 置換後のDDLパターンを格納
            $replace_pattern = $$replacement_candidate_items[1];
            
            if($replaced_ddl_body =~ /$pattern/i) {
                # 抽出パターンの先頭に後方参照があるかどうかで分岐 
                if(defined $1) {
                    $replaced_ddl_body =~ s/$pattern/$1$replace_pattern/i;
                }
                else {
                    $replaced_ddl_body =~ s/$pattern/$replace_pattern/i;
                }
                
                get_loglevel() > 4 and print_log("(DEBUG 5) | [replace] line_bumber $line_number, column_number $$replacement_candidate_items[4], ID = $$replacement_candidate_items[6]");
                
                # メッセージID　ごとの置換回数をカウント
                if(!defined $$replacement_summary_of_onefile{$$replacement_candidate_items[6]}) {
                	$$replacement_summary_of_onefile{$$replacement_candidate_items[6]} = 1;
                }
                else {
                	++$$replacement_summary_of_onefile{$$replacement_candidate_items[6]};
                }
            }
        }
        #　置換実行フラグが"delete"のとき単純削除する
        elsif($$replacement_candidate_items[0] eq "delete") {
            #単純削除実行
            if($replaced_ddl_body =~ /$pattern/i) {
            	# 抽出パターンの先頭に後方参照があるかどうかで分岐 
                if(defined $1) {
                	# 後方参照の最後に余計な空白がある場合は削除               	
                	my $leaving_body = $1;
                	$leaving_body =~ s/\s$//;
                	$replaced_ddl_body =~ s/$pattern/$leaving_body/i;
                }
                else {
                    $replaced_ddl_body =~ s/\s?$pattern//i;
                }
                
                get_loglevel() > 4 and print_log("(DEBUG 5) | [delete]  line_bumber $line_number, column_number $$replacement_candidate_items[4], ID = $$replacement_candidate_items[6]");
                
                # メッセージID　ごとの置換回数をカウント
                if(!defined $$replacement_summary_of_onefile{$$replacement_candidate_items[6]}) {
                	$$replacement_summary_of_onefile{$$replacement_candidate_items[6]} = 1;
                }
                else {
                	++$$replacement_summary_of_onefile{$$replacement_candidate_items[6]};
                }
            }
        }
        ++$count;
    }
    
    # 実際に置換があったときのみ置換後のDDLを出力させる
    if($count > 0) {
            get_loglevel() > 2 and print_log("(DEBUG 3) | [replaced_ddl]  ".$replaced_ddl_body); 
    }
    # 置換後DDLの最後に改行コードを付与
    $replaced_ddl_body .= "\n";  
    
    return $replaced_ddl_body	
}
#####################################################################
# Function: output_replaced_sqlfile
#
# 概要:
# 置換後のDDL情報を格納したハッシュから
# 置換後SQLファイルに出力する
#
# パラメータ:
# replaced_sqlfile_info   - 置換実行後のSQLファイルの情報を格納した配列のリファレンス
# output_dir              - 置換後SQLファイルを出力するディレクトリ
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
sub output_replaced_sqlfile{
    # 引数受け取り
    my ($replaced_sqlfile_info, $output_dir, $encoding_name) = @_;
    # 置換対象SQLファイルに対応するように置換後SQLファイルを出力する
    foreach my $one_replaced_ddl_filename (sort keys %{$replaced_sqlfile_info}) {
    	# 置換対象SQLファイルに対応する置換後DDL情報を取得
    	my $one_replaced_sqlfile_info = $replaced_sqlfile_info->{$one_replaced_ddl_filename};
    	# 置換後対象SQLファイル名からパスを削除
    	my ($base_sqlfile_name, $dirname) = fileparse $one_replaced_ddl_filename;
    	
    	# 出力先ディレクトリが指定されているか確認
    	if(!defined $output_dir) {
    		$output_dir = $dirname;
    	}
    	elsif($output_dir !~ /\/$/) {
    		$output_dir = $output_dir."/";
    	}
    	
    	# 置換後SQLファイル名の付与
    	$base_sqlfile_name =~ s/^.*?_/rpd_/;
    	
    	# ファイルのオープン
        open(my $fh, ">:encoding($encoding_name)",$output_dir.$base_sqlfile_name)
            or croak "Cannot create $output_dir$base_sqlfile_name for write: $!";

        # 一行ごとに書き込み
        foreach my $sql_items(@{$one_replaced_sqlfile_info}) {
            print $fh $sql_items;
        }
        close $fh;
    }
}
#####################################################################
# Function: output_replacemnet_summary
#
# 概要:
# 置換結果の統計情報を標準出力する
#
# パラメータ:
# replacement_summary      - 置換結果の統計情報を格納したハッシュのリファレンス
#
# 戻り値:
# なし
#
# 例外:
# なし
#
# 特記事項:
# なし
#####################################################################
sub output_replacement_summary {
	# 引数受け取り
	my($replacement_summary) = @_;
	# 全置換箇所を数える変数
	my $all_count = 0;
	# 出力のインデント調整用の変数
	my $brank2 = "  ";
	my $brank4 = "    ";
	# 全置換結果の統計情報を格納する変数  
	my $summary_strings = "\nReplacement summary. \n";
	
	# 置換対象SQLファイルごとに統計情報を取得する
	foreach my $replacement_summary_of_onefile (sort keys %{$replacement_summary}) {
		# 置換対象SQLファイルごとに統計情報を格納する変数
		my $summary_strings_of_onefile = "";
		# 置換対象SQLファイルごとにの置換箇所を数える変数
		my $count = 0;
		# 置換対象SQLファイルごとの統計情報が存在するか確認
        if(%{$replacement_summary->{$replacement_summary_of_onefile}}) {
		    
		    # メッセージIDごとに統計情報を取得
		    foreach my $replacement_summary_of_messageID(sort keys %{$replacement_summary->{$replacement_summary_of_onefile}}) {
			    # メッセージIDごとの置換回数を出力
			    $summary_strings_of_onefile .= $brank4.$replacement_summary_of_messageID.", ".$replacement_summary->{$replacement_summary_of_onefile}->{$replacement_summary_of_messageID}."\n";
			    # 置換対象SQLファイルごとにの置換箇所を数える変数にメッセージIDごとの置換回数を加える
			    $count += $replacement_summary->{$replacement_summary_of_onefile}->{$replacement_summary_of_messageID};			
		    }
		}
		# 置換対象SQLファイルごとの全置換回数を出力
		$summary_strings_of_onefile = $brank2."Summary of ".$replacement_summary_of_onefile.", ".$count."\n".$summary_strings_of_onefile;
		
		# 置換対象SQLファイルに一箇所も置換箇所がなかったことを出力
		if($count == 0) {
			$summary_strings_of_onefile .= $brank2."No information of can be replaced ddl correspons to $replacement_summary_of_onefile in replacement candidate file.\n"
		}
		# 全置換結果の統計情報を格納する変数に置換対象SQLファイルごとの統計情報を追加
		$summary_strings .= $summary_strings_of_onefile;
		# 全置換箇所を数える変数に置換対象SQLファイルごとにの置換回数を加える
		$all_count +=  $count;
	}
	# 全置換回数を格納
	$summary_strings .= "Summary of all, ".$all_count;
	
	# 結果を標準出力
	get_loglevel() > 0 and print_summary($summary_strings);
	
}
#####################################################################
# Functions: print_summary
#
# 概要:
# 置換結果の統計情報を標準出力する
#
# パラメータ:
# summary      - 統計情報の文字列
#
# 戻り値:
# なし
#
# 例外:
# なし
#
# 特記事項:
# なし
#####################################################################
sub print_summary {
    my ($summary) = @_;   #引数の格納
	printf(STDOUT "%s %s\n", get_localtime(), $summary);
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
#| (6) -pオプションの判定
#|     オプションを指定して値の指定がない場合は異常終了する。
#| (7) -iオプションの判定
#|     オプションを指定して値の指定がない場合は異常終了する。
#| (8) -ｇオプション指定時の処理
#|     オプションを指定して値の指定がない場合は異常終了する。
#| (9) -oオプション指定時の処理
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
#|  candidatefile =>"個別置換候補ァイル名",
#|  candidatefile_path =>"個別置換候補ファイルのファイルパス",
#|  input_dir =>"置換対象SQLファイル格納ディレクトリ",
#|  suffix_list => "置換対象SQLファイルの拡張子",
#|  input_file_list => "置換対象SQLファイルのリスト",
#|  group_candidatefile =>"一括置換候補ァイル名",
#|  mode =>"動作モード",
#|  verbose =>"出力レベル"
#|  output_dir =>"置換後SQLを出力するディレクトリ"
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
    $option_analytical_result{replacement_candidatefile} = undef;
    $option_analytical_result{group_replacement_candidatefile} = undef;
    $option_analytical_result{input_dir}       = undef;
    $option_analytical_result{output_dir}        = undef;
    $option_analytical_result{verbose}         = 0;
    $option_analytical_result{suffix_list}     = ['sql'];
    $option_analytical_result{input_file_list} = [];

    #
    #GetOptionsでオプションをハッシュに格納
    #
    my $GetOptions_result = GetOptions(
        'encoding=s' => \$option_analytical_result{encodingname},
        'replacementcandidate=s' => \$option_analytical_result{replacement_candidatefile},
        'groupreplacementcandidate=s' => \$option_analytical_result{group_replacement_candidatefile},
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
    # -rオプションの判定
    # -rオプションファイルが存在しない、フィルが存在しない、ファイル読み込み不可の場合はエラー
    #
    if(!defined $option_analytical_result{replacement_candidatefile}) {
        croak("Requires option --replacement-candidate-file");
    }
    elsif($option_analytical_result{replacement_candidatefile}) {
       if(!(-e $option_analytical_result{replacement_candidatefile})) {
           croak("Option --replacement-candidate-file: No such file $option_analytical_result{replacement_candidatefile}");
       }
       elsif(!(-r $option_analytical_result{replacement_candidatefile})) {
           croak("Option --replacement-candidate-file: Access denied $option_analytical_result{replacement_candidatefile}");
       }
    }
    
    #
    #-gオプションの判定
    #ファイルが存在しない、ファイル読み込み不可の場合はエラー
    #
    if($option_analytical_result{group_replacement_candidatefile}) {
        if(!(-e $option_analytical_result{group_replacement_candidatefile})) {
            croak("Option --group-candidate-file: No such file $option_analytical_result{group_replacement_candidatefile}");
        }
        elsif(!(-r $option_analytical_result{group_replacement_candidatefile})) {
            croak("Option --group-candidate-file: Access denied $option_analytical_result{group_replacement_candidatefile}");
        }
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
            else{
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
        croak("Requires option --inputsqldir or inputsqlname");
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

db_ddl_replace version 3.0
The tool to replace DDL of Oracle with DDL of PostgreSQL.

Usage:db_ddl_replace.pl [-e encodingname][-r replacemnetcandidate-file]
[-i inputsqldir[,suffix1[,suffix2]...] ]
[-o outputsqldir][-g group-replacement-candidate-file]
[-h][-v][inputsqlfilename]...

    -e encodingname, --encoding=encodingname  File encoding. The value which can be specified is "utf8" and "shiftjis" and "eucjp". [default: eucjp]
    -r replacemnet-candidate-file, --replacement=replacement-candidate-file Replacement-candaiate-file file name. Use this when you replace individually the DDL to be replaced. 
Specification of this option is mandatory.
    -g group-replacemnet-candidate-file, --group=group-replacement-candidate-file Group-replacement-candaiate-file file name. Use this when you replace the message-ID for each which SQL-files to replace.
    -i inputsqldir, --input=inputsqldir  Input-sql-file directory. [default suffix: sql]
    -o outputsqldir, --output=outputdir     Output-sql-file directory. 
    -h, --help    Print usage and exit.
    -v, --verbose Print progress of the practice to STDERR and replacement result to STDOUT. The value which can be specified is "1","3" and "5". [default: none]
    inputsqlfilename  Input-sql file name.

_USAGE_

}

__END__
