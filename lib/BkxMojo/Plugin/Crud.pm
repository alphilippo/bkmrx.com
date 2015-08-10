package BkxMojo::Plugin::Crud;
use Mojo::Base 'Mojolicious::Plugin';

use Net::IP::Match::Regexp qw( create_iprange_regexp match_ip );
use Mojo::URL;
use Data::Validate::Domain;
use Data::Validate::IP;
use List::Util qw( max min );
use POSIX qw( ceil );
use Digest::SHA1 qw(sha1_hex);
use Mojo::Log;
use Data::Dumper;
use HTML::Entities;
my $log = Mojo::Log->new;

sub register {
	my ($self, $app) = @_;

	# Controller alias helpers
	for my $name (qw(add_bookmark add_bookmark_bulk)) {
		$app->helper($name => sub { shift->$name(@_) });
	}

	$app->helper(add_bookmark  => \&_add_bookmark);
    $app->helper(add_bookmark_bulk  => \&_add_bookmark_bulk);
}

sub new {
    my $class = shift;
    my $self = { @_ };
    
    bless ($self, $class);

    return $self;
}

sub _add_bookmark {
    my ($self, $param) = @_;

    my $url     = $self->clean_url($param->{'url'});
    my $title   = $self->clean_text($param->{'title'})  || '[[blank]]';
    my $desc    = $self->clean_text($param->{'desc'})   || '';
    # default to private bkmrk if not specified
    my $privacy = $param->{'privacy'} || 0;
    my $from    = $param->{'from'} || '';
    my @tags    = @{$param->{'tags'}};
    my $user_id = $param->{'user_id'};

    # remove whitespace-only tags
    @tags = grep /\S/, @tags;

    # clean tags
    for (my $i=0; $i < scalar(@tags); $i++) {
        $tags[$i] = $self->clean_tag($tags[$i]);
    }

    my $es = $self->es;
    my $doc_id = sha1_hex($user_id . $url);
    my $url_hex = sha1_hex($url);

    my $url_res = $es->create(
        index => 'bkmrx',
        type => 'url',
        id => $url_hex,
        ignore => [409],
        body => {
            url => $url,
            crawled => 0,
            added_by => $user_id,
            votes => 1,
        }
    );

    my $doc_res = $es->create(
        index => 'bkmrx',
        type => 'bookmark',
        id => $doc_id,
        ignore => [409],
        parent => $url_hex,
        body => {
            user_id   => $user_id,
            url => $url,
            user_title => $title,
            user_description => $desc,
            private => $privacy,
            from => $from,
            tags => \@tags,
            added     => (time() * 1000),
        }
    );

    return $doc_res;
}

sub _add_bookmark_bulk {
    my ($self, $array) = @_;

    my $es = $self->es;
    my $fail_count = 0;
    
    my $bulk_url = Search::Elasticsearch::Bulk->new(
        es          => $es,
        index       => 'bkmrx',
        type        => 'url',
        on_conflict => sub {
            my ($action,$response,$i,$version) = @_;
            # increment counter for bookmark count 'votes'
            # ie get the id from 'response', then run a script to incr
        },
    );

    my $bulk_bkx = Search::Elasticsearch::Bulk->new(
        es          => $es,
        index       => 'bkmrx',
        type        => 'bookmark',
        on_conflict => sub {
            my ($action,$response,$i,$version) = @_;
            $fail_count++;
        },
    );
    my (@bkx, @urls);

    for my $param (@$array) {

        # ignore junk
        unless ($param->{'url'} =~ m{^https?://}i) {
            # don't count towards the total
            $fail_count++;
            next;
        }

        # Insert tags
        my @new_tags;
        for my $t (@{$param->{'tags'}}) {
            my $t_id;
            my $tag = $self->clean_tag($t);
            next if $tag =~ m{^$};

            push(@new_tags, $tag);
        }

        my $url = $self->clean_url($param->{'url'});

        my $doc_id = sha1_hex($param->{'user_id'} . $url);
        my $url_hex = sha1_hex($url);

        push @bkx, {
            type => 'bookmark',
            id => $doc_id,
            parent => $url_hex,
            source => {
                user_id   => $param->{'user_id'},
                url => $url,
                user_title => $self->clean_text($param->{'title'}),
                user_description => $self->clean_text($param->{'desc'}),
                private => int $param->{'private'},
                from => $param->{'from'},
                tags => \@new_tags,
                added => ((int $param->{'added'}) * 1000),
                modified => (time() * 1000),
            }
        };

        push @urls, {
            type => 'url',
            id => $url_hex,
            source => {
                url => $url,
                crawled => 0,
                added_by => $param->{'user_id'},
                votes => 1,
            }
        };
    }

    $bulk_url->create(@urls);
    # flush needed to import anything that doesn't fit into the default 
    # (or specified) 'max_size'
    $bulk_url->flush();

    $bulk_bkx->index(@bkx);
    # flush needed to import anything that doesn't fit into the default 
    # (or specified) 'max_size'
    $bulk_bkx->flush();

    my $bkx_count = scalar @bkx;
    $bkx_count = $bkx_count - $fail_count;

    return {status => 'ok', fail_count => $fail_count, insert_count => $bkx_count};
}

1;

=head1 NAME

Mojolicious::Plugin::Bkmrx - Bkmrx helpers plugin for bkmrx.org

=head1 SYNOPSIS

  # Mojolicious
  $self->plugin('BkxMojo::Plugin::Bkmrx');

=head1 DESCRIPTION

Mojolicious::Plugin::Bkmrx is a collection of helpers for
bkmrx.org


=head1 HELPERS

Mojolicious::Plugin::Bkmrx implements the following helpers.

=head2 paginate

  $self->paginate($total_hits, $offset, $page_size, $href, \%params)

Accepts a list of arguments and produces Bootstrap-friendly pagination HTML.

=head2 clean_tag

  $self->clean_tag($tag)

Applies rules to 'clean' tag inputs

=head2 clean_url

  $self->clean_url($url)

Applies rules to 'clean' URL inputs

=head2 valid_uri

  $self->valid_uri($url)

Tests any given URI for validity.

=head2 register

  $plugin->register(Mojolicious->new);

Register helpers in L<Mojolicious> application.

=cut
