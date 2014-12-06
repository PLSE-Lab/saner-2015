#!/bin/bash
while read p; do
  cd mediawiki-core
  git checkout $p
  mkdir $HOME/PHPAnalysis/systems/MediaWiki/mediawiki-$p
  cp -R * $HOME/PHPAnalysis/systems/MediaWiki/mediawiki-$p/
  cd ..
done<mwtags
