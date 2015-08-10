rdb = typeof rdb === 'undefined' ? {} : rdb;

rdb.firefox = (function(){
    var // Components
        prefs = Components.classes['@mozilla.org/preferences-service;1']
            .getService(Components.interfaces.nsIPrefBranch),
        os = Components.classes['@mozilla.org/xre/app-info;1']
            .getService(Components.interfaces.nsIXULRuntime).OS,
        //
        // URLs
        site_name = "www.readability.com",
        baseUrl = 'http://' + site_name,
        secureBaseUrl = 'https://' + site_name,
        urls = {
            index           : baseUrl,
            secureIndex     : secureBaseUrl,
            firstRunUrl     : baseUrl + '/account/extension/complete/',
            syncUrl         : baseUrl + '/account/extension/sync',
            ajax_sync_url   : baseUrl + '/extension/ajax/sync',
            accountToolsUrl : baseUrl + '/account/tools',
            addonsUrl       : baseUrl + '/addons',
            // Will require a schema
            readUrl         : site_name + '/bookmarklet/read.js',
            saveUrl         : site_name + '/bookmarklet/save.js',
            kindleUrl       : site_name + '/bookmarklet/send-to-kindle.js'
        },
        //
        debug   = false,
        version = '2.4',
        sync_string = ['firefox', os, version].join('_') + (debug ? '.debug' : ''),
        constants = {
            'pref_branch': 'extensions.readability.'
        },
        // Toolbar buttons to install by id
        toolbar_buttons = [
            'readability-toolbar-read',
            'readability-toolbar-save',
            'readability-toolbar-kindle'
        ];

    // Properly encode a string url into something firefox understands for opening tabs
    var url_to_uri = (function(spec){
        var ios = Components.classes['@mozilla.org/network/io-service;1'].getService(Components.interfaces.nsIIOService);
        return function(url){
            return ios.newURI(url, null, null);
        };
    }());

    function get_token(callback){
        rdb.extensions.log("Requesting token from server");

        var req = new XMLHttpRequest();
        req.onreadystatechange = receive_token_response;
        req.open('GET', urls.ajax_sync_url, true);
        req.send();

        function receive_token_response(event){
            if(event.currentTarget.readyState === 4){
                var req = event.currentTarget,
                    response = JSON.parse(req.responseText),
                    response_token = response.readabilityToken || "";

                rdb.extensions.log("Received token from server: " + response_token);

                callback(response_token);
            }
        }
    }

    function focus_tab_by_url(urls) {
        var wm = Components.classes["@mozilla.org/appshell/window-mediator;1"]
                .getService(Components.interfaces.nsIWindowMediator),
            browserEnumerator = wm.getEnumerator("navigator:browser");

        while (browserEnumerator.hasMoreElements()) {
            var browserWin = browserEnumerator.getNext(),
                tabbrowser = browserWin.gBrowser,
                numTabs = tabbrowser.browsers.length,
                //
                currentBrowser, tabUrl, index;

            for (index = 0; index < numTabs; index++) {
                currentBrowser = tabbrowser.getBrowserAtIndex(index);
                // Remove any trailing slash in the url
                tabUrl = currentBrowser.currentURI.spec.replace(/\/$/,'')

                if( // Checking a single url
                    tabUrl == urls ||
                    // Checking an array of urls
                    urls.indexOf(tabUrl) != -1
                ){
                    // Focus the tab
                    tabbrowser.selectedTab = tabbrowser.tabContainer.childNodes[index];
                    // Focus the browser
                    browserWin.focus();

                    return true;
                }
            }
        }

        return false;
    }

    function install_toolbar_buttons(){
        var insert_before = 'urlbar-container',
            //
            nav_bar = document.getElementById('nav-bar'),
            current_set_array = nav_bar.currentSet.split(','),
            //
            new_set;

        // Install all the buttons one by one
        for(var button_index in toolbar_buttons){
            if(toolbar_buttons.hasOwnProperty(button_index)){
                var button = toolbar_buttons[button_index],
                    insert_index = current_set_array.indexOf(insert_before);

                // Only install the button if it's not already in the set
                if(current_set_array.indexOf(button) === -1){
                    current_set_array.splice(insert_index, 0, button);
                }
            }
        }

        // Set the toolbar to the current set
        new_set = current_set_array.join(",");
        nav_bar.setAttribute('currentset', new_set);
        nav_bar.currentSet = new_set;
        document.persist("nav-bar", "currentset");
        //nav_bar.ownerDocument.persist(nav_bar.id, 'currentset');
        BrowserToolboxCustomizeDone(true);
    }

    function PrefListener(branch_name, callback) {
        var // Components
            pref_service = Components.classes["@mozilla.org/preferences-service;1"]
                .getService(Components.interfaces.nsIPrefService),
            //
            that = this,
            branch;

        branch = pref_service.getBranch(branch_name);
        branch.QueryInterface(Components.interfaces.nsIPrefBranch2);

        that.observe = function(subject, topic, pref_name) {
            if (topic == 'nsPref:changed'){
                callback(constants.pref_branch + pref_name);
            }
        };

        function register(trigger) {
            branch.addObserver('', that, false);
            if (trigger) {
                branch.getChildList('', {}).
                    forEach(function (pref_name)
                        { callback(branch, pref_name) });
            }
        };

        return {
            register: register
        }
    }

    // Listen for pref updates. Provide a callback with an argument of pref
    function listen_for_pref_updates(callback, trigger){
        pref_listener = new PrefListener(constants.pref_branch, callback);
        pref_listener.register(trigger);
    };

    // Inject key:values into the active windows scope
    function inject_window_variable(name, value){
        var win = window.top.getBrowser().selectedBrowser.contentWindow.wrappedJSObject;
        win[name] = value;
    }


    return {
        urls: urls,
        version: version,
        sync_string: sync_string,
        url_to_uri: url_to_uri,
        focus_tab_by_url: focus_tab_by_url,
        get_token: get_token,
        install_toolbar_buttons: install_toolbar_buttons,
        listen_for_pref_updates: listen_for_pref_updates,
        inject_window_variable: inject_window_variable,
        // Components
        prefs: prefs,
        os: os
    };
}());
