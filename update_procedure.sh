#!/bin/sh
set -euo pipefail

ENDPOINT=https://integbio.jp/rdf/pubchem/sparql
WORK_DIR=/data/yayamamo/pubchem_fdaapproved_neighbours
CURL=/usr/bin/curl
PERL=/usr/bin/perl
XARGS=/usr/bin/xargs
FIND=/usr/bin/find
RAPPER=/data/yayamamo/local/bin/rapper
GREP=/usr/bin/grep
SED=/usr/bin/sed
TIMESTAMP=$(date -I)
LIMIT=10000000

cd $WORK_DIR
echo "FDA承認薬、ChEBI、およびChEMBLにつながるCIDを取得。"
if [ -e FDA_CHEBI_cids_${TIMESTAMP}.txt ]; then rm FDA_CHEBI_cids_${TIMESTAMP}.txt; fi
CID_TOTAL=$($CURL -sSH "Accept: text/csv" --data-urlencode query@query_01_count.rq $ENDPOINT | tail -1)
COUNT=$(expr $CID_TOTAL / $LIMIT)
for i in $(seq 0 ${COUNT}); do
  QUERY=$(sed -e "$ a OFFSET ${i}000000 LIMIT ${LIMIT}" query_01.rq)
  $CURL -sSH "Accept: text/csv" --data-urlencode query="$QUERY" $ENDPOINT | tail -n +2 >> FDA_CHEBI_cids_${TIMESTAMP}.txt
done
$SED -i.bak -e '/CID313"/d' FDA_CHEBI_cids_${TIMESTAMP}.txt # HClを除去（関連トリプル数が巨大なため別途特別対応している）
echo "ATC分類情報を取得。"
$CURL -sSH "Accept: text/turtle" -o skos_concept_${TIMESTAMP}.ttl --data-urlencode query="CONSTRUCT WHERE { ?attr a <http://www.w3.org/2004/02/skos/core#concept> ; ?p ?o .}" $ENDPOINT

echo "取得したCIDについてDESCRIBEで関連するトリプルを取得。"
if [ -e FDA_CHEBI-cids ]; then touch FDA_CHEBI-cids/a; rm FDA_CHEBI-cids/*; fi
$CURL -sSH "Accept: text/turtle" -o FDA_CHEBI-cids/HydrochloricAcid.ttl --data-urlencode query@query_02.rq $ENDPOINT
$PERL -ne 'chomp;m,([^/]+)"$,;push @vals, ":$1";if(@vals == 500){print "PREFIX : <http://rdf.ncbi.nlm.nih.gov/pubchem/compound/> DESCRIBE ?cid WHERE { VALUES ?cid {", join(" ", @vals), "}}\n";@vals=()}' FDA_CHEBI_cids_${TIMESTAMP}.txt | $XARGS -P10 -i get_describes.sh FDA_CHEBI-cids "{}"
ls FDA_CHEBI-cids/*.err &> /dev/null
if [ $? = 0 ]; then echo "エラーファイルがあります。"
  ERROR_FILES=FDA_CHEBI-cids/*.err
  $PERL -ne 'chomp;@args=m,(:[^{}/ ]+),g;pop @args;$pat=join(" ",("_") x @args);for $uri ( @args ){s/${uri}/_/};while ( @args ){$uris = join(" ",splice(@args,0,100));($query = $_) =~ s/${pat}/${uris}/;print $query,"\n"}' FDA_CHEBI-cids/*.err | $XARGS -P10 -i get_describes.sh FDA_CHEBI-cids "{}"
  $FIND /data/yayamamo/pubchem_fdaapproved_neighbours/FDA_CHEBI-cids -type f -name \*.ttl -exec sh -c '(head -1 {} | grep -q "^@prefix") || (echo {}; rm {})' \;
  for fn in $ERROR_FILES; do rm $fn; done
fi
ls FDA_CHEBI-cids/*.err &> /dev/null
if [ $? = 0 ]; then echo "まだエラーファイルがあります。"; exit; fi

echo "取得したCIDについて、has-attribute述語の目的語が主語になるトリプルを取得。"
if [ -e FDA_CHEBI-cids-attrs ]; then touch FDA_CHEBI-cids-attrs/a; rm FDA_CHEBI-cids-attrs/*; fi
$FIND FDA_CHEBI-cids -type f -name \*.ttl -exec $RAPPER -i turtle -o ntriples "{}" \; | $GREP has-attribute | cut -f3 -d ' ' | $PERL -ne 'chomp;m,([^/]+)>$,;push @vals, ":$1";if(@vals == 500){print "PREFIX : <http://rdf.ncbi.nlm.nih.gov/pubchem/descriptor/> CONSTRUCT {?attr ?p ?o .} WHERE { VALUES ?attr {", join(" ", @vals), "} ?attr ?p ?o }\n";@vals=()}' | $XARGS -P10 -i get_describes.sh FDA_CHEBI-cids-attrs "{}"

echo "取得したCIDが目的語で、主語のURIにsynonymが含まれるトリプルを取得。"
$FIND FDA_CHEBI-cids -type f -name \*.ttl -exec $RAPPER -i turtle -o ntriples "{}" \;  | $GREP synonym | cut -f1 -d ' ' | $PERL -ne 'chomp;m,([^/]+)>$,;push @vals, ":$1";if(@vals == 500){print "PREFIX : <http://rdf.ncbi.nlm.nih.gov/pubchem/synonym/> CONSTRUCT {?attr ?p ?o .} WHERE { VALUES ?attr {", join(" ", @vals), "} ?attr ?p ?o }\n";@vals=()}' | $XARGS -P10 -i get_describes.sh FDA_CHEBI-cids-attrs "{}"

ls FDA_CHEBI-cids-attrs/*.err &> /dev/null
if [ $? = 0 ]; then echo "エラーファイルがあります。"
  ERROR_FILES=FDA_CHEBI-cids-attrs/*.err
  $PERL -ne 'chomp;@args=m,(:[^{}/ ]+),g;pop @args;$pat=join(" ",("_") x @args);for $uri ( @args ){s/${uri}/_/};while ( @args ){$uris = join(" ",splice(@args,0,100));($query = $_) =~ s/${pat}/${uris}/;print $query,"\n"}' FDA_CHEBI-cids-attrs/*.err | $XARGS -P10 -i get_describes.sh FDA_CHEBI-cids-attrs "{}"
  $FIND /data/yayamamo/pubchem_fdaapproved_neighbours/FDA_CHEBI-cids-attrs -type f -name \*.ttl -exec sh -c '(head -1 {} | grep -q "^@prefix") || (echo {}; rm {})' \;
  for fn in $ERROR_FILES; do rm $fn; done
fi
ls FDA_CHEBI-cids-attrs/*.err &> /dev/null
if [ $? = 0 ]; then echo "まだエラーファイルがあります。"; exit; fi

echo "取得したCIDと何らかの関係のあるCIDを示すトリプルを取得。"
if [ -e FDA_CHEBI-cids-interrelations ]; then touch FDA_CHEBI-cids-interrelations/a; rm FDA_CHEBI-cids-interrelations/*; fi
$FIND FDA_CHEBI-cids -type f -name \*.ttl -exec $RAPPER -i turtle -o ntriples "{}" \; 2> /dev/null | $GREP -e _000461 -e _000455 | cut -f3 -d ' ' | sort -u | $PERL -ne 'chomp;m,([^/]+)>$,;push @vals, ":$1";if(@vals == 500){print "PREFIX : <http://rdf.ncbi.nlm.nih.gov/pubchem/compound/> DESCRIBE ?cid WHERE { VALUES ?cid {", join(" ", @vals), "}}\n";@vals=()}' | $XARGS -P10 -i get_describes.sh FDA_CHEBI-cids-interrelations "{}"
$FIND FDA_CHEBI-cids -type f -name \*.ttl -exec $RAPPER -i turtle -o ntriples "{}" \; 2> /dev/null | $GREP -e _000480 -e has_parent | cut -f1 -d ' ' | sort -u | $PERL -ne 'chomp;m,([^/]+)>$,;push @vals, ":$1";if(@vals == 500){print "PREFIX : <http://rdf.ncbi.nlm.nih.gov/pubchem/compound/> DESCRIBE ?cid WHERE { VALUES ?cid {", join(" ", @vals), "}}\n";@vals=()}' | $XARGS -P10  -i get_describes.sh FDA_CHEBI-cids-interrelations "{}"
ls FDA_CHEBI-cids-interrelations/*.err &> /dev/null
if [ $? = 0 ]; then echo "エラーファイルがあります。"
  ERROR_FILES=FDA_CHEBI-cids-interrelations/*.err
  $PERL -ne 'chomp;@args=m,(:[^{}/ ]+),g;pop @args;$pat=join(" ",("_") x @args);for $uri ( @args ){s/${uri}/_/};while ( @args ){$uris = join(" ",splice(@args,0,100));($query = $_) =~ s/${pat}/${uris}/;print $query,"\n"}' FDA_CHEBI-cids-interrelations/*.err | $XARGS -P10 -i get_describes.sh FDA_CHEBI-cids-interrelations "{}"
  $FIND /data/yayamamo/pubchem_fdaapproved_neighbours/FDA_CHEBI-cids-interrelations -type f -name \*.ttl -exec sh -c '(head -1 {} | grep -q "^@prefix") || (echo {}; rm {})' \;
  for fn in $ERROR_FILES; do rm $fn; done
fi
ls FDA_CHEBI-cids-interrelations/*.err &> /dev/null
if [ $? = 0 ]; then echo "まだエラーファイルがあります。"; exit; fi

if [ ! -e final_ntriples ]; then mkdir final_triples; else rm -rf final_ntriples; mkdir final_ntriples ; fi
$FIND FDA_CHEBI-cids-interrelations/ FDA_CHEBI-cids-attrs/ FDA_CHEBI-cids/ skos_concept_${TIMESTAMP}.ttl -type f -name \*.ttl | $XARGS -P20 -i sh -c "F=\$(basename {} .ttl); $RAPPER -i turtle -o ntriples {} 2> /dev/null > final_ntriples/\${F}.nt"
$FIND final_ntriples -type f -exec cat "{}" \; | sort --parallel=20 --compress-program=gzip -S12G | gzip -9c > FDA_CHEBI_subset_${TIMESTAMP}.nt.gz
#$FIND ${WORK_DIR}/FDA_CHEBI-cids-interrelations/ ${WORK_DIR}/FDA_CHEBI-cids-attrs/ ${WORK_DIR}/FDA_CHEBI-cids/ ${WORK_DIR}/skos_concept_${TIMESTAMP}.ttl -type f -name \*.ttl -exec $RAPPER -i turtle -o ntriples "{}" \; 2>/dev/null | sort --parallel=20 --compress-program=gzip -S12G | gzip -9c > FDA_CHEBI_subset_${TIMESTAMP}.nt.gz
