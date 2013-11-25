#!/bin/sh

if [ $# -eq 1 -a -f "$1" ]; then
  source "$1";
else
  echo "$0 <controlfile_path>" >&2;
  exit 1;
fi

CUR=`dirname $0`;
cd $CUR;

OUTDIR="../output/$OUTPUT_DIR_NAME";
TMPDIR="../tmp/$OUTPUT_DIR_NAME";
if [ -e "$OUTDIR" ]; then
  echo "output directory is already exist.($OUTDIR)" >&2;
  exit 1;
fi
if [ -e "$TMPDIR" ]; then
  echo "tmp directory is already exist.($TMPDIR)" >&2;
  exit 1;
fi
mkdir -p "$OUTDIR";
mkdir -p "$TMPDIR";
STYLEDIR="../stylesheet"

#echo $STDERR_OUTPUT_FLAG
# 1. execute db_syntax_diff
#    > $TMPDIR/tmp.xml

# オプションを変数化する
option="-e ${TARGET_CHAR} -i ${TARGET_PATH},${TARGET_EXT} -o ${TMPDIR}/tmp.xml -m ${TARGET_MODE}"

# ヘッダファイルの存在箇所が設定されていれば-Iオプションを追加する
if [ -n "${INCLUDE_DIRECTORY_NAME}" ]; then
   option="${option} -I ${INCLUDE_DIRECTORY_NAME}"
fi

# ログの出力の仕方により、-vオプションの内容を変更する
if [ "${STDERR_OUTPUT_FLAG}" = "both" ]; then
   option="${option} -v 1 2>&1 | tee ${OUTDIR}/${STDERR_FILE_NAME}"
elif [ "${STDERR_OUTPUT_FLAG}" = "screen" ]; then
   option="${option} -v"
elif [ "${STDERR_OUTPUT_FLAG}" = "file" ]; then
   option="${option} -v 1 2> ${OUTDIR}/${STDERR_FILE_NAME}"
fi


#-----------------
# ツール実行処理
#-----------------

eval "db_syntax_diff.pl ${option}";


# 実行結果のエラー判定
if [ $? -ne 0 ]; then
  echo "db_syntax_diff.pl error." >&2;
  exit 1;
fi


# 2. multibyte_space
#    > $TMPDIR/multibyte_space.xml
java org.apache.xalan.xslt.Process -in "${TMPDIR}/tmp.xml" -xsl ${STYLEDIR}/erase_multibyte_space.xsl -out "${TMPDIR}/multibyte_space.xml";
# 3. remove duplicate
#    > ${TMPDIR}/rm_duplicate.xml
java org.apache.xalan.xslt.Process -in "${TMPDIR}/multibyte_space.xml" -xsl ${STYLEDIR}/erase_duplicate.xsl -out "${TMPDIR}/rm_duplicate.xml";

# 4. translate to csv
if [ -z "${POSTGRESQL_VERSION}" -a -z "${ORAFCE_VERSION}" ]; then
  ## 4-1. if version is NOT given
  ##      > ${OUTDIR}/result.csv
  java org.apache.xalan.xslt.Process -in "${TMPDIR}/rm_duplicate.xml" -xsl ${STYLEDIR}/make_csv.xsl -out "${OUTDIR}/result.csv";
elif [ -z "${ORAFCE_VERSION}" -a -n "${POSTGRESQL_VERSION}" ]; then
  ## 4-2. if PostgreSQL version is given
  ##      > ${TMPDIR}/adjust_version_PG.xml
  ##      > ${OUTDIR}/result.csv
  java org.apache.xalan.xslt.Process -in "${TMPDIR}/rm_duplicate.xml" -xsl ${STYLEDIR}/support_version.xsl -out "${TMPDIR}/adjust_version_PG.xml" -param product_val PostgreSQL -param version_val "${POSTGRESQL_VERSION}";
  java org.apache.xalan.xslt.Process -in "${TMPDIR}/adjust_version_PG.xml" -xsl ${STYLEDIR}/make_csv.xsl -out "${OUTDIR}/result.csv";
elif [ -z "${POSTGRESQL_VERSION}" -a -n "${ORAFCE_VERSION}" ]; then
  ## 4-3. if orafce version is given
  ##      > ${TMPDIR}/adjust_version_orafce.xml
  ##      > ${OUTDIR}/result.csv
  java org.apache.xalan.xslt.Process -in "${TMPDIR}/rm_duplicate.xml" -xsl ${STYLEDIR}/support_version.xsl -out "${TMPDIR}/adjust_version_orafce.xml" -param product_val orafce -param version_val "${ORAFCE_VERSION}";
  java org.apache.xalan.xslt.Process -in "${TMPDIR}/adjust_version_orafce.xml" -xsl ${STYLEDIR}/make_csv.xsl -out "${OUTDIR}/result.csv";
else
  ## 4-4. if PostgreSQL and orafce version is given
  ##      > ${TMPDIR}/adjust_version_PG.xml
  ##      > ${TMPDIR}/adjust_version_orafce.xml
  ##      > ${OUTDIR}/result.csv
  java org.apache.xalan.xslt.Process -in "${TMPDIR}/rm_duplicate.xml" -xsl ${STYLEDIR}/support_version.xsl -out "${TMPDIR}/adjust_version_PG.xml" -param product_val PostgreSQL -param version_val "${POSTGRESQL_VERSION}";
  java org.apache.xalan.xslt.Process -in "${TMPDIR}/adjust_version_PG.xml" -xsl ${STYLEDIR}/support_version.xsl -out "${TMPDIR}/adjust_version_orafce.xml" -param product_val orafce -param version_val "${ORAFCE_VERSION}";
  java org.apache.xalan.xslt.Process -in "${TMPDIR}/adjust_version_orafce.xml" -xsl ${STYLEDIR}/make_csv.xsl -out "${OUTDIR}/result.csv";
fi

## clean tmpdir
rm -rf "${TMPDIR}";

# 5. execute csvtool
## 5-1. make csv & link solution files.
cd ${OUTDIR};
mkdir csv;
mkdir editdata;
mv result.csv csv/;
cd csv;
perl ../../../src/csvtool_utf8.pl result.csv "${TARGET_CHAR}"

# csvツールのエラー判定
if [ $? -ne 0 ]; then
  echo "csvtool_utf8.pl error." >&2;
  rm -rf "${TMPDIR}";
  exit 1;
fi


if [ $(find -name "*.err" | wc -w) -ne 0 ]; then
    ## 5-2. make data for editing.
    mv *.err ../editdata/
fi

exit 0;
