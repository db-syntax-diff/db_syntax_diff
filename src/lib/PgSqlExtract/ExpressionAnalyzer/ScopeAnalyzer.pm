#############################################################################
#  Copyright (C) 2008-2010 NTT
#############################################################################

#####################################################################
# Function: ScopeAnalyzer.pm
#
#
# 概要:
# ロジック上のスコープに着目して式解析を実行する解析モジュールである。
#
# 特記事項:
# 変数辞書
# - 変数辞書は、スコープ単位で作成される。スコープの上下関係を保持する形
# で変数辞書も親子関係を保持する。つまり、変数辞書は親の変数辞書（
# 上位スコープに対する変数辞書)を保持する。
# - 変数辞書の親子関係を利用して、スコープ内で参照可能な変数であるかの
# 判定を行うことが出来る。より上位スコープで宣言された変数の情報は、
# 親の変数辞書に格納されているため、変数辞書を先祖方向へたどることで
# 上位スコープで宣言された変数の情報を参照することが可能となる。
#
# 一時辞書
# - 一時辞書は正規化された行単位で作成される。正規化された行の要素に
#   ついて式解析を行った結果を一時的に保持する。
# - 正規化された行に対する式解析が完了（解析終端を検出）した時点で、
#   一時辞書に保持されている内容が評価され、パターン抽出対象となる。
#
#####################################################################

package PgSqlExtract::ExpressionAnalyzer::ScopeAnalyzer;
use warnings;
no warnings "recursion";
use strict;
use Carp;
use utf8;

use Class::Struct;
use List::Util qw( first );
use PgSqlExtract::Common;

#
# variable: G_is_StringClass
# String型、もしくはStringBuffer型であるか判定する正規表現。
#
my $G_is_StringClass = qr{\b String (?: Buffer )? \z}xms;

#
# variable: G_no_result
# 解析結果なしを示す一時辞書情報。
#
my $G_no_result = Temp_Content->new(codeType => RESTYPE_OTHER, name => '',
    value => '', line => '', val_flg =>'0', component => undef);

#
# variable: G_ws_result
# 空白文字列を示す一時辞書情報。
#
my $G_ws_result = Temp_Content->new(codeType => RESTYPE_STRING, name => '',
    value => ' ', line => '', val_flg =>'0', component => undef);

#
# variable: G_oprlist_other
# 演算子(+, =, +=以外)のトークンIDを格納するリスト。
#
my @G_oprlist_other;

#
# variable: G_oprlist_ep
# 演算子(+, =, +=)のトークンIDを格納するリスト。
#
my @G_oprlist_ep;

#
# variable: G_sprlist
# 解析終端() ]  }  ; ,)のトークンIDを格納するリスト。
#
my @G_sprlist;

#
# variable: G_literal_other
# 文字列以外のリテラルのトークンIDを格納するリスト。
#
my @G_literal_other;


#
# variable: G_method_processer_ref
# メソッド名と対応する処理のハッシュ。
#
my %G_method_processer_ref = (
    'String'        => \&process_method_string,
    'StringBuffer'  => \&process_method_stringbuffer,
    'toString'      => \&process_method_tostring,
    'append'        => \&process_method_append
);

#
# variable: G_judge_word_recures
# judge_word関数の再帰呼び出し回数をカウントする。デバッグ出力用である。
#
my $G_judge_word_recures = 0;

my $G_current_method_name = '[no name]';



#####################################################################
# Function: new
#
#
# 概要:
# ScopeAnalyzerを新規に生成する。
#
# パラメータ:
# なし
#
# 戻り値:
# self - ScopeAnalyzerオブジェクト
#
# 例外:
# なし
#
# 特記事項:
# なし
#
#####################################################################
sub new {
    my $class = shift;
    my $self = { };
    ref($class) and $class = ref($class);
    bless($self, $class);
    
    @G_oprlist_other = map {$tokenId{$_}} qw (
        ASSIGN_OPR COR_OPR CAND_OPR OR_OPR NOR_OPR MULTI_OPR EQUALITY_OPR
        RELATIONAL_OPR PREFIX_OPR MINUS_OPR POSTFIX_OPR CLN_TOKEN QUES_TOKEN
    );
    
    @G_oprlist_ep = map {$tokenId{$_}} qw (ASSIGN_P_OPR PLUS_OPR EQUAL_OPR);
    
    @G_sprlist = map {$tokenId{$_}} qw (
        RP_TOKEN RCB_TOKEN RSB_TOKEN SMC_TOKEN CM_TOKEN
    );
    
    @G_literal_other = map {$tokenId{$_}} qw(
        INTEGER_LITERAL FLOAT_LITERAL CHAR_LITERAL TRUE_TOKEN FALSE_TOKEN NULL_TOKEN
    );
    
    return $self;
}

#####################################################################
# Function: analyze
#
#
# 概要:
# クラス情報に登録されているすべてのメソッド情報と変数情報について、
# 式解析を実行する。
# 式解析モジュールを実行するためのトリガである。
#
# - 変数情報のリストより変数辞書を生成する。この変数辞書は変数辞書構造の
#   最上位辞書となる。
# - 各メソッドについて、スコープごとの式解析を実行する。
#
# パラメータ:
# classinfo         - クラス情報
# result_list       - 式解析結果(メソッド)のリスト(出力用)
#
# 戻り値:
# なし
#
# 特記事項:
# - 式解析結果として、式解析結果(コード)のリストがresult_listに格納される。
#
#
#####################################################################
sub analyze {
    my $self = shift;
    my ($classinfo, $result_list) = @_;
    
    get_loglevel() > 2 and print_log("(DEBUG 3) | [in] analyze");

    #
    # クラス名の取得
    #
    $self->{CLASSNAME} = $classinfo->classname();
    
    
    #
    # クラスの変数情報を解析し、変数辞書を作成する
    # 変数情報を解析した結果を取得する
    #
    my @result_at_scope = ();
    my $var_dic = $self->analyze_variablelist($classinfo->varlist, \@result_at_scope);

    #
    # すべてのメソッド情報について式解析を実行する
    #
    for my $methodinfo (@{$classinfo->methodlist()}) {
        $G_current_method_name = (defined $methodinfo->name() ? $methodinfo->name() : '[no name]');


        #
        # 式解析結果(メソッド)のオブジェクトを新規に生成する
        #
        my $result_at_method = AnalysisResultsMethod->new();
        $result_at_method->methodinfo_ref($methodinfo);

        #
        # スコープごとの式解析を実行する
        #
        my @result_at_codes = ();
        $self->analyze_scope($methodinfo->rootscope_ref, $var_dic, \@result_at_codes);
        push(@{ $result_at_method->codelist() }, @result_at_codes);       
        
        #
        # メソッドごとの式解析結果を式解析結果(クラス)へ登録する
        #
        
        push(@{$result_list},  $result_at_method);
        $G_current_method_name = '[no name]';
    }

    #
    # メソッドごとの式解析終了後、未参照の変数情報の内容を式解析結果として登録する
    #
    $self->register_analyze_result_at_scope(\@result_at_scope, $var_dic);

    #
    # 変数情報の式解析結果を式解析結果(メソッド)へ登録する
    #
    my $result_at_variables = AnalysisResultsMethod->new();
    push(@{ $result_at_variables->codelist() }, @result_at_scope);       

    push(@{$result_list},  $result_at_variables);
    
    get_loglevel() > 2 and print_log("(DEBUG 3) | [out] analyze");

}

#####################################################################
# Function: analyze_variablelist
#
#
# 概要:
# 変数情報の内容を解析し、変数辞書を作成する。また、解析中に抽出した
# 報告対象を式解析結果へ登録する。
#
# パラメータ:
# varlist     - 変数情報
# result_list - 式解析結果(コード)のリスト(出力用)
#
# 戻り値:
# var_dic - 変数辞書
#
# 特記事項:
# - 式解析結果として、式解析結果(コード)のリストがresult_listに格納される。
#
#
#####################################################################
sub analyze_variablelist {
    my $self = shift;
    my ($variable_list, $result_list) = @_;

    #
    # 空の変数辞書の作成
    #
    my $var_dic = $self->create_variable_dic();
    
    #
    # 空の一時変数辞書の生成
    # 変数情報はコード上で宣言された順番に処理する必要があるため、リストで
    # 管理する
    # 
    #
    my $temp_var_dic = [];
    
    #
    # 変数情報(メンバ変数)を確認し、データ型が(String or StringBuffer) かつ 
    # 値が文字列リテラルのみ場合、変数辞書に変数情報を格納する。
    # (下位のスコープで参照される可能性有)
    # その他は一時変数辞書に格納する。
    # 値の判定を文字リテラルのみから文字リテラルと解析終端の組み合わせに変更
    #
    for my $var_cont (@{$variable_list}) {

        if(($var_cont->type() eq RESTYPE_STRING or $var_cont->type() eq RESTYPE_SB)
            and defined $var_cont->value()->[0]
            and ($var_cont->value()->[0]->id() == $tokenId{'STRING_LITERAL'})
            and ($var_cont->value()->[1]->id() == $tokenId{'VARDECL_DELIMITER'})) {

            $self->register_variable_dic($var_dic, $var_cont->type(), $var_cont->name(), 
                $var_cont->value()->[0]->token(), $var_cont->linenumber());
            get_loglevel() > 4
                and print_log("(DEBUG 5) | variable_list:register_variable_dic:name=".$var_cont->name());
        } else {
            push(@{$temp_var_dic}, $var_cont);
            get_loglevel() > 4 and print_log("(DEBUG 5) | variable_list:temp_var_dic:name=".$var_cont->name());
            get_loglevel() > 4 and print_log("(DEBUG 5) | variable_list:temp_var_dic:type=".$var_cont->type());
        }
    }
    
    #
    # 論理行用のカウンタ
    #
    my $code_count=0;
    
    #
    # 一時変数辞書の値を1つずつ取得し、処理を行う。
    # 一時変数辞書には式解析が必要な値(メソッド、変数、複数の文字列等)が
    # 格納されている。
    #
    for my $value (@{$temp_var_dic}) {
        get_loglevel() > 4 and print_log("(DEBUG 5) | variables::name=".$value->name());
        get_loglevel() > 4 and print_log("(DEBUG 5) | variables::type=".$value->type());

        #
        # 一時辞書の生成
        #
        my %temp_dic_ref = (
            stack => [],        # 変数情報のリスト
            status => {},       # ステータス
            code_count => $code_count, # コードカウンタ
            block_count => 0    # ブロックカウンタ

        );
        
        # 一時変数辞書に格納されている値を式解析する
        $self->judge_word($value->value(), 0, $value->linenumber(), $var_dic, \%temp_dic_ref, $result_list);
        
        #
        # 一時辞書に1件も登録されていない場合は一時変数辞書を確認する
        # (staticで宣言されている場合を考慮するため)。
        # 一時変数辞書の変数名(…(1))と取得している一時変数辞書の値が等しい場合、
        # (1)の値を式解析する
        #
        if(!defined $self->refer_temp_dic(\%temp_dic_ref)){
            if(defined $value->value()->[0]) {
                for my $key (@{$temp_var_dic}) {
                    if($key->name() eq $value->value()->[0]->token()) {
                        $self->judge_word($key->value(), 
                            0, $value->linenumber(), $var_dic, \%temp_dic_ref, $result_list);
                        get_loglevel() > 4 and print_log("(DEBUG 5) | key=".$key);
                        get_loglevel() > 4 and print_log("(DEBUG 5) | token=".$value->value()->[0]->token());
                       last;
                    }
                }
            }   

        }

        #
        # String,StringBufferの場合は変数辞書に登録する
        #
        if($value->type() eq RESTYPE_STRING or $value->type() eq RESTYPE_SB){
            my $one_result = $self->pop_temp_dic(\%temp_dic_ref);
            #
            # 初期化子の解析結果の型がString,StringBuffer以外の場合は空文字で登録する
            #
            if($one_result->codeType() eq RESTYPE_STRING or $one_result->codeType() eq RESTYPE_SB){
                $self->register_variable_dic($var_dic, $value->type(), 
                                        $value->name(), $one_result->value(), $value->linenumber(), undef, 0, $one_result->component);
            }
            else{
                $self->register_variable_dic($var_dic, $value->type(), 
                                        $value->name(), "", $value->linenumber());
            }
        }
        
        #
        # 初期化子を解析した結果、複数の結果が返却されている場合はその内容を
        # 報告結果として登録する
        # 初期化子にメソッド定義が存在する場合など
        # int i = execute("SELECT");
        #
        $self->register_analyze_result_dic($result_list, \%temp_dic_ref, $value->linenumber());
    }
    
    return $var_dic;
    
}


#####################################################################
# Function: analyze_scope
#
#
# 概要:
# スコープ単位の解析処理である。
# スコープ情報に格納されているすべてのコード情報について、式解析を
# 実行し、式解析結果(コード)を取得する。
#
# - 親スコープの変数辞書を指定して、当該スコープに対する変数辞書を生成
#   する。
# - スコープ情報より、1行分のコード情報を取り出す。そのコード情報が
#   実コードに対するコード情報の場合は式解析の主制御(judge_word)を
#   実行する。コード情報が下位スコープ情報の場合は、下位スコープに
#   対するスコープ単位の解析処理(analyze_scope)を実行する。
#
#
# パラメータ:
# scopeinfo         - スコープ情報
# variable_dic_ref  - 親スコープの変数辞書
# result_list       - 式解析結果(コード)のリスト(出力用)
#
# 戻り値:
# なし
#
# 特記事項:
# - 式解析結果として、式解析結果(コード)のリストがresult_listに格納される。
#
#
#####################################################################
sub analyze_scope {
    my $self = shift;
    my ($scopeinfo, $variable_dic_ref, $result_list) = @_;
    
    get_loglevel() > 2 and print_log("(DEBUG 3) | [in] analyze_scope");
    #
    # 当該スコープに対する変数辞書を作成する
    #
    my $current_dic = $self->create_variable_dic($variable_dic_ref);

    #
    # 論理行用のカウンタ
    #
    my $code_count=0;

    #
    # スコープに属するすべてのコード情報について式解析を実行する
    # 当該行がコード情報の場合は、式解析を実行する
    # 当該行がスコープ情報の場合は、スコープの解析を実行する
    #
    for my $code (@{ $scopeinfo->codelist() }) {
        if($code->codeType() == CODETYPE_CODE) {
            
            #
            # 一時辞書の生成
            #
            my %temp_dic_ref = (
                stack => [],        # 変数情報のリスト
                status => {},       # ステータス
                code_count => $code_count, # コードカウンタ
                block_count => 0    # ブロックカウンタ
            );
            
            #
            # コード情報が格納する式情報をひとつずつ解析する
            # ひとつの式に対する解析終了後、評価対象となっている文字列を
            # 式解析結果(コード)へ登録する
            #
            for my $current_expr (@{$code->exprlist()}) {
                $self->judge_word($current_expr, 0, $code->linenumber(), $current_dic, \%temp_dic_ref, $result_list);
                $self->register_analyze_result_dic($result_list, \%temp_dic_ref, $code->linenumber());              
            }
        }
        else {
            $self->analyze_scope($code->tokenlist(0), $current_dic, $result_list);
        }
        #
        # 論理行のカウントアップ
        #
        $code_count++;
    }
    
    #
    # スコープ終端を検出した場合、未参照の変数辞書の内容を式解析結果として
    # 登録する
    #
    $self->register_analyze_result_at_scope($result_list, $current_dic);
    get_loglevel() > 2 and print_log("(DEBUG 3) | [out] analyze_scope");

}


#####################################################################
# Function: judge_word
#
#
# 概要:
# 式解析の主制御である。
# コード情報よりトークンを1つ読み出し、特定コードの判別を行う。下記の特定コード
# を検出した場合、それぞれの処理を行う。
# - 演算子(=, +, +=)を検出した場合、演算子(=, +, +=)の解析処理を実行する。
# - 演算子(=, +, +=以外)を検出した場合、演算子(その他)の解析処理を実行する。
# - 解析終端を検出した場合、解析終端処理を実行する。
# - 文字リテラルを検出した場合、評価対象として一時辞書へ登録する。
# - 識別子を検出した場合、識別子の解析処理を実行する。
# - その他のトークンを検出した場合、解析位置をひとつ進める。
#
# パラメータ:
# code_info_ref         - コード情報のリストのリファレンス
# point                 - 解析の開始位置
# line                  - コードが記述された行番号
# variable_dic_ref      - 変数辞書のリファレンス
# temp_dic_ref          - 一時辞書のリファレンス
# analyze_result_list   - 式解析結果(コード)のリスト(出力用)のリファレンス
#
# 戻り値:
# point                 - 次の解析位置
#
#
# 特記事項:
# - 次の解析位置は、各解析処理を実行した場合はその結果となる位置、文字列
#   リテラルを含むその他のトークンを検出した場合は当該トークンの次の位置
#   となる。
# - 変数辞書への登録は、各解析処理に依存する。
# - 一時辞書への登録は、文字列リテラルを検出した場合に行われる。それ以外
#   の場合は、各解析処理に依存する。ただし、一度も解析が行われることなく
#   終了する場合は、「解析結果なし」を登録する。
#
#####################################################################
sub judge_word {
    my $self = shift;
    my ($code_info_ref, $point, $line, $variable_dic_ref, $temp_dic_ref, $analyze_result_list) = @_;
    
    get_loglevel() > 2 and do {$G_judge_word_recures++; print_log("(DEBUG 3) | [in] judge_word [". $G_judge_word_recures . "] line = " . $line);};
    #
    # トークンの終端まで解析を実行する
    #
    my $is_result = 0;                           # 一度でも下位の式解析が実行
                                                 # された場合に真となる
    my $enf_of_token = scalar @{$code_info_ref}; #トークンの終端位置
    get_loglevel() > 4 and print_log("(DEBUG 5) | token_end=".$enf_of_token);
    while($enf_of_token > $point){
        
        #
        # 現在のトークンを格納
        #
        my $current_token = $code_info_ref->[$point];
        get_loglevel() > 4 and print_log("(DEBUG 5) | judge_word TOKEN_START=".$current_token->token);
        #
        # 特定コード(=)の場合
        #
        if($current_token->id() == $tokenId{'EQUAL_OPR'}){
            $point = $self->process_equal($code_info_ref, $point, $line, 
                     $variable_dic_ref, $temp_dic_ref);
            $is_result++;
        }
        #
        # 特定コード(+)の場合
        #
        elsif($current_token->id() == $tokenId{'PLUS_OPR'}){
            $point = $self->process_plus($code_info_ref, $point, $line, 
                     $variable_dic_ref, $temp_dic_ref);
            $is_result++;
        }
        #
        # 特定コード(+=)の場合
        #
        elsif($current_token->id() == $tokenId{'ASSIGN_P_OPR'}){
            $point = $self->process_plus_equal($code_info_ref, $point, $line, 
                     $variable_dic_ref, $temp_dic_ref);
            $is_result++;
        }
        #
        # 特定コード(=,+,+=)以外の演算子の場合
        #
        elsif(first {$current_token->id() == $_} @G_oprlist_other) {
            $point = $self->process_sign_the_others($code_info_ref, $point, $line, 
                     $variable_dic_ref, $temp_dic_ref, $analyze_result_list);
            $self->register_temp_nodata($temp_dic_ref);
            $is_result++;
        }
        #
        # 特定コード(解析終端)の場合
        # 一度も下位の式解析が実施されていない場合、本式解析の解析結果として
        # 「解析結果なし」を登録する
        #
        elsif( $current_token->id() == $tokenId{'RP_TOKEN'} 
            or $current_token->id() == $tokenId{'SMC_TOKEN'}
            or $current_token->id() == $tokenId{'CM_TOKEN'}){
            
            #
            # メソッド宣言中、計算中、変数宣言の解析中は式解析結果へ登録せずに
            # 呼び出し元へ制御を戻す
            #
            if($self->refer_temp_status($temp_dic_ref, 'MethodDec')
                or $self->refer_temp_status($temp_dic_ref, 'CalDec')){

                if($current_token->id() == $tokenId{'RP_TOKEN'}
                    or $current_token->id() == $tokenId{'SMC_TOKEN'}){
                    get_loglevel() > 4 and print_log("(DEBUG 5) | judge_word TOKEN_END=".$current_token->token);
                    get_loglevel() > 2 and do{ print_log("(DEBUG 3) | [out] judge_word(MethodDec1) [". $G_judge_word_recures . "]"); $G_judge_word_recures-- ; };
                }

            }
            elsif($self->refer_temp_status($temp_dic_ref, 'VarDec')){
                get_loglevel() > 4 and print_log("(DEBUG 5) | judge_word TOKEN_END=".$current_token->token);
                get_loglevel() > 2 and do{ print_log("(DEBUG 3) | [out] judge_word(refer_temp_status) [". $G_judge_word_recures . "]"); $G_judge_word_recures-- ; };
            }
            #
            # メソッド宣言中、計算中、変数宣言以外で解析終端を検出した場合は
            # その時点での評価対象文字列を式解析結果(コード)へ登録し、処理を
            # 続行する（配列の初期化子などはこのルートとなる）
            #
            else{
                $self->register_analyze_result_dic($analyze_result_list, $temp_dic_ref, $line);             
                ++$point;
                next;
            }
            
            #
            # 解析結果なしの登録（下位の式解析が実行されていない場合）
            #
            if($is_result == 0) {
                $self->register_temp_nodata($temp_dic_ref);
            }
            return $point;

        }
        #
        # 文字列リテラルの場合
        # 文字列リテラルは「評価対象」となる
        #
        elsif($current_token->id() == $tokenId{'STRING_LITERAL'}){
            # 文字列リテラルを一時辞書へ登録
            $self->register_temp_dic($temp_dic_ref, RESTYPE_STRING, 
                              undef, $current_token->token(), $line, 1);
            ++$point;
            $is_result++;
        }
        
        #
        # その他のリテラルの場合
        # 解析結果なしを登録する
        elsif(first {$current_token->id() == $_} @G_literal_other) {
            $self->register_temp_nodata($temp_dic_ref);
            ++$point;
            $is_result++;
        }
        #
        #
        # 識別子(super, thisトークン含む)の場合
        #
        elsif($current_token->id() == $tokenId{'IDENTIFIER'}
              or $current_token->id() == $tokenId{'SUPER_TOKEN'}
              or $current_token->id() == $tokenId{'THIS_TOKEN'}){
            ++$point;
            $point = $self->judge_next_word($code_info_ref, $point, $line, $variable_dic_ref, 
                     $temp_dic_ref, $analyze_result_list);
            $is_result++;
        }
        #
        # 変数情報から変数辞書作成時に変数情報のメンバ変数終端を検出した場合
        #
        elsif($current_token->id() == $tokenId{'VARDECL_DELIMITER'}){
            get_loglevel() > 4 and print_log("(DEBUG 5) | judge_word TOKEN_END=".$current_token->token);
            get_loglevel() > 2 and do{ print_log("(DEBUG 3) | [out] judge_word [". $G_judge_word_recures . "]"); $G_judge_word_recures-- ; };
            return ++$point;
        }
        #
        # 識別子に続かないドットを検出した場合
        # 例)
        # method().value;
        # strvalue[1].value;
        #
        # 直前の内容を取得し、その型がString/StringBuffer以外の場合は
        # 「ドット解析中」を設定する
        #
        elsif($current_token->id() == $tokenId{'DOT_TOKEN'}) {
            $self->register_temp_status($temp_dic_ref, 'DotDec', 1);
            ++$point;
        }
        #
        # その他の場合
        #
        else{
            ++$point;
        }
        get_loglevel() > 4 and print_log("(DEBUG 5) | judge_word TOKEN_END=".$current_token->token);
    }

    #
    # トークンが存在しない場合
    # 解析結果なしを登録する
    #
    if($enf_of_token == 0){
        get_loglevel() > 4 and print_log("(DEBUG 5) | judge_word register_temp_nodata");
        $self->register_temp_nodata($temp_dic_ref);
    }
    
    get_loglevel() > 2 and do{ print_log("(DEBUG 3) | [out] judge_word [". $G_judge_word_recures . "]"); $G_judge_word_recures-- ; };
    return $point;
}


#####################################################################
# Function: judge_next_word
#
#
# 概要:
# 識別子の解析処理である。
# 取得済みの識別子と、次のトークンの種別により特定コードを判別し、それぞれの
# 処理を行う。
# 次のトークンが下記の種別の場合、処理を行う。
# - 次のトークンが開き括弧(()の場合、メソッド呼び出しと判断し、メソッド呼び出し
#   の解析処理を行う。
# - 次のトークンがドット(.)の場合、ドットを含む変数指定と判断し、ドット含む
#   変数指定の解析処理を行う。
# - 次のトークンが解析終端もしくは演算子(*1)の場合、変数指定と判断し、変数指定
#   の解析処理を行う。
# - 次のトークンが識別子の場合、変数宣言と判断し、変数宣言の解析処理を行う。
# - 次のトークンが上記以外の場合は、何もしない。
#
#
# パラメータ:
# code_info_ref         - コード情報のリストのリファレンス
# point                 - 解析の開始位置
# line                  - コードが記述された行番号 
# variable_dic_ref      - 変数辞書のリファレンス
# temp_dic_ref          - 一時辞書のリファレンス
# analyze_result_list   - 式解析結果(コード)のリスト(出力用)のリファレンス
# 
# 戻り値:
# next_point            - 次の解析位置
#
# 特記事項:
# - *1 変数指定の解析処理を実行する解析終端、演算子は以下とする。中括弧({})は
#   コード情報には含まれない。また、条件演算子(?,:)は入力ファイル解析時点で
#   式集合に分割されているため、コード情報には含まれない。
# | ) ] ; , 
# | > < ! ~ ? :
# | == <= >= != && || ++ --
# | - * / & | ^ % << >> >>>
# | -= *= /= &= |= ^= %= <<= >>= >>>=
# |
#
# - 解析開始位置は、識別子の位置である。
# - 次の解析位置は、各解析処理を実行した場合はその結果となる位置、その他の
#   トークンを検出した場合は当該トークンの位置となる。
# - 変数辞書への登録は、各解析処理に依存する。
# - 一時辞書への登録は、各解析処理に依存する。ただし、一度も解析が行われる
#   ことなく終了する場合は、「解析結果なし」を登録する。
#
#####################################################################
sub judge_next_word{
    my $self = shift;
    my ($code_info_ref, $point, $line, $variable_dic_ref, $temp_dic_ref, $analyze_result_list) = @_;
    my $current_token = $code_info_ref->[$point];  # 現在のトークンを格納
    my $next_point;                                # 戻り値となる次の解析位置を格納する

    get_loglevel() > 2 and print_log("(DEBUG 3) | [in] judge_next_word");

    get_loglevel() > 4 and do {
        if(!defined $current_token) {
            my $past_token = $code_info_ref->[$point - 1];
            print_log("(DEBUG 5) | judge_next_word ONLY PAST TOKEN =" . $past_token->token());
        } else {
            print_log("(DEBUG 5) | judge_next_word TOKEN_START=".$current_token->token);
        }
    };

    #
    # 識別子単独の場合
    #
    if(!defined $current_token) {
        $next_point = $self->process_ident_analyze_end_and_calc($code_info_ref, 
                      $point, $line, $variable_dic_ref, $temp_dic_ref);
    }
    #
    # メソッド呼び出しの場合
    #
    elsif($current_token->id() == $tokenId{'LP_TOKEN'}){

        # クラス名のドット解析中であるフラグを解除する
        $self->register_temp_status($temp_dic_ref, 'DotDec', 0);
        
        $next_point = $self->process_ident_parenthesis($code_info_ref, $point, $line,
                      $variable_dic_ref, $temp_dic_ref, $analyze_result_list);
    }
    #
    # 変数指定(識別子.)の場合
    #
    elsif($current_token->id() == $tokenId{'DOT_TOKEN'}){
        $next_point = $self->process_ident_dot($code_info_ref, $point, $line,
                      $variable_dic_ref, $temp_dic_ref);
    }
    #
    # 変数指定(「識別子 解析終端」と「識別子 演算子」)の場合
    #
    elsif(first {$current_token->id() == $_} @G_oprlist_other, @G_oprlist_ep, @G_sprlist , $tokenId{'VARDECL_DELIMITER'}) {
        $next_point = $self->process_ident_analyze_end_and_calc($code_info_ref, 
                      $point, $line, $variable_dic_ref, $temp_dic_ref);
    }
    #
    # 変数宣言(識別子 識別子)の場合
    #
    elsif($current_token->id() == $tokenId{'IDENTIFIER'}){
        # クラス名のドット解析中であるフラグを解除する
        $self->register_temp_status($temp_dic_ref, 'DotDec', 0);
        
        $next_point = $self->process_ident_ident($code_info_ref, $point, $line,
                      $variable_dic_ref, $temp_dic_ref);
    }
    #
    # 上記以外([しかない)の場合
    # 解析処理が行われないため、「解析結果なし」を登録する
    #
    else{
        $next_point = ++$point;
        $self->register_temp_nodata($temp_dic_ref);

        # クラス名のドット解析中であるフラグを解除する
        $self->register_temp_status($temp_dic_ref, 'DotDec', 0);
    }
    get_loglevel() > 4 and print_log("(DEBUG 5) | judge_next_word TOKEN_END");
    get_loglevel() > 4 and print_log("(DEBUG 5) | next_point =" . $next_point);
    get_loglevel() > 2 and print_log("(DEBUG 3) | [out] judge_next_word");
    return $next_point;
}


#####################################################################
# Function: process_ident_parenthesis
#
#
# 概要:
# メソッドごとの解析処理である。「識別子 (」の並びについて解析を行う。
# 識別子の内容を判別して、対応するメソッド解析処理を実行する。識別子の内容が
# 下記の場合、対応する処理を行う。
# - Stringの場合、Stringメソッド解析処理を実行する。
# - StringBufferの場合、StringBufferメソッド解析処理を実行する。
# - toStringの場合、toStringメソッド解析処理を実行する。
# - appendの場合、appendメソッド解析処理を実行する。
# - 上記以外の場合、その他メソッド解析処理を実行する。
#
# パラメータ:
# code_info_ref         - コード情報のリストのリファレンス
# point                 - 解析の開始位置
# line                  - コードが記述された行番号
# variable_dic_ref      - 変数辞書のリファレンス
# temp_dic_ref          - 一時辞書のリファレンス
# analyze_result_list   - 式解析結果(コード)のリスト(出力用)のリファレンス
#
# 戻り値:
# next_point        - 次の解析位置
#
# 特記事項:
# - 解析開始位置は、メソッド呼び出しの開始括弧である。
# - 次の解析位置は、メソッド呼び出しの終了括弧の次のトークンである。
# - 変数辞書への登録は、各解析処理に依存する。
# - 一時辞書への登録は、各解析処理に依存する。
#
#####################################################################
sub process_ident_parenthesis{
    my $self = shift;
    my ($code_info_ref, $point, $line, $variable_dic_ref, $temp_dic_ref, $analyze_result_list) = @_;
    my $next_point = $point;
    
    get_loglevel() > 2 and print_log("(DEBUG 3) | [in] process_ident_parenthesis");
    #
    # 識別子(1つ目のトークン)によってどのメソッドかを判断する
    #
    my $past_token = $$code_info_ref[$point - 1];
    
    #
    # Stringメソッドの場合
    # StringBufferメソッドの場合
    # toStringメソッドの場合
    # appendメソッドの場合
    #
    if(my $process = $G_method_processer_ref{$past_token->token()}) {
        $next_point = $process->($self, $code_info_ref, $point + 1, $line, $variable_dic_ref, 
                                 $temp_dic_ref, $analyze_result_list);
    }
    #
    # その他のメソッドの場合
    #
    else {
        $next_point = $self->process_method_the_others($code_info_ref, $point + 1,
                      $line, $variable_dic_ref, $temp_dic_ref, $analyze_result_list);
    }

    get_loglevel() > 4 and print_log("(DEBUG 5) | next_point =" . $next_point);
    get_loglevel() > 2 and print_log("(DEBUG 3) | [out] process_ident_parenthesis");
    return $next_point;
}


#####################################################################
# Function: process_ident_dot
#
# 概要:
# ドットを含む変数指定の解析処理である。「識別子 ドット」の並びについて
# 解析を行う。
# 識別子の名称で変数辞書を探索し、情報が取得できた場合は、その内容を一時辞書
# へ登録する。情報が取得できなかった場合は「解析結果なし」を一時辞書へ登録する。
#
# パラメータ:
# code_info_ref     - コード情報のリストのリファレンス
# point             - 解析の開始位置
# line              - コードの記述された行番号
# variable_dic_ref  - 変数辞書のリファレンス
# temp_dic_ref      - 一時辞書のリファレンス
#
# 戻り値:
# point             - 次の解析位置
#
#
# 特記事項:
# - 解析開始位置は、ドットの位置である。
# - 次の解析位置は、ドットの次の位置である。
# - 変数辞書への登録は行わない。
# - 一時辞書への登録は、識別子(変数)に関する情報か、「解析結果なし」を行う。
#
#####################################################################
sub process_ident_dot{
    my $self = shift;
    my ($code_info_ref, $point, $line, $variable_dic_ref, $temp_dic_ref) = @_;

    get_loglevel() > 2 and print_log("(DEBUG 3) | [in] process_ident_dot");

    #
    # クラス名のドット解析中は何もしない
    #
    if($self->refer_temp_status($temp_dic_ref, 'DotDec')){
    }
    else{
        #
        # 1つ目のトークンが変数辞書にあるか確認し、
        # 存在することが確認できた場合、一時辞書に情報を登録
        #
        my $past_token = $$code_info_ref[$point - 1];
        my $var_content = $self->refer_variable_dic($variable_dic_ref, $past_token->token());

        if($var_content and $var_content->codeType() =~ $G_is_StringClass) {
            $self->register_temp_dic($temp_dic_ref, $var_content->codeType(),
                $var_content->name(), $var_content->value(), $line, 0, $var_content->component );
        }
        else {
            $self->register_temp_nodata($temp_dic_ref);
            
            #
            # 以下のドット記述以外はドット解析中とする
            # thisトークン
            # 自身クラス名による修飾
            #
            if(   $past_token->id() != $tokenId{'THIS_TOKEN'}
               and $past_token->token() ne $self->{CLASSNAME}) {
                # クラス名のドット解析中であるフラグを一時辞書に登録する
                $self->register_temp_status($temp_dic_ref, 'DotDec', 1);
            }
        }   
    }

    get_loglevel() > 2 and print_log("(DEBUG 3) | [out] process_ident_dot");
    return ++$point;
}


#####################################################################
# Function: process_ident_analyze_end_and_calc
#
# 概要:
# 変数指定の解析処理である。「識別子 解析終端」と「識別子 演算子」の並びについて
# 解析を行う。
# - 解析状態が「変数宣言中」である場合、識別子を変数として、変数辞書と一時辞書へ
#   登録する。
# - 変数宣言以外の場合は、識別子を変数として変数辞書を探索し、情報を取得した場合
#   はその内容を一時辞書へ登録する。
#
# パラメータ:
# code_info_ref     - コード情報のリストのリファレンス
# point             - 解析の開始位置
# line              - コードが記述された行番号
# variable_dic_ref  - 変数辞書のリファレンス
# temp_dic_ref      - 一時辞書のリファレンス
#
# 戻り値:
# point             - 次の解析位置
#
# 特記事項:
# - 解析開始位置は、解析終端または演算子の位置である。
# - 次の解析位置は、解析終端または演算子の位置である(変更されない)。
# - 変数辞書への登録は、解析状態が「変数宣言中」で、なおかつその識別子が
#   変数辞書に存在しない場合に行われる。
# - 一時辞書への登録は、
#   (1) 識別子の情報を変数辞書より検出した場合、
#   (2) 識別子の情報を変数辞書より検出しなかったが、解析状態が
#      「変数宣言中」である場合、
#   に行われる。
#
#####################################################################
sub process_ident_analyze_end_and_calc{
    my $self = shift;
    my ($code_info_ref, $point, $line, $variable_dic_ref, $temp_dic_ref) = @_;
    
    my $past_token = $$code_info_ref[$point - 1];   # 1つ前のトークンを格納
    
    get_loglevel() > 2 and print_log("(DEBUG 3) | [in] process_ident_analyze_end_and_calc");


    #
    # クラス名のドット解析中は何もしない
    #
    if($self->refer_temp_status($temp_dic_ref, 'DotDec')){
    }
    else{
        my $variable_content = $self->refer_variable_dic(
                              $variable_dic_ref, $past_token->token());

        #
        # 変数辞書を探索し、検出した場合は、その内容を一時辞書へ登録する
        # 変数宣言中の場合：
        #     String b = "bbb"; "String a = b;  <-- b; に相当するケース
        # 変数宣言中でない場合：
        #     a = b;         <-- b; に相当するケース
        #
        if(defined $variable_content) {
            get_loglevel() > 4 and print_log("(DEBUG 5) | variable_content =" . $variable_content->value());
            $self->register_temp_dic($temp_dic_ref, $variable_content->codeType(),
            $variable_content->name(), $variable_content->value(), $line, 1, $variable_content->component );
        
        #
        # 変数辞書に存在しない場合、変数宣言中か否かにより処理を分岐する
        # 二項式の右辺解析中の場合、解析結果なしを登録する
        #     String b = OtherClass.unrefvalue;  <-- 他クラスの変数のケースなど
        # 変数宣言中の場合、その識別子を変数辞書へ登録する
        #     String a, b;  <-- a, または b; に相当するケース
        # 変数宣言中でない場合、解析結果なしを登録する
        #     int x = i;    <-- i; (iはint変数)に相当するケース
        #
        } else {
            if($self->refer_temp_status($temp_dic_ref, 'CalDec')) {
                $self->register_temp_nodata($temp_dic_ref);
            } elsif(my $type = $self->refer_temp_status($temp_dic_ref, 'VarDec')) {
                $self->register_variable_dic($variable_dic_ref, $type, $past_token->token(), '', $line);
                $self->register_temp_dic($temp_dic_ref, $type, $past_token->token(), '', $line);
            } else {
                $self->register_temp_nodata($temp_dic_ref);
            } 
        }
    }
    
    # クラス名のドット解析中であるフラグを解除する
    $self->register_temp_status($temp_dic_ref, 'DotDec', 0);

    get_loglevel() > 2 and print_log("(DEBUG 3) | [out] process_ident_analyze_end_and_calc");
    return $point;
}


#####################################################################
# Function: process_ident_ident
#
# 概要:
# 変数宣言の解析処理である。「識別子 識別子」の並びについて解析を行う。
# 変数宣言においては、コンマを使用した連続した宣言が行われる場合がある。
# その場合は、すべての宣言について当該関数内で制御を行う。
# - 1つめの識別子を型宣言とみなして、解析状態をその型における「変数宣言中」へ
#   遷移させる。
# - 2つめ以降の識別子(変数名)について、式解析の主制御を実行する。コンマで
#   区切られている場合は、すべての変数名について解析を行う。
#
# パラメータ:
# code_info_ref     - コード情報のリストのリファレンス
# point             - 解析の開始位置
# line              - コードが記述された行番号
# variable_dic_ref  - 変数辞書のリファレンス
# temp_dic_ref      - 一時辞書のリファレンス
#
# 戻り値:
# point             - 次の解析位置
#
# 特記事項:
# - 解析開始位置は、右端の識別子(変数名)である。
# - 次の解析位置は、右端の識別子の次のトークンである。
# - 変数辞書への登録は、型がStringがStringBufferの場合に行われる。
# - 一時辞書への登録は、型がStringがStringBufferの場合に行われる。
# - 変数名を取得する間、解析状態を「変数宣言中」へ更新する。
#
#
#####################################################################
sub process_ident_ident{
    my $self = shift;
    my ($code_info_ref, $point, $line, $variable_dic_ref, $temp_dic_ref) = @_;

    get_loglevel() > 2 and print_log("(DEBUG 3) | [in] process_ident_ident");

    my $past_token = $code_info_ref->[$point - 1];  # 型名
    my $current_token = $code_info_ref->[$point];   # 変数名

    #
    # 型名がString or StringBufferの場合
    #
    if($past_token->token() eq RESTYPE_STRING or $past_token->token() eq RESTYPE_SB){
        
        my $next_token = $code_info_ref->[$point + 1]; # 変数名の次のトークン

        #
        # 配列変数の場合は、解析結果なしとする
        #
        if(defined $next_token and $next_token->id() == $tokenId{'LSB_TOKEN'}) {
            $self->register_temp_nodata($temp_dic_ref);
            get_loglevel() > 2 and print_log("(DEBUG 3) | [out] process_ident_ident");
           return ++$point;
        }
        
        #
        # 変数情報を変数辞書と一時辞書に登録する
        #
        $self->register_variable_dic($variable_dic_ref, $past_token->token(), $current_token->token(), '', $line);
        $self->register_temp_dic($temp_dic_ref, $past_token->token(), $current_token->token(), '', $line);

        # 一時辞書に「変数宣言中」である状態を登録する
        $self->register_temp_status($temp_dic_ref, 'VarDec', $past_token->token());

        #
        # コンマで区切られている間、式解析を続行し変数名を辞書へ登録する
        #
        do {
            ++$point;
            $point = $self->judge_word($code_info_ref, $point, $line, $variable_dic_ref, $temp_dic_ref);
            $current_token = $code_info_ref->[$point];                                

        } while(defined $current_token and $current_token->id() != $tokenId{'SMC_TOKEN'});

        # 「変数宣言中」を解除する
        $self->register_temp_status($temp_dic_ref, 'VarDec', 0);

    }
    else{
        $self->register_temp_nodata($temp_dic_ref);
        ++$point;
    }

    get_loglevel() > 2 and print_log("(DEBUG 3) | [out] process_ident_ident");
    return $point;
}


#####################################################################
# Function: process_equal
#
#
# 概要
# 演算子(=)の解析処理である。実質の処理は、演算子(共通)の解析処理で実行する。
# 
#
# パラメータ:
# code_info_ref     - コード情報のリストのリファレンス
# point             - 解析の開始位置
# line              - コードが記述された行番号
# variable_dic_ref  - 変数辞書のリファレンス
# temp_dic_ref      - 一時辞書のリファレンス
#
# 戻り値:
# next_point        - 次の解析位置
#
# 特記事項:
# - 解析開始位置は、演算子の位置である。
# - 次の解析位置は、演算子の右辺の式解析結果位置である。
# - 変数辞書への登録は右辺の式解析結果に依存する。
# - 一時辞書への登録は右辺の式解析結果に依存する。
#
#####################################################################
sub process_equal {
    my $self = shift;
    return $self->process_plusequal_core((@_, 'E'));
}


#####################################################################
# Function: process_plus
#
# 概要
# 演算子(+)の解析処理である。実質の処理は、演算子(共通)の解析処理で実行する。
# 
#
# パラメータ:
# code_info_ref     - コード情報のリストのリファレンス
# point             - 解析の開始位置
# line              - コードが記述された行番号
# variable_dic_ref  - 変数辞書のリファレンス
# temp_dic_ref      - 一時辞書のリファレンス
#
# 戻り値:
# next_point        - 次の解析位置
#
# 特記事項:
# - 解析開始位置は、演算子の位置である。
# - 次の解析位置は、演算子の右辺の式解析結果位置である。
# - 変数辞書への登録は右辺の式解析結果に依存する。
# - 一時辞書への登録は右辺の式解析結果に依存する。
#
#####################################################################
sub process_plus {
    my $self = shift;
    return $self->process_plusequal_core((@_, 'P'));
}


#####################################################################
# Function: process_plus_equal
#
# 概要
# 演算子(+=)の解析処理である。実質の処理は、演算子(共通)の解析処理で実行する。
# 
#
# パラメータ:
# code_info_ref     - コード情報のリストのリファレンス
# point             - 解析の開始位置
# line              - コードが記述された行番号
# variable_dic_ref  - 変数辞書のリファレンス
# temp_dic_ref      - 一時辞書のリファレンス
#
# 戻り値:
# next_point        - 次の解析位置
#
# 特記事項:
# - 解析開始位置は、演算子の位置である。
# - 次の解析位置は、演算子の右辺の式解析結果位置である。
# - 変数辞書への登録は右辺の式解析結果に依存する。
# - 一時辞書への登録は右辺の式解析結果に依存する。
#
#####################################################################
sub process_plus_equal {
    my $self = shift;
    return $self->process_plusequal_core((@_, 'PE'));
}

#####################################################################
# Function: process_plusequal_core
#
# 概要:
# 演算子(共通)の解析処理である。演算子(+, =, +=)について解析を実行する。
# 左辺の式解析結果と右辺の式解析結果を取得し、処理種別に対応する処理を
# 実行する。
# - 処理種別が「左辺の内容を右辺に連結」の場合、「左辺の内容　右辺の内容」の
#   並びで両者を連結した文字列を生成し、一時辞書へ登録する。
# - 処理種別が「左辺へ代入」の場合、左辺より取得した変数名に、右辺の内容を
#   代入する。つまり、左辺の変数名に対する変数辞書の内容を、右辺の内容に
#   置き換える。また、右辺の内容を一時辞書へ登録する。
# - 一時辞書へ登録された情報は、「評価対象外」とする。
#
# パラメータ:
# code_info_ref     - コード情報のリストのリファレンス
# point             - 解析の開始位置
# line              - コードが記述された行番号
# variable_dic_ref  - 変数辞書のリファレンス
# temp_dic_ref      - 一時辞書のリファレンス
# type              - 処理種別(E = 左辺へ代入、P = 左辺の内容を右辺に連結)
#
# 戻り値:
# next_point        - 次の解析位置
#
# 特記事項:
# - 解析開始位置は、演算子の位置である。
# - 次の解析位置は、演算子の右辺の式解析結果位置である。
# - 変数辞書への登録は左辺の型がString, StringBufferで、演算子(=)の場合
#   左辺の変数名の内容を右辺の内容に置き換える。
# - 一時辞書への登録は左右辺の型どちらか、または両方ががString, 
#   StringBufferの場合、行われる。
#
#####################################################################
sub process_plusequal_core {
    my $self = shift;
    my ($code_info_ref, $point, $line, $variable_dic_ref, $temp_dic_ref, $type) = @_;
    
    my $isNotEvaluate = 1;               # 演算不可能な場合、真となる
    
    get_loglevel() > 2 and print_log("(DEBUG 3) | [in] process_plusequal_core");
    #
    # 左辺の式解析結果を取得する
    #
    my $leftvalue = $self->pop_temp_dic($temp_dic_ref);
    my $lefttype = undef;
    if(defined $leftvalue) {
        $lefttype = $leftvalue->codeType();
    }
    
    #
    # 左辺の式解析結果が「解析結果なし」の場合は、空白文字とする
    #
    if(!defined $lefttype or $lefttype !~ $G_is_StringClass) {
        $leftvalue = $G_ws_result;
        my @left_componet_buff = ();
        push(@left_componet_buff, VariableComponent->new(line => $line, 
            length => '1', code_count => $temp_dic_ref->{code_count}, 
            block_count => $temp_dic_ref->{block_count}));
        #
        # ブロックの追加をしたのでカウンタをカウントアップ
        #
        $temp_dic_ref->{block_count}++;

        #
        # 空白文字列をあらわす文字列位置情報を登録
        #
        $leftvalue->component(\@left_componet_buff);
    } else {
        $isNotEvaluate = 0;
    }

    # 計算中であるフラグを立てる
    $self->register_temp_status($temp_dic_ref, 'CalDec', ++($temp_dic_ref->{status}->{"CalDec"}));
    
    #
    # 右辺の式解析を実行する
    # 右辺の式解析結果は、一時辞書に格納される
    #
    my $next_point = $self->judge_word($code_info_ref, $point + 1,
                           $line, $variable_dic_ref, $temp_dic_ref);

    # 計算が終了したのでフラグを戻す
    $self->register_temp_status($temp_dic_ref, 'CalDec',  --($temp_dic_ref->{status}->{"CalDec"}));

    #
    # 右辺の式解析結果が「解析結果なし」の場合は空白文字とする
    #
    my $right_value = $self->pop_temp_dic($temp_dic_ref);
    my $right_type = undef;
    if(defined $right_value) {
        $right_type = $right_value->codeType();
    }
    
    if(!defined $right_type or $right_type !~ $G_is_StringClass) {
        $right_value = $G_ws_result;
        my @right_componet_buff = ();
        push(@right_componet_buff, VariableComponent->new(line => $line, 
            length => '1', code_count => $temp_dic_ref->{code_count}, 
            block_count => $temp_dic_ref->{block_count}));
        #
        # ブロックの追加をしたのでカウンタをカウントアップ
        #
        $temp_dic_ref->{block_count}++;

        #
        # 空白文字列をあらわす文字列位置情報を登録
        #
        $right_value->component(\@right_componet_buff);
    } else {
        $isNotEvaluate = 0;
    }
    
    get_loglevel() > 4 and print_log("(DEBUG 5) | leftvalue = " . $leftvalue->value() . '(' . $lefttype . '), rightvalue = ' . $right_value->value() . '(' . $right_type . ')');
    #
    # 左右辺共に「解析結果なし」の場合は、「解析結果なし」とする
    #
    if($isNotEvaluate) {
        $self->register_temp_nodata($temp_dic_ref);
        get_loglevel() > 4 and print_log("(DEBUG 5) | next_point =" . $next_point);
        get_loglevel() > 2 and print_log("(DEBUG 3) | [out] process_plusequal_core(isNotEvaluate)");
        return $next_point;
    }

    #
    # 演算子が+=の場合、左辺の変数情報が変更されている場合があるため、
    # 変数辞書から変数情報を再取得する。
    #
    if($type =~ m{PE} and defined $leftvalue and $leftvalue->name()){
        $leftvalue = $self->refer_variable_dic($variable_dic_ref, $leftvalue->name());
        $lefttype = $leftvalue->codeType();
    }
        
    #
    # 処理種別が「左辺の内容を右辺に連結」の場合：
    # 左辺の式解析結果へ右辺の式解析結果を連結する
    #
    my $new_value = '';
    if($type =~ m{P}xms) {
        #
        # 右辺の式解析結果が空白文字のみか判定
        # 空白文字のみ場合は新規にTemp_Contentを作成
        #
        if($#{$right_value->component} eq '0'
          and $right_value->component->[0]->line eq '0' 
          and $right_value->component->[0]->length eq '1'){
            my @componet_buff = ();
            push(@componet_buff, VariableComponent->new(line => $line, 
                length => '1', code_count => $temp_dic_ref->{code_count}, 
                block_count => $temp_dic_ref->{block_count}));
            #
            # ブロックの追加をしたのでカウンタをカウントアップ
            #
            $temp_dic_ref->{block_count}++;

            #
            # 空白文字列をあらわす文字列位置情報を登録
            #
            $right_value = Temp_Content->new(codeType => RESTYPE_STRING, name => '',
                value => ' ', line => '', val_flg =>'0', 
                component => \@componet_buff);
        }
        $new_value = $leftvalue->value() . $right_value->value();
        $lefttype = RESTYPE_STRING;
        my @componet_buff = ();
        push( @componet_buff,@{$leftvalue->component} );
        push( @componet_buff,@{$right_value->component} );
        $right_value->component(\@componet_buff);
    }
    else{
        $new_value = $right_value->value()
    }

    #
    # 処理種別が「左辺へ代入」の場合：
    # 右辺の式解析結果を左辺に代入する(一時辞書、変数辞書へ登録)
    # ただし、右辺または左辺が式解析結果なしだった場合は、本処理は行われない
    # (int a = 1; といった代入は処理しない)
    # 左辺が解析結果なしのケースは、＋演算のケースか、左右辺が解析結果なし
    # となるケースしか発生しない
    #
    if($type =~ m{E}) {
        if($lefttype =~ $G_is_StringClass) {
           if(defined $right_type and $right_type ne RESTYPE_OTHER) {
              $self->register_variable_dic($variable_dic_ref, 
                   $lefttype, $leftvalue->name(), $new_value, $line, undef, 0, 
                   $right_value->component);
           }
              $self->register_temp_dic($temp_dic_ref,
                  $lefttype, $leftvalue->name(), $new_value, $line, undef, 
                  $right_value->component);
        }
        else {
            $self->register_object_to_temp_dic($temp_dic_ref, $right_value);
        }
    }

    #
    # 左辺への代入が発生しない場合：
    # 現在の式解析結果を評価対象として一時辞書に登録する
    #
    else {
        $self->register_temp_dic($temp_dic_ref,
                $lefttype, undef, $new_value, $line, 1, 
                $right_value->component);
    }
    get_loglevel() > 4 and print_log("(DEBUG 5) | next_point =" . $next_point);
    get_loglevel() > 2 and print_log("(DEBUG 3) | [out] process_plusequal_core");
    return $next_point;
}


#####################################################################
# Function: process_sign_the_others
#
#
# 概要:
# 演算子(その他)の解析処理の解析処理である。演算子(=, +, +=)以外の
# 演算子について解析を行う。
# これらの演算子の場合は、演算子に関する処理は行なわず、右辺の式解析
# を実行する。
# - 演算子の右辺について式解析を行い、その結果を返却する。
#
# パラメータ:
# code_info_ref     - コード情報のリストのリファレンス
# point             - 解析の開始位置
# line              - コードが記述された行番号
# variable_dic_ref  - 変数辞書のリファレンス
# temp_dic_ref      - 一時辞書のリファレンス
#
# 戻り値:
# next_point        - 次の解析位置
#
# 特記事項:
# - 解析開始位置は、演算子の位置である。
# - 次の解析位置は、演算子の右辺の式解析結果位置である。
# - 一時辞書への登録は右辺の式解析結果に依存する。
# - 変数辞書への登録は右辺の式解析結果に依存する。
#
#####################################################################
sub process_sign_the_others {
    my $self = shift;
    my ($code_info_ref, $point, $line, $variable_dic_ref, $temp_dic_ref) = @_;
    my $next_point = $self->judge_word($code_info_ref, $point + 1, $line, $variable_dic_ref, $temp_dic_ref);
    $self->register_temp_nodata($temp_dic_ref);
    
    return $next_point;
}


#####################################################################
# Function: process_method_string
#
#
# 概要:
# Stringコンストラクタの処理を実行する。実質の処理は、コンストラクタの解析処理
# で実行する。
#
# パラメータ:
# code_info_ref     - コード情報のリストのリファレンス
# point             - 解析の開始位置
# line              - コードが記述された行番号
# variable_ref      - 変数辞書のリファレンス
# temp_dic_ref      - 一時辞書のリファレンス
# result_ref        - 解析結果(コード)のリストのリファレンス
#
# 戻り値:
# next_point        - 次の解析位置
#
#
# 特記事項:
# - 解析開始位置は、コンストラクタ開始括弧の次のトークンである。
# - 次の解析位置は、コンストラクタ終了括弧の次のトークンである。
# - 一時辞書への登録はコンストラクタの解析結果に依存する。
# - 変数辞書への登録は行われない。
#
#####################################################################
sub process_method_string {
    my $self = shift;
    my ($code_info_ref, $point, $line, $variable_ref, $temp_dic_ref, $result_ref) = @_;
    return $self->process_method_construct($code_info_ref, $point, $line, $variable_ref, 
                                    $temp_dic_ref, $result_ref, RESTYPE_STRING);
}

#####################################################################
# Function: process_method_stringbuffer
#
#
# 概要:
# StringBufferコンストラクタの処理を実行する。実質の処理は、コンストラクタの
# 解析処理で実行する。
#
# パラメータ:
# code_info_ref     - コード情報のリストのリファレンス
# point             - 解析の開始位置
# line              - コードが記述された行番号
# variable_ref      - 変数辞書のリファレンス
# temp_dic_ref      - 一時辞書のリファレンス
# result_ref        - 解析結果(コード)のリストのリファレンス
#
# 戻り値:
# next_point            - 次の解析位置
#
#
# 特記事項:
# - 解析開始位置は、コンストラクタ開始括弧の次のトークンである。
# - 次の解析位置は、コンストラクタ終了括弧の次のトークンである。
# - 一時辞書への登録はコンストラクタの解析結果に依存する。
# - 変数辞書への登録は行われない。
#
#####################################################################
sub process_method_stringbuffer {
    my $self = shift;
    my ($code_info_ref, $point, $line, $variable_ref, $temp_dic_ref, $result_ref) = @_;
    return $self->process_method_construct($code_info_ref, $point, $line, $variable_ref, 
                                    $temp_dic_ref, $result_ref, RESTYPE_SB);
}


#####################################################################
# Function: process_method_construct
#
#
# 概要:
# コンストラクタの解析処理である。
# 1パラメータで構成されるコンストラクタ指定の場合、そのパラメータの
# 内容を一時辞書へ格納する。そうでない場合は空文字列を一時辞書へ格納する。
#
# パラメータ:
# code_info_ref     - コード情報のリストのリファレンス
# point             - 解析の開始位置
# line              - コードが記述された行番号
# variable_ref      - 変数辞書のリファレンス
# temp_dic_ref      - 一時辞書のリファレンス
# result_ref        - 解析結果(コード)のリストのリファレンス
# result_type       - 戻り値の型文字列
#
# 戻り値:
# next_point        - 次の解析位置
#
# 特記事項:
# - 解析開始位置は、コンストラクタ開始括弧の次のトークンである。
# - 次の解析位置は、コンストラクタ終了括弧の次のトークンである。
# - 一時辞書への登録はコンストラクタの解析結果に依存する。
# - 変数辞書への登録は行われない。
#
#####################################################################
sub process_method_construct {
    my $self = shift;
    my ($code_info_ref, $point, $line, $variable_ref, $temp_dic_ref, $result_ref, $result_type) = @_;
    
    get_loglevel() > 2 and print_log("(DEBUG 3) | [in] process_method_construct");
    #
    # パラメータなしのコンストラクタの場合は空文字を登録して終了する
    #
    my $current_token = $code_info_ref->[$point];
    if($current_token->id() == $tokenId{'RP_TOKEN'}) {
        $self->register_temp_dic($temp_dic_ref, $result_type, undef, '', $line, 0);
        get_loglevel() > 4 and print_log("(DEBUG 5) | no parameter found.");
        get_loglevel() > 2 and print_log("(DEBUG 3) | [out] process_method_construct");
        return ++$point;
    }
    
    # メソッド宣言中であるフラグを立てる
    $self->register_temp_status($temp_dic_ref, 'MethodDec', ++($temp_dic_ref->{status}->{"MethodDec"}));
    
    #
    # 現在の開始位置（第１パラメータ）について式解析を実行する
    #
    my $next_point = $self->judge_word($code_info_ref, $point, $line, $variable_ref, $temp_dic_ref, $result_ref);
    my $next_token = $code_info_ref->[$next_point];
    
    #
    # StringXXX(String original)形式の指定の場合、originalの内容を一時辞書へ登録する
    # (実際の登録処理は、judge_word内で実施済みである)
    #
    if($next_token->id() == $tokenId{'RP_TOKEN'}) {
        get_loglevel() > 4 and print_log("(DEBUG 5) | A String object parameter found.");
        #
        # 登録されている一時辞書のデータ型を
        #  Stringのコンストラクタの場合はString型、StringBufferのコンストラクタの場合はStringBuffer型
        # へ変更する
        #
        if($result_type eq RESTYPE_STRING){
            my $result = $self->pop_temp_dic($temp_dic_ref);
                get_loglevel() > 4 and print_log("(DEBUG 5) | object type ->" . $result->codeType());
            #
            # Stringオブジェクト生成時、パラメタのデータ型がString型の場合のみ
            # String型に変更した情報を一時辞書に登録する。
            #
            if($result->codeType() eq RESTYPE_STRING){
                $self->register_temp_dic($temp_dic_ref, RESTYPE_STRING, undef, $result->value(), 
                                         $result->line(), $result->val_flg(), $result->component );
            }
            else{
                
                #
                # パラメータがStringオブジェクト以外の場合は、解析処理を実施
                # しない。つまり、当コンストラクタにパラメータが指定されて
                # いなかったように振舞う
                # - 変数が指定されていた場合は、変数の参照フラグをコンストラクタ
                #   による解析前の状態に戻す
                # - 変数でない場合は、そのパラメータの式解析結果を一時辞書に
                #   戻す
                #
                if($result->name()) {
                    my $reffered_var = $self->refer_variable_dic($variable_ref, $result->name(), 1);
                    if(defined $reffered_var) {
                        get_loglevel() > 4 and do {
                            my $value = defined $reffered_var->prev_ref_flg() ? $reffered_var->prev_ref_flg() : "undef";
                            print_log("(DEBUG 5) | set variable_dic::ref_flg to " . $value . ".  name = " . $result->name());
                        };
                        $reffered_var->ref_flg($reffered_var->prev_ref_flg());                        
                    }
                } else {
                    $self->register_object_to_temp_dic($temp_dic_ref, $result);
                }
                $self->register_temp_nodata($temp_dic_ref);
            }           
        }
        #
        # StringBufferコンストラクタの場合は、パラメータの式解析結果の型を
        # StringBuffer型に変更する
        #
        else{
            my $result = $self->pop_temp_dic($temp_dic_ref);
            $self->register_temp_dic($temp_dic_ref, RESTYPE_SB, undef, $result->value(), 
                                $result->line(), $result->val_flg(), $result->component );           
        }
    }
    #
    # StringXXX(String original)形式以外の指定の場合、当該メソッド呼び出しの
    # 式解析結果を空文字とする
    # メソッド実行分を右括弧までとばす
    #
    else{
        $next_point = $self->skip_token($code_info_ref, $next_point, 'RP_TOKEN');
        $self->pop_temp_dic($temp_dic_ref);
        $self->register_temp_dic($temp_dic_ref, $result_type, undef, '', $line, 0);
    }

    # メソッドが終了したのでフラグを戻す
    $self->register_temp_status($temp_dic_ref, 'MethodDec', --($temp_dic_ref->{status}->{"MethodDec"}));
    
    get_loglevel() > 2 and print_log("(DEBUG 3) | [out] process_method_construct");
    return ++$next_point;
}


#####################################################################
# Function: process_method_tostring
#
#
# 概要:
# toStringメソッド解析処理である。
# - toString()の場合、何もしない(呼び出し元オブジェクトの式解析結果は既に
#   一時辞書へ登録済みである)。
# - toString(パラメータ)の場合、その他メソッド解析処理を実行する。
#
# パラメータ:
# code_info_ref     - コード情報のリストのリファレンス
# point             - 解析の開始位置
# line              - コードが記述された行番号
# variable_ref      - 変数辞書のリファレンス
# temp_dic_ref      - 一時辞書のリファレンス
# result_ref        - 解析結果(コード)のリストのリファレンス
#
# 戻り値:
# next_point            - 次の解析位置
#
# 例外:
# なし
#
# 特記事項:
# - 解析開始位置は、toString開始括弧の次のトークンである。
# - 次の解析位置は、メソッド終了括弧の次のトークンである。
# - 一時辞書への登録は行われない（既に登録済みであるため）。
# - 変数辞書への登録は行われない。
#
#####################################################################
sub process_method_tostring {
    my $self = shift;
    my ($code_info_ref, $point, $line, $variable_ref, $temp_dic_ref, $result_ref) = @_;

    get_loglevel() > 2 and print_log("(DEBUG 3) | [in] process_method_tostring");

    my $current_token = $code_info_ref->[$point];

    if($current_token->id() != $tokenId{'RP_TOKEN'}) {
        $point = $self->process_method_the_others($code_info_ref, $point, $line, 
                        $variable_ref, $temp_dic_ref, $result_ref);
    }
    #
    # toString()の場合、呼出元変数の値を評価対象とする。
    #
    else{
        my $result = $self->pop_temp_dic($temp_dic_ref);
        if(defined $result and $result->codeType() =~ $G_is_StringClass) {
            $self->register_temp_dic($temp_dic_ref, RESTYPE_STRING, $result->name(), $result->value(), 
                                $result->line(), 1, $result->component );
        } else {
            $self->register_temp_nodata($temp_dic_ref);
        }
        ++$point;
    }
    
    get_loglevel() > 2 and print_log("(DEBUG 3) | [out] process_method_tostring");
    return $point;
    
}


#####################################################################
# Function: process_method_append
#
#
# 概要:
# appendメソッド解析処理である。
# - 呼び出し元オブジェクトの型がStringBufferの場合、呼び出し元オブジェクトの
#   内容(一時辞書に格納)と、パラメータの式解析結果の内容を連結し、その結果を
#   変数辞書と一時辞書へ格納する。
# - 呼び出し元オブジェクトの型がStringBuffer以外の場合、その他メソッド解析処理を
#   実行する。
#
# パラメータ:
# code_info_ref     - コード情報のリストのリファレンス
# point             - 解析の開始位置
# line              - コードが記述された行番号
# variable_ref      - 変数辞書のリファレンス
# temp_dic_ref      - 一時辞書のリファレンス
# result_ref        - 解析結果(コード)のリストのリファレンス
#
# 戻り値:
# next_point        - 次の解析位置
#
# 特記事項:
# - 解析開始位置は、append開始括弧の次のトークンである。
# - 次の解析位置は、メソッド終了括弧の次のトークンである。
# - 一時辞書への登録は、呼び出し元オブジェクトの型がStringBufferの場合、行われる。
# - 変数辞書への登録は、呼び出し元オブジェクトの型がStringBufferの場合、行われる。
#
#####################################################################
sub process_method_append {
    my $self = shift;
    my ($code_info_ref, $point, $line, $variable_ref, $temp_dic_ref, $result_ref) = @_;

    get_loglevel() > 2 and print_log("(DEBUG 3) | [in] process_method_append");

    my $current_token = $code_info_ref->[$point - 1];
    my $next_point = $point;
    
    #
    # appendメソッド呼び出し元の情報を取得する
    #
    my $varinfo = $self->refer_temp_dic($temp_dic_ref);
    
    #
    # appendメソッド呼び出し元がStringBufferの場合、文字列の連結を行う
    #
    if(defined $varinfo and $varinfo->codeType eq RESTYPE_SB) {
    
        #
        # 呼び出し元オブジェクトの解析結果を取得しておく
        #
        $varinfo = $self->pop_temp_dic($temp_dic_ref);

        # メソッド宣言中であるフラグを立てる
        $self->register_temp_status($temp_dic_ref, 'MethodDec', ++($temp_dic_ref->{status}->{"MethodDec"}));
        
        #
        # パラメータの解析結果がStringかStringBufferの場合、その内容を
        # 一時辞書に登録する(実際の登録処理は、judge_word内で実施済みである)
        #
        $next_point = $self->judge_word($code_info_ref, $next_point, $line, $variable_ref, 
                                 $temp_dic_ref, $result_ref);
        
        # メソッドが終了したのでフラグを戻す
        $self->register_temp_status($temp_dic_ref, 'MethodDec', --($temp_dic_ref->{status}->{"MethodDec"}));
    
        #
        # パラメータの式解析結果がStringかStringBufferの場合は右辺の内容を左辺に連結、代入する
        # パラメータ式解析結果がStringでもStringBufferでもない場合は、空白文字を連結する
        # - sb.append(1)など
        #
        my $paraminfo = $self->pop_temp_dic($temp_dic_ref);
        my $appended_string = $varinfo->value();

        if(defined $paraminfo and $paraminfo->codeType() =~ $G_is_StringClass) {
            $appended_string .= $paraminfo->value();
        } else {
            $appended_string .= ' ';
            my @componet_buff = ();
            push(@componet_buff, VariableComponent->new(line => $line, 
                length => '1', code_count => $temp_dic_ref->{code_count}, 
                block_count => $temp_dic_ref->{block_count}));
            #
            # ブロックの追加をしたのでカウンタをカウントアップ
            #
            $temp_dic_ref->{block_count}++;

            #
            # 空白文字列をあらわす文字列位置情報を登録
            #
            $paraminfo->component(\@componet_buff);
            #
            # 複数パラメータappendの場合、メソッド完了の括弧までポインタを進める
            # その間の文字列(J2SE6では存在しない)は無視される
            #
            $next_point = $self->skip_token($code_info_ref, $next_point, 'RP_TOKEN');
        }
        #
        # 連結結果を一時辞書と変数辞書へ登録
        #
        $self->register_temp_dic($temp_dic_ref,
                RESTYPE_SB, $varinfo->name(), $appended_string, $line, undef, 
                $varinfo->component, $paraminfo->value(), $paraminfo->component );
        if(defined $varinfo->name){
            $self->register_variable_dic($variable_ref, 
                   RESTYPE_SB, $varinfo->name(), $appended_string, $line, undef, 0, 
                    $varinfo->component, $paraminfo->value(), $paraminfo->component );
        }
        ++$next_point;
    }
    #
    # 呼び出し元がStringBufferではない場合は、その他メソッド解析処理を行う
    #
    else {
        $next_point = $self->process_method_the_others($code_info_ref, $point, $line, 
                                $variable_ref, $temp_dic_ref, $result_ref);
    }

    get_loglevel() > 2 and print_log("(DEBUG 3) | [out] process_method_append");
    return $next_point;
}


#####################################################################
# Function: process_method_the_others
#
#
# 概要:
# その他メソッド解析処理である。
# パラメータに対して式解析の主制御を行い、その結果、文字列リテラルが
# 取得できた場合は「評価対象」として、一時辞書へ登録する。
#
# パラメータ:
# code_info_ref     - コード情報のリストのリファレンス
# point             - 解析の開始位置
# line              - コードが記述された行番号
# variable_ref      - 変数辞書のリファレンス
# temp_dic_ref      - 一時辞書のリファレンス
# result_ref        - 解析結果(コード)のリストのリファレンス
#
# 戻り値:
# next_point        - 次の解析位置
#
# 特記事項:
# - 解析開始位置は、メソッド開始括弧の次のトークンである。
# - 次の解析位置は、メソッド終了括弧の次のトークンである。
# - 一時辞書への登録は、パラメータより文字列リテラルが取得できた場合、行われる。
# - 変数辞書への登録は行われない。
#
#####################################################################
sub process_method_the_others {
    my $self = shift;
    my ($code_info_ref, $point, $line, $variable_ref, $temp_dic_ref, $result_ref) = @_;
    
    get_loglevel() > 2 and print_log("(DEBUG 3) | [in] process_method_the_others");
    my $next_point = $point;
    my $current_token = $code_info_ref->[$point];
    
    #
    # その他のメソッドの場合、変数情報に対して作用することはないため、当該
    # メソッドを実行するために参照しているオブジェクトについて、参照前の
    # 状態へ戻す
    #
    # ただし、親スコープからカレントスコープへコピーしてきた変数情報の場合は、
    # 親スコープにて報告されることが予測されるので、この場合は「参照済み」の
    # ままとする
    #
    my $result = $self->refer_temp_dic($temp_dic_ref);
    if($result and defined $result->name() and $result->name() ne '') {

        my $reffered_var = $self->refer_variable_dic($variable_ref, $result->name(), 1);
        
        if(!defined $reffered_var->prev_ref_flg() and !$reffered_var->copy()) {
            get_loglevel() > 4 and print_log("(DEBUG 5) | set variable_dic::ref_flg to undef.  name = " . $result->name());
            $reffered_var->ref_flg(undef);      
        }
    }
    
    # メソッド宣言中であるフラグを立てる
    $self->register_temp_status($temp_dic_ref, 'MethodDec', ++($temp_dic_ref->{status}->{"MethodDec"}));

    # )まで式解析を実行
    while($current_token->id() != $tokenId{'RP_TOKEN'}) {
        $next_point = $self->judge_word($code_info_ref, $next_point, $line, $variable_ref, 
                                 $temp_dic_ref, $result_ref);
        
        #
        # パラメータの解析結果がStringかStringBufferの場合、その内容を
        # 評価対象として一時辞書に登録する(実際の登録処理は、judge_word内で実施済みである)
        #
        my $parameter_value = $self->refer_temp_dic($temp_dic_ref);
        if(defined $parameter_value and $parameter_value->codeType =~ $G_is_StringClass) {
            $parameter_value->val_flg(1);
        }

        #
        # 現在のトークンがパラメータ区切り(,)である場合は次のトークンを取得する
        #
        $code_info_ref->[$next_point]->id() == $tokenId{'CM_TOKEN'} and $next_point++;
        $current_token = $code_info_ref->[$next_point];
    }
    
    # メソッドが終了したのでフラグを戻す
    $self->register_temp_status($temp_dic_ref, 'MethodDec', --($temp_dic_ref->{status}->{"MethodDec"}));

    # メソッドの式解析結果として空白文字を登録する
    $self->register_temp_whitespace($temp_dic_ref);

my @componet_buff = ();
push(@componet_buff, VariableComponent->new(line => $line, 
    length => '1', code_count => $temp_dic_ref->{code_count}, 
    block_count => $temp_dic_ref->{block_count}));
#
# ブロックの追加をしたのでカウンタをカウントアップ
#
$temp_dic_ref->{block_count}++;

#
# 空白文字列をあらわす文字列位置情報を登録
#
$temp_dic_ref->{stack}->[$#{$temp_dic_ref->{stack}}]->component(\@componet_buff);

    get_loglevel() > 2 and print_log("(DEBUG 3) | [out] process_method_the_others");
    return ++$next_point;
}


#####################################################################
# Function: register_analyze_result_dic
#
#
# 概要:
# 式解析結果辞書に登録する処理を実行する。
#
# パラメータ:
# analyze_result_list   - 式解析結果(コード)のリスト(出力用)
# temp_dic_ref          - 一時辞書のリファレンス
# line                  - 行番号
#
# 戻り値:
# なし
#
# 例外:
# なし
#
# 特記事項:
# 下記のタイミングで式解析結果辞書に書き込む。ただし、格納対象となる文字列が
# 空白文字以外の場合に限る。
# - 解析終端で式解析結果に書き込む。
# - スコープ終了時に一時辞書内で参照フラグが立っていない情報を式解析結果に書き込む。
# 格納情報としては文字列がリストとして保持されている。
#
#####################################################################
sub register_analyze_result_dic {
    my $self = shift;
    my ($analyze_result_list, $temp_dic_ref, $line) = @_;

    get_loglevel() > 2 and print_log("(DEBUG 3) | [in] register_analyze_result_dic");
    
    while(my $one_result = $self->pop_temp_dic($temp_dic_ref)) {
        
        #
        # 参照フラグが「評価対象」であり、なおかつ空白のみの文字列でない
        # 場合は式解析結果に登録する
        #
        if(    $one_result->val_flg() and defined $one_result->value()
           and $one_result->value() !~ m{^\s*$}xms) {
           	if(!defined $one_result->name()){
           		$one_result->name('[no identifier]');
           	}
            my $targstr = $G_current_method_name . ':' . $one_result->name() . ":" . $line;
            push(@{$analyze_result_list}, 
                AnalysisResultsCode->new(target=> $one_result->value(),
                                        linenumber => $targstr, variablename => $one_result->name(), details => $one_result->component)
            );
        get_loglevel() > 4 and print_log("(DEBUG 5) | AnalysisResultsCode=".$one_result->value());
        }
    }
    get_loglevel() > 2 and print_log("(DEBUG 3) | [out] register_analyze_result_dic");
}


#####################################################################
# Function: register_analyze_result_at_scope
#
#
# 概要:
# 式解析結果辞書に登録する処理を実行する。
#
# パラメータ:
# analyze_result_list   - 式解析結果(コード)のリスト(出力用)
# variable_dic_ref      - 変数辞書のリファレンス
#
# 戻り値:
# なし
#
# 例外:
# なし
#
# 特記事項:
# 下記のタイミングで式解析結果辞書に書き込む。
# - 解析終端で式解析結果に書き込む。
# - スコープ終了時に変数辞書内で参照フラグが立っていない変数を式解析結果に書き込む。
# 格納情報としては文字列がリストとして保持されている。
#
#####################################################################
sub register_analyze_result_at_scope {
    my $self = shift;
    my ($analyze_result_list, $variable_dic_ref) = @_;
    
    get_loglevel() > 2 and print_log("(DEBUG 3) | [in] register_analyze_result_at_scope");
    for my $value(values (%{$variable_dic_ref->variable_contents_ref})) {
        if(defined $value->value() and $value->value() !~ m{^\s*$}xms and !($value->ref_flg())) {

    		my $targstr = "";
    		if($G_current_method_name eq '[no name]') {
    			$targstr = '[class variable]';
    		} else {
    			$targstr = $G_current_method_name;
    		}
            if(!defined $value->name()) {
                $value->name('[no identifier]');
            }
            $targstr .= ':' . $value->name() . ':' . $value->line();

            push(@{$analyze_result_list}, 
                AnalysisResultsCode->new(target=> $value->value(),
                                        linenumber => $targstr, variablename => $value->name(), details => $value->component)
            );
            get_loglevel() > 4 and print_log("(DEBUG 5) | AnalysisResultsCode=".$value->value());
        }
    }
    get_loglevel() > 2 and print_log("(DEBUG 3) | [out] register_analyze_result_at_scope");
}


#####################################################################
# Function: create_variable_dic
#
#
# 概要:
# 変数辞書を新規に作成する。
#
# パラメータ:
# parent - 親変数辞書
#
# 戻り値:
# 変数辞書
#
# 例外:
# なし
#
# 特記事項:
# なし
#
#####################################################################
sub create_variable_dic {
    my $self = shift;
    my ($parent) = @_;
    return VariableDic->new(parent => $parent, variable_contents_ref => {});
}


#####################################################################
# Function: register_variable_dic
#
#
# 概要:
# 指定された変数名に対する変数情報を変数辞書へ登録する。既に当該変数名
# で登録済みの場合は、値の内容と行番号を上書きする。
# 連結文字列の有無で、連結結果格納時か判定し、
# 連結時は既存の連結文字列情報を追加して登録する。
#
# パラメータ:
# variable_dic_ref  - 変数辞書のリファレンス
# codeType          - 型名
# name              - 変数名
# value             - 値
# line              - 記述された行番号
# ref_flg           - 当該変数が参照された場合に真となるフラグ
# copy              - 親の変数辞書からコピーした際に真となるフラグ
# component         - 連結文字列情報
# appended          - 連結文字列
# append_component  - 追加分の連結文字列情報
#
# 戻り値:
# なし
#
# 例外:
# なし
#
# 特記事項:
# - 格納情報は、データ型、変数名、値、行、参照フラグである。
# - 登録時に参照フラグを「未参照」に設定する。
#
#####################################################################
sub register_variable_dic {
    my $self = shift;
    my ($variable_dic_ref, $codeType, $name, $value, $line, $ref_flg, $copy, $component, $appended, $append_component) = @_;
    my @componet_buff = ();
    
    get_loglevel() > 2 and print_log("(DEBUG 3) | [in] register_variable_dic");

    my $varinfo = $self->refer_variable_dic($variable_dic_ref, $name, 1);
    
    if(!defined $varinfo) {
        $varinfo = VariableContent->new(codeType => $codeType, name => $name);
        $variable_dic_ref->variable_contents_ref->{$name} = $varinfo;
    }
    
    $varinfo->value($value);
    $varinfo->line($line);
    $varinfo->prev_ref_flg($varinfo->ref_flg());
    $varinfo->ref_flg($ref_flg);
    $varinfo->copy($copy);
    if (defined $appended) {
        #
        # 文字列追加かつ既存のcomponentが存在か判定
        #
        if(defined $component){
                @componet_buff = @{$component};
        }
        #
        # 追加文字列分のcomponentを追加
        #
        push(@componet_buff, @{$append_component});
        $varinfo->component(\@componet_buff);
    } elsif(defined $component) {
        #
        # 文字列追加でなく既存のcomponentが存在の場合は引き継ぐ
        #
        $varinfo->component($component);
    }else {
        #
        # 文字列追加でなく既存のcomponentが存在しないの場合は新規と考え
        # 値をそのままcomponentに登録する
        #
        push(@componet_buff, VariableComponent->new(
            line => $line, length => length($value), code_count => 0, block_count => 0));
        $varinfo->component(\@componet_buff);
    }

    get_loglevel() > 4 and print_log("(DEBUG 5) | name=(".$name.")");
    get_loglevel() > 4 and print_log("(DEBUG 5) | value=(".$value.")");
    get_loglevel() > 4 and print_log("(DEBUG 5) | line=(".$line.")");
    get_loglevel() > 2 and print_log("(DEBUG 3) | [out] register_variable_dic");
}


#####################################################################
# Function: refer_variable_dic
#
#
# 概要:
# 指定された変数名に対する変数情報を変数辞書から取得する。当該変数辞書
# より取得できない場合は、親の変数辞書を参照する。
# 親の変数辞書が参照できない場合は、結果なし(undef)を返却する。
#
# パラメータ:
# variable_dic_ref  - 変数辞書のリファレンス
# variable_name     - 変数名
# no_update         - 参照フラグの更新を抑止する場合は真を指定する
#
# 戻り値:
# variable_content  - 変数情報(変数辞書)のリファレンス
#
# 例外:
# なし
#
# 特記事項:
# - 格納情報は、データ型、変数名、値、行、参照フラグである。
# - 参照時に参照フラグ「参照済み」に更新する。
#
#####################################################################
sub refer_variable_dic {
    my $self = shift;
    my ($variable_dic_ref, $variable_name, $no_update) = @_;
    my $result = $variable_dic_ref->variable_contents_ref->{$variable_name};
    my $parent_ref;
    if(!defined $result and $variable_dic_ref->parent()) {
        $parent_ref = 1;
        $result = $self->refer_variable_dic($variable_dic_ref->parent(), $variable_name, 1);
    }

    #
    # 親の変数辞書を参照し、変数が定義されている場合は、
    # 現在の変数辞書にコピーを作成する
    #
    if(defined $parent_ref and defined $result){
        my $varinfo = VariableContent->new(codeType => $result->codeType(), name => $result->name());
        $variable_dic_ref->variable_contents_ref->{$result->name()} = $varinfo;

        $varinfo->value($result->value());
        $varinfo->line($result->line());
        $varinfo->component($result->component());

        if(!defined $no_update){
            $varinfo->prev_ref_flg($result->ref_flg());
            $varinfo->ref_flg(1);
        }
        
        #親からコピーしたのでフラグを立てる
        $varinfo->copy(1);
        
        return $varinfo;
    }
    else{
        if(defined $result and !defined $no_update){
            $result->prev_ref_flg($result->ref_flg());
            $result->ref_flg(1);
        }
    }

    return $result;
}


#####################################################################
# Function: register_temp_dic
#
#
# 概要:
# 一時辞書に登録する処理を実行する。
#
# パラメータ:
# temp_dic_ref - 一時辞書のリファレンス
# codetype     - 登録対象の型
# name         - 登録対象の変数名(存在しない場合はundef)
# value        - 登録する文字列
# line         - 登録対象が記述された行番号
# val_flg      - 評価対象となる内容の場合、真
# component    - 連結文字列情報
# appended     - 連結文字列
# append_component  - 追加分の連結文字列情報
#
# 戻り値:
# なし
#
# 例外:
# なし
#
# 特記事項:
# - 一時辞書はスタックとして振舞う。
# - 格納情報は、データ型、変数名、値、行番号である。
#
#####################################################################
sub register_temp_dic {
    my $self = shift;
    my ($temp_dic_ref, $codetype, $name, $value, $line, $val_flg, $component, $appended, $append_component) = @_;
    my @componet_buff = ();
    
    get_loglevel() > 2 and print_log("(DEBUG 3) | [in] register_temp_dic");
    #
    # 一時変数辞書へ登録する
    #
    my $temp_dic_content = new Temp_Content();
    $temp_dic_content->codeType($codetype);
    defined $name and $name ne '' and $temp_dic_content->name($name);
    $temp_dic_content->value($value);
    $temp_dic_content->line($line);
    $temp_dic_content->val_flg($val_flg);

    if (defined $appended) {
        if(defined $component){
            @componet_buff = @{$component};
        }
        #
        # 追加文字列分のcomponentを追加
        #
        push(@componet_buff, @{$append_component});
        $temp_dic_content->component(\@componet_buff);
    } elsif(defined $component) {
        #
        # 文字列追加でなく既存のcomponentが存在の場合は引き継ぐ
        #
        $temp_dic_content->component($component);
    } else {
        #
        # 文字列追加でなく既存のcomponentが存在しないの場合は新規と考え
        # 値をそのままcomponentに登録する
        #
        push(@componet_buff, VariableComponent->new(
            line => $line, length => length($value), code_count => $temp_dic_ref->{code_count}, block_count => $temp_dic_ref->{block_count}));
        $temp_dic_content->component(\@componet_buff);
        #
        # ブロックの追加をしたのでカウンタをカウントアップ
        #
        $temp_dic_ref->{block_count}++;
    }

    push(@{$temp_dic_ref->{stack}}, $temp_dic_content);
    get_loglevel() > 4 and print_log("(DEBUG 5) | codeType=(".$codetype.")");
    get_loglevel() > 4 and do {
        if(defined $name) {
            print_log("(DEBUG 5) | name=(".$name.")"); 
        } else {
            print_log("(DEBUG 5) | name=(undef)"); 
        }
    };
    get_loglevel() > 4 and print_log("(DEBUG 5) | value=(".$value.")");
    get_loglevel() > 4 and print_log("(DEBUG 5) | line=(".$line.")");
    get_loglevel() > 2 and print_log("(DEBUG 3) | [out] register_temp_dic");
}


#####################################################################
# Function: register_object_to_temp_dic
#
#
# 概要:
# 一時辞書に一時辞書内容オブジェクトを登録する。
#
# パラメータ:
# temp_dic_ref - 一時辞書のリファレンス
# object       - 一時辞書内容のオブジェクト
#
# 戻り値:
# なし
#
# 例外:
# なし
#
# 特記事項:
# - 一時辞書はスタックとして振舞う。
# - 格納情報は、データ型、変数名、値、行番号である。
#
#####################################################################
sub register_object_to_temp_dic {
    my $self = shift;
    my ($temp_dic_ref, $object) = @_;
    get_loglevel() > 2 and print_log("(DEBUG 3) | [in] register_object_to_temp_dic");
    get_loglevel() > 4 and print_log("(DEBUG 5) | name = " . $object->name());
    push(@{$temp_dic_ref->{stack}}, $object);
    get_loglevel() > 2 and print_log("(DEBUG 3) | [out] register_object_to_temp_dic");
}

#####################################################################
# Function: register_temp_status
#
#
# 概要:
# 一時辞書に現在の状況を登録する。
#
# パラメータ:
# temp_dic_ref - 一時辞書のリファレンス
# key          - 状況名
# value        - 登録する情報
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
sub register_temp_status {
    my $self = shift;
    my ($temp_dic_ref, $key, $value) = @_;
    get_loglevel() > 2 and print_log("(DEBUG 3) | [in] register_temp_status");
    $temp_dic_ref->{status}->{$key} = $value;
    get_loglevel() > 4 and print_log("(DEBUG 5) | set $key => $value");
    get_loglevel() > 2 and print_log("(DEBUG 3) | [out] register_temp_status");
}


#####################################################################
# Function: refer_temp_status
#
#
# 概要:
# 一時辞書より現在の状況を参照する。
#
# パラメータ:
# temp_dic_ref - 一時辞書のリファレンス
# key          - 状況名
#
# 戻り値:
# value - 状況に対する情報
#
# 例外:
# なし
#
# 特記事項:
# なし
#
#####################################################################
sub refer_temp_status {
    my $self = shift;
    return $_[0]->{status}->{$_[1]};
}


#####################################################################
# Function: register_temp_nodata
#
#
# 概要:
# 一時辞書に「解析結果なし」を登録する。
#
# パラメータ:
# temp_dic_ref - 一時辞書のリファレンス
#
# 戻り値:
# なし
#
# 例外:
# なし
#
# 特記事項:
# - 「解析結果なし」を示す一時辞書内容はG_no_result変数に生成済みである。
#
#####################################################################
sub register_temp_nodata {
    my $self = shift;
    push(@{$_[0]->{stack}}, $G_no_result);
}   

#####################################################################
# Function: register_temp_whitespace
#
#
# 概要:
# 一時辞書に「空白文字」を登録する。
#
# パラメータ:
# temp_dic_ref - 一時辞書のリファレンス
#
# 戻り値:
# なし
#
# 例外:
# なし
#
# 特記事項:
# - 「空白文字」を示す一時辞書内容はG_ws_result変数に生成済みである。
#
#####################################################################
sub register_temp_whitespace {
    my $self = shift;
    push(@{$_[0]->{stack}}, $G_ws_result);
}   


#####################################################################
# Function: pop_temp_dic
#
#
# 概要:
# 一時辞書に登録された最も新しい一時辞書内容をpopする。
#
# パラメータ:
# temp_dic_ref          - 一時辞書のリファレンス
#
# 戻り値:
# temp_content - 一時辞書内容
#
# 例外:
# なし
#
# 特記事項:
# なし
#
#####################################################################
sub pop_temp_dic {
    my $self = shift;
    return pop(@{$_[0]->{stack}});
}


#####################################################################
# Function: refer_temp_dic
#
#
# 概要:
# 一時辞書に登録された最も新しい一時辞書内容を参照する。popはしない。
#
# パラメータ:
# temp_dic_ref      - 一時辞書のリファレンス
#
# 戻り値:
# temp_content      - 一時辞書内容
#
# 例外:
# なし
#
# 特記事項:
# なし
#
#####################################################################
sub refer_temp_dic {
    my $self = shift;
    return $_[0]->{stack}->[$#{$_[0]->{stack}}];
}

#####################################################################
# Function: skip_token
#
#
# 概要:
# 指定されたトークンまでポインタを進め、そのポインタを返却する。
# トークン中にネストされた丸括弧が存在する場合は括弧の対応が完了するまで
# ポインタを進める。
#
# パラメータ:
# code_info_ref - 式リスト
# point         - 式リスト上のトークン開始位置
# token_name    - トークン名 
#
# 戻り値:
# point - トークンまで進めたポインタ
#
# 例外:
# なし
#
# 特記事項:
# なし
#
#####################################################################
sub skip_token {
    my $self = shift;
    my ($code_info_ref, $point, $token_name) = @_;

    my $brace_count = 0;
    my $next_token = $code_info_ref->[$point];
        
    while(!($brace_count == 0 and $next_token->id() == $tokenId{$token_name})){
        #
        # パラメータ内のネストされた括弧を読み飛ばす
        #
        $next_token->id() == $tokenId{'LP_TOKEN'} and $brace_count++;
        $next_token->id() == $tokenId{'RP_TOKEN'} and $brace_count--;
            
        $point++;
        $next_token = $code_info_ref->[$point];
    }
    
    return $point;
}


1;
