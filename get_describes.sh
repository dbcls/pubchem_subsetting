#!/bin/sh

endpoint=https://integbio.jp/rdf/pubchem/sparql
directory=$1
fn=$(uuidgen)
curl -sSH "Accept: text/turtle" --data-urlencode query="$2" -o ${directory}/${fn}.ttl ${endpoint}
(head -1 ${directory}/${fn}.ttl | grep -Pq "^(@prefix|# Empty TURTLE)") || echo "$2" > ${directory}/${fn}.err
