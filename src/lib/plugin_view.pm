#!/usr/bin/perl
#############################################################################
#  Copyright (C) 2011 NTT
#############################################################################

#####################################################################
# Function: plugin_view.pm
#
#
# 概要:
# Oracleのビューの報告を制御し、必要に応じて報告結果を返却する
#
# 特記事項:
#
#
#
#####################################################################

#####################################################################
# Function: checkOracleView
#
#
# 概要:
# Oracleのビュー検出時に呼び出され、設定に応じて報告するかどうかを
# 判断し、報告が必要な設定の場合は報告結果を作成し返却する
# 報告の必要なしの場合は空の報告結果を返却する
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
sub checkOracleView {
    use utf8;
    my ($plugin_ref) = @_;

    my @matching_list = ();               # パターン抽出結果

    my %off_report_view = (               # 報告対象外の名称一覧
#        ''=>"",
       );

    #
    # ビュー名の切り出し
    #
    $plugin_ref->{code}=~m/^([\w\$#]+)/;
    my $code=$1;

    #
    # codeが報告対象かチェックし、報告対象外の場合空の報告結果を返却する
    #
    if(exists $off_report_view{$code}) {
        return @matching_list;
    }

    #
    # 報告情報の格納
    #
    my $one_matching = {
        message_id   => "SQL-119-001",
        pattern_type => $plugin_ref->{pattern_type},
        report_level => "WARNING",
        report_score => "10",
        pattern_body => $plugin_ref->{pattern_name},
        pattern_pos => $plugin_ref->{pattern_pos},
        message_body => $code . "のデータ・ディクショナリ・ビューまたは動的パフォーマンス・ビューを参照しているため、修正が必要です。",
    };

    #
    # 報告情報をリストに格納
    #
    push(@matching_list, $one_matching);

    return @matching_list;
}

1;
