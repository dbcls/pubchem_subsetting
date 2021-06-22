#!/usr/bin/env perl
#
use warnings;
use strict;
use utf8;
use open ":utf8";

my $preamble = <<'HERE';
PREFIX : <http://rdf.ncbi.nlm.nih.gov/pubchem/compound/>
PREFIX cheminf: <http://semanticscience.org/resource/>
PREFIX vocab: <http://rdf.ncbi.nlm.nih.gov/pubchem/vocabulary#>
CONSTRUCT  {
  ?cid ?p1 ?o .
  ?s ?p2 ?cid .
} WHERE {
  VALUES ?cid {
HERE

my $epilogue = <<'AFTER';
  }
  {?cid ?p1 ?o .}
  UNION
  {?s ?p2 ?cid .}
  FILTER (
    ?p1 NOT IN (cheminf:CHEMINF_000461, cheminf:CHEMINF_000462, cheminf:CHEMINF_000455, vocab:has_parent, cheminf:CHEMINF_000480) &&
    ?p2 NOT IN (cheminf:CHEMINF_000461, cheminf:CHEMINF_000462, cheminf:CHEMINF_000455, vocab:has_parent, cheminf:CHEMINF_000480)
    )
}
AFTER

my @vals;
while(<>){
  chomp;
  m,([^/]+)"$,;
  push @vals, ":$1";
  if(@vals == 500){
    print $preamble;
    print join(" ", @vals), "\n";
    print $epilogue;
    print "\0";
    @vals = ();
  }
}
