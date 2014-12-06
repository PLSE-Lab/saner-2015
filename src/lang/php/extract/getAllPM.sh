#!/bin/bash
while read p; do
	v=${p//RELEASE_/}
	v=${v//_/.}
  cd phpmyadmin
  git checkout $p
  mkdir $HOME/PHPAnalysis/systems/phpMyAdmin/phpMyAdmin-$v
  cp -R * $HOME/PHPAnalysis/systems/phpMyAdmin/phpMyAdmin-$v/
  cd ..
done<pmtags
