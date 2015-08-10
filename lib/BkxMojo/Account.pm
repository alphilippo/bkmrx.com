package BkxMojo::Account;
use Mojo::Base 'Mojolicious::Controller';

use BkxMojo::Crud;
use DateTime;
use String::Truncate qw(elide);
use List::MoreUtils qw(uniq);
use Digest::MD5 qw(md5_hex);
use Digest::SHA1 qw(sha1_hex);
use List::Util qw( max min );
use Data::Random qw(rand_chars rand_words);

use Data::Dumper;
use Mojo::Log;

my $log = Mojo::Log->new;

# Standard account dashboard
sub account {
	my $self = shift;

	my $es	  = $self->es;

	my %user_details;

	my $doc = $es->get(
		index => 'bkmrx',
		type => 'users',
		id => $self->session('user_id')
	);
	if ($doc->{'found'}) {
		$user_details{'email'}    = $doc->{'_source'}->{'email'};
		$user_details{'name'}     = $doc->{'_source'}->{'name'};
		$user_details{'website'}  = $doc->{'_source'}->{'website'};
		$user_details{'twitter'}  = $doc->{'_source'}->{'social'}->{'twitter'};
		$user_details{'github'}   = $doc->{'_source'}->{'social'}->{'github'};
		$user_details{'google_plus'}   = $doc->{'_source'}->{'social'}->{'google_plus'};
		$user_details{'amazon_wishlist'}   = $doc->{'_source'}->{'social'}->{'amazon_wishlist'};
		$user_details{'hacker_news'}   = $doc->{'_source'}->{'social'}->{'hacker_news'};
		$user_details{'reddit'}   = $doc->{'_source'}->{'social'}->{'reddit'};
		$user_details{'gravatar'} = "https://secure.gravatar.com/avatar/" . md5_hex( lc( $doc->{'_source'}->{'email'} ) ) . "?d=&s=40";

	} else {
		return $self->reply->exception("user not found");
	}

	$self->render(user_details => \%user_details);
}

# import bkmrx
sub import {
	my $self = shift;

	$self->render( );
}

# edit tags
sub edit_tags {
	my $self = shift;

	my $offset 	= $self->param('offset') || 0;
	my $tag 	= $self->stash('tag');
	my $type 	= $self->param('type');
	my $page_size = 10;

	my $user_id = $self->session('user_id');

    my $es = $self->es;
    my $results = $es->search(
        index => 'bkmrx',
        type => 'bookmark',
        body  => {
            query => { 
            	match => {
            		user_id => $user_id,
            	} 
            },
            aggs => {
            	tag_agg => {
            		terms => {
            			field => "tags",
            			order => { _count => "desc" },
            			
            		},
            	},
            },
        },
        size => $page_size,
        from => $offset,
    );
    # $log->info(Dumper($results));
    my $total_results = $results->{'facets'}->{'tags'}->{'other'} + $page_size;

    my @tags;
    for my $doc (@{ $results->{'aggregations'}->{'tag_agg'}->{'buckets'} }) {
    	push @tags, { tag => $doc->{'key'}, count => $doc->{'doc_count'} };
    }

    my $last_result  = min( ( $offset + $page_size ), $total_results );
	my $first_result = min( ( $offset + 1 ), $last_result );

	my $req_path = $self->req->url->path;

	$self->render( 
		tags => \@tags,
		first_result => $first_result,
		last_result => $last_result,
		total_results => $total_results, 
		pages => $self->paginate($total_results, $offset, $page_size, $req_path) );
}

# main bkmrx page
sub my_bkmrx {
	my $self = shift;

	my $offset 	     = $self->param('offset') || 0;
	my $query_tag 	 = $self->param('tag') 	  || '';
	my $query_from   = $self->param('from') || '';
	my $user_id      = $self->session('user_id');
	my $page_size 	 = 10;

	my $es = $self->es;

	my @tags = split(/\|/, $query_tag);
	
	my $es_query = {
	    match => { 
	    	user_id => $user_id,
	    },
	};

	if ($query_tag && $query_from) {
		$es_query = {
			filtered => {
	            filter => {
                	and => [
	                    { terms => { tags    => \@tags, execution => 'and' } },
	                    { term  => { from    => $query_from } },
	                    { term  => { user_id => $user_id} },
	                ]
	            },
        	}
    	};
	} elsif ($query_tag) {
		$es_query = {
			filtered => {
	            filter => {
                	and => [
	                    { terms => { tags => \@tags, execution => 'and' } },
	                    { term  => { user_id => $user_id } }
	                ]
	            }
        	}
    	};
	} elsif ($query_from) {
		$es_query = {
			filtered => {
	            filter => {
                	and => [
	                    { term => { from => $query_from } },
	                    { term => { user_id => $user_id } }
	                ]
	            }
        	}
    	};
	}

	$log->info(Dumper($es_query));
	
	my $results = $es->search(
	    index => 'bkmrx',
	    type => 'bookmark',
	    body  => {
	    	query => $es_query,
	    	sort => [{
		    	added => "desc",
			}],
	    },
	    size => $page_size,
	    from => $offset,
	);

	$log->info(Dumper($results));

	my $total_results = $results->{'hits'}->{'total'};

	my (@bkx, @dates);

	for my $doc (@{ $results->{'hits'}->{'hits'} }) {

		my $url = $doc->{'_source'}->{'url'};
		my ($disp_url) = $url =~ m{^[hf]tt?ps?://(?:www\.)?(.*)$}i;
		$disp_url = elide($disp_url, 90);
		my $title = $doc->{'_source'}->{'user_title'};
		my $disp_title = elide($title, 55);

		my $desc = $doc->{'_source'}->{'user_description'} || '';

		my $dt = DateTime->from_epoch( epoch => ($doc->{'_source'}->{'added'} / 1000) );
		my $added = $dt->day . " " . $dt->month_abbr . " " . $dt->year;

		push(@bkx, {
			b_id 	=> $doc->{'_id'},
			added 	=> $added,
			url 	=> $url,
			url_id 	=> sha1_hex($url),
			disp_url => $disp_url,
			title 	=> $title,
			disp_title => $disp_title,
			tags 	=> $doc->{'_source'}->{'tags'},
			status 	=> $doc->{'_source'}->{'private'},
			desc 	=> $desc,
			from => $doc->{'_source'}->{'from'},
		});
		push(@dates, $added);
	}
	
	my @uniq_dates = uniq @dates;

	my $last_result  = min( ( $offset + $page_size ), $total_results );
	my $first_result = min( ( $offset + 1 ), $last_result );

	my $req_path = $self->req->url->path;

	my $heading = 'my bkmrx';
	if ($query_from eq 'twitter') {
		$heading = '<i class="fa fa-twitter"></i> your tweets';
	} elsif ($query_from eq 'github') {
		$heading = '<i class="fa fa-github"></i> your repos';
	}

	my %params = ( tag => $query_tag, from => $query_from );

	$self->render(
		first_result => $first_result, 
		last_result => $last_result, 
		total_results => $total_results,
		pages => $self->paginate($total_results, $offset, $page_size, $req_path, \%params),
		bkmrx => \@bkx,
		dates => \@uniq_dates,
		heading => $heading,
		from => $query_from,
		tags => \@tags,
	);
}

# addons page
sub addons {
	my $self = shift;

	# alter bookmarklet based on host
	my $host = $self->req->url->base->host;
	my $port = $self->req->url->base->port;
	if ($port != 80 || $port != 443) {
		$port = ":$port";
	} else {
		$port = "";
	}
	$self->render( host => $host, port => $port );
}

sub bklet {
	my $self = shift;

	return $self->redirect_to('/login') unless $self->session('username');

	my $title   = $self->param('title');
	my $url     = $self->param('url');
	my $from  = $self->param('from');
	my $user_id = $self->session('user_id');

	my $es = $self->es;

	my $doc_id = sha1_hex($user_id . $url);

	my $res = $es->exists(
		index => 'bkmrx',
		type => 'bookmark',
        id => $doc_id,
        parent => sha1_hex($url),
	);

	my $dupe = '';
	if ($res == 1) {
		$dupe = 'URL already bookmarked!';
	}

	$self->render( display_url => elide($url, 60), dupe => $dupe );
}

sub backup {
	my $self = shift;

	$self->render();
}

1;