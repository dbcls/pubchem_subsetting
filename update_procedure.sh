#!/bin/sh
set -euo pipefail

SCRIPT_DIR=$(cd $(dirname $0); pwd)

# グローバルに定義される変数を読み込む
source $SCRIPT_DIR/../../common_settings.sh

REMOTE_UPDATE_DATE=$1

ENDPOINT=https://rdfportal.org/pubchem/sparql
EBI_ENDPOINT=https://rdfportal.org/ebi/sparql
WORK_DIR=/tmp/pubchem_fdaapproved_neighbours
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
OUT_DIR=FDA_ChEBI-cids
TIMESTAMP=$(date -I)
FINAL_DESTINATION=${LOCALDIR}/pubchem/${REMOTE_UPDATE_DATE}
CURL=/usr/bin/curl
PERL=/usr/bin/perl
XARGS=/usr/bin/xargs
SORT=/usr/bin/sort
FIND=/usr/bin/find
RAPPER=/usr/bin/rapper
GREP=/usr/bin/grep
SED=/usr/bin/sed
TIMESTAMP=$(date -I)
LIMIT=1000000
CID_LIST=FDA_ChEBI_cids_${TIMESTAMP}.txt
CID_FROM_CHEMBL_LIST=cids_from_ChEMBL_${TIMESTAMP}.txt
CID4SUBSET=cids4subset_${TIMESTAMP}.txt

mkdir -p $FINAL_DESTINATION

rm -rf $WORK_DIR
mkdir -p $WORK_DIR
cd $WORK_DIR

echo "ChEMBLから繋がっているPubChem IDを取得。"
if [ -e $CID_FROM_CHEMBL_LIST ]; then rm $CID_FROM_CHEMBL_LIST; fi
CID_TOTAL=$($CURL -sSH "Accept: text/csv" --data-urlencode query@$SCRIPT_DIR/query_03_count.rq $EBI_ENDPOINT | tail -1)
echo ChEMBL→CID数: $CID_TOTAL
COUNT=$(expr $CID_TOTAL / $LIMIT)
for i in $(seq 0 ${COUNT}); do
  QUERY=$(sed -e "$ a OFFSET ${i}000000 LIMIT ${LIMIT}" $SCRIPT_DIR/query_03.rq)
  $CURL -sSH "Accept: text/csv" --data-urlencode query="$QUERY" $EBI_ENDPOINT | tail -n +2 >> $CID_FROM_CHEMBL_LIST
done
$SED -i -Ee 's/pubchem/rdf/;s,gov,gov/pubchem,;s,nd/,nd/CID,' $CID_FROM_CHEMBL_LIST

echo "FDA承認薬、ChEBI、およびChEMBLにつながるCIDを取得。"
echo 実行日: ${TIMESTAMP}
if [ -e $CID_LIST ]; then rm $CID_LIST; fi
CID_TOTAL=$($CURL -sSH "Accept: text/csv" --data-urlencode query@$SCRIPT_DIR/query_01_count.rq $ENDPOINT | tail -1)
echo 取得対象CID数: $CID_TOTAL
COUNT=$(expr $CID_TOTAL / $LIMIT)
for i in $(seq 0 ${COUNT}); do
  QUERY=$(sed -e "$ a OFFSET ${i}000000 LIMIT ${LIMIT}" $SCRIPT_DIR/query_01.rq)
  $CURL -sSH "Accept: text/csv" --data-urlencode query="$QUERY" $ENDPOINT | tail -n +2 >> $CID_LIST
done

$SORT -u $CID_FROM_CHEMBL_LIST $CID_LIST > $CID4SUBSET

$SED -i.bak -e '/CID313"/d' $CID4SUBSET # HClを除去（関連トリプル数が巨大なため別途特別対応している）
echo "ATC分類情報を取得。"
$CURL -sSH "Accept: application/n-triples" -o skos_concept_${TIMESTAMP}.nt --data-urlencode query="CONSTRUCT WHERE { ?attr a <http://www.w3.org/2004/02/skos/core#concept> ; ?p ?o .}" $ENDPOINT

echo "取得したCIDについて、それが主語もしくは目的語になるトリプルのうち、CID同士を結ばないものを取得。"
if [ -e ${OUT_DIR} ]; then $FIND ${OUT_DIR} -type f -exec rm "{}" \; ; else mkdir ${OUT_DIR} ; fi
$CURL -sSH "Accept: application/n-triples" -o ${OUT_DIR}/HydrochloricAcid.nt --data-urlencode query@query_02.rq $ENDPOINT
$PERL $SCRIPT_DIR/construct_1.pl $CID4SUBSET | xargs -0 -i -P10 $SCRIPT_DIR/get_describes.sh ${OUT_DIR} "{}" nt
RES=$($FIND ${OUT_DIR} -maxdepth 1 -name *.err 2>/dev/null)
if [ $? -ne 0 ]; then
  echo "$FIND の実行に失敗しました。"
elif [ -z "$RES" ]; then
  echo "エラーなし。"
else
  echo "エラーファイルがあります。"
  $FIND ${OUT_DIR} -maxdepth 1 -type f -name \*.err -exec $PERL -MFile::Slurp -e '$query=read_file( $ARGV[0] ); @args = ($query=~m,:CID\d+,g); $pat = join(" ",("_") x @args); for $uri ( @args ){$query =~ s/${uri}/_/}; while ( @args ){$uris = join(" ",splice(@args,0,100)); ($_query = $query) =~ s/${pat}/${uris}/; print $_query,"\n"; print "\0"}' "{}" \; | $XARGS -P10 -i -0 $SCRIPT_DIR/get_describes.sh ${OUT_DIR} "{}" nt
  $FIND ${OUT_DIR} -type f -name \*.nt -exec sh -c '(head -1 {} | grep -Pq "^(?:@prefix|<https?:)") || (echo {}; rm {})' \;
  for fn in $RES; do rm $fn; done
  RES=$($FIND ${OUT_DIR} -maxdepth 1 -name *.err 2>/dev/null)
  if [ -z "$RES" ]; then
    echo "エラーなし。"
  else
    echo "エラーファイルがまだあります。"
    $FIND ${OUT_DIR} -maxdepth 1 -type f -name \*.err -exec $PERL -MFile::Slurp -e '$query=read_file( $ARGV[0] ); @args = ($query=~m,:CID\d+,g); $pat = join(" ",("_") x @args); for $uri ( @args ){$query =~ s/${uri}/_/}; while ( @args ){$uris = join(" ",splice(@args,0,20)); ($_query = $query) =~ s/${pat}/${uris}/; print $_query,"\n"; print "\0"}' "{}" \; | $XARGS -P10 -i -0 $SCRIPT_DIR/get_describes.sh ${OUT_DIR} "{}" nt
    $FIND ${OUT_DIR} -type f -name \*.nt -exec sh -c '(head -1 {} | grep -Pq "^(?:@prefix|<https?:)") || (echo {}; rm {})' \;
    for fn in $RES; do rm $fn; done
    RES=$($FIND ${OUT_DIR} -maxdepth 1 -name *.err 2>/dev/null)
    if [ -z "$RES" ]; then
      echo "エラーなし。"
    else
      echo "エラーファイルがまだあります。更新スクリプトを中断します。"
      exit
    fi
  fi
fi

echo "取得したCIDについて、has-attribute述語の目的語が主語になるトリプルを取得。"
HAS_ATTRIBUTE="SIO_000008"
if [ -e ${OUT_DIR}-attrs ]; then $FIND ${OUT_DIR}-attrs -type f -exec rm "{}" \; ; else mkdir ${OUT_DIR}-attrs ; fi
$FIND ${OUT_DIR} -type f -name \*.nt -exec cat "{}" \; | $GREP $HAS_ATTRIBUTE | cut -f3 | $PERL -ne 'chomp; m,([^/]+)> \.$,; push @vals, ":$1"; if(@vals == 500){print "PREFIX : <http://rdf.ncbi.nlm.nih.gov/pubchem/descriptor/> CONSTRUCT {?attr ?p ?o .} WHERE { VALUES ?attr {", join(" ", @vals), "} ?attr ?p ?o }\n"; @vals=()}' | $XARGS -P10 -i $SCRIPT_DIR/get_describes.sh ${OUT_DIR}-attrs "{}"

echo "取得したCIDが目的語で、主語のURIにsynonymが含まれるトリプルを取得。"
SYNONYM="SIO_000122"
$FIND ${OUT_DIR} -type f -name \*.nt -exec cat "{}" \; | $GREP $SYNONYM | cut -f1 | $PERL -ne 'chomp; m,([^/]+)>$,; push @vals, ":$1"; if(@vals == 500){print "PREFIX : <http://rdf.ncbi.nlm.nih.gov/pubchem/synonym/> CONSTRUCT {?attr ?p ?o .} WHERE { VALUES ?attr {", join(" ", @vals), "} ?attr ?p ?o }\n"; @vals=()}' | $XARGS -P10 -i $SCRIPT_DIR/get_describes.sh ${OUT_DIR}-attrs "{}"

chk_error() {
  $FIND ${OUT_DIR}-attrs -maxdepth 1 -type f -name \*.err -exec $PERL -ne 'chomp; @args=m,(:[^{}/ ]+),g; pop @args; $pat=join(" ",("_") x @args); for $uri ( @args ){s/${uri}/_/}; while ( @args ){$uris = join(" ",splice(@args,0,$1)); ($query = $_) =~ s/${pat}/${uris}/; print $query,"\n"}' "{}" \; | $XARGS -P10 -i $SCRIPT_DIR/get_describes.sh ${OUT_DIR}-attrs "{}"
  $FIND ${OUT_DIR}-attrs -type f -name \*.ttl -exec sh -c '(head -1 {} | grep -q "^@prefix") || (echo {}; rm {})' \;
  for fn in $RES; do rm $fn; done
}

RES=$($FIND ${OUT_DIR}-attrs -maxdepth 1 -name *.err 2>/dev/null)
if [ $? -ne 0 ]; then 
  echo "$FIND の実行に失敗しました。"
elif [ -z "$RES" ]; then
  echo "エラーなし。"
else
  echo "エラーファイルがあります。"
  chk_error 100
  RES=$($FIND ${OUT_DIR}-attrs -maxdepth 1 -name *.err 2>/dev/null)
  if [ -z "$RES" ]; then
    echo "エラーなし。"
  else
    echo "エラーファイルがまだあります。"
    chk_error 20
    RES=$($FIND ${OUT_DIR}-attrs -maxdepth 1 -name *.err 2>/dev/null)
    if [ -z "$RES" ]; then
      echo "エラーなし。"
    else
      echo "エラーファイルがまだあります。"
      chk_error 10
      RES=$($FIND ${OUT_DIR}-attrs -maxdepth 1 -name *.err 2>/dev/null)
      if [ -z "$RES" ]; then
        echo "エラーなし。"
      else
        echo "エラーファイルがまだあります。更新スクリプトを中断します。"
        exit
      fi
    fi
  fi
fi

mv skos_concept_${TIMESTAMP}.nt ${OUT_DIR}/
$FIND ${OUT_DIR}-attrs -type f -name \*.ttl | $XARGS -P20 -i sh -c "F=\$(basename {} .ttl); $RAPPER -i turtle -o ntriples {} 2> /dev/null > ${OUT_DIR}/\${F}.nt"
$FIND ${OUT_DIR} -type f -exec cat "{}" \; | sort --parallel=20 --compress-program=gzip -S12G -u | gzip -9c > ${FINAL_DESTINATION}/pubchem_subset_slim_${TIMESTAMP}.nt.gz
