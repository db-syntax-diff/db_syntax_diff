#############################################################################
#  Copyright (C) 2010 NTT
#############################################################################

#####################################################################
# Function: CScopeAnalyzer.pm
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

package PgSqlExtract::CExpressionAnalyzer::CScopeAnalyzer;
use warnings;
no warnings "recursion";
use strict;
use Carp;
use utf8;

use Class::Struct;
use List::Util qw( first );
use PgSqlExtract::Common;

#
# variable: G_is_String
# char型であるか判定する正規表現。
#
my $G_is_String = qr{\b char \z}xms;

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
my $G_ws_result = Temp_Content->new(codeType => RESTYPE_CHAR, name => '',
    value => ' ', line => '', val_flg =>'0', component => undef);

#
# variable: G_oprlist_other
# 演算子(=以外)のトークンIDを格納するリスト。
#
my @G_oprlist_other;

#
# variable: G_oprlist_ep
# 演算子(=)のトークンIDを格納するリスト。
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
# 関数名と対応する処理のハッシュ。
#
my %G_method_processer_ref = (
    'strcpy'    => \&process_function_strcpy,
#    'strncpy'   => \&process_function_strncpy,
    'strcat'    => \&process_function_strcat,
#    'strncat'   => \&process_function_strncat,
#    'strpbrk'   => \&process_function_strpbrk,
#    'strrchr'   => \&process_function_strrchr,
#    'strstr'    => \&process_function_strstr,
#    'strtok'    => \&process_function_strtok,
#    'memcpy'    => \&process_function_memcpy,
#    'memmove'   => \&process_function_memmove,
#    'memset'    => \&process_function_memset
);

#
# variable: G_judge_word_recures
# judge_word関数の再帰呼び出し回数をカウントする。デバッグ出力用である。
#
my $G_judge_word_recures = 0;

my $G_current_function_name = '[no name]';

my $G_DeclarationType = 0;

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
    my $file = shift;
    my $self = { };
    ref($file) and $file = ref($file);
    bless($self, $file);
    
    @G_oprlist_other = map {$tokenId{$_}} qw (
        ASSIGN_OPR COR_OPR CAND_OPR OR_OPR NOR_OPR MULTI_OPR EQUALITY_OPR
        RELATIONAL_OPR PREFIX_OPR MINUS_OPR POSTFIX_OPR CLN_TOKEN QUES_TOKEN
        ASSIGN_P_OPR PLUS_OPR
    );
    
    @G_oprlist_ep = map {$tokenId{$_}} qw (EQUAL_OPR);
    
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
# ファイル情報に登録されているすべての関数情報と変数情報について、
# 式解析を実行する。
# 式解析モジュールを実行するためのトリガである。
#
# - 変数情報のリストより変数辞書を生成する。この変数辞書は変数辞書構造の
#   最上位辞書となる。
# - 各関数について、スコープごとの式解析を実行する。
#
# パラメータ:
# fileinfo         - ファイル情報
# result_list       - 式解析結果(関数)のリスト(出力用)
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
    my ($fileinfo, $result_list) = @_;
    
    get_loglevel() > 2 and print_log("(DEBUG 3) | [in] analyze");

    #
    # ファイルの変数情報を解析し、変数辞書を作成する
    # 変数情報を解析した結果を取得する
    #
    my @result_at_scope = ();
    my $var_dic = $self->analyze_variablelist($fileinfo->varlist, \@result_at_scope, undef);

    #
    # すべての関数情報について式解析を実行する
    #
    for my $functioninfo (@{$fileinfo->functionlist()}) {
        $G_current_function_name = (defined $functioninfo->functionname() ? $functioninfo->functionname() : '[no name]');

        #
        # 式解析結果(関数)のオブジェクトを新規に生成する
        #
        my $result_at_function = AnalysisResultsFunction->new();
        $result_at_function->functionname($G_current_function_name);

        #
        # スコープごとの式解析を実行する
        #
        my @result_at_codes = ();
        my @result_at_emb_codes = ();
        my %host_variable = ();
        $self->analyze_scope($functioninfo->rootscope_ref, $var_dic, \@result_at_codes, \@result_at_emb_codes, \%host_variable);
        push(@{ $result_at_function->codelist() }, @result_at_codes);
        push(@{ $result_at_function->embcodelist() }, @result_at_emb_codes);
        foreach my $key ( keys( %host_variable ) ) {
            $result_at_function->host_variable(($key=>''));
        }
        #
        # 関数ごとの式解析結果を式解析結果(ファイル)へ登録する
        #
        
        push(@{$result_list},  $result_at_function);
        $G_current_function_name = '[no name]';
    }

    #
    # 関数ごとの式解析終了後、未参照の変数情報の内容を式解析結果として登録する
    #
    $self->register_analyze_result_at_scope(\@result_at_scope, $var_dic);

    #
    # 変数情報の式解析結果を式解析結果(関数)へ登録する
    #
    my $result_at_variables = AnalysisResultsFunction->new();
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
# parent_var_dic - 親スコープの変数情報
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
    my ($variable_list, $result_list, $parent_var_dic) = @_;

    #
    # 変数辞書の作成
    #
    my $var_dic = $self->create_variable_dic($parent_var_dic);
    
    #
    # 空の一時変数辞書の生成
    # 変数情報はコード上で宣言された順番に処理する必要があるため、リストで
    # 管理する
    # 
    #
    my $temp_var_dic = [];
    
    if(defined $parent_var_dic){
        for my $parent_var_key (keys %{$parent_var_dic->variable_contents_ref()}) {
            my $parent_var=$parent_var_dic->variable_contents_ref->{$parent_var_key};
            $self->register_variable_dic($var_dic, $parent_var->codeType(), $parent_var->name(), 
                    $parent_var->value(), $parent_var->line(), $parent_var->declarationType(), undef, 0, $parent_var->component);
            get_loglevel() > 4
                    and print_log("(DEBUG 5) | variable_list:register_variable_dic:name=".$parent_var->name());
        }
    }
    
    #
    # 変数情報を確認し、データ型が(char) かつ 
    # 値が文字列リテラルのみ場合、変数辞書に変数情報を格納する。
    # (下位のスコープで参照される可能性有)
    # その他は一時変数辞書に格納する。
    # 値の判定を文字リテラルのみから文字リテラルと解析終端の組み合わせに変更
    #
    for my $var_cont (@{$variable_list}) {

        if((int($var_cont->declarationType()) & TYPE_DEFINE)
            or (($var_cont->type() eq RESTYPE_CHAR)
            and defined $var_cont->value()->[0]
            and ($var_cont->value()->[0]->id() == $tokenId{'STRING_LITERAL'})
            and ($var_cont->value()->[1]->id() == $tokenId{'VARDECL_DELIMITER'}))) {

            $self->register_variable_dic($var_dic, $var_cont->type(), $var_cont->name(), 
                $var_cont->value()->[0]->token(), $var_cont->linenumber(), $var_cont->declarationType());
            get_loglevel() > 4
                and print_log("(DEBUG 5) | variable_list:register_variable_dic:name=".$var_cont->name());
        } elsif((int($var_cont->declarationType()) & TYPE_HOST)) {
            $self->register_variable_dic($var_dic, $var_cont->type(), $var_cont->name(), 
                undef, $var_cont->linenumber(), $var_cont->declarationType());
            get_loglevel() > 4
                and print_log("(DEBUG 5) | variable_list:register_variable_dic:name=".$var_cont->name());
        }else {
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
    # 一時変数辞書には式解析が必要な値(関数、変数、複数の文字列等)が
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
        # charの場合は変数辞書に登録する
        #
        if($value->type() eq RESTYPE_CHAR){
            my $one_result = $self->pop_temp_dic(\%temp_dic_ref);
            #
            # 初期化子の解析結果の型がchar以外の場合は空文字で登録する
            #
            if($one_result->codeType() eq RESTYPE_CHAR){
                $self->register_variable_dic($var_dic, $value->type(), 
                                        $value->name(), $one_result->value(), $value->linenumber(), $value->declarationType(), undef, 0, $one_result->component);
            }
            else{
                $self->register_variable_dic($var_dic, $value->type(), 
                                        $value->name(), "", $value->linenumber(), $value->declarationType());
            }
        }
        
        #
        # 初期化子を解析した結果、複数の結果が返却されている場合はその内容を
        # 報告結果として登録する
        # 初期化子に関数定義が存在する場合など
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
# host_variable     - 報告対象ホスト名(出力用)
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
    my ($scopeinfo, $variable_dic_ref, $result_list, $result_emb_list, $host_variable) = @_;
    
    get_loglevel() > 2 and print_log("(DEBUG 3) | [in] analyze_scope");
    #
    # 当該スコープに対する変数辞書を作成する
    #
    my $current_dic = $self->analyze_variablelist($scopeinfo->varlist, $result_list, $variable_dic_ref);

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
                #
                # コード情報が格納されていない場合は次の式情報へ
                #
                if( scalar @$current_expr == 0){
                    next;
                }
                #
                # 先頭が特定コード(EXEC)の場合
                #
                if($current_expr->[0]->id() == $tokenId{'EXEC_TOKEN'}){
                    #埋め込みSQLの式解析結果を登録する
                    $self->judge_word_emb($current_expr, 1, $code->linenumber(), $current_dic, \%temp_dic_ref, $result_list, $result_emb_list, \$host_variable);
                }
                else {
                    $self->judge_word($current_expr, 0, $code->linenumber(), $current_dic, \%temp_dic_ref, $result_list);
                    $self->register_analyze_result_dic($result_list, \%temp_dic_ref, $code->linenumber());              
                }#endif EXEC_TOKEN
            }#end for loop
        }#endif CODETYPE_CODE
        else {
            $self->analyze_scope($code->tokenlist(0), $current_dic, $result_list, $result_emb_list, $host_variable);
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
# - 演算子(=)を検出した場合、演算子(=)の解析処理を実行する。
# - 演算子(=以外)を検出した場合、演算子(その他)の解析処理を実行する。
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
        # 特定コード(=)以外の演算子の場合
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
            # 関数宣言中、計算中、変数宣言の解析中は式解析結果へ登録せずに
            # 呼び出し元へ制御を戻す
            #
            if($self->refer_temp_status($temp_dic_ref, 'FunctionDec')
                or $self->refer_temp_status($temp_dic_ref, 'CalDec')){

                if($current_token->id() == $tokenId{'RP_TOKEN'}
                    or $current_token->id() == $tokenId{'SMC_TOKEN'}){
                    get_loglevel() > 4 and print_log("(DEBUG 5) | judge_word TOKEN_END=".$current_token->token);
                    get_loglevel() > 2 and do{ print_log("(DEBUG 3) | [out] judge_word(FunctionDec1) [". $G_judge_word_recures . "]"); $G_judge_word_recures-- ; };
                }

            }
            elsif($self->refer_temp_status($temp_dic_ref, 'VarDec')){
                get_loglevel() > 4 and print_log("(DEBUG 5) | judge_word TOKEN_END=".$current_token->token);
                get_loglevel() > 2 and do{ print_log("(DEBUG 3) | [out] judge_word(refer_temp_status) [". $G_judge_word_recures . "]"); $G_judge_word_recures-- ; };
            }
            #
            # 関数宣言中、計算中、変数宣言以外で解析終端を検出した場合は
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
            $self->register_temp_dic($temp_dic_ref, RESTYPE_CHAR, 
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
        # 識別子の場合
        #
        elsif($current_token->id() == $tokenId{'IDENTIFIER_ORG'} 
            or $current_token->id() == $tokenId{'EXEC_TOKEN'}
            or $current_token->id() == $tokenId{'SQL_TOKEN'}
            or $current_token->id() == $tokenId{'ORACLE_TOKEN'}
            or $current_token->id() == $tokenId{'TOOLS_TOKEN'}
            or $current_token->id() == $tokenId{'BEGIN_TOKEN'}
            or $current_token->id() == $tokenId{'END_TOKEN'}
            or $current_token->id() == $tokenId{'DECLARE_TOKEN'}
            or $current_token->id() == $tokenId{'SECTION_TOKEN'}
            or $current_token->id() == $tokenId{'CHAR_TOKEN'}){
            ++$point;
            $point = $self->judge_next_word($code_info_ref, $point, $line, $variable_dic_ref, 
                     $temp_dic_ref, $analyze_result_list);
            $is_result++;
        }
        #
        # 変数情報から変数辞書作成時に変数情報の変数終端を検出した場合
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
# - 次のトークンが開き括弧(()の場合、関数呼び出しと判断し、関数呼び出し
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
    # 関数呼び出しの場合
    #
    elsif($current_token->id() == $tokenId{'LP_TOKEN'}){

        # ファイル名のドット解析中であるフラグを解除する
        $self->register_temp_status($temp_dic_ref, 'DotDec', 0);
        
        $next_point = $self->process_ident_parenthesis($code_info_ref, $point, $line,
                      $variable_dic_ref, $temp_dic_ref, $analyze_result_list);
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
    elsif($current_token->id() == $tokenId{'IDENTIFIER_ORG'} 
        or $current_token->id() == $tokenId{'EXEC_TOKEN'}
        or $current_token->id() == $tokenId{'SQL_TOKEN'}
        or $current_token->id() == $tokenId{'ORACLE_TOKEN'}
        or $current_token->id() == $tokenId{'TOOLS_TOKEN'}
        or $current_token->id() == $tokenId{'BEGIN_TOKEN'}
        or $current_token->id() == $tokenId{'END_TOKEN'}
        or $current_token->id() == $tokenId{'DECLARE_TOKEN'}
        or $current_token->id() == $tokenId{'SECTION_TOKEN'}){
        # ファイル名のドット解析中であるフラグを解除する
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

        # ファイル名のドット解析中であるフラグを解除する
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
# 関数ごとの解析処理である。「識別子 (」の並びについて解析を行う。
# 識別子の内容を判別して、対応する関数解析処理を実行する。識別子の内容が
# 下記の場合、対応する処理を行う。
# - strcpyの場合、strcpy関数解析処理を実行する。
# - strcatの場合、strcat関数解析処理を実行する。
# - 上記以外の場合、その他関数解析処理を実行する。
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
# - 解析開始位置は、関数呼び出しの開始括弧である。
# - 次の解析位置は、関数呼び出しの終了括弧の次のトークンである。
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
    # 識別子(1つ目のトークン)によってどの関数かを判断する
    #
    my $past_token = $$code_info_ref[$point - 1];
    
    #
    # strcpy関数の場合
    # strcat関数の場合
    #
    if(my $process = $G_method_processer_ref{$past_token->token()}) {
        $next_point = $process->($self, $code_info_ref, $point + 1, $line, $variable_dic_ref, 
                                 $temp_dic_ref, $analyze_result_list);
    }
    #
    # その他の関数の場合
    #
    else {
        $next_point = $self->process_function_the_others($code_info_ref, $point + 1,
                      $line, $variable_dic_ref, $temp_dic_ref, $analyze_result_list);
    }

    get_loglevel() > 4 and print_log("(DEBUG 5) | next_point =" . $next_point);
    get_loglevel() > 2 and print_log("(DEBUG 3) | [out] process_ident_parenthesis");
    return $next_point;
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
    # ファイル名のドット解析中は何もしない
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
        #     String b = OtherClass.unrefvalue;  <-- 他ファイルの変数のケースなど
        # 変数宣言中の場合、その識別子を変数辞書へ登録する
        #     String a, b;  <-- a, または b; に相当するケース
        # 変数宣言中でない場合、解析結果なしを登録する
        #     int x = i;    <-- i; (iはint変数)に相当するケース
        #
        } else {
            if($self->refer_temp_status($temp_dic_ref, 'CalDec')) {
                $self->register_temp_nodata($temp_dic_ref);
            } elsif(my $type = $self->refer_temp_status($temp_dic_ref, 'VarDec')) {
                $self->register_variable_dic($variable_dic_ref, $type, $past_token->token(), '', $line, $G_DeclarationType);
                $self->register_temp_dic($temp_dic_ref, $type, $past_token->token(), '', $line);
            } else {
                $self->register_temp_nodata($temp_dic_ref);
            } 
        }
    }
    
    # ファイル名のドット解析中であるフラグを解除する
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
# - 変数辞書への登録は、型がcharの場合に行われる。
# - 一時辞書への登録は、型がcharの場合に行われる。
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
    # 型名がcharの場合
    #
    if($past_token->token() eq RESTYPE_CHAR){
        
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
        $self->register_variable_dic($variable_dic_ref, $past_token->token(), $current_token->token(), '', $line, $G_DeclarationType);
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
    my ($code_info_ref, $point, $line, $variable_dic_ref, $temp_dic_ref, $type) = @_;
    
    my $isNotEvaluate = 1;               # 演算不可能な場合、真となる
    
    get_loglevel() > 2 and print_log("(DEBUG 3) | [in] process_equal");
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
    if(!defined $lefttype or $lefttype !~ $G_is_String) {
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
    
    if(!defined $right_type or $right_type !~ $G_is_String) {
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

        # 空白文字としたため、typeを変更
        $right_type=$right_value->codeType();
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
        get_loglevel() > 2 and print_log("(DEBUG 3) | [out] process_equal(isNotEvaluate)");
        return $next_point;
    }
    #
    # 右辺の式解析結果を左辺に代入する(一時辞書、変数辞書へ登録)
    # ただし、右辺または左辺が式解析結果なしだった場合は、本処理は行われない
    # (int a = 1; といった代入は処理しない)
    # 左辺が解析結果なしのケースは、左右辺が解析結果なしとなるケースしか発生しない
    #
    if($lefttype =~ $G_is_String) {
       if(defined $right_type and $right_type ne RESTYPE_OTHER) {
          $self->register_variable_dic($variable_dic_ref, 
               $lefttype, $leftvalue->name(), $right_value->value(), $line, undef,
               undef, 0, $right_value->component);
       }
          $self->register_temp_dic($temp_dic_ref,
              $lefttype, $leftvalue->name(), $right_value->value(), $line, undef, 
              $right_value->component);
    }
    else {
        $self->register_object_to_temp_dic($temp_dic_ref, $right_value);
    }

    get_loglevel() > 4 and print_log("(DEBUG 5) | next_point =" . $next_point);
    get_loglevel() > 2 and print_log("(DEBUG 3) | [out] process_equal");
    return $next_point;
}

#####################################################################
# Function: process_sign_the_others
#
#
# 概要:
# 演算子(その他)の解析処理の解析処理である。演算子(=)以外の
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
# Function: process_function_the_others
#
#
# 概要:
# その他関数解析処理である。
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
# - 解析開始位置は、関数開始括弧の次のトークンである。
# - 次の解析位置は、関数終了括弧の次のトークンである。
# - 一時辞書への登録は、パラメータより文字列リテラルが取得できた場合、行われる。
# - 変数辞書への登録は行われない。
#
#####################################################################
sub process_function_the_others {
    my $self = shift;
    my ($code_info_ref, $point, $line, $variable_ref, $temp_dic_ref, $result_ref) = @_;
    
    get_loglevel() > 2 and print_log("(DEBUG 3) | [in] process_function_the_others");
    my $next_point = $point;
    my $current_token = $code_info_ref->[$point];
    
    #
    # その他の関数の場合、変数情報に対して作用することはないため、当該
    # 関数を実行するために参照しているオブジェクトについて、参照前の
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
    
    # 関数宣言中であるフラグを立てる
    $self->register_temp_status($temp_dic_ref, 'FunctionDec', ++($temp_dic_ref->{status}->{"FunctionDec"}));

    # )まで式解析を実行
    while($current_token->id() != $tokenId{'RP_TOKEN'}) {
        $next_point = $self->judge_word($code_info_ref, $next_point, $line, $variable_ref, 
                                 $temp_dic_ref, $result_ref);
        
        #
        # パラメータの解析結果がcharの場合、その内容を
        # 評価対象として一時辞書に登録する(実際の登録処理は、judge_word内で実施済みである)
        #
        my $parameter_value = $self->refer_temp_dic($temp_dic_ref);
        if(defined $parameter_value and defined  $parameter_value->codeType and $parameter_value->codeType =~ $G_is_String) {
            $parameter_value->val_flg(1);
        }

        #
        # 現在のトークンがパラメータ区切り(,)である場合は次のトークンを取得する
        #
        $code_info_ref->[$next_point]->id() == $tokenId{'CM_TOKEN'} and $next_point++;
        $current_token = $code_info_ref->[$next_point];
    }
    
    # 関数が終了したのでフラグを戻す
    $self->register_temp_status($temp_dic_ref, 'FunctionDec', --($temp_dic_ref->{status}->{"FunctionDec"}));

    # 関数の式解析結果として空白文字を登録する
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

    get_loglevel() > 2 and print_log("(DEBUG 3) | [out] process_function_the_others");
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
            my $targstr = $G_current_function_name . ':' . $one_result->name() . ":" . $line;
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
    		if($G_current_function_name eq '[no name]') {
    			$targstr = '[function variable]';
    		} else {
    			$targstr = $G_current_function_name;
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
# declarationType   - 宣言種別
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
    my ($variable_dic_ref, $codeType, $name, $value, $line, $declarationType, $ref_flg, $copy, $component, $appended, $append_component) = @_;
    my @componet_buff = ();
    
    get_loglevel() > 2 and print_log("(DEBUG 3) | [in] register_variable_dic");

    my $varinfo = $self->refer_variable_dic($variable_dic_ref, $name, 1);
    
    if(!defined $varinfo) {
        $varinfo = VariableContent->new(codeType => $codeType, name => $name);
        $variable_dic_ref->variable_contents_ref->{$name} = $varinfo;
    }
    
    if(!defined $value) {
        $value="";
    }
    
    $varinfo->value($value);
    $varinfo->line($line);
    $varinfo->prev_ref_flg($varinfo->ref_flg());
    $varinfo->ref_flg($ref_flg);
    $varinfo->copy($copy);
    defined $declarationType and $varinfo->declarationType($declarationType);
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
    get_loglevel() > 4 and do {
        if(defined $codetype) {
            print_log("(DEBUG 5) | codeType=(".$codetype.")");
        } else {
            print_log("(DEBUG 5) | codeType=(undef)"); 
        }
    };
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

#####################################################################
# Function: judge_word_emb
#
#
# 概要:
# 式解析の主制御である。
# コード情報よりトークンを1つ読み出し、特定コードの判別を行う。下記の特定コード
# を検出した場合、それぞれの処理を行う。
# - 「SQL」を検出した場合、評価対象として埋め込みSQL用一時辞書へ登録する。
# - 「PREPARE」を検出後、ホスト変数を検出した場合、
#   ホスト変数の内容を評価対象として文字リテラル用一時辞書へ登録する。
# - 「EXECUTE」「IMMEDIATE」を検出後、ホスト変数を検出した場合、
#   ホスト変数の内容を評価対象として文字リテラル用一時辞書へ登録する。
#
# パラメータ:
# code_info_ref         - コード情報のリストのリファレンス
# point                 - 解析の開始位置
# line                  - コードが記述された行番号
# variable_dic_ref      - 変数辞書のリファレンス
# temp_dic_ref          - 一時辞書のリファレンス
# analyze_result_list   - 式解析結果(コード)のリスト(出力用)のリファレンス
# host_variable         - 報告対象ホスト名(出力用)
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
sub judge_word_emb {
    my $self = shift;
    my ($code_info_ref, $point, $line, $variable_dic_ref, $temp_dic_ref, $analyze_result_list, $analyze_result_list_emb, $host_variable) = @_;
    
    get_loglevel() > 2 and print_log("(DEBUG 3) | [in] judge_word_emb line = " . $line);
    my $enf_of_token = scalar @{$code_info_ref}; #トークンの終端位置
    get_loglevel() > 4 and print_log("(DEBUG 5) | token_end=".$enf_of_token);

    #
    # 特定コード(SQL)の場合
    #
    if($code_info_ref->[$point]->id() == $tokenId{'SQL_TOKEN'}){
        ++$point;
        if($code_info_ref->[$point]->id() == $tokenId{'BEGIN_TOKEN'}
            and $code_info_ref->[$point+1]->id() == $tokenId{'DECLARE_TOKEN'}
            and $code_info_ref->[$point+2]->id() == $tokenId{'SECTION_TOKEN'}){
            $G_DeclarationType = int($G_DeclarationType) | TYPE_HOST;
        }

        if($code_info_ref->[$point]->id() == $tokenId{'END_TOKEN'}
            and $code_info_ref->[$point+1]->id() == $tokenId{'DECLARE_TOKEN'}
            and $code_info_ref->[$point+2]->id() == $tokenId{'SECTION_TOKEN'}){
            $G_DeclarationType = int($G_DeclarationType) & ~TYPE_HOST;
        }

        # ターゲットはundefを設定すると未初期化のエラーが出力されたため、空白を設定
        my $target = "";
        my %host_name_list=();
        for( my $i = $point ; $i < $enf_of_token ; $i++){
            $target =  $target . ' ' . $code_info_ref->[$i]->token();
            # ホスト変数を検出した場合は別途格納
            if($code_info_ref->[$i]->id() == $tokenId{'CLN_TOKEN'}){
                $i++;
                $host_name_list{$code_info_ref->[$i]->token()}="";
                $target =  $target . $code_info_ref->[$i]->token();
            }#endif $tokenId{'CLN_TOKEN'}
            
        }
        # 「SQL」以降を一時辞書へ登録
        $self->register_temp_dic($temp_dic_ref, RESTYPE_CHAR, 
                          undef, $target, $line, 1);
        $self->register_analyze_result_dic($analyze_result_list_emb, $temp_dic_ref, $line);             

        my $chaser_pattern = get_chaserpattern();

        foreach my $host_name (keys %host_name_list){
            if(!exists $variable_dic_ref->variable_contents_ref->{$host_name} ){
                $$host_variable->{$host_name . ':' . $line}="";
                next;
            }            
            my $value = $variable_dic_ref->variable_contents_ref->{$host_name};
            if(defined $value and !(int($value->declarationType()) & TYPE_HOST) ) {
                $$host_variable->{$value->name() . ':' . $value->line()}="";
            }
            if($target =~ m{$chaser_pattern}xms) {
                get_loglevel() > 4 and print_log("(DEBUG 5) | chaserpattern =".$chaser_pattern);

                if(defined $value and defined $value->value() and $value->value() !~ m{^\s*$}xms and !($value->ref_flg())) {       
            		my $targstr = "";
          			$targstr = $G_current_function_name;
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
            }#endif chaser_pattern
        }
    }#endif $tokenId{'SQL_TOKEN'}
    
    get_loglevel() > 2 and print_log("(DEBUG 3) | [out] judge_word_emb");
}

#####################################################################
# Function: process_function_strcpy
#
#
# 概要:
# strcpy関数解析処理である。
# 
# 
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
# - 解析開始位置は、関数開始括弧の次のトークンである。
# - 次の解析位置は、関数終了括弧の次のトークンである。
# - 一時辞書への登録は、
# - 変数辞書への登録は
#
#####################################################################
sub process_function_strcpy {
    my $self = shift;
    my ($code_info_ref, $point, $line, $variable_ref, $temp_dic_ref, $result_ref) = @_;
    
    get_loglevel() > 2 and print_log("(DEBUG 3) | [in] process_function_strcpy");
    my $next_point=$point;
    my $size=undef;
    # 第一引数が変数名のみか判定、変数名のみの場合は文字列操作を実施
    if($code_info_ref->[$point]->id() == $tokenId{'IDENTIFIER_ORG'} 
        or $code_info_ref->[$point]->id() == $tokenId{'EXEC_TOKEN'}
        or $code_info_ref->[$point]->id() == $tokenId{'SQL_TOKEN'}
        or $code_info_ref->[$point]->id() == $tokenId{'ORACLE_TOKEN'}
        or $code_info_ref->[$point]->id() == $tokenId{'TOOLS_TOKEN'}
        or $code_info_ref->[$point]->id() == $tokenId{'BEGIN_TOKEN'}
        or $code_info_ref->[$point]->id() == $tokenId{'END_TOKEN'}
        or $code_info_ref->[$point]->id() == $tokenId{'DECLARE_TOKEN'}
        or $code_info_ref->[$point]->id() == $tokenId{'SECTION_TOKEN'}){
        if( $code_info_ref->[$point+1]->id() == $tokenId{'CM_TOKEN'}){
            my $variable_name = $code_info_ref->[$point]->token();
            $next_point=$self->analyze_function_argument($code_info_ref, $point, $line, $variable_ref, $temp_dic_ref, $result_ref, \$size);
            my $result = $self->pop_temp_dic($temp_dic_ref);
            
            if(defined $result){
                $self->register_variable_dic($variable_ref, 
                   $result->codeType(), $variable_name, $result->value(), $line, undef, undef, 0, 
                   $result->component());
                $self->register_temp_dic($temp_dic_ref,
                   $result->codeType(), undef, $result->value(), $line, undef, 
                   $result->component());
            }
            # 第一引数が変数名の場合の終了
            get_loglevel() > 2 and print_log("(DEBUG 3) | [out] process_function_strcpy");
            return ++$next_point;
        }
    }
    # 第一引数が変数名のみでない場合も、最後まで解析をすすめる
    $next_point=$self->analyze_function_argument($code_info_ref, $point, $line, $variable_ref, $temp_dic_ref, $result_ref, \$size);
    get_loglevel() > 2 and print_log("(DEBUG 3) | [out] process_function_strcpy");
    return ++$next_point;
}

#####################################################################
# Function: process_function_strncpy
#
#
# 概要:
# strncpy関数解析処理である。(現状では呼び出されない)
# 
# 
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
# - 解析開始位置は、関数開始括弧の次のトークンである。
# - 次の解析位置は、関数終了括弧の次のトークンである。
# - 一時辞書への登録は、
# - 変数辞書への登録は
#
#####################################################################
sub process_function_strncpy {
    my $self = shift;
    return $self->process_function_strncpy_core(@_);
}

#####################################################################
# Function: process_function_strcat
#
#
# 概要:
# strcat関数解析処理である。
# 
# 
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
# - 解析開始位置は、関数開始括弧の次のトークンである。
# - 次の解析位置は、関数終了括弧の次のトークンである。
# - 一時辞書への登録は、
# - 変数辞書への登録は
#
#####################################################################
sub process_function_strcat {
    my $self = shift;
    my ($code_info_ref, $point, $line, $variable_ref, $temp_dic_ref, $result_ref) = @_;
    
    get_loglevel() > 2 and print_log("(DEBUG 3) | [in] process_function_strcat");
    my $next_point=$point;
    my $size=undef;
    # 第一引数が変数名のみか判定、変数名のみの場合は文字列操作を実施
    if($code_info_ref->[$point]->id() == $tokenId{'IDENTIFIER_ORG'} 
        or $code_info_ref->[$point]->id() == $tokenId{'EXEC_TOKEN'}
        or $code_info_ref->[$point]->id() == $tokenId{'SQL_TOKEN'}
        or $code_info_ref->[$point]->id() == $tokenId{'ORACLE_TOKEN'}
        or $code_info_ref->[$point]->id() == $tokenId{'TOOLS_TOKEN'}
        or $code_info_ref->[$point]->id() == $tokenId{'BEGIN_TOKEN'}
        or $code_info_ref->[$point]->id() == $tokenId{'END_TOKEN'}
        or $code_info_ref->[$point]->id() == $tokenId{'DECLARE_TOKEN'}
        or $code_info_ref->[$point]->id() == $tokenId{'SECTION_TOKEN'}){
        if( $code_info_ref->[$point+1]->id() == $tokenId{'CM_TOKEN'}){
            my $variable_name = $code_info_ref->[$point]->token();
            $next_point=$self->analyze_function_argument($code_info_ref, $point, $line, $variable_ref, $temp_dic_ref, $result_ref, \$size);
            my $result = $self->pop_temp_dic($temp_dic_ref);

            my $varinfo = $self->refer_variable_dic($variable_ref, $variable_name, 1);
            
            if(defined $varinfo){
                $self->register_variable_dic($variable_ref, 
                   $result->codeType(), $variable_name, $varinfo->value().$result->value(), $line, undef, undef, 0, 
                   $varinfo->component(), $result->value(), $result->component());
                $self->register_temp_dic($temp_dic_ref,
                   $result->codeType(), undef, $varinfo->value(), $line, undef, 
                   $varinfo->component());
            }
            # 第一引数が変数名の場合の終了
            get_loglevel() > 2 and print_log("(DEBUG 3) | [out] process_function_strcat");
            return ++$next_point;
        }
    }
    # 第一引数が変数名のみでない場合も、最後まで解析をすすめる
    $next_point=$self->analyze_function_argument($code_info_ref, $point, $line, $variable_ref, $temp_dic_ref, $result_ref, \$size);
    get_loglevel() > 2 and print_log("(DEBUG 3) | [out] process_function_strcat");
    return ++$next_point;
}

#####################################################################
# Function: process_function_strncat
#
#
# 概要:
# strncat関数解析処理である。(現状では呼び出されない)
# 
# 
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
# - 解析開始位置は、関数開始括弧の次のトークンである。
# - 次の解析位置は、関数終了括弧の次のトークンである。
# - 一時辞書への登録は、
# - 変数辞書への登録は
#
#####################################################################
sub process_function_strncat {
    my $self = shift;
    my ($code_info_ref, $point, $line, $variable_ref, $temp_dic_ref, $result_ref) = @_;
    
    get_loglevel() > 2 and print_log("(DEBUG 3) | [in] process_function_strncat");
    my $next_point = $point;
    my $current_token = $code_info_ref->[$point];
    
    # )まで式解析を実行
    while($current_token->id() != $tokenId{'RP_TOKEN'}) {
        $code_info_ref->[$next_point]->id() == $tokenId{'CM_TOKEN'} and $next_point++;
        $current_token = $code_info_ref->[$next_point];
    }
    
    get_loglevel() > 2 and print_log("(DEBUG 3) | [out] process_function_strncat");
    return ++$next_point;
}

#####################################################################
# Function: process_function_strpbrk
#
#
# 概要:
# strpbrk関数解析処理である。(現状では呼び出されない)
# 
# 
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
# - 解析開始位置は、関数開始括弧の次のトークンである。
# - 次の解析位置は、関数終了括弧の次のトークンである。
# - 一時辞書への登録は、
# - 変数辞書への登録は
#
#####################################################################
sub process_function_strpbrk {
    my $self = shift;
    my ($code_info_ref, $point, $line, $variable_ref, $temp_dic_ref, $result_ref) = @_;
    
    get_loglevel() > 2 and print_log("(DEBUG 3) | [in] process_function_strpbrk");
    my $next_point = $point;
    my $current_token = $code_info_ref->[$point];
    
    # )まで式解析を実行
    while($current_token->id() != $tokenId{'RP_TOKEN'}) {
        $code_info_ref->[$next_point]->id() == $tokenId{'CM_TOKEN'} and $next_point++;
        $current_token = $code_info_ref->[$next_point];
    }
    
    get_loglevel() > 2 and print_log("(DEBUG 3) | [out] process_function_strpbrk");
    return ++$next_point;
}

#####################################################################
# Function: process_function_strrchr
#
#
# 概要:
# strrchr関数解析処理である。(現状では呼び出されない)
# 
# 
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
# - 解析開始位置は、関数開始括弧の次のトークンである。
# - 次の解析位置は、関数終了括弧の次のトークンである。
# - 一時辞書への登録は、
# - 変数辞書への登録は
#
#####################################################################
sub process_function_strrchr {
    my $self = shift;
    my ($code_info_ref, $point, $line, $variable_ref, $temp_dic_ref, $result_ref) = @_;
    
    get_loglevel() > 2 and print_log("(DEBUG 3) | [in] process_function_strrchr");
    my $next_point = $point;
    my $current_token = $code_info_ref->[$point];
    
    # )まで式解析を実行
    while($current_token->id() != $tokenId{'RP_TOKEN'}) {
        $code_info_ref->[$next_point]->id() == $tokenId{'CM_TOKEN'} and $next_point++;
        $current_token = $code_info_ref->[$next_point];
    }
    
    get_loglevel() > 2 and print_log("(DEBUG 3) | [out] process_function_strrchr");
    return ++$next_point;
}

#####################################################################
# Function: process_function_strstr
#
#
# 概要:
# strstr関数解析処理である。(現状では呼び出されない)
# 
# 
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
# - 解析開始位置は、関数開始括弧の次のトークンである。
# - 次の解析位置は、関数終了括弧の次のトークンである。
# - 一時辞書への登録は、
# - 変数辞書への登録は
#
#####################################################################
sub process_function_strstr {
    my $self = shift;
    my ($code_info_ref, $point, $line, $variable_ref, $temp_dic_ref, $result_ref) = @_;
    
    get_loglevel() > 2 and print_log("(DEBUG 3) | [in] process_function_strstr");
    my $next_point = $point;
    my $current_token = $code_info_ref->[$point];
    
    # )まで式解析を実行
    while($current_token->id() != $tokenId{'RP_TOKEN'}) {
        $code_info_ref->[$next_point]->id() == $tokenId{'CM_TOKEN'} and $next_point++;
        $current_token = $code_info_ref->[$next_point];
    }
    
    get_loglevel() > 2 and print_log("(DEBUG 3) | [out] process_function_strstr");
    return ++$next_point;
}

#####################################################################
# Function: process_function_strtok
#
#
# 概要:
# strtok関数解析処理である。(現状では呼び出されない)
# 
# 
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
# - 解析開始位置は、関数開始括弧の次のトークンである。
# - 次の解析位置は、関数終了括弧の次のトークンである。
# - 一時辞書への登録は、
# - 変数辞書への登録は
#
#####################################################################
sub process_function_strtok {
    my $self = shift;
    my ($code_info_ref, $point, $line, $variable_ref, $temp_dic_ref, $result_ref) = @_;
    
    get_loglevel() > 2 and print_log("(DEBUG 3) | [in] process_function_strtok");
    my $next_point = $point;
    my $current_token = $code_info_ref->[$point];
    
    # )まで式解析を実行
    while($current_token->id() != $tokenId{'RP_TOKEN'}) {
        $code_info_ref->[$next_point]->id() == $tokenId{'CM_TOKEN'} and $next_point++;
        $current_token = $code_info_ref->[$next_point];
    }
    
    get_loglevel() > 2 and print_log("(DEBUG 3) | [out] process_function_strtok");
    return ++$next_point;
}

#####################################################################
# Function: process_function_memcpy
#
#
# 概要:
# memcpy関数解析処理である。(現状では呼び出されない)
# 
# 
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
# - 解析開始位置は、関数開始括弧の次のトークンである。
# - 次の解析位置は、関数終了括弧の次のトークンである。
# - 一時辞書への登録は、
# - 変数辞書への登録は
#
#####################################################################
sub process_function_memcpy {
    my $self = shift;
    return $self->process_function_strncpy_core(@_);
}

#####################################################################
# Function: process_function_memmove
#
#
# 概要:
# memmove関数解析処理である。(現状では呼び出されない)
# 
# 
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
# - 解析開始位置は、関数開始括弧の次のトークンである。
# - 次の解析位置は、関数終了括弧の次のトークンである。
# - 一時辞書への登録は、
# - 変数辞書への登録は
#
#####################################################################
sub process_function_memmove {
    my $self = shift;
    return $self->process_function_strncpy_core(@_);
}

#####################################################################
# Function: process_function_memset
#
#
# 概要:
# memset関数解析処理である。(現状では呼び出されない)
# 
# 
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
# - 解析開始位置は、関数開始括弧の次のトークンである。
# - 次の解析位置は、関数終了括弧の次のトークンである。
# - 一時辞書への登録は、
# - 変数辞書への登録は
#
#####################################################################
sub process_function_memset {
    my $self = shift;
    my ($code_info_ref, $point, $line, $variable_ref, $temp_dic_ref, $result_ref) = @_;
    
    get_loglevel() > 2 and print_log("(DEBUG 3) | [in] process_function_memset");
    my $next_point = $point;
    my $current_token = $code_info_ref->[$point];
    
    # )まで式解析を実行
    while($current_token->id() != $tokenId{'RP_TOKEN'}) {
        $code_info_ref->[$next_point]->id() == $tokenId{'CM_TOKEN'} and $next_point++;
        $current_token = $code_info_ref->[$next_point];
    }
    
    get_loglevel() > 2 and print_log("(DEBUG 3) | [out] process_function_memset");
    return ++$next_point;
}

#####################################################################
# Function: process_function_strncpy_core
#
#
# 概要:
# strncpy,memcpy,memmove関数の共通処理である。
# 
# 
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
# - 解析開始位置は、関数開始括弧の次のトークンである。
# - 次の解析位置は、関数終了括弧の次のトークンである。
# - 一時辞書への登録は、
# - 変数辞書への登録は
#
#####################################################################
sub process_function_strncpy_core {
    my $self = shift;
    my ($code_info_ref, $point, $line, $variable_ref, $temp_dic_ref, $result_ref) = @_;
    
    get_loglevel() > 2 and print_log("(DEBUG 3) | [in] process_function_strncpy_core");
    my $variable_name = $code_info_ref->[$point]->token();
    my $size=undef;
    my $next_point=$self->analyze_function_argument($code_info_ref, $point, $line, $variable_ref, $temp_dic_ref, $result_ref, \$size);
    my $result = $self->pop_temp_dic($temp_dic_ref);
    my $componet_buff=$self->analyze_component($result, $size);

    $self->register_variable_dic($variable_ref, 
       $result->codeType(), $variable_name, substr($result->value(),0,$size), $line, undef, undef, 0, 
       $componet_buff);
    $self->register_temp_dic($temp_dic_ref,
       $result->codeType(), undef, substr($result->value(),0,$size), $line, undef, 
       $componet_buff);
    get_loglevel() > 2 and print_log("(DEBUG 3) | [out] process_function_strncpy_core");
    return ++$next_point;
}

#####################################################################
# Function: analyze_function_argument
#
#
# 概要:
# 文字列操作関数の引数解析処理である。
#
# パラメータ:
# code_info_ref     - コード情報のリストのリファレンス
# point             - 解析の開始位置
# line              - コードが記述された行番号
# variable_ref      - 変数辞書のリファレンス
# temp_dic_ref      - 一時辞書のリファレンス(第2引数の解析結果の出力用)
# result_ref        - 解析結果(コード)のリストのリファレンス
# size        - 操作文字数(出力用)
#
# 戻り値:
# next_point        - 次の解析位置
#
# 特記事項:
# - 解析開始位置は、関数開始括弧の次のトークンである。
# - 一時辞書への登録は、第2引数の解析結果を格納
#
#####################################################################
sub analyze_function_argument {
    my $self = shift;
    my ($code_info_ref, $point, $line, $variable_ref, $temp_dic_ref, $result_ref, $size) = @_;
    
    get_loglevel() > 2 and print_log("(DEBUG 3) | [in] analyze_function_argument");
    my $next_point = $point;
    my $current_token = $code_info_ref->[$point];
    
    my $arg_flg = 0;#第2引数と第3引数の判定用フラグ
    
    # )まで式解析を実行
    while($current_token->id() != $tokenId{'RP_TOKEN'}) {
        if( $code_info_ref->[$next_point]->id() == $tokenId{'CM_TOKEN'} ){
            if($arg_flg == 0){
                # 関数宣言中であるフラグを立てる
                $self->register_temp_status($temp_dic_ref, 'FunctionDec', ++($temp_dic_ref->{status}->{"FunctionDec"}));
                $next_point++;
                $next_point = $self->judge_word($code_info_ref, $next_point, $line, $variable_ref, $temp_dic_ref, $result_ref);
                $arg_flg = 1;#第2引数判定済みのフラグを真
                # フラグを戻す
                $self->register_temp_status($temp_dic_ref, 'FunctionDec', --($temp_dic_ref->{status}->{"FunctionDec"}));
            }elsif($arg_flg == 1){
                $next_point++;
                # 第3引数が整数か判定、整数の場合は操作文字数として変数に格納
                if( $code_info_ref->[$next_point]->id() == $tokenId{'INTEGER_LITERAL'}
                    and $code_info_ref->[$next_point+1]->id() == $tokenId{'RP_TOKEN'}){
                        # 第3引数を出力用の引数にデリファレンスして格納
                        $$size = $code_info_ref->[$next_point]->token();
                }
            }#endif $arg_flg == 0
        }else{
            $next_point++;
        }#endif $code_info_ref->[$next_point]->id() == $tokenId{'CM_TOKEN'}
        $current_token = $code_info_ref->[$next_point];
    }#while loop end

    get_loglevel() > 2 and print_log("(DEBUG 3) | [out] analyze_function_argument");
    return $next_point;
}

#####################################################################
# Function: analyze_component
#
#
# 概要:
# 操作文字数に合わせて文字列位置情報を修正する。
#
# パラメータ:
# temp_dic_ref      - 一時辞書のリファレンス
# size        - 操作文字数
#
# 戻り値:
# componet_buff        - 文字列位置情報
#
# 特記事項:
#
#####################################################################
sub analyze_component {
    my $self = shift;
    my ($result, $size) = @_;
    
    my @componet_buff=();
    get_loglevel() > 2 and print_log("(DEBUG 3) | [in] analyze_component");
    
    foreach my $detail ( @{ $result->component() } ){
        if(!defined $size or $detail->length <= $size){
            $size = $size - $detail->length;
            push(@componet_buff,$detail);
        } else{        
            push(@componet_buff,VariableComponent->new(
            line => $detail->line, length => $size , code_count => $detail->code_count, block_count => $detail->block_count));
            last;
        }#endif $detail->length < $pos_buff
    }#foreach loop end

    get_loglevel() > 2 and print_log("(DEBUG 3) | [out] analyze_component");
    return \@componet_buff;
}

1;
