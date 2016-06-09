# Eneroth Townhouse System

# Copyright Julia Christina Eneroth, eneroth3@gmail.com

module EneBuildings

  # Internal: Require required Gems or install them if they are not already
  # installed.
  #
  # required_gems - An array where each element is an array of the name used to
  #                 require the Gem and the name used to install it.
  #
  # Yields once required Gems are present.
  #
  # Returns nothing.
  def self.gem_installer required_gems

    # Dialog settings.
    title = "Preparing #{NAME} for first use"
    dlg_registry = "ene_gem_installer"
    dlg_width = 500
    dlg_height = 200

    # Try requiring all Gems.
    missing = []
    required_gems.each do |g|
      begin
        require g[0]
      rescue LoadError
        missing << g
      end
    end

    if missing.empty?
      # run associated code block.
      yield
    else
      # Try to install those missing.
      # Inform user what is taking time with a web dialog.

      # Have full HTML and CSS within this file so it can easily be moved to and
      # used in other plugin projects.
      missing_names = missing.map { |g| g[1] }
      missing_list = missing_names[0..-2].join ", "
      missing_list += " and " if missing_list.size > 1
      missing_list += missing_names[-1]
      missing_list += "."
      html = <<EOF
<!DOCTYPE HTML>
<html>
  <head>
    <meta charset="utf-8">
    <meta http-equiv="X-UA-Compatible" content="IE=edge"/>
    <title>TITLE</title>
    <script type="text/javascript">
      //Toggle what div is shown.
      function set_state(state){
        body = document.getElementsByTagName("body")[0];
        divs = body.children;//IE includes comments when childNodes is used and Safari include line breaks.
        for(i=0;i<divs.length;i++) divs[i].className = '';
        divs[state].className = 'current';
      }
    </script>
    <style type="text/css">
      body{
        margin: 4px;
        padding: 0;
        font: message-box;
        font-size: 12px;
      }
      button{
        font-size: 12px;
      }
      .main_scrollable_container{
        position: absolute;
        top: 0;
        left: 0;
        right: 0;
        bottom: 30px;
        padding: 1em;
        overflow: auto;
        background: white;
      }
      .dialog_buttons{
        position: fixed;
        bottom: 4px; right: 4px;
        width: auto;
        height: auto;
      }
      .dialog_buttons button{
        width: 75px;
        margin-left: 16px;
        font-size: 12px;
      }
      body > div{
        display: none;
      }
      .current{
        display: block;
      }
    </style>
  </head>
  <body>

    <div class="current">
      <!--State 0, prompt user.-->
      <div class="main_scrollable_container">
        <p>#{NAME} requires the following Ruby Gems to function:</p>
        <p>#{missing_list}</p>
        <p>Downloading and installing may take some minute. Do you want to download and install them now?</p>
      </div>
      <div class="dialog_buttons">
        <button onclick="set_state(1);setTimeout(function(){ window.location='skp:install'; }, 1);">Yes</button>
        <button onclick="window.location='skp:close';">No</button>
      </div>
    </div>

    <div>
      <!--State 1, installing.-->
      <div class="main_scrollable_container">
        <p>Downloading and installing...</p>
        <!--TODO: Progress bar is not moving :( . It seems like this runs in teh same thread as SU and halts until installation is finished.-->
        <!--<progress style="width: 100%;"></progress>-->
      </div>
      <div class="dialog_buttons">
        <button disabled>OK</button>
      </div>
    </div>

    <div>
      <!--State 2, success!-->
      <div class="main_scrollable_container">
        <p>All required gems have been successfully installed to '#{Gem.dir}'.</p>
        <p>#{NAME} is ready to be used.</p>
      </div>
      <div class="dialog_buttons">
        <button onclick="window.location='skp:close';">OK</button>
      </div>
    </div>

    <div>
      <!--State 3, install error :( .-->
      <div class="main_scrollable_container">
        <p>The Gem <span id="install_name"></span> could not be downloaded and installed. Error message:</p>
        <p id="gem_install_error"></p>
        <p>If the error persists contact #{CONTACT}.</p>
      </div>
      <div class="dialog_buttons">
        <button onclick="set_state(1);setTimeout(function(){ window.location='skp:install'; }, 1);">Retry</button>
        <button onclick="window.location='skp:close';">Cancel</button>
      </div>
    </div>
    
    <div>
      <!--State 4, load error :( .-->
      <div class="main_scrollable_container">
        <p>The Gem <span id="install_name2"></span> could not be loaded.</p>
        <p>Try restarting Sketchup.</p>
        <p>If the error persists contact #{CONTACT}.</p>
      </div>
      <div class="dialog_buttons">
        <button onclick="window.location='skp:close';">OK</button>
      </div>
    </div>

  </body>
</html>
EOF

      view = Sketchup.active_model.active_view
      l = (view.vpwidth - dlg_width)/2
      t = (view.vpheight - dlg_height)/2
      dlg = UI::WebDialog.new title, false, dlg_registry, dlg_width, dlg_height, l, t, false
      dlg.navigation_buttons_enabled = false
      dlg.set_background_color dlg.get_default_dialog_color
      dlg.set_html html
      Sketchup.platform == :platform_win ? dlg.show : dlg.show_modal

      dlg.add_action_callback("close") do
        dlg.close
      end

      dlg.add_action_callback("install") do
        error = false
        until missing.empty? do
        
          require_name, install_name = missing.first
          
          # Install gem.
          begin
            gem_spec = Gem.install(install_name)[0]
          rescue => e
            error = true
            js = "document.getElementById('install_name').innerHTML = '#{install_name}';"
            js << "document.getElementById('gem_install_error').innerHTML = '#{e.message.gsub "'", "\\\\'"}';"
            js << "set_state(3);"
            dlg.execute_script js
            break
          end
          
          # Load gem.
          begin
            # Just using require with the name without specifying path doesn't
            # work in SU2017. I had reports of behavior identical to what a
            # failure here would produce so maybe the same error occurs on MAC.
            # Error cannot be reproduced when isolated. Fuck this!
            ###require require_name
            require File.join(gem_spec.gem_dir, gem_spec.require_path, require_name)
          rescue LoadError => e
            # For some unknown reason UI.messagebox doesn't show up when called
            # from here.
            error = true
            js = "document.getElementById('install_name2').innerHTML = '#{install_name}';"
            js << "set_state(4);"
            dlg.execute_script js
            break
          end
          
          missing.shift
          
        end
        UI.beep
        unless error
          dlg.execute_script "set_state(2);"
          yield
        end
      end

    end

    nil

  end

end
