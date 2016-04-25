#!/bin/bash
while read p; do
  output=`curl https://wordpress.org/plugins/$p/`
  e1='<strong>Last Updated: </strong> <meta itemprop="dateModified" content="2015'
  e2='<strong>Compatible up to:</strong> 4'
  if [[ $output =~ $e1 && $output =~ $e2 ]]; then
    mkdir $p
    svn co http://plugins.svn.wordpress.org/$p/trunk $p
  else
  	echo "Skipping $p"
  fi
done<plugins.txt
