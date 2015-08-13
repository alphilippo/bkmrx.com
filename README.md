# 	bkmrx.com

##Synopsis

[bkmrx.com][1] is an open source social bookmarking website, built in Perl, using the [Mojolicious][3] framework, [Twitter Bootstrap][4], and [Elasticsearch][5].

## Setup

 - Use a server with Perl 5.10+ installed
 - Install ElasticSearch (version >= 1.1 but < 1.3)
 - Install the Perl modules listed in the INSTALL file
 - Run initialise-es-db.pl file in root folder to set up ElasticSearch indices
 - Fill in required credentials in bkx_mojo.conf file
 - Run server!

### Setting up twitter integration

You need a twitter API key in order for the twitter integration to work. When you have a consumer key/secret and token/token secret, fill in the details in the _bin/fetch-twitter-api.pl_ script.

### Setting up the search engine

*Be polite to webmasters: add a contact email address in the _$user___agent_ variable in the _bin/mojo-crawler.pl_ script.*

On first run, you need to create the search index, which is stored in the _web-index/_ folder. In order to avoid any index duplication, I recommend installing the site, adding a few bookmarks, then running the _bin/mojo-crawler.pl_ script from the command line with the **--create=1** option.

This tells the crawler to create the index; only do this once (or delete the contents of the _web-index/_ folder), otherwise your search index will start showing duplicate results.

By default the crawler will only crawl 500 URLs at a time, and will only crawl them once.

### Cron tasks

Add the following lines to the crontab :

 - 0 0 * * * perl
   /_[app-dir]_/bin/fetch-twitter-api.pl
 - 0 0 * * * perl /_[app-dir]_/bin/fetch-github.pl
 - */4 * * * * perl /_[app-dir]_/bin/mojo-crawler.pl

You can view a working version of the software at [bkmrx.com][7]

## Deploying

### _How to deploy_

You can run bkmrx.com using the built-in Mojolicious morbo / hypnotoad servers, or through a reverse proxy such as nginx.

## Contributing changes

- Contact me on [twitter][8] if you're interested in joining the project or contributing code.
- Have a bug or a feature request? Please [open a new issue][9].

## License

The MIT License (MIT)

Copyright (c) 2015 Rob Hammond

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.



  [1]: https://bkmrx.com/
  [3]: http://mojolicio.us/
  [4]: http://twitter.github.com/bootstrap/
  [5]: http://elasticsearch.org/
  [6]: http://lucy.apache.org/
  [7]: https://bkmrx.com/
  [8]: http://twitter.com/robhammond
  [9]: https://github.com/robhammond/bkmrx/issues