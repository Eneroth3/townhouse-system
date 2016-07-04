# Eneroth Townhouse System

# Copyright Julia Christina Eneroth, eneroth3@gmail.com

module EneBuildings

# Public: A Building object consists of a reference to a Template, a path
# (Point3d Array, horizontal) and a reference to a Group its drawn to.
# Additionally it has some information how to read the Template, for instance if
# any materials should be replaced.
#
# Building objects are created when they are needed, for instance when the
# properties dialog is opened or when the reposition tool is used on it.
# All the Building data is stored to the Group.
class Building

  # Public: Name of attribute dictionary for data in Building Group.
  # Uses term "house" instead of "building" for backward compatibility.
  ATTR_DICT = "#{ID}_house"

  # Internal: Warning message when entering building group
  # Used in observer.
  ENTER_WARNING =
    "You are about to enter a building drawn by #{NAME}.\n"\
    "Manually made changes will be lost when redrawn by plugin.\n\n"\
    "Do you want to continue?"

  # Internal: Statusbar text.
  STATUS_DRAWING       = "Drawing Building..."
  STATUS_DONE          = "Done Drawing."
  STATUS_SOLIDS        = "Performing solid operations"# + " (progress/total)"
  STATUS_CUTTING       = "Cutting openings..."

  # Class methods

  # Public: Get the Building object for the selected building group.
  # Used in menus for instance.
  #
  # Returns a Building object or nil if not a single group that is a building is
  # selected.
  def self.get_from_selection

    selection  = Sketchup.active_model.selection
    return unless selection.size == 1
    e = selection.first
    return unless e.attribute_dictionary ATTR_DICT

    new e

  end

  # Public: Check if an object is a Group a Building is drawn to.
  # Performs fast check without initializing Building object from Group.
  #
  # entity - The object to test.
  #
  # Returns true if is a Building Group, otherwise false.
  def self.group_is_building?(entity)

    return false unless entity.is_a?(Sketchup::Group)
    return false unless entity.attribute_dictionary ATTR_DICT

    true

  end
  
  # Public: Check if selection is a Group a Building is drawn to.
  # Performs fast check without initializing Building object from group.
  #
  # Returns true if is a Building Group, otherwise false.
  def self.selection_is_building?

    selection  = Sketchup.active_model.selection
    return unless selection.size == 1

    group_is_building? selection.first

  end

  # Internal: Display message telling user they are entering a Building Group.
  # Called from observer.
  #
  # Returns true if user wants to proceed, false if user wants to cancel.
  def self.onGroupEnter
  
    UI.messagebox(ENTER_WARNING, MB_OKCANCEL) == IDOK
    
  end
  
  # Instance attribute accessors
  
  # Public: Gets/sets whether path represents building back side instead of
  # front.
  attr_accessor :back_along_path
  
  # Public: Gets/sets component replacements.
  # Array where each element is array of original (string identifier) and
  # replacement (array of replacement of each slot, also string identifier).
  attr_accessor :componet_replacement
  
  # Public: Gets/sets rotation of gables.
  # Array containing 2 angels in radians cc seen from above.
  attr_accessor :end_angles
  
  # Public: Returns Group Building is drawn to.
  attr_reader :group

  # Public: Gets/set material replacements.
  # Array where each element is an array of original and replacement Material.
  attr_accessor :material_replacement

  # Public: Gets/sets path Building is drawn to in local coordinates of the
  # parent  drawing context (e.g. model root or a group representing a
  # property). When group is manually moved in SU the path will be transformed
  # along with it and be updated next time an object is loaded from it.
  # Make sure all points have same z value.
  attr_accessor :path# TODO: PART REPLACEMENTS: BEFORE PUBLISHING: Handle @part_replacement when @path changes (or @back_along_path). Purge it or do something. anything.

  # Public: Gets/set whether solid operations should e performed, boolean.
  attr_accessor :perform_solid_operations

  # Public: Gets/sets Template object for Building.
  attr_accessor :template

  # Instance methods

  # Public: Create a new Building object.
  #
  # group - Group to base Building on. Used to re-create previously created
  #         object (default: nil).
  def initialize(group = nil)

    # Make sure templates are loaded.
    Template.require_all

    if group

      # Load saved object attributes from group.
      @group = group
      load_attributes

    else

      # Initialize variables.

      # Reference to template object.
      @template

      # Point3d Array of where to draw building.
      @path = []
      
      @back_along_path = false

      # End angles in radians.
      @end_angles = [0, 0]
      
      # Defines what corner parts should be drawn to building.
      # Variable is Hash indexed by Template id String.
      # Each value is a Hash indexed by corner name String.
      # Each such value is an Array of Booleans corresponding to each building
      # corner (from left to tight) telling whether given corner part should be
      # drawn to that corner.
      @corners = {}
      
      # Defines what gable parts should be drawn to building.
      # Variable is Hash indexed by Template id String.
      # Each value is a Hash indexed by gable name String.
      # Each such value is an Array of Booleans corresponding to the building
      # end (left, right) telling whether given gable part should be
      # drawn at that end.
      @gables = {}
      
      # Defines margins for spread and aligned parts on building segment.
      # Variable is Hash indexed by Template id String.
      # Each value is an array containing margin Lengths or nil where there is
      # no margin.
      @facade_margins = {}
      
      # Defines how to replace facade elements when drawing buidling.
      # Variable is Hash indexed by Template id String.
      # Each value is a Hash indexed by original part name.
      # Each such value is an Array where each element corresponds to a building
      # segment (what is between 2 adjacent corners).
      # Each element is an Array where each each element corresponds to a slot
      # (an instance of the original part that can be replaced).
      # A slot either contains nil when not replaced or the name of the
      # replacing part.
      @part_replacements = {}

      # Array of Materials to replace and replacement.
      # Each element is an array containing the original and the replacement
      # Material object.
      @material_replacement = []

      # Boolean telling whether solid operations should be performed during
      # building drawing.
      @perform_solid_operations = true

    end

  end

  # Public: Draws building.
  #
  # write_status - Write to statusbar while drawing (default: true).
  #
  # Returns nothing.
  def draw(write_status = true)
  
    raise "No template set for building." unless @template

    Sketchup.status_text = STATUS_DRAWING if write_status
        
    # Get a copy of the instance variables as they were when building was last
    # drawn. Use these to compare changes and only draw what is relevant.
    last_drawn_as = @group && @group.valid? ? load_attributes_to_hash : {}

    # Do either full or partial redraw depending on what has changed
    # since method was previously called.
    if(
      !@group ||
      !@group.entities.first ||
      @template                 != last_drawn_as[:template] ||
      @path                     != last_drawn_as[:path] ||
      @back_along_path          != last_drawn_as[:back_along_path] ||
      @end_angles               != last_drawn_as[:end_angles] ||
      @perform_solid_operations != last_drawn_as[:perform_solid_operations] ||
      (
        @template.has_solids? &&
        last_drawn_as[:perform_solid_operations] &&
        (
          @gables  != last_drawn_as[:gables] ||
          @corners != last_drawn_as[:corners] ||
          @part_replacements != last_drawn_as[:part_replacements]
        )
      )
    )
      draw_volume
      draw_parts
      draw_solids write_status
      draw_material_replacement
     elsif(
      @gables  != last_drawn_as[:gables] ||
      @corners != last_drawn_as[:corners] ||
      @part_replacements != last_drawn_as[:part_replacements]
     )
       draw_parts
       draw_material_replacement
    else
      draw_material_replacement
    end
    
    save_attributes

    Sketchup.status_text = STATUS_DONE if write_status
    
    nil

  end

  # Public: Find what part replacement currently uses a specific slot.
  #
  # original_name - String name of the original part being replace.
  # segment       - Int segment index (counting from left, starting at 0).
  # index         - Int slot index for leftmost slot to be checked
  #                 (counting from left, starting at 0).
  # slots         - How many slots to check (default: 1).
  #
  # Example:
  #
  #   my_building.slot_use("Window", 0, 0)
  #   # -> []
  #   # The first Winow from the left in the first segment from the left is
  #   # not being replaced.
  #
  #   my_building.slot_use("Window", 0, 0, 4)
  #   # -> []
  #   # The first 4 Winow from the left in the first segment from the left are
  #   # not being replaced.
  #
  #   my_building.slot_use("Window", 0, 1)
  #   # -> [["Door", 1, true]]
  #   # The second Window from the left in the first segment is being replaced
  #   # by a Door.
  #
  #   my_building.slot_use("Window", 0, 3)
  #   # -> [["Balcony", 2, true]]
  #   # The fourth Window from the left in the first segment is being replaced
  #   # by a Balcony. The leftmost (start) slot of the balcony is the third slot
  #   # in the same section, meaning the balcony must span at least 2 slots.
  #
  #   my_building.slot_use("Window", 1, 2)
  #   # -> [["Balcony Wide", 0, false]]
  #   # The third Window in the second segment is being replaced by a Balcony
  #   # Wide. The Balcony Wide is invalid and will not be drawn.
  #   # Either the Balcony Wide uses slots that doesn't exist because segment is
  #   # too short or "Balcony Wide" isn't the name of a replacement that is
  #   # available for thye current template.
  #
  # Returns Array listing replacements using giving slots or nil when any of the
  # slots doesn't exist.
  # Each Array element is another Array containg String name of replacement using
  # slot, it's leftmost (start) slot index and a boolean telling if its valid.
  # A replacement isn't valid when there isn't any available replacement by that
  # name or when it uses slots that doesn't exist.
  def inspect_slots(original_name, segment, index, slots = 1)# TODO: Under construction.
    
    # Check if given segment even exists.
    # TODO: return nil when segment doesn't exist (compare to path)...
  
    last_slot = index + slots - 1
  
    part_replacements      = (@part_replacements[@template.id] ||= {})
    available_replacements = list_available_replacements
    #available_replacable = list_available_replacable...
    
    # Check if all given slots exists within segment.
    # TODO: return nul if last_slot doesn't exist...
        
    uses_slot = []
    
    segment_array = part_replacements[original_name][segment]
    return [] unless segment_array
    segment_array.each_with_index do |v, other_i|
    
      next unless v
      valid = true
      using_slot = available_replacements.find { |r| r[:name] == v }
      unless using_slot
        valid = false
        using_slot = {}
      end
      other_slots = using_slot[:slots] || 1
      other_last_slot = other_i + other_slots - 1
      
      # TODO: valid = false if other_last_slot is greater than the index of the last available slot.

      next if other_i > last_slot || other_last_slot < index
      
      uses_slot << [v, other_i, valid]
      
    end
    
    uses_slot
    
  end
  
  # Public: List replaceable materials (based o template).
  # Materials directly in segment groups are listed. Materials in nested groups
  # are also listed if the group has an attribute specifically saying so.
  #
  # Called when opening properties dialog to allow user to set what materials
  # to replace with what other materials.
  #
  # Returns array of Material objects.
  def list_replaceable_materials

    @template.list_replaceable_materials

  end

  # Public: [Re-]Load class instance variables from group attributes.
  # Unknown (not installed) template will be nil.
  #
  # Returns nothing.
  def load_attributes

    # Set instance variable for each attribute.
    load_attributes_to_hash.each_pair do |key, value|
      instance_variable_set("@" + key.to_s, value)
    end
    
    nil
    
  end

  # Public: Check if template isn't missing.
  # If template is missing a the template select panel opens up to let user 
  # pick another template to use instead for this building.
  #
  # Yields if template was missing but user chose to pick a new one instead.
  #
  # Examples
  #
  #   def my_method(building)
  #     # If there is no valid_template, call same method again after once
  #     # user has selected a new template.
  #     return unless building.valid_template? { my_method(building) }
  #     # Do stuff with building here.
  #     p building.template
  #   end
  #
  # Returns true if template can be found and nil if it's missing.
  def valid_template?(&block)

    return true if @template
    return false unless block

    missing = @group.get_attribute ATTR_DICT, "template", "nil"
    msg =
      "The template '#{missing}' used on this building could not be found.\n"\
      "Perhaps building was drawn on a computer with more templates installed.\n\n"\
      "Choose new template?"
    return false if UI.messagebox(msg, MB_OKCANCEL) == IDCANCEL

    Template.select_panel("Replace missing template") do |t|
      next unless t
      @template = t
      block.call
    end

    false

  end

  # Public: Open web dialog and let user set Building properties.
  # Template, material replacement and component replacement among others can be
  # set.
  #
  # When changing values in the form the Building object attributes are directly
  # changed. These changes are not saved to the Group if user cancels but still
  # exist in the Building object.
  #
  # Do not use the same Building object at a later point, instead initialize a
  # new from the group as this:
  #   b = Building.new b.group
  #
  # REVIEW: Do not instantly change Building object. Change it once user saves.
  #
  # Returns WebDialog object.
  def properties_panel
  
    # Building object is instantly updated when changes are made in the dialog.
    # The building Group is redrawn and instance variables saved as attributes
    # once the user clicks OK ar Apply.

    model = @group ? @group.model : Sketchup.active_model
    
    # Only allow one properties dialog for each building at a time.
    # References to opened properties dialogs are saved as a hash indexed by the
    # GUID of the group.
    @@opened_dialogs ||= {}
    dlg = @@opened_dialogs[@group.guid]
    if dlg
      dlg.bring_to_front
      return dlg
    end

    # Check if template is known.
    # Model could be created on a computer that has more templates installed.
    return unless valid_template? { properties_panel }

    # Create dialog.
    dlg = UI::WebDialog.new(
      "Building Properties",
      false,
      "#{ID}_building_properties_panel",
      610,
      450,
      100,
      100,
      true
    )
    dlg.min_width  = 440
    dlg.min_height = 300
    dlg.navigation_buttons_enabled = false
    dlg.set_file(File.join(PLUGIN_DIR, "dialogs", "building_properties_panel.html"))
    @@opened_dialogs[@group.guid] = dlg

    # Reference to template dialog.
    # Used to make sure just one is opened from this properties dialog and to
    # close when this dialog closes.
    dlg_template = nil

    # Adds data to form. Called when dialog is shown and when template has been
    # changed.
    add_data = lambda do

      js ="var preview_dir = '#{Template::PREVIEW_DIR}';"

      # If more dialogs are opened, offset this one to avoid it being on top of others
      js << "offset_window(10);" if @@opened_dialogs.size > 1

      # Template info.
      js << "var template_info=#{@template.json_data};"
      js << "update_template_section();";

      # Gables.
      js << "var has_gables = #{@template.has_gables?};"
      if @template.has_gables?
        gable_list = list_available_gables.map do |g|
          #gable_is_used = @gables[@template.id][g[:name]]
          gable_is_used = @gables.fetch(@template.id, {}).fetch(g[:name], [false, false])
          {
            :name       => g[:name],
            :used_left  => gable_is_used[0],
            :used_right => gable_is_used[1]
          }
        end
        js << "var gable_settings = #{JSON.generate gable_list};"
      end
      js << "update_gable_section();";
      
      # Corners.
      js << "var has_corners = #{@template.has_corners?};"
      js << "var corner_number = #{@path.size};"
      if @template.has_corners?
        corner_list = list_available_corners.map do |g|
          #corner_use = @corners[@template.id][g[:name]]
          corner_use = @corners.fetch(@template.id, {}).fetch(g[:name], [])
          {
            :name       => g[:name],
            :use  => corner_use
          }
        end
        js << "var corner_settings = #{JSON.generate corner_list};"
      end
      js << "update_corner_section();";

      # Margins.
      margins = (0..(@path.size*2-3)).map { |i| (@facade_margins[@template.id] || [])[i].to_s }
      js << "var margins=#{JSON.generate(margins)};"

      # Part replacements.
      available_replacable   = list_available_replacable
      available_replacements = list_available_replacements
      replacement_info = available_replacable.map do |r_able|
        r_ments = available_replacements.select { |r| r[:replaces] == r_able[:name] }
        next if r_ments.empty?
        original_name = r_able[:name]
        available_slots = r_able[:transformations].map { |a| a.size }
      
        replacements = r_ments.map do |r_ment|
          slots = r_ment[:slots]
          next if slots > available_slots.max
          replacement_name = r_ment[:name]
          use = @part_replacements.fetch(@template.id, {}).fetch(original_name, {}).map { |s| (s||[]).map { |v| v  == replacement_name } }
          {
            :replacement_name => replacement_name,
            :slots => slots,
            :use => use
          }
        end
        replacements.compact!
      
        {
          :original_name => original_name,
          :available_slots => available_slots,
          :replacements => replacements
        }
      end
      replacement_info.compact!
      js << "var replacement_info=#{JSON.generate(replacement_info)};"
      js << "update_facade_section();"

      # Material replacement options (based on template component) and current
      # preferences (saved to building).
      material_pairs = list_replaceable_materials.map do |original|
        pair = @material_replacement.find { |e| e[0] == original}
        replacement = pair[1] if pair
        a = [
          {# Original to replace.
            :name => original.display_name,
            :id => original.name,
            :css_string => EneBuildings.material_to_css(original),
            :textured => !original.texture.nil?
          }
        ]
        a << {# Replace preference (if any is set).
          :name => replacement.display_name,
          :id => replacement.name,
          :css_string => EneBuildings.material_to_css(replacement),
          :textured => !replacement.texture.nil?
        } if replacement
        a
      end
      js << "var material_pairs=#{JSON.generate(material_pairs)};"
      js << "update_material_section();";

      # Solids.
      js << "var has_solids = #{@template.has_solids?};"
      js << "var perform_solids = #{@perform_solid_operations};"
      js << "update_solids_section();";

      dlg.execute_script js

    end

    # Show dialog.
    if Sketchup.platform == :platform_win
      dlg.show { add_data.call }
    else
      dlg.show_modal { add_data.call }
    end

    # Start operator.
    # This operator is committed when pressing OK or Apply and aborted when
    # pressing cancel.
    op_name = "Building Properties"
    model.start_operation op_name, true
    
    # HACK: Make a temporary group to apply materials to to load them into
    # model.
    temp_material_group = model.entities.add_group
    temp_material_group.visible = false
    temp_material_group.entities.add_cpoint ORIGIN

    # Closing dialog.
    # Cancels (Abort operation) unless called from "apply" callback.
    set_on_close_called_from_apply = false
    dlg.set_on_close do
      unless set_on_close_called_from_apply
        temp_material_group.erase! if temp_material_group.valid?
        model.abort_operation
      end

      # Close template selector if opened.
      dlg_template.close if dlg_template && dlg_template.visible?

      @@opened_dialogs.delete @group.guid
    end
    
    # Clicking OK or apply buttons.
    dlg.add_action_callback("apply") do |_, close|
      close = close == "close"

      # Call all draw methods.
      draw

      temp_material_group.erase! if temp_material_group.valid?
      model.commit_operation

      if close
        set_on_close_called_from_apply = true
        dlg.close
      else
        model.start_operation op_name, true
      end
    end

    # Clicking cancel button.
    dlg.add_action_callback("cancel") do
      dlg.close
    end

    # Clicking on browse template button.
    # Open building template selector or bring to front if already opened.
    dlg.add_action_callback("browse_template") do
      if dlg_template && dlg_template.visible?
        dlg_template.bring_to_front
      else
        dlg_template = Template.select_panel("Change Template", @template) do |t|
          next unless t
          next if t == @template
          @template = t

          # Update form.
          add_data.call
          dlg.bring_to_front
        end
      end
    end
    
    # Toggling a gable.
    dlg.add_action_callback("toggle_gable") do |_, params|
      set_gable *JSON.parse(params)
    end
    
    # Toggling a corner.
    dlg.add_action_callback("toggle_corner") do |_, params|
      set_corner *JSON.parse(params)
    end
    
    # Setting margin
    dlg.add_action_callback("set_margin") do |_, params|
      index, length = *JSON.parse(params)
      length = length.to_l# TODO: rescue length
      length = nil if length == 0
      set_margin index, length
    end
    
    # Setting part replacement
    dlg.add_action_callback("toggle_replacement") do |_, params|
      original, replacement, segment, index, status = *JSON.parse(params)
      replacement = status ? replacement : nil
      set_replacement original, segment, index, replacement
    end

    # Clicking material replacement button.
    dlg.add_action_callback("replace_material") do |_, original_string|
      original = model.materials[original_string]
      next unless original
      active_m = model.materials.current

      # Make sure active_m is added to model.
      temp_face = temp_material_group.entities.add_face(# FIXME: In SU2015 when applying a material not already defined in the model temp_face refers to the material :S ??? :O
        Geom::Point3d.new(rand, rand, rand),
        Geom::Point3d.new(rand, rand, rand),
        Geom::Point3d.new(rand, rand, rand)
      )
      temp_face.material = active_m
      active_m = temp_face.material

      # Save setting.
      pair = @material_replacement.find { |e| e[0] == original}
      if pair
        # override replacement or remove if active material is nil.
          if active_m
            pair[1] = active_m
          else
            @material_replacement.delete pair
          end
      elsif active_m
        # Create replacement unless active material is nil.
        @material_replacement << [original, active_m]
      end

      # Update preview.
      json =
        if active_m
          JSON.generate({
            :name => active_m.display_name,
            :id => active_m.name,
            :css_string => EneBuildings.material_to_css(active_m),
            :textured => !active_m.texture.nil?
          })
        else
         "null"
        end
      # js = "update_material_section();"# Recreating whole list moves focus.
      js = "update_material_replacment('#{original_string}', #{json});"
      dlg.execute_script js
    end

    # Toggling  solid operations checkbox.
    dlg.add_action_callback("perform_solids") do |_, perform_solids|
      @perform_solid_operations = perform_solids == "true"
    end

    # Misc (UI stuff)

    # Open information website.
    dlg.add_action_callback("openUrl") do
    p @template.source_url
      UI.openURL @template.source_url
    end

    # Open material browser.
    dlg.add_action_callback("browse_materials") do
      UI.show_inspector "Materials"
    end

    # Set dialog position
    dlg.add_action_callback("set_position") do |_, callbacks|
      left, top = callbacks.split(",")
      dlg.set_position left.to_i, top.to_i
    end

    # Update style rule for hovered "apply material" button so thumbnail shows
    # the currently active material.
    # Runs when mouse enters document.
    dlg.add_action_callback("update_style_rule") do
    
      mat_string = EneBuildings.material_to_css model.materials.current
      js = "var selector = '#material_list button:hover div';"
      js << "var property = 'background';"
      js << "var value = \"#{mat_string} !important\";"
      js << "var stylesheet = document.styleSheets[1];"#0th stylesheet is linked, 1st is the embedded.
      js << "var rule_string = selector+'{'+property+':'+value+';}';"
      js << "var rule_index = stylesheet.cssRules.length;"
      js << "stylesheet.insertRule(rule_string, rule_index);"
      dlg.execute_script js

    end

    dlg

  end

  # Public: Saves the instance variables of the building object as attributes to
  # Group so they ca be retrieved when object is later re-initialized.
  # Called from draw.
  #
  # Returns nothing.
  def save_attributes

    # Add all class instance variables as group attributes.
    instance_variables.each do |key|
      next if key == :@group # Do not save group reference.
      value = instance_variable_get(key)
      key = key.to_s  # Make string of symbol
      key[0] = ""     # Remove @ sign from key
      @group.set_attribute ATTR_DICT, key, value
    end

    # Override template object reference with string.
    @group.set_attribute ATTR_DICT, "template", @template ? @template.id : nil

    # Override corner Hash with JSON String.
    @group.set_attribute ATTR_DICT, "corners", JSON.generate(@corners)
    
    # Override gable Hash with JSON String.
    @group.set_attribute ATTR_DICT, "gables", JSON.generate(@gables)
    
    # Override facade_margins Hash with Array.
    @group.set_attribute ATTR_DICT, "facade_margins", @facade_margins.to_a
    
    # Override part_replacements Hash with JSON String.
    @group.set_attribute ATTR_DICT, "part_replacements", JSON.generate(@part_replacements)
    
    # Override material replacements wit string identifiers.
    array = @material_replacement.map { |e| e.map{ |m| m.name } }
    @group.set_attribute ATTR_DICT, "material_replacement", array

    nil

  end

  # Public: Sets whether a specific corner part should be drawn to a specific
  # corner of building.
  #
  # name   - String name of the corner part.
  # index  - Int index of the corner (counting from left, starting at 0).
  #          If index is too high to represent a currently existing corner,
  #          setting will be kept but not affect how buidling is drawn until the
  #          corner exists.
  # status - Boolean whether part should be used.
  #
  # Returns nothing.
  def set_corner(name, index, status)
  
    @corners[@template.id] ||= {}
    @corners[@template.id][name] ||= []
    @corners[@template.id][name][index] = status
    
    @corners[@template.id].delete(name) unless @corners[@template.id][name].any?
    
    nil
    
  end
  
  # Public: Sets whether a specific gable part should be drawn to a specific
  # side of building.
  #
  # name   - String name of the gable part.
  # side   - Int, 0 being left and 1 right.
  # status - Boolean whether part should be used.
  #
  # Returns nothing.
  def set_gable(name, side, status)
  
    @gables[@template.id] ||= {}
    @gables[@template.id][name] ||= []
    @gables[@template.id][name][side] = status
    
    @gables[@template.id].delete(name) unless @gables[@template.id][name].any?
    
    nil
    
  end
  
  # Public: Sets the margin used when aligning or spreading parts in segment.
  #
  # index  - Index of margin counting from left. Odd values represents the left
  #          side of a segment and even the right side.
  # length - A Length or nil when there shouldn't be any margin.
  def set_margin(index, length)
  
    @facade_margins[@template.id] ||= []
    @facade_margins[@template.id][index] = length
    
    @facade_margins[@template.id] = @facade_margins[@template.id].reverse.drop_while {|i| i.nil? }.reverse
    
    nil
  
  end
  
  # Public: Sets replacement for a replaceable part on a given slot by a
  # with a given replacing part.
  #
  # original_name   - String name of the original part to replace.
  # segment         - Int segment index (counting from left, starting at 0).
  #                   If segment index is to high to represent a currently
  #                   existing segment, setting will be kept but not affect how
  #                   buidling is drawn until the segment exists.
  # index           - Int slot index (counting from left, starting at 0).
  #                   If replacment uses several slots, index is of the leftmost
  #                   one. If slot index is to high to represent a currently
  #                   existing slot, setting will be kept but not affect how
  #                   buidling is drawn until the slot exists.
  # replacement     - String name of replacing part or nil when resetting to no
  #                   replacement.
  # purge_colliding - Wether potential colliding replacements (those taking up
  #                   the same slot(s)) should be purged to make space for this
  #                   replacment. A collding replacement that currently wouldn't
  #                   be drawn anyway because it requires slots that doesnn't_array
  #                   currently exist is always purged. (default: false)
  #
  # Returns nothing.
  # Raises RuntimeError if replcement is invalid.
  # Raises RuntimeError if there is a slot collision and purge_colliding is
  # false.
  def set_replacement(original, segment, index, replacement, purge_colliding = false)
  
    # TODO: raise error if slots doesn't even exist.
  
    #if replacement# TODO: Under construction.
    #
    #  replacments = list_available_replacements
    #  replacement_data = replacments.find { |r| r[:name] == replacement }
    #  raise "Unknow replacement '#{replacement}." unless replacement_data
    #  slots = replacement_data[:slots]
    #  collisions = inspect_slots original, segment, index, slots
    #  
    #  # Invalid colldiding replacements (those that aren't drawn anyway because they replaces
    #  # slots that doesn't exist or because they aren't defined by the template)
    #  # can safely be purged.
    #  # TODO: purge...
    #  
    #  # If colliding replacements are either purged or raises error depending on
    #  # purge_colliding
    #  # TODO: implement...
    #  
    #end
        
    part_replacements = (@part_replacements[@template.id] ||= {})
    part_replacements[original] ||= []
    part_replacements[original][segment] ||= []
    part_replacements[original][segment][index] = replacement
    
    part_replacements[original][segment] = nil unless part_replacements[original][segment].any?
    part_replacements.delete(original) unless part_replacements[original].any?
    
    nil
    
  end

  # Internal: List corner parts available for building.
  # Based on Template.
  #
  # Returns Array of Hash objects corresponding to each corner.
  # Hash has reference to definition, name, original_instance and margin.
  def list_available_corners
  
    parts_data = []
    
    @template.component_def.entities.each do |e|
      next unless e.get_attribute(Template::ATTR_DICT_PART, "corner")
      next unless e.get_attribute(Template::ATTR_DICT_PART, "name")
      
      part_data = {
        :defintion => e.definition,
        :original_instance => e,
        :name => e.get_attribute(Template::ATTR_DICT_PART, "name"),
        :margin => e.get_attribute(Template::ATTR_DICT_PART, "corner_margin")
      }
      parts_data << part_data
    end
    
    parts_data.sort_by! { |p| p[:name] || "" }
    
    parts_data
    
  end
  
  # Internal: List gables available for building.
  # Based on Template.
  #
  # Returns Array of Hash objects corresponding to each gable.
  # Hash has reference to definition, name, original_instance and margin.
  def list_available_gables
  
    parts_data = []
    
    @template.component_def.entities.each do |e|
      next unless e.get_attribute(Template::ATTR_DICT_PART, "gable")
      next unless e.get_attribute(Template::ATTR_DICT_PART, "name")
      
      part_data = {
        :defintion => e.definition,
        :original_instance => e,
        :name => e.get_attribute(Template::ATTR_DICT_PART, "name"),
        :margin => e.get_attribute(Template::ATTR_DICT_PART, "gable_margin")
      }
      parts_data << part_data
    end
    
    parts_data.sort_by! { |p| p[:name] || "" }
    
    parts_data
    
  end
  
  # Internal: List replaceable parts (spread and aligned parts) available for
  # this building.
  # Also list the Transformation objects for each part.
  # Based on Template and @path. # TODO: Should also be based on @facade_margins
  #
  # Return Array of Hash objects corresponding to each part.
  # Hash has reference to definition, name, original_instance and
  # transformations Array.
  # Transformations Array has one element for each segment in building.
  # Each element is an Array of Transformation objects.
  # Transformation is in the local coordinate system of the relevant segment
  # group.
  def list_available_replacable

    # Prepare path.
  
    # RVIWEW: Make Path class and move some of this stuff there instead of
    # just having same code copied here from draw_basic.
    
    # Transform path to local building coordinates.
    trans_inverse = @group.transformation.inverse
    path = @path.map { |p| p.transform trans_inverse }

    # Get tangent for each point in path.
    # Tangents point in the positive direction of path.
    tangents = []
    tangents << path[1] - path[0]
    if path.size > 2
      (1..path.size - 2).each do |corner|
        p_prev = path[corner - 1]
        p_here = path[corner]
        p_next = path[corner + 1]
        v_prev = p_here - p_prev
        v_next = p_next - p_here
        tangents << Geom.linear_combination(0.5, v_prev, 0.5, v_next)
      end
    end
    tangents << path[-1] - path[-2]

    # Rotate first and last tangent according to @end_angles.
    tangents.first.transform! Geom::Transformation.rotation ORIGIN, Z_AXIS, @end_angles.first
    tangents.last.transform! Geom::Transformation.rotation ORIGIN, Z_AXIS, @end_angles.last
    
    # If building should be drawn with it back along the path instead of its
    # front, reverse the path and tangents.
    # The terms left and right relates to the building front side.
    if @back_along_path
      path.reverse!
      tangents.reverse!
      tangents.each { |t| t.reverse! }
    end
    
    # Collect parts data.
    
    parts_data = []
    
    # Loop parts in Template's ComponentDefinition.
    @template.component_def.entities.each do |e|
      next unless [Sketchup::Group, Sketchup::ComponentInstance].include? e.class
      next unless ad = e.attribute_dictionary(Template::ATTR_DICT_PART)
      
      part_data = {
        :defintion => e.definition,
        :name => ad["name"],
        :original_instance => e,
        :transformations => []
      }
      parts_data << part_data
      
      transformation_original = e.transformation
      
      # If building is drawn with its back along path, adapt transformation.
      if @back_along_path
        delta_y = -(@template.depth || Template::FALLBACK_DEPTH)
        translation = Geom::Transformation.translation([0, delta_y, 0])
        transformation_original = translation * transformation_original
      end

      origin      = transformation_original.origin
      line_origin = [origin, X_AXIS]
      t_array     = transformation_original.to_a
      
      # Loop path segments.
      (0..path.size - 2).each do |segment_index|
      
        transformations = []
        part_data[:transformations] << transformations
      
        # Values in main building @group's coordinates.
        corner_left    = path[segment_index]
        corner_right   = path[segment_index + 1]
        segment_vector = corner_right - corner_left
        segment_length = segment_vector.length
        tangent_left   = tangents[segment_index]
        tangent_right  = tangents[segment_index + 1]
        segment_trans  = Geom::Transformation.axes(
          corner_left,
          segment_vector,
          Z_AXIS * segment_vector,
          Z_AXIS
        )
        
        # Values in local segment group's coordinates.
        plane_left       = [ORIGIN, tangent_left.reverse.transform(segment_trans.inverse)]
        plane_right      = [[segment_length, 0, 0], tangent_right.transform(segment_trans.inverse)]
        origin_leftmost  = Geom.intersect_line_plane line_origin, plane_left
        origin_rightmost = Geom.intersect_line_plane line_origin, plane_right
        
        # Create Transformation objects from current Transformation, path
        # segment and attribute data.
        if ad["align"]
          # Align one instance
          # Either "left", "right", "center" or percentage (float between 0 and
          # 1).
          
          new_origin =
            if ad["align"] == "left"
              origin_leftmost
            elsif ad["align"] == "right"
             origin_rightmost
            elsif ad["align"] == "center"
              Geom.linear_combination 0.5, origin_leftmost, 0.5, origin_rightmost
            elsif ad["align"].is_a? Float
              Geom.linear_combination(1-ad["align"], origin_leftmost, ad["align"], origin_rightmost)
            end
          t_array[12] = new_origin.x
          transformations << Geom::Transformation.new(t_array)

        elsif ad["spread"]
          # Spread multiple groups/components.
          # Either Fixnum telling number of copies or float/length telling
          # approximate distance between (in inches). This distance will adapt
          # to fit available space.
          
          available_distance = origin_leftmost.distance origin_rightmost
          margin_l = ad["margin_left"] || ad["margin"] || 0
          margin_r = ad["margin_right"] || ad["margin"] || 0
          available_distance -= (margin_l + margin_r)
          if ad["spread"].is_a?(Fixnum)
            total_number = ad["spread"]
            raise "If 'spread' is a Fuxnum it must be zero or more." if total_number < 0
          else
            total_number = available_distance/ad["spread"]
            raise "If 'spread' is a Length it must bigger than zero." unless ad["spread"] > 0
            # Round total_number to closets Int or force to odd/even.
            #(If rounding is set to anything else than "force_odd" it's used as "force_even".)
            total_number =
              if ad["rounding"]
                fraction = total_number%2
                (ad["rounding"] == "force_odd") && fraction > 1 ? total_number.floor : total_number.ceil
              else
                total_number.round
              end
          end
          distance_between = available_distance/total_number
          # Each copy has its origin at x = margin_l + (n + 0.5)*distance_between
          e_def = e.definition
          (0..total_number-1).each do |n|
            x = origin_leftmost.x + margin_l + (n + 0.5) * distance_between
            t_array[12] = x
            trans = Geom::Transformation.new t_array
            # Don't place anything with its bounding box outside the segment if
            # not specifically told to do so.
            unless ad["override_cut_planes"]
              corners = MyGeom.bb_corners(e_def.bounds)
              corners.each { |c| c.transform! trans }
              next if corners.any? { |c| MyGeom.front_of_plane?(plane_left, c) || MyGeom.front_of_plane?(plane_right, c) }
            end
            transformations << trans
          end
          
        end

      end
    
    end
    
    parts_data.sort_by! { |p| p[:name] || "" }
    
    parts_data
    
  end
  
  # Internal: List replacements available for building.
  # Based on Template.
  #
  # Returns Array of Hash objects corresponding to each replacement part.
  # Hash has reference to definition, name, original_instance and slots it uses.
  def list_available_replacements
  
    parts_data = []
    
    @template.component_def.entities.each do |e|
      next unless e.get_attribute(Template::ATTR_DICT_PART, "replacement")
      next unless e.get_attribute(Template::ATTR_DICT_PART, "name")
      next unless e.get_attribute(Template::ATTR_DICT_PART, "replaces")
      
      part_data = {
        :defintion => e.definition,
        :original_instance => e,
        :name => e.get_attribute(Template::ATTR_DICT_PART, "name"),
        :replaces => e.get_attribute(Template::ATTR_DICT_PART, "replaces"),
        :slots => e.get_attribute(Template::ATTR_DICT_PART, "slots", 1)
      }
      parts_data << part_data
    end
    
    parts_data.sort_by! { |p| p[:name] || "" }
    
    parts_data
    
  end
  
  # Internal: List corner parts currently used in building.
  # Based on Template and @corners.
  #
  # Return Array of Hash objects corresponding to each corner part.
  # Hash has reference to definition, name, original_instance and
  # transformations Array.
  # Transformations Array has one element for each segment in building.
  # Each element is an Array of Transformation objects.
  # Transformation is in the local coordinate system of the relevant segment
  # group.
  def list_used_corners

    # Prepare path.
  
    # RVIWEW: Make Path class and move some of this stuff there instead of
    # just having same code copied here from list_available_replacable.
    
    # Transform path to local building coordinates.
    trans_inverse = @group.transformation.inverse
    path = @path.map { |p| p.transform trans_inverse }

    # Get tangent for each point in path.
    # Tangents point in the positive direction of path.
    tangents = []
    tangents << path[1] - path[0]
    if path.size > 2
      (1..path.size - 2).each do |corner|
        p_prev = path[corner - 1]
        p_here = path[corner]
        p_next = path[corner + 1]
        v_prev = p_here - p_prev
        v_next = p_next - p_here
        tangents << Geom.linear_combination(0.5, v_prev, 0.5, v_next)
      end
    end
    tangents << path[-1] - path[-2]

    # Rotate first and last tangent according to @end_angles.
    tangents.first.transform! Geom::Transformation.rotation ORIGIN, Z_AXIS, @end_angles.first
    tangents.last.transform! Geom::Transformation.rotation ORIGIN, Z_AXIS, @end_angles.last
    
    # If building should be drawn with it back along the path instead of its
    # front, reverse the path and tangents.
    # The terms left and right relates to the building front side.
    if @back_along_path
      path.reverse!
      tangents.reverse!
      tangents.each { |t| t.reverse! }
    end
    
    # Collect parts data.
    
    parts_data = list_available_corners
    
    corner_settings = @corners[@template.id] || {}
    parts_data.map! do |part_data|
      part_data = part_data.dup

      next unless a = corner_settings[part_data[:name]]
      next unless a.any?

      transformation_original = part_data[:original_instance].transformation
      
      # If building is drawn with its back along path, adapt transformation.
      # REVIEW: Only transform origin Point3d. Transformation isn't used.
      if @back_along_path
        delta_y = -(@template.depth || Template::FALLBACK_DEPTH)
        translation = Geom::Transformation.translation([0, delta_y, 0])
        transformation_original = translation * transformation_original
      end

      origin      = transformation_original.origin
      line_origin = [origin, X_AXIS]
      
      part_data[:transformations] ||= []
      
      # Loop path segments.
      (0..path.size - 2).each do |segment_index|
      
        transformations = []
        part_data[:transformations] << transformations
        
        # Values in main building @group's coordinates.
        corner_left    = path[segment_index]
        corner_right   = path[segment_index + 1]
        segment_vector = corner_right - corner_left
        segment_length = segment_vector.length
        tangent_left   = tangents[segment_index]
        tangent_right  = tangents[segment_index + 1]
        segment_trans  = Geom::Transformation.axes(
          corner_left,
          segment_vector,
          Z_AXIS * segment_vector,
          Z_AXIS
        )
        
        # Values in local segment group's coordinates.
        tangent_left     = tangent_left.transform(segment_trans.inverse)
        tangent_right    = tangent_right.transform(segment_trans.inverse)
        plane_left       = [ORIGIN, tangent_left.reverse]
        plane_right      = [[segment_length, 0, 0], tangent_right]
        origin_leftmost  = Geom.intersect_line_plane line_origin, plane_left
        origin_rightmost = Geom.intersect_line_plane line_origin, plane_right
        
        # All corner parts expect for that of the last corner is drawn at the
        # left side of the segment group by the same index.
        if a[segment_index]
          transformations << Geom::Transformation.axes(
            origin_leftmost,
            tangent_left,
            Z_AXIS*tangent_left,
            Z_AXIS
          )
        end
        
        # The rightmost corner part is drawn at the right side of the last
        # segment group. This group is the only one that may contain two
        # corner parts.
        if segment_index == (@path.size - 2) && a[segment_index + 1]
          transformations << Geom::Transformation.axes(
            origin_rightmost,
            tangent_right,
            Z_AXIS*tangent_right,
            Z_AXIS
          )
        end
        
      end

      part_data
    end
    parts_data.compact!
    
    parts_data
    
  end
  
  # Internal: List facade elements (replaceable and replacements parts) currently
  # used for this building.
  # Based on list_available_replacable and @part_replacements.
  #
  # Return Array of Hash objects corresponding to each part.
  # Hash has reference to definition, name, original_instance and
  # transformations Array.
  # Transformations Array has one element for each segment in building.
  # Each element is an Array of Transformation objects.
  # Transformation is in the local coordinate system of the relevant segment
  # group.
  def list_used_facade_elements
  
    replaceables  = list_available_replacable
    replacements = list_available_replacements

    if @part_replacements[@template.id]
      replaceables.each do |replaceable|
        next unless @part_replacements[@template.id][replaceable[:name]]
        
        replaceable[:transformations].each_with_index do |transformations, segment|
          next unless transformations
          next unless @part_replacements[@template.id][replaceable[:name]][segment]

          to_delete = []
          transformations.each_with_index do |tr_start, slot|
            replacement_name = @part_replacements[@template.id][replaceable[:name]][segment][slot]
            next unless replacement_name

            replacement_data = replacements.find { |r| r[:name] == replacement_name }
            unless replacement_data
              warn "Unknown replacement '#{replacement_name}'."
              next
            end
            
            if replacement_data[:slots] == 1
              tr = tr_start
            else
              tr_end = transformations[slot + replacement_data[:slots] -1]
              next unless tr_end
              tr = Geom::Transformation.interpolate tr_start, tr_end, 0.5
            end
            
            replacement_data[:transformations] ||= []
            replacement_data[:transformations][segment] ||= []
            replacement_data[:transformations][segment] << tr

            to_delete += (slot..(slot + replacement_data[:slots] -1)).to_a
          end
          to_delete.reverse_each { |i| transformations.delete_at i }
          
        end
        
      end
    end
    
    # Purge replacements that aren't used.
    replacements.keep_if { |r| r[:transformations] }
    
    replaceables + replacements
  
  end
  
  # Internal: List gables currently used in building.
  # Based on Template and @gables.
  #
  # Return Array of Hash objects corresponding to each gable.
  # Hash has reference to definition, name, original_instance and
  # transformations Array.
  # Transformations Array has one element for each segment in building.
  # Each element is an Array of Transformation objects.
  # Transformation is in the local coordinate system of the relevant segment
  # group.
  def list_used_gables
  
    if @back_along_path
      delta_y = -(@template.depth || Template::FALLBACK_DEPTH)
      transformation_left = MyGeom.transformation_axes(
        Geom::Point3d.new(
          - Math.tan(@end_angles[1])*delta_y,
          delta_y,
          0
        ),
        X_AXIS,
        Geom::Vector3d.new(-Math.tan(@end_angles[1]), 1, 0),
        Z_AXIS,
        true,
        true
      )
      transformation_right = MyGeom.transformation_axes(
        Geom::Point3d.new(
          @path[0].distance(@path[1]) - Math.tan(@end_angles[0])*delta_y,
          delta_y,
          0
        ),
        X_AXIS.reverse,
        Geom::Vector3d.new(-Math.tan(@end_angles[0]), 1, 0),
        Z_AXIS,
        true,
        true
      )
    else
      transformation_left = MyGeom.transformation_axes(
        ORIGIN,
        X_AXIS,
        Geom::Vector3d.new(-Math.tan(@end_angles[0]), 1, 0),
        Z_AXIS,
        true,
        true
      )
      transformation_right = MyGeom.transformation_axes(
        Geom::Point3d.new(@path[-1].distance(@path[-2]), 0, 0),
        X_AXIS.reverse,
        Geom::Vector3d.new(-Math.tan(@end_angles[1]), 1, 0),
        Z_AXIS,
        true,
        true
      )
    end
    
    parts_data = list_available_gables
    
    gable_settings = @gables[@template.id] || {}
    parts_data.map! do |part_data|
      part_data = part_data.dup
      
      next unless a = gable_settings[part_data[:name]]
      next unless a.any?
      part_data[:transformations] = (0..@path.length-2).map { [] }
      if a[0]
        part_data[:transformations][0] << transformation_left
      end
      if a[1]
        part_data[:transformations][-1] << transformation_right
      end

      part_data
    end
    parts_data.compact!
    
    parts_data
    
  end
  
  # Internal: Load building group's attributes as Hash.
  # Replaces string references used in attributes with actual objects such as
  # Template and Material.
  #
  # Return Hash.
  def load_attributes_to_hash
  
    h = EneBuildings.attr_dict_to_hash @group, ATTR_DICT, true
    
    # Backward compatibility: Set back_along_path to false if not already set. 
    # The value nil is reserved to let PathHandling handle paths where
    # back_along_path doesn't make any sense, e.g. plots instead of individual
    # buildings.
    h[:back_along_path] ||= false

    # Override template id string with reference to actual object.
    # Nil if not found.
    h[:template] = Template.get_from_id h[:template]
    
    # Override corner JSON String with actual Hash object.
    # Backward compatibility: Set corners to empty Hash if not already set.
    h[:corners] = h[:corners] ? JSON.parse(h[:corners]) : {}

    # Override gable JSON String with actual Hash object.
    # Backward compatibility: Set gables to empty Hash if not already set.
    h[:gables] = h[:gables] ? JSON.parse(h[:gables]) : {}
    
    # Override facade_margins Array with actual Array object.
    # Backward compatibility: Set facade_margins to empty Hash if not already set.
    h[:facade_margins] = h[:facade_margins] ? Hash[h[:facade_margins]] : {}
    
    # Override part replacements JSON String with actual Hash object.
    # Backward compatibility: Set part replacements to empty Hash if not already
    # set.
    h[:part_replacements] = h[:part_replacements] ? JSON.parse(h[:part_replacements]) : {}

    # Override material replacement string identifiers with actual material
    # references.
    model_materials = @group.model.materials
    h[:material_replacement] = (h[:material_replacement] || []).map do |p|
      p.map{ |name| model_materials[name] }
    end
    # Delete replacement pair if replacement Material is nil. Replacer
    # Material becomes nil if it has been deleted from model.
    h[:material_replacement].delete_if { |p| !p[1] }
    
    h
  
  end
  
  # Building drawing methods ordered by the order they should be called in.
  
  # Internal: Draw the volume of the building to @group according to @path and
  # @template.
  #
  # This is the most fundamental of the draw methods.
  # Calling this resets all modifications by any other draw method.
  # When calling this, call the others too.
  # This method has to be called at least once for the other draw methods to
  # have anything to work on.
  #
  # entities     - Entities object (drawing context) to add Building Group to if
  #                not yet drawn (default: current).
  #
  # Returns nothing.
  def draw_volume(entities = nil)

    entities ||= Sketchup.active_model.active_entities

    # Create group if there isn't one.
    if !@group || @group.deleted?
      @group = entities.add_group
    end

    # Prepare for drawing.
    ents = @group.entities
    ents.clear!

    # Transform path to local building coordinates.
    trans_inverse = @group.transformation.inverse
    path = @path.map { |p| p.transform trans_inverse }

    # Get tangent for each point in path.
    # Tangents point in the positive direction of path.
    tangents = []
    tangents << path[1] - path[0]
    if path.size > 2
      (1..path.size - 2).each do |corner|
        p_prev = path[corner - 1]
        p_here = path[corner]
        p_next = path[corner + 1]
        v_prev = p_here - p_prev
        v_next = p_next - p_here
        tangents << Geom.linear_combination(0.5, v_prev, 0.5, v_next)
      end
    end
    tangents << path[-1] - path[-2]

    # Rotate first and last tangent according to @end_angles.
    tangents.first.transform! Geom::Transformation.rotation ORIGIN, Z_AXIS, @end_angles.first
    tangents.last.transform! Geom::Transformation.rotation ORIGIN, Z_AXIS, @end_angles.last
    
    # If building should be drawn with it back along the path instead of its
    # front, reverse the path and tangents.
    # The terms left and right relates to the building front side.
    if @back_along_path
      path.reverse!
      tangents.reverse!
      tangents.each { |t| t.reverse! }
    end
    
    # Loop path segments.
    (0..path.size - 2).each do |segment_index|

      # Values in main building @group's coordinates.
      corner_left    = path[segment_index]
      corner_right   = path[segment_index + 1]
      segment_vector = corner_right - corner_left
      segment_length = segment_vector.length
      tangent_left   = tangents[segment_index]
      tangent_right  = tangents[segment_index + 1]
      segment_trans  = Geom::Transformation.axes(
        corner_left,
        segment_vector,
        Z_AXIS * segment_vector,
        Z_AXIS
      )
      
      # Values in local segment group's coordinates.
      plane_left       = [ORIGIN, tangent_left.reverse.transform(segment_trans.inverse)]
      plane_right      = [[segment_length, 0, 0], tangent_right.transform(segment_trans.inverse)]

      # Place template component in segment and explode it so it can be edited
      # without interfering with template.
      # Shift position along Y axis if the back of the building is what follows
      # the given path and not the front.
      segment_group                = ents.add_group
      segment_group.transformation = segment_trans
      segment_ents                 = segment_group.entities
      component_trans = if @back_along_path
        Geom::Transformation.new [0, -(@template.depth || Template::FALLBACK_DEPTH), 0]
      else
        Geom::Transformation.new
      end
      component_inst = segment_ents.add_instance @template.component_def, component_trans
      component_inst.explode
      
      # Remove all Groups and ComponentInstances from segment.
      # This method only draws the volume and another methods add the details.
      instances = segment_ents.select { |e| [Sketchup::Group, Sketchup::ComponentInstance].include? e.class }
      segment_ents.erase_entities instances

      # Allow material replacement in segment group.
      segment_group.set_attribute Template::ATTR_DICT_PART, "replace_nested_mateials", true

      # Find faces at segment ends.
      faces_left  = segment_ents.select { |e| e.is_a?(Sketchup::Face) && e.normal.samedirection?(X_AXIS.reverse) }
      faces_right = segment_ents.select { |e| e.is_a?(Sketchup::Face) && e.normal.samedirection?(X_AXIS) }
      unless faces_left.size == 1 && faces_right.size == 1
        msg =
          "Invalid building volume. Template root must contain exactly 2 "\
          "gable faces, one with its normal along positive X and one with its "\
          "normal along negative X."
        raise msg
      end
      face_left = faces_left.first
      face_right = faces_right.first

      # Hide walls between segments.
      unless segment_index == 0
        face_left.hidden = true
        face_left.edges.each { |e| e.hidden = true if e.line[1].perpendicular?(Z_AXIS) }
      end
      unless segment_index == path.size - 2
        face_right.hidden = true
        face_right.edges.each { |e| e.hidden = true if e.line[1].perpendicular?(Z_AXIS) }
      end

      # Adapt building volume to fill this segment by moving and shearing side
      # walls.
      
      x_min       = face_left.vertices.first.position.x
      x_max       = face_right.vertices.first.position.x
      edges       = segment_ents.select { |e| e.is_a? Sketchup::Edge }
      edges_left  = edges.select { |e| e.vertices.all? { |v| v.position.x.to_l == x_min } } # All these edges may not bound the left face. For instance Landshövdingehus äldre has a rainwater pipe thingy.
      edges_right = edges.select { |e| e.vertices.all? { |v| v.position.x.to_l == x_max } }
      
      trans_a = Geom::Transformation.new.to_a

      y_axis = plane_left[1]*Z_AXIS
      y_axis.length = 1/Math.cos(y_axis.angle_between(Y_AXIS))
      trans_left = MyGeom.transformation_axes [-x_min, 0, 0], X_AXIS, y_axis, Z_AXIS, true, true
      y_axis = Z_AXIS*plane_right[1]
      y_axis.length = 1/Math.cos(y_axis.angle_between(Y_AXIS))
      trans_right = MyGeom.transformation_axes [segment_length - x_max, 0, 0], X_AXIS, y_axis, Z_AXIS, true, true

      segment_ents.transform_entities trans_left, edges_left
      segment_ents.transform_entities trans_right, edges_right

    end
    
    nil

  end

  # Internal: Draw groups and/or components inside the building @group according
  # to @template, @path, @gables and in the future also part replacement settings.
  #
  # This method modifies the building @group non-destructively.
  # If the replacement setting changes this can be called again without first
  # calling draw_volume to reset what it has previously drawn (unless there are
  # solid operations too to perform).
  # draw_material_replacement should be called after calling this to make sure
  # new groups/components get the right materials.
  #
  # Return nothing.
  def draw_parts
    
    part_data = list_used_facade_elements
    part_data += list_used_gables
    part_data += list_used_corners
   
    segment_groups = @group.entities.to_a

    # Loop path segments.
    (0..path.size - 2).each do |segment_index|
      
      segment_group = segment_groups[segment_index]
      segment_ents  = segment_group.entities
      
      # Purge all existing parts in segment.
      # This method can be called if part settings are changed without first
      # calling draw_volume.
      instances = segment_ents.select { |e| [Sketchup::Group, Sketchup::ComponentInstance].include? e.class }
      segment_ents.erase_entities instances
      
      # Place instances of all spread or aligned parts that has transformations
      # for this segment.
      part_data.each do |part|
        (part[:transformations][segment_index] || []).each do |trans|
          original = part[:original_instance]
          EneBuildings.copy_instance original, segment_ents, trans
        end
      end
      
      # Glue all components to the face they are located on.
      valid_cps = [
        Sketchup::Face::PointInside,
        Sketchup::Face::PointOnEdge,
        Sketchup::Face::PointOnVertex
      ]
      segment_ents.to_a.each do |f|
        next unless f.is_a? Sketchup::Face
        segment_ents.to_a.each do |c|
          next unless c.respond_to? :glued_to
          next if c.glued_to
          t = c.transformation
          next unless f.normal.parallel? t.zaxis
          cp = f.classify_point t.origin
          next unless valid_cps.include? cp
          c.glued_to = f
        end
      end
      
    end
    
    nil
 
  end
  
  # Internal: Perform solid operations on Building if @perform_solid_operations is
  # true.
  #
  # This method modifies the building @group DESTRUCTIVELY.
  # If this has run previously draw_volume must be called before this or
  # draw_parts is called again and draw_material_replacement should be called
  # after.
  #
  # write_status - Write to statusbar that solid operations are performed
  #                (default: true).
  #
  # Returns nothing.
  def draw_solids(write_status = true)

    return unless @perform_solid_operations
    
    segment_groups = @group.entities.select { |e| e.is_a? Sketchup::Group }

    ops = []
    hidden = []

    # List all parts to perform operations with.
    # Parts are listed in all segments before any solid operation is performed
    # so statusbar can show the total number of operations when showing progress.
    segment_groups.each do |segment_group|

      # Find groups and components to perform solid operations with.
      segment_group.entities.to_a.each do |e|
        hidden << e if e.hidden?
        next unless [Sketchup::Group, Sketchup::ComponentInstance].include? e.class
        next unless ad = e.attribute_dictionary(Template::ATTR_DICT_PART)
# FIXME: ad is sometimes an edge :S .
        next unless operation = ad["solid"]
        ops << [e, operation, segment_group]
      end

      # Sort by solid_index.
      # Smallest number first, 0 as default.
      ops.sort_by! do |s|
        s[0].get_attribute(Template::ATTR_DICT_PART, "solid_index", 0)
      end

    end

    nbr_solid_ops = ops.count { |o| o[1] != "cut_multiple_faces" }
    nbr_cutting_ops = ops.size - nbr_solid_ops
    
    # Show all hidden entities to prevent Sketchup popup telling user shown and
    # hidden geometry was merged.
    hidden.each { |e| e.hidden = false }

    # Perform solid operations.
    ops.each_with_index do |s, i|
      part, operation, segment_group = s
	    next if operation == "cut_multiple_faces"

      progress = " (#{i + 1}/#{nbr_solid_ops})"
      Sketchup.status_text = STATUS_SOLIDS + progress if write_status

      # Only allow certain strings as solid operators to prevent code
      # injection from building template.
      next unless %w(union subtract).include? operation

      # "Lift" up to parent drawing context.
      trans = segment_group.transformation * part.transformation
      instance = @group.entities.add_instance part.definition, trans

      # Perform solid operation.
      Solids.send operation, segment_group, instance, false

      # Remove original group/component.
      part.erase!
    end

    # Re-hide geometry.
    # Entities may have been deleted during solid operations or just refer to
    # a small part of the original entity.
    hidden.each { |e| e.hidden = true unless e.deleted? }
	
    # REVIEW: Move multi face cut to external class. Make separate method for copying edges and possibly other geometry.
  
    # Perform own multiple-face cut-opening.
    # Done after solid operations since it's not strictly a solid operation.
    
    Sketchup.status_text = STATUS_CUTTING if write_status
=begin
    segment_groups.each do |segment_group|

      # Copy naked edges of cutting parts into a temporary group and explode it
      # to merge and split them with pre-existing edges.
            
      naked_edge_points = []
      hidden = []
      
      cut_temp_group = segment_group.entities.add_group
      ops.each do |s|
        part, operation, part_segment_group = s
        next unless part_segment_group == segment_group
        next unless operation == "cut_multiple_faces"
                
        naked_edges = EneBuildings.naked_edges part.definition.entities
        original_mirrored = MyGeom.transformation_mirrored? part.transformation
        
        # TODO: wrap drawing welded edges into own method.
        new_vertices = []
        
        naked_edges.each do |edge|
          points = edge.vertices.map { |v| v.position }
          points.each { |p| p.transform! part.transformation }
          points.reverse! if edge.reversed_in?(edge.faces.first)
          points.reverse! if original_mirrored 
          naked_edge_points << points
          
          vertices_or_points = points.map { |p| new_vertices.find{ |v| v.position == p } || p}

          new_edge = cut_temp_group.entities.add_line vertices_or_points
          hidden << new_edge.hidden = edge.hidden?
          
          new_vertices = new_edge.vertices + new_vertices
          new_vertices.uniq!
          
          # Create temporary faces, if possible, to make Sketchup punch holes
          # inside existing faces.
          new_edge.find_faces
        end
        
      end
      
      # make sure the new temporary faces are directed so they later can be
      # identified as faces to cut away.
      cut_temp_group.entities.to_a.each do |f|
        next unless f.is_a? Sketchup::Face
        next unless f.edges.first.reversed_in?(f)
        f.reverse!
      end
      
      # Draw cutting edges in segment group (before temp group is exploded onto
      # them).
      i = 0
      cutting_edges = naked_edge_points.map do |pts|
        edge = segment_group.entities.add_line pts
        edge.hidden = hidden[i]
        i += 1
        edge
      end
      
      exploded = cut_temp_group.explode
      exploded.each { |f| f.erase! if f.is_a?(Sketchup::Face) }
      cutting_edges += exploded.select { |e| e.is_a? Sketchup::Edge }
      
      cutting_edges.uniq!
      cutting_edges.delete_if { |e| e.deleted? }
      
      cut_away_faces = []
      faces_to_keep  = []
      
      # Determine what face should be kept or removed based on edge direction.
      cutting_edges.each do |e|
        e.faces.each do |f|
          if e.reversed_in?(f)
            faces_to_keep << f
          else
            cut_away_faces << f
          end
        end
      end
      
      # Traverse faces sharing a binding edge to list faces to cut away and to
      # keep.
      #
      # If the loop of cutting edges doesn't lie tight onto the original
      # mesh the cut away faces will leak out to the rest of the mesh but the
      # faces to keep will also leak in. That is why faces to keep are also
      # listed.
      #
      # If a face is listed both as a face to keep and a face to remove it is
      # because cutting loops overlap. Delete those faces.
      faces_to_keep -= cut_away_faces
      cut_away_faces = EneBuildings.connected_faces cut_away_faces, cutting_edges
      faces_to_keep = EneBuildings.connected_faces faces_to_keep, cutting_edges
      cut_away_faces -= faces_to_keep

      cut_away_edges = cut_away_faces.map { |f| f.edges }.flatten.uniq
      cut_away_edges.keep_if { |e| (e.faces - cut_away_faces).empty? }
      
      cut_away_faces.each { |f| f.hidden = true }
      cut_away_edges.each { |f| f.hidden = true }
      
      segment_group.entities.erase_entities cut_away_faces.map { |f| f.get_glued_instances }.flatten
      
    end
=end


    segment_groups.each do |segment_group|
    
      # Copy naked edges on cutting parts into parent drawing context and keep
      # reference to new edges.
      # Also keep references to the end points of each edge, in normalized
      # order, to later determine which faces are inside the cutting edges.
      cutting_edges = []
      cutting_edge_points = []
      ops.each do |s|
        part, operation, part_segment_group = s
        next unless part_segment_group == segment_group
        next unless operation == "cut_multiple_faces"
        
        Sketchup.status_text = STATUS_CUTTING if write_status
        
        naked_edges = EneBuildings.naked_edges part.definition.entities
        original_mirrored = MyGeom.transformation_mirrored? part.transformation
        
        naked_edges.each do |edge|
          points = edge.vertices.map { |v| v.position }
          points.each { |p| p.transform! part.transformation }
          points.reverse! if edge.reversed_in?(edge.faces.first)
          points.reverse! if original_mirrored
          cutting_edge_points << points
          
          new_edge = segment_group.entities.add_line points
          new_edge.hidden = edge.hidden?
          cutting_edges << new_edge
        end
        
      end
      
      # HACK: Run intersect to split edges where they cross and punch holes in
      # faces. Would be much much very much faster if the geometry merger
      # that runs after each tool operation in SU could be called directly.
      #
      # Use attributes for referencing cutting edges since attributes
      # are kept on both sides when an edge is split.
      # Life would be easier if the internal geometry merger thing could be
      # called as somehow return the relationship between new entities
      # and the entities they are split off from.
      cutting_edges.each { |e| e.set_attribute ID, "cutting_edges", true }
      cutting_edges += segment_group.entities.intersect_with(
        false,
        Geom::Transformation.new,
        segment_group.entities,
        Geom::Transformation.new,
        true,
        cutting_edges
      )
      cutting_edges.keep_if { |e| e.valid? }
      cutting_edges += segment_group.entities.select { |e| e.get_attribute ID, "cutting_edges" }
      cutting_edges.uniq!

      # MUCH HACK: Do the freaking thing again if some of the cutting edges are
      # still free standing. When some cutting objects touches the outer loops
      # of a face somehow the the intersect method fucks up with finding inside
      # loops for that face.
      free_cutting_edges = cutting_edges.select { |e| e.faces.empty? }
      unless free_cutting_edges.empty?
        cutting_edges += segment_group.entities.intersect_with(
          false,
          Geom::Transformation.new,
          segment_group.entities,
          Geom::Transformation.new,
          true,
          free_cutting_edges
        )
        cutting_edges.keep_if { |e| e.valid? }
        cutting_edges += segment_group.entities.select { |e| e.get_attribute ID, "cutting_edges" }
        cutting_edges.uniq!
      end

      # Loop cutting edges an look for bounded faces that are "inside" the
      # cutting edge.
      cut_away_faces = []
      faces_to_keep  = []
      cutting_edges.each do |e|
        # Edge can be marked as deleted if merged with another edge.
        next unless e.valid?
        
        edge_points = e.vertices.map { |v| v.position }
        matches_as_non_reversed = cutting_edge_points.include?(edge_points)
        matches_as_reversed = cutting_edge_points.include?(edge_points.reverse)
        
        # If edge has been split it doesn't match any pair of points and no
        # face can be found from it. If any of the edges of a loop is intact
        # all faces inside will be found later on.
        next unless matches_as_non_reversed || matches_as_reversed
        next if matches_as_non_reversed && matches_as_reversed
        
        reversed = matches_as_reversed
        e.faces.each do |face|
          if e.reversed_in?(face) == reversed
            cut_away_faces << face
          else
            faces_to_keep << face
          end
        end
      end
      
      # Traverse faces sharing a binding edge to list faces to cut away and to
      # keep.
      #
      # If the loop of cutting edges doesn't lie tight onto the original
      # mesh the cut away faces will leak out to the rest of the mesh but the
      # faces to keep will also leak in. That is why faces to keep are also
      # listed.
      #
      # If a face is listed both as a face to keep and a face to remove it is
      # because cutting loops overlap. Delete those faces.
      faces_to_keep -= cut_away_faces
      cut_away_faces = EneBuildings.connected_faces cut_away_faces, cutting_edges
      faces_to_keep = EneBuildings.connected_faces faces_to_keep, cutting_edges
      cut_away_faces -= faces_to_keep

      cut_away_edges = cut_away_faces.map { |f| f.edges }.flatten.uniq
      cut_away_edges.keep_if { |e| (e.faces - cut_away_faces).empty? }
      
      cut_away_faces.each { |f| f.hidden = true }
      cut_away_edges.each { |f| f.hidden = true }
      
      segment_group.entities.erase_entities cut_away_faces.map { |f| f.get_glued_instances }.flatten
      
    end
    
    
    
    

    nil

  end

  # Internal: Replaces materials in building @group according to
  # @material_replacement.
  #
  # This method modifies the building @group non-destructively.
  # If the material replacement settings changes this can be called again
  # without having to call any other draw methods.
  #
  # Returns nothing.
  def draw_material_replacement

    # Hash of replacements. Original as key and replacement as value.
    # Used for faster indexing.
    replacements  = Hash[*@material_replacement.flatten]

    # Recursive material replacer.
    # Replace materials in group and in all nested groups with an attribute
    # specifically telling it to do so.
    recursive = lambda do |group|
      group.name += ""# Make group unique.
      group.entities.each do |e|
        next unless e.respond_to? :material
        original_name = e.get_attribute(Template::ATTR_DICT_PART, "original_material")
        original = if original_name
          @group.model.materials[original_name]
        else
          e.material
        end
        replacment = replacements[original]
        if replacment
          e.material = replacment
          e.set_attribute(Template::ATTR_DICT_PART, "original_material", original.name)
        elsif e.material != original && original.valid?
          e.material = original
        end

        if e.is_a?(Sketchup::Group) && e.get_attribute(Template::ATTR_DICT_PART, "replace_nested_mateials")# OPTIMIZE: edit groups using same definition once. Create one new definition for all instances in this building (this entities collection)
          recursive.call(e)
        end
      end
    end

    # Replace materials in all groups in building root (segments, corner etc).
    recursive.call @group

    nil

  end

end

end
