rdb = typeof rdb === 'undefined' ? {} : rdb;
rdb.firefox = rdb.firefox || {};

rdb.firefox.options = (function(){
    function set_pref(option, passed_value){
        rdb.firefox.prefs.setCharPref(option, passed_value);
    }


    function clear_pref(option){
        set_pref(option, rdb.extensions.constants.DISABLED_PREF);
    }


    function shortcut_mouseup_handler(event){
        event.preventDefault();

        var shortcut_bar = $(event.currentTarget),
            property = shortcut_bar.attr('data-property'),
            cached_value = shortcut_bar.html();

        shortcut_bar.parent().addClass('active');

        // Clicking the bar again should cancel
        shortcut_bar.unbind('mouseup', shortcut_mouseup_handler);

        Keanu.get_shortcut({
            max_keys: 4,
            on_update: function(shortcut){
                if(shortcut){
                    rdb.extensions.display_shortcut_as_ul(shortcut_bar, shortcut);
                }
            },
            on_set: function(shortcut){
                if(shortcut){
                    set_pref(property, shortcut);
                    rdb.extensions.display_shortcut_as_ul(shortcut_bar, shortcut);
                }
                // If we get false back for shortcut, redisplay the original shortcut
                else {
                    shortcut_bar.html(cached_value);
                }
            },
            on_complete: function(){
                shortcut_bar.parent().removeClass('active');
                setTimeout(function(){
                    shortcut_bar.bind('mouseup', shortcut_mouseup_handler);
                } , 200);
            }
        });
    }


    // Options init
    function init(){
        // Keyboard shortcut boxes ui handlers
        $(".shortcut-bar").each(function(){
            var shortcut_bar = $(this),
                clear_button = shortcut_bar.parent().find('.clear-shortcut'),
                property = shortcut_bar.attr('data-property'),
                initial_value;

            // Update the display initially
            initial_value = rdb.firefox.prefs.getCharPref(property);
            if(initial_value !== rdb.extensions.constants.DISABLED_PREF){
                rdb.extensions.display_shortcut_as_ul(shortcut_bar, initial_value);
            }
            else{
                rdb.extensions.display_shortcut_as_ul(shortcut_bar);
            }

            shortcut_bar.bind('mouseup', shortcut_mouseup_handler);
            clear_button.bind('mouseup', function(event){
                clear_pref(property);
                // Display 'disabled'
                rdb.extensions.display_shortcut_as_ul(shortcut_bar);
            });
        });
    }

    return {
        init: init
    };
}());

$(rdb.firefox.options.init);
