package BkxMojo::User;
use Mojo::Base 'Mojolicious::Controller';

use DateTime;
use Digest::MD5 qw(md5_hex);
use URI::Encode qw(uri_encode);
use String::Truncate qw(elide);
use Data::Dumper;
use Mojo::Log;
my $log = Mojo::Log->new;

# User page
sub profile {
	my $self = shift;

	my $es    = $self->es;

	my $res = $es->search(
		index => 'bkmrx',
		type => 'users',
		body => {
			query => {
				match => { 
					username => $self->stash('name') 
				}
			}
		}
	);
	my $count = $res->{'hits'}->{'total'};
	
	return $self->render_not_found() unless $count == 1;

	my $doc = $res->{'hits'}->{'hits'}->[0];

	my $size = 100;
	my $grav_url = "https://secure.gravatar.com/avatar/" . md5_hex( lc( $doc->{'_source'}->{'email'} ) ) . "?d=&s=" . $size;

	my $type;

	my $profile_id = $doc->{'_id'};

	if (($self->session('user_id')) && (($self->session('user_id') =~ m/^$profile_id$/))) {
		# the user is looking at their own profile
		$type = 'me';
	} elsif (($self->session('user_id')) && (($self->session('user_id') !~ m/^$profile_id$/))) {
		my $usr_res = $es->search(
			index => 'bkmrx',
			type => 'users',
			body => {
				query => {
					match => { 
						username => $self->session('username'),
						follows => $doc->{'_id'},
					}
				}
			}
		);
		my $usr_count = $usr_res->{'hits'}->{'total'};
		if ($usr_res == 0) {
			# the user is looking at another user they follow
			$type = 'friend';
		} else {
			# the user isn't following this person yet
			$type = 'stranger';
		}
	} else {
		# the user isn't logged in
		$type = 'viewer';
	}

	my $page_size = 10;
	my $offset = 0;

	my $es_query = {
		filtered => {
            filter => {
            	term => {
                    private => 0,
                }
            },
            query => {
                match => {
                   user_id => $profile_id
                }
            }
    	}
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
	    size => $page_size,
	    from => $offset,
	);

	my $total_results = $results->{'hits'}->{'total'};

	my (@bkx);

	for my $doc (@{ $results->{'hits'}->{'hits'} }) {
		my $url = $doc->{'_source'}->{'url'};
		my ($disp_url) = $url =~ m{^[hf]tt?ps?://(?:www\.)?(.*)$}i;
		$disp_url = elide($disp_url, 90);
		
		my $title = $doc->{'_source'}->{'user_title'};
		my $disp_title = elide($title, 55);

		my $dt = DateTime->from_epoch( epoch => $doc->{'_source'}->{'added'} );
		my $added = $dt->day . " " . $dt->month_abbr . " " . $dt->year;

		my $from_icon = '';
		if ($doc->{'_source'}->{'from'} eq 'twitter') {
			$from_icon = " <i class='fa fa-twitter'></i>";
		} elsif ($doc->{'_source'}->{'from'} eq 'github') {
			$from_icon = " <i class='fa fa-github'></i>";
		} elsif ($doc->{'_source'}->{'from'} eq 'google_plus') {
			$from_icon = " <i class='fa fa-google-plus'></i>";
		}

		push(@bkx, {
			b_id 	=> $doc->{'_id'},
			added 	=> $added,
			url 	=> $url,
			disp_url => $disp_url,
			title 	=> $title,
			disp_title => $disp_title,
			tags 	=> $doc->{'_source'}->{'tags'},
			status 	=> $doc->{'_source'}->{'private'},
			from => $doc->{'_source'}->{'from'},
			from_icon => $from_icon,
			});
	}

	$self->render( user => $doc, gravatar => $grav_url, type => $type, bkmrx => \@bkx );
}

# User page
sub tags {
	my $self = shift;

	my $es    = $self->es;

	my $res = $es->search(
		index => 'bkmrx',
		type => 'users',
		body => {
			query => {
				match => { 
					username => $self->stash('name') 
				}
			}
		}
	);
	my $count = $res->{'hits'}->{'total'};
	
	return $self->render_not_found() unless $count == 1;

	my $doc = $res->{'hits'}->{'hits'}->[0];

	my $size = 100;
	my $grav_url = "https://secure.gravatar.com/avatar/" . md5_hex( lc( $doc->{'_source'}->{'email'} ) ) . "?d=&s=" . $size;

	my $type;

	my $profile_id = $doc->{'_id'};

	if (($self->session('user_id')) && (($self->session('user_id') =~ m/^$profile_id$/))) {
		# the user is looking at their own profile
		$type = 'me';
	} elsif (($self->session('user_id')) && (($self->session('user_id') !~ m/^$profile_id$/))) {
		my $usr_res = $es->search(
			index => 'bkmrx',
			type => 'users',
			body => {
				query => {
					match => { 
						username => $self->session('username'),
						follows => $doc->{'_id'},
					}
				}
			}
		);
		my $usr_count = $usr_res->{'hits'}->{'total'};
		if ($usr_res == 0) {
			# the user is looking at another user they follow
			$type = 'friend';
		} else {
			# the user isn't following this person yet
			$type = 'stranger';
		}
	} else {
		# the user isn't logged in
		$type = 'viewer';
	}

	my $page_size = 10;
	my $offset = 0;

	my $es_query = {
		filtered => {
            filter => {
            	bool => {
            		must => {
        				term => {
        					tags => $self->stash("tag")
        				}
        			},
        			must_not => {
        				term => {
	                    	private => 1,
	                	}
        			},
            	}
            },
            query => {
                match => {
                   user_id => $profile_id
                }
            }
    	}
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
	    size => $page_size,
	    from => $offset,
	);

	my $total_results = $results->{'hits'}->{'total'};

	my (@bkx);

	for my $doc (@{ $results->{'hits'}->{'hits'} }) {
		my $url = $doc->{'_source'}->{'url'};
		my ($disp_url) = $url =~ m{^[hf]tt?ps?://(?:www\.)?(.*)$}i;
		$disp_url = elide($disp_url, 60);
		
		my $title = $doc->{'_source'}->{'user_title'};
		my $disp_title = elide($title, 55);

		my $dt = DateTime->from_epoch( epoch => $doc->{'_source'}->{'added'} );
		my $added = $dt->day . " " . $dt->month_abbr . " " . $dt->year;

		my $from_icon = '';
		if ($doc->{'_source'}->{'from'} eq 'twitter') {
			$from_icon = " <i class='fa fa-twitter'></i>";
		} elsif ($doc->{'_source'}->{'from'} eq 'github') {
			$from_icon = " <i class='fa fa-github'></i>";
		} elsif ($doc->{'_source'}->{'from'} eq 'google_plus') {
			$from_icon = " <i class='fa fa-google-plus'></i>";
		}

		push(@bkx, {
			b_id 	=> $doc->{'_id'},
			added 	=> $added,
			url 	=> $url,
			disp_url => $disp_url,
			title 	=> $title,
			disp_title => $disp_title,
			tags 	=> $doc->{'_source'}->{'tags'},
			status 	=> $doc->{'_source'}->{'private'},
			from => $doc->{'_source'}->{'from'},
			from_icon => $from_icon,
		});
	}

	$self->render( user => $doc, gravatar => $grav_url, type => $type, bkmrx => \@bkx );
}

sub json {
	my $self = shift;

	my $page_size = $self->param('num') || 50;
	my $offset = $self->param('from') || 0;
	if ($page_size > 500) {
		$page_size = 500;
	}

	my $es    = $self->es;

	my $res = $es->search(
		index => 'bkmrx',
		type => 'users',
		body => {
			query => {
				match => { 
					username => $self->stash('name') 
				}
			}
		}
	);

	my $count = $res->{'hits'}->{'total'};
	
	return $self->render_not_found() unless $count == 1;

	my $doc = $res->{'hits'}->{'hits'}->[0];

	my $profile_id = $doc->{'_id'};

	my $es_query = {
		filtered => {
            filter => {
            	term => {
                    private => 0,
                }
            },
            query => {
                match => {
                   user_id => $profile_id
                }
            }
    	}
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
	    size => $page_size,
	    from => $offset,
	);

	my $total_results = $results->{'hits'}->{'total'};

	my (@bkx);

	for my $doc (@{ $results->{'hits'}->{'hits'} }) {
		push(@bkx, {
			added 	=> $doc->{'_source'}->{'added'},
			url 	=> $doc->{'_source'}->{'url'},
			tags 	=> $doc->{'_source'}->{'tags'},
			}
		);
	}

	$self->render( json => \@bkx );
}


1;
