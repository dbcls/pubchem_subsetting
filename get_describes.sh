#!/bin/bash

declare -A ctype
ctype["ttl"]="text/turtle"
ctype["nt"]="application/n-triples"

endpoint=https://rdfportal.org/pubchem/sparql
directory=$1
fn=$(uuidgen)
ext=$3
if [ -z $ext ]; then ext="ttl"; fi
content_type=${ctype[$ext]}
curl -sSH "Accept: ${content_type}" --data-urlencode query="$2" -o ${directory}/${fn}.${ext} ${endpoint}
(test -e ${directory}/${fn}.${ext} && (head -1 ${directory}/${fn}.${ext} | grep -Pq "^(?:@prefix|# Empty (?:NT|TURTLE)|<https?:)")) || echo "$2" > ${directory}/${fn}.err
