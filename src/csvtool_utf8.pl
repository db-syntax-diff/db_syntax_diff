#!/usr/bin/perl
#
# usage: perl csvtool_utf8.pl <CSV file> <TARGET_CHAR>
#

use File::Basename;
use utf8;
use encoding 'utf-8';
#
# □ Java
#
# 00. フルパス名		PATHNAME
# 01. クラス名			CLASS
# 02. メソッド名		METHOD
# 03. 行数				LINE
# 04. カラム位置		COLUMN
# 05. 非互換ID			ID
# 06. 非互換の分類		TYPE
# 07. エラーレベル		ERRORLV
# 08. 移行作業工数		SCORE
# 09. メッセージ		MESSAGE
# 10. SQL				SQL

$PATHNAME	= 0;
$CLASS		= 1;
$METHOD		= 2;
$LINE		= 3;
$COLUMN		= 4;
$ID			= 5;
$TYPE		= 6;
$ERRORLV	= 7;
$SCORE      = 8;
$MESSAGE	= 9;
$SQL		= 10;
$MAXCOL		= 11;

my @messages = ();
my $line = "";
$" = ',';

open(IN, "<:encoding(shiftjis)" , "$ARGV[0]") or die "file open error.($ARGV[0]:$!)";

# 報告対象の有無を判定
if ( $line = <IN> ) 
{
    do
    {
    	# CSV 解析
    	my $tmp = $line;
    	$tmp =~ s/(?:¥x0D¥x0A|[¥x0D¥x0A])?$/,/;
    	my @onemsg = map {/^"(.*)"$/ ? scalar($_ = $1, s/""/"/g, $_) : $_}
                    ($tmp =~ /("[^"]*(?:""[^"]*)*"|[^,]*),/g);

    	# メッセージとSQLはダブルクォートで括っておく
    	@onemsg[$MESSAGE] = '"' . @onemsg[$MESSAGE] . '"';
    	@onemsg[$SQL] = '"' . @onemsg[$SQL] . '"';

    	#print "@onemsg[$ID] \n";
    	#print "@onemsg\n";
    	push(@messages, \@onemsg);
    }while ( $line = <IN> );

    # 非互換IDでソート
    sort_messages_by_id(@messages);

    # LINE毎にSCOREを集計する。
    sum_score_by_path_and_line(@messages);

    close(IN);
}
else{
    print STDOUT "修正箇所はありませんでした。\n";
    close(IN);
    exit 0;
}

#
# 非互換IDでソートし、集計する。
# 結果を <入力ファイル名>_id.csv に出力する。
#
sub sort_messages_by_id
{
	my @msgs = @_;

	my $arg_encoding = $ARGV[1];
    if ($arg_encoding eq 'eucjp') {$arg_encoding = "euc-jp";}

	# ソート
	my @sort_id = sort { $a->[$ID] cmp $b->[$ID] 				# 非互換ID
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
	
    #各出力ファイルのオープン
	@extlist = ('.csv');
	($fn, $path, $ext) = fileparse($ARGV[0], @extlist);
	my $outfn = $path . $fn . "_id.csv";
	open(OUT, ">:encoding($arg_encoding)" , "$outfn") or die "file open error.($outfn:$!)";
	my $outfn_sjis = $path . $fn . "_id_sjis.csv";
	open(OUT2, ">:encoding(shiftjis)" , "$outfn_sjis") or die "file open error.($outfn_sjis:$!)";
	#メッセージID毎のファイルオープン
#	$outfn3 = $path . $fn. '_' . $id . '.csv';
#	open(OUT3, ">:encoding($arg_encoding)" , "$outfn3") or die "file open error.($outfn3:$!)";
	my $outfn4 = $path . $fn . '_' . $id . '.err';
	open(OUT4, ">:encoding($arg_encoding)" , "$outfn4") or die "file open error.($outfn4:$!)";

	foreach $m (@sort_id)
	{
		#print "id = $id $m->[$ID]\n";
		if ($id ne $m->[$ID])
		{
			# 新しい非互換IDが現れたので、
			# これまで集計した非互換IDを持つメッセージの数を出力。
			print OUT "$m_pre->[$ID],$m_pre->[$TYPE],$m_pre->[$ERRORLV],$m_pre->[$MESSAGE],$count\n";
			print OUT2 "$m_pre->[$ID],$m_pre->[$TYPE],$m_pre->[$ERRORLV],$m_pre->[$MESSAGE],$count\r\n";
			# 新しい非互換IDを設定して、カウンタリセット。
			$id = $m->[$ID];
			$count = 0;

            #メッセージID毎のファイルクローズ
#			close(OUT3);
			close(OUT4);
            #新しいメッセージIDでファイルオープン
#			$outfn3 = $path . $fn. '_' . $id . '.csv';
#			open(OUT3, ">:encoding($arg_encoding)" , "$outfn3") or die "file open error.($outfn3:$!)";
			$outfn4 = $path . $fn . '_' . $id . '.err';
			open(OUT4, ">:encoding($arg_encoding)" , "$outfn4") or die "file open error.($outfn4:$!)";

		}
		$m_pre = $m;
		$count++;

#		$comma = '';
#		for (my $i = 0; $i < $MAXCOL; $i++)
#		{
#			print OUT3 $comma . "$m->[$i]";
#			$comma = ',';
#		}
#		print OUT3 "\n";
		print OUT4 "$m->[$FILE]:$m->[$LINE]:$m->[$COLUMN]:$m->[$MESSAGE]\n";

	}
	
	# 新しい非互換ID。
	print OUT "$m_pre->[$ID],$m_pre->[$TYPE],$m_pre->[$ERRORLV],$m_pre->[$MESSAGE],$count\n";
	print OUT2 "$m_pre->[$ID],$m_pre->[$TYPE],$m_pre->[$ERRORLV],$m_pre->[$MESSAGE],$count\r\n";

    #各出力ファイルのクローズ
	close(OUT);
	close(OUT2);
#	close(OUT3);
	close(OUT4);
}




#
# 各ファイルの行毎のSCOREの合計値を出力する。
# 結果を <入力ファイル名>_score.csv に出力する。
#
sub sum_score_by_path_and_line{
    my @msgs = @_;
    my $arg_encoding = $ARGV[1];
    if ($arg_encoding eq 'eucjp') {$arg_encoding = "euc-jp";}
    # ソート
    my @sort_id_score = sort { $a->[$PATHNAME] cmp $b->[$PATHNAME]    # パス名
                              || $a->[$LINE] <=> $b->[$LINE]          # 行
                             } @msgs;

    #--------------------------
    # 行単位でのSCORE値の算出
    #--------------------------

    # 現在読み込んでいるCSVファイルの1行分のデータ
    my $csv_line = "";
    # 1つ前のデータ
    my $csv_line_pre = "";

    # 初期値を設定
    my $sum_score = 0;
    my $compare_path = $sort_id_score[0][$PATHNAME];
    my $compare_line = $sort_id_score[0][$LINE];

    #出力ファイルのオープン
    @extlist = ('.csv');
    ($fn, $path, $ext) = fileparse($ARGV[0], @extlist);
    my $outfn_score = $path . $fn . "_score.csv";
    open(OUT5, ">:encoding($arg_encoding)" , "$outfn_score") or die "file open error.($outfn_score:$!)";

    foreach $csv_line (@sort_id_score)
    {
        if ($compare_path ne $csv_line->[$PATHNAME] || $compare_line ne $csv_line->[$LINE])
        {
            print OUT5 "$sum_score,$csv_line_pre->[$SQL],$csv_line_pre->[$PATHNAME],$csv_line_pre->[$LINE]\n";
            $compare_path = $csv_line->[$PATHNAME];
            $compare_line = $csv_line->[$LINE];
            $sum_score = 0;
        }
        $csv_line_pre = $csv_line;
        $sum_score = $sum_score + $csv_line->[$SCORE];
    }

    print OUT5 "$sum_score,$csv_line_pre->[$SQL],$csv_line_pre->[$PATHNAME],$csv_line_pre->[$LINE]\n";
    close(OUT5);

}


