package BkxMojo::Ajax;
use Mojo::Base 'Mojolicious::Controller';

use Data::Dumper;
use Mojo::Log;
use DateTime;
use Tie::IxHash;
use Digest::SHA1 qw(sha1_hex);
my $log = Mojo::Log->new;

sub checkname {
    my $self = shift;
    my $username = lc $self->param('username');

    $username =~ s![^a-z0-9_]!!g;

    my $status = 'taken';
    
    my $es     = $self->es;

    my $res = $es->count(
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
    # don't be rude
    my @reserved_names = qw(fuck 
        shit piss wank bollocks cunt motherfucker fucker robots index home xxx 
        porn cialis viagra about contact insurance loans 
        me bkmrx popular account ajax admin auth user profile search addons api);

    if ($res->{'count'} == 0) {
        unless ($username ~~ @reserved_names) {
            $status = 'ok';
        }
    }

    $self->render( text => $status );
}

# Render modal window 
sub modal_add {
	my $self = shift;

	$self->render();
}

# Add bookmark from serps
sub serp_add {
    my $self = shift;

    my $url_id  = $self->param('url_id');
    my $title   = $self->param('title')  || '[[blank]]';
    my $desc    = $self->param('desc')   || '';
    my $from  = 'serps';
    my @tags = ();
    my $user_id = $self->session('user_id');

    my $es = $self->es;

    my $res = $es->get(
        index => 'bkmrx',
        type => 'url',
        id => $url_id,
    );

    $self->add_bookmark({
        url => $res->{'_source'}->{'url'},
        title => $title,
        privacy => 0,
        from => 'serps',
        tags => \@tags,
        user_id => $user_id,
    });

    $self->render( text => 'added!' );
}

# list of tags on bkmrx page
sub json_taglist {
	my $self = shift;

	my $filter = $self->param('filter') || '';
    my $exists = $self->param('exists');

	my $user_id = $self->session('user_id');

    my $page_size = 10;
    my $offset = 0;
    my $es = $self->es;

    my $es_query = {
        filtered => {
            filter => {
                bool => {
                    must => [
                        {
                            term => {
                                user_id => $user_id
                            }
                        },
                    ]
                },
            }
        }
    };
    my $facets = {
        tags => {
            terms => {
                field => "tags",
                regex => "$filter.*",
                regex_flags => "DOTALL",
            },
        }
    };
    
    if ($exists) {
        my @tags = split(/\|/, $filter);
        $es_query = {
            filtered => {
                filter => {
                    bool => {
                        must => [
                            {
                                term => {
                                    user_id => $user_id
                                }
                            },
                            {
                                terms => { tags    => \@tags, execution => 'and' },
                            }
                        ]
                    },
                }
            }
        };

         $facets = {
            tags => {
                terms => {
                    field => "tags",
                },
            }
        };
    }
    
    my $results = $es->search(
        index => 'bkmrx',
        type => 'bookmark',
        body  => {
            query => $es_query,
            sort => [{
                added => "desc",
            }],
            facets => $facets
        },
        size => $page_size,
        from => $offset,
    );
    # $log->info(Dumper($results));

    my @json_tags;

    for my $doc (@{ $results->{'facets'}->{'tags'}->{'terms'} }) {
        push @json_tags, {$doc->{'term'} => $doc->{'count'}};
    }

	$self->render( json => \@json_tags );
}

sub user_top_tags {
    my $self = shift;

    my $user_id = $self->param('user_id');

    # my $page_size = 10;
    my $offset = 0;
    my $es = $self->es;

    my $es_query = {
        bool => {
            must => { 
                match => {
                    user_id => $user_id
                }
            }
        },
    };
    
    my $results = $es->search(
        index => 'bkmrx',
        type => 'bookmark',
        body  => {
            query => $es_query,
            facets => {
                tags => {
                    terms => {
                        field => "tags",
                        regex => ".*",
                        regex_flags => "DOTALL",
                        size => 20,
                    },
                },
            },
        },
        size => 0,
    );
    # $log->info(Dumper($results));

    my @json_tags;

    for my $doc (@{ $results->{'facets'}->{'tags'}->{'terms'} }) {
        push @json_tags, {$doc->{'term'} => $doc->{'count'}};
    }

    $self->render( json => \@json_tags );
}

sub user_top_domains {
    my $self = shift;

    my $user_id = $self->param('user_id');

    my $es = $self->es;

    my $results = $es->search(
        index => 'bkmrx',
        type => 'url',
        body  => {
            query => {
                match_all => {},
                has_child => {
                    type => 'bookmark',
                    query => {
                        match => {
                            user_id => $user_id,
                        }
                    }
                }
            },
            aggregations => {
                domains => {
                    terms => {
                        field => "domain",
                        size => 5,
                    },
                }
            },
        },
        size => 0,
    );
    # $log->info(Dumper($results));

    my @json_tags;

    for my $doc (@{ $results->{'aggregations'}->{'domains'}->{'buckets'} }) {
        push @json_tags, {$doc->{'key'} => $doc->{'doc_count'}};
    }

    $self->render( json => \@json_tags );
}

# list of tags on bkmrx page
sub json_to_list {
    my $self = shift;

    my $user_id = $self->session('user_id');

    my $page_size = 50;
    my $offset = 0;
    my $es = $self->es;

    my $es_query = {
        bool => {
            must => { 
                match => {
                    user_id => $user_id
                }
            }
        },
    };
    
    my $results = $es->search(
        index => 'bkmrx',
        type => 'bookmark',
        body  => {
            query => $es_query,
            facets => {
                tags => {
                    terms => {
                        field => "tags",
                        regex => "to-.*",
                        regex_flags => "DOTALL",
                        order => 'term',
                    },
                }
            }
        },
        size => $page_size,
        from => $offset,
    );
    # $log->info(Dumper($results));

    return $self->reply->exception() unless $results->{'hits'}->{'total'} > 0;

    my @json_tags;

    for my $doc (@{ $results->{'facets'}->{'tags'}->{'terms'} }) {
        push @json_tags, {$doc->{'term'} => $doc->{'count'}};
    }

    $self->render( json => \@json_tags );
}


sub json_social_networks {
    my $self = shift;

    my $user_id = $self->session('user_id');

    my $es = $self->es;
    
    my $results = $es->get(
        index => 'bkmrx',
        type => 'users',
        id => $user_id
    );
    # $log->info(Dumper($results));

    return $self->reply->exception() unless $results->{'found'};

    $self->render( json => $results->{'_source'}->{'social'} );
}

# does an array of search results exist in users bookmarks?
sub json_serp_bkx {
    my $self = shift;

    my @urls = $self->param("urls[]");

    # $log->info(Dumper(@urls));

    my (@url_terms, @url_ids_in);

    for my $u (@urls) {
        push @url_terms, { term => { url => $u } };
    }

    for my $u (@urls) {
        push @url_ids_in, $u;
    }

    # $log->info(Dumper(@url_terms));

    my $user_id = $self->session('user_id');

    my $es = $self->es;
    
    my $results = $es->search(
        index => 'bkmrx',
        type => 'bookmark',
        body  => {
            query => {
                filtered => {
                    query => {
                        term => {
                            user_id => $user_id
                        }
                    },
                    filter => {
                        or => \@url_terms
                    }
                }
            }
        },
    );
    # $log->info(Dumper($results));
    my @urls_returned;
    for my $u (@{$results->{'hits'}->{'hits'}}) {
        push @urls_returned, $u->{'_source'}->{'url'};
    }
    
    # return $self->reply->exception() unless $results->{'found'};
    my @url_ids_out;
    for my $u (@url_ids_in) {
        # only want url ids that aren't returned in the search
        # (ie aren't bookmarked by user)
        
        unless ($u ~~ @urls_returned) {
            $log->info($u);
            push @url_ids_out, sha1_hex($u);
        }
    }

    $self->render( json => \@url_ids_out );
}

# who added
sub json_serp_who {
    my $self = shift;

    my @urls = $self->param("urls[]");

    # $log->info(Dumper(@urls));

    my (@url_terms, @url_ids_in);

    for my $u (@urls) {
        push @url_terms, { term => { url => $u } };
    }

    for my $u (@urls) {
        push @url_ids_in, $u;
    }

    # $log->info(Dumper(@url_terms));

    my $user_id = $self->session('user_id');

    my $es = $self->es;
    
    my $results = $es->search(
        index => 'bkmrx',
        type => 'url',
        body  => {
            query => {
                filtered => {
                    filter => {
                        or => \@url_terms
                    }
                }
            }
        },
    );
    $log->info(Dumper($results));
    my @urls_returned;
    for my $u (@{$results->{'hits'}->{'hits'}}) {
        push @urls_returned, $u->{'_source'}->{'url'};
    }
    
    # return $self->reply->exception() unless $results->{'found'};
    my @url_ids_out;
    for my $u (@url_ids_in) {
        # only want url ids that aren't returned in the search
        # (ie aren't bookmarked by user)
        
        unless ($u ~~ @urls_returned) {
            $log->info($u);
            push @url_ids_out, sha1_hex($u);
        }
    }

    $self->render( json => \@url_ids_out );
}
# follow another user's bkmrx
sub follow {
    my $self = shift;

    # to be implemented

    $self->redirect_to('/');
}

# add a tag from the bkmrx page
sub add_tag {
    my $self = shift;

    my $tag     = $self->clean_tag($self->param('tag')) || '';
    my ($b_id, $url_id)    = $self->param('id')  =~ m{^([^_]+)__(.+)$};
    my $user_id = $self->session('user_id');

    if ($tag && $b_id) {
        my $es = $self->es;
        my $result = $es->update(
            index => 'bkmrx',
            type => 'bookmark',
            id => $b_id,
            parent => $url_id,
            body => {
                # update if doesn't exist, otherwise do nothing (ie no version update etc)
                script => "if (!ctx._source.tags.contains(tag)) {ctx._source.tags += tag} else {ctx.op = \"none\"}",
                params => { tag => $tag }
            }
        );
    }
    $self->render( json => { tag => $tag, b_id => $b_id, url_id => $url_id } );
}

1;