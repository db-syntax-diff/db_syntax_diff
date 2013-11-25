#!/usr/bin/perl
#############################################################################
#  Copyright (C) 2008-2013 NTT
#############################################################################

#####################################################################
# Function: db_syntax_diff.pl
#
#
# 概要:
# Oracle上で稼動するアプリケーションをPostgreSQLへ移行する場合の修正
# が必要な項目の概要を報告する。
# アプリケーションのソースコードを静的に解析し、前述の情報を収集し、
# 出力する。
#
# 特記事項:
# 本モジュールは、SQL抽出支援ツール(Java対応版)のユーザインタフェース
# となる。
#
#####################################################################


use warnings;
use strict;
use Carp;
use Getopt::Long qw(:config no_ignore_case);
use File::Path qw(rmtree);
use File::Basename;
use FindBin;
use PgSqlExtract::Loader qw(load_definition_file);
use PgSqlExtract::Analyzer qw(analyze_input_files);
use PgSqlExtract::InputAnalyzer qw(analyze_input_files_java create_target_dictionary);
use PgSqlExtract::Extractor qw(extract_pattern);
use PgSqlExtract::Reporter qw(set_metadata set_starttime set_finishtime 
create_report write_report write_report_by_plane);
use PgSqlExtract::Common;
use utf8;

main();

1;

#####################################################################
# Function: main
#
#
# 概要:
#
# SQL抽出支援ツール実行の主制御を行う。
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
sub main {
    
    #
    # 終了コード 
    #
    my $exit_status = 0;                   # 終了コード

    #
    # 報告結果配列（出力用） 
    #
    my $result_ref = [];                   # 報告結果配列（出力用）

    #
    # オプション解析結果 
    #
    my $options = undef;                   # オプション解析結果

    eval {
        
        #
        # 実行開始時間の取得およびReporterへの設定
        #
        set_starttime(get_localtime());

        #
        # パラメータ文字列の取得
        #
        set_metadata(REPORT_PARAMETER_NAME, join(" ", @ARGV));

        #
        # オプション解析の実行
        #
        $options = analyze_option();
        
        get_loglevel() > 0 and print_log('(INFO) db_syntax_diff was started.');
               
        #
        # 報告対象定義ファイルの読み込み
        #
        get_loglevel() > 0 and print_log('(INFO) [start]  loading definition file.');
        #
        # 
        # パターン辞書のリファレンス。
        #
        my $pattern_dic_ref = load_definition_file($options->{deffile}, $options->{filter});
        get_loglevel() > 0 and print_log('(INFO) [finish] loading definition file.');
        
        #
        # 抽出対象ファイルを解析し、パターン抽出に必要となる情報を収集する
        #
        get_loglevel() > 0 and print_log('(INFO) [start]  analyze input files.');

        #
        # Javaモードとそれ以外を判定
        #
        if($options->{mode} eq MODE_JAVA) {
            #
            # 入力ファイルを格納するディレクトリ内に存在する、全ての抽出対象ファイル名
            # を格納するリストを作成する。
            #
            my $file_name_list = analyze_input_files_java(
                $options->{input_dir},
                $options->{suffix_list},
                $options->{input_file_list},
                $options->{encodingname},
                \$options->{mode}
            );
            get_loglevel() > 0 and print_log('(INFO) [finish] analyze input files.');
            
            for my $file_name (@{$file_name_list}) {
                #
                # 入力ファイルに対して抽出対象辞書を作成する。
                #
                my $func_dic_ref = create_target_dictionary($file_name, $options->{encodingname});
                #
                # 式解析結果のすべてのコード情報に対して、パターン抽出を
                # 実行する
                #
                get_loglevel() > 0 and print_log('(INFO) [start]  extract pattern.');
                extract_pattern($func_dic_ref, $pattern_dic_ref, 
                                        $options->{mode}, $result_ref);
                get_loglevel() > 0 and print_log('(INFO) [finish] extract pattern.');
            }
        } else {
            #
            # variable: func_dic_ref
            # 関数辞書のリファレンス 
            #
            my $func_dic_ref = analyze_input_files(
                $options->{input_dir},
                $options->{suffix_list},
                $options->{input_file_list},
                $options->{encodingname},
                \$options->{mode},
                $options->{include_dir_list},
                $options->{deffile_path}
            );
            get_loglevel() > 0 and print_log('(INFO) [finish] analyze input files.');
            #
            # 関数辞書に格納されているすべてのコード情報に対して、パターン抽出を
            # 実行する
            #
            get_loglevel() > 0 and print_log('(INFO) [start]  extract pattern.');
            extract_pattern($func_dic_ref, $pattern_dic_ref, 
                                    $options->{mode}, $result_ref);
            get_loglevel() > 0 and print_log('(INFO) [finish] extract pattern.');
        }
        #
        # 報告結果をXML形式に成形する
        # 実行終了時間の取得およびReporterへの設定も同時に行う
        #
        get_loglevel() > 0 and print_log('(INFO) [start]  creating report.');
        my $report_dom = create_report($result_ref, $options->{encodingname},$options->{mode});
        set_finishtime($report_dom, get_localtime());
        get_loglevel() > 0 and print_log('(INFO) [finish] creating report.');
        
        #
        # 報告結果の内容を指定されたエンコーディングに変換して、出力する
        #
        get_loglevel() > 0 and print_log('(INFO) [start]  writing report.');
        $exit_status = write_report($report_dom, $options->{outfile});
        get_loglevel() > 0 and print_log('(INFO) [finish] writing report.');
    };
    
    #
    # パターン抽出中に例外が発生した場合は、その時点の報告内容を出力する
    #
    if($@) {
        $exit_status = 1;
        print_log($@);

        #
        # 報告結果が存在する場合は出力を行う
        #
        if(scalar @{$result_ref} > 0) {
            write_report_by_plane($result_ref, $options->{encodingname});
        }
    }
    get_loglevel() > 0 and print_log('(INFO) db_syntax_diff was finished.');
    #
    # 中間ファイルの削除
    #
    eval{
        rmtree([ANALYZE_TEMPDIR]);
    };  
    if($@) {
        $exit_status = 1;
        print_log($@);
    }
    exit($exit_status);
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
#| (6) -dオプションの判定
#|     オプションを指定して値の指定がない場合は異常終了する。
#| (7) -iオプションの判定
#|     オプションを指定して値の指定がない場合は異常終了する。
#| (8) -oオプション指定時の処理
#|     オプションを指定して値の指定がない場合は異常終了する。
#|     -oオプションが指定された場合、指定されたファイルのオープンチェックを行う。
#| (9) -fオプションの判定
#|     「oracle8」、「oracle8i」以外の値か、オプションを指定して値の指定がない場合は異常終了する。
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
#|  deffile =>"報告対象定義ファイル名",
#|  deffile_path =>"報告対象定義ファイルのファイルパス",
#|  input_dir =>"抽出対象ファイル格納ディレクトリ",
#|  suffix_list => "抽出対象ファイルの拡張子",
#|  input_file_list => "抽出対象ファイルのリスト",
#|  outfile =>"報告結果ファイル名",
#|  filter =>"フィルタキーワード",
#|  mode =>"動作モード",
#|  verbose =>"出力レベル"
#|  include_dir_list =>"インクルードパスのリスト"
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
    $option_analytical_result{deffile}         = $FindBin::Bin . "/../config/extractdef.xml";
    $option_analytical_result{deffile_path}    = '';
    $option_analytical_result{input_dir}       = undef;
    $option_analytical_result{outfile}         = undef;
    $option_analytical_result{filter}          = FILTER_ALL;
    $option_analytical_result{mode}            = MODE_JAVA;
    $option_analytical_result{verbose}         = 0;
    $option_analytical_result{suffix_list}     = [];
    $option_analytical_result{input_file_list} = [];
    $option_analytical_result{include_dir_list} = undef;

    #
    #GetOptionsでオプションをハッシュに格納
    #
    my $GetOptions_result = GetOptions(
        'encoding=s' => \$option_analytical_result{encodingname},
        'define=s' => \$option_analytical_result{deffile},
        'inputsourcedir=s' => \$option_analytical_result{input_dir},
        'output=s' => \$option_analytical_result{outfile},
        'filter=s' => \$option_analytical_result{filter},
        'mode=s' => \$option_analytical_result{mode},
        'help' => \$help_option_flg,
        'verbose:1' => \$option_analytical_result{verbose},
        'Include=s' => \$option_analytical_result{include_dir_list}
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
    #-dオプションの判定
    #ファイルが存在しない、ファイル読み込み不可の場合はエラー
    #また、報告対象定義ファイルのファイルパスを取得
    #
    if($option_analytical_result{deffile}) {
        if(!(-e $option_analytical_result{deffile})) {
            croak("Option --definition-file: No such file $option_analytical_result{deffile}");
        }
        elsif(!(-r $option_analytical_result{deffile})) {
            croak("Option --definition-file: Access denied $option_analytical_result{deffile}");
        }
    }
    $option_analytical_result{deffile_path} = dirname($option_analytical_result{deffile});

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
        
        #ディレクトリの存在有無を確認する
        if(!(-d $option_analytical_result{input_dir})) {
            croak("Option --inputsourcedir: No such directory $option_analytical_result{input_dir}");
        }
    }
    #
    #-oオプションの判定
    #
    if($option_analytical_result{outfile}) {
        open(FILEHANDLEOUT, "> $option_analytical_result{outfile}") 
            || croak "Option --outfile: Cannot create file $option_analytical_result{outfile} ($!)\n";
        close(FILEHANDLEOUT);
    }
    #
    #-fオプションの判定
    #
    if(     $option_analytical_result{filter} ne FILTER_ORACLE8
        and $option_analytical_result{filter} ne FILTER_ORACLE8i
        and $option_analytical_result{filter} ne FILTER_ALL){
        croak("Option --filter: Invalid argument");
    }
    #
    #-mオプションの判定
    #
    if($option_analytical_result{mode} ne MODE_C
        and $option_analytical_result{mode} ne MODE_SQL
        and $option_analytical_result{mode} ne MODE_SIMPLE
        and $option_analytical_result{mode} ne MODE_JAVA){
        croak("Option --mode: Invalid argument");
    }

    #
    # -vオプションの取得
    # -vオプションに数値が指定されている場合はその数値をログ出力
    # レベルとして設定する
    #
    set_loglevel($option_analytical_result{verbose});

    #
    #-lオプションの判定
    #ディレクトリが存在しない場合はエラー
    #
    if($option_analytical_result{include_dir_list}) {
        my @include_dir_list = split(/,/, $option_analytical_result{include_dir_list});
        if($#include_dir_list >= 0) {
            foreach my $includedir (@include_dir_list){
                #ディレクトリの存在有無を確認する
                if(!(-d $includedir)) {
                    croak("Option --Include: No such directory $includedir");
                }                
            }
            $option_analytical_result{include_dir_list} = \@include_dir_list;
        }
    }



    #
    # 抽出対象ファイルのリスト指定を取得する
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
    if(    !defined $option_analytical_result{input_dir}
       and scalar @{$option_analytical_result{input_file_list}} == 0 ) {
        croak("Requires option --inputsourcedir or inputfilename");
    }
    
    #
    #戻り値の設定
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

db_syntax_diff version 3.0
The SQL analyzer for converting to PostgreSQL.

Usage:db_syntax_diff.pl [-e encodingname][-d definition-file]
[-i inputsourcedir[,suffix1[,suffix2]...] ]
[-o outfile][-f filterword][-m modename]
[-I includedir[,includedir1[,includedir2]...]][-h][-v [loglevel]]
[inputfilename]...

    -e encodingname,    --encoding=encodingname   File encoding. The value which can be specified is "utf8" and "shiftjis" and "eucjp". [default: eucjp]
    -d definition-file, --define=definition-file  Definition-file file name. [default: <install_directory>/config/extractdef.xml]
    -i inputsourcedir,  --input=inputsourcedir    Input-file directry.
    -o outfile,    --output=outfile      Output-file file name. [default: STDOUT]
    -f filterword, --filter=filterword   Pattern filterword. The value which can be specified is "oracle8" and "oracle8i". [default: ALL]
    -m modename,   --mode=modename       File type of source file. The value which can be specified is "c" and "sql" and "cpp" and "java". [default: java]
    -I includedir, --Include=includedir  Add the directory includedir to the list of directories to be searched for header files. [default: ./]
    -h, --help     Print usage and exit.
    -v, --verbose  Print progress of the practice to STDERR. The value which can be specified is "1" and "3" and "5" and "7". [default: none]
    inputfilename  Input-file file name.

_USAGE_

}
