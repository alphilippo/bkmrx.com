#!/usr/bin/env perl
use strict;
use Net::Twitter;
use Scalar::Util 'blessed';
use Search::Elasticsearch;
use WWW::Mechanize;
use Date::Manip;
use Digest::SHA1 qw(sha1_hex);
use DateTime;
use Mojo::Home;

my ($lib_dir, $conf_dir);
BEGIN {
    my $home = Mojo::Home->new;
    $home->detect;
    $lib_dir = $home->rel_dir('../lib');
    $conf_dir = $home->rel_dir('../');
}

use lib $lib_dir;
use BkxMojo::Plugin::Bkmrx;

my $plugin = BkxMojo::Plugin::Bkmrx->new;

my $config = &_parse($conf_dir . "/news_check.conf");


exit unless $config->{'twitter'}->{'consumer_key'} ne '';

# As of 13-Aug-2010, Twitter requires OAuth for authenticated requests
my $nt = Net::Twitter->new(
    traits   => [qw/OAuth API::RESTv1_1/],
    consumer_key        => $config->{'twitter'}->{'consumer_key'},
    consumer_secret     => $config->{'twitter'}->{'consumer_secret'},
    access_token        => $config->{'twitter'}->{'token'},
    access_token_secret => $config->{'twitter'}->{'token_secret'},
    ssl => 1,
);

my %months = qw(jan 1 feb 2 mar 3 apr 4 may 5 jun 6 jul 7 aug 8 sep 9 oct 10 nov 11 dec 12);

my $es = Search::Elasticsearch->new(
    nodes      => '127.0.0.1:9200'
);

my $res = $es->search(
    index => 'bkmrx',
    type => 'users',
    body => {
        query => {
            regexp => {
                'social.twitter' => '.+'
            }
        }
    }
);

for my $doc (@{$res->{'hits'}->{'hits'}}) {
    my $now = DateTime->now(time_zone => 'Europe/London');
    next unless $doc->{'_source'}->{'logged_in'};
    my $last_in = DateTime->from_epoch( epoch => $doc->{'_source'}->{'logged_in'}, time_zone => 'Europe/London' );
    my $dt_diff = $now - $last_in;

    # don't process if user hasn't logged in in 2 months
    next if $dt_diff->days > 60;

    my $screen_name = $doc->{'_source'}->{'social'}->{'twitter'};
    my $since_id    = $doc->{'_source'}->{'twitter_since'} || undef;
    my $user_id     = $doc->{'_id'};
    
    #user_timeline
    #Parameters: id, user_id, screen_name, since_id, max_id, count, page, skip_user, trim_user, include_entities, include_rts
    my $statuses;
    my %params = (
                    include_entities => 'true', 
                    include_rts => 'true', 
                    screen_name => $screen_name, 
                    count => 50
                  );
        
    if (defined($since_id)) {
        $params{'since_id'} = $since_id;
    }
    
    eval { $statuses = $nt->user_timeline(\%params); };
        
    if ( my $err = $@ ) {
        die $@ unless blessed $err && $err->isa('Net::Twitter::Error');
    
        warn "HTTP Response Code: ", $err->code, "\n",
        "HTTP Message......: ", $err->message, "\n",
        "Twitter error.....: ", $err->error, "\n";
    }
        
    my @since_ids;
        
    for my $status ( @$statuses ) {
        my $created_at       = $status->{'created_at'};
        my $user_screen_name = $status->{'user'}{'screen_name'};
        my $status_text      = $status->{'text'};
        my $hashtags         = $status->{'entities'}{'hashtags'};
        my $tweet_id         = $status->{'id'};
        my $urls             = $status->{'entities'}{'urls'};
            
        # add id to array so we can track which the last tweet we fetched was
        push @since_ids, $tweet_id;
        
        # reformat date for DB
        my $dm = new Date::Manip::Date;
        my $err = $dm->parse($created_at);
        my $unix = $dm->printf('%s');
        
        if (scalar(@$urls) > 0) {
            foreach my $u (@$urls) {
                # although unlikely to be a t.co url could well be another shortened url
                # so let's fetch & insert longer url instead
                my $t_url = $u->{'expanded_url'};
                my ($t_title, $t_desc);
                $t_url = $plugin->_clean_url($t_url);
                
                my $mech2 = WWW::Mechanize->new( autocheck => 0 );
                $mech2->get($t_url);
                
                if ($mech2->success) {
                    $t_url = $plugin->_clean_url($mech2->uri->as_string);
                    $t_title = $mech2->title || $t_url;
                } else {
                    # skip onto next url if this one doesn't resolve
                    next;
                }

                my @tags;

                if (scalar(@$hashtags) > 0) {
                    foreach my $h (@$hashtags) {
                        my $tag = lc $h->{'text'};
                        $tag =~ s![^-a-z0-9]!!g;
                        push(@tags, $tag);
                    }
                }

                my $doc_id = sha1_hex($user_id . $t_url);
                my $url_hex = sha1_hex($t_url);

                my $res = $es->create(
                    index => 'bkmrx',
                    type => 'url',
                    id => $url_hex,
                    ignore => [409],
                    body => {
                        url => $t_url,
                        crawled => 0,
                        added_by => $user_id,
                        votes => 1,
                    }
                );

                $res = $es->create(
                    index => 'bkmrx',
                    type => 'bookmark',
                    id => $doc_id,
                    ignore => [409],
                    parent => $url_hex,
                    body => {
                        user_id   => $user_id,
                        url => $t_url,
                        user_title => $plugin->_clean_text($t_title),
                        user_description => $plugin->_clean_text($status_text),
                        private => 0,
                        from => 'twitter',
                        tags => \@tags,
                        added     => ((int $unix) * 1000),
                    }
                );
            }
        }
    }
    @since_ids = sort { $b cmp $a } @since_ids;
    $es->update(
        index => 'bkmrx',
        type => 'users',
        id => $user_id,
        body => {
            doc => {
                twitter_since => $since_ids[0],
            }
        }
    );
}

# Bastardised Mojo Config file parser
sub _parse {
    my $file = shift;
    my $content = decode('UTF-8', slurp $file);

    my $config
        = eval 'package Mojolicious::Plugin::Config::Sandbox; no warnings;'
            . "use Mojo::Base -strict; $content";
    die qq{Couldn't load configuration from file "$file": $@} if !$config && $@;
    die qq{Config file "$file" did not return a hash reference.\n}
        unless ref $config eq 'HASH';

    return $config;
}