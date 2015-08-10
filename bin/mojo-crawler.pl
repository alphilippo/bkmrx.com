#!/usr/bin/env perl
use Modern::Perl;
use open qw(:locale);
use strict;
use utf8;
use warnings qw(all);
use Modern::Perl;
use Mojo::Util qw(decode encode html_unescape xml_escape);
use Mojo::DOM;
use Mojo::Log;
use Mojo::Home;
use Mojo::UserAgent;

use File::Spec::Functions qw( catfile );
use Getopt::Long;
use Time::HiRes qw(time);
use File::Path qw(make_path);
use Digest::MD5 qw(md5_hex);
use Digest::SHA1 qw(sha1_hex);
use Data::Dumper;
use Search::Elasticsearch;
use FindBin;

my ($lib_dir, $conf_dir);
BEGIN {
    my $home = Mojo::Home->new;
    $home->detect;
    $lib_dir = $home->rel_dir('../lib');
    $conf_dir = $home->rel_dir('../');
}

use lib $lib_dir;
use BkxMojo::Plugin::Bkmrx;

# limit download size to 500KB
$ENV{MOJO_MAX_MESSAGE_SIZE} = 500000;

my $plugin = BkxMojo::Plugin::Bkmrx->new;

my $log = Mojo::Log->new;

# Change user agent string and add contact email for webmasters
my $user_agent = 'Mozilla/5.0 (compatible; BkmrxBot/0.1; +https://github.com/robhammond/bkmrx/bot)';

# default to only indexing links which *haven't* been indexed
my $all_links = 0;
# default limit set to 500 since the crontab's running this script 
# every 2 minutes, so no point in thrashing it all in one go.
my $limit     = 150;
my $debug = 0;
GetOptions( 'all_links=i' => \$all_links, 'limit=i' => \$limit, 'debug=i' => \$debug );

my $es = Search::Elasticsearch->new(
    nodes      => '127.0.0.1:9200'
);

my $queue;
my $es_query;

if ($all_links == 1) {
    $es_query = {
        match_all => { },
    };
} else {
    $es_query = {
        match => { 
            crawled => 0,
        },
    };
}

my $es_queue;

if ($all_links == 0) {
    $es_queue = $es->search(
        index => 'bkmrx',
        type => 'url',
        body  => {
            query => $es_query,
        },
        size => $limit,
    );
} else {
    # not currently working
    # $es_queue = $es->search(
    #     index => 'bkmrx',
    #     type => 'url',
    #     body  => {
    #         query => $es_query,
    #     },
    # );
}

if ($debug == 1) {
    $log->info(Dumper($es_queue));
}

# don't continue if we've nothing to index.
if ( $es_queue->{'hits'}->{'total'} == 0 ) {
    $log->error("no urls found!");
    exit;
}

# FIFO queue
my @urls = @{ $es_queue->{'hits'}->{'hits'} };

# Limit parallel connections to 4
my $max_conn = 4;

# User agent following up to 5 redirects
my $ua = Mojo::UserAgent->new(max_redirects => 5);
$ua->proxy->detect;
$ua->transactor->name($user_agent);

# Keep track of active connections
my $active = 0;

Mojo::IOLoop->recurring(
    0 => sub {
        for ($active + 1 .. $max_conn) {

            # Dequeue or halt if there are no active crawlers anymore
            return ($active or Mojo::IOLoop->stop)
                unless my $obj = shift @urls;

            # Fetch non-blocking just by adding
            # a callback and marking as active
            ++$active;
            $ua->get($obj->{'_source'}->{'url'} => sub {
                my (undef, $tx) = @_;

                # Deactivate
                --$active;

                # Parse only OK HTML responses
                unless ($tx->res->is_status_class(200)) {
                    _crawl_fail($obj->{'_id'}, $tx->res->code);
                    return;
                }
                if ($tx->res->headers->content_type !~ m{^text/html\b}ix) {
                    # need something better here - ie record content type
                    _crawl_ok($obj->{'_id'});
                    return;
                }

                # Request URL
                my $url = $tx->req->url;

                parse_html($url, $tx, $obj->{'_id'});

                return;
            });
        }
    }
);

# Start event loop if necessary
Mojo::IOLoop->start unless Mojo::IOLoop->is_running;

sub parse_html {
    my ($url, $tx, $id) = @_;

    my $content = $tx->res->body;
                    
    my ($charset) = $tx->res->headers->content_type =~ /charset=([-0-9A-Za-z]+)$/; 
    
    # attempt to decode content
    if ($charset) {
        $charset =~ s!utf-8!utf8!;
        $content = decode($charset, $tx->res->body);
    }

    if (!$content) {
        # no content!
        _crawl_ok($id);
        return;
    }

    # remove junk
    $content =~ s!<(script|style|iframe)[^>]*>.*?</\1>!!gis;

    # initialise DOM parser
    my $dom = Mojo::DOM->new($content);
    
    my $domain = $url;
    $domain =~ s!^https?://([^/]+)/?.*$!$1!i;

    # Store title or URL if title not found
    my $title = $tx->res->dom->at('head > title') ? $tx->res->dom->at('head > title')->text : $url->to_string;

    $title =~ s!\n!!g;
    $title =~ s!\s+! !g;
    $title =~ s!^ !!;
    $title =~ s! $!!;
    
    my $meta_desc = '';
    my $h1 = '';
    if ($dom->at('head > meta[name="description"]')) {
        $meta_desc = $dom->at('head > meta[name="description"]')->{'content'};
    }
    
    if ($dom->at('h1')) {
        $h1 = $dom->at('h1')->all_text;
    }
  
    # Turn back into DOM object to retrieve text
    my $clean_content = $dom->all_text;
    $clean_content =~ s![<>]!!g;
    $clean_content =~ s!\s+! !gs;

    # url crawled successfully
    _crawl_ok($id);

    my $result = $es->update(
        index => 'bkmrx',
        type => 'url',
        id => $id,
        body => {
            script => "ctx._source.crawled = 1; 
                ctx._source.content = content; 
                ctx._source.page_title = title;
                ctx._source.meta_description = desc;
                ctx._source.tag_h1 = h1;
                ctx._source.domain = domain;",
            params => { 
                content => $clean_content, 
                title => $plugin->_clean_text($title),
                h1 => $plugin->_clean_text($h1),
                desc => $plugin->_clean_text($meta_desc),
                domain => $domain,
            }
        }
    );
    if ($debug == 1) {
        $log->info(Dumper($result));
    }

    return;
}


sub _crawl_checkout {
    my $id = shift;
    # say $id;
    # checking out URL for crawling
    my $result = $es->update(
        index => 'bkmrx',
        type => 'url',
        id => $id,
        body => {
            # NOTE = DEPRECATED IN ES >= 1.3
            script => "ctx._source.crawled = 2",
        }
    );
}

sub _crawl_ok {
    my $id = shift;
    # url crawled successfully
    my $result = $es->update(
        index => 'bkmrx',
        type => 'url',
        id => $id,
        body => {
            # NOTE = DEPRECATED IN ES >= 1.3
            script => "ctx._source.crawled = 1; ctx._source.status = 'ok'; ctx._source.crawled_date = now;",
            params => {
                now => time(),
            }
        }
    );
}

sub _crawl_fail {
    my $id = shift;
    my $http_status = shift;
    # url crawled unsuccessfully
    my $result = $es->update(
        index => 'bkmrx',
        type => 'url',
        id => $id,
        body => {
            # NOTE = DEPRECATED IN ES >= 1.3 - SCRIPTS GET MORE COMPLICATED
            script => "ctx._source.crawled = 3; ctx._source.status = http_status; ctx._source.crawled_date = now;",
            params => {
                now => time(),
                http_status => $http_status,
            }
        }
    );
}



__DATA__
Based on code from:
http://blogs.perl.org/users/stas/2013/01/web-scraping-with-modern-perl-part-1.html