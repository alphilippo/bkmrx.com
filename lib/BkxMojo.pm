package BkxMojo;
use Mojo::Base 'Mojolicious';
use Search::Elasticsearch;
use Mojolicious::Plugin::Config;
use Mojolicious::Plugin::Bcrypt;
use URI::Escape qw(uri_escape uri_escape_utf8);
use Mojolicious::Plugin::Web::Auth;
use Mojolicious::Plugin::AssetPack;
use Data::Dumper;
use Mojo::Log;
use DateTime;
my $log = Mojo::Log->new;

sub startup {
	my $self = shift;

	# set defaults
	$self->secrets(['examplesecret']);
	$self->sessions->default_expiration(28800);
	# for secure
	# $self->sessions->secure(1);

	my $asset = $self->plugin('AssetPack' => {
		minify => 1,
		});

	$self->asset('js-foot.js' => '/js/bkx-js-foot.js');
	$self->asset('app.css' => '/css/bkx-styles.css');

	# Helpers.. #

	# Initialise config file
	my $config = $self->plugin('Config');
	# $self->plugin('PODRenderer');
	# Initialise password crypt
	$self->plugin('bcrypt', { cost => 6 });
	# common functions
	$self->plugin('BkxMojo::Plugin::Bkmrx');

	$self->plugin('BkxMojo::Plugin::Crud');

	# elasticsearch
	$self->attr( es => sub { 
		Search::Elasticsearch->new(
		    nodes      => $config->{es_host},  # default '127.0.0.1:9200'
	    );
	});
	$self->helper('es' => sub { shift->app->es });

	# Routing #
	my $r = $self->routes;

	# Normal route to controller
	$r->get('/')->to('core#welcome');
	$r->get('/about')->to('core#about');
	$r->get('/contact-us')->to('core#contact');
	$r->get('/privacy')->to('core#privacy');
	$r->get('/tos')->to('core#tos');
	$r->get('/faqs')->to('core#faqs');
	$r->get('/bot')->to('core#bot');

	# Login functions
	$r->get('/login')->to( 'auth#login', user_id => '' );
	$r->get('/forgot')->to( 'auth#forgot', user_id => '' );
	$r->get('/_checkname')->to( 'ajax#checkname');
	$r->post('/forgot')->to( 'auth#verify_reset' );
	$r->get('/reset')->to( 'auth#reset_form', user_id => '' );
	$r->post('/reset')->to( 'auth#reset', user_id => '' );
	$r->get('/register_service')->to( 'crud#register_service' );

	$r->get('/register-details')->to( 'auth#register_details' );
	$r->post('/register-details')->to( 'crud#register_full' );


	$self->plugin('Web::Auth', {
		module      => 'Twitter',
		key         => $config->{'twitter_sso'}->{'key'},
		secret      => $config->{'twitter_sso'}->{'secret'},
		on_finished => sub {
			my ( $c, $access_token, $access_secret, $account_info ) = @_;
			$c->session('access_token'  => $access_token);
	        $c->session('access_secret' => $access_secret);
	        $c->session('account_info'  => { 
	        	screen_name => $account_info->{screen_name},
	        	service => 'twitter',
	        	name => $account_info->{name},
	        	id => $account_info->{id},
	        	entities => $account_info->{entities},
	        });
	        return $c->redirect_to('/register_service');
		},
	});

	# must enable Google+ API service for this to work
	$self->plugin('Web::Auth', {
		module      => 'Google',
		key         => $config->{'google_sso'}->{'key'},
		secret      => $config->{'google_sso'}->{'secret'},
		on_finished => sub {
			my ( $c, $access_token, $account_info ) = @_;
			$c->session('access_token'  => $access_token);
	        $c->session('account_info'  => { 
	        	account => $account_info,
	        	name => $account_info->{'account'}->{'displayName'},
	        	id => $account_info->{'account'}->{'id'},
	        	screen_name => $account_info->{'account'}->{'id'},
	        	service => 'google',
	        });
	        return $c->redirect_to('/register_service');
		},
	});

	$self->plugin('Web::Auth', {
		module      => 'Facebook',
		key         => $config->{'facebook_sso'}->{'key'},
		secret      => $config->{'facebook_sso'}->{'secret'},
		on_finished => sub {
			my ( $c, $access_token, $account_info ) = @_;
			$c->session('access_token'  => $access_token);
	        $c->session('account_info'  => {
	        	service => 'facebook',
	        	id => $account_info->{'id'},
	        	screen_name => $account_info->{'username'},
	        	name => $account_info->{'name'},
	        });
	        return $c->redirect_to('/register_service');
		},
	});

	$self->plugin('Web::Auth', {
		module      => 'Github',
		key         => $config->{'github_sso'}->{'key'},
		secret      => $config->{'github_sso'}->{'secret'},
		on_finished => sub {
			my ( $c, $access_token, $account_info ) = @_;
			$c->session('access_token'  => $access_token);
	        $c->session('account_info'  => { 
	        	service => 'github',
	        	id => $account_info->{'id'},
	        	name => $account_info->{'name'},
	        	screen_name => $account_info->{'login'},
	        });
	        return $c->redirect_to('/register_service');
		},
	});

	$r->post('/login' => sub {
		my $self = shift;

		my $email = $self->param('email') || '';
		my $pass  = $self->param('pass')  || '';

		my $es = $self->es;

		my ($results, $count);

		if ($email =~ m{\@}i) {
			$results = $es->search(
				index => 'bkmrx',
				type => 'users',
				body => {
					query => {
						match => {
							email => $email,
						}
					}
				}
			);
			$count = $results->{'hits'}->{'total'};
		} else {
			$results = $es->search(
				index => 'bkmrx',
				type => 'users',
				body => {
					query => {
						match => {
							username => $email,
						}
					}
				}
			);
			$count = $results->{'hits'}->{'total'};
		}

		# error unless 1 result
		unless ($count == 1) {
			$self->flash( error => "Error logging in - please try again" );
			return $self->redirect_to('/login');
		}

		my $doc = $results->{'hits'}->{'hits'}->[0];
		my $user_id = $doc->{"_id"};
		my $username = $doc->{'_source'}->{"username"};

		if ($doc->{'_source'}->{'fail_count'} > 4) {
			$self->flash( error => "Too many failed login attempts. Please reset your password using the link below." );
			return $self->redirect_to('/login');
		}

		# error unless password matches
		unless ($self->bcrypt_validate( $pass, $doc->{'_source'}->{"pass"} )) {
			my $res = $es->update(
				index => 'bkmrx',
				type => 'users',
				id => $doc->{'_id'}, 
				body => { 
					script => "ctx._source.fail_count += 1", 
				}
			);
			$self->flash( error => "Error logging in - please try again" );
			return $self->redirect_to('/login');
		}

		my $res = $es->update(
			index => 'bkmrx',
			type => 'users',
			id => $doc->{'_id'}, 
			body => { 
				doc => {
					logged_in => DateTime->now()->epoch,
					fail_count => 0
				}
			}
		);

		# log the user in
		$self->session( user_id => $user_id );
		$self->session( username => $username );

		# go to bookmarklet if applicable
		if ($self->param('title') && $self->param('url')) {
			return $self->redirect_to('/bklet?url=' . 
				uri_escape_utf8($self->param('url')) . 
				'&title=' . 
				uri_escape_utf8($self->param('title')) .
				'&from=' . 
				uri_escape_utf8($self->param('from'))
				);
		}

		$self->flash( message => 'welcome back!' );
		if ($self->session('login_referer')) {
            return $self->redirect_to($self->session('login_referer'));
        } else {
        	return $self->redirect_to('/bkmrx');
        }
	} => 'auth/login');
  
	$r->post('/register')->to('crud#register');

	# account - protected area
	my $logged_in = $r->under( sub {
		my $self = shift;

		return 1 if $self->session('user_id');

		if ($self->tx->req->url->path eq '/bklet') {
			$self->flash(bk_title => $self->param('title'), bk_url => $self->param('url'), bk_from => $self->param('from'));
		}

		$self->session(login_referer => $self->req->url);

		$self->redirect_to('/login');
		return undef;
	} );

	# AJAJ Functions
	$logged_in->post('/ajax/fetch_url')->to('functions#fetch_url');
	$logged_in->get('/ajax/modal')->to('ajax#modal_add');
	$logged_in->post('/ajax/serp-add')->to('ajax#serp_add');

	# core account pages
	$logged_in->get('/bkmrx')->to('account#my_bkmrx');
	$logged_in->get('/bkmrx/:tag')->to('account#my_bkmrx');
	$logged_in->get('/me/')->to('account#account');
	$logged_in->get('/me/import')->to('account#import');
	$logged_in->post('/me/import-ffx')->to('functions#import_ffx');
	$logged_in->post('/me/import-delicious')->to('functions#import_delicious');
	$logged_in->get('/me/edit-tags')->to('account#edit_tags');
	$logged_in->get('/me/backup')->to('account#backup');
	$logged_in->get('/me/backup-html')->to('functions#backup_html');

	$logged_in->get('/addons')->to('account#addons');
	
	# search
	$r->get('/search')->to('esearch#search');

	$logged_in->get('/bklet')->to('account#bklet');

	# ajax
	$logged_in->any('/ajax/json_taglist')->to('ajax#json_taglist');
	$logged_in->any('/ajax/json_to')->to('ajax#json_to_list');
	$logged_in->any('/ajax/json_social')->to('ajax#json_social_networks');
	$logged_in->any('/ajax/json_serp')->to('ajax#json_serp_bkx');
	$logged_in->any('/ajax/json_serp_who')->to('ajax#json_serp_who');
	$logged_in->any('/ajax/add-tag')->to('ajax#add_tag');

	# crud
	$logged_in->get('/me/delete-tags')->to('crud#remove_tags');
	$logged_in->get('/ajax/delete-tag')->to('crud#remove_tag');
	$logged_in->post('/ajax/update-bkmrk')->to('crud#update_bkmrk');
	$logged_in->get('/ajax/delete-bkmrk')->to('crud#delete_bkmrk');
	$logged_in->get('/ajax/delete-bkmrk-all')->to('crud#delete_bkmrk_all');
	$logged_in->get('/ajax/lock-unlock')->to('crud#lock_unlock');
	$logged_in->post('/me/')->to('crud#update_user');
	$logged_in->post('/me/add')->to('crud#add_bkmrk');

	# log out
	$logged_in->get('/logout' => sub {
		my $self = shift;
		$self->session(expires => 1);
		$self->redirect_to('/');
	});

	# public user profiles
	# legacy redirect
	$r->get('/user/:name')->to(cb => sub {
		my $self = shift;
		$self->res->code(301);
		$self->redirect_to('/' . $self->stash('name'));
	});

	$r->get('/ajax/top-tags')->to('ajax#user_top_tags');
	$r->get('/ajax/top-domains')->to('ajax#user_top_domains');

	$r->get('/:name.json')->to('user#json');
	$r->get('/:name')->to('user#profile');
	$r->get('/:name/:tag')->to('user#tags');

	$r->post('/api')->to('api#api_endpoint');

}


1;
