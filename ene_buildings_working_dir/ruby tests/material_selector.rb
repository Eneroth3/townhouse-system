# UI for picking material, typically used for web dialogs.
# Behavior inspired by Layout color or pattern selection.
#
# NOTE: When loading this example from console, not on Sketchup start, a model
# must be opened or a new model created for observer to be initialized.
#
# To test dialog, run "MaterialSelectorTest.example".


module MaterialSelectorTest

  # Interface for picking material from material browser.
  class MaterialSelector

    # Block to call when a material is selected.
    # TODO: store blocks as hash indexed by calling Model to function better in multi document view?
    @@callback = nil

    # Public: Open the material browser to let user choose a material.
    # Typically called when user clicks a button for making material input in
    # web dialog.
    #
    # old_material - Material to be selected when material browser starts
    #                or nil to not select any specific material in browser
    #                (default: nil)
    #
    # Yields Material whenever a material is selected.
    #
    # Returns nothing.
    def self.pick_material(old_material = nil, &callback)
    
      # Disable callback if any so current material first can be set to
      # old_material.
      @@callback = nil
      
      Sketchup.active_model.materials.current = old_material if old_material
      self.open_material_inspector
      @@callback = callback
      
      nil
      
    end
    
    # Public: Stop executing callback when materials are selected.
    # Typically called when the web dialog containing the material selection
    # input is closed.
    #
    # returns nothing.
    def self.done_picking_material
    
      @@callback = nil
      
      # REVIEW: If possible, maybe reset material inspector view state to what
      # it was before calling select_material.
      
      nil
      
    end
    
    # Internal: Open the material inspector.
    def self.open_material_inspector
    
      # TODO: Look up how these function on MAC.
      # TODO: If material browser is already opened it should somehow be focused to attract the user's attention.
      if Sketchup.version >= "16" # REVIEW: won't work for 1 or 3 digit mayor version numbers
        # In 2015 this toggles the material browser instead of showing it.
        UI.show_inspector "Materials"
      elsif Sketchup.platform == :platform_win
        # Windows only for opening the inspector.
        Sketchup.send_action 21074
      else
        # Select paint bucket tool.
        # Has the drawback that the tool is selected.
        Sketchup.send_action "selectPaintTool"
      end
      
    end
    
    # Observer interface.  
    
    # Internal: Current material has changed.
    def self.onMaterialSetCurrent(clicked_material)
          
      @@callback.call(clicked_material) if @@callback
      
    end
    
    # TODO: If such an observer is ever implemented, implement this.
    # Internal: Material inspector was closed
    def self.onClosingMaterialInspector
    
      @@callback = nil
      
    end

  end
  
  
  # Example web dialog.
  def self.example
  
    html = <<EOF
<!DOCTYPE HTML>
<html>
  <head>
    <meta charset="utf-8">
    <meta http-equiv="X-UA-Compatible" content="IE=edge"/>
    <title>TITLE</title>
    <script>
      function pickMaterial(inputId) {
        window.location= 'skp:pick_material@' + inputId;
      }
      function setPreview(inputId, colorString) {
        var input = document.getElementById(inputId);
        var span = input.getElementsByTagName('span')[0];
        span.style.backgroundColor = colorString;
      }
    </script>
    <style>
      button span {
        display: inline-block;
        width: 22px;
        height: 22px;
      }
    </style>
  </head>
  <body>
    <p>
      Example material picker. Behaviour is copied from color picking in Layout.
      Click a material button in this dialog and the material browser lets you
      select a material.
    </p>
    <label>
      Material 1:
      <button type="button" id="material1" onclick="pickMaterial(this.id)"><span></span></button>
    </label>
    <br />
    <label>
      Material 2:
      <button type="button" id="material2" onclick="pickMaterial(this.id)"><span></span></button>
    </label>
    <p>
      For this example only the material color is previewed in the button, not
      the texture.
    </p>
  </body>
</html>
EOF

    dlg = UI::WebDialog.new(
      "Pick Material Example",
      false,
      "ene_pick_material",
      500,
      400,
      100,
      100,
      false
    )
    dlg.navigation_buttons_enabled = false
    dlg.set_background_color dlg.get_default_dialog_color
    dlg.set_html html
    Sketchup.platform == :platform_win ? dlg.show : dlg.show_modal

    # Start picking material.
    dlg.add_action_callback("pick_material") do |_, input_id|
    
      MaterialSelector.pick_material(nil) do |new_material|
      
        # Set material preview in dialog.
        # For this example only the color is used but texture could be saved to
        # file using write_thumbnail.
        if new_material
          color = new_material.color
          color_string = "rgb(#{color.red},#{color.green},#{color.blue})"
        else
          # When material is an image similar to the one inside Sketchup showing
          # front and back color could be used.
          color_string = "transparent"
        end
        js = "setPreview('#{input_id}', '#{color_string}');"
        dlg.execute_script js
        
        # Save the given material reference and the relation to the given
        # input_id.
        puts "Material #{new_material} was selected for input #{input_id}."
        
      end
    
    end
    
    # Stop picking material.
    dlg.set_on_close do
    
      MaterialSelector.done_picking_material
      
    end
    
  end


  # Observer stuff.
  class MyMaterialsObserver < Sketchup::MaterialsObserver

    def onMaterialSetCurrent(_, material)
    
      MaterialSelector.onMaterialSetCurrent material
      
    end
   
  end

  class MyAppObserver < Sketchup::AppObserver

    def expectsStartupModelNotifications
    
      true
      
    end
    
    def onNewModel(model)
    
      model.materials.add_observer MyMaterialsObserver.new
      
    end
    
    def onOpenModel(model)
    
      model.materials.add_observer MyMaterialsObserver.new
      
    end

  end

  @@app_observer ||= nil
  unless @@app_observer
    
    @@app_observer = MyAppObserver.new
    Sketchup.add_observer @@app_observer
    
  end

end
