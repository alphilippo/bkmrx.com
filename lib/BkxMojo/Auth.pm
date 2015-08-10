package BkxMojo::Auth;
use Mojo::Base 'Mojolicious::Controller';
use String::Random;
use Mojo::Log;
use Data::Dumper;
my $log = Mojo::Log->new;

sub login {
	my $self = shift;
	
	if ($self->flash('bk_title') && $self->flash('bk_url')) {
		$self->flash(bk_title => $self->flash('bk_title'));
		$self->flash(bk_url => $self->flash('bk_url'));

		return $self->render();
	}

	if ($self->session('user_id')) {
		return $self->redirect_to('/bkmrx');
	}

	$self->render();
}

sub storeToken {
	my $self = shift;

	$self->render( text => {});
}

sub forgot {
	my $self = shift;

	$self->render();
}

sub verify_reset {
	my $self = shift;
	my $email = $self->param('email');

	my $es    = $self->es;

	my $string_gen = String::Random->new;

	my $token = $string_gen->randregex('[0-9a-zA-Z]{32}');

	my $res = $es->search(
		index => 'bkmrx', 
		type => 'users', 
		body => {
			query => {
				filtered => {
					filter => {
						term => {
							email => $email
						}
					}
				}
				
			}
		}
	);

	if ($res->{'hits'}->{'total'} > 0) {
		
		my $user_id = $es->update(
			index => 'bkmrx',
			type => 'users',
			id => $res->{'hits'}->{'hits'}->[0]->{'_id'},
			body => {
				doc => {
					reset_token => {
						token => $token,
						expires => DateTime->now()->add(hours => 48)->epoch,
					}
				}
				
			}
		);

		# first, create your message
		use Email::MIME;
		my $message = Email::MIME->create(
		  header_str => [
		    From    => 'web@bkmrx.com',
		    To      => $email,
		    Subject => 'Your bkmrx.com password reset request',
		  ],
		  attributes => {
		    encoding => 'quoted-printable',
		    charset  => 'UTF-8',
		  },
		  body_str => "Hi\n\nYou requested a password reset for your account on bkmrx.com\n\nPlease click on the link below to reset your password:\n\nhttps://bkmrx.com/reset?email=$email\&token=$token\n\nbkmrx.com",
		);

		# send the message
		use Email::Sender::Simple qw(sendmail);
		sendmail($message);
	} else {
		$self->flash(error => 'Email not found!');
		return $self->redirect_to('/forgot');
	}

	$self->flash(msg => 'A link to reset your password has been sent to your email address.');
	$self->redirect_to('/login');
}

sub reset_form {
	my $self  = shift;
	my $email = $self->param('email');
	my $token = $self->param('token');

	my $es    = $self->es;

	my $res = $es->search(
		index => 'bkmrx',
		type => 'users',
		body => {
			query => {
				filtered => {
					filter => {
						and => [
							{term => {email => $email}},
							{term => {'reset_token.token' => $token}}
						]
					}
				}
			}
		}
	);

	if ($res->{'hits'}->{'total'} > 0) {
		return $self->render(template => 'auth/reset');
	}

	$self->reply->exception("user not found");
}

sub reset {
	my $self  = shift;
	my $email = $self->param('email');
	my $pass  = $self->param('password');
	my $token = $self->param('token');

	my $es    = $self->es;

	my $res = $es->search(
		index => 'bkmrx',
		type => 'users',
		body => {
			query => {
				filtered => {
					filter => {
						and => [
							{ term => { email => $email } },
							{ term => { 'reset_token.token' => $token } }
						]
					}
				}
			}
		}
	);
	my $doc = $res->{'hits'}->{'hits'}->[0];

	if ($doc->{'_source'}->{'reset_token'}->{'expires'} < DateTime->now()->epoch) {
		$self->flash(Error => 'Reset token expired! Please try again');
		return $self->redirect_to('/login');
	}

	my $user_id = $es->update(
		index => 'bkmrx',
		type => 'users',
		id => $doc->{'_id'},
		body => {
			doc => {
				pass => $self->bcrypt($pass),
				fail_count => 0,
				reset_token => {},
			}
		}
	);
	$self->flash(msg => 'Password changed!');
	$self->redirect_to('/login');
}

1;