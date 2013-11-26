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
if [ -e "$OUTDIR/replaced" ]; then
  echo "output directory is already exist.($OUTDIR/replaced)" >&2;
  exit 1;
fi
mkdir -p "$OUTDIR"/{replaced,log};

#
# 1. execute db_ddl_replace
#    > $output/rpd
# オプションを変数化
option="-e ${TARGET_CHAR} -i ${OUTDIR}/intermediate,${TARGET_EXT} -r ${OUTDIR}/candidate/replacement_candidate.csv -o ${OUTDIR}/replaced"

# 一括置換候補ファイルの使用で条件分岐
if [ "${USE_GROUP_REPLACEMENT_CANDIDATE}" = "y" ]; then
  option="$option -g ${OUTDIR}/candidate/group_replacement_candidate.csv"
fi

# ログ出力によって -v オプションの条件分岐
if [ "${STDERR_OUTPUT_FLAG}" = "both" ]; then
  option="$option -v 1 2>&1 1>${OUTDIR}/log/rpd_summary | tee ${OUTDIR}/log/rpd_${STDERR_FILE_NAME}"
elif [ "${STDERR_OUTPUT_FLAG}" = "screen" ]; then
  option="${option} -v"
elif [ "${STDERR_OUTPUT_FLAG}" = "file" ]; then
  option="${option} -v 1 1> ${OUTDIR}/log/rpd_summary 2> ${OUTDIR}/log/rpd_${STDERR_FILE_NAME}"
fi

# コマンド実行
eval "db_ddl_replace_prot.pl ${option}";

if [ $? -ne 0 ]; then
  echo "db_ddl_replace.prot.pl error." >&2;
exit 1;
fi

if [ "${STDERR_OUTPUT_FLAG}" = "both" ]; then
  cat ${OUTDIR}/log/rpd_summary
fi

exit 0;
