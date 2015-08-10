rdb = typeof rdb === 'undefined' ? {} : rdb;
rdb.firefox = rdb.firefox || {};

rdb.firefox.overlay = (function(){
    var shortcut_function_map = {
            'extensions.readability.shortcuts.read_now': read_now,
            'extensions.readability.shortcuts.read_later': read_later,
            'extensions.readability.shortcuts.send_to_kindle': send_to_kindle
        },
        // Populated by the preferences listener
        shortcut_map = {},
        //
        pref_listener;

    function inject_script(schemaless_url) {
        var active_window = gBrowser.selectedBrowser.contentWindow,
            active_tab_url = active_window.location.href,
            // Apply the right protocol to the script relative url
            script_url = active_window.location.protocol + '//' + schemaless_url;


        if(rdb.extensions.page_is_valid(active_tab_url)){
            rdb.extensions.log("Injecting script " + script_url);

            // Try to "sign" the request with a users token
            rdb.firefox.get_token(function(readability_token){
                var doc = window.content.document,
                    script = doc.createElement('script');

                // If we don't get a token back, pass an empty string
                rdb.firefox.inject_window_variable('readabilityToken', readability_token);

                rdb.firefox.inject_window_variable('readabilityExtensionType', 'addon');
                rdb.firefox.inject_window_variable('readabilityExtensionVersion', rdb.firefox.version);
                rdb.firefox.inject_window_variable('readabilityExtensionBrowser', 'firefox');

                rdb.extensions.log("Injecting with token:" + readability_token);

                script.setAttribute('type', 'text/javascript');
                script.setAttribute('charset', 'UTF-8');
                script.setAttribute('src', script_url);
                doc.documentElement.appendChild(script);
            });
        }

    }

    function read_now(event){
        // Disregard right clicks on the buttons
        if(event && event.button > 0){ return; }

        rdb.extensions.log('read now');
        inject_script(rdb.firefox.urls.readUrl);
    }

    function read_later(event){
        // Disregard right clicks on the buttons
        if(event && event.button > 0){ return; }

        rdb.extensions.log('read later');
        inject_script(rdb.firefox.urls.saveUrl);
    }

    function send_to_kindle(event){
        // Disregard right clicks on the buttons
        if(event && event.button > 0){ return; }

        rdb.extensions.log('send to kindle');
        inject_script(rdb.firefox.urls.kindleUrl);
    }

    // Event listener fired when content is loaded in any tab
    function content_loaded_handler(event){
        var content_document = event.originalTarget;

        if(rdb.extensions.url_is_local(content_document.location.href)){
            rdb.firefox.inject_window_variable('readabilityAddonInstalled', true);
        }

        Keanu.listen(function(shortcut){
            if(shortcut && shortcut != rdb.extensions.DISABLED_PREF){
                shortcut_function = shortcut_map[shortcut];
                if(shortcut_function){
                    shortcut_function_map[shortcut_function]();
                }
            }
        }, content_document);
    }

    // Open a given url inside one of our own tabs if one is open. Passing
    // force will open a new tab if one is not found. Returns the tab or false.
    function open_first_run_url(force){
        // Bring the focus to one of these tabs if it exists
        var addon_tab = rdb.firefox.focus_tab_by_url([
            rdb.firefox.urls.addonsUrl,
            rdb.firefox.urls.accountToolsUrl,
            rdb.firefox.urls.index,
            rdb.firefox.urls.secureIndex
        ]);

        if(addon_tab){
            gBrowser.selectedBrowser.contentDocument.location.href = rdb.firefox.urls.firstRunUrl;
        }

        else if(force){
            gBrowser.selectedTab = gBrowser.addTab(rdb.firefox.urls.firstRunUrl);
        }
    }

    // Catch preference updates
    function handle_pref_updates(pref_name){
        var value = rdb.firefox.prefs.getCharPref(pref_name);
        update_shortcut(pref_name, value);
    }

    function update_shortcut(pref_name, value){
        // Remove any existing shortcut by value
        for(var shortcut in shortcut_map){
            if(shortcut_map[shortcut] === pref_name){
                rdb.extensions.log("Deleting old shortcut for " + shortcut);
                delete shortcut_map[shortcut];
            }
        }
        // Add the shortcut to the map
        shortcut_map[value] = pref_name;
        rdb.extensions.log("New shortcut, " + pref_name + ": " + value);
    }

    // Extension init. Called on every new window launch and startup.
    function init(){
        var first_run_complete = rdb.firefox.prefs.getBoolPref('extensions.readability.first_run_complete', false),
            current_version    = rdb.firefox.prefs.getCharPref('extensions.readability.version', '0'),
            pref_name;

        // Add page load listener to catch sync page
        gBrowser.addEventListener('load', content_loaded_handler, true);

        // First run after install
        if(!first_run_complete){
            rdb.firefox.install_toolbar_buttons();
            // Pause a bit before attempting to load the installation complete
            // page
            setTimeout(function(){
                open_first_run_url(true);
            }, 2000);

            // Close the first run prefs
            rdb.firefox.prefs.setBoolPref('extensions.readability.first_run_complete', true);
            rdb.firefox.prefs.setCharPref('extensions.readability.version', rdb.firefox.version);
        }

        // First run after update
        else if(current_version !== rdb.firefox.version){
            // Do anything you'd want to do on version update here
            
            // Close up the version pref so this version of the extension
            // doesnt run this block of code again
            rdb.firefox.prefs.setCharPref('extensions.readability.version', rdb.firefox.version);
        }

        // Set up the listeners for pref changes
        rdb.firefox.listen_for_pref_updates(handle_pref_updates);

        // Populate the shortcut_map
        for(pref_name in shortcut_function_map){
            update_shortcut(pref_name, rdb.firefox.prefs.getCharPref(pref_name));
        }

        rdb.extensions.log("init complete");
    }

    // Public properties and methods
    return {
        init:           init,
        read_now:       read_now,
        read_later:     read_later,
        send_to_kindle: send_to_kindle
    };
}());

window.addEventListener("load", rdb.firefox.overlay.init, false);
