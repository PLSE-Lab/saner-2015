This is the project source for an empirical analysis of trends in dynamic feature evolution across the release history of two projects, MediaWiki and WordPress. 

To run the Rascal code in this project, you will of course first need to install Rascal. Details on how to install Rascal are available at the [Rascal homepage](http://www.rascal-mpl.org). You will also need the current versions of PHP AiR and the PHP parser that we use on this project. Details on the parser are available on the [GitHub project page for our fork](https://github.com/cwi-swat/PHP-Parser), while details on PHP AiR are also available on its [GitHub project page](https://github.com/cwi-swat/php-analysis/), including installation details. The newest version of both projects should work; you can also specifically pull v1.0.0 of PHP AiR. 

To run the code, you should import PHP Air and this project both into Eclipse. You can then open a Rascal console and execute the code in the SANER2015 module. The code currently generates figures for MediaWiki, WordPress, and phpMyAdmin, although only MediaWiki and WordPress are included in the paper (the work on phpMyAdmin is ongoing, and space in the paper was also limited).

To get the systems, you can clone the following repositories:

* The [MediaWiki GitHub repository](https://github.com/wikimedia/mediawiki)
* The [WordPress GitHub repository](https://github.com/WordPress/WordPress/)

The scripts in `/src/lang/php/extract` then show how the versions of MediaWiki and phpMyAdmin were extracted from the repositories; a similar script for WordPress will be added soon, although the WordPress repository is missing some earlier versions of the system which need to be downloaded manually.
