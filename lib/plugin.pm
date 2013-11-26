#!/usr/bin/perl
#############################################################################
#  Copyright (C) 2010 NTT
#############################################################################

#####################################################################
# Function: plugin.pm
#
#
# 概要:
# TO_関数(TO_CHAR、TO_DATE、TO_NUMBER)の引数を解析し、
# 引数2以外の場合と指定外の書式が記述されている場合は報告結果を作成し
# 返却する。
#
# 特記事項:
#
#
#
#####################################################################

#####################################################################
# Function: checkToFunction
#
#
# 概要:
# TO_関数(TO_CHAR、TO_DATE、TO_NUMBER)の引数を解析し、
# 引数2以外の場合と指定外の書式が記述されている場合は報告結果を作成し
# 返却する。
#
# パラメータ:
# plugin_ref - プラグイン情報。以下の情報を格納するハッシュである
# - code - TARGETの文字列
# - pattern_type - 抽出パターン種別
# - pattern_name - 抽出パターン定義
# - pattern_pos - パターンを検出した先頭位置
# 
# 戻り値:
# matching_list - 合致パターンの基本情報のリスト
#
# 例外:
# なし
#
# 特記事項:
# 合致パターンの情報は以下の構造を持つ。
#|<合致パターンの基本情報>
#|{
#|  message_id => "メッセージID",
#|  pattern_type => "抽出パターン種別",
#|  report_level => "報告レベル",
#|  pattern_body => "抽出パターン定義",
#|  message_body => "メッセージ内容"
#|  pattern_pos => "パターンを検出した先頭位置"
#|}
#|
#
#####################################################################
sub checkToFunction {
    use utf8;
    my ($plugin_ref) = @_;
    
    my @matching_list = ();               # パターン抽出結果
    my $function_name = undef;          # 関数名
    my $first_argument = undef;         # 第一引数
    my $second_argument = undef;        # 第二引数
    my $third_argument = undef;         # 第三引数
    
    my $brace_number = 0;                   # 丸括弧のネスト数
    my $sqr_number = 0;                     # 角括弧のネスト数
    my $literal_number = 0;                 # リテラル内かのフラグ
    my $argument_top_pos = 0;               # 引数の先頭位置格納

    #
    #コードを一文字づつの配列に展開
    #
    my @code_array = split(//, $plugin_ref->{code});
    my $len = scalar @code_array;
    
    #
    #関数名、引数を抽出する
    #
    for(my $i = 0; $i < $len; $i++) {
        
        my $str = $code_array[$i];

        if($str eq '(') {
            #
            #1つ目の開き括弧なら括弧前までを関数名として格納、括弧後を第一引数の先頭位置に登録
            #
            if($brace_number == 0){
                $function_name = substr($plugin_ref->{code}, 0, $i);
                $argument_top_pos = $i + 1;
            }
            #
            #リテラル内でなければネスト数を増加
            #
            if($literal_number == 0){
                $brace_number++;
            }
        }
        elsif($str eq ')') {
            #
            #リテラル内でなければネスト数を減少
            #
            if($literal_number == 0){
                $brace_number--;
                #
                #丸括弧のネスト数が0ならば、引数として登録
                #
                if($literal_number == 0 and $brace_number == 0){
                    if(!defined $first_argument){
                        $first_argument = substr($plugin_ref->{code}, $argument_top_pos, $i - $argument_top_pos);
                    }elsif(!defined $second_argument){
                        $second_argument = substr($plugin_ref->{code}, $argument_top_pos, $i - $argument_top_pos);
                    }elsif(!defined $third_argument){
                        $third_argument = substr($plugin_ref->{code}, $argument_top_pos, $i - $argument_top_pos);
                    }
                    last;
                }
            }
        }
        elsif($str eq "'") {
            #
            #リテラル内でなければ以降をリテラルとしてフラグを設定
            #
            if($literal_number == 0){
                $literal_number++;
            }else{
                #
                #エスケープされていない場合はリテラル終端としてフラグを無効に設定
                #
                if($code_array[$i + 1] eq "'"){
                    $i++;
                }else{
                    $literal_number--;
                }
            }
        }
        elsif($str eq ',') {
            #
            #リテラル内でなく、丸括弧のネスト数が1ならば、引数として登録
            #Oracle構文上引数は3が上限のため、
            #カンマ区切りでは引数2まで格納し、それ以降は全て引数3に格納する
            #
            if($literal_number == 0 and $brace_number == 1){
                if(!defined $first_argument){
                    $first_argument = substr($plugin_ref->{code}, $argument_top_pos, $i - $argument_top_pos);
                    #
                    #次の位置を引数の先頭位置に登録
                    #
                    $argument_top_pos = $i + 1;
                }elsif(!defined $second_argument){
                    $second_argument = substr($plugin_ref->{code}, $argument_top_pos, $i - $argument_top_pos);
                    #
                    #次の位置を引数の先頭位置に登録
                    #
                    $argument_top_pos = $i + 1;
                }
            }
        }
    }
    #
    # 関数名の判定、関数名に合わせてmessage_idを設定
    #
    my $message_id = undef;
    if($function_name =~ m/TO_CHAR/i){
        $message_id = "FNC-088";
    }elsif($function_name =~ m/TO_DATE/i){
        $message_id = "FNC-089";
    }elsif($function_name =~ m/TO_NUMBER/i){
        $message_id = "FNC-092";
    }
    
    
    #
    # 引数のチェック(引数が1つの場合)
    #
    if(!defined $second_argument){
        #
        # 報告情報の格納
        #
        my $one_matching = {
            message_id   => $message_id . "-001",
            pattern_type => $plugin_ref->{pattern_type},
            report_level => "CHECK_LOW2",
            pattern_body => $plugin_ref->{pattern_name},
            pattern_pos => $plugin_ref->{pattern_pos},
            message_body => $function_name . "関数の1引数は未サポートです。",
        };
        #
        # 報告情報をリストに格納
        #
        push(@matching_list, $one_matching);
    #
    # 引数のチェック(引数が3つの場合)
    #
    }elsif(defined $third_argument){
        #
        # 報告情報の格納
        #
        my $one_matching = {
            message_id   => $message_id . "-002",
            pattern_type => $plugin_ref->{pattern_type},
            report_level => "ERROR LV4",
            pattern_body => $plugin_ref->{pattern_name},
            pattern_pos => $plugin_ref->{pattern_pos},
            message_body => $function_name . "関数の3引数は未サポートです。",
        };
        #
        # 報告情報をリストに格納
        #
        push(@matching_list, $one_matching);
    }
    #
    # 書式のチェック
    #
    if(defined $second_argument and $second_argument !~ m/'(?:YYYY|YY|MM|DD|HH12|HH24|MI|SS|FM9+|\/|-|\s|:|\.)+'/ismo){
        #
        # 報告情報の格納
        #
        my $one_matching = {
                message_id   => $message_id . "-003",
                pattern_type => $plugin_ref->{pattern_type},
                report_level => "ERROR LV4",
                pattern_body => $plugin_ref->{pattern_name},
                pattern_pos => $plugin_ref->{pattern_pos},
                message_body => $function_name . "関数の書式は確認対象です。",
        };
        #
        # 報告情報をリストに格納
        #
        push(@matching_list, $one_matching);
    }

    return @matching_list;
}

1;
