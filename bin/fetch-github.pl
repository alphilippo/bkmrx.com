#!/usr/bin/env perl
use Modern::Perl;
use Mojo::UserAgent;
use HTML::TreeBuilder::XPath;
use HTML::Entities;
use JSON;
use Date::Manip;
use Date::Calc;
use Mojo::Log;
use Digest::SHA1 qw(sha1_hex);
use Search::Elasticsearch;
use Data::Dumper;
use DateTime;

my $log = Mojo::Log->new();

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
                'social.github' => '.+'
            }
        }
    }
);
# $log->info(Dumper($res));
for my $doc (@{$res->{'hits'}->{'hits'}}) {
    my $now = DateTime->now(time_zone => 'Europe/London');
    next unless $doc->{'_source'}->{'logged_in'};
    my $last_in = DateTime->from_epoch( epoch => $doc->{'_source'}->{'logged_in'}, time_zone => 'Europe/London' );
    my $dt_diff = $now - $last_in;

    # don't process if user hasn't logged in in 2 months
    next if $dt_diff->days > 60;
    
    next unless my $git_user = $doc->{'_source'}->{'social'}->{'github'};
    my $user_id  = $doc->{'_id'};
    
    my $url = 'https://github.com/' . $git_user . '.json';
    
    my $ua = Mojo::UserAgent->new;
    
    my $tx = $ua->get($url);
    
    if (my $res = $tx->success) {
        my $content = $res->body;
        
        my $parsed = from_json($content);
        
        foreach my $node (@$parsed) {
            
            my $g_url       = $node->{'url'};
            my $created_at  = $node->{'created_at'};
            my $type        = $node->{'type'};
            my $title       = $node->{'repository'}->{'description'};
            
            my $dm = new Date::Manip::Date;
            my $err = $dm->parse($created_at);
            my $unix = $dm->printf('%s');
            
            if ($type eq 'WatchEvent') {
                my $g_url_id;
                my $doc_id = sha1_hex($user_id . $g_url);
                my $url_hex = sha1_hex($g_url);

                # ignore is bad behaviour; need to check for error, then update
                # if already exists
                $es->create(
                    index => 'bkmrx',
                    type => 'url',
                    id => $url_hex,
                    ignore => [409],
                    body => {
                        url => $g_url,
                        crawled => 0,
                        # hex => sha1_hex($g_url),
                        added_by => $user_id,
                        votes => 1,
                    }
                );

                $es->create(
                    index => 'bkmrx',
                    type => 'bookmark',
                    id => $doc_id,
                    ignore => [409],
                    parent => $url_hex,
                    body => {
                        user_id   => $user_id,
                        url => $g_url,
                        user_title => $title,
                        private => 0,
                        from => 'github',
                        added     => ((int $unix) * 1000),
                        tags => ['github']
                    }
                );
        	} else {
        	    next;
        	}    
        }
    } else {
        my ($err, $code) = $tx->error;
        $log->error("$url error: $err - $code");
    }
}
