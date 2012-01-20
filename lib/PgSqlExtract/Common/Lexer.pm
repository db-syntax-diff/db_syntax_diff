#!/usr/bin/perl
#############################################################################
#  Copyright (C) 2008-2011 NTT
#############################################################################

#####################################################################
# Function: Lexer.pm
#
#
# 概要:
# 字句解析モジュールである。
# キーワードおよびパターンマッチングによる字句解析を実行する。
# 字句解析を行うキーワード、パターンを定義後、字句解析処理を実行すると
# キーワード、またはパターンにマッチする字句を1件返却する。
# 繰り返し字句解析処理を実行することで、解析対象よりすべての字句を抽出
# することができる。
#
#|　
#|　
#|実行例
#|　
#|my %keywords = ( key1 => 'KEY1_TOKEN', key2 => 'KEY2_TOKEN'
#|               );
#|my @patern   = (q( ([\w_][\w\d_]*) ), 'IDENTIFIER_ORG'
#|               );
#|my $comment  = q( (?: \s+ | //[^\n]*)+ );
#|　
#|my $lex = Lexer->new();
#|my $lex->setPattern({
#|     EXT_KEYWORD => \%keywords,
#|     EXT_PATTERN => \@pattern,
#|     SKIP_PATTERN => $comment
#|   });
#|　
#|$lex->setTarget('key1 key2 ident');
#|　
#|while(my $token = $lex->nextToken) {
#|  do something...;    
#|}
#|　
#|　
# - 字句解析の定義は、キーワードまたは正規表現によるパターン、または
#   その両方で定義することができる。
# - キーワードを指定した場合、そのキーワードと完全一致する文字列を
#   字句として抽出する。これは、マッチングの順番に依存しない字句を
#   抽出する際に使用する。
# - パターンを指定した場合、その正規表現にマッチする文字列を字句と
#   して抽出する。パターンによる抽出の場合、パターンマッチングを行う
#   順番を制御できる。例えば、「<<<」と「<<」をマッチングさせたい
#   場合は、先に「<<<」のマッチングを行わないと誤認識するケースが
#   ある。このようなケースでは、マッチングの順番を制御可能なパターン
#   指定を使用する。
#   キーワード指定と、パターン指定の両者を指定した場合は、キーワード
#   による抽出の後、パターンによる抽出が行われる。
# - コメント文字など字句解析の対象としない部分を正規表現で指定する。
#   この正規表現にマッチする部分は、字句解析の対象とならない。
#
#####################################################################

package PgSqlExtract::Common::Lexer;
use warnings;
use strict;
use Carp;
use PgSqlExtract::Common;
use utf8;
use Encode;
use base qw( Exporter );

our @EXPORT = qw( clear_typedef_name set_typedefname all_clear_typedef_name);

#
# variable: typedefname
# ユーザ定義型の型名を格納するハッシュ。
#
my %typedefname = ();

#####################################################################
# Function: new
#
#
# 概要:
# レクサを新規に生成する
#
# パラメータ:
# なし
#
# 戻り値:
# Lexer - レクサオブジェクト
#
# 例外:
# なし
#
# 特記事項:
# メンバ変数は下記の通り
# | TEXT         - 字句解析対象となる文字列
# | EXT_KEYWORD  - 字句抽出対象となるキーワードとトークンIDのハッシュを格納する
# | EXT_PATTERN  - 字句解析対象となるパターンとトークンIDのリストを格納する
# | SKIP_PATTERN - 字句解析対象となるパターンを格納する
# | POSITION     - 現在の字句解析位置を保持する
# | LINE         - 現在の行番号を保持する
# | VERBOSE      - デバッグ出力の有無を保持する
# | DISABLE      - 一時的に無効とする字句解析対象の定義を保持する
#
#####################################################################
sub new {
    my $class = shift;
    my $self = { };
    ref($class) and $class=ref($class);
    bless($self, $class);
    
    $self->{TEXT} = '';
    $self->{LINE} = 0;
    $self->{DISABLE} = {};
    return $self;
}


#####################################################################
# Function: setPattern
#
#
# 概要:
# 字句解析対象となるキーワード、パターン、および字句解析対象外パターン
# を登録する。
#
# パラメータ:
# register - 字句解析対象を格納したハッシュ
#
# 戻り値:
# なし
#
# 例外:
# なし
#
# 特記事項:
# 字句解析対象を格納したハッシュには以下を設定することができる。
# - EXT_KEYWORD：キーワード(key)とトークンID(value)を格納したハッシュ
# - EXT_PATTERN：字句解析を行うパターンとトークンIDを格納したリスト。この
#   リストには、n番目にパターン、n+1番目にトークンIDを格納する
# - SKIP_PATTERN：字句解析対象外となるパターン文字列を格納する。空白文字や
#   コメント文字などを字句解析対象外として設定する。
#
#####################################################################
sub setPattern {
    my $self = shift;
    my $param = $_[0];

    #
    # キーワード解析パターンの構築
    #
    if($param->{EXT_KEYWORD}) {
        my $keywordsHash = $param->{EXT_KEYWORD};
        
        
        #
        # 1文字のキーワードは文字クラスとして定義する
        #
        my $string_class = '';
        my @patterns = ();
        for my $key (keys %$keywordsHash) {
            if(length($key) == 1 and $key !~ m{ []^-] }xms) {
                $string_class .= $key;
            }
            else {
                length($key) != 1 and $key .= '\b';
                push @patterns, $key;
            }
        }
        if($string_class ne '') {
            $string_class = '[' . $string_class . ']';
            push @patterns, $string_class;
        }
        
        #
        # 指定されたキーワードをor(|)で連結した正規表現を生成する
        #
        my $pattern = join('|', sort {$b cmp $a} @patterns);

        $self->{EXT_KEYWORD} = {
                EXT_KEYWORD_CODE => qr{ $pattern }xms,
                EXT_KEYWORD_HASH => $keywordsHash
        };
    }

    #
    # パターン解析パターンの構築
    #
    if($param->{EXT_PATTERN}) {
        $self->{EXT_PATTERN} = $param->{EXT_PATTERN};
    }

    #
    # 解析対象外パターンの構築
    #
    if($param->{SKIP_PATTERN}) {
        $self->{SKIP_PATTERN} = qr{ $param->{SKIP_PATTERN} }xms;
    }
}

#####################################################################
# Function: disablePattern
#
#
# 概要:
# 指定した字句解析対象を一時的に無効とする。
#
# パラメータ:
# target  - 無効とする字句解析対象名（EXT_PATTERN, SKIP_PATTERN)
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
sub disablePattern {
    my $self = shift;
    my ($target) = @_;
    $self->{DISABLE}->{$target} = $self->{$target};
    delete $self->{$target};
    $self->{VERBOZE} and print "Lexer== disablePattern $target\n";
}


#####################################################################
# Function: enablePattern
#
#
# 概要:
# 一度無効とした字句解析対象を有効とする。
#
# パラメータ:
# target  - 有効とする字句解析対象名（EXT_PATTERN, SKIP_PATTERN)
#
# 戻り値:
# なし
#
# 例外:
# なし
#
# 特記事項:
# - 字句解析対象が無効となっていない場合は、何もしない
#
#####################################################################
sub enablePattern {
    my $self = shift;
    my ($target) = @_;
    if( exists $self->{DISABLE}->{$target}) {
        $self->{$target} = $self->{DISABLE}->{$target};
        delete $self->{DISABLE}->{$target};
        $self->{VERBOZE} and print "Lexer== enablePattern $target\n";
    }
}


#####################################################################
# Function: setTarget
#
#
# 概要:
# 字句解析対象となる文字列を設定する。この時点で解析時の行番号は1に
# 初期化される。
#
# パラメータ:
# text - 字句解析対象となる文字列
#
# 戻り値:
# なし
#
# 例外:
# なし
#
# 特記事項:
# - 1ファイル全体の内容を読み込んだ文字列が指定されると想定する。
#
#####################################################################
sub setTarget {
    my $self = shift;
    $self->{TEXT}     = shift;
    $self->{POSITION} = undef;
    $self->{LINE}     = 1;
}


#####################################################################
# Function: getTarget
#
#
# 概要:
# 字句解析対象となる文字列を返却する。
#
# パラメータ:
# なし
#
# 戻り値:
# 字句解析対象となる文字列
#
# 例外:
# なし
#
# 特記事項:
# なし
#
#####################################################################
sub getTarget {
    my $self = shift;
    return $self->{TEXT};
}

#####################################################################
# Function: getLine
#
#
# 概要:
# 解析箇所の行番号を返却する。
#
# パラメータ:
# なし
#
# 戻り値:
# 行番号
#
# 例外:
# なし
#
# 特記事項:
# なし
#
#####################################################################
sub getLine {
    my $self = shift;
    return $self->{LINE};
}

#####################################################################
# Function: setLine
#
#
# 概要:
# 解析箇所の行番号をlineに変更する
#
# パラメータ:
# line - 行番号
#
# 戻り値:
# なし
#
# 例外:
# なし
#
# 特記事項:
# - 解析箇所は改行文字の直前に位置しているケースが存在するため
#   そのような場合は、次トークンの行番号がlineで指定した行番号
#   より後の行に位置づけられる。
#
#####################################################################
sub setLine {
    my $self = shift;
    $self->{LINE} = $_[0];
}



#####################################################################
# Function: setDebugMode
#
#
# 概要:
# デバッグモードを設定する。値として真値を設定した場合、標準出力に
# デバッグ情報が出力される。
#
# パラメータ:
# be_debug_mode - デバッグモードを指定する真偽値
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
sub setDebugMode {
    my $self = shift;
    $self->{VERBOZE} = shift;
}


#####################################################################
# Function: nextToken
#
# 概要:
# 字句解析を実行し、抽出対象となるキーワード、パターンを1件
# 抽出した場合は、その字句とトークンID、および行番号を返却する。
#
# パラメータ:
# なし
#
# 戻り値:
# token - 抽出した文字列とトークンID、および行番号を格納したハッシュ。
# 全ての字句を抽出した場合は、undef
#
# 例外:
# なし
#
# 特記事項:
# tokenの構造は以下の通り。
# - KEYWORD => トークンID
# - TOKEN   => 抽出した文字列
# - LINE    => 行番号
#
#####################################################################
sub nextToken {
    use bytes;
    my $self = shift;

    #
    # 字句解析開始位置の設定する
    # 初回の解析の場合は、先頭(0番目)とし、2回目以降の解析の場合は、
    # 前回、パターンにマッチした最後の位置より字句解析が開始される
    #
    if(defined $self->{POSITION}) {
        pos($self->{TEXT}) = $self->{POSITION};
    }
    else {
        $self->{POSITION} = 0;
    }
    
    $self->{VERBOZE} and print "Lexer== current pos = $self->{POSITION}\n";
    
    TOKENS: for($self->{TEXT}) {
        
        #
        # すべての字句を抽出した場合は、字句解析を終了する
        #
        $self->{POSITION} >= length($self->{TEXT}) and last TOKENS;
        
        #
        # 空白文字(コメント含む)のスキップ
        #
        if($self->{SKIP_PATTERN}) {
            my $evaluator = $self->{SKIP_PATTERN};
            
            if(m{\G $evaluator }xmsgc) {
                my $token = $1;
                $self->{LINE} += ($token =~ tr/\n//);
                $self->{POSITION} = pos;
                $self->{VERBOZE} and 
                    print "Lexer== detect Comment ($token) pos = $self->{POSITION} linenumber = $self->{LINE}\n";
                redo TOKENS;
            }
        }
        
        #
        # キーワードの切り出し
        #
        if($self->{EXT_KEYWORD}) {
            my $keywordHash = $self->{EXT_KEYWORD}->{EXT_KEYWORD_HASH};
            my $evaluator   = $self->{EXT_KEYWORD}->{EXT_KEYWORD_CODE};

            if(m{\G ($evaluator) }xmsgc) {
                my $token = $1;
                my $keyword = $keywordHash->{$token};
                $self->{POSITION} = pos;
                $self->{VERBOZE} and 
                    print "Lexer== detect $keyword ($token) pos = $self->{POSITION} linenumber = $self->{LINE}\n";
                
                return {KEYWORD => $keyword, TOKEN => decode("utf8", $token), LINE => $self->{LINE}};
            }
        }
        
        #
        # パターンの切り出し
        #
        if($self->{EXT_PATTERN}) {
            my $patternArray = $self->{EXT_PATTERN};
            
            for(my $i = 0; $i < scalar @$patternArray; $i += 2) {
                if(m{\G (${$patternArray}[$i]) }xmsgc) {
                    my $token = $1;
                    my $keyword = ${$patternArray}[$i + 1];
                    $self->{POSITION} = pos;
                    $self->{LINE} += ($token =~ tr/\n//);
                    
                    #
                    # TypeArgumentsの削除
                    #
                    if($keyword eq 'LT_OPR') {
                        $self->{VERBOZE} and 
                            print "Lexer== find special keyword => $keyword ($token) pos = $self->{POSITION} linenumber = $self->{LINE}\n";
                        my $regx_argments = qr{[]\w\d_\$\.,\[\?\s]+?}xms;
                        my $pair = 1;
                        my $gtpos;
                        while($pair != 0) {
                            if(m{\G  $regx_argments [<] }xmsgc) {
                                $pair++;
                            } elsif(m{\G $regx_argments? [>] }xmsgc) {
                                $gtpos = pos;
                                $pair--;
                            } else {
                                $pair = -1;
                                last;
                            }
                        }
                        if(m{\G $regx_argments? [>] }xmsgc) {
                            $pair--;
                        }
                        if($pair == 0) {
                            pos($self->{TEXT}) = $gtpos;
                            $self->{VERBOZE} and 
                                print "Lexer== reset pos $gtpos linenumber = $self->{LINE}\n";
                            redo TOKENS;
                        }
                    }
                    #
                    # typedef判定
                    #
                    if($keyword eq 'IDENTIFIER_ORG') {
                        if(exists $typedefname{$token}) {
                            return {KEYWORD => 'TNAME_TOKEN', TOKEN => decode("utf8", $token), LINE => $self->{LINE}};
                        }
                    }
                    $self->{VERBOZE} and 
                        print "Lexer== detect $keyword ($token) pos = $self->{POSITION} linenumber = $self->{LINE}\n";

                    return {KEYWORD => $keyword, TOKEN => decode("utf8", $token), LINE => $self->{LINE}};
                }
            }
        }
        
        #
        # その他文字列の切り出し
        #
        if(m{\G (.)}xmsgc) {
            my $token = $1;
            $self->{POSITION} = pos;

            $self->{VERBOZE} and 
            print "Lexer== detect OTHER ($token) pos = $self->{POSITION} linenumber = $self->{LINE}\n";
                
            return {KEYWORD => 'OTHER', TOKEN => decode("utf8", $token), LINE => $self->{LINE}};
                
        }
    }
    
    #
    # 字句解析の終了
    #
    $self->{VERBOZE} and 
            print "Lexer== finished lexer   pos = $self->{POSITION} linenumber = $self->{LINE}\n";
    return;
}

#####################################################################
# Function: set_typedefname
#
#
# 概要:
#
# ユーザ定義型の型名を格納する。
#
# パラメータ:
# tname - ユーザ定義型の型名
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
sub set_typedefname {
    my $self = shift;
    my ($tname,$flag) = @_;#標準ヘッダの型と区別するための引数の追加
    
    # 型に重複が見られたらメッセージを出力
	if(exists $typedefname{$tname}){
	    print_log('duplicative type:' . $tname);
	}
	
    %typedefname = ( %typedefname , $tname=>"$flag" );

}

#####################################################################
# Function: clear_typedef_name
#
#
# 概要:
#
# ユーザ定義型の型名の格納変数のみを初期化する。
# Cの標準ヘッダとProCの型は初期化しない。
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
sub clear_typedef_name {
    while((my $key,my $value) = each(%typedefname)){
        if($value != 1){
            delete $typedefname{$key};#ユーザ定義型の型名のみハッシュから削除
        }
    }
}

#####################################################################
# Function: all_clear_typedef_name
#
#
# 概要:
#
# %typedefnameを初期化する。
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
sub all_clear_typedef_name {
    %typedefname = ();
}

1;
