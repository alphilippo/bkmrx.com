package BkxMojo::Functions;
use Mojo::Base 'Mojolicious::Controller';

use WWW::Mechanize;
use HTML::TreeBuilder::XPath;
use HTML::Entities;
use Mojo::DOM;
use Search::Elasticsearch::Bulk;
use Mojo::Log;
use Data::Dumper;
use Digest::SHA1 qw(sha1_hex);

my $log = Mojo::Log->new;

sub fetch_url {
	my $self = shift;

	my $url = $self->clean_url($self->param("url"));
	
	unless ($self->valid_uri($url)) {
		return $self->render( json => { 
			title => '[[unknown]]', 
			metad => '', 
			metak => '', 
			url => _rm_quotes($url),
			orig_url => _rm_quotes($url),
			status => 'error' 
		});
	}

	my $mech = WWW::Mechanize->new( autocheck => 0 );
	$mech->timeout(2);
	# may want a short timeout; if no return, just return default values based on the URL?
	$mech->get($url);

	if ($mech->success) {
		my $content = $mech->content;
		my $tree = HTML::TreeBuilder::XPath->new;
		$tree->parse_content($content);

		my $title  = $tree->findvalue(q{//title});
		my $meta_d = $tree->findvalue(q{//meta[@name="description"]/@content});
		my $meta_k = $tree->findvalue(q{//meta[@name="keywords"]/@content});
		# sending back returned URL for now; given 302s exist, perhaps it's wise
		# to add a feature that has an option to override this behaviour
		my $uri = $mech->uri->as_string;

		return $self->render( json => { 
			title => $title, 
			metad => $meta_d,
			metak => _escape($meta_k), 
			url => $uri,
			orig_url => $url,
			status => 'ok' } );
	} else {
		# May want to allow users to add invalid URLs (must still be a URL)?
		return $self->render( json => { 
			title => 'Error: URL Not Found', 
			metad => '', 
			metak => '', 
			url => _rm_quotes($url),
			orig_url => _rm_quotes($url),
			status => 'ok' } );
	}
}

# Import bookmarks form Firefox HTML export
sub import_ffx {
	my $self = shift;

	return $self->redirect_to('/me/import')
		unless my $upload = $self->req->upload('ffx');

	my $user_id = $self->session('user_id');

	my $file = $upload->slurp;
	# fix the funny formatting to something more parseable
	$file =~ s!<(/?)dl>!<$1ul>!igs;
	$file =~ s!<dt>!<li>!igs;
	$file =~ s!<dd>([^<]+)!<section>$1</section></li>!igs;

	# kill <p> tags
	$file =~ s!</?p>!!gis;

	## now use mojo dom
	my $dom = Mojo::DOM->new($file);

	my $li = $dom->find('ul ul li');
	my $li_count = @$li;
	if ($li_count < 1) {
		return $self->render_exception("no links found");
	}

	my @bkx;

	for my $l (@$li) {
		# in case of there being an li element with no a tag
		unless ($l->at('a')) {
			next;
		}
    
		my $title   = $l->at('a')->text;
		my $date    = $l->at('a')->{add_date};
		my $href    = $self->clean_url($l->at('a')->{href});
		my $tag     = $l->at('a')->{tags}    || '';
		my $private = $l->at('a')->{private} || 1;
		my $desc = '';
		if ($l->at('section')) {
			$desc    = $l->at('section')->text;
		}
    	
		# ignore firefox junk
		unless ($href =~ m{^https?://}i) {
			# don't count towards the total
			$li_count--;
			next;
		}

		# Insert tags
		my @new_tags;
		if (my @tags = split(/,| /,$tag)) {
			foreach my $t (@tags) {
				my $t_id;
				next if $t =~ m{^$};

				push(@new_tags, $self->clean_tag($t));
			}
		}

		push @bkx, {
			user_id   => $user_id,
			url => $href,
			title => $title,
			desc => $desc,
			private => int $private,
			from => 'firefox',
			tags => \@new_tags,
			added => int $date,
		};
	}

	my $insert = $self->add_bookmark_bulk(\@bkx);

	$self->flash(msg => "Success! $insert->{'insert_count'} bkmrx imported!");
	$self->redirect_to('/me/import');
}

# Import bookmarks from Delicious HTML export
sub import_delicious {
	my $self = shift;

	return $self->redirect_to('/me/import')
		unless my $upload = $self->req->upload('delicious');

	my $user_id = $self->session('user_id');

	my @bkx;

	my $file = $upload->slurp;
	# fix the funny formatting to something more parseable
	$file =~ s!<(/?)dl>!<$1ul>!igs;
	$file =~ s!<dt>!<li>!igs;
	$file =~ s!<dd>([^<]+)!<section>$1</section></li>!igs;

	# kill <p> tags etc
	$file =~ s!</?p>!!gis;

	## now use mojo dom
	my $dom = Mojo::DOM->new($file);

	my $li = $dom->find('li');
	my $li_count = @$li;

	for my $l (@$li) {
		my $title   = $l->at('a')->text;
		my $date    = $l->at('a')->{add_date};
		my $href    = $self->clean_url($l->at('a')->{href});
		my $tag     = $l->at('a')->{tags};
		my $private = $l->at('a')->{private};
		my $desc = '';

		next unless $href =~ m{^https?://}i;

		if ($l->at('section')) {
			$desc    = $l->at('section')->text;
		}

		# Insert tags
		my @new_tags;
		if (my @tags = split(/,| /,$tag)) {
			for my $t (@tags) {
				my $t_id;
				if ($t =~ m{^$}) {
					next;
				}
				push(@new_tags, $self->clean_tag($t));
			}
		}
		
		my $doc_id = sha1_hex($user_id . $href);
		my $url_hex = sha1_hex($href);

		push @bkx, {
			user_id   => $user_id,
			url => $href,
			title => $title,
			desc => $desc,
			private => int $private,
			from => 'delicious',
			tags => \@new_tags,
			added => int $date,
		};
	}
	
	my $insert = $self->add_bookmark_bulk(\@bkx);

	$self->flash(msg => "Success! $insert->{'insert_count'} bkmrx imported!");
	$self->redirect_to('/me/import');
}

sub backup_html {
	my $self = shift;

	my $es = $self->es;
	
	my $user_id    = $self->session('user_id');

	my $es_query = {
	    match => { 
	    	user_id => $user_id,
	    },
	};

	my $results = $es->search(
	    index => 'bkmrx',
	    type => 'bookmark',
	    body  => {
	    	query => $es_query,
	    	sort => [{
		    	added => "desc",
			}],
	    },
	);

	# AFAIK need to do 2 calls here to get full set of results
	my $total_results = $results->{'hits'}->{'total'};

	$results = $es->search(
	    index => 'bkmrx',
	    type => 'bookmark',
	    body  => {
	    	query => $es_query,
	    	sort => [{
		    	added => "desc",
			}],
	    },
	    size => $total_results,
	);

	my @bkx;

	for my $doc (@{ $results->{'hits'}->{'hits'} }) {
		my $tags = join(',', @{$doc->{'_source'}->{'tags'}});
		$tags =~ s!,$!!;
		push(@bkx, {
			added 	=> $doc->{'_source'}->{'added'},
			url 	=> $doc->{'_source'}->{'url'},
			title 	=> $doc->{'_source'}->{'user_title'},
			tags 	=> $tags,
			status 	=> $doc->{'_source'}->{'private'},
			desc 	=> $doc->{'_source'}->{'user_description'},
			});
	}

	# send as a download
	$self->tx->res->headers->header('content-type' => "text/html");
	$self->tx->res->headers->header('content-disposition' => "attachment; filename=bkmrx.html");

	$self->render( template => 'account/backup-html', bkmrx => \@bkx );
}

sub _rm_quotes {
    my $q = $_[0];
    $q =~ s!^"!!;
    $q =~ s!"$!!;
    return $q;
}

sub _escape {
    my $e = shift;
    return HTML::Entities::encode_numeric($e);
}

1;