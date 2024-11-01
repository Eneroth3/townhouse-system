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

  # Public: Gets/sets rotation of gables.
  # Array containing 2 angels in radians cc seen from above.
  attr_accessor :end_angles

  # Public: Returns Group Building is drawn to.
  attr_reader :group

  # Public: Gets/set material replacements.
  # Hash of replacement Materials indexed by original Material to replace.
  attr_accessor :material_replacement

  # Public: Gets/sets path Building is drawn to in local coordinates of the
  # parent  drawing context (e.g. model root or a group representing a
  # property). When group is manually moved in SU the path will be transformed
  # along with it and be updated next time an object is loaded from it.
  # Make sure all points have same z value.
  attr_accessor :path

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
      
      # Defines how interioer corners should be drawn.
      # Variable is Hash indexed by Template id String.
      # Each value is an Array with elements corresponding to interior corners
      # listed from left ro right.
      # Elements is nil for sharp corners or a Hash conatining keys :type
      # and length when a transition is used. Valid types are
      # "chamfer_d" and "chamfer_p".
      @corner_transitions = {}

      @suggest_corner_transitions = true

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

      @suggest_margins = true

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

      # Hash of replacement Materials indexed by original Material to replace.
      @material_replacement = {}

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
      @corner_transitions       != last_drawn_as[:corner_transitions] ||
      (
        @template.has_solids? &&
        last_drawn_as[:perform_solid_operations] &&
        (
          @gables  != last_drawn_as[:gables] ||
          @corners != last_drawn_as[:corners] ||
          !@facade_margins.eql?(last_drawn_as[:facade_margins]) || # Using eql? because Length == nil comparision raises error.
          @part_replacements != last_drawn_as[:part_replacements]
        )
      )
    )
      # Complete redraw
      draw_volume
      draw_parts
      draw_solids write_status
      draw_material_replacement
    elsif(
      @gables  != last_drawn_as[:gables] ||
      @corners != last_drawn_as[:corners] ||
      !@facade_margins.eql?(last_drawn_as[:facade_margins]) ||
      @part_replacements != last_drawn_as[:part_replacements]
    )
      # Part redraw (keep volume)
      draw_parts
      draw_material_replacement
    else
      # Replace materials only (keep parts and volume)
      draw_material_replacement
    end

    save_attributes

    Sketchup.status_text = STATUS_DONE if write_status

    nil

  end

  # Public: List corner parts.
  # A part is either a Group or ComponentInstance.
  #
  # calculate_transformations - Whether transformations should be calculated
  #                             for part placement (default: false).
  #
  # Returns Array of Hash objects corresponding to each corner part.
  # Hash contains the following:
  #   :definition         - ComponetDefinition defining the part.
  #   :name               - String name used to identify part.
  #   :original_instance  - Group or ComponentInstance defining the part inside
  #                         the Template's ComponentDefinition.
  #   :margin             - Facade margin Length suggested for this corner.
  #   :skewed             - true when the part should be skewed with X and
  #                         Y axes along following building path, false
  #                         when part should be drawn with Y axis along
  #                         bisector of corner.
  #   :use                - Array of booleans telling what corners this part
  #                         should be drawn to.
  #   :transition_type    - #TODO: Document!
  #   :transition_length  -
  #   :transformations    - (Only when calculate_transformations is true)
  #                        Transformations object defining instance placement
  #                        in local coordinates grouped by building segment.
  def list_corner_parts(calculate_transformations = false)

    corner_settings = @corners[@template.id] || {}

    parts_data = []

    @template.component_def.entities.each do |e|
      next unless e.get_attribute(Template::ATTR_DICT_PART, "corner")
      next unless name = e.get_attribute(Template::ATTR_DICT_PART, "name")
      use = corner_settings[name] || []

      part_data = {
        :definition => e.definition,
        :original_instance => e,
        :name => name,
        :use => use,
        :margin => e.get_attribute(Template::ATTR_DICT_PART, "corner_margin"),
        :skewed => !!e.get_attribute(Template::ATTR_DICT_PART, "corner_skewed"),
        :transition_type => e.get_attribute(Template::ATTR_DICT_PART, "transition_type"),
        :transition_length => e.get_attribute(Template::ATTR_DICT_PART, "transition_length")
      }

      parts_data << part_data
    end

    parts_data.sort_by! { |p| p[:name] || "" }

    if calculate_transformations
      calculate_corner_transformations parts_data
    end

    parts_data

  end

  # Public: List gable parts.
  # A part is either a Group or ComponentInstance.
  #
  # calculate_transformations - Whether transformations should be calculated
  #                             for part placement (default: false).
  #
  # Returns Array of Hash objects corresponding to each gable part.
  # Hash contains the following:
  #   :definition        - ComponetDefinition defining the part.
  #   :name              - String name used to identify part.
  #   :original_instance - Group or ComponentInstance defining the part inside
  #                        the Template's ComponentDefinition.
  #   :margin            - Facade margin Length suggested for this gable.
  #   :use               - Array of booleans telling what sides this part
  #                        should be drawn to.
  #   :transformations   - (Only when calculate_transformations is true)
  #                        Transformations object defining instance placement
  #                        in local coordinates grouped by building segment.
  def list_gable_parts(calculate_transformations = false)

    gable_settings = @gables[@template.id] || {}

    parts_data = []

    @template.component_def.entities.each do |e|
      next unless e.get_attribute(Template::ATTR_DICT_PART, "gable")
      next unless name = e.get_attribute(Template::ATTR_DICT_PART, "name")
      use = gable_settings[name] || []

      part_data = {
        :definition => e.definition,
        :original_instance => e,
        :name => name,
        :use => use,
        :margin => e.get_attribute(Template::ATTR_DICT_PART, "gable_margin")
      }
      parts_data << part_data
    end

    parts_data.sort_by! { |p| p[:name] || "" }

    if calculate_transformations
      calculate_gable_transformations parts_data
    end

    parts_data

  end

  # Public: List replaceable parts.
  # A part is either a Group or ComponentInstance.
  # A part is replaceable if it's positioning is either array, align, center or
  # relative.
  #
  # calculate_transformations - Whether transformations should be calculated
  #                             for part placement (default: false).
  #
  # Returns Array of Hash objects corresponding to each replaceable part.
  # Hash contains the following:
  #   :definition        - ComponetDefinition defining the part.
  #   :name              - String name used to identify part.
  #   :original_instance - Group or ComponentInstance defining the part inside
  #                        the Template's ComponentDefinition.
  #   :transformations   - (Only when calculate_transformations is true)
  #                        Transformations object defining instance placement
  #                        in local coordinates grouped by building segment.
  def list_replaceable_parts(calculate_transformations = false)

    # Aligned (left, right, center and percentage) and "spread" (arrayed) parts
    # are considered replaceable. Other parts like gables and corners are only
    # drawn when actively enabled in building properties.
    replaceable_attributes = ["align", "spread"]

    parts_data = []

    @template.component_def.entities.each do |e|
      next unless ad = e.attribute_dictionary(Template::ATTR_DICT_PART)
      next unless replaceable_attributes.any? { |a| ad[a] }

      part_data = {
        :definition => e.definition,
        :original_instance => e,
        :name => ad["name"]
      }
      parts_data << part_data
    end

    parts_data.sort_by! { |p| p[:name] || "" }

    if calculate_transformations
      calculate_replaceable_transformations parts_data
    end

    parts_data

  end

  # Public: List replacement parts.
  # A part is either a Group or ComponentInstance.
  #
  # Returns Array of Hash objects corresponding to each replacement part.
  # Hash contains the following:
  #   :definition        - ComponetDefinition defining the part.
  #   :name              - String name used to identify part.
  #   :original_instance - Group or ComponentInstance defining the part inside
  #                        the Template's ComponentDefinition.
  #   :replaces          - String named used to identify what part this one
  #                        replaces.
  #   :slots             - Integer of how many instances if the replaceable part
  #                        this one replaces.
  def list_replacement_parts

    parts_data = []

    @template.component_def.entities.each do |e|
      next unless e.get_attribute(Template::ATTR_DICT_PART, "replacement")
      next unless replaces = e.get_attribute(Template::ATTR_DICT_PART, "replaces")
      next unless name = e.get_attribute(Template::ATTR_DICT_PART, "name")

      part_data = {
        :definition => e.definition,
        :original_instance => e,
        :name => name,
        :replaces => replaces,
        :slots => e.get_attribute(Template::ATTR_DICT_PART, "slots", 1)
      }
      parts_data << part_data
    end

    parts_data.sort_by! { |p| p[:name] || "" }

    parts_data

  end

  # Public: List the used replacement parts and the kept replaceable parts.
  # A part is either a Group or ComponentInstance.
  #
  # calculate_transformations - Whether transformations should be calculated
  #                             for part placement (default: false).
  #
  # Returns Array of Hash objects corresponding to each part.
  # Hash contains the following:
  #   :definition        - ComponetDefinition defining the part.
  #   :name              - String name used to identify part.
  #   :original_instance - Group or ComponentInstance defining the part inside
  #                        the Template's ComponentDefinition.
  #   :transformations   - Transformations object defining instance placement
  #                        in local coordinates grouped by building segment.
  def list_replaced_parts

    replaceables = list_replaceable_parts true
    replacements = list_replacement_parts

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

    parts = replaceables + replacements

    # Purge references to available slots and other irrelevant values.
    allowed_keys = %i(definition name original_instance transformations)
    parts.map! { |p| p.select { |k, v| allowed_keys.include? k } }

    parts

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
      
      js << "remember_active_element();"

      # Template info.
      js << "var template_info=#{JSON.generate(@template.to_hash)};"
      js << "update_template_section();";

      # Gables.
      js << "var has_gable_parts = #{@template.has_gables?};"
      if @template.has_gables?
        gable_list = list_gable_parts.map do |g|
          {
            :name => g[:name],
            :use  => g[:use]
          }
        end
        js << "var gable_part_settings = #{JSON.generate gable_list};"
      end
      js << "update_gable_section();";

      # Corners.
      js << "var has_corner_parts = #{@template.has_corners?};"
      js << "var corner_number = #{@path.size};"
      if @template.has_corners?
        corner_list = list_corner_parts.map do |c|
          {
            :name => c[:name],
            :use  => c[:use]
          }
        end
        js << "var corner_part_settings = #{JSON.generate corner_list};"
      end
      corner_transitions = @corner_transitions[@template.id] || []
      js << "var corner_transitions=#{JSON.generate(corner_transitions)};"
      js << "var suggest_corner_transitions = #{@suggest_corner_transitions};"
      js << "update_corner_section();";

      # Margins.
      margins = (0..(@path.size*2-3)).map { |i| (@facade_margins[@template.id] || [])[i].to_s }
      js << "var margins=#{JSON.generate(margins)};"
      js << "var suggest_margins=#{@suggest_margins};"

      # Part replacements.
      available_replacable   = list_replaceable_parts true
      available_replacements = list_replacement_parts
      js << "var has_facade_elements = #{!list_replaceable_parts.empty?};"
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
      material_pairs = @template.list_replaceable_materials.map do |original|
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

      js << "fous_element();"
      
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

    temp_material_group = nil

    # Closing dialog.
    # Cancels (Abort operation) unless called from "apply" callback.
    set_on_close_called_from_apply = false
    dlg.set_on_close do
      unless set_on_close_called_from_apply
        temp_material_group.erase! if temp_material_group && temp_material_group.valid?
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

      temp_material_group.erase! if temp_material_group && temp_material_group.valid?
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
          suggest_margins if @suggest_margins
          add_data.call
          dlg.bring_to_front
        end
      end
    end

    # Toggling a gable.
    dlg.add_action_callback("toggle_gable") do |_, params|
      set_gable *JSON.parse(params)
      if @suggest_margins
        suggest_margins
        add_data.call
      end
    end

    # Toggling a corner.
    dlg.add_action_callback("toggle_corner") do |_, params|
      set_corner *JSON.parse(params)
      if @suggest_margins || @suggest_corner_transitions
        suggest_margins if @suggest_margins
        suggest_corner_transitions if @suggest_corner_transitions
        add_data.call
      end
    end
    
    # Change corner transition type.
    dlg.add_action_callback("set_corner_transition_type") do |_, params|
      set_corner_transition_type *JSON.parse(params)
      @suggest_corner_transitions = false
      add_data.call
    end
    
    # Change corner transition length.
    dlg.add_action_callback("set_corner_transition_length") do |_, params|
      index, length = *JSON.parse(params)
      begin
        length = length.to_l
      rescue ArgumentError
        # Do nothing.
      else
        length = 0.to_l if length < 0
        set_corner_transition_length index, length
        @suggest_corner_transitions = false
        add_data.call
      end
    end
    
    # Toggle transition suggestions.
    dlg.add_action_callback("toggle_suggest_corner_transitions") do |_, params|
      status = params == "true"
      @suggest_corner_transitions = status
      if @suggest_corner_transitions
        suggest_corner_transitions
        add_data.call
      end
    end

    # Setting margin
    dlg.add_action_callback("set_margin") do |_, params|
      index, length = *JSON.parse(params)
      begin
        length = length.to_l
      rescue ArgumentError
        # Do nothing.
      else
        length = nil if length == 0
        set_margin index, length
        @suggest_margins = false
        add_data.call
      end
    end

    # Toggle margin suggestions.
    dlg.add_action_callback("toggle_suggest_margins") do |_, params|
      status = params == "true"
      @suggest_margins = status
      if @suggest_margins
        suggest_margins
        add_data.call
      end
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

      # Make sure active_m exists model.
      # HACK: Make a temporary group to apply materials to to load them into
      # model.
      unless temp_material_group && temp_material_group.valid?
        temp_material_group = model.entities.add_group
        temp_material_group.visible = false
        temp_material_group.entities.add_cpoint ORIGIN
      end
      temp_face = temp_material_group.entities.add_face(# FIXME: In SU2015 when applying a material not already defined in the model temp_face refers to the material :S ??? :O
        Geom::Point3d.new(rand, rand, rand),
        Geom::Point3d.new(rand, rand, rand),
        Geom::Point3d.new(rand, rand, rand)
      )
      temp_face.material = active_m
      active_m = temp_face.material

      # Save setting.
      if active_m
        @material_replacement[original] = active_m
      else
        @material_replacement.delete original
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

    # Override non-supported objects by serialized versions, e.g. String identifier, JSON String or Array.
    @group.set_attribute ATTR_DICT, "template", @template ? @template.id : nil
    @group.set_attribute ATTR_DICT, "corners", JSON.generate(@corners)
    corner_transitions = Hash[@corner_transitions.map { |k, v|
      [k, v.map { |c| next unless c; c = c.dup; c["length"] = c["length"].to_f; c }]
    }]
    @group.set_attribute ATTR_DICT, "corner_transitions", JSON.generate(corner_transitions)
    @group.set_attribute ATTR_DICT, "gables", JSON.generate(@gables)
    @group.set_attribute ATTR_DICT, "facade_margins", @facade_margins.to_a
    @group.set_attribute ATTR_DICT, "part_replacements", JSON.generate(@part_replacements)
    array = @material_replacement.to_a.map { |e| e.map{ |m| m.name } }
    @group.set_attribute ATTR_DICT, "material_replacement", array

    nil

  end

  # Public: Sets facade margins to whatever is the biggest suggested margin for
  # a used adjacent gable or corner part.
  #
  # Returns nothing.
  def suggest_margins

    corners = list_corner_parts
    gables  = list_gable_parts

    @facade_margins[@template.id] = (0..(@path.size*2-3)).map do |i|
      segment = i/2 # Integer division.
      side    = i%2 # 0 = left, 1 = right.
      corner  = segment + side
      first   = i == 0
      last    = i == @path.size*2-3

      margins = corners.select{ |c| c[:use][corner] }.map { |c| c[:margin] }

      if first || last
        margins +=  gables.select{ |g| g[:use][side] }.map { |g| g[:margin] }
      end

      margins.compact.max
    end

    nil

  end

  # Public: Sets corner transition type and length based on used corner parts.
  #
  # returns nothings.
  def suggest_corner_transitions
  
    corners = list_corner_parts
    
    (0..@path.size-2).each do |i|
    
      corner = i+1
      used_corner_parts = corners.select{ |c| c[:use][corner] }
      
      # Use the values of the first found corner that has any saved preferences
      # for transition.
      used_corner = used_corner_parts.find { |c| c[:transition_type] && c[:transition_length] }

      @corner_transitions[@template.id] ||= []
      @corner_transitions[@template.id][i] =
        if used_corner
          {
            "type" =>   used_corner[:transition_type],
            "length" => used_corner[:transition_length]
          }
        else
          nil
        end
      
    end
  
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

  # Public: Sets what length a transition for a specific corner should use.
  # Only applies to corners between facades, not building ends.
  #
  # index  - Int index of the corner (counting from left, starting at 0).
  # length - Length used for transition. How length is interpreted depends on
  #          what type has been set in #set_corner_transition_type.
  #
  # Returns nothing.
  def set_corner_transition_length(index, length)
  
    @corner_transitions[@template.id] ||= []
    @corner_transitions[@template.id][index] ||= {}
    @corner_transitions[@template.id][index]["length"] = length
    
    nil
  
  end
  
  # Public: Sets what kind of transition to use on a specific corner.
  # Only applies to corners between facades, not building ends.
  #
  # index - Int index of the corner (counting from left, starting at 0).
  # type  - String "chamfer_d", "chamfer_p" or nil.
  #         chamfer_d uses Length set by #set_corner_transition_length as the
  #         diagonal length and chamfer_p uses it as the projected length on the
  #         facade plane.
  #         Nil means no transition (sharp corner).
  #
  # returns nothing.
  def set_corner_transition_type(index, type)
  
    @corner_transitions[@template.id] ||= []
    if type
      @corner_transitions[@template.id][index] ||= {}
      @corner_transitions[@template.id][index]["type"] = type
    else
      @corner_transitions[@template.id][index] = nil
    end
    
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
  #                   building is drawn until the segment exists.
  # index           - Int slot index (counting from left, starting at 0).
  #                   If replacement uses several slots, index is of the leftmost
  #                   one. If slot index is to high to represent a currently
  #                   existing slot, setting will be kept but not affect how
  #                   building is drawn until the slot exists.
  # replacement     - String name of replacing part or nil when resetting to no
  #                   replacement.
  # purge_colliding - Werther potential colliding replacements (those taking up
  #                   the same slot(s)) should be purged to make space for this
  #                   replacement. A colliding replacement that currently wouldn't
  #                   be drawn anyway because it requires slots that doesnn't_array
  #                   currently exist is always purged. (default: false)
  #
  # Returns nothing.
  # Raises RuntimeError if replacement is invalid.
  # Raises RuntimeError if there is a slot collision and purge_colliding is
  # false.
  def set_replacement(original, segment, index, replacement, purge_colliding = false)# TODO: lock over purge_colliding and docs.

    if replacement
      available_replacements = list_replacement_parts
      replacement_info = available_replacements.find { |r| r[:name] == replacement }
      unless replacement_info
        raise ArgumentError, "Unknown replacement '#{replacement}'."
      end
      slots = replacement_info[:slots]
    else
      slots = 1
    end

    part_replacements = (@part_replacements[@template.id] ||= {})
    part_replacements[original] ||= []
    part_replacements[original][segment] ||= []
    part_replacements[original][segment][index] = replacement

    # HACK: Empty extra slots used if multi slot replacement.
    # When called from the properties panel the javascript prevents collisions
    # with replacements to the left. Those to the right however could use slots
    # that doesn't exist with the current segment length and therefore aren't
    # sent to the javascript side. For now collisions are prevented here only if
    # they couldn't be prevented in javascript which gives this method an odd,
    # asymmetric behavior that doesn't make much sense when called from the
    # planned public API.
    # TODO: API: Improve this behavior (or document better).
    if slots > 1
      (index+1..index+slots-1).each do |i|
        part_replacements[original][segment][i] = nil
      end
    end

    part_replacements[original][segment] = nil unless part_replacements[original][segment].any?
    part_replacements.delete(original) unless part_replacements[original].any?

    nil

  end

  # Internal: Adds corner Transformation information to parts_data Array.
  #
  # parts_data - The Array to add transformations to.
  #
  # Returns nil.
  def calculate_corner_transformations(parts_data)

    segments_info = calculate_segment_info

    parts_data.each do |part_data|

      part_data[:transformations] ||= []

      next unless part_data[:use].any?

      tr_original = part_data[:original_instance].transformation

      # If building is drawn with its back along path, adapt transformation.
      if @back_along_path
        delta_y = -(@template.depth || Template::FALLBACK_DEPTH)
        translation = Geom::Transformation.translation([0, delta_y, 0])
        tr_original = translation * tr_original
      end

      origin      = tr_original.origin
      line_origin = [origin, X_AXIS]

      # Loop path segments.
      (0..@path.size - 2).each do |segment_index|
      
        segment_info = segments_info[segment_index]
        #first_segment = segment_index == 0
        last_segment  = segment_index == @path.size - 2

        transformations = []
        part_data[:transformations] << transformations

        plane_left  = segment_info[:plane_left]
        plane_right = segment_info[:plane_right]
        pt_left  = Geom.intersect_line_plane line_origin, plane_left
        pt_right = Geom.intersect_line_plane line_origin, plane_right

        # All corner parts expect for that of the last corner is drawn at the
        # left side of the segment group by the same index.
        if part_data[:use][segment_index]
          if part_data[:skewed]
            transformations << MyGeom.transformation_axes(
              pt_left,
              X_AXIS,
              segment_info[:adjacent_vector_left],
              Z_AXIS,
              false,
              true
            )
          else
            transformations << Geom::Transformation.axes(
              pt_left,
              segment_info[:tangent_left],
              Z_AXIS*segment_info[:tangent_left],
              Z_AXIS
            )
          end
          
        end

        # The rightmost corner part is drawn at the right side of the last
        # segment group. This group is the only one that may contain two
        # corner parts.
        if last_segment && part_data[:use][segment_index + 1]
          if part_data[:skewed]
            transformations << MyGeom.transformation_axes(
              pt_right,
              segment_info[:adjacent_vector_right],
              X_AXIS.reverse,
              Z_AXIS,
              false,
              true
            )
          else
            transformations << Geom::Transformation.axes(
              pt_right,
              segment_info[:tangent_right],
              Z_AXIS*segment_info[:tangent_right],
              Z_AXIS
            )
          end
        end

      end

    end

    nil

  end

  # Internal: Adds gable Transformation information to parts_data Array.
  #
  # parts_data - The Array to add transformations to.
  #
  # Returns nil.
  def calculate_gable_transformations(parts_data)

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

    parts_data.each do |part_data|

      part_data[:transformations] = []

      next unless part_data[:use].any?

      part_data[:transformations] = (0..@path.length-2).map { [] }
      if part_data[:use][0]
        part_data[:transformations][0] << transformation_left
      end
      if part_data[:use][1]
        part_data[:transformations][-1] << transformation_right
      end

    end

    nil

  end

  # Internal: Adds arrayed and aligned Transformation information to parts_data
  # Array.
  #
  # parts_data - The Array to add transformations to.
  #
  # Returns nil.
  def calculate_replaceable_transformations(parts_data)

    segments_info = calculate_segment_info

    parts_data.each do |part_data|

      part_data[:transformations] ||= []

      original    = part_data[:original_instance]
      tr_original = original.transformation

      # If building is drawn with its back along path, adapt transformation.
      if @back_along_path
        delta_y = -(@template.depth || Template::FALLBACK_DEPTH)
        translation = Geom::Transformation.translation([0, delta_y, 0])
        tr_original = translation * tr_original
      end

      tr_original_ary = tr_original.to_a
      ad = original.attribute_dictionary(Template::ATTR_DICT_PART)

      origin      = tr_original.origin
      line_origin = [origin, X_AXIS]

      # Loop path segments.
      (0..@path.size - 2).each do |segment_index|
      
        segment_info = segments_info[segment_index]

        transformations = []
        part_data[:transformations] << transformations
        
        # Project origin point to side planes and find outermost point in each
        # direction.
        pts_left     = segment_info[:planes_left].map { |p| Geom.intersect_line_plane line_origin, p}
        pts_right    = segment_info[:planes_right].map { |p| Geom.intersect_line_plane line_origin, p}
        pt_leftmost  = pts_left.max_by { |p| p.x }
        pt_rightmost = pts_right.min_by { |p| p.x }
        
        # Take facade margin into account.
        margin_left  = (@facade_margins[@template.id] || [])[2*segment_index]
        margin_right = (@facade_margins[@template.id] || [])[2*segment_index+1]
        pt_leftmost.offset!(X_AXIS, margin_left) if margin_left
        pt_rightmost.offset!(X_AXIS, -margin_right) if margin_right

        # Skip segment for this part if leftmost is to the right of rightmost.
        unless (pt_rightmost-pt_leftmost).samedirection?(X_AXIS)
          next
        end

        # Create Transformations.
        if ad["align"]
          # Align one instance.
          # Either "left", "right", "center" or percentage (float between 0 and
          # 1).

          new_origin =
            if ad["align"] == "left"
              pt_leftmost
            elsif ad["align"] == "right"
             pt_rightmost
            elsif ad["align"] == "center"
              Geom.linear_combination 0.5, pt_leftmost, 0.5, pt_rightmost
            elsif ad["align"].is_a? Float
              Geom.linear_combination(1-ad["align"], pt_leftmost, ad["align"], pt_rightmost)
            end
          tr_ary = tr_original_ary.dup
          tr_ary[12] = new_origin.x
          transformations << Geom::Transformation.new(tr_ary)

        elsif ad["spread"]
          # Array multiple instances.
          # Either Integer telling number of copies or float/length telling
          # approximate distance between (in inches). This distance will adapt
          # to fit available space.

          available_distance = pt_leftmost.distance pt_rightmost
          margin_l = ad["margin_left"] || ad["margin"] || 0
          margin_r = ad["margin_right"] || ad["margin"] || 0
          available_distance -= (margin_l + margin_r)
          if ad["spread"].is_a?(Integer)
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
          (0..total_number-1).each do |n|
            x = pt_leftmost.x + margin_l + (n + 0.5) * distance_between
            tr_ary = tr_original_ary.dup
            tr_ary[12] = x
            tr = Geom::Transformation.new tr_ary
            # Don't place anything with its bounding box outside the segment if
            # not specifically told to do so.
            unless ad["override_cut_planes"]
              corners = MyGeom.bb_corners(part_data[:definition].bounds)
              corners.each { |c| c.transform! tr }
              next if corners.any? { |c| segment_info[:all_planes].any? { |p| MyGeom.front_of_plane?(p, c) }}
            end
            transformations << tr
          end

        end

      end

    end

    nil

  end

  # Internal: Get information for building segments.
  # A segment is the what is between two adjacent corners.
  #
  # Returns Array with information for each segment starting from the left.
  # Information is a Hash. For Hash content, see the comments inside method.
  def calculate_segment_info

    # Transform path to local building coordinates.
    building_tr = @group.transformation
    path = @path.map { |p| p.transform building_tr.inverse }

    # Get tangent for each point in path.
    # Tangents point in the positive direction of path.
    tangents = []
    tangents << path[1] - path[0]
    if path.size > 2
      (1..path.size - 2).each do |corner_index|
        p_prev = path[corner_index - 1]
        p_this = path[corner_index]
        p_next = path[corner_index + 1]
        v_prev = (p_this - p_prev).normalize
        v_next = (p_next - p_this).normalize
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
    
    # Determine if interior corners (all but the building ends) are convex.
    convex = (1..path.size - 2).map do |corner_index|
      p_prev = path[corner_index - 1]
      p_this = path[corner_index]
      p_next = path[corner_index + 1]
      v_prev = p_this - p_prev
      v_next = p_next - p_this
      (v_prev * v_next).z > 0
    end
    
    # Get segment information.
    # Coordinates are relative to the segment group except for the group's
    # Transformation itself which is relative to the building group coordinates.
    segments_info = []
    (0..path.size - 2).each do |segment_index|
    
      segment_info = {}
      segments_info << segment_info
    
      first = segment_index == 0
      last  = segment_index == path.size - 2
    
      # Values in main building @group's coordinates.
      corner_left    = path[segment_index]
      corner_right   = path[segment_index + 1]
      segment_vector = corner_right - corner_left
      length         = segment_vector.length
      tangent_left   = tangents[segment_index]
      tangent_right  = tangents[segment_index + 1]
      transformation = Geom::Transformation.axes(
        corner_left,
        segment_vector,
        Z_AXIS * segment_vector,
        Z_AXIS
      )
      
      # Transformation of segment group.
      segment_info[:transformation] = transformation
      
      # The Length of the segment in the facade plane.
      segment_info[:length]         = length

      # Values in local segment group's coordinates.
      tangent_left  = tangent_left.transform transformation.inverse
      tangent_right = tangent_right.transform transformation.inverse
      plane_left    = [ORIGIN, tangent_left.reverse]
      plane_right   = [[length, 0, 0], tangent_right]
      side_planes   = [plane_left, plane_right]
      
      # Vectors of adjacent path segments (in coordinates of local group).
      adjacent_vector_left = 
        if first
          Z_AXIS*tangents.first.transform(transformation.inverse)
        else
          (path[segment_index]-path[segment_index-1]).transform(transformation.inverse).reverse
        end
      adjacent_vector_right = 
        if last
          Z_AXIS*tangents.last.transform(transformation.inverse)
        else
          (path[segment_index+2]-path[segment_index+1]).transform transformation.inverse
        end
      segment_info[:adjacent_vector_left]  = adjacent_vector_left
      segment_info[:adjacent_vector_right] = adjacent_vector_right
      segment_info[:adjacent_vectors]      = [adjacent_vector_left, adjacent_vector_right]
      
      # Tangents of the corners for this segment.
      segment_info[:tangent_left]  = tangent_left
      segment_info[:tangent_right] = tangent_right
      
      # Planes defining main sides of this segment.
      segment_info[:plane_left]  = plane_left
      segment_info[:plane_right] = plane_right
      
      # Array of planes defining the main sides of the segment. 0th element is
      # left plane, 1st is right.
      segment_info[:side_planes] = side_planes

      # Determine planes to cut volume with for corner transitions.
      cts = @corner_transitions[@template.id]
      cut_planes = []
      if cts
      
        # Left side of segment
        ct = cts[segment_index-1]
        if ct && ct["length"] && ct["length"] > 0 && !first && convex[segment_index-1]
          half_angle  = Y_AXIS.angle_between(tangent_left)
          tangent_vector  = X_AXIS.reverse
          bisector_vector = Geom.linear_combination 0.5, X_AXIS.reverse, 0.5, tangent_left.reverse
          case ct["type"]
          when "chamfer_d"
            diagonal_length  = ct["length"]
            projected_length = diagonal_length/(2*Math.sin(half_angle))
            cut_vector       = bisector_vector
          when "chamfer_p"
            projected_length = ct["length"]
            cut_vector       = bisector_vector
          end
          if @back_along_path
            y = -(@template.depth || Template::FALLBACK_DEPTH)
            x = y*Math.tan(half_angle-90.degrees) + projected_length
          else
            x = projected_length
            y = 0
          end
          cut_planes[0] = [[x, y, 0], cut_vector]
        end
        
        # Right side of segment
        ct = cts[segment_index]
        if ct && ct["length"] && ct["length"] > 0 && !last && convex[segment_index]
          half_angle  = Y_AXIS.angle_between(tangent_right.reverse)
          tangent_vector  = X_AXIS
          bisector_vector = Geom.linear_combination 0.5, X_AXIS, 0.5, tangent_right
          case ct["type"]
          when "chamfer_d"
            diagonal_length  = ct["length"]
            projected_length = diagonal_length/(2*Math.sin(half_angle))
            cut_vector       = bisector_vector
          when "chamfer_p"
            projected_length = ct["length"]
            cut_vector       = bisector_vector
          end
          if @back_along_path
            y = -(@template.depth || Template::FALLBACK_DEPTH)
            x = length - y*Math.tan(half_angle-90.degrees) - projected_length
          else
            x = length - projected_length
            y = 0
          end
          cut_planes[1] = [[x, y, 0], cut_vector]
        end
      
      end
      
      # Array of planes defining how segment should be cut to leave space for
      # corner transition. 0th element is left plane, 1st is right.
      segment_info[:cut_planes] = cut_planes

      # List planes that are hidden within building.
      # All side and cut planes except for gables.
      internal_planes = []
      internal_planes << plane_left unless first
      internal_planes << plane_right unless last
      internal_planes += cut_planes.compact
      segment_info[:internal_planes] = internal_planes
      
      # List all planes defining the perimeter of segment.
      all_planes = side_planes + cut_planes.compact
      segment_info[:all_planes] = all_planes
      
      # List all planes for each side.
      segment_info[:planes_left]  = [plane_left, cut_planes[0]].compact
      segment_info[:planes_right] = [plane_right, cut_planes[1]].compact
      
      # Information for the group the transition geometry is drawn to.
      # Group should be drawn at the left side of segment similar to how corner
      # parts are placed.
      if cts
        ct = cts[segment_index-1]
        if ct && ct["length"] && ct["length"] > 0 && !first && convex[segment_index-1]
          prev_segment = segments_info[segment_index-1]
          transition_group = {}
          tr_correction = transformation.inverse*prev_segment[:transformation]
          plane_left = prev_segment[:cut_planes][1].map { |c| c.transform tr_correction }
          plane_left[1].reverse!
          transition_group[:plane_left] = plane_left
          plane_right = cut_planes[0].dup
          plane_right[1] = plane_right[1].reverse
          transition_group[:plane_right] = plane_right
          transition_group[:planes] = [plane_left, plane_right]
          
          segment_info[:transition_group] = transition_group
        end
      end
       
    end

    segments_info

  end

  # Internal: Load building group's attributes as Hash.
  # Replaces string references used in attributes with actual objects such as
  # Template and Material.
  #
  # Return Hash.
  def load_attributes_to_hash

    h = EneBuildings.attr_dict_to_hash @group, ATTR_DICT

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
    
    # Override corner_transitions JSON String with actual Hash object.
    # Backward compatibility: Set corner_transitions to empty Hash if not already set.
    h[:corner_transitions] = h[:corner_transitions] ? JSON.parse(h[:corner_transitions]) : {}
    h[:corner_transitions].each_value { |a| a.each { |c| c["length"] = c["length"].to_l if c }}

    # Backward compatibility: Default suggest_corner_transitions to true.
    h[:suggest_corner_transitions] = true if h[:suggest_corner_transitions].nil?
    
    # Override gable JSON String with actual Hash object.
    # Backward compatibility: Set gables to empty Hash if not already set.
    h[:gables] = h[:gables] ? JSON.parse(h[:gables]) : {}

    # Override facade_margins Array with actual Array object.
    # Backward compatibility: Set facade_margins to empty Hash if not already set.
    h[:facade_margins] = h[:facade_margins] ? Hash[h[:facade_margins]] : {}

    # Backward compatibility: Default suggest_margins to true.
    h[:suggest_margins] = true if h[:suggest_margins].nil?

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
    h[:material_replacement] = Hash[h[:material_replacement]]

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

    segments_info = calculate_segment_info

    # Loop path segments.
    (0..@path.size - 2).each do |segment_index|

      segment_info = segments_info[segment_index]
      
      # Place template component in segment and explode it so it can be edited
      # without interfering with template.
      # Shift position along Y axis if the back of the building is what follows
      # the given path and not the front.
      segment_group                = ents.add_group
      segment_group.transformation = segment_info[:transformation]
      segment_ents                 = segment_group.entities
      component_trans = if @back_along_path
        Geom::Transformation.new [0, -(@template.depth || Template::FALLBACK_DEPTH), 0]
      else
        Geom::Transformation.new
      end
      component_inst = segment_ents.add_instance @template.component_def, component_trans
      component_inst.explode

      # Purge everything but edges and faces from template.
      # This method only draws the volume and another methods add the details.
      allowed_classes = [Sketchup::Face, Sketchup::Edge]
      segment_ents.erase_entities segment_ents.select { |e| !allowed_classes.include? e.class }

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

      # Adapt building volume to fill this segment by moving and skewing sides.
      # walls.

      x_min       = face_left.vertices.first.position.x
      x_max       = face_right.vertices.first.position.x
      edges       = segment_ents.select { |e| e.is_a? Sketchup::Edge }
      edges_left  = edges.select { |e| e.vertices.all? { |v| v.position.x.to_l == x_min } } # All these edges may not bound the left face. For instance Landshövdingehus äldre has a rainwater pipe thingy.
      edges_right = edges.select { |e| e.vertices.all? { |v| v.position.x.to_l == x_max } }

      y_axis = segment_info[:plane_left][1]*Z_AXIS
      y_axis.length = 1/Math.cos(y_axis.angle_between(Y_AXIS))
      trans_left = MyGeom.transformation_axes [-x_min, 0, 0], X_AXIS, y_axis, Z_AXIS, true, true
      
      y_axis = Z_AXIS*segment_info[:plane_right][1]
      y_axis.length = 1/Math.cos(y_axis.angle_between(Y_AXIS))
      trans_right = MyGeom.transformation_axes [segment_info[:length] - x_max, 0, 0], X_AXIS, y_axis, Z_AXIS, true, true

      segment_ents.transform_entities trans_left, edges_left
      segment_ents.transform_entities trans_right, edges_right
      
      # Cut away from volume for corner transition.
      cut_planes = segment_info[:cut_planes]
      if cut_planes
        cut_planes.compact.each { |p| MyGeom.cut segment_ents, p }
      end
      
      # Hide faces and edges where segments meet.
      plns = segment_info[:internal_planes]
      segment_ents.each do |e|
        next unless e.respond_to? :vertices
        next if e.is_a?(Sketchup::Edge) && !e.line[1].perpendicular?(Z_AXIS)
        next unless plns.any?{ |p| e.vertices.all? { |v| v.position.on_plane? p }}
        e.hidden = true
      end
      
      
      
      
      
      # Draw volume for corner transition.
      if segment_info[:transition_group]
      transition_group = segment_ents.add_group
        transition_ents = transition_group.entities

        plane_left  = segment_info[:transition_group][:plane_left]
        plane_right = segment_info[:transition_group][:plane_right]
        plane_front = [plane_left[0], segment_info[:tangent_left]*Z_AXIS]
        lines       = [
          Geom.intersect_plane_plane(plane_front, plane_left),
          Geom.intersect_plane_plane(plane_left,  plane_right),
          Geom.intersect_plane_plane(plane_right, plane_front)
        ]
        base_plane  = [ORIGIN, Z_AXIS]
        corners     = lines.map { |l| Geom.intersect_line_plane l, base_plane }
        depth       = corners[1].distance_to_plane plane_front
        length      = corners[0].distance corners[2]
        
        # Place template.
        # TODO: Add support for chamfer or comment out on all places in UI.
        transition_trans = Geom::Transformation.axes(
          corners[0],
          corners[2] - corners[0],
          plane_front[1].reverse,
          Z_AXIS
        )
        transition_group                = segment_ents.add_group
        transition_group.transformation = transition_trans
        transition_ents                 = transition_group.entities
        component_inst                  = transition_ents.add_instance(
          @template.component_def,
          Geom::Transformation.new
        )
        component_inst.explode
        transition_ents.erase_entities transition_ents.select { |e| !allowed_classes.include? e.class }
        
        # Move ends.
        edges       = transition_ents.select { |e| e.is_a? Sketchup::Edge }
        edges_left  = edges.select { |e| e.vertices.all? { |v| v.position.x.to_l == x_min }}
        edges_right = edges.select { |e| e.vertices.all? { |v| v.position.x.to_l == x_max }}
        trans_left  = Geom::Transformation.new([-x_min - 1.m, 0, 0])
        trans_right = Geom::Transformation.new([length - x_max + 1.m, 0, 0])
        transition_ents.transform_entities trans_left, edges_left
        transition_ents.transform_entities trans_right, edges_right
        
        # Cut sides.
        plns = segment_info[:transition_group][:planes].map { |p| p.map { |c| c.transform transition_trans.inverse }}
        plns.each { |p| MyGeom.cut transition_ents, p }
      
        # Hide sides.
        transition_ents.each do |e|
          next unless e.respond_to? :vertices
          next if e.is_a?(Sketchup::Edge) && (!e.line[1].valid? || !e.line[1].perpendicular?(Z_AXIS))
          next unless plns.any?{ |p| e.vertices.all? { |v| v.position.on_plane? p }}
          e.hidden = true
        end
      
      end
      
      

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

    part_data = list_replaced_parts
    part_data += list_gable_parts true
    part_data += list_corner_parts true

    segment_groups = @group.entities.to_a

    # Loop path segments.
    (0..path.size - 2).each do |segment_index|

      segment_group = segment_groups[segment_index]
      segment_ents  = segment_group.entities

      # Purge all existing parts in segment.
      # This method can be called if part settings are changed without first
      # calling draw_volume.
      instances = segment_ents.select { |e| e.attribute_dictionary Template::ATTR_DICT_PART }
      segment_ents.erase_entities instances

      # Place instances of all spread or aligned parts that has transformations
      # for this segment.
      part_data.each do |part|
        transformations = part[:transformations][segment_index] || []
        (transformations).each do |trans|
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
        # SU ISSUE: ad is sometimes an edge :S . seems to happen when invalid
        # geometry has been produced earlier.
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

    # TODO: Find fast and stable way to cut openings.

    # Disabled own fast cut code in favor of old intersect_with code.
    # New code caused invalid geometry which seems to have messed up object
    # references (tested in SU2015).
    #
    # E.g. attribute_dictionary could return an edge.
    #
    # Test geometry validity with:
    #    Sketchup.send_action 21124
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

      # Also delete parts glued to faces cut away, except for parts with solid
      # operations. That would risk deleting the part that cut the hole itself.
      segment_group.entities.erase_entities cut_away_faces.map { |f| f.get_glued_instances }.flatten.select { |p| !p.get_attribute(Template::ATTR_DICT_PART, "solid") }

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

    # Recursive material replacer.
    # Replace materials in group and in all nested groups with an attribute
    # specifically telling it to do so.
    recursive = lambda do |group|
      group.name += ""# Make group unique. # OPTIMIZE: Keep hash of new definitions indexed by old definitions. Re-use repainted definition.
      group.entities.each do |e|
        next unless e.respond_to? :material
        original_name = e.get_attribute(Template::ATTR_DICT_PART, "original_material")
        original = if original_name
          @group.model.materials[original_name]
        else
          e.material
        end
        replacment = @material_replacement[original]
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
