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
# 08. メッセージ		MESSAGE
# 09. SQL				SQL

$PATHNAME	= 0;
$CLASS		= 1;
$METHOD		= 2;
$LINE		= 3;
$COLUMN		= 4;
$ID			= 5;
$TYPE		= 6;
$ERRORLV	= 7;
$MESSAGE	= 8;
$SQL		= 9;
$MAXCOL		= 10;

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
