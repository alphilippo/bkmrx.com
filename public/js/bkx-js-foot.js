 // Functions for Modal popup window */

/* Modal window */
$(document).ready(function() {
	$('[data-toggle="modal"]').click(function(e) {
		e.preventDefault();
		var href = $(this).attr('href');
		if (href.indexOf('#') == 0) {
			$(href).modal('open');
		} else {
			$('#bkx-modal').modal('show');
		    $('#bkx-modal').load(this.href);
		}
	});
});

/* End functions for modal popup window */

/* Update filter on bkmrx page */
$('#filter').keyup(function() {
	updateTags($('#filter').val());
});

function updateTags (tagname, param) {
	$.ajax({
		url: '/ajax/json_taglist',
		data: {
			filter : tagname,
			exists : param
		},
		dataType: "json",
		type: 'POST',
		success: function(result) {
			var items = [];
			$.each(result, function(arr, hash) {
				$.each(hash, function(key, val) {
					var href = '/bkmrx/' + key;
					if (param == 'y') {
						href = '/bkmrx/' + tagname + '|' + key;
					}
					items.push('<li><a href="' + href + '"><i class="fa fa-tag"></i> ' + key + '</a> <sup>' + val + '</sup></li>');
				});
			});
			$('#ajaxtags').html(items.join(''));
		}
	});
}
/* End update filter */

/* start to-do filter */

function updateTo() {
	$.ajax({
		url: '/ajax/json_to',
		dataType: "json",
		type: 'POST',
		success: function(result) {
			var items = [];
			$.each(result, function(arr, hash) {
				$.each(hash, function(key, val) {
					var active = '';
					var close  = '';
					var tagname = '';
					if (tagname == key) {
						active = ' class="active"';
						close  = ' <a href="/bkmrx">&times;</a>';
					}

					var icon = 'fa-check';

					if (key == 'to-listen') {
						icon = 'fa-headphones';
					} else if (key == 'to-watch') {
						icon = 'fa-film';
					} else if (key == 'to-read') {
						icon = 'fa-book';
					} else if (key == 'to-buy') {
						icon = 'fa-shopping-cart';
					} else if (key == 'to-torrent') {
						icon = 'fa-cloud-download';
					} else if (key == 'to-download') {
						icon = 'fa-download';
					} else if (key == 'to-go') {
						icon = 'fa-plane';
					} else if ((key == 'to-eat') || (key == 'to-drink')) {
						icon = 'fa-glass';
					} else if (key == 'to-visit') {
						icon = 'fa-camera';
					}

					items.push('<li' + active + '><a href="/bkmrx/' + key + '"><i class="fa ' + icon + '"></i> ' + key + '</a> <sup>' + val + '</sup>' + close + '</li>');
				});
			});
			$('#to').html('<h5>To Dos</h5><ul class="nav bkx-nav-tags">' + items.join('') + '</ul><hr>');
		}
	});
}

/* end to-do filter */

/* start sources filter */

function updateSources() {
	$.ajax({
		url: '/ajax/json_social',
		dataType: "json",
		type: 'POST',
		success: function(result) {
			var i = 0;
			var items = [];
			$.each(result, function(key, val) {
				var active = '';
				var close  = '';

				if (val != '') {
					var icon = key;
					var name = key.replace('_',' ');

					if (key == 'google_plus') {
						icon = 'google-plus';
					} else if (key == 'amazon_wishlist') {
						icon = 'shopping-cart';
					}

					items.push('<li><a href="/bkmrx/?from=' + key + 
						'"><i class="fa fa-' + icon + 
						'"></i> ' + name + 
						'</a></li>');
					i++;
				}

				
			});
			if (i > 0) {
				$('#source_filter').html('<h5>Filter</h5><ul class="nav nav-pills nav-stacked bkx-nav-tags">' + 
					'<li><a href="/bkmrx"><i class="fa fa-globe"></i> all</a></li>' +
					items.join('') + 
					'</ul><hr>');
			}
		}
	});
}

/* end sources filter */

function updateSearchSources(query) {
	$.ajax({
		url: '/ajax/json_social',
		dataType: "json",
		type: 'POST',
		success: function(result) {
			var i = 0;
			var items = [];
			$.each(result, function(key, val) {
				var active = '';
				var close  = '';

				if (val != '') {
					var icon = key;
					var name = key.replace('_',' ');

					if (key == 'google_plus') {
						icon = 'google-plus';
					} else if (key == 'amazon_wishlist') {
						icon = 'shopping-cart';
					}

					items.push('<li><a href="/search/?q=' + query + '&type=' + key + 
						'"><i class="fa fa-' + icon + 
						'"></i> ' + name + 
						'</a></li>');
					i++;
				}

				
			});
			if (i > 0) {
				$('#source_filter').replaceWith(items.join(''));
			}
		}
	});
}

/* add tags function */
function add_tags() {
    $('.add_tag').editable('/ajax/add-tag', {
    	indicator   : '',
        tooltip     : 'Add a tag...',
        placeholder : '+tag',
        name : 'tag',
        width : '100',
        breakKeyCodes : [9, 13, 44, 32, 46, 59, 188],
        ajaxoptions : {success: function(result){
            				// weirdly need to eval result to get it as a json obj
            				var json = eval('(' + result + ')');
            				var b_id = json.b_id;
            				var tag  = json.tag;
            				var url_id = json.url_id;
            				$('div#d' + b_id).find("span#" + b_id + "__" + url_id).remove();
            				$('#added_tags_' + b_id).append("<span class='label label-info' style='margin:2px;' id='" 
            					+ tag + "-" + b_id 
            					+ "'><a href='?tag=" 
            					+ tag 
            					+ "' style='color:white'>" 
            					+ tag 
            					+ "</a> <a href='/ajax/delete-tag?tag=" 
            					+ tag 
            					+ "&amp;b_id=" 
            					+ b_id 
            					+ "' style='color:white;' class='deltag'>&times;</a></span><span class='add_tag' id='" 
            					+ b_id + "'></span>");
            				add_tags();
            		   }}
    });
}
/* end add tags function */

/* Functions for hovering lock icons on bkx page */

// ensure that ajax events happen on doc load as well as ajax refresh
$(document).ready(function(){
	initBinding();
});

function initBinding() {
	$('i.bkx-lock').on({
		click: function(){
			var b_id = $(this).attr('b_id');
			bkxLock(b_id, 'unlock');
		},
		mouseenter: function(){
			$(this).attr("class", "bkx-unlock fa fa-unlock");
		},
		mouseleave: function() {
			$(this).attr("class", "bkx-lock fa fa-lock");
		}
	});
	
	$('i.bkx-unlock').on({
		click: function(){
			var b_id = $(this).attr('b_id');
			bkxLock(b_id, 'lock');
		},
		mouseenter: function(){
			$(this).attr("class", "bkx-lock fa fa-lock");
		},
		mouseleave: function() {
			$(this).attr("class", "bkx-unlock fa fa-unlock");
		}
	});
	
}
function bkxLock(b_id, action) {
	$.ajax({
		url: '/ajax/lock-unlock',
		data: "b_id=" + b_id + "&action=" + action,
		dataType: "json",
		success: function() {
			// Now update the user interface
			$("i[b_id=" + b_id + "]").attr("class", "bkx-" + action + " fa fa-" + action);
			initBinding();
		}
	});
}
/* end locks */
function apiToggle(action) {
	$.ajax({
		url: '/me/api',
		data: "enable_api=" + action,
		type : 'POST',
		success: function(response) {
			// Now update the user interface
			// console.log(response.api_key);
			if (response.status == 'on') {
				$('#api_key').html(response.api_key);
				$('#api_on').show();
				$('input[name="enable_api"]').attr('checked', 'checked');
			} else {
				$('#api_key').html('');
				$('#api_off').hide();
				$('input[name="enable_api"]').removeAttr('checked');
			}
		}
	});
}

/* delete tags from a page */
$('.deltag').click(function(e) {
    var answer = confirm("Are you sure you want to delete this tag?");
    var span_id = $(this).parent().attr('id');
    var b_id = span_id.replace(/__.*$/, '');
    var tag  = span_id.replace(/^[^_]+__/, '');
    var url_id = $(this).parent().attr('url-id');
    if (answer){
        // do the default action
        e.preventDefault();
    	$.ajax({
    		url: '/ajax/delete-tag',
    		data: {"tag" : tag, "b_id" : b_id, "url_id" : url_id},
    		dataType: "html",
    		success: function(result) {
    			// Now update the user interface
    			$('span#' + span_id).remove();
    		}
    	});
    } else {
      e.preventDefault();
    }
});
/* end delete tags */

/* add bkmrk directly from SERP */
function addBkx (url_id, title) {
	$.ajax({
		url: '/ajax/serp-add',
		data: "url_id=" + url_id + "&title=" + title,
		dataType: "html",
		type: 'POST',
		success: function(result) {
			// below was rushed so need to fix
			$('div#' + url_id + ' button').addClass('btn-success');
			$('div#' + url_id + ' button').addClass('disabled');
			$('div#' + url_id + ' button').attr('disabled', 'disabled');
			$('div#' + url_id + ' button').removeClass('btn-primary');
			$('div#' + url_id + ' button').text('added!');
		}
	});
}
/* end SERP bookmarking */

/* edit bkmrx inline functions */

$('button.delbkmrk').click(function(e) {
    var answer = confirm("Are you sure you want to delete this bookmark?");
    var b_id   = $(this).parent().attr('bkx');
    var added  = $('div.bkmrk[bkx="' + b_id + '"]').attr('added');
    if (answer){
        // do the default action
        e.preventDefault();
    	$.ajax({
    		url: '/ajax/delete-bkmrk',
    		data: "b_id=" + b_id,
    		dataType: "html",
    		success: function(result) {
    			var len = $('div.bkmrk[added="' + added + '"]').length;
    			// Remove date separator if there's only one added on that date
    			if (len == 1) {
    				$('div.bkmrk[bkx="' + b_id + '"]').prev('div.d').remove();
    			}
    			// Remove deleted bookmark from DOM
    			$('div.bkmrk[bkx="' + b_id + '"]').remove();
    		}
    	});
    } else {
      e.preventDefault();
    }
});
/* end edit bkmrx functions */

/* function for toggling editor on bkmrx page */
var placeholder_text = '...';
$('span.desc').each(function() {
	if ($(this).text() == '') {
		$(this).html("<span style='color:gray;'>" + placeholder_text + "</span>");
	}
});

function bkxEditOn(bkx_id) {
	// Show all elements and add well class
	$('.bkx-jedit-hide[bkx="' + bkx_id + '"]').each(function(index) {
			$(this).attr("class", 'bkx-jedit-show')
		});
	$('.row[bkx="' + bkx_id + '"]').addClass("well");

	// change a bunch of classes
	$('div[bkx="' + bkx_id + '"] i.fa-wrench').attr("style", "color:orange");
	$('div[bkx="' + bkx_id + '"] i.source_icon').hide();
	$('div#d' + bkx_id + ' h3 a').replaceWith("<span href='" + 
			$('div#d' + bkx_id + ' h3 a').attr('href') + 
			"' id='t_" + bkx_id +
			"'>" + 
			$('div#d' + bkx_id + ' h3 a').attr('title') +
			"</span>");

	// save the title
	$('div#d' + bkx_id + ' h3 span').editable('/ajax/update-bkmrk', {
    	indicator : 'Saving...',
        tooltip   : 'Click to edit title...',
        placeholder : 'Click to edit title...',
        width     : 450,
        cancel    : 'Cancel',
        submit    : 'Save',
        name : 'title'
    });

	// save the description
	if ($('div#d' + bkx_id + ' .bkx-wrapper span.desc').text() == placeholder_text) {
		$('div#d' + bkx_id + ' .bkx-wrapper span.desc').html('');
	}
	
	$('div#d' + bkx_id + ' .bkx-wrapper span.desc').attr("id", "d_" + bkx_id);
	$('div#d' + bkx_id + ' .bkx-wrapper span#d_' + bkx_id).editable('/ajax/update-bkmrk', {
    	indicator : 'Saving...',
        tooltip   : 'Click to edit description...',
        placeholder : 'Click to edit description...',
        width     : 350,
        cancel    : 'Cancel',
        submit    : 'Save',
        name : 'desc'
    });
}

function bkxEditOff(bkx_id) {
	$('div[bkx="' + bkx_id + '"] i.fa-wrench').attr("style", "color:gray");
	$('div[bkx="' + bkx_id + '"] i.source_icon').show();
	// Change back to a href
	$('div#d' + bkx_id + ' h3 span').replaceWith("<a href='" + 
			$('div#d' + bkx_id + ' h3 span').attr('href') + 
			"'>" + 
			$('div#d' + bkx_id + ' h3 span').text() +
			"</a>");

	// Remove editable part from span
	$('div#d' + bkx_id + ' .bkx-wrapper span.desc').attr("id", "");

	$('.row[bkx="' + bkx_id + '"]').removeClass("well");
	$('.bkx-jedit-show[bkx="' + bkx_id + '"]').attr("class", 'bkx-jedit-hide');
}
/* end function */