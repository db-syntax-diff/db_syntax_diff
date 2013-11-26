#!/usr/bin/perl
#############################################################################
#  Copyright (C) 2013 NTT
#############################################################################

##################################################################
# Function: make_group_replacement_candidate.pl
#
#
# 概要:
# 個別置換候補ファイルを一括置換候補ファイルに変換する。
#
# 特記事項:
# 特になし
# 
# usage: perl make_group_replacement_candaiate.pl <CSV file>
#
###################################################################

use File::Basename;
use utf8;
use encoding 'utf-8';
use strict;

# 00. フルパス名		PATHNAME
# 01. クラス名			CLASS
# 02. メソッド名		METHOD
# 03. 行数			LINE
# 04. カラム位置		COLUMN
# 05. メッセージID		ID
# 06. 非互換の分類	TYPE
# 07. エラーレベル		ERRORLV
# 08. メッセージ		MESSAGE

my $REPLACE_FLAG = 0;
my $REPLACE_PATTERN = 1;
my $PATTERN = 2;
my $LINE= 3;
my $COLUMN = 4;
my $PATHNAME = 5;
my $ID = 6;
my $TYPE = 7;
my $MESSAGE = 8;

my @messages = ();
my $line = "";
$" = ',';

open(IN, "<:encoding(utf8)" , "$ARGV[0]") or die "File open error $ARGV[0]($!)";

# 置換候補情報の有無を判定
if ( $line = <IN> ) 
{
    do
    {
    	# CSV 解析
    	my $tmp = $line;
    	$tmp =~ s/(?:¥x0D¥x0A|[¥x0D¥x0A])?$/,/;
    	my @onemsg = map {/^"(.*)"$/ ? scalar($_ = $1, s/""/"/g, $_) : $_}
                    ($tmp =~ /("[^"]*(?:""[^"]*)*"|[^,]*),/g);

    	# SQL抽出パターンとメッセージはダブルクォートで括っておく
    	@onemsg[$PATTERN] = '"' . @onemsg[$PATTERN] . '"';
    	@onemsg[$MESSAGE] = '"' . @onemsg[$MESSAGE] . '"';

    	if($onemsg[$REPLACE_FLAG] eq "replace" || $onemsg[$REPLACE_FLAG] eq "delete") {
    	    push(@messages, \@onemsg);
    	}
    }while ( $line = <IN> );

    if(!@messages) {
        print STDOUT "No information of replaceable DDL in replacement candidate file.\n";
        close(IN);
        exit 0;
    }

    # メッセージIDでソート
    sort_messages_by_id(@messages);

    close(IN);
}
else{
    print STDOUT "No information of replaceable DDL in replacement candidate file.\n";
    close(IN);
    exit 0;
}

#
# メッセージIDでソートし、集計する。
#
sub sort_messages_by_id
{
	my @msgs = @_;

	# ソート
	my @sort_id = sort { $a->[$ID] cmp $b->[$ID] 				# メッセージID
						|| $a->[$PATHNAME] cmp $b->[$PATHNAME]	# パス名
						|| $a->[$LINE] <=> $b->[$LINE] 			# 行
						|| $a->[$COLUMN] <=> $b->[$COLUMN] 		# カラム
						} @msgs;

	# いまのメッセージ
	my $m = "";
	# 1つ前のメッセージ
	my $m_pre = "";
	my $count = 0;

	my $id = $sort_id[0][$ID];
	#print "id = $id\n";
	
    #出力ファイルのオープン
	my @extlist = ('.csv');
	my($fn, $path, $ext) = fileparse($ARGV[0], @extlist);
	my $outfn = $path . "group_replacement_candidate.csv";
	open(OUT, ">:encoding(utf8)" , "$outfn") or die "Cannot create $outfn for write:$!";

	foreach $m (@sort_id)
	{
		#print "id = $id $m->[$ID]\n";
		if ($id ne $m->[$ID])
		{
			# 新しいメッセージIDが現れたので、
			# これまで集計したメッセージIDを持つメッセージの数を出力。
			
			print OUT "$m_pre->[$REPLACE_FLAG],$m_pre->[$ID],$m_pre->[$REPLACE_PATTERN],$m_pre->[$PATTERN],$m_pre->[$TYPE],$m_pre->[$MESSAGE],$count\n";
			# 新しいメッセージIDを設定して、カウンタリセット。
			$id = $m->[$ID];
			$count = 0;

		}
		$m_pre = $m;
		$count++;

	}
	
	# 新しいメッセージID。
	print OUT "$m_pre->[$REPLACE_FLAG],$m_pre->[$ID],$m_pre->[$REPLACE_PATTERN],$m_pre->[$PATTERN],$m_pre->[$TYPE],$m_pre->[$MESSAGE],$count\n";

    #出力ファイルのクローズ
	close(OUT);

}
