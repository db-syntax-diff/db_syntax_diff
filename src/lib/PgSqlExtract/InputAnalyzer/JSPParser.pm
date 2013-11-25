#############################################################################
#  Copyright (C) 2008 NTT
#############################################################################

#####################################################################
# Function: JSPParser.pm
#
#
# 概要:
# JSPソースコードよりJava言語部分を抽出し、抽出した内容を擬似的なJava
# ソースコードへ出力する。
# 擬似的なJavaソースコードは、ファイルとして出力は行わず、メモリ上の
# データとして存在する。
# 
# 特記事項:
#
# なし
#
#####################################################################

package PgSqlExtract::InputAnalyzer::JSPParser;

use warnings;
no warnings "recursion";
use strict;
use Carp;
use base qw(Exporter);
use utf8;

use PgSqlExtract::Common::Lexer;
use PgSqlExtract::Common;

#
# variable: taglist
# タグリスト：字句解析での抽出対象と、対応する処理の定義である。
# 以下の定義をひとまとまりとして、ハッシュ形式で管理する。
# - 抽出対象のトークンID(ハッシュキー)。
# - 字句解析で抽出する内容(正規表現による定義)および抽出した場合に実行する処理。
#
my %taglist = (
    #
    # リテラルパターン
    # 文字列リテラル内のタグを誤認識しないように、レクサで抽出する
    #
    1 => {
        pattern => qr{ ["] ( (?: [^"\\\\]|\\\\["\\\\] )* ) ["] }xms,
        method  => \&addCode
    },

    #
    # 開始タグ(Declaration構文定義)
    #
    2 => {
        pattern => qr{(?: <%! | <jsp:declaration>) }xms,
        method  => \&setDeclaration
    },

    #
    # 開始タグ(Expression構文定義)
    #
    3 => {
        pattern => qr{(?: <%= | <jsp:expression>) }xms,
        method  => \&setExpression
    },

    #
    # 開始タグ(Directives構文定義)
    # タグの誤認識を防ぐため定義する
    # 実際には何も処理をしない
    #
    4 => {
        pattern => qr{ <%@ }xms,
        method  => sub {
            my $self = shift;
            $self->{ADD_METHOD} = sub {};
        }
    },


    #
    # 開始タグ(Scriptlet構文定義)
    #
    5 => {
        pattern => qr{(?: <% | <jsp:scriptlet>) }xms,
        method  => \&setScriptlet
    },

    #
    # 終了タグ(共通)
    #
    6 => {
        pattern => qr{ (?: %> | </jsp: (?: declaration | expression | scriptlet ) > ) }xms,
        method  => \&createCode
    },

    #
    # その他のすべてのコード(1)
    # ただし終了タグや開始タグ、文字列の開始を含めないように「<%"」以外の任意の文字とする
    #
    7 => {
        pattern => qr{ [^<%"]+ }xms,
        method  => \&addCode
    },

    #
    # その他のすべてのコード(2)
    # その他の全てのコード(1)は、「<%」の直前で一旦切り出すため、終了タグ以外の
    # %文字はこれにマッチする
    #
    8 => {
        pattern => qr{ [<%] }xms,
        method  => \&addCode
    },

);

#
# variable: commentPattern
# JSPにおいて字句解析で解析対象外となるパターンを正規表現で定義する。
# 解析対象外とするのは以下の通り。
# - 空白、HT(水平タブ)、FF(フォームフィード)、改行(CR, LF, CR+LF)
# - XML形式のコメント
#
my $commentPattern = q(
    ( (?:  \s+
           | <!--.*?-->
           | <%--.*?--%>
      )+
    )
);

#
# variable: javaCommentPattern
# Javaにおいて字句解析で解析対象外となるパターンを正規表現で定義する。
# 
#
my $javaCommentPattern = q(
    ( (?:  \s+
           | //[^\n]*
           | /\*.*?\*/
      )+
    )
);


#
# variable: G_fileCnt
# クラス名作成時のファイルカウント定義である。
# 疑似的なJavaソースコード作成時のクラス名作成時に使用する。
# 具体的には下記のように命名される。
# - JSP1,JSP2,JSP3・・・
#
my $G_fileCnt;

#
# variable: G_code
# 擬似的なJavaソースコード文字列のテンプレートである。テンプレート内容
# は以下である。
#
#|　
#|　
#| public class %s(*1) {
#|     public void service() {
#|         %s(*2)
#|     }
#|     %s(*3)
#| }
#|　
#|　
#| (*1)は、G_fileCnt番号を元に生成されるクラス名が埋め込まれる。
#| (*2)は、Scriptlet構文、Expression構文より抽出した内容が埋め込まれる。
#| (*3)は、Declaration構文より抽出した内容が埋め込まれる。
#
my $G_code = do {local $/; <DATA>};


#####################################################################
# Function: new
#
#
# 概要:
# JSPパーサを新規に生成する。
#
# パラメータ:
# なし
#
# 戻り値:
# JSPParser - JSPパーサオブジェクト
#
# 例外:
# なし
#
# 特記事項:
# メンバ変数は下記の通り。
# |  INPUT      - JSPソースコードファイル名
# |  DECL       - コード領域。Declaration構文より抽出したコード
# |  SCRIPT     - コード領域。Scriptlet構文より抽出したコード
# |  EXPR1      - コード領域。Expression構文より抽出したコード(行番号)
# |  EXPR2      - コード領域。Expression構文より抽出したコード(タグ内の構文)
# |  ADD_METHOD - 抽出した構文をDECL, SCRIPT, EXPR2へ追加するメソッドへの
# |               リファレンス
# |  CREATE_METHOD - 抽出した構文を加工してEXPR2をSCRIPTへ追加する
# |                  メソッドへのリファレンス  
#
#
#####################################################################
sub new {
    my $class = shift;
    my $self = { };
    ref($class) and $class = ref($class);
    bless($self, $class);
    
    $self->{INPUT}  = undef;
    $self->{DECL}   = "";
    $self->{SCRIPT} = "";
    $self->{EXPR1}   = "";
    $self->{EXPR2}   = "";
    delete $self->{ADD_METHOD};
    delete $self->{CREATE_METHOD};

    return $self;
}

#####################################################################
# Function: init
#
#
# 概要:
# JSPソースコード解析用のレクサを生成し、抽出対象となるパターン定義を
# 登録する。
#
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
# - 抽出対象となるパターン定義は%taglistに定義する。
#
#####################################################################
sub init {
    my $self = shift;
    
    #
    # レクサオブジェクトを生成する
    #
    if(!defined $self->{LEXER}) {
        $self->{LEXER} = PgSqlExtract::Common::Lexer->new();

        my @pattern = ();
        
        #
        # タグリストの内容より、レクサに設定するパターンとトークンIDを
        # 抽出する
        #
        for my $ident (sort keys %taglist) {
            push(@pattern, $taglist{$ident}->{pattern});
            push(@pattern, $ident);
        }
     
        $self->{LEXER}->
            setPattern({EXT_PATTERN => \@pattern, SKIP_PATTERN => $commentPattern});
    }
    $self->{DECL}   = "";
    $self->{SCRIPT} = "";
    $self->{EXPR1}   = "";
    $self->{EXPR2}   = "";
    delete $self->{ADD_METHOD};
    delete $self->{CREATE_METHOD};
    
    get_loglevel() > 9 and $self->{LEXER}->setDebugMode(1);
}

#####################################################################
# Function: run
#
#
# 概要:
# JSPファイルに対する構文解析を実行し、擬似的なJavaソースコードを
# 生成する。
# - パース対象となる文字列（JSPソースコード)を解析し、擬似的なJavaソース
#   コード文字列を生成する。
# - 抽出すべき構文を検出した場合、その内容を取得する。
# - コメントタグを検出した場合は無視する。
# - 擬似的なJavaソースコードには、line指定を埋め込む。
#
# パラメータ:
# なし
#
# 戻り値:
# code - 擬似的なJavaソースコード文字列
#
# 例外:
# なし
#
# 特記事項:
# なし
#
#
#####################################################################
sub run {
    my $self = shift;
    
    #
    # レクサを準備していない場合は新規に生成する
    #
    my $lexer;
    if(defined($self->{LEXER})) {
        $lexer = $self->{LEXER};
    } else {
        return;
    }

    #
    # JSPファイルに対して字句解析を行い、結果をコード領域へ格納する
    # コード領域への格納は、抽出した構文に対応する処理内で実施される
    #    
    while(my $result = $lexer->nextToken) {
        #
        # 抽出した構文に対応する処理を実行する
        # 対応する処理は、字句解析結果のトークンIDをキーにしてタグリストから
        # 取り出す
        #
        my $method_ref = $taglist{$result->{KEYWORD}}->{method};
        $method_ref->($self, $result->{TOKEN}, $result->{LINE});
    }
    
    #
    # 擬似的なJavaソースコードのクラス名を生成する
    #
	my $classname = 'JSP' . sprintf ("%d", ++$G_fileCnt);    
    
    #
    # 擬似的なJavaソースコードのテンプレートへ、抽出したコードを埋め込む
    #
    my $code = sprintf $G_code, $classname, $self->{SCRIPT}, $self->{DECL};

    return $code;
}


#####################################################################
# Function: set_input
#
#
# 概要:
# 構文解析対象となるJSPファイルの内容（文字列）を設定する。
#
# パラメータ:
# filename - JSPファイル名
#
# 戻り値:
# なし
#
# 例外:
# なし
#
# 特記事項:
# - レクサが生成されていない場合は、新規に生成する。
#
#
#####################################################################
sub set_input {
    my $self = shift;
    
    $self->init();
    $self->{LEXER}->setTarget($_[0]);
    $self->{LEXER}->enablePattern('SKIP_PATTERN');
    $self->{INPUT} = $_[0];
}


#####################################################################
# Function: setDeclaration(private)
#
#
# 概要:
# Declaration構文に対するコード追加処理する。
# 当メソッドの実行により、Declaration構文の抽出が開始される。
#
# パラメータ:
# token      - 抽出したトークン
# linenumber - 抽出開始時点の行番号 
#
# 戻り値:
# なし
#
# 例外:
# - 既に開始タグが存在している場合。
#
# 特記事項:
# - ADD_METHODとして、抽出したトークンをDECLへ追加する処理を定義する。
# - Declaration構文内容については、コメント、改行も含めて抽出する必要が
#   あるため、字句解析のコメント抽出を一旦無効化する。
# - CREATE_METHODは定義しない。
#
#
#####################################################################
sub setDeclaration {
    my $self = shift;
    my ($token, $linenumber) = @_;

    if(exists $self->{ADD_METHOD}) {
        $token =~ s{%}{%%}xms;
        my $message = sprintf "Parse error %%s:%d (The start tag has already existed. '%s')\n", $linenumber, $token;
        croak $message;
    }

    $self->{DECL} .= "#line $linenumber;";
    $self->{LEXER}->disablePattern('SKIP_PATTERN');
    
    $self->{ADD_METHOD} = sub {
        $self->{DECL} .= $_[0];
    };
}


#####################################################################
# Function: setScriptlet(private)
#
#
# 概要:
# Scriptlet構文に対するコード追加処理を登録する。
# 当メソッドの実行により、Scriptlet構文の抽出が開始される。
#
# パラメータ:
# token      - 抽出したトークン
# linenumber - 抽出開始時点の行番号 
#
# 戻り値:
# なし
#
# 例外:
# - 既に開始タグが存在している場合。
#
# 特記事項:
# - ADD_METHODとして、抽出したトークンをSCRIPTへ追加する処理を定義する
# - CREATE_METHODは定義しない。
# - Scriptlet構文内容については、コメント、改行も含めて抽出する必要が
#   あるため、字句解析のコメント抽出を一旦無効化する。
#
#
#####################################################################
sub setScriptlet {
    my $self = shift;
    my ($token, $linenumber) = @_;

    if(exists $self->{ADD_METHOD}) {
        $token =~ s{%}{%%}xms;
        my $message = sprintf "Parse error %%s:%d (The start tag has already existed. '%s')\n", $linenumber, $token;
        croak $message;
    }
        
    $self->{SCRIPT} .= "#line $linenumber;";
    $self->{LEXER}->disablePattern('SKIP_PATTERN');
    
    $self->{ADD_METHOD} = sub {
        $self->{SCRIPT} .= $_[0];
    };
}

#####################################################################
# Function: setExpression(private)
#
#
# 概要:
# Expression構文に対するコード追加処理を登録する。
# 当メソッドの実行により、Expression構文の抽出が開始される。
#
# パラメータ:
# token      - 抽出したトークン
# linenumber - 抽出開始時点の行番号 
#
# 戻り値:
# なし
#
# 例外:
# - 既に開始タグが存在している場合。
#
# 特記事項:
# - ADD_METHODとして、抽出したトークンをEXPR2へ追加する処理を定義する。
# - CREATE_METHODとして、抽出したEXPRを「EXPR1 print(EXPR2)」に加工してSCRIPTに
#   追加する処理を定義する。
# - Expression構文内容については、コメント、改行も含めて抽出する必要が
#   あるため、字句解析のコメント抽出を一旦無効化する。
#
#
#####################################################################
sub setExpression {
    my $self = shift;
    my ($token, $linenumber) = @_;

    if(exists $self->{ADD_METHOD}) {
        $token =~ s{%}{%%}xms;
        my $message = sprintf "Parse error %%s:%d (The start tag has already existed. '%s')\n", $linenumber, $token;
        croak $message;
    }
    
    $self->{EXPR1} .= "#line $linenumber;";
    $self->{LEXER}->disablePattern('SKIP_PATTERN');
    
    $self->{ADD_METHOD} = sub {
        $self->{EXPR2} .= $_[0];
    };
    
    
    $self->{CREATE_METHOD} = sub {
        if($self->{EXPR1} ne "") {

            $self->{EXPR2} =~ s{\A ($javaCommentPattern) }{}xms;
            my $before_comment = $1;
            !defined $before_comment and $before_comment = '';

            $self->{SCRIPT} .= sprintf "%s %s print(%s);\n", $self->{EXPR1}, $before_comment, $self->{EXPR2};
            $self->{EXPR1} = "";
            $self->{EXPR2} = "";
        }
    }
}


#####################################################################
# Function: addCode(private)
#
#
# 概要:
# ADD_METHODが定義されている場合、その処理を実行する。
#
# パラメータ:
# token      - 抽出したトークン
# linenumber - 抽出開始時点の行番号 
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
sub addCode {
    my $self = shift;
    my ($token, $linenumber) = @_;
    
    defined $self->{ADD_METHOD} and do {
        $self->{ADD_METHOD}->($token);
    };
}

#####################################################################
# Function: createCode(private)
#
#
# 概要:
# CREATE_METHODが定義されている場合、その処理を実行し、現在ADD_METHOD,
# CREATE_METHODに登録済み処理を削除する。
# 当メソッドの実行により、JSP構文の抽出が解除される。 
#
# パラメータ:
# token      - 抽出したトークン
# linenumber - 抽出開始時点の行番号 
#
# 戻り値:
# なし
#
# 例外:
# - 開始タグを検出する前に終了タグを検出した場合。
#
# 特記事項:
# - 無効化したコメント抽出を再度有効化する。
#
#####################################################################
sub createCode {
    my $self = shift;
    my ($token, $linenumber) = @_;
    
    if(!exists $self->{ADD_METHOD}) {
        $token =~ s{%}{%%}xms;
        my $message = sprintf "Parse error %%s:%d (The end tag ahead of the start tag exists. '%s')\n", $linenumber, $token;
        croak $message;
    }
    
    defined $self->{CREATE_METHOD} and do {
        $self->{CREATE_METHOD}->();
    };
    
    delete $self->{CREATE_METHOD};
    delete $self->{ADD_METHOD};
    $self->{LEXER}->enablePattern('SKIP_PATTERN');
}

1;

__DATA__
public class %s {
    
    public void service() {
        %s
    }
    
    %s
}

