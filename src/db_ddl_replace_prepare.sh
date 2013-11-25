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
mkdir -p "$OUTDIR"/{intermediate,candidate,log};
mkdir -p "$TMPDIR";
STYLEDIR="../stylesheet"

#
# 1. execute db_ddl_replace_formatter
#    > $OUTDIR/imd/
# オプションを変数化
option="-e ${TARGET_CHAR} -i ${TARGET_PATH},${TARGET_EXT} -o ${OUTDIR}/intermediate/"

# ログ出力によって -v オプションの条件分岐
if [ "${STDERR_OUTPUT_FLAG}" = "both" ]; then
   option="${option} -v 1 2>&1 | tee ${OUTDIR}/log/imd_${STDERR_FILE_NAME}"
elif [ "${STDERR_OUTPUT_FLAG}" = "screen" ]; then
   option="${option} -v"
elif [ "${STDERR_OUTPUT_FLAG}" = "file" ]; then
   option="${option} -v 1 2> ${OUTDIR}/log/imd_${STDERR_FILE_NAME}"
fi

# コマンド実行
eval "db_ddl_replace_formatter.pl ${option}";

if [ $? -ne 0 ]; then
  echo "db_ddl_replace_formatter.pl error." >&2;
  exit 1;
fi

# 2. execute db_syntax_diff
#    > $TMPDIR/tmp.xml
# オプションを変数化
option="-e ${TARGET_CHAR} -i ${OUTDIR}/intermediate/,${TARGET_EXT} -o ${TMPDIR}/tmp.xml -m sql"

# ログ出力によって -v オプションの条件分岐
if [ "${STDERR_OUTPUT_FLAG}" = "both" ]; then
   option="${option} -v 1 2>&1 | tee ${OUTDIR}/log/diff_${STDERR_FILE_NAME}"
elif [ "${STDERR_OUTPUT_FLAG}" = "screen" ]; then
   option="${option} -v"
elif [ "${STDERR_OUTPUT_FLAG}" = "file" ]; then
   option="${option} -v 1 2> ${OUTDIR}/log/diff_${STDERR_FILE_NAME}"
fi

# コマンド実行
eval "db_syntax_diff.pl ${option}";


if [ $? -ne 0 ]; then
  echo "db_syntax_diff.pl error." >&2;
  exit 1;
fi


# 3. multibyte_space
#    > $TMPDIR/multibyte_space.xml
java org.apache.xalan.xslt.Process -in "${TMPDIR}/tmp.xml" -xsl ${STYLEDIR}/erase_multibyte_space.xsl -out "${TMPDIR}/multibyte_space.xml";
# 4. remove duplicate
#    > ${TMPDIR}/rm_duplicate.xml
java org.apache.xalan.xslt.Process -in "${TMPDIR}/multibyte_space.xml" -xsl ${STYLEDIR}/erase_duplicate.xsl -out "${TMPDIR}/rm_duplicate.xml";

# 5. make replacement_candidate.csv
if [ -z "${POSTGRESQL_VERSION}" -a -z "${ORAFCE_VERSION}" ]; then
  ## 5-1. if version is NOT given
  ##      > ${OUTDIR}/result.csv
  java org.apache.xalan.xslt.Process -in "${TMPDIR}/rm_duplicate.xml" -xsl ${STYLEDIR}/make_replacement_candidate.xsl -out "${OUTDIR}/candidate/replacement_candidate.csv";
elif [ -z "${ORAFCE_VERSION}" -a -n "${POSTGRESQL_VERSION}" ]; then
  ## 5-2. if PostgreSQL version is given
  ##      > ${TMPDIR}/adjust_version_PG.xml
  ##      > ${OUTDIR}/candidate/replacement_candidate.csv
  java org.apache.xalan.xslt.Process -in "${TMPDIR}/rm_duplicate.xml" -xsl ${STYLEDIR}/support_version.xsl -out "${TMPDIR}/adjust_version_PG.xml" -param product_val PostgreSQL -param version_val "${POSTGRESQL_VERSION}";
  java org.apache.xalan.xslt.Process -in "${TMPDIR}/adjust_version_PG.xml" -xsl ${STYLEDIR}/make_replacement_candidate.xsl -out "${OUTDIR}/candidate/replacement_candidate.csv";
elif [ -z "${POSTGRESQL_VERSION}" -a -n "${ORAFCE_VERSION}" ]; then
  ## 5-3. if orafce version is given
  ##      > ${TMPDIR}/adjust_version_orafce.xml
  ##      > ${OUTDIR}/candidate/replacement_candidate.csv
  java org.apache.xalan.xslt.Process -in "${TMPDIR}/rm_duplicate.xml" -xsl ${STYLEDIR}/support_version.xsl -out "${TMPDIR}/adjust_version_orafce.xml" -param product_val orafce -param version_val "${ORAFCE_VERSION}";
  java org.apache.xalan.xslt.Process -in "${TMPDIR}/adjust_version_orafce.xml" -xsl ${STYLEDIR}/make_replacement_candidate.xsl -out "${OUTDIR}/candidate/replacement_candidate.csv";
else
  ## 5-4. if PostgreSQL and orafce version is given
  ##      > ${TMPDIR}/adjust_version_PG.xml
  ##      > ${TMPDIR}/adjust_version_orafce.xml
  ##      > ${OUTDIR}/candidate/replacement_candidate.csv
  java org.apache.xalan.xslt.Process -in "${TMPDIR}/rm_duplicate.xml" -xsl ${STYLEDIR}/support_version.xsl -out "${TMPDIR}/adjust_version_PG.xml" -param product_val PostgreSQL -param version_val "${POSTGRESQL_VERSION}";
  java org.apache.xalan.xslt.Process -in "${TMPDIR}/adjust_version_PG.xml" -xsl ${STYLEDIR}/support_version.xsl -out "${TMPDIR}/adjust_version_orafce.xml" -param product_val orafce -param version_val "${ORAFCE_VERSION}";
  java org.apache.xalan.xslt.Process -in "${TMPDIR}/adjust_version_orafce.xml" -xsl ${STYLEDIR}/make_replacement_candidate.xsl -out "${OUTDIR}/candidate/replacement_candidate.csv";
fi

## clean tmpdir
rm -rf "${TMPDIR}";

# 6. make group_replacement_candidate
cd ${OUTDIR}/candidate;
# コマンド実行
eval "make_group_replacement_candidate.pl replacement_candidate.csv";

if [ $? -ne 0 ]; then
  echo "make_group_replacement_candidate.pl error." >&2;
  rm -rf "${TMPDIR}";
  exit 1;
fi

exit 0;
