package BkxMojo::Crud;
use Mojo::Base 'Mojolicious::Controller';
use Data::Dumper;
use Digest::SHA1 qw(sha1_hex);
use Mojo::Log;
my $log = Mojo::Log->new;
# insert info into DB
sub add_bkmrk {
	my $self = shift;

	my $url     = $self->param('url');
	my $title   = $self->param('title')  || '[[blank]]';
	my $desc    = $self->param('desc')   || '';
	# default to private bkmrk if not specified
	my $privacy  = $self->param('privacy') || 0;
	my $from  = $self->param('from') || '';
	my @tags    = $self->param('tags[]');
	my $user_id = $self->session('user_id');

	my $doc = $self->add_bookmark({
		url => $url,
		title => $title,
		desc => $desc,
		privacy => $privacy,
		from => $from,
		tags => \@tags,
		user_id => $user_id
	});

	my $referrer = Mojo::URL->new($self->tx->req->headers->referrer)->path;

	# close the wondow using JS if the save request is from the bookmarklet
	return $self->render(template => 'addons/success') 
		if $referrer eq '/bklet';

	# if referrer != bklet, redirect
	$self->flash( added => $doc->{'_id'} );

	# redirect
	$self->res->code(303);
	$self->redirect_to('/bkmrx?id=' . $doc->{'_id'});
}

sub update_user {
	my $self = shift;

	my $name     	= $self->param('name') 		|| '';
	my $website  	= $self->param('website') 	|| '';
	my $email  		= $self->param('email') 	|| '';
	my $github  	= $self->param('github') 	|| '';
	my $twitter  	= $self->param('twitter') 	|| '';
	my $google_plus	= $self->param('google_plus') 	|| '';
	my $amazon_wishlist = $self->param('amazon_wishlist') || '';
	my $reddit = $self->param('reddit') || '';
	my $hacker_news = $self->param('hacker_news') || '';

	if ($email !~ m{.+\@.+}) {
		$self->flash( msg => 'Error updating email!' );
		return $self->redirect_to('/me/');
	}

	# sanitise
	$twitter =~ s!^\@!!;
	$google_plus =~ s!^\+!!;

	my $es = $self->es;

	my $user_id    = $self->session('user_id');

	my $res = $es->update(
		index => 'bkmrx',
		type => 'users',
		id => $user_id,
		body => {
			doc => {
				name   	 => $name,
				website => $website,
				email => $email,
				social => {
					github   => $github, 
					twitter  => $twitter,
					google_plus  => $google_plus,
					amazon_wishlist => $amazon_wishlist,
					reddit => $reddit,
					hacker_news => $hacker_news,
				}
			}
		}
	);

	$self->flash( msg => 'Profile updated!<br><br><b>Please note:</b> any social profiles added may take up to 24 hours to show in your bookmarks');

	# redirect
	$self->redirect_to('/me/');
}


# register user
sub register {
	my $self = shift;

	my $username = lc $self->param('username');
	$username =~ s![^a-z0-9_]!!g;
	my $email    = $self->param('email');
	my $pass     = $self->param('pass');
	my $pass2    = $self->param('pass2');

	if ($pass !~ m{^$pass2$}) {
		$self->flash(error => "passwords don't match!");
		return $self->redirect_to('/login');
	}

	unless ($username =~ m{[a-z0-9_]+}) {
		$self->flash(error => "Please choose a valid username!");
		return $self->redirect_to('/login');
	}

	my $es    = $self->es;

	# search to see if username is unique before inserting
	my $un_exists = $es->count(
		index => 'bkmrx',
		type => 'users',
		body => {
			query => {
				match => {
					username => $username
				}
			}
		}
	);
	my $email_exists = $es->count(
		index => 'bkmrx',
		type => 'users',
		body => {
			query => {
				match => {
					email => $email
				}
			}
		}
	);
	if ($un_exists->{'count'} > 0) {
		$self->flash(error => "username already exists - please try again");
		return $self->redirect_to('/login');
	} elsif ($email_exists->{'count'} > 0) {
		$self->flash(error => "email already exists - please try again");
		return $self->redirect_to('/login');
	}

	my $user_id = $es->index(
		index => 'bkmrx',
		type => 'users',
		body => {
			username => $username,
			email => $email,
			pass => $self->bcrypt($pass),
			joined => (time() * 1000),
			logged_in => time(),
			login => {
				service => 'bkmrx',
			},
			fail_count => 0,
		}
	);

	$self->session( user_id => $user_id->{'_id'} );
	$self->session( username => $username );

	$self->redirect_to('/me/');
}

# register from a service
sub register_service {
	my $self = shift;

	my $account_info = $self->session('account_info');

	my $es    = $self->es;
	
	# give option to choose username or use twitter one (as long as it's available)
	my $id = $account_info->{'id'} || '';

	# search to see if user exists
	my $user_exists = $es->search(
		index => 'bkmrx',
		type => 'users',
		body => {
			query => {
				filtered => {
					filter => {
						and => [
							{ term => {"login.service" => $account_info->{'service'}} },
							{ term => {"login.id" => $id } },
						]
					}
				}
			}
		}
	);
	
	if ($user_exists->{'hits'}->{'total'} > 0) {
		my $doc = $user_exists->{'hits'}->{'hits'}->[0];

		$self->session( user_id => $doc->{'_id'} );
		$self->session( username => $doc->{'_source'}->{'username'} );
		return $self->redirect_to('/');
	}

	else {
		return $self->render(template => 'auth/register_details');
	}
}

# register from a service
sub register_full {
	my $self = shift;

	my $account_info = $self->session('account_info');
	my $username = lc $self->param('username');
	$username =~ s![^a-z0-9_]!!g;

	unless ($username =~ m{[a-z0-9_]+}) {
		$self->flash(error => "Please choose a valid username!");
		return $self->redirect_to('/login');
	}

	my $es    = $self->es;

	# give option to choose username or use twitter one (as long as it's available)
	# search to see if username is unique before inserting
	my $user_exists = $es->search(
		index => 'bkmrx',
		type => 'users',
		body => {
			query => {
				match => { 
					username => $username
				}
			}
		}
	);
	
	if ($user_exists->{'hits'}->{'total'} > 0) {
		$self->flash(error => "username already exists - please try again");
		
		return $self->redirect_to('/login');
	}

	if (!$username) {
		$self->flash(error => "Please specify a username and try again");
		
		return $self->redirect_to('/login');
	}

	my $user_id = $es->index(
		index => 'bkmrx',
		type => 'users',
		body => {
			username => $username,
			joined => (time() * 1000),
			logged_in => time(),
			login => $account_info,
			fail_count => 0,
		}
	);

	$self->session( user_id => $user_id->{'_id'} );
	$self->session( username => $username );

	$self->redirect_to('/bkmrx');
}


# remove tag from all bookmarks
sub remove_tags {
	my $self  = shift;
	my $tag   = $self->param('tag') || '';
	
	my $user_id = $self->session('user_id');
	if ($tag) {

		my $es = $self->es;

		# stuff goes here

		$self->flash(msg => "Tag '$tag' removed from all bookmarks!");
		return $self->redirect_to($self->tx->req->headers->referrer);
	}
	$self->flash(msg => "Error: no tag provided!");
	$self->redirect_to($self->tx->req->headers->referrer);
}

# remove from a single bookmark
sub remove_tag {
	my $self  = shift;
	my $tag   = $self->param('tag')  || '';
	my $b_id = $self->param('b_id');
	my $url_id = $self->param('url_id');
	
	# $log->info(Dumper($self->param()));
	# $log->info($url_id);
	if ($tag) {
		my $es = $self->es;
        my $result = $es->update(
            index => 'bkmrx',
            type => 'bookmark',
            id => $b_id,
            parent => $url_id,
            body => {
                script => "ctx._source.tags.remove(tag)",
                params => { tag => $tag }
            }
        );
        # $log->info(Dumper($result));

		return $self->render( json => {status => 'ok'} );
	}
	$self->redirect_to($self->tx->req->headers->referrer);
}

# update a bookmark
sub update_bkmrk {
	my $self  = shift;
	my $b_id  = $self->param('id')    || '';
	my $title = $self->param('title') || '';
	my $desc  = $self->param('desc')  || '';
	my $url_id = $b_id;
	$url_id =~ s!^[^_]+__!!;
	$b_id   =~ s!__.*$!!;
	$url_id =~ s!^d_!!;

	if ($b_id) {
		$b_id =~ s!^\w_!!;
		my $es = $self->es;
		my $result;
		if ($title ne '') {
			$result = $es->update(
	            index => 'bkmrx',
	            type => 'bookmark',
	            id => $b_id,
	            parent => $url_id,
	            body => {
	                script => "ctx._source.user_title = user_title",
	                params => { user_title => $title }
	            }
	        );
	        $self->render(text => $title);
		} elsif ($desc ne '') {
			$result = $es->update(
	            index => 'bkmrx',
	            type => 'bookmark',
	            id => $b_id,
	            parent => $url_id,
	            body => {
	                script => "ctx._source.user_description = page_desc",
	                params => { page_desc => $desc }
	            }
	        );
	        $self->render(text => $desc);
		}

	} else {
		$self->render( exception => 'Error: No bookmark ID passed!' );
	}
}

# delete a bookmark
sub delete_bkmrk {
	my $self  = shift;
	my $b_id  = $self->param('b_id')  || '';

	if ($b_id) {
		$b_id =~ s!^\w_!!;
		my $es = $self->es;
		# may want to add in some kind of verification to stop possibility
		# of users deleting others' bookmarks somehow
		# ie hash self->session(user_id) w/ URL and see if that matches
		# the ID passed - if not, fail
		$es->delete(
	            index => 'bkmrx',
	            type => 'bookmark',
	            id => $b_id,
	            );
		$self->render( text => 'ok');
	} else {
		$self->render( exception => 'Error: No bookmark ID passed!');
	}
}

# delete all bookmarks
sub delete_bkmrk_all {
	my $self  = shift;


	my $es = $self->es;

	my $result = $es->delete_by_query(
		index => 'bkmrx',
	    body  => {
	    	query => {
    			user_id   => $self->session('user_id'),
	    	}
	    }
	);

	return $self->render( text => Dumper($result) );
	
	$self->reply->exception('Error: No bookmark ID passed!');
}

# public/private bookmark
sub lock_unlock {
	my $self  = shift;
	my $b_id  = $self->param('b_id')  || '';
	my $action = $self->param('action') || '';

	my $url_id = $b_id;
	$url_id =~ s!^[^_]+__!!;
	$b_id   =~ s!__.*$!!;

	if ($action eq 'lock') {
		$action = 1;
	} else {
		$action = 0;
	}

	if ($b_id) {
		my $es = $self->es;
		
		my $res = $es->update(
			index => 'bkmrx',
			type=> 'bookmark',
			id => $b_id,
			parent => $url_id,
			body => {
				doc => {
					private => $action
				}
			}
		);
		return $self->render( json => {status => 'ok'});
	}
	
	$self->reply->exception('Error: No bookmark ID passed!');
}


1;
