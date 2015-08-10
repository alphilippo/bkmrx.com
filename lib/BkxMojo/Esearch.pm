package BkxMojo::Esearch;
use Mojo::Base 'Mojolicious::Controller';

use DateTime;
use Mojo::Home;
use List::Util qw( max min );
use Encode qw( decode );
use String::Truncate qw(elide);
use Search::Elasticsearch;
use Mojo::Log;
use Search::Query;

my $log = Mojo::Log->new;
use Data::Dumper;

my $home = Mojo::Home->new;
$home->detect('BkxMojo');

sub search {
	my $self = shift;

	# need to tokenize q somehow to allow for site: queries etc
	my $q         = $self->param('q')      || '';
	my $offset    = $self->param('offset') || 0;
	my $type      = $self->param('type')   || '';
	my $page_size = $self->param('num')    || 10;
	my $user_id   = $self->session('user_id') || '';
	my %params = ( q => $q );

	my $parser = Search::Query->parser;
	my $qparse = $parser->parse($params{'q'});

	my (@clauses, @negatives);

	for my $plus ($qparse->{'+'}) {
		if ($plus) {
			push @clauses, _process_query($plus);
		}
	}

	for my $minus ($qparse->{'-'}) {
		if ($minus) {
			push @negatives, _process_query($minus);
		}
	}

	my $es = $self->es;

	my $public_highlight = {
		order => "score",
		fields => {
			content => {
				type => 'plain'
			},
			page_title => {
				type => 'plain'
			},
			url => {
				type => 'plain'
			},
		}
	};

	my $user_highlight = {
		order => "score",
		fields => {
			user_title => {
				type => 'plain'
			},
			page_title => {
				type => 'plain'
			},
			url => {
				type => 'plain'
			},
			content => {
				type => 'plain'
			},
		}
	};

	my $public_query = {
        query => {
        	filtered => {
				filter => {
					term => {
						crawled => 1,
					}
				},
				query => {
					bool => {
						should => \@clauses,
						must_not => \@negatives
					}
				}
			}
        },
    	highlight => $public_highlight,
	};

	my $user_query = {
		query => {
			filtered => {
				query => {
					bool => {
						should => \@clauses,
						must_not => \@negatives
					}
	            },
	            filter => {
	            	has_child => {
	            		type => 'bookmark',
	            		query => {
	            			match => {
	            				user_id => $user_id,
	            			}
	            		}
	                    
	                }
	            },
	    	}
	    },
	    highlight => $user_highlight,
	};

	# Custom searches
	if ($type) {
	    my $res;
	    if ($type eq 'all') {
	    	$user_query = $public_query;
	    	$params{'type'} = $type;
    	} else {
    		$params{'type'} = $type;
    		$user_query = {
    			query => {
					filtered => {
			            filter => {
			            	has_child => {
			            		type => 'bookmark',
			            		query => {
			            			filtered => {
							            filter => {
							            	and => [
								            	{ term => { 'bookmark.from' => $type } },
								            	{ term => { 'bookmark.user_id' => $user_id } }
							            	]
							            },
							        }
			            		}
			                }
			            },
			            query => {
			                bool => {
								should => \@clauses,
								must_not => \@negatives
							}
			            }
			    	}
			    },
			    highlight => $user_highlight,
			};
    	}
	}

	my $results;
	if ($self->session('user_id')) {
		$results = $es->search(
		    index => 'bkmrx',
		    # type => 'url',
		    body  => $user_query,
		    size => $page_size,
		    from => $offset,
		);
	} else {
		$results = $es->search(
		    index => 'bkmrx',
		    # type => 'url',
		    body  => $public_query,
		    size => $page_size,
		    from => $offset,
		);
	}

	my $hit_count = $results->{'hits'}->{'total'};

	my (@search_results, %search_meta, @url_ids);

	# loop through results
	for my $hit (@{ $results->{'hits'}->{'hits'} }) {
	    my $score   = sprintf( "%0.3f", $hit->{'_score'} );

	    my ($title, $url, $excerpt, $orig_title);

		$title = $hit->{'highlight'}->{'page_title'}->[0] || $hit->{'_source'}->{'page_title'};
		$title =~ s!\n!!g;
		$title =~ s!\s+! !g;
		$title =~ s!^ !!;
		$title =~ s! $!!;
		$orig_title = $hit->{'_source'}->{'page_title'};
		$excerpt = $hit->{'highlight'}->{'content'}->[0] || '';

    	$url = $hit->{'highlight'}->{'url'}->[0] || $hit->{'_source'}->{'url'};
    	

    	my ($display_url) = $url =~ m{^[hf]tt?ps?://(?:www\.)?(.*)$}i;
	    
	    # search all users' bookmarks
	    push(@search_results, {
	        url => $hit->{'_source'}->{'url'},
	        orig_url => $hit->{'_source'}->{'url'},
	        display_url => elide($display_url, 90),
	        url_id => $hit->{'_id'}, 
	        orig_title => $orig_title,
	        title => $title,
	        snippet => $excerpt,
	        tags => $hit->{'_source'}->{'tags'},
	        added => $hit->{'_source'}->{'added'},
	        added_by => $hit->{'_source'}->{'added_by'},
	        score => $score,
	    });
	    push @url_ids, $hit->{'_source'}->{'url'};
	}

	$search_meta{'total_results'} = $hit_count;
	my $last_result = min( ( $offset + $page_size ), $hit_count );
	my $first_result = min( ( $offset + 1 ), $last_result );
	$search_meta{'first_result'} = $first_result;
	$search_meta{'last_result'} = $last_result;

	$search_meta{'query'}   = $q;
	$search_meta{'results'} = \@search_results;
	

	my $req_path = $self->req->url->path;
	if ($self->session('user_id')) {
		$self->render( template => 'search/search', 
			results => \%search_meta, 
			pages => $self->paginate($hit_count, $offset, $page_size, $req_path, \%params) ,
			url_ids => \@url_ids,
		);
	} else {
		$self->render( template => 'search/public_search', 
			results => \%search_meta, 
			pages => $self->paginate($hit_count, $offset, $page_size, $req_path, \%params) 
		);
	}
	
}

sub _process_query {
	my $input = shift;

	my @bool_term;
	
	for my $clause (@$input) {

		my $field = $clause->{'field'};
		
		if ($field) {
			if ($field eq 'inurl') {
				push @bool_term, { match => { "url.searchable" => $clause->{'value'} }};
			} elsif ($field eq 'intitle') {
				my $match_type = 'match';
				if ($clause->{'quote'}) {
					$match_type = 'match_phrase';
				}
				push @bool_term, { $match_type => { "page_title" => $clause->{'value'} }};
			} elsif ($field eq 'tag') {
				# doesn't work
				push @bool_term, { match => { "bookmark.tags" => $clause->{'value'} }};
			} else {
				my $match = { 
					multi_match => { 
						query => $clause->{'value'}, 
						fields => [
							'page_title', 
							'content', 
							'domain',
							'tag_h1',
							'url.searchable'
						],
					}
				};
				if ($clause->{'quote'}) {
					$match->{'multi_match'}->{'type'} = 'phrase';
				}
				push @bool_term, $match;
			}
		} else {
			my $match = { 
				multi_match => { 
					query => $clause->{'value'}, 
					fields => [
						'page_title', 
						'content', 
						'domain',
						'tag_h1',
						'url.searchable'
					],
				}
			};
			if ($clause->{'quote'}) {
				$match->{'multi_match'}->{'type'} = 'phrase';
			}
			push @bool_term, $match;
		}
	}

	return \@bool_term;
}

1;