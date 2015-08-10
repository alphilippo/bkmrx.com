#!/usr/bin/env perl
use strict;
use Search::Elasticsearch;

my $es = Search::Elasticsearch->new(
    nodes      => '127.0.0.1:9200'
);

my $result = $es->indices->create(
    index => 'bkmrx',
 
    body  => {
        
        mappings => {
        	url => {
		        properties => {
		            page_title => {
		                type => "multi_field",
		                fields => {
		                    page_title => {
		                        type => "string",
		                        index => "analyzed",
		                        analyzer => "english"
		                    },
		                    untouched => {
		                        type => "string",
		                        index => "not_analyzed"
		                    }
		                }
		            },
		            added_by => {
		                type => "string",
		                index => "not_analyzed",
		            },
		            added => {
		            	type => "date",
		            },
		            tag_h1 => {
		                type => "string",
		                index => "analyzed",
		                analyzer => "english"
		            },
		            content => {
		                type =>          "string",
		                analyzer =>      "english",
		                index_options => "offsets"
		            },
		            meta_description => {
		                type => "multi_field",
		                fields => {
		                    meta_description => {
		                        type => "string",
		                        index => "analyzed",
		                        analyzer => "english"
		                    },
		                    untouched => {
		                        type => "string",
		                        index => "not_analyzed"
		                    }
		                }
		            },
		            url => {
		                type => "multi_field",
		                fields => {
		                    url => {
		                        type => "string",
		                        index => "not_analyzed"
		                    },
		                    searchable => {
		                        type => "string",
		                        index => "analyzed"
		                    }
		                }
		            },
		            domain => {
		                type => "string",
		                index => "not_analyzed",
		            },
		            http_status => {
		                type => "integer"
		            },
		            crawled => {
		                type => "integer"
		            },
		            crawled_date => {
		                type => "date"
		            },
		            votes => {
		                type => "integer"
		            },
		            hex => {
		                type => "string",
		                index => "not_analyzed"
		            },
		        }
			},
			bookmark => {
				_parent => {
					type => 'url'
				},
			    properties => {
		            user_title => {
		                type =>          "string",
		                analyzer =>      "english",
		                index_options => "offsets"
		            },
		            user_description => {
		                type =>          "string",
		                analyzer =>      "english",
		                index_options => "offsets"
		            },
		            url => {
		                type => "string",
		                index => "not_analyzed"
		            },
		            user_id => {
		                type => "string",
		                index => "not_analyzed"
		            },
		            tags => {
		                type => "string",
		                index => "not_analyzed"
		            },
		            added => {
		            	type => "date"
		            },
		            modified => {
		            	type => "date"
		            },
		        }
			},
			users => {
			    properties => {
		            email => {
		                type => "string",
		                index => "not_analyzed"
		            },
		            username => {
		                type => "string",
		                index => "not_analyzed"
		            },
		            pass => {
		                type => "string",
		                index => "not_analyzed"
		            },
		            api_key => {
		                type => "string",
		                index => "not_analyzed"
		            },
		            joined => {
		            	type => "date"
		            },
		            'social.twitter' => {
		                type => "string",
		                index => "not_analyzed"
		            },
		            'social.github' => {
		                type => "string",
		                index => "not_analyzed"
		            },
		            'social.facebook' => {
		                type => "string",
		                index => "not_analyzed"
		            },
		            'social.reddit' => {
		                type => "string",
		                index => "not_analyzed"
		            },
		            'social.hacker_news' => {
		                type => "string",
		                index => "not_analyzed"
		            },
		            'social.google_plus' => {
		                type => "string",
		                index => "not_analyzed"
		            },
		            'social.amazon_wishlist' => {
		                type => "string",
		                index => "not_analyzed"
		            },
		            'reset_token.token' => {
		                type => "string",
		                index => "not_analyzed"
		            },
		        }
			}

        }
        
    }
);
